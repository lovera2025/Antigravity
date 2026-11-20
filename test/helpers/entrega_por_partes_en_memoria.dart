// La entrega en dos partes (`EntregarParte`) sin base ni nube: cada equipo con
// su "base" en memoria y su cola, y una nube de mentira compartida que hace lo
// mismo que la de verdad: los renglones se suman, y la fila de
// `entradas_retiro` se pisa entera con la última que sube (un upsert ciego).
//
// Bajar trae lo de la nube como la bajada de verdad: los renglones que faltan,
// y la fila solo si este equipo no tiene un cambio suyo esperando subir.
import 'package:arguello_events/features/eventos/services/entregar_parte.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

/// La hora de todos los equipos de una prueba: cada vez que alguien la pide,
/// avanza un minuto (así cada cosa tiene su hora y el orden es el de la prueba).
class RelojDeLaEntrega {
  RelojDeLaEntrega([DateTime? desde])
      : _ahora = desde ?? DateTime.utc(2026, 11, 20, 13);

  DateTime _ahora;

  DateTime ahora() => _ahora = _ahora.add(const Duration(minutes: 1));
}

/// El reloj de **un** equipo, que dice la [hora] que se le ponga: para probar
/// equipos con la hora corrida (una tablet atrasada unos minutos).
class RelojCorrido extends RelojDeLaEntrega {
  RelojCorrido(this.hora);

  DateTime hora;

  @override
  DateTime ahora() => hora;
}

class NubeDeEntregas {
  /// La fila de cada alumno.
  final retiros = <String, EntradasRetiro>{};

  /// Los renglones, por id.
  final renglones = <String, EntregaEntradas>{};

  /// Cuántas veces subió una fila de `entradas_retiro`.
  int filasSubidas = 0;

  List<EntregaEntradas> renglonesDe(String alumnoId) => [
        for (final r in renglones.values)
          if (r.contratoAlumnoId == alumnoId) r,
      ]..sort(EntregaEntradas.enOrden);
}

class EquipoDeEntrega implements PuertosDeLaEntrega {
  EquipoDeEntrega({
    required this.nombre,
    required this.nube,
    required this.reloj,
    required this.alumnos,
    Map<String, List<Map<String, dynamic>>>? pagos,
  }) : pagos = pagos ?? {};

  final String nombre;
  final NubeDeEntregas nube;

  /// Se puede cambiar a mitad de la prueba: un equipo con la hora corrida.
  RelojDeLaEntrega reloj;

  /// Si está, corre apenas termina de subir: lo que otro equipo anotó en ese
  /// mismo momento y baja enseguida.
  void Function()? alTerminarDeSubir;

  /// Los alumnos de la fiesta tal como los ve este equipo (se pueden cambiar
  /// a mitad de la prueba: "cambió la cuenta").
  List<ContratoAlumno> alumnos;
  final Map<String, List<Map<String, dynamic>>> pagos;

  @override
  bool hayInternet = true;

  final retiros = <String, EntradasRetiro>{};
  final renglones = <String, EntregaEntradas>{};

  /// Lo que espera subir: ids de renglones, y alumnos cuya fila cambió.
  final colaDeRenglones = <String>{};
  final colaDeFilas = <String>{};

  /// Cuántas veces este equipo escribió una fila de `entradas_retiro`.
  int filasEscritas = 0;

  /// Cuántas veces se le preguntó a la nube.
  int consultasALaNube = 0;

  List<EntregaEntradas> renglonesDe(String alumnoId) => [
        for (final r in renglones.values)
          if (r.contratoAlumnoId == alumnoId) r,
      ]..sort(EntregaEntradas.enOrden);

  @override
  Future<LoDeLaNube> deLaNube(String contratoAlumnoId) async {
    if (!hayInternet) throw StateError('sin internet');
    consultasALaNube++;
    final deLaNube = nube.renglonesDe(contratoAlumnoId);
    for (final r in deLaNube) {
      renglones.putIfAbsent(r.id, () => r);
    }
    final fila = nube.retiros[contratoAlumnoId];
    if (fila != null && !colaDeFilas.contains(contratoAlumnoId)) {
      retiros[contratoAlumnoId] = fila;
    }
    return LoDeLaNube(retiro: fila, renglones: deLaNube);
  }

  @override
  Future<LoDeLaFiesta> leer(String eventoId) async => LoDeLaFiesta(
        alumnos: [for (final a in alumnos) if (a.eventoId == eventoId) a],
        retiros: Map.of(retiros),
        renglones: renglones.values.toList(),
      );

  @override
  Future<CuentaDelAlumno> cuentaDe(ContratoAlumno alumno) async =>
      CuentaDelAlumno(pagos: pagos[alumno.id] ?? const [], moraCobradaHistorial: 0);

  @override
  Future<void> guardar(
    List<EntregaEntradas> nuevos, {
    EntradasRetiro? retiro,
  }) async {
    for (final r in nuevos) {
      if (renglones.containsKey(r.id)) continue;
      renglones[r.id] = r;
      colaDeRenglones.add(r.id);
    }
    if (retiro != null) {
      retiros[retiro.contratoAlumnoId] = retiro;
      colaDeFilas.add(retiro.contratoAlumnoId);
      filasEscritas++;
    }
  }

  @override
  Future<bool> subir({
    required List<String> renglones,
    String? retiro,
    required DateTime desde,
  }) async {
    subirLaCola();
    final subio = colaDeRenglones.isEmpty && colaDeFilas.isEmpty;
    alTerminarDeSubir?.call();
    return subio;
  }

  /// Sube todo lo que espera, si hay internet (lo que hace el motor cuando
  /// vuelve la red).
  void subirLaCola() {
    if (!hayInternet) return;
    for (final id in colaDeRenglones) {
      nube.renglones.putIfAbsent(id, () => renglones[id]!);
    }
    colaDeRenglones.clear();
    for (final alumnoId in colaDeFilas) {
      nube.retiros[alumnoId] = retiros[alumnoId]!;
      nube.filasSubidas++;
    }
    colaDeFilas.clear();
  }

  /// La bajada: los renglones que faltan, y cada fila salvo la que este equipo
  /// tiene esperando subir.
  void bajar() {
    if (!hayInternet) return;
    for (final r in nube.renglones.values) {
      renglones.putIfAbsent(r.id, () => r);
    }
    nube.retiros.forEach((alumnoId, fila) {
      if (!colaDeFilas.contains(alumnoId)) retiros[alumnoId] = fila;
    });
  }

  @override
  Future<String?> equipo() async => nombre;

  @override
  DateTime ahora() => reloj.ahora();
}
