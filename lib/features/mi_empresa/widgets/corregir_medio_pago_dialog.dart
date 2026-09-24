import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../cierre_caja/providers/cierre_caja_provider.dart';
import '../providers/finanzas_provider.dart';
import '../repositories/finanzas_repository.dart';
import 'selector_cobros.dart';

/// Diálogo admin: buscar cobros por nombre/concepto y corregir su [medio_pago]
/// (efectivo ↔ transferencia), de uno o de varios a la vez. Con un solo cobro
/// también se puede corregir la fecha.
class CorregirMedioPagoDialog extends ConsumerStatefulWidget {
  const CorregirMedioPagoDialog({super.key});

  @override
  ConsumerState<CorregirMedioPagoDialog> createState() => _CorregirMedioPagoDialogState();
}

class _CorregirMedioPagoDialogState extends ConsumerState<CorregirMedioPagoDialog> {
  bool _submitting = false;
  List<Map<String, dynamic>> _seleccion = [];
  String _nuevoMedio = 'efectivo';
  DateTime? _nuevaFecha;

  static String _medioNorm(dynamic raw) =>
      raw == null ? '' : raw.toString().toLowerCase().trim();

  void _alCambiarSeleccion(List<Map<String, dynamic>> lista) {
    setState(() {
      final antes = _seleccion.length;
      _seleccion = lista;
      // Al tildar el primero, el medio arranca en el que ya tiene: hay que
      // cambiarlo a propósito para poder aplicar.
      if (antes == 0 && lista.isNotEmpty) {
        final mp = _medioNorm(lista.first['medio_pago']);
        _nuevoMedio = (mp == 'transferencia' || mp == 'efectivo') ? mp : 'efectivo';
      }
      if (lista.length != 1) _nuevaFecha = null;
    });
  }

  /// Los tildados a los que de verdad les cambia el medio.
  List<Map<String, dynamic>> get _aCambiarMedio => [
    for (final r in _seleccion)
      if (_medioNorm(r['medio_pago']) != _nuevoMedio) r,
  ];

  bool _puedeAplicar() =>
      _seleccion.isNotEmpty &&
      !_submitting &&
      (_aCambiarMedio.isNotEmpty || _nuevaFecha != null);

  Future<void> _aplicar() async {
    if (!_puedeAplicar()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elegí un medio o fecha distinto al actual.')),
      );
      return;
    }
    setState(() => _submitting = true);

    try {
      final repo = ref.read(finanzasRepositoryProvider);
      final cambiar = _aCambiarMedio;
      if (cambiar.isNotEmpty) {
        await repo.corregirMedioPagoVarios(
          [
            for (final r in cambiar)
              (tabla: r['tabla'].toString(), id: r['id'].toString()),
          ],
          _nuevoMedio,
        );
      }
      final fecha = _nuevaFecha;
      if (fecha != null && _seleccion.length == 1) {
        final r = _seleccion.first;
        await repo.actualizarFechaPagoRegistro(
          tabla: r['tabla'].toString(),
          id: r['id'].toString(),
          nuevaFecha: fecha,
        );
      }

      await ref.read(finanzasProvider.notifier).recargar();
      if (ref.exists(cierreCajaProvider)) {
        await ref.read(cierreCajaProvider.notifier).refrescarTrasAnular();
      }

      if (!mounted) return;
      final n = _seleccion.length;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 1 ? 'Registro actualizado correctamente.' : '$n registros actualizados correctamente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  Future<void> _elegirFecha() async {
    final base = DateTime.tryParse(_seleccion.first['fecha_pago']?.toString() ?? '') ??
        ArTime.nowUtc();
    // El día se elige en calendario argentino y se conserva la hora argentina
    // del cobro. Antes se armaba con la hora UTC como si fuera local, y el cobro
    // quedaba corrido tres horas.
    final baseAr = ArTime.toAr(base);
    final inicialAr = _nuevaFecha != null ? ArTime.toAr(_nuevaFecha!) : baseAr;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(inicialAr.year, inicialAr.month, inicialAr.day),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _nuevaFecha = ArTime.arToUtc(
        DateTime(
          picked.year,
          picked.month,
          picked.day,
          baseAr.hour,
          baseAr.minute,
          baseAr.second,
          baseAr.millisecond,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = _seleccion.length;
    final grey = Colors.grey.shade700;
    final cambian = _aCambiarMedio.length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit_outlined, color: cs.primary.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Corregir medio de pago',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Buscá por nombre de cliente/alumno o por texto del concepto y '
                'tildá uno o varios. Podés cambiar el medio de pago (y la fecha, '
                'si es uno solo); no borra registros.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
              ),
              const SizedBox(height: 14),
              SelectorCobros(
                habilitado: !_submitting,
                hintBusqueda: 'Ej. MONZON, cuota…',
                onCambio: _alCambiarSeleccion,
              ),
              if (n > 0) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  n == 1 ? 'Nuevo medio:' : 'Nuevo medio (para los $n):',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: grey),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _nuevoMedio,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                  ],
                  onChanged: _submitting
                      ? null
                      : (v) {
                          if (v != null) setState(() => _nuevoMedio = v);
                        },
                ),
                if (n > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    cambian == 0
                        ? 'Todos ya están en ${etiquetaMedioCobro(_nuevoMedio)}.'
                        : cambian == n
                        ? 'Cambian los $n.'
                        : 'Cambian $cambian de $n (los demás ya están en '
                              '${etiquetaMedioCobro(_nuevoMedio)}).',
                    style: TextStyle(fontSize: 12, color: grey),
                  ),
                ],
                if (n == 1) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Nueva fecha de pago (opcional):',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: grey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _submitting ? null : _elegirFecha,
                          borderRadius: BorderRadius.circular(10),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            child: Text(
                              _nuevaFecha != null
                                  ? ArTime.formatFechaCorta(_nuevaFecha!)
                                  : 'Mantener fecha original',
                            ),
                          ),
                        ),
                      ),
                      if (_nuevaFecha != null && !_submitting) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.undo, color: Colors.redAccent),
                          tooltip: 'Restablecer fecha original',
                          onPressed: () => setState(() => _nuevaFecha = null),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _puedeAplicar() ? _aplicar : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(n <= 1 ? 'Aplicar cambio' : 'Aplicar a ${cambian == 0 ? n : cambian}'),
        ),
      ],
    );
  }
}
