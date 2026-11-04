import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../services/imagen_de_producto.dart';
import '../services/productos_para_vender.dart';
import 'tarjeta_producto.dart';

/// "Cómo se ve": los dos diseños, cada uno con una tarjeta pintada con su tema de
/// verdad (no puede mentir). Tocar uno lo guarda en este equipo y VENDER se repinta.
/// [muestra] es un producto de la fiesta; sin ninguno, un fernet de ejemplo.
Future<void> elegirDisenio(BuildContext context, WidgetRef ref, {ProductoEnVenta? muestra}) async {
  final actual = ref.read(disenioDeLaBarraProvider);
  final producto = muestra ?? _ejemplo();
  final imagen = ref.read(imagenDelProductoProvider)(producto.producto);
  final elegido = await showDialog<DisenioBarra>(
    context: context,
    builder: (_) => _ElegirDisenio(actual: actual, muestra: producto, imagen: imagen),
  );
  if (elegido != null && elegido != actual) {
    await ref.read(disenioDeLaBarraProvider.notifier).elegir(elegido);
  }
}

ProductoEnVenta _ejemplo() {
  final ahora = DateTime.utc(2026, 11, 4);
  final p = ProductoBarra.nuevo(nombre: 'Fernet con coca', categoria: 'Tragos', ahora: ahora);
  return ProductoEnVenta(
    p,
    PrecioBarra.para(eventoId: 'muestra', productoId: p.id, precio: 6000, ahora: ahora),
  );
}

class _ElegirDisenio extends StatelessWidget {
  final DisenioBarra actual;
  final ProductoEnVenta muestra;
  final ImageProvider? imagen;

  const _ElegirDisenio({required this.actual, required this.muestra, required this.imagen});

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('elegir_disenio'),
        title: const Text('Cómo se ve'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            alignment: WrapAlignment.center,
            children: [for (final d in DisenioBarra.values) _opcion(context, d)],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR')),
        ],
      );

  Widget _opcion(BuildContext context, DisenioBarra d) {
    const ancho = 150.0;
    final elegido = d == actual;
    final tema = TemaBarra.de(d);
    return InkWell(
      key: Key('disenio_${d.clave}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(context, d),
      child: Container(
        width: ancho + 24,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: tema.fondo,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: elegido ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // La tarjeta de verdad, quieta: el toque es de toda la opción.
            IgnorePointer(
              child: ExcludeSemantics(
                child: Theme(
                  data: temaDeVender(d, base: Theme.of(context)),
                  child: SizedBox(
                    width: ancho,
                    height: TarjetaProducto.alto(d, ancho),
                    child: TarjetaProducto(
                      producto: muestra,
                      cantidad: 1,
                      quedan: null,
                      enAviso: false,
                      imagen: imagen,
                      alSumar: () {},
                      alRestar: () {},
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              d.nombre,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            if (elegido)
              const Text(
                'El de este equipo',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
