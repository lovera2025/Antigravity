import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class UuidUtils {
  static const _uuid = Uuid();

  /// Genera un UUID v4 estándar.
  static String generate() {
    return _uuid.v4();
  }

  /// Identificador de **línea** estable e idempotente para sincronizar filas
  /// que en la nube aún no tienen columna `id` (PK compuesta antigua).
  /// Mismo contexto + padre + servicio + orden en lista remota → mismo UUID local.
  static String lineaIdDeterministic(
    String contexto,
    String parentId,
    String servicioId,
    int ordinal,
  ) {
    final h = sha256.convert(utf8.encode('$contexto|$parentId|$servicioId|$ordinal'));
    final u = List<int>.from(h.bytes.sublist(0, 16));
    u[6] = (u[6] & 0x0f) | 0x40;
    u[8] = (u[8] & 0x3f) | 0x80;
    String hx(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${hx(u[0])}${hx(u[1])}${hx(u[2])}${hx(u[3])}-'
        '${hx(u[4])}${hx(u[5])}-'
        '${hx(u[6])}${hx(u[7])}-'
        '${hx(u[8])}${hx(u[9])}-'
        '${hx(u[10])}${hx(u[11])}${hx(u[12])}${hx(u[13])}${hx(u[14])}${hx(u[15])}';
  }

  /// PK estable para `cierre_caja_anotaciones`: una fila por día + turno.
  static String cierreCajaAnotacionId(String fechaIso, String turnoSlug) {
    final h = sha256.convert(
      utf8.encode('cierre_caja_anotacion_v1|$fechaIso|$turnoSlug'),
    );
    final u = List<int>.from(h.bytes.sublist(0, 16));
    u[6] = (u[6] & 0x0f) | 0x40;
    u[8] = (u[8] & 0x3f) | 0x80;
    String hx(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${hx(u[0])}${hx(u[1])}${hx(u[2])}${hx(u[3])}-'
        '${hx(u[4])}${hx(u[5])}-'
        '${hx(u[6])}${hx(u[7])}-'
        '${hx(u[8])}${hx(u[9])}-'
        '${hx(u[10])}${hx(u[11])}${hx(u[12])}${hx(u[13])}${hx(u[14])}${hx(u[15])}';
  }

  /// PK estable para `notas_operativas_contrato`: una fila por contrato, mismo UUID en todos los equipos.
  static String notaOperativaContratoId(String contratoAlumnoId) {
    final h = sha256.convert(
      utf8.encode('nota_operativa_contrato_v1|$contratoAlumnoId'),
    );
    final u = List<int>.from(h.bytes.sublist(0, 16));
    u[6] = (u[6] & 0x0f) | 0x40;
    u[8] = (u[8] & 0x3f) | 0x80;
    String hx(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${hx(u[0])}${hx(u[1])}${hx(u[2])}${hx(u[3])}-'
        '${hx(u[4])}${hx(u[5])}-'
        '${hx(u[6])}${hx(u[7])}-'
        '${hx(u[8])}${hx(u[9])}-'
        '${hx(u[10])}${hx(u[11])}${hx(u[12])}${hx(u[13])}${hx(u[14])}${hx(u[15])}';
  }

  /// PK estable para `sillas_reparto`: una fila por alumno, el mismo UUID en
  /// las dos PCs. Si las dos eligen a la vez, pisan la misma fila en vez de
  /// dejar dos repartos para el mismo alumno.
  static String sillasRepartoId(String contratoAlumnoId) =>
      _uuidDe('sillas_reparto_v1|$contratoAlumnoId');

  /// PK estable para `entradas_retiro`: una fila por alumno. Es lo que hace
  /// que un egresado no pueda tener dos retiros: las dos PCs escriben la misma.
  static String entradasRetiroId(String contratoAlumnoId) =>
      _uuidDe('entradas_retiro_v1|$contratoAlumnoId');

  static String _uuidDe(String semilla) {
    final h = sha256.convert(utf8.encode(semilla));
    final u = List<int>.from(h.bytes.sublist(0, 16));
    u[6] = (u[6] & 0x0f) | 0x40;
    u[8] = (u[8] & 0x3f) | 0x80;
    String hx(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${hx(u[0])}${hx(u[1])}${hx(u[2])}${hx(u[3])}-'
        '${hx(u[4])}${hx(u[5])}-'
        '${hx(u[6])}${hx(u[7])}-'
        '${hx(u[8])}${hx(u[9])}-'
        '${hx(u[10])}${hx(u[11])}${hx(u[12])}${hx(u[13])}${hx(u[14])}${hx(u[15])}';
  }
}
