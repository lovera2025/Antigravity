import '../../common/utils/currency_extensions.dart';
import '../../mi_empresa/models/ingreso_detallado.dart';
import '../models/medio_pago_caja.dart';
import 'cobro_agrupado.dart';

/// Tablas cuya novedad cambia lo que muestra el cierre de caja.
///
/// `sesiones_caja` entra aunque la toque el latido de cada minuto: el refresco
/// es una consulta local y silenciosa, y sin ella el jefe no vería aparecer la
/// sesión que el operario acaba de abrir o cerrar en la otra PC.
const Set<String> kTablasDelCierre = {
  'pagos_contrato_alumno',
  'sesiones_caja',
  'egresos',
  'transacciones',
  'pagos_prestamo_alquiler',
  'cierre_caja_guia_movimientos',
  'cierre_caja_anotaciones',
};

/// Si lo que bajó de la otra PC obliga a rehacer el cierre.
bool cambiosTocanElCierre(Set<String> tablas) =>
    tablas.any(kTablasDelCierre.contains);

/// Líneas de cobro que estaban en [antes] y ya no están en [despues].
List<IngresoDetallado> lineasQueSeFueron(
  List<IngresoDetallado> antes,
  List<IngresoDetallado> despues,
) {
  final siguen = {for (final i in despues) i.id};
  return [
    for (final i in antes)
      if (!siguen.contains(i.id)) i,
  ];
}

/// "El jefe anuló 1 cobro de esta sesión: PEREZ, JUAN · $ 45.000".
///
/// Sin esto, el total del operario bajaba de golpe sin explicación, que es
/// justo lo que hace desconfiar de la caja. Agrupa por cobro —un cobro de plan
/// y mora son varias líneas— así el conteo coincide con lo que el operario
/// cobró en el mostrador.
String? textoAvisoAnulados(
  List<IngresoDetallado> anuladas, {
  required bool delDia,
}) {
  if (anuladas.isEmpty) return null;
  final cobros = agruparIngresosPorCobro(anuladas);
  final cuantos = cobros.length == 1 ? '1 cobro' : '${cobros.length} cobros';
  final donde = delDia ? 'del día' : 'de esta sesión';
  final detalle = cobros
      .map((c) => '${c.alumno} · ${c.monto.toCurrency()}')
      .join('; ');
  return 'El jefe anuló $cuantos $donde: $detalle';
}

/// Plata de una sesión ya cerrada que se anuló **después** del cierre.
class AnuladoPostCierre {
  final double efectivo;
  final double transferencia;

  const AnuladoPostCierre({this.efectivo = 0, this.transferencia = 0});

  static const cero = AnuladoPostCierre();

  double get total => efectivo + transferencia;
  bool get hayAlgo => total > 0.004;
}

/// Suma lo anulado después del cierre de cada sesión.
///
/// Los totales del cierre ya no cuentan un cobro anulado, pero el arqueo quedó
/// guardado con lo que se contó ese día, con ese cobro adentro. Esta cifra es
/// la que explica la diferencia sin tocar el arqueo.
///
/// [pagosAnulados] son filas de `pagos_contrato_alumno` con `anulado = 1`;
/// [cierrePorSesion], el instante de cierre de cada sesión cerrada. Una sesión
/// abierta no figura: lo que se anula mientras está abierta simplemente sale.
AnuladoPostCierre anuladoDespuesDelCierre({
  required Iterable<Map<String, dynamic>> pagosAnulados,
  required Map<String, DateTime> cierrePorSesion,
}) {
  var efectivo = 0.0;
  var transferencia = 0.0;
  for (final p in pagosAnulados) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) == 0) continue;
    final cerrada = cierrePorSesion[p['sesion_caja_id']?.toString()];
    if (cerrada == null) continue;
    final anuladoAt = DateTime.tryParse(p['fecha_anulacion']?.toString() ?? '');
    if (anuladoAt == null || !anuladoAt.isAfter(cerrada)) continue;
    final monto = (p['monto'] as num?)?.toDouble() ?? 0;
    if (esTransferenciaCaja(p['medio_pago']?.toString())) {
      transferencia += monto;
    } else {
      efectivo += monto;
    }
  }
  return AnuladoPostCierre(
    efectivo: double.parse(efectivo.toStringAsFixed(2)),
    transferencia: double.parse(transferencia.toStringAsFixed(2)),
  );
}
