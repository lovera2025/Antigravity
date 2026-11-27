import 'dart:math' as math;

import '../datos/barra_repositorio.dart';
import '../datos/movimiento_de_stock.dart';
import '../datos/receta_barra.dart';
import '../datos/stock_en_la_barra.dart';
import 'cierre_de_barra.dart';
import 'dia_de_operacion.dart';
import 'pesos.dart';
import 'recetas_de_la_barra.dart';
import 'stock_por_barra.dart';

/// Lo que hace falta de una fiesta para la pestaña GANANCIA del jefe (audio 77 del jefe,
/// 26-nov-2026). Todo de esa fiesta; [listas] es el precio de lista de cada producto
/// (`barra_costos`): sin clave o null, falta cargarlo; en 0, no se le paga a nadie.
/// [recetas] son las de los tragos (`barra_recetas`), y [contenidos], cuántos cc trae la
/// botella de cada ingrediente que se sirve por cc (también de `barra_costos`).
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
  final List<RecetaBarra> recetas;
  final Map<String, int?> contenidos;

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
    this.recetas = const [],
    this.contenidos = const {},
  });
}

/// **"Para el proveedor"**: lo mismo que "Le debo", contado por lo que se le compra (una
/// lata, una botella). Las botellas de los tragos son un cálculo con la receta ("más o
/// menos", el jefe): [cc] ÷ [contenidoCc]. Todo en centavos.
class UsoDelProveedor {
  final String productoId;
  final String nombre;

  /// Vendidas sueltas, sin las anuladas.
  final int sueltas;

  /// Las perdidas (faltantes y conteos de menos, netos).
  final int perdidas;

  /// Las que se fueron enteras adentro de un trago (el Speed del vodka).
  final int enTragos;

  /// Los cc que se sirvieron en tragos, y cuántos cc trae la botella.
  final int cc;
  final int? contenidoCc;

  /// El precio de lista por unidad (lata o botella). Null si varía entre fiestas o falta.
  final int? lista;
  final int leDebo;
  final bool faltaLaLista;

  const UsoDelProveedor({
    required this.productoId,
    required this.nombre,
    this.sueltas = 0,
    this.perdidas = 0,
    this.enTragos = 0,
    this.cc = 0,
    this.contenidoCc,
    this.lista,
    this.leDebo = 0,
    this.faltaLaLista = false,
  });

  /// Unidades enteras: sueltas + perdidas + adentro de los tragos.
  int get unidades => sueltas + perdidas + enTragos;

  /// Lo que se usó, en latas o botellas (con las de los tragos por cc, calculadas).
  double get usadas => unidades + (cc > 0 && (contenidoCc ?? 0) > 0 ? cc / contenidoCc! : 0);

  bool get seUso => unidades > 0 || cc > 0;
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

  /// (vendidas + perdidas) × precio de lista, de lo que tiene lista. En un trago con
  /// receta, lo que cuesta lo que lleva, por cada vendido.
  final int leDebo;

  /// Si es un trago con receta: [lista] es lo que cuesta un trago, calculado.
  final bool porReceta;

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
    this.porReceta = false,
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

  /// Lo mismo que [productos], contado por lo que se le compra al proveedor.
  final List<UsoDelProveedor> paraElProveedor;

  const GananciaDeUnaFiesta({
    required this.eventoId,
    required this.nombre,
    required this.noche,
    this.otrasNoches = const {},
    this.productos = const [],
    this.recargo = 0,
    this.paraElProveedor = const [],
  });
}

/// **La única cuenta de la pestaña GANANCIA**: lo que se vendió, lo que se le debe al
/// proveedor y lo que se ganó, de una o varias fiestas. Pura, sin base ni pantalla. Solo
/// la ve el jefe (`ReglasDeLaBarra.veElCostoYLaGanancia`).
class CuentaDelProveedor {
  final List<GananciaDeUnaFiesta> fiestas;

  /// Por producto, juntando las fiestas; en el orden del nombre.
  final List<GananciaDeUnProducto> productos;

  /// "Para el proveedor", juntando las fiestas; en el orden del nombre. Su total es el
  /// mismo que el de [leDebo].
  final List<UsoDelProveedor> paraElProveedor;

  const CuentaDelProveedor._(this.fiestas, this.productos, this.paraElProveedor);

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
        porReceta: partes.any((p) => p.porReceta),
      ));
    }
    productos.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    final usos = <String, List<UsoDelProveedor>>{};
    for (final f in porFiesta) {
      for (final u in f.paraElProveedor) {
        (usos[u.productoId] ??= []).add(u);
      }
    }
    final proveedor = <UsoDelProveedor>[];
    for (final e in usos.entries) {
      final partes = e.value;
      final listas = {for (final u in partes) if (u.seUso && !u.faltaLaLista) u.lista};
      final contenidos = {for (final u in partes) if (u.cc > 0) u.contenidoCc};
      proveedor.add(UsoDelProveedor(
        productoId: e.key,
        nombre: partes.last.nombre,
        sueltas: partes.fold(0, (s, u) => s + u.sueltas),
        perdidas: partes.fold(0, (s, u) => s + u.perdidas),
        enTragos: partes.fold(0, (s, u) => s + u.enTragos),
        cc: partes.fold(0, (s, u) => s + u.cc),
        contenidoCc: contenidos.length == 1 ? contenidos.single : null,
        lista: listas.length == 1 ? listas.single : null,
        leDebo: partes.fold(0, (s, u) => s + u.leDebo),
        faltaLaLista: partes.any((u) => u.faltaLaLista),
      ));
    }
    proveedor.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return CuentaDelProveedor._(porFiesta, productos, proveedor);
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
    final recetas = RecetasDeLaBarra.de(f.recetas, eventoId: f.eventoId);
    final stock = StockPorBarra.deLaNoche(
      eventoId: f.eventoId,
      precios: f.precios,
      repartos: f.repartos,
      movimientos: f.movimientos,
      // Con lo que va entero adentro de los tragos (el Speed del vodka).
      ventas: recetas.paraElStock(f.ventas),
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
    int? listaDe(String id) {
      final l = f.listas[id];
      return l == null ? null : centavos(l);
    }

    String nombreDe(String id) => vendido[id]?.nombre ?? nombres[id] ?? 'Producto';
    // "Para el proveedor": por lo que se le compra. Se arma con los mismos centavos que
    // "Le debo" de cada producto, así los dos totales dan igual.
    final usos = <String, _Uso>{};
    _Uso uso(String id) => usos[id] ??= _Uso();

    final productos = <GananciaDeUnProducto>[];
    for (final id in ids) {
      final v = vendido[id];
      if (recetas.tieneReceta(id)) {
        // Un trago con receta: no tiene stock propio; lo que se le debe es lo que lleva,
        // por cada vendido. Lo entero (el Speed) ya baja de su propio stock.
        final vendidas = v?.unidades ?? 0;
        var leDebo = 0;
        var porUno = 0.0;
        var falta = false;
        for (final r in recetas.de(id)) {
          final l = listaDe(r.ingredienteId);
          final cc = f.contenidos[r.ingredienteId];
          final u = uso(r.ingredienteId);
          if (l == null || (r.unidad == UnidadDeReceta.cc && (cc == null || cc <= 0))) {
            falta = true;
            if (vendidas > 0) u.falta = true;
            continue;
          }
          final int parte;
          if (r.unidad == UnidadDeReceta.cc) {
            final trae = cc!;
            porUno += r.cantidad * l / trae;
            parte = (vendidas * r.cantidad * l / trae).round();
            u.cc += vendidas * r.cantidad;
          } else {
            porUno += r.cantidad * l;
            parte = vendidas * r.cantidad * l;
            u.enTragos += vendidas * r.cantidad;
          }
          u.leDebo += parte;
          leDebo += parte;
        }
        productos.add(GananciaDeUnProducto(
          productoId: id,
          nombre: nombreDe(id),
          vendidas: vendidas,
          seVendio: centavos(v?.plata ?? 0),
          // Sin la lista de algo que lleva, lo que se debe va con lo que sí se sabe (lo
          // mismo que suma "Para el proveedor"), y la ganancia no se sabe.
          lista: falta ? null : porUno.round(),
          leDebo: leDebo,
          faltaLaLista: falta && vendidas > 0,
          porReceta: true,
        ));
        continue;
      }
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
      final lista = listaDe(id);
      final falta = lista == null && (vendidas > 0 || perdidas > 0);
      final u = uso(id)
        ..sueltas += vendidas
        ..perdidas += perdidas
        ..leDebo += lista == null ? 0 : (vendidas + perdidas) * lista;
      if (falta) u.falta = true;
      productos.add(GananciaDeUnProducto(
        productoId: id,
        nombre: nombreDe(id),
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
    final paraElProveedor = <UsoDelProveedor>[
      for (final e in usos.entries)
        if (e.value.seUso || e.value.falta)
          UsoDelProveedor(
            productoId: e.key,
            nombre: nombreDe(e.key),
            sueltas: e.value.sueltas,
            perdidas: e.value.perdidas,
            enTragos: e.value.enTragos,
            cc: e.value.cc,
            contenidoCc: f.contenidos[e.key],
            lista: listaDe(e.key),
            leDebo: e.value.leDebo,
            faltaLaLista: e.value.falta,
          ),
    ];
    return GananciaDeUnaFiesta(
      eventoId: f.eventoId,
      nombre: f.nombre,
      noche: noche,
      otrasNoches: otras,
      productos: productos,
      recargo: centavos(cierre.recargos),
      paraElProveedor: paraElProveedor,
    );
  }
}

/// Lo que se va juntando de un producto para "Para el proveedor", en una fiesta.
class _Uso {
  int sueltas = 0;
  int perdidas = 0;
  int enTragos = 0;
  int cc = 0;
  int leDebo = 0;
  bool falta = false;

  bool get seUso => sueltas > 0 || perdidas > 0 || enTragos > 0 || cc > 0;
}
