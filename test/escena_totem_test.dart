// Las cuatro apariencias del tótem (`estilos/`): la espera y la llegada de
// cada una, en una pantalla vertical, una apaisada y una chica, sin desbordes,
// con lo que tiene que decir y sin lo que no.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/features/totem/estilos/plano_del_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/services/foto_guardada.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/personalizar_en_memoria.dart' show fotoDePrueba;
import 'helpers/puerta_en_memoria.dart';

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
const _qr = 'https://arguello-events.vercel.app/lista?evento=$eventoParticular';

ContenidoBienvenida _llegada(
  List<Invitado> personas, {
  FichaTotem? ficha,
  TotemConfig cfg = _masivo,
}) =>
    ContenidoBienvenida.armar(
      BienvenidaTotem(
        familia: personas.first.id,
        personas: personas,
        empezo: DateTime(2026, 12, 12, 22),
      ),
      ficha: ficha ?? fichaDePrueba(),
      cfg: cfg,
    );

const _tamanos = {
  'vertical': Size(1080, 1920),
  'apaisada': Size(1920, 1080),
  'chica': Size(360, 640),
};

Future<void> _montar(
  WidgetTester tester,
  Widget escena, {
  Size tamano = const Size(1080, 1920),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: escena)),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await cargarFuentesTotem();
  });

  setUp(() async => FondoTotem.precargar());
  tearDown(FondoTotem.olvidar);

  group('la apariencia', () {
    test('si nadie eligió: Neón en un masivo, Cristal en un particular', () {
      expect(estiloDelTotem(ficha: fichaDePrueba()), EstiloTotem.neon);
      expect(
        estiloDelTotem(ficha: const FichaTotem.particular(eventoParticular)),
        EstiloTotem.cristal,
      );
      // El tótem por el navegador no sabe el tipo: Cristal.
      expect(estiloDelTotem(), EstiloTotem.cristal);
    });

    test('la elegida manda, en cualquier tipo de evento', () {
      expect(estiloDelTotem(elegido: 'gala', ficha: fichaDePrueba()),
          EstiloTotem.gala);
      expect(estiloDelTotem(elegido: 'POSTER'), EstiloTotem.poster);
    });

    test('vacía o desconocida, la del tipo: nunca una pantalla rota', () {
      for (final rara in ['', '  ', 'aurora', null]) {
        expect(estiloDelTotem(elegido: rara, ficha: fichaDePrueba()),
            EstiloTotem.neon,
            reason: '$rara');
      }
    });

    test('"Tu fondo" sin imagen no cuenta: va la del tipo', () {
      for (final url in [null, '']) {
        expect(
          estiloDelTotem(elegido: 'tu_fondo', fondoUrl: url, ficha: fichaDePrueba()),
          EstiloTotem.neon,
          reason: '$url',
        );
        expect(EstiloTotem.elegida('tu_fondo', fondoUrl: url), isNull);
      }
      expect(
        estiloDelTotem(
          elegido: 'TU_FONDO',
          fondoUrl: 'https://x.test/fondo.jpg?v=1',
          ficha: fichaDePrueba(),
        ),
        EstiloTotem.tuFondo,
      );
      // Las demás no necesitan imagen.
      expect(EstiloTotem.elegida('gala', fondoUrl: null), EstiloTotem.gala);
    });

    // La 6.1.1 (019bca3) busca la clave entre sus cuatro con este mismo
    // `desdeClave`: "tu_fondo" no está y va la del tipo.
    test('una versión que no conoce "tu_fondo" va a la del tipo', () {
      EstiloTotem? comoLaVieja(String clave) {
        for (final e in EstiloTotem.deLaCasa) {
          if (e.clave == clave) return e;
        }
        return null;
      }

      expect(comoLaVieja(EstiloTotem.tuFondo.clave), isNull);
    });

    test('ida y vuelta de la clave', () {
      for (final e in EstiloTotem.values) {
        expect(EstiloTotem.desdeClave(e.clave), e);
      }
    });

    test('el segundo neón: cian, o rosa si el color es frío', () {
      expect(segundoNeon(const Color(0xFFD4AF37)), const Color(0xFF4FE3F0));
      expect(segundoNeon(const Color(0xFF4EA8DE)), const Color(0xFFFF3CAC));
      expect(segundoNeon(const Color(0xFF9B5DE5)), const Color(0xFFFF3CAC));
      expect(segundoNeon(const Color(0xFFE63946)), const Color(0xFF4FE3F0));
    });

    test('el título en dos palabras se parte; si no, va entero', () {
      expect(partirTitulo('PROMOCIÓN 2026'), (chico: 'PROMOCIÓN', grande: '2026'));
      expect(partirTitulo('  LOS  15 '), (chico: 'LOS', grande: '15'));
      expect(partirTitulo('GÓMEZ · RÍOS'), (chico: null, grande: 'GÓMEZ · RÍOS'));
      expect(partirTitulo('JUNIOR'), (chico: null, grande: 'JUNIOR'));
    });
  });

  for (final estilo in EstiloTotem.values) {
    group(estilo.nombre, () {
      for (final MapEntry(key: nombre, value: tamano) in _tamanos.entries) {
        testWidgets('la espera de un masivo, sin QR, en pantalla $nombre',
            (tester) async {
          await _montar(
            tester,
            EscenaTotem(estilo: estilo, cfg: _masivo, quieta: true),
            tamano: tamano,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('2026'), findsOneWidget);
          expect(find.text('PROMOCIÓN'), findsOneWidget);
          expect(find.byType(QrImageView), findsNothing);
          expect(find.textContaining('YA LLEGARON'), findsNothing);
        });

        testWidgets('la familia que llega, en pantalla $nombre', (tester) async {
          await _montar(
            tester,
            EscenaTotem(
              estilo: estilo,
              cfg: _masivo,
              quieta: true,
              enCamino: 2,
              llegada: _llegada(
                [filaDe('perez'), filaDe('perez', 1), filaDe('perez', 2)],
              ),
            ),
            tamano: tamano,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('¡Bienvenidos!'), findsOneWidget);
          expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
          expect(find.text('con GÓMEZ, ANA y PÉREZ, LUIS'), findsOneWidget);
          expect(find.textContaining('12'), findsWidgets);
          expect(find.text('10 sillas (8 + 2 extra)'), findsOneWidget);
          expect(find.text('Tusa · Karol G'), findsOneWidget);
          expect(find.text('2 más en camino'), findsOneWidget);
          expect(find.textContaining('YA LLEGARON'), findsNothing);
        });
      }

      testWidgets('la espera de un particular, con su QR', (tester) async {
        await _montar(
          tester,
          EscenaTotem(estilo: estilo, cfg: _particular, qrUrl: _qr, quieta: true),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('ESCANEÁ PARA INGRESAR'), findsOneWidget);
        expect(find.text('GÓMEZ · RÍOS'), findsOneWidget);
      });

      testWidgets('un acompañante solo, dos mesas y sin mesa', (tester) async {
        for (final (personas, debe, noDebe) in [
          ([filaDe('perez', 1)], 'acompaña a PÉREZ, JUAN MARTÍN', 'Tusa · Karol G'),
          ([filaDe('acosta')], '14: 10 sillas · 15: 9 sillas', 'confirmar'),
          ([filaDe('sosa')], 'SOSA, EMILIA', 'sillas'),
        ]) {
          await _montar(
            tester,
            EscenaTotem(
              estilo: estilo,
              cfg: _masivo,
              quieta: true,
              llegada: _llegada(personas),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text(debe), findsOneWidget);
          expect(find.textContaining(noDebe), findsNothing);
        }
      });

      testWidgets('muchos acompañantes de nombre largo: se achica, no desborda',
          (tester) async {
        final ficha = FichaTotem(
          eventoId: eventoMasivo,
          masivo: true,
          personas: {
            for (var i = 1; i <= 5; i++)
              'a$i': PersonaFicha(
                id: 'a$i',
                nombre: 'FERNÁNDEZ DE LA SANTÍSIMA TRINIDAD, MARÍA JOSEFINA $i',
                familia: 'alumno',
                esAlumno: false,
                mesa: '128-129',
                sillas: '128: 10 sillas · 129: 10 sillas',
                titular: 'GONZÁLEZ DEL CORAZÓN DE JESÚS, JUAN BAUTISTA',
              ),
          },
        );
        final personas = [
          for (var i = 1; i <= 5; i++)
            filaSuelta('a$i', ficha.de('a$i')!.nombre),
        ];
        for (final tamano in [const Size(360, 640), const Size(1920, 1080)]) {
          await _montar(
            tester,
            EscenaTotem(
              estilo: estilo,
              cfg: _masivo,
              quieta: true,
              enCamino: 3,
              llegada: _llegada(personas, ficha: ficha),
            ),
            tamano: tamano,
          );
          expect(tester.takeException(), isNull);
          expect(
            find.text('acompañan a GONZÁLEZ DEL CORAZÓN DE JESÚS, JUAN BAUTISTA'),
            findsOneWidget,
          );
        }
      });

      testWidgets('un nombre muy largo no desborda', (tester) async {
        final largo = filaSuelta(
          'largo',
          'DE LA SANTÍSIMA TRINIDAD GONZÁLEZ FERNÁNDEZ, MARÍA DE LOS ÁNGELES',
          mesa: '128-129 y 140',
        );
        for (final tamano in _tamanos.values) {
          await _montar(
            tester,
            EscenaTotem(
              estilo: estilo,
              cfg: _particular,
              quieta: true,
              enCamino: 12,
              llegada: _llegada(
                [largo],
                ficha: const FichaTotem.particular(eventoParticular),
                cfg: _particular,
              ),
            ),
            tamano: tamano,
          );
          expect(tester.takeException(), isNull);
        }
      });
    });
  }

  group('el plano en la llegada de un masivo', () {
    final salon = ArmadosPredefinidos.normal2aPagina3();
    final familia = [filaDe('perez'), filaDe('perez', 1), filaDe('perez', 2)];

    for (final estilo in EstiloTotem.values) {
      for (final MapEntry(key: nombre, value: tamano) in _tamanos.entries) {
        testWidgets('${estilo.nombre}, pantalla $nombre: la mesa en el plano',
            (tester) async {
          await _montar(
            tester,
            EscenaTotem(
              estilo: estilo,
              cfg: _masivo,
              quieta: true,
              enCamino: 1,
              llegada: _llegada(familia),
              plano: salon,
            ),
            tamano: tamano,
          );
          expect(tester.takeException(), isNull);
          final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
          expect(vista.resaltadas, {12});
          expect(vista.hoja, salon.mesa(12)!.hoja);
          // El salón de la Normal tiene marcado el ingreso: va el camino,
          // entero porque la escena está quieta.
          expect(vista.ruta, isNotNull);
          expect(vista.progresoRuta, 1);
          // Lo de la llegada sigue estando.
          expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
          expect(find.text('10 sillas (8 + 2 extra)'), findsOneWidget);
          expect(find.text('1 más en camino'), findsOneWidget);
          // El plano va abajo, o a la derecha en una pantalla apaisada.
          final plano = tester.getRect(find.byType(PanelPlano));
          final nombreEn = tester.getRect(find.text('PÉREZ, JUAN MARTÍN'));
          if (tamano.width > tamano.height) {
            expect(plano.left, greaterThanOrEqualTo(nombreEn.right));
          } else {
            expect(plano.top, greaterThanOrEqualTo(nombreEn.bottom));
          }
        });
      }
    }

    testWidgets('sin plano, sin mesa o con un número que no está: como antes',
        (tester) async {
      for (final (llegada, plano) in [
        (_llegada(familia), null),
        (_llegada([filaDe('sosa')]), salon),
        (
          _llegada(
            [filaSuelta('i1', 'LÓPEZ, MARTA', mesa: '999')],
            ficha: const FichaTotem.particular(eventoParticular),
            cfg: _particular,
          ),
          salon,
        ),
      ]) {
        await _montar(
          tester,
          EscenaTotem(
            estilo: EstiloTotem.neon,
            cfg: _masivo,
            quieta: true,
            llegada: llegada,
            plano: plano,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(PanelPlano), findsNothing);
      }
    });

    testWidgets('el camino se dibuja de a poco después de la entrada',
        (tester) async {
      Future<double> progresoCon(DateTime empezo) async {
        await _montar(
          tester,
          EscenaTotem(
            estilo: EstiloTotem.neon,
            cfg: _masivo,
            llegada: _llegada(familia),
            claveLlegada: empezo,
            empezo: empezo,
            fin: empezo.add(const Duration(seconds: 7)),
            plano: salon,
          ),
        );
        await tester.pump(EscenaTotem.entrada);
        return tester.widget<VistaPlano>(find.byType(VistaPlano)).progresoRuta;
      }

      // La escena mide con el reloj de verdad: recién empezada, nada; a los
      // 3 s, entero.
      expect(await progresoCon(DateTime.now()), lessThan(0.5));
      expect(
        await progresoCon(DateTime.now().subtract(const Duration(seconds: 3))),
        1,
      );
    });

    testWidgets('en la espera no hay plano', (tester) async {
      await _montar(
        tester,
        EscenaTotem(
          estilo: EstiloTotem.gala,
          cfg: _masivo,
          quieta: true,
          plano: salon,
        ),
      );
      expect(find.byType(PanelPlano), findsNothing);
    });

    test('el tema del plano se arma una vez por apariencia y color', () {
      for (final e in EstiloTotem.values) {
        final a = temaPlanoDelTotem(e, const Color(0xFFD4AF37));
        expect(identical(a, temaPlanoDelTotem(e, const Color(0xFFD4AF37))),
            isTrue,
            reason: e.nombre);
        expect(a.resaltado, const Color(0xFFD4AF37));
        expect(a.divisiones, [const Color(0xFFD4AF37)]);
        expect(
          identical(a, temaPlanoDelTotem(e, const Color(0xFFFF8FB1))),
          isFalse,
        );
      }
      // Un color oscuro lleva el número claro, y uno claro, oscuro.
      expect(
        temaPlanoDelTotem(EstiloTotem.neon, const Color(0xFF1B1464))
            .resaltadoNumero,
        const Color(0xFFFFFFFF),
      );
      expect(
        temaPlanoDelTotem(EstiloTotem.neon, const Color(0xFFE8E3D3))
            .resaltadoNumero,
        const Color(0xFF1A1406),
      );
    });

    testWidgets('animada: el plano se arma una vez por llegada, no por cuadro',
        (tester) async {
      EscenaTotem.planosArmados = 0;
      final llegada = _llegada(familia);
      final clave = Object();
      await _montar(
        tester,
        EscenaTotem(
          estilo: EstiloTotem.neon,
          cfg: _masivo,
          llegada: llegada,
          claveLlegada: clave,
          plano: salon,
        ),
      );
      TemaPlano? tema;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final t = tester.widget<VistaPlano>(find.byType(VistaPlano)).tema;
        if (tema != null) expect(identical(t, tema), isTrue);
        tema = t;
      }
      expect(EscenaTotem.planosArmados, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('la foto', () {
    bool esDe<T extends ImageProvider>(Widget w) => w is Image && w.image is T;
    final conFoto = _masivo.copyWith(imagenUrl: 'https://ejemplo.test/foto.jpg');

    for (final estilo in EstiloTotem.values) {
      testWidgets('${estilo.nombre}: la recién elegida manda sobre la guardada',
          (tester) async {
        await _montar(
          tester,
          EscenaTotem(
            estilo: estilo,
            cfg: conFoto,
            foto: MemoryImage(fotoDePrueba),
            quieta: true,
          ),
        );
        expect(find.byWidgetPredicate(esDe<MemoryImage>), findsWidgets);
        expect(find.byWidgetPredicate(esDe<FotoGuardada>), findsNothing);
      });

      // Sección 5: la del evento, guardada en la PC, no la de internet.
      testWidgets('${estilo.nombre}: sin elegir, la guardada en la PC',
          (tester) async {
        await _montar(
          tester,
          EscenaTotem(estilo: estilo, cfg: conFoto, quieta: true),
        );
        expect(find.byWidgetPredicate(esDe<FotoGuardada>), findsWidgets);
        expect(find.byWidgetPredicate(esDe<NetworkImage>), findsNothing);
        expect(find.byWidgetPredicate(esDe<MemoryImage>), findsNothing);
      });
    }
  });

  testWidgets('si el fondo no carga, la escena se ve igual (con el degradé)',
      (tester) async {
    FondoTotem.olvidar();
    FondoTotem.cargar = (_) async => throw StateError('esta PC no puede');
    await tester.runAsync(FondoTotem.precargar);
    await _montar(
      tester,
      EscenaTotem(
        estilo: EstiloTotem.neon,
        cfg: _masivo,
        quieta: true,
        llegada: _llegada([filaDe('garcia')]),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(FondoTotem.tieneShader(EstiloTotem.neon), isFalse);
    expect(find.text('GARCÍA, BRUNO'), findsOneWidget);
  });

  testWidgets('animada: entra, se va y vuelve a la espera', (tester) async {
    final llegada = _llegada([filaDe('garcia')]);
    final clave = Object();
    Widget escena({ContenidoBienvenida? c, bool saliendo = false}) => EscenaTotem(
          estilo: EstiloTotem.gala,
          cfg: _masivo,
          llegada: c,
          claveLlegada: c == null ? null : clave,
          saliendo: saliendo,
        );
    await _montar(tester, escena());
    expect(find.text('GARCÍA, BRUNO'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: escena(c: llegada))),
    );
    await tester.pump(EscenaTotem.entrada);
    expect(find.text('GARCÍA, BRUNO'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: escena(c: llegada, saliendo: true))),
    );
    await tester.pump(EscenaTotem.salida);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: escena())));
    await tester.pump();
    expect(find.text('GARCÍA, BRUNO'), findsNothing);
    expect(find.text('2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
