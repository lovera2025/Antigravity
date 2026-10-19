import 'dart:io';

import '../../features/common/utils/currency_extensions.dart';
import '../database/local_database.dart';
import '../utils/ar_time.dart';

/// Cómo se enteró esta PC de que algo se borró en otra.
///
/// Queda escrito en cada renglón de `borrados_en_otra_pc.txt`: así se sabe si el
/// aviso al instante anda, o si lo está cubriendo la red de seguridad.
enum CaminoDelBorrado {
  /// El aviso al instante que manda la PC que borró (el pulso).
  aviso('por el aviso de la otra PC'),

  /// Al abrir un alumno (su estado de cuenta, su historial, la ventana de
  /// cobro) o antes de rehacer su cuenta: se le preguntó a la nube por sus
  /// pagos en ese momento.
  alumno('al abrir el alumno'),

  /// La cuenta de cada 10 segundos: en la nube había menos filas que acá.
  cuenta('porque en la nube había menos'),

  /// La revisión de cada 10 minutos, y la que corre al abrir el programa.
  revision('por la revisión de lo borrado');

  const CaminoDelBorrado(this.texto);

  final String texto;
}

/// Lo que se sacó de esta PC porque en la nube ya no estaba queda escrito en
/// `borrados_en_otra_pc.txt`, en la carpeta de la base (Documentos\Junior
/// Eventos): cada vez, la fecha, por qué camino se enteró y un renglón por cosa.
///
/// Existe por el 19-oct-2026: el jefe borró un pago de DE CARLO, MICAELA
/// ESTEFANIA en su PC y la del operario se lo quedó; al cobrarle, contó los dos
/// pagos y le pisó el saldo a la nube. Con esto, al instalar en cada PC se ve
/// qué tenía de más.
class BorradosConstancia {
  BorradosConstancia._();

  static const archivo = 'borrados_en_otra_pc.txt';

  static Future<void> anotar(
    List<String> renglones,
    CaminoDelBorrado camino,
  ) async {
    if (renglones.isEmpty) return;
    final base = File(await LocalDatabase.dbPath);
    final destino = File('${base.parent.path}${Platform.pathSeparator}$archivo');
    await destino.writeAsString(
      textoDe(renglones, ArTime.nowAr(), camino),
      mode: FileMode.append,
      flush: true,
    );
  }

  /// El bloque que se agrega al archivo, aparte para poder probarlo.
  static String textoDe(
    List<String> renglones,
    DateTime ahoraAr,
    CaminoDelBorrado camino,
  ) {
    final b = StringBuffer()
      ..writeln(
        '${_fechaYHora(ahoraAr)} · se sacó de esta PC, porque en la nube ya '
        'no estaba (${camino.texto}), ${renglones.length} cosa(s):',
      );
    for (final r in renglones) {
      b.writeln('  $r');
    }
    b.writeln();
    return b.toString();
  }
}

/// Cómo se llama cada tabla en la constancia.
const Map<String, String> _nombreDeLaTabla = {
  'pagos_contrato_alumno': 'PAGO',
  'contratos_alumnos': 'ALUMNO',
  'presupuesto_servicios': 'RENGLÓN DE PRESUPUESTO',
  'presupuestos': 'PRESUPUESTO',
  'eventos_servicios': 'SERVICIO DEL EVENTO',
  'eventos': 'EVENTO',
  'clientes': 'CLIENTE',
  'servicios': 'SERVICIO',
  'egresos': 'EGRESO',
  'transacciones': 'TRANSACCIÓN',
  'notas_operativas_contrato': 'NOTA',
  'obligaciones_pago': 'OBLIGACIÓN',
  'compromisos_personal': 'COMPROMISO DEL PERSONAL',
  'cierre_caja_anotaciones': 'ANOTACIÓN DEL CIERRE',
  'solicitudes_cotizacion': 'PEDIDO DE COTIZACIÓN',
  'prestamos_alquiler': 'ALQUILER',
  'prestamo_alquiler_lineas': 'LÍNEA DE ALQUILER',
  'pagos_prestamo_alquiler': 'PAGO DE ALQUILER',
  'operadores_caja': 'OPERADOR',
  'sesiones_caja': 'SESIÓN DE CAJA',
};

/// El renglón de la constancia para una fila que se sacó.
///
/// Un pago dice de quién era, cuánto, de qué día y por qué concepto: es lo que
/// hace falta para reconocerlo en el estado de cuenta. El resto dice qué era y
/// lo que la fila tenga para reconocerla.
String renglonDeLoBorrado(
  String tabla,
  Map<String, Object?> fila, {
  String? alumno,
}) {
  final que = _nombreDeLaTabla[tabla] ?? tabla;
  final id = (fila['id'] as String?) ?? '';
  final corto = id.length >= 8 ? id.substring(0, 8) : id;

  if (tabla == 'pagos_contrato_alumno') {
    final monto = _numero(fila['monto_gross']) ?? _numero(fila['monto']) ?? 0;
    final fecha = _fecha(fila['fecha_pago']);
    final concepto = (fila['concepto'] as String?)?.trim() ?? '';
    final quien = (alumno == null || alumno.trim().isEmpty)
        ? 'alumno ${_corto(fila['contrato_alumno_id'])}'
        : alumno.trim();
    final b = StringBuffer('$que · $quien: ${monto.toCurrency()}');
    if (fecha != null) b.write(' del $fecha');
    if (concepto.isNotEmpty) b.write(', "$concepto"');
    if (((fila['anulado'] as num?)?.toInt() ?? 0) != 0) b.write(' (anulado)');
    b.write(' [$corto]');
    return b.toString();
  }

  final partes = <String>[];
  for (final c in const [
    'nombre_alumno',
    'nombre',
    'concepto',
    'descripcion',
    'detalle_servicio',
    'texto',
  ]) {
    final v = (fila[c] as String?)?.trim() ?? '';
    if (v.isNotEmpty) {
      partes.add('"$v"');
      break;
    }
  }
  for (final c in const ['monto', 'precio_final']) {
    final v = _numero(fila[c]);
    if (v != null) {
      partes.add(v.toCurrency());
      break;
    }
  }
  final cantidad = _numero(fila['cantidad']);
  if (cantidad != null) partes.add('cantidad ${_sinCeros(cantidad)}');
  for (final c in const ['presupuesto_id', 'evento_id', 'contrato_alumno_id']) {
    final v = fila[c];
    if (v is String && v.isNotEmpty) {
      partes.add('${c.replaceAll('_id', '')} ${_corto(v)}');
      break;
    }
  }
  final fecha = _fecha(fila['fecha']) ?? _fecha(fila['created_at']);
  if (fecha != null) partes.add('del $fecha');

  return partes.isEmpty ? '$que [$corto]' : '$que · ${partes.join(', ')} [$corto]';
}

double? _numero(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String _sinCeros(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

String _corto(Object? v) {
  final s = v?.toString() ?? '';
  return s.length >= 8 ? s.substring(0, 8) : s;
}

String _dos(int n) => n.toString().padLeft(2, '0');

String? _fecha(Object? crudo) {
  if (crudo == null) return null;
  final f = DateTime.tryParse(crudo.toString());
  if (f == null) return null;
  final ar = ArTime.toAr(f);
  return '${_dos(ar.day)}/${_dos(ar.month)}/${ar.year}';
}

String _fechaYHora(DateTime ar) =>
    '${_dos(ar.day)}/${_dos(ar.month)}/${ar.year} '
    '${_dos(ar.hour)}:${_dos(ar.minute)}';
