// El orden por cumplimiento (12-nov-2026): cómo cumplió cada familia con sus
// cuotas, los tres grupos, el plan nuevo y la oración del porqué. Todo con
// familias inventadas (F1, F2…): el repo es público.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/cumplimiento_de_cuotas.dart';
import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';

String _id(int n) => 'c0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// 9 cuotas de $30.000, alta el 30/3 (Argentina): la cuota 1 vence el 30/4, la
/// 2 el 31/5, la 3 el 30/6, la 4 el 31/7, la 5 el 31/8, la 6 el 30/9, la 7 el
/// 31/10, la 8 el 30/11 y la 9 el 31/12.
ContratoAlumno _f(
  int n, {
  int cuotas = 9,
  double total = 270000,
  DateTime? alta,
  double mesaExtra = 0,
  double saldo = 270000,
  int pagadas = 0,
  DateTime? exentaHasta,
  String? nombre,
}) =>
    ContratoAlumno(
      id: _id(n),
      eventoId: _evento,
      nombreAlumno: nombre ?? 'F$n',
      cantidadAcompanantes: 0,
      montoTotalPactado: total + mesaExtra,
      mesaExtraPrecio: mesaExtra,
      saldoDeudor: saldo,
      cuotasPagadas: pagadas,
      totalCuotas: cuotas,
      createdAt: alta ?? DateTime.utc(2026, 3, 30, 3),
      moraExentaHasta: exentaHasta,
    );

var _n = 0;

/// Un pago, con su día en Argentina (a las 12, para que el huso no lo corra).
Map<String, dynamic> _pago(
  int mes,
  int dia,
  double monto, {
  String concepto = 'Cuota Base',
  String? lineKind,
  bool anulado = false,
  DateTime? creado,
}) {
  final fecha = DateTime.utc(2026, mes, dia, 15);
  _n++;
  return {
    'id': 'p$_n',
    'concepto': concepto,
    'monto': monto,
    'monto_gross': monto,
    'fecha_pago': fecha.toIso8601String(),
    'created_at': (creado ?? fecha.add(Duration(seconds: _n))).toIso8601String(),
    'line_kind': lineKind,
    'anulado': anulado ? 1 : 0,
  };
}

final _nov12 = DateTime(2026, 11, 12);

CumplimientoDeCuotas _de(ContratoAlumno a, List<Map<String, dynamic>> pagos) =>
    CumplimientoDeCuotas.de(a, pagos, corteAr: _nov12);

/// Las siete cuotas vencidas al 12/11, cada una pagada el día de su vencimiento.
List<Map<String, dynamic>> _alDia() => [
      _pago(4, 30, 30000),
      _pago(5, 31, 30000),
      _pago(6, 30, 30000),
      _pago(7, 31, 30000),
      _pago(8, 31, 30000),
      _pago(9, 30, 30000),
      _pago(10, 31, 30000),
    ];

void main() {
  tearDown(MoraCongelada.vaciar);

  group('la cuenta de cada cuota', () {
    test('en término: cero días, también pagando el mismo día que vence', () {
      final c = _de(_f(1), _alDia());
      expect(c.vencidas, 7);
      expect(c.tarde, 0);
      expect(c.diasDeAtraso, 0);
      expect(c.impagas, 0);
      expect(c.cubiertas, 7);
      expect(c.canceloEl, isNull);
    });

    test('tarde: los días entre el vencimiento y el pago', () {
      final pagos = _alDia()..[1] = _pago(6, 10, 30000);
      // La 2 vencía el 31/5 y se pagó el 10/6: 10 días.
      final c = _de(_f(1), pagos);
      expect(c.tarde, 1);
      expect(c.diasDeAtraso, 10);
      expect(c.detalle[1].dias, 10);
      expect(c.detalle[1].cubierta, DateTime(2026, 6, 10));
    });

    test('un día tarde ya es atraso: la tolerancia es 0', () {
      expect(kToleranciaDiasDeAtraso, 0);
      final pagos = _alDia()..[0] = _pago(5, 1, 30000);
      expect(_de(_f(1), pagos).diasDeAtraso, 1);
    });

    test('sin cubrir: los días hasta el corte', () {
      // Pagó 5; la 6 (30/9) y la 7 (31/10) están vencidas sin pagar.
      final c = _de(_f(1), _alDia().take(5).toList());
      expect(c.impagas, 2);
      expect(c.diasDeAtraso, 43 + 12);
      expect(c.pagadasTarde, 0);
    });

    test('la que todavía no venció no suma ni resta', () {
      final c = _de(_f(1), _alDia());
      expect(c.detalle[7].vencida, isFalse);
      expect(c.detalle[7].dias, 0);
      expect(c.detalle[8].vencida, isFalse);
    });

    test('adelantada: queda cubierta el día del pago, sin atraso', () {
      final c = _de(_f(1), [_pago(4, 8, 270000)]);
      expect(c.cubiertas, 9);
      expect(c.diasDeAtraso, 0);
      expect(c.canceloEl, DateTime(2026, 4, 8));
    });

    test('entregas parciales: la cuota se cubre con el pago que la completa', () {
      final c = _de(_f(1), [
        _pago(4, 10, 10000),
        _pago(4, 20, 10000),
        _pago(5, 5, 10000),
      ]);
      // La 1 vencía el 30/4 y se completó el 5/5.
      expect(c.detalle[0].cubierta, DateTime(2026, 5, 5));
      expect(c.detalle[0].dias, 5);
    });

    test('un pago de dos cuotas juntas cubre las dos ese día', () {
      final c = _de(_f(1), [_pago(4, 30, 60000)]);
      expect(c.detalle[0].cubierta, DateTime(2026, 4, 30));
      expect(c.detalle[1].cubierta, DateTime(2026, 4, 30));
      expect(c.detalle[2].cubierta, isNull);
    });

    test('anulados, interés por mora, cargo por canal, mesa y sillas no cuentan',
        () {
      final c = _de(_f(1), [
        _pago(4, 30, 30000, anulado: true),
        _pago(4, 30, 30000, lineKind: kLineKindInteresMora),
        _pago(4, 30, 30000, lineKind: kLineKindCargoCanal),
        _pago(4, 30, 30000, concepto: 'Mesa extra (1/1)'),
        _pago(4, 30, 30000, concepto: 'Sillas extra'),
      ]);
      expect(c.cubiertas, 0);
    });

    test('vale la fecha del pago, no cuándo se cargó', () {
      final c = _de(_f(1), [
        _pago(4, 30, 30000, creado: DateTime.utc(2026, 6, 15, 15)),
      ]);
      expect(c.detalle[0].cubierta, DateTime(2026, 4, 30));
      expect(c.detalle[0].dias, 0);
    });

    test('un pago de madrugada (UTC) es del día anterior en Argentina', () {
      // 1/5 a las 02:00 UTC son las 23:00 del 30/4 en Argentina: en término.
      final p = _pago(4, 30, 30000)
        ..['fecha_pago'] = DateTime.utc(2026, 5, 1, 2).toIso8601String();
      expect(_de(_f(1), [p]).detalle[0].dias, 0);
    });

    test('los días congelados no son atraso', () {
      final a = _f(1);
      // La 6 (30/9) sin pagar: 43 días al 12/11. Congelada desde el 23/10: 23.
      MoraCongelada.poner(
        a.id,
        MoraCongelada.nada.congelar(cuotas: {6}, dia: DateTime(2026, 10, 23)),
      );
      final c = _de(a, _alDia().take(5).toList());
      expect(c.detalle[5].dias, 23);
      expect(c.detalle[6].dias, 12);
    });

    test('la eximición de la mora no borra el atraso', () {
      final pagos = _alDia()..[1] = _pago(6, 10, 30000);
      final sin = _de(_f(1), pagos);
      final con = _de(_f(1, exentaHasta: DateTime(2026, 6, 30)), pagos);
      expect(con.diasDeAtraso, sin.diasDeAtraso);
      expect(con.diasDeAtraso, 10);
    });

    test('plan de una sola cuota', () {
      final c = _de(_f(1, cuotas: 1), [_pago(5, 10, 270000)]);
      // Vencía el 30/4.
      expect(c.vencidas, 1);
      expect(c.diasDeAtraso, 10);
      expect(c.canceloEl, DateTime(2026, 5, 10));
    });

    test('alta tardía: sus cuotas vencen más tarde', () {
      final a = _f(1, cuotas: 4, alta: DateTime.utc(2026, 8, 20, 15));
      // La 1 vence el 30/9, la 2 el 31/10, la 3 el 30/11.
      final c = _de(a, [_pago(9, 30, 67500), _pago(10, 31, 67500)]);
      expect(c.vencidas, 2);
      expect(c.diasDeAtraso, 0);
    });

    test('un pago posterior al corte no cuenta', () {
      final c = CumplimientoDeCuotas.de(
        _f(1),
        [_pago(6, 10, 30000)],
        corteAr: DateTime(2026, 5, 15),
      );
      expect(c.cubiertas, 0);
      expect(c.diasDeAtraso, 15);
    });
  });

  group('atado a la app', () {
    final casos = <String, List<Map<String, dynamic>> Function()>{
      'al día': _alDia,
      'parciales': () => [
            _pago(4, 10, 10000),
            _pago(4, 20, 10000),
            _pago(5, 5, 10000),
            _pago(6, 1, 45000),
          ],
      'todo junto': () => [_pago(4, 8, 270000)],
      'casi una cuota': () => [_pago(4, 8, 29999.95)],
      'nada': () => [],
    };
    for (final caso in casos.entries) {
      test('las cuotas cubiertas son las del recálculo del saldo: ${caso.key}',
          () {
        final a = _f(1);
        final pagos = caso.value();
        final r = recalcularSaldoDesdePagos(
          montoTotalPactado: a.montoTotalPactado,
          totalCuotas: a.totalCuotas,
          mesaExtraPrecio: a.mesaExtraPrecio,
          sillasExtraPrecioTotal: a.sillasExtraPrecioTotal,
          precioUnitarioMesaExtra: 0,
          mesaExtraCuotas: a.mesaExtraCuotas,
          mesaExtraCantidad: a.mesaExtraCantidad,
          sillasExtraCuotas: a.sillasExtraCuotas,
          pagos: pagos,
        );
        expect(_de(a, pagos).cubiertas, r.cuotasBase);
      });
    }

    test('los días de una cuota impaga son los que usa la mora', () {
      // Pagó 3 y debe la 4, la 5, la 6 y la 7.
      final a = _f(1, saldo: 180000, pagadas: 3);
      final mora = MoraCuotaCalculator.calcularDesglose(a, _nov12);
      final c = _de(a, _alDia().take(3).toList());
      expect(mora, isNotEmpty);
      for (final m in mora) {
        expect(c.detalle[m.numeroCuota - 1].dias, m.diasMora,
            reason: 'cuota ${m.numeroCuota}');
        expect(c.detalle[m.numeroCuota - 1].vencimiento, m.vencimiento);
      }
      expect(c.impagas, mora.length);
    });
  });

  group('el plan nuevo', () {
    // La mayoría: 9 cuotas, $270.000, alta en marzo.
    List<ContratoAlumno> fiesta(ContratoAlumno raro) =>
        [for (var i = 1; i <= 6; i++) _f(i), raro];

    test('menos cuotas, total más alto y alta con la mayoría: sí', () {
      final raro = _f(9, cuotas: 1, total: 310000);
      final plan = PlanDeLaFiesta.de(fiesta(raro));
      expect(plan.cuotas, 9);
      expect(plan.totalBase, 270000);
      expect(plan.esPlanNuevo(raro), isTrue);
      expect(plan.esPlanDistinto(raro), isFalse);
    });

    test('alta tardía con total más alto: no', () {
      final raro = _f(9,
          cuotas: 4, total: 310000, alta: DateTime.utc(2026, 8, 20, 15));
      final plan = PlanDeLaFiesta.de(fiesta(raro));
      expect(plan.esPlanNuevo(raro), isFalse);
      expect(plan.esPlanDistinto(raro), isTrue);
    });

    test('menos cuotas con el mismo total: no', () {
      final raro = _f(9, cuotas: 6);
      final plan = PlanDeLaFiesta.de(fiesta(raro));
      expect(plan.esPlanNuevo(raro), isFalse);
      expect(plan.esPlanDistinto(raro), isTrue);
    });

    test('más cuotas que la mayoría: no', () {
      final raro = _f(9, cuotas: 12, total: 310000);
      expect(PlanDeLaFiesta.de(fiesta(raro)).esPlanNuevo(raro), isFalse);
    });

    test('las mesas extra no hacen más alto el total de la base', () {
      final raro = _f(9, cuotas: 6, mesaExtra: 80000);
      expect(PlanDeLaFiesta.de(fiesta(raro)).esPlanNuevo(raro), isFalse);
    });

    test('una fiesta donde todos tienen el mismo plan: nadie', () {
      final todos = [for (var i = 1; i <= 6; i++) _f(i)];
      final plan = PlanDeLaFiesta.de(todos);
      expect(todos.where(plan.esPlanNuevo), isEmpty);
      expect(todos.where(plan.esPlanDistinto), isEmpty);
    });

    test('los de baja no cuentan para la mayoría', () {
      final plan = PlanDeLaFiesta.de([
        _f(1),
        _f(2),
        for (var i = 3; i <= 7; i++) _f(i, cuotas: 3, nombre: '[BAJA] F$i'),
      ]);
      expect(plan.cuotas, 9);
    });

    test('el inicio es el primer pago que lleva el plan de hoy', () {
      final a = _f(9, cuotas: 1, total: 310000);
      final pagos = [
        _pago(4, 30, 30000, concepto: 'Cuota Base (1/9)'),
        _pago(5, 31, 30000, concepto: 'Cuota Base (2/9)'),
        _pago(11, 6, 250000, concepto: 'Cuota Base (1/1)'),
      ];
      expect(inicioDelPlan(a, pagos), DateTime(2026, 11, 6));
    });

    test('si ningún concepto lo dice, el inicio es su primer pago de base', () {
      final a = _f(9, cuotas: 1, total: 310000);
      expect(
        inicioDelPlan(a, [_pago(11, 11, 310000), _pago(11, 12, 1)]),
        DateTime(2026, 11, 11),
      );
      expect(inicioDelPlan(a, const []), isNull);
    });
  });

  group('el orden', () {
    List<PuestoDelOrden> orden(
      List<ContratoAlumno> alumnos,
      Map<int, List<Map<String, dynamic>>> pagos, {
      int semilla = 1,
      Set<String> siempre = const {},
      Set<String> nunca = const {},
    }) =>
        OrdenPorCumplimiento.de(
          alumnos: alumnos,
          pagos: {for (final e in pagos.entries) _id(e.key): e.value},
          corteAr: _nov12,
          rng: Random(semilla),
          siempre: siempre,
          nunca: nunca,
        );

    List<String> nombres(List<PuestoDelOrden> o) =>
        [for (final p in o) p.alumno.nombreAlumno];

    test('grupo 1 antes que el 2, y el 2 antes que el 3', () {
      final nuevo = _f(3, cuotas: 1, total: 310000);
      final o = orden([
        nuevo,
        _f(2),
        _f(1),
        _f(4),
        _f(5),
      ], {
        // Plan nuevo, ya cancelado: grupo 3 igual.
        3: [_pago(11, 6, 310000, concepto: 'Cuota Base (1/1)')],
        // Pagó tarde una cuota.
        2: _alDia()..[1] = _pago(6, 10, 30000),
        1: _alDia(),
        4: _alDia(),
        5: _alDia(),
      });
      expect(o.map((p) => p.grupo.numero), [1, 1, 1, 2, 3]);
      expect(o[3].alumno.nombreAlumno, 'F2');
      expect(o[4].alumno.nombreAlumno, 'F3');
      expect(o[4].inicioDelPlan, DateTime(2026, 11, 6));
    });

    test('en el grupo 1: quien canceló, por fecha; después, más cuotas cubiertas',
        () {
      final o = orden([
        _f(1),
        _f(2),
        _f(3),
        _f(4),
      ], {
        1: _alDia(),
        2: [_pago(6, 20, 270000)..['fecha_pago'] = DateTime.utc(2026, 4, 28, 15).toIso8601String()],
        3: [_pago(4, 8, 270000)],
        4: [..._alDia(), _pago(11, 2, 30000)],
      });
      expect(nombres(o), ['F3', 'F2', 'F4', 'F1']);
    });

    test('un día de atraso manda al grupo 2, aunque después haya cancelado', () {
      final o = orden([
        _f(1),
        _f(2),
      ], {
        1: _alDia(),
        2: [_pago(5, 1, 30000), _pago(5, 2, 240000)],
      });
      expect(nombres(o), ['F1', 'F2']);
      expect(o[1].grupo, GrupoDeCumplimiento.pagoTarde);
      expect(o[1].cumplimiento.canceloEl, isNotNull);
    });

    test('en el grupo 2: menos días; a igualdad, más cuotas en término', () {
      final o = orden([
        _f(1),
        _f(2),
        _f(3),
      ], {
        // 20 días en una cuota.
        1: _alDia()..[1] = _pago(6, 20, 30000),
        // 10 días en una cuota.
        2: _alDia()..[1] = _pago(6, 10, 30000),
        // 10 días repartidos en dos cuotas: una menos en término.
        3: _alDia()
          ..[1] = _pago(6, 5, 30000)
          ..[2] = _pago(7, 5, 30000),
      });
      expect(nombres(o), ['F2', 'F3', 'F1']);
    });

    test('en el grupo 3: el plan que empezó antes; a igualdad, más cuotas', () {
      final o = orden([
        _f(1),
        _f(2),
        _f(3),
        _f(4),
        _f(5, cuotas: 1, total: 310000),
        _f(6, cuotas: 3, total: 310000),
        _f(7, cuotas: 1, total: 310000),
      ], {
        for (var i = 1; i <= 4; i++) i: _alDia(),
        5: [_pago(11, 6, 310000, concepto: 'Cuota Base (1/1)')],
        6: [_pago(11, 6, 100000, concepto: 'Cuota Base (1/3)')],
        7: [_pago(10, 20, 310000, concepto: 'Cuota Base (1/1)')],
      });
      expect(nombres(o).skip(4), ['F7', 'F6', 'F5']);
    });

    test('sin ningún pago de base, o de baja, no entra', () {
      final o = orden([
        _f(1),
        _f(2),
        _f(3, nombre: '[BAJA] F3'),
      ], {
        1: _alDia(),
        2: [_pago(4, 30, 30000, concepto: 'Mesa extra (1/1)')],
        3: _alDia(),
      });
      expect(nombres(o), ['F1']);
    });

    test('"Siempre" va primero y "Nunca" no figura', () {
      final o = orden(
        [_f(1), _f(2), _f(3)],
        {
          1: _alDia(),
          2: _alDia().take(3).toList(),
          3: _alDia(),
        },
        siempre: {_id(2)},
        nunca: {_id(3)},
      );
      expect(nombres(o), ['F2', 'F1']);
      expect(o.first.aMano, isTrue);
      expect(o.first.frase, 'Elegida a mano.');
    });

    test('los empates, al azar: con el mismo Random, el mismo orden', () {
      final alumnos = [for (var i = 1; i <= 8; i++) _f(i)];
      final pagos = {for (var i = 1; i <= 8; i++) i: _alDia()};
      final a = nombres(orden(alumnos, pagos, semilla: 7));
      final b = nombres(orden(alumnos.reversed.toList(), pagos, semilla: 7));
      expect(a, b);
      final otros = {
        for (var s = 1; s <= 20; s++) nombres(orden(alumnos, pagos, semilla: s)).join(),
      };
      expect(otros.length, greaterThan(1));
      expect(orden(alumnos, pagos).every((p) => p.empatadas == 7), isTrue);
    });

    test('los puestos van del 1 al último, sin saltos', () {
      final o = orden(
        [for (var i = 1; i <= 5; i++) _f(i)],
        {for (var i = 1; i <= 5; i++) i: _alDia().take(i + 2).toList()},
      );
      expect(o.map((p) => p.puesto), [1, 2, 3, 4, 5]);
    });
  });

  group('la oración del porqué', () {
    String frase(
      ContratoAlumno a,
      List<Map<String, dynamic>> pagos, {
      int empatadas = 0,
      GrupoDeCumplimiento? grupo,
      DateTime? inicio,
      bool aMano = false,
    }) {
      final c = _de(a, pagos);
      return fraseDelPuesto(
        grupo: grupo ??
            (c.diasDeAtraso > 0
                ? GrupoDeCumplimiento.pagoTarde
                : GrupoDeCumplimiento.nuncaTarde),
        cumplimiento: c,
        aMano: aMano,
        inicioDelPlan: inicio,
        empatadas: empatadas,
        corte: _nov12,
      );
    }

    test('canceló sin atrasos', () {
      expect(frase(_f(1), [_pago(4, 8, 270000)]),
          'Nunca pagó tarde y terminó de pagar el 8 de abril.');
    });

    test('al día', () {
      expect(frase(_f(1), _alDia()),
          'Nunca pagó tarde. Lleva 7 de 9 cuotas pagas.');
    });

    test('pagó tarde', () {
      final pagos = _alDia()
        ..[1] = _pago(6, 10, 30000)
        ..[2] = _pago(7, 24, 30000);
      expect(frase(_f(1), pagos),
          'Pagó tarde 2 cuotas: 34 días de atraso en total.');
    });

    test('pagó tarde una y debe otra', () {
      final pagos = _alDia().take(6).toList()..[1] = _pago(6, 10, 30000);
      expect(frase(_f(1), pagos),
          'Pagó tarde 1 cuota y debe 1 cuota vencida: 22 días de atraso en total.');
    });

    test('solo debe', () {
      expect(frase(_f(1), _alDia().take(5).toList()),
          'Debe 2 cuotas vencidas: 55 días de atraso en total.');
    });

    test('plan nuevo', () {
      expect(
        frase(_f(1), const [],
            grupo: GrupoDeCumplimiento.planNuevo,
            inicio: DateTime(2026, 11, 6)),
        'Rehízo su plan de pago el 6 de noviembre.',
      );
    });

    test('a mano', () {
      expect(frase(_f(1), _alDia(), aMano: true), 'Elegida a mano.');
    });

    test('con empate', () {
      expect(
        frase(_f(1), _alDia(), empatadas: 3),
        'Nunca pagó tarde. Lleva 7 de 9 cuotas pagas. '
        'Empató con otras 3 familias: entre ellas se sorteó.',
      );
      expect(frase(_f(1), _alDia(), empatadas: 1),
          endsWith('Empató con otra familia: entre ellas se sorteó.'));
    });

    test('ninguna dice "mora" ni "deuda"', () {
      final todas = [
        frase(_f(1), [_pago(4, 8, 270000)]),
        frase(_f(1), _alDia()),
        frase(_f(1), _alDia().take(5).toList()),
        frase(_f(1), const [], grupo: GrupoDeCumplimiento.planNuevo),
        frase(_f(1), _alDia(), aMano: true),
      ].join(' ').toLowerCase();
      expect(todas, isNot(contains('mora')));
      expect(todas, isNot(contains('deuda')));
    });
  });
}
