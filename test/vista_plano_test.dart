import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';

Widget _vista({
  required ArmadoSalon armado,
  required EstadoPlano estado,
  required TemaPlano tema,
  String hoja = 'A',
  Size tam = const Size(780, 560),
  Set<int> resaltadas = const {},
  int? seleccionada,
  bool animar = false,
  ValueChanged<int>? onTapMesa,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: tam.width,
          height: tam.height,
          child: VistaPlano(
            armado: armado,
            hoja: hoja,
            tema: tema,
            estado: estado,
            resaltadas: resaltadas,
            seleccionada: seleccionada,
            animar: animar,
            onTapMesa: onTapMesa,
          ),
        ),
      ),
    );

double _distancia(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Sin esto el plano se dibuja con la letra de prueba (cuadraditos), y un
  // apellido que no entra o una familia de letra mal escrita pasan igual.
  setUpAll(cargarFuentesPlano);

  final armado = ArmadosPredefinidos.normal2aPagina3();
  final estado = EstadoPlano.desde(
    armado: armado,
    ocupantes: const [
      OcupantePlano(
        id: 'a',
        nombre: 'GÓMEZ, SOFÍA',
        numeros: [31, 32],
        division: '5° A',
        sillasExtraPorMesa: {31: 2},
      ),
    ],
    libres: const {78},
  );

  group('NivelDetalle', () {
    test('una miniatura no lleva números ni sillas', () {
      final n = NivelDetalle.para(5);
      expect(n.numeros, isFalse);
      expect(n.sillas, isFalse);
      expect(n.apellidos, isFalse);
    });

    test('la pantalla lleva números y sillas, sin apellidos', () {
      final n = NivelDetalle.para(17);
      expect(n.numeros, isTrue);
      expect(n.sillas, isTrue);
      expect(n.apellidos, isFalse);
    });

    test('con zoom aparecen los apellidos', () {
      expect(NivelDetalle.para(30).apellidos, isTrue);
    });
  });

  test('un estilo guardado que no existe no se rompe: pide elegir', () {
    expect(EstiloPlano.deClave('neon'), EstiloPlano.neon);
    expect(EstiloPlano.deClave('cristal'), isNull);
    expect(EstiloPlano.deClave(null), isNull);
  });

  group('las letras del plano', () {
    test('lo que carga cargarFuentesPlano es lo que declara pubspec.yaml',
        () async {
      final manifiesto =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      final declaradas = {
        for (final f in manifiesto.cast<Map<String, dynamic>>())
          f['family'] as String: [
            for (final a in (f['fonts'] as List).cast<Map<String, dynamic>>())
              a['asset'] as String,
          ],
      };
      for (final e in archivosFuentesPlano.entries) {
        expect(declaradas[e.key], e.value, reason: 'familia ${e.key}');
      }
    });

    test('cada estilo usa una familia que existe', () {
      for (final e in EstiloPlano.values) {
        expect(
          archivosFuentesPlano.keys,
          contains(TemaPlano.de(e).fuente),
          reason: e.name,
        );
      }
    });
  });

  group('la paleta de cada estilo', () {
    for (final e in EstiloPlano.values) {
      final tema = TemaPlano.de(e);

      test('${e.name}: ninguna división repite color', () {
        expect(tema.divisiones.toSet().length, tema.divisiones.length);
      });

      test('${e.name}: el número de cada división tiene su color', () {
        final numeros = tema.numeroDivision;
        if (numeros != null) {
          expect(numeros.length, tema.divisiones.length);
        }
      });
    }

    // Gala y Neón distinguen la división solo por el color (Arquitecto además
    // rellena la mesa con tonos pastel, que entre sí se parecen a propósito).
    for (final e in const [EstiloPlano.gala, EstiloPlano.neon]) {
      final tema = TemaPlano.de(e);

      test('${e.name}: las divisiones no se confunden entre sí', () {
        for (var i = 0; i < tema.divisiones.length; i++) {
          for (var j = i + 1; j < tema.divisiones.length; j++) {
            expect(
              _distancia(tema.divisiones[i], tema.divisiones[j]),
              greaterThanOrEqualTo(60),
              reason: 'divisiones ${i + 1} y ${j + 1}',
            );
          }
        }
      });

      test('${e.name}: ninguna división se confunde con otra marca', () {
        final reservados = {
          'sin división': tema.mesaBorde,
          'resaltado': tema.resaltado,
          'pasto': tema.pasto,
          'conflicto': tema.conflicto,
        };
        for (var i = 0; i < tema.divisiones.length; i++) {
          for (final r in reservados.entries) {
            expect(
              _distancia(tema.divisiones[i], r.value),
              greaterThanOrEqualTo(60),
              reason: 'división ${i + 1} y ${r.key}',
            );
          }
        }
      });
    }

    test('neón: los apellidos no van en el color de una división', () {
      expect(TemaPlano.neon.divisiones, isNot(contains(TemaPlano.neon.tituloSuave)));
    });
  });

  group('la grilla', () {
    test('con el paso de un metro, hay una línea por metro', () {
      final paso = armado.aUnidades(1);
      expect(paso, closeTo(52.5, 1e-9));
      final l = lineasGrilla(const Rect.fromLTRB(0, 0, 210, 100), paso: paso);
      // 210 unidades son 4 m: cinco líneas, con la del borde incluida.
      expect(l.xs.length, 5);
      for (final (i, x) in l.xs.indexed) {
        expect(x, closeTo(i * 52.5, 1e-6));
      }
      expect(l.ys.length, 2);
    });

    test('arranca en el múltiplo de 50 anterior y cubre todo lo visible', () {
      final l = lineasGrilla(const Rect.fromLTRB(-30, 120, 260, 310));
      expect(l.xs, [-50, 0, 50, 100, 150, 200, 250]);
      expect(l.ys, [100, 150, 200, 250, 300]);
    });

    test('un borde que cae justo en un múltiplo no suma una línea de más', () {
      final l = lineasGrilla(const Rect.fromLTRB(100, 0, 200, 50));
      expect(l.xs, [100, 150, 200]);
      expect(l.ys, [0, 50]);
    });
  });

  group('el lugar del apellido', () {
    const caja = RectPlano(0, 0, 1000, 800);

    test('va debajo de la mesa, centrado y con ancho tope', () {
      final f = franjaApellido(const Offset(500, 400), 35, caja, conSillas: false);
      expect(f.width, closeTo(35 * anchoApellidoEnRadios, 0.001));
      expect(f.center.dx, closeTo(500, 0.001));
      expect(f.top, closeTo(400 + 35 + 6, 0.001));
    });

    test('con sillas, baja para no pisarlas', () {
      final sin = franjaApellido(const Offset(500, 400), 30, caja, conSillas: false);
      final con = franjaApellido(const Offset(500, 400), 30, caja, conSillas: true);
      expect(con.top, greaterThan(sin.top));
    });

    test('en el borde de la hoja se corre para no salirse', () {
      final izq = franjaApellido(const Offset(10, 400), 35, caja, conSillas: false);
      expect(izq.left, 0);
      final der = franjaApellido(const Offset(995, 400), 35, caja, conSillas: false);
      expect(der.right, closeTo(1000, 0.001));
    });

    test('solo la mesa principal lleva apellido, y solo con zoom', () {
      final conZoom = NivelDetalle.para(30);
      final sinZoom = NivelDetalle.para(17);
      expect(familiaConApellido(estado.info(31), conZoom)?.apellido, 'GÓMEZ');
      expect(familiaConApellido(estado.info(32), conZoom), isNull);
      expect(familiaConApellido(estado.info(31), sinZoom), isNull);
      expect(familiaConApellido(estado.info(1), conZoom), isNull);
    });

    test('una mesa fijada lleva el apellido de para quién es', () {
      final e = EstadoPlano.desde(
        armado: armado,
        fijadas: const {
          60: OcupantePlano(id: 'f', nombre: 'RÍOS, MATEO', numeros: []),
        },
      );
      expect(
        familiaConApellido(e.info(60), NivelDetalle.para(30))?.apellido,
        'RÍOS',
      );
    });
  });

  group('lo resaltado es por hoja', () {
    final dosHojas = ArmadosPredefinidos.normal2a2b();

    test('una mesa de la hoja B no cuenta en la A', () {
      expect(mesasEnHoja(dosHojas, 'A', {1, 2, 102}), {1, 2});
      expect(mesasEnHoja(dosHojas, 'B', {1, 2, 102}), {102});
      expect(mesasEnHoja(dosHojas, 'A', {999}), isEmpty);
    });
  });

  group('tocar una mesa', () {
    // Entra en la pantalla de prueba (800 × 600), así no se achica.
    const tam = Size(780, 560);
    final encuadre = EncuadrePlano.de(armado.hoja('A')!.caja, tam);
    final m31 = armado.mesa(31)!;
    final centro31 = encuadre.aPantalla(Offset(m31.x, m31.y));

    test('el centro de la 31 es la 31; un hueco no es ninguna', () {
      expect(mesaEnPunto(armado, 'A', tam, centro31), 31);
      // Entre la 31 y la barra no hay mesas.
      final hueco = encuadre.aPantalla(Offset(m31.x - 150, m31.y));
      expect(mesaEnPunto(armado, 'A', tam, hueco), isNull);
    });

    testWidgets('la vista avisa qué mesa se tocó', (tester) async {
      final tocadas = <int>[];
      await tester.pumpWidget(
        _vista(
          armado: armado,
          estado: estado,
          tema: TemaPlano.arquitecto,
          onTapMesa: tocadas.add,
        ),
      );
      final origen = tester.getTopLeft(find.byType(VistaPlano));
      await tester.tapAt(origen + centro31);
      await tester.tapAt(origen + encuadre.aPantalla(Offset(m31.x - 150, m31.y)));
      expect(tocadas, [31]);
    });

    testWidgets('en la hoja B se tocan las mesas de la B, no las de la A',
        (tester) async {
      final dosHojas = ArmadosPredefinidos.normal2a2b();
      final m102 = dosHojas.mesa(102)!;
      expect(m102.hoja, 'B');
      final encuadreB = EncuadrePlano.de(dosHojas.hoja('B')!.caja, tam);
      final punto = encuadreB.aPantalla(Offset(m102.x, m102.y));

      final tocadas = <int>[];
      await tester.pumpWidget(
        _vista(
          armado: dosHojas,
          hoja: 'B',
          estado: EstadoPlano.vacio,
          tema: TemaPlano.gala,
          onTapMesa: tocadas.add,
        ),
      );
      await tester.tapAt(tester.getTopLeft(find.byType(VistaPlano)) + punto);
      expect(tocadas, [102]);
    });
  });

  for (final e in EstiloPlano.values) {
    for (final tam in const [Size(900, 600), Size(1920, 1080), Size(160, 110)]) {
      testWidgets('${e.name} se dibuja sin errores en ${tam.width}×${tam.height}',
          (tester) async {
        tester.view.physicalSize = tam;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _vista(
            armado: armado,
            estado: estado,
            tema: TemaPlano.de(e),
            tam: tam,
            resaltadas: const {31, 32},
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '${e.name} dibuja fijada, conflicto, libre, pasto, apellido largo y '
        'seleccionada', (tester) async {
      const tam = Size(1920, 1080);
      tester.view.physicalSize = tam;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tecnica = ArmadosPredefinidos.tecnica1a1b();
      final pasto = tecnica.pasto.where((n) => tecnica.mesa(n)!.hoja == 'A');
      const fija = OcupantePlano(
        id: 'f',
        nombre: 'RÍOS, MATEO',
        numeros: [],
        division: '6° B',
      );
      final completo = EstadoPlano.desde(
        armado: tecnica,
        ocupantes: [
          const OcupantePlano(
            id: 'a',
            nombre: 'FERNÁNDEZ DE LA CONCEPCIÓN, MARÍA',
            numeros: [1, 2],
            division: '6° A',
            sillasExtraPorMesa: {1: 2, 2: 1},
          ),
          const OcupantePlano(id: 'b', nombre: 'SOSA, LUZ', numeros: [5]),
          const OcupantePlano(id: 'c', nombre: 'VEGA, ANA', numeros: [5, 6]),
          OcupantePlano(
            id: 'p',
            nombre: 'PAREDES, IVÁN',
            numeros: [pasto.first],
            division: '6° C',
          ),
          const OcupantePlano(id: 'd', nombre: 'ORTIZ, BRUNO', numeros: [9]),
        ],
        libres: const {8, 9},
        fijadas: const {3: fija, 4: fija},
      );
      for (final hoja in const ['A', 'B']) {
        await tester.pumpWidget(
          _vista(
            armado: tecnica,
            hoja: hoja,
            estado: completo,
            tema: TemaPlano.de(e),
            tam: tam,
            resaltadas: const {1, 2},
            // Una mesa vacía seleccionada.
            seleccionada: 12,
          ),
        );
        expect(tester.takeException(), isNull, reason: 'hoja $hoja');
      }
    });
  }

  group('el plano con medidas', () {
    final hecho = ArmarAMedida.armar(
      const OpcionesAMedida(
        playon: PlayonReal.costaSurubi,
        cantidad: 132,
        partirEnFila: 6,
      ),
    ).armado;
    final conFamilias = EstadoPlano.desde(
      armado: hecho,
      ocupantes: const [
        OcupantePlano(
          id: 'a',
          nombre: 'GÓMEZ, SOFÍA',
          numeros: [12, 13],
          division: '5° A',
          sillasExtraPorMesa: {12: 2, 13: 1},
        ),
        // Sin división: las sillas extra van en el color neutro.
        OcupantePlano(
          id: 'b',
          nombre: 'SOSA, LUZ',
          numeros: [40],
          sillasExtraPorMesa: {40: 2},
        ),
      ],
    );

    for (final e in EstiloPlano.values) {
      for (final tam in const [Size(1400, 1225), Size(900, 600), Size(160, 110)]) {
        testWidgets(
            '${e.name}: borde, regla, medidas y lugares en '
            '${tam.width}×${tam.height}', (tester) async {
          tester.view.physicalSize = tam;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          for (final hoja in const ['A', 'B']) {
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: VistaPlano(
                  armado: hecho,
                  hoja: hoja,
                  tema: TemaPlano.de(e),
                  estado: conFamilias,
                  animar: false,
                  mostrarRegla: true,
                  mostrarMedidas: true,
                  lugares: const MedidasPlano(),
                ),
              ),
            );
            expect(tester.takeException(), isNull, reason: 'hoja $hoja');
          }
        });
      }
    }

    testWidgets('en un armado del Canva la regla y los lugares no rompen',
        (tester) async {
      for (final e in EstiloPlano.values) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: VistaPlano(
              armado: armado,
              hoja: 'A',
              tema: TemaPlano.de(e),
              estado: estado,
              animar: false,
              mostrarRegla: true,
              // No tiene borde: no hay medidas que escribir.
              mostrarMedidas: true,
              lugares: const MedidasPlano(),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: e.name);
      }
    });

    testWidgets('todo va en el mismo dibujo: no suma capas', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: VistaPlano(
            armado: hecho,
            hoja: 'A',
            tema: TemaPlano.arquitecto,
            estado: EstadoPlano.vacio,
            animar: false,
            mostrarRegla: true,
            mostrarMedidas: true,
            lugares: const MedidasPlano(),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    test('cambiar la regla, las medidas o los lugares vuelve a dibujar', () {
      PintorPlano pintor({
        bool regla = false,
        bool cotas = false,
        MedidasPlano? lugares,
      }) =>
          PintorPlano(
            armado: hecho,
            hoja: 'A',
            tema: TemaPlano.gala,
            estado: conFamilias,
            regla: regla,
            cotas: cotas,
            lugares: lugares,
          );
      final base = pintor();
      expect(pintor().shouldRepaint(base), isFalse);
      expect(pintor(regla: true).shouldRepaint(base), isTrue);
      expect(pintor(cotas: true).shouldRepaint(base), isTrue);
      expect(pintor(lugares: const MedidasPlano()).shouldRepaint(base), isTrue);
      // Las mismas medidas, en otro objeto, no.
      expect(
        pintor(lugares: const MedidasPlano(lugarMesaM: 2.2)).shouldRepaint(
          pintor(lugares: const MedidasPlano(lugarMesaM: 2.2)),
        ),
        isFalse,
      );
    });
  });

  testWidgets('una hoja que no existe dibuja solo el fondo', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: VistaPlano(
          armado: armado,
          hoja: 'Z',
          tema: TemaPlano.gala,
          estado: EstadoPlano.vacio,
          animar: false,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('el pulso', () {
    testWidgets('sin nada resaltado, la vista queda quieta', (tester) async {
      await tester.pumpWidget(
        _vista(
          armado: armado,
          estado: estado,
          tema: TemaPlano.gala,
          animar: true,
        ),
      );
      // Si el pulso corriera, esto no terminaría nunca.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('lo resaltado en la otra hoja no mueve esta', (tester) async {
      await tester.pumpWidget(
        _vista(
          armado: ArmadosPredefinidos.normal2a2b(),
          hoja: 'A',
          estado: EstadoPlano.vacio,
          tema: TemaPlano.neon,
          resaltadas: const {102},
          animar: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('con algo resaltado corre, y se frena al sacarlo',
        (tester) async {
      await tester.pumpWidget(
        _vista(
          armado: armado,
          estado: estado,
          tema: TemaPlano.gala,
          resaltadas: const {31},
          animar: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        _vista(
          armado: armado,
          estado: estado,
          tema: TemaPlano.gala,
          animar: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('prender, apagar y volver a prender no rompe', (tester) async {
      for (final animar in const [true, false, true, false, true]) {
        await tester.pumpWidget(
          _vista(
            armado: armado,
            estado: estado,
            tema: TemaPlano.arquitecto,
            resaltadas: const {31},
            animar: animar,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: 'animar: $animar');
        expect(tester.hasRunningAnimations, animar);
      }
      // Se apaga antes de terminar, para no dejar un ticker corriendo.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
