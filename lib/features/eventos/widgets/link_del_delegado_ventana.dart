import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../delegado/datos/link_del_delegado.dart';
import '../../delegado/datos/nube_del_delegado.dart';

/// El día y la hora límite que eligió el jefe, en hora de Argentina.
typedef LimiteElegido = ({DateTime dia, TimeOfDay hora});

/// Deja elegir el límite. Las pruebas la reemplazan: los selectores de fecha y
/// de hora no se pueden manejar con comodidad en una prueba.
typedef ElegirLimite = Future<LimiteElegido?> Function(
  BuildContext context,
  LimiteElegido desde,
);

Future<LimiteElegido?> elegirLimiteConSelectores(
  BuildContext context,
  LimiteElegido desde,
) async {
  final hoy = DateTime.now();
  final dia = await showDatePicker(
    context: context,
    initialDate: desde.dia.isBefore(hoy) ? hoy : desde.dia,
    firstDate: DateTime(hoy.year, hoy.month, hoy.day),
    lastDate: hoy.add(const Duration(days: 365)),
    // Corto: el selector corta un título largo ("Hasta qué día pu…").
    helpText: 'Día límite',
  );
  if (dia == null || !context.mounted) return null;
  final hora = await showTimePicker(
    context: context,
    initialTime: desde.hora,
    helpText: 'Hasta qué hora',
  );
  if (hora == null) return null;
  return (dia: dia, hora: hora);
}

/// Qué alumnos se ven en la lista.
enum FiltroDelLink { todos, faltan, sinEnviar, paraTraer }

/// **Link para los delegados**: la ventana propia del link de una fiesta
/// (6.9.2; antes era una sección al fondo del cartel del Excel). Se abre desde
/// PLANILLAS ▾ → "Link para los delegados" y desde la alerta del Centro de
/// Comando.
///
/// Todo en una hoja: arriba, si el link está abierto y hasta cuándo, con
/// COPIAR LINK, REABRIR HASTA… y CERRAR AHORA; a la izquierda los delegados (la
/// persona, con todos sus celulares) y a la derecha los alumnos, con lo
/// vigente, **quién lo cargó y cuándo**, en qué quedó y su historial.
///
/// **No guarda nada en la grilla.** [onTraer] abre el "Antes de guardar" de
/// siempre, y de ahí entra solo lo que el jefe acepta. Todo lo que cambia el
/// link lo decide la nube ([LinkDelDelegado]). La abre la pantalla de la fiesta
/// desde la función que ya pidió el modo jefe (`test/solo_modo_jefe_test.dart`).
class LinkDelDelegadoVentana extends StatefulWidget {
  final LinkDelDelegado link;
  final String eventoId;

  /// El nombre de la fiesta, como lo va a ver el delegado.
  final String fiesta;

  /// El link completo, a partir de la clave.
  final String Function(String clave) urlDelLink;

  /// TRAER LO CARGADO: abre la revisión. Al volver, la ventana se relee.
  final Future<void> Function() onTraer;
  final ElegirLimite elegirLimite;

  const LinkDelDelegadoVentana({
    super.key,
    required this.link,
    required this.eventoId,
    required this.fiesta,
    required this.urlDelLink,
    required this.onTraer,
    this.elegirLimite = elegirLimiteConSelectores,
  });

  @override
  State<LinkDelDelegadoVentana> createState() => _LinkDelDelegadoVentanaState();
}

class _LinkDelDelegadoVentanaState extends State<LinkDelDelegadoVentana> {
  EstadoDelLink? _estado;
  List<AlumnoDelTablero> _alumnos = const [];
  List<CambioDelHistorial> _historial = const [];
  bool _fallo = false;
  bool _ocupado = false;
  String? _dicho;
  bool _dichoEsError = false;

  FiltroDelLink _filtro = FiltroDelLink.todos;

  /// El delegado elegido a la izquierda ([DelegadoDelLink.id]). Null: todos.
  String? _deQuien;

  /// Los alumnos con el historial abierto.
  final _conHistorial = <String>{};

  /// Lo elegido para un link nuevo.
  late LimiteElegido _limite = (
    dia: DateTime.now().add(const Duration(days: 7)),
    hora: const TimeOfDay(hour: 20, minute: 0),
  );
  int _cupo = 1;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  /// Vuelve a preguntarle a la nube cómo está todo.
  Future<void> _recargar() async {
    try {
      final e = await widget.link.estado(widget.eventoId);
      var alumnos = const <AlumnoDelTablero>[];
      var historial = const <CambioDelHistorial>[];
      if (e.hay) {
        alumnos = await widget.link.alumnos(widget.eventoId);
        historial = await widget.link.historial(widget.eventoId);
      }
      if (!mounted) return;
      setState(() {
        _estado = e;
        _alumnos = alumnos;
        _historial = historial;
        _fallo = false;
        // Si el delegado elegido ya no está, se ven todos.
        if (!e.delegados.any((d) => d.id == _deQuien)) _deQuien = null;
      });
    } catch (_) {
      if (mounted) setState(() => _fallo = true);
    }
  }

  void _decir(String? texto, {bool error = false}) => setState(() {
        _dicho = texto;
        _dichoEsError = error;
      });

  static const _porQueNo = <String, String>{
    'pasada': 'El día y la hora límite tienen que ser futuros.',
    'fecha': 'Elegí el día y la hora límite.',
    'cupo': 'Elegí cuántos delegados, de 1 a $kMaxDelegadosPorLink.',
    'ya_existe': 'Esta fiesta ya tiene su link.',
    'fiesta': 'La fiesta no tiene nombre para mostrarle al delegado.',
  };

  /// Hace [accion] contra la nube y vuelve a leer. Un error se dice en
  /// palabras, nunca con el texto de la excepción.
  Future<void> _hacer(
    Future<RespuestaDelegado> Function() accion, {
    String? dicho,
  }) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _dicho = null;
    });
    try {
      final r = await accion();
      await _recargar();
      if (!mounted) return;
      if (r.ok) {
        _decir(dicho);
      } else {
        _decir(_porQueNo[r.motivo] ?? 'No se pudo. Probá de nuevo.', error: true);
      }
    } catch (_) {
      if (mounted) {
        _decir('No se pudo: hace falta internet. Probá de nuevo.', error: true);
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  String _local(LimiteElegido l) =>
      venceLocalDe(l.dia, l.hora.hour, l.hora.minute);

  String _diaYHora(LimiteElegido l) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(l.dia.day)}/${dos(l.dia.month)} a las '
        '${dos(l.hora.hour)}:${dos(l.hora.minute)}';
  }

  Future<void> _elegirParaCrear() async {
    final l = await widget.elegirLimite(context, _limite);
    if (l != null && mounted) setState(() => _limite = l);
  }

  /// REABRIR HASTA… / CAMBIAR LA FECHA…: una fecha futura abre el link para
  /// todos, también si estaba cerrado a mano o vencido, las veces que haga
  /// falta.
  Future<void> _cambiarLimite(EstadoDelLink e) async {
    final p = e.venceLocal.split(RegExp(r'[- :]'));
    final guardado = p.length == 5
        ? (
            dia: DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])),
            hora: TimeOfDay(hour: int.parse(p[3]), minute: int.parse(p[4])),
          )
        : _limite;
    // Reabriendo, la fecha vieja ya pasó: se ofrece la de una semana más.
    final l = await widget.elegirLimite(context, e.abierto ? guardado : _limite);
    if (l == null || !mounted) return;
    await _hacer(
      () => widget.link.cambiar(widget.eventoId, 'vence', _local(l)),
      dicho: e.abierto
          ? 'El límite quedó para el ${_diaYHora(l)}.'
          : 'Abierto hasta el ${_diaYHora(l)}. Todos pueden volver a cargar y '
              'corregir.',
    );
  }

  /// Si el equipo no deja copiar (pasa en algunos navegadores), lo dice: el
  /// link está escrito debajo y se puede seleccionar. Antes el botón no hacía
  /// nada y no avisaba.
  Future<void> _copiar(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) _decir('Link copiado. Pegalo en WhatsApp.');
    } catch (_) {
      if (mounted) {
        _decir(
          'No se pudo copiar solo. El link está escrito arriba: '
          'seleccionalo y copialo.',
          error: true,
        );
      }
    }
  }

  Future<void> _sacar(DelegadoDelLink d) async {
    final como = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sacar a ${d.nombre}'),
        content: Text(
          'No va a poder entrar más con su nombre, desde ningún celular. '
          'Cargó ${d.cargados} alumno(s). ¿Qué hacemos con eso?\n\n'
          'Si lo dejás, sigue diciendo que lo cargó ${d.nombre} y cuándo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('NO SACAR'),
          ),
          TextButton(
            key: const Key('link_sacar_borrando'),
            onPressed: () => Navigator.pop(context, 'sacar_borrando'),
            child: const Text('SACAR Y BORRAR LO QUE CARGÓ'),
          ),
          ElevatedButton(
            key: const Key('link_sacar_dejando'),
            onPressed: () => Navigator.pop(context, 'sacar_dejando'),
            child: const Text('SACAR Y DEJAR LO QUE CARGÓ'),
          ),
        ],
      ),
    );
    if (como == null || !mounted) return;
    await _hacer(
      () => widget.link.cambiar(widget.eventoId, como, d.id),
      dicho: '${d.nombre} ya no puede entrar.',
    );
  }

  Future<void> _traer() async {
    if (_ocupado) return;
    setState(() => _dicho = null);
    await widget.onTraer();
    if (mounted) await _recargar();
  }

  // ── Lo que se ve ──────────────────────────────────────────────────────────

  List<AlumnoDelTablero> get _visibles => [
        for (final a in _alumnos)
          if ((_deQuien == null || a.delegadoId == _deQuien) &&
              switch (_filtro) {
                FiltroDelLink.todos => true,
                FiltroDelLink.faltan => a.estado == EstadoDeLaCarga.falta,
                FiltroDelLink.sinEnviar => a.estado == EstadoDeLaCarga.sinEnviar,
                FiltroDelLink.paraTraer => a.estado == EstadoDeLaCarga.enviado,
              })
            a,
      ];

  static (String, Color) _rotuloDe(EstadoDeLaCarga e) => switch (e) {
        EstadoDeLaCarga.falta => ('Falta', Colors.orange.shade800),
        EstadoDeLaCarga.sinEnviar => ('Sin enviar', Colors.blueGrey),
        EstadoDeLaCarga.enviado => ('Enviado · falta traerlo', Colors.indigo),
        EstadoDeLaCarga.aceptado => ('Aceptado', Colors.green.shade700),
        EstadoDeLaCarga.programa =>
          ('Ya estaba en el programa', Colors.green.shade700),
      };

  Widget _chip(String texto, Color color, {Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          texto,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final e = _estado;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 780),
        child: Padding(
          key: const Key('link_del_delegado'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Link para los delegados',
                          style: tema.textTheme.titleLarge,
                        ),
                        Text(
                          widget.fiesta,
                          style: tema.textTheme.bodySmall
                              ?.copyWith(color: tema.hintColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('link_cerrar_ventana'),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_fallo)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'No se pudo consultar el link: hace falta '
                                'internet.',
                                key: const Key('link_sin_red'),
                                style: tema.textTheme.bodyMedium,
                              ),
                            ),
                            TextButton(
                              key: const Key('link_reintentar'),
                              onPressed: _recargar,
                              child: const Text('REINTENTAR'),
                            ),
                          ],
                        )
                      else if (e == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (!e.hay)
                        ..._sinLink(tema)
                      else
                        ..._conLink(tema, e),
                    ],
                  ),
                ),
              ),
              // Lo que pasó, fijo abajo: al final de la lista de alumnos no se
              // veía sin desplazarse (se vio en la prueba de punta a punta).
              if (_dicho != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _dicho!,
                    key: const Key('link_dicho'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _dichoEsError ? Colors.redAccent : Colors.teal,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sinLink(ThemeData tema) => [
        Text(
          'Esta fiesta todavía no tiene link. Los delegados cargan desde el '
          'celular los acompañantes y la música de los alumnos; a la grilla '
          'entra solo lo que vos aceptás.',
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('link_elegir_limite'),
              onPressed: _ocupado ? null : _elegirParaCrear,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Hasta el ${_diaYHora(_limite)}'),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Delegados: '),
                DropdownButton<int>(
                  key: const Key('link_cupo'),
                  value: _cupo,
                  onChanged: _ocupado
                      ? null
                      : (v) => setState(() => _cupo = v ?? _cupo),
                  items: [
                    for (var n = 1; n <= kMaxDelegadosPorLink; n++)
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                ),
              ],
            ),
            ElevatedButton.icon(
              key: const Key('link_crear'),
              onPressed: _ocupado
                  ? null
                  : () => _hacer(
                        () => widget.link.crear(
                          eventoId: widget.eventoId,
                          fiesta: widget.fiesta,
                          venceLocal: _local(_limite),
                          cupo: _cupo,
                        ),
                        dicho: 'Link creado. Copialo y mandáselo a los '
                            'delegados.',
                      ),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('CREAR LINK'),
            ),
          ],
        ),
      ];

  /// "De 12 alumnos: 9 faltan · 1 sin enviar · 1 enviado · 0 aceptados · 1 ya
  /// estaba en el programa.": con uno solo no dice "1 enviados".
  static String _laCuenta(EstadoDelLink e) {
    String n(int c, String uno, String varios) => '$c ${c == 1 ? uno : varios}';
    return 'De ${n(e.total, 'alumno', 'alumnos')}: '
        '${n(e.faltan, 'falta', 'faltan')} · ${e.sinEnviar} sin enviar · '
        '${n(e.enviados, 'enviado', 'enviados')} · '
        '${n(e.aceptados, 'aceptado', 'aceptados')} · '
        '${n(e.enPrograma, 'ya estaba', 'ya estaban')} en el programa.';
  }

  List<Widget> _conLink(ThemeData tema, EstadoDelLink e) {
    final abierto = e.abierto;
    final color = abierto ? Colors.green.shade700 : Colors.red.shade700;
    final sinTraer = e.enviados + e.sinEnviar;
    return [
      // ── Arriba: el estado, en grande ──
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    abierto ? 'ABIERTO hasta el ${e.venceTexto}' : 'CERRADO',
                    key: const Key('link_estado'),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  Text(
                    abierto
                        ? 'Los delegados pueden cargar y corregir. Se cierra '
                            'solo ese día.'
                        : e.estado == EstadoLink.apagado
                            ? 'Lo cerraste vos. Nadie puede cargar hasta que '
                                'lo reabras.'
                            : 'El plazo terminó el ${e.venceTexto}. Nadie '
                                'puede cargar hasta que lo reabras.',
                    key: const Key('link_estado_detalle'),
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              key: const Key('link_copiar'),
              onPressed: () => _copiar(widget.urlDelLink(e.clave)),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('COPIAR LINK'),
            ),
            abierto
                ? OutlinedButton(
                    key: const Key('link_cambiar_limite'),
                    onPressed: _ocupado ? null : () => _cambiarLimite(e),
                    child: const Text('CAMBIAR LA FECHA…'),
                  )
                : FilledButton(
                    key: const Key('link_cambiar_limite'),
                    onPressed: _ocupado ? null : () => _cambiarLimite(e),
                    child: const Text('REABRIR HASTA…'),
                  ),
            if (abierto)
              TextButton(
                key: const Key('link_apagar'),
                onPressed: _ocupado
                    ? null
                    : () => _hacer(
                          () => widget.link.cambiar(widget.eventoId, 'apagar'),
                          dicho: 'Link cerrado. Nadie puede cargar hasta que '
                              'lo reabras.',
                        ),
                child: Text(
                  'CERRAR AHORA',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      SelectableText(
        widget.urlDelLink(e.clave),
        key: const Key('link_url'),
        style: tema.textTheme.bodySmall?.copyWith(color: tema.hintColor),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _laCuenta(e),
            key: const Key('link_cuenta'),
            style: tema.textTheme.bodySmall,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Delegados: hasta ', style: tema.textTheme.bodySmall),
              DropdownButton<int>(
                key: const Key('link_cupo'),
                value: e.cupo.clamp(1, kMaxDelegadosPorLink),
                isDense: true,
                onChanged: _ocupado
                    ? null
                    : (v) => v == null || v == e.cupo
                        ? null
                        : _hacer(
                            () => widget.link
                                .cambiar(widget.eventoId, 'cupo', '$v'),
                          ),
                items: [
                  for (var n = 1; n <= kMaxDelegadosPorLink; n++)
                    DropdownMenuItem(
                      value: n,
                      child: Text(n == 1 ? '1 persona' : '$n personas'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ElevatedButton.icon(
            key: const Key('link_traer'),
            onPressed: _ocupado || sinTraer == 0 ? null : _traer,
            icon: const Icon(Icons.download_done_rounded, size: 18),
            label: Text(
              e.enviados > 0
                  ? 'TRAER LO CARGADO (${e.enviados})'
                  : 'TRAER LO CARGADO',
            ),
          ),
          Text(
            'Nada entra a la grilla sin tu ACEPTAR Y CARGAR.',
            style: tema.textTheme.bodySmall,
          ),
        ],
      ),
      const Divider(height: 26),
      // ── La hoja: los delegados a la izquierda, los alumnos a la derecha ──
      LayoutBuilder(
        builder: (context, c) {
          final delegados = _losDelegados(tema, e);
          final alumnos = _losAlumnos(tema);
          if (c.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [delegados, const SizedBox(height: 12), alumnos],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 270, child: delegados),
              const SizedBox(width: 14),
              Expanded(child: alumnos),
            ],
          );
        },
      ),
    ];
  }

  Widget _tarjeta({
    required Key key,
    required bool elegida,
    required VoidCallback alTocar,
    required List<Widget> hijos,
  }) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: alTocar,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: elegida ? tema.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: hijos,
            ),
          ),
        ),
      ),
    );
  }

  Widget _losDelegados(ThemeData tema, EstadoDelLink e) {
    final chico = tema.textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DELEGADOS', style: tema.textTheme.labelLarge),
        const SizedBox(height: 6),
        _tarjeta(
          key: const Key('link_delegado_todos'),
          elegida: _deQuien == null,
          alTocar: () => setState(() => _deQuien = null),
          hijos: [
            const Text('Todos', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              '${e.total} alumnos · ${e.faltan} faltan',
              style: chico,
            ),
          ],
        ),
        if (e.delegados.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Todavía no entró ningún delegado.',
              key: const Key('link_sin_delegados'),
              style: chico,
            ),
          ),
        for (final d in e.delegados)
          _tarjeta(
            key: Key('link_delegado_${d.id}'),
            elegida: _deQuien == d.id,
            alTocar: () => setState(() {
              _deQuien = d.id;
              _filtro = FiltroDelLink.todos;
            }),
            hijos: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      d.nombre,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: d.sacado ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (d.sacado)
                    TextButton(
                      key: Key('link_readmitir_${d.id}'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _ocupado
                          ? null
                          : () => _hacer(
                                () => widget.link.cambiar(
                                  widget.eventoId,
                                  'readmitir',
                                  d.id,
                                ),
                                dicho: '${d.nombre} puede entrar de nuevo.',
                              ),
                      child: const Text('DEJAR ENTRAR'),
                    )
                  else
                    TextButton(
                      key: Key('link_sacar_${d.id}'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.red.shade700,
                      ),
                      onPressed: _ocupado ? null : () => _sacar(d),
                      child: const Text('SACAR'),
                    ),
                ],
              ),
              Text(
                d.sacado
                    ? 'Sacado · entró ${d.entroTexto}'
                    : 'Entró ${d.entroTexto}'
                        '${d.aparatos > 1 ? ' · desde ${d.aparatos} celulares' : ''}',
                style: chico,
              ),
              Text(
                'Cargó ${d.cargados} · '
                '${d.envioTexto == null ? 'todavía no envió' : 'envió ${d.envioTexto}'}'
                '${d.sinEnviar > 0 && d.envioTexto != null ? ' · ${d.sinEnviar} sin enviar' : ''}',
                style: chico,
              ),
            ],
          ),
      ],
    );
  }

  Widget _losAlumnos(ThemeData tema) {
    final chico = tema.textTheme.bodySmall;
    final visibles = _visibles;
    final porAlumno = <String, List<CambioDelHistorial>>{};
    for (final h in _historial) {
      porAlumno.putIfAbsent(h.alumnoId, () => []).add(h);
    }
    Widget filtro(FiltroDelLink f, String texto) => ChoiceChip(
          key: Key('link_filtro_${f.name}'),
          label: Text(texto),
          selected: _filtro == f,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _filtro = f),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ALUMNOS', style: tema.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            filtro(FiltroDelLink.todos, 'Todos'),
            filtro(FiltroDelLink.faltan, 'Faltan'),
            filtro(FiltroDelLink.sinEnviar, 'Sin enviar'),
            filtro(FiltroDelLink.paraTraer, 'Para traer'),
          ],
        ),
        const SizedBox(height: 8),
        if (visibles.isEmpty)
          Text(
            'Ningún alumno con ese filtro.',
            key: const Key('link_sin_alumnos'),
            style: chico,
          ),
        for (final a in visibles)
          Container(
            key: Key('link_alumno_${a.alumnoId}'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: tema.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      a.division.isEmpty ? a.alumno : '${a.alumno} · ${a.division}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    _chip(
                      _rotuloDe(a.estado).$1,
                      _rotuloDe(a.estado).$2,
                      key: Key('link_estado_${a.alumnoId}'),
                    ),
                    if (a.otraVez)
                      _chip(
                        a.estado == EstadoDeLaCarga.sinEnviar ||
                                a.estado == EstadoDeLaCarga.enviado
                            ? 'Corrige lo que ya está en el programa'
                            : 'Corregido',
                        Colors.red.shade700,
                        key: Key('link_otra_vez_${a.alumnoId}'),
                      ),
                    TextButton(
                      key: Key('link_historial_${a.alumnoId}'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(() {
                        if (!_conHistorial.remove(a.alumnoId)) {
                          _conHistorial.add(a.alumnoId);
                        }
                      }),
                      child: Text(
                        _conHistorial.contains(a.alumnoId)
                            ? 'CERRAR'
                            : 'HISTORIAL',
                      ),
                    ),
                  ],
                ),
                if (a.acompanantes.isNotEmpty || a.musica.isNotEmpty)
                  Text(
                    [
                      if (a.acompanantes.isNotEmpty)
                        'Acompañantes: ${a.acompanantes.join(' · ')}',
                      if (a.musica.isNotEmpty) 'Música: ${a.musica}',
                    ].join(' — '),
                    style: chico,
                  ),
                if (a.cargo != null)
                  Text(
                    'Lo cargó ${a.cargo}'
                    '${a.cuandoTexto == null ? '' : ' · ${a.cuandoTexto}'}',
                    key: Key('link_quien_${a.alumnoId}'),
                    style: chico?.copyWith(fontWeight: FontWeight.w600),
                  ),
                if (_conHistorial.contains(a.alumnoId))
                  Container(
                    key: Key('link_cambios_${a.alumnoId}'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((porAlumno[a.alumnoId] ?? const []).isEmpty)
                          Text(
                            a.estado == EstadoDeLaCarga.programa
                                ? 'Se cargó en el programa (por Excel o a '
                                    'mano), no por el link.'
                                : 'Todavía nadie cargó a este alumno.',
                            style: chico,
                          ),
                        for (final h in porAlumno[a.alumnoId] ?? const [])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.5),
                            child: Text(
                              '${h.cuandoTexto} · ${h.quien} · ${h.enPalabras}',
                              style: chico,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
