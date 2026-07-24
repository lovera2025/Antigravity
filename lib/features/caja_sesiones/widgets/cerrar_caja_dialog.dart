import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/utils/currency_input_formatter.dart';
import '../providers/app_role_provider.dart';
import '../repositories/sesiones_caja_repository.dart';

Future<bool?> showCerrarCajaDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const CerrarCajaDialog(),
  );
}

class CerrarCajaDialog extends ConsumerStatefulWidget {
  const CerrarCajaDialog({super.key});

  @override
  ConsumerState<CerrarCajaDialog> createState() => _CerrarCajaDialogState();
}

class _CerrarCajaDialogState extends ConsumerState<CerrarCajaDialog> {
  final _arqueoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  double? _totalCobrado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTotal());
  }

  Future<void> _loadTotal() async {
    final sesion = ref.read(appRoleProvider).sesionActiva;
    if (sesion == null) return;
    final total = await ref
        .read(sesionesCajaRepositoryProvider)
        .totalCobradoSesion(sesion.id);
    if (mounted) setState(() => _totalCobrado = total);
  }

  @override
  void dispose() {
    _arqueoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final arqueoText = _arqueoCtrl.text.trim();
      final arqueo = arqueoText.isEmpty
          ? null
          : CurrencyInputFormatter.parse(arqueoText);
      final notifier = ref.read(appRoleProvider.notifier);
      if (ref.read(appRoleProvider).esJefe) {
        // El jefe cierra su caja pero sigue logueado en su dashboard.
        await notifier.cerrarCajaJefe(
          arqueoCierre: arqueo,
          notaCierre: _notaCtrl.text,
        );
      } else {
        await notifier.cerrarSesionCaja(
          arqueoCierre: arqueo,
          notaCierre: _notaCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(appRoleProvider);

    return AlertDialog(
      title: Text(
        role.esJefe
            ? 'Cerrar caja · Modo jefe'
            : 'Cerrar caja${role.operador != null ? ' · ${role.operador!.nombre}' : ''}',
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_totalCobrado != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Cobrado en esta sesión: \$${_totalCobrado!.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            TextField(
              controller: _arqueoCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [CurrencyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Arqueo de cierre (opcional)',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notaCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Nota de cierre',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirmar,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Cerrar caja'),
        ),
      ],
    );
  }
}
