// Las mesas de más van lejos, y el jefe elige dónde (6.5.0, pedido del usuario
// el 9-nov): la principal y 2 adicionales juntas se toleran; de ahí en más, las
// de más van lejos. El cartel del sorteo trae tildadas a esas familias, y con
// "Donde yo elija" se marcan las mesas en el plano, encima del cartel. Vale
// también para la mesa que se compra después del sorteo.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/features/plano/widgets/elegir_zona_dialog.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

ContratoAlumno _familia(String id, {int extras = 0, List<int>? mesas}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 1,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas == null ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

void main() {
  final salon = ArmarAMedida.acomodar(
    ArmarAMedida.vacio(PlayonReal.costaSurubi),
    cantidad: 132,
  ).armado;

  group('el sorteo con "Donde yo elija"', () {
    test('las lejos caen en la zona elegida, sin tocar a la familia', () {
      // RÍOS: 5 mesas, 3 juntas y 2 lejos, en la zona 120 a 125.
      final zona = {120, 121, 122, 123, 124, 125};
      final alumnos = [
        _familia('rios', extras: 4),
        for (var i = 0; i < 30; i++) _familia('s$i'),
      ];
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        separaciones: const {'rios': 2},
        distancias: const {'rios': DistanciaLejos.enLaZona},
        zonas: {'rios': zona},
      );
      for (var s = 0; s < 30; s++) {
        final r = SorteoConPlano.sortear(e, random: Random(s));
        expect(SorteoConPlano.validar(e, r), isNull);
        final nums = r.asignaciones['rios']!;
        expect(nums, hasLength(5));
        expect(nums.where(zona.contains), hasLength(2), reason: 'sorteo $s');
        expect(SorteoConPlano.lejosEnElSalon(salon, nums, 2), isTrue);
        expect(r.avisosLejos, isEmpty);
      }
    });

    test('con la zona ocupada, van lo más lejos que se pueda y lo avisa', () {
      final alumnos = [
        _familia('rios', extras: 3),
        _familia('ya', mesas: [120]),
        for (var i = 0; i < 20; i++) _familia('s$i'),
      ];
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        separaciones: const {'rios': 1},
        distancias: const {'rios': DistanciaLejos.enLaZona},
        zonas: const {'rios': {120}},
      );
      final r = SorteoConPlano.sortear(e, random: Random(1));
      expect(SorteoConPlano.validar(e, r), isNull);
      expect(r.asignaciones['rios'], isNot(contains(120)));
      expect(r.avisosLejos.single, startsWith('RIOS: una adicional no quedó en '
          'la zona elegida'));
    });

    test('sin zona marcada, como bien lejos y sin aviso', () {
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: [_familia('rios', extras: 3), _familia('s')],
        separaciones: const {'rios': 1},
        distancias: const {'rios': DistanciaLejos.enLaZona},
      );
      final r = SorteoConPlano.sortear(e, random: Random(2));
      expect(SorteoConPlano.validar(e, r), isNull);
      expect(r.avisosLejos, isEmpty);
    });
  });

  test('dos familias con lejos en un salón justo: busca unas mesas más', () {
    // Con lo justo para el motor, las lejos de RÍOS y SOSA quedaban tocando a
    // su familia y el cartel decía que no entraba (pasaba también antes de la
    // 6.5.0, pero con las de más de 3 mesas tildadas solas iba a ser seguido).
    final alumnos = [
      _familia('rios', extras: 4),
      _familia('sosa', extras: 3),
      _familia('luna', extras: 2),
      for (var i = 1; i <= 30; i++) _familia('a$i', mesas: [i]),
    ];
    final e = EntradaSorteoPlano(
      armado: ArmadosPredefinidos.normal2aPagina3(),
      alumnos: alumnos,
      separaciones: const {'rios': 2, 'sosa': 1},
      distancias: const {
        'rios': DistanciaLejos.bienLejos,
        'sosa': DistanciaLejos.bienLejos,
      },
    );
    final plan = SorteoConPlano.preparar(e);
    expect(plan.entra, isTrue, reason: '${plan.avisos}');
    for (var s = 0; s < 10; s++) {
      final r = SorteoConPlano.sortear(e, random: Random(s));
      expect(SorteoConPlano.validar(e, r), isNull);
    }
  });

  group('la mesa que se compró después', () {
    test('pedida lejos, va suelta y sin tocar las suyas', () {
      // GÓMEZ tiene la 10 y la 11, y compró una más.
      final alumnos = [
        _familia('gomez', extras: 2, mesas: [10, 11]),
        for (var i = 0; i < 12; i++) _familia('s$i', mesas: [i + 20]),
      ];
      final pedidos = SorteoMesasMotor.pedidos(
        alumnos,
        separaciones: const {'gomez': 1},
      );
      expect(pedidos.single.separadas, 1);
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        separaciones: const {'gomez': 1},
        distancias: const {'gomez': DistanciaLejos.enLaZona},
        zonas: const {'gomez': {100, 101}},
      );
      for (var s = 0; s < 20; s++) {
        final r = SorteoConPlano.sortear(e, random: Random(s));
        expect(SorteoConPlano.validar(e, r), isNull);
        final nums = r.asignaciones['gomez']!;
        expect(nums, containsAll([10, 11]));
        final nueva = nums.firstWhere((n) => n != 10 && n != 11);
        expect({100, 101}, contains(nueva), reason: 'sorteo $s');
        expect(
          SorteoConPlano.nuevasLejosEnElSalon(salon, const [10, 11], nums),
          isTrue,
        );
      }
    });

    test('sin pedirla lejos, va pegada a las suyas, como siempre', () {
      final alumnos = [_familia('gomez', extras: 2, mesas: [10, 11])];
      final pedidos = SorteoMesasMotor.pedidos(alumnos);
      expect(pedidos.single.separadas, 0);
      final r = SorteoMesasMotor.sortear(
        pedidos: pedidos,
        ocupadas: const {10, 11},
        capacidad: 30,
        random: Random(3),
      );
      expect(r['gomez'], anyOf(equals([9, 10, 11]), equals([10, 11, 12])));
    });

    test('sin plano, pedida lejos, no queda pegada', () {
      final alumnos = [_familia('gomez', extras: 2, mesas: [10, 11])];
      final pedidos = SorteoMesasMotor.pedidos(
        alumnos,
        separaciones: const {'gomez': 1},
      );
      for (var s = 0; s < 20; s++) {
        final r = SorteoMesasMotor.sortear(
          pedidos: pedidos,
          ocupadas: const {10, 11},
          capacidad: 30,
          random: Random(s),
        );
        final nueva = r['gomez']!.firstWhere((n) => n != 10 && n != 11);
        expect((nueva - 10).abs() > 1 && (nueva - 11).abs() > 1, isTrue);
        expect(
          SorteoMesasMotor.validar(
            pedidos: pedidos,
            ocupadas: const {10, 11},
            capacidad: 30,
            asignaciones: r,
          ),
          isNull,
        );
      }
    });
  });

  test('el registro guarda la zona, y una versión vieja la ignora', () {
    final r = SorteoMesasRegistro(
      id: 'r',
      eventoId: 'e',
      tipo: TipoRegistroSorteo.sorteo,
      resultado: const {'rios': '1, 2, 3, 120, 122'},
      lejos: const {'rios': 'enLaZona'},
      zonas: const {'rios': '120, 121, 122'},
      createdAt: DateTime.utc(2026, 11, 10),
    );
    final vuelta = SorteoMesasRegistro.fromMap(r.toMap());
    expect(vuelta.zonas, {'rios': '120, 121, 122'});
    expect(vuelta.resultado, {'rios': '1, 2, 3, 120, 122'});
    expect(DistanciaLejos.deClave('enLaZona'), DistanciaLejos.enLaZona);
    expect(DistanciaLejos.enLaZona.texto, 'en la zona elegida');
  });

  group('en el cartel del sorteo', () {
    Future<void> abrir(
      WidgetTester tester,
      List<ContratoAlumno> alumnos, {
      SorteoMesasDialogResult? inicial,
      Map<String, PagoAlumno> pagos = const {},
    }) async {
      tester.view.physicalSize = const Size(1300, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SorteoMesasDialog(
            tituloInstitucion: 'ESCUELA',
            alumnos: alumnos,
            avisos: const [],
            inicial: inicial,
            pagos: pagos,
            plano: PlanoEvento.nuevo(
              eventoId: 'e',
              armado: salon,
              estilo: EstiloPlano.gala,
              modo: ModoSorteo.entera,
              ahora: DateTime.utc(2026, 11, 9),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    // Sin "solo lo pagado": se sortea todo lo cargado.
    const todoCargado = SorteoMesasDialogResult(
      capacidadSalon: 0,
      soloPagado: false,
    );

    testWidgets('más de 3 mesas viene tildada la primera vez, con las de más '
        'bien lejos', (tester) async {
      await abrir(
        tester,
        [
          _familia('rios', extras: 4),
          _familia('luna', extras: 2),
          _familia('s'),
        ],
        pagos: const {
          'rios': PagoAlumno(base: 1, mesas: 1),
          'luna': PagoAlumno(base: 1, mesas: 1),
          's': PagoAlumno(base: 1),
        },
      );
      expect(find.byKey(const Key('aviso_mas_de_tres')), findsOneWidget);
      expect(find.textContaining('1 familia con más de 3 mesas'), findsOneWidget);
      expect(
        find.text('La principal y 2 adicionales juntas; las otras 2 van '
            'lejos.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButton<DistanciaLejos>>(
              find.byKey(const Key('distancia_lejos_rios')),
            )
            .value,
        DistanciaLejos.bienLejos,
      );
      // LUNA, con 3, no.
      expect(find.byKey(const Key('distancia_lejos_luna')), findsNothing);

      // Destildada: dice que van todas juntas.
      await tester.tap(find.widgetWithText(CheckboxListTile, 'RIOS, ALUMNO'));
      await tester.pump();
      expect(find.textContaining('destildada: van todas juntas'), findsOneWidget);
    });

    testWidgets('abierto de nuevo (con lo elegido), no se vuelve a tildar',
        (tester) async {
      await abrir(tester, [_familia('rios', extras: 4)], inicial: todoCargado);
      expect(find.byKey(const Key('distancia_lejos_rios')), findsNothing);
    });

    testWidgets('"Donde yo elija" abre el plano encima y vuelve con la zona',
        (tester) async {
      await abrir(tester, [_familia('rios', extras: 1), _familia('s')],
          inicial: todoCargado);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'RIOS, ALUMNO'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('distancia_lejos_rios')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Donde yo elija').last);
      await tester.pumpAndSettle();
      expect(find.text('Ninguna elegida todavía: van bien lejos.'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('elegir_zona_rios')));
      await tester.pumpAndSettle();
      expect(find.byType(ElegirZonaDialog), findsOneWidget);
      VistaPlano vista() =>
          tester.widget<VistaPlano>(find.byKey(const ValueKey('zona_plano')));
      // Sin marcar ninguna, LISTO no cierra.
      await tester.tap(find.byKey(const ValueKey('zona_listo')));
      await tester.pump();
      expect(find.text('Marcá al menos una mesa libre.'), findsOneWidget);

      vista().onTapMesa!(100);
      vista().onTapMesa!(101);
      vista().onTapMesa!(101); // otra vez: se saca
      await tester.pump();
      expect(vista().resaltadas, {100});
      await tester.tap(find.byKey(const ValueKey('zona_listo')));
      await tester.pumpAndSettle();
      expect(find.byType(ElegirZonaDialog), findsNothing);
      expect(find.text('1 mesa elegida: 100'), findsOneWidget);
    });

    testWidgets('en la zona no se elige una mesa que ya tiene familia',
        (tester) async {
      await abrir(
        tester,
        [_familia('rios', extras: 1), _familia('ya', mesas: [100])],
        inicial: todoCargado,
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'RIOS, ALUMNO'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('distancia_lejos_rios')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Donde yo elija').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('elegir_zona_rios')));
      await tester.pumpAndSettle();
      tester
          .widget<VistaPlano>(find.byKey(const ValueKey('zona_plano')))
          .onTapMesa!(100);
      await tester.pump();
      expect(find.text('La mesa 100 ya es de YA, ALUMNO.'), findsOneWidget);
    });

    testWidgets('la que compró después se puede pedir lejos de las suyas',
        (tester) async {
      await abrir(
        tester,
        [_familia('gomez', extras: 2, mesas: [10, 11]), _familia('s')],
        inicial: todoCargado,
      );
      expect(find.textContaining('le falta 1'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'GOMEZ, ALUMNO'));
      await tester.pump();
      expect(find.text('La que le falta va lejos de las suyas.'), findsOneWidget);
      expect(find.byKey(const Key('separadas_gomez')), findsNothing);
    });
  });
}
