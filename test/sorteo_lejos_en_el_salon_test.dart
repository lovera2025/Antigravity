import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// Que "lejos" se cumpla en el salón dibujado (6.1.0, pedido del usuario el
/// 19-oct: "cuando marquen que una mesa quede lejos o cerca de una, que se
/// cumpla").
///
/// Hasta acá "lejos" se medía por número: que las mesas no fueran seguidas. En
/// un salón acomodado sin pasarela eso no alcanza: la 1 y la 132 quedan una al
/// lado de la otra en el medio, y la 6 justo delante de la 9. En una prueba
/// del 19-oct, 2 de 800 familias con "1 lejos" quedaron tocándose.
ContratoAlumno _familia(String id, {int extras = 0, String division = '5° A'}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 1,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      cursoDivision: division,
    );

void main() {
  final acomodado = ArmarAMedida.acomodar(
    ArmarAMedida.vacio(PlayonReal.costaSurubi),
    cantidad: 132,
  ).armado;
  final aMedida = ArmarAMedida.armar(
    const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 132),
  ).armado;
  final canva = ArmadosPredefinidos.normal2a2b();

  test('en el salón acomodado sin pasarela, números lejos pueden tocarse', () {
    // Por eso no alcanza con mirar los números.
    expect(acomodado.pegadas(1, 132), isTrue);
    expect(acomodado.pegadas(6, 9), isTrue);
  });

  group('las mesas de una familia en el salón', () {
    test('se juntan por las que se tocan', () {
      expect(SorteoConPlano.gruposEnElSalon(acomodado, [1, 2, 132]),
          [[1, 2, 132]]);
      expect(SorteoConPlano.gruposEnElSalon(acomodado, [1, 60]), [[1], [60]]);
    });

    test('en cadena: la 1 toca a la 2 y la 2 a la 3, aunque la 1 y la 3 no se '
        'toquen', () {
      expect(acomodado.pegadas(1, 3), isFalse);
      expect(SorteoConPlano.gruposEnElSalon(acomodado, [1, 2, 3]), [[1, 2, 3]]);
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [1, 2, 3], 1), isFalse);
    });

    test('"1 lejos": la extra no toca a la principal', () {
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [1, 60], 1), isTrue);
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [1, 132], 1), isFalse);
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [6, 9], 1), isFalse);
    });

    test('"2 juntas + 1 lejos" y "1 + 2 lejos, sin tocarse"', () {
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [1, 2, 60], 1), isTrue);
      // La lejos toca a las juntas.
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [1, 2, 132], 1), isFalse);
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [1, 40, 80], 2), isTrue);
      // Dos lejos que se tocan entre sí.
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [1, 60, 61], 2), isFalse);
    });

    test('sin "lejos" no se mira nada', () {
      expect(SorteoConPlano.lejosEnElSalon(acomodado, [1, 132], 0), isTrue);
    });
  });

  // 20 familias de dos mesas con "1 lejos", 6 de tres con "2 juntas + 1
  // lejos", y 30 de una mesa: 88 mesas, más el lugar que piden las lejos para
  // no tocarse.
  final alumnos = [
    for (var i = 0; i < 20; i++)
      _familia('dos$i', extras: 1, division: i.isEven ? '5° A' : '5° B'),
    for (var i = 0; i < 6; i++) _familia('tres$i', extras: 2, division: '5° C'),
    for (var i = 0; i < 30; i++)
      _familia('uno$i', division: i.isEven ? '5° A' : '5° C'),
  ];
  final separaciones = {
    for (var i = 0; i < 20; i++) 'dos$i': 1,
    for (var i = 0; i < 6; i++) 'tres$i': 1,
  };

  for (final (nombre, armado) in [
    ('acomodado sin pasarela', acomodado),
    ('A medida', aMedida),
    ('del Canva', canva),
  ]) {
    for (final modo in ModoSorteo.values) {
      test('$nombre, ${modo.clave}: en 60 sorteos ninguna mesa "lejos" toca a '
          'su familia, y las juntas quedan juntas', () {
        final e = EntradaSorteoPlano(
          armado: armado,
          alumnos: alumnos,
          separaciones: separaciones,
          modo: modo,
        );
        expect(SorteoConPlano.preparar(e).entra, isTrue);
        var lejos = 0;
        for (var s = 0; s < 60; s++) {
          final r = SorteoConPlano.sortear(e, random: Random(s));
          expect(SorteoConPlano.validar(e, r), isNull, reason: 'sorteo $s');
          for (final x in r.asignaciones.entries) {
            final nums = x.value;
            final sep = separaciones[x.key] ?? 0;
            if (sep > 0) lejos++;
            expect(SorteoConPlano.lejosEnElSalon(armado, nums, sep), isTrue,
                reason: 'sorteo $s, ${x.key}: $nums');
            if (sep == 0) {
              expect(SorteoConPlano.gruposEnElSalon(armado, nums), hasLength(1),
                  reason: 'sorteo $s, ${x.key}: $nums');
            }
          }
        }
        expect(lejos, 60 * 26);
      });
    }
  }

  group('si en el salón no hay dónde separarlas', () {
    // Tres mesas en triángulo: todas se tocan. Para el motor, la 1 y la 3 no
    // son seguidas; en el salón, se tocan.
    final triangulo = ArmadoSalon(
      clave: 'triangulo',
      nombre: 'Triángulo',
      distanciaPegadas: 160,
      hojas: const [
        HojaPlano(id: 'A', titulo: '', caja: RectPlano(-100, -100, 400, 400)),
      ],
      mesas: const [
        MesaPlano(numero: 1, hoja: 'A', x: 0, y: 0),
        MesaPlano(numero: 2, hoja: 'A', x: 105, y: 0),
        MesaPlano(numero: 3, hoja: 'A', x: 52, y: 90),
      ],
    );
    final e = EntradaSorteoPlano(
      armado: triangulo,
      alumnos: [_familia('x', extras: 1)],
      separaciones: const {'x': 1},
    );

    test('no se sortea, y se dice por qué', () {
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isFalse);
      expect(plan.avisos.last, contains('"lejos" quedarían tocando'));
      expect(() => SorteoConPlano.sortear(e, random: Random(1)),
          throwsStateError);
    });

    test('la revisión final no deja pasar unas "lejos" que se tocan', () {
      const r = ResultadoSorteoPlano(asignaciones: {'x': [1, 3]});
      expect(SorteoConPlano.validar(e, r),
          'Las mesas "lejos" de una familia quedaron tocándose en el salón.');
    });
  });
}
