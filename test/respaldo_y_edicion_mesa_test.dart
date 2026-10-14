import 'package:arguello_events/features/eventos/services/respaldo_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/modal_alumno_premium.dart';
import 'dart:convert';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ContratoAlumno alumno(String id, {String? mesa}) => ContratoAlumno(
      id: id,
      eventoId: 'e1',
      nombreAlumno: id,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 100000,
      numeroMesa: mesa,
    );

void main() {
  group('la copia del sorteo guarda también los bloques', () {
    const bloques = [BloqueDivision('5A', 1, 24), BloqueDivision('5B', 25, 49)];
    final fecha = DateTime.utc(2026, 11, 10, 20);

    PlanoEvento plano({List<BloqueDivision> conBloques = const []}) =>
        PlanoEvento.nuevo(
          eventoId: 'e1',
          armado: ArmadosPredefinidos.normal2aPaginas45(),
          estilo: EstiloPlano.gala,
          modo: ModoSorteo.bloques,
          ahora: fecha,
        ).copyWith(config: ConfigPlano(bloques: conBloques), ahora: fecha);

    test('ida y vuelta por el archivo', () {
      final json = jsonDecode(
        jsonEncode(
          RespaldoSorteo.aJson(fecha, const {'a': '1, 2'}, bloques: bloques),
        ),
      );
      final r = RespaldoSorteo.deJson(json)!;
      expect(r.fecha, fecha);
      expect(r.numeros, {'a': '1, 2'});
      expect(
        [for (final b in r.bloques) (b.division, b.desde, b.hasta)],
        [('5A', 1, 24), ('5B', 25, 49)],
      );
    });

    test('una copia de antes de los bloques se lee igual, sin bloques', () {
      final r = RespaldoSorteo.deJson({
        'fecha': fecha.toIso8601String(),
        'numeros': {'a': '3'},
      })!;
      expect(r.numeros, {'a': '3'});
      expect(r.bloques, isEmpty);
    });

    test('una copia vacía o rota no sirve', () {
      expect(RespaldoSorteo.deJson(null), isNull);
      expect(RespaldoSorteo.deJson('texto'), isNull);
      expect(
        RespaldoSorteo.deJson({'fecha': fecha.toIso8601String(), 'numeros': {}}),
        isNull,
      );
      // Bloques ilegibles no rompen la copia: se pierden solo ellos.
      final r = RespaldoSorteo.deJson({
        'fecha': fecha.toIso8601String(),
        'numeros': {'a': '3'},
        'bloques': [
          7,
          {'division': '5A'},
          {'division': '5B', 'desde': 1, 'hasta': 9},
        ],
      })!;
      expect(r.bloques.single.division, '5B');
    });

    test('al restaurar vuelven los bloques, si el plano de hoy no tiene', () {
      // Deshacer los borra del plano; sin esto, los que llegan tarde ya no iban
      // al bloque de su división.
      final r = RespaldoSorteo(
        fecha: fecha,
        numeros: const {'a': '1'},
        bloques: bloques,
      );
      expect(RespaldoSorteo.bloquesARestaurar(r, plano()), bloques);
    });

    test('la copia guarda las mesas de cada bloque, una por una', () {
      final conLista = [
        BloqueDivision.deMesas('6C', [151, 131, 132]),
      ];
      final r = RespaldoSorteo.deJson(
        jsonDecode(
          jsonEncode(
            RespaldoSorteo.aJson(fecha, const {'a': '151'}, bloques: conLista),
          ),
        ),
      )!;
      expect(r.bloques.single.mesas, [151, 131, 132]);
      expect(r.bloques.single.contiene(140), isFalse);
    });

    test('no se pisan los bloques de un sorteo que se volvió a hacer', () {
      final r = RespaldoSorteo(
        fecha: fecha,
        numeros: const {'a': '1'},
        bloques: bloques,
      );
      final nuevo = plano(conBloques: const [BloqueDivision('5B', 1, 25)]);
      expect(RespaldoSorteo.bloquesARestaurar(r, nuevo), isNull);
    });

    test('sin plano, o con una copia sin bloques, no hay nada que reponer', () {
      final conBloques = RespaldoSorteo(
        fecha: fecha,
        numeros: const {'a': '1'},
        bloques: bloques,
      );
      final sinBloques = RespaldoSorteo(fecha: fecha, numeros: const {'a': '1'});
      expect(RespaldoSorteo.bloquesARestaurar(conBloques, null), isNull);
      expect(RespaldoSorteo.bloquesARestaurar(sinBloques, plano()), isNull);
    });
  });

  group('Restaurar sorteo anterior', () {
    final respaldo = RespaldoSorteo(
      fecha: DateTime.utc(2026, 11, 10, 20),
      numeros: const {
        'a': '1, 2',
        'b': '3',
        'c': '4',
        'd': '5',
        'ya_no_esta': '6',
      },
    );

    test('devuelve cada número a quien sigue sin mesa', () {
      final plan = RespaldoSorteo.planRestauracion(respaldo, [
        alumno('a'),
        alumno('b'),
        alumno('c'),
        alumno('d'),
      ]);
      expect(plan.aRestaurar, {
        'a': '1, 2',
        'b': '3',
        'c': '4',
        'd': '5',
      });
      expect(plan.omitidos, 1, reason: 'el que ya no está en el evento');
    });

    test('no pisa a quien ya tiene mesa ni un número ocupado', () {
      final plan = RespaldoSorteo.planRestauracion(respaldo, [
        alumno('a', mesa: '9'), // ya tiene mesa: no se toca
        alumno('b'),
        alumno('c'),
        alumno('d'),
        alumno('nuevo', mesa: '4'), // el 4 hoy es de otro
      ]);
      expect(plan.aRestaurar, {'b': '3', 'd': '5'});
      expect(plan.omitidos, 3);
    });

    test('un número repetido en la copia no se entrega dos veces', () {
      final copia = RespaldoSorteo(
        fecha: DateTime.utc(2026, 11, 10),
        numeros: const {'x': '7', 'y': '7'},
      );
      final plan = RespaldoSorteo.planRestauracion(copia, [
        alumno('x'),
        alumno('y'),
      ]);
      expect(plan.aRestaurar.length, 1);
      expect(plan.omitidos, 1);
    });
  });

  group('Restaurar después de deshacer solo a los últimos sorteados', () {
    // `a` tenía la 12 y el último sorteo le sumó la 13; `c` no tenía nada y le
    // tocó la 20. Al deshacer, `a` se quedó con la 12 y `c` sin mesa.
    final copia = RespaldoSorteo(
      fecha: DateTime.utc(2026, 11, 20, 21),
      numeros: const {'a': '12, 13', 'c': '20'},
      quedaron: const {'a': '12'},
    );

    test('a cada uno le vuelve lo suyo, y a nadie más', () {
      final plan = RespaldoSorteo.planRestauracion(copia, [
        alumno('a', mesa: '12'),
        alumno('b', mesa: '14'),
        alumno('c'),
      ]);
      expect(plan.aRestaurar, {'a': '12, 13', 'c': '20'});
      expect(plan.omitidos, 0);
    });

    test('si la que se le había sumado hoy es de otro, no se le devuelve', () {
      final plan = RespaldoSorteo.planRestauracion(copia, [
        alumno('a', mesa: '12'),
        alumno('nuevo', mesa: '13'),
        alumno('c'),
      ]);
      expect(plan.aRestaurar, {'c': '20'});
      expect(plan.omitidos, 1);
    });

    test('si después del deshacer le cambiaron la mesa, no se toca', () {
      final plan = RespaldoSorteo.planRestauracion(copia, [
        alumno('a', mesa: '30'),
        alumno('c', mesa: '31'),
      ]);
      expect(plan.aRestaurar, isEmpty);
      expect(plan.omitidos, 2);
    });

    test('si quedó sin la que conservaba, tampoco', () {
      final plan = RespaldoSorteo.planRestauracion(copia, [
        alumno('a'),
        alumno('c'),
      ]);
      expect(plan.aRestaurar, {'c': '20'});
      expect(plan.omitidos, 1);
    });

    test('lo que conservó cada uno va y vuelve por el archivo', () {
      final json = jsonDecode(
        jsonEncode(
          RespaldoSorteo.aJson(
            copia.fecha,
            copia.numeros,
            quedaron: copia.quedaron,
          ),
        ),
      );
      final r = RespaldoSorteo.deJson(json)!;
      expect(r.numeros, copia.numeros);
      expect(r.quedaron, {'a': '12'});
      expect(r.bloques, isEmpty);
    });

    test('una copia de antes (sin esa clave) se lee como siempre', () {
      final r = RespaldoSorteo.deJson({
        'fecha': copia.fecha.toIso8601String(),
        'numeros': {'a': '3'},
      })!;
      expect(r.quedaron, isEmpty);
    });
  });

  group('Editar alumno: el número de mesa solo si se cambió', () {
    final antes = alumno('a', mesa: '12, 13');

    test('sin tocar el campo no se manda: otra PC no pisa el sorteo', () {
      final datos = datosEdicionAlumno(
        antes: antes,
        editado: antes.copyWith(telefono: '3777123456'),
        numeroMesaEscrito: '12, 13',
      );
      expect(datos.containsKey('numero_mesa'), isFalse);
      expect(datos['telefono'], '3777123456');
    });

    test('con el campo vacío en una PC sin el sorteo, tampoco', () {
      final sinSorteo = alumno('a');
      final datos = datosEdicionAlumno(
        antes: sinSorteo,
        editado: sinSorteo,
        numeroMesaEscrito: '',
      );
      expect(datos.containsKey('numero_mesa'), isFalse);
    });

    test('cambiado a mano, se manda', () {
      final datos = datosEdicionAlumno(
        antes: antes,
        editado: antes,
        numeroMesaEscrito: '12, 13, 14',
      );
      expect(datos['numero_mesa'], '12, 13, 14');
    });

    test('vaciado a propósito, se libera', () {
      final datos = datosEdicionAlumno(
        antes: antes,
        editado: antes,
        numeroMesaEscrito: '  ',
      );
      expect(datos.containsKey('numero_mesa'), isTrue);
      expect(datos['numero_mesa'], isNull);
    });
  });

  // Cambiar una mesa cambia el salón, y eso lo hace solo el jefe: se cambia
  // desde el plano, con su motivo y su renglón en el Historial.
  group('Editar alumno: el número de mesa lo cambia solo el jefe', () {
    final antes = alumno('a', mesa: '12, 13');

    Map<String, dynamic> guardar({
      required bool esJefe,
      required ContratoAlumno alumnoAntes,
      required String escrito,
    }) =>
        datosEdicionAlumno(
          antes: alumnoAntes,
          editado: alumnoAntes.copyWith(telefono: '3777123456'),
          numeroMesaEscrito: numeroMesaParaGuardar(
            esJefe: esJefe,
            antes: alumnoAntes.numeroMesa,
            escrito: escrito,
          ),
        );

    test('sin modo jefe, lo escrito no viaja: queda la mesa que tenía', () {
      final datos = guardar(esJefe: false, alumnoAntes: antes, escrito: '40');
      expect(datos.containsKey('numero_mesa'), isFalse);
      // Lo demás del alumno se guarda igual.
      expect(datos['telefono'], '3777123456');
    });

    test('sin modo jefe, vaciarlo tampoco la libera', () {
      final datos = guardar(esJefe: false, alumnoAntes: antes, escrito: '');
      expect(datos.containsKey('numero_mesa'), isFalse);
    });

    test('sin modo jefe, a quien no tiene mesa no se le pone una', () {
      final datos =
          guardar(esJefe: false, alumnoAntes: alumno('b'), escrito: '40');
      expect(datos.containsKey('numero_mesa'), isFalse);
    });

    test('en modo jefe viaja como siempre', () {
      expect(
        guardar(esJefe: true, alumnoAntes: antes, escrito: '40')['numero_mesa'],
        '40',
      );
      final vaciado = guardar(esJefe: true, alumnoAntes: antes, escrito: ' ');
      expect(vaciado.containsKey('numero_mesa'), isTrue);
      expect(vaciado['numero_mesa'], isNull);
    });

    test('en un alta sin modo jefe no se carga ninguna mesa', () {
      expect(
        numeroMesaParaGuardar(esJefe: false, antes: null, escrito: '40'),
        '',
      );
      expect(
        numeroMesaParaGuardar(esJefe: true, antes: null, escrito: '40'),
        '40',
      );
    });

    Future<TextEditingController> mostrar(
      WidgetTester tester, {
      required bool esJefe,
    }) async {
      final controller = TextEditingController(text: '12, 13');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CasilleroNumeroMesa(
              controller: controller,
              esJefe: esJefe,
              decoration: const InputDecoration(
                labelText: 'N° de Mesa Asignada / Contrato',
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('sin modo jefe el casillero se ve, no se escribe y dice por qué',
        (tester) async {
      final controller = await mostrar(tester, esJefe: false);
      expect(find.text('12, 13'), findsOneWidget);
      expect(find.text('Solo en modo jefe'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('numero_mesa')),
        '40',
      );
      await tester.pump();
      expect(controller.text, '12, 13');
    });

    testWidgets('en modo jefe se escribe como siempre, sin el motivo',
        (tester) async {
      final controller = await mostrar(tester, esJefe: true);
      expect(find.text('Solo en modo jefe'), findsNothing);
      await tester.enterText(find.byKey(const Key('numero_mesa')), '40');
      await tester.pump();
      expect(controller.text, '40');
    });
  });

  // La lista de la puerta dice el nombre, la mesa y los acompañantes de cada
  // alumno: solo un cambio en eso tiene que llegar a Recepción y al tótem.
  group('Editar alumno: qué cambia lo que dice la puerta', () {
    final antes = alumno('a', mesa: '12, 13').copyWith(
      nombresAcompanantes: ['ANA PEREZ', 'HUGO PEREZ'],
    );

    bool cambia(ContratoAlumno editado, {String mesa = '12, 13'}) =>
        edicionCambiaLaPuerta(
          antes: antes,
          editado: editado,
          numeroMesaEscrito: mesa,
        );

    test('el teléfono, una silla o las cuotas no la cambian', () {
      expect(
        cambia(
          antes.copyWith(
            telefono: '3777123456',
            sillasExtraCantidad: 2,
            totalCuotas: 6,
          ),
        ),
        isFalse,
      );
    });

    test('el nombre, sí', () {
      expect(cambia(antes.copyWith(nombreAlumno: 'OTRO NOMBRE')), isTrue);
    });

    test('la mesa escrita a mano, sí; con espacios de más, no', () {
      expect(cambia(antes, mesa: '40'), isTrue);
      expect(cambia(antes, mesa: ''), isTrue);
      expect(cambia(antes, mesa: ' 12, 13 '), isFalse);
    });

    test('sumar, sacar o cambiar un acompañante, sí', () {
      expect(
        cambia(antes.copyWith(nombresAcompanantes: ['ANA PEREZ'])),
        isTrue,
      );
      expect(
        cambia(
          antes.copyWith(
            nombresAcompanantes: ['ANA PEREZ', 'HUGO PEREZ', 'TÍA NORA'],
          ),
        ),
        isTrue,
      );
      expect(
        cambia(
          antes.copyWith(nombresAcompanantes: ['ANA PEREZ', 'HUGO PÉREZ']),
        ),
        isTrue,
      );
    });

    test('los mismos acompañantes, con un renglón vacío de más, no', () {
      expect(
        cambia(
          antes.copyWith(
            nombresAcompanantes: [' ANA PEREZ ', '', 'HUGO PEREZ'],
          ),
        ),
        isFalse,
      );
    });
  });
}
