import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/caja_sesiones/models/sesion_caja.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/sesiones_caja_repository.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/sesion_caja_status_chip.dart';
import 'package:arguello_events/features/dashboard/widgets/encabezado_del_inicio.dart';

import 'helpers/operadores_en_memoria.dart';

/// La barra de arriba del inicio **en un celular** (6.5.0). El 10-nov el usuario abrió la
/// app en su Android y mandó la foto: el logo, "JUNIOR EVENTOS", MODO JEFE, "Caja
/// cerrada", la nube y los tres botones salían uno encima del otro. En un celular el
/// título va sin el nombre, el estado de la caja va corto y los botones, en un menú.
///
/// Con `--dart-define=salida=<carpeta>` deja además una imagen de cada caso para mirarla.
const _salida = String.fromEnvironment('salida', defaultValue: '');

class _CajasAbiertas extends SesionesEnMemoria {
  _CajasAbiertas(this.lista);
  final List<SesionCaja> lista;

  @override
  Future<List<SesionCaja>> sesionesAbiertas() async => lista;
}

SesionCaja _sesion(String id, String nombre) {
  final ahora = DateTime.now().toUtc();
  return SesionCaja(
    id: id,
    operadorId: 'op-$id',
    abiertaAt: ahora.subtract(const Duration(hours: 3)),
    cambioInicial: 20000,
    etiqueta: 'Tarde',
    lastHeartbeat: ahora,
    createdAt: ahora,
    updatedAt: ahora,
    operadorNombre: nombre,
  );
}

void main() {
  setUpAll(() async {
    // Las letras de verdad: con las de prueba (cuadrados) la imagen no se lee.
    final roboto = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await roboto.load();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  });

  final clave = GlobalKey();

  /// La barra del inicio como la arma `DashboardScreen`: el menú, el título, el estado
  /// de la caja (solo en modo jefe), la nube (acá, un lugar de su tamaño) y los botones.
  Future<List<String>> abrir(
    WidgetTester tester, {
    required double ancho,
    bool modoJefe = true,
    String? cajaDe,
    List<SesionCaja> abiertas = const [],
  }) async {
    final tocados = <String>[];
    final enCelular = ancho < 600;
    tester.view.physicalSize = Size(ancho, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sesionesCajaRepositoryProvider.overrideWithValue(_CajasAbiertas(abiertas)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
        home: RepaintBoundary(
          key: clave,
          child: Scaffold(
            drawer: const Drawer(),
            appBar: AppBar(
              titleSpacing: enCelular ? 4 : null,
              title: TituloDelInicio(
                enCelular: enCelular,
                modoJefe: modoJefe,
                cajaDe: cajaDe,
              ),
              actions: [
                if (modoJefe)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Center(
                      child: SesionCajaStatusChip(
                        key: const Key('estado_caja'),
                        compacto: enCelular,
                      ),
                    ),
                  ),
                // La nube (`SyncCloudIndicator`): un botón de ícono.
                const SizedBox(key: Key('nube'), width: 40, height: 40, child: Icon(Icons.cloud_done_outlined, size: 20)),
                if (enCelular)
                  MasDelInicio(
                    temaOscuro: false,
                    onActualizar: () => tocados.add('actualizar'),
                    onCambiarTema: () => tocados.add('tema'),
                    onCerrarSesion: () => tocados.add('salir'),
                  )
                else ...[
                  IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.dark_mode_rounded, size: 20), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.logout_rounded, size: 20), onPressed: () {}),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return tocados;
  }

  /// Nada se pisa ni se sale: el título termina antes de donde empieza lo de la derecha,
  /// y todo queda adentro de la pantalla.
  void nadaSePisa(WidgetTester tester, double ancho) {
    expect(tester.takeException(), isNull);
    final titulo = tester.getRect(find.byType(TituloDelInicio));
    final derecha = [
      if (find.byKey(const Key('estado_caja')).evaluate().isNotEmpty)
        tester.getRect(find.byKey(const Key('estado_caja'))),
      tester.getRect(find.byKey(const Key('nube'))),
    ];
    final primero = derecha.map((r) => r.left).reduce((a, b) => a < b ? a : b);
    expect(titulo.left, greaterThanOrEqualTo(48), reason: 'el título no pisa el menú');
    expect(titulo.right, lessThanOrEqualTo(primero + 0.5), reason: 'el título pisa lo de la derecha');
    for (final r in derecha) {
      expect(r.right, lessThanOrEqualTo(ancho), reason: 'algo se sale de la pantalla');
    }
    final mas = find.byKey(const Key('inicio_mas'));
    if (mas.evaluate().isNotEmpty) {
      expect(tester.getRect(mas).right, lessThanOrEqualTo(ancho));
    }
  }

  Future<void> foto(WidgetTester tester, String nombre) async {
    if (_salida.isEmpty) return;
    await tester.runAsync(() async {
      final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      Directory(_salida).createSync(recursive: true);
      File('$_salida${Platform.pathSeparator}$nombre.png')
          .writeAsBytesSync(datos!.buffer.asUint8List());
    });
  }

  for (final ancho in [360.0, 393.0, 412.0]) {
    testWidgets('en un celular de ${ancho.toInt()} de ancho, en modo jefe, nada se pisa',
        (tester) async {
      await abrir(tester, ancho: ancho);
      nadaSePisa(tester, ancho);
      expect(find.text('JUNIOR EVENTOS'), findsNothing, reason: 'en el celular va el logo solo');
      expect(find.byKey(const Key('inicio_modo_jefe')), findsOneWidget);
      expect(find.text('Cerrada'), findsOneWidget);
      expect(find.text('Caja cerrada'), findsNothing);
      expect(find.byKey(const Key('inicio_mas')), findsOneWidget);
      await foto(tester, 'inicio_celular_${ancho.toInt()}_jefe');
    });

    testWidgets('en un celular de ${ancho.toInt()}, con una caja abierta de nombre largo, '
        'tampoco', (tester) async {
      await abrir(
        tester,
        ancho: ancho,
        abiertas: [_sesion('1', 'MARIA DE LOS ANGELES'), _sesion('2', 'Juan')],
      );
      nadaSePisa(tester, ancho);
      // El cartel del modo jefe se sigue leyendo: entero si entra, y si no, "JEFE".
      final cartel = find.byKey(const Key('inicio_modo_jefe'));
      final dice = tester.widget<Text>(find.descendant(of: cartel, matching: find.byType(Text))).data;
      expect(['MODO JEFE', 'JEFE'], contains(dice));
      expect(tester.getSize(cartel).width, greaterThanOrEqualTo(dice == 'JEFE' ? 36 : 60),
          reason: 'el cartel quedó aplastado');
      expect(find.textContaining('desde'), findsNothing, reason: 'el "desde cuándo" no entra');
      expect(find.text('+1'), findsOneWidget, reason: 'hay otra caja abierta');
      await foto(tester, 'inicio_celular_${ancho.toInt()}_caja_abierta');
    });

    testWidgets('en un celular de ${ancho.toInt()}, en la caja con un nombre largo, el '
        'cartel se acorta', (tester) async {
      await abrir(
        tester,
        ancho: ancho,
        modoJefe: false,
        cajaDe: 'MARIA DE LOS ANGELES FERNANDEZ DE LA TORRE',
      );
      nadaSePisa(tester, ancho);
      expect(find.byKey(const Key('inicio_caja_de')), findsOneWidget);
      await foto(tester, 'inicio_celular_${ancho.toInt()}_caja');
    });
  }

  testWidgets('en el celular, el menú tiene Actualizar, el tema y Cerrar sesión, y andan',
      (tester) async {
    final tocados = await abrir(tester, ancho: 393);
    for (final (clave, esperado) in [
      ('inicio_mas_actualizar', 'actualizar'),
      ('inicio_mas_tema', 'tema'),
      ('inicio_mas_salir', 'salir'),
    ]) {
      await tester.tap(find.byKey(const Key('inicio_mas')));
      await tester.pumpAndSettle();
      expect(find.text('Actualizar'), findsOneWidget);
      expect(find.text('Tema oscuro'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      await tester.tap(find.byKey(Key(clave)));
      await tester.pumpAndSettle();
      expect(tocados.last, esperado);
    }
    expect(tocados, ['actualizar', 'tema', 'salir']);
  });

  testWidgets('en la PC sigue como estaba: el nombre, el estado entero y los tres botones',
      (tester) async {
    await abrir(tester, ancho: 1280, abiertas: [_sesion('1', 'Maxi')]);
    expect(tester.takeException(), isNull);
    expect(find.text('JUNIOR EVENTOS'), findsOneWidget);
    expect(find.textContaining('Caja activa · Maxi · Tarde · desde'), findsOneWidget);
    expect(find.byKey(const Key('inicio_mas')), findsNothing);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    await foto(tester, 'inicio_pc');
  });

  test('en el cierre de caja, el total neto no parte el monto entre dos renglones', () {
    final c = File('lib/features/cierre_caja/cierre_caja_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(c, contains(r"state.totalNeto.toCurrency().replaceAll(' ', ' ')"));
  });

  test('la pantalla del inicio usa este encabezado, con el corte del celular', () {
    final d = File('lib/features/dashboard/dashboard_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(d, contains('CortesPantalla.esCelular(MediaQuery.sizeOf(context).width)'));
    expect(d, contains('title: TituloDelInicio('));
    expect(d, contains('SesionCajaStatusChip(compacto: enCelular)'));
    expect(d, contains('MasDelInicio('));
  });
}
