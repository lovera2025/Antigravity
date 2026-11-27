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

/// Lo que cobra el proveedor y cómo se prepara cada trago, como lo cargaría el jefe: las
/// latas y botellas con su precio de lista; los tragos, con su receta (nunca un precio de
/// lista escrito a mano). Devuelve el id del Fernet con coca.
Future<String> listaYRecetas(BarraEnPrueba prueba) async {
  final b = prueba.barra;
  final ahora = DateTime(2026, 11, 20);
  final fiesta = BarraEnPrueba.id(1);
  ProductoBarra de(String nombre) => b.productosGuardados.firstWhere((p) => p.nombre == nombre);
  ProductoBarra botella(String nombre) => b.producto(nombre, categoria: 'Para los tragos');
  final fernet = botella('Fernet 750');
  final coca = botella('Coca-Cola 2,25');
  final gin = botella('Gin 750');
  final tonica = botella('Agua tónica 1,5');
  final ron = botella('Ron 750');
  final campari = botella('Campari 750');
  final naranja = botella('Jugo de naranja 1 L');
  final vodka = botella('Vodka 1 L');
  final speed = botella('Speed 250');
  for (final (id, lista, cc) in [
    (de('Cerveza tirada').id, 1500.0, null),
    (de('Quilmes lata').id, 1500.0, null),
    (de('Coca-Cola').id, 900.0, null),
    (de('Agua sin gas').id, 600.0, null),
    (de('Champán').id, 14000.0, null),
    (de('Silla extra').id, 0.0, null),
    (fernet.id, 11740.0, 750),
    (coca.id, 3000.0, 2250),
    (gin.id, 9000.0, 750),
    (tonica.id, 2500.0, 1500),
    (ron.id, 8000.0, 750),
    (campari.id, 12000.0, 750),
    (naranja.id, 1500.0, 1000),
    (vodka.id, 8000.0, 1000),
    (speed.id, 1200.0, null),
  ]) {
    await b.guardarCosto(
      CostoBarra.para(eventoId: fiesta, productoId: id, precioLista: lista, contenidoCc: cc, ahora: ahora),
      quien: 'Jefe',
    );
  }
  for (final (trago, lleva) in [
    ('Fernet con coca', [(fernet.id, 200, UnidadDeReceta.cc), (coca.id, 500, UnidadDeReceta.cc)]),
    ('Gin tonic', [(gin.id, 100, UnidadDeReceta.cc), (tonica.id, 300, UnidadDeReceta.cc)]),
    ('Mojito', [(ron.id, 100, UnidadDeReceta.cc)]),
    ('Campari con naranja', [(campari.id, 100, UnidadDeReceta.cc), (naranja.id, 300, UnidadDeReceta.cc)]),
    ('Speed con vodka', [(vodka.id, 500, UnidadDeReceta.cc), (speed.id, 1, UnidadDeReceta.unidad)]),
  ]) {
    for (final (id, cantidad, unidad) in lleva) {
      await b.guardarReceta(
        RecetaBarra.para(
          eventoId: fiesta,
          productoId: de(trago).id,
          ingredienteId: id,
          cantidad: cantidad,
          unidad: unidad,
          ahora: ahora,
        ),
        quien: 'Jefe',
      );
    }
  }
  return de('Fernet con coca').id;
}

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

  testWidgets('PRECIOS con el precio de lista, y la ventanita de cómo se prepara un trago', (tester) async {
    late String fernetConCoca;
    final (clave, _) = await montar(
      tester,
      const Size(1400, 1100),
      PestanaBarraJefe.precios,
      antes: (prueba) async => fernetConCoca = await listaYRecetas(prueba),
    );
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_2b_precios_con_lista_pc.png');
    await tester.tap(find.byKey(Key('jefe_receta_$fernetConCoca')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_2c_como_se_prepara_pc.png');
  });

  testWidgets('GANANCIA en la PC, con la ganancia de cada producto abierta', (tester) async {
    final (clave, _) = await montar(
      tester,
      const Size(1280, 1500),
      PestanaBarraJefe.ganancia,
      antes: (prueba) async => listaYRecetas(prueba),
    );
    await tester.tap(find.byKey(const Key('jefe_ganancia_por_producto')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_8_ganancia_pc.png');
  });

  testWidgets('CAJAS: una caja con lo que sacó y dio la encargada, y el cartel de SACAR EFECTIVO', (tester) async {
    late CajaBarra laDeMarta;
    final (clave, marta) = await montar(
      tester,
      const Size(1280, 1100),
      PestanaBarraJefe.cajas,
      antes: (prueba) async {
        final b = prueba.barra;
        laDeMarta = b.cajasGuardadas.firstWhere((c) => c.operadorNombre == 'Marta');
        for (final (tipo, monto, motivo) in [
          (TipoMovimientoDeCaja.cambio, 5000.0, 'Se quedó sin billetes chicos'),
          (TipoMovimientoDeCaja.retiro, 25000.0, 'Mucho efectivo en la caja'),
        ]) {
          await b.anotarMovimientoDeCaja(
            MovimientoDeCaja.nuevo(
              eventoId: laDeMarta.eventoId,
              cajaBarraId: laDeMarta.id,
              tipo: tipo,
              monto: monto,
              motivo: motivo,
              ahora: DateTime.utc(2026, 12, 5, 2),
            ),
            quien: 'Romi',
          );
        }
      },
    );
    await tester.tap(find.byKey(Key('jefe_caja_${laDeMarta.id}')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_9_caja_con_retiros_pc.png');
    await tester.ensureVisible(find.byKey(const Key('jefe_caja_sacar_efectivo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('jefe_caja_sacar_efectivo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mov_monto')), '20000');
    await tester.tap(find.byKey(const Key('mov_rapido_0')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Jefe_10_sacar_efectivo_pc.png');
    expect(marta, isNotNull);
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
