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
}
