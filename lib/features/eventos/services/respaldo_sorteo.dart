import 'dart:convert';
import 'dart:io';

import '../../../core/database/local_database.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import 'mesas_extra_utils.dart';

/// Qué se puede devolver de una copia sin pisar nada de lo que hay hoy.
class PlanRestauracion {
  /// Alumno → su número de antes.
  final Map<String, String> aRestaurar;

  /// Alumnos de la copia que no se restauran: ya tienen mesa, su número está
  /// ocupado, o ya no están en el evento.
  final int omitidos;

  const PlanRestauracion({required this.aRestaurar, required this.omitidos});
}

/// Copia local de los números de mesa de un evento. Se guarda justo antes de
/// deshacer el sorteo, así un deshacer por error —después de avisarle las
/// mesas a las familias— tiene vuelta atrás.
///
/// Vive al lado de la base (`Documentos/Junior Eventos/respaldos_sorteo/`),
/// una por evento: la de cada deshacer reemplaza a la anterior.
class RespaldoSorteo {
  final DateTime fecha;

  /// Alumno → número de mesa, tal como estaba guardado.
  final Map<String, String> numeros;

  /// Con plano: los bloques de división del sorteo que se deshizo. Deshacer
  /// los borra del plano (el próximo sorteo los arma de nuevo), así que sin
  /// esto Restaurar devolvía los números pero no los bloques, y los que
  /// llegaban tarde ya no iban al bloque de su división.
  final List<BloqueDivision> bloques;

  const RespaldoSorteo({
    required this.fecha,
    required this.numeros,
    this.bloques = const [],
  });

  static Future<File> _archivo(String eventoId) async {
    final base = File(await LocalDatabase.dbPath).parent.path;
    final dir = Directory('$base${Platform.pathSeparator}respaldos_sorteo');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$eventoId.json');
  }

  /// Guarda la copia. Si falla, tira: quien deshace no tiene que borrar nada
  /// sin la copia a salvo.
  static Future<void> guardar(
    String eventoId,
    Map<String, String> numeros, {
    List<BloqueDivision> bloques = const [],
  }) async {
    final archivo = await _archivo(eventoId);
    await archivo.writeAsString(
      jsonEncode(aJson(DateTime.now(), numeros, bloques: bloques)),
      flush: true,
    );
  }

  /// Lo que se escribe en el archivo de la copia.
  static Map<String, dynamic> aJson(
    DateTime fecha,
    Map<String, String> numeros, {
    List<BloqueDivision> bloques = const [],
  }) =>
      {
        'fecha': fecha.toUtc().toIso8601String(),
        'numeros': numeros,
        if (bloques.isNotEmpty) 'bloques': [for (final b in bloques) b.toMap()],
      };

  /// Lee una copia. Null si está vacía o no se entiende. Una copia de antes
  /// de los bloques (sin esa clave) se lee igual, sin bloques.
  static RespaldoSorteo? deJson(Object? json) {
    try {
      if (json is! Map) return null;
      final numeros = Map<String, String>.from(json['numeros'] as Map);
      if (numeros.isEmpty) return null;
      final crudos = json['bloques'];
      return RespaldoSorteo(
        fecha: DateTime.parse(json['fecha'] as String),
        numeros: numeros,
        bloques: [
          for (final b in crudos is List ? crudos : const [])
            ?BloqueDivision.fromMap(b),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static Future<RespaldoSorteo?> leer(String eventoId) async {
    try {
      final archivo = await _archivo(eventoId);
      if (!await archivo.exists()) return null;
      return deJson(jsonDecode(await archivo.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// Los bloques que hay que reponer en el plano al restaurar: los de la copia,
  /// solo si el plano de hoy no tiene (si alguien ya volvió a sortear por
  /// bloques, mandan los nuevos). Null si no hay nada que reponer.
  static List<BloqueDivision>? bloquesARestaurar(
    RespaldoSorteo respaldo,
    PlanoEvento? planoHoy,
  ) {
    if (planoHoy == null) return null;
    if (respaldo.bloques.isEmpty) return null;
    if (planoHoy.config.bloques.isNotEmpty) return null;
    return respaldo.bloques;
  }

  /// Devuelve cada número solo a quien sigue sin mesa, y nunca a un número
  /// que hoy esté ocupado o que aparezca dos veces en la copia.
  static PlanRestauracion planRestauracion(
    RespaldoSorteo respaldo,
    Iterable<ContratoAlumno> alumnosHoy,
  ) {
    final porId = {for (final a in alumnosHoy) a.id: a};
    final ocupadas = {
      for (final a in alumnosHoy)
        ...MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa),
    };
    final aRestaurar = <String, String>{};
    var omitidos = 0;
    for (final e in respaldo.numeros.entries) {
      final alumno = porId[e.key];
      final numeros = MesasExtraUtils.numerosMesaDesdeTexto(e.value);
      final libre = alumno != null &&
          (alumno.numeroMesa?.trim().isEmpty ?? true) &&
          numeros.isNotEmpty &&
          numeros.every((n) => !ocupadas.contains(n));
      if (!libre) {
        omitidos++;
        continue;
      }
      ocupadas.addAll(numeros);
      aRestaurar[e.key] = e.value;
    }
    return PlanRestauracion(aRestaurar: aRestaurar, omitidos: omitidos);
  }
}
