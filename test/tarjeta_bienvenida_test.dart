// Lo que dice la bienvenida del tótem (`contenido_bienvenida.dart`) y cómo se
// ve (`tarjeta_bienvenida.dart`), y la pantalla de espera con y sin QR
// (`portada_totem.dart`). La pantalla entera del tótem lee la nube y no se
// puede montar en un test; estas piezas sí, y de ahí salen las muestras.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/widgets/portada_totem.dart';
import 'package:arguello_events/features/totem/widgets/tarjeta_bienvenida.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

final _t0 = DateTime(2026, 12, 12, 22);
const _cfg = TotemConfig(eventoId: eventoMasivo);

BienvenidaTotem _tarjeta(List<Invitado> personas) => BienvenidaTotem(
      familia: personas.first.id,
      personas: personas,
      empezo: _t0,
    );

ContenidoBienvenida _armar(
  List<Invitado> personas, {
  FichaTotem? ficha,
  TotemConfig cfg = _cfg,
}) =>
    ContenidoBienvenida.armar(
      _tarjeta(personas),
      ficha: ficha ?? fichaDePrueba(),
      cfg: cfg,
    );

void main() {
  group('lo que dice', () {
    test('la familia: el alumno en grande, con quién viene, mesa y sillas', () {
      final c = _armar([filaDe('perez'), filaDe('perez', 1), filaDe('perez', 2)]);
      expect(c.saludo, '¡Bienvenidos!');
      expect(c.nombres, ['PÉREZ, JUAN MARTÍN']);
      expect(c.conQuien, 'con GÓMEZ, ANA y PÉREZ, LUIS');
      expect(c.acompanaA, isNull);
      expect(c.rotuloMesa, 'Mesa');
      expect(c.mesa, '12');
      expect(c.sillas, '10 sillas (8 + 2 extra)');
      expect(c.musica, 'Tusa · Karol G');
    });

    test('el alumno va primero aunque haya entrado después', () {
      final c = _armar([filaDe('perez', 1), filaDe('perez')]);
      expect(c.nombres, ['PÉREZ, JUAN MARTÍN']);
      expect(c.conQuien, 'con GÓMEZ, ANA');
    });

    test('el alumno solo: saludo de siempre, sin "con"', () {
      final c = _armar([filaDe('garcia')]);
      expect(c.saludo, '¡Bienvenido!');
      expect(c.nombres, ['GARCÍA, BRUNO']);
      expect(c.conQuien, isNull);
      expect(c.mesa, '17');
      expect(c.sillas, '8 sillas');
      expect(c.musica, isNull, reason: 'no tiene música cargada');
    });

    test('un acompañante solo: a quién acompaña', () {
      final c = _armar([filaDe('perez', 1)]);
      expect(c.nombres, ['GÓMEZ, ANA']);
      expect(c.acompanaA, 'acompaña a PÉREZ, JUAN MARTÍN');
      expect(c.mesa, '12');
      expect(c.sillas, '10 sillas (8 + 2 extra)');
      expect(c.musica, isNull, reason: 'la música es del alumno');
    });

    test('dos acompañantes sin el alumno', () {
      final c = _armar([filaDe('perez', 1), filaDe('perez', 2)]);
      expect(c.nombres, ['GÓMEZ, ANA', 'PÉREZ, LUIS']);
      expect(c.acompanaA, 'acompañan a PÉREZ, JUAN MARTÍN');
      expect(c.saludo, '¡Bienvenidos!');
    });

    test('dos mesas: "Mesas", y las sillas de cada una', () {
      final c = _armar([filaDe('acosta')]);
      expect(c.rotuloMesa, 'Mesas');
      expect(c.mesa, '14-15');
      expect(c.sillas, '14: 10 sillas · 15: 9 sillas');
      expect(c.sillas, isNot(contains('confirmar')));
    });

    test('sin sortear: el saludo sin mesa ni sillas, con la música', () {
      final ficha = fichaDePrueba(sorteado: false);
      final c = _armar(
        [filaDe('perez', 0, ficha), filaDe('perez', 1, ficha)],
        ficha: ficha,
      );
      expect(c.mesa, isNull);
      expect(c.sillas, isNull);
      expect(c.musica, 'Tusa · Karol G');
      expect(c.conQuien, 'con GÓMEZ, ANA');
    });

    test('la fila con una mesa vieja no manda: la ficha dice sin sortear', () {
      final ficha = fichaDePrueba(sorteado: false);
      final vieja = Invitado(
        id: idDe('perez'),
        eventoId: eventoMasivo,
        nombreCompleto: 'PÉREZ, JUAN MARTÍN',
        dni: '',
        numeroMesa: '12',
        estadoIngreso: EstadoIngreso.ingresado,
      );
      expect(_armar([vieja], ficha: ficha).mesa, isNull);
    });

    test('el que quedó sin mesa en un evento sorteado: sin mesa, nunca '
        '"sin mesa"', () {
      final c = _armar([filaDe('sosa')]);
      expect(c.mesa, isNull);
      expect(c.sillas, isNull);
      for (final texto in [c.saludo, ...c.nombres, c.conQuien, c.acompanaA]) {
        expect(texto ?? '', isNot(contains(RegExp('sin mesa', caseSensitive: false))));
      }
    });

    test('con la música apagada en Personalizar, no va', () {
      final c = _armar(
        [filaDe('perez')],
        cfg: _cfg.copyWith(mostrarMusica: false),
      );
      expect(c.musica, isNull);
      expect(c.mesa, '12', reason: 'lo demás sigue igual');
    });

    test('un saludo escrito a mano no se pasa al plural', () {
      final c = _armar(
        [filaDe('perez'), filaDe('perez', 1)],
        cfg: _cfg.copyWith(mensajeBienvenida: '¡Hola, promo 2026!'),
      );
      expect(c.saludo, '¡Hola, promo 2026!');
    });

    test('un particular: nombre y mesa de la fila, como siempre', () {
      final c = ContenidoBienvenida.armar(
        _tarjeta([filaSuelta('i1', 'LÓPEZ, MARTA', mesa: '4')]),
        ficha: const FichaTotem.particular(eventoParticular),
        cfg: _cfg,
      );
      expect(c.saludo, '¡Bienvenido!');
      expect(c.nombres, ['LÓPEZ, MARTA']);
      expect(c.mesa, '4');
      expect(c.sillas, isNull);
      expect(c.musica, isNull);
      expect(c.conQuien, isNull);
    });

    test('sin ficha (la web) o alguien que la ficha no tiene: la fila', () {
      final suelta = filaSuelta('a-mano', 'INVITADO ESPECIAL', mesa: '1');
      for (final ficha in [null, fichaDePrueba()]) {
        final c = ContenidoBienvenida.armar(
          _tarjeta([suelta]),
          ficha: ficha,
          cfg: _cfg,
        );
        expect(c.nombres, ['INVITADO ESPECIAL']);
        expect(c.mesa, '1');
        expect(c.sillas, isNull);
      }
    });

    test('tres que llegan juntos: sin comas entre nombres', () {
      final ficha = FichaTotem(
        eventoId: eventoMasivo,
        masivo: true,
        personas: {
          for (final (id, n, alumno) in [
            ('a', 'PÉREZ, JUAN', true),
            ('b', 'GÓMEZ, ANA', false),
            ('c', 'SOSA, EVA', false),
            ('d', 'RÍOS, LUIS', false),
          ])
            id: PersonaFicha(id: id, nombre: n, familia: 'a', esAlumno: alumno),
        },
      );
      final c = ContenidoBienvenida.armar(
        _tarjeta([
          for (final id in ['a', 'b', 'c', 'd'])
            filaSuelta(id, ficha.de(id)!.nombre),
        ]),
        ficha: ficha,
        cfg: _cfg,
      );
      expect(c.conQuien, 'con GÓMEZ, ANA · SOSA, EVA y RÍOS, LUIS');
    });
  });

  group('el QR', () {
    test('en la ventana del escritorio: solo en un particular', () {
      expect(
        hayQrEnElTotem(
          enLaVentanaDelEscritorio: true,
          ficha: const FichaTotem.particular(eventoParticular),
        ),
        isTrue,
      );
      expect(
        hayQrEnElTotem(enLaVentanaDelEscritorio: true, ficha: fichaDePrueba()),
        isFalse,
      );
    });

    test('mientras no llega la ficha, no: podría ser un masivo', () {
      expect(
        hayQrEnElTotem(enLaVentanaDelEscritorio: true, ficha: null),
        isFalse,
      );
    });

    test('en la web, como siempre: no hay ficha que pedir', () {
      expect(
        hayQrEnElTotem(enLaVentanaDelEscritorio: false, ficha: null),
        isTrue,
      );
    });
  });

  group('cómo se ve', () {
    setUpAll(() {
      // Outfit regular y negrita vienen con la app: anda sin internet.
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    Future<void> montar(
      WidgetTester tester,
      Widget hijo, {
      Size tamano = const Size(1080, 1920),
    }) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: hijo),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final familia = _armar([
      filaDe('perez'),
      filaDe('perez', 1),
      filaDe('perez', 2),
    ]);

    for (final (nombre, tamano, escala) in [
      ('vertical', const Size(1080, 1920), 1.74),
      ('apaisada', const Size(1920, 1080), 1.38),
      ('chica', const Size(360, 640), 0.7),
    ]) {
      testWidgets('la familia entera, sin desbordes, en pantalla $nombre',
          (tester) async {
        await montar(
          tester,
          TarjetaBienvenida(
            contenido: familia,
            cfg: _cfg,
            escala: escala,
            enCamino: 3,
          ),
          tamano: tamano,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('¡Bienvenidos!'), findsOneWidget);
        expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
        expect(find.text('con GÓMEZ, ANA y PÉREZ, LUIS'), findsOneWidget);
        expect(find.text('Nº 12'), findsOneWidget);
        expect(find.text('10 sillas (8 + 2 extra)'), findsOneWidget);
        expect(find.text('Tusa · Karol G'), findsOneWidget);
        expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
        expect(find.text('3 más en camino'), findsOneWidget);
        // Las sillas van debajo de la mesa, y la música debajo de las sillas.
        final mesa = tester.getTopLeft(find.text('Nº 12')).dy;
        final sillas = tester.getTopLeft(find.text('10 sillas (8 + 2 extra)')).dy;
        final musica = tester.getTopLeft(find.text('Tusa · Karol G')).dy;
        expect(sillas, greaterThan(mesa));
        expect(musica, greaterThan(sillas));
      });
    }

    testWidgets('sin mesa no hay recuadro de mesa', (tester) async {
      await montar(
        tester,
        TarjetaBienvenida(
          contenido: _armar([filaDe('sosa')]),
          cfg: _cfg,
          escala: 1.5,
        ),
      );
      expect(find.text('SOSA, EMILIA'), findsOneWidget);
      expect(find.textContaining('Nº'), findsNothing);
      expect(find.byIcon(Icons.table_restaurant_rounded), findsNothing);
      expect(find.textContaining('más en camino'), findsNothing);
    });

    testWidgets('el acompañante solo dice a quién acompaña', (tester) async {
      await montar(
        tester,
        TarjetaBienvenida(
          contenido: _armar([filaDe('perez', 1)]),
          cfg: _cfg,
          escala: 1.5,
        ),
      );
      expect(find.text('acompaña a PÉREZ, JUAN MARTÍN'), findsOneWidget);
      expect(find.byIcon(Icons.music_note_rounded), findsNothing);
    });

    testWidgets('la espera de un masivo no tiene QR; la de un particular, sí',
        (tester) async {
      for (final (qr, esperado) in [
        (null, findsNothing),
        ('https://arguello-events.vercel.app/lista?evento=$eventoParticular',
            findsOneWidget),
      ]) {
        await montar(
          tester,
          PortadaTotem(
            cfg: _cfg.copyWith(titulo: 'PROMOCIÓN 2026', subtitulo: 'Escuela Normal'),
            qrUrl: qr,
            apaisado: false,
            escala: 1.5,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(QrImageView), esperado);
        expect(find.text('PROMOCIÓN 2026'), findsOneWidget);
        expect(find.text('ESCUELA NORMAL'), findsOneWidget);
      }
    });
  });
}
