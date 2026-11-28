// Muestras del repositor y del stock por barra (28-nov-2026, para la Técnica del 4-dic),
// sin base ni nube, para mirarlas:
//
//   flutter test tool/repositor_y_stock_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen, con una noche inventada en TÉCNICA PINAROLI:
//   • Stock_1_repositor.png: STOCK en el celular del repositor;
//   • Stock_2_reponer.png: REPONER, con la cuenta de lo vendido sin stock;
//   • Stock_3_reparto_del_jefe.png: STOCK POR BARRA, en PRECIOS del jefe;
//   • Stock_4_vender_no_queda.png: VENDER con señal, lo que no queda no se vende;
//   • Stock_5_vender_sin_senial.png: VENDER sin señal, avisa en rojo y deja vender;
//   • Stock_6_vender_avisos.png: "está en camino" y "Se repusieron…" arriba de VENDER.

// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/reparto_del_stock.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/repositor/stock_de_las_barras_screen.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/widgets/operational_sync_coordinator.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/evento.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart';
import '../test/helpers/tema_de_la_app.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _nico = 'a0000000-0000-4000-8000-000000000009';
const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty ? _salida : Directory.systemTemp.createTempSync('stock_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  // La noche de la fiesta (4-dic, 23:30 en Argentina).
  final ahora = DateTime.utc(2026, 12, 5, 2, 30);

  late BarraEnPrueba prueba;
  late Evento fiesta;
  late ProductoBarra speed, cerveza, agua, fernet;
  late CajaBarra cajaDeMarta;

  BarraEnMemoria b() => prueba.barra;

  Future<void> reparto(ProductoBarra p, String barra, int arranque, {int? aviso}) => b().guardarReparto(
        StockEnLaBarra.para(
          eventoId: fiesta.id,
          productoId: p.id,
          barra: barra,
          arranque: arranque,
          aviso: aviso,
          ahora: ahora,
        ),
        quien: 'Jefe',
      );

  Future<void> vender(CajaBarra caja, ProductoBarra p, int cantidad) => b().vender(
        caja: caja,
        renglones: [RenglonVenta(productoId: p.id, nombre: p.nombre, precio: 5000, cantidad: cantidad)],
        medio: MedioBarra.efectivo,
        efectivo: 5000.0 * cantidad,
        quien: 'Marta',
      );

  Future<void> armarLaNoche() async {
    SharedPreferences.setMockInitialValues({});
    prueba = BarraEnPrueba();
    b().reloj = () => ahora;
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    prueba.eventos.add(fiesta);
    speed = b().producto('Speed', categoria: 'Sin alcohol');
    cerveza = b().producto('Cerveza lata', categoria: 'Cervezas');
    agua = b().producto('Agua sin gas', categoria: 'Sin alcohol');
    fernet = b().producto('Fernet con coca', categoria: 'Tragos');
    b().precio(fiesta.id, speed, 5000, orden: 0, stock: 96);
    b().precio(fiesta.id, cerveza, 4000, orden: 1, stock: 240);
    b().precio(fiesta.id, agua, 2500, orden: 2, stock: 60);
    b().precio(fiesta.id, fernet, 7000, orden: 3);
    await reparto(speed, 'Barra 1', 24, aviso: 6);
    await reparto(speed, 'Barra 2', 24, aviso: 6);
    await reparto(cerveza, 'Barra 1', 60, aviso: 10);
    await reparto(cerveza, 'Barra 2', 60, aviso: 10);
    await reparto(agua, 'Barra 1', 20, aviso: 5);
    await reparto(agua, 'Barra 2', 20, aviso: 5);
    cajaDeMarta = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: _marta,
      operadorNombre: 'Marta',
      numeroCaja: 2,
      sede: 'Barra 1',
    );
    final cajaDeLu = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'l',
      operadorNombre: 'Lu',
      numeroCaja: 7,
      sede: 'Barra 2',
    );
    // La Barra 1 se quedó sin Speed y vendió 5 de más sin señal; la cerveza, en aviso.
    await vender(cajaDeMarta, speed, 29);
    await vender(cajaDeMarta, cerveza, 52);
    await vender(cajaDeMarta, agua, 6);
    await vender(cajaDeLu, speed, 9);
    await vender(cajaDeLu, cerveza, 31);
  }

  Future<void> guardar(WidgetTester tester, GlobalKey clave, String nombre) async {
    await tester.runAsync(() async {
      final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 1);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final archivo = File('$carpeta${Platform.pathSeparator}$nombre')..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${archivo.path}');
    });
  }

  Future<void> fotos(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> letras() async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('STOCK del repositor, en su celular', (tester) async {
    await letras();
    await armarLaNoche();
    final operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_nico, 'Nico', '5555'));
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(412, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: ProviderScope(
        overrides: [
          ...operadores.reemplazos,
          ...prueba.reemplazos,
          barraDelJefeProvider.overrideWithValue(b()),
          rolEnLaBarraProvider.overrideWithValue(RolEnLaBarra.repositor),
          relojDeLaBarraProvider.overrideWithValue(() => ahora),
          enLaWebProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaroDeLaApp(),
          home: StockDeLasBarrasScreen(fiesta: fiesta),
        ),
      ),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(StockDeLasBarrasScreen)));
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          operadores.operadores.lista.single,
          const PermisosEfectivos(repositorBarra: true),
        );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Stock_1_repositor.png');

    // REPONER desde la alerta del Speed de la Barra 1: trae 24 y ya se vendieron 5 de más.
    final reponer = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('stock_reponer_'),
    );
    await tocar(tester, reponer.first);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Stock_2_reponer.png');
  });

  testWidgets('STOCK POR BARRA, el reparto del jefe', (tester) async {
    await letras();
    await armarLaNoche();
    final operadores = OperadoresEnPrueba();
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: ProviderScope(
        overrides: [
          ...operadores.reemplazos,
          ...prueba.reemplazos,
          barraDelJefeProvider.overrideWithValue(b()),
          esRolJefeProvider.overrideWithValue(true),
          relojDelJefeProvider.overrideWithValue(() => ahora),
          relojDeLaBarraProvider.overrideWithValue(() => ahora),
          enLaWebProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaroDeLaApp(),
          home: RepartoDelStockScreen(fiesta: fiesta),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Stock_3_reparto_del_jefe.png');
  });

  testWidgets('VENDER con el stock de su barra: con señal, sin señal y los avisos', (tester) async {
    await letras();
    await armarLaNoche();
    final operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    var conSenial = true;
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: ProviderScope(
        overrides: [
          ...operadores.reemplazos,
          ...prueba.reemplazos,
          hayCentralALaVistaProvider.overrideWithValue((_) => conSenial),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaroDeLaApp(),
          home: VenderScreen(fiesta: fiesta, caja: cajaDeMarta),
        ),
      ),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(VenderScreen)));
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          operadores.operadores.lista.single,
          const PermisosEfectivos(barra: true),
        );
    await tester.pumpAndSettle();
    await fotos(tester);
    final elSpeed = find.byKey(Key('producto_${speed.id}'));

    // Con señal: no queda Speed en la Barra 1, no se vende.
    await tocar(tester, elSpeed);
    expect(find.byKey(const Key('sin_stock_no_se_vende')), findsOneWidget);
    await guardar(tester, clave, 'Stock_4_vender_no_queda.png');
    await tocar(tester, find.byKey(const Key('sin_stock_entendido')));

    // Sin señal: avisa en rojo y deja vender.
    conSenial = false;
    await tocar(tester, elSpeed);
    expect(find.byKey(const Key('sin_stock_sin_senial')), findsOneWidget);
    await guardar(tester, clave, 'Stock_5_vender_sin_senial.png');
    await tocar(tester, find.text('NO HAY'));

    // Vuelve la señal: el repositor avisó que va con cerveza y ya repuso el Speed.
    conSenial = true;
    await b().avisarQueVa(eventoId: fiesta.id, productoId: cerveza.id, barra: 'Barra 1', quien: 'Nico');
    await b().anotarMovimientoDeStock(
      MovimientoDeStock.reposicion(
        eventoId: fiesta.id,
        productoId: speed.id,
        barra: 'Barra 1',
        cantidad: 24,
        ahora: ahora,
      ),
      quien: 'Nico',
    );
    c.read(operationalSyncRevisionProvider.notifier).bump();
    await tester.pumpAndSettle();
    await fotos(tester);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Stock_6_vender_avisos.png');
  });
}
