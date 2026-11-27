// Muestras de BARRA del jefe (etapa 7), sin base ni nube, para mirarla:
//
//   flutter test tool/barra_jefe_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen, con una noche inventada en TÉCNICA PINAROLI (el 4 de diciembre):
//   • Jefe_1_catalogo_pc.png: CATÁLOGO en la PC, con las fotos y el producto elegido al lado;
//   • Jefe_2_precios_pc.png: PRECIOS, con el recargo y la lista en papel al costado;
//   • Jefe_3_cajas_pc.png: CAJAS, los totales, una tarjeta por caja y el stock;
//   • Jefe_4_ventas_de_una_caja_pc.png: las ventas de una caja, con anular y reimprimir;
//   • Jefe_5_cambiar_fiesta_pc.png: CAMBIAR DE FIESTA;
//   • Jefe_6_cajas_celular.png y Jefe_7_precios_celular.png: lo mismo en un celular.

// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/noche_de_barra.dart';
import '../test/helpers/operadores_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty ? _salida : Directory.systemTemp.createTempSync('jefe_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  /// TÉCNICA PINAROLI con su catálogo, sus precios y tres cajas: dos abiertas y una
  /// cerrada con $ 500 de menos. Una venta anulada (`test/helpers/noche_de_barra.dart`).
  Future<(BarraEnPrueba, OperadoresEnPrueba, CajaBarra)> noche() async {
    final n = await nocheDeBarra();
    return (n.prueba, n.operadores, n.marta);
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

  Future<void> letras() async {
    SharedPreferences.setMockInitialValues({});
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  }

  Future<void> fotos(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
  }

  Future<(GlobalKey, CajaBarra)> montar(
    WidgetTester tester,
    Size tamano,
    PestanaBarraJefe pestana, {
    Future<void> Function(BarraEnPrueba prueba)? antes,
  }) async {
    await letras();
    final (prueba, operadores, marta) = await noche();
    await antes?.call(prueba);
    final clave = GlobalKey();
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: ProviderScope(
        overrides: [
          ...operadores.reemplazos,
          ...prueba.reemplazos,
          barraDelJefeProvider.overrideWithValue(prueba.barra),
          esRolJefeProvider.overrideWithValue(true),
          relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 11, 20, 15)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
          home: BarraJefeScreen(pestanaInicial: pestana),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await fotos(tester);
    return (clave, marta);
  }

  testWidgets('CATÁLOGO en la PC', (tester) async {
    final (clave, _) = await montar(tester, const Size(1280, 860), PestanaBarraJefe.catalogo);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_1_catalogo_pc.png');
  });

  testWidgets('PRECIOS en la PC', (tester) async {
    final (clave, _) = await montar(tester, const Size(1280, 860), PestanaBarraJefe.precios);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_2_precios_pc.png');
  });

  testWidgets('PRECIOS con el precio de lista, una receta abierta y las botellas', (tester) async {
    late String fernetConCoca;
    final (clave, _) = await montar(
      tester,
      const Size(1400, 1500),
      PestanaBarraJefe.precios,
      antes: (prueba) async {
        final b = prueba.barra;
        final ahora = DateTime(2026, 11, 20);
        ProductoBarra de(String nombre) => b.productosGuardados.firstWhere((p) => p.nombre == nombre);
        fernetConCoca = de('Fernet con coca').id;
        final botellaFernet = b.producto('Fernet 750', categoria: 'Botellas');
        final botellaCoca = b.producto('Coca-Cola 2,25', categoria: 'Botellas');
        for (final (id, lista, cc) in [
          (de('Cerveza tirada').id, 1500.0, null),
          (de('Quilmes lata').id, 1500.0, null),
          (de('Coca-Cola').id, 900.0, null),
          (de('Champán').id, 14000.0, null),
          (de('Silla extra').id, 0.0, null),
          (botellaFernet.id, 11740.0, 750),
          (botellaCoca.id, 3000.0, 2250),
        ]) {
          await b.guardarCosto(
            CostoBarra.para(eventoId: BarraEnPrueba.id(1), productoId: id, precioLista: lista, contenidoCc: cc, ahora: ahora),
            quien: 'Jefe',
          );
        }
        for (final (id, cc) in [(botellaFernet.id, 200), (botellaCoca.id, 500)]) {
          await b.guardarReceta(
            RecetaBarra.para(
              eventoId: BarraEnPrueba.id(1),
              productoId: fernetConCoca,
              ingredienteId: id,
              cantidad: cc,
              unidad: UnidadDeReceta.cc,
              ahora: ahora,
            ),
            quien: 'Jefe',
          );
        }
      },
    );
    await tester.tap(find.byKey(Key('jefe_receta_$fernetConCoca')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_2b_precios_con_lista_pc.png');
  });

  testWidgets('GANANCIA en la PC, con la ganancia de cada producto abierta', (tester) async {
    final (clave, _) = await montar(
      tester,
      const Size(1280, 1300),
      PestanaBarraJefe.ganancia,
      antes: (prueba) async {
        final b = prueba.barra;
        final ahora = DateTime(2026, 11, 20);
        ProductoBarra de(String nombre) => b.productosGuardados.firstWhere((p) => p.nombre == nombre);
        final fernetConCoca = de('Fernet con coca').id;
        final botellaFernet = b.producto('Fernet 750', categoria: 'Botellas');
        final botellaCoca = b.producto('Coca-Cola 2,25', categoria: 'Botellas');
        for (final (id, lista, cc) in [
          (de('Cerveza tirada').id, 1500.0, null),
          (de('Quilmes lata').id, 1500.0, null),
          (de('Coca-Cola').id, 900.0, null),
          (de('Gin tonic').id, 2400.0, null),
          (de('Mojito').id, 2100.0, null),
          (de('Campari con naranja').id, 2200.0, null),
          (de('Speed con vodka').id, 2600.0, null),
          (de('Agua sin gas').id, 600.0, null),
          (de('Champán').id, 14000.0, null),
          (de('Silla extra').id, 0.0, null),
          (botellaFernet.id, 11740.0, 750),
          (botellaCoca.id, 3000.0, 2250),
        ]) {
          await b.guardarCosto(
            CostoBarra.para(eventoId: BarraEnPrueba.id(1), productoId: id, precioLista: lista, contenidoCc: cc, ahora: ahora),
            quien: 'Jefe',
          );
        }
        for (final (id, cc) in [(botellaFernet.id, 200), (botellaCoca.id, 500)]) {
          await b.guardarReceta(
            RecetaBarra.para(
              eventoId: BarraEnPrueba.id(1),
              productoId: fernetConCoca,
              ingredienteId: id,
              cantidad: cc,
              unidad: UnidadDeReceta.cc,
              ahora: ahora,
            ),
            quien: 'Jefe',
          );
        }
      },
    );
    await tester.tap(find.byKey(const Key('jefe_ganancia_por_producto')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_8_ganancia_pc.png');
  });

  testWidgets('CAJAS y las ventas de una caja en la PC', (tester) async {
    final (clave, marta) = await montar(tester, const Size(1280, 860), PestanaBarraJefe.cajas);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_3_cajas_pc.png');
    await tester.tap(find.byKey(Key('jefe_caja_${marta.id}')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_4_ventas_de_una_caja_pc.png');
  });

  testWidgets('CAMBIAR DE FIESTA', (tester) async {
    final (clave, _) = await montar(tester, const Size(1280, 860), PestanaBarraJefe.catalogo);
    await tester.tap(find.byKey(const Key('jefe_cambiar_fiesta')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_5_cambiar_fiesta_pc.png');
  });

  testWidgets('CAJAS y PRECIOS en un celular', (tester) async {
    final (clave, _) = await montar(tester, const Size(390, 844), PestanaBarraJefe.cajas);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_6_cajas_celular.png');
    await tester.tap(find.byKey(const Key('jefe_pestana_precios')));
    await tester.pumpAndSettle();
    await fotos(tester);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_7_precios_celular.png');
  });
}
