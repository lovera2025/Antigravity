// La base de la notebook central, en memoria: las filas de la puerta y lo que
// se le pidió. La usan `test/central_puerta_test.dart` y
// `test/cliente_central_test.dart`.
import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/invitado.dart';

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

  /// La lista como la armaría Recepción con estas filas.
  PuertaDelEvento lista() => PuertaDelEvento.particular(filas.values.toList());
}
