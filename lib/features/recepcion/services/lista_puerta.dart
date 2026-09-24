import '../../../core/utils/uuid_utils.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/invitado.dart';
import '../../eventos/services/salon_mesas.dart';

/// La lista de la puerta de una fiesta de alumnos, armada desde los alumnos.
///
/// El sorteo guarda la mesa en `contratos_alumnos.numero_mesa`, pero el tótem,
/// la lista del QR, la búsqueda y el operador leen `invitados`. Esto lleva cada
/// alumno —y cada acompañante con nombre— a `invitados`, con su mesa, para que
/// el día de la fiesta la puerta diga dónde sentarse.
///
/// Los ids son **fijos** por alumno y lugar (0 el alumno, 1.. sus acompañantes):
/// pasar la lista otra vez actualiza las mismas filas en vez de duplicarlas.
class FilaPuerta {
  final String id;
  final String nombre;
  final String? mesa;
  final String contratoId;
  final bool esAlumno;

  const FilaPuerta({
    required this.id,
    required this.nombre,
    required this.mesa,
    required this.contratoId,
    required this.esAlumno,
  });
}

/// Hasta cuántos acompañantes por alumno se reconocen como "de la lista":
/// alcanza de sobra (una familia son 10 lugares como mucho) y acota la
/// búsqueda de filas que quedaron de más.
const int kMaxLugaresPorAlumno = 30;

String idInvitadoPuerta(String contratoId, int lugar) =>
    UuidUtils.lineaIdDeterministic('puerta', contratoId, 'invitado', lugar);

/// Una fila por alumno activo y una por cada acompañante con nombre, todas con
/// la mesa del alumno. Los de baja no entran.
List<FilaPuerta> filasPuertaDesdeAlumnos(Iterable<ContratoAlumno> alumnos) {
  final out = <FilaPuerta>[];
  for (final a in alumnos) {
    if (a.esBajaTemporal) continue;
    final nombre = a.nombreAlumno.trim();
    if (nombre.isEmpty) continue;
    final mesa = SalonMesas.textoMesasPuerta(a);
    out.add(
      FilaPuerta(
        id: idInvitadoPuerta(a.id, 0),
        nombre: nombre,
        mesa: mesa,
        contratoId: a.id,
        esAlumno: true,
      ),
    );
    var lugar = 0;
    for (final acomp in a.nombresAcompanantes) {
      final n = acomp.trim();
      if (n.isEmpty) continue;
      lugar++;
      if (lugar >= kMaxLugaresPorAlumno) break;
      out.add(
        FilaPuerta(
          id: idInvitadoPuerta(a.id, lugar),
          nombre: n,
          mesa: mesa,
          contratoId: a.id,
          esAlumno: false,
        ),
      );
    }
  }
  return out;
}

/// Qué hay que escribir para que la puerta quede como los alumnos.
class PlanListaPuerta {
  final List<FilaPuerta> nuevas;
  final List<FilaPuerta> aActualizar;
  final int iguales;

  /// Filas que armó una pasada anterior y ya no corresponden (alumno de baja,
  /// acompañante que se sacó). **No se borran**: se informan, y si hay que
  /// sacarlas lo hace una persona desde Recepción.
  final List<Invitado> sobrantes;

  /// Los que ya ingresaron: se les puede corregir la mesa, pero su ingreso no
  /// se toca nunca.
  final int yaIngresados;

  const PlanListaPuerta({
    required this.nuevas,
    required this.aActualizar,
    required this.iguales,
    required this.sobrantes,
    required this.yaIngresados,
  });

  bool get hayCambios => nuevas.isNotEmpty || aActualizar.isNotEmpty;
  int get alumnos =>
      [...nuevas, ...aActualizar].where((f) => f.esAlumno).length;
}

/// Compara lo que debería haber con lo que hay.
///
/// Solo mira nombre y mesa. Las filas cargadas a mano o por CSV (ids que no
/// salen de [idInvitadoPuerta]) no se tocan ni se cuentan como sobrantes.
PlanListaPuerta planListaPuerta({
  required Iterable<ContratoAlumno> alumnos,
  required List<Invitado> existentes,
}) {
  final filas = filasPuertaDesdeAlumnos(alumnos);
  final porId = {for (final i in existentes) i.id: i};
  final nuevas = <FilaPuerta>[];
  final aActualizar = <FilaPuerta>[];
  var iguales = 0;
  var yaIngresados = 0;

  for (final f in filas) {
    final e = porId[f.id];
    if (e == null) {
      nuevas.add(f);
      continue;
    }
    if (e.estadoIngreso == EstadoIngreso.ingresado) yaIngresados++;
    final mesaActual = (e.numeroMesa ?? '').trim();
    if (e.nombreCompleto.trim() != f.nombre || mesaActual != (f.mesa ?? '')) {
      aActualizar.add(f);
    } else {
      iguales++;
    }
  }

  final vigentes = {for (final f in filas) f.id};
  final generables = {
    for (final a in alumnos)
      for (var lugar = 0; lugar < kMaxLugaresPorAlumno; lugar++)
        idInvitadoPuerta(a.id, lugar),
  };
  final sobrantes = [
    for (final e in existentes)
      if (generables.contains(e.id) && !vigentes.contains(e.id)) e,
  ];

  return PlanListaPuerta(
    nuevas: nuevas,
    aActualizar: aActualizar,
    iguales: iguales,
    sobrantes: sobrantes,
    yaIngresados: yaIngresados,
  );
}
