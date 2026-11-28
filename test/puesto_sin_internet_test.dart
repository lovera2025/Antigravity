// La página del celular de la puerta tiene que abrir sin internet (6.2.1).
//
// Flutter en la web necesita una letra de base: si la app no trae una familia
// llamada "Roboto", la baja de fonts.gstatic.com al arrancar y no dibuja nada
// hasta tenerla. Con el router del salón sin internet ese pedido se queda
// esperando y el celular veía la página en blanco (23-oct-2026, con la central
// en 192.168.1.40). Lo cuida que la app traiga su Roboto.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la app trae su Roboto, y el archivo está', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final familia = RegExp(
      r'-\s*family:\s*Roboto\s*\n\s*fonts:\s*\n\s*-\s*asset:\s*(\S+)',
    ).firstMatch(pubspec);
    expect(familia, isNotNull, reason: 'sin la familia Roboto, la web la baja de internet');
    final archivo = File(familia!.group(1)!);
    expect(archivo.existsSync(), isTrue, reason: archivo.path);
    // Un TTF de verdad, no un archivo vacío.
    expect(archivo.lengthSync(), greaterThan(50000));
    expect(File('assets/fonts/LICENSE-Roboto.txt').existsSync(), isTrue);
  });

  test('la página del celular no baja letras de google_fonts', () {
    final main = File('lib/puesto_main.dart').readAsStringSync();
    expect(main, contains('GoogleFonts.config.allowRuntimeFetching = false'));
  });

  // El locutor (28-nov-2026): la misma página, con `?locutor`. Las letras se cortan
  // antes de elegir, y el locutor se elige antes de crear el cliente de la puerta (si
  // no, el mismo celular se conectaría además como un puesto y se sacaría a sí mismo).
  test('la rama del locutor: sin bajar letras, y antes del cliente de la puerta', () {
    final main = File('lib/puesto_main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final letras = main.indexOf('GoogleFonts.config.allowRuntimeFetching = false');
    final locutor = main.indexOf("containsKey('locutor')");
    final puerta = main.indexOf('final cliente = ClienteCentral(');
    expect(letras, greaterThan(0));
    expect(locutor, greaterThan(letras));
    expect(puerta, greaterThan(locutor));
    expect(main.substring(locutor, puerta), contains('return;'));
    final pantalla = File('lib/features/recepcion/central/pantalla_locutor.dart').readAsStringSync();
    expect(pantalla, contains('GoogleFonts.outfit'), reason: 'Outfit viene con la página');
    expect(pantalla, isNot(contains('GoogleFonts.oswald')));
  });
}
