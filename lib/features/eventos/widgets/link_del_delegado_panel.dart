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

/// La sección LINK PARA LOS DELEGADOS de PLANILLAS → "Acompañantes y música"
/// (6.8.0): crear el link de la fiesta, ver quién entró y cuánto cargó, y
/// traer lo cargado.
///
/// No guarda nada en la grilla: [onTraer] le pasa a la ventana lo que cargaron
/// los delegados, y la ventana lo muestra en el "Antes de guardar" de siempre.
/// Todo lo que cambia el link lo decide la nube (`LinkDelDelegado`).
class LinkDelDelegadoPanel extends StatefulWidget {
  final LinkDelDelegado link;
  final String eventoId;

  /// El nombre de la fiesta, como lo va a ver el delegado.
  final String fiesta;

  /// El link completo, a partir de la clave.
  final String Function(String clave) urlDelLink;
  final Future<void> Function() onTraer;
  final ElegirLimite elegirLimite;

  const LinkDelDelegadoPanel({
    super.key,
    required this.link,
    required this.eventoId,
    required this.fiesta,
    required this.urlDelLink,
    required this.onTraer,
    this.elegirLimite = elegirLimiteConSelectores,
  });

  @override
  State<LinkDelDelegadoPanel> createState() => LinkDelDelegadoPanelState();
}

class LinkDelDelegadoPanelState extends State<LinkDelDelegadoPanel> {
  EstadoDelLink? _estado;
  bool _fallo = false;
  bool _ocupado = false;
  String? _dicho;
  bool _dichoEsError = false;

  /// Lo elegido para un link nuevo.
  late LimiteElegido _limite = (
    dia: DateTime.now().add(const Duration(days: 7)),
    hora: const TimeOfDay(hour: 20, minute: 0),
  );
  int _cupo = 1;

  @override
  void initState() {
    super.initState();
    recargar();
  }

  /// Vuelve a preguntarle a la nube cómo está el link.
  Future<void> recargar() async {
    try {
      final e = await widget.link.estado(widget.eventoId);
      if (mounted) {
        setState(() {
          _estado = e;
          _fallo = false;
        });
      }
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

  /// Hace [accion] contra la nube y vuelve a leer el link. Un error se dice en
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
      await recargar();
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

  String _dicho2(LimiteElegido l) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(l.dia.day)}/${dos(l.dia.month)} a las '
        '${dos(l.hora.hour)}:${dos(l.hora.minute)}';
  }

  Future<void> _elegirParaCrear() async {
    final l = await widget.elegirLimite(context, _limite);
    if (l != null && mounted) setState(() => _limite = l);
  }

  Future<void> _cambiarLimite(EstadoDelLink e) async {
    final p = e.venceLocal.split(RegExp(r'[- :]'));
    final desde = p.length == 5
        ? (
            dia: DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])),
            hora: TimeOfDay(hour: int.parse(p[3]), minute: int.parse(p[4])),
          )
        : _limite;
    final l = await widget.elegirLimite(context, desde);
    if (l == null || !mounted) return;
    await _hacer(
      () => widget.link.cambiar(widget.eventoId, 'vence', _local(l)),
      dicho: 'El límite quedó para el ${_dicho2(l)}.',
    );
  }

  Future<void> _copiar(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _decir('Link copiado. Pegalo en WhatsApp.');
  }

  Future<void> _sacar(CelularDelLink c) async {
    final como = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sacar a ${c.nombre}'),
        content: Text(
          'Ese celular no va a poder entrar más. Cargó ${c.cargados} '
          'alumno(s). ¿Qué hacemos con eso?',
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
      () => widget.link.cambiar(widget.eventoId, como, c.id),
      dicho: '${c.nombre} ya no puede entrar.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final e = _estado;
    return Container(
      key: const Key('link_del_delegado'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tema.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LINK PARA LOS DELEGADOS', style: tema.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (e == null && !_fallo)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (e == null)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'No se pudo consultar el link: hace falta internet. El '
                    'Excel anda igual.',
                    key: Key('link_sin_internet'),
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: recargar,
                  child: const Text('REINTENTAR'),
                ),
              ],
            )
          else if (!e.hay)
            ..._sinLink(tema)
          else
            ..._conLink(tema, e),
          if (_dicho != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _dicho!,
                key: const Key('link_dicho'),
                style: TextStyle(
                  fontSize: 13,
                  color: _dichoEsError ? Colors.redAccent : Colors.teal,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sinLink(ThemeData tema) => [
        Text(
          'Los delegados cargan desde el celular los acompañantes y la música '
          'de los alumnos. A la grilla entra solo lo que vos aceptás.',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('link_elegir_limite'),
              onPressed: _ocupado ? null : _elegirParaCrear,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Hasta el ${_dicho2(_limite)}'),
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

  List<Widget> _conLink(ThemeData tema, EstadoDelLink e) {
    final url = widget.urlDelLink(e.clave);
    final (rotulo, color) = switch (e.estado) {
      EstadoLink.abierto => ('Abierto', Colors.teal),
      EstadoLink.vencido => ('Vencido', Colors.orange.shade800),
      EstadoLink.apagado => ('Apagado', Colors.redAccent),
    };
    return [
      Row(
        children: [
          Expanded(
            child: SelectableText(
              url,
              key: const Key('link_url'),
              maxLines: 1,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          TextButton.icon(
            key: const Key('link_copiar'),
            onPressed: () => _copiar(url),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('COPIAR'),
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            rotulo,
            key: const Key('link_estado'),
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          Text(
            '· hasta el ${e.venceTexto} · '
            '${e.cupo == 1 ? '1 delegado' : '${e.cupo} delegados'}',
            key: const Key('link_limite'),
            style: const TextStyle(fontSize: 13),
          ),
          TextButton(
            key: const Key('link_cambiar_limite'),
            onPressed: _ocupado ? null : () => _cambiarLimite(e),
            child: const Text('CAMBIAR EL LÍMITE'),
          ),
          DropdownButton<int>(
            key: const Key('link_cambiar_cupo'),
            value: e.cupo.clamp(1, kMaxDelegadosPorLink),
            isDense: true,
            onChanged: _ocupado
                ? null
                : (v) {
                    if (v == null || v == e.cupo) return;
                    _hacer(
                      () => widget.link.cambiar(widget.eventoId, 'cupo', '$v'),
                    );
                  },
            items: [
              for (var n = 1; n <= kMaxDelegadosPorLink; n++)
                DropdownMenuItem(
                  value: n,
                  child: Text(n == 1 ? '1 delegado' : '$n delegados'),
                ),
            ],
          ),
          TextButton(
            key: const Key('link_apagar'),
            onPressed: _ocupado
                ? null
                : () => _hacer(
                      () => widget.link.cambiar(
                        widget.eventoId,
                        e.estado == EstadoLink.apagado ? 'prender' : 'apagar',
                      ),
                    ),
            child: Text(
              e.estado == EstadoLink.apagado ? 'PRENDER' : 'APAGAR',
            ),
          ),
        ],
      ),
      Text(
        'De ${e.total} alumnos: ${e.enPrograma} ya estaban en el programa · '
        '${e.cargados} cargaron los delegados · faltan ${e.faltan}',
        key: const Key('link_cuenta'),
        style: const TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 6),
      if (e.celulares.isEmpty)
        Text(
          'Todavía no entró ningún delegado.',
          style: tema.textTheme.bodySmall,
        )
      else
        for (final c in e.celulares)
          Padding(
            key: Key('link_celular_${c.id}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${c.nombre}${c.sacado ? ' (sacado)' : ''} · entró el '
                    '${c.entroTexto} · cargó ${c.cargados} · '
                    '${c.entregado ? 'envió el ${c.entregadoTexto ?? ''}' : 'todavía no envió'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (!c.sacado && c.entregado)
                  TextButton(
                    key: Key('link_reabrir_${c.id}'),
                    onPressed: _ocupado
                        ? null
                        : () => _hacer(
                              () => widget.link
                                  .cambiar(widget.eventoId, 'reabrir', c.id),
                              dicho: '${c.nombre} puede volver a cambiar lo '
                                  'suyo y enviar de nuevo.',
                            ),
                    child: const Text('REABRIRLE'),
                  ),
                if (!c.sacado)
                  TextButton(
                    key: Key('link_sacar_${c.id}'),
                    onPressed: _ocupado ? null : () => _sacar(c),
                    child: const Text('SACAR'),
                  ),
              ],
            ),
          ),
      const SizedBox(height: 8),
      ElevatedButton.icon(
        key: const Key('link_traer'),
        onPressed: _ocupado || e.cargados == 0 ? null : widget.onTraer,
        icon: const Icon(Icons.download_done_rounded, size: 18),
        label: const Text('TRAER LO CARGADO'),
      ),
    ];
  }
}
