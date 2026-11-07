import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../cuentas/cierre_de_barra.dart';
import '../cuentas/stock_de_la_barra.dart';
import '../datos/barra_repositorio.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import '../services/fiestas_del_jefe.dart';

/// La hora de esta PC, para saber cuál es la próxima fiesta. Los tests la fijan.
final relojDelJefeProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Las fiestas de BARRA: las que vienen y las últimas. Se vuelve a leer cuando baja algo.
final fiestasDelJefeProvider = FutureProvider<FiestasDelJefe>((ref) async {
  final eventos = await ref.watch(eventosDeLaBarraProvider.future);
  return FiestasDelJefe.de(eventos, ref.read(relojDelJefeProvider)());
});

/// La fiesta que eligió el jefe con CAMBIAR DE FIESTA. Null: la próxima.
class FiestaElegidaDelJefe extends Notifier<String?> {
  @override
  String? build() => null;

  void elegir(String eventoId) => state = eventoId;
}

final fiestaElegidaDelJefeProvider =
    NotifierProvider<FiestaElegidaDelJefe, String?>(FiestaElegidaDelJefe.new);

/// Quién queda anotado en lo que hace el jefe: su nombre si entró con PIN, o "Jefe".
String quienEsElJefe(WidgetRef ref) => ref.read(appRoleProvider).operador?.nombre ?? 'Jefe';

/// El catálogo entero, también los dados de baja: los activos primero.
final catalogoDelJefeProvider = FutureProvider<List<ProductoBarra>>((ref) async {
  ref.watch(operationalSyncRevisionProvider);
  final todos = await ref.read(barraDelJefeProvider).productos(conBajas: true);
  return [
    for (final p in todos) if (p.activo) p,
    for (final p in todos) if (!p.activo) p,
  ];
});

/// Lo de PRECIOS de una fiesta: los precios (también los sacados de la lista) y el
/// recargo.
class PreciosDeLaFiesta {
  final List<PrecioBarra> precios;
  final RecargoBarra? recargo;

  const PreciosDeLaFiesta({required this.precios, this.recargo});

  PrecioBarra? de(String productoId) {
    for (final p in precios) {
      if (p.productoId == productoId) return p;
    }
    return null;
  }
}

final preciosDelJefeProvider =
    FutureProvider.family<PreciosDeLaFiesta, String>((ref, eventoId) async {
  ref.watch(operationalSyncRevisionProvider);
  final barra = ref.read(barraDelJefeProvider);
  return PreciosDeLaFiesta(
    precios: await barra.precios(eventoId, conBajas: true),
    recargo: await barra.recargo(eventoId),
  );
});

/// Un producto en el stock de CAJAS, con su nombre.
typedef StockConNombre = ({StockDeProducto stock, String nombre});

/// Lo de CAJAS de una fiesta: cada caja con sus cuentas, los totales, el stock y todo lo
/// que hace falta para ver las ventas de una caja.
class CajasDeLaFiesta {
  final ResumenDeCajas resumen;
  final List<StockConNombre> stock;
  final List<VentaBarra> ventas;
  final List<AnulacionBarra> anulaciones;
  final List<ValeBarra> vales;

  const CajasDeLaFiesta({
    required this.resumen,
    required this.stock,
    required this.ventas,
    required this.anulaciones,
    required this.vales,
  });

  bool get sinCajas => resumen.cajas.isEmpty;
}

final cajasDelJefeProvider =
    FutureProvider.family<CajasDeLaFiesta, String>((ref, eventoId) async {
  ref.watch(operationalSyncRevisionProvider);
  final barra = ref.read(barraDelJefeProvider);
  final cajas = await barra.cajas(eventoId);
  final ventas = await barra.ventas(eventoId);
  final anulaciones = await barra.anulaciones(eventoId);
  final vales = await barra.vales(eventoId);
  final precios = await barra.precios(eventoId);
  final productos = await barra.productos(conBajas: true);
  final nombres = {for (final p in productos) p.id: p.nombre};
  final stock = StockDeLaBarra.de(
    eventoId: eventoId,
    precios: precios,
    ventas: ventas,
    anulaciones: anulaciones,
  );
  return CajasDeLaFiesta(
    resumen: ResumenDeCajas.de(cajas: cajas, ventas: ventas, anulaciones: anulaciones),
    stock: [
      for (final s in StockDeLaBarra.paraElJefe(stock))
        (stock: s, nombre: nombres[s.productoId] ?? 'Producto'),
    ],
    ventas: ventas,
    anulaciones: anulaciones,
    vales: vales,
  );
});
