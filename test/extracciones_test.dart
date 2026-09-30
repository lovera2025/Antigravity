import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/cierre_caja/models/turno_caja.dart';
import 'package:arguello_events/features/mi_empresa/bolsa_personal_helpers.dart';
import 'package:arguello_events/features/mi_empresa/extracciones.dart';
import 'package:arguello_events/features/mi_empresa/widgets/extracciones_negocio.dart';
import 'package:arguello_events/models/egreso.dart';

/// Qué va a "Extracciones" en el panel del negocio y qué queda en "En qué se
/// fue". Las extracciones —lo apartado para el dueño, los retiros de caja y sus
/// gastos pagados con plata del negocio— no son gastos del negocio, y estaban
/// a la vista mezcladas con ellos.
void main() {
  var n = 0;
  Egreso eg(
    String categoria, {
    String? proveedor,
    double monto = 1000,
    String medio = 'Efectivo',
  }) =>
      Egreso(
        id: '${n++}',
        eventoId: '',
        monto: monto,
        proveedor: proveedor ?? categoria,
        categoria: categoria,
        medioPago: medio,
        fecha: DateTime.utc(2026, 9, 21, 13),
      );

  group('rubroExtraccion', () {
    test('lo apartado para el dueño y los retiros de caja son extracciones', () {
      expect(rubroExtraccion(eg(kCategoriaRetiroDueno)), RubroExtraccion.apartado);
      expect(rubroExtraccion(eg(kCategoriaRetiroCaja)), RubroExtraccion.retiroCaja);
    });

    test('un gasto personal pagado con plata del negocio es extracción', () {
      expect(
        rubroExtraccion(eg(kCategoriaGastoPersonal, proveedor: '[empresa] Nafta')),
        RubroExtraccion.gastoPersonal,
      );
    });

    test('un gasto personal pagado desde el bolsillo no resta del negocio', () {
      expect(
        rubroExtraccion(eg(kCategoriaGastoPersonal, proveedor: '[pendiente] Feria')),
        isNull,
      );
    });

    test('los gastos del negocio no son extracciones', () {
      for (final c in ['Personal', 'Proveedores', 'Logística', kCategoriaGastoEmpresa]) {
        expect(rubroExtraccion(eg(c)), isNull, reason: c);
      }
    });

    test('se decide por la categoría: un "EXTRACCION" cargado como Operadores '
        'sigue siendo Operadores', () {
      expect(rubroExtraccion(eg('Personal', proveedor: 'EXTRACCION')), isNull);
    });
  });

  test('resumen: por rubro, en orden y con su parte en cada medio', () {
    final r = resumenExtracciones([
      eg(kCategoriaRetiroCaja, monto: 500),
      eg(kCategoriaRetiroDueno, monto: 28733965.83),
      eg(kCategoriaRetiroDueno, monto: 20266034.17, medio: 'Transferencia'),
      eg('Personal', monto: 99999),
    ]);
    expect(r.map((x) => x.rubro), [
      RubroExtraccion.apartado,
      RubroExtraccion.retiroCaja,
    ]);
    expect(r.first.cantidad, 2);
    expect(r.first.efectivo, closeTo(28733965.83, 0.001));
    expect(r.first.transferencia, closeTo(20266034.17, 0.001));
    expect(r.first.total, closeTo(49000000, 0.001));
    expect(r.last.efectivo, 500);
  });

  test('gastos + extracciones = todo lo que salió del negocio', () {
    final egresos = [
      eg(kCategoriaRetiroDueno, monto: 3000),
      eg(kCategoriaRetiroCaja, monto: 200),
      eg(kCategoriaGastoPersonal, proveedor: '[empresa] Nafta', monto: 50),
      eg(kCategoriaGastoPersonal, proveedor: '[pendiente] Feria', monto: 70),
      eg('Personal', monto: 400),
      eg('Proveedores', monto: 600, medio: 'Transferencia'),
    ];
    final salio = egresos
        .where(finanzasEgresoAfectaCajaEmpresa)
        .fold<double>(0, (s, e) => s + e.monto);
    final extracciones = resumenExtracciones(egresos)
        .fold<double>(0, (s, r) => s + r.total);
    final gastos = egresos
        .where((e) => finanzasEgresoAfectaCajaEmpresa(e) && !esExtraccion(e))
        .fold<double>(0, (s, e) => s + e.monto);
    expect(extracciones, 3250);
    expect(gastos, 1000);
    expect(gastos + extracciones, salio);
  });

  testWidgets('la sección arranca cerrada y se abre al tocarla', (tester) async {
    final resumen = resumenExtracciones([
      eg(kCategoriaRetiroDueno, monto: 82232537.59),
      eg(kCategoriaRetiroCaja, monto: 2831500),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExtraccionesNegocio(resumen: resumen, isDark: false),
        ),
      ),
    );

    expect(find.text('EXTRACCIONES'), findsOneWidget);
    expect(find.textContaining('2 movimientos'), findsOneWidget);
    expect(find.textContaining('Aparté para mí'), findsNothing);

    await tester.tap(find.text('EXTRACCIONES'));
    await tester.pump();
    expect(find.textContaining('Aparté para mí'), findsOneWidget);
    expect(find.textContaining('Retiro de caja'), findsOneWidget);
  });

  testWidgets('sin extracciones no se dibuja nada', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExtraccionesNegocio(resumen: [], isDark: false)),
      ),
    );
    expect(find.text('EXTRACCIONES'), findsNothing);
  });
}
