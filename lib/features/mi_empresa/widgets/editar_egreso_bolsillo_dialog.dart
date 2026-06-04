import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/egreso.dart';
import '../../cierre_caja/models/turno_caja.dart';
import '../../common/utils/currency_extensions.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../bolsa_personal_helpers.dart';
import '../providers/finanzas_provider.dart';

enum _CategoriaEditable { retiroPersonal, gastoPersonal, gastoEmpresa }

/// Diálogo para editar/reclasificar/eliminar un movimiento del bolsillo personal.
class EditarEgresoBolsilloDialog extends ConsumerStatefulWidget {
  final Egreso egreso;
  const EditarEgresoBolsilloDialog({super.key, required this.egreso});

  @override
  ConsumerState<EditarEgresoBolsilloDialog> createState() => _EditarEgresoBolsilloDialogState();
}

class _EditarEgresoBolsilloDialogState extends ConsumerState<EditarEgresoBolsilloDialog> {
  late final TextEditingController _conceptoController;
  late _CategoriaEditable _categoria;
  bool _isSubmitting = false;

  static const _gold = Color(0xFFD4AF37);
  static const _amber = Color(0xFFFFB74D);
  static const _teal = Color(0xFF26A69A);
  static const _indigo = Color(0xFF5C6BC0);

  @override
  void initState() {
    super.initState();
    _conceptoController = TextEditingController(
      text: proveedorGastoPersonalVisible(widget.egreso.proveedor),
    );

    final cat = (widget.egreso.categoria ?? '').trim();
    if (cat == kCategoriaRetiroDueno) {
      _categoria = _CategoriaEditable.retiroPersonal;
    } else if (cat == kCategoriaGastoEmpresa) {
      _categoria = _CategoriaEditable.gastoEmpresa;
    } else {
      _categoria = _CategoriaEditable.gastoPersonal;
    }
  }

  @override
  void dispose() {
    _conceptoController.dispose();
    super.dispose();
  }

  String get _categoriaDb {
    switch (_categoria) {
      case _CategoriaEditable.retiroPersonal:
        return kCategoriaRetiroDueno;
      case _CategoriaEditable.gastoPersonal:
        return kCategoriaGastoPersonal;
      case _CategoriaEditable.gastoEmpresa:
        return kCategoriaGastoEmpresa;
    }
  }

  String _buildProveedor() {
    final concepto = _conceptoController.text.trim().isEmpty
        ? 'Movimiento'
        : _conceptoController.text.trim();
    switch (_categoria) {
      case _CategoriaEditable.retiroPersonal:
      case _CategoriaEditable.gastoEmpresa:
        return concepto;
      case _CategoriaEditable.gastoPersonal:
        return empaquetarProveedorGastoEmpresa(concepto);
    }
  }

  Future<void> _guardar() async {
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(egresosRepositoryProvider);
      await repo.actualizarEgreso(
        id: widget.egreso.id,
        categoria: _categoriaDb,
        proveedor: _buildProveedor(),
      );
      await ref.read(finanzasProvider.notifier).recargar();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Movimiento actualizado'), backgroundColor: Color(0xFF00B894)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar movimiento?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(egresosRepositoryProvider);
      await repo.eliminarEgreso(widget.egreso.id);
      await ref.read(finanzasProvider.notifier).recargar();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Movimiento eliminado'), backgroundColor: Color(0xFF00B894)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent;
    switch (_categoria) {
      case _CategoriaEditable.retiroPersonal:
        accent = _amber;
        break;
      case _CategoriaEditable.gastoPersonal:
        accent = _teal;
        break;
      case _CategoriaEditable.gastoEmpresa:
        accent = _indigo;
        break;
    }

    return AlertDialog(
      actionsAlignment: MainAxisAlignment.spaceBetween,
      title: Row(
        children: [
          Icon(Icons.edit_rounded, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Editar movimiento',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Text('Monto: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white70 : Colors.black54)),
                    Text(widget.egreso.monto.toCurrency(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: accent)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('TIPO DE MOVIMIENTO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
              const SizedBox(height: 8),
              SegmentedButton<_CategoriaEditable>(
                segments: const [
                  ButtonSegment(
                    value: _CategoriaEditable.retiroPersonal,
                    icon: Icon(Icons.person_rounded, size: 14),
                    label: Text('Personal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                  ButtonSegment(
                    value: _CategoriaEditable.gastoEmpresa,
                    icon: Icon(Icons.store_rounded, size: 14),
                    label: Text('Empresa', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                  ButtonSegment(
                    value: _CategoriaEditable.gastoPersonal,
                    icon: Icon(Icons.shopping_bag_rounded, size: 14),
                    label: Text('Gasto mío', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ],
                selected: {_categoria},
                onSelectionChanged: (v) => setState(() => _categoria = v.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  side: WidgetStatePropertyAll(BorderSide(color: accent.withValues(alpha: 0.5))),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _categoria == _CategoriaEditable.retiroPersonal
                    ? 'Plata que sacaste para vos (retiro pendiente).'
                    : _categoria == _CategoriaEditable.gastoEmpresa
                        ? 'Gasto directo del negocio.'
                        : 'Plata que gastaste personalmente.',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54, height: 1.3),
              ),
              const SizedBox(height: 16),
              Text('CONCEPTO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _conceptoController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ej. Supermercado',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _isSubmitting ? null : _eliminar,
          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
          label: const Text('ELIMINAR', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 11)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _guardar,
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
              icon: _isSubmitting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                  : const Icon(Icons.check_rounded, size: 16),
              label: Text(_isSubmitting ? 'GUARDANDO...' : 'GUARDAR', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ],
        ),
      ],
    );
  }
}
