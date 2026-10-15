// El instalador lleva lo que necesita la central de la puerta: la página del
// celular (que no puede bajarse de internet en el salón) y la regla del
// cortafuegos (sin ella, Windows bloquea a los celulares). Se lee el archivo,
// como `solo_modo_jefe_test.dart`: el instalador no se puede correr acá.
import 'dart:io';

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
}
