import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/silla_puerta.dart';
import '../central/pedidos_de_la_puerta.dart' show DatosSilla, kPorMandar;
import '../chat/chat_del_puesto.dart';
import '../chat/chat_provider.dart';
import '../chat/hoja_chat.dart' show AvisoDelChat;
import '../providers/acciones_puerta_provider.dart';
import '../providers/recepcion_provider.dart';
import '../providers/salon_de_la_puerta_provider.dart';
import '../services/plano_de_la_puerta.dart';
import '../services/puerta_del_evento.dart';
import '../services/sillas_de_la_puerta.dart';
import 'hoja_plano_puerta.dart';
import 'hoja_sumar_silla.dart';
import 'linea_sin_internet.dart';

/// El panel de Recepción de un evento: el progreso, la búsqueda, los filtros y
/// la lista con "Ingresar" por persona.
///
/// Distingue un evento particular de uno masivo ([PuertaDelEvento]): en un
/// masivo la lista sale de los alumnos de la institución, con su mesa y sus
/// sillas si ya se sorteó, sus acompañantes y su música; en un particular, de
/// la lista cargada a mano o por CSV.
///
/// Lo que decide —quién se ve, qué hace Enter— está en [PuertaDelEvento]; acá
/// se dibuja y se marca por [AccionesPuerta]: en la PC, la base; en el celular
/// de la puerta, la notebook central.
///
/// La letra es Outfit, que viene con la app: anda sin internet.
class PanelPuerta extends ConsumerStatefulWidget {
  final String eventoId;
  final VoidCallback onActualizar;

  /// Solo en particulares: en un masivo la lista sale de los alumnos.
  final VoidCallback? onAgregar;
  final VoidCallback? onImportar;
  final VoidCallback? onExportar;
  final VoidCallback? onVaciar;

  /// False: el plano que abre VER EN EL PLANO va quieto (los tests: con el
  /// borde latiendo, la pantalla nunca queda quieta).
  final bool animarElPlano;

  const PanelPuerta({
    super.key,
    required this.eventoId,
    required this.onActualizar,
    this.onAgregar,
    this.onImportar,
    this.onExportar,
    this.onVaciar,
    this.animarElPlano = true,
  });

  @override
  ConsumerState<PanelPuerta> createState() => _PanelPuertaState();
}

/// Lo que se dice debajo de la búsqueda después de algo.
class _Aviso {
  final String texto;
  final bool bien;
  final bool error;
  const _Aviso(this.texto, {this.bien = false, this.error = false});
}

class _PanelPuertaState extends ConsumerState<PanelPuerta> {
  static const _perla = Color(0xFFE2E2E2);
  static const _verde = Color(0xFF4ADE80);
  static const _ambar = Color(0xFFFBBF24);

  final _busqueda = TextEditingController();
  final _foco = FocusNode();
  FiltroPuerta _filtro = FiltroPuerta.todos;
  _Aviso? _aviso;
  final _ocupados = <String>{};
  StreamSubscription<String>? _avisosDeLaCentral;
  StreamSubscription<String>? _hechosDeLaCentral;

  @override
  void initState() {
    super.initState();
    // Lo que contesta la central cuando no hizo lo pedido ("ya ingresó a las
    // 22:41 · Pato"): puede llegar un rato después del toque.
    _avisosDeLaCentral = ref.read(accionesPuertaProvider).avisos.listen((t) {
      if (mounted) setState(() => _aviso = _Aviso(t));
    });
    // Lo que la central confirmó después (una silla anotada sin conexión, que se
    // mandó al volver).
    _hechosDeLaCentral = ref.read(accionesPuertaProvider).hechos.listen((t) {
      if (mounted) setState(() => _aviso = _Aviso(t, bien: true));
    });
  }

  @override
  void dispose() {
    unawaited(_avisosDeLaCentral?.cancel());
    unawaited(_hechosDeLaCentral?.cancel());
    _busqueda.dispose();
    _foco.dispose();
    super.dispose();
  }

  TextStyle _letra({
    double size = 14,
    bool negrita = false,
    Color? color,
    double? espaciado,
    bool tachado = false,
  }) =>
      GoogleFonts.outfit(
        fontSize: size,
        fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
        color: color,
        letterSpacing: espaciado,
        decoration: tachado ? TextDecoration.lineThrough : null,
      );

  /// El salón para VER EN EL PLANO (6.5.0). Se lee en [build] y lo usan las
  /// tarjetas, que se arman después (la lista es perezosa).
  SalonParaLaPuerta? _salon;

  /// El chat de la puerta (6.5.0): su aviso va arriba de la lista.
  ChatDelPuesto? _chat;

  @override
  Widget build(BuildContext context) {
    _salon = ref.watch(salonDeLaPuertaProvider(widget.eventoId));
    _chat = ref.watch(chatDeLaPuertaProvider);
    final puerta = ref.watch(puertaDelEventoProvider(widget.eventoId));
    return puerta.when(
      data: _contenido,
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
      ),
      error: (_, _) => _sinLista(),
    );
  }

  bool get _oscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _texto => _oscuro ? _perla : Colors.black87;
  Color get _suave => _oscuro ? Colors.white54 : Colors.black54;
  Color get _borde => _oscuro ? Colors.white12 : Colors.black12;

  Widget _contenido(PuertaDelEvento p) {
    final visibles = p.buscar(_busqueda.text, filtro: _filtro);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _progreso(p),
        // La web se sirve desde internet: sin internet no anda, no hay nada
        // que decir. Y en el celular de la puerta marca la central, no esta
        // pantalla.
        if (!kIsWeb && ref.watch(accionesPuertaProvider).enEstaPc)
          LineaSinInternet(
            eventoId: widget.eventoId,
            personas: p.total,
            adentro: p.adentro,
          ),
        if (p.masivo && !p.sorteado) _avisoSinSortear(),
        _barra(p),
        if (_chat != null) AvisoDelChat(chat: _chat!),
        if (_aviso != null) _lineaAviso(_aviso!),
        _filtros(p),
        if (p.conteoDeLaNoche.texto != null) _conteoDeLaNoche(p),
        Expanded(
          child: visibles.isEmpty
              ? _vacio(p)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: visibles.length,
                  itemBuilder: (_, i) => _tarjeta(visibles[i], p),
                ),
        ),
        if (p.masivo && p.bajas > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              p.bajas == 1
                  ? '1 dado de baja: no aparece.'
                  : '${p.bajas} dados de baja: no aparecen.',
              style: _letra(size: 12, color: _suave),
            ),
          ),
      ],
    );
  }

  // ── Arriba ────────────────────────────────────────────────────────────────

  Widget _progreso(PuertaDelEvento p) {
    final fraccion = p.total == 0 ? 0.0 : p.adentro / p.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  '${_miles(p.adentro)} de ${_miles(p.total)} adentro',
                  style: _letra(size: 18, negrita: true, color: _texto),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '· faltan ${_miles(p.faltan)}',
                style: _letra(size: 13, color: _suave),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraccion,
              minHeight: 6,
              color: _verde,
              backgroundColor: _borde,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoSinSortear() => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _ambar.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _ambar.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: _ambar, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Todavía no se sorteó. Los alumnos se ven sin mesa: las mesas, '
                'las sillas y el plano aparecen después del sorteo.',
                style: _letra(size: 13, color: _oscuro ? _ambar : Colors.brown),
              ),
            ),
          ],
        ),
      );

  Widget _barra(PuertaDelEvento p) {
    final particular = !p.masivo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: LayoutBuilder(
        builder: (context, c) {
          final angosto = c.maxWidth < 480;
          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _busqueda,
                  focusNode: _foco,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: _letra(size: 16, color: _texto),
                  decoration: InputDecoration(
                    hintText: particular
                        ? 'Buscar por nombre, DNI o mesa'
                        : 'Buscar por nombre o mesa',
                    hintStyle: _letra(size: 15, color: _suave),
                    prefixIcon: Icon(Icons.search_rounded, color: _suave),
                    suffixIcon: _busqueda.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Borrar la búsqueda',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _busqueda.clear();
                              setState(() => _aviso = null);
                              _foco.requestFocus();
                            },
                          ),
                    filled: true,
                    fillColor: _oscuro
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _borde),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _borde),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _perla, width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setState(() => _aviso = null),
                  onSubmitted: (_) => _enter(p),
                  // En la web de un celular, Flutter suelta el teclado al
                  // apoyar el dedo afuera, y eso se comía el toque: el primer
                  // INGRESAR después de buscar no andaba. Se suelta al
                  // levantarlo.
                  onTapOutside: kIsWeb ? (_) {} : null,
                  onTapUpOutside: kIsWeb ? (_) => _foco.unfocus() : null,
                ),
              ),
              if (particular && widget.onAgregar != null) ...[
                const SizedBox(width: 8),
                angosto
                    ? IconButton.filled(
                        tooltip: 'Agregar invitado',
                        onPressed: widget.onAgregar,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: _perla,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(48, 48),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: widget.onAgregar,
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            size: 18),
                        label: Text('AGREGAR',
                            style: _letra(size: 12, negrita: true)),
                        style: FilledButton.styleFrom(
                          backgroundColor: _perla,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 52),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
              ],
              const SizedBox(width: 4),
              _menuMas(p),
            ],
          );
        },
      ),
    );
  }

  Widget _menuMas(PuertaDelEvento p) {
    final particular = !p.masivo;
    final salon = _salon;
    final verPlano = p.masivo && p.sorteado && salon != null;
    PopupMenuItem<String> item(String valor, IconData icono, String texto,
            {Color? color}) =>
        PopupMenuItem<String>(
          value: valor,
          child: Row(
            children: [
              Icon(icono, size: 18, color: color),
              const SizedBox(width: 12),
              Text(texto, style: _letra(color: color)),
            ],
          ),
        );
    return PopupMenuButton<String>(
      tooltip: 'Más',
      icon: Icon(Icons.more_horiz_rounded, color: _texto),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        switch (v) {
          case 'plano':
            if (salon != null) {
              unawaited(abrirPlanoEntero(
                context,
                eventoId: widget.eventoId,
                puerta: p,
                salon: salon,
                animar: widget.animarElPlano,
              ));
            }
          case 'actualizar':
            widget.onActualizar();
          case 'importar':
            widget.onImportar?.call();
          case 'exportar':
            widget.onExportar?.call();
          case 'vaciar':
            widget.onVaciar?.call();
        }
      },
      itemBuilder: (_) => [
        if (verPlano) item('plano', Icons.map_outlined, 'Ver el plano entero'),
        item('actualizar', Icons.refresh_rounded, 'Actualizar la lista'),
        if (particular) ...[
          if (widget.onImportar != null)
            item('importar', Icons.upload_file_rounded, 'Importar lista'),
          if (widget.onExportar != null)
            item('exportar', Icons.table_view_rounded, 'Exportar a Excel'),
          if (widget.onVaciar != null) ...[
            const PopupMenuDivider(),
            item('vaciar', Icons.delete_sweep_rounded, 'Vaciar lista…',
                color: Colors.redAccent),
          ],
        ],
      ],
    );
  }

  Widget _lineaAviso(_Aviso a) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
        child: Text(
          a.texto,
          style: _letra(
            size: 13,
            negrita: a.bien,
            color: a.error
                ? Colors.redAccent
                : a.bien
                    ? _verde
                    : _ambar,
          ),
        ),
      );

  Widget _filtros(PuertaDelEvento p) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final f in FiltroPuerta.values)
              ChoiceChip(
                label: Text('${f.nombre} ${_miles(p.cuantos(f))}'),
                labelStyle: _letra(
                  size: 13,
                  negrita: _filtro == f,
                  color: _filtro == f ? Colors.black : _texto,
                ),
                selected: _filtro == f,
                showCheckmark: false,
                selectedColor: _perla,
                side: BorderSide(color: _borde),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => setState(() {
                  _filtro = f;
                  _aviso = null;
                }),
              ),
          ],
        ),
      );

  /// "Esta noche: 4 sillas sumadas · vales …": lo que se compara con las "Silla
  /// extra" vendidas en la barra.
  Widget _conteoDeLaNoche(PuertaDelEvento p) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Row(
          children: [
            Icon(Icons.event_seat_outlined, size: 15, color: _suave),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                p.conteoDeLaNoche.texto!,
                key: const ValueKey('conteo_de_la_noche'),
                style: _letra(size: 12, color: _suave),
              ),
            ),
          ],
        ),
      );

  // ── La lista ──────────────────────────────────────────────────────────────

  Widget _vacio(PuertaDelEvento p) {
    final String texto;
    if (p.total == 0) {
      texto = p.masivo
          ? 'Esta institución no tiene alumnos cargados.'
          : 'Todavía no hay invitados. Agregalos, o importá la lista desde Más.';
    } else if (_busqueda.text.trim().isNotEmpty) {
      texto = 'No hay nadie con esa búsqueda.';
    } else if (_filtro == FiltroPuerta.adentro) {
      texto = 'Todavía no entró nadie.';
    } else {
      texto = 'Ya entraron todos.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: _letra(size: 14, color: _suave),
        ),
      ),
    );
  }

  Widget _tarjeta(GrupoPuerta g, PuertaDelEvento p) {
    final todosAdentro = g.personas.every((x) => x.ingresado);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _oscuro
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: todosAdentro ? _verde.withValues(alpha: 0.35) : _borde,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _renglon(
            g.titular,
            detalle: _detalleTitular(g, p),
            puedeEliminar:
                g.cargadoAMano && ref.watch(accionesPuertaProvider).puedeEliminar,
          ),
          for (final a in g.acompanantes)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 8),
              child: _renglon(
                a,
                chico: true,
                detalle: [
                  // En una mesa reservada (los profes) nadie acompaña a nadie:
                  // cada uno lleva la distinción de la mesa.
                  Text(
                    g.reservadaPara ?? 'acompañante',
                    style: _letra(size: 12, color: _suave),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _detalleTitular(GrupoPuerta g, PuertaDelEvento p) {
    final t = g.titular;
    if (!p.masivo || g.cargadoAMano) {
      final partes = [
        if (t.dni.isNotEmpty) 'DNI ${_dni(t.dni)}',
        if (t.mesa != null) 'Mesa ${t.mesa}',
        if (p.masivo) 'cargado a mano',
      ];
      return [
        if (partes.isNotEmpty)
          Text(partes.join(' · '), style: _letra(size: 12, color: _suave)),
      ];
    }
    return [
      Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // La distinción de quien no es alumno ("PROFES", 6.5.0), marcada:
          // la recepcionista tiene que verla de un vistazo.
          if (g.reservadaPara != null) ...[
            Container(
              key: ValueKey('distincion_${t.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(
                color: _ambar.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _ambar.withValues(alpha: 0.55)),
              ),
              child: Text(
                g.reservadaPara!.toUpperCase(),
                style: _letra(size: 11, negrita: true, color: _ambar),
              ),
            ),
            if (t.mesa != null) _punto(),
          ],
          if (g.division != null)
            Text(g.division!, style: _letra(size: 12, color: _suave)),
          if (t.mesa != null) ...[
            if (g.division != null) _punto(),
            Text('Mesa ${t.mesa}',
                style: _letra(size: 13, negrita: true, color: _texto)),
          ] else if (g.sinMesa) ...[
            if (g.division != null) _punto(),
            Text('Sin mesa', style: _letra(size: 12, negrita: true, color: _ambar)),
          ],
        ],
      ),
      ..._sillas(g, p),
      ..._botonesDeLaFamilia(g, p),
      if (g.musica != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Icon(Icons.music_note_rounded, size: 13, color: _suave),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  g.musica!,
                  overflow: TextOverflow.ellipsis,
                  style: _letra(size: 12, color: _suave),
                ),
              ),
            ],
          ),
        ),
      if (g.acompanantesSinNombre > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            g.acompanantesSinNombre == 1
                ? '+1 acompañante sin nombre'
                : '+${g.acompanantesSinNombre} acompañantes sin nombre',
            style: _letra(size: 12, color: _suave),
          ),
        ),
    ];
  }

  Widget _punto() => Text('·', style: _letra(size: 12, color: _suave));

  // ── Las sillas de la noche ────────────────────────────────────────────────

  /// Una línea por mesa ("Mesa 12: 8 sillas + 1 extra · puede agregar 1 más ·
  /// se cobran en la barra"), cada silla sumada o quitada esa noche, y SUMAR
  /// SILLA.
  List<Widget> _sillas(GrupoPuerta g, PuertaDelEvento p) {
    final mesas = g.sillasPorMesa.mesas;
    if (mesas.isEmpty) {
      // Sin mesa, o una central de antes que manda solo el texto.
      if (g.sillas == null) return const [];
      return [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            g.sillasAConfirmar
                ? '${g.sillas} · reparto a confirmar'
                : g.sillas!,
            style: _letra(
              size: 12,
              color: g.sillasAConfirmar ? _ambar : _suave,
            ),
          ),
        ),
      ];
    }
    return [
      for (final m in mesas)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            m.texto,
            key: ValueKey('mesa_${g.contratoId}_${m.numero}'),
            style: _letra(
              size: 12,
              negrita: m.estado == EstadoMesaPuerta.revisar,
              color: switch (m.estado) {
                EstadoMesaPuerta.conLugar => _suave,
                EstadoMesaPuerta.llena => _ambar,
                EstadoMesaPuerta.revisar => Colors.redAccent,
              },
            ),
          ),
        ),
      if (g.sillasAConfirmar)
        Text(
          'El reparto de las sillas del contrato está a confirmar.',
          style: _letra(size: 12, color: _ambar),
        ),
      for (final s in g.movimientos) _movimiento(g, p, s),
    ];
  }

  /// Los botones de la familia: SUMAR SILLA y VER EN EL PLANO (6.5.0), juntos y
  /// a la izquierda; en un celular angosto bajan de renglón solos.
  List<Widget> _botonesDeLaFamilia(GrupoPuerta g, PuertaDelEvento p) {
    final salon = _salon;
    final sumar = g.contratoId != null && g.sillasPorMesa.tieneMesa;
    // La suelta (6.5.0): para la familia de un alumno, también en el tope.
    final suelta = g.contratoId != null && p.sorteado;
    final verPlano = salon != null && salon.tieneMesaDe(g);
    if (!sumar && !suelta && !verPlano) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (sumar) _botonSumar(g, p),
            if (suelta) _botonSuelta(g, p),
            if (verPlano) _botonPlano(g, p, salon),
          ],
        ),
      ),
    ];
  }

  /// SILLA SUELTA (6.5.0): una silla que no va a ninguna mesa, sin tope.
  Widget _botonSuelta(GrupoPuerta g, PuertaDelEvento p) => OutlinedButton.icon(
        key: ValueKey('silla_suelta_${g.contratoId}'),
        onPressed: _ocupados.contains(g.contratoId)
            ? null
            : () => _sumarSilla(g, p, suelta: true),
        icon: const Icon(Icons.chair_alt_outlined, size: 16),
        label: Text('SILLA SUELTA', style: _letra(size: 12, negrita: true)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _texto,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(color: _borde),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Widget _botonPlano(GrupoPuerta g, PuertaDelEvento p, SalonParaLaPuerta salon) =>
      OutlinedButton.icon(
        key: ValueKey('ver_en_el_plano_${g.titular.id}'),
        onPressed: () => abrirPlanoDeLaFamilia(
          context,
          eventoId: widget.eventoId,
          puerta: p,
          grupo: g,
          salon: salon,
          animar: widget.animarElPlano,
        ),
        icon: const Icon(Icons.map_outlined, size: 16),
        label: Text('VER EN EL PLANO', style: _letra(size: 12, negrita: true)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _texto,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(color: _borde),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  /// "+1 silla · mesa 12 · vale 2-17 · Pato 23:05" con QUITAR. Una quitada queda
  /// tachada, con quién y por qué: nada desaparece.
  Widget _movimiento(GrupoPuerta g, PuertaDelEvento p, SillaPuerta s) {
    final quitada = textoSillaQuitada(s);
    final ocupado = _ocupados.contains(s.id);
    // La barra anuló la venta de este vale: la silla quedó sin pagar. No se saca
    // sola: la recepcionista la revisa y la quita con motivo.
    final anulada = quitada == null && g.valeAnulado(s);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(
            Icons.event_seat_outlined,
            size: 14,
            color: anulada
                ? Colors.redAccent
                : quitada == null
                    ? _verde
                    : _suave,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textoSillaSumada(s),
                  key: ValueKey('silla_${s.id}'),
                  style: _letra(
                    size: 12,
                    color: quitada == null ? _texto : _suave,
                    tachado: quitada != null,
                  ),
                ),
                if (quitada != null)
                  Text(quitada, style: _letra(size: 11, color: _suave)),
                if (anulada)
                  Text(
                    'vale anulado en la barra: revisar',
                    key: ValueKey('vale_anulado_${s.id}'),
                    style: _letra(
                      size: 12,
                      negrita: true,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
          if (quitada == null)
            TextButton(
              key: ValueKey('quitar_${s.id}'),
              onPressed: ocupado ? null : () => _quitarSilla(g, p, s),
              style: TextButton.styleFrom(
                foregroundColor: _suave,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text('QUITAR', style: _letra(size: 11, negrita: true)),
            ),
        ],
      ),
    );
  }

  Widget _botonSumar(GrupoPuerta g, PuertaDelEvento p) {
    final puede = g.puedeSumarSilla;
    final ocupado = _ocupados.contains(g.contratoId);
    final boton = OutlinedButton.icon(
      key: ValueKey('sumar_silla_${g.contratoId}'),
      onPressed: puede && !ocupado ? () => _sumarSilla(g, p) : null,
      icon: const Icon(Icons.event_seat_outlined, size: 16),
      label: Text('SUMAR SILLA', style: _letra(size: 12, negrita: true)),
      style: OutlinedButton.styleFrom(
        foregroundColor: _texto,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: BorderSide(color: _borde),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    if (puede) return boton;
    return Tooltip(
      message: 'Ya no puede agregar a la mesa: ${SillasDeUnaMesa.tope} extra '
          'por mesa. Una silla suelta, con el botón de al lado',
      child: boton,
    );
  }

  Widget _renglon(
    PersonaPuerta persona, {
    required List<Widget> detalle,
    bool chico = false,
    bool puedeEliminar = false,
  }) {
    final lado = chico ? 30.0 : 38.0;
    return Row(
      children: [
        Container(
          width: lado,
          height: lado,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (persona.ingresado ? _verde : _texto).withValues(alpha: 0.12),
          ),
          child: persona.ingresado
              ? Icon(Icons.check_rounded, size: chico ? 16 : 20, color: _verde)
              : Text(
                  persona.iniciales,
                  style: _letra(
                    size: chico ? 11 : 13,
                    negrita: true,
                    color: _texto,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                persona.nombre,
                style: _letra(
                  size: chico ? 13 : 15,
                  negrita: true,
                  color: _texto,
                  espaciado: 0.3,
                ),
              ),
              ...detalle,
            ],
          ),
        ),
        const SizedBox(width: 8),
        _estado(persona),
        if (puedeEliminar)
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: Icon(Icons.more_vert_rounded, color: _suave),
            onSelected: (_) => _eliminar(persona),
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'eliminar',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded,
                        size: 18, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    Text('Eliminar de la lista',
                        style: _letra(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          )
        else
          const SizedBox(width: 8),
      ],
    );
  }

  Widget _estado(PersonaPuerta persona) {
    final ocupado = _ocupados.contains(persona.id);
    if (persona.ingresado) {
      // Quién lo ingresó ("Juli"), o que el celular todavía no lo mandó.
      final marca = ref.watch(accionesPuertaProvider).marca(persona.id);
      final porMandar = marca == kPorMandar;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                persona.textoHora == null
                    ? 'ADENTRO'
                    : 'ADENTRO · ${persona.textoHora}',
                style: _letra(size: 12, negrita: true, color: _verde),
              ),
              if (marca != null && marca.isNotEmpty)
                Text(
                  porMandar ? 'POR MANDAR' : marca,
                  style: _letra(
                    size: 11,
                    negrita: porMandar,
                    color: porMandar ? _ambar : _suave,
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Deshacer el ingreso',
            icon: Icon(Icons.undo_rounded, size: 20, color: _suave),
            onPressed: ocupado ? null : () => _deshacer(persona),
          ),
        ],
      );
    }
    return FilledButton(
      onPressed: ocupado ? null : () => _ingresar(persona),
      style: FilledButton.styleFrom(
        backgroundColor: _verde,
        foregroundColor: Colors.black,
        minimumSize: const Size(96, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: ocupado
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text('INGRESAR', style: _letra(size: 12, negrita: true)),
    );
  }

  Widget _sinLista() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No se pudo leer la lista de esta PC.',
                textAlign: TextAlign.center,
                style: _letra(size: 15, negrita: true, color: _texto),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(invitadosStreamProvider(widget.eventoId));
                  ref.invalidate(alumnosDeLaPuertaProvider(widget.eventoId));
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('Probar de nuevo', style: _letra()),
              ),
            ],
          ),
        ),
      );

  // ── Lo que se hace ────────────────────────────────────────────────────────

  /// Enter en la búsqueda: si queda una sola persona sin entrar, la ingresa y
  /// deja la búsqueda lista para la siguiente.
  Future<void> _enter(PuertaDelEvento p) async {
    final r = p.alApretarEnter(_busqueda.text, filtro: _filtro);
    if (r.ingresa) {
      final entro = await _ingresar(r.persona!);
      if (entro && mounted) _busqueda.clear();
    } else if (r.aviso != null) {
      setState(() => _aviso = _Aviso(r.aviso!));
    }
    if (mounted) _foco.requestFocus();
  }

  Future<bool> _ingresar(PersonaPuerta persona) async {
    if (_ocupados.contains(persona.id)) return false;
    setState(() => _ocupados.add(persona.id));
    try {
      await ref.read(accionesPuertaProvider).ingresar(widget.eventoId, persona);
      if (mounted) {
        setState(() => _aviso = _Aviso('${persona.nombre} ingresó.', bien: true));
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _aviso = const _Aviso(
              'No se pudo marcar el ingreso. Probá de nuevo.',
              error: true,
            ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _ocupados.remove(persona.id));
    }
  }

  Future<void> _deshacer(PersonaPuerta persona) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deshacer el ingreso'),
        content: Text(
          '${persona.nombre} vuelve a la lista de los que faltan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DESHACER'),
          ),
        ],
      ),
    );
    if (si != true || !mounted) return;
    setState(() => _ocupados.add(persona.id));
    try {
      await ref.read(accionesPuertaProvider).deshacer(persona);
      if (mounted) {
        setState(() => _aviso = _Aviso('${persona.nombre} vuelve a faltar.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _aviso = const _Aviso(
              'No se pudo deshacer el ingreso. Probá de nuevo.',
              error: true,
            ));
      }
    } finally {
      if (mounted) setState(() => _ocupados.remove(persona.id));
    }
  }

  /// SUMAR SILLA: la hoja (mesa, vale, nota) y el candado. La recepcionista no
  /// cobra: la silla ya se pagó en la barra.
  Future<void> _sumarSilla(
    GrupoPuerta g,
    PuertaDelEvento p, {
    bool suelta = false,
  }) async {
    final acciones = ref.read(accionesPuertaProvider);
    final datos = await HojaSumarSilla.abrir(
      context,
      grupo: g,
      quienSoy: acciones.quienSoy,
      suelta: suelta,
    );
    if (datos == null || !mounted) return;
    final clave = g.contratoId!;
    setState(() => _ocupados.add(clave));
    try {
      final r = await acciones.sumarSilla(widget.eventoId, p, g, datos);
      if (mounted) {
        setState(() => _aviso = _Aviso(r.texto, bien: r.hecho && !r.porMandar));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _aviso = const _Aviso(
              'No se pudo sumar la silla. Probá de nuevo.',
              error: true,
            ));
      }
    } finally {
      if (mounted) setState(() => _ocupados.remove(clave));
    }
  }

  Future<void> _quitarSilla(
    GrupoPuerta g,
    PuertaDelEvento p,
    SillaPuerta s,
  ) async {
    final motivo = await HojaQuitarSilla.abrir(
      context,
      silla: s,
      nombre: g.titular.nombre,
    );
    if (motivo == null || !mounted) return;
    setState(() => _ocupados.add(s.id));
    try {
      final r = await ref.read(accionesPuertaProvider).quitarSilla(
            widget.eventoId,
            p,
            g,
            DatosSilla(sillaId: s.id, motivo: motivo),
          );
      if (mounted) {
        setState(() => _aviso = _Aviso(r.texto, bien: r.hecho && !r.porMandar));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _aviso = const _Aviso(
              'No se pudo quitar la silla. Probá de nuevo.',
              error: true,
            ));
      }
    } finally {
      if (mounted) setState(() => _ocupados.remove(s.id));
    }
  }

  Future<void> _eliminar(PersonaPuerta persona) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar de la lista'),
        content: Text(
          '${persona.nombre} sale de la lista de la puerta. No se puede '
          'deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (si != true || !mounted) return;
    try {
      await ref.read(accionesPuertaProvider).eliminar(persona);
      if (mounted) {
        setState(() => _aviso = _Aviso('${persona.nombre} salió de la lista.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _aviso = const _Aviso(
              'No se pudo eliminar. Probá de nuevo.',
              error: true,
            ));
      }
    }
  }

  // ── Formatos ──────────────────────────────────────────────────────────────

  /// 1100 → "1.100".
  static String _miles(int n) => _conPuntos(n.toString());

  /// "30123456" → "30.123.456". Lo que no son solo cifras queda como está.
  static String _dni(String dni) =>
      RegExp(r'^\d{7,9}$').hasMatch(dni) ? _conPuntos(dni) : dni;

  static String _conPuntos(String cifras) {
    final b = StringBuffer();
    for (var i = 0; i < cifras.length; i++) {
      if (i > 0 && (cifras.length - i) % 3 == 0) b.write('.');
      b.write(cifras[i]);
    }
    return b.toString();
  }
}
