import 'anulacion_barra.dart';
import 'caja_barra.dart';
import 'precio_barra.dart';
import 'producto_barra.dart';
import 'vale_barra.dart';
import 'venta_barra.dart';

export 'anulacion_barra.dart';
export 'caja_barra.dart';
export 'precio_barra.dart';
export 'producto_barra.dart';
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

  /// Las cajas abiertas de la fiesta que conoce este equipo, de cualquier operador:
  /// para avisar si el número elegido ya lo tiene otra.
  Future<List<CajaBarra>> cajasAbiertas(String eventoId);

  /// Cuántas ventas de este equipo esperan subir.
  Future<int> ventasSinSubir();

  /// La caja abierta de [operadorId] en esa fiesta, **en este equipo**. Null si no
  /// tiene.
  Future<CajaBarra?> cajaAbierta({
    required String eventoId,
    required String operadorId,
  });

  /// Abre una caja en este equipo. Si [operadorId] ya tiene una abierta en esa fiesta
  /// en este equipo, devuelve esa: no se abren dos por tocar dos veces.
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
