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
      ('Vodka con naranja', 'vodka'),
      ('Campari con naranja', 'campari'),
      ('Aperol spritz', 'aperol'),
      ('Whisky', 'whisky'),
      ('Cuba libre', 'ron'),
      ('Margarita', 'tequila'),
      ('Mojito', 'trago_frutal'),
      ('Caipiroska de frutilla', 'trago_frutal'),
      ('Cerveza lata', 'cerveza_lata'),
      ('Cerveza', 'cerveza_lata'),
      ('Cerveza Quilmes porrón', 'cerveza_porron'),
      ('Cerveza tirada', 'cerveza_tirada'),
      ('Pinta de rubia', 'cerveza_tirada'),
      ('Vino tinto Malbec', 'vino_tinto'),
      ('Vino blanco', 'vino_blanco'),
      ('Champán Chandon Extra Brut', 'champan'),
      ('Champaña', 'champan'),
      ('Agua sin gas', 'agua'),
      ('Agua con gas', 'agua_con_gas'),
      ('Agua tónica', 'gaseosa'),
      ('Gaseosa', 'gaseosa'),
      ('Coca lata', 'gaseosa'),
      ('Sprite', 'gaseosa'),
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

    test('cada regla lleva a una foto de la biblioteca', () {
      for (final n in ['fernet', 'gin', 'vodka', 'campari', 'aperol', 'whisky', 'ron', 'tequila', 'mojito',
          'cerveza', 'cerveza tirada', 'cerveza porron', 'vino', 'vino blanco', 'champan', 'agua',
          'agua con gas', 'gaseosa', 'jugo', 'cafe']) {
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

  test('cada foto de la biblioteca está en la app', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- ${FotoDeLaBarra.carpeta}/'), reason: 'la carpeta tiene que ir en los assets');
    for (final c in FotoDeLaBarra.claves) {
      final f = File(FotoDeLaBarra.ruta(c));
      expect(f.existsSync(), isTrue, reason: 'falta ${f.path}');
      expect(f.lengthSync(), lessThan(120 * 1024), reason: '${f.path}: achicarla');
    }
  });
}
