// Las cuatro apariencias del tótem (`estilos/`): la espera y la llegada de
// cada una, en una pantalla vertical, una apaisada y una chica, sin desbordes,
// con lo que tiene que decir y sin lo que no.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_propio.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/features/totem/estilos/plano_del_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/features/totem/estilos/tu_fondo.dart';
import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/features/totem/services/cuadro_del_salon.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/services/foto_guardada.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/fondo_de_prueba.dart';
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
          // Las sillas ya no van en el salón (6.4.0): las ve la recepcionista.
          expect(find.textContaining('sillas'), findsNothing);
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
          ([filaDe('acosta')], 'ACOSTA, LUCÍA', 'sillas'),
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

  // El salón entero en un masivo sorteado (6.4.0, pedido del jefe el 4-nov):
  // en la espera, sin nadie; al llegar una familia, su nombre en grande y
  // después acomodado en el cuadro, con su mesa encendida y el camino.
  group('el salón en un masivo', () {
    final salon = ArmadosPredefinidos.normal2aPagina3();
    final familia = [filaDe('perez'), filaDe('perez', 1), filaDe('perez', 2)];
    double uDe(Size s) => math.min(s.width, s.height * 9 / 16) / 27;
    CuadroDelSalon cuadroDe(Size s, {TotemConfig cfg = _masivo}) =>
        CuadroDelSalon.para(
          salon,
          pantalla: s,
          u: uDe(s),
          elegido: LugarElegido.deClave(cfg.llegadaLugar),
        )!;

    /// Adentro, con un píxel de tolerancia por el redondeo.
    void adentro(Rect chico, Rect grande, String razon) {
      expect(chico.left, greaterThanOrEqualTo(grande.left - 1), reason: razon);
      expect(chico.top, greaterThanOrEqualTo(grande.top - 1), reason: razon);
      expect(chico.right, lessThanOrEqualTo(grande.right + 1), reason: razon);
      expect(chico.bottom, lessThanOrEqualTo(grande.bottom + 1), reason: razon);
    }

    for (final estilo in EstiloTotem.values) {
      for (final MapEntry(key: nombre, value: tamano) in _tamanos.entries) {
        testWidgets('${estilo.nombre}, pantalla $nombre: la espera con el '
            'salón entero y las frases en el cuadro', (tester) async {
          await _montar(
            tester,
            EscenaTotem(
              estilo: estilo,
              cfg: _masivo,
              quieta: true,
              plano: salon,
            ),
            tamano: tamano,
          );
          expect(tester.takeException(), isNull);
          final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
          expect(vista.resaltadas, isEmpty);
          expect(vista.ruta, isNull);
          expect(tester.widget<PanelPlano>(find.byType(PanelPlano)).pulsar,
              isFalse);
          for (final m in salon.mesas) {
            expect(vista.estado.info(m.numero).ocupantes, isEmpty);
          }
          final c = cuadroDe(tamano);
          expect(tester.getRect(find.byType(PanelPlano)), c.panel);
          // En una tele acostada el fondo del salón llega a los cuatro bordes
          // (pedido del usuario, 12-nov-2026); parada, no hay nada debajo del
          // panel. El dibujo no se mueve en ninguna de las dos.
          final completo = find.byKey(const Key('salon_a_pantalla_completa'));
          if (tamano.width > tamano.height * 1.2) {
            expect(tester.getRect(completo), Offset.zero & tamano,
                reason: 'acostada');
          } else {
            expect(completo, findsNothing, reason: 'parada');
          }
          // Adentro del salón (la pista) va resumido: el título entero.
          final enElSalon = c.lugar == LugarDelCuadro.pista ||
              c.lugar == LugarDelCuadro.hueco;
          for (final frase
              in enElSalon ? ['PROMOCIÓN 2026'] : ['2026', 'PROMOCIÓN']) {
            adentro(tester.getRect(find.text(frase)), c.cuadro, frase);
          }
          expect(find.byType(ResumenEnElSalon),
              enElSalon ? findsOneWidget : findsNothing);
        });

        testWidgets('${estilo.nombre}, pantalla $nombre: la llegada acomodada, '
            'con la mesa encendida y el camino', (tester) async {
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
          // Con el camino marcando la mesa, el borde del salón late.
          expect(tester.widget<PanelPlano>(find.byType(PanelPlano)).pulsar,
              isTrue);
          expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
          expect(find.textContaining('sillas'), findsNothing);
          expect(find.text('1 más en camino'), findsOneWidget);
          final c = cuadroDe(tamano);
          adentro(tester.getRect(find.text('PÉREZ, JUAN MARTÍN')), c.cuadro,
              'el nombre, en el cuadro');
        });
      }
    }

    testWidgets('en grande: el nombre al medio y el salón apagado, sin '
        'encender', (tester) async {
      const tamano = Size(1920, 1080);
      await _montar(
        tester,
        EscenaTotem(
          estilo: EstiloTotem.neon,
          cfg: _masivo,
          quieta: true,
          faseFija: FaseLlegada.grande,
          llegada: _llegada(familia),
          plano: salon,
        ),
        tamano: tamano,
      );
      expect(tester.takeException(), isNull);
      final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
      expect(vista.resaltadas, isEmpty);
      expect(vista.ruta, isNull);
      expect(tester.widget<PanelPlano>(find.byType(PanelPlano)).pulsar, isFalse);
      final c = cuadroDe(tamano);
      final nombreEn = tester.getRect(find.text('PÉREZ, JUAN MARTÍN'));
      expect(nombreEn.width, greaterThan(c.cuadro.width * 0.6),
          reason: 'en grande, mucho más que en el cuadro');
      final opacidad = tester
          .widget<Opacity>(find
              .ancestor(of: find.byType(PanelPlano), matching: find.byType(Opacity))
              .first)
          .opacity;
      expect(opacidad, closeTo(EscenaTotem.salonDetrasDelNombre, 0.01));
    });

    testWidgets('el salón no se mueve entre la espera y la llegada',
        (tester) async {
      await _montar(
        tester,
        EscenaTotem(estilo: EstiloTotem.gala, cfg: _masivo, quieta: true, plano: salon),
      );
      final enLaEspera = tester.getRect(find.byType(PanelPlano));
      await _montar(
        tester,
        EscenaTotem(
          estilo: EstiloTotem.gala,
          cfg: _masivo,
          quieta: true,
          llegada: _llegada(familia),
          plano: salon,
        ),
      );
      expect(tester.getRect(find.byType(PanelPlano)), enLaEspera);
    });

    testWidgets('el lugar que elige el jefe manda', (tester) async {
      const tamano = Size(1920, 1080);
      final cfg = _masivo.copyWith(llegadaLugar: 'derecha');
      await _montar(
        tester,
        EscenaTotem(
          estilo: EstiloTotem.cristal,
          cfg: cfg,
          quieta: true,
          llegada: _llegada(familia),
          plano: salon,
        ),
        tamano: tamano,
      );
      final c = cuadroDe(tamano, cfg: cfg);
      expect(c.cuadro.left, greaterThanOrEqualTo(c.panel.right));
      expect(tester.getRect(find.byType(PanelPlano)), c.panel);
      adentro(tester.getRect(find.text('PÉREZ, JUAN MARTÍN')), c.cuadro,
          'el nombre, a la derecha');
    });

    testWidgets('sin plano, como siempre: sin salón', (tester) async {
      for (final llegada in [null, _llegada(familia)]) {
        await _montar(
          tester,
          EscenaTotem(
            estilo: EstiloTotem.neon,
            cfg: _masivo,
            quieta: true,
            llegada: llegada,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(PanelPlano), findsNothing);
      }
    });

    testWidgets('sin mesa o con un número que no está: el salón, sin encender',
        (tester) async {
      for (final llegada in [
        _llegada([filaDe('sosa')]),
        _llegada(
          [filaSuelta('i1', 'LÓPEZ, MARTA', mesa: '999')],
          ficha: const FichaTotem.particular(eventoParticular),
          cfg: _particular,
        ),
      ]) {
        await _montar(
          tester,
          EscenaTotem(
            estilo: EstiloTotem.neon,
            cfg: _masivo,
            quieta: true,
            llegada: llegada,
            plano: salon,
          ),
        );
        expect(tester.takeException(), isNull);
        final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
        expect(vista.resaltadas, isEmpty);
        expect(vista.ruta, isNull);
      }
    });

    testWidgets('animada: el nombre en grande sus segundos, después se '
        'enciende la mesa y se dibuja el camino', (tester) async {
      Future<VistaPlano> conEmpezo(DateTime empezo) async {
        await _montar(
          tester,
          EscenaTotem(
            estilo: EstiloTotem.neon,
            cfg: _masivo,
            llegada: _llegada(familia),
            claveLlegada: empezo,
            empezo: empezo,
            fin: empezo.add(const Duration(seconds: 12)),
            plano: salon,
          ),
        );
        await tester.pump(EscenaTotem.entrada);
        await tester.pump(EscenaTotem.acomodo);
        return tester.widget<VistaPlano>(find.byType(VistaPlano));
      }

      // La escena mide con el reloj de verdad: recién empezada, en grande.
      final recien = await conEmpezo(DateTime.now());
      expect(recien.resaltadas, isEmpty);
      // Pasados los 4 s del nombre y el acomodo, encendida y con el camino.
      final despues = await conEmpezo(
        DateTime.now().subtract(const Duration(seconds: 7)),
      );
      expect(despues.resaltadas, {12});
      expect(despues.progresoRuta, 1);
    });

    test('el salón es claro, en las cinco, con el color del evento', () {
      for (final e in EstiloTotem.values) {
        final a = temaPlanoDelTotem(e, const Color(0xFFD4AF37));
        expect(identical(a, temaPlanoDelTotem(e, const Color(0xFFD4AF37))),
            isTrue,
            reason: e.nombre);
        expect(a.fondo.computeLuminance(), greaterThan(0.8), reason: e.nombre);
        expect(a.mesaRelleno, const Color(0xFFFFFFFF));
        expect(a.numeroVacia.computeLuminance(), lessThan(0.05));
        expect(a.escalaNumero, greaterThan(1));
        expect(a.resaltado, const Color(0xFFD4AF37));
        expect(a.divisiones, [const Color(0xFFD4AF37)]);
        // El dorado como línea sobre el papel claro no se lee: va oscurecido.
        expect(a.ruta.computeLuminance(),
            lessThan(const Color(0xFFD4AF37).computeLuminance()));
        expect(
          identical(a, temaPlanoDelTotem(e, const Color(0xFFFF8FB1))),
          isFalse,
        );
        // El de antes, vestido como la apariencia, sigue para comparar.
        final oscuro = temaPlanoDelTotem(e, const Color(0xFFD4AF37), claro: false);
        expect(identical(oscuro, a), isFalse, reason: e.nombre);
        expect(oscuro.estilo, isNot(EstiloPlano.arquitecto), reason: e.nombre);
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

    testWidgets('animada: se arma una vez por llegada y el salón no cambia de '
        'cuadro a cuadro', (tester) async {
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
      Object? estado;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final v = tester.widget<VistaPlano>(find.byType(VistaPlano));
        if (tema != null) expect(identical(v.tema, tema), isTrue);
        if (estado != null) expect(identical(v.estado, estado), isTrue);
        tema = v.tema;
        estado = v.estado;
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

  group('"Tu fondo"', () {
    late Uint8List png;
    final fiesta = ArmadosPredefinidos.normal2aPagina3();
    final familia = [filaDe('perez'), filaDe('perez', 1), filaDe('perez', 2)];

    setUpAll(() async => png = await pngDePrueba());
    setUp(FondoPropio.olvidar);
    tearDown(FondoPropio.olvidar);

    /// Deja que la imagen se lea (es de verdad, no de mentira).
    Future<void> esperarFondo(WidgetTester tester) async {
      await tester.runAsync(FondoPropio.precargar);
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final f = find.byType(FondoPropio);
        if (f.evaluate().isNotEmpty && tester.widget<FondoPropio>(f).imagen != null) {
          return;
        }
      }
    }

    EscenaTotem escena(
      TotemConfig cfg, {
      ContenidoBienvenida? llegada,
      String? qr,
      bool quieta = true,
      int enCamino = 0,
      ImageProvider? fondo,
    }) =>
        EscenaTotem(
          estilo: EstiloTotem.tuFondo,
          respaldo: EstiloTotem.neon,
          cfg: cfg,
          fondo: fondo ?? MemoryImage(png),
          llegada: llegada,
          qrUrl: qr,
          quieta: quieta,
          enCamino: enCamino,
        );

    for (final MapEntry(key: nombre, value: tamano) in _tamanos.entries) {
      testWidgets('la espera y la familia que llega, en pantalla $nombre',
          (tester) async {
        await _montar(tester, escena(conTuFondo(_masivo)), tamano: tamano);
        await esperarFondo(tester);
        expect(tester.takeException(), isNull);
        expect(tester.widget<FondoPropio>(find.byType(FondoPropio)).imagen,
            isNotNull);
        expect(find.byType(FondoTotem), findsNothing);
        expect(find.text('2026'), findsOneWidget);
        expect(find.text('PROMOCIÓN'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);

        await _montar(
          tester,
          escena(
            conTuFondo(_masivo),
            enCamino: 2,
            llegada: _llegada(familia),
          ),
          tamano: tamano,
        );
        await esperarFondo(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('¡Bienvenidos!'), findsOneWidget);
        expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
        expect(find.text('con GÓMEZ, ANA y PÉREZ, LUIS'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        expect(find.textContaining('sillas'), findsNothing);
        expect(find.text('Tusa · Karol G'), findsOneWidget);
        expect(find.text('2 más en camino'), findsOneWidget);
      });
    }

    testWidgets('un particular, con su QR', (tester) async {
      await _montar(tester, escena(conTuFondo(_particular), qr: _qr));
      await esperarFondo(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('ESCANEÁ PARA INGRESAR'), findsOneWidget);
    });

    testWidgets('cada animación y cada efecto se mueven sin romper nada',
        (tester) async {
      for (final a in AnimacionFondo.values) {
        await _montar(
          tester,
          escena(
            conTuFondo(
              _masivo,
              animacion: a.clave,
              efectos: [for (final e in EfectoFondo.values) e.clave],
            ),
            quieta: false,
          ),
        );
        await esperarFondo(tester);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(tester.takeException(), isNull, reason: a.nombre);
      }
    });

    testWidgets('con una imagen clara y sin oscurecer, el texto va oscuro',
        (tester) async {
      await _montar(
        tester,
        escena(conTuFondo(_masivo, oscurecer: 0, luz: 92, efectos: ['bokeh'])),
      );
      await esperarFondo(tester);
      final titulo = tester.widget<Text>(find.text('2026'));
      expect(titulo.style!.color!.computeLuminance(), lessThan(0.2));

      await _montar(tester, escena(conTuFondo(_masivo)));
      await esperarFondo(tester);
      final claro = tester.widget<Text>(find.text('2026'));
      expect(claro.style!.color!.computeLuminance(), greaterThan(0.5));
    });

    testWidgets('si la imagen no está ni baja, la apariencia del tipo',
        (tester) async {
      await _montar(
        tester,
        escena(
          conTuFondo(_masivo),
          fondo: MemoryImage(Uint8List.fromList(const [1, 2, 3])),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(FondoPropio), findsNothing);
      expect(tester.widget<FondoTotem>(find.byType(FondoTotem)).estilo,
          EstiloTotem.neon);
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('sin fondo cargado, directamente la del tipo', (tester) async {
      await _montar(
        tester,
        EscenaTotem(
          estilo: EstiloTotem.tuFondo,
          respaldo: EstiloTotem.gala,
          cfg: _masivo.copyWith(estilo: 'tu_fondo'),
          quieta: true,
        ),
      );
      expect(find.byType(FondoPropio), findsNothing);
      expect(tester.widget<FondoTotem>(find.byType(FondoTotem)).estilo,
          EstiloTotem.gala);
    });

    testWidgets('la mesa en el plano va en el brillo de la imagen',
        (tester) async {
      final cfg = conTuFondo(_masivo);
      await _montar(
        tester,
        EscenaTotem(
          estilo: EstiloTotem.tuFondo,
          cfg: cfg,
          fondo: MemoryImage(png),
          quieta: true,
          llegada: _llegada(familia),
          plano: fiesta,
        ),
      );
      await esperarFondo(tester);
      expect(tester.takeException(), isNull);
      final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
      expect(vista.resaltadas, {12});
      expect(vista.tema.resaltado, cfg.fondoPaleta![0]);
      expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
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
        for (var i = 1; i <= 5; i++) filaSuelta('a$i', ficha.de('a$i')!.nombre),
      ];
      for (final tamano in [const Size(360, 640), const Size(1920, 1080)]) {
        await _montar(
          tester,
          escena(
            conTuFondo(_masivo),
            enCamino: 3,
            llegada: _llegada(personas, ficha: ficha),
          ),
          tamano: tamano,
        );
        await esperarFondo(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('128-129'), findsOneWidget);
        expect(find.textContaining('sillas'), findsNothing);
      }
    });
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
