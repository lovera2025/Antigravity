import '../cuentas/dia_de_operacion.dart';
import 'anulacion_barra.dart';
import 'caja_barra.dart';
import 'costo_barra.dart';
import 'movimiento_de_caja.dart';
import 'movimiento_de_stock.dart';
import 'paso_del_cierre.dart';
import 'precio_barra.dart';
import 'producto_barra.dart';
import 'receta_barra.dart';
import 'recargo_barra.dart';
import 'stock_en_la_barra.dart';
import 'vale_barra.dart';
import 'venta_barra.dart';

export '../cuentas/dia_de_operacion.dart' show DiaDeOperacion;
export 'anulacion_barra.dart';
export 'caja_barra.dart';
export 'costo_barra.dart';
export 'movimiento_de_caja.dart';
export 'movimiento_de_stock.dart';
export 'paso_del_cierre.dart';
export 'precio_barra.dart';
export 'producto_barra.dart';
export 'receta_barra.dart';
export 'recargo_barra.dart';
export 'stock_en_la_barra.dart';
export 'vale_barra.dart';
export 'venta_barra.dart';

/// Lo que hace el jefe con la barra: el catálogo, los precios de cada fiesta, mirar
/// las cajas y anular. Lo mismo en la PC ([BarraLocal], la base y la cola de subida)
/// y en la web del iPhone ([BarraNube], la nube directo).
///
/// [quien] es el nombre que queda en `hecho_por`.
abstract interface class BarraDelJefe {
  /// Por orden y nombre. Con [conBajas] también los dados de baja.
  Future<List<ProductoBarra>> productos({bool conBajas = false});

  /// Lo guarda como está, con quién, desde qué equipo y cuándo.
  Future<ProductoBarra> guardarProducto(ProductoBarra producto, {required String quien});

  /// Los precios de la fiesta, por orden. Con [conBajas] también los sacados.
  Future<List<PrecioBarra>> precios(String eventoId, {bool conBajas = false});

  Future<PrecioBarra> guardarPrecio(PrecioBarra precio, {required String quien});

  /// El recargo por transferencia de la fiesta. Null si el jefe todavía no lo puso.
  Future<RecargoBarra?> recargo(String eventoId);

  Future<RecargoBarra> guardarRecargo(RecargoBarra recargo, {required String quien});

  /// Las recetas activas de los tragos de la fiesta (`barra_recetas`, v84; sin plata).
  /// Las cuentas del stock reciben las ventas por `RecetasDeLaBarra.paraElStock`: el
  /// Speed de cada vodka baja del stock del Speed.
  Future<List<RecetaBarra>> recetas(String eventoId);

  /// Guarda un ingrediente de la receta de un trago (id fijo por fiesta, trago e
  /// ingrediente). **Sacarlo es guardarlo con `activo: false`**: no se borra.
  Future<RecetaBarra> guardarReceta(RecetaBarra receta, {required String quien});

  /// El precio de lista de cada producto en la fiesta (`barra_costos`, v84): lo que le
  /// cobra el proveedor. **Solo del jefe** (`ReglasDeLaBarra.veElCostoYLaGanancia`):
  /// ninguna pantalla de la cajera, la encargada o el repositor lo lee, y no baja a una
  /// tablet.
  Future<List<CostoBarra>> costos(String eventoId);

  Future<CostoBarra> guardarCosto(CostoBarra costo, {required String quien});

  Future<List<CajaBarra>> cajas(String eventoId);

  /// Todas las de la fiesta, también las anuladas: lo que dice si cuentan es
  /// [anulaciones].
  Future<List<VentaBarra>> ventas(String eventoId);

  Future<List<AnulacionBarra>> anulaciones(String eventoId);

  /// **La venta no se toca:** se agrega su anulación. Anular de nuevo la misma venta
  /// devuelve la anulación que ya había.
  Future<AnulacionBarra> anular(
    VentaBarra venta, {
    required String motivo,
    required String quien,
  });

  /// Los papeles de vale que salieron de la fiesta, originales y copias.
  Future<List<ValeBarra>> vales(String eventoId);

  /// Los pasos del cierre con el OK de la encargada (`barra_cierres`, v79) de la
  /// fiesta: los pedidos de las cajas y lo que se les contestó.
  Future<List<PasoDelCierre>> pasosDelCierre(String eventoId);

  /// Anota la respuesta de la encargada o del jefe a un pedido (ok, o que cuente de
  /// nuevo). **La caja de la cajera no se toca:** la cierra su tablet cuando le llega.
  /// Solo se agregan filas.
  Future<PasoDelCierre> anotarPasoDelCierre(PasoDelCierre paso);

  /// Los retiros de efectivo y el cambio que dio la encargada (o el jefe) en las cajas
  /// de la fiesta (`barra_caja_movimientos`, v84). Entran en el efectivo que tiene que
  /// haber (`CierreDeBarra.de(movimientos:)`).
  Future<List<MovimientoDeCaja>> movimientosDeCaja(String eventoId);

  /// Anota un retiro, un cambio o una corrección, **con motivo** y a nombre de [quien].
  /// Solo se agregan filas. Sobre una caja ya cerrada no se anota: tira [CajaYaCerrada].
  /// Lo hacen la encargada, desde su sesión (también en su propia caja), y el jefe.
  Future<MovimientoDeCaja> anotarMovimientoDeCaja(MovimientoDeCaja movimiento, {required String quien});

  // ── El stock por barra (v83) ──────────────────────────────────────────────

  /// El reparto del jefe en [eventoId]: con cuánto arranca cada producto en cada barra y
  /// desde cuánto se avisa (`barra_stock_barras`), también lo sacado del reparto.
  Future<List<StockEnLaBarra>> repartos(String eventoId);

  /// Guarda con cuánto arranca un producto en una barra. Una fila por fiesta, producto y
  /// barra (id fijo): guardar de nuevo la reemplaza. **Solo el jefe.** Los límites los
  /// dice `StockPorBarra.errorDelReparto`.
  Future<StockEnLaBarra> guardarReparto(StockEnLaBarra reparto, {required String quien});

  /// Lo que anotó el repositor en [eventoId] (`barra_stock_movimientos`): reposiciones,
  /// traspasos, faltantes, conteos, entradas y avisos, del más viejo al más nuevo.
  Future<List<MovimientoDeStock>> movimientosDeStock(String eventoId);

  /// Anota un movimiento del stock, a nombre de [quien] y con este equipo. **Solo se
  /// agregan filas**: el mismo, anotado dos veces, queda como estaba. Lo hacen el
  /// repositor y el jefe. Los límites (no más de lo que hay) los dice `StockPorBarra`.
  Future<MovimientoDeStock> anotarMovimientoDeStock(MovimientoDeStock movimiento, {required String quien});

  /// **"Voy en camino"** a [barra] con [productoId]. Lo arma el repositorio y no la
  /// pantalla: en el aviso va cuántas veces **este equipo** ya llegó a esa barra con ese
  /// producto (`avisos_previos`), y contado con otro equipo el aviso nacería ya cumplido.
  Future<MovimientoDeStock> avisarQueVa({
    required String eventoId,
    required String productoId,
    required String barra,
    required String quien,
  });
}

/// Lo que hace la cajera, **solo en su equipo** (la tablet o la PC): abrir su caja,
/// vender y cerrarla. Todo se guarda en la base del equipo y sube solo cuando hay
/// internet. La web no vende.
abstract interface class BarraDeLaCaja {
  Future<List<ProductoBarra>> productos({bool conBajas = false});

  Future<List<PrecioBarra>> precios(String eventoId, {bool conBajas = false});

  /// Las fiestas con al menos un precio activo en este equipo: las únicas que la
  /// cajera puede elegir.
  Future<Set<String>> fiestasConPrecio();

  /// El recargo que puso el jefe para la fiesta: cada cobro arranca con ese. Null si
  /// no lo puso (arranca con el último que usó el equipo).
  Future<RecargoBarra?> recargo(String eventoId);

  /// Las recetas activas de los tragos de la fiesta (`barra_recetas`, v84; sin plata).
  /// Las cuentas del stock reciben las ventas por `RecetasDeLaBarra.paraElStock`: el
  /// Speed de cada vodka baja del stock del Speed.
  Future<List<RecetaBarra>> recetas(String eventoId);

  /// Las cajas abiertas de la fiesta que conoce este equipo, de cualquier operador:
  /// para avisar si el número elegido ya lo tiene otra.
  Future<List<CajaBarra>> cajasAbiertas(String eventoId);

  /// Todas las cajas de la fiesta que conoce este equipo, abiertas y cerradas: con ellas
  /// se sabe la noche de cada venta (el "Quedan" de VENDER cuenta solo la de esta noche).
  Future<List<CajaBarra>> cajas(String eventoId);

  /// Cuántas ventas de este equipo esperan subir.
  Future<int> ventasSinSubir();

  /// La caja abierta de [operadorId] en esa fiesta, **en este equipo**, la más nueva.
  /// Con [desdeLaNoche], solo una abierta esa noche o después (`cuentas/dia_de_operacion.dart`):
  /// una de una noche anterior (una de prueba que quedó abierta) no cuenta. "O después"
  /// por si el reloj de la tablet está corrido: esa sí es la caja de hoy.
  /// Null si no tiene.
  Future<CajaBarra?> cajaAbierta({
    required String eventoId,
    required String operadorId,
    DiaDeOperacion? desdeLaNoche,
  });

  /// Abre una caja en este equipo. Si [operadorId] ya tiene una abierta en esa fiesta
  /// en este equipo **esta noche**, devuelve esa: no se abren dos por tocar dos veces.
  /// Una suya de otra noche (una de prueba que quedó abierta) no cuenta: se abre la de
  /// hoy y la otra sigue aparte, en su día (25-nov-2026).
  Future<CajaBarra> abrirCaja({
    required String eventoId,
    required String operadorId,
    required String operadorNombre,
    required int numeroCaja,
    String? sede,
    double cambioInicial = 0,
  });

  /// Guarda la venta con el número que le toca en su caja, en una transacción.
  /// La venta se guarda **antes** de imprimir: sin impresora, igual queda.
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
  });

  /// Pone el cambio con que arrancó la caja, cuando lo haya: abrir no lo pregunta.
  /// Una caja cerrada queda como se cerró.
  Future<CajaBarra> ponerCambio(CajaBarra caja, double cambio, {required String quien});

  /// Todas las de la fiesta que conoce este equipo, de todas las cajas: el stock es
  /// general, y lo descuentan todas.
  Future<List<VentaBarra>> ventas(String eventoId);

  Future<List<AnulacionBarra>> anulaciones(String eventoId);

  /// Por número.
  Future<List<VentaBarra>> ventasDeLaCaja(String cajaId);

  Future<List<AnulacionBarra>> anulacionesDeLaCaja(String cajaId);

  /// La cajera también anula (decidido el 3-nov), **solo las ventas de su caja** (lo
  /// cuida la pantalla) y con motivo. La venta no se toca: se agrega su anulación.
  /// Anular de nuevo devuelve la que ya había.
  Future<AnulacionBarra> anular(
    VentaBarra venta, {
    required String motivo,
    required String quien,
  });

  /// Anota un papel de vale que **salió**, con quién y desde qué equipo. Solo se
  /// agregan filas.
  Future<ValeBarra> anotarVale(ValeBarra vale);

  /// Los papeles de vale que salieron de la caja, originales y copias, por fecha.
  Future<List<ValeBarra>> valesDeLaCaja(String cajaId);

  /// Pone la nota de una caja **ya cerrada**: lo único que se puede agregar después de
  /// contar a ciegas. Lo contado y la diferencia no se tocan. Sobre una caja abierta no
  /// hace nada (la nota va al cerrar).
  Future<CajaBarra> anotarCierre(CajaBarra caja, {String? nota, required String quien});

  /// Los pasos del cierre con el OK de la encargada que conoce este equipo, de todas
  /// las cajas de la fiesta.
  Future<List<PasoDelCierre>> pasosDelCierre(String eventoId);

  /// Los retiros y el cambio que la encargada anotó en [cajaId], que este equipo
  /// conoce: con ellos la cajera, al cerrar, ve lo que tenía que haber. La cajera no los
  /// anota (eso es [BarraDelJefe.anotarMovimientoDeCaja]).
  Future<List<MovimientoDeCaja>> movimientosDeLaCaja(String cajaId);

  /// El reparto del jefe y lo que anotó el repositor, que este equipo conoce: con eso
  /// VENDER dice cuántas quedan **en su barra** (`StockPorBarra`). La cajera no los
  /// escribe.
  Future<List<StockEnLaBarra>> repartos(String eventoId);

  Future<List<MovimientoDeStock>> movimientosDeStock(String eventoId);

  /// Anota un paso del cierre (el pedido de la cajera, que volvió a vender, que cerró
  /// sin esperar; o la respuesta de la encargada desde su equipo). Solo se agregan
  /// filas.
  Future<PasoDelCierre> anotarPasoDelCierre(PasoDelCierre paso);

  /// La cierra con lo que contó la cajera y la diferencia. Una caja ya cerrada queda
  /// como se cerró: no se vuelve a cerrar.
  Future<CajaBarra> cerrarCaja(
    CajaBarra caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  });
}
