import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
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
      expect(display[1]['display'], 'Mora (interés por atraso, 27 días)');
      expect(display[1]['anidada'], isTrue);
      expect(display[1]['arrastre'], isNot(true));
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

  group('compactarCuotasBaseParaResumenPdf', () {
    test('compacta cuotas consecutivas sin mora', () {
      final finales = _finales(
        [_previewBase(), _previewBase(), _previewBase()],
        cPagadas: 0,
      );
      final out = compactarCuotasBaseParaResumenPdf(finales);
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
      final out = compactarCuotasBaseParaResumenPdf(finales);
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
}
