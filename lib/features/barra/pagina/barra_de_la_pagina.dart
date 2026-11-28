import '../../../core/utils/uuid_utils.dart';
import '../cuentas/stock_por_barra.dart';
import '../datos/barra_repositorio.dart';
import '../central/filas_de_la_red.dart';
import 'cliente_de_la_pagina.dart';

/// **La barra de la fiesta como la ve la página del iPhone** (28-nov-2026): en memoria,
/// con lo que manda la notebook de la barra ([recibir]). Es lo que leen LAS CAJAS y
/// STOCK en la página (las mismas pantallas de la app).
///
/// Lo que se anota (anular, el OK de un cierre, un retiro o el cambio, lo del stock) va
/// a la notebook por [ClienteDeLaPagina.escribir] y **queda recién cuando la notebook
/// contesta**: sin conexión no se anota nada. El catálogo, los precios, las recetas, el
/// recargo y el reparto **no se cambian desde la página**, y el precio de lista **nunca
/// llega** ([costos] da vacío).
class BarraDeLaPagina implements BarraDelJefe {
  BarraDeLaPagina(this._cliente);

  final ClienteDeLaPagina _cliente;

  /// tabla → id → fila.
  final _filas = <String, Map<String, Map<String, dynamic>>>{};

  static final _tablas = {...tablasDeLaRed, ...tablasDelCatalogoDeLaPagina};

  /// Lo que manda la notebook: `{tabla: [fila…]}`. Una fila con el mismo id reemplaza a la
  /// que había (la notebook manda lo último que tiene).
  void recibir(Map<dynamic, dynamic> filas) {
    for (final e in filas.entries) {
      final tabla = e.key;
      final lista = e.value;
      if (tabla is! String || !_tablas.contains(tabla) || lista is! List) continue;
      final deLaTabla = _filas[tabla] ??= {};
      for (final f in lista) {
        if (f is! Map) continue;
        final id = f['id'];
        if (id is String) deLaTabla[id] = Map<String, dynamic>.from(f);
      }
    }
  }

  /// Una fila que la notebook ya guardó ([ClienteDeLaPagina.escribir]).
  void poner(String tabla, Map<String, Object?> fila) => recibir({
        tabla: [fila],
      });

  Iterable<Map<String, dynamic>> _de(String tabla, [String? eventoId]) => [
        for (final f in (_filas[tabla] ?? const <String, Map<String, dynamic>>{}).values)
          if (eventoId == null || f['evento_id'] == eventoId) f,
      ];

  static int _porCreacion(Map<String, dynamic> a, Map<String, dynamic> b) {
    final c = '${a['created_at'] ?? ''}'.compareTo('${b['created_at'] ?? ''}');
    return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
  }

  List<Map<String, dynamic>> _ordenadas(String tabla, String eventoId) =>
      _de(tabla, eventoId).toList()..sort(_porCreacion);

  Never _noEnLaPagina() => throw UnsupportedError('Eso no se cambia desde la página: se hace en la notebook.');

  // ── El catálogo (solo se mira) ────────────────────────────────────────────

  @override
  Future<List<ProductoBarra>> productos({bool conBajas = false}) async {
    final lista = [
      for (final f in _de('barra_productos'))
        if (ProductoBarra.fromMap(f) case final p when conBajas || p.activo) p,
    ]..sort((a, b) {
        final o = a.orden.compareTo(b.orden);
        if (o != 0) return o;
        final n = a.nombre.compareTo(b.nombre);
        return n != 0 ? n : a.id.compareTo(b.id);
      });
    return lista;
  }

  @override
  Future<List<PrecioBarra>> precios(String eventoId, {bool conBajas = false}) async {
    final lista = [
      for (final f in _de('barra_precios', eventoId))
        if (PrecioBarra.fromMap(f) case final p when conBajas || p.activo) p,
    ]..sort((a, b) {
        final o = a.orden.compareTo(b.orden);
        return o != 0 ? o : a.id.compareTo(b.id);
      });
    return lista;
  }

  @override
  Future<RecargoBarra?> recargo(String eventoId) async {
    final f = _de('barra_recargos', eventoId).firstOrNull;
    return f == null ? null : RecargoBarra.fromMap(f);
  }

  @override
  Future<List<RecetaBarra>> recetas(String eventoId) async => [
        for (final f in _ordenadas('barra_recetas', eventoId))
          if (RecetaBarra.fromMap(f) case final r when r.activo) r,
      ];

  /// **El precio de lista nunca llega a la página.**
  @override
  Future<List<CostoBarra>> costos(String eventoId) async => const [];

  @override
  Future<ProductoBarra> guardarProducto(ProductoBarra producto, {required String quien}) => _noEnLaPagina();

  @override
  Future<PrecioBarra> guardarPrecio(PrecioBarra precio, {required String quien}) => _noEnLaPagina();

  @override
  Future<RecargoBarra> guardarRecargo(RecargoBarra recargo, {required String quien}) => _noEnLaPagina();

  @override
  Future<RecetaBarra> guardarReceta(RecetaBarra receta, {required String quien}) => _noEnLaPagina();

  @override
  Future<CostoBarra> guardarCosto(CostoBarra costo, {required String quien}) => _noEnLaPagina();

  @override
  Future<StockEnLaBarra> guardarReparto(StockEnLaBarra reparto, {required String quien}) => _noEnLaPagina();

  // ── Las cajas de la noche ─────────────────────────────────────────────────

  @override
  Future<List<CajaBarra>> cajas(String eventoId) async {
    final lista = [for (final f in _de('barra_cajas', eventoId)) CajaBarra.fromMap(f)]
      ..sort((a, b) {
        final n = a.numeroCaja.compareTo(b.numeroCaja);
        if (n != 0) return n;
        final t = a.abiertaAt.compareTo(b.abiertaAt);
        return t != 0 ? t : a.id.compareTo(b.id);
      });
    return lista;
  }

  @override
  Future<List<VentaBarra>> ventas(String eventoId) async =>
      [for (final f in _ordenadas('barra_ventas', eventoId)) VentaBarra.fromMap(f)];

  @override
  Future<List<AnulacionBarra>> anulaciones(String eventoId) async =>
      [for (final f in _ordenadas('barra_anulaciones', eventoId)) AnulacionBarra.fromMap(f)];

  @override
  Future<List<ValeBarra>> vales(String eventoId) async =>
      [for (final f in _ordenadas('barra_vales', eventoId)) ValeBarra.fromMap(f)];

  @override
  Future<List<PasoDelCierre>> pasosDelCierre(String eventoId) async =>
      [for (final f in _ordenadas('barra_cierres', eventoId)) PasoDelCierre.fromMap(f)];

  @override
  Future<List<MovimientoDeCaja>> movimientosDeCaja(String eventoId) async =>
      [for (final f in _ordenadas('barra_caja_movimientos', eventoId)) MovimientoDeCaja.fromMap(f)];

  @override
  Future<List<StockEnLaBarra>> repartos(String eventoId) async =>
      [for (final f in _de('barra_stock_barras', eventoId)) StockEnLaBarra.fromMap(f)];

  @override
  Future<List<MovimientoDeStock>> movimientosDeStock(String eventoId) async =>
      [for (final f in _ordenadas('barra_stock_movimientos', eventoId)) MovimientoDeStock.fromMap(f)];

  // ── Lo que se anota (va a la notebook y espera su respuesta) ─────────────

  @override
  Future<AnulacionBarra> anular(
    VentaBarra venta, {
    required String motivo,
    required String quien,
    bool valeVolvio = true,
  }) async {
    final ya = _filas['barra_anulaciones']?[UuidUtils.barraAnulacionId(venta.id)];
    if (ya != null) return AnulacionBarra.fromMap(ya);
    final nueva = AnulacionBarra.de(
      venta,
      motivo: motivo,
      valeVolvio: valeVolvio,
      hechoPor: quien,
      deviceId: _cliente.equipo,
      ahora: _cliente.ahora(),
    );
    // Si la notebook ya la tenía (desde otro equipo), vale la de la notebook.
    return AnulacionBarra.fromMap(Map<String, dynamic>.from(await _cliente.escribir('barra_anulaciones', nueva.toMap())));
  }

  @override
  Future<PasoDelCierre> anotarPasoDelCierre(PasoDelCierre paso) async {
    final conEquipo = paso.conEquipo(_cliente.equipo);
    if (_filas['barra_cierres']?[conEquipo.id] case final ya?) return PasoDelCierre.fromMap(ya);
    return PasoDelCierre.fromMap(Map<String, dynamic>.from(await _cliente.escribir('barra_cierres', conEquipo.toMap())));
  }

  @override
  Future<MovimientoDeCaja> anotarMovimientoDeCaja(MovimientoDeCaja movimiento, {required String quien}) async {
    final caja = _filas['barra_cajas']?[movimiento.cajaBarraId];
    if (caja != null && !CajaBarra.fromMap(caja).abierta) {
      throw CajaYaCerrada(CajaBarra.fromMap(caja).numeroCaja);
    }
    final sellado = movimiento.sellado(hechoPor: quien, deviceId: _cliente.equipo, ahora: _cliente.ahora());
    return MovimientoDeCaja.fromMap(
        Map<String, dynamic>.from(await _cliente.escribir('barra_caja_movimientos', sellado.toMap())));
  }

  @override
  Future<MovimientoDeStock> anotarMovimientoDeStock(MovimientoDeStock movimiento, {required String quien}) async {
    final sellado = movimiento.selladoPor(quien).conEquipo(_cliente.equipo);
    return MovimientoDeStock.fromMap(
        Map<String, dynamic>.from(await _cliente.escribir('barra_stock_movimientos', sellado.toMap())));
  }

  @override
  Future<MovimientoDeStock> avisarQueVa({
    required String eventoId,
    required String productoId,
    required String barra,
    required String quien,
  }) async {
    final aviso = MovimientoDeStock.enCamino(
      eventoId: eventoId,
      productoId: productoId,
      barra: barra,
      avisosPrevios: StockPorBarra.llegadasDesde(
          await movimientosDeStock(eventoId), eventoId, barra, productoId, _cliente.equipo),
      hechoPor: quien,
      ahora: _cliente.ahora(),
    );
    return anotarMovimientoDeStock(aviso, quien: quien);
  }
}
