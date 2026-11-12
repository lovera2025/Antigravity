// El instalador lleva lo que necesita la central de la puerta: la página del
// celular (que no puede bajarse de internet en el salón) y la regla del
// cortafuegos (sin ella, Windows bloquea a los celulares). Se lee el archivo,
// como `solo_modo_jefe_test.dart`: el instalador no se puede correr acá.
import 'dart:io';

import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final iss = File('installer/junior_eventos_setup.iss').readAsStringSync();
  final armar = File('installer/build_installer.ps1').readAsStringSync();
  const regla = 'Junior Eventos - celulares de la puerta';

  test('arma la página del celular sin nada de internet', () {
    // La línea que se ejecuta, no un mensaje que la nombra.
    final orden = armar
        .split('\n')
        .map((l) => l.trim())
        .singleWhere((l) => l.startsWith('flutter build web'));
    expect(orden, contains('-t lib/puesto_main.dart'));
    expect(orden, contains('--no-web-resources-cdn'));
    expect(orden, contains(r'-o "$puesto"'));
    expect(armar, contains(r'$puesto = Join-Path $root "build\puesto"'));
    // Antes de compilar el instalador, que la lleva adentro.
    expect(armar.indexOf(orden), lessThan(armar.indexOf(r'& $iscc')));
  });

  test('la deja en la carpeta "puesto" al lado del programa, entera', () {
    // `paginaDelCelularProvider` la busca ahí.
    expect(iss, contains(r'Source: "..\build\puesto\*"; DestDir: "{app}\puesto"'));
    expect(iss, contains(r'Type: filesandordirs; Name: "{app}\puesto"'));
  });

  // La 6.6.0 (11-nov-2026) salió con la página a medio copiar: sin la letra de
  // los íconos (cuadraditos en el celular) ni la del texto (sin internet, nada).
  // La línea con el asterisco se lleva lo que haya; estas van con su nombre, y
  // si falta una el instalador no compila.
  test('no se arma con la página del celular a medio copiar', () {
    const obligatorios = [
      r'assets\FontManifest.json',
      r'assets\fonts\MaterialIcons-Regular.otf',
      r'assets\assets\fonts\Roboto-Regular.ttf',
    ];
    for (final archivo in obligatorios) {
      final linea = iss.split('\n').map((l) => l.trim()).singleWhere(
            (l) => l.startsWith('Source: "..\\build\\puesto\\$archivo"'),
            orElse: () => '',
          );
      expect(linea, isNotEmpty, reason: 'el instalador no nombra $archivo');
      expect(
        linea,
        isNot(contains('skipifsourcedoesntexist')),
        reason: 'si falta $archivo, tiene que frenar',
      );
      // Y el script lo comprueba antes de llamar al instalador.
      expect(armar, contains('"$archivo"'));
    }
    expect(
      armar.indexOf('quedó incompleta'),
      inInclusiveRange(
        armar.indexOf('flutter build web'),
        armar.indexOf(r'& $iscc'),
      ),
      reason: 'la comprobación va entre armar la página y el instalador',
    );
    // La letra del texto viene con la app: sin ella, sin internet no dibuja.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/fonts/Roboto-Regular.ttf'));
  });

  test('abre en el cortafuegos los puertos que prueba la central, para la red '
      'que sea', () {
    // La línea de [Run] que crea la regla, no los comentarios.
    final agregar = RegExp(
      '^Filename: .*add rule name=""$regla"".*localport=(\\d+)-(\\d+).*\$',
      multiLine: true,
    ).firstMatch(iss);
    expect(agregar, isNotNull);
    final desde = int.parse(agregar!.group(1)!);
    final hasta = int.parse(agregar.group(2)!);
    // `CentralPuerta.arrancar` prueba kPuertoCentral y los nueve siguientes.
    expect(desde, kPuertoCentral);
    expect(hasta, kPuertoCentral + 9);
    final linea = agregar.group(0)!;
    expect(linea, contains('dir=in'));
    expect(linea, contains('action=allow'));
    expect(linea, contains('protocol=TCP'));
    expect(linea, contains('profile=any'));
    expect(linea, contains(r'program=""{app}\{#MyAppExeName}""'));
  });

  test('borra la regla vieja antes de crearla, y al desinstalar', () {
    final borrar = 'delete rule name=""$regla""';
    expect(iss.indexOf(borrar), greaterThan(-1));
    expect(iss.indexOf(borrar), lessThan(iss.indexOf('add rule name=""$regla""')));
    final desinstalar = iss.substring(iss.indexOf('[UninstallRun]'));
    expect(desinstalar, contains(borrar));
  });

  // La central de la barra (7-nov): las tablets se conectan por TCP y la buscan por UDP.
  test('abre los puertos de la central de la barra y el de buscarla', () {
    Match? regla(String nombre) => RegExp(
          '^Filename: .*add rule name=""$nombre"".*\$',
          multiLine: true,
        ).firstMatch(iss);
    final cajas = regla('Junior Eventos - cajas de la barra')!.group(0)!;
    expect(cajas, contains('protocol=TCP localport=$kPuertoCentralBarra-${kPuertoCentralBarra + 9}'));
    expect(cajas, contains('profile=any'));
    final buscar = regla('Junior Eventos - buscar la central de la barra')!.group(0)!;
    expect(buscar, contains('protocol=UDP localport=$kPuertoBusquedaBarra'));
    expect(buscar, contains('profile=any'));
    final desinstalar = iss.substring(iss.indexOf('[UninstallRun]'));
    expect(desinstalar, contains('delete rule name=""Junior Eventos - cajas de la barra""'));
    expect(desinstalar, contains('delete rule name=""Junior Eventos - buscar la central de la barra""'));
  });
}
