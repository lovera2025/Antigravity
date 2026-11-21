import '../../../models/entradas_retiro.dart' show TramoTalonario;
import '../../barra/datos/venta_barra.dart' show MedioBarra;
import 'anulacion_entradas.dart';
import 'caja_entradas.dart';
import 'config_entradas.dart';
import 'movimiento_para_rendir.dart';
import 'venta_entradas.dart';
import 'verificacion_entradas.dart';

export '../../barra/datos/venta_barra.dart' show MedioBarra;
export 'anulacion_entradas.dart';
export 'caja_entradas.dart';
export 'config_entradas.dart';
export 'movimiento_para_rendir.dart';
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

  /// Los renglones de las entradas para rendir de la fiesta (v82), anulados o
  /// no, en el orden en que se hicieron: los bloques dados, lo rendido, lo
  /// devuelto, lo que no volvió y las anulaciones. Quien vende los necesita
  /// para no vender un número que tiene otra persona.
  Future<List<MovimientoParaRendir>> paraRendir(String eventoId);
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

  /// Quien se llevó [bloque] para rendir rinde: [vendidas] con su plata y
  /// [devueltas] sin vender, con sus números ([numerosDevueltos], la cantidad
  /// justa). Se puede rendir de a partes.
  ///
  /// **Todo o nada, en una sola transacción:** la venta (si vendió algo, en
  /// [caja], que tiene que estar en la base de este equipo y abierta, como en
  /// [vender]: la de [cajaAbierta]; con su número)
  /// y los renglones `vendio` y `devolvio`, cada uno con su cola. La venta va a
  /// nombre de quien rinde, **sin familia** (`contratoAlumnoId` null) y sin
  /// números, con un solo renglón al precio y con el nombre del día en que se
  /// las llevó, sin descuento.
  ///
  /// **Vuelve a contar lo que le queda al bloque dentro de la transacción**: si
  /// se pasa (otro rindió en el medio), tira `StateError` y no guarda nada. Si
  /// solo devuelve, no pide caja ni plata. Tira `ArgumentError` si lo que se
  /// pide no cierra.
  Future<RendicionDeEntradas> rendir({
    CajaEntradas? caja,
    required MovimientoParaRendir bloque,
    required int vendidas,
    int devueltas = 0,
    List<TramoTalonario> numerosDevueltos = const [],
    MedioBarra medio = MedioBarra.efectivo,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    required String quien,
  });

  Future<List<AnulacionEntradas>> anulacionesDeLaCaja(String cajaId);

  /// Cuántas ventas de este equipo esperan subir a la nube.
  Future<int> ventasSinSubir();

  /// Lo demás de la venta de este equipo que espera subir: cajas que se
  /// abrieron o cerraron, anulaciones, verificaciones y precios (20-nov-2026:
  /// la línea de VENDER decía "Todo subido" con la caja cerrada sin subir).
  Future<int> cambiosSinSubir();
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

  /// Le da a [personaNombre] [cantidad] entradas para rendir, con sus números
  /// ([numeros], obligatorios) y el [precio] de hoy con su [nombrePrecio], que
  /// quedan fijos (`MovimientoParaRendir.dio`). [contratoAlumnoId]: si es un
  /// alumno de la fiesta.
  Future<MovimientoParaRendir> darParaRendir({
    required String eventoId,
    required String personaNombre,
    String? personaContacto,
    String? contratoAlumnoId,
    required int cantidad,
    required List<TramoTalonario> numeros,
    required double precio,
    required String nombrePrecio,
    String? nota,
    required String quien,
  });

  /// Da por perdidas [cantidad] de [bloque], con motivo: no entra plata y esos
  /// números quedan anulados para siempre. Vuelve a contar lo que le queda
  /// dentro de la transacción: si se pasa, `StateError`.
  Future<MovimientoParaRendir> noVolvieron(
    MovimientoParaRendir bloque, {
    required int cantidad,
    List<TramoTalonario> numeros = const [],
    required String motivo,
    required String quien,
  });

  /// Anula [movimiento] con motivo: un bloque **sin movimientos vigentes**
  /// (revisado dentro de la transacción; si tiene, `StateError`), un "devolvió"
  /// o un "no volvieron". **Lo vendido no se anula acá**: se anula su venta en
  /// VENTAS. Es otra fila con id fijo: anular dos veces devuelve la que ya
  /// había.
  Future<MovimientoParaRendir> anularDeParaRendir(
    MovimientoParaRendir movimiento, {
    required String motivo,
    required String quien,
  });
}
