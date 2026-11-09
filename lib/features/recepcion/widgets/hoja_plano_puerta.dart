import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../common/utils/cortes_pantalla.dart';
import '../../plano/dibujo/pintor_plano.dart' show EncuadrePlano;
import '../../plano/estilos/estilo_plano.dart' show NivelDetalle, TemaPlano;
import '../../plano/widgets/vista_plano.dart';
import '../../totem/estilos/escena_totem.dart';
import '../../totem/estilos/plano_del_totem.dart';
import '../../totem/estilos/totem_estilo.dart';
import '../../totem/services/bienvenidas_totem.dart';
import '../../totem/services/contenido_bienvenida.dart';
import '../../totem/services/ficha_totem.dart';
import '../../totem/services/plano_de_la_llegada.dart';
import '../services/plano_de_la_puerta.dart';
import '../services/puerta_del_evento.dart';

const _fondo = Color(0xFF141418);
const _perla = Color(0xFFE2E2E2);
const _verde = Color(0xFF4ADE80);
const _ambar = Color(0xFFFBBF24);

TextStyle _letra({double size = 14, bool negrita = false, Color? color}) =>
    GoogleFonts.outfit(
      fontSize: size,
      fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
      color: color ?? _perla,
    );

/// La ventana donde va el plano: a pantalla completa en el celular, grande y al
/// medio en la PC.
class _Marco extends StatelessWidget {
  const _Marco({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tam = MediaQuery.sizeOf(context);
    if (CortesPantalla.esCelular(tam.width)) {
      return Dialog.fullscreen(backgroundColor: _fondo, child: child);
    }
    return Dialog(
      backgroundColor: _fondo,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _perla.withValues(alpha: 0.15)),
      ),
      child: SizedBox(
        width: math.min(1180, tam.width - 48),
        height: tam.height - 48,
        child: child,
      ),
    );
  }
}

/// La apariencia y el color del tótem de esa noche, como los dibuja la tele.
/// "Tu fondo" sin imagen (el celular no la tiene) va con la del evento masivo.
EstiloTotem _estiloDe(SalonParaLaPuerta salon) =>
    EstiloTotem.elegida(salon.cfg.estilo, fondoUrl: salon.cfg.fondoUrl) ??
    EstiloTotem.porDefecto(masivo: true);

/// Abre el plano de [grupo]: el salón con su mesa encendida y el camino desde
/// el Ingreso, y VER LA LLEGADA. Lo mismo en la PC y en el celular.
Future<void> abrirPlanoDeLaFamilia(
  BuildContext context, {
  required String eventoId,
  required PuertaDelEvento puerta,
  required GrupoPuerta grupo,
  required SalonParaLaPuerta salon,
  bool animar = true,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _Marco(
        child: HojaPlanoFamilia(
          eventoId: eventoId,
          puerta: puerta,
          grupo: grupo,
          salon: salon,
          animar: animar,
        ),
      ),
    );

/// Abre el plano entero, con cada familia en su mesa.
Future<void> abrirPlanoEntero(
  BuildContext context, {
  required String eventoId,
  required PuertaDelEvento puerta,
  required SalonParaLaPuerta salon,
  bool animar = true,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _Marco(
        child: HojaPlanoEntero(
          eventoId: eventoId,
          puerta: puerta,
          salon: salon,
          animar: animar,
        ),
      ),
    );

/// Arriba de cada hoja: el título, lo de abajo y la X.
Widget _cabeza(BuildContext context, String titulo, String? debajo) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: _letra(size: 18, negrita: true)),
                if (debajo != null) ...[
                  const SizedBox(height: 2),
                  Text(debajo, style: _letra(size: 13, color: Colors.white60)),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: _perla),
          ),
        ],
      ),
    );

/// Una familia en el salón, en la pantalla de la recepcionista (6.5.0): su
/// mesa encendida y el camino desde el Ingreso, con el mismo panel de la tele
/// ([PanelPlano]). VER LA LLEGADA la reproduce entera, como la vio el salón,
/// **solo acá**: la tele no se entera.
class HojaPlanoFamilia extends StatefulWidget {
  const HojaPlanoFamilia({
    super.key,
    required this.eventoId,
    required this.puerta,
    required this.grupo,
    required this.salon,
    this.animar = true,
  });

  final String eventoId;
  final PuertaDelEvento puerta;
  final GrupoPuerta grupo;
  final SalonParaLaPuerta salon;

  /// False: quieta (los tests). Sin latido ni animación de la llegada.
  final bool animar;

  static const verLaLlegada = 'VER LA LLEGADA';
  static const soloAca =
      'Solo en tu pantalla: la tele del salón no se entera.';

  @override
  State<HojaPlanoFamilia> createState() => _HojaPlanoFamiliaState();
}

class _HojaPlanoFamiliaState extends State<HojaPlanoFamilia> {
  late final _guia = widget.salon.deLaFamilia(widget.grupo);
  late final _ficha = FichaTotem.desdePuerta(
    widget.eventoId,
    widget.puerta,
    plano: widget.salon.armado,
  );

  /// La llegada que se está reproduciendo, o null.
  BienvenidaTotem? _llegada;
  DateTime? _fin;
  bool _saliendo = false;
  Timer? _alTerminar;
  Timer? _alSalir;

  void _verLlegada() {
    _alTerminar?.cancel();
    _alSalir?.cancel();
    final ahora = DateTime.now();
    final dura = TiemposDeBienvenida.de(widget.salon.cfg, conSalon: true)
        .total(hayCola: false);
    setState(() {
      _llegada = SalonParaLaPuerta.llegadaDe(widget.eventoId, widget.grupo, ahora);
      _fin = ahora.add(dura);
      _saliendo = false;
    });
    _alTerminar = Timer(dura, () {
      if (!mounted) return;
      setState(() => _saliendo = true);
      _alSalir = Timer(EscenaTotem.salida, () {
        if (!mounted) return;
        setState(() {
          _llegada = null;
          _fin = null;
          _saliendo = false;
        });
      });
    });
  }

  @override
  void dispose() {
    _alTerminar?.cancel();
    _alSalir?.cancel();
    super.dispose();
  }

  String get _debajo {
    final g = widget.grupo;
    final t = g.titular;
    final partes = [
      if (t.mesa != null) 'Mesa ${t.mesa}',
      ?g.division,
      if (g.personas.any((p) => p.ingresado))
        'ADENTRO${t.textoHora == null ? '' : ' · ${t.textoHora}'}',
    ];
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final salon = widget.salon;
    final estilo = _estiloDe(salon);
    final llegada = _llegada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabeza(context, widget.grupo.titular.nombre, _debajo),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                final u = math.min(c.maxWidth, c.maxHeight) / 27;
                if (llegada != null) {
                  return ClipRRect(
                    key: const ValueKey('llegada_en_la_puerta'),
                    borderRadius: BorderRadius.circular(12),
                    child: EscenaTotem(
                      estilo: estilo,
                      respaldo: EstiloTotem.porDefecto(masivo: true),
                      cfg: salon.cfg,
                      llegada: ContenidoBienvenida.armar(
                        llegada,
                        ficha: _ficha,
                        cfg: salon.cfg,
                      ),
                      plano: salon.armado,
                      claveLlegada: llegada,
                      saliendo: _saliendo,
                      empezo: llegada.empezo,
                      fin: _fin,
                      quieta: !widget.animar,
                    ),
                  );
                }
                final guia = _guia;
                if (guia == null) {
                  return Center(
                    child: Text(
                      'Esta familia no tiene una mesa del plano.',
                      style: _letra(color: Colors.white60),
                    ),
                  );
                }
                final tema = temaPlanoDelTotem(estilo, salon.cfg.colorAcento);
                final caja = salon.armado.hoja(guia.hoja)?.caja;
                final radioPx = caja == null
                    ? double.infinity
                    : salon.armado.radio * EncuadrePlano.de(caja, c.biggest).escala;
                // En un celular el salón entero queda chico y sin números:
                // arranca acercado sobre la mesa de la familia, y se mueve con
                // los dedos.
                if (radioPx < _PlanoAcercado.radioLegible) {
                  return _PlanoAcercado(
                    key: const ValueKey('plano_de_la_familia'),
                    guia: guia,
                    tema: tema,
                    borde: salon.cfg.colorAcento,
                    tam: c.biggest,
                    animar: widget.animar,
                  );
                }
                return PanelPlano.deLaLlegada(
                  guia,
                  key: const ValueKey('plano_de_la_familia'),
                  tema: tema,
                  borde: salon.cfg.colorAcento,
                  u: u,
                  relleno: u * 0.35,
                  animar: widget.animar,
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                HojaPlanoFamilia.soloAca,
                style: _letra(size: 12, color: Colors.white54),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('ver_la_llegada'),
                    onPressed:
                        _guia == null || llegada != null ? null : _verLlegada,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      HojaPlanoFamilia.verLaLlegada,
                      style: _letra(size: 12, negrita: true, color: null),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _perla,
                      side: BorderSide(color: _perla.withValues(alpha: 0.4)),
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _perla,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(
                      'CERRAR',
                      style: _letra(size: 12, negrita: true, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// El salón de una familia en una pantalla chica (el celular de la puerta):
/// arranca acercado sobre su mesa principal, con los números a la vista, y se
/// mueve y se acerca con los dedos. La mesa encendida y el camino, los mismos de
/// [PanelPlano].
class _PlanoAcercado extends StatefulWidget {
  const _PlanoAcercado({
    super.key,
    required this.guia,
    required this.tema,
    required this.borde,
    required this.tam,
    required this.animar,
  });

  final PlanoDeLaLlegada guia;
  final TemaPlano tema;
  final Color borde;
  final Size tam;
  final bool animar;

  /// Por debajo de este radio en pantalla, una mesa no lleva su número.
  static const radioLegible = 14.0;

  @override
  State<_PlanoAcercado> createState() => _PlanoAcercadoState();
}

class _PlanoAcercadoState extends State<_PlanoAcercado> {
  final _zoom = TransformationController();
  Size? _armadoPara;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// Acercado sobre la mesa principal, sin salirse del salón.
  void _acercar() {
    final tam = widget.tam;
    if (_armadoPara == tam) return;
    _armadoPara = tam;
    final g = widget.guia;
    final caja = g.armado.hoja(g.hoja)?.caja;
    final mesa = g.armado.mesa(g.principal);
    if (caja == null || mesa == null) return;
    final encuadre = EncuadrePlano.de(caja, tam);
    final radioPx = g.armado.radio * encuadre.escala;
    if (radioPx <= 0) return;
    final z = (_PlanoAcercado.radioLegible * 1.3 / radioPx).clamp(1.0, 6.0);
    final p = encuadre.aPantalla(Offset(mesa.x, mesa.y));
    final tx = (tam.width / 2 - p.dx * z).clamp(tam.width * (1 - z), 0.0);
    final ty = (tam.height / 2 - p.dy * z).clamp(tam.height * (1 - z), 0.0);
    _zoom.value = Matrix4.diagonal3Values(z, z, 1)..setTranslationRaw(tx, ty, 0);
  }

  @override
  Widget build(BuildContext context) {
    _acercar();
    final g = widget.guia;
    final caja = g.armado.hoja(g.hoja)?.caja;
    final base =
        caja == null ? 1.0 : EncuadrePlano.de(caja, widget.tam).escala;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.borde, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: widget.tema.fondo,
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: 6,
            child: AnimatedBuilder(
              animation: _zoom,
              builder: (context, _) => VistaPlano(
                armado: g.armado,
                hoja: g.hoja,
                tema: widget.tema,
                estado: g.estado,
                resaltadas: g.mesas,
                ruta: g.ruta,
                animar: widget.animar,
                zoom: NivelDetalle.zoomQueCuenta(
                  g.armado.radio * base,
                  _zoom.value.getMaxScaleOnAxis(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El salón entero en la puerta (6.5.0): cada familia en su mesa, con los
/// apellidos al acercar, y FALTAN ENTRAR que deja encendidas solo las de las
/// familias en las que no entró nadie. Tocar una mesa abre esa familia.
class HojaPlanoEntero extends StatefulWidget {
  const HojaPlanoEntero({
    super.key,
    required this.eventoId,
    required this.puerta,
    required this.salon,
    this.animar = true,
  });

  final String eventoId;
  final PuertaDelEvento puerta;
  final SalonParaLaPuerta salon;
  final bool animar;

  static const titulo = 'El plano entero';

  @override
  State<HojaPlanoEntero> createState() => _HojaPlanoEnteroState();
}

class _HojaPlanoEnteroState extends State<HojaPlanoEntero> {
  late final _entero = widget.salon.entero(widget.puerta);
  late String _hoja = _entero.hoja;
  final _zoom = TransformationController();
  bool _soloFaltan = false;
  String? _aviso;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _tocar(int mesa) {
    final g = _entero.familiaDeMesa[mesa];
    if (g == null) {
      setState(() => _aviso = 'La mesa $mesa no es de ninguna familia.');
      return;
    }
    setState(() => _aviso = null);
    unawaited(abrirPlanoDeLaFamilia(
      context,
      eventoId: widget.eventoId,
      puerta: widget.puerta,
      grupo: g,
      salon: widget.salon,
      animar: widget.animar,
    ));
  }

  Widget _chip(String texto, bool elegido, VoidCallback alTocar, {Key? key}) =>
      ChoiceChip(
        key: key,
        label: Text(texto),
        labelStyle: _letra(
          size: 13,
          negrita: elegido,
          color: elegido ? Colors.black : _perla,
        ),
        selected: elegido,
        showCheckmark: false,
        selectedColor: _perla,
        backgroundColor: Colors.white.withValues(alpha: 0.04),
        side: BorderSide(color: _perla.withValues(alpha: 0.2)),
        onSelected: (_) => alTocar(),
      );

  @override
  Widget build(BuildContext context) {
    final salon = widget.salon;
    final armado = salon.armado;
    final estilo = _estiloDe(salon);
    final tema = temaPlanoDelTotem(estilo, salon.cfg.colorAcento);
    final faltan = _entero.familiasQueFaltan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabeza(
          context,
          HojaPlanoEntero.titulo,
          'Tocá una mesa para ver esa familia. Con dos dedos, o la rueda, se '
          'acerca y aparecen los apellidos.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip('Todas', !_soloFaltan,
                  () => setState(() => _soloFaltan = false)),
              _chip(
                faltan == 1
                    ? 'Falta entrar 1 familia'
                    : 'Faltan entrar $faltan familias',
                _soloFaltan,
                () => setState(() => _soloFaltan = true),
                key: const ValueKey('faltan_entrar'),
              ),
              if (armado.hojas.length > 1)
                for (final h in armado.hojas)
                  if (armado.mesasDeHoja(h.id).isNotEmpty)
                    _chip(
                      h.titulo.isEmpty ? 'Hoja' : h.titulo,
                      h.id == _hoja,
                      () => setState(() {
                        _hoja = h.id;
                        _zoom.value = Matrix4.identity();
                      }),
                    ),
            ],
          ),
        ),
        if (_aviso != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(_aviso!, style: _letra(size: 13, color: _ambar)),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                final hoja = armado.hoja(_hoja);
                if (hoja == null) return const SizedBox.shrink();
                final base = EncuadrePlano.de(hoja.caja, c.biggest).escala;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: tema.fondo,
                    child: InteractiveViewer(
                      transformationController: _zoom,
                      minScale: 1,
                      maxScale: 6,
                      child: AnimatedBuilder(
                        animation: _zoom,
                        builder: (context, _) => VistaPlano(
                          key: const ValueKey('plano_entero'),
                          armado: armado,
                          hoja: _hoja,
                          tema: tema,
                          estado: _entero.estado,
                          resaltadas: _soloFaltan ? _entero.faltan : const {},
                          animar: false,
                          zoom: NivelDetalle.zoomQueCuenta(
                            armado.radio * base,
                            _zoom.value.getMaxScaleOnAxis(),
                          ),
                          onTapMesa: _tocar,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _soloFaltan
                      ? 'Encendidas: las familias en las que todavía no entró nadie.'
                      : '${widget.puerta.adentro} de ${widget.puerta.total} '
                          'adentro.',
                  style: _letra(
                    size: 12,
                    color: _soloFaltan ? _ambar : _verde,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: _perla,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 44),
                ),
                child: Text(
                  'CERRAR',
                  style: _letra(size: 12, negrita: true, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
