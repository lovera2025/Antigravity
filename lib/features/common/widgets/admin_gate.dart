import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';

class AdminGate {
  /// Si [forceVerification] es true, se muestra el PIN aunque ya haya sesión admin (p. ej. reingreso a Mi Empresa).
  static Future<bool> check(
    BuildContext context,
    WidgetRef ref, {
    bool forceVerification = false,
  }) async {
    final adminState = ref.read(adminAuthProvider);

    if (adminState.isAdmin && !forceVerification) {
      return true;
    }

    final pinController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        Future<void> submitPin() async {
          final success = await ref
              .read(adminAuthProvider.notifier)
              .verifyAndLogin(pinController.text);
          if (context.mounted) Navigator.pop(context, success);
        }

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock_outline, color: Color(0xFFD4AF37)),
              const SizedBox(width: 12),
              const Text(
                'Acceso Restringido',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Esta acción requiere permisos de administrador.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: pinController,
                decoration: InputDecoration(
                  labelText: 'PIN MAESTRO',
                  hintText: '****',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(
                    Icons.key_rounded,
                    color: Color(0xFFD4AF37),
                  ),
                ),
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofocus: true,
                onSubmitted: (_) => submitPin(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async => submitPin(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('DESBLOQUEAR'),
            ),
          ],
        );
      },
    );

    if (result == false && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN incorrecto o acción cancelada'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    return result ?? false;
  }
}
