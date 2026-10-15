// El modo kiosco del tótem (sección 6 de la 6.0.0): qué es un doble clic
// (`DobleClic`), los pedidos a la ventana y los avisos (`ControladorKiosco`), y
// la capa que escucha Esc, el doble clic y el puntero (`CapaKiosco`). La
// ventana se reemplaza por una en memoria: la de verdad se prueba con el arnés
// `tool/kiosco_prueba.dart`.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/services/kiosco.dart';
import 'package:arguello_events/features/totem/widgets/capa_kiosco.dart';

/// La ventana, en memoria: lo que se le pidió y si puede.
class _Ventana implements Kiosco {
  var puede = true;
  final pedidos = <String>[];
  Completer<void>? frenar;

  /// En el navegador, si está en pantalla completa ahora; null en la ventana
  /// del escritorio.
  @override
  bool? activo;

  @override
  Future<bool> entrar() async {
    pedidos.add('entrar');
    await frenar?.future;
    if (puede && activo != null) activo = true;
    return puede;
  }

  @override
  Future<bool> salir() async {
    pedidos.add('salir');
    if (activo != null) activo = false;
    return true;
  }
}

void main() {
  group('qué es un doble clic', () {
    final t0 = DateTime(2026, 12, 12, 23);
    DateTime en(int ms) => t0.add(Duration(milliseconds: ms));

    test('dos toques rápidos y cerca, sí', () {
      final d = DobleClic();
      expect(d.toque(const Offset(100, 100), en(0)), isFalse);
      expect(d.toque(const Offset(110, 105), en(250)), isTrue);
    });

    test('lentos, no', () {
      final d = DobleClic();
      d.toque(const Offset(100, 100), en(0));
      expect(d.toque(const Offset(100, 100), en(400)), isFalse);
    });

    test('lejos uno del otro, no', () {
      final d = DobleClic();
      d.toque(const Offset(100, 100), en(0));
      expect(d.toque(const Offset(300, 100), en(100)), isFalse);
    });

    test('un tercer toque no hace otro', () {
      final d = DobleClic();
      d.toque(const Offset(100, 100), en(0));
      expect(d.toque(const Offset(100, 100), en(100)), isTrue);
      expect(d.toque(const Offset(100, 100), en(200)), isFalse);
    });

    test('el lento cuenta como primero del siguiente', () {
      final d = DobleClic();
      d.toque(const Offset(100, 100), en(0));
      d.toque(const Offset(100, 100), en(500));
      expect(d.toque(const Offset(100, 100), en(700)), isTrue);
    });
  });

  group('los pedidos a la ventana', () {
    test('entrar y salir, con el aviso de cómo se sale', () async {
      final v = _Ventana();
      final c = ControladorKiosco(v);
      addTearDown(c.dispose);
      await c.entrar();
      expect(c.enKiosco, isTrue);
      expect(c.aviso, ControladorKiosco.avisoAlEntrar);
      await c.salir();
      expect(c.enKiosco, isFalse);
      expect(c.aviso, isNull);
      expect(v.pedidos, ['entrar', 'salir']);
    });

    test('si la ventana no puede, lo dice y sigue como ventana', () async {
      final v = _Ventana()..puede = false;
      final c = ControladorKiosco(v);
      addTearDown(c.dispose);
      await c.entrar();
      expect(c.enKiosco, isFalse);
      expect(c.aviso, ControladorKiosco.avisoSiFalla);
    });

    test('salir sin estar en kiosco no le pide nada a la ventana', () async {
      final v = _Ventana();
      final c = ControladorKiosco(v);
      addTearDown(c.dispose);
      await c.salir();
      expect(v.pedidos, isEmpty);
    });

    test('un salir que llega mientras entra, sale después', () async {
      final v = _Ventana()..frenar = Completer<void>();
      final c = ControladorKiosco(v);
      addTearDown(c.dispose);
      final entra = c.entrar();
      final sale = c.salir();
      v.frenar!.complete();
      await Future.wait([entra, sale]);
      expect(c.enKiosco, isFalse);
      expect(v.pedidos, ['entrar', 'salir']);
    });

    test('dos entrar seguidos piden una sola vez', () async {
      final v = _Ventana();
      final c = ControladorKiosco(v);
      addTearDown(c.dispose);
      await Future.wait([c.entrar(), c.entrar()]);
      expect(v.pedidos, ['entrar']);
    });
  });

  group('la capa', () {
    late _Ventana ventana;
    late ControladorKiosco c;
    late DateTime ahora;

    Future<void> montar(WidgetTester tester) async {
      ventana = _Ventana();
      c = ControladorKiosco(ventana);
      ahora = DateTime(2026, 12, 12, 23);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CapaKiosco(
            controlador: c,
            reloj: () => ahora,
            child: const ColoredBox(
              color: Colors.black,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ));
    }

    // Saca el aviso y sus temporizadores antes de que termine la prueba.
    Future<void> cerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    Future<void> clic(WidgetTester tester, {int despuesDe = 0}) async {
      ahora = ahora.add(Duration(milliseconds: despuesDe));
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
    }

    MouseCursor cursor(WidgetTester tester) => tester
        .widgetList<MouseRegion>(find.descendant(
          of: find.byType(CapaKiosco),
          matching: find.byType(MouseRegion),
        ))
        .first
        .cursor;

    testWidgets('Esc saca del kiosco', (tester) async {
      await montar(tester);
      await c.entrar();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.enKiosco, isFalse);
      await cerrar(tester);
    });

    testWidgets('fuera del kiosco, Esc no hace nada y sigue de largo',
        (tester) async {
      await montar(tester);
      final manejada = await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(manejada, isFalse);
      expect(ventana.pedidos, isEmpty);
      await cerrar(tester);
    });

    testWidgets('doble clic en cualquier lugar saca del kiosco', (tester) async {
      await montar(tester);
      await c.entrar();
      await tester.pump();
      await clic(tester);
      expect(c.enKiosco, isTrue, reason: 'un clic solo, no');
      await clic(tester, despuesDe: 200);
      expect(c.enKiosco, isFalse);
      await cerrar(tester);
    });

    testWidgets('dos clics lentos no lo sacan', (tester) async {
      await montar(tester);
      await c.entrar();
      await tester.pump();
      await clic(tester);
      await clic(tester, despuesDe: 800);
      expect(c.enKiosco, isTrue);
      await cerrar(tester);
    });

    testWidgets('fuera del kiosco, el doble clic no hace nada', (tester) async {
      await montar(tester);
      await clic(tester);
      await clic(tester, despuesDe: 100);
      expect(ventana.pedidos, isEmpty);
      await cerrar(tester);
    });

    testWidgets('el aviso al entrar dura 3 s', (tester) async {
      await montar(tester);
      await c.entrar();
      await tester.pump();
      expect(find.text(ControladorKiosco.avisoAlEntrar), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(c.aviso, isNull);
      await cerrar(tester);
    });

    testWidgets('si no se pudo, lo dice en palabras', (tester) async {
      await montar(tester);
      ventana.puede = false;
      await c.entrar();
      await tester.pump();
      expect(find.text(ControladorKiosco.avisoSiFalla), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('en kiosco el puntero se esconde a los 3 s y vuelve al moverlo',
        (tester) async {
      await montar(tester);
      await c.entrar();
      await tester.pump();
      expect(cursor(tester), MouseCursor.defer);
      await tester.pump(const Duration(seconds: 3));
      expect(cursor(tester), SystemMouseCursors.none);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(50, 50));
      await tester.pump();
      expect(cursor(tester), MouseCursor.defer);
      await mouse.removePointer();
      await cerrar(tester);
    });

    testWidgets('fuera del kiosco el puntero no se esconde', (tester) async {
      await montar(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(cursor(tester), MouseCursor.defer);
      await cerrar(tester);
    });

    testWidgets('al salir, el puntero vuelve', (tester) async {
      await montar(tester);
      await c.entrar();
      await tester.pump(const Duration(seconds: 3));
      expect(cursor(tester), SystemMouseCursors.none);
      await c.salir();
      await tester.pump();
      expect(cursor(tester), MouseCursor.defer);
      await cerrar(tester);
    });
  });
}
