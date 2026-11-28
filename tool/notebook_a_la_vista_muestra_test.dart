// Muestras de la notebook de la barra a la vista de todos (27-nov-2026), sin base ni
// nube, para mirarlas:
//
//   flutter test tool/notebook_a_la_vista_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen, con una noche inventada en TÉCNICA PINAROLI:
//   • Notebook_1_el_candado.png: BARRA del jefe, con el candado de arriba abierto;
//   • Notebook_2_vista_simple.png: la vista simple, solo la central (con lo que no aceptó);
//   • Notebook_3_la_clave.png: el logo apretado 2 segundos: la clave de la notebook;
//   • Notebook_4_se_bloquea_sola.png: con la clave bien, si se bloquea sola, y ENTRAR.

// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/central/filas_de_la_red.dart' show PendientesDeLaBarra;
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/jefe/vista_simple_de_la_notebook.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/noche_de_barra.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

/// La central de la Barra 1, prendida, con sus tablets y enganchada con la Barra 2.
class _CentralDeLaMuestra extends CentralDeLaBarra {
  @override
  EstadoCentralBarra build() {
    final ahora = DateTime(2026, 12, 4, 23, 50);
    return EstadoCentralBarra(
      eventoId: BarraEnPrueba.id(1),
      puerto: kPuertoCentralBarra,
      barra: 'Barra 1',
      direcciones: const ['192.168.1.100'],
      contestaBusqueda: true,
      cajas: [
        CajaConectada(
          equipo: 't1',
          nombre: 'Caja 1 · Marta',
          conectada: true,
          ultimaVez: ahora,
          porSubir: PendientesDeLaBarra.nada,
          barra: 'Barra 1',
        ),
        CajaConectada(
          equipo: 't2',
          nombre: 'Caja 2 · Sofía',
          conectada: true,
          ultimaVez: ahora,
          porSubir: const PendientesDeLaBarra(ventas: 2, otros: 0),
          barra: 'Barra 1',
        ),
        CajaConectada(
          equipo: 't3',
          nombre: 'Encargada · Romi',
          conectada: true,
          ultimaVez: ahora,
          porSubir: PendientesDeLaBarra.nada,
        ),
      ],
      otras: const [EngancheConOtra(barra: 'Barra 2', conectada: true)],
      rechazos: [
        RechazoDeLaCentral(
          cuando: DateTime(2026, 12, 4, 23, 41),
          equipo: 't2',
          nombre: 'Caja 2 · Sofía',
          tabla: 'barra_anulaciones',
          id: 'x',
          motivo: 'Anula solo la encargada',
        ),
      ],
    );
  }

  @override
  Future<void> reanudar(String eventoId, {DateTime? fechaDeLaFiesta}) async {}

  @override
  Future<void> apagar() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty ? _salida : Directory.systemTemp.createTempSync('notebook_muestra').path;
  Directory(carpeta).createSync(recursive: true);

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

  testWidgets('la notebook de la barra, a la vista de todos', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    final n = await nocheDeBarra();
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: ProviderScope(
        overrides: [
          ...n.operadores.reemplazos,
          ...n.prueba.reemplazos,
          barraDelJefeProvider.overrideWithValue(n.prueba.barra),
          esRolJefeProvider.overrideWithValue(true),
          centralSePrendeAcaProvider.overrideWithValue(true),
          centralDeLaBarraProvider.overrideWith(_CentralDeLaMuestra.new),
          relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 11, 20, 15)),
          esLaClaveDeEstaNotebookProvider.overrideWithValue((escrita) async => escrita.trim() == '2026'),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
          home: const BarraJefeScreen(pestanaInicial: PestanaBarraJefe.cajas),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await fotos(tester);

    // 1. El candado de arriba, abierto.
    await tester.tap(find.byKey(const Key('jefe_bloquear')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Notebook_1_el_candado.png');

    // 2. "Dejar solo la central ahora": la vista simple.
    await tester.tap(find.byKey(const Key('jefe_bloquear_ahora')));
    await tester.pumpAndSettle();
    await fotos(tester);
    expect(find.byKey(const Key('jefe_vista_simple')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Notebook_2_vista_simple.png');

    // 3. El logo, apretado 2 segundos: la clave.
    final dedo = await tester.startGesture(tester.getCenter(find.byKey(const Key('jefe_logo'))));
    await tester.pump(kApretarElLogo + const Duration(milliseconds: 200));
    await dedo.up();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('notebook_clave')), '2026');
    await tester.pumpAndSettle();
    await guardar(tester, clave, 'Notebook_3_la_clave.png');

    // 4. Con la clave bien: si se bloquea sola, y ENTRAR.
    await tester.tap(find.byKey(const Key('notebook_clave_listo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notebook_se_bloquea_sola')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Notebook_4_se_bloquea_sola.png');
  });
}
