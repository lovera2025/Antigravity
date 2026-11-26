import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja_sesiones/providers/app_role_provider.dart';
import '../datos/barra_repositorio.dart';

/// **La encargada pone su PIN en la tablet de la cajera** (26-nov-2026): para anular una
/// venta o dar el OK del cierre ahí mismo (LA ENCARGADA ESTÁ ACÁ). La cajera sola no
/// anula ni se aprueba el cierre.
///
/// Devuelve el nombre de la encargada si el PIN es de una encargada de barra **y no es la
/// dueña de esa caja** (su propia caja la aprueba el jefe), o null si se canceló. Lo que
/// no da, lo dice con [decir].
Future<String?> laEncargadaAutoriza(
  BuildContext context,
  WidgetRef ref, {
  required CajaBarra caja,
  required String titulo,
  required String explicacion,
  required void Function(String) decir,
}) async {
  final pin = await _pedirElPin(context, titulo: titulo, explicacion: explicacion);
  if (pin == null || !context.mounted) return null;
  try {
    final encontrado = await ref.read(appRoleProvider.notifier).buscarOperador(pin);
    if (encontrado == null) {
      decir('Ese PIN no es de nadie.');
      return null;
    }
    if (!encontrado.permisos.encargadaBarra) {
      decir('Ese PIN no es de una encargada de barra.');
      return null;
    }
    if (encontrado.operador.id == caja.operadorId) {
      decir('Tu propia caja la aprueba el jefe.');
      return null;
    }
    return encontrado.operador.nombre;
  } catch (_) {
    decir('No se pudo comprobar el PIN. Probá de nuevo.');
    return null;
  }
}

Future<String?> _pedirElPin(BuildContext context, {required String titulo, required String explicacion}) {
  final pin = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(explicacion),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pin_de_la_encargada'),
            controller: pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN de la encargada', border: OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
        FilledButton(
          key: const Key('pin_de_la_encargada_listo'),
          onPressed: () => Navigator.pop(ctx, pin.text.trim().isEmpty ? null : pin.text.trim()),
          child: const Text('LISTO'),
        ),
      ],
    ),
  );
}
