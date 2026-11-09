import 'package:flutter/material.dart';

import '../../../models/evento.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../estilos/disenio_barra.dart';
import '../jefe/cajas_de_la_fiesta.dart';

/// LAS CAJAS de la Encargada de barra (6.4.0): cómo va cada caja de la fiesta, con
/// cuánto cambio arrancó, cuánto generó y las sillas vendidas, y anular o reimprimir
/// cualquier venta con motivo. Es la misma vista que CAJAS del jefe
/// ([CajasDeLaFiestaVista]); la llave es `mandaEnLaBarraProvider`.
///
/// Se llega solo desde el inicio de la barra de la encargada. Sin catálogo, sin
/// precios y sin nada más del modo jefe (`test/modo_barra_cerrado_test.dart`).
class LasCajasScreen extends StatelessWidget {
  final Evento fiesta;

  const LasCajasScreen({super.key, required this.fiesta});

  @override
  Widget build(BuildContext context) {
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
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Padding(
                padding: EdgeInsets.fromLTRB(margen, 8, margen, 0),
                child: CajasDeLaFiestaVista(key: ValueKey('cajas_${fiesta.id}'), fiesta: fiesta),
              ),
            ),
          ),
        );
      }),
    );
  }
}
