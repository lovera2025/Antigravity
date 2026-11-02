// "Qué tan lejos" (etapa 6 de docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md): al marcar
// "lejos" se elige cerca, a unas mesas o bien lejos. Juntas y una mesa no cambian. La
// medición grande, con 1.000 sorteos por salón: tool/lejos_distancias_test.dart.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/planilla_sorteo.dart';
import 'package:arguello_events/features/eventos/services/registro_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import 'helpers/salon_puerto_viejo.dart';

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
  final grande = ArmarAMedida.acomodar(
    ArmarAMedida.vacio(PlayonReal.costaSurubi),
    cantidad: 132,
  ).armado;
  final puertoViejo = ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado;

  /// Una escuela: [lejos] familias con "1 lejos", tres con dos mesas juntas y el
  /// resto de a una, hasta llenar [mesas].
  List<ContratoAlumno> escuela(int mesas, int lejos) {
    final l = [
      for (var i = 0; i < lejos; i++) _familia('l$i', extras: 1),
      for (var i = 0; i < 3; i++) _familia('j$i', extras: 1),
    ];
    final usadas = lejos * 2 + 6;
    return [...l, for (var i = 0; i < mesas - usadas; i++) _familia('s$i')];
  }

  List<double> medir(
    ArmadoSalon a,
    int mesas,
    int lejos,
    DistanciaLejos? distancia, {
    int sorteos = 40,
  }) {
    final alumnos = escuela(mesas, lejos);
    final entrada = EntradaSorteoPlano(
      armado: a,
      alumnos: alumnos,
      separaciones: {for (var i = 0; i < lejos; i++) 'l$i': 1},
      distancias: distancia == null
          ? const {}
          : {for (var i = 0; i < lejos; i++) 'l$i': distancia},
    );
    final salida = <double>[];
    for (var s = 0; s < sorteos; s++) {
      final r = SorteoConPlano.sortear(entrada, random: Random(s));
      expect(SorteoConPlano.validar(entrada, r), isNull);
      for (var i = 0; i < lejos; i++) {
        final nums = r.asignaciones['l$i']!;
        expect(SorteoConPlano.lejosEnElSalon(a, nums, 1), isTrue,
            reason: 'la familia l$i quedó tocándose: $nums');
        salida.add(SorteoConPlano.lugaresDeLaSuelta(a, nums)!);
      }
    }
    return salida..sort();
  }

  double mediana(List<double> l) => l[l.length ~/ 2];
  double parte(List<double> l, bool Function(double) cumple) =>
      l.where(cumple).length / l.length;

  group('en el salón grande', () {
    test('cerca: casi siempre a menos de 3 lugares', () {
      final d = medir(grande, 100, 10, DistanciaLejos.cerca);
      expect(parte(d, (x) => x <= 3), greaterThanOrEqualTo(0.95));
      expect(d.first, greaterThan(1.5), reason: 'nunca tocándose');
    });

    test('a unas mesas: entre 3 y 6', () {
      final d = medir(grande, 100, 10, DistanciaLejos.aUnasMesas);
      expect(parte(d, (x) => x >= 3 && x <= 6), greaterThanOrEqualTo(0.9));
    });

    test('bien lejos: mucho más lejos que las otras dos', () {
      final bien = medir(grande, 100, 10, DistanciaLejos.bienLejos);
      final unas = medir(grande, 100, 10, DistanciaLejos.aUnasMesas);
      expect(mediana(bien), greaterThan(mediana(unas) + 2));
    });

    test('sin decir nada es lo de siempre: como bien lejos, con la misma semilla',
        () {
      expect(
        medir(grande, 100, 10, null),
        medir(grande, 100, 10, DistanciaLejos.bienLejos),
      );
    });
  });

  group('en Puerto Viejo, con 35 mesas', () {
    test('cerca y a unas mesas también se cumplen, sin tocarse', () {
      final c = medir(puertoViejo, 30, 3, DistanciaLejos.cerca);
      expect(parte(c, (x) => x <= 3), greaterThanOrEqualTo(0.9));
      final u = medir(puertoViejo, 30, 3, DistanciaLejos.aUnasMesas);
      expect(parte(u, (x) => x >= 3 && x <= 6), greaterThanOrEqualTo(0.8));
    });
  });

  group('lo demás del sorteo no cambia', () {
    test('las familias con adicional siguen juntas, y las de una mesa, con una', () {
      final alumnos = escuela(100, 10);
      final entrada = EntradaSorteoPlano(
        armado: grande,
        alumnos: alumnos,
        separaciones: {for (var i = 0; i < 10; i++) 'l$i': 1},
        distancias: {
          for (var i = 0; i < 10; i++) 'l$i': DistanciaLejos.cerca,
        },
      );
      for (var s = 0; s < 40; s++) {
        final r = SorteoConPlano.sortear(entrada, random: Random(s));
        for (var i = 0; i < 3; i++) {
          final nums = r.asignaciones['j$i']!;
          expect(nums, hasLength(2));
          expect(SorteoConPlano.tramosPegados(grande, nums), hasLength(1));
        }
        for (final a in alumnos.where((x) => x.id.startsWith('s'))) {
          expect(r.asignaciones[a.id], hasLength(1));
        }
      }
    });

    test('lo que entra no depende de qué tan lejos', () {
      for (final d in DistanciaLejos.values) {
        final plan = SorteoConPlano.preparar(EntradaSorteoPlano(
          armado: puertoViejo,
          alumnos: escuela(35, 3),
          separaciones: const {'l0': 1, 'l1': 1, 'l2': 1},
          distancias: {'l0': d, 'l1': d, 'l2': d},
        ));
        expect(plan.entra, isTrue, reason: d.name);
      }
    });
  });

  group('si no hay lugar a esa distancia', () {
    test('queda en la más cercana a lo pedido, y lo dice con el apellido', () {
      // Todo el salón ocupado menos dos mesas lejanas: "cerca" no puede cumplirse.
      final ocupadas = <ContratoAlumno>[
        for (final n in grande.numeros)
          if (n != 1 && n != 40) _familia('o$n', mesas: [n]),
      ];
      final entrada = EntradaSorteoPlano(
        armado: grande,
        alumnos: [...ocupadas, _familia('perez', extras: 1)],
        separaciones: const {'perez': 1},
        distancias: const {'perez': DistanciaLejos.cerca},
      );
      final r = SorteoConPlano.sortear(entrada, random: Random(1));
      final quedo = SorteoConPlano.lugaresDeLaSuelta(
        grande,
        r.asignaciones['perez']!,
      )!;
      expect(quedo, greaterThan(3));
      expect(r.avisosLejos.single, startsWith('PEREZ: la adicional quedó a '));
      expect(r.avisosLejos.single, endsWith('no había lugar cerca.'));
      expect(SorteoConPlano.validar(entrada, r), isNull);
    });

    test('a la distancia pedida, sin aviso', () {
      final entrada = EntradaSorteoPlano(
        armado: grande,
        alumnos: escuela(40, 2),
        separaciones: const {'l0': 1, 'l1': 1},
        distancias: const {
          'l0': DistanciaLejos.cerca,
          'l1': DistanciaLejos.cerca,
        },
      );
      expect(
        SorteoConPlano.sortear(entrada, random: Random(1)).avisosLejos,
        isEmpty,
      );
    });
  });

  group('sin plano, por número', () {
    final pedidos = SorteoMesasMotor.pedidos(
      [_familia('a', extras: 1), for (var i = 0; i < 30; i++) _familia('s$i')],
      separaciones: const {'a': 1},
    );

    List<int> sortear(DistanciaLejos? d, int semilla) =>
        SorteoMesasMotor.sortear(
          pedidos: pedidos,
          ocupadas: const {},
          capacidad: 60,
          random: Random(semilla),
          ordenLejos: d == null
              ? null
              : SorteoMesasMotor.ordenPorNumero({'a': d}),
        )['a']!;

    test('cerca es una de por medio; a unas mesas, de 3 a 6', () {
      for (var s = 0; s < 40; s++) {
        final c = sortear(DistanciaLejos.cerca, s);
        expect(c[1] - c[0], 2);
        final u = sortear(DistanciaLejos.aUnasMesas, s);
        expect(u[1] - u[0], inInclusiveRange(3, 6));
      }
    });

    test('bien lejos es lo de hoy', () {
      for (var s = 0; s < 10; s++) {
        expect(sortear(DistanciaLejos.bienLejos, s), sortear(null, s));
      }
    });

    test('el motor sigue validando el resultado', () {
      final r = SorteoMesasMotor.sortear(
        pedidos: pedidos,
        ocupadas: const {},
        capacidad: 60,
        random: Random(3),
        ordenLejos: SorteoMesasMotor.ordenPorNumero(
          {'a': DistanciaLejos.cerca},
        ),
      );
      expect(
        SorteoMesasMotor.validar(
          pedidos: pedidos,
          ocupadas: const {},
          capacidad: 60,
          asignaciones: r,
        ),
        isNull,
      );
    });
  });

  group('queda escrito', () {
    SorteoMesasRegistro renglon(
      TipoRegistroSorteo tipo,
      Map<String, String> numeros, {
      Map<String, String>? lejos,
      int minuto = 0,
    }) =>
        SorteoMesasRegistro(
          id: 'r$minuto',
          eventoId: 'e',
          tipo: tipo,
          resultado: numeros,
          lejos: lejos,
          createdAt: DateTime.utc(2026, 11, 2, 12, minuto),
        );

    test('en el registro: va y vuelve, sin contarse como un alumno', () {
      final r = renglon(
        TipoRegistroSorteo.sorteo,
        const {'a': '5, 30'},
        lejos: const {'a': 'cerca'},
      );
      final leido = SorteoMesasRegistro.fromMap(r.toMap());
      expect(leido.lejos, {'a': 'cerca'});
      expect(leido.resultado, {'a': '5, 30'});
      expect(leido.alumnos, 1);
      expect(leido.tipo, TipoRegistroSorteo.sorteo);
    });

    test('sin marcas, el registro queda como siempre', () {
      final r = renglon(TipoRegistroSorteo.sorteo, const {'a': '5'});
      expect(r.toMap()['resultado'], isNot(contains('_lejos')));
    });

    test('la planilla lee el último sorteo de cada familia', () {
      final registros = [
        renglon(
          TipoRegistroSorteo.sorteo,
          const {'a': '5, 30', 'b': '6, 40'},
          lejos: const {'a': 'cerca', 'b': 'bienLejos'},
        ),
        renglon(TipoRegistroSorteo.deshacer, const {'a': '5, 30'}, minuto: 1),
      ];
      expect(RegistroSorteo.lejosDeLosSorteos(registros), {
        'b': DistanciaLejos.bienLejos,
      });
    });

    test('en la planilla: "lejos · cerca", solo si quedó separada', () {
      final separada = PlanillaSorteo.fila(
        _familia('a', extras: 1, mesas: [5, 30]),
        lejos: DistanciaLejos.cerca,
      );
      expect(separada.adicional, '30 (separada) · lejos · cerca');
      final junta = PlanillaSorteo.fila(
        _familia('a', extras: 1, mesas: [5, 6]),
        lejos: DistanciaLejos.cerca,
      );
      expect(junta.adicional, '6');
      final sin = PlanillaSorteo.fila(_familia('a', extras: 1, mesas: [5, 30]));
      expect(sin.adicional, '30 (separada)');
    });
  });

  group('en el diálogo de SORTEO', () {
    Future<void> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SorteoMesasDialog(
            tituloInstitucion: 'ESCUELA',
            alumnos: [_familia('a', extras: 1), _familia('b')],
            avisos: const [],
            // Con todo cargado, no solo lo pagado.
            inicial: const SorteoMesasDialogResult(capacidadSalon: 0),
            pagos: const {},
            plano: PlanoEvento.nuevo(
              eventoId: 'e',
              armado: puertoViejo,
              estilo: EstiloPlano.arquitecto,
              modo: ModoSorteo.entera,
              ahora: DateTime.utc(2026, 11, 2),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    final distancia = find.byKey(const Key('distancia_lejos_a'));

    testWidgets('sale al tildar "lejos", y viene en cerca', (tester) async {
      await abrir(tester);
      expect(distancia, findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'A, ALUMNO'));
      await tester.pump();
      expect(distancia, findsOneWidget);
      expect(
        tester.widget<DropdownButton<DistanciaLejos>>(distancia).value,
        DistanciaLejos.cerca,
      );
    });

    testWidgets('al destildar, se va', (tester) async {
      await abrir(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'A, ALUMNO'));
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'A, ALUMNO'));
      await tester.pump();
      expect(distancia, findsNothing);
    });
  });
}
