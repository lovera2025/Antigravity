import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/models/egreso.dart';
import 'package:arguello_events/features/mi_empresa/models/ingreso_detallado.dart';
import 'package:arguello_events/features/mi_empresa/providers/finanzas_provider.dart';

/// La "Comparativa de ingresos" tiene que comparar dos meses de verdad.
///
/// Mostraba **+100,0% de crecimiento** siempre: `calcularMesData` leía de
/// `state.ingresos`, que ya viene recortado al mes elegido arriba, así que
/// pedirle el mes anterior era buscar julio en una lista que solo tenía agosto.
/// Daba cero, y con `prev.ingresos <= 0` el score escribía `deltaPct = 1.0`.
/// Como el momentum pesa 25 de los 100 puntos, el puntaje venía inflado.
void main() {
  IngresoDetallado ing(DateTime fechaUtc, double monto) => IngresoDetallado(
        id: 'i${fechaUtc.millisecondsSinceEpoch}$monto',
        fuente: 'cuota',
        fecha: fechaUtc,
        monto: monto,
        concepto: 'Cuota',
        alumnoOCliente: 'Alumno',
        nombreEvento: 'Evento',
      );

  /// Estado con las listas históricas cargadas y las de listado **vacías**,
  /// que es justo el caso que rompía: el filtro de mes no debe afectar esto.
  FinanzasState estadoCon(List<IngresoDetallado> historicos) => FinanzasState(
        ingresos: const [],
        egresos: const [],
        totalIngresos: 0,
        totalEgresos: 0,
        balanceGlobal: 0,
        ingresosHistoricosLista: historicos,
        egresosHistoricosLista: const <Egreso>[],
      );

  final julio = DateTime(2026, 7);
  final agosto = DateTime(2026, 8);

  test('lee el mes pedido aunque el listado filtrado esté vacío', () {
    final s = estadoCon([
      ing(DateTime.utc(2026, 7, 10, 15), 100000),
      ing(DateTime.utc(2026, 8, 10, 15), 150000),
    ]);

    expect(calcularMesData(s, julio).ingresos, 100000);
    expect(calcularMesData(s, agosto).ingresos, 150000);
  });

  test('creciste 50%, no 100%', () {
    final s = estadoCon([
      ing(DateTime.utc(2026, 7, 10, 15), 100000),
      ing(DateTime.utc(2026, 8, 10, 15), 150000),
    ]);

    final prev = calcularMesData(s, julio).ingresos;
    final curr = calcularMesData(s, agosto).ingresos;
    expect((curr - prev) / prev, 0.5);
  });

  test('dos meses iguales dan 0%, no +100%', () {
    final s = estadoCon([
      ing(DateTime.utc(2026, 7, 10, 15), 100000),
      ing(DateTime.utc(2026, 8, 10, 15), 100000),
    ]);

    final prev = calcularMesData(s, julio).ingresos;
    final curr = calcularMesData(s, agosto).ingresos;
    expect((curr - prev) / prev, 0);
  });

  test('caída de ingresos se ve como caída', () {
    final s = estadoCon([
      ing(DateTime.utc(2026, 7, 10, 15), 200000),
      ing(DateTime.utc(2026, 8, 10, 15), 150000),
    ]);

    final prev = calcularMesData(s, julio).ingresos;
    final curr = calcularMesData(s, agosto).ingresos;
    expect((curr - prev) / prev, -0.25);
  });

  test('el corte de mes es en hora argentina', () {
    // 31/07 23:00 AR == 01/08 02:00 UTC: es de julio.
    final s = estadoCon([ing(DateTime.utc(2026, 8, 1, 2), 50000)]);

    expect(calcularMesData(s, julio).ingresos, 50000);
    expect(calcularMesData(s, agosto).ingresos, 0);
  });

  test('un mes sin cobros da cero y no rompe', () {
    final s = estadoCon([ing(DateTime.utc(2026, 8, 10, 15), 150000)]);
    expect(calcularMesData(s, julio).ingresos, 0);
  });
}
