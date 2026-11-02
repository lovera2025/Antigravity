// Las familias con adicional en el plano (etapa 5 de
// docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md): juntas con una cápsula, separadas con un
// aro punteado y la otra mesa. Sin base ni pantalla.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/familias_en_el_plano.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/imprimir_plano_dialog.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno _familia(String id, List<int> mesas, {int extras = 0}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

double _contraste(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  final salon = ArmarAMedida.acomodar(
    ArmarAMedida.vacio(
      const PlayonReal(frenteM: 30, fondoM: 30, profundidadM: 40),
    ),
    cantidad: 60,
  ).armado;

  FamiliasEnElPlano de(
    List<ContratoAlumno> alumnos, {
    ArmadoSalon? armado,
    ConfigPlano config = ConfigPlano.vacia,
  }) =>
      PlanoDeLaFiesta.desde(
        armado: armado ?? salon,
        config: config,
        alumnos: alumnos,
      ).familias;

  test('una mesa: nada', () {
    final f = de([_familia('a', [5])]);
    expect(f.hayAlguna, isFalse);
    expect(f.marcas, isEmpty);
    expect(f.capsulas, isEmpty);
  });

  test('dos pegadas: juntas, con su cápsula, P en la principal y A en la otra', () {
    final f = de([_familia('a', [5, 6], extras: 1)]);
    expect(f.hayJuntas, isTrue);
    expect(f.haySeparadas, isFalse);
    expect(f.capsulas, [[5, 6]]);
    expect(f.marcas[5]!.principal, isTrue);
    expect(f.marcas[6]!.principal, isFalse);
    expect(f.marcas[5]!.separada, isFalse);
    expect(f.marcas[5]!.otra, isNull);
  });

  test('tres que doblan de fila: juntas, siguiendo la serpentina', () {
    // Busca tres números seguidos con el del medio al final de la fila.
    int? desde;
    for (var n = 1; n < 58; n++) {
      if (salon.mesa(n)!.y == salon.mesa(n + 1)!.y &&
          salon.mesa(n + 1)!.y != salon.mesa(n + 2)!.y &&
          salon.pegadas(n, n + 1) &&
          salon.pegadas(n + 1, n + 2)) {
        desde = n;
        break;
      }
    }
    final n = desde!;
    final f = de([_familia('a', [n, n + 1, n + 2], extras: 2)]);
    expect(f.hayJuntas, isTrue);
    expect(f.capsulas, [[n, n + 1, n + 2]]);
  });

  test('dos lejos: separadas, sin cápsula, y cada una dice la otra', () {
    final f = de([_familia('a', [5, 30], extras: 1)]);
    expect(f.haySeparadas, isTrue);
    expect(f.hayJuntas, isFalse);
    expect(f.capsulas, isEmpty);
    expect(f.marcas[5]!.separada, isTrue);
    expect(f.marcas[5]!.otra, 30);
    expect(f.marcas[30]!.otra, 5);
  });

  test('tres con una lejos: la cápsula en las dos y el aro en las tres', () {
    final f = de([_familia('a', [5, 6, 30], extras: 2)]);
    expect(f.capsulas, [[5, 6]]);
    for (final n in [5, 6, 30]) {
      expect(f.marcas[n]!.separada, isTrue, reason: '$n');
    }
    expect(f.marcas[5]!.otra, 30);
    expect(f.marcas[6]!.otra, 30);
    expect(f.marcas[30]!.otra, 5);
  });

  test('un número seguido con un salto en el medio cuenta como separada', () {
    final corte = salon.cortes.first;
    final f = de([_familia('a', [corte, corte + 1], extras: 1)]);
    expect(f.haySeparadas, isTrue);
  });

  test('en un salón de dos hojas, la flecha cruza de hoja', () {
    final dos = ArmadosPredefinidos.todos.firstWhere((a) => a.hojas.length > 1);
    final enA = dos.mesasDeHoja(dos.hojas.first.id).first.numero;
    final enB = dos.mesasDeHoja(dos.hojas.last.id).first.numero;
    final f = de([_familia('a', [enA, enB], extras: 1)], armado: dos);
    expect(f.marcas[enA]!.otra, enB);
    expect(f.marcas[enB]!.otra, enA);
  });

  test('en el pasto también', () {
    final tecnica = ArmadosPredefinidos.tecnica1a1b();
    final pasto = tecnica.pasto.toList()..sort();
    final f = de(
      [_familia('a', [pasto[0], pasto[1]], extras: 1)],
      armado: tecnica,
    );
    expect(f.hayAlguna, isTrue);
  });

  test('antes del sorteo, con las fijadas', () {
    const config = ConfigPlano(
      fijadas: {
        5: MesaFijada(alumnoId: 'a'),
        30: MesaFijada(alumnoId: 'a'),
      },
    );
    final sinMesa = ContratoAlumno(
      id: 'a',
      eventoId: 'e',
      nombreAlumno: 'A, ALUMNO',
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      cursoDivision: '5° A',
    );
    final f = de([sinMesa], config: config);
    expect(f.haySeparadas, isTrue);
    expect(f.marcas[5]!.otra, 30);
  });

  test('una mesa que el armado no tiene no se marca', () {
    final f = de([_familia('a', [5, 900], extras: 1)]);
    expect(f.marcas, isEmpty);
  });

  test('dos familias no se mezclan', () {
    final f = de([
      _familia('a', [5, 6], extras: 1),
      _familia('b', [10]),
      _familia('c', [20, 40], extras: 1),
    ]);
    expect(f.capsulas, [[5, 6]]);
    expect(f.hayJuntas, isTrue);
    expect(f.haySeparadas, isTrue);
    expect(f.marcas.containsKey(10), isFalse);
  });

  test('en los tres estilos, la marca se lee sobre el fondo', () {
    for (final e in EstiloPlano.values) {
      final t = TemaPlano.de(e);
      expect(_contraste(t.marcaFamilia, t.fondo), greaterThanOrEqualTo(4.5),
          reason: e.name);
    }
  });

  group('en la pantalla', () {
    final alumnos = [
      _familia('a', [5, 6], extras: 1),
      _familia('c', [20, 40], extras: 1),
      _familia('b', [10]),
    ];

    Future<void> montar(WidgetTester tester, List<ContratoAlumno> quienes) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlanoEventoCuerpo(
            plano: PlanoDeLaFiesta.desde(
              armado: salon,
              config: ConfigPlano.vacia,
              alumnos: quienes,
            ),
            estilo: EstiloPlano.arquitecto,
            alumnos: quienes,
          ),
        ),
      ));
      await tester.pump();
    }

    VistaPlano vista(WidgetTester tester) =>
        tester.widget<VistaPlano>(find.byType(VistaPlano));

    testWidgets('prendido de entrada, con su leyenda; se apaga con la casilla',
        (tester) async {
      await montar(tester, alumnos);
      expect(vista(tester).familias, isNotNull);
      expect(find.byKey(const Key('leyenda_juntas')), findsOneWidget);
      expect(find.byKey(const Key('leyenda_separadas')), findsOneWidget);

      await tester.tap(find.byKey(const Key('familias_adicional')));
      await tester.pump();
      expect(vista(tester).familias, isNull);
      expect(find.byKey(const Key('leyenda_juntas')), findsNothing);
    });

    testWidgets('la leyenda dice solo lo que hay', (tester) async {
      await montar(tester, [_familia('a', [5, 6], extras: 1)]);
      expect(find.byKey(const Key('leyenda_juntas')), findsOneWidget);
      expect(find.byKey(const Key('leyenda_separadas')), findsNothing);
    });

    testWidgets('sin familias con adicional no sale la casilla', (tester) async {
      await montar(tester, [_familia('b', [10])]);
      expect(find.byKey(const Key('familias_adicional')), findsNothing);
    });

    testWidgets('tocar una mesa de una familia separada resalta también la otra',
        (tester) async {
      await montar(tester, alumnos);
      vista(tester).onTapMesa!(20);
      await tester.pump();
      expect(vista(tester).resaltadas, {20, 40});
    });

    for (final estilo in EstiloPlano.values) {
      testWidgets('se dibuja en ${estilo.name}, en color y sin apellidos',
          (tester) async {
        final plano = PlanoDeLaFiesta.desde(
          armado: salon,
          config: ConfigPlano.vacia,
          alumnos: alumnos,
        );
        for (final tam in [const Size(1500, 1000), const Size(200, 140)]) {
          await tester.pumpWidget(MaterialApp(
            home: Center(
              child: SizedBox.fromSize(
                size: tam,
                child: VistaPlano(
                  armado: salon,
                  hoja: salon.hojas.first.id,
                  tema: TemaPlano.de(estilo),
                  estado: plano.estado,
                  familias: plano.familias,
                  animar: false,
                ),
              ),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          // La marca llega al que dibuja.
          final pintor = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((c) => c.painter)
              .whereType<PintorPlano>()
              .single;
          expect(identical(pintor.familias, plano.familias), isTrue);
        }
      });
    }
  });

  group('en papel', () {
    final evento = Evento(
      id: 'e',
      clienteId: 'c',
      tipo: 'Recepción',
      fechaEvento: DateTime(2026, 12, 1),
      estado: EstadoEvento.planificacion,
      modalidad: 'masivo',
      cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA'),
    );
    final plano = PlanoDeLaFiesta.desde(
      armado: salon,
      config: ConfigPlano.vacia,
      alumnos: [
        _familia('a', [5, 6], extras: 1),
        _familia('c', [20, 40], extras: 1),
      ],
    );

    for (final estilo in EstiloPlano.values) {
      for (final bn in [false, true]) {
        test('${estilo.name}, ${bn ? 'blanco y negro' : 'color'}: con la marca '
            'sale distinto y sin ella, igual que antes', () async {
          Future<int> tam({required bool familias}) async =>
              (await PdfService.construirPlanoPdf(
                evento,
                plano,
                estilo: estilo,
                blancoYNegro: bn,
                familias: familias,
                generada: DateTime(2026, 11, 2),
              ))
                  .length;
          expect(
            await tam(familias: true),
            greaterThan(await tam(familias: false)),
          );
        });
      }
    }
  });

  group('el diálogo de imprimir', () {
    Future<ComoImprimirPlano?> imprimir(
      WidgetTester tester, {
      required bool hayFamilias,
      bool destildar = false,
    }) async {
      ComoImprimirPlano? respuesta;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              respuesta = await elegirComoImprimirPlano(
                context,
                hojas: 1,
                hayFamilias: hayFamilias,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      if (destildar) {
        await tester.tap(find.byKey(const Key('imprimir_familias')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('imprimir_color')));
      await tester.pumpAndSettle();
      return respuesta;
    }

    testWidgets('viene prendida', (tester) async {
      final r = await imprimir(tester, hayFamilias: true);
      expect(r!.familias, isTrue);
      expect(r.blancoYNegro, isFalse);
    });

    testWidgets('se puede apagar', (tester) async {
      final r = await imprimir(tester, hayFamilias: true, destildar: true);
      expect(r!.familias, isFalse);
    });

    testWidgets('sin familias con adicional, no sale la casilla', (tester) async {
      final r = await imprimir(tester, hayFamilias: false);
      expect(r!.familias, isFalse);
      expect(find.byKey(const Key('imprimir_familias')), findsNothing);
    });
  });
}
