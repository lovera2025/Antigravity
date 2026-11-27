import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../cuentas/cierre_de_barra.dart';
import '../cuentas/dia_de_operacion.dart';
import '../cuentas/pedido_de_cierre.dart';
import '../cuentas/recetas_de_la_barra.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../cuentas/stock_de_la_barra.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/impresora_bluetooth.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import '../services/fiestas_del_jefe.dart';

/// La hora de esta PC, para saber cuál es la próxima fiesta y la noche que se mira en
/// CAJAS. Es la de la barra ([relojDeLaBarraProvider]); los tests la fijan.
final relojDelJefeProvider = Provider<DateTime Function()>((ref) => ref.watch(relojDeLaBarraProvider));

/// Cada cuánto CAJAS vuelve a leer la nube **en la web** (etapa 8): en la PC la rehace el
/// sync cuando bajan ventas, pero en la web nada avisa y las tablas de la barra no están
/// en Realtime (a propósito). Deslizar hacia abajo la relee ya.
const kRelecturaDeCajasEnLaWeb = Duration(seconds: 30);

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

/// Lo que se dice cuando esta PC nunca eligió impresora.
const kSinImpresoraEnEstaPc =
    'Esta PC no tiene impresora elegida: elegila con el ícono de la impresora, arriba.';

/// Antes de imprimir desde BARRA del jefe: deja la impresora lista, como VENDER al abrir,
/// y si esta PC nunca eligió una lo dice ([kSinImpresoraEnEstaPc]). Null: se puede
/// imprimir (si no contesta, lo dice el papel que no sale).
///
/// Lo encontró el recorrido con el mouse del 7-nov: la impresora solo se elegía desde
/// VENDER, y en la PC de la oficina nadie abre una caja. El jefe tocaba IMPRIMIR y le
/// salía "¿La impresora está prendida?", con la impresora prendida al lado.
Future<String?> faltaLaImpresora(WidgetRef ref) async {
  final estado = await ref.read(papelDeLaBarraProvider).preparar();
  return estado == EstadoImpresora.sinElegir ? kSinImpresoraEnEstaPc : null;
}

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

/// El precio de lista y las recetas de una fiesta (v84). **Solo para el jefe**: lo leen
/// PRECIOS del jefe y GANANCIA, nunca una pantalla de la cajera, la encargada o el
/// repositor (`test/recetas_en_la_barra_test.dart`).
class ListaDelProveedor {
  final List<CostoBarra> costos;

  /// Las activas.
  final List<RecetaBarra> recetas;

  const ListaDelProveedor({this.costos = const [], this.recetas = const []});

  CostoBarra? costoDe(String productoId) {
    for (final c in costos) {
      if (c.productoId == productoId) return c;
    }
    return null;
  }
}

final listaDelProveedorProvider = FutureProvider.family<ListaDelProveedor, String>((ref, eventoId) async {
  ref.watch(operationalSyncRevisionProvider);
  // Solo el jefe, también en la web (ahí la barra es la nube y no tiene la segunda llave).
  if (!ReglasDeLaBarra.veElCostoYLaGanancia(ref.watch(rolEnLaBarraProvider))) return const ListaDelProveedor();
  final barra = ref.read(barraDelJefeProvider);
  return ListaDelProveedor(costos: await barra.costos(eventoId), recetas: await barra.recetas(eventoId));
});

/// Un producto en el stock de CAJAS, con su nombre.
typedef StockConNombre = ({StockDeProducto stock, String nombre});

/// Lo de CAJAS de una fiesta: **todas sus cajas, separadas por noche** ([porDia],
/// 25-nov-2026), y lo que hace falta para armar cada noche ([delDia]) y ver las ventas de
/// una caja. Las cajas de prueba de otro día no se suman con las de la fiesta: cada noche
/// tiene sus totales, su diferencia, su LO VENDIDO y su stock, como un cierre de caja en
/// su fecha. Nada se borra.
class CajasDeLaFiesta {
  final String eventoId;
  final CajasPorDia porDia;
  final List<VentaBarra> ventas;
  final List<AnulacionBarra> anulaciones;
  final List<ValeBarra> vales;
  final List<PrecioBarra> precios;

  /// El nombre y la categoría de cada producto del catálogo.
  final Map<String, String> nombres;
  final Map<String, String> categorias;

  /// Las cajas que cerraron sin esperar el OK de la encargada (`barra_cierres`, v79).
  final Set<String> sinOk;

  CajasDeLaFiesta({
    required this.eventoId,
    required this.porDia,
    required this.ventas,
    required this.anulaciones,
    required this.vales,
    this.precios = const [],
    this.nombres = const {},
    this.categorias = const {},
    this.sinOk = const {},
    this.recetas = RecetasDeLaBarra.ninguna,
    this.movimientos = const [],
  });

  /// Las recetas de los tragos (v84): el Speed de cada vodka baja del stock del Speed.
  final RecetasDeLaBarra recetas;

  /// Los retiros y el cambio de la encargada (v84): entran en lo que tiene que haber.
  final List<MovimientoDeCaja> movimientos;

  final _noches = <DiaDeOperacion, NocheDeLaBarra>{};

  /// Ninguna caja en ninguna noche.
  bool get sinCajas => porDia.vacio;

  /// Las cuentas de la noche [dia]: sus cajas, los totales, LO VENDIDO y el stock.
  NocheDeLaBarra delDia(DiaDeOperacion dia) => _noches[dia] ??= _armar(dia);

  NocheDeLaBarra _armar(DiaDeOperacion dia) {
    final stock = StockDeLaBarra.deLaNoche(
      eventoId: eventoId,
      precios: precios,
      // Con lo que va entero adentro de los tragos (el Speed del vodka).
      ventas: recetas.paraElStock(ventas),
      anulaciones: anulaciones,
      cajas: porDia,
      dia: dia,
    );
    return NocheDeLaBarra(
      dia: dia,
      resumen: ResumenDeCajas.de(
        cajas: porDia.delDia(dia),
        ventas: ventas,
        anulaciones: anulaciones,
        // La categoría de cada bebida, para el papel corto y LO VENDIDO.
        categorias: categorias,
        dia: dia,
        movimientos: movimientos,
      ),
      stock: [
        for (final s in StockDeLaBarra.paraElJefe(stock))
          (stock: s, nombre: nombres[s.productoId] ?? 'Producto'),
      ],
    );
  }
}

/// Una noche de la barra en CAJAS: sus cajas con las cuentas y su stock.
class NocheDeLaBarra {
  final DiaDeOperacion dia;
  final ResumenDeCajas resumen;
  final List<StockConNombre> stock;

  const NocheDeLaBarra({required this.dia, required this.resumen, required this.stock});

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
  // Sin la tabla en la nube o en la base (una versión anterior), CAJAS se ve igual.
  var sinOk = const <String>{};
  try {
    sinOk = PedidoDeCierre.cerraronSinOk(await barra.pasosDelCierre(eventoId));
  } catch (_) {}
  final recetas = RecetasDeLaBarra.de(await barra.recetas(eventoId), eventoId: eventoId);
  // Lo mismo: sin la tabla (v84), sin retiros.
  var movimientos = const <MovimientoDeCaja>[];
  try {
    movimientos = await barra.movimientosDeCaja(eventoId);
  } catch (_) {}
  return CajasDeLaFiesta(
    eventoId: eventoId,
    porDia: CajasPorDia.de(cajas),
    ventas: ventas,
    anulaciones: anulaciones,
    vales: vales,
    precios: precios,
    nombres: {for (final p in productos) p.id: p.nombre},
    categorias: {for (final p in productos) p.id: p.categoria},
    sinOk: sinOk,
    recetas: recetas,
    movimientos: movimientos,
  );
});
