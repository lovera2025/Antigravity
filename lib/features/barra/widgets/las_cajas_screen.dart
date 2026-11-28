import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../central/central_barra_provider.dart';
import '../central/linea_de_la_caja.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../estilos/disenio_barra.dart';
import '../jefe/cajas_de_la_fiesta.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../repositor/aviso_de_vendido_sin_stock.dart';
import '../repositor/stock_de_las_barras_screen.dart';
import 'catalogo_y_precios_screen.dart';

/// LAS CAJAS de la Encargada de barra (6.4.0): cómo va cada caja de la fiesta, con
/// cuánto cambio arrancó, cuánto generó y las sillas vendidas, y anular o reimprimir
/// cualquier venta con motivo. Es la misma vista que CAJAS del jefe
/// ([CajasDeLaFiestaVista]); la llave es `mandaEnLaBarraProvider`.
///
/// Se llega solo desde el inicio de la barra de la encargada. Sin nada más del modo
/// jefe (`test/modo_barra_cerrado_test.dart`): el catálogo y los precios de venta los
/// ve **solo mirando** (CATÁLOGO Y PRECIOS, 26-nov-2026), nunca el precio de lista ni la
/// ganancia.
class LasCajasScreen extends ConsumerWidget {
  final Evento fiesta;

  const LasCajasScreen({super.key, required this.fiesta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final veCatalogo = ReglasDeLaBarra.veCatalogoYPrecios(ref.watch(rolEnLaBarraProvider));
    // Este aparato habla con la central de la barra (la tablet de la encargada): la misma
    // línea de VENDER, con lo que espera subir, cómo está la central y **lo que la central
    // no le aceptó** (28-nov-2026: en LAS CAJAS no se veía, y lo que ella anulaba o
    // aceptaba podía no haber llegado sin que nada lo dijera).
    final conLaCentral = !ref.watch(enLaWebProvider) && ref.watch(clienteDeLaBarraProvider) != null;
    final tema = temaDeVender(DisenioBarra.nocheDorada, base: Theme.of(context));
    return Theme(
      data: tema,
      child: Builder(builder: (context) {
        final ancho = MediaQuery.sizeOf(context).width;
        final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'LAS CAJAS',
                  key: Key('las_cajas_titulo'),
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
                ),
                Text(
                  EventoPresentacion.tituloPrincipal(fiesta),
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA7A29A)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              // El stock de cada barra: la encargada lo mira, lo anota el repositor. **En un
              // celular, solo el ícono** (28-nov-2026: en el iPhone de la encargada el
              // título quedaba "LAS CAJ…").
              if (veCatalogo && CortesPantalla.esCelular(ancho))
                IconButton(
                  key: const Key('las_cajas_stock'),
                  tooltip: 'STOCK',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => StockDeLasBarrasScreen(fiesta: fiesta),
                  )),
                  icon: const Icon(Icons.inventory_2_outlined),
                )
              else if (veCatalogo)
                TextButton.icon(
                  key: const Key('las_cajas_stock'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => StockDeLasBarrasScreen(fiesta: fiesta),
                  )),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('STOCK'),
                ),
              if (veCatalogo && CortesPantalla.esCelular(ancho))
                IconButton(
                  key: const Key('las_cajas_catalogo_precios'),
                  tooltip: 'CATÁLOGO Y PRECIOS',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CatalogoYPreciosScreen(fiesta: fiesta),
                  )),
                  icon: const Icon(Icons.list_alt_outlined),
                )
              else if (veCatalogo)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    key: const Key('las_cajas_catalogo_precios'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => CatalogoYPreciosScreen(fiesta: fiesta),
                    )),
                    icon: const Icon(Icons.list_alt_outlined),
                    label: const Text('CATÁLOGO Y PRECIOS'),
                  ),
                ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (conLaCentral) const LineaDeLaCaja(),
                  // Lo que alguna caja vendió con el stock en cero (sin señal no se frena).
                  if (veCatalogo) AvisoDeVendidoSinStock(fiesta: fiesta),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(margen, 8, margen, 0),
                      child: CajasDeLaFiestaVista(key: ValueKey('cajas_${fiesta.id}'), fiesta: fiesta),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
