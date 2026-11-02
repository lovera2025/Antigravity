import 'package:flutter/material.dart';

/// Cómo se imprime el plano.
typedef ComoImprimirPlano = ({bool blancoYNegro, bool familias});

/// Pregunta cómo se imprime el plano: en color o en blanco y negro, y si van
/// marcadas las familias con adicional. Null si se cancela. La casilla sale solo
/// si hay alguna ([hayFamilias]) y viene prendida. Lo demás no se elige: el papel
/// sale con el estilo de la fiesta.
Future<ComoImprimirPlano?> elegirComoImprimirPlano(
  BuildContext context, {
  required int hojas,
  bool hayFamilias = false,
}) {
  var familias = hayFamilias;
  return showDialog<ComoImprimirPlano>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, cambiar) => AlertDialog(
        title: const Text('Imprimir el plano'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${hojas == 1 ? 'Sale una hoja A4 acostada' : 'Salen $hojas hojas A4 acostadas'}, '
                'con el número de cada mesa, el apellido de cada familia y la '
                'regla en metros.\n\n'
                'En blanco y negro las divisiones van en gris; en color, cada una '
                'con el suyo.',
              ),
              if (hayFamilias)
                CheckboxListTile(
                  key: const Key('imprimir_familias'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: familias,
                  onChanged: (v) => cambiar(() => familias = v ?? true),
                  title: const Text('Familias con adicional'),
                ),
            ],
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
            onPressed: () => Navigator.of(context).pop((
              blancoYNegro: true,
              familias: familias,
            )),
            icon: const Icon(Icons.contrast, size: 18),
            label: const Text('BLANCO Y NEGRO'),
          ),
          FilledButton.icon(
            key: const Key('imprimir_color'),
            onPressed: () => Navigator.of(context).pop((
              blancoYNegro: false,
              familias: familias,
            )),
            icon: const Icon(Icons.palette_outlined, size: 18),
            label: const Text('EN COLOR'),
          ),
        ],
      ),
    ),
  );
}
