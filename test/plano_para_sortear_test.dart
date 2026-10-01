// Antes de sortear se lee el plano de la fiesta. Lo que pase ahí decide si el
// sorteo se hace sobre el plano, como siempre, o si no se hace.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/services/plano_para_sortear.dart';
import 'package:arguello_events/models/plano_evento.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 1);
  PlanoEvento plano({ConfigPlano config = ConfigPlano.vacia}) =>
      PlanoEvento.nuevo(
        eventoId: 'e0000000-0000-4000-8000-000000000001',
        armado: ArmadosPredefinidos.normal2aPagina3(),
        estilo: EstiloPlano.gala,
        modo: ModoSorteo.bloques,
        ahora: ahora,
      ).copyWith(config: config, ahora: ahora);
  PlanoEvento roto() =>
      PlanoEvento.fromMap(plano().toMap()..['armado_json'] = '{roto');

  Future<PlanoEvento?> ninguno() async => null;
  Future<PlanoEvento?> falla() async => throw StateError('no such table');

  test('la nube manda: si la otra PC fijó una mesa, se sortea con eso', () async {
    final deLaNube = plano(
      config: const ConfigPlano(fijadas: {5: MesaFijada(alumnoId: 'a')}),
    );
    final r = await leerPlanoParaSortear(
      deLaNube: () async => deLaNube,
      deEstaPc: () async => plano(),
    );
    expect(r.sePuedeSeguir, isTrue);
    expect(r.plano!.config.fijadas.keys, {5});
  });

  test('sin red, vale el de esta PC', () async {
    final r = await leerPlanoParaSortear(
      deLaNube: () async => throw Exception('sin conexión'),
      deEstaPc: () async => plano(),
    );
    expect(r.sePuedeSeguir, isTrue);
    expect(r.plano, isNotNull);
  });

  test('si ya se sabe que no hay red, ni se le pregunta a la nube', () async {
    var preguntas = 0;
    final r = await leerPlanoParaSortear(
      deLaNube: () async {
        preguntas++;
        return plano();
      },
      deEstaPc: ninguno,
      consultarNube: false,
    );
    expect(preguntas, 0);
    expect(r.plano, isNull);
    expect(r.sePuedeSeguir, isTrue);
  });

  test('la nube no lo tiene todavía y esta PC sí (sin subir): vale el de acá',
      () async {
    final r = await leerPlanoParaSortear(
      deLaNube: ninguno,
      deEstaPc: () async => plano(),
    );
    expect(r.plano, isNotNull);
  });

  test('una fiesta sin plano: el sorteo de siempre', () async {
    final r = await leerPlanoParaSortear(deLaNube: ninguno, deEstaPc: ninguno);
    expect(r.plano, isNull);
    expect(r.sePuedeSeguir, isTrue);
  });

  test('la tabla de esta PC no se puede leer, pero la nube dice que no hay '
      'plano: se sortea como siempre', () async {
    // Sin esto, una PC con la tabla sin crear no podía sortear ninguna fiesta.
    final r = await leerPlanoParaSortear(deLaNube: ninguno, deEstaPc: falla);
    expect(r.plano, isNull);
    expect(r.sePuedeSeguir, isTrue);
  });

  test('no se puede saber si hay plano (ni la nube ni esta PC): no se sortea',
      () async {
    final sinRed = await leerPlanoParaSortear(
      deLaNube: () async => throw Exception('sin conexión'),
      deEstaPc: falla,
    );
    expect(sinRed.sePuedeSeguir, isFalse);
    expect(sinRed.problema, contains('No se pudo leer el plano'));

    final sinPreguntar = await leerPlanoParaSortear(
      deLaNube: ninguno,
      deEstaPc: falla,
      consultarNube: false,
    );
    expect(sinPreguntar.sePuedeSeguir, isFalse);
  });

  test('un plano con el armado ilegible no es "sin plano": no se sortea',
      () async {
    for (final r in [
      await leerPlanoParaSortear(deLaNube: () async => roto(), deEstaPc: ninguno),
      await leerPlanoParaSortear(
        deLaNube: () async => throw Exception('sin conexión'),
        deEstaPc: () async => roto(),
      ),
    ]) {
      expect(r.sePuedeSeguir, isFalse);
      expect(r.plano, isNull);
      expect(r.problema, contains('elegí el armado de nuevo'));
    }
  });
}
