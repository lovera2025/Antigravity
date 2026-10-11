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

  /// Cuando se deshizo solo a los últimos sorteados: lo que conservó cada
  /// familia que no quedó sin mesa. Restaurar le devuelve lo de [numeros] solo
  /// si sigue teniendo exactamente esto.
  final Map<String, String> quedaron;

  const RespaldoSorteo({
    required this.fecha,
    required this.numeros,
    this.bloques = const [],
    this.quedaron = const {},
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
    Map<String, String> quedaron = const {},
  }) async {
    final archivo = await _archivo(eventoId);
    await archivo.writeAsString(
      jsonEncode(
        aJson(DateTime.now(), numeros, bloques: bloques, quedaron: quedaron),
      ),
      flush: true,
    );
  }

  /// Lo que se escribe en el archivo de la copia.
  static Map<String, dynamic> aJson(
    DateTime fecha,
    Map<String, String> numeros, {
    List<BloqueDivision> bloques = const [],
    Map<String, String> quedaron = const {},
  }) =>
      {
        'fecha': fecha.toUtc().toIso8601String(),
        'numeros': numeros,
        if (bloques.isNotEmpty) 'bloques': [for (final b in bloques) b.toMap()],
        if (quedaron.isNotEmpty) 'quedaron': quedaron,
      };

  /// Lee una copia. Null si está vacía o no se entiende. Una copia de antes
  /// de los bloques o del deshacer parcial (sin esas claves) se lee igual.
  static RespaldoSorteo? deJson(Object? json) {
    try {
      if (json is! Map) return null;
      final numeros = Map<String, String>.from(json['numeros'] as Map);
      if (numeros.isEmpty) return null;
      final crudos = json['bloques'];
      final quedaron = json['quedaron'];
      return RespaldoSorteo(
        fecha: DateTime.parse(json['fecha'] as String),
        numeros: numeros,
        quedaron: quedaron is Map
            ? {
                for (final e in quedaron.entries)
                  e.key.toString(): e.value?.toString() ?? '',
              }
            : const {},
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

  /// Devuelve cada número solo a quien sigue como lo dejó el deshacer —sin
  /// mesa, o con las que conservó si se deshizo solo a los últimos—, y nunca a
  /// un número que hoy esté ocupado o que aparezca dos veces en la copia.
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
      final hoy = MesasExtraUtils.numerosMesaDesdeTexto(alumno?.numeroMesa);
      final conservo =
          MesasExtraUtils.numerosMesaDesdeTexto(respaldo.quedaron[e.key]);
      final sigueIgual = alumno != null &&
          (conservo.isEmpty
              ? (alumno.numeroMesa?.trim().isEmpty ?? true)
              : hoy.length == conservo.length && hoy.containsAll(conservo));
      // Las que conservó ya son suyas: lo que tiene que estar libre es el resto.
      final vuelven = numeros.difference(hoy);
      final libre = sigueIgual &&
          vuelven.isNotEmpty &&
          vuelven.every((n) => !ocupadas.contains(n));
      if (!libre) {
        omitidos++;
        continue;
      }
      ocupadas.addAll(vuelven);
      aRestaurar[e.key] = e.value;
    }
    return PlanRestauracion(aRestaurar: aRestaurar, omitidos: omitidos);
  }
}
