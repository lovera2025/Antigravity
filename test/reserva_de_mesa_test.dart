// Una mesa del plano reservada para quien no es alumno (6.5.0).
//
// El 10-nov-2026 el jefe pidió, después del sorteo, una mesa para los
// profesores: se la regala la empresa, sin contrato ni pago, y la quiere dejar
// en el plano con los nombres de quienes van. Es una mesa libre ("Dejar libre")
// que dice para quién: el sorteo no la da, y en el plano lleva ese nombre en
// vez de la tachadura de "no se usa". Todo va en el motivo de la mesa libre,
// sin claves nuevas.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/plano_pdf.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/modelo/reserva_de_mesa.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/features/plano/widgets/reserva_de_mesa_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/leer_pdf.dart';

ContratoAlumno _alumno(String id, {String? mesa, String curso = '5° A'}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: 'FAMILIA${id.toUpperCase()}, HIJO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      cursoDivision: curso,
      numeroMesa: mesa,
    );

ConfigPlano _config(Map<int, String?> libres) => ConfigPlano.vacia.copyWith(
      libres: {
        for (final e in libres.entries) e.key: MesaLibre(motivo: e.value),
      },
    );

void main() {
  final ahora = DateTime.utc(2026, 11, 10, 15);

  group('lo que dice el motivo', () {
    test('"Reservada para Profes: …" es una reserva, con sus nombres', () {
      final r = ReservaDeMesa.deMotivo(
        'Reservada para Profes: GARCÍA, ANA; LÓPEZ, LUIS',
      )!;
      expect(r.para, 'Profes');
      // La coma no separa: los nombres se escriben "APELLIDO, NOMBRE".
      expect(r.quienes, ['GARCÍA, ANA', 'LÓPEZ, LUIS']);
    });

    test('sin nombres, también', () {
      final r = ReservaDeMesa.deMotivo('reservada para  los   directivos ')!;
      expect(r.para, 'los directivos');
      expect(r.quienes, isEmpty);
    });

    test('una mesa que no se usa no es una reserva', () {
      for (final motivo in [
        null,
        '',
        '   ',
        'Columna',
        'Paso de mozos',
        'Reserva del salón',
        'Reservada para',
        'Reservada para : ANA',
      ]) {
        expect(ReservaDeMesa.deMotivo(motivo), isNull, reason: '"$motivo"');
      }
    });

    test('lo que se guarda se vuelve a leer igual', () {
      const r = ReservaDeMesa('Profes', ['GARCÍA, ANA', 'LÓPEZ, LUIS']);
      expect(r.motivo, 'Reservada para Profes: GARCÍA, ANA; LÓPEZ, LUIS');
      final leida = ReservaDeMesa.deMotivo(r.motivo)!;
      expect(leida.para, r.para);
      expect(leida.quienes, r.quienes);
      expect(const ReservaDeMesa('Profes').motivo, 'Reservada para Profes');
    });

    test('los nombres van uno por renglón, y lo que cortaría al leer se saca',
        () {
      expect(
        ReservaDeMesa.nombresDe('GARCÍA, ANA\n\n  LÓPEZ,   LUIS \r\nPÉREZ; DÍAZ'),
        ['GARCÍA, ANA', 'LÓPEZ, LUIS', 'PÉREZ', 'DÍAZ'],
      );
      const r = ReservaDeMesa('Profes: turno tarde', ['A; B', '  ']);
      expect(r.motivo, 'Reservada para Profes turno tarde: A, B');
      expect(ReservaDeMesa.deMotivo(r.motivo)!.quienes, ['A, B']);
    });
  });

  group('en el plano', () {
    final armado = ArmadosPredefinidos.normal2aPaginas45();

    PlanoDeLaFiesta plano(
      Map<int, String?> libres, {
      List<ContratoAlumno> alumnos = const [],
    }) =>
        PlanoDeLaFiesta.desde(
          armado: armado,
          config: _config(libres),
          alumnos: alumnos,
        );

    test('la reservada lleva su nombre; la que no se usa, no', () {
      final p = plano({
        3: 'Reservada para Profes: GARCÍA, ANA',
        4: 'Columna',
        5: null,
      });
      expect(p.estado.info(3).libre, isTrue);
      expect(p.estado.info(3).reservada, 'Profes');
      expect(p.estado.info(3).nombreDeReservada, 'Profes');
      for (final n in [4, 5]) {
        expect(p.estado.info(n).libre, isTrue, reason: 'mesa $n');
        expect(p.estado.info(n).nombreDeReservada, isNull, reason: 'mesa $n');
      }
      // Sigue contando como libre: es lo que la saca del sorteo.
      expect(p.estado.info(3).estado, EstadoMesa.libre);
    });

    test('si quedó ocupada es un conflicto, y no se muestra como reservada',
        () {
      final p = plano(
        {3: 'Reservada para Profes'},
        alumnos: [_alumno('a', mesa: '3')],
      );
      expect(p.estado.info(3).estado, EstadoMesa.conflicto);
      expect(p.estado.info(3).nombreDeReservada, isNull);
    });

    test('un nombre largo se corta para entrar debajo de la mesa', () {
      final p = plano({
        3: 'Reservada para ${'Profesores y directivos de la escuela técnica'}',
      });
      final nombre = p.estado.info(3).reservada!;
      expect(nombre.length, lessThanOrEqualTo(kLargoDeReservada));
      expect(nombre, endsWith('…'));
    });

    test('el sorteo no se la da a nadie, ni al sortear a los que faltan', () {
      final config = _config({3: 'Reservada para Profes: GARCÍA, ANA'});
      // Diez familias sin mesa: ninguna cae en la 3.
      final nuevas = [for (var i = 0; i < 10; i++) _alumno('n$i')];
      for (var semilla = 0; semilla < 20; semilla++) {
        final entrada = EntradaSorteoPlano(
          armado: armado,
          config: config,
          alumnos: nuevas,
        );
        final sorteo = SorteoConPlano.sortear(entrada, random: Random(semilla));
        expect(SorteoConPlano.validar(entrada, sorteo), isNull);
        for (final mesas in sorteo.asignaciones.values) {
          expect(mesas, isNot(contains(3)), reason: 'semilla $semilla');
        }
      }
      // Con las mesas 1, 2 y 4 dadas, a la que falta le toca otra, no la 3.
      final conMesa = [
        _alumno('a', mesa: '1'),
        _alumno('b', mesa: '2'),
        _alumno('c', mesa: '4'),
        _alumno('falta'),
      ];
      final entrada = EntradaSorteoPlano(
        armado: armado,
        config: config,
        alumnos: conMesa,
      );
      final sorteo = SorteoConPlano.sortear(entrada, random: Random(1));
      expect(sorteo.asignaciones['falta'], isNotNull);
      expect(sorteo.asignaciones['falta'], isNot(contains(3)));
    });

    test('en el papel: el nombre, quiénes se sientan y su renglón en el pie',
        () async {
      final p = plano(
        {
          3: 'Reservada para Profes: GARCIA, ANA; LOPEZ, LUIS',
          4: 'Columna',
        },
        alumnos: [_alumno('a', mesa: '1')],
      );
      // Sin las letras de la app, para poder leer lo que escribió.
      final texto = contenidoDelPdf(await PlanoPdf.construir(
        institucion: 'ESCUELA DE PRUEBA',
        plano: p,
        estilo: EstiloPlano.arquitecto,
        generada: DateTime(2026, 11, 10, 12),
      ));
      for (final palabra in [
        '(PROFES)',
        '(PROFES:)',
        '(GARCIA,)',
        '(LOPEZ,)',
        '(Reservada:)',
        // La 4 no se usa: su renglón del pie sigue.
        '(Libre:)',
      ]) {
        expect(texto.contains(palabra), isTrue, reason: palabra);
      }
    });

    test('sin ninguna reservada, el papel no habla de reservas', () async {
      final texto = contenidoDelPdf(await PlanoPdf.construir(
        institucion: 'ESCUELA DE PRUEBA',
        plano: plano({4: 'Columna'}, alumnos: [_alumno('a', mesa: '1')]),
        estilo: EstiloPlano.arquitecto,
        generada: DateTime(2026, 11, 10, 12),
      ));
      expect(texto.contains('(Reservada:)'), isFalse);
      expect(texto.contains('(Libre:)'), isTrue);
    });
  });

  group('cambiar para quién es', () {
    test('una mesa libre pasa a reservada y sigue libre', () {
      final r = CambiosDeMesa.cambiarMotivoDeLibre(
        config: _config({3: 'Columna', 7: null}),
        mesa: 3,
        motivo: const ReservaDeMesa('Profes', ['GARCÍA, ANA']).motivo,
        por: 'Jefe',
        ahora: ahora,
      );
      expect(r.sePuede, isTrue);
      expect(r.mesas, [3]);
      expect(r.config!.libres.keys, unorderedEquals([3, 7]));
      expect(
        r.config!.libres[3]!.motivo,
        'Reservada para Profes: GARCÍA, ANA',
      );
      expect(r.config!.libres[3]!.por, 'Jefe');
      // La otra no se toca.
      expect(r.config!.libres[7]!.motivo, isNull);
    });

    test('sin texto queda libre sin motivo', () {
      final r = CambiosDeMesa.cambiarMotivoDeLibre(
        config: _config({3: 'Reservada para Profes'}),
        mesa: 3,
        motivo: '  ',
        por: null,
        ahora: ahora,
      );
      expect(r.config!.libres[3]!.motivo, isNull);
    });

    test('una mesa que ya no está libre no se cambia', () {
      final r = CambiosDeMesa.cambiarMotivoDeLibre(
        config: _config({3: 'Columna'}),
        mesa: 9,
        motivo: 'Reservada para Profes',
        por: null,
        ahora: ahora,
      );
      expect(r.sePuede, isFalse);
      expect(r.problema, 'La mesa 9 ya no está libre.');
    });
  });

  group('el cartel', () {
    Future<List<String?>> abrir(
      WidgetTester tester, {
      String? motivoActual,
      bool yaEstaLibre = false,
    }) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final elegido = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => elegido.add(
                  await pedirReservaDeMesa(
                    context: context,
                    mesa: 151,
                    motivoActual: motivoActual,
                    yaEstaLibre: yaEstaLibre,
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return elegido;
    }

    testWidgets('viene en "No se usa", como siempre', (tester) async {
      final elegido = await abrir(tester);
      expect(find.text('Dejar libre la mesa 151'), findsOneWidget);
      expect(find.byKey(const Key('motivo')), findsOneWidget);
      expect(find.byKey(const Key('reserva_quienes')), findsNothing);
      await tester.enterText(find.byKey(const Key('motivo')), 'Columna');
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(elegido.single, 'Columna');
    });

    testWidgets('sin escribir nada, queda libre sin motivo', (tester) async {
      final elegido = await abrir(tester);
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(elegido.single, '');
    });

    testWidgets('"Es para alguien" pide para quién y deja cargar los nombres',
        (tester) async {
      final elegido = await abrir(tester);
      await tester.tap(find.text('Es para alguien'));
      await tester.pumpAndSettle();
      // Sin decir para quién no se puede confirmar.
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('confirmar'))).onPressed,
        isNull,
      );
      await tester.tap(find.text('Profes'));
      await tester.enterText(
        find.byKey(const Key('reserva_quienes')),
        'GARCÍA, ANA\nLÓPEZ, LUIS',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(elegido.single, 'Reservada para Profes: GARCÍA, ANA; LÓPEZ, LUIS');
    });

    testWidgets('para cambiarla abre con lo que tenía', (tester) async {
      final elegido = await abrir(
        tester,
        motivoActual: 'Reservada para Profes: GARCÍA, ANA',
        yaEstaLibre: true,
      );
      expect(find.text('La mesa 151, libre'), findsOneWidget);
      expect(find.text('GUARDAR'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('reserva_para')))
            .controller!
            .text,
        'Profes',
      );
      await tester.enterText(
        find.byKey(const Key('reserva_quienes')),
        'GARCÍA, ANA\nDÍAZ, EVA',
      );
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(elegido.single, 'Reservada para Profes: GARCÍA, ANA; DÍAZ, EVA');
    });

    testWidgets('cancelar no cambia nada', (tester) async {
      final elegido = await abrir(tester);
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(elegido.single, isNull);
    });
  });
}
