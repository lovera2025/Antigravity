import 'package:arguello_events/features/eventos/services/respaldo_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/modal_alumno_premium.dart';
import 'dart:convert';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
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
}
