// Personalizar tótem (paso 3b de la 6.0.0): las cuatro apariencias para elegir,
// la vista del tótem de verdad con "Ver una llegada", ventana al centro en la PC
// y hoja a pantalla completa en tablet y celular. Se monta entero, con la nube
// reemplazada por los mismos providers que usa la app.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_propio.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/features/totem/totem_orientation.dart';
import 'package:arguello_events/features/totem/widgets/link_totem_navegador.dart';
import 'package:arguello_events/features/totem/widgets/totem_config_sheet.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/fondo_de_prueba.dart';
import 'helpers/personalizar_en_memoria.dart';
import 'helpers/puerta_en_memoria.dart';

const _pc = Size(1366, 768);
const _celular = Size(390, 844);
const _tablet = Size(800, 1280);

final _vista = find.byKey(const ValueKey('vista_totem'));
Finder _tarjeta(EstiloTotem e) => find.byKey(ValueKey('apariencia_${e.clave}'));
Finder _enLaVista(Finder f) => find.descendant(of: _vista, matching: f);

/// Abre Personalizar del evento desde el botón, como la paleta de Recepción.
Future<RepoTotemEnMemoria> _abrir(
  WidgetTester tester, {
  Size tamano = _pc,
  String eventoId = eventoMasivo,
  TotemConfig? guardada,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = RepoTotemEnMemoria();
  // Si ya había una abierta, que se vaya con sus providers: un ProviderScope
  // nuevo en el mismo lugar se queda con los de antes.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    anfitrionPersonalizar(
      eventoId: eventoId,
      guardada: guardada ??
          TotemConfig(eventoId: eventoId, titulo: 'PROMOCIÓN 2026'),
      repo: repo,
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text(abrirPersonalizar));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return repo;
}

EscenaTotem _escenaDeLaVista(WidgetTester tester) =>
    tester.widget<EscenaTotem>(_vista);

TarjetaApariencia _laTarjeta(WidgetTester tester, EstiloTotem e) =>
    tester.widget<TarjetaApariencia>(_tarjeta(e));

Future<void> _guardar(WidgetTester tester) async {
  await tester.tap(find.text('GUARDAR'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    await cargarFuentesTotem();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PersonalizarTotem.elegirFoto = elegirFotoDePrueba;
    await FondoTotem.precargar();
  });

  tearDown(FondoTotem.olvidar);

  group('cómo se abre', () {
    testWidgets('en la PC, ventana al centro con la vista a la izquierda',
        (tester) async {
      await _abrir(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      for (final e in EstiloTotem.deLaCasa) {
        expect(_tarjeta(e), findsOneWidget);
        expect(
          tester.getCenter(_vista).dx,
          lessThan(tester.getTopLeft(_tarjeta(e)).dx),
          reason: 'la vista va a la izquierda de ${e.nombre}',
        );
      }
      expect(find.text('VISTA DEL TÓTEM · NEÓN'), findsOneWidget);
    });

    for (final tamano in [_celular, _tablet]) {
      testWidgets('en ${tamano.width.toInt()} px, hoja a pantalla completa con '
          'la vista arriba', (tester) async {
        await _abrir(tester, tamano: tamano);
        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          tester.getSize(find.byType(PersonalizarTotem)).height,
          moreOrLessEquals(tamano.height, epsilon: 1),
        );
        expect(
          tester.getBottomLeft(_vista).dy,
          lessThan(tester.getTopLeft(_tarjeta(EstiloTotem.neon)).dy),
        );
      });
    }

    testWidgets('se cierra con la cruz sin guardar nada', (tester) async {
      final repo = await _abrir(tester);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PersonalizarTotem), findsNothing);
      expect(repo.guardadas, isEmpty);
    });
  });

  group('sin desbordes', () {
    for (final tamano in [const Size(360, 640), _tablet, _pc]) {
      for (final evento in [eventoMasivo, eventoParticular]) {
        testWidgets(
            '${tamano.width.toInt()}×${tamano.height.toInt()}, '
            '${evento == eventoMasivo ? 'masivo' : 'particular'}, vertical y '
            'horizontal, con una llegada', (tester) async {
          await _abrir(tester, tamano: tamano, eventoId: evento);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Horizontal'));
          await tester.tap(find.text('Horizontal'));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('ver_una_llegada')));
          await tester.pump();
          await tester.pump(EscenaTotem.entrada);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('la apariencia', () {
    testWidgets('si nadie eligió: Neón marcada en un masivo, con el rótulo',
        (tester) async {
      await _abrir(tester);
      expect(_escenaDeLaVista(tester).estilo, EstiloTotem.neon);
      for (final e in EstiloTotem.deLaCasa) {
        final t = _laTarjeta(tester, e);
        expect(t.elegida, e == EstiloTotem.neon, reason: e.nombre);
        expect(t.vaSiNoElegis, e == EstiloTotem.neon, reason: e.nombre);
      }
      expect(find.text(TarjetaApariencia.rotuloPorDefecto), findsOneWidget);
    });

    testWidgets('si nadie eligió: Cristal marcada en un particular',
        (tester) async {
      await _abrir(tester, eventoId: eventoParticular);
      expect(_escenaDeLaVista(tester).estilo, EstiloTotem.cristal);
      expect(_laTarjeta(tester, EstiloTotem.cristal).elegida, isTrue);
      expect(_laTarjeta(tester, EstiloTotem.cristal).vaSiNoElegis, isTrue);
      expect(_laTarjeta(tester, EstiloTotem.neon).elegida, isFalse);
    });

    testWidgets('tocar Gala la pone en la vista, y guardar la manda',
        (tester) async {
      final repo = await _abrir(tester);
      await tester.tap(_tarjeta(EstiloTotem.gala));
      await tester.pump();
      expect(_escenaDeLaVista(tester).estilo, EstiloTotem.gala);
      expect(_laTarjeta(tester, EstiloTotem.gala).elegida, isTrue);
      expect(_laTarjeta(tester, EstiloTotem.neon).elegida, isFalse);
      expect(find.text(TarjetaApariencia.rotuloPorDefecto), findsNothing);
      expect(find.text('VISTA DEL TÓTEM · GALA'), findsOneWidget);

      await _guardar(tester);
      expect(repo.guardadas.single.estilo, 'gala');
      expect(find.byType(PersonalizarTotem), findsNothing);
      expect(find.text('Tótem actualizado.'), findsOneWidget);
    });

    testWidgets('en el celular también se elige y se guarda', (tester) async {
      final repo = await _abrir(tester, tamano: _celular);
      await tester.ensureVisible(_tarjeta(EstiloTotem.poster));
      await tester.tap(_tarjeta(EstiloTotem.poster));
      await tester.pump();
      expect(_escenaDeLaVista(tester).estilo, EstiloTotem.poster);
      await _guardar(tester);
      expect(repo.guardadas.single.estilo, 'poster');
    });

    testWidgets('guardar sin tocar una tarjeta conserva lo que había',
        (tester) async {
      for (final antes in [null, 'poster', 'aurora']) {
        final repo = await _abrir(
          tester,
          guardada: TotemConfig(
            eventoId: eventoMasivo,
            titulo: 'PROMOCIÓN 2026',
            estilo: antes,
          ),
        );
        await _guardar(tester);
        expect(repo.guardadas.single.estilo, antes, reason: '$antes');
      }
    });

    testWidgets('con una guardada, va marcada esa y sin el rótulo',
        (tester) async {
      await _abrir(
        tester,
        guardada: const TotemConfig(eventoId: eventoMasivo, estilo: 'poster'),
      );
      expect(_escenaDeLaVista(tester).estilo, EstiloTotem.poster);
      expect(_laTarjeta(tester, EstiloTotem.poster).elegida, isTrue);
      expect(find.text(TarjetaApariencia.rotuloPorDefecto), findsNothing);
    });

    testWidgets('las tarjetas están quietas y la vista se mueve',
        (tester) async {
      await _abrir(tester);
      for (final e in EstiloTotem.deLaCasa) {
        final escena = tester.widget<EscenaTotem>(
          find.descendant(of: _tarjeta(e), matching: find.byType(EscenaTotem)),
        );
        expect(escena.quieta, isTrue, reason: e.nombre);
      }
      expect(_escenaDeLaVista(tester).quieta, isFalse);
    });
  });

  group('lo que se escribe se ve', () {
    testWidgets('el título y el color, en la vista y en las tarjetas',
        (tester) async {
      await _abrir(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Título'),
        'EGRESADOS 2026',
      );
      await tester.pump();
      expect(_escenaDeLaVista(tester).cfg.titulo, 'EGRESADOS 2026');
      for (final e in EstiloTotem.deLaCasa) {
        expect(_laTarjeta(tester, e).cfg.titulo, 'EGRESADOS 2026');
      }
      await tester.ensureVisible(find.byTooltip('Rosa'));
      await tester.tap(find.byTooltip('Rosa'));
      await tester.pump();
      expect(
        _escenaDeLaVista(tester).cfg.colorAcento,
        const Color(0xFFFF8FB1),
      );
    });

    testWidgets('una foto recién elegida se ve antes de guardar',
        (tester) async {
      await _abrir(tester);
      expect(_escenaDeLaVista(tester).foto, isNull);
      await tester.ensureVisible(find.text('Elegir foto'));
      await tester.tap(find.text('Elegir foto'));
      await tester.pump();
      await tester.pump();
      final foto = _escenaDeLaVista(tester).foto;
      expect(foto, isA<MemoryImage>());
      expect((foto! as MemoryImage).bytes, fotoDePrueba);
      for (final e in EstiloTotem.deLaCasa) {
        expect(_laTarjeta(tester, e).foto, foto, reason: e.nombre);
      }
      expect(find.text('Quitar foto'), findsOneWidget);
    });
  });

  group('ver una llegada', () {
    testWidgets('en un masivo, la familia de ejemplo y vuelve la espera',
        (tester) async {
      await _abrir(tester);
      expect(_enLaVista(find.text('2026')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ver_una_llegada')));
      await tester.pump();
      await tester.pump(EscenaTotem.entrada);
      expect(_enLaVista(find.text('¡Bienvenidos!')), findsOneWidget);
      expect(_enLaVista(find.text('PÉREZ, JUAN MARTÍN')), findsOneWidget);
      expect(
        _enLaVista(find.text('con GÓMEZ, ANA y PÉREZ, LUIS')),
        findsOneWidget,
      );
      expect(_enLaVista(find.text('10 sillas (8 + 2 extra)')), findsOneWidget);
      expect(_enLaVista(find.text('Tusa · Karol G')), findsOneWidget);
      // Las tarjetas siguen en la espera.
      expect(
        find.descendant(
          of: _tarjeta(EstiloTotem.gala),
          matching: find.text('PÉREZ, JUAN MARTÍN'),
        ),
        findsNothing,
      );

      // A los 5 s sigue; a los 7 s se va y vuelve la espera.
      await tester.pump(const Duration(seconds: 4));
      expect(_enLaVista(find.text('PÉREZ, JUAN MARTÍN')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(EscenaTotem.salida);
      await tester.pump();
      expect(_enLaVista(find.text('PÉREZ, JUAN MARTÍN')), findsNothing);
      expect(_enLaVista(find.text('2026')), findsOneWidget);
      expect(_escenaDeLaVista(tester).llegada, isNull);
    });

    testWidgets('si se cambia de apariencia mientras, la llegada sigue',
        (tester) async {
      await _abrir(tester);
      await tester.tap(find.byKey(const ValueKey('ver_una_llegada')));
      await tester.pump();
      await tester.pump(EscenaTotem.entrada);
      await tester.tap(_tarjeta(EstiloTotem.cristal));
      await tester.pump();
      expect(_escenaDeLaVista(tester).estilo, EstiloTotem.cristal);
      expect(_enLaVista(find.text('PÉREZ, JUAN MARTÍN')), findsOneWidget);
    });

    testWidgets('con la música apagada, sin música', (tester) async {
      await _abrir(
        tester,
        guardada: const TotemConfig(
          eventoId: eventoMasivo,
          titulo: 'PROMOCIÓN 2026',
          mostrarMusica: false,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('ver_una_llegada')));
      await tester.pump();
      await tester.pump(EscenaTotem.entrada);
      expect(_enLaVista(find.text('PÉREZ, JUAN MARTÍN')), findsOneWidget);
      expect(find.text('Tusa · Karol G'), findsNothing);
    });

    test('lo que dice, armado como en el salón', () {
      const cfg = TotemConfig(eventoId: eventoMasivo);
      final familia = LlegadaDeEjemplo.para(masivo: true, cfg: cfg);
      expect(familia.saludo, '¡Bienvenidos!');
      expect(familia.nombres, ['PÉREZ, JUAN MARTÍN']);
      expect(familia.conQuien, 'con GÓMEZ, ANA y PÉREZ, LUIS');
      expect(familia.mesa, '12');
      expect(familia.sillas, '10 sillas (8 + 2 extra)');
      expect(familia.musica, 'Tusa · Karol G');

      final sinMusica = LlegadaDeEjemplo.para(
        masivo: true,
        cfg: cfg.copyWith(mostrarMusica: false),
      );
      expect(sinMusica.musica, isNull);

      // Un saludo escrito a mano no se pasa al plural.
      final propio = LlegadaDeEjemplo.para(
        masivo: true,
        cfg: cfg.copyWith(mensajeBienvenida: '¡Qué bueno verte!'),
      );
      expect(propio.saludo, '¡Qué bueno verte!');

      final particular = LlegadaDeEjemplo.para(
        masivo: false,
        cfg: const TotemConfig(eventoId: eventoParticular),
      );
      expect(particular.saludo, '¡Bienvenido!');
      expect(particular.nombres, ['GONZÁLEZ, MARÍA']);
      expect(particular.mesa, '4');
      expect(particular.sillas, isNull);
      expect(particular.musica, isNull);
      expect(particular.conQuien, isNull);
    });
  });

  // Sección 8: el tótem por el navegador lee con la clave que va en el link, y
  // el link sale de acá.
  testWidgets('al pie, el link del tótem por el navegador con su clave',
      (tester) async {
    await _abrir(tester, eventoId: eventoParticular);
    final link = find.text(
        'https://arguello-events.vercel.app/?totem&evento=$eventoParticular'
        '&clave=$claveDePrueba');
    await tester.ensureVisible(find.text(LinkTotemNavegador.titulo));
    await tester.pump();
    expect(link, findsOneWidget);
    expect(find.text(LinkTotemNavegador.copiar), findsOneWidget);
  });

  group('el QR', () {
    testWidgets('en un particular, en la vista y con su texto para escribir',
        (tester) async {
      await _abrir(tester, eventoId: eventoParticular);
      expect(_enLaVista(find.byType(QrImageView)), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Texto del QR'), findsOneWidget);
      expect(find.byType(CasillaMusicaTotem), findsNothing);
    });

    testWidgets('en un masivo, ni el QR ni su texto: la casilla de la música',
        (tester) async {
      await _abrir(tester);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.widgetWithText(TextField, 'Texto del QR'), findsNothing);
      expect(find.byType(CasillaMusicaTotem), findsOneWidget);
    });
  });

  testWidgets('la vista arranca como quedó el tótem del evento',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await TotemOrientationStore.save(eventoMasivo, TotemOrientation.horizontal);
    await _abrir(tester);
    await tester.pump();
    final tam = tester.getSize(_vista);
    expect(tam.width, greaterThan(tam.height));
  });

  group('"Tu fondo"', () {
    late Uint8List png;
    setUpAll(() async => png = await pngDePrueba());
    setUp(() {
      FondoPropio.olvidar();
      PersonalizarTotem.elegirFondo = elegirFondoDePrueba(png);
    });
    tearDown(FondoPropio.olvidar);

    /// Elige el fondo y deja que se lea la imagen.
    Future<void> elegirFondo(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('elegir_fondo')));
      await tester.tap(find.byKey(const ValueKey('elegir_fondo')));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.text('Leyendo la imagen…').evaluate().isEmpty &&
            find.text('Se lee:').evaluate().isNotEmpty) {
          break;
        }
      }
    }

    testWidgets('sin fondo, no se puede elegir: no hay tarjeta', (tester) async {
      await _abrir(tester);
      expect(_tarjeta(EstiloTotem.tuFondo), findsNothing);
      expect(find.text('Elegir fondo'), findsOneWidget);
      expect(find.text('Automático · según la imagen'), findsNothing);
    });

    testWidgets('al elegirlo queda elegida "Tu fondo" y la receta sale de la '
        'imagen', (tester) async {
      await _abrir(tester);
      await elegirFondo(tester);
      expect(tester.takeException(), isNull);
      expect(_tarjeta(EstiloTotem.tuFondo), findsOneWidget);
      expect(_laTarjeta(tester, EstiloTotem.tuFondo).elegida, isTrue);
      expect(_escenaDeLaVista(tester).estilo, EstiloTotem.tuFondo);
      expect(_escenaDeLaVista(tester).fondo, isA<MemoryImage>());
      expect(find.text('VISTA DEL TÓTEM · TU FONDO'), findsOneWidget);
      // Lo que se leyó y lo que eligió.
      expect(find.text('Se lee:'), findsOneWidget);
      expect(find.textContaining('Eligió: '), findsOneWidget);
      final cfg = _escenaDeLaVista(tester).cfg;
      expect(cfg.fondoAutomatico, isTrue);
      expect(cfg.fondoPaleta, hasLength(3));
      expect(cfg.fondoAnimacion, isNotNull);
    });

    testWidgets('guardar sube el fondo y manda toda la receta', (tester) async {
      final repo = await _abrir(tester);
      await elegirFondo(tester);
      final antes = _escenaDeLaVista(tester).cfg;
      await _guardar(tester);
      expect(repo.fondosSubidos.single, png);
      final g = repo.guardadas.single;
      expect(g.estilo, 'tu_fondo');
      expect(g.fondoUrl, 'https://nube.test/totem/$eventoMasivo/fondo.png?v=1');
      expect(g.fondoAutomatico, isTrue);
      expect(g.fondoAnimacion, antes.fondoAnimacion);
      expect(g.fondoEfectos, antes.fondoEfectos);
      expect(g.fondoPaleta, antes.fondoPaleta);
      expect(g.fondoFoco, antes.fondoFoco);
      expect(g.fondoLetras, antes.fondoLetras);
      expect(g.fondoLuz, antes.fondoLuz);
    });

    testWidgets('tocar una animación o un efecto apaga "Automático"',
        (tester) async {
      final repo = await _abrir(tester);
      await elegirFondo(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('animacion_ondular')));
      await tester.tap(find.byKey(const ValueKey('animacion_ondular')));
      await tester.pump();
      expect(_escenaDeLaVista(tester).cfg.fondoAutomatico, isFalse);
      expect(find.textContaining('Lo elegiste vos'), findsOneWidget);
      final antes = _escenaDeLaVista(tester).cfg.fondoEfectos ?? const [];
      final yaEstaba = antes.contains('glitch');
      await tester.ensureVisible(find.byKey(const ValueKey('efecto_glitch')));
      await tester.tap(find.byKey(const ValueKey('efecto_glitch')));
      await tester.pump();
      await _guardar(tester);
      final g = repo.guardadas.single;
      expect(g.fondoAutomatico, isFalse);
      expect(g.fondoAnimacion, 'ondular');
      expect(g.fondoEfectos!.contains('glitch'), !yaEstaba);
    });

    testWidgets('volver a "Automático" vuelve a la receta de la imagen',
        (tester) async {
      await _abrir(tester);
      await elegirFondo(tester);
      final receta = _escenaDeLaVista(tester).cfg.fondoAnimacion;
      await tester.ensureVisible(find.byKey(const ValueKey('animacion_quieta')));
      await tester.tap(find.byKey(const ValueKey('animacion_quieta')));
      await tester.pump();
      expect(_escenaDeLaVista(tester).cfg.fondoAnimacion, 'quieta');
      await tester.ensureVisible(find.byKey(const ValueKey('fondo_automatico')));
      await tester.tap(find.byKey(const ValueKey('fondo_automatico')));
      await tester.pump();
      expect(_escenaDeLaVista(tester).cfg.fondoAutomatico, isTrue);
      expect(_escenaDeLaVista(tester).cfg.fondoAnimacion, receta);
    });

    testWidgets('otra apariencia conserva el fondo para volver', (tester) async {
      final repo = await _abrir(tester);
      await elegirFondo(tester);
      // Elegir el fondo bajó la columna: las tarjetas quedaron arriba.
      await tester.ensureVisible(_tarjeta(EstiloTotem.gala));
      await tester.pump();
      await tester.tap(_tarjeta(EstiloTotem.gala));
      await tester.pump();
      expect(_escenaDeLaVista(tester).estilo, EstiloTotem.gala);
      expect(_tarjeta(EstiloTotem.tuFondo), findsOneWidget);
      await _guardar(tester);
      final g = repo.guardadas.single;
      expect(g.estilo, 'gala');
      expect(g.fondoUrl, isNotNull, reason: 'queda guardado para volver');
    });

    group('con un fondo guardado', () {
      final guardada = conTuFondo(
        const TotemConfig(eventoId: eventoMasivo, titulo: 'PROMOCIÓN 2026'),
        animacion: 'respirar',
        efectos: ['bokeh', 'marco'],
      ).copyWith(fondoAutomatico: false);

      testWidgets('guardar sin tocar nada lo conserva entero', (tester) async {
        final repo = await _abrir(tester, guardada: guardada);
        expect(_tarjeta(EstiloTotem.tuFondo), findsOneWidget);
        expect(_escenaDeLaVista(tester).estilo, EstiloTotem.tuFondo);
        await _guardar(tester);
        final a = repo.guardadas.single.toJson();
        final b = guardada.toJson();
        for (final k in b.keys.where((k) => k.startsWith('fondo_'))) {
          expect(a[k], b[k], reason: k);
        }
        expect(repo.fondosSubidos, isEmpty);
        expect(repo.fondosBorrados, 0);
      });

      testWidgets('quitarlo lo borra y vuelve a la apariencia del tipo',
          (tester) async {
        final repo = await _abrir(tester, guardada: guardada);
        await tester.ensureVisible(find.text('Quitar fondo'));
        await tester.tap(find.text('Quitar fondo'));
        await tester.pump();
        expect(_tarjeta(EstiloTotem.tuFondo), findsNothing);
        expect(_escenaDeLaVista(tester).estilo, EstiloTotem.neon);
        await _guardar(tester);
        expect(repo.fondosBorrados, 1);
        final g = repo.guardadas.single;
        expect(g.fondoUrl, isNull);
        expect(g.estilo, isNull);
      });

      testWidgets('el oscurecido se cambia a mano', (tester) async {
        final repo = await _abrir(tester, guardada: guardada);
        final barra = find.byKey(const ValueKey('oscurecer'));
        await tester.ensureVisible(barra);
        // Hasta la punta derecha: el máximo.
        await tester.drag(barra, const Offset(600, 0));
        await tester.pump();
        await _guardar(tester);
        expect(repo.guardadas.single.fondoOscurecer, TotemConfig.oscurecerMaximo);
        expect(repo.guardadas.single.fondoAutomatico, isFalse);
      });
    });

    for (final tamano in [const Size(360, 640), _tablet, _pc]) {
      testWidgets(
          '${tamano.width.toInt()}×${tamano.height.toInt()}: con fondo, vertical '
          'y horizontal y una llegada, sin desbordes', (tester) async {
        await _abrir(tester, tamano: tamano);
        await elegirFondo(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Horizontal'));
        await tester.tap(find.text('Horizontal'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('ver_una_llegada')));
        await tester.pump();
        await tester.pump(EscenaTotem.entrada);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('un error al guardar se dice en palabras y no cierra',
      (tester) async {
    final repo = await _abrir(tester);
    repo.fallar = true;
    await _guardar(tester);
    expect(find.text(PersonalizarTotem.errorAlGuardar), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('supabase'), findsNothing);
    expect(find.byType(PersonalizarTotem), findsOneWidget);
    expect(repo.guardadas, isEmpty);
  });
}
