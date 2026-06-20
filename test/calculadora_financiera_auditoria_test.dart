import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/calculadora_financiera.dart';

void main() {
  group('CalculadoraFinanciera.montoGrossAcumuladoEnAuditoria', () {
    test('abono con descuento: conserva gross aunque el neto sea menor', () {
      final gross = CalculadoraFinanciera.montoGrossAcumuladoEnAuditoria(
        montoNeto: 18000,
        montoGrossOriginal: 20000,
        debeInflar: false,
        targetGrossTotal: 30000,
        totalMontoGrupoNeto: 18000,
        lineasEnGrupo: 1,
      );
      expect(gross, closeTo(20000, 0.01));
    });

    test('cuota con descuento inflada: reparte gross objetivo', () {
      final gross = CalculadoraFinanciera.montoGrossAcumuladoEnAuditoria(
        montoNeto: 27000,
        montoGrossOriginal: 30000,
        debeInflar: true,
        targetGrossTotal: 30000,
        totalMontoGrupoNeto: 27000,
        lineasEnGrupo: 1,
      );
      expect(gross, closeTo(30000, 0.01));
    });

    test('sin descuento y sin inflar: usa gross original', () {
      final gross = CalculadoraFinanciera.montoGrossAcumuladoEnAuditoria(
        montoNeto: 20000,
        montoGrossOriginal: 20000,
        debeInflar: false,
        targetGrossTotal: 30000,
        totalMontoGrupoNeto: 20000,
        lineasEnGrupo: 1,
      );
      expect(gross, closeTo(20000, 0.01));
    });
  });
}
