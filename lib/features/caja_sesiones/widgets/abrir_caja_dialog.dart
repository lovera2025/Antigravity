import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/utils/currency_input_formatter.dart';
import '../providers/app_role_provider.dart';

Future<bool?> showAbrirCajaDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AbrirCajaDialog(),
  );
}

class AbrirCajaDialog extends ConsumerStatefulWidget {
  const AbrirCajaDialog({super.key});

  @override
  ConsumerState<AbrirCajaDialog> createState() => _AbrirCajaDialogState();
}

class _AbrirCajaDialogState extends ConsumerState<AbrirCajaDialog> {
  bool _conCambio = false;
  final _cambioCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  String? _etiqueta;
  bool _saving = false;
  String? _error;

  static const _presets = ['Mañana', 'Tarde'];

  @override
  void dispose() {
    _cambioCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_etiqueta == null) {
      setState(() => _error = 'Elegí el turno Mañana o Tarde.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cambio = _conCambio
          ? CurrencyInputFormatter.parse(_cambioCtrl.text)
          : 0.0;
      await ref
          .read(appRoleProvider.notifier)
          .abrirSesionCaja(
            cambioInicial: cambio,
            notaApertura: _notaCtrl.text,
            etiqueta: _etiqueta!,
          );
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
    final op = ref.watch(appRoleProvider).operador;
    const gold = Color(0xFFD4AF37);

    return AlertDialog(
      title: Text('Abrir caja${op != null ? ' · ${op.nombre}' : ''}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Iniciar con cambio'),
                subtitle: const Text('Si está apagado, arrancás en \$0'),
                value: _conCambio,
                activeThumbColor: gold,
                onChanged: (v) => setState(() => _conCambio = v),
              ),
              if (_conCambio) ...[
                TextField(
                  controller: _cambioCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Cambio inicial',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Turno (obligatorio)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in _presets)
                    ChoiceChip(
                      label: Text(p),
                      selected: _etiqueta == p,
                      onSelected: (sel) => setState(() {
                        _etiqueta = sel ? p : null;
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notaCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota de apertura',
                  hintText: 'Ej. cambio incompleto, sigo de ayer…',
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
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving || _etiqueta == null ? null : _confirmar,
          style: FilledButton.styleFrom(
            backgroundColor: gold,
            foregroundColor: Colors.black,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Abrir caja'),
        ),
      ],
    );
  }
}
