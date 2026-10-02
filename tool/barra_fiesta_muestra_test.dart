// Arnés manual: dibuja la barra de la fiesta con los cuatro botones nuevos
// (PLANO, SORTEO, PLANILLAS y ENTRADAS) y MÁS, y guarda PNG para mirarlos sin
// levantar la app ni tocar la base.
//
//   flutter test tool/barra_fiesta_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
//   Barra_ancha.png, Barra_notebook.png y Barra_angosta.png — la barra en tres
//     anchos de ventana;
//   Barra_menu_sorteo.png, Barra_menu_planillas.png y Barra_menu_mas.png — cada
//     menú abierto.
//
// Los botones y los menús son los de la app. Lo de la izquierda (contadores,
// chips, REGISTRAR y CONTRATOS) está copiado a mano de la pantalla, con los
// mismos tamaños, para ver cuánto lugar le queda al grupo.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/widgets/grupo_fiesta_toolbar.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

Widget _pastilla(String texto, IconData icono, Color color, bool compacto) =>
    Container(
      margin: EdgeInsets.only(right: compacto ? 6 : 10),
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 6 : 10,
        vertical: compacto ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(compacto ? 10 : 12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: compacto ? 13 : 14, color: color),
          SizedBox(width: compacto ? 4 : 6),
          Text(
            texto,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: compacto ? 12 : 13,
              color: color,
            ),
          ),
        ],
      ),
    );

Widget _botonLleno(
  String texto,
  IconData icono,
  Color fondo,
  Color letra,
  bool compacto, {
  required bool grande,
}) =>
    Padding(
      padding: EdgeInsets.only(right: compacto ? 6 : 10),
      child: ElevatedButton.icon(
        onPressed: () {},
        icon: Icon(icono, size: compacto ? 15 : 18),
        label: Text(
          texto,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: compacto ? 11 : 12,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: fondo,
          foregroundColor: letra,
          padding: EdgeInsets.symmetric(
            horizontal: compacto ? (grande ? 10 : 8) : (grande ? 20 : 16),
            vertical: compacto ? 6 : 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compacto ? 12 : 16),
          ),
        ),
      ),
    );

/// La barra entera, armada como en `detalle_evento_masivo_screen.dart`.
Widget _barra(double anchoVentana, {bool conCopia = false}) {
  final compacto = anchoVentana < 1520;
  final double margen = compacto ? 12 : 32;
  final anchoMaximoPrimarios = math.max(
    160.0,
    anchoVentana -
        margen * 2 -
        GrupoFiestaToolbar.anchoSoloIconos(compacto: compacto) -
        (compacto ? 100 : 130),
  );
  final primarios = Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'ALUMNOS INSCRIPTOS',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: compacto ? 10 : 12,
          letterSpacing: compacto ? 0.7 : 1.2,
          color: Colors.grey,
        ),
      ),
      SizedBox(width: compacto ? 8 : 12),
      _pastilla('132', Icons.people_alt_rounded, const Color(0xFFD4AF37),
          compacto),
      _pastilla('118/132', Icons.assignment_turned_in_outlined,
          Colors.teal.shade700, compacto),
      _pastilla('14 · \$ 412.000', Icons.warning_amber_rounded,
          Colors.red.shade700, compacto),
      _pastilla('23', Icons.table_restaurant_outlined,
          Colors.deepPurple.shade600, compacto),
      SizedBox(width: compacto ? 2 : 6),
      _botonLleno(
        compacto ? 'REGISTRAR' : 'REGISTRAR ALUMNO',
        Icons.person_add_alt_1,
        const Color(0xFFD4AF37),
        Colors.black,
        compacto,
        grande: true,
      ),
      _botonLleno(
        'CONTRATOS',
        Icons.assignment_turned_in_outlined,
        Colors.teal.shade700,
        Colors.white,
        compacto,
        grande: false,
      ),
    ],
  );
  return SizedBox(
    width: anchoVentana,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: 10),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: anchoMaximoPrimarios),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: primarios,
            ),
          ),
          SizedBox(width: compacto ? 8 : 12),
          Expanded(
            child: GrupoFiestaToolbar(
              compacto: compacto,
              onPlano: () {},
              onSortear: () {},
              onDeshacer: () {},
              onRestaurar: conCopia ? () {} : null,
              onHistorial: () {},
              onPlanillaSorteo: () {},
              onPlanoImpreso: () {},
              onPlanillaEntrega: () {},
              onPlanillaMora: () {},
              alumnosConMora: 14,
              onEntradas: () {},
            ),
          ),
          SizedBox(width: compacto ? 6 : 8),
          BotonMasFiesta(
            compacto: compacto,
            ordenAlfabetico: true,
            modoSeleccion: false,
            onOrden: () {},
            onSeleccion: () {},
            onListaPuerta: () {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('barra_muestra').path;

  Future<void> preparar() async {
    await cargarFuentesPlano();
    // Los íconos de Material, que en los tests no vienen cargados.
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  }

  /// Dibuja la barra en una ventana de [ancho], abre [menu] si se pide, y
  /// guarda el PNG.
  Future<void> sacar(
    WidgetTester tester, {
    required String archivo,
    required double ancho,
    double alto = 76,
    String? menu,
    bool conCopia = false,
  }) async {
    await preparar();
    final clave = GlobalKey();
    final tam = Size(ancho, alto);
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Align(
              alignment: Alignment.topLeft,
              child: _barra(ancho, conCopia: conCopia),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (menu != null) {
      await tester.tap(find.byKey(Key(menu)));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);

    final grupo = tester.getSize(find.byKey(const Key('fiesta_grupo')));
    print('── $archivo: ventana de ${ancho.round()} px, el grupo ocupa '
        '${grupo.width.round()} px');

    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$archivo')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  }

  testWidgets('la barra en una pantalla ancha', (tester) async {
    await sacar(tester, archivo: 'Barra_ancha.png', ancho: 1920);
  });

  testWidgets('la barra en una notebook', (tester) async {
    await sacar(tester, archivo: 'Barra_notebook.png', ancho: 1366);
  });

  testWidgets('la barra en una ventana angosta', (tester) async {
    await sacar(tester, archivo: 'Barra_angosta.png', ancho: 1000);
  });

  testWidgets('el menú de SORTEO', (tester) async {
    await sacar(
      tester,
      archivo: 'Barra_menu_sorteo.png',
      ancho: 1366,
      alto: 330,
      menu: 'fiesta_sorteo',
      conCopia: true,
    );
  });

  testWidgets('el menú de PLANILLAS', (tester) async {
    await sacar(
      tester,
      archivo: 'Barra_menu_planillas.png',
      ancho: 1366,
      alto: 330,
      menu: 'fiesta_planillas',
    );
  });

  testWidgets('el menú de MÁS', (tester) async {
    await sacar(
      tester,
      archivo: 'Barra_menu_mas.png',
      ancho: 1366,
      alto: 290,
      menu: 'fiesta_mas',
    );
  });
}
