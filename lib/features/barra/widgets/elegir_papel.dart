import 'package:flutter/material.dart';

/// Qué papel de la barra sale por la impresora (11-nov-2026).
enum PapelDeLaBarraElegido {
  /// Lo vendido por categoría: mide lo mismo se venda lo que se venda.
  corto,

  /// Un renglón por bebida: en una noche de mucha venta la tira sale larga.
  conCadaBebida,
}

/// "¿Qué papel imprimo?": el corto arriba, que es el de siempre; el largo queda para
/// cuando hace falta. Null si se cierra sin elegir.
Future<PapelDeLaBarraElegido?> elegirPapelDeLaBarra(BuildContext context) =>
    showDialog<PapelDeLaBarraElegido>(
      context: context,
      builder: (ctx) {
        Widget opcion(String clave, PapelDeLaBarraElegido cual, String titulo, String detalle) =>
            SimpleDialogOption(
              key: Key(clave),
              onPressed: () => Navigator.pop(ctx, cual),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(detalle, style: const TextStyle(fontSize: 13)),
                ],
              ),
            );
        return SimpleDialog(
          title: const Text('¿Qué papel imprimo?'),
          children: [
            opcion(
              'papel_corto',
              PapelDeLaBarraElegido.corto,
              'CORTO',
              'Lo vendido por categoría. Mide lo mismo se venda lo que se venda.',
            ),
            opcion(
              'papel_con_cada_bebida',
              PapelDeLaBarraElegido.conCadaBebida,
              'CON CADA BEBIDA',
              'Un renglón por bebida: con mucha venta la tira sale larga.',
            ),
          ],
        );
      },
    );
