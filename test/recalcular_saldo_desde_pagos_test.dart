import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/calculadora_financiera.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';

/// Simula la heurística vieja de auditoría que inflaba monto_gross.
double _grossInfladoLegacy({
  required double montoNeto,
  required double montoGrossOriginal,
  required double cuotaPura,
  required String concepto,
}) {
  final c = concepto.toLowerCase();
  final esEntregaParcial = c.contains('entrega') ||
      c.contains('adelanto') ||
      c.contains('parcial') ||
      c.contains('abono');
  var targetCant = 0;
  final matchCuotas = RegExp(r'(\d+)\s+cuota').firstMatch(c);
  if (matchCuotas != null) {
    targetCant = int.parse(matchCuotas.group(1)!);
  } else if (!esEntregaParcial && c.contains('cuota')) {
    targetCant = 1;
  }
  final targetGross = cuotaPura * targetCant;
  final debeInflar =
      cuotaPura > 0 && targetCant > 0 && montoNeto < (targetGross - 0.1);
  return CalculadoraFinanciera.montoGrossAcumuladoEnAuditoria(
    montoNeto: montoNeto,
    montoGrossOriginal: montoGrossOriginal,
    debeInflar: debeInflar,
    targetGrossTotal: targetGross,
    totalMontoGrupoNeto: montoNeto,
    lineasEnGrupo: 1,
  );
}

void main() {
  group('recalcularSaldoDesdePagos — regresión auditoría', () {
    const pactado = 270000.0;
    const totalCuotas = 9;
    const cuotaPura = 30000.0;

    RecalculoContratoDesdePagos recalc(List<Map<String, dynamic>> pagos) =>
        recalcularSaldoDesdePagos(
          montoTotalPactado: pactado,
          totalCuotas: totalCuotas,
          mesaExtraPrecio: 0,
          sillasExtraPrecioTotal: 0,
          precioUnitarioMesaExtra: 0,
          mesaExtraCuotas: 0,
          mesaExtraCantidad: 0,
          sillasExtraCuotas: 0,
          pagos: pagos,
        );

    test('Chamorro: hist 83.500 + cobro 66.500 → saldo 120.000', () {
      final pagos = [
        {
          'anulado': 0,
          'concepto': '2 Cuotas (Cuota Base) + Adelanto Cuota Base (3/9) · \$23.500,00',
          'monto': 83500,
          'monto_gross': 83500,
          'fecha_pago': '2025-03-01T10:00:00',
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (3/9) — Completada',
          'monto': 6500,
          'monto_gross': 6500,
          'fecha_pago': '2025-06-15T10:00:00',
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (4/9)',
          'monto': 30000,
          'monto_gross': 30000,
          'fecha_pago': '2025-06-15T10:01:00',
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (5/9)',
          'monto': 30000,
          'monto_gross': 30000,
          'fecha_pago': '2025-06-15T10:02:00',
        },
      ];

      final r = recalc(pagos);
      expect(r.saldoDeudor, closeTo(120000, 0.01));
      expect(r.cuotasBase, 5);
      expect(r.grossBase, closeTo(150000, 0.01));

      final infladoC3 = _grossInfladoLegacy(
        montoNeto: 6500,
        montoGrossOriginal: 6500,
        cuotaPura: cuotaPura,
        concepto: 'Cuota Base (3/9) — Completada',
      );
      expect(infladoC3, closeTo(30000, 0.01));
      expect(infladoC3, isNot(closeTo(6500, 0.01)));
    });

    test('Jazmín: C3 Completada gross 26.000 no debe inflarse a 28.000', () {
      const pactadoJ = 252000.0;
      const cuotaPuraJ = 28000.0;

      final pagos = [
        {
          'anulado': 0,
          'concepto': 'Cuota Base (1/9)',
          'monto': 30000,
          'monto_gross': 30000,
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (2/9)',
          'monto': 28000,
          'monto_gross': 28000,
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (3/9) — Completada',
          'monto': 26000,
          'monto_gross': 26000,
        },
      ];

      final r = recalcularSaldoDesdePagos(
        montoTotalPactado: pactadoJ,
        totalCuotas: 9,
        mesaExtraPrecio: 0,
        sillasExtraPrecioTotal: 0,
        precioUnitarioMesaExtra: 0,
        mesaExtraCuotas: 0,
        mesaExtraCantidad: 0,
        sillasExtraCuotas: 0,
        pagos: pagos,
      );

      expect(r.saldoDeudor, closeTo(168000, 0.01));
      expect(r.grossBase, closeTo(84000, 0.01));

      final inflado = _grossInfladoLegacy(
        montoNeto: 26000,
        montoGrossOriginal: 26000,
        cuotaPura: cuotaPuraJ,
        concepto: 'Cuota Base (3/9) — Completada',
      );
      expect(inflado, closeTo(28000, 0.01));
      expect(r.grossBase, isNot(closeTo(pactadoJ - 166000, 0.01)));
    });

    test('Ayala: abono 10.000 + cierre → saldo 180.000 sin fantasma', () {
      const pactadoA = 270000.0;

      final pagos = [
        {
          'anulado': 0,
          'concepto': 'Cuota Base (1/9)',
          'monto': 30000,
          'monto_gross': 30000,
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (2/9)',
          'monto': 30000,
          'monto_gross': 30000,
        },
        {
          'anulado': 0,
          'concepto': 'Entrega parcial — Cuota Base (3/9)',
          'monto': 10000,
          'monto_gross': 10000,
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (3/9) — Completada',
          'monto': 20000,
          'monto_gross': 20000,
        },
      ];

      final r = recalcularSaldoDesdePagos(
        montoTotalPactado: pactadoA,
        totalCuotas: 9,
        mesaExtraPrecio: 0,
        sillasExtraPrecioTotal: 0,
        precioUnitarioMesaExtra: 0,
        mesaExtraCuotas: 0,
        mesaExtraCantidad: 0,
        sillasExtraCuotas: 0,
        pagos: pagos,
      );

      expect(r.saldoDeudor, closeTo(180000, 0.01));
      expect(r.grossBase, closeTo(90000, 0.01));
      expect(r.saldoDeudor, isNot(closeTo(170000, 0.01)));
    });

    test('auditoría repetida: mismos pagos → mismo saldo (idempotente)', () {
      final pagos = [
        {
          'anulado': 0,
          'concepto': '2 Cuotas (Cuota Base) + Adelanto Cuota Base (3/9) · \$23.500,00',
          'monto': 83500,
          'monto_gross': 83500,
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (3/9) — Completada',
          'monto': 6500,
          'monto_gross': 6500,
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (4/9)',
          'monto': 30000,
          'monto_gross': 30000,
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (5/9)',
          'monto': 30000,
          'monto_gross': 30000,
        },
      ];

      final r1 = recalc(pagos);
      final r2 = recalc(pagos);
      expect(r1.saldoDeudor, r2.saldoDeudor);
      expect(r1.grossBase, r2.grossBase);
    });
  });
}
