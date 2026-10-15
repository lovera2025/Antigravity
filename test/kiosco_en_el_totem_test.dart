import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El modo kiosco en la pantalla del tótem (`totem_display.dart`, sección 6
/// de la 6.0.0).
///
/// La pantalla habla con la nube y con la otra ventana y no se puede montar
/// en un test, así que se lee del texto del archivo, como
/// `solo_modo_jefe_test`. Lo que decide el kiosco (Esc, doble clic, puntero,
/// avisos) se prueba entero en `capa_kiosco_test`; la ventana de verdad, con
/// el arnés `tool/kiosco_prueba.dart`.
///
/// Acá se cuida lo que dice el pendiente: **al esconder el tótem sale del
/// kiosco antes**, por los dos caminos (el ✕ del tótem y `KioskLauncher.close`,
/// que manda "pausar" y espera la respuesta antes de esconder). Si no, la
/// ventana escondida quedaría sin bordes y, al volver, tapando la tele entera.
void main() {
  final fuente = File('lib/features/totem/totem_display.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  /// El cuerpo de la función que empieza con [firma], hasta la próxima que
  /// empieza en la misma columna.
  String cuerpo(String firma) {
    final i = fuente.indexOf(firma);
    expect(i, isNot(-1), reason: 'no está "$firma"');
    final fin = fuente.indexOf('\n  }\n', i);
    return fuente.substring(i, fin);
  }

  test('pausar sale del kiosco antes que nada', () {
    final pausar = cuerpo('Future<void> _pausar() async {');
    final sale = pausar.indexOf('await _kiosco?.salir();');
    expect(sale, isNot(-1), reason: 'pausar tiene que salir del kiosco');
    expect(sale, lessThan(pausar.indexOf('_sub?.cancel()')),
        reason: 'antes de cortar nada');
  });

  test('"pausar" contesta recién cuando salió del kiosco', () {
    final i = fuente.indexOf("case 'pausar':");
    final caso = fuente.substring(i, fuente.indexOf('return null;', i));
    expect(caso, contains('await _pausar();'),
        reason: 'KioskLauncher.close esconde la ventana cuando esto contesta');
  });

  test('el ✕ sale del kiosco antes de esconder la ventana', () {
    final i = fuente.indexOf('_ExitButton(');
    final boton = fuente.substring(i, fuente.indexOf('.hide();', i));
    expect(boton, contains('await _pausar();'));
  });

  test('en kiosco no se le cambia la forma a la ventana', () {
    expect(
      cuerpo('Future<void> _aplicarFrameVentana(TotemOrientation orientacion)'),
      contains('if (_enKiosco) return;'),
    );
    expect(cuerpo('Future<void> _girarPantalla() async {'),
        contains('if (_enKiosco) return;'));
  });

  test('el kiosco es solo de la ventana del escritorio', () {
    expect(fuente, contains('late final ControladorKiosco? _kiosco = widget.windowId == null'));
    expect(fuente, contains('CapaKiosco(controlador: kiosco, child: pantalla)'));
  });
}
