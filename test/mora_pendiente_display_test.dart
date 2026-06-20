import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';

void main() {
  group('MoraCuotaCalculator.pendienteDisplay', () {
    // --- Caso base ---
    test('mora acumulando, sin carry-over, sin pagar: devuelve interesAcumulado', () {
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 3000,
        moraCobradaHistorial: 0,
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
        moraCobradaPeriodo: 0,
      );
      expect(r, closeTo(3000, 0.01));
    });

    // --- Carry-over legítimo (mora cuota anterior no pagada) ---
    test('carry-over de cuota anterior: cuota avanzó, interés = 0, mora no pagada aún', () {
      // cuotasPagadas avanzó → interesAcumulado = 0 para próxima cuota aún no vencida
      // mora_pendiente_tracked = 5400 (snapshot guardado al pagar cuota)
      // moraCobradaHistorial = 20100 = moraCobradaOffset (nada pagado en este período)
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 0,
        moraCobradaHistorial: 20100,
        moraPendienteTracked: 5400,
        moraCobradaOffset: 20100, // offset = todo lo que había antes
        moraCobradaPeriodo: 0,    // nada pagado en este período
      );
      expect(r, closeTo(5400, 0.01)); // debe mostrar la mora pendiente
    });

    // --- Regresión Arguello: mora de mayo ya pagada, pero período arranca el 30/06 ---
    // Síntoma: pagó $5.400 mora el 18/06 pero el 30/06 es el vencimiento próximo,
    // por lo que moraCobradaPeriodo = 0 (pago fuera de ventana) y el modal
    // seguía mostrando $5.400 como pendiente.
    test('regresión mora de mayo: mora pagada el 18/06, período arranca 30/06 → debe ser 0', () {
      // Tras pagar los $5.400 el 18/06:
      // moraCobradaHistorial = 20100 (prev) + 5400 (nuevo) = 25500
      // moraCobradaOffset  = 20100 (fijo desde migración)
      // moraCobradaPeriodo = 0 (pago del 18/06 queda ANTES del vencimiento 30/06)
      // interesAcumulado   = 0 (cuota 3 no venció aún)
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 0,
        moraCobradaHistorial: 25500,
        moraPendienteTracked: 5400,
        moraCobradaOffset: 20100,
        moraCobradaPeriodo: 0,
      );
      expect(r, closeTo(0, 0.01)); // mora ya pagada → 0
    });

    // --- Carry-over parcialmente pagado (tracked ya reducido por registrarPago) ---
    test('carry-over parcialmente pagado: tracked vivo muestra el resto', () {
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 0,
        moraCobradaHistorial: 20100 + 3000, // pagó 3000 de los 5400
        moraPendienteTracked: 2400, // registrarPago ya descontó el pago parcial
        moraCobradaOffset: 20100,
        moraCobradaPeriodo: 0,
      );
      expect(r, closeTo(2400, 0.01));
    });

    // --- Carry-over parcial legacy (tracked no se redujo en DB antigua) ---
    test('carry-over parcial legacy: tracked stale deduce del historial', () {
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 0,
        moraCobradaHistorial: 20100 + 3000,
        moraPendienteTracked: 5400,
        moraCobradaOffset: 20100,
        moraCobradaPeriodo: 0,
      );
      expect(r, closeTo(2400, 0.01));
    });

    // --- Mora nueva + carry-over (interesAcumulado > 0) → lógica original sin cambios ---
    test('mora nueva acumulando + carry-over: usa lógica original (max)', () {
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 4200,
        moraCobradaHistorial: 20100,
        moraPendienteTracked: 5400,
        moraCobradaOffset: 20100,
        moraCobradaPeriodo: 0,
      );
      // f = 4200, t = 5400 → max = 5400
      expect(r, closeTo(5400, 0.01));
    });

    // --- Mora nueva sin carry-over: devuelve fórmula ---
    test('mora nueva sin carry-over: devuelve interesAcumulado - cobrada', () {
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 2300,
        moraCobradaHistorial: 0,
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
        moraCobradaPeriodo: 0,
      );
      expect(r, closeTo(2300, 0.01));
    });

    // --- Mora nueva parcialmente pagada en el período ---
    test('mora nueva parcialmente pagada en período', () {
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 5000,
        moraCobradaHistorial: 2000,
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
        moraCobradaPeriodo: 2000,
      );
      expect(r, closeTo(3000, 0.01));
    });

    // --- Contrato nuevo (offset = 0): carry-over pagado ---
    test('contrato nuevo (offset=0): carry-over pagado queda en 0', () {
      // Para contratos creados después de la migración v44, offset = 0.
      // El carry-over de $230 fue trackeado y luego pagado.
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 0,
        moraCobradaHistorial: 230,
        moraPendienteTracked: 230,
        moraCobradaOffset: 0,
        moraCobradaPeriodo: 0,
      );
      expect(r, closeTo(0, 0.01));
    });

    // --- Contrato nuevo (offset = 0): carry-over aún no pagado ---
    test('contrato nuevo (offset=0): carry-over sin pagar sigue mostrando', () {
      final r = MoraCuotaCalculator.pendienteDisplay(
        interesAcumulado: 0,
        moraCobradaHistorial: 0,
        moraPendienteTracked: 230,
        moraCobradaOffset: 0,
        moraCobradaPeriodo: 0,
      );
      expect(r, closeTo(230, 0.01));
    });
  });

  group('MoraCuotaCalculator.desglosePendiente', () {
    final desglose = [
      MoraCuotaDetalle(
        numeroCuota: 1,
        vencimiento: DateTime(2024, 4, 30),
        diasMora: 49,
        interesBruto: 14700,
        mesLabel: 'Abr 2024',
      ),
      MoraCuotaDetalle(
        numeroCuota: 2,
        vencimiento: DateTime(2024, 5, 31),
        diasMora: 19,
        interesBruto: 5400,
        mesLabel: 'May 2024',
      ),
    ];

    test('sin pagos: devuelve desglose bruto completo', () {
      final r = MoraCuotaCalculator.desglosePendiente(desglose, 0);
      expect(r.length, 2);
      expect(r[0].interesBruto, closeTo(14700, 0.01));
      expect(r[1].interesBruto, closeTo(5400, 0.01));
    });

    test('mora cuota 1 pagada: omite cuota 1 y deja cuota 2', () {
      final r = MoraCuotaCalculator.desglosePendiente(desglose, 14700);
      expect(r.length, 1);
      expect(r.first.numeroCuota, 2);
      expect(r.first.interesBruto, closeTo(5400, 0.01));
    });

    test('pago parcial en cuota 1: reduce solo la primera cuota', () {
      final r = MoraCuotaCalculator.desglosePendiente(desglose, 10000);
      expect(r.length, 2);
      expect(r[0].numeroCuota, 1);
      expect(r[0].interesBruto, closeTo(4700, 0.01));
      expect(r[1].interesBruto, closeTo(5400, 0.01));
    });
  });

  group('MoraCuotaCalculator.pendienteEfectivoConDesglose', () {
    final desglose = [
      MoraCuotaDetalle(
        numeroCuota: 1,
        vencimiento: DateTime(2024, 4, 30),
        diasMora: 49,
        interesBruto: 14700,
        mesLabel: 'Abr 2024',
      ),
      MoraCuotaDetalle(
        numeroCuota: 2,
        vencimiento: DateTime(2024, 5, 31),
        diasMora: 19,
        interesBruto: 5400,
        mesLabel: 'May 2024',
      ),
    ];

    test('regresión Arguello: mora cuota 1 pagada no re-infla el modal', () {
      final r = MoraCuotaCalculator.pendienteEfectivoConDesglose(
        moraPendienteUi: 5400,
        desgloseBruto: desglose,
        moraCobradaHistorial: 14700,
      );
      expect(r, closeTo(5400, 0.01));
    });

    test('sin pagos: usa el máximo entre ui y desglose bruto', () {
      final r = MoraCuotaCalculator.pendienteEfectivoConDesglose(
        moraPendienteUi: 14700,
        desgloseBruto: desglose,
        moraCobradaHistorial: 0,
      );
      expect(r, closeTo(20100, 0.01));
    });
  });
}
