import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import '../services/reparto_de_sillas.dart';
import '../services/salon_mesas.dart';

/// Elegir dónde van las sillas extra de un alumno: en la mesa principal (P) o
/// en la adicional (A). Solo muestra las formas posibles —hasta 2 por mesa y
/// que sumen lo comprado—, así que no se puede elegir una que no entre.
///
/// Devuelve la opción elegida, o `null` si se cerró sin guardar.
Future<OpcionReparto?> mostrarRepartoSillasDialog({
  required BuildContext context,
  required ContratoAlumno alumno,
  SillasReparto? guardado,
}) =>
    showDialog<OpcionReparto>(
      context: context,
      builder: (_) => _RepartoSillasDialog(alumno: alumno, guardado: guardado),
    );

class _RepartoSillasDialog extends StatefulWidget {
  final ContratoAlumno alumno;
  final SillasReparto? guardado;

  const _RepartoSillasDialog({required this.alumno, this.guardado});

  @override
  State<_RepartoSillasDialog> createState() => _RepartoSillasDialogState();
}

class _RepartoSillasDialogState extends State<_RepartoSillasDialog> {
  late final List<OpcionReparto> _opciones;
  OpcionReparto? _elegida;
  String? _error;

  @override
  void initState() {
    super.initState();
    _opciones = RepartoDeSillas.opcionesDe(widget.alumno);
    _elegida = RepartoDeSillas.elegidoVigente(widget.alumno, widget.guardado);
  }

  String _descripcion(OpcionReparto o, int adicionales) {
    final partes = <String>[
      if (o.principal > 0)
        '${o.principal} en la principal',
      if (o.adicionales > 0)
        adicionales == 1
            ? '${o.adicionales} en la adicional'
            : '${o.adicionales} en las adicionales',
    ];
    return partes.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alumno;
    final sillas = SalonMesas.sillasExtra(a);
    final mesas = SalonMesas.mesas(a);
    final adicionales = mesas - 1;
    final tieneNumeros = SalonMesas.tramos(a).isNotEmpty;
    final g = widget.guardado;
    final vigente = RepartoDeSillas.elegidoVigente(a, g);
    final vieja = g != null && vigente == null
        ? 'Lo que eligió antes era para ${g.sillasExtra} '
            '${g.sillasExtra == 1 ? 'silla' : 'sillas'} y ${g.mesas} '
            '${g.mesas == 1 ? 'mesa' : 'mesas'}: la cuenta cambió, hay que '
            'volver a elegir.'
        : null;

    String enMesas(OpcionReparto o) => SalonMesas.repartoSillas(
          a,
          sillasPrincipal: o.principal,
        ).map((e) => 'mesa ${e.$1}: +${e.$2}').join(' · ');

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Dónde van las sillas extra?'),
          const SizedBox(height: 4),
          Text(
            a.nombreAlumno,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$sillas ${sillas == 1 ? 'silla extra' : 'sillas extra'} · '
              '$mesas mesas: la principal y '
              '${adicionales == 1 ? '1 adicional' : '$adicionales adicionales'}'
              ' · hasta ${SalonMesas.maxSillasExtraPorMesa} por mesa',
              style: const TextStyle(fontSize: 13),
            ),
            if (vieja != null) ...[
              const SizedBox(height: 8),
              Text(
                vieja,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final o in _opciones)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Opcion(
                  titulo: o.texto,
                  detalle: tieneNumeros
                      ? enMesas(o)
                      : _descripcion(o, adicionales),
                  elegida: _elegida == o,
                  onTap: () => setState(() {
                    _elegida = o;
                    _error = null;
                  }),
                ),
              ),
            if (g != null && vigente != null && _elegida == vigente)
              Text(
                'Elegido${g.hechoPor != null ? ' por ${g.hechoPor}' : ''} el '
                '${ArTime.formatFechaHora(g.updatedAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: () {
            final e = _elegida;
            if (e == null) {
              setState(() => _error = 'Elegí una opción.');
              return;
            }
            Navigator.pop(context, e);
          },
          child: const Text('GUARDAR'),
        ),
      ],
    );
  }
}

class _Opcion extends StatelessWidget {
  final String titulo;
  final String detalle;
  final bool elegida;
  final VoidCallback onTap;

  const _Opcion({
    required this.titulo,
    required this.detalle,
    required this.elegida,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: elegida ? color.withValues(alpha: 0.10) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: elegida ? color : Colors.grey.withValues(alpha: 0.4),
          width: elegida ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                elegida ? Icons.radio_button_checked : Icons.radio_button_off,
                color: elegida ? color : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      detalle,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
