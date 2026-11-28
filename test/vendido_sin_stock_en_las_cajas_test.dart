// "Se vendió sin stock…" arriba de las cajas, para la encargada y el jefe (28-nov-2026):
// lo que una caja vendió con el stock de su barra en cero (sin señal no se frena). Sale de
// `StockDeLaFiesta.vendidoDeMas`; sin nada de más, no ocupa lugar. Sin plata.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/stock_por_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/repositor/aviso_de_vendido_sin_stock.dart';
import 'package:arguello_events/features/barra/repositor/stock_de_las_barras_screen.dart';
import 'package:arguello_events/features/barra/repositor/texto_del_stock.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late ProductoBarra speed, agua;
  late CajaBarra cajaDeLaUno, cajaDeLaDos;

  final ahora = DateTime.utc(2026, 12, 5, 2, 30);
  BarraEnMemoria b() => prueba.barra;

  Future<void> reparto(ProductoBarra p, String barra, int arranque) => b().guardarReparto(
        StockEnLaBarra.para(eventoId: fiesta.id, productoId: p.id, barra: barra, arranque: arranque, ahora: ahora),
        quien: 'Jefe',
      );

  Future<void> vender(CajaBarra caja, ProductoBarra p, int cantidad) => b().vender(
        caja: caja,
        renglones: [RenglonVenta(productoId: p.id, nombre: p.nombre, precio: 5000, cantidad: cantidad)],
        medio: MedioBarra.efectivo,
        efectivo: 5000.0 * cantidad,
        quien: 'Marta',
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    prueba = BarraEnPrueba();
    b().reloj = () => ahora;
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    prueba.eventos.add(fiesta);
    speed = b().producto('Speed', categoria: 'Sin alcohol');
    agua = b().producto('Agua', categoria: 'Sin alcohol');
    b().precio(fiesta.id, speed, 5000, stock: 96);
    b().precio(fiesta.id, agua, 2500, stock: 60);
    await reparto(speed, 'Barra 1', 3);
    await reparto(speed, 'Barra 2', 10);
    await reparto(agua, 'Barra 2', 4);
    cajaDeLaUno = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'm',
      operadorNombre: 'Marta',
      numeroCaja: 1,
      sede: 'Barra 1',
    );
    cajaDeLaDos = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'l',
      operadorNombre: 'Lu',
      numeroCaja: 7,
      sede: 'Barra 2',
    );
  });

  Future<void> abrir(WidgetTester tester, {Size tamano = const Size(1000, 700)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        barraDelJefeProvider.overrideWithValue(b()),
        rolEnLaBarraProvider.overrideWithValue(RolEnLaBarra.encargada),
        relojDeLaBarraProvider.overrideWithValue(() => ahora),
        enLaWebProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        home: Scaffold(body: Column(children: [AvisoDeVendidoSinStock(fiesta: fiesta)])),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String texto(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('vendido_sin_stock_texto'))).data!;

  testWidgets('sin nada vendido de más no aparece', (tester) async {
    await vender(cajaDeLaUno, speed, 3);
    await abrir(tester);
    expect(find.byKey(const Key('vendido_sin_stock')), findsNothing);
  });

  testWidgets('dice cuánto se vendió de más, de qué y en qué barra, sin plata', (tester) async {
    await vender(cajaDeLaUno, speed, 8); // había 3: 5 de más
    await vender(cajaDeLaDos, agua, 6); // había 4: 2 de más
    await vender(cajaDeLaDos, speed, 4); // quedan 6: no cuenta
    await abrir(tester);
    final t = texto(tester);
    expect(t, contains('5 speed en la Barra 1'));
    expect(t, contains('2 agua en la Barra 2'));
    expect(t, contains('Se descuenta de lo que se reponga'));
    expect(t.contains(r'$'), isFalse);
    expect(t.contains('Barra 2 · 4'), isFalse);
  });

  testWidgets('cuando se repone lo que faltaba, se va', (tester) async {
    await vender(cajaDeLaUno, speed, 8);
    await b().anotarMovimientoDeStock(
      MovimientoDeStock.reposicion(eventoId: fiesta.id, productoId: speed.id, barra: 'Barra 1', cantidad: 24, ahora: ahora),
      quien: 'Nico',
    );
    await abrir(tester);
    expect(find.byKey(const Key('vendido_sin_stock')), findsNothing);
  });

  testWidgets('tocarlo abre STOCK; en un celular no desborda', (tester) async {
    await vender(cajaDeLaUno, speed, 8);
    await vender(cajaDeLaDos, agua, 6);
    await abrir(tester, tamano: const Size(360, 740));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('vendido_sin_stock')));
    await tester.pumpAndSettle();
    expect(find.byType(StockDeLasBarrasScreen), findsOneWidget);
  });

  test('el texto: una o varias, y null sin nada de más', () {
    StockDeUnLugar s(String p, String lugar, int queda) =>
        StockDeUnLugar(productoId: p, lugar: lugar, inicial: 0, queda: queda);
    String nombre(String id) => id == 's' ? 'Speed' : 'Agua';
    expect(vendidoSinStock(const [], nombre), isNull);
    expect(vendidoSinStock([s('s', 'Barra 1', 0), s('a', 'Barra 2', 7)], nombre), isNull);
    expect(
      vendidoSinStock([s('s', 'Barra 1', -1)], nombre),
      'Se vendió sin stock: 1 speed en la Barra 1. Se descuenta de lo que se reponga.',
    );
    expect(
      vendidoSinStock([s('s', 'Barra 1', -5), s('a', 'Barra 2', -2), s('a', 'Barra 1', 3)], nombre),
      'Se vendió sin stock: 5 speed en la Barra 1 · 2 agua en la Barra 2. Se descuenta de lo que se reponga.',
    );
  });

  test('está arriba de las cajas de la encargada y del jefe', () {
    for (final ruta in [
      'lib/features/barra/widgets/las_cajas_screen.dart',
      'lib/features/barra/jefe/barra_jefe_screen.dart',
    ]) {
      expect(File(ruta).readAsStringSync(), contains('AvisoDeVendidoSinStock(fiesta: fiesta)'), reason: ruta);
    }
    // La cajera no lo ve: VENDER no lo nombra.
    expect(
      File('lib/features/barra/widgets/vender_screen.dart').readAsStringSync().contains('AvisoDeVendidoSinStock'),
      isFalse,
    );
  });
}
