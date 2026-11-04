import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/estilos/fotos_de_la_barra.dart';
import 'package:arguello_events/features/barra/services/imagen_de_producto.dart';
import 'package:arguello_events/features/totem/services/foto_guardada.dart';

/// Las fotos de los tragos vienen adentro de la app y cada producto toma la suya por
/// el nombre (pedido del usuario, 3 y 4-nov: "el jefe no las va a cargar").
void main() {
  group('la foto que le toca a cada nombre', () {
    for (final (nombre, clave) in [
      ('Fernet con coca', 'fernet'),
      ('FERNÉT', 'fernet'),
      ('Fernet Branca 1L', 'fernet'),
      ('Gin tonic', 'gin_tonic'),
      ('Speed con vodka', 'vodka'),
      ('Vodka con Red Bull', 'vodka'),
      ('Vodka con naranja', 'destornillador'),
      ('Destornillador', 'destornillador'),
      ('Campari con naranja', 'campari'),
      ('Aperol spritz', 'aperol'),
      ('Cynar con pomelo', 'cynar'),
      ('Gancia con Sprite', 'gancia'),
      ('Vermú con soda', 'vermut'),
      ('Martini Rosso', 'vermut'),
      ('Gin de frutos rojos', 'gin_frutos_rojos'),
      ('Whisky', 'whisky'),
      ('Cuba libre', 'ron'),
      ('Margarita', 'tequila'),
      ('Tequila sunrise', 'tequila_sunrise'),
      ('Shot de tequila', 'shot'),
      ('Mojito', 'mojito'),
      ('Caipiroska de frutilla', 'caipirinha'),
      ('Daiquiri de frutilla', 'daiquiri'),
      ('Piña colada', 'pina_colada'),
      ('Blue lagoon', 'trago_azul'),
      ('Clericó', 'clerico'),
      ('Sex on the beach', 'trago_frutal'),
      // Las cervezas por marca, y la lata cuando hay una aparte.
      ('Quilmes', 'quilmes'),
      ('Cerveza Quilmes porrón', 'quilmes'),
      ('Quilmes lata 473', 'quilmes_lata'),
      ('Heineken', 'heineken'),
      ('Heineken lata', 'heineken_lata'),
      ('Brahma lata', 'brahma'),
      ('Andes Origen Negra', 'andes'),
      ('Patagonia Amber Lager', 'patagonia'),
      ('Stella Artois', 'stella'),
      ('Coronita', 'corona'),
      ('Budweiser', 'budweiser'),
      ('Amstel', 'amstel'),
      ('Miller lata', 'miller'),
      ('Guinness', 'cerveza_negra'),
      // Sin marca: por estilo, y si no por cómo se sirve.
      ('IPA', 'cerveza_ipa'),
      ('Cerveza APA tirada', 'cerveza_ipa'),
      ('Cerveza roja', 'cerveza_roja'),
      ('Stout', 'cerveza_negra'),
      ('Pinta de rubia', 'cerveza_rubia'),
      ('Imperial Golden', 'imperial_golden'),
      ('Imperial lata 710', 'imperial'),
      ('Cerveza rubia', 'cerveza_rubia'),
      ('Cerveza lata', 'cerveza_lata'),
      ('Cerveza', 'cerveza_lata'),
      ('Cerveza tirada', 'cerveza_tirada'),
      ('Cerveza porrón', 'cerveza_porron'),
      // Bebidas blancas por marca.
      ('Smirnoff con Speed', 'smirnoff'),
      ('Absolut', 'absolut'),
      ('Gin Gordon\'s', 'gordons'),
      ('Bombay Sapphire tonic', 'bombay'),
      ('Johnnie Walker Red Label', 'johnnie_walker'),
      ('Jack Daniel\'s con coca', 'jack_daniels'),
      ('Chivas Regal 12', 'chivas'),
      ('Bacardi', 'bacardi'),
      ('Havana Club 7', 'havana_club'),
      ('Jäger', 'jagermeister'),
      ('Malibu con piña', 'malibu'),
      ('Cinzano Rosso', 'cinzano'),
      ('Vino tinto Malbec', 'vino_tinto'),
      ('Vino blanco', 'vino_blanco'),
      ('Champán Chandon Extra Brut', 'champan'),
      ('Champaña', 'champan'),
      // Sin alcohol.
      ('Agua sin gas', 'agua'),
      ('Agua con gas', 'agua_con_gas'),
      ('Agua Villavicencio', 'villavicencio'),
      ('Agua tónica', 'gaseosa'),
      ('Gaseosa', 'gaseosa'),
      ('Coca lata', 'coca_cola'),
      ('Coca-Cola', 'coca_cola'),
      ('Sprite', 'sprite'),
      ('Fanta', 'fanta'),
      ('Pepsi', 'pepsi'),
      ('Speed', 'speed'),
      ('Red Bull', 'red_bull'),
      ('Monster', 'monster'),
      ('Limonada con menta', 'limonada'),
      ('Jugo de naranja', 'jugo'),
      ('Café', 'cafe'),
    ]) {
      test('"$nombre" → $clave', () => expect(FotoDeLaBarra.para(nombre), clave));
    }

    test('si el nombre no dice nada, por la categoría', () {
      expect(FotoDeLaBarra.para('La de la casa', 'Cervezas'), 'cerveza_lata');
      expect(FotoDeLaBarra.para('Especial del barman', 'Tragos'), 'gin_tonic');
      expect(FotoDeLaBarra.para('Botella', 'Espumantes'), 'champan');
    });

    test('si tampoco, ninguna: la tarjeta muestra la inicial', () {
      expect(FotoDeLaBarra.para('Combo egresados'), isNull);
      expect(FotoDeLaBarra.para(''), isNull);
    });

    test('"gin" es una palabra: "Ginger ale" no es gin tonic', () {
      expect(FotoDeLaBarra.para('Ginger ale'), isNot('gin_tonic'));
    });

    test('cada foto de la biblioteca la puede tomar algún nombre, y ninguna está dos veces', () {
      expect(FotoDeLaBarra.claves.toSet().length, FotoDeLaBarra.claves.length);
      final nombres = [
        'fernet', 'gin', 'gin frutos rojos', 'vodka', 'destornillador', 'campari', 'aperol', 'cynar',
        'gancia', 'vermut', 'whisky', 'ron', 'tequila', 'tequila sunrise', 'shot', 'mojito', 'caipi',
        'daiquiri', 'pina colada', 'trago azul', 'frutal', 'clerico', 'cerveza', 'cerveza porron',
        'cerveza tirada', 'cerveza rubia', 'cerveza roja', 'cerveza negra', 'ipa', 'quilmes',
        'quilmes lata', 'brahma', 'andes', 'patagonia', 'imperial', 'imperial golden', 'stella', 'heineken', 'heineken lata', 'corona',
        'budweiser', 'amstel', 'miller', 'warsteiner', 'isenbeck', 'smirnoff', 'absolut', 'gordons',
        'bombay', 'johnnie walker', 'jack daniels', 'chivas', 'bacardi', 'havana club', 'jagermeister',
        'malibu', 'cinzano', 'vino', 'vino blanco', 'champan', 'agua', 'agua con gas', 'villavicencio',
        'gaseosa', 'coca', 'sprite', 'fanta', 'pepsi', 'speed', 'red bull', 'monster', 'jugo',
        'limonada', 'cafe',
      ];
      final tomadas = {for (final n in nombres) FotoDeLaBarra.para(n)};
      expect(tomadas, containsAll(FotoDeLaBarra.claves), reason: 'una foto que ningún nombre toma no se ve nunca');
      for (final n in nombres) {
        expect(FotoDeLaBarra.claves, contains(FotoDeLaBarra.para(n)), reason: n);
      }
    });
  });

  group('de dónde sale la foto de un producto', () {
    final ahora = DateTime.utc(2026, 11, 4);
    ProductoBarra producto(String nombre, {String? imagenUrl}) =>
        ProductoBarra.nuevo(nombre: nombre, imagenUrl: imagenUrl, ahora: ahora);

    test('sin nada cargado, la de su nombre, de adentro de la app', () {
      final i = imagenDelProducto(producto('Fernet con coca'));
      expect(i, isA<AssetImage>());
      expect((i! as AssetImage).assetName, 'assets/barra/fernet.jpg');
    });

    test('una de la biblioteca elegida a mano gana a la del nombre', () {
      final i = imagenDelProducto(producto('Fernet con coca', imagenUrl: 'biblioteca:champan'));
      expect((i! as AssetImage).assetName, 'assets/barra/champan.jpg');
    });

    test('una de la biblioteca que no existe: la del nombre', () {
      final i = imagenDelProducto(producto('Fernet con coca', imagenUrl: 'biblioteca:no_existe'));
      expect((i! as AssetImage).assetName, 'assets/barra/fernet.jpg');
    });

    test('una foto propia del jefe gana a todas, y en la PC se guarda en el equipo', () {
      final i = imagenDelProducto(producto('Fernet con coca', imagenUrl: 'https://x.supabase.co/barra/f.jpg'));
      expect(kIsWeb, isFalse);
      expect(i, isA<FotoGuardada>(), reason: 'nunca NetworkImage en la PC: sin internet no se vería');
      expect((i! as FotoGuardada).fotos, same(fotosPropiasDeLaBarra));
    });

    test('un nombre sin foto conocida: ninguna', () {
      expect(imagenDelProducto(producto('Combo egresados')), isNull);
    });
  });

  test('cada foto de la biblioteca está en la app, y tiene su renglón en los créditos', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- ${FotoDeLaBarra.carpeta}/'), reason: 'la carpeta tiene que ir en los assets');
    final creditos = File('docs/FOTOS_DE_LA_BARRA.md').readAsStringSync();
    for (final c in FotoDeLaBarra.claves) {
      final f = File(FotoDeLaBarra.ruta(c));
      expect(f.existsSync(), isTrue, reason: 'falta ${f.path}');
      expect(f.lengthSync(), lessThan(120 * 1024), reason: '${f.path}: achicarla');
      expect(creditos, contains('`$c.jpg`'), reason: 'falta de dónde salió $c.jpg y su licencia');
    }
    // Y ninguna foto suelta en la carpeta que la app no use: pesa y no se ve nunca.
    final enLaCarpeta = Directory(FotoDeLaBarra.carpeta)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.jpg'))
        .map((n) => n.substring(0, n.length - 4))
        .toSet();
    expect(enLaCarpeta, FotoDeLaBarra.claves.toSet());
  });
}
