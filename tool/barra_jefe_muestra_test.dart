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
import 'package:arguello_events/features/barra/services/imagen_de_producto.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty ? _salida : Directory.systemTemp.createTempSync('jefe_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  /// TÉCNICA PINAROLI con su catálogo, sus precios y tres cajas: dos abiertas y una
  /// cerrada con $ 500 de menos. Una venta anulada.
  Future<(BarraEnPrueba, OperadoresEnPrueba, CajaBarra)> noche() async {
    final operadores = OperadoresEnPrueba();
    final prueba = BarraEnPrueba()..imagen = imagenDelProducto;
    final pinaroli = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    prueba.eventos.addAll([
      pinaroli,
      fiestaDePrueba(BarraEnPrueba.id(2), 'ROTONDA', DateTime(2026, 12, 12, 22)),
      fiestaDePrueba(BarraEnPrueba.id(3), 'GUEMEZ DE TEJADA', DateTime(2026, 12, 18, 22)),
      fiestaDePrueba(BarraEnPrueba.id(4), 'LA DE OCTUBRE', DateTime(2026, 10, 30, 22)),
    ]);
    final b = prueba.barra;
    final productos = <(ProductoBarra, double, int?, int?)>[];
    var orden = 0;
    for (final (nombre, categoria, precio, stock, aviso) in [
      ('Fernet con coca', 'Tragos', 6000.0, 120, 20),
      ('Gin tonic', 'Tragos', 6500.0, 80, 15),
      ('Mojito', 'Tragos', 6500.0, 60, 10),
      ('Campari con naranja', 'Tragos', 6000.0, 40, 8),
      ('Speed con vodka', 'Tragos', 6500.0, 30, 5),
      ('Cerveza tirada', 'Cervezas', 4000.0, 200, 30),
      ('Quilmes lata', 'Cervezas', 3500.0, 96, 12),
      ('Coca-Cola', 'Sin alcohol', 2500.0, 72, 12),
      ('Agua sin gas', 'Sin alcohol', 2000.0, null, null),
      ('Champán', 'Botellas', 35000.0, 12, 2),
      ('Silla extra', 'Otros', 8000.0, null, null),
    ]) {
      final p = b.producto(nombre, categoria: categoria, orden: orden++);
      b.precio(pinaroli.id, p, precio, orden: orden, stock: stock, aviso: aviso);
      productos.add((p, precio, stock, aviso));
    }
    final redBull = b.producto('Red Bull', categoria: 'Sin alcohol', orden: orden);
    await b.guardarProducto(redBull.conCambios(activo: false), quien: 'Jefe');
    await b.guardarRecargo(
      RecargoBarra.para(eventoId: pinaroli.id, pct: 5, ahora: DateTime(2026, 11, 1)),
      quien: 'Jefe',
    );

    var hora = DateTime.utc(2026, 12, 5, 1, 5); // 22:05 en Argentina
    b.reloj = () => hora;
    final cajas = <CajaBarra>[];
    for (final (numero, nombre) in [(1, 'Marta'), (2, 'Sofía'), (3, 'Lucas')]) {
      cajas.add(await b.abrirCaja(eventoId: pinaroli.id, operadorId: 'op$numero', operadorNombre: nombre, numeroCaja: numero));
      hora = hora.add(const Duration(minutes: 5));
    }
    VentaBarra? anular;
    for (var i = 0; i < 60; i++) {
      hora = hora.add(Duration(minutes: 2 + i % 3));
      final caja = cajas[i % 3];
      final (p, precio, _, _) = productos[(i * 7) % productos.length];
      final n = 1 + i % 3;
      final total = precio * n;
      final transferencia = i % 4 == 1;
      final recargo = transferencia ? (total * 0.05).roundToDouble() : 0.0;
      final v = await b.vender(
        caja: caja,
        renglones: [RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: n)],
        medio: transferencia ? MedioBarra.transferencia : MedioBarra.efectivo,
        efectivo: transferencia ? 0 : total,
        transferencia: transferencia ? total + recargo : 0,
        recargo: recargo,
        recargoPct: transferencia ? 5 : null,
        quien: caja.operadorNombre!,
      );
      await b.anotarVale(ValeBarra.salio(
        venta: v,
        bebidas: [BebidaDelVale(n, p.nombre)],
        porSeparado: false,
        hechoPor: caja.operadorNombre,
        ahora: hora,
      ));
      if (i == 9) anular = v;
    }
    await b.anular(anular!, motivo: 'se cobró dos veces', quien: 'Marta');
    hora = hora.add(const Duration(minutes: 30));
    final lucas = cajas[2];
    final ventasLucas = await b.ventasDeLaCaja(lucas.id);
    final efectivo = ventasLucas.fold<double>(0, (s, v) => s + v.efectivo);
    await b.cerrarCaja(lucas, efectivoContado: efectivo - 500, diferencia: -500, quien: 'Lucas');
    return (prueba, operadores, cajas.first);
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
