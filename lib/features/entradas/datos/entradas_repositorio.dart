import '../../barra/datos/venta_barra.dart' show MedioBarra;
import 'anulacion_entradas.dart';
import 'caja_entradas.dart';
import 'config_entradas.dart';
import 'venta_entradas.dart';
import 'verificacion_entradas.dart';

export '../../barra/datos/venta_barra.dart' show MedioBarra;
export 'anulacion_entradas.dart';
export 'caja_entradas.dart';
export 'config_entradas.dart';
export 'venta_entradas.dart';
export 'verificacion_entradas.dart';

/// Lo que se lee de la venta de entradas de una fiesta, para todos: quien vende
/// lo necesita para los números del talonario y para saber cuántas de sus
/// lugares ya compró cada familia; el jefe, para verlo todo.
abstract interface class EntradasDeLaFiesta {
  /// El precio de la fiesta. Null: el jefe todavía no puso nada.
  Future<ConfigEntradas?> config(String eventoId);

  /// Las cajas de la fiesta, la más vieja primero.
  Future<List<CajaEntradas>> cajas(String eventoId);

  /// Todas las ventas de la fiesta, anuladas o no, en el orden en que se
  /// hicieron.
  Future<List<VentaEntradas>> ventas(String eventoId);

  Future<List<AnulacionEntradas>> anulaciones(String eventoId);

  Future<List<VerificacionEntradas>> verificaciones(String eventoId);
}

/// La caja de quien vende entradas: abre su caja, vende y la cierra. **Solo en
/// el equipo** (la PC o la tablet): la web no vende.
///
/// Nada de acá cobra una cuota ni toca el contrato de un alumno.
abstract interface class EntradasDeLaCaja implements EntradasDeLaFiesta {
  /// La caja abierta de ese operador en esa fiesta **en este equipo**, si hay:
  /// tocar VENDER dos veces la retoma, no abre otra. [operadorId] null: la del
  /// jefe.
  Future<CajaEntradas?> cajaAbierta({
    required String eventoId,
    String? operadorId,
  });

  /// Abre una caja nueva con su cambio inicial (puede ser 0).
  Future<CajaEntradas> abrirCaja({
    required String eventoId,
    String? operadorId,
    String? operadorNombre,
    double cambioInicial = 0,
  });

  /// La cierra con lo contado. Una caja cerrada no se vuelve a cerrar: devuelve
  /// la que ya estaba.
  Future<CajaEntradas> cerrarCaja(
    CajaEntradas caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  });

  /// Le agrega o cambia la nota a una caja ya cerrada. Es lo único que cambia
  /// después de cerrar.
  Future<CajaEntradas> anotarCierre(
    CajaEntradas caja, {
    String? nota,
    required String quien,
  });

  /// Guarda una venta con su número, que se da en la misma transacción: dos
  /// seguidas no llevan el mismo. Tira si la caja no está en este equipo o está
  /// cerrada, o si la venta no cierra (`VentaEntradas.nueva`).
  Future<VentaEntradas> vender({
    required CajaEntradas caja,
    String? contratoAlumnoId,
    required String compradorNombre,
    String? compradorDni,
    required List<RenglonEntradas> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    String? numeros,
    required String quien,
  });

  Future<List<VentaEntradas>> ventasDeLaCaja(String cajaId);

  Future<List<AnulacionEntradas>> anulacionesDeLaCaja(String cajaId);

  /// Cuántas ventas de este equipo esperan subir a la nube.
  Future<int> ventasSinSubir();
}

/// Lo que hace el jefe con la venta de entradas: el precio, anular y "Pago
/// verificado". Las pantallas lo llaman **solo en modo jefe** (doble llave).
abstract interface class EntradasDelJefe implements EntradasDeLaFiesta {
  /// Guarda el precio de la fiesta. Sin cambios contra lo guardado, no escribe
  /// y devuelve lo que había.
  Future<ConfigEntradas> guardarConfig(
    ConfigEntradas config, {
    required String quien,
  });

  /// Anula [venta] con motivo, y dice si devolvieron las entradas y las
  /// pulseras. Anular dos veces devuelve la que ya había.
  Future<AnulacionEntradas> anular(
    VentaEntradas venta, {
    required String motivo,
    required bool devueltas,
    required String quien,
  });

  /// Tilda o destilda "Pago verificado" de [venta].
  Future<VerificacionEntradas> verificar(
    VentaEntradas venta, {
    required bool verificado,
    required String quien,
  });
}
