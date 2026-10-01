// El chip "Mesas y sillas" de la barra del evento masivo.
import 'package:arguello_events/features/eventos/services/filtro_mesas_sillas.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/chip_mesas_sillas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ContratoAlumno _alumno(String id, {int extras = 0, int sillas = 0}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e1',
      nombreAlumno: id,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
    );

void main() {
  final alumnos = [
    _alumno('alDia', extras: 1, sillas: 2),
    _alumno('extraSinPago', extras: 1),
    _alumno('sillasSinPago', sillas: 3),
    _alumno('nada'),
    _alumno('soloContrato'),
  ];
  final extras = extrasPorAlumno(alumnos, {
    'alDia': const PagoAlumno(base: 30000, mesas: 70000, sillas: 16000),
    'extraSinPago': const PagoAlumno(base: 30000),
    'sillasSinPago': const PagoAlumno(base: 30000),
    'soloContrato': const PagoAlumno(base: 30000),
  });
  final conAvisos = {'soloContrato'};

  Future<List<FiltroExtras>> mostrar(
    WidgetTester tester, {
    FiltroExtras filtro = FiltroExtras.todos,
  }) async {
    final elegidos = <FiltroExtras>[];
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ChipMesasSillas(
              filtro: filtro,
              onFiltro: elegidos.add,
              pendientes: alumnos
                  .where(
                    (a) => tieneAlgoPendienteDeExtras(
                      a,
                      extras[a.id],
                      tieneAvisos: conAvisos.contains(a.id),
                    ),
                  )
                  .length,
              cuantos: contarPorFiltro(alumnos, extras, conAvisos),
              totales: totalesDeExtras(alumnos, extras),
            ),
          ),
        ),
      ),
    );
    return elegidos;
  }

  test('cuántos entran en cada opción', () {
    final c = contarPorFiltro(alumnos, extras, conAvisos);
    expect(c[FiltroExtras.conMesaAgregada], 2);
    expect(c[FiltroExtras.mesaPagada], 1);
    expect(c[FiltroExtras.mesaSinPagar], 1);
    expect(c[FiltroExtras.mesaEnCuotas], 0);
    expect(c[FiltroExtras.sinPagoBase], 1);
    expect(c[FiltroExtras.conSillas], 2);
    expect(c[FiltroExtras.sillasPagadas], 1);
    expect(c[FiltroExtras.sillasSinPagar], 1);
    expect(c[FiltroExtras.revisar], 1);
    expect(c.containsKey(FiltroExtras.todos), isFalse);
  });

  testWidgets('el chip dice cuántos tienen algo pendiente', (tester) async {
    await mostrar(tester);
    // Sin pagar la extra, sin pagar las sillas, sin pagar la base y el aviso.
    expect(find.text('4'), findsOneWidget);
    // Sin filtro no hay nada que quitar.
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('el menú trae los tres grupos, con cuántos hay en cada opción',
      (tester) async {
    final elegidos = await mostrar(tester);
    await tester.tap(find.byType(ChipMesasSillas));
    await tester.pumpAndSettle();
    for (final titulo in ['MESAS', 'SILLAS', 'ANTES DEL SORTEO']) {
      expect(find.text(titulo), findsOneWidget);
    }
    for (final f in FiltroExtras.values) {
      expect(find.text(f.label), findsOneWidget, reason: f.name);
    }
    await tester.tap(find.text('Mesa agregada sin pagar'));
    await tester.pumpAndSettle();
    expect(elegidos, [FiltroExtras.mesaSinPagar]);
  });

  testWidgets('con un filtro puesto, dice cuál y se saca con la X',
      (tester) async {
    final elegidos = await mostrar(tester, filtro: FiltroExtras.sillasSinPagar);
    expect(find.text('SILLAS SIN PAGAR'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    expect(elegidos, [FiltroExtras.todos]);
  });

  test('el resumen del evento: lo cargado y lo que daría hoy el sorteo', () {
    final chip = ChipMesasSillas(
      filtro: FiltroExtras.todos,
      onFiltro: (_) {},
      pendientes: 0,
      cuantos: const {},
      totales: totalesDeExtras(alumnos, extras),
    );
    // 7 mesas cargadas (5 del contrato + 2 agregadas). Con lo pagado: alDia 2,
    // extraSinPago 1, sillasSinPago 1, nada 0, soloContrato 1.
    expect(
      chip.resumen,
      'Mesas: 7 (2 agregadas) · con lo pagado hoy: 5 · Sillas extra: 5',
    );
  });
}
