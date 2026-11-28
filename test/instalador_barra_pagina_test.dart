// La página del iPhone de la encargada y del repositor de barra (28-nov-2026): el
// instalador la arma sin nada de internet, la deja entera en {app}\barra_pagina (donde la
// busca la central de la barra) y frena si quedó a medio copiar, como la del celular de
// la puerta (`instalador_puesto_test.dart`). Se leen los archivos: el instalador no se
// corre acá.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final iss = File('installer/junior_eventos_setup.iss').readAsStringSync();
  final armar = File('installer/build_installer.ps1').readAsStringSync();
  final provider = File('lib/features/barra/central/central_barra_provider.dart').readAsStringSync();

  test('arma la página del iPhone sin nada de internet, antes del instalador', () {
    final orden = armar
        .split('\n')
        .map((l) => l.trim())
        .singleWhere((l) => l.startsWith('flutter build web') && l.contains('barra_pagina_main'));
    expect(orden, contains('-t lib/barra_pagina_main.dart'));
    expect(orden, contains('--no-web-resources-cdn'));
    expect(orden, contains(r'-o "$barraPagina"'));
    expect(armar, contains(r'$barraPagina = Join-Path $root "build\barra_pagina"'));
    expect(armar.indexOf(orden), lessThan(armar.indexOf(r'& $iscc')));
    // Dos `flutter build web` seguidos: se borra lo que dejó el primero.
    expect(armar.indexOf(r'.dart_tool\flutter_build'), lessThan(armar.indexOf(orden)));
  });

  test('la deja entera en "barra_pagina", donde la busca la central', () {
    expect(iss, contains(r'Source: "..\build\barra_pagina\*"; DestDir: "{app}\barra_pagina"'));
    expect(iss, contains(r'Type: filesandordirs; Name: "{app}\barra_pagina"'));
    expect(provider, contains(r"${Platform.pathSeparator}barra_pagina'"));
  });

  test('no se arma con la página a medio copiar', () {
    const obligatorios = [
      r'assets\FontManifest.json',
      r'assets\fonts\MaterialIcons-Regular.otf',
      r'assets\assets\fonts\Roboto-Regular.ttf',
    ];
    for (final archivo in obligatorios) {
      final linea = iss.split('\n').map((l) => l.trim()).singleWhere(
            (l) => l.startsWith('Source: "..\\build\\barra_pagina\\$archivo"'),
            orElse: () => '',
          );
      expect(linea, isNotEmpty, reason: 'el instalador no nombra $archivo');
      expect(linea, isNot(contains('skipifsourcedoesntexist')));
    }
    final control = armar.indexOf('La página del iPhone de la barra quedó incompleta');
    expect(control, greaterThan(armar.indexOf('lib/barra_pagina_main.dart')));
    expect(control, lessThan(armar.indexOf(r'& $iscc')));
  });

  test('la página no baja letras de internet', () {
    final main = File('lib/barra_pagina_main.dart').readAsStringSync();
    expect(main, contains('GoogleFonts.config.allowRuntimeFetching = false'));
    // Ni Supabase: todo se lo dice la notebook.
    expect(main, isNot(contains('Supabase.initialize')));
  });
}
