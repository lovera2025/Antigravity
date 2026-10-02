import 'package:flutter/material.dart';

/// Pregunta cómo se imprime el plano: en color o en blanco y negro.
///
/// Devuelve `true` si va en blanco y negro, `false` si va en color y `null` si
/// se cancela. Es una sola pregunta con sus dos respuestas como botones: no
/// hay nada más que elegir, el papel sale con el estilo de la fiesta.
Future<bool?> elegirComoImprimirPlano(
  BuildContext context, {
  required int hojas,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Imprimir el plano'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(
          '${hojas == 1 ? 'Sale una hoja A4 acostada' : 'Salen $hojas hojas A4 acostadas'}, '
          'con el número de cada mesa, el apellido de cada familia y la '
          'regla en metros.\n\n'
          'En blanco y negro las divisiones van en gris; en color, cada una '
          'con el suyo.',
        ),
      ),
      actions: [
        TextButton(
          key: const Key('imprimir_cancelar'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        OutlinedButton.icon(
          key: const Key('imprimir_bn'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.contrast, size: 18),
          label: const Text('BLANCO Y NEGRO'),
        ),
        FilledButton.icon(
          key: const Key('imprimir_color'),
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.palette_outlined, size: 18),
          label: const Text('EN COLOR'),
        ),
      ],
    ),
  );
}
