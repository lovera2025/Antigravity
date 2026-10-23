// "Tu fondo" (`fondo_propio.dart`): la imagen del evento como fondo, con su
// animación (el shader `totem_tu_fondo.frag`) y, si el shader no anda, quieta;
// una story en una tele horizontal, entera al medio; y la carga de la imagen.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/estilos/fondo_propio.dart';
import 'package:arguello_events/features/totem/estilos/tu_fondo.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/fondo_de_prueba.dart';

const _ev = 'e0000000-0000-4000-8000-00000000000a';

RecetaDibujada _receta({
  String animacion = 'acercarse',
  List<String> efectos = const [],
  int oscurecer = 30,
}) =>
    RecetaDibujada.de(
      conTuFondo(
        const TotemConfig(eventoId: _ev),
        animacion: animacion,
        efectos: efectos,
        oscurecer: oscurecer,
      ),
    );

/// La imagen de prueba, decodificada, y su copia chica.
Future<(ui.Image, ui.Image)> _imagenes(
  WidgetTester tester, {
  int ancho = 90,
  int alto = 160,
}) async {
  late ui.Image imagen;
  late ui.Image chica;
  await tester.runAsync(() async {
    final png = await pngDePrueba(ancho: ancho, alto: alto);
    final codec = await ui.instantiateImageCodec(png);
    imagen = (await codec.getNextFrame()).image;
    chica = CargaDelFondo.achicar(imagen);
  });
  return (imagen, chica);
}

/// Monta [hijo] de [tam] y devuelve sus píxeles (RGBA).
Future<(Uint8List, Size)> _pixeles(
  WidgetTester tester,
  Widget hijo, {
  Size tam = const Size(270, 480),
}) async {
  final clave = GlobalKey();
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: clave, child: hijo));
  await tester.pump();
  late Uint8List datos;
  await tester.runAsync(() async {
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await boundary.toImage();
    datos = (await imagen.toByteData())!.buffer.asUint8List();
    imagen.dispose();
  });
  return (datos, tam);
}

/// La luz media (0 a 255) de la franja de [x0] a [x1] y de [y0] a [y1], en
/// partes de la pantalla.
double _luz(
  (Uint8List, Size) p, {
  double x0 = 0,
  double x1 = 1,
  double y0 = 0,
  double y1 = 1,
}) {
  final (datos, tam) = p;
  final w = tam.width.toInt(), h = tam.height.toInt();
  var suma = 0.0;
  var n = 0;
  for (var y = (y0 * h).floor(); y < (y1 * h).ceil() && y < h; y++) {
    for (var x = (x0 * w).floor(); x < (x1 * w).ceil() && x < w; x++) {
      final i = (y * w + x) * 4;
      suma += (datos[i] + datos[i + 1] + datos[i + 2]) / 3;
      n++;
    }
  }
  return n == 0 ? 0 : suma / n;
}

Widget _fondo(ui.Image imagen, ui.Image chica, RecetaDibujada receta) =>
    FondoPropio(
      imagen: imagen,
      chica: chica,
      receta: receta,
      tiempoFijo: 3,
    );

void main() {
  setUp(FondoPropio.olvidar);
  tearDown(FondoPropio.olvidar);

  testWidgets('el shader compila y dibuja la imagen, con cada animación y el '
      'glitch', (tester) async {
    await tester.runAsync(FondoPropio.precargar);
    expect(FondoPropio.tieneShader, isTrue);
    final (imagen, chica) = await _imagenes(tester);
    for (final a in AnimacionFondo.values) {
      for (final efectos in [const <String>[], const ['glitch']]) {
        final p = await _pixeles(
          tester,
          _fondo(imagen, chica, _receta(animacion: a.clave, efectos: efectos)),
        );
        expect(tester.takeException(), isNull, reason: '${a.nombre} $efectos');
        expect(_luz(p), greaterThan(40), reason: '${a.nombre} $efectos');
      }
    }
  });

  testWidgets('quieta y sin glitch no necesita el shader', (tester) async {
    expect(FondoPropio.necesitaShader(_receta(animacion: 'quieta')), isFalse);
    expect(
      FondoPropio.necesitaShader(_receta(animacion: 'quieta', efectos: ['glitch'])),
      isTrue,
    );
    expect(FondoPropio.necesitaShader(_receta(animacion: 'flotar')), isTrue);
  });

  testWidgets('si el shader no carga, la imagen quieta con el oscurecido',
      (tester) async {
    FondoPropio.cargar = (_) async => throw StateError('esta PC no puede');
    await tester.runAsync(FondoPropio.precargar);
    expect(FondoPropio.tieneShader, isFalse);
    final (imagen, chica) = await _imagenes(tester);
    final p = await _pixeles(tester, _fondo(imagen, chica, _receta()));
    expect(tester.takeException(), isNull);
    expect(_luz(p), greaterThan(40));
    // Es la misma que "Quieta".
    final quieta = await _pixeles(
      tester,
      _fondo(imagen, chica, _receta(animacion: 'quieta')),
    );
    expect((_luz(p) - _luz(quieta)).abs(), lessThan(1));
  });

  testWidgets('el oscurecido baja la luz, más arriba que en el medio',
      (tester) async {
    final (imagen, chica) = await _imagenes(tester);
    // Quietas: sin shader, el mismo dibujo que con el shader en el instante 0.
    final sin = await _pixeles(
      tester,
      _fondo(imagen, chica, _receta(animacion: 'quieta', oscurecer: 0)),
    );
    final con = await _pixeles(
      tester,
      _fondo(imagen, chica, _receta(animacion: 'quieta', oscurecer: 60)),
    );
    expect(_luz(con), lessThan(_luz(sin) * 0.8));
    final arriba = _luz(con, y1: 0.08) / _luz(sin, y1: 0.08);
    final medio = _luz(con, y0: 0.45, y1: 0.55) / _luz(sin, y0: 0.45, y1: 0.55);
    expect(arriba, lessThan(medio));
  });

  group('una story en una tele horizontal', () {
    test('se contiene solo si la forma es muy distinta', () async {
      final r = ui.PictureRecorder();
      ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 9, 16), Paint());
      final cuadro = r.endRecording();
      final story = cuadro.toImageSync(9, 16);
      expect(FondoPropio.contener(const Size(1920, 1080), story), isTrue);
      expect(FondoPropio.contener(const Size(1080, 1920), story), isFalse);
      expect(FondoPropio.contener(const Size(1000, 1920), story), isFalse);
      story.dispose();
      cuadro.dispose();
    });

    for (final conShader in [true, false]) {
      testWidgets(
          '${conShader ? 'con' : 'sin'} shader: entera al medio y los costados '
          'con la copia oscurecida', (tester) async {
        if (!conShader) {
          FondoPropio.cargar = (_) async => throw StateError('esta PC no puede');
        }
        await tester.runAsync(FondoPropio.precargar);
        expect(FondoPropio.tieneShader, conShader);
        final (imagen, chica) = await _imagenes(tester);
        final p = await _pixeles(
          tester,
          _fondo(
            imagen,
            chica,
            _receta(animacion: conShader ? 'acercarse' : 'quieta', oscurecer: 0),
          ),
          tam: const Size(480, 270),
        );
        expect(tester.takeException(), isNull);
        final medio = _luz(p, x0: 0.45, x1: 0.55);
        final costado = _luz(p, x0: 0.02, x1: 0.12);
        expect(costado, lessThan(medio * 0.75), reason: 'el costado, oscurecido');
        expect(costado, greaterThan(8), reason: 'con la imagen, no negro');
      });
    }
  });

  group('la carga de la imagen', () {
    testWidgets('carga la imagen y su copia chica; la suelta al cambiar',
        (tester) async {
      late Uint8List png;
      await tester.runAsync(() async => png = await pngDePrueba());
      final carga = CargaDelFondo();
      var avisos = 0;
      carga.addListener(() => avisos++);
      await tester.runAsync(() async {
        carga.cargar(MemoryImage(png));
        for (var i = 0; i < 50 && carga.imagen == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(carga.imagen, isNotNull);
      expect(carga.imagen!.width, 90);
      expect(carga.chica!.width, CargaDelFondo.anchoChica);
      expect(carga.fallo, isFalse);
      expect(avisos, greaterThan(0));

      carga.cargar(null);
      expect(carga.imagen, isNull);
      expect(carga.chica, isNull);
      carga.dispose();
    });

    testWidgets('si no se puede, avisa que falló', (tester) async {
      final carga = CargaDelFondo();
      await tester.runAsync(() async {
        carga.cargar(MemoryImage(Uint8List.fromList(const [1, 2, 3, 4])));
        for (var i = 0; i < 50 && !carga.fallo; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(carga.fallo, isTrue);
      expect(carga.imagen, isNull);
      carga.dispose();
    });
  });
}
