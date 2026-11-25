import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/common/widgets/foto_de_lo_quieto.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/tele/calidad_de_la_tele.dart';
import 'package:arguello_events/features/tele/fluidez.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/models/totem_config.dart';

/// La tele es el tótem, fluido (25-nov-2026): lo quieto en foto, el fondo en
/// chico y quieto mientras el salón lo tapa. Apagado, todo como siempre. Que
/// se vea igual lo prueba `tool/tele_salones_de_verdad_test.dart` con los
/// salones de verdad, píxel por píxel.

final _cfg = TotemConfig.defaults('e0000000-0000-4000-8000-000000000001');

ArmadoSalon _salon() => ArmarAMedida.acomodar(
      ArmarAMedida.vacio(const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8)),
      cantidad: 101,
    ).armado;

const _llegada = ContenidoBienvenida(
  saludo: '¡Bienvenidos!',
  nombres: ['PÉREZ, JUAN MARTÍN'],
  conQuien: 'con GÓMEZ, ANA',
  mesa: '37',
);

Future<void> _montar(
  WidgetTester tester, {
  required bool enLaTele,
  EstiloTotem estilo = EstiloTotem.neon,
  ArmadoSalon? plano,
  ContenidoBienvenida? llegada,
  bool quieta = false,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final ahora = DateTime.now();
  await tester.pumpWidget(MaterialApp(
    home: EscenaTotem(
      estilo: estilo,
      cfg: _cfg,
      plano: plano,
      llegada: llegada,
      claveLlegada: llegada,
      empezo: llegada == null ? null : ahora,
      fin: llegada == null ? null : ahora.add(const Duration(seconds: 20)),
      quieta: quieta,
      faseFija: FaseLlegada.grande,
      enLaTele: enLaTele,
      escalaDelFondo: enLaTele ? 0.5 : 1,
    ),
  ));
}

Future<void> _andar(WidgetTester tester, Duration cuanto) async {
  final hasta = cuanto.inMilliseconds ~/ 16;
  for (var i = 0; i < hasta; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await FondoTotem.precargar();
  });
  setUp(() {
    FotoDeLoQuieto.fotosSacadas = 0;
    FotoDeLoQuieto.dibujosEnVivo = 0;
  });

  testWidgets('apagado (la PC, Recepción): ninguna foto y el fondo entero', (tester) async {
    await _montar(tester, enLaTele: false, plano: _salon());
    await _andar(tester, const Duration(milliseconds: 500));
    expect(find.byType(FotoDeLoQuieto), findsNothing);
    expect(FotoDeLoQuieto.fotosSacadas, 0);
    final fondo = tester.widget<FondoTotem>(find.byType(FondoTotem));
    expect(fondo.escala, 1);
    expect(fondo.tapado, isFalse);
  });

  testWidgets('en la tele: el salón y la espera en foto, y no una por imagen', (tester) async {
    await _montar(tester, enLaTele: true, plano: _salon());
    // Las primeras: el salón, la espera (con la letra floja de Neón prendida
    // y apagada) y lo que haya. Una vuelta entera del parpadeo: 4 s.
    await _andar(tester, const Duration(seconds: 5));
    final alPrincipio = FotoDeLoQuieto.fotosSacadas;
    expect(alPrincipio, greaterThan(0));
    expect(alPrincipio, lessThan(12));
    final enVivoAlPrincipio = FotoDeLoQuieto.dibujosEnVivo;
    // Otros 8 s, unas 500 imágenes: ninguna foto más, y nada dibujado en vivo
    // (el plano se volvía a acomodar en cada imagen y su foto no servía).
    await _andar(tester, const Duration(seconds: 8));
    expect(FotoDeLoQuieto.fotosSacadas, alPrincipio);
    expect(FotoDeLoQuieto.dibujosEnVivo - enVivoAlPrincipio, lessThan(5));
  });

  testWidgets('en la tele, con el salón a pantalla completa el fondo se queda quieto; '
      'con el nombre en grande, se mueve', (tester) async {
    await _montar(tester, enLaTele: true, plano: _salon());
    await tester.pump(const Duration(milliseconds: 16));
    final enLaEspera = tester.widget<FondoTotem>(find.byType(FondoTotem));
    expect(enLaEspera.tapado, isTrue);
    expect(enLaEspera.escala, 0.5);

    await _montar(tester, enLaTele: true, plano: _salon(), llegada: _llegada);
    await _andar(tester, const Duration(milliseconds: 600));
    expect(tester.widget<FondoTotem>(find.byType(FondoTotem)).tapado, isFalse);
  });

  testWidgets('en la tele, la llegada entera: pocas fotos, nunca una por imagen', (tester) async {
    await _montar(tester, enLaTele: true, plano: _salon(), llegada: _llegada);
    // La entrada (1,35 s), el nombre en grande y el acomodo con el camino.
    await _andar(tester, const Duration(seconds: 12));
    final enLaLlegada = FotoDeLoQuieto.fotosSacadas;
    // 12 s son unas 750 imágenes.
    expect(enLaLlegada, lessThan(40));
    final enVivo = FotoDeLoQuieto.dibujosEnVivo;
    await _andar(tester, const Duration(seconds: 4));
    expect(FotoDeLoQuieto.fotosSacadas - enLaLlegada, lessThanOrEqualTo(1),
        reason: 'acomodada y con el camino dibujado, ya está todo en foto');
    expect(FotoDeLoQuieto.dibujosEnVivo - enVivo, lessThan(5),
        reason: 'y nada se dibuja en vivo');
  });

  testWidgets('Cristal en la tele: el vidrio sin desenfocar lo de atrás', (tester) async {
    await _montar(tester, enLaTele: false, estilo: EstiloTotem.cristal, quieta: true);
    expect(find.byType(BackdropFilter), findsWidgets);
    await _montar(tester, enLaTele: true, estilo: EstiloTotem.cristal, quieta: true);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('las cinco apariencias se dibujan en la tele sin errores', (tester) async {
    for (final e in EstiloTotem.deLaCasa) {
      await _montar(tester, enLaTele: true, estilo: e, plano: _salon(), llegada: _llegada);
      await _andar(tester, const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: e.name);
    }
  });

  group('la tele se ajusta sola, callada', () {
    MedidaDeFluidez medida(double fps) => MedidaDeFluidez(
          porSegundo: fps,
          msArmado: 3,
          msDibujo: 1000 / fps,
          imagenes: 200,
        );

    test('arranca con el fondo a la mitad; si anda suave, no cambia', () {
      final a = AjusteDeLaTele();
      expect(a.fondo, FondoDeLaTele.mitad);
      for (var i = 0; i < 10; i++) {
        expect(a.mirar(medida(58), hz: 60), isFalse);
      }
      expect(a.fondo, FondoDeLaTele.mitad);
    });

    test('si la placa no llega, baja de a un escalón, con tres medidas malas seguidas, '
        'y se queda si mejoró', () {
      final a = AjusteDeLaTele();
      expect(a.mirar(medida(30), hz: 60), isFalse, reason: 'una puede ser un tirón');
      expect(a.mirar(medida(30), hz: 60), isFalse, reason: 'dos, también');
      expect(a.mirar(medida(30), hz: 60), isTrue);
      expect(a.fondo, FondoDeLaTele.tercio);
      // Mejoró (de 30 a 38): se queda; pero sigue sin llegar.
      expect(a.mirar(medida(38), hz: 60), isFalse);
      expect(a.mirar(medida(38), hz: 60), isFalse);
      expect(a.mirar(medida(38), hz: 60), isTrue);
      expect(a.fondo, FondoDeLaTele.quieto);
      expect(a.mirar(medida(47), hz: 60), isFalse);
      expect(a.fondo, FondoDeLaTele.quieto);
      // Más abajo no hay: el salón y las letras no se tocan nunca.
      for (var i = 0; i < 6; i++) {
        expect(a.mirar(medida(47), hz: 60), isFalse);
      }
      expect(a.fondo, FondoDeLaTele.quieto);
    });

    test('si bajar no ayudó, vuelve a como estaba y no prueba más (el emulador)', () {
      final a = AjusteDeLaTele();
      for (var i = 0; i < 2; i++) {
        a.mirar(medida(44), hz: 60);
      }
      expect(a.mirar(medida(44), hz: 60), isTrue);
      expect(a.fondo, FondoDeLaTele.tercio);
      // Igual que antes: no era el fondo.
      expect(a.mirar(medida(44), hz: 60), isTrue);
      expect(a.fondo, FondoDeLaTele.mitad);
      for (var i = 0; i < 9; i++) {
        expect(a.mirar(medida(44), hz: 60), isFalse);
      }
      expect(a.fondo, FondoDeLaTele.mitad);
    });

    test('si salen pocas imágenes pero la placa dibuja rápido, no baja: no ayudaría', () {
      // Lo que se vio en el emulador: 50 por segundo con 11 ms de dibujo.
      final a = AjusteDeLaTele();
      const rapida = MedidaDeFluidez(porSegundo: 45, msArmado: 1, msDibujo: 11, imagenes: 200);
      for (var i = 0; i < 6; i++) {
        expect(a.mirar(rapida, hz: 60), isFalse);
      }
      expect(a.fondo, FondoDeLaTele.mitad);
    });

    test('una buena en el medio vuelve a empezar la cuenta', () {
      final a = AjusteDeLaTele();
      a.mirar(medida(30), hz: 60);
      a.mirar(medida(30), hz: 60);
      a.mirar(medida(59), hz: 60);
      expect(a.mirar(medida(30), hz: 60), isFalse);
      expect(a.mirar(medida(30), hz: 60), isFalse);
      expect(a.fondo, FondoDeLaTele.mitad);
    });

    test('una pantalla de 50 Hz que saca 49 anda suave', () {
      final a = AjusteDeLaTele();
      for (var i = 0; i < 4; i++) {
        expect(a.mirar(medida(49), hz: 50), isFalse);
      }
      expect(a.fondo, FondoDeLaTele.mitad);
    });

    test('con pocas imágenes medidas no decide nada', () {
      final a = AjusteDeLaTele();
      const poca = MedidaDeFluidez(porSegundo: 10, msArmado: 1, msDibujo: 90, imagenes: 20);
      for (var i = 0; i < 4; i++) {
        expect(a.mirar(poca, hz: 60), isFalse);
      }
      expect(a.fondo, FondoDeLaTele.mitad);
    });
  });

  test('pintarEnChico pinta en la imagen chica con la medida y los píxeles por punto', () {
    Size? mide;
    double? porPunto;
    final grabador = PictureRecorder();
    pintarEnChico(
      Canvas(grabador),
      const Rect.fromLTWH(0, 0, 960, 540),
      escala: 0.5,
      pixeles: 2,
      dibujar: (lienzo, m, p) {
        mide = m;
        porPunto = p;
      },
    );
    grabador.endRecording().dispose();
    // 960 × 540 puntos a 2 píxeles por punto, a la mitad: 960 × 540 píxeles.
    expect(mide, const Size(960, 540));
    expect(porPunto, 1);
  });
}
