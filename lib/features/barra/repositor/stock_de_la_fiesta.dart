import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/widgets/operational_sync_coordinator.dart';
import '../cuentas/dia_de_operacion.dart';
import '../cuentas/recetas_de_la_barra.dart';
import '../cuentas/stock_por_barra.dart';
import '../datos/barra_repositorio.dart';
import '../providers/barra_del_jefe_provider.dart';

/// El stock por barra de una fiesta **esta noche**, con lo que hace falta para mostrarlo:
/// la cuenta ([StockPorBarra], la única), los nombres de los productos y los movimientos.
///
/// Lo usan STOCK del repositor, el reparto del jefe y el stock de LAS CAJAS: **ninguna
/// pantalla hace otra cuenta al lado**; lo que se puede reponer, pasar o descontar lo
/// dice [stock].
class StockDeLaFiesta {
  final String eventoId;

  /// La noche que se mira: las cajas y las ventas de esa noche descuentan.
  final DiaDeOperacion dia;
  final StockPorBarra stock;

  /// El nombre de cada producto del catálogo.
  final Map<String, String> nombres;
  final List<PrecioBarra> precios;

  /// El reparto del jefe, también lo sacado.
  final List<StockEnLaBarra> repartos;

  /// Lo que anotó el repositor, **del más nuevo al más viejo**.
  final List<MovimientoDeStock> movimientos;

  /// Cuándo se leyó: "al día hasta las 23:40".
  final DateTime leidoEl;

  const StockDeLaFiesta({
    required this.eventoId,
    required this.dia,
    required this.stock,
    required this.nombres,
    required this.precios,
    required this.repartos,
    required this.movimientos,
    required this.leidoEl,
  });

  String nombreDe(String productoId) => nombres[productoId] ?? 'Producto';

  /// Las barras con reparto, por nombre.
  List<String> get barras => stock.nombresDeBarras;

  /// Los productos que el jefe repartió (los que se controlan en alguna barra), por
  /// nombre.
  List<String> get productos {
    final ids = <String>{
      for (final r in repartos)
        if (r.eventoId == eventoId && r.activo && stock.en(kDeposito, r.productoId) != null) r.productoId,
    }.toList()
      ..sort((a, b) => nombreDe(a).toLowerCase().compareTo(nombreDe(b).toLowerCase()));
    return ids;
  }

  /// Lo que hay de cada producto en [lugar] (una barra o el depósito), por nombre.
  List<StockDeUnLugar> en(String lugar) => [
        for (final p in productos)
          if (stock.en(lugar, p) case final s?) s,
      ];

  /// El stock general que cargó el jefe en PRECIOS para [productoId], o null.
  int? generalDe(String productoId) {
    for (final p in precios) {
      if (p.productoId == productoId) return p.stockInicial;
    }
    return null;
  }

  /// Lo que se vendió de más en las barras con el stock en cero (sin señal no se frena):
  /// se descuenta solo de lo que se reponga. Por lugar y producto.
  List<StockDeUnLugar> get vendidoDeMas => [
        for (final b in barras)
          for (final s in en(b))
            if (s.queda < 0) s,
      ];
}

/// El stock de [eventoId] para la noche de hoy. Se vuelve a leer cuando baja algo de la
/// nube o llega algo por la red del salón (`operationalSyncRevisionProvider`), y cuando
/// este equipo anota algo (quien guarda lo invalida).
final stockDeLaFiestaProvider = FutureProvider.family<StockDeLaFiesta, String>((ref, eventoId) async {
  ref.watch(operationalSyncRevisionProvider);
  final barra = ref.read(barraDelJefeProvider);
  final ahora = ref.read(relojDeLaBarraProvider)();
  final dia = DiaDeOperacion.de(ahora);
  final precios = await barra.precios(eventoId, conBajas: true);
  final repartos = await barra.repartos(eventoId);
  final movimientos = await barra.movimientosDeStock(eventoId);
  final ventas = await barra.ventas(eventoId);
  final anulaciones = await barra.anulaciones(eventoId);
  final cajas = CajasPorDia.de(await barra.cajas(eventoId));
  final recetas = RecetasDeLaBarra.de(await barra.recetas(eventoId), eventoId: eventoId);
  final productos = await barra.productos(conBajas: true);
  return StockDeLaFiesta(
    eventoId: eventoId,
    dia: dia,
    stock: StockPorBarra.deLaNoche(
      eventoId: eventoId,
      precios: precios,
      repartos: repartos,
      movimientos: movimientos,
      // Con lo que va entero adentro de los tragos (el Speed del vodka).
      ventas: recetas.paraElStock(ventas),
      anulaciones: anulaciones,
      cajas: cajas,
      dia: dia,
    ),
    nombres: {for (final p in productos) p.id: p.nombre},
    precios: precios,
    repartos: repartos,
    movimientos: movimientos.reversed.toList(),
    leidoEl: ahora,
  );
});
