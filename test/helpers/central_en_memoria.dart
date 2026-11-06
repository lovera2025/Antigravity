// La base de la notebook central, en memoria: las filas de la puerta y lo que
// se le pidió. La usan `test/central_puerta_test.dart` y
// `test/cliente_central_test.dart`.
import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/totem/services/tiempos_a_mano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/silla_puerta.dart';

const eventoDeLaCentral = 'e0000000-0000-4000-8000-00000000000b';
final horaDeLaCentral = DateTime.utc(2026, 12, 13, 1, 41);

Invitado filaDePrueba(String id, String nombre, {bool adentro = false}) =>
    Invitado(
      id: id,
      eventoId: eventoDeLaCentral,
      nombreCompleto: nombre,
      dni: '',
      estadoIngreso:
          adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
      updatedAt: adentro ? horaDeLaCentral : null,
    );

class PcEnMemoria implements PuertaDeEstaPc {
  final filas = <String, Invitado>{};

  /// Cada ingreso, con si se saludó en el tótem.
  final ingresos = <(String, bool)>[];
  final deshechos = <String>[];
  var falla = false;

  /// Cuánto tarda en marcar: para que dos pedidos se crucen.
  var demora = Duration.zero;

  /// Se llama después de cada cambio, como la base que avisa a Recepción.
  void Function()? alCambiar;

  @override
  Future<Invitado?> fila(String id) async => filas[id];

  @override
  Future<void> ingresar(
    String eventoId,
    PersonaPuerta persona, {
    required bool saludar,
  }) async {
    await Future<void>.delayed(demora);
    if (falla) throw StateError('la base no anda');
    ingresos.add((persona.id, saludar));
    filas[persona.id] = filaDePrueba(persona.id, persona.nombre, adentro: true);
    alCambiar?.call();
  }

  @override
  Future<void> deshacer(String id) async {
    await Future<void>.delayed(demora);
    if (falla) throw StateError('la base no anda');
    deshechos.add(id);
    filas[id] = filaDePrueba(id, filas[id]!.nombreCompleto);
    alCambiar?.call();
  }

  /// Los alumnos de un masivo: si hay, la lista se arma desde ellos, con las
  /// sillas de la noche.
  final alumnos = <ContratoAlumno>[];

  /// Las sillas de la noche en la base.
  final sillas = <SillaPuerta>[];

  /// Los segundos del tótem que se pusieron.
  final tiempos = <TiemposAMano>[];

  @override
  Future<List<SillaPuerta>> sillasDelEvento(String eventoId) async =>
      [for (final s in sillas) if (s.eventoId == eventoId) s];

  @override
  Future<void> sumarSilla({
    required String eventoId,
    required String contratoId,
    required int mesa,
    required String vale,
    required String anotadoPor,
    String? nota,
  }) async {
    await Future<void>.delayed(demora);
    if (falla) throw StateError('la base no anda');
    sillas.add(SillaPuerta(
      id: 'silla-${sillas.length + 1}',
      eventoId: eventoId,
      contratoAlumnoId: contratoId,
      mesa: mesa,
      vale: vale,
      anotadoPor: anotadoPor,
      nota: nota,
      createdAt: horaDeLaCentral.add(Duration(minutes: sillas.length)),
      updatedAt: horaDeLaCentral.add(Duration(minutes: sillas.length)),
    ));
    alCambiar?.call();
  }

  @override
  Future<void> quitarSilla(
    String sillaId, {
    required String por,
    required String motivo,
  }) async {
    await Future<void>.delayed(demora);
    if (falla) throw StateError('la base no anda');
    final i = sillas.indexWhere((s) => s.id == sillaId);
    sillas[i] = sillas[i].quitada(por: por, motivo: motivo, ahora: horaDeLaCentral);
    alCambiar?.call();
  }

  @override
  Future<void> ponerTiempos(String eventoId, TiemposAMano t) async {
    tiempos.add(t);
  }

  /// La lista como la armaría Recepción con estas filas.
  PuertaDelEvento lista() => alumnos.isEmpty
      ? PuertaDelEvento.particular(filas.values.toList())
      : PuertaDelEvento.masivo(
          alumnos: alumnos,
          invitados: filas.values.toList(),
          sillasPuerta: sillas,
        );
}
