// Cada línea de mora va a lo que dice su concepto (spec del 14-nov-2026,
// `docs/SPEC_remanente_mora_por_concepto_2026-11-14.md`, sección 7.1).
//
// Familias inventadas (F1 a F5): contrato de 9 cuotas de $30.000, alta el
// 30/03/2026, la cuota 1 vence el 30/04 y la mora es de $300 por día. La regla
// de la 6.8.0 corre al lado (`InferirDeLa680`) para ver qué cambia.

import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/eventos/services/concepto_pago_display.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/inferir_de_la_6_8_0.dart';

ContratoAlumno _contrato({double saldo = 150000}) => ContratoAlumno(
      id: 'f',
      eventoId: 'ev',
      nombreAlumno: 'FAMILIA, INVENTADA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      totalCuotas: 9,
      cuotasPagadas: 0,
      saldoDeudor: saldo,
      createdAt: DateTime.parse('2026-03-30T03:00:00+00:00'),
    );

var _n = 0;

Map<String, dynamic> _pago(String fecha, String concepto, double monto) {
  final esMora = esPagoInteresMoraPorConcepto(concepto);
  return {
    'id': 'p${_n++}',
    'concepto': concepto,
    'monto': monto,
    'monto_gross': monto,
    'fecha_pago': '${fecha}T15:00:00-03:00',
    'anulado': 0,
    if (esMora) 'line_kind': kLineKindInteresMora,
  };
}

/// Lo que importa de un origen, para comparar con la tabla de la spec.
String _o(MoraPendientePreviaDetalle d) =>
    'C${d.numeroCuota} ${d.mesLabel} ${d.montoAtribuido.toStringAsFixed(0)} '
    '${d.diasMora}d cobrada ${d.moraCobrada.toStringAsFixed(0)}';

double _suma(List<MoraPendientePreviaDetalle> l) =>
    l.fold<double>(0, (s, d) => s + d.montoAtribuido);

/// Las dos reglas sobre la misma ficha.
({List<MoraPendientePreviaDetalle> hoy, List<MoraPendientePreviaDetalle> antes})
    _ficha(ContratoAlumno c, List<Map<String, dynamic>> pagos, double tracked) {
  return (
    hoy: MoraTrackedOrigen.inferir(
      contratoBase: c,
      pagos: pagos,
      trackedMonto: tracked,
      recorte: MoraOrigenRecorte.loQueQueda,
    ),
    antes: InferirDeLa680.inferir(
      contratoBase: c,
      pagos: pagos,
      trackedMonto: tracked,
      recorte: MoraOrigenRecorte.loQueQueda,
    ),
  );
}

void main() {
  group('F1: pagó el arrastre viejo y no la mora de lo que liquidó', () {
    final c = _contrato(saldo: 149900);
    final linea = _pago(
      '2026-11-12',
      'Mora pendiente cuotas 1 y 2 (no cobrada al pagar)',
      39300,
    );
    final pagos = [
      _pago('2026-07-20', 'Cuota Base (1/9)', 30000),
      _pago('2026-07-20', 'Cuota Base (2/9)', 30000),
      _pago('2026-11-12', 'Cuota Base (3/9)', 30000),
      _pago('2026-11-12', 'Cuota Base (4/9)', 30000),
      _pago('2026-11-12', 'Entrega parcial — Cuota Base (5/9)', 100),
      linea,
    ];

    test('1. la ficha nombra las cuotas 3 y 4, no la 1 y la 2', () {
      final r = _ficha(c, pagos, 71700);
      expect(r.hoy.map(_o), [
        'C3 Jun 2026 40500 135d cobrada 0',
        'C4 Jul 2026 31200 104d cobrada 0',
      ]);
      expect(r.hoy.first.moraDebida, 40500);
      expect(
        MoraTrackedOrigen.sinExplicar(tracked: 71700, origen: r.hoy),
        0,
      );
      // La 6.8.0 decía abril y mayo, ya pagados.
      expect(r.antes.map((d) => d.numeroCuota), [1, 2, 3, 4]);
      expect(r.antes.map((d) => d.montoAtribuido), [24300, 15000, 1200, 31200]);
    });

    test('2. el recibo del 12/11 sigue diciendo las cuotas 1 y 2', () {
      List<MoraPendientePreviaDetalle> correr(bool hoy) {
        final args = (
          antesDe: DateTime.utc(2026, 11, 12, 3),
          excluir: linea['id'] as String,
        );
        return hoy
            ? MoraTrackedOrigen.inferir(
                contratoBase: c,
                pagos: pagos,
                trackedMonto: 39300,
                antesDe: args.antesDe,
                excluirPagoId: args.excluir,
              )
            : InferirDeLa680.inferir(
                contratoBase: c,
                pagos: pagos,
                trackedMonto: 39300,
                antesDe: args.antesDe,
                excluirPagoId: args.excluir,
              );
      }

      final hoy = correr(true);
      expect(hoy.map(_o), [
        'C1 Abr 2026 24300 81d cobrada 0',
        'C2 May 2026 15000 50d cobrada 0',
      ]);
      expect(correr(false).map(_o), hoy.map(_o));
    });
  });

  test('3. F2: una línea de calendario que paga toda la mora de su cuota, '
      'igual que en la 6.8.0', () {
    final c = _contrato(saldo: 180000);
    final pagos = [
      _pago('2026-05-30', 'Cuota Base (1/9)', 30000),
      _pago('2026-05-30', 'Cuota Base (2/9)', 30000),
      _pago('2026-07-10', 'Cuota Base (3/9)', 30000),
      _pago('2026-07-10', 'Interés mora cuota 3 (vto Jun 2026)', 3000),
    ];
    final r = _ficha(c, pagos, 9000);
    expect(r.hoy.map(_o), ['C1 Abr 2026 9000 30d cobrada 0']);
    expect(r.antes.map(_o), r.hoy.map(_o));
  });

  group('F3: línea mixta (calendario + arrastre) que no alcanza para todo', () {
    test('4. desde la v4.9 paga primero el arrastre', () {
      final c = _contrato(saldo: 150000);
      final pagos = [
        _pago('2026-05-30', 'Cuota Base (1/9)', 30000),
        _pago('2026-05-30', 'Cuota Base (2/9)', 30000),
        _pago('2026-06-30', 'Cuota Base (3/9)', 30000),
        _pago('2026-09-09', 'Cuota Base (4/9)', 30000),
        _pago(
          '2026-09-09',
          'Interés mora cuota 4 (vto Jul 2026) + mora pendiente cuota 1',
          15000,
        ),
      ];
      final r = _ficha(c, pagos, 6000);
      expect(r.hoy.map(_o), ['C4 Jul 2026 6000 40d cobrada 6000']);
      expect(r.hoy.single.moraDebida, 12000);
      expect(r.antes.map(_o), ['C1 Abr 2026 6000 30d cobrada 3000']);
    });

    test('5. antes del 21/08/2026 pagaba primero el calendario, y así queda',
        () {
      final c = _contrato(saldo: 180000);
      final pagos = [
        _pago('2026-05-30', 'Cuota Base (1/9)', 30000),
        _pago('2026-05-30', 'Cuota Base (2/9)', 30000),
        _pago('2026-08-09', 'Cuota Base (3/9)', 30000),
        _pago(
          '2026-08-09',
          'Interés mora cuota 3 (vto Jun 2026) + mora pendiente cuota 1',
          15000,
        ),
      ];
      final r = _ficha(c, pagos, 6000);
      expect(r.hoy.map(_o), ['C1 Abr 2026 6000 30d cobrada 3000']);
      expect(r.antes.map(_o), r.hoy.map(_o));
    });
  });

  test('6. F4: la línea de calendario va a la cuota que nombra, no a la más '
      'vieja del lote', () {
    final c = _contrato(saldo: 90000);
    final pagos = [
      _pago('2026-04-20', 'Cuota Base (1/9)', 30000),
      _pago('2026-05-20', 'Cuota Base (2/9)', 30000),
      _pago('2026-06-20', 'Cuota Base (3/9)', 30000),
      _pago('2026-07-20', 'Cuota Base (4/9)', 30000),
      _pago('2026-10-20', 'Cuota Base (5/9)', 30000),
      _pago('2026-10-20', 'Cuota Base (6/9)', 30000),
      _pago('2026-10-20', 'Interés mora cuota 6 (vto Sep 2026)', 6000),
    ];
    final r = _ficha(c, pagos, 15000);
    expect(r.hoy.map(_o), ['C5 Ago 2026 15000 50d cobrada 0']);
    expect(r.antes.map(_o), [
      'C5 Ago 2026 9000 50d cobrada 6000',
      'C6 Sep 2026 6000 20d cobrada 0',
    ]);
  });

  test('7. F5: una línea solo de arrastre que nombra la cuota, con un perdón '
      'antes', () {
    final c = _contrato(saldo: 180000);
    final pagos = [
      _pago('2026-05-30', 'Cuota Base (1/9)', 30000),
      _pago('2026-06-30', 'Cuota Base (2/9)', 30000),
      _pago('2026-09-09', 'Cuota Base (3/9)', 30000),
      _pago(
        '2026-09-09',
        'Mora pendiente cuota 2 (no cobrada al pagar)',
        9000,
      ),
    ];
    // El perdón de los $9.000 de la cuota 1 no está en los pagos: la ficha
    // tiene $21.300 y no $30.300.
    final r = _ficha(c, pagos, 21300);
    expect(r.hoy.map(_o), ['C3 Jun 2026 21300 71d cobrada 0']);
    expect(r.antes.map((d) => '${d.numeroCuota} ${d.montoAtribuido}'),
        ['2 9000.0', '3 12300.0']);
  });

  group('8. qué dice cada concepto', () {
    final casos = <String, (bool, List<int>)>{
      'Interés mora cuota 3 (vto Jun 2026)': (false, [3]),
      'Interés mora cuota 3 (Jun 2026)': (false, [3]),
      'INTERES MORA CUOTA 12 (VTO OCT 2026)': (false, [12]),
      'Interés mora cuotas 3, 4 (vto Jun, Jul)': (false, [3, 4]),
      'Interes mora cuotas 5,6, 7 (Ago, Sep, Oct)': (false, [5, 6, 7]),
      'Interés mora (cuota base — este cobro)': (false, []),
      'Interés mora cuotas 3, 4 + mora pendiente cuota 2': (true, [3, 4]),
      'Interés mora cuota 7 (vto Oct 2026) + mora pendiente cuota 6':
          (true, [7]),
      'Mora pendiente cuotas 1 y 2 (no cobrada al pagar)': (true, []),
      'MORA PENDIENTE CUOTA 3 (NO COBRADA AL PAGAR)': (true, []),
      'Mora pendiente de cuotas ya pagadas (no cobrada al pagar)': (true, []),
      'Interés mora cuota 4 (Jul 2026) + Remanente': (true, [4]),
      // NFD: la tilde como marca aparte.
      'Interés mora cuota 3 (vto Jun 2026)': (false, [3]),
    };
    for (final e in casos.entries) {
      test(e.key, () {
        expect(mencionaArrastre(e.key), e.value.$1);
        expect(cuotasDeCalendarioEnConcepto(e.key), e.value.$2);
      });
    }
  });

  test('9. la suma no cambia: solo de qué cuotas se dice que es', () {
    // F1, F3, F4 y F5 con las dos reglas: los totales de los casos de arriba.
    final c = _contrato(saldo: 149900);
    final pagos = [
      _pago('2026-07-20', 'Cuota Base (1/9)', 30000),
      _pago('2026-07-20', 'Cuota Base (2/9)', 30000),
      _pago('2026-11-12', 'Cuota Base (3/9)', 30000),
      _pago('2026-11-12', 'Cuota Base (4/9)', 30000),
      _pago(
        '2026-11-12',
        'Mora pendiente cuotas 1 y 2 (no cobrada al pagar)',
        39300,
      ),
    ];
    // Un monto más grande que la ficha, para que se vea toda la cola.
    final r = (
      hoy: MoraTrackedOrigen.inferir(
        contratoBase: c,
        pagos: pagos,
        trackedMonto: 999999,
      ),
      antes: InferirDeLa680.inferir(
        contratoBase: c,
        pagos: pagos,
        trackedMonto: 999999,
      ),
    );
    expect(_suma(r.hoy), closeTo(_suma(r.antes), 0.01));
    expect(_suma(r.hoy), 71700);
  });

  group('10. parte B: la reimpresión de una línea mixta', () {
    test('cuota 7 + arrastre de la 6 que no alcanza: primero la 6', () {
      final c = _contrato(saldo: 60000);
      final linea = _pago(
        '2026-11-05',
        'Interés mora cuota 7 (vto Oct 2026) + mora pendiente cuota 6',
        1810,
      );
      final pagos = [
        _pago('2026-04-20', 'Cuota Base (1/9)', 30000),
        _pago('2026-05-20', 'Cuota Base (2/9)', 30000),
        _pago('2026-06-20', 'Cuota Base (3/9)', 30000),
        _pago('2026-07-20', 'Cuota Base (4/9)', 30000),
        _pago('2026-08-20', 'Cuota Base (5/9)', 30000),
        // La 6 vence el 30/09: 3 días tarde, sin su mora ($900 de arrastre).
        _pago('2026-10-03', 'Cuota Base (6/9)', 30000),
        _pago('2026-11-05', 'Cuota Base (7/9)', 30000),
        linea,
      ];
      final lineas = ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
        c,
        [pagos[6], linea],
        historialCompleto: pagos,
      ).where((l) => l['esMora'] == true).toList();
      expect(
        lineas.map((l) => '${l['cuotaPrevia'] ?? '-'} '
            '${l['numeroCuota'] ?? '-'} ${l['monto']}'),
        // El recibo ordena el calendario antes que el arrastre.
        unorderedEquals(['6 - 900.0', '- 7 910.0']),
      );
      final la7 = lineas.firstWhere((l) => l['numeroCuota'] == 7);
      expect(la7['concepto'], contains('(parcial)'));
      expect(la7['montoPleno'], 1500);
    });

    test('cuotas 3, 4 + arrastre de la 2: la 2, la 3 entera y la 4 parcial',
        () {
      final f = _familiaDel14();
      final lineas = ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
        f.c,
        f.loteDel12,
        historialCompleto: f.pagos,
      ).where((l) => l['esMora'] == true).toList();
      expect(
        lineas.map((l) => '${l['cuotaPrevia'] ?? '-'} '
            '${l['numeroCuota'] ?? '-'} ${l['monto']}'),
        unorderedEquals(['2 - 350.0', '- 3 47250.0', '- 4 27400.0']),
      );
    });
  });

  group('11. parte C: el Estado de cuenta nombra el mes de cada cuota', () {
    final c = _contrato();
    final casos = {
      'Mora pendiente cuotas 1 y 2 (no cobrada al pagar)':
          'Mora cuota 1 (vto Abr 2026) y cuota 2 (vto May 2026)',
      'Mora pendiente cuota 3 (no cobrada al pagar)':
          'Mora cuota 3 (vto Jun 2026)',
      'Interés mora cuota 7 (vto Oct 2026) + mora pendiente cuota 6':
          'Interés mora cuota 7 (vto Oct 2026) + mora cuota 6 (vto Sep 2026)',
      'Interés mora cuota 3 (vto Jun 2026)': 'Interés mora cuota 3 (vto Jun 2026)',
    };
    for (final e in casos.entries) {
      test(e.key, () {
        expect(
          MoraConceptoRotulo.rotuloFichaMora(e.key, contrato: c).titulo,
          e.value,
        );
      });
    }
    test('sin la fecha de alta, como antes', () {
      expect(
        MoraConceptoRotulo.rotuloFichaMora(
          'Mora pendiente cuotas 1 y 2 (no cobrada al pagar)',
        ).titulo,
        'Mora de las cuotas 1 y 2',
      );
    });
    test('el subtexto no cambia', () {
      expect(
        MoraConceptoRotulo.rotuloFichaMora(
          'Mora pendiente cuotas 1 y 2 (no cobrada al pagar)',
          contrato: c,
        ).subtexto,
        'Quedaba de cuando se pagaron esas cuotas · se cobró en este pago',
      );
    });
  });

  group('parte D: las filas del arrastre ya guardadas', () {
    String ficha(ContratoAlumno c, List<Map<String, dynamic>> pagos, String id) {
      final filas = ConceptoPagoDisplay.enriquecerPagosHistorial(c, pagos);
      return filas.firstWhere((p) => p['id'] == id)['concepto_ficha'] as String;
    }

    List<int> reimpresas(
      ContratoAlumno c,
      List<Map<String, dynamic>> lote,
      List<Map<String, dynamic>> pagos,
    ) {
      return [
        for (final l in ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
          c,
          lote,
          historialCompleto: pagos,
        ))
          if (l['cuotaPrevia'] != null) (l['cuotaPrevia'] as num).toInt(),
      ];
    }

    test('D1. la línea del 14/11 ya no nombra la cuota 2', () {
      final f = _familiaDel14();
      expect(
        ficha(f.c, f.pagos, f.lineaDel14['id'] as String),
        'Mora cuota 4 (vto Jul 2026), cuota 5 (vto Ago 2026), '
        'cuota 6 (vto Sep 2026) y cuota 7 (vto Oct 2026)',
      );
      final det = ConceptoPagoDisplay.arrastreDeUnaLinea(
        contrato: f.c,
        pago: f.lineaDel14,
        historial: f.pagos,
        monto: 53800,
      );
      expect(det.map((d) => d.montoAtribuido), [9000, 25550, 15050, 4200]);
    });

    test('D2. la mixta del 12/11: el calendario igual, el sufijo con su mes',
        () {
      final f = _familiaDel14();
      expect(
        ficha(f.c, f.pagos, f.lineaDel12['id'] as String),
        'Interés mora cuotas 3, 4 + mora cuota 2 (vto May 2026)',
      );
      final det = ConceptoPagoDisplay.arrastreDeUnaLinea(
        contrato: f.c,
        pago: f.lineaDel12,
        historial: f.pagos,
        monto: 75000,
      );
      expect(det.map((d) => '${d.numeroCuota} ${d.montoAtribuido}'),
          ['2 350.0']);
    });

    test('D3. un concepto que ya estaba bien sigue igual, con el mes', () {
      final f = _familiaF1();
      expect(
        ficha(f.c, f.pagos, f.linea['id'] as String),
        'Mora cuota 1 (vto Abr 2026) y cuota 2 (vto May 2026)',
      );
    });

    test('D4. sin historial para reconstruir: los números del texto', () {
      final c = _contrato();
      final linea = _pago(
        '2026-09-09',
        'Mora pendiente cuota 3 (no cobrada al pagar)',
        5000,
      );
      expect(ficha(c, [linea], linea['id'] as String),
          'Mora cuota 3 (vto Jun 2026)');
    });

    test('D5. la reconstrucción no cubre el monto: los números del texto', () {
      final c = _contrato(saldo: 210000);
      final linea = _pago(
        '2026-09-09',
        'Mora pendiente cuota 2 (no cobrada al pagar)',
        20000,
      );
      final pagos = [
        // La 1 vence el 30/04: 30 días tarde, $9.000 de arrastre.
        _pago('2026-05-30', 'Cuota Base (1/9)', 30000),
        linea,
      ];
      expect(ficha(c, pagos, linea['id'] as String),
          'Mora cuota 2 (vto May 2026)');
    });

    test('D6. el Estado de cuenta y la reimpresión nombran las mismas cuotas',
        () {
      final f = _familiaDel14();
      expect(reimpresas(f.c, [f.lineaDel14], f.pagos), [4, 5, 6, 7]);
      expect(reimpresas(f.c, f.loteDel12, f.pagos), [2]);
      final f1 = _familiaF1();
      expect(reimpresas(f1.c, [f1.linea], f1.pagos), [1, 2]);
    });

    test('D7. una fila que no es del arrastre no cambia', () {
      final c = _contrato(saldo: 210000);
      final linea = _pago(
        '2026-07-10',
        'Interés mora cuota 3 (vto Jun 2026)',
        3000,
      );
      final pagos = [
        _pago('2026-04-20', 'Cuota Base (1/9)', 30000),
        _pago('2026-05-20', 'Cuota Base (2/9)', 30000),
        _pago('2026-07-10', 'Cuota Base (3/9)', 30000),
        linea,
      ];
      expect(ficha(c, pagos, linea['id'] as String),
          'Interés mora cuota 3 (vto Jun 2026)');
    });
  });
}

/// F1 de la spec: el 12/11 paga la mora de las cuotas 1 y 2 y liquida la 3 y
/// la 4 sin su mora.
({
  ContratoAlumno c,
  List<Map<String, dynamic>> pagos,
  Map<String, dynamic> linea,
}) _familiaF1() {
  final linea = _pago(
    '2026-11-12',
    'Mora pendiente cuotas 1 y 2 (no cobrada al pagar)',
    39300,
  );
  return (
    c: _contrato(saldo: 149900),
    pagos: [
      _pago('2026-07-20', 'Cuota Base (1/9)', 30000),
      _pago('2026-07-20', 'Cuota Base (2/9)', 30000),
      _pago('2026-11-12', 'Cuota Base (3/9)', 30000),
      _pago('2026-11-12', 'Cuota Base (4/9)', 30000),
      linea,
    ],
    linea: linea,
  );
}

/// Una familia inventada con la forma del cobro que se reclamó el 14-nov:
/// cuotas de $35.000 ($350 por día de mora). La cuota 2 se pagó un día tarde
/// sin su mora; el 12/11 liquidó de la 3 a la 7 y pagó $75.000 de mora (la 2,
/// la 3 entera y parte de la 4); el 14/11 pagó los $53.800 que quedaban.
({
  ContratoAlumno c,
  List<Map<String, dynamic>> pagos,
  List<Map<String, dynamic>> loteDel12,
  Map<String, dynamic> lineaDel12,
  Map<String, dynamic> lineaDel14,
}) _familiaDel14() {
  final c = ContratoAlumno(
    id: 'f14',
    eventoId: 'ev',
    nombreAlumno: 'FAMILIA, INVENTADA',
    cantidadAcompanantes: 0,
    montoTotalPactado: 315000,
    totalCuotas: 9,
    cuotasPagadas: 7,
    saldoDeudor: 70000,
    createdAt: DateTime.parse('2026-03-30T03:00:00+00:00'),
  );
  final lineaDel12 = _pago(
    '2026-11-12',
    'Interés mora cuotas 3, 4 + mora pendiente cuota 2',
    75000,
  );
  final loteDel12 = [
    for (var n = 3; n <= 7; n++) _pago('2026-11-12', 'Cuota Base ($n/9)', 35000),
    lineaDel12,
  ];
  final lineaDel14 = _pago(
    '2026-11-14',
    'Mora pendiente cuotas 2, 4, 5, 6 y 7 (no cobrada al pagar)',
    53800,
  );
  return (
    c: c,
    pagos: [
      _pago('2026-04-25', 'Cuota Base (1/9)', 35000),
      _pago('2026-06-01', 'Cuota Base (2/9)', 35000),
      ...loteDel12,
      lineaDel14,
    ],
    loteDel12: loteDel12,
    lineaDel12: lineaDel12,
    lineaDel14: lineaDel14,
  );
}
