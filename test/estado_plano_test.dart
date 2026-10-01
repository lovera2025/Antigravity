import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/services/divisiones.dart';

OcupantePlano _fam(
  String id,
  List<int> numeros, {
  String? division,
  Map<int, int> sillas = const {},
}) =>
    OcupantePlano(
      id: id,
      nombre: 'FAMILIA $id, NOMBRE',
      numeros: numeros,
      division: division,
      sillasExtraPorMesa: sillas,
    );

void main() {
  group('la mesa principal de una familia', () {
    test('es la primera del tramo más largo', () {
      expect(OcupantePlano.principalDe([40, 12, 13, 14]), 12);
      expect(OcupantePlano.principalDe([3, 20, 21]), 20);
    });

    test('a igual largo, la que empieza antes', () {
      expect(OcupantePlano.principalDe([9, 5]), 5);
    });

    test('sin mesas no hay principal', () {
      expect(OcupantePlano.principalDe(const []), isNull);
    });
  });

  test('el apellido es lo anterior a la coma', () {
    expect(_fam('x', const []).apellido, 'FAMILIA x');
    expect(
      const OcupantePlano(id: 'y', nombre: 'SIN COMA', numeros: []).apellido,
      'SIN COMA',
    );
  });

  group('EstadoPlano.desde', () {
    final armado = ArmadosPredefinidos.normal2aPagina3();

    test('cada mesa sabe qué tiene', () {
      final a = _fam('a', [12, 13], division: '5° A', sillas: {12: 2});
      final fija = _fam('f', [60], division: '5° C');
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [a],
        libres: {77},
        fijadas: {60: fija},
      );
      expect(e.info(12).estado, EstadoMesa.ocupada);
      expect(e.info(12).principal, isTrue);
      expect(e.info(13).principal, isFalse);
      expect(e.info(12).sillasExtra, 2);
      expect(e.info(13).sillasExtra, 0);
      expect(e.info(77).estado, EstadoMesa.libre);
      expect(e.info(77).libre, isTrue);
      expect(e.info(60).estado, EstadoMesa.fijada);
      expect(e.info(60).fijadaPara?.id, 'f');
      expect(e.info(1).estado, EstadoMesa.vacia);
    });

    test('dos familias con el mismo número: conflicto', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [_fam('a', [5]), _fam('b', [5])],
      );
      expect(e.info(5).estado, EstadoMesa.conflicto);
      expect(e.info(5).ocupantes.map((o) => o.id), ['a', 'b']);
    });

    test('un número que el armado no tiene queda aparte, para avisar', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [_fam('a', [3, 200])],
      );
      expect(e.info(3).estado, EstadoMesa.ocupada);
      expect(e.fueraDelPlano.single.numero, 200);
      expect(e.fueraDelPlano.single.ocupante.id, 'a');
    });

    test('una fijada o una libre que el armado no tiene quedan aparte', () {
      final fija = _fam('f', const [], division: '5° A');
      final e = EstadoPlano.desde(
        armado: armado,
        libres: {77, 300, 250},
        fijadas: {60: fija, 400: fija},
      );
      expect(e.fijadasFueraDelPlano.map((f) => f.numero), [400]);
      expect(e.fijadasFueraDelPlano.single.para.id, 'f');
      expect(e.libresFueraDelPlano, [250, 300]);
      expect(e.info(60).estado, EstadoMesa.fijada);
      expect(e.info(77).estado, EstadoMesa.libre);
    });
  });

  group('las divisiones del plano', () {
    final armado = ArmadosPredefinidos.normal2aPagina3();

    test('van por su mesa más chica, salvo que se dé el orden', () {
      final ocupantes = [
        _fam('a', [40], division: '5° B'),
        _fam('b', [3], division: '5° C'),
        _fam('c', [70], division: '5° A'),
      ];
      expect(
        EstadoPlano.desde(armado: armado, ocupantes: ocupantes).divisiones,
        ['5C', '5B', '5A'],
      );
      // El orden guardado está en claves; una que no tiene familias se saltea.
      expect(
        EstadoPlano.desde(
          armado: armado,
          ocupantes: ocupantes,
          ordenDivisiones: ['5A', '5E'],
        ).divisiones,
        ['5A', '5C', '5B'],
      );
    });

    test('"5° a" y "5° A" son la misma, con un solo color', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [
          _fam('a', [1], division: '5° A'),
          _fam('b', [2], division: '5° a'),
          _fam('c', [3], division: '5ºA'),
          _fam('d', [4], division: '5° B'),
        ],
      );
      expect(e.divisiones, ['5A', '5B']);
      expect(e.info(1).division, 0);
      expect(e.info(2).division, 0);
      expect(e.info(3).division, 0);
      expect(e.info(4).division, 1);
      expect(e.indiceDivision('5° a'), 0);
      expect(e.indiceDivision('5 B'), 1);
    });

    test('la leyenda muestra la forma más usada de cada división', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [
          _fam('a', [1], division: '5° A'),
          _fam('b', [2], division: '5° A'),
          _fam('c', [3], division: '5ºa'),
        ],
      );
      expect(e.nombresDivision['5A'], '5° A');
    });

    test('sin división: sin color, fuera de la lista y con nombre propio', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [
          _fam('a', [1], division: '5° A'),
          _fam('b', [2]),
          _fam('c', [3], division: '   '),
        ],
      );
      expect(e.divisiones, ['5A']);
      expect(e.haySinDivision, isTrue);
      expect(e.info(1).division, 0);
      expect(e.info(2).division, isNull);
      expect(e.info(3).division, isNull);
      expect(e.indiceDivision(null), -1);
      expect(e.nombresDivision[''], Divisiones.sinDivision);
    });

    test('con todas las familias con división, no hay "sin división"', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [_fam('a', [1], division: '5° A')],
      );
      expect(e.haySinDivision, isFalse);
      expect(e.nombresDivision.containsKey(''), isFalse);
    });

    test('una fijada sin números se ordena por su mesa', () {
      // La 5° B está fijada en la mesa 2 y todavía no tiene números: va antes
      // que la 5° A, que arranca en la 30.
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [_fam('a', [30], division: '5° A')],
        fijadas: {2: _fam('f', const [], division: '5° B')},
      );
      expect(e.divisiones, ['5B', '5A']);
      expect(e.info(2).division, 0);
    });
  });

  group('fijadas, libres y familias en la misma mesa', () {
    final armado = ArmadosPredefinidos.normal2aPagina3();

    test('fijada para la familia que la ocupa: sigue marcada, sin conflicto',
        () {
      final a = _fam('a', [10, 11], division: '5° A');
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [a],
        fijadas: {10: a, 11: a},
      );
      expect(e.info(10).estado, EstadoMesa.ocupada);
      expect(e.info(10).fijadaPara?.id, 'a');
      expect(e.info(11).fijadaPara?.id, 'a');
      expect(e.info(10).principal, isTrue);
    });

    test('fijada para una familia y ocupada por otra: conflicto', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [_fam('b', [10])],
        fijadas: {10: _fam('a', const [])},
      );
      expect(e.info(10).estado, EstadoMesa.conflicto);
      expect(e.info(10).fijadaPara?.id, 'a');
      expect(e.info(10).ocupante?.id, 'b');
    });

    test('una mesa libre con familia: conflicto, y sigue marcada libre', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [_fam('a', [20])],
        libres: {20},
      );
      expect(e.info(20).estado, EstadoMesa.conflicto);
      expect(e.info(20).libre, isTrue);
    });

    test('antes del sorteo, el apellido va en una sola de las fijadas', () {
      final a = _fam('a', const [], division: '5° A');
      final e = EstadoPlano.desde(
        armado: armado,
        fijadas: {40: a, 41: a},
      );
      expect(e.info(40).principal, isTrue);
      expect(e.info(41).principal, isFalse);
    });
  });

  group('la mesa que lleva el apellido', () {
    final armado = ArmadosPredefinidos.normal2aPagina3();

    test('si la principal está fuera del plano, pasa a una que se dibuja', () {
      // Por los números, la principal sería la 200 (tramo 200-201), que el
      // armado no tiene.
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [_fam('a', [7, 200, 201])],
      );
      expect(e.info(7).principal, isTrue);
    });

    test('si la principal está en conflicto, pasa a otra de la familia', () {
      final e = EstadoPlano.desde(
        armado: armado,
        ocupantes: [_fam('a', [5, 6, 30]), _fam('b', [5])],
      );
      expect(e.info(5).estado, EstadoMesa.conflicto);
      expect(e.info(5).principal, isFalse);
      // De las que son solo suyas (6 y 30), la primera.
      expect(e.info(6).principal, isTrue);
      expect(e.info(30).principal, isFalse);
    });
  });
}
