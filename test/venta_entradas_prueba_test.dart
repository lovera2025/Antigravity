// La ventana de prueba de la venta de entradas (tool/venta_entradas_prueba.dart)
// anda: la tablet de Carla y la PC del jefe, cada una con su base, y lo que hace
// una le llega a la otra como en la app (spec 11.7: una vende y cierra, la otra ve
// la venta y el cierre; una familia compra las de sus lugares y la entrega lo
// muestra). Si deja de compilar o los lados dejan de hablarse, salta acá. El
// detalle de cada pantalla está en sus propias pruebas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';

import '../tool/venta_entradas_prueba.dart';
import 'helpers/entrega_en_memoria.dart';

void main() {
  late LadosDeLaVenta lados;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    lados = await armarLados(
      demoraDeSubida: Duration.zero,
      hoy: () => DateTime.utc(2026, 11, 20, 12),
      relojDelJefe: () => DateTime(2026, 11, 20, 12),
    );
  });
  tearDown(() => lados.dispose());

  /// Sin `pumpAndSettle`: la entrega relee cada 15 s.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PruebaDeLaVenta(lados));
    await asentar(tester);
  }

  Future<void> tocar(WidgetTester tester, String clave) async {
    await tester.tap(find.byKey(Key(clave)));
    await asentar(tester);
  }

  /// Carla abre su caja (si no la tiene) y le vende a PÉREZ [n] de sus lugares, por la
  /// base de la tablet, como lo haría VENDER.
  Future<VentaEntradas> venderAPerez(WidgetTester tester, int n) async {
    late VentaEntradas venta;
    await tester.runAsync(() async {
      final caja = await lados.tablet.abrirCaja(
        eventoId: idFiestaEntrega,
        operadorId: lados.operadora.id,
        operadorNombre: 'Carla',
        cambioInicial: 5000,
      );
      venta = await lados.tablet.vender(
        caja: caja,
        contratoAlumnoId: EntregaEnMemoria.idPerez,
        compradorNombre: 'PEREZ, MARTA',
        renglones: [
          RenglonEntradas.lugar(
            nombre: PedidoDeEntradas.nombreDeLugar(50),
            precioLista: 10000,
            descuentoPct: 50,
            cantidad: n,
          ),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 5000.0 * n,
        quien: 'Carla',
      );
    });
    await asentar(tester);
    return venta;
  }

  Finder enElJefe(String texto) => find.textContaining(texto);

  testWidgets('abre sin excepción, y cada lado mide su ancho', (tester) async {
    await abrir(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(EntradasHomeScreen), findsOneWidget);
    expect(find.byKey(const Key('vender_$idFiestaEntrega')), findsOneWidget);
    expect(find.byType(RetiroEntradasScreen), findsOneWidget);
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(EntradasHomeScreen))).width,
      800,
    );
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(RetiroEntradasScreen))).width,
      2000 - 800 - 6,
    );
    // La noche arranca con la caja de Maxi cerrada, $ 500 de menos.
    await tocar(tester, 'prueba_jefe_cierre');
    await tocar(tester, 'cierre_sector_entradas');
    expect(
      tester
          .widget<Text>(find.byKey(Key('cierre_entradas_diferencia_${lados.cajaDeMaxi.id}')))
          .data,
      contains('500'),
    );
    await tocar(tester, 'prueba_ancho_carla');
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(EntradasHomeScreen))).width,
      390,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Carla le vende 3 de sus lugares a PÉREZ y el jefe lo ve: en la entrega, '
      'en VENTAS y en el cierre de caja', (tester) async {
    await abrir(tester);
    expect(enElJefe('0 vendidas de 8'), findsOneWidget);
    final venta = await venderAPerez(tester, 3);
    expect(lados.tablet.pendientes, isEmpty, reason: 'subió');
    expect(lados.pc.listaVentas.map((v) => v.id), contains(venta.id));
    expect(enElJefe('3 vendidas de 8'), findsOneWidget);
    expect(enElJefe('8 al 50 % (compró 3)'), findsOneWidget);

    await tocar(tester, 'entradas_ventas');
    expect(find.byKey(Key('venta_${venta.id}')), findsOneWidget);
    await tester.pageBack();
    await asentar(tester);

    await tocar(tester, 'prueba_jefe_cierre');
    await tocar(tester, 'cierre_sector_entradas');
    expect(find.text('Carla · abierta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin internet el jefe no ve la venta; al volver, sí, y Carla queda en '
      '"Todo subido"', (tester) async {
    await abrir(tester);
    await tocar(tester, 'prueba_internet');
    expect(lados.hayInternet, isFalse);
    await venderAPerez(tester, 3);
    expect(lados.tablet.pendientes, hasLength(2), reason: 'la caja y la venta');
    expect(lados.pc.listaVentas.where((v) => v.contratoAlumnoId == EntregaEnMemoria.idPerez),
        isEmpty);
    // Aunque el jefe relea, no está.
    lados.nube.pc.bajo({'entradas_ventas'});
    await asentar(tester);
    expect(enElJefe('0 vendidas de 8'), findsOneWidget);

    // Carla, en VENDER: la línea lo dice.
    await tocar(tester, 'vender_$idFiestaEntrega');
    await asentar(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('vender_linea_texto'))).data,
      'Caja abierta · Carla · Sin internet · 1 venta por subir',
    );

    await tocar(tester, 'prueba_internet');
    await asentar(tester);
    expect(lados.hayInternet, isTrue);
    expect(lados.tablet.pendientes, isEmpty);
    expect(enElJefe('3 vendidas de 8'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('vender_linea_texto'))).data,
      'Caja abierta · Carla · Todo subido',
    );
  });

  testWidgets('Carla cierra su caja y el cierre de caja del jefe la muestra cerrada',
      (tester) async {
    await abrir(tester);
    await venderAPerez(tester, 3);
    await tocar(tester, 'prueba_jefe_cierre');
    await tocar(tester, 'cierre_sector_entradas');
    expect(find.text('Carla · abierta'), findsOneWidget);

    final caja = lados.tablet.listaCajas.firstWhere((c) => c.operadorNombre == 'Carla');
    await tester.runAsync(() => lados.tablet.cerrarCaja(
          caja,
          efectivoContado: 20000,
          diferencia: 0,
          quien: 'Carla',
        ));
    await asentar(tester);
    expect(find.text('Carla · abierta'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(Key('cierre_entradas_diferencia_${caja.id}'))).data,
      'Justo',
    );
  });

  testWidgets('con MODO JEFE en NO, PRECIOS, VENTAS y VENDER se apagan, y el cierre '
      'queda en COBROS', (tester) async {
    await abrir(tester);
    bool apagado(String clave) =>
        tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).onPressed == null;
    expect(apagado('entradas_precios'), isFalse);
    expect(apagado('entradas_ventas'), isFalse);
    expect(apagado('entradas_vender'), isFalse);
    await tocar(tester, 'prueba_modo_jefe');
    expect(apagado('entradas_precios'), isTrue);
    expect(apagado('entradas_ventas'), isTrue);
    expect(apagado('entradas_vender'), isTrue);
    await tocar(tester, 'prueba_jefe_cierre');
    expect(find.byKey(const Key('cierre_sector_entradas')), findsNothing);
  });

  testWidgets('Carla, con el mouse: abre la caja, le vende a PÉREZ y sale el comprobante',
      (tester) async {
    await abrir(tester);
    // PÉREZ debe su mesa adicional: desde el 20-nov-2026 lo de A PAGAR se vende
    // solo si está pago entero. La paga antes, en la caja de cuotas.
    lados.entrega.cobrar(EntregaEnMemoria.idPerez, 70000);
    await asentar(tester);
    await tocar(tester, 'vender_$idFiestaEntrega');
    await tester.enterText(find.byKey(const Key('abrir_caja_cambio')), '5000');
    await asentar(tester);
    await tocar(tester, 'abrir_caja_abrir');
    await tester.enterText(find.byKey(const Key('vender_buscar')), 'perez');
    await asentar(tester);
    await tocar(tester, 'vender_familia_${EntregaEnMemoria.idPerez}');
    for (var i = 0; i < 5; i++) {
      await tocar(tester, 'vender_lugar_menos');
    }
    await tester.enterText(find.byKey(const Key('vender_comprador')), 'PEREZ, MARTA');
    await asentar(tester);
    await tester.ensureVisible(find.byKey(const Key('vender_efectivo')));
    await tocar(tester, 'vender_efectivo');
    await tocar(tester, 'cobro_confirmar');
    await asentar(tester);
    expect(lados.papeles.comprobantes, hasLength(1));
    expect(lados.papeles.comprobantes.single.venta.cantidad, 3);
    expect(enElJefe('3 vendidas de 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('cortar el internet avisa a la línea de VENDER, y volver sube todo', () async {
    var avisos = 0;
    final sub = lados.entrega.conexion.stream.listen((_) => avisos++);
    addTearDown(sub.cancel);
    lados.cambiarInternet();
    lados.cambiarInternet();
    await Future<void>.delayed(Duration.zero);
    expect(avisos, 2);
    expect(lados.entrega.conexion.currentStatus, AppConnectivity.online);
  });
}
