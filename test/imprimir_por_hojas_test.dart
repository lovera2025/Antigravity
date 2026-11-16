// El cartel antes de imprimir un historial largo (pedido del usuario, 15-nov:
// "imaginá 1.000 entradas"): Todo junto, o Por hojas, de a tandas o eligiendo
// un tramo. Y VENTAS lo abre solo cuando son muchas hojas.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/historial_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/widgets/imprimir_por_hojas.dart';
import 'package:arguello_events/features/entradas/widgets/ventas_de_entradas_screen.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';

void main() {
  test('las tandas, de a 10, y la última con lo que quede', () {
    expect(tandasDeHojas(23), [
      (desde: 1, hasta: 10),
      (desde: 11, hasta: 20),
      (desde: 21, hasta: 23),
    ]);
    expect(tandasDeHojas(10), [(desde: 1, hasta: 10)]);
  });

  group('el cartel', () {
    HojasElegidas? elegidas;
    var contesto = false;

    Future<void> abrir(WidgetTester tester, {Set<int> impresas = const {}}) async {
      elegidas = null;
      contesto = false;
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  elegidas = await elegirHojasParaImprimir(
                    context,
                    hojas: 23,
                    ventas: 950,
                    impresas: impresas,
                  );
                  contesto = true;
                },
                child: const Text('IMPRIMIR'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('IMPRIMIR'));
      await tester.pumpAndSettle();
    }

    testWidgets('viene en Por hojas, con las tandas; una tanda imprime esas', (tester) async {
      await abrir(tester);
      expect(find.text('950 ventas · 23 hojas'), findsOneWidget);
      expect(find.byKey(const Key('hojas_tanda_1')), findsOneWidget);
      expect(find.byKey(const Key('hojas_tanda_21')), findsOneWidget);
      expect(find.text('Hojas 21 a 23'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hojas_tanda_11')));
      await tester.pumpAndSettle();
      expect(elegidas, (desde: 11, hasta: 20, tanda: true));
    });

    testWidgets('una tanda ya impresa lo dice', (tester) async {
      await abrir(tester, impresas: {11});
      expect(
        find.descendant(of: find.byKey(const Key('hojas_tanda_11')), matching: find.text('impresa')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('hojas_tanda_1')), matching: find.text('impresa')),
        findsNothing,
      );
    });

    testWidgets('de la hoja X a la Y; mal escrito, lo dice y no imprime', (tester) async {
      await abrir(tester);
      await tester.enterText(find.byKey(const Key('hojas_desde')), '15');
      await tester.enterText(find.byKey(const Key('hojas_hasta')), '30');
      await tester.tap(find.byKey(const Key('hojas_imprimir_rango')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hojas_error')), findsOneWidget);
      expect(contesto, isFalse);
      await tester.enterText(find.byKey(const Key('hojas_hasta')), '18');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hojas_error')), findsNothing, reason: 'al escribir se va');
      await tester.tap(find.byKey(const Key('hojas_imprimir_rango')));
      await tester.pumpAndSettle();
      expect(elegidas, (desde: 15, hasta: 18, tanda: false));
    });

    // La cajita del número de hoja es angosta: solo cifras, y hasta 4.
    testWidgets('el número de hoja: solo cifras, hasta 4', (tester) async {
      await abrir(tester);
      await tester.enterText(find.byKey(const Key('hojas_hasta')), '12a345');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const Key('hojas_hasta'))).controller!.text,
        '1234',
      );
    });

    testWidgets('Todo junto imprime las 23', (tester) async {
      await abrir(tester);
      await tester.tap(find.byKey(const Key('hojas_todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hojas_imprimir_todo')));
      await tester.pumpAndSettle();
      expect(elegidas, (desde: 1, hasta: 23, tanda: false));
    });

    testWidgets('VOLVER no imprime nada', (tester) async {
      await abrir(tester);
      await tester.tap(find.byKey(const Key('hojas_volver')));
      await tester.pumpAndSettle();
      expect(contesto, isTrue);
      expect(elegidas, isNull);
    });
  });

  group('VENTAS', () {
    late EntradasEnMemoria entradas;

    Future<List<DatosDelHistorial>> montar(WidgetTester tester, {required int ventas}) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final e = EntregaEnMemoria();
      entradas = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      final historiales = <DatosDelHistorial>[];
      final c = ProviderContainer(overrides: [
        ...e.reemplazos(jefe: true),
        ...entradas.reemplazos,
        abrirHistorialDeEntradasProvider
            .overrideWithValue((datos, {context}) async => historiales.add(datos)),
      ]);
      addTearDown(c.dispose);
      await c.read(appRoleProvider.notifier).entrarComoEntradas(
            e.operador(),
            const PermisosEfectivos(entradas: true, vendeEntradas: true),
          );
      final caja = await entradas.abrirCaja(
        eventoId: idFiestaEntrega,
        operadorId: 'maxi',
        operadorNombre: 'Maxi',
      );
      for (var i = 0; i < ventas; i++) {
        await entradas.vender(
          caja: caja,
          compradorNombre: 'COMPRADOR $i',
          renglones: [RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 1)],
          medio: MedioBarra.efectivo,
          efectivo: 10000,
          quien: 'Maxi',
        );
      }
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: VentasDeEntradasScreen(evento: fiestaDeLaEntrega)),
      ));
      await tester.pumpAndSettle();
      return historiales;
    }

    testWidgets('con pocas hojas imprime entero, sin preguntar', (tester) async {
      final historiales = await montar(tester, ventas: 30);
      await tester.tap(find.byKey(const Key('ventas_imprimir')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hojas_cartel')), findsNothing);
      expect(historiales.single.desdeHoja, isNull);
      expect(historiales.single.hastaHoja, isNull);
    });

    testWidgets('con muchas hojas pregunta, y una tanda sale sola y queda marcada',
        (tester) async {
      final historiales = await montar(tester, ventas: 600);
      await tester.tap(find.byKey(const Key('ventas_imprimir')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hojas_cartel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('hojas_tanda_11')));
      await tester.pumpAndSettle();
      final datos = historiales.single;
      final total = HistorialEntradasPdf.hojas(datos);
      expect(total, greaterThan(kHojasParaPreguntar));
      expect(datos.desdeHoja, 11);
      expect(datos.hastaHoja, total < 20 ? total : 20, reason: 'la última tanda llega hasta la última hoja');

      await tester.tap(find.byKey(const Key('ventas_imprimir')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const Key('hojas_tanda_11')), matching: find.text('impresa')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('hojas_volver')));
      await tester.pumpAndSettle();
      expect(historiales, hasLength(1), reason: 'VOLVER no imprime');
    });

    // Revisión del 15-nov: una tanda impresa seguía marcada aunque sus hojas
    // cambiaran (una venta anulada después): la pila de papel quedaba vieja.
    testWidgets('si cambian sus hojas, la tanda deja de estar "impresa"', (tester) async {
      await montar(tester, ventas: 600);
      await tester.tap(find.byKey(const Key('ventas_imprimir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hojas_tanda_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ventas_imprimir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hojas_tanda_11')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ventas_imprimir')));
      await tester.pumpAndSettle();
      Finder impresa(int desde) => find.descendant(
            of: find.byKey(Key('hojas_tanda_$desde')),
            matching: find.text('impresa'),
          );
      expect(impresa(1), findsOneWidget);
      expect(impresa(11), findsOneWidget);
      await tester.tap(find.byKey(const Key('hojas_volver')));
      await tester.pumpAndSettle();

      // Se tilda "Pago verificado" en la última venta (la más nueva: arriba en
      // la pantalla, en la última hoja del papel).
      final ultima = entradas.listaVentas.last;
      await tester.tap(find.byKey(Key('verificar_${ultima.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ventas_imprimir')));
      await tester.pumpAndSettle();
      expect(impresa(1), findsOneWidget, reason: 'sus hojas no cambiaron');
      expect(impresa(11), findsNothing, reason: 'su última hoja cambió: hay que volver a imprimirla');
    });
  });
}
