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
///
/// Desde la 6.0.0 **la lista sigue al sorteo**: se arma sola cuando el jefe
/// sortea o cambia una mesa, y se vacía sola cuando deshace el sorteo entero
/// (`puerta_al_dia.dart`). MÁS → "Pasar a la lista de la puerta" queda para
/// ponerla al día a mano.
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

/// Si se puede pasar la lista de la puerta de una fiesta de alumnos.
///
/// Estuvo en `false` hasta el 13-oct-2026, a la espera de cerrar la RLS de
/// `invitados`. Ese día el usuario decidió que **la puerta sigue al sorteo**
/// (ver [planListaPuerta]) dentro de la 6.0.0, y que la RLS se cierra en la
/// misma versión (`docs/pendientes/rls-invitados.md`). Queda la bandera para
/// poder trabarlo de nuevo en un solo lugar si hiciera falta.
const bool kListaPuertaHabilitada = true;

/// Lo que dice el menú y el aviso si [kListaPuertaHabilitada] vuelve a false.
const String kListaPuertaTrabadaLeyenda =
    'Trabado hasta cerrar los permisos de la lista de la puerta';

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

  /// Filas que armó una pasada anterior y ya no corresponden: un alumno de
  /// baja, un acompañante que se sacó, o todas si el sorteo se deshizo
  /// ([sinSorteo]). **Se sacan de la lista**: son filas que salieron de los
  /// alumnos, con su id fijo, así que siguen a los alumnos. Lo cargado a mano
  /// nunca entra acá.
  final List<Invitado> sobrantes;

  /// Los que ya ingresaron y se quedan: se les puede corregir la mesa, pero su
  /// ingreso no se toca nunca.
  final int yaIngresados;

  /// Ningún alumno activo tiene mesa: la fiesta no está sorteada, y por eso no
  /// va en la lista de la puerta.
  final bool sinSorteo;

  const PlanListaPuerta({
    required this.nuevas,
    required this.aActualizar,
    required this.iguales,
    required this.sobrantes,
    required this.yaIngresados,
    this.sinSorteo = false,
  });

  /// Nada para hacer.
  const PlanListaPuerta.nada({this.sinSorteo = false})
      : nuevas = const [],
        aActualizar = const [],
        iguales = 0,
        sobrantes = const [],
        yaIngresados = 0;

  bool get hayCambios =>
      nuevas.isNotEmpty || aActualizar.isNotEmpty || sobrantes.isNotEmpty;
  int get alumnos =>
      [...nuevas, ...aActualizar].where((f) => f.esAlumno).length;

  /// Cuántas personas quedan en la lista de la puerta con este plan aplicado.
  int get personas => nuevas.length + aActualizar.length + iguales;

  /// De los que se sacan, cuántos están marcados como adentro. Al deshacer el
  /// sorteo su ingreso se va con la fila: el aviso lo tiene que decir antes.
  int get adentroQueSeVan => sobrantes
      .where((i) => i.estadoIngreso == EstadoIngreso.ingresado)
      .length;
}

/// Lo que se le muestra al que pasa la lista a mano, antes de confirmar: un
/// renglón por cada cosa que va a pasar.
List<String> renglonesPlanPuerta(
  PlanListaPuerta plan, {
  required bool conConexion,
}) {
  final sinMesa = [...plan.nuevas, ...plan.aActualizar]
      .where((f) => f.esAlumno && f.mesa == null)
      .length;
  final adentro = plan.adentroQueSeVan;
  return [
    if (plan.nuevas.isNotEmpty)
      '• ${plan.nuevas.length} persona(s) nuevas en la lista.',
    if (plan.aActualizar.isNotEmpty)
      '• ${plan.aActualizar.length} ya estaban: se actualiza su nombre o su '
          'mesa.',
    if (plan.iguales > 0) '• ${plan.iguales} ya estaban al día.',
    if (plan.yaIngresados > 0)
      '• ${plan.yaIngresados} ya ingresaron: su ingreso no cambia.',
    if (sinMesa > 0) '• $sinMesa alumno(s) todavía sin mesa sorteada.',
    if (plan.sobrantes.isNotEmpty)
      '• ${plan.sobrantes.length} se sacan de la lista: '
          '${plan.sinSorteo ? 'ya nadie tiene mesa' : 'ya no corresponden '
              '(baja o acompañante quitado)'}.'
          '${adentro > 0 ? ' $adentro de ellos están marcados como adentro: '
              'ese ingreso se pierde.' : ''}',
    if (!conConexion)
      '• Sin conexión: no se pudo mirar lo que cargó la otra PC.',
  ];
}

/// Si la fiesta está sorteada: algún alumno activo tiene mesa.
bool hayMesasSorteadas(Iterable<ContratoAlumno> alumnos) => alumnos.any(
      (a) =>
          !a.esBajaTemporal &&
          (SalonMesas.textoMesasPuerta(a) ?? '').isNotEmpty,
    );

/// Compara lo que debería haber con lo que hay.
///
/// **La puerta sigue al sorteo.** Mientras algún alumno activo tenga mesa, la
/// lista lleva a todos los activos y a sus acompañantes con nombre. Si nadie
/// tiene mesa (no se sorteó, o se deshizo), no lleva a ninguno: lo que había
/// armado una pasada anterior pasa a [PlanListaPuerta.sobrantes].
///
/// Solo mira nombre y mesa. Las filas cargadas a mano o por CSV (ids que no
/// salen de [idInvitadoPuerta]) no se tocan ni se cuentan como sobrantes.
///
/// Con [soloDe], el plan se limita a las filas de esos alumnos (alguien les
/// cambió el nombre, la mesa o los acompañantes). Ahí **nunca vacía**: si en
/// esta PC nadie tiene mesa, no hace nada. Vaciar es cosa de deshacer el
/// sorteo, que antes mira la nube; una PC que todavía no bajó el sorteo no
/// puede sacar a una familia de la puerta por editar un teléfono.
PlanListaPuerta planListaPuerta({
  required Iterable<ContratoAlumno> alumnos,
  required List<Invitado> existentes,
  Set<String>? soloDe,
}) {
  final sorteada = hayMesasSorteadas(alumnos);
  if (soloDe != null && !sorteada) {
    return const PlanListaPuerta.nada(sinSorteo: true);
  }
  final delPlan = soloDe == null
      ? alumnos.toList()
      : [
          for (final a in alumnos)
            if (soloDe.contains(a.id)) a,
        ];
  final filas =
      sorteada ? filasPuertaDesdeAlumnos(delPlan) : const <FilaPuerta>[];
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
    for (final a in delPlan)
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
    sinSorteo: !sorteada,
  );
}
