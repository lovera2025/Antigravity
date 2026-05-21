import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../common/utils/currency_extensions.dart';
import '../providers/finanzas_provider.dart';
import '../repositories/finanzas_repository.dart';

/// Diálogo admin: buscar cobro por nombre/concepto y corregir solo [medio_pago] (efectivo ↔ transferencia).
class CorregirMedioPagoDialog extends ConsumerStatefulWidget {
  const CorregirMedioPagoDialog({super.key});

  @override
  ConsumerState<CorregirMedioPagoDialog> createState() => _CorregirMedioPagoDialogState();
}

class _CorregirMedioPagoDialogState extends ConsumerState<CorregirMedioPagoDialog> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _submitting = false;
  List<Map<String, dynamic>> _resultados = [];
  Map<String, dynamic>? _seleccion;
  String _nuevoMedio = 'efectivo';
  DateTime? _nuevaFecha;

  static String _etf(String tabla) {
    switch (tabla) {
      case 'pagos_contrato_alumno':
        return 'Masivo';
      case 'transacciones':
        return 'Particular';
      case 'pagos_prestamo_alquiler':
        return 'Alquiler ítems';
      default:
        return tabla;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresá al menos 2 caracteres para buscar.')),
        );
      }
      return;
    }

    setState(() {
      _searching = true;
      _seleccion = null;
      _resultados = [];
    });

    try {
      final repo = ref.read(finanzasRepositoryProvider);
      final list = await repo.buscarPagosParaCorregirMedio(q);
      if (!mounted) return;
      setState(() {
        _resultados = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al buscar: $e')),
      );
    }
  }

  Future<void> _aplicar() async {
    final sel = _seleccion;
    if (sel == null || !_puedeAplicar()) return;

    final tabla = sel['tabla']?.toString();
    final id = sel['id']?.toString();
    if (tabla == null || id == null || id.isEmpty) return;

    final nuevoMedio = _nuevoMedio.toLowerCase().trim();
    final raw = sel['medio_pago'];
    final actNorm = raw == null || raw.toString().trim().isEmpty
        ? ''
        : raw.toString().toLowerCase().trim();
    
    final bool medioCambio = actNorm != nuevoMedio;
    final bool fechaCambio = _nuevaFecha != null;

    if (!medioCambio && !fechaCambio) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Elegí un medio o fecha distinto al actual.')),
        );
      }
      return;
    }

    setState(() => _submitting = true);

    try {
      final repo = ref.read(finanzasRepositoryProvider);
      
      if (medioCambio) {
        await repo.actualizarMedioPagoRegistro(
          tabla: tabla,
          id: id,
          medioPago: nuevoMedio,
        );
      }
      
      if (fechaCambio) {
        await repo.actualizarFechaPagoRegistro(
          tabla: tabla,
          id: id,
          nuevaFecha: _nuevaFecha!,
        );
      }
      
      await ref.read(finanzasProvider.notifier).recargar();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro actualizado correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  String _lblMedio(dynamic raw) {
    final mp = raw?.toString().toLowerCase().trim();
    if (mp == null || mp.isEmpty) return '(Sin medio registrado)';
    if (mp == 'transferencia') return 'Transferencia';
    if (mp == 'efectivo') return 'Efectivo';
    return raw.toString();
  }

  bool _puedeAplicar() {
    final sel = _seleccion;
    if (sel == null || _searching || _submitting) return false;
    final nuevoMedio = _nuevoMedio.toLowerCase().trim();
    final raw = sel['medio_pago'];
    final actNorm = raw == null || raw.toString().trim().isEmpty
        ? ''
        : raw.toString().toLowerCase().trim();
    
    final bool medioCambio = actNorm != nuevoMedio;
    final bool fechaCambio = _nuevaFecha != null;
    return medioCambio || fechaCambio;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Buscá por nombre de cliente/alumno o por texto del concepto. '
                'Podrás cambiar la fecha o el medio de pago; no borra registros.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        labelText: 'Buscar',
                        hintText: 'Ej. MONZON, cuota…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _buscar(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: (_searching || _submitting) ? null : _buscar,
                    child: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Buscar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_resultados.isEmpty && !_searching && _searchCtrl.text.trim().length >= 2)
                Text('Sin coincidencias.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
              else if (_resultados.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _resultados.length,
                    itemBuilder: (ctx, i) {
                      final r = _resultados[i];
                      final fechaRaw = r['fecha_pago']?.toString();
                      final fecha = DateTime.tryParse(fechaRaw ?? '');
                      final fechaTxt = fecha != null ? ArTime.formatFechaHora(fecha) : '';
                      final selected = _seleccion?['tabla'] == r['tabla'] && _seleccion?['id'] == r['id'];
                      final titulo = r['titulo'] ?? '';
                      final monto = (r['monto'] as num?)?.toDouble() ?? 0;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          final mpLow = r['medio_pago']?.toString().toLowerCase().trim();
                          final String def = (mpLow == 'transferencia' || mpLow == 'efectivo') ? mpLow! : 'efectivo';
                          setState(() {
                            _seleccion = Map<String, dynamic>.from(r);
                            _nuevoMedio = def;
                            _nuevaFecha = null;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFD4AF37).withValues(alpha: 0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? const Color(0xFFD4AF37).withValues(alpha: 0.3) : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                size: 20,
                                color: selected ? const Color(0xFFD4AF37) : Colors.grey,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titulo.toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                    Text(
                                      '${_etf(r['tabla']?.toString() ?? '')} · ${r['subtitulo'] ?? ''}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$fechaTxt · ${_lblMedio(r['medio_pago'])} · ${monto.toCurrency()}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_seleccion != null) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Nuevo medio:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('medio_pago_${_seleccion?['tabla']}_${_seleccion?['id']}'),
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
                  onChanged: (_submitting)
                      ? null
                      : (v) {
                          if (v != null) setState(() => _nuevoMedio = v);
                        },
                ),
                const SizedBox(height: 16),
                Text(
                  'Nueva fecha de pago (opcional):',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: (_submitting) ? null : () async {
                          final DateTime baseDate = DateTime.tryParse(_seleccion?['fecha_pago']?.toString() ?? '') ?? DateTime.now();
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: _nuevaFecha ?? baseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                               _nuevaFecha = DateTime(
                                 picked.year,
                                 picked.month,
                                 picked.day,
                                 baseDate.hour,
                                 baseDate.minute,
                                 baseDate.second,
                               );
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          child: Text(
                            _nuevaFecha != null ? ArTime.formatFechaCorta(_nuevaFecha!) : 'Mantener fecha original',
                          ),
                        ),
                      ),
                    ),
                    if (_nuevaFecha != null && !_submitting) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.undo, color: Colors.redAccent),
                        tooltip: 'Restablecer fecha original',
                        onPressed: () {
                          setState(() {
                            _nuevaFecha = null;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_submitting) ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: (_puedeAplicar() && !_submitting)
              ? _aplicar
              : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Aplicar cambio'),
        ),
      ],
    );
  }
}
