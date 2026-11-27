import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../cuentas/pesos.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../jefe/barra_jefe_providers.dart';
import '../providers/barra_del_jefe_provider.dart';

/// CATÁLOGO Y PRECIOS de la Encargada de barra (26-nov-2026: "que pueda ver el catálogo
/// y precio, y hasta ahí"). **Solo mirar:** lo que se vende en la fiesta con su precio de
/// venta, el recargo por transferencia y el resto del catálogo. Sin campos para
/// escribir, sin GUARDAR ni COPIAR, y **nunca el precio de lista ni la ganancia**
/// (`ReglasDeLaBarra.veElCostoYLaGanancia`: solo el jefe). Se abre desde LAS CAJAS.
class CatalogoYPreciosScreen extends ConsumerWidget {
  final Evento fiesta;

  const CatalogoYPreciosScreen({super.key, required this.fiesta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = temaDeVender(DisenioBarra.nocheDorada, base: Theme.of(context));
    return Theme(
      data: tema,
      child: Builder(builder: (context) {
        final ancho = MediaQuery.sizeOf(context).width;
        final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;
        final puede = ReglasDeLaBarra.veCatalogoYPrecios(ref.watch(rolEnLaBarraProvider));
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CATÁLOGO Y PRECIOS',
                  key: Key('catalogo_precios_titulo'),
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
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: EdgeInsets.fromLTRB(margen, 8, margen, 0),
                child: puede
                    ? _Lista(fiesta: fiesta)
                    : const Center(
                        key: Key('catalogo_precios_no_le_toca'),
                        child: Text('El catálogo y los precios los ve la encargada o el jefe.'),
                      ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Lista extends ConsumerWidget {
  final Evento fiesta;

  const _Lista({required this.fiesta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(catalogoDelJefeProvider);
    final precios = ref.watch(preciosDelJefeProvider(fiesta.id));
    if (catalogo.hasError || precios.hasError) {
      return const Center(child: Text('No se pudieron leer el catálogo y los precios.'));
    }
    final productos = catalogo.value;
    final datos = precios.value;
    if (productos == null || datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final van = <(ProductoBarra, PrecioBarra)>[];
    final resto = <ProductoBarra>[];
    for (final p in productos) {
      if (!p.activo) continue;
      final precio = datos.de(p.id);
      if (precio != null && precio.activo) {
        van.add((p, precio));
      } else {
        resto.add(p);
      }
    }
    van.sort((a, b) {
      final c = a.$1.categoria.compareTo(b.$1.categoria);
      return c != 0 ? c : a.$2.orden.compareTo(b.$2.orden);
    });
    final recargo = datos.recargo?.pct ?? 0;
    String pct(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    String? categoria;
    return ListView(
      key: const Key('catalogo_precios_lista'),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            recargo == 0
                ? 'Sin recargo por transferencia en esta fiesta.'
                : 'Recargo por transferencia: ${pct(recargo)} %, sobre lo transferido.',
            key: const Key('catalogo_precios_recargo'),
            style: const TextStyle(color: Color(0xFFC9C4BA)),
          ),
        ),
        if (van.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta fiesta todavía no tiene precios. Los pone el jefe.',
              key: Key('catalogo_precios_sin_precios'),
              textAlign: TextAlign.center,
            ),
          ),
        for (final (producto, precio) in van) ...[
          if (producto.categoria != categoria) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Text(
                (categoria = producto.categoria).toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFA7A29A),
                ),
              ),
            ),
          ],
          DecoratedBox(
            key: Key('catalogo_precios_${producto.id}'),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2830))),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(producto.nombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    pesos(precio.precio),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: TemaBarra.dorado),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (resto.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 22, 4, 6),
            child: Text(
              'EN EL CATÁLOGO, PERO NO SE VENDE EN ESTA FIESTA',
              style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Color(0xFFA7A29A)),
            ),
          ),
          for (final p in resto)
            Padding(
              key: Key('catalogo_precios_no_va_${p.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(p.nombre, style: const TextStyle(color: Color(0xFFA7A29A))),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
