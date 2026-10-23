// La foto del evento guardada en la PC (`foto_guardada.dart`, sección 5 de la
// 6.0.0): sin internet el tótem sigue mostrándola. Sobre una carpeta temporal y
// con una conexión simulada: no se baja nada de verdad.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:arguello_events/features/totem/services/foto_guardada.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/personalizar_en_memoria.dart' show fotoDePrueba;

const _ev = 'eeeeeeee-0000-4000-8000-000000000005';
const _otro = 'eeeeeeee-0000-4000-8000-000000000006';
const _v1 = 'https://nube.test/totem/$_ev/portada.png?v=1';
const _v2 = 'https://nube.test/totem/$_ev/portada.png?v=2';

/// Una conexión que se puede cortar.
class _Red {
  var hayInternet = true;
  var pedidos = 0;
  int estado = 200;
  String tipo = 'image/png';
  Uint8List cuerpo = fotoDePrueba;
  Completer<void>? frenar;

  http.Client cliente() => MockClient((req) async {
        pedidos++;
        await frenar?.future;
        if (!hayInternet) {
          throw const SocketException('Sin internet');
        }
        return http.Response.bytes(cuerpo, estado,
            headers: {'content-type': tipo});
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory carpeta;
  late _Red red;
  late FotosDelTotem fotos;

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('fotos_totem');
    red = _Red();
    fotos = FotosDelTotem(
      carpeta: () async => carpeta,
      cliente: red.cliente,
    );
  });

  tearDown(() {
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  List<String> guardadas(String evento) {
    final dir = Directory('${carpeta.path}${Platform.pathSeparator}$evento');
    if (!dir.existsSync()) return const [];
    return [for (final f in dir.listSync()) f.path.split(Platform.pathSeparator).last];
  }

  test('con internet la baja y la guarda; después sale de la PC', () async {
    expect(await fotos.bytes(_v1, eventoId: _ev), fotoDePrueba);
    expect(red.pedidos, 1);
    expect(guardadas(_ev), hasLength(1));

    red.hayInternet = false;
    expect(await fotos.bytes(_v1, eventoId: _ev), fotoDePrueba);
    expect(red.pedidos, 1, reason: 'la guardada no se vuelve a pedir');
  });

  test('sin internet y sin ninguna guardada, nada: la escena muestra el logo',
      () async {
    red.hayInternet = false;
    expect(await fotos.bytes(_v1, eventoId: _ev), isNull);
    expect(guardadas(_ev), isEmpty);
  });

  test('se cambió la foto: baja la nueva y recién ahí borra la vieja', () async {
    await fotos.bytes(_v1, eventoId: _ev);
    final nueva = Uint8List.fromList([...fotoDePrueba]);
    red.cuerpo = nueva;
    expect(await fotos.bytes(_v2, eventoId: _ev), nueva);
    expect(guardadas(_ev), hasLength(1));
    expect(await fotos.estaGuardada(_v2, eventoId: _ev), isTrue);
    expect(await fotos.estaGuardada(_v1, eventoId: _ev), isFalse);
  });

  test('sin internet y sin la nueva, la última que se guardó', () async {
    await fotos.bytes(_v1, eventoId: _ev);
    red.hayInternet = false;
    expect(await fotos.bytes(_v2, eventoId: _ev), fotoDePrueba,
        reason: 'mejor la foto anterior que el logo');
    expect(await fotos.estaGuardada(_v1, eventoId: _ev), isTrue,
        reason: 'la vieja no se borra si la nueva no bajó');
  });

  test('un error del servidor, o algo que no es una foto, no se guarda',
      () async {
    red.estado = 404;
    expect(await fotos.bytes(_v1, eventoId: _ev), isNull);
    red
      ..estado = 200
      ..tipo = 'text/html';
    expect(await fotos.bytes(_v1, eventoId: _ev), isNull);
    expect(guardadas(_ev), isEmpty);
  });

  test('cada evento con la suya', () async {
    await fotos.bytes(_v1, eventoId: _ev);
    await fotos.bytes('https://nube.test/totem/$_otro/portada.png?v=1',
        eventoId: _otro);
    expect(guardadas(_ev), hasLength(1));
    expect(guardadas(_otro), hasLength(1));
  });

  test('dos pantallas que la piden a la vez la bajan una sola vez', () async {
    red.frenar = Completer<void>();
    final a = fotos.bytes(_v1, eventoId: _ev);
    final b = fotos.bytes(_v1, eventoId: _ev);
    await Future<void>.delayed(Duration.zero);
    red.frenar!.complete();
    expect(await a, fotoDePrueba);
    expect(await b, fotoDePrueba);
    expect(red.pedidos, 1);
  });

  test('guardar la deja en la PC y avisa si quedó', () async {
    expect(await fotos.estaGuardada(_v1, eventoId: _ev), isFalse);
    expect(await fotos.guardar(_v1, eventoId: _ev), isTrue);
    expect(await fotos.estaGuardada(_v1, eventoId: _ev), isTrue);
    expect(await fotos.guardar(_v1, eventoId: _ev), isTrue);
    expect(red.pedidos, 1, reason: 'si ya está, no se baja de nuevo');

    red.hayInternet = false;
    expect(await fotos.guardar(_v2, eventoId: _ev), isFalse);
  });

  test('si la carpeta no se puede usar, no rompe: nada', () async {
    final rota = FotosDelTotem(
      carpeta: () async => throw const FileSystemException('sin permiso'),
      cliente: red.cliente,
    );
    red.hayInternet = false;
    expect(await rota.bytes(_v1, eventoId: _ev), isNull);
    expect(await rota.estaGuardada(_v1, eventoId: _ev), isFalse);
  });

  // "Tu fondo": el fondo va en su propia carpeta. En la misma, guardar uno
  // borraba el otro (cada carpeta deja una sola imagen por evento), y sin
  // internet el círculo podía mostrar el fondo.
  group('la foto y el fondo conviven', () {
    const fondo1 = 'https://nube.test/totem/$_ev/fondo.jpg?v=1';
    const fondo2 = 'https://nube.test/totem/$_ev/fondo.jpg?v=2';
    final fondoBytes = Uint8List.fromList([...fotoDePrueba, 0]);
    late FotosDelTotem deFotos;
    late FotosDelTotem deFondos;

    setUp(() {
      // Las mismas dos carpetas que usa la app, dentro de una de documentos
      // de mentira.
      deFotos = FotosDelTotem(
        carpeta: FotosDelTotem.carpetaEnDocumentos(
          FotosDelTotem.carpetaFotos,
          documentos: () async => carpeta,
        ),
        cliente: red.cliente,
      );
      deFondos = FotosDelTotem(
        carpeta: FotosDelTotem.carpetaEnDocumentos(
          FotosDelTotem.carpetaFondos,
          documentos: () async => carpeta,
        ),
        cliente: red.cliente,
        que: 'El fondo del tótem',
      );
    });

    test('guardar uno no borra el otro, en ningún orden', () async {
      expect(await deFotos.guardar(_v1, eventoId: _ev), isTrue);
      red.cuerpo = fondoBytes;
      expect(await deFondos.guardar(fondo1, eventoId: _ev), isTrue);
      expect(await deFotos.estaGuardada(_v1, eventoId: _ev), isTrue);

      // Se cambian los dos: cada uno borra solo su versión vieja.
      red.cuerpo = fotoDePrueba;
      expect(await deFotos.guardar(_v2, eventoId: _ev), isTrue);
      red.cuerpo = fondoBytes;
      expect(await deFondos.guardar(fondo2, eventoId: _ev), isTrue);
      expect(await deFotos.estaGuardada(_v2, eventoId: _ev), isTrue);
      expect(await deFondos.estaGuardada(fondo2, eventoId: _ev), isTrue);
      expect(await deFotos.estaGuardada(_v1, eventoId: _ev), isFalse);
      expect(await deFondos.estaGuardada(fondo1, eventoId: _ev), isFalse);
    });

    test('sin internet, cada uno devuelve el suyo', () async {
      await deFotos.guardar(_v1, eventoId: _ev);
      red.cuerpo = fondoBytes;
      await deFondos.guardar(fondo1, eventoId: _ev);
      red.hayInternet = false;
      // Las direcciones nuevas no bajan: va la última guardada de cada uno.
      expect(await deFotos.bytes(_v2, eventoId: _ev), fotoDePrueba);
      expect(await deFondos.bytes(fondo2, eventoId: _ev), fondoBytes);
    });

    test('las carpetas de la app son distintas', () {
      expect(FotosDelTotem.carpetaFotos, isNot(FotosDelTotem.carpetaFondos));
      expect(identical(FotosDelTotem.enLaPc, FotosDelTotem.fondosEnLaPc),
          isFalse);
    });
  });

  group('lo que dibuja el tótem', () {
    test('sin foto en Personalizar, nada', () {
      expect(fotoDelEvento(TotemConfig.defaults(_ev)), isNull);
    });

    test('con foto, la guardada en la PC', () {
      final cfg = TotemConfig.defaults(_ev).copyWith(imagenUrl: _v1);
      expect(fotoDelEvento(cfg), FotoGuardada(_v1, eventoId: _ev));
    });

    test('el fondo, el guardado en la PC, en su carpeta', () {
      expect(fondoDelEvento(TotemConfig.defaults(_ev)), isNull);
      const url = 'https://nube.test/totem/$_ev/fondo.jpg?v=1';
      final cfg = TotemConfig.defaults(_ev).copyWith(fondoUrl: url);
      expect(
        fondoDelEvento(cfg),
        FotoGuardada(url, eventoId: _ev, fotos: FotosDelTotem.fondosEnLaPc),
      );
      expect(fondoDelEvento(cfg), isNot(FotoGuardada(url, eventoId: _ev)));
    });

    // Con `test` y no `testWidgets`: dibujar una imagen de verdad necesita el
    // reloj de verdad.
    test('se dibuja con lo guardado, sin internet', () async {
      await fotos.bytes(_v1, eventoId: _ev);
      red.hayInternet = false;
      final foto = FotoGuardada(_v1, eventoId: _ev, fotos: fotos);
      final completer = Completer<ImageInfo>();
      foto.resolve(ImageConfiguration.empty).addListener(
            ImageStreamListener(
              (info, _) => completer.complete(info),
              onError: (e, _) => completer.completeError(e),
            ),
          );
      final info = await completer.future.timeout(const Duration(seconds: 10));
      expect(info.image.width, 1);
    });

    test('sin nada guardado ni internet, avisa el error (va el logo)',
        () async {
      red.hayInternet = false;
      final foto = FotoGuardada(_v2, eventoId: _otro, fotos: fotos);
      final error = Completer<Object>();
      foto.resolve(ImageConfiguration.empty).addListener(
            ImageStreamListener(
              (_, _) {},
              onError: (e, _) => error.complete(e),
            ),
          );
      expect(await error.future.timeout(const Duration(seconds: 10)),
          isA<StateError>());
    });
  });
}
