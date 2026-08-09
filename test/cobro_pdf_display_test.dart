import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:flutter_test/flutter_test.dart';

/// Preview de una cuota base tal como lo arma el modal de cobro masivo.
Map<String, dynamic> _previewBase({double monto = 30000}) => {
      'concepto': 'Cuota Base',
      'monto': monto,
      'gross': monto,
      'cuotas': 1,
    };

/// Preview de mora de calendario para la cuota [n].
Map<String, dynamic> _previewMora({
  required int n,
  required double monto,
  required int dias,
  String mesLabel = 'Jun 2026',
}) => {
      'concepto': 'Interés mora (cuota base — este cobro)',
      'monto': monto,
      'lineKind': 'interes_mora',
      'moraDesglose': <Map<String, dynamic>>[
        {
          'numeroCuota': n,
          'mesLabel': mesLabel,
          'monto': monto,
          'diasMora': dias,
        },
      ],
    };

List<Map<String, dynamic>> _finales(
  List<Map<String, dynamic>> preview, {
  int cPagadas = 2,
  int tCuotas = 9,
}) =>
    conceptosFinalesDesdePreviewMasivo(
      previewConceptos: preview,
      esLineaCargoCanal: (c) => c['lineKind'] == 'cargo_canal_ref',
      esLineaInteresMora: (c) => c['lineKind'] == 'interes_mora',
      cPagadas: cPagadas,
      tCuotas: tCuotas,
      mPagadas: 0,
      mCuotas: 1,
      sPagadas: 0,
      sCuotas: 1,
    );

void main() {
  // Bernel: cuota 3 de 9, Reg 30-mar-2026 → vence 30-jun; al 27-jul son 27 días.
  final regAr = DateTime(2026, 3, 30);
  final hoyAr = DateTime(2026, 7, 27);

  group('lineasDisplayParaPdf — anidado de la mora bajo su cuota', () {
    test('la mora de la cuota N queda pegada a la cuota N y sangrada', () {
      final finales = _finales([
        _previewBase(),
        _previewMora(n: 3, monto: 8100, dias: 27),
      ]);
      final display = lineasDisplayParaPdf(finales, regAr: regAr, hoyAr: hoyAr);

      expect(display.length, 2);
      expect(display[0]['display'], 'Cuota 3 de 9 — venció 30/06/2026');
      expect(display[0]['anidada'], isNot(true));
      expect(display[1]['display'], 'Mora — 27 días fuera de término');
      expect(display[1]['anidada'], isTrue);
      expect(display[1]['arrastre'], isNot(true));
    });

    test('cobro de sola mora: la línea nombra su cuota, no queda huérfana', () {
      // Recibo Nº 0661293D (BERNEL, 07/08/2026): se cobró únicamente mora, así
      // que no hay renglón de cuota del que colgarla. Sin nombrar la cuota, la
      // línea salía "Mora · 7 d" y no había forma de saber a cuál correspondía
      // — justo cuando el aviso de abajo hablaba de "cuota 4 (Jul, 7 d)".
      final finales = _finales([
        _previewMora(n: 4, monto: 2100, dias: 7, mesLabel: 'Jul 2026'),
      ], cPagadas: 3);
      final display = lineasDisplayParaPdf(finales, regAr: regAr, hoyAr: hoyAr);

      expect(display.single['display'], 'Mora de la cuota 4 — 7 días fuera de término');
      expect(display.single['anidada'], isNot(true));
      expect(display.single['arrastre'], isTrue);
      // Y abreviada, cuando el papel no entra, sigue diciendo la cuota.
      expect(
        abreviarDisplayPdf(display.single['display'] as String),
        'Mora cuota 4',
      );
    });

    test('cuota que todavía no venció dice "vence", no "venció"', () {
      final finales = _finales([_previewBase()], cPagadas: 3);
      final display = lineasDisplayParaPdf(
        finales,
        regAr: regAr,
        // Cuota 4 vence 31-jul: al 27-jul sigue en fecha.
        hoyAr: hoyAr,
      );
      expect(display.single['display'], 'Cuota 4 de 9 — vence 31/07/2026');
    });

    test('mora de cuotas ya pagadas va al bloque de arrastre, sin anidar', () {
      final finales = _finales([
        _previewBase(),
        {
          'concepto': 'Mora pendiente de cuotas ya pagadas',
          'monto': 6900.0,
          'lineKind': 'interes_mora',
        },
      ]);
      final display = lineasDisplayParaPdf(finales, regAr: regAr, hoyAr: hoyAr);

      final arrastre = display.where((c) => c['arrastre'] == true).toList();
      expect(arrastre.length, 1);
      expect(arrastre.single['anidada'], isNot(true));
      expect(
        arrastre.single['display'],
        'Mora de cuotas anteriores, no cobrada en su momento',
      );
      // Y va después de la cuota, no intercalada.
      expect(display.last['arrastre'], isTrue);
    });

    test('sin Reg no imprime vencimiento pero mantiene el rótulo', () {
      final finales = _finales([_previewBase()]);
      final display = lineasDisplayParaPdf(finales);
      expect(display.single['display'], 'Cuota 3 de 9');
    });

    test('cargo de canal se llama "Costo por transferencia"', () {
      final finales = _finales([
        {
          'concepto': 'Cargo canal / operador (ref. MP u otro)',
          'monto': 2000.0,
          'lineKind': 'cargo_canal_ref',
        },
      ]);
      final display = lineasDisplayParaPdf(finales);
      expect(display.single['display'], 'Costo por transferencia');
    });
  });

  group('compactarCuotasBaseParaPdf', () {
    test('compacta cuotas consecutivas sin mora', () {
      final finales = _finales(
        [_previewBase(), _previewBase(), _previewBase()],
        cPagadas: 0,
      );
      final out = compactarCuotasBaseParaPdf(finales);
      expect(out.length, 1);
      expect(out.single['concepto'], 'Cuotas base (1–3/9)');
    });

    test('no compacta un tramo con mora anidada', () {
      // Si fusionara, el interés de la cuota 1 colgaría de una línea que ya no
      // la nombra.
      final finales = _finales(
        [
          _previewBase(),
          _previewBase(),
          _previewMora(n: 1, monto: 3000, dias: 10, mesLabel: 'Abr 2026'),
        ],
        cPagadas: 0,
      );
      final out = compactarCuotasBaseParaPdf(finales);
      final bases = out.where((c) => c['esPlanLiquidacion'] == true).toList();
      expect(bases.length, 2);
      expect(bases.first['concepto'], 'Cuota Base (1/9)');
    });
  });

  group('blindaje: el display no toca las claves que persisten', () {
    test('concepto original intacto tras el display', () {
      final finales = _finales([
        _previewBase(),
        _previewMora(n: 3, monto: 8100, dias: 27),
      ]);
      final display = lineasDisplayParaPdf(finales, regAr: regAr, hoyAr: hoyAr);

      // 'concepto' es lo que leen esPagoInteresMoraPorConcepto,
      // MoraTrackedRecovery._esBaseCuota y recalcularSaldoDesdePagos.
      expect(display[0]['concepto'], 'Cuota Base (3/9)');
      expect(display[1]['concepto'], 'Interés mora cuota 3 (vto Jun 2026)');
      // El rótulo nuevo vive en una clave aparte.
      expect(display[0]['display'], isNot(display[0]['concepto']));
    });

    test('montos y banderas sobreviven al reordenamiento', () {
      final finales = _finales([
        _previewBase(),
        _previewMora(n: 3, monto: 8100, dias: 27),
      ]);
      final display = lineasDisplayParaPdf(finales, regAr: regAr, hoyAr: hoyAr);

      expect(display[0]['monto'], closeTo(30000, 0.01));
      expect(display[0]['esPlanLiquidacion'], isTrue);
      expect(display[1]['monto'], closeTo(8100, 0.01));
      expect(display[1]['esMora'], isTrue);
      final total = display.fold<double>(
        0,
        (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
      );
      expect(total, closeTo(38100, 0.01));
    });
  });

  group('el arrastre parcial llega igual por los dos caminos', () {
    // C2 $6.900 y C3 $8.100 en ficha; la familia entrega $10.000: cubre la C2
    // entera y $3.100 de la C3. Esa C3 es la que tiene que quedar marcada.
    final detallePendiente = [
      const MoraPendientePreviaDetalle(
        numeroCuota: 2,
        mesLabel: 'May 2026',
        montoAtribuido: 6900,
        diasMora: 23,
      ),
      const MoraPendientePreviaDetalle(
        numeroCuota: 3,
        mesLabel: 'Jun 2026',
        montoAtribuido: 8100,
        diasMora: 27,
      ),
    ];

    Map<String, dynamic> previewParcial() =>
        MoraConceptoRotulo.construirPreviewMora(
          montoTotal: 10000,
          detallesCalendario: const [],
          montoPendientePrevias: 15000,
          lineKind: 'interes_mora',
          detallePendiente: detallePendiente,
        );

    List<String> conceptosDe(List<Map<String, dynamic>> lineas) =>
        lineas.map((l) => l['concepto'] as String).toList();

    test('vía conceptosFinalesDesdePreviewMasivo (cobro real)', () {
      final finales = _finales([previewParcial()]);

      expect(conceptosDe(finales), [
        'Mora pendiente cuota 2',
        'Mora pendiente cuota 3${MoraConceptoRotulo.sufijoParcial}',
      ]);
      expect(
        finales.fold<double>(0, (s, l) => s + (l['monto'] as num).toDouble()),
        closeTo(10000, 0.01),
      );
    });

    test('vía filasPreviewDesdeMora (grilla del modal) — mismo resultado', () {
      final filas = MoraConceptoRotulo.filasPreviewDesdeMora(previewParcial());

      expect(conceptosDe(filas), conceptosDe(_finales([previewParcial()])));
    });
  });
}
