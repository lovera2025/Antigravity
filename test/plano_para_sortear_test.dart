// Antes de sortear se lee el plano de la fiesta. Lo que pase ahí decide si el
// sorteo se hace sobre el plano, como siempre, o si no se hace.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
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
      expect(r.problemaParaSortear, r.problema);
    }
  });

  // 6.1.0, "el salón primero": el jefe arma el espacio y después pone las
  // mesas. Mientras tanto no hay a qué mesas sortear.
  group('el salón vacío', () {
    PlanoEvento vacio() => PlanoEvento.nuevo(
          eventoId: 'e0000000-0000-4000-8000-000000000001',
          armado: ArmarAMedida.vacio(PlayonReal.costaSurubi),
          estilo: EstiloPlano.gala,
          modo: ModoSorteo.bloques,
          ahora: ahora,
        );

    test('se lee, pero no se sortea: primero las mesas', () async {
      final r =
          await leerPlanoParaSortear(deLaNube: () async => vacio(), deEstaPc: ninguno);
      // Se lee bien: deshacer o mirar el plano no se frena.
      expect(r.sePuedeSeguir, isTrue);
      expect(r.plano!.armado.mesas, isEmpty);
      expect(
        r.problemaParaSortear,
        'El salón de esta fiesta todavía no tiene mesas. Abrí PLANO y ponelas '
        'en Personalizar → Acomodar antes de sortear.',
      );
    });

    // La pantalla de la fiesta no se puede montar en un test (son casi 10.000
    // líneas): se lee su código. El SORTEO pregunta antes de abrir el diálogo
    // y otra vez con el plano recién leído, y las dos veces tiene que mirar
    // también el salón vacío.
    test('el SORTEO de la fiesta frena con el salón vacío, las dos veces', () {
      final codigo = File(
        'lib/features/eventos/detalle_evento_masivo_screen.dart',
      ).readAsStringSync();
      expect('problemaParaSortear'.allMatches(codigo).length, 2);
      expect(codigo, isNot(contains('sePuedeSeguir')));
    });

    test('con mesas, o sin plano, se sortea', () async {
      final conMesas =
          await leerPlanoParaSortear(deLaNube: () async => plano(), deEstaPc: ninguno);
      expect(conMesas.problemaParaSortear, isNull);
      final sinPlano =
          await leerPlanoParaSortear(deLaNube: ninguno, deEstaPc: ninguno);
      expect(sinPlano.problemaParaSortear, isNull);
    });
  });
}
