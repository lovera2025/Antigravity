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

  Future<(GlobalKey, CajaBarra)> montar(WidgetTester tester, Size tamano, PestanaBarraJefe pestana) async {
    await letras();
    final (prueba, operadores, marta) = await noche();
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
