import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_role_provider.dart';
import 'abrir_caja_dialog.dart';

/// Pantalla post-login Supabase: elegir Jefe o Caja e ingresar PIN.
class RoleGateScreen extends ConsumerStatefulWidget {
  const RoleGateScreen({super.key});

  @override
  ConsumerState<RoleGateScreen> createState() => _RoleGateScreenState();
}

class _RoleGateScreenState extends ConsumerState<RoleGateScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _entrarJefe() async {
    final pin = await _pedirPin(
      titulo: 'Modo jefe',
      subtitulo: 'Ingresá el PIN maestro',
    );
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Esperar a que el route del diálogo termine de desmontarse.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final ok = await ref.read(appRoleProvider.notifier).loginJefe(pin);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'PIN de jefe incorrecto';
      });
    }
    // Si ok, el router reemplaza esta pantalla; no setState.
  }

  Future<void> _entrarCaja() async {
    final pin = await _pedirPin(
      titulo: 'Modo caja',
      subtitulo: 'Ingresá el PIN de tu usuario de caja',
    );
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final err = await ref.read(appRoleProvider.notifier).loginCaja(pin);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    final role = ref.read(appRoleProvider);
    if (!role.tieneSesionCaja) {
      final opened = await showAbrirCajaDialog(context);
      if (opened != true && mounted) {
        await ref.read(appRoleProvider.notifier).logoutApp();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<String?> _pedirPin({
    required String titulo,
    required String subtitulo,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PinDialog(titulo: titulo, subtitulo: subtitulo),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storefront_rounded, size: 48, color: gold),
                const SizedBox(height: 16),
                Text(
                  'Junior Eventos',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Elegí cómo entrar',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: gold),
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _entrarJefe,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      style: FilledButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      label: const Text(
                        'MODO JEFE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _entrarCaja,
                      icon: const Icon(Icons.point_of_sale_outlined),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: gold,
                        side: const BorderSide(color: gold),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      label: const Text(
                        'MODO CAJA',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog que posee el controller y lo dispone en su propio [dispose].
class _PinDialog extends StatefulWidget {
  final String titulo;
  final String subtitulo;

  const _PinDialog({required this.titulo, required this.subtitulo});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitulo, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Entrar'),
        ),
      ],
    );
  }
}
