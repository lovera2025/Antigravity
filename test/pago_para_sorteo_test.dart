// El sorteo solo le da mesa a lo que tiene algo pagado (v5.0.0).
//
// Lo cargado sigue cargado: lo que cambia es a quién se le reserva una mesa el
// día del sorteo. Al 24-sep-2026 había 101 alumnos sin nada pagado de la base y
// 15 con mesas extra en $0.
import 'dart:math';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';

ContratoAlumno alumno(
  String id, {
  int extras = 0,
  String? mesa,
  bool baja = false,
  int sillas = 0,
  double saldo = 0,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e1',
      nombreAlumno: baja ? '[BAJA] $id' : id,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: saldo,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      mesaExtraCuotas: 7,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa: mesa,
    );

Map<String, dynamic> pago(String concepto, double monto, {bool anulado = false}) => {
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'anulado': anulado ? 1 : 0,
    };

const pagaBase = PagoAlumno(base: 30000);
const pagaTodo = PagoAlumno(base: 30000, mesas: 10000, sillas: 8000);

void main() {
  group('PagoAlumno desde los pagos', () {
    test('separa base, mesas y sillas, igual que el saldo de la app', () {
      final p = PagoAlumno.desdePagos([
        pago('Cuota Base (1/9)', 30000),
        pago('Mesa Extra (1/7)', 20000),
        pago('Sillas Extras - Entrega', 8000),
        pago('Interés mora cuota 1 (vto Abr 2026)', 900),
        pago('Cargo canal / operador (ref. MP u otro)', 1500),
        pago('Cuota Base (2/9)', 30000, anulado: true),
      ]);
      expect(p.base, 30000);
      expect(p.mesas, 20000);
      expect(p.sillas, 8000);
    });

    test('solo mora o recargo no es haber pagado la base', () {
      final p = PagoAlumno.desdePagos([
        pago('Interés mora cuota 1 (vto Abr 2026)', 900),
      ]);
      expect(p.pagoBase, isFalse);
    });

    test('una entrega parcial de la primera cuota es "algo pagado"', () {
      final p = PagoAlumno.desdePagos([
        pago('Entrega parcial — Cuota Base (1/9)', 5000),
      ]);
      expect(p.pagoBase, isTrue);
    });
  });

  group('quiénes quedan afuera', () {
    test(r'$0 de base y sin mesa: sin mesa', () {
      final c = candidatosPorPago([alumno('a')], {});
      expect(c.sinPagoBase.map((a) => a.id), ['a']);
    });

    test('el contrato dice que pagó, pero no hay pagos: cuenta lo que dicen los pagos',
        () {
      // Caso real de sep-2026: el saldo del contrato daba $30.000 de base
      // pagados y no había ningún pago cargado.
      final a = alumno('arguello', saldo: 270000);
      final c = candidatosPorPago([a], pagosPorAlumno([a], {}));
      expect(c.sinPagoBase.map((a) => a.id), ['arguello']);
    });

    test('lo ya asignado no se toca, pague o no', () {
      final c = candidatosPorPago([alumno('a', mesa: '12')], {});
      expect(c.vacio, isTrue);
    });

    test('los de baja no cuentan', () {
      final c = candidatosPorPago([alumno('b', baja: true)], {});
      expect(c.vacio, isTrue);
    });

    test(r'pagó la base y $0 de sus mesas extra (Ortiz): solo base', () {
      final c = candidatosPorPago([alumno('ortiz', extras: 2)], {'ortiz': pagaBase});
      expect(c.sinPagoBase, isEmpty);
      expect(c.sinPagoMesasExtra.map((a) => a.id), ['ortiz']);
    });

    test('pagó algo de sus mesas extra (Ponce): entra con todas', () {
      final c = candidatosPorPago(
        [alumno('ponce', extras: 2)],
        {'ponce': const PagoAlumno(base: 90000, mesas: 60000)},
      );
      expect(c.vacio, isTrue);
    });

    test(r'$0 de base y de mesas extra: sin mesa, y marcado con extras sin pagar', () {
      final c = candidatosPorPago([alumno('x', extras: 1)], {});
      expect(c.sinPagoBase.map((a) => a.id), ['x']);
      expect(c.sinPagoMesasExtra, isEmpty);
      expect(c.sinPagoBaseConExtras, {'x'});
    });

    test('ya tiene su base y le falta la extra sin pagar: no se le completa', () {
      final c = candidatosPorPago(
        [alumno('y', extras: 1, mesa: '5')],
        {'y': pagaBase},
      );
      expect(c.sinPagoMesasExtra.map((a) => a.id), ['y']);
    });
  });

  group('exclusión con las casillas', () {
    final alumnos = [
      alumno('sinbase'),
      alumno('sinbase_extra', extras: 1),
      alumno('ortiz', extras: 2),
      alumno('ok', extras: 1),
    ];
    final pagos = {'ortiz': pagaBase, 'ok': pagaTodo};
    final candidatos = candidatosPorPago(alumnos, pagos);

    test('"a todo lo cargado": no deja a nadie afuera', () {
      expect(exclusionSorteo(candidatos: candidatos, soloPagado: false).vacia, isTrue);
    });

    test('"solo lo pagado": sin mesa y solo base', () {
      final ex = exclusionSorteo(candidatos: candidatos, soloPagado: true);
      expect(ex.sinMesa, {'sinbase', 'sinbase_extra'});
      expect(ex.soloBase, {'ortiz'});
    });

    test('sortear igual por la base: entra con la base, sin sus extras sin pagar', () {
      final ex = exclusionSorteo(
        candidatos: candidatos,
        soloPagado: true,
        incluirBase: {'sinbase_extra'},
      );
      expect(ex.sinMesa, {'sinbase'});
      expect(ex.soloBase, {'ortiz', 'sinbase_extra'});
    });

    test('sortear igual las extras: entra completo', () {
      final ex = exclusionSorteo(
        candidatos: candidatos,
        soloPagado: true,
        incluirExtras: {'ortiz'},
      );
      expect(ex.soloBase, isEmpty);
    });
  });

  group('el sorteo con lo pagado', () {
    test('sin mesa no pide nada; solo base pide 1; lo demás, lo suyo', () {
      final pedidos = SorteoMesasMotor.pedidos(
        [alumno('a'), alumno('b', extras: 2), alumno('c', extras: 1)],
        sinMesa: {'a'},
        soloBase: {'b'},
      );
      expect({for (final p in pedidos) p.alumnoId: p.mesas}, {'b': 1, 'c': 2});
    });

    test('separar no aplica a quien va solo con la base', () {
      final pedidos = SorteoMesasMotor.pedidos(
        [alumno('b', extras: 2)],
        separaciones: {'b': 1},
        soloBase: {'b'},
      );
      expect(pedidos.single.separadas, 0);
    });

    test('lo ya asignado no se toca aunque figure sin mesa', () {
      final pedidos = SorteoMesasMotor.pedidos(
        [alumno('a', mesa: '3', extras: 1)],
        sinMesa: {'a'},
      );
      expect(pedidos, isEmpty);
    });

    test('la capacidad sugerida baja con lo que queda afuera', () {
      final alumnos = [
        for (var i = 0; i < 10; i++) alumno('a$i'),
        alumno('b', extras: 2),
      ];
      int minima(Set<String> sinMesa, Set<String> soloBase) =>
          SorteoMesasMotor.capacidadMinima(
            pedidos: SorteoMesasMotor.pedidos(
              alumnos,
              sinMesa: sinMesa,
              soloBase: soloBase,
            ),
            ocupadas: const {},
          );
      expect(minima({}, {}), 13);
      expect(minima({'a0', 'a1'}, {'b'}), 9);
    });

    test('si paga después, el segundo sorteo le da mesa y le suma la extra sin mover a nadie', () {
      final rng = Random(7);
      // Primer sorteo: "sinpago" no pagó nada, "extra" no pagó sus mesas extra.
      var alumnos = [
        for (var i = 0; i < 6; i++) alumno('a$i'),
        alumno('sinpago'),
        alumno('extra', extras: 1),
      ];
      final pedidos1 = SorteoMesasMotor.pedidos(
        alumnos,
        sinMesa: {'sinpago'},
        soloBase: {'extra'},
      );
      final ocupadas1 = SorteoMesasMotor.ocupadas(alumnos);
      // Con lugar de sobra, para que el número al lado de "extra" pueda estar libre.
      const capacidad = 12;
      final r1 = SorteoMesasMotor.sortear(
        pedidos: pedidos1,
        ocupadas: ocupadas1,
        capacidad: capacidad,
        random: rng,
      );
      expect(r1.containsKey('sinpago'), isFalse);
      expect(r1['extra'], hasLength(1));
      alumnos = [
        for (final a in alumnos)
          a.copyWith(numeroMesa: r1[a.id] == null
              ? null
              : MesasExtraUtils.formatearAsignacionMesas(r1[a.id]!)),
      ];

      // Pagaron: segundo sorteo sin exclusiones.
      final pedidos2 = SorteoMesasMotor.pedidos(alumnos);
      expect({for (final p in pedidos2) p.alumnoId: p.faltan}, {'sinpago': 1, 'extra': 1});
      final ocupadas2 = SorteoMesasMotor.ocupadas(alumnos);
      final r2 = SorteoMesasMotor.sortear(
        pedidos: pedidos2,
        ocupadas: ocupadas2,
        capacidad: capacidad,
        random: rng,
      );
      expect(
        SorteoMesasMotor.validar(
          pedidos: pedidos2,
          ocupadas: ocupadas2,
          capacidad: capacidad,
          asignaciones: r2,
        ),
        isNull,
      );
      // Nadie que ya tenía mesa se movió.
      for (final e in r1.entries) {
        if (e.key == 'extra') continue;
        expect(r2[e.key] ?? e.value, e.value);
      }
      expect(r2['sinpago'], hasLength(1));
      // "extra" conserva su mesa y suma una.
      expect(r2['extra'], containsAll(r1['extra']!));
      expect(r2['extra'], hasLength(2));
    });
  });

  test('firmaPagos cambia si entra un pago con el diálogo abierto', () {
    final alumnos = [alumno('a'), alumno('b')];
    final antes = firmaPagos(alumnos, {});
    final despues = firmaPagos(alumnos, {'b': pagaBase});
    expect(despues, isNot(antes));
    expect(firmaPagos(alumnos, {}), antes);
  });
}
