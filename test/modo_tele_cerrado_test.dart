import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Desde la tele no hay camino al panel ni a cobrar** (la tele es el tótem,
/// 24-nov-2026), como en `modo_barra_cerrado_test`: la tele abre sin PIN y
/// queda en un salón, así que lo único que sale de ella es "Salir del modo
/// tele", con el PIN del jefe. Lee los archivos de `lib/features/tele/`.
void main() {
  final carpeta = Directory('lib/features/tele');
  // Sin los \r: en una carpeta con core.autocrlf, git deja los archivos con finales de
  // línea de Windows y la búsqueda del fin de cada función ('\n  }\n') no los encontraba
  // (26-nov-2026, al juntar la tele).
  final archivos = {
    for (final f in carpeta.listSync().whereType<File>())
      if (f.path.endsWith('.dart'))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync().replaceAll('\r\n', '\n'),
  };

  test('hay archivos que leer', () {
    expect(archivos.keys.any((p) => p.endsWith('pantalla_tele.dart')), isTrue);
  });

  test('ningún archivo de la tele llega a cobrar, a la caja, al panel ni a Mi Empresa',
      () {
    const prohibidos = [
      'dashboard_screen.dart',
      'role_gate_screen.dart',
      'cierre_caja',
      'mi_empresa',
      'finanzas',
      'caja_sesiones/widgets',
      'detalle_evento_masivo_screen.dart',
      'pago',
      'cobro',
      'entradas/widgets',
      'barra/widgets',
      'recepcion_unified_screen.dart',
    ];
    for (final MapEntry(key: archivo, value: texto) in archivos.entries) {
      for (final linea in texto.split('\n')) {
        if (!linea.trimLeft().startsWith('import ')) continue;
        for (final p in prohibidos) {
          expect(linea.contains(p), isFalse, reason: '$archivo importa $p: $linea');
        }
      }
      // Tampoco se navega a otra pantalla desde la tele.
      expect(texto.contains('Navigator.push('), isFalse, reason: archivo);
      expect(texto.contains('MaterialPageRoute'), isFalse, reason: archivo);
    }
  });

  test('salir del modo tele y pasar a principal piden el PIN del jefe', () {
    final pantalla = archivos.entries
        .firstWhere((e) => e.key.endsWith('pantalla_tele.dart'))
        .value;
    for (final f in ['_salirDelModoTele', '_pasarAPrincipal']) {
      final desde = pantalla.indexOf('Future<void> $f(');
      expect(desde, greaterThan(0), reason: f);
      final cuerpo = pantalla.substring(desde, pantalla.indexOf('\n  }\n', desde));
      expect(cuerpo, contains('_pinDelJefe('), reason: f);
    }
    expect(pantalla, contains('esPinMaestro('));
  });

  test('la tele no se cierra con el control: Atrás abre o cierra el menú', () {
    final pantalla = archivos.entries
        .firstWhere((e) => e.key.endsWith('pantalla_tele.dart'))
        .value;
    expect(pantalla, contains('canPop: false'));
  });

  test('la app entra al modo tele antes de mirar el rol y el PIN', () {
    final main = File('lib/main.dart').readAsStringSync();
    final router = main.substring(main.indexOf('class _RoleRouter'));
    final tele = router.indexOf('modoTeleProvider');
    final rol = router.indexOf('userRoleProvider');
    expect(tele, greaterThan(0));
    expect(tele, lessThan(rol));
    expect(router, contains('return const PantallaTele()'));
  });

  test('el modo tele lo elige solo el jefe, desde la tarjeta TÓTEM', () {
    final llamadas = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.readAsStringSync().contains('elegirModoTele(')) {
        llamadas.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(
      llamadas..sort(),
      ['lib/features/dashboard/dashboard_screen.dart', 'lib/features/tele/elegir_modo_tele.dart'],
    );
  });
}
