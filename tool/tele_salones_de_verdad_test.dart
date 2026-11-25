// La tele es el tótem: **con los salones de los eventos masivos de verdad**
// (25-nov-2026). Por cada salón (41 a 151 mesas) y cada momento (la espera, el
// nombre en grande y acomodado en el cuadro, con la mesa del fondo encendida y
// el camino), dibuja el tótem como hoy y como en la tele (lo quieto en foto,
// el fondo a la mitad) y compara los dos, píxel por píxel.
//
//   python -I tool/copiar_base_solo_lectura.py build/copia_salones_tele.db
//   python -I tool/salones_de_verdad.py build/copia_salones_tele.db
//   flutter test tool/tele_salones_de_verdad_test.dart
//
// Deja en build/capturas_tele/ (o en --dart-define=salida=<carpeta>) una imagen
// por salón y momento con las dos lado a lado: HOY a la izquierda, EN LA TELE a
// la derecha. Sin `build/salones_prueba/salones.json`, no corre.
//
// La pantalla es la de una tele: 960 × 540 puntos a 2 píxeles por punto (1920 ×
// 1080), acostada, con el salón a pantalla completa.

// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/common/widgets/foto_de_lo_quieto.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'raiz_del_proyecto.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

/// La tele: 960 × 540 puntos, a 2 píxeles por punto.
const _tele = Size(960, 540);
const _pixeles = 2.0;

String get _carpeta => _salida.isNotEmpty ? _salida : carpetaEnBuild('capturas_tele').path;

Future<void> _cargarLetras() async {
  await cargarFuentesTotem();
  final iconos = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await iconos.load();
}

class _Salon {
  _Salon(this.nombre, this.armado, this.familias);
  final String nombre;
  final ArmadoSalon armado;
  final List<List<int>> familias;
}

List<_Salon> _leerSalones() {
  final f = File('${carpetaEnBuild('salones_prueba').path}${Platform.pathSeparator}salones.json');
  if (!f.existsSync()) return const [];
  final lista = (jsonDecode(f.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  return [
    for (final s in lista)
      _Salon(
        s['nombre'] as String,
        ArmadoSalon.fromJson(s['armado'] as Map<String, dynamic>),
        [
          for (final fam in s['familias'] as List) [for (final n in fam as List) n as int],
        ],
      ),
  ];
}

enum _Momento { espera, grande, acomodada }

/// Dibuja el tótem quieto en [momento] y devuelve sus píxeles (RGBA).
Future<(ui.Image, Uint8List)> _dibujar(
  WidgetTester tester, {
  required ArmadoSalon? salon,
  required _Momento momento,
  required ContenidoBienvenida llegada,
  required bool enLaTele,
  EstiloTotem estilo = EstiloTotem.neon,
  double? entrada,
  double? acomodo,
  double? camino,
}) async {
  final clave = GlobalKey();
  final cfg = TotemConfig.defaults('e0000000-0000-4000-8000-000000000001');
  await tester.pumpWidget(
    RepaintBoundary(
      key: clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: FuentesPlano.linea),
        home: EscenaTotem(
          // Cada escena se arma de cero: que no se lleve la foto de la otra.
          key: ValueKey('$enLaTele-$momento-$estilo-${salon == null}-$entrada-$acomodo-$camino'),
          estilo: estilo,
          cfg: cfg,
          plano: salon,
          quieta: true,
          llegada: momento == _Momento.espera ? null : llegada,
          faseFija: momento == _Momento.grande ? FaseLlegada.grande : FaseLlegada.acomodada,
          entradaFija: entrada,
          acomodoFijo: acomodo,
          caminoFijo: camino,
          progresoFijo: 0.35,
          enLaTele: enLaTele,
          escalaDelFondo: enLaTele ? 0.5 : 1,
        ),
      ),
    ),
  );
  await tester.pump();
  late ui.Image imagen;
  late Uint8List bytes;
  await tester.runAsync(() async {
    final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    imagen = await boundary.toImage(pixelRatio: _pixeles);
    bytes = (await imagen.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  });
  return (imagen, bytes);
}

/// Cuánto se parecen: lo que difiere cada píxel en promedio (de 0 a 255) y qué
/// parte de los píxeles difiere a la vista (más de 24 en algún color).
({double promedio, double aLaVista}) _comparar(Uint8List a, Uint8List b) {
  var suma = 0, distintos = 0;
  final n = a.length ~/ 4;
  for (var i = 0; i < a.length; i += 4) {
    var maximo = 0;
    for (var k = 0; k < 3; k++) {
      final d = (a[i + k] - b[i + k]).abs();
      suma += d;
      if (d > maximo) maximo = d;
    }
    if (maximo > 24) distintos++;
  }
  return (promedio: suma / (n * 3), aLaVista: distintos / n);
}

/// Dónde difieren a la vista: en rojo sobre la de hoy apagada.
Future<void> _guardarDiferencias(
  WidgetTester tester,
  Uint8List a,
  Uint8List b,
  int ancho,
  int alto,
  String archivo,
) async {
  final m = Uint8List(a.length);
  for (var i = 0; i < a.length; i += 4) {
    var maximo = 0;
    for (var k = 0; k < 3; k++) {
      final d = (a[i + k] - b[i + k]).abs();
      if (d > maximo) maximo = d;
    }
    if (maximo > 24) {
      m[i] = 255;
      m[i + 1] = 0;
      m[i + 2] = 0;
    } else {
      m[i] = a[i] ~/ 3;
      m[i + 1] = a[i + 1] ~/ 3;
      m[i + 2] = a[i + 2] ~/ 3;
    }
    m[i + 3] = 255;
  }
  await tester.runAsync(() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(m);
    final desc = ui.ImageDescriptor.raw(buffer,
        width: ancho, height: alto, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final img = (await codec.getNextFrame()).image;
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(_carpeta).createSync(recursive: true);
    File('$_carpeta${Platform.pathSeparator}$archivo').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Las dos lado a lado, con su rótulo, a la mitad (960 × 540 cada una).
Future<void> _guardarLadoALado(
  WidgetTester tester,
  ui.Image hoy,
  ui.Image tele,
  String archivo,
) async {
  await tester.runAsync(() async {
    const ancho = 960.0, alto = 540.0, hueco = 24.0, arriba = 44.0;
    final grabador = ui.PictureRecorder();
    final c = Canvas(grabador);
    c.drawRect(
      const Rect.fromLTWH(0, 0, ancho * 2 + hueco, alto + arriba),
      Paint()..color = const Color(0xFF0E0E10),
    );
    void rotulo(String t, double x) {
      final p = (ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: FuentesTotem.linea, fontSize: 24))
            ..pushStyle(ui.TextStyle(color: const Color(0xFFE8E6F0)))
            ..addText(t))
          .build()
        ..layout(const ui.ParagraphConstraints(width: ancho));
      c.drawParagraph(p, Offset(x + 8, 8));
    }

    rotulo('HOY', 0);
    rotulo('EN LA TELE', ancho + hueco);
    for (final (i, img) in [hoy, tele].indexed) {
      c.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(i * (ancho + hueco), arriba, ancho, alto),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    final junta = await grabador.endRecording().toImage((ancho * 2 + hueco).round(), (alto + arriba).round());
    final png = await junta.toByteData(format: ui.ImageByteFormat.png);
    Directory(_carpeta).createSync(recursive: true);
    File('$_carpeta${Platform.pathSeparator}$archivo').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final salones = _leerSalones();

  setUpAll(() async {
    await _cargarLetras();
    await FondoTotem.precargar();
  });

  if (salones.isEmpty) {
    test('sin los salones de verdad (tool/salones_de_verdad.py)', () {}, skip: true);
    return;
  }

  final resumen = <String>[];
  tearDownAll(() {
    print('\n${resumen.join('\n')}');
    print('── Las imágenes, en $_carpeta');
  });

  for (final (i, s) in salones.indexed) {
    testWidgets('${s.nombre}: se ve igual en la tele', (tester) async {
      tester.view.physicalSize = _tele * _pixeles;
      tester.view.devicePixelRatio = _pixeles;
      addTearDown(tester.view.reset);
      final llegada = _llegadaA(_masLejos(s));
      for (final momento in _Momento.values) {
        final fotosAntes = FotoDeLoQuieto.fotosSacadas;
        final (hoy, bytesHoy) = await _dibujar(
          tester,
          salon: s.armado,
          momento: momento,
          llegada: llegada,
          enLaTele: false,
        );
        if (momento == _Momento.espera) {
          resumen.add('${s.nombre}: la llegada va a la mesa ${llegada.mesa}, la más lejos del Ingreso');
        }
        expect(FotoDeLoQuieto.fotosSacadas, fotosAntes, reason: 'hoy no saca fotos');
        final (tele, bytesTele) = await _dibujar(
          tester,
          salon: s.armado,
          momento: momento,
          llegada: llegada,
          enLaTele: true,
        );
        expect(FotoDeLoQuieto.fotosSacadas, greaterThan(fotosAntes),
            reason: 'en la tele, el salón y las letras van en foto');
        final d = _comparar(bytesHoy, bytesTele);
        resumen.add('${s.nombre} · ${momento.name}: difiere ${d.promedio.toStringAsFixed(2)} '
            'de 255 en promedio; a la vista, ${(d.aLaVista * 100).toStringAsFixed(2)} % de los píxeles');
        await _guardarLadoALado(tester, hoy, tele, 'Salon_${i + 1}_${momento.name}.png');
        if (d.aLaVista > 0.001) {
          await _guardarDiferencias(tester, bytesHoy, bytesTele, hoy.width, hoy.height,
              'Salon_${i + 1}_${momento.name}_diferencias.png');
        }
        // El salón y las letras, iguales: lo único que cambia es el fondo a
        // la mitad, que en la espera y acomodada no se ve (lo tapa el salón) y
        // con el nombre en grande se ve apenas detrás.
        if (momento == _Momento.grande) {
          expect(d.promedio, lessThan(4), reason: 'el nombre en grande, sobre el salón apagado');
        } else {
          expect(d.promedio, lessThan(1), reason: 'el salón entero a la vista');
          expect(d.aLaVista, lessThan(0.002), reason: 'casi ningún píxel distinto a la vista');
        }
      }
    });
  }

  // La bienvenida, momento por momento, con el salón más grande y la mesa más
  // lejos del Ingreso: las letras a medio encender, el círculo de la mesa a
  // medio dibujar, el nombre en grande, el nombre achicándose mientras vuelve
  // el salón, y la flecha a mitad de camino.
  testWidgets('la bienvenida, momento por momento, se ve igual en la tele', (tester) async {
    tester.view.physicalSize = _tele * _pixeles;
    tester.view.devicePixelRatio = _pixeles;
    addTearDown(tester.view.reset);
    final s = salones.first;
    final llegada = _llegadaA(_masLejos(s));
    final momentos = <(String, _Momento, double?, double?, double?)>[
      ('1_letras_a_medio_encender', _Momento.grande, 0.5, null, null),
      ('2_circulo_a_medio_dibujar', _Momento.grande, 0.78, null, null),
      ('3_nombre_en_grande', _Momento.grande, null, null, null),
      ('4_se_achica_y_vuelve_el_salon', _Momento.acomodada, null, 0.5, 0.0),
      ('5_flecha_a_mitad_de_camino', _Momento.acomodada, null, null, 0.5),
      ('6_flecha_en_la_mesa', _Momento.acomodada, null, null, 1.0),
    ];
    for (final (nombre, momento, entrada, acomodo, camino) in momentos) {
      final (hoy, bytesHoy) = await _dibujar(tester,
          salon: s.armado, momento: momento, llegada: llegada, enLaTele: false,
          entrada: entrada, acomodo: acomodo, camino: camino);
      final (tele, bytesTele) = await _dibujar(tester,
          salon: s.armado, momento: momento, llegada: llegada, enLaTele: true,
          entrada: entrada, acomodo: acomodo, camino: camino);
      final d = _comparar(bytesHoy, bytesTele);
      resumen.add('Bienvenida $nombre: difiere ${d.promedio.toStringAsFixed(2)} de 255 en '
          'promedio; a la vista, ${(d.aLaVista * 100).toStringAsFixed(2)} % de los píxeles');
      await _guardarLadoALado(tester, hoy, tele, 'Bienvenida_$nombre.png');
      if (d.aLaVista > 0.001) {
        await _guardarDiferencias(tester, bytesHoy, bytesTele, hoy.width, hoy.height,
            'Bienvenida_${nombre}_diferencias.png');
      }
      expect(d.promedio, lessThan(1.5), reason: nombre);
    }
  });

  // Las otras apariencias: con el salón más grande y sin salón (un particular,
  // o antes del sorteo), donde el fondo animado se ve entero.
  for (final estilo in [EstiloTotem.neon, EstiloTotem.cristal, EstiloTotem.poster, EstiloTotem.gala]) {
    testWidgets('${estilo.name}: se ve igual en la tele, con y sin salón', (tester) async {
      tester.view.physicalSize = _tele * _pixeles;
      tester.view.devicePixelRatio = _pixeles;
      addTearDown(tester.view.reset);
      final s = salones.first;
      final llegada = _llegadaA(_masLejos(s));
      for (final conSalon in [true, false]) {
        for (final momento in [_Momento.espera, _Momento.acomodada]) {
          final (hoy, bytesHoy) = await _dibujar(tester,
              salon: conSalon ? s.armado : null, momento: momento, llegada: llegada,
              enLaTele: false, estilo: estilo);
          final (tele, bytesTele) = await _dibujar(tester,
              salon: conSalon ? s.armado : null, momento: momento, llegada: llegada,
              enLaTele: true, estilo: estilo);
          final d = _comparar(bytesHoy, bytesTele);
          final nombre = '${estilo.name} ${conSalon ? 'con salón' : 'sin salón'} · '
              '${momento == _Momento.espera ? 'espera' : 'llegada'}';
          resumen.add('$nombre: difiere ${d.promedio.toStringAsFixed(2)} de 255 en promedio; '
              'a la vista, ${(d.aLaVista * 100).toStringAsFixed(2)} % de los píxeles');
          final archivo = '${estilo.name}_${conSalon ? 'salon' : 'sin_salon'}_'
              '${momento == _Momento.espera ? 'espera' : 'llegada'}';
          await _guardarLadoALado(tester, hoy, tele, '$archivo.png');
          if (d.aLaVista > 0.001) {
            await _guardarDiferencias(
                tester, bytesHoy, bytesTele, hoy.width, hoy.height, '${archivo}_diferencias.png');
          }
          // Sin salón el fondo se ve entero y va a la mitad: es bruma y luz,
          // difiere poco. Lo que tiene que dar igual son las letras.
          expect(d.promedio, lessThan(conSalon ? 1 : 4), reason: nombre);
        }
      }
    });
  }
}

/// La mesa de [s] más lejos del Ingreso: el camino más largo.
int _masLejos(_Salon s) {
  final ingresos = s.armado.sectores.where((x) => x.tipo == TipoSector.ingreso);
  final todas = [for (final f in s.familias) ...f];
  if (ingresos.isEmpty) return todas.reduce((a, b) => a < b ? a : b);
  final i = ingresos.first.caja;
  double lejos(int n) {
    final m = s.armado.mesa(n);
    if (m == null) return -1;
    final dx = m.x - i.centroX, dy = m.y - i.centroY;
    return dx * dx + dy * dy;
  }

  return todas.reduce((a, b) => lejos(a) >= lejos(b) ? a : b);
}

ContenidoBienvenida _llegadaA(int mesa) => ContenidoBienvenida(
      saludo: '¡Bienvenidos!',
      nombres: const ['PÉREZ, JUAN MARTÍN'],
      conQuien: 'con GÓMEZ, ANA y PÉREZ, LUIS',
      mesa: '$mesa',
      musica: 'Tusa · Karol G',
    );
