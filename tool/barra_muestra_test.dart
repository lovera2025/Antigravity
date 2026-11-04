// Muestras de VENDER de la barra con los dos diseños (Noche dorada y Mostrador) y las
// fotos de verdad de `assets/barra/`, sin base ni nube: para mirar cómo se ve.
//
//   flutter test tool/barra_muestra_test.dart
//   flutter test tool/barra_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen cuatro PNG: cada diseño en una tablet acostada y en un celular. Lo que se mira:
//   • cada producto con la foto de su trago, sola, por el nombre;
//   • uno sin foto conocida, con sus iniciales;
//   • uno agotado (apagado y en gris) y uno con pocos (la marca en rojo);
//   • dos productos en la cuenta, con el − n + en su tarjeta;
//   • los tres pagos (en Mostrador, en la tablet, como barras).
//
// Los productos y los precios son inventados.

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
import 'package:arguello_events/features/barra/estilos/disenio_barra.dart';
import 'package:arguello_events/features/barra/services/imagen_de_producto.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final carpeta = _salida.isNotEmpty ? _salida : Directory.systemTemp.createTempSync('barra_muestra').path;

  for (final d in DisenioBarra.values) {
    for (final (nombre, tamano) in [('tablet', const Size(1280, 800)), ('celular', const Size(390, 844))]) {
      testWidgets('${d.nombre} en $nombre', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await cargarFuentesPlano();
        final iconos = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await iconos.load();

        final operadores = OperadoresEnPrueba();
        operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
        final prueba = BarraEnPrueba()..imagen = imagenDelProducto;
        prueba.disenio.disenio = d;
        final fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', DateTime.now().add(const Duration(days: 5)));
        prueba.eventos.add(fiesta);
        final b = prueba.barra;
        final productos = <ProductoBarra>[];
        var orden = 0;
        for (final (n, cat, precio, stock) in [
          ('Fernet con coca', 'Tragos', 6000.0, null),
          ('Cerveza lata', 'Cervezas', 3500.0, 24),
          ('Gin tonic', 'Tragos', 7000.0, null),
          ('Speed con vodka', 'Tragos', 8000.0, 3),
          ('Mojito', 'Tragos', 7000.0, null),
          ('Champán Chandon', 'Espumantes', 45000.0, null),
          ('Gaseosa', 'Sin alcohol', 2000.0, null),
          ('Agua sin gas', 'Sin alcohol', 1000.0, 0),
          ('Combo egresados', 'Promos', 15000.0, null),
        ]) {
          final p = b.producto(n, categoria: cat);
          b.precio(fiesta.id, p, precio, orden: orden++, stock: stock, aviso: stock == null ? null : 3);
          productos.add(p);
        }
        final caja = await b.abrirCaja(eventoId: fiesta.id, operadorId: _marta, operadorNombre: 'Marta', numeroCaja: 2);

        // Las fotos se leen de verdad: antes de pintar, que estén en memoria.
        final clave = GlobalKey();
        tester.view.physicalSize = tamano * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(RepaintBoundary(
          key: clave,
          child: ProviderScope(
            overrides: [...operadores.reemplazos, ...prueba.reemplazos],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
              home: VenderScreen(fiesta: fiesta, caja: caja),
            ),
          ),
        ));
        final c = ProviderScope.containerOf(tester.element(find.byType(VenderScreen)));
        await c.read(appRoleProvider.notifier).entrarComoBarra(
              operadores.operadores.lista.single,
              const PermisosEfectivos(barra: true),
            );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (final p in productos) {
            final img = imagenDelProducto(p);
            if (img != null) await precacheImage(img, tester.element(find.byType(VenderScreen)));
          }
        });
        await tester.pumpAndSettle();
        for (final p in [productos[0], productos[0], productos[1]]) {
          final f = find.byKey(Key('producto_${p.id}'));
          await tester.ensureVisible(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
        }
        await tester.drag(find.byType(GridView), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.runAsync(() async {
          final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final imagen = await boundary.toImage(pixelRatio: 1.5);
          final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
          final archivo = File('$carpeta${Platform.pathSeparator}Barra_${d.clave}_$nombre.png')
            ..writeAsBytesSync(datos!.buffer.asUint8List());
          print('── PNG en: ${archivo.path}');
        });
      });
    }
  }
}
