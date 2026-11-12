// Las mesas adicionales al final (6.6.1, pedido del jefe el 11-nov-2026): "si son
// 66 mesas principales, la mesa adicional que se vaya agregando a partir de la 67
// en adelante". Es una opción del cartel del sorteo; sin elegirla, todo sigue
// como siempre. Cuenta pura: sin base ni pantalla.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

/// El playón de Costa Surubí, numerado fila por fila.
const _playon = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39);

ArmadoSalon _salon(int mesas, {FinNumeracion fin = FinNumeracion.filas}) =>
    ArmarAMedida.armar(
      OpcionesAMedida(playon: _playon, cantidad: mesas, fin: fin),
    ).armado;

ContratoAlumno _familia(
  String id, {
  int extras = 0,
  List<int> mesas = const [],
  String division = '5° A',
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

/// Una escuela como la del sorteo del 12-nov: 67 familias y 13 adicionales
/// (nueve familias con una y dos familias con dos). 80 mesas.
List<ContratoAlumno> _escuela() => [
      for (var i = 1; i <= 67; i++)
        _familia(
          'f$i',
          extras: i <= 9 ? 1 : (i <= 11 ? 2 : 0),
          division: i.isEven ? '5° A' : '5° B',
        ),
    ];

/// Lo que arma el cartel con "Al final" elegido.
Map<String, int> _alFinal(
  List<ContratoAlumno> alumnos, {
  int juntas = 0,
  Set<String> dejarJuntas = const {},
  ExclusionSorteo exclusion = ExclusionSorteo.ninguna,
}) =>
    SorteoConPlano.alFinalSegunElCartel(
      SorteoMesasMotor.pedidos(
        alumnos,
        sinMesa: exclusion.sinMesa,
        soloBase: exclusion.soloBase,
      ),
      juntas: juntas,
      dejarJuntas: dejarJuntas,
    );

void main() {
  final alumnos = _escuela();
  final extrasDe = {for (final a in alumnos) a.id: a.mesaExtraCantidad};

  group('sin elegir la opción, todo sigue como siempre', () {
    test('cada familia queda con todas sus mesas juntas', () {
      final salon = _salon(90);
      for (var semilla = 0; semilla < 20; semilla++) {
        final e = EntradaSorteoPlano(armado: salon, alumnos: alumnos);
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull);
        for (final nums in r.asignaciones.values) {
          expect(SorteoConPlano.tramosPegados(salon, nums), hasLength(1));
        }
      }
      final plan = SorteoConPlano.preparar(
        EntradaSorteoPlano(armado: salon, alumnos: alumnos),
      );
      expect(plan.mesasAlFinal, 0);
      expect(plan.alFinalDesde, isNull);
    });

    test('lo que pide el cartel: nada, si nadie tiene adicionales para mandar',
        () {
      expect(_alFinal([_familia('a'), _familia('b')]), isEmpty);
      expect(_alFinal(alumnos, juntas: 2), isEmpty,
          reason: 'con 2 juntas, nadie de esta escuela manda ninguna');
      expect(_alFinal(alumnos, juntas: 1).keys, {'f10', 'f11'});
      expect(_alFinal(alumnos), hasLength(11));
      expect(
        _alFinal(alumnos, dejarJuntas: {'f1', 'f10'}).keys,
        isNot(anyOf(contains('f1'), contains('f10'))),
      );
    });
  });

  group('todas las adicionales al final', () {
    final salon = _salon(80);
    EntradaSorteoPlano entrada() => EntradaSorteoPlano(
          armado: salon,
          alumnos: alumnos,
          alFinal: _alFinal(alumnos),
        );

    test('el cartel dice de qué mesa a qué mesa va cada cosa', () {
      final plan = SorteoConPlano.preparar(entrada());
      expect(plan.entra, isTrue, reason: plan.avisos.join(' '));
      expect(plan.hastaMesa, 67, reason: 'las principales, de la 1 a la 67');
      expect(plan.hastaMesaMinima, 67);
      expect(plan.mesasAlFinal, 13);
      expect(plan.alFinalDesde, 68);
      expect(plan.alFinalHasta, 80);
    });

    test('60 sorteos: principales de corrido y adicionales después', () {
      for (var semilla = 0; semilla < 60; semilla++) {
        final e = entrada();
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        expect(r.asignaciones, hasLength(67));
        final principales = <int>[];
        final adicionales = <int>[];
        for (final x in r.asignaciones.entries) {
          expect(x.value, hasLength(1 + extrasDe[x.key]!));
          principales.add(x.value.first);
          adicionales.addAll(x.value.skip(1));
          // Las dos adicionales de una misma familia, juntas entre sí.
          if (x.value.length == 3) {
            expect(
              salon.pegadas(x.value[1], x.value[2]),
              isTrue,
              reason: 'semilla $semilla: ${x.value}',
            );
          }
        }
        expect(principales..sort(), [for (var n = 1; n <= 67; n++) n]);
        expect(adicionales..sort(), [for (var n = 68; n <= 80; n++) n]);
      }
    });

    test('no sale siempre igual: es un sorteo', () {
      final e = entrada();
      final uno = SorteoConPlano.sortear(e, random: Random(1)).asignaciones;
      final otro = SorteoConPlano.sortear(e, random: Random(2)).asignaciones;
      expect(uno['f1'], isNot(otro['f1']));
      expect(
        [for (final x in uno.entries) x.value.first == otro[x.key]!.first]
            .where((igual) => !igual),
        isNotEmpty,
      );
    });

    test('en la numeración de siempre también: las adicionales, los números '
        'más altos', () {
      final deSiempre = _salon(80, fin: FinNumeracion.escenario);
      for (var semilla = 0; semilla < 20; semilla++) {
        final e = EntradaSorteoPlano(
          armado: deSiempre,
          alumnos: alumnos,
          alFinal: _alFinal(alumnos),
        );
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull);
        final principales = [for (final l in r.asignaciones.values) l.first];
        expect(principales.reduce(max), 67);
      }
    });
  });

  group('la regla por cantidad', () {
    final salon = _salon(90);

    test('con 1: la principal y una adicional juntas, y la tercera al final',
        () {
      final alFinal = _alFinal(alumnos, juntas: 1);
      expect(alFinal, {'f10': 1, 'f11': 1});
      for (var semilla = 0; semilla < 30; semilla++) {
        final e = EntradaSorteoPlano(
          armado: salon,
          alumnos: alumnos,
          alFinal: alFinal,
        );
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        final delFinal = <int>[];
        final deAdelante = <int>[];
        for (final x in r.asignaciones.entries) {
          final nums = x.value;
          if (alFinal.containsKey(x.key)) {
            expect(nums, hasLength(3));
            expect(salon.pegadas(nums[0], nums[1]), isTrue, reason: '$nums');
            deAdelante.addAll(nums.take(2));
            delFinal.add(nums[2]);
          } else {
            expect(SorteoConPlano.tramosPegados(salon, nums), hasLength(1));
            deAdelante.addAll(nums);
          }
        }
        expect(delFinal, hasLength(2));
        expect(delFinal.reduce(min) > deAdelante.reduce(max), isTrue);
      }
    });

    test('con 2: en esta escuela nadie manda ninguna, y es el sorteo de siempre',
        () {
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        alFinal: _alFinal(alumnos, juntas: 2),
      );
      final r = SorteoConPlano.sortear(e, random: Random(3));
      expect(SorteoConPlano.validar(e, r), isNull);
      for (final nums in r.asignaciones.values) {
        expect(SorteoConPlano.tramosPegados(salon, nums), hasLength(1));
      }
    });
  });

  group('las excepciones por familia', () {
    final salon = _salon(90);

    test('la familia tildada "dejar juntas" queda entera, adelante', () {
      const juntas = {'f1', 'f10'};
      final alFinal = _alFinal(alumnos, dejarJuntas: juntas);
      for (var semilla = 0; semilla < 30; semilla++) {
        final e = EntradaSorteoPlano(
          armado: salon,
          alumnos: alumnos,
          alFinal: alFinal,
        );
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        final delFinal = <int>[
          for (final x in r.asignaciones.entries)
            if (alFinal.containsKey(x.key)) ...x.value.skip(1),
        ];
        final primeraDelFinal = delFinal.reduce(min);
        for (final id in juntas) {
          final nums = r.asignaciones[id]!;
          expect(SorteoConPlano.tramosPegados(salon, nums), hasLength(1));
          expect(nums.last < primeraDelFinal, isTrue, reason: '$id: $nums');
        }
      }
    });
  });

  group('con el candado', () {
    final salon = _salon(80);
    // f1 no pagó su adicional; f2 no pagó nada.
    const exclusion = ExclusionSorteo(sinMesa: {'f2'}, soloBase: {'f1'});

    test('la adicional sin pagar no va a ningún lado, y quien no pagó nada no '
        'entra', () {
      final alFinal = _alFinal(alumnos, exclusion: exclusion);
      expect(alFinal.containsKey('f1'), isFalse);
      expect(alFinal.containsKey('f2'), isFalse);
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        exclusion: exclusion,
        alFinal: alFinal,
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.hastaMesa, 66, reason: 'una principal menos');
      expect(plan.mesasAlFinal, 11, reason: '13 menos la de f1 y la de f2');
      expect(plan.alFinalDesde, 67);
      expect(plan.alFinalHasta, 77);
      final r = SorteoConPlano.sortear(e, random: Random(5));
      expect(SorteoConPlano.validar(e, r), isNull);
      expect(r.asignaciones['f1'], hasLength(1));
      expect(r.asignaciones.containsKey('f2'), isFalse);
    });

    test('aunque el cartel la mande igual, a quien va solo con la base no se '
        'le parte nada', () {
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        exclusion: exclusion,
        alFinal: {'f1': 1, 'f2': 1},
      );
      final r = SorteoConPlano.sortear(e, random: Random(5));
      expect(SorteoConPlano.validar(e, r), isNull);
      expect(r.asignaciones['f1'], hasLength(1));
    });
  });

  group('con mesas libres y fijadas', () {
    final salon = _salon(84);

    test('la libre no se da, la fijada va a su familia, y el final sigue al '
        'final', () {
      final config = ConfigPlano(
        libres: {10: const MesaLibre(motivo: 'Columna')},
        fijadas: {84: const MesaFijada(alumnoId: 'f20')},
      );
      for (var semilla = 0; semilla < 20; semilla++) {
        final e = EntradaSorteoPlano(
          armado: salon,
          config: config,
          alumnos: alumnos,
          alFinal: _alFinal(alumnos),
        );
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        expect(r.asignaciones['f20'], [84]);
        final todas = [for (final l in r.asignaciones.values) ...l];
        expect(todas, isNot(contains(10)));
        expect(todas.toSet(), hasLength(80));
        final principales = [
          for (final x in r.asignaciones.entries)
            if (x.key != 'f20') x.value.first,
        ];
        final adicionales = [
          for (final l in r.asignaciones.values) ...l.skip(1),
        ];
        expect(adicionales.reduce(min) > principales.reduce(max), isTrue);
      }
    });
  });

  group('por división no cambia nada', () {
    test('el sorteo por bloques no mira la opción', () {
      final salon = _salon(90);
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        modo: ModoSorteo.bloques,
        alFinal: _alFinal(alumnos),
      );
      expect(SorteoConPlano.mesasAlFinal(e, 'f1', 2), 0);
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isTrue, reason: plan.avisos.join(' '));
      expect(plan.mesasAlFinal, 0);
      final r = SorteoConPlano.sortear(e, random: Random(1));
      expect(SorteoConPlano.validar(e, r), isNull);
      for (final nums in r.asignaciones.values) {
        expect(SorteoConPlano.tramosPegados(salon, nums), hasLength(1));
      }
    });
  });

  group('con familias que ya tienen mesa', () {
    final salon = _salon(90);

    test('a nadie se le mueve nada, y la opción vale solo para las que llegan '
        'sin mesa', () {
      final sentadas = [
        for (var n = 1; n <= 40; n++) _familia('s$n', mesas: [n]),
        // Le falta la adicional que compró después.
        _familia('completa', extras: 1, mesas: [41]),
      ];
      final nuevas = [
        _familia('n1', extras: 1),
        _familia('n2'),
        _familia('n3', extras: 2),
      ];
      final todos = [...sentadas, ...nuevas];
      final alFinal = _alFinal(todos);
      expect(alFinal.keys, {'n1', 'n3'},
          reason: 'la que ya tiene mesa no entra en la opción');
      for (var semilla = 0; semilla < 20; semilla++) {
        final e = EntradaSorteoPlano(
          armado: salon,
          alumnos: todos,
          alFinal: alFinal,
        );
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        expect(r.asignaciones['completa'], hasLength(2));
        expect(r.asignaciones['completa'], contains(41));
        final n1 = r.asignaciones['n1']!, n3 = r.asignaciones['n3']!;
        final n2 = r.asignaciones['n2']!;
        final adelante = [n1.first, n2.first, n3.first];
        final atras = [...n1.skip(1), ...n3.skip(1)];
        expect(atras.reduce(min) > adelante.reduce(max), isTrue);
        expect(salon.pegadas(n3[1], n3[2]), isTrue);
      }
    });
  });

  group('cuando no entra', () {
    test('lo dice antes de sortear, y sortear no guarda nada', () {
      final e = EntradaSorteoPlano(
        armado: _salon(78),
        alumnos: alumnos,
        alFinal: _alFinal(alumnos),
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isFalse);
      expect(plan.avisos.join(' '), contains('van al final no entran'));
      expect(() => SorteoConPlano.sortear(e), throwsStateError);
    });
  });

  group('queda anotado en el registro del sorteo', () {
    final salon = _salon(80);

    test('qué mesas de cada familia fueron al final', () {
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        alFinal: _alFinal(alumnos),
      );
      final r = SorteoConPlano.sortear(e, random: Random(4));
      final delFinal = SorteoConPlano.delFinal(e, r);
      expect(delFinal.keys.toSet(), {for (var i = 1; i <= 11; i++) 'f$i'});
      for (final x in delFinal.entries) {
        expect(x.value, r.asignaciones[x.key]!.skip(1).toList());
      }
      // Sin la opción, nada.
      final sin = EntradaSorteoPlano(armado: salon, alumnos: alumnos);
      expect(
        SorteoConPlano.delFinal(sin, SorteoConPlano.sortear(sin)),
        isEmpty,
      );
    });

    test('viaja adentro del resultado, y una versión anterior lo ignora', () {
      final registro = SorteoMesasRegistro(
        id: 'r',
        eventoId: 'e',
        tipo: TipoRegistroSorteo.sorteo,
        resultado: const {'f1': '5-68', 'f12': '9'},
        alFinal: const {'f1': '68'},
        createdAt: DateTime.utc(2026, 11, 12),
      );
      final mapa = registro.toMap();
      final crudo = jsonDecode(mapa['resultado'] as String) as Map;
      expect(crudo['_al_final'], {'f1': '68'});
      expect(mapa['tipo'], 'sorteo', reason: 'el tipo no cambia');
      final vuelta = SorteoMesasRegistro.fromMap(mapa);
      expect(vuelta.alFinal, {'f1': '68'});
      expect(vuelta.resultado, {'f1': '5-68', 'f12': '9'},
          reason: 'la clave con guion bajo no es un alumno');
      // Sin la opción, la clave no se escribe.
      final sin = SorteoMesasRegistro(
        id: 'r',
        eventoId: 'e',
        tipo: TipoRegistroSorteo.sorteo,
        resultado: const {'f1': '5-6'},
        createdAt: DateTime.utc(2026, 11, 12),
      );
      expect(
        jsonDecode(sin.toMap()['resultado'] as String) as Map,
        isNot(contains('_al_final')),
      );
    });
  });

  group('el control final', () {
    final salon = _salon(80);
    final e = EntradaSorteoPlano(
      armado: salon,
      alumnos: alumnos,
      alFinal: _alFinal(alumnos),
    );
    final bueno = SorteoConPlano.sortear(e, random: Random(9));

    test('frena si una del final quedó antes que una de adelante', () {
      // La adicional de f1 y la principal de f30 cambian de lugar.
      final a = bueno.asignaciones;
      final adicional = a['f1']!.last, principal = a['f30']!.single;
      final malo = ResultadoSorteoPlano(asignaciones: {
        ...a,
        'f1': [a['f1']!.first, principal]..sort(),
        'f30': [adicional],
      });
      expect(
        SorteoConPlano.validar(e, malo),
        contains('quedó antes que una de adelante'),
      );
    });

    test('frena si las dos del final de una familia no quedaron juntas', () {
      final a = bueno.asignaciones;
      // f10 tiene dos al final; se le cambia una por la adicional más lejana.
      final suyas = a['f10']!;
      final otra = [
        for (final x in a.entries)
          if (x.key != 'f10' && x.value.length == 2) x,
      ].firstWhere(
        (x) =>
            !salon.pegadas(x.value.last, suyas[1]) &&
            !salon.pegadas(x.value.last, suyas[2]) &&
            (x.value.last - suyas[1]).abs() > 2,
      );
      final malo = ResultadoSorteoPlano(asignaciones: {
        ...a,
        'f10': [suyas[0], suyas[1], otra.value.last]..sort(),
        otra.key: [otra.value.first, suyas[2]]..sort(),
      });
      expect(
        SorteoConPlano.validar(e, malo),
        contains('del final de una familia no quedaron juntas'),
      );
    });
  });
}
