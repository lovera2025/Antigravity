import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import 'stock_de_la_fiesta.dart';
import 'stock_de_las_barras_screen.dart';
import 'texto_del_stock.dart';

/// A la encargada y al jefe, arriba de las cajas: **lo que se vendió con el stock en
/// cero** ("Se vendió sin stock: 5 speed en la Barra 1"). Pasa cuando una caja vende sin
/// señal (ahí no se frena: no sabe si repusieron); se descuenta solo de lo que se reponga.
///
/// Sin nada vendido de más no ocupa lugar. Tocarlo abre STOCK. Sin plata.
class AvisoDeVendidoSinStock extends ConsumerWidget {
  final Evento fiesta;

  const AvisoDeVendidoSinStock({super.key, required this.fiesta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(stockDeLaFiestaProvider(fiesta.id)).value;
    final texto = datos == null ? null : vendidoSinStock(datos.vendidoDeMas, datos.nombreDe);
    if (texto == null) return const SizedBox.shrink();
    final tema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        color: tema.errorContainer,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const Key('vendido_sin_stock'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => StockDeLasBarrasScreen(fiesta: fiesta),
          )),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: tema.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    texto,
                    key: const Key('vendido_sin_stock_texto'),
                    style: TextStyle(color: tema.onErrorContainer, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text('VER STOCK', style: TextStyle(color: tema.onErrorContainer, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
