// Arnés manual: la página del QR del tótem (sección 8 de la 6.0.0) con datos
// inventados, en PNG para mirarla sin levantar la web.
//
//   flutter test tool/pagina_qr_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
// - PaginaQR_1_busca.png: escribió "gom" y aparecen los que coinciden.
// - PaginaQR_2_dni.png: eligió a Laura, puso un DNI que no coincide.
// - PaginaQR_3_bienvenida.png: entró con su DNI y ve su mesa.
// - PaginaQR_4_a_la_recepcion.png: Pedro no tiene DNI cargado.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/recepcion/lista_invitados_screen.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/recepcion/repositories/supabase_invitados_repository.dart';
import 'package:arguello_events/features/totem/providers/totem_config_provider.dart';
import 'package:arguello_events/models/totem_config.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _ev = 'e0000000-0000-4000-8000-00000000000a';

final _gente = [
  ('i1', 'GÓMEZ, LAURA', '12', true, false),
  ('i2', 'GÓMEZ, PEDRO', '12', false, false),
  ('i3', 'GOMEZA, RUTH', null, true, false),
  ('i4', 'GÓMEZ RUIZ, VALENTINA', '7', true, true),
];

Future<dynamic> _nube(String funcion, Map<String, dynamic> p) async {
  if (funcion == 'puerta_buscar') {
    return [
      for (final g in _gente)
        {
          'id': g.$1,
          'nombre_completo': g.$2,
          'numero_mesa': g.$3,
          'tiene_dni': g.$4,
          'ingresado': g.$5,
        },
    ];
  }
  final g = _gente.firstWhere((g) => g.$1 == p['p_invitado']);
  if (p['p_dni'] == '30111222') {
    return {
      'resultado': 'ok',
      'invitado': {
        'id': g.$1,
        'evento_id': _ev,
        'nombre_completo': g.$2,
        'numero_mesa': g.$3,
        'estado_ingreso': 'ingresado',
      },
    };
  }
  return {'resultado': 'dni_incorrecto', 'quedan': 2};
}

Future<void> _guardar(WidgetTester tester, GlobalKey clave, String nombre,
    String carpeta) async {
  await tester.runAsync(() async {
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await boundary.toImage(pixelRatio: 2);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$carpeta${Platform.pathSeparator}$nombre')
      ..writeAsBytesSync(datos!.buffer.asUint8List());
    print('── PNG en: ${f.path}');
  });
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('pagina_qr_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  setUpAll(() async {
    for (final (familia, archivo) in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('Outfit_regular', 'assets/google_fonts/Outfit-Regular.ttf'),
      ('Outfit_700', 'assets/google_fonts/Outfit-Bold.ttf'),
      ('Oswald_700', 'assets/google_fonts/Oswald-Bold.ttf'),
    ]) {
      await (FontLoader(familia)..addFont(rootBundle.load(archivo))).load();
    }
  });

  Future<GlobalKey> abrir(WidgetTester tester) async {
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseInvitadosRepositoryProvider.overrideWithValue(
            SupabaseInvitadosRepository.con(llamar: _nube, avisar: (_) async {}),
          ),
          totemConfigProvider(_ev).overrideWith(
            (ref) => Stream.value(TotemConfig.defaults(_ev)
                .copyWith(titulo: 'CASAMIENTO GÓMEZ – RUIZ')),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: clave,
            child: const ListaInvitadosScreen(eventoId: _ev),
          ),
        ),
      ),
    );
    await _asentar(tester);
    return clave;
  }

  Future<void> buscar(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('buscador')), 'gom');
    await tester.pump(const Duration(milliseconds: 350));
    await _asentar(tester);
  }

  testWidgets('1 busca', (tester) async {
    final clave = await abrir(tester);
    await buscar(tester);
    await _guardar(tester, clave, 'PaginaQR_1_busca.png', carpeta);
  });

  testWidgets('2 dni', (tester) async {
    final clave = await abrir(tester);
    await buscar(tester);
    await tester.tap(find.text('GÓMEZ, LAURA'));
    await _asentar(tester);
    await tester.enterText(find.byKey(const ValueKey('dni')), '30111999');
    await tester.tap(find.byKey(const ValueKey('ingresar')));
    await _asentar(tester);
    await _guardar(tester, clave, 'PaginaQR_2_dni.png', carpeta);
  });

  testWidgets('3 bienvenida', (tester) async {
    final clave = await abrir(tester);
    await buscar(tester);
    await tester.tap(find.text('GÓMEZ, LAURA'));
    await _asentar(tester);
    await tester.enterText(find.byKey(const ValueKey('dni')), '30111222');
    await tester.tap(find.byKey(const ValueKey('ingresar')));
    await _asentar(tester);
    await _guardar(tester, clave, 'PaginaQR_3_bienvenida.png', carpeta);
  });

  testWidgets('4 a la recepción', (tester) async {
    final clave = await abrir(tester);
    await buscar(tester);
    await tester.tap(find.text('GÓMEZ, PEDRO'));
    await _asentar(tester);
    await _guardar(tester, clave, 'PaginaQR_4_a_la_recepcion.png', carpeta);
  });
}
