// La ventana del tótem no escribe el archivo de preferencias (revisión del
// 13-nov). Cada ventana es otro proceso con su copia de las preferencias; en
// Windows, cada escritura reescribe el archivo entero con esa copia. La del
// tótem lo volvía a como estaba cuando se abrió, y se llevaba puesto lo que la
// principal había guardado después: entre otras cosas, la sesión.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/preferencias_de_la_ventana.dart';
import 'package:arguello_events/core/services/totem_config_cache.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/services/puente_ficha.dart';
import 'package:arguello_events/features/totem/totem_orientation.dart';
import 'package:arguello_events/models/totem_config.dart';

const _evento = '11111111-2222-4333-8444-555555555555';
const _sesion = 'sb-proyecto-auth-token';
const _claveConfig = 'totem_config_v1_$_evento';
const _claveGiro = 'totem_orient_v1_$_evento';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PreferenciasDeLaVentana.reiniciar();
    // Lo que la principal guardó después de que se abrió el tótem.
    SharedPreferences.setMockInitialValues({_sesion: 'la-de-las-23hs'});
  });

  tearDown(PreferenciasDeLaVentana.reiniciar);

  Future<SharedPreferences> archivo() => SharedPreferences.getInstance();

  group('en la ventana principal', () {
    test('guardar escribe el archivo, y se lee de ahí', () async {
      await PreferenciasDeLaVentana.guardar(_claveGiro, 'vertical');
      expect((await archivo()).getString(_claveGiro), 'vertical');
      expect(await PreferenciasDeLaVentana.leer(_claveGiro), 'vertical');

      await PreferenciasDeLaVentana.guardar(_claveGiro, null);
      expect((await archivo()).containsKey(_claveGiro), isFalse);
      expect(PreferenciasDeLaVentana.porElPuente, isFalse);
    });
  });

  group('en la ventana del tótem', () {
    late List<(String, String?)> pedidos;

    setUp(() {
      pedidos = [];
      PreferenciasDeLaVentana.usarElPuente(
        (clave, valor) async => pedidos.add((clave, valor)),
      );
    });

    test('guardar no toca el archivo: se lo pide a la principal', () async {
      final cfg = TotemConfig.defaults(_evento).copyWith(titulo: 'PROMOCIÓN 2026');
      await TotemConfigCache.save(cfg);
      await TotemOrientationStore.save(_evento, TotemOrientation.vertical);

      final prefs = await archivo();
      expect(prefs.getKeys(), {_sesion}, reason: 'esta ventana no escribió nada');
      expect(prefs.getString(_sesion), 'la-de-las-23hs',
          reason: 'la sesión de la principal sigue como estaba');
      expect([for (final p in pedidos) p.$1], [_claveConfig, _claveGiro]);
      expect(pedidos.last.$2, 'vertical');
    });

    test('lo que guardó lo vuelve a leer, aunque su copia del archivo no lo tenga',
        () async {
      await TotemConfigCache.save(
        TotemConfig.defaults(_evento).copyWith(titulo: 'PROMOCIÓN 2026'),
      );
      await TotemOrientationStore.save(_evento, TotemOrientation.horizontal);

      expect((await TotemConfigCache.load(_evento))?.titulo, 'PROMOCIÓN 2026');
      expect(await TotemOrientationStore.load(_evento),
          TotemOrientation.horizontal);
    });

    test('lo que no guardó ella lo lee de su copia', () async {
      SharedPreferences.setMockInitialValues({_claveGiro: 'vertical'});
      expect(await TotemOrientationStore.load(_evento), TotemOrientation.vertical);
    });

    test('sacar una preferencia tampoco escribe, y deja de leerse', () async {
      SharedPreferences.setMockInitialValues({
        _claveConfig: jsonEncode(TotemConfig.defaults(_evento).toJson()),
      });
      await TotemConfigCache.clear(_evento);
      expect((await archivo()).containsKey(_claveConfig), isTrue,
          reason: 'la saca la principal, no esta ventana');
      expect(await TotemConfigCache.load(_evento), isNull);
      expect(pedidos.single, (_claveConfig, null));
    });

    // Revisión final de la 6.9.0: la config de la fiesta de la noche la guardó
    // la principal después de que se abrió la tele; sin internet, la tele la
    // buscaba en su copia vieja y salía con la de fábrica.
    test('lo de la tele se lo pregunta a la principal antes que a su copia vieja',
        () async {
      SharedPreferences.setMockInitialValues({_claveGiro: 'vertical', _sesion: 'la-de-las-23hs'});
      final preguntas = <String>[];
      PreferenciasDeLaVentana.usarElPuente(
        (clave, valor) async => pedidos.add((clave, valor)),
        leer: (clave) async {
          preguntas.add(clave);
          return (contesto: true, valor: clave == _claveGiro ? 'horizontal' : null);
        },
      );
      expect(await TotemOrientationStore.load(_evento), TotemOrientation.horizontal);
      expect(await TotemConfigCache.load(_evento), isNull,
          reason: 'la principal contestó que no tiene nada');
      expect(preguntas, [_claveGiro, _claveConfig]);
      expect(await PreferenciasDeLaVentana.leer(_sesion), 'la-de-las-23hs',
          reason: 'lo que no es de la tele no se pregunta');
      expect(preguntas, hasLength(2));
    });

    test('si la principal no contesta la pregunta, lee su copia', () async {
      SharedPreferences.setMockInitialValues({_claveGiro: 'vertical'});
      PreferenciasDeLaVentana.usarElPuente(
        (clave, valor) async => pedidos.add((clave, valor)),
        leer: (_) async => (contesto: false, valor: null),
      );
      expect(await TotemOrientationStore.load(_evento), TotemOrientation.vertical);
      PreferenciasDeLaVentana.usarElPuente(
        (clave, valor) async => pedidos.add((clave, valor)),
        leer: (_) async => throw Exception('la principal no está lista'),
      );
      expect(await TotemOrientationStore.load(_evento), TotemOrientation.vertical);
    });

    test('si la principal no contesta, no escribe igual: se lo acuerda ella',
        () async {
      PreferenciasDeLaVentana.usarElPuente(
        (_, _) async => throw Exception('la ventana principal no contestó'),
      );
      await TotemOrientationStore.save(_evento, TotemOrientation.vertical);
      expect((await archivo()).getKeys(), {_sesion});
      expect(await TotemOrientationStore.load(_evento), TotemOrientation.vertical);
    });
  });

  group('la principal guarda lo que le pide la del tótem', () {
    test('solo sus dos preferencias, con el id del evento', () async {
      expect(await PreferenciasDeLaVentana.guardarLoDelTotem(_claveGiro, 'vertical'), isTrue);
      expect(await PreferenciasDeLaVentana.guardarLoDelTotem(_claveConfig, '{}'), isTrue);
      final prefs = await archivo();
      expect(prefs.getString(_claveGiro), 'vertical');
      expect(prefs.getString(_claveConfig), '{}');
      expect(prefs.getString(_sesion), 'la-de-las-23hs');
    });

    test('ninguna otra clave: lo que llega por el puente es un dato', () async {
      for (final clave in <Object?>[
        _sesion,
        'central_puerta_codigo_v1_$_evento',
        'caja_device_id',
        'totem_orient_v1_',
        'totem_orient_v1_${_evento}x',
        'totem_config_v1_corto',
        null,
        7,
      ]) {
        expect(
          await PreferenciasDeLaVentana.guardarLoDelTotem(clave, 'x'),
          isFalse,
          reason: '$clave',
        );
      }
      final prefs = await archivo();
      expect(prefs.getKeys(), {_sesion});
      expect(prefs.getString(_sesion), 'la-de-las-23hs');
    });

    test('ni un valor que no sea texto o que sea enorme', () async {
      expect(await PreferenciasDeLaVentana.guardarLoDelTotem(_claveGiro, 7), isFalse);
      expect(
        await PreferenciasDeLaVentana.guardarLoDelTotem(
          _claveConfig,
          'x' * (PreferenciasDeLaVentana.largoMaximo + 1),
        ),
        isFalse,
      );
      expect((await archivo()).getKeys(), {_sesion});
    });

    test('con null la saca', () async {
      SharedPreferences.setMockInitialValues({_claveGiro: 'vertical', _sesion: 's'});
      expect(await PreferenciasDeLaVentana.guardarLoDelTotem(_claveGiro, null), isTrue);
      expect((await archivo()).getKeys(), {_sesion});
    });

    test('por el puente contesta lo que tiene de la tele, y nada más', () async {
      SharedPreferences.setMockInitialValues({_claveGiro: 'vertical', _sesion: 's'});
      Future<FichaTotem> armar(String id) async => FichaTotem.particular(id);
      Future<String?> pedir(Object? clave) => PuenteFichaTotem.responder(
            MethodCall(PuenteFichaTotem.metodoLeer, clave),
            armar,
          );
      expect(await pedir(_claveGiro), jsonEncode({'valor': 'vertical'}));
      expect(await pedir(_claveConfig), jsonEncode({'valor': null}));
      expect(await pedir(_sesion), isNull, reason: 'la sesión no sale por el puente');
      expect(await pedir(null), isNull);
    });

    test('por el puente: contesta "ok", y lo mal armado no guarda nada', () async {
      Future<FichaTotem> armar(String id) async => FichaTotem.particular(id);
      Future<String?> pedir(Object? argumentos) => PuenteFichaTotem.responder(
            MethodCall(PuenteFichaTotem.metodoGuardar, argumentos),
            armar,
          );

      expect(
        await pedir(jsonEncode({'clave': _claveGiro, 'valor': 'horizontal'})),
        'ok',
      );
      expect((await archivo()).getString(_claveGiro), 'horizontal');

      expect(await pedir(jsonEncode({'clave': _sesion, 'valor': 'robada'})), isNull);
      expect(await pedir('esto no es json'), isNull);
      expect(await pedir(jsonEncode(['una', 'lista'])), isNull);
      expect(await pedir(null), isNull);
      expect((await archivo()).getString(_sesion), 'la-de-las-23hs');
    });
  });

  group('nadie vuelve a escribir desde la ventana del tótem', () {
    String leer(String ruta) => File(ruta).readAsStringSync();

    test('la ventana del tótem arranca guardando por el puente', () {
      final main = leer('lib/main.dart').replaceAll('\r\n', '\n');
      final secundaria = main.substring(
        main.indexOf("args.firstOrNull == 'multi_window'"),
        main.indexOf('// Activar Path URL Strategy'),
      );
      final puente = secundaria.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        puente,
        contains('PreferenciasDeLaVentana.usarElPuente( PuenteFichaTotem.guardarPreferencia, '
            'leer: PuenteFichaTotem.leerPreferencia, )'),
        reason: 'guarda y lee por el puente',
      );
      expect(
        secundaria.indexOf('PreferenciasDeLaVentana.usarElPuente'),
        lessThan(secundaria.indexOf('runApp(')),
        reason: 'antes de que corra nada que guarde',
      );
    });

    test('lo que corre en esa ventana no usa SharedPreferences a mano', () {
      final archivos = [
        'lib/features/totem/totem_display.dart',
        'lib/features/totem/totem_orientation.dart',
        'lib/features/totem/providers/totem_config_provider.dart',
        'lib/core/services/totem_config_cache.dart',
        for (final f in Directory('lib/features/totem/estilos').listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart')) f.path,
      ];
      expect(archivos.length, greaterThan(8));
      for (final ruta in archivos) {
        // Un comentario puede nombrarlo; lo que no puede es usarlo.
        final codigo = leer(ruta)
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(codigo, isNot(contains('SharedPreferences')), reason: ruta);
      }
    });
  });
}
