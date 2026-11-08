// La ventana de prueba de la barra (tool/barra_prueba.dart) anda: la cajera y el jefe
// lado a lado, sobre la misma barra en memoria, y lo que hace uno le llega al otro como
// en la app. Si deja de compilar o los lados dejan de hablarse, salta acá. El recorrido
// de cada pantalla está en barra_pantalla_test y barra_jefe_pantalla_test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/cuentas/pesos.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';

import '../tool/barra_prueba.dart';

void main() {
  late LadosDeLaPrueba lados;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    lados = armarLados(papelEnPantalla: true);
  });
  tearDown(() => lados.dispose());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PruebaDeLaBarra(lados));
    await asentar(tester);
  }

  String valor(WidgetTester tester, String kpi) =>
      tester.widget<Text>(find.byKey(Key('jefe_kpi_${kpi}_valor'))).data!;

  /// Lo que hace VENDER: guarda la venta en la tablet y la manda a subir.
  Future<(CajaBarra, VentaBarra)> venderEnLaTablet() async {
    final b = lados.barra;
    final caja = await b.abrirCaja(
      eventoId: idPuertoViejo,
      operadorId: 'a0000000-0000-4000-8000-000000000001',
      operadorNombre: 'Marta',
      numeroCaja: 1,
    );
    final lata = b.productosGuardados.first;
    final venta = await b.vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: lata.id, nombre: lata.nombre, precio: 3500, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 7000,
      quien: 'Marta',
    );
    await lados.cajera.read(subirVentaProvider)(venta);
    return (caja, venta);
  }

  testWidgets('abre con la cajera en su PIN y el jefe en CAJAS, cada uno con su ancho', (tester) async {
    await abrir(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(RoleGateScreen), findsOneWidget);
    expect(find.byKey(const Key('jefe_sin_cajas')), findsOneWidget);
    expect(find.text('PUERTO VIEJO'), findsOneWidget, reason: 'el jefe abre en la fiesta de hoy');
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(BarraJefeScreen))).width,
      2000 - 800 - 6,
      reason: 'el jefe mide su lado, no la ventana',
    );
    expect(MediaQuery.sizeOf(tester.element(find.byType(RoleGateScreen))).width, 800);

    await tester.tap(find.byKey(const Key('prueba_ancho_cajera')));
    await asentar(tester);
    expect(MediaQuery.sizeOf(tester.element(find.byType(RoleGateScreen))).width, 390);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo que vende la tablet aparece solo en CAJAS del jefe', (tester) async {
    await abrir(tester);
    final (caja, _) = await venderEnLaTablet();
    await asentar(tester);
    expect(find.byKey(Key('jefe_caja_${caja.id}')), findsOneWidget);
    expect(valor(tester, 'ventas'), '1');
    expect(valor(tester, 'total'), pesos(7000));
    expect(lados.barra.sinSubir, isEmpty);
  });

  testWidgets('sin internet el jefe no ve la venta; al volver, aparece', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('prueba_internet')));
    await asentar(tester);
    expect(find.text('VOLVER EL INTERNET'), findsOneWidget);

    final (caja, venta) = await venderEnLaTablet();
    await asentar(tester);
    expect(find.byKey(const Key('jefe_sin_cajas')), findsOneWidget, reason: 'no le llegó ningún aviso');
    expect(lados.barra.sinSubir, contains(venta.id));

    // Aunque el jefe vuelva a leer por su cuenta, la venta que la tablet no subió no está.
    lados.jefe.invalidate(cajasDelJefeProvider(idPuertoViejo));
    await asentar(tester);
    expect(find.byKey(Key('jefe_caja_${caja.id}')), findsOneWidget);
    expect(valor(tester, 'ventas'), '0');

    await tester.tap(find.byKey(const Key('prueba_internet')));
    await asentar(tester);
    expect(lados.barra.sinSubir, isEmpty);
    expect(valor(tester, 'ventas'), '1');
    expect(valor(tester, 'total'), pesos(7000));
  });

  test('un precio que guarda el jefe le llega a la tablet: la fiesta aparece', () async {
    final sub = lados.cajera.listen(fiestasDeLaBarraProvider, (_, _) {});
    addTearDown(sub.close);
    Future<List<String>> fiestas() async =>
        [for (final e in await lados.cajera.read(fiestasDeLaBarraProvider.future)) e.id];
    expect(await fiestas(), isNot(contains(idBuenaVista)));

    final lata = lados.barra.productosGuardados.first;
    final precio = await lados.barra.guardarPrecio(
      PrecioBarra.para(eventoId: idBuenaVista, productoId: lata.id, precio: 4000, ahora: DateTime(2026, 11, 7)),
      quien: 'Jefe',
    );
    expect(await fiestas(), isNot(contains(idBuenaVista)), reason: 'todavía no le llegó el aviso');
    await lados.jefe.read(subirDeLaBarraProvider)('barra_precios', precio.id);
    expect(await fiestas(), contains(idBuenaVista));
  });

  testWidgets('MODO JEFE en NO deja ver todo, con el aviso', (tester) async {
    await abrir(tester);
    expect(find.byKey(const Key('jefe_sin_modo_jefe')), findsNothing);
    await tester.tap(find.byKey(const Key('prueba_modo_jefe')));
    await asentar(tester);
    expect(find.byKey(const Key('jefe_sin_modo_jefe')), findsOneWidget);
    expect(find.text('MODO JEFE: NO'), findsOneWidget);
  });
}
