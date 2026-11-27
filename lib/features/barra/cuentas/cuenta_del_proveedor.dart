import 'dart:math' as math;

import '../datos/barra_repositorio.dart';
import '../datos/movimiento_de_stock.dart';
import '../datos/stock_en_la_barra.dart';
import 'cierre_de_barra.dart';
import 'dia_de_operacion.dart';
import 'pesos.dart';
import 'stock_por_barra.dart';

/// Lo que hace falta de una fiesta para la pestaña GANANCIA del jefe (audio 77 del jefe,
/// 26-nov-2026). Todo de esa fiesta; [listas] es el precio de lista de cada producto
/// (`barra_costos`): sin clave o null, falta cargarlo; en 0, no se le paga a nadie.
class FiestaParaLaGanancia {
  final String eventoId;
  final String nombre;
  final DateTime fecha;
  final List<CajaBarra> cajas;
  final List<VentaBarra> ventas;
  final List<AnulacionBarra> anulaciones;
  final List<PrecioBarra> precios;
  final List<StockEnLaBarra> repartos;
  final List<MovimientoDeStock> movimientos;
  final Map<String, double?> listas;

  const FiestaParaLaGanancia({
    required this.eventoId,
    required this.nombre,
    required this.fecha,
    this.cajas = const [],
    this.ventas = const [],
    this.anulaciones = const [],
    this.precios = const [],
    this.repartos = const [],
    this.movimientos = const [],
    this.listas = const {},
  });
}

/// Un producto en una fiesta, o juntando las fiestas del período. **Todo en centavos.**
class GananciaDeUnProducto {
  final String productoId;
  final String nombre;

  /// Las vendidas, sin las anuladas.
  final int vendidas;

  /// Las que se rompieron, congelaron o perdieron: los faltantes y lo que dio de menos un
  /// conteo, netos. **Se le pagan igual al proveedor** (decisión del usuario, 26-nov).
  final int perdidas;

  /// Lo que se vendió a precio de venta, sin el recargo por transferencia.
  final int seVendio;

  /// El precio de lista. Null: falta en alguna fiesta donde se movió; [listaVaria]: no
  /// es el mismo en todas.
  final int? lista;
  final bool listaVaria;

  /// (vendidas + perdidas) × precio de lista, de lo que tiene lista.
  final int leDebo;

  /// Si a alguna fiesta donde se movió le falta el precio de lista: [leDebo] no está
  /// completo y la ganancia no se sabe.
  final bool faltaLaLista;

  /// Lo que quedó (en el depósito y las barras). Null: no se controla el stock.
  final int? quedaron;

  const GananciaDeUnProducto({
    required this.productoId,
    required this.nombre,
    this.vendidas = 0,
    this.perdidas = 0,
    this.seVendio = 0,
    this.lista,
    this.listaVaria = false,
    this.leDebo = 0,
    this.faltaLaLista = false,
    this.quedaron,
  });

  /// [seVendio] − [leDebo]; null si falta el precio de lista.
  int? get ganancia => faltaLaLista ? null : seVendio - leDebo;

  bool get seMovio => vendidas > 0 || perdidas > 0;
}

/// Una fiesta del período.
class GananciaDeUnaFiesta {
  final String eventoId;
  final String nombre;

  /// La noche que se cuenta: la de la fecha de la fiesta, o, si esa noche no tuvo cajas,
  /// la que más vendió.
  final DiaDeOperacion noche;

  /// Las noches con cajas que no se cuentan (cajas de prueba de otro día) y cuántas cajas.
  final Map<DiaDeOperacion, int> otrasNoches;

  final List<GananciaDeUnProducto> productos;

  /// El recargo por transferencia cobrado: no entra en la ganancia.
  final int recargo;

  const GananciaDeUnaFiesta({
    required this.eventoId,
    required this.nombre,
    required this.noche,
    this.otrasNoches = const {},
    this.productos = const [],
    this.recargo = 0,
  });
}

/// **La única cuenta de la pestaña GANANCIA**: lo que se vendió, lo que se le debe al
/// proveedor y lo que se ganó, de una o varias fiestas. Pura, sin base ni pantalla. Solo
/// la ve el jefe (`ReglasDeLaBarra.veElCostoYLaGanancia`).
class CuentaDelProveedor {
  final List<GananciaDeUnaFiesta> fiestas;

  /// Por producto, juntando las fiestas; en el orden del nombre.
  final List<GananciaDeUnProducto> productos;

  const CuentaDelProveedor._(this.fiestas, this.productos);

  int get seVendio => productos.fold(0, (s, p) => s + p.seVendio);
  int get leDebo => productos.fold(0, (s, p) => s + p.leDebo);

  /// La ganancia de lo que tiene precio de lista (lo demás va en [faltaLaLista]).
  int get ganancia => productos.fold(0, (s, p) => s + (p.ganancia ?? 0));
  int get vendidas => productos.fold(0, (s, p) => s + p.vendidas);
  int get perdidas => productos.fold(0, (s, p) => s + p.perdidas);
  int get recargo => fiestas.fold(0, (s, f) => s + f.recargo);

  /// Los productos que se movieron sin precio de lista en alguna fiesta.
  List<GananciaDeUnProducto> get faltaLaLista => [for (final p in productos) if (p.faltaLaLista) p];

  factory CuentaDelProveedor.de(Iterable<FiestaParaLaGanancia> fiestas, {Map<String, String> nombres = const {}}) {
    final ordenadas = fiestas.toList()..sort((a, b) => a.fecha.compareTo(b.fecha));
    final porFiesta = [for (final f in ordenadas) _deUnaFiesta(f, nombres)];
    final juntos = <String, List<GananciaDeUnProducto>>{};
    for (final f in porFiesta) {
      for (final p in f.productos) {
        (juntos[p.productoId] ??= []).add(p);
      }
    }
    final productos = <GananciaDeUnProducto>[];
    for (final e in juntos.entries) {
      final partes = e.value;
      final movidas = [for (final p in partes) if (p.seMovio) p];
      final listas = {for (final p in movidas) if (!p.faltaLaLista) p.lista};
      productos.add(GananciaDeUnProducto(
        productoId: e.key,
        nombre: partes.last.nombre,
        vendidas: partes.fold(0, (s, p) => s + p.vendidas),
        perdidas: partes.fold(0, (s, p) => s + p.perdidas),
        seVendio: partes.fold(0, (s, p) => s + p.seVendio),
        leDebo: partes.fold(0, (s, p) => s + p.leDebo),
        faltaLaLista: movidas.any((p) => p.faltaLaLista),
        lista: listas.length == 1 ? listas.single : (movidas.isEmpty ? partes.last.lista : null),
        listaVaria: listas.length > 1,
        // Lo que quedó al final: el de la última fiesta del período.
        quedaron: partes.last.quedaron,
      ));
    }
    productos.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return CuentaDelProveedor._(porFiesta, productos);
  }

  static DiaDeOperacion _laNoche(FiestaParaLaGanancia f, CajasPorDia porDia) {
    final suya = DiaDeOperacion.delCalendario(f.fecha);
    if (porDia.tiene(suya) || porDia.vacio) return suya;
    var mejor = porDia.dias.first;
    var mas = -1;
    for (final d in porDia.dias) {
      final n = porDia.ventasDelDia(f.ventas, d).length;
      if (n > mas) {
        mas = n;
        mejor = d;
      }
    }
    return mejor;
  }

  static GananciaDeUnaFiesta _deUnaFiesta(FiestaParaLaGanancia f, Map<String, String> nombres) {
    final porDia = CajasPorDia.de([for (final c in f.cajas) if (c.eventoId == f.eventoId) c]);
    final noche = _laNoche(f, porDia);
    final ventas = [for (final v in porDia.ventasDelDia(f.ventas, noche)) if (v.eventoId == f.eventoId) v];
    final cierre = CierreDeBarra.deLaFiesta(ventas, f.anulaciones);
    final stock = StockPorBarra.deLaNoche(
      eventoId: f.eventoId,
      precios: f.precios,
      repartos: f.repartos,
      movimientos: f.movimientos,
      ventas: f.ventas,
      anulaciones: f.anulaciones,
      cajas: porDia,
      dia: noche,
    );
    final vendido = {for (final p in cierre.porProducto) p.productoId: p};
    final ids = <String>{
      ...vendido.keys,
      for (final p in f.precios) if (p.eventoId == f.eventoId && p.activo) p.productoId,
    };
    final generalDe = <String, int?>{
      for (final p in f.precios)
        if (p.eventoId == f.eventoId && p.activo) p.productoId: p.stockInicial,
    };
    final productos = <GananciaDeUnProducto>[];
    for (final id in ids) {
      final v = vendido[id];
      final lugares = [
        stock.en(kDeposito, id),
        for (final b in stock.nombresDeBarras) stock.en(b, id),
      ].whereType<StockDeUnLugar>().toList();
      // Faltantes y lo que dio de menos un conteo, netos: un conteo que encontró de más
      // no baja lo que se le debe por lo vendido.
      final netas = lugares.fold<int>(0, (s, l) => s + l.falto - l.porConteos);
      final perdidas = math.max(0, netas);
      final vendidas = v?.unidades ?? 0;
      // Lo vendido en una caja de una barra donde ese producto no se controla no lo
      // descuenta ningún lugar: se descuenta acá, para que "quedaron" no diga de más.
      final sinDescontar = math.max(0, vendidas - lugares.fold<int>(0, (s, l) => s + l.vendido));
      // Sin reparto a las barras, el stock por barra no lo controla: queda la cuenta de
      // siempre, lo que cargó el jefe menos lo vendido (como el "Quedan" de CAJAS).
      final general = generalDe[id];
      final quedaron = lugares.isNotEmpty
          ? math.max(0, lugares.fold<int>(0, (s, l) => s + math.max(0, l.queda)) - sinDescontar)
          : (general == null ? null : math.max(0, general - vendidas));
      final listaPesos = f.listas[id];
      final lista = listaPesos == null ? null : centavos(listaPesos);
      final falta = lista == null && (vendidas > 0 || perdidas > 0);
      productos.add(GananciaDeUnProducto(
        productoId: id,
        nombre: v?.nombre ?? nombres[id] ?? 'Producto',
        vendidas: vendidas,
        perdidas: perdidas,
        seVendio: centavos(v?.plata ?? 0),
        lista: lista,
        leDebo: lista == null ? 0 : (vendidas + perdidas) * lista,
        faltaLaLista: falta,
        quedaron: quedaron,
      ));
    }
    final otras = <DiaDeOperacion, int>{
      for (final d in porDia.dias)
        if (d != noche) d: porDia.delDia(d).length,
    };
    return GananciaDeUnaFiesta(
      eventoId: f.eventoId,
      nombre: f.nombre,
      noche: noche,
      otrasNoches: otras,
      productos: productos,
      recargo: centavos(cierre.recargos),
    );
  }
}
