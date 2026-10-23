// Arnés manual: dibuja el tótem con datos inventados y guarda PNG para mirarlo
// sin levantar la app.
//
//   flutter test tool/totem_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen (en cada una, las cuatro apariencias lado a lado: Neón, Cristal,
// Póster y Gala):
// - Totem_espera_masivo.png: la espera de un evento masivo, sin QR.
// - Totem_llegada_familia.png: la familia que llega, con mesa, sillas, música y
//   "2 más en camino".
// - Totem_particular.png: la espera de un particular, con el QR, y una llegada.
// - Totem_horizontal.png: la llegada en una pantalla apaisada.
// - Totem_sin_internet.png: el aviso de la barra del operador.
// - Personalizar_musica.png: la casilla de la música en Personalizar.
// - Totem_llegada_plano.png y Totem_llegada_plano_horizontal.png: la familia
//   que llega con el salón abajo (o a la derecha) y su mesa encendida.
// - Personalizar_PC.png: Personalizar en la PC, recién abierta (un masivo).
// - Personalizar_llegada.png: con Gala elegida y "Ver una llegada".
// - Personalizar_celular.png y Personalizar_celular_tarjetas.png: en el
//   celular (un particular), recién abierta y deslizada hasta las tarjetas.
// - TuFondo_espera.png, TuFondo_llegada.png y TuFondo_horizontal.png: "Tu
//   fondo" con las imágenes de --dart-define=fondos=<carpeta> (JPG o PNG; sin
//   carpeta, una de mentira), cada una con la receta que le arma la lectura.
// - La foto del evento (6.2.1), en unos quince con una foto y un logo de
//   mentira: Foto_formas.png (las nueve formas), Foto_tamanos.png (del 50 al
//   300 %), Foto_en_cada_apariencia.png (el corazón), Foto_TuFondo.png (con
//   foto, el logo tal cual y sin foto) y Foto_Personalizar.png y
//   Foto_Personalizar_celular.png (la forma, el tamaño y las manijas).
//
// Las escenas, los fondos (los shaders de verdad) y las letras son los de la
// app. La pantalla entera del tótem lee la nube y no se monta en una prueba.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_propio.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/forma_foto.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/features/totem/estilos/tu_fondo.dart';
import 'package:arguello_events/features/totem/services/lectura_del_fondo.dart';
import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/widgets/aviso_sin_internet.dart';
import 'package:arguello_events/features/totem/widgets/totem_config_sheet.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import '../test/helpers/ficha_de_prueba.dart';
import '../test/helpers/fondo_de_prueba.dart';
import '../test/helpers/personalizar_en_memoria.dart';
import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _fondos = String.fromEnvironment('fondos', defaultValue: '');

/// Una pantalla vertical de tótem, achicada: 1080×1920 a la mitad.
const _vertical = Size(540, 960);
const _apaisada = Size(960, 540);
const _hueco = 24.0;

final _carpeta = _salida.isNotEmpty
    ? _salida
    : Directory.systemTemp.createTempSync('totem_muestra').path;

const _masivo = TotemConfig(
  eventoId: eventoMasivo,
  titulo: 'PROMOCIÓN 2026',
  subtitulo: 'Escuela Normal',
);
const _particular = TotemConfig(
  eventoId: eventoParticular,
  titulo: 'GÓMEZ · RÍOS',
  subtitulo: 'Nos casamos',
  colorAcento: Color(0xFFFF8FB1),
);

/// Unos quince, para las muestras de la foto (6.2.1).
const _quince = TotemConfig(
  eventoId: eventoParticular,
  titulo: 'MIS XV',
  subtitulo: 'Sofía',
  mensajeBienvenida: '¡Bienvenidos!',
  colorAcento: Color(0xFFFF8FB1),
);

/// Una foto de mentira: una silueta sobre un degradé rosa.
Future<Uint8List> _retrato(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final grabador = ui.PictureRecorder();
    final c = Canvas(grabador);
    const r = Rect.fromLTWH(0, 0, 400, 400);
    c.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topCenter,
          r.bottomCenter,
          const [Color(0xFFF7C6D5), Color(0xFFB9659B)],
        ),
    );
    final silueta = Paint()..color = const Color(0xFF5B2747);
    c.drawCircle(const Offset(200, 160), 80, silueta);
    c.drawPath(
      Path()
        ..moveTo(40, 400)
        ..cubicTo(56, 285, 128, 243, 200, 243)
        ..cubicTo(272, 243, 344, 285, 360, 400)
        ..close(),
      silueta,
    );
    final imagen = await grabador.endRecording().toImage(400, 400);
    bytes = (await imagen.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  });
  return bytes;
}

/// Un logo de mentira sin fondo, apaisado: una corona dorada.
Future<Uint8List> _logoSinFondo(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final grabador = ui.PictureRecorder();
    final c = Canvas(grabador);
    final oro = Paint()..color = const Color(0xFFEBC86A);
    c.drawPath(
      Path()
        ..moveTo(70, 90)
        ..lineTo(130, 140)
        ..lineTo(200, 60)
        ..lineTo(270, 140)
        ..lineTo(330, 90)
        ..lineTo(310, 200)
        ..lineTo(90, 200)
        ..close(),
      oro,
    );
    for (final p in const [Offset(70, 84), Offset(200, 52), Offset(330, 84)]) {
      c.drawCircle(p, 12, oro);
    }
    c.drawRRect(
      RRect.fromLTRBR(90, 212, 310, 232, const Radius.circular(6)),
      oro,
    );
    final imagen = await grabador.endRecording().toImage(400, 250);
    bytes = (await imagen.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  });
  return bytes;
}

/// Una story de mentira que ya trae el logo: violeta, con luces, y la corona
/// dorada arriba.
Future<Uint8List> _fondoConLogo(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final grabador = ui.PictureRecorder();
    final c = Canvas(grabador);
    const r = Rect.fromLTWH(0, 0, 540, 960);
    c.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topCenter,
          r.bottomCenter,
          const [Color(0xFF2A1240), Color(0xFF8E3B6E), Color(0xFFE9A06A)],
          const [0, 0.6, 1],
        ),
    );
    final azar = math.Random(7);
    for (var i = 0; i < 40; i++) {
      c.drawCircle(
        Offset(azar.nextDouble() * 540, azar.nextDouble() * 960),
        4 + azar.nextDouble() * 18,
        Paint()
          ..color = const Color(0xFFFFE3B0).withValues(alpha: 0.12 + azar.nextDouble() * 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    final oro = Paint()..color = const Color(0xFFEBC86A);
    c.save();
    c.translate(170, 70);
    c.scale(0.5);
    c.drawPath(
      Path()
        ..moveTo(70, 90)
        ..lineTo(130, 140)
        ..lineTo(200, 60)
        ..lineTo(270, 140)
        ..lineTo(330, 90)
        ..lineTo(310, 200)
        ..lineTo(90, 200)
        ..close(),
      oro,
    );
    for (final p in const [Offset(70, 84), Offset(200, 52), Offset(330, 84)]) {
      c.drawCircle(p, 12, oro);
    }
    c.restore();
    final imagen = await grabador.endRecording().toImage(540, 960);
    bytes = (await imagen.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  });
  return bytes;
}

/// Varias pantallas en filas de a [porFila], cada una con su nombre arriba.
Widget _grilla(Size pantalla, List<(String, Widget)> todas, {int porFila = 4}) {
  return Padding(
    padding: const EdgeInsets.all(_hueco),
    child: Wrap(
      spacing: _hueco,
      runSpacing: _hueco,
      children: [
        for (final (nombre, escena) in todas)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 38,
                child: Text(
                  nombre,
                  style: const TextStyle(
                    fontFamily: FuentesTotem.linea,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(width: pantalla.width, height: pantalla.height, child: escena),
            ],
          ),
      ],
    ),
  );
}

Future<void> _cargarLetras() async {
  await cargarFuentesTotem();
  final iconos = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await iconos.load();
  // Outfit negrita, con el nombre con que la pide `google_fonts` (el aviso sin
  // internet la usa así).
  final negrita = FontLoader('Outfit_700')
    ..addFont(rootBundle.load('assets/google_fonts/Outfit-Bold.ttf'));
  await negrita.load();
}

ContenidoBienvenida _llegada(
  List<Invitado> personas,
  FichaTotem ficha,
  TotemConfig cfg,
) =>
    ContenidoBienvenida.armar(
      BienvenidaTotem(
        familia: personas.first.id,
        personas: personas,
        empezo: DateTime(2026, 12, 12, 22),
      ),
      ficha: ficha,
      cfg: cfg,
    );

Future<void> _guardar(WidgetTester tester, GlobalKey clave, String archivo) async {
  await tester.runAsync(() async {
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await boundary.toImage(pixelRatio: 1);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_carpeta${Platform.pathSeparator}$archivo')
      ..writeAsBytesSync(datos!.buffer.asUint8List());
    print('── PNG en: ${f.path}');
  });
}

/// Monta [hijo] del tamaño [tam], espera las imágenes y lo guarda. Falla si
/// algo no entra.
Future<void> _sacar(
  WidgetTester tester,
  Size tam,
  Widget hijo,
  String archivo,
) async {
  final clave = GlobalKey();
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
        home: Scaffold(backgroundColor: const Color(0xFF0E0E10), body: hijo),
      ),
    ),
  );
  // El logo de la empresa es una imagen: hay que dejar que se lea del disco.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
  expect(tester.takeException(), isNull);
  await _guardar(tester, clave, archivo);
}

/// Las cuatro apariencias lado a lado, cada una con su nombre arriba.
Widget _cuatro(
  Size pantalla,
  Widget Function(EstiloTotem) escena, {
  int porFila = 4,
}) {
  final filas = <List<EstiloTotem>>[];
  const estilos = EstiloTotem.deLaCasa;
  for (var i = 0; i < estilos.length; i += porFila) {
    filas.add(estilos.sublist(i, math.min(i + porFila, estilos.length)));
  }
  return Padding(
    padding: const EdgeInsets.all(_hueco),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final fila in filas)
          Padding(
            padding: const EdgeInsets.only(bottom: _hueco),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in fila)
                  Padding(
                    padding: const EdgeInsets.only(right: _hueco),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            e.nombre,
                            style: const TextStyle(
                              fontFamily: FuentesTotem.linea,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: pantalla.width,
                          height: pantalla.height,
                          child: escena(e),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Lo que mide [_cuatro]: el margen, y cada pantalla con su nombre arriba (48)
/// y su hueco. [veces], si van varias [_cuatro] una debajo de la otra.
Size _lienzo(Size pantalla, {int columnas = 4, int filas = 1, int veces = 1}) =>
    Size(
      2 * _hueco + columnas * (pantalla.width + _hueco),
      veces * (2 * _hueco + filas * (pantalla.height + 48 + _hueco)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin esto `google_fonts` intenta bajar la letra y la prueba se cuelga.
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() async {
    await _cargarLetras();
    await FondoTotem.precargar();
  });

  final ficha = fichaDePrueba();
  final familia = _llegada(
    [filaDe('perez'), filaDe('perez', 1), filaDe('perez', 2)],
    ficha,
    _masivo,
  );

  testWidgets('la espera de un masivo', (tester) async {
    await _sacar(
      tester,
      _lienzo(_vertical),
      _cuatro(
        _vertical,
        (e) => EscenaTotem(estilo: e, cfg: _masivo, quieta: true, tiempoFijo: 6),
      ),
      'Totem_espera_masivo.png',
    );
  });

  testWidgets('la familia que llega', (tester) async {
    await _sacar(
      tester,
      _lienzo(_vertical),
      _cuatro(
        _vertical,
        (e) => EscenaTotem(
          estilo: e,
          cfg: _masivo,
          quieta: true,
          tiempoFijo: 6,
          llegada: familia,
          enCamino: 2,
        ),
      ),
      'Totem_llegada_familia.png',
    );
  });

  testWidgets('un particular: la espera con QR y una llegada', (tester) async {
    final lopez = _llegada(
      [filaSuelta('i1', 'LÓPEZ, MARTA', mesa: '4')],
      const FichaTotem.particular(eventoParticular),
      _particular,
    );
    await _sacar(
      tester,
      _lienzo(_vertical, veces: 2),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cuatro(
            _vertical,
            (e) => EscenaTotem(
              estilo: e,
              cfg: _particular,
              quieta: true,
              tiempoFijo: 9,
              qrUrl:
                  'https://arguello-events.vercel.app/lista?evento=$eventoParticular',
            ),
          ),
          _cuatro(
            _vertical,
            (e) => EscenaTotem(
              estilo: e,
              cfg: _particular,
              quieta: true,
              tiempoFijo: 9,
              llegada: lopez,
            ),
          ),
        ],
      ),
      'Totem_particular.png',
    );
  });

  testWidgets('la llegada en una pantalla apaisada', (tester) async {
    await _sacar(
      tester,
      _lienzo(_apaisada, columnas: 2, filas: 2),
      _cuatro(
        _apaisada,
        porFila: 2,
        (e) => EscenaTotem(
          estilo: e,
          cfg: _masivo,
          quieta: true,
          tiempoFijo: 6,
          llegada: familia,
          enCamino: 2,
        ),
      ),
      'Totem_horizontal.png',
    );
  });

  testWidgets('el aviso de que no hay internet', (tester) async {
    Widget renglon(String donde, bool conPuente) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 250,
                child: Text(
                  donde,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
              Flexible(child: AvisoSinInternet(conPuente: conPuente)),
            ],
          ),
        );
    await _sacar(
      tester,
      const Size(680, 176),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            renglon('En la ventana del tótem, en la PC', true),
            renglon('En el tótem de la web', false),
          ],
        ),
      ),
      'Totem_sin_internet.png',
    );
  });

  testWidgets('la casilla de la música en Personalizar', (tester) async {
    await _sacar(
      tester,
      const Size(620, 190),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: TotemConfig.acentoPorDefecto.withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'PERSONALIZAR TÓTEM · en un evento masivo, en lugar de '
                '"Texto del QR"',
                style: TextStyle(
                  fontFamily: FuentesTotem.linea,
                  color: TotemConfig.acentoPorDefecto,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              CasillaMusicaTotem(valor: true, onChanged: (_) {}),
            ],
          ),
        ),
      ),
      'Personalizar_musica.png',
    );
  });

  group('la llegada con el plano', () {
    final salon = ArmadosPredefinidos.normal2aPagina3();

    testWidgets('vertical', (tester) async {
      await _sacar(
        tester,
        _lienzo(_vertical),
        _cuatro(
          _vertical,
          (e) => EscenaTotem(
            estilo: e,
            cfg: _masivo,
            quieta: true,
            tiempoFijo: 6,
            llegada: familia,
            enCamino: 2,
            plano: salon,
          ),
        ),
        'Totem_llegada_plano.png',
      );
    });

    testWidgets('horizontal', (tester) async {
      await _sacar(
        tester,
        _lienzo(_apaisada, columnas: 2, filas: 2),
        _cuatro(
          _apaisada,
          (e) => EscenaTotem(
            estilo: e,
            cfg: _masivo,
            quieta: true,
            tiempoFijo: 6,
            llegada: familia,
            plano: salon,
          ),
          porFila: 2,
        ),
        'Totem_llegada_plano_horizontal.png',
      );
    });
  });

  group('Tu fondo', () {
    // Las imágenes, leídas como en Personalizar: cada una con su receta.
    Future<List<(String, Uint8List, TotemConfig)>> imagenes(
      WidgetTester tester,
      TotemConfig base,
    ) async {
      final lista = <(String, Uint8List, TotemConfig)>[];
      await tester.runAsync(() async {
        final archivos = _fondos.isEmpty
            ? <File>[]
            : (Directory(_fondos)
                .listSync()
                .whereType<File>()
                .where((f) => RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false)
                    .hasMatch(f.path))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path)));
        final todos = archivos.isEmpty
            ? [('De prueba', await pngDePrueba(ancho: 540, alto: 960))]
            : [
                for (final f in archivos)
                  (
                    f.uri.pathSegments.last.split('.').first,
                    f.readAsBytesSync(),
                  ),
              ];
        for (final (nombre, bytes) in todos) {
          final lectura = await LecturaDelFondo.deBytes(bytes);
          final cfg = conLaLectura(
            base.copyWith(
              estilo: 'tu_fondo',
              fondoUrl: 'https://nube.test/$nombre.jpg',
            ),
            lectura,
            automatico: true,
          );
          print('── $nombre: ${lectura.palabras.join(', ')} → '
              '${lectura.receta().resumen}');
          lista.add((nombre, bytes, cfg));
        }
      });
      return lista;
    }

    /// Lado a lado, cada una con su nombre y su receta arriba.
    Widget fila(
      Size pantalla,
      List<(String, Uint8List, TotemConfig)> todas,
      Widget Function(Uint8List, TotemConfig) escena,
    ) =>
        Padding(
          padding: const EdgeInsets.all(_hueco),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (nombre, bytes, cfg) in todas)
                Padding(
                  padding: const EdgeInsets.only(right: _hueco),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: pantalla.width,
                        height: 38,
                        child: Text(
                          '$nombre · ${AnimacionFondo.de(cfg.fondoAnimacion).nombre}'
                          ' · ${EfectoFondo.de(cfg.fondoEfectos).map((e) => e.nombre).join(', ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: FuentesTotem.linea,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: pantalla.width,
                        height: pantalla.height,
                        child: escena(bytes, cfg),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

    Future<void> sacarConFondos(
      WidgetTester tester,
      Size pantalla,
      List<(String, Uint8List, TotemConfig)> todas,
      Widget Function(Uint8List, TotemConfig) escena,
      String archivo,
    ) async {
      final clave = GlobalKey();
      final tam = Size(
        2 * _hueco + todas.length * (pantalla.width + _hueco),
        2 * _hueco + 48 + pantalla.height,
      );
      tester.view.physicalSize = tam;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: clave,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
            home: Scaffold(
              backgroundColor: const Color(0xFF0E0E10),
              body: fila(pantalla, todas, escena),
            ),
          ),
        ),
      );
      // Que se lean las imágenes de fondo y el logo.
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final listos = find
            .byType(FondoPropio)
            .evaluate()
            .every((e) => (e.widget as FondoPropio).imagen != null);
        if (listos && find.byType(FondoPropio).evaluate().length == todas.length) {
          break;
        }
      }
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _guardar(tester, clave, archivo);
    }

    setUpAll(FondoPropio.precargar);

    testWidgets('la espera, cada una con su receta', (tester) async {
      final todas = await imagenes(tester, _masivo);
      await sacarConFondos(
        tester,
        _vertical,
        todas,
        (bytes, cfg) => EscenaTotem(
          estilo: EstiloTotem.tuFondo,
          cfg: cfg,
          fondo: MemoryImage(bytes),
          quieta: true,
          tiempoFijo: 6,
        ),
        'TuFondo_espera.png',
      );
    });

    testWidgets('la familia que llega, con el plano', (tester) async {
      final todas = await imagenes(tester, _masivo);
      await sacarConFondos(
        tester,
        _vertical,
        todas,
        (bytes, cfg) => EscenaTotem(
          estilo: EstiloTotem.tuFondo,
          cfg: cfg,
          fondo: MemoryImage(bytes),
          quieta: true,
          tiempoFijo: 6,
          llegada: familia,
          enCamino: 2,
          plano: ArmadosPredefinidos.normal2aPagina3(),
        ),
        'TuFondo_llegada.png',
      );
    });

    testWidgets('Personalizar en la PC, con un fondo elegido', (tester) async {
      final todas = await imagenes(tester, _masivo);
      final (_, bytes, _) = todas.firstWhere(
        (t) => t.$1 == 'oro',
        orElse: () => todas.first,
      );
      // ignore: invalid_use_of_visible_for_testing_member
      PersonalizarTotem.elegirFondo = elegirFondoDePrueba(bytes);
      await _sacarPersonalizar(
        tester,
        const Size(1366, 900),
        guardada: _masivo,
        archivo: 'TuFondo_Personalizar.png',
        antes: (tester) async {
          final boton = find.byKey(const ValueKey('elegir_fondo'));
          await tester.ensureVisible(boton);
          await tester.tap(boton);
          for (var i = 0; i < 80; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
            final leida = find.text('Se lee:').evaluate().isNotEmpty;
            final fondos = find.byType(FondoPropio).evaluate();
            if (leida &&
                fondos.isNotEmpty &&
                fondos.every((e) => (e.widget as FondoPropio).imagen != null)) {
              break;
            }
          }
          await tester.ensureVisible(find.text('Automático · según la imagen'));
          await tester.pump();
        },
      );
    });

    testWidgets('en una tele horizontal', (tester) async {
      final todas = await imagenes(tester, _masivo);
      await sacarConFondos(
        tester,
        _apaisada,
        todas.take(2).toList(),
        (bytes, cfg) => EscenaTotem(
          estilo: EstiloTotem.tuFondo,
          cfg: cfg,
          fondo: MemoryImage(bytes),
          quieta: true,
          tiempoFijo: 6,
        ),
        'TuFondo_horizontal.png',
      );
    });

    // 6.2.1: con un fondo que ya trae el logo, la foto se saca; o va el logo
    // sin fondo, "tal cual" y grande.
    testWidgets('la foto: con foto, el logo tal cual y sin foto',
        (tester) async {
      // Una story que ya trae su logo arriba, leída como en Personalizar.
      final bytes = await _fondoConLogo(tester);
      late TotemConfig cfg;
      await tester.runAsync(() async {
        cfg = conLaLectura(
          _quince.copyWith(estilo: 'tu_fondo', fondoUrl: 'https://nube.test/story.png'),
          await LecturaDelFondo.deBytes(bytes),
          automatico: true,
        );
      });
      final retrato = await _retrato(tester);
      final logo = await _logoSinFondo(tester);
      final casos = [
        ('Con foto', bytes, cfg),
        ('Logo tal cual 220 %', bytes, cfg.copyWith(fotoForma: 'tal_cual', fotoTamano: 220)),
        ('Sin foto', bytes, cfg.copyWith(mostrarFoto: false)),
        (
          'Sin foto, frases abajo al 140 %',
          bytes,
          cfg.copyWith(mostrarFoto: false, textoTamano: 140, ubicacionY: 100),
        ),
      ];
      await sacarConFondos(
        tester,
        _vertical,
        casos,
        (bytes, cfg) => EscenaTotem(
          estilo: EstiloTotem.tuFondo,
          cfg: cfg,
          fondo: MemoryImage(bytes),
          foto: MemoryImage(cfg.fotoForma == 'tal_cual' ? logo : retrato),
          quieta: true,
          tiempoFijo: 6,
        ),
        'Foto_TuFondo.png',
      );
    });
  });

  group('La foto (6.2.1)', () {
    testWidgets('las nueve formas', (tester) async {
      final retrato = await _retrato(tester);
      final logo = await _logoSinFondo(tester);
      const chica = Size(320, 569);
      await _sacar(
        tester,
        Size(2 * _hueco + 5 * (chica.width + _hueco), 2 * (2 * _hueco + 48 + chica.height)),
        _grilla(chica, [
          for (final f in FormaFoto.values)
            (
              f.nombre,
              EscenaTotem(
                estilo: EstiloTotem.neon,
                cfg: _quince.copyWith(fotoForma: f.clave, fotoTamano: 160),
                foto: MemoryImage(f == FormaFoto.talCual ? logo : retrato),
                quieta: true,
                tiempoFijo: 6,
              ),
            ),
        ], porFila: 5),
        'Foto_formas.png',
      );
    });

    testWidgets('del más chico al más grande', (tester) async {
      final retrato = await _retrato(tester);
      final tamanos = [
        TotemConfig.fotoTamanoMinimo,
        100,
        200,
        TotemConfig.fotoTamanoMaximo,
      ];
      await _sacar(
        tester,
        _lienzo(_vertical),
        _grilla(_vertical, [
          for (final t in tamanos)
            (
              '$t %',
              EscenaTotem(
                estilo: EstiloTotem.gala,
                cfg: _quince.copyWith(fotoTamano: t),
                foto: MemoryImage(retrato),
                quieta: true,
                tiempoFijo: 6,
              ),
            ),
        ]),
        'Foto_tamanos.png',
      );
    });

    testWidgets('el corazón en cada apariencia', (tester) async {
      final retrato = await _retrato(tester);
      await _sacar(
        tester,
        _lienzo(_vertical),
        _cuatro(
          _vertical,
          (e) => EscenaTotem(
            estilo: e,
            cfg: _quince.copyWith(fotoForma: 'corazon', fotoTamano: 180),
            foto: MemoryImage(retrato),
            quieta: true,
            tiempoFijo: 6,
          ),
        ),
        'Foto_en_cada_apariencia.png',
      );
    });

    testWidgets('las frases: más grandes, más chicas y en otro lugar',
        (tester) async {
      final retrato = await _retrato(tester);
      await _sacar(
        tester,
        _lienzo(_vertical),
        _grilla(_vertical, [
          for (final (nombre, cfg) in [
            ('Como siempre', _quince),
            ('Foto 220 %, frases 80 %, arriba', _quince.copyWith(fotoTamano: 220, textoTamano: 80, ubicacionY: -100)),
            ('Frases 160 %, abajo', _quince.copyWith(textoTamano: 160, ubicacionY: 100)),
            ('Óvalo, abajo a la izquierda', _quince.copyWith(fotoForma: 'ovalo', ubicacionX: -100, ubicacionY: 100)),
          ])
            (
              nombre,
              EscenaTotem(
                estilo: EstiloTotem.gala,
                cfg: cfg,
                foto: MemoryImage(retrato),
                quieta: true,
                tiempoFijo: 6,
              ),
            ),
        ]),
        'Foto_frases.png',
      );
    });

    testWidgets('Personalizar en la PC: la forma, el tamaño y las manijas',
        (tester) async {
      await _sacarPersonalizar(
        tester,
        const Size(1366, 900),
        guardada: _quince,
        archivo: 'Foto_Personalizar.png',
        antes: (tester) async {
          await tester.ensureVisible(find.byKey(const ValueKey('forma_corazon')));
          await tester.tap(find.byKey(const ValueKey('forma_corazon')));
          await tester.pump();
          for (var i = 0; i < 6; i++) {
            await tester.tap(find.byKey(const ValueKey('agrandar_foto')));
            await tester.pump();
          }
          await tester.ensureVisible(find.text('FOTO DEL EVENTO'));
          // Que termine el cambio de borde de las formas (0,2 s).
          await tester.pump(const Duration(milliseconds: 400));
        },
      );
    });

    testWidgets('Personalizar en la PC: las frases y dónde van', (tester) async {
      await _sacarPersonalizar(
        tester,
        const Size(1366, 900),
        guardada: _quince.copyWith(fotoTamano: 140, textoTamano: 120, ubicacionY: 60),
        archivo: 'Foto_Personalizar_frases.png',
        antes: (tester) async {
          await tester.ensureVisible(find.byKey(const ValueKey('ubicacion_al_medio')));
          await tester.pump();
        },
      );
    });

    testWidgets('Personalizar en el celular, en la parte de la foto',
        (tester) async {
      await _sacarPersonalizar(
        tester,
        const Size(390, 844),
        guardada: _quince,
        archivo: 'Foto_Personalizar_celular.png',
        antes: (tester) async {
          await tester.ensureVisible(find.byKey(const ValueKey('tamano_foto')));
          await tester.pump();
        },
      );
    });
  });

  group('Personalizar con las cuatro apariencias', () {
    testWidgets('en la PC, recién abierta', (tester) async {
      await _sacarPersonalizar(
        tester,
        const Size(1366, 768),
        guardada: _masivo,
        archivo: 'Personalizar_PC.png',
      );
    });

    testWidgets('en la PC, con Gala elegida y una llegada', (tester) async {
      await _sacarPersonalizar(
        tester,
        const Size(1366, 768),
        guardada: _masivo,
        archivo: 'Personalizar_llegada.png',
        antes: (tester) async {
          await tester.tap(find.byKey(const ValueKey('apariencia_gala')));
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('ver_una_llegada')));
          await tester.pump();
          await tester.pump(EscenaTotem.entrada);
        },
      );
    });

    testWidgets('en el celular, un particular, recién abierta', (tester) async {
      await _sacarPersonalizar(
        tester,
        const Size(390, 844),
        guardada: _particular,
        archivo: 'Personalizar_celular.png',
      );
    });

    testWidgets('en el celular, deslizada hasta las tarjetas', (tester) async {
      await _sacarPersonalizar(
        tester,
        const Size(390, 844),
        guardada: _particular,
        archivo: 'Personalizar_celular_tarjetas.png',
        antes: (tester) async {
          await tester.drag(
            find.byType(SingleChildScrollView).last,
            const Offset(0, -420),
          );
          await tester.pump();
        },
      );
    });
  });
}

/// Abre Personalizar desde un botón, como la paleta de Recepción, hace [antes]
/// y la guarda. Falla si algo no entra.
Future<void> _sacarPersonalizar(
  WidgetTester tester,
  Size tam, {
  required TotemConfig guardada,
  required String archivo,
  Future<void> Function(WidgetTester)? antes,
}) async {
  final clave = GlobalKey();
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: clave,
      child: anfitrionPersonalizar(
        eventoId: guardada.eventoId,
        guardada: guardada,
        repo: RepoTotemEnMemoria(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text(abrirPersonalizar));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (antes != null) await antes(tester);
  // El logo de la empresa es una imagen: hay que dejar que se lea del disco.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump(const Duration(milliseconds: 16));
  expect(tester.takeException(), isNull);
  await _guardar(tester, clave, archivo);
}
