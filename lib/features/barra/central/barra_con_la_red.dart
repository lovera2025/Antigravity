import 'dart:async';

import 'package:flutter/foundation.dart';

import '../datos/barra_repositorio.dart';
import 'filas_de_la_red.dart';

/// Por dónde sale a la red del salón lo que escribe este equipo. Lo pone la central de la
/// barra cuando se prende (en la notebook) o el cliente cuando arranca (en la tablet); sin
/// ninguno, no sale nada y todo sigue igual que antes.
class AvisoALaRed {
  Future<void> Function(String tabla, String id)? salida;

  /// Sube con cada cosa que este equipo escribe en la barra (también el catálogo y los
  /// precios, que no salen a la red): con eso VENDER y la notebook vuelven a contar lo que
  /// espera subir sin estar contando todo el tiempo.
  final escrituras = ValueNotifier<int>(0);

  void escribio() => escrituras.value++;

  void avisar(String tabla, String id) {
    escribio();
    final s = salida;
    if (s == null) return;
    unawaited(s(tabla, id).catchError((Object _) {}));
  }
}

/// La barra de este equipo, **más la red del salón**: hace lo mismo que la que envuelve
/// (la base y la cola de subida) y, después de cada cosa que escribe la caja (abrir,
/// poner el cambio, vender, anular, un vale, cerrar, la nota del cierre), se la pasa a la
/// central por [AvisoALaRed]. Vender nunca espera a la red: el aviso va después.
///
/// `test/barra_con_la_red_test.dart` lee las escrituras de `BarraDeLaCaja` y falla si
/// aparece una que no avisa.
class BarraConLaRed implements BarraDeLaCaja, BarraDelJefe, BarraDeLaRed {
  BarraConLaRed({
    required BarraDeLaCaja caja,
    required BarraDelJefe jefe,
    required BarraDeLaRed red,
    required this.aviso,
  })  : _caja = caja,
        _jefe = jefe,
        _red = red;

  final BarraDeLaCaja _caja;
  final BarraDelJefe _jefe;
  final BarraDeLaRed _red;
  final AvisoALaRed aviso;

  T _avisar<T>(String tabla, String id, T hecho) {
    aviso.avisar(tabla, id);
    return hecho;
  }

  // ── Lo que escribe la caja: sale a la red ─────────────────────────────────

  @override
  Future<CajaBarra> abrirCaja({
    required String eventoId,
    required String operadorId,
    required String operadorNombre,
    required int numeroCaja,
    String? sede,
    double cambioInicial = 0,
  }) async {
    final caja = await _caja.abrirCaja(
      eventoId: eventoId,
      operadorId: operadorId,
      operadorNombre: operadorNombre,
      numeroCaja: numeroCaja,
      sede: sede,
      cambioInicial: cambioInicial,
    );
    return _avisar('barra_cajas', caja.id, caja);
  }

  @override
  Future<CajaBarra> ponerCambio(CajaBarra caja, double cambio, {required String quien}) async {
    final hecho = await _caja.ponerCambio(caja, cambio, quien: quien);
    return _avisar('barra_cajas', hecho.id, hecho);
  }

  @override
  Future<VentaBarra> vender({
    required CajaBarra caja,
    required List<RenglonVenta> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    required String quien,
  }) async {
    final venta = await _caja.vender(
      caja: caja,
      renglones: renglones,
      medio: medio,
      efectivo: efectivo,
      transferencia: transferencia,
      recibe: recibe,
      recargo: recargo,
      recargoPct: recargoPct,
      quien: quien,
    );
    return _avisar('barra_ventas', venta.id, venta);
  }

  @override
  Future<AnulacionBarra> anular(VentaBarra venta, {required String motivo, required String quien}) async {
    final hecho = await _caja.anular(venta, motivo: motivo, quien: quien);
    return _avisar('barra_anulaciones', hecho.id, hecho);
  }

  @override
  Future<ValeBarra> anotarVale(ValeBarra vale) async {
    final hecho = await _caja.anotarVale(vale);
    return _avisar('barra_vales', hecho.id, hecho);
  }

  @override
  Future<CajaBarra> anotarCierre(CajaBarra caja, {String? nota, required String quien}) async {
    final hecho = await _caja.anotarCierre(caja, nota: nota, quien: quien);
    return _avisar('barra_cajas', hecho.id, hecho);
  }

  /// El pedido de cierre de la cajera y el OK de la encargada (v79): por la red del
  /// salón llegan al otro equipo en el momento, haya internet o no.
  @override
  Future<PasoDelCierre> anotarPasoDelCierre(PasoDelCierre paso) async {
    final hecho = await _caja.anotarPasoDelCierre(paso);
    return _avisar('barra_cierres', hecho.id, hecho);
  }

  @override
  Future<CajaBarra> cerrarCaja(
    CajaBarra caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  }) async {
    final hecho = await _caja.cerrarCaja(
      caja,
      efectivoContado: efectivoContado,
      diferencia: diferencia,
      nota: nota,
      quien: quien,
    );
    return _avisar('barra_cajas', hecho.id, hecho);
  }

  // ── Lo del jefe: el catálogo, los precios y el recargo van por la nube ───────

  T _escribio<T>(T hecho) {
    aviso.escribio();
    return hecho;
  }

  @override
  Future<ProductoBarra> guardarProducto(ProductoBarra producto, {required String quien}) async =>
      _escribio(await _jefe.guardarProducto(producto, quien: quien));

  @override
  Future<PrecioBarra> guardarPrecio(PrecioBarra precio, {required String quien}) async =>
      _escribio(await _jefe.guardarPrecio(precio, quien: quien));

  @override
  Future<RecargoBarra> guardarRecargo(RecargoBarra recargo, {required String quien}) async =>
      _escribio(await _jefe.guardarRecargo(recargo, quien: quien));

  @override
  Future<List<CajaBarra>> cajas(String eventoId) => _jefe.cajas(eventoId);

  @override
  Future<List<ValeBarra>> vales(String eventoId) => _jefe.vales(eventoId);

  // ── Lo que solo lee ────────────────────────────────────────────────────────

  @override
  Future<List<ProductoBarra>> productos({bool conBajas = false}) => _caja.productos(conBajas: conBajas);

  @override
  Future<List<PrecioBarra>> precios(String eventoId, {bool conBajas = false}) =>
      _caja.precios(eventoId, conBajas: conBajas);

  @override
  Future<Set<String>> fiestasConPrecio() => _caja.fiestasConPrecio();

  @override
  Future<RecargoBarra?> recargo(String eventoId) => _caja.recargo(eventoId);

  @override
  Future<List<CajaBarra>> cajasAbiertas(String eventoId) => _caja.cajasAbiertas(eventoId);

  @override
  Future<int> ventasSinSubir() => _caja.ventasSinSubir();

  @override
  Future<CajaBarra?> cajaAbierta({required String eventoId, required String operadorId}) =>
      _caja.cajaAbierta(eventoId: eventoId, operadorId: operadorId);

  @override
  Future<List<VentaBarra>> ventas(String eventoId) => _caja.ventas(eventoId);

  @override
  Future<List<AnulacionBarra>> anulaciones(String eventoId) => _caja.anulaciones(eventoId);

  @override
  Future<List<VentaBarra>> ventasDeLaCaja(String cajaId) => _caja.ventasDeLaCaja(cajaId);

  @override
  Future<List<AnulacionBarra>> anulacionesDeLaCaja(String cajaId) => _caja.anulacionesDeLaCaja(cajaId);

  @override
  Future<List<ValeBarra>> valesDeLaCaja(String cajaId) => _caja.valesDeLaCaja(cajaId);

  @override
  Future<List<PasoDelCierre>> pasosDelCierre(String eventoId) => _caja.pasosDelCierre(eventoId);

  // ── La red ─────────────────────────────────────────────────────────────────

  @override
  Future<bool> guardarDeOtroEquipo(String tabla, Map<String, Object?> fila) =>
      _red.guardarDeOtroEquipo(tabla, fila);

  @override
  Future<Map<String, List<Map<String, Object?>>>> filasDeLaFiesta(String eventoId) =>
      _red.filasDeLaFiesta(eventoId);

  @override
  Future<Map<String, Object?>?> filaDeLaRed(String tabla, String id) => _red.filaDeLaRed(tabla, id);

  @override
  Future<PendientesDeLaBarra> pendientesDeLaBarra() => _red.pendientesDeLaBarra();
}
