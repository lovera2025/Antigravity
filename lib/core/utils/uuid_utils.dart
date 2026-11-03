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

  /// PK estable para `planos_evento`: una fila por fiesta. Las dos PCs escriben
  /// la misma fila; si fueran dos ids, la nube rechazaría la segunda por el
  /// `unique (evento_id)` y la subida quedaría trabada.
  static String planoEventoId(String eventoId) =>
      _uuidDe('planos_evento_v1|$eventoId');

  /// PK estable para `mora_congelada` (6.2.1): una fila por alumno. Si las dos
  /// PCs congelan al mismo alumno, escriben la misma fila (gana la última).
  static String moraCongeladaId(String contratoAlumnoId) =>
      _uuidDe('mora_congelada_v1|$contratoAlumnoId');

  /// PK estable para `permisos_operador` (v76): una fila por operador. Si el jefe
  /// los cambia desde dos PCs, escriben la misma fila (gana la última).
  static String permisosOperadorId(String operadorId) =>
      _uuidDe('permisos_operador_v1|$operadorId');

  /// PK de un renglón de `permisos_operador_cambios`: un permiso de un operador en
  /// un momento. Si la subida se reintenta, no se duplica.
  static String cambioDePermisoId(
    String operadorId,
    String permiso,
    String momento,
  ) =>
      _uuidDe('permisos_operador_cambios_v1|$operadorId|$permiso|$momento');

  /// PK estable para `barra_precios` (v77): un producto en una fiesta. Si el jefe
  /// le pone precio desde dos PCs, escriben la misma fila (gana la última).
  static String barraPrecioId(String eventoId, String productoId) =>
      _uuidDe('barra_precios_v1|$eventoId|$productoId');

  /// PK estable para `barra_anulaciones` (v77): una por venta. Anular dos veces la
  /// misma venta, desde la PC y desde la web, deja una sola anulación.
  static String barraAnulacionId(String ventaId) =>
      _uuidDe('barra_anulaciones_v1|$ventaId');

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
