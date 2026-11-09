// Muestras de VER EN EL PLANO (6.5.0): la Recepción de verdad, con un salón y
// una institución inventados, sin base ni nube.
//
//   flutter test tool/puerta_plano_muestra_test.dart --dart-define=salida=<carpeta>
//
// Saca la hoja de una familia en la PC y en el celular, la llegada que se
// vuelve a ver, y el plano entero con las que faltan entrar.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/models/invitado.dart';

import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('puerta_plano').path;
  late SupabaseClient supabase;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    supabase = SupabaseClient('http://localhost:1', 'anon-de-muestra');
    await cargarFuentesPlano();
    await cargarFuentesTotem();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  });

  final alumnos = [
    alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN',
        mesas: [12], sillas: 1, acomp: ['GÓMEZ, ANA'], musica: 'Tusa · Karol G'),
    alumnoDePrueba('acosta', 'ACOSTA, LUCÍA',
        mesas: [14, 15], extras: 1, division: '5° A'),
    alumnoDePrueba('benitez', 'BENÍTEZ, TOMÁS', mesas: [13]),
    for (var i = 1; i <= 30; i++)
      if (![12, 13, 14, 15].contains(i))
        alumnoDePrueba('a$i', 'FAMILIA$i, ALUMNO', mesas: [i]),
  ];
  final filas = [
    for (final (id, nombre, min) in [
      ('benitez', 'BENÍTEZ, TOMÁS', 5),
      ('a3', 'FAMILIA3, ALUMNO', 10),
      ('a7', 'FAMILIA7, ALUMNO', 20),
    ])
      Invitado(
        id: idInvitadoPuerta(id, 0),
        eventoId: eventoMasivo,
        nombreCompleto: nombre,
        dni: '',
        estadoIngreso: EstadoIngreso.ingresado,
        updatedAt: DateTime(2026, 12, 12, 22, min),
      ),
  ];

  Future<void> sacar(
    WidgetTester tester, {
    required String archivo,
    required Size tam,
    required Future<void> Function() tocar,
  }) async {
    await tester.runAsync(FondoTotem.precargar);
    final mundo = PuertaEnMemoria(
      supabase,
      alumnos: alumnos,
      filas: filas,
      plano: ArmadosPredefinidos.normal2aPagina3(),
    );
    final clave = GlobalKey();
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(mundo.motor.bajo.close);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: mundo.panel(eventoMasivo, animarElPlano: false),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tocar();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // La Outfit del panel se carga la primera vez que se usa.
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$archivo')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      // ignore: avoid_print
      print('── PNG en: ${f.path}');
    });
  }

  Finder boton(String alumno) =>
      find.byKey(ValueKey('ver_en_el_plano_${idInvitadoPuerta(alumno, 0)}'));

  testWidgets('la lista, con VER EN EL PLANO', (tester) async {
    await sacar(
      tester,
      archivo: '1_lista_PC.png',
      tam: const Size(1100, 760),
      tocar: () async {},
    );
  });

  testWidgets('la familia en la PC', (tester) async {
    await sacar(
      tester,
      archivo: '2_familia_PC.png',
      tam: const Size(1366, 860),
      tocar: () async {
        await tester.tap(boton('acosta'));
      },
    );
  });

  testWidgets('la familia en el celular', (tester) async {
    await sacar(
      tester,
      archivo: '3_familia_celular.png',
      tam: const Size(390, 844),
      tocar: () async {
        await tester.ensureVisible(boton('acosta'));
        await tester.pump();
        await tester.tap(boton('acosta'));
      },
    );
  });

  testWidgets('la llegada, vuelta a ver en la PC', (tester) async {
    await sacar(
      tester,
      archivo: '4_llegada_PC.png',
      tam: const Size(1366, 860),
      tocar: () async {
        await tester.tap(boton('acosta'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.tap(find.byKey(const ValueKey('ver_la_llegada')));
      },
    );
  });

  testWidgets('el plano entero, con las que faltan entrar', (tester) async {
    await sacar(
      tester,
      archivo: '5_plano_entero_PC.png',
      tam: const Size(1366, 860),
      tocar: () async {
        await tester.tap(find.byTooltip('Más'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.tap(find.text('Ver el plano entero'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.tap(find.byKey(const ValueKey('faltan_entrar')));
      },
    );
  });
}
