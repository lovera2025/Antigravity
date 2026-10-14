// Arnés manual: dibuja piezas del tótem con datos inventados y guarda PNG para
// mirarlas sin levantar la app.
//
//   flutter test tool/totem_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
// - Totem_sin_internet.png: el aviso de la barra del operador, en la ventana
//   del tótem y en la web.
// - Totem_bienvenidas.png: la bienvenida en cuatro casos, lado a lado (son
//   momentos distintos de la noche, no opciones): la familia junta de un
//   masivo, un acompañante solo, un masivo sin sortear y un particular.
// - Totem_espera.png: la parte de arriba de la pantalla de espera, en un masivo
//   (sin QR) y en un particular (con QR).
// - Personalizar_musica.png: la casilla de la música en Personalizar.
//
// La tarjeta, la portada y la casilla son las de la app. El fondo es el negro
// del tótem con su resplandor, sin lo demás: la pantalla entera lee de la nube
// y no se puede montar en una prueba.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/widgets/aviso_sin_internet.dart';
import 'package:arguello_events/features/totem/widgets/portada_totem.dart';
import 'package:arguello_events/features/totem/widgets/tarjeta_bienvenida.dart';
import 'package:arguello_events/features/totem/widgets/totem_config_sheet.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import '../test/helpers/ficha_de_prueba.dart';
import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

/// Una pantalla vertical de tótem, achicada: 1080×1920 a la mitad.
const _pantalla = Size(540, 960);

final _carpeta = _salida.isNotEmpty
    ? _salida
    : Directory.systemTemp.createTempSync('totem_muestra').path;

Future<void> _cargarLetras() async {
  await cargarFuentesPlano();
  final iconos = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await iconos.load();
  // Outfit regular y negrita, con el nombre con que las pide `google_fonts`.
  // En la app las encuentra solas entre los archivos; acá hay que tenerlas
  // cargadas antes de dibujar, o el primer cuadro sale con la letra de prueba.
  for (final (nombre, archivo) in [
    ('Outfit_regular', 'Outfit-Regular.ttf'),
    ('Outfit_700', 'Outfit-Bold.ttf'),
  ]) {
    final f = FontLoader(nombre)
      ..addFont(rootBundle.load('assets/google_fonts/$archivo'));
    await f.load();
  }
}

Future<void> _guardar(
  WidgetTester tester,
  GlobalKey clave,
  String archivo,
) async {
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

/// Monta [hijo] del tamaño [tam], espera a que carguen las imágenes y lo
/// guarda.
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
        home: Scaffold(backgroundColor: const Color(0xFF050505), body: hijo),
      ),
    ),
  );
  // El logo de la empresa es una imagen: hay que dejar que se lea del disco.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await _guardar(tester, clave, archivo);
}

Widget _rotulo(String texto) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Text(
        texto,
        style: GoogleFonts.outfit(
          color: Colors.white70,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

/// Una pantalla de tótem con su rótulo arriba.
Widget _panel(String rotulo, Widget pantalla, {double alto = 960}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rotulo(rotulo),
        Container(
          width: _pantalla.width,
          height: alto,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: const Color(0xFF2A2A2A), width: 2),
          ),
          child: pantalla,
        ),
      ],
    );

/// Lo que se ve durante una bienvenida: el negro, el resplandor del color del
/// evento y la tarjeta.
Widget _bienvenida(ContenidoBienvenida c, TotemConfig cfg, {int enCamino = 0}) =>
    Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.1,
                colors: [
                  cfg.colorAcento.withValues(alpha: 0.42),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Center(
          child: TarjetaBienvenida(
            contenido: c,
            cfg: cfg,
            escala: _pantalla.width / 620,
            enCamino: enCamino,
          ),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin esto `google_fonts` intenta bajar la letra y la prueba se cuelga.
  // Outfit regular y negrita vienen con la app.
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(_cargarLetras);

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

  testWidgets('la bienvenida, en cuatro momentos', (tester) async {
    final t0 = DateTime(2026, 12, 12, 22);
    const masivo = TotemConfig(
      eventoId: eventoMasivo,
      titulo: 'PROMOCIÓN 2026',
      subtitulo: 'Escuela Normal',
    );
    const particular = TotemConfig(
      eventoId: eventoParticular,
      titulo: 'GÓMEZ · RÍOS',
      subtitulo: 'Nos casamos',
      colorAcento: Color(0xFFFF8FB1),
    );
    final ficha = fichaDePrueba();
    final sinSortear = fichaDePrueba(sorteado: false);
    ContenidoBienvenida armar(
      List<Invitado> personas,
      FichaTotem f,
      TotemConfig cfg,
    ) =>
        ContenidoBienvenida.armar(
          BienvenidaTotem(
            familia: personas.first.id,
            personas: personas,
            empezo: t0,
          ),
          ficha: f,
          cfg: cfg,
        );

    await _sacar(
      tester,
      Size(_pantalla.width * 4 + 24 * 5, _pantalla.height + 110),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _panel(
              'Masivo: la familia junta, con cola',
              _bienvenida(
                armar(
                  [filaDe('perez'), filaDe('perez', 1), filaDe('perez', 2)],
                  ficha,
                  masivo,
                ),
                masivo,
                enCamino: 2,
              ),
            ),
            const SizedBox(width: 24),
            _panel(
              'Masivo: un acompañante solo',
              _bienvenida(armar([filaDe('perez', 1)], ficha, masivo), masivo),
            ),
            const SizedBox(width: 24),
            _panel(
              'Masivo sin sortear',
              _bienvenida(
                armar(
                  [filaDe('acosta', 0, sinSortear), filaDe('acosta', 1, sinSortear)],
                  sinSortear,
                  masivo,
                ),
                masivo,
              ),
            ),
            const SizedBox(width: 24),
            _panel(
              'Particular',
              _bienvenida(
                armar(
                  [filaSuelta('i1', 'LÓPEZ, MARTA', mesa: '4')],
                  const FichaTotem.particular(eventoParticular),
                  particular,
                ),
                particular,
              ),
            ),
          ],
        ),
      ),
      'Totem_bienvenidas.png',
    );
  });

  testWidgets('la espera, con y sin QR', (tester) async {
    // En la pantalla vertical la portada ocupa el 62 % de arriba; debajo
    // sigue la lista "YA LLEGARON", que en esta sección no cambia.
    const alto = 595.0;
    const masivo = TotemConfig(
      eventoId: eventoMasivo,
      titulo: 'PROMOCIÓN 2026',
      subtitulo: 'Escuela Normal',
    );
    const particular = TotemConfig(
      eventoId: eventoParticular,
      titulo: 'GÓMEZ · RÍOS',
      subtitulo: 'Nos casamos',
      colorAcento: Color(0xFFFF8FB1),
    );
    Widget portada(TotemConfig cfg, String? qr) => PortadaTotem(
          cfg: cfg,
          qrUrl: qr,
          apaisado: false,
          escala: _pantalla.width / 620,
          pulso: const AlwaysStoppedAnimation(1),
        );
    await _sacar(
      tester,
      Size(_pantalla.width * 2 + 24 * 3, alto + 110),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _panel('Masivo: sin QR', portada(masivo, null), alto: alto),
            const SizedBox(width: 24),
            _panel(
              'Particular: con QR, como siempre',
              portada(
                particular,
                'https://arguello-events.vercel.app/lista?evento=$eventoParticular',
              ),
              alto: alto,
            ),
          ],
        ),
      ),
      'Totem_espera.png',
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
              Text(
                'PERSONALIZAR TÓTEM · en un evento masivo, en lugar de '
                '"Texto del QR"',
                style: GoogleFonts.outfit(
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
}
