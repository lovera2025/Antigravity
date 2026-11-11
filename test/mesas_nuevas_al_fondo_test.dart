// Las mesas que llegan después del sorteo van al fondo (6.5.1, pedido del jefe el
// 10-nov-2026): a la familia que confirma una mesa con el sorteo ya hecho se le
// agrega una mesa con el número que sigue, al fondo a la derecha, y nadie se mueve.
// Cuenta pura: sin base ni pantalla.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// El playón de la escuela del 10-nov, con sus 101 mesas en la serpentina de
/// siempre: la 101 queda junto al escenario.
const _playon = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8);

ArmadoSalon _salon({FinNumeracion fin = FinNumeracion.escenario}) =>
    ArmarAMedida.armar(
      OpcionesAMedida(playon: _playon, cantidad: 101, fin: fin),
    ).armado;

ContratoAlumno _familia(
  String id, {
  int extras = 0,
  List<int> mesas = const [],
  bool baja = false,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${baja ? '[BAJA] ' : ''}${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

/// Una escuela ya sorteada: una familia en cada mesa de la 1 a la 100, menos la
/// 9 (que es de [tarde]) y la 52, que quedó libre.
List<ContratoAlumno> _sorteados() => [
      for (var n = 1; n <= 100; n++)
        if (n != 9 && n != 52) _familia('f$n', mesas: [n]),
    ];

String _lugar(MesaPlano m) => '${m.numero} ${m.hoja} ${m.x} ${m.y}';

double _medio(ArmadoSalon a) => EditarArmado.centroX(a, a.hojas.last.id);

PlanMesasNuevas _planear(
  ArmadoSalon armado,
  List<ContratoAlumno> alumnos, {
  ConfigPlano config = ConfigPlano.vacia,
  Map<String, DateTime> llegada = const {},
}) =>
    MesasNuevasAlFondo.planear(
      armado: armado,
      config: config,
      alumnos: alumnos,
      pedidos: SorteoMesasMotor.pedidos(alumnos),
      llegada: llegada,
      por: 'Jefe',
      ahora: DateTime.utc(2026, 11, 11, 12),
    );

void main() {
  final salon = _salon();

  // La familia de la mesa 9 pagó su adicional después del sorteo: le falta una.
  final tarde = _familia('tarde', extras: 1, mesas: [9]);

  group('una familia que llegó tarde', () {
    final alumnos = [..._sorteados(), tarde];
    final plan = _planear(salon, alumnos);

    test('recibe la 102: el número que sigue, no el hueco de la 52', () {
      expect(plan.mesas.map((m) => (m.numero, m.alumnoId)), [(102, 'tarde')]);
      expect(plan.porAlumno, {
        'tarde': [102],
      });
      expect(plan.armado.existe(102), isTrue);
      expect(plan.armado.mesas, hasLength(102));
    });

    test('ninguna otra mesa se mueve ni cambia de número', () {
      expect(
        [for (final m in plan.armado.mesas) if (m.numero <= 101) _lugar(m)],
        [for (final m in salon.mesas) _lugar(m)],
      );
    });

    test('la 102 va al fondo, a la derecha, a continuación de la última fila',
        () {
      final m = plan.armado.mesa(102)!;
      final cx = _medio(salon);
      final ultimaFila = salon.mesas
          .where((x) => x.x >= cx)
          .map((x) => x.y)
          .reduce(max);
      final masAfuera = salon.mesas
          .where((x) => x.x >= cx && (ultimaFila - x.y).abs() < 1)
          .map((x) => x.x)
          .reduce(max);
      expect(m.x > cx, isTrue, reason: 'a la derecha');
      expect(m.y, closeTo(ultimaFila, 0.01), reason: 'en la última fila');
      expect(m.x > masAfuera, isTrue, reason: 'sigue a la de más afuera');
      final paso = salon.aUnidades(ArmarAMedida.lugarDe(salon)!);
      expect(m.x - masAfuera, closeTo(paso, 0.5), reason: 'a un paso');
    });

    test('entra en el hormigón y no pisa a ninguna', () {
      final a = plan.armado;
      final m = a.mesa(102)!;
      expect(
        a.hoja(m.hoja)!.contorno!.contieneCirculo(m.x, m.y, a.radio),
        isTrue,
      );
      expect(EditarArmado.pisadas(a), isEmpty);
    });

    test('queda fijada para esa familia, con el motivo', () {
      final f = plan.config.fijadas[102]!;
      expect(f.alumnoId, 'tarde');
      expect(f.motivo, MesasNuevasAlFondo.motivo);
      expect(f.por, 'Jefe');
      expect(plan.config.fijadas, hasLength(1));
    });

    test('el sorteo de siempre se la entrega y no mueve a nadie', () {
      final entrada = EntradaSorteoPlano(
        armado: plan.armado,
        config: plan.config,
        alumnos: alumnos,
      );
      expect(SorteoConPlano.preparar(entrada).entra, isTrue);
      final r = SorteoConPlano.sortear(entrada, random: Random(1));
      expect(SorteoConPlano.validar(entrada, r), isNull);
      expect(r.asignaciones, {
        'tarde': [9, 102],
      });
    });

    test('sin esto, el sorteo le da la 52, que es la única libre', () {
      final entrada = EntradaSorteoPlano(armado: salon, alumnos: alumnos);
      final r = SorteoConPlano.sortear(entrada, random: Random(1));
      expect(r.asignaciones['tarde'], [9, 52]);
    });
  });

  group('varias a la vez', () {
    // Otra familia entera sin mesa (pagó su primera cuota después) y una que
    // compró dos adicionales.
    final nueva = _familia('nueva');
    final dos = _familia('dos', extras: 2, mesas: [52]);
    final alumnos = [..._sorteados(), tarde, nueva, dos];

    test('por orden de llegada: quien pagó primero recibe el número más bajo',
        () {
      final plan = _planear(salon, alumnos, llegada: {
        'nueva': DateTime.utc(2026, 11, 10, 20),
        'tarde': DateTime.utc(2026, 11, 10, 21),
        'dos': DateTime.utc(2026, 11, 10, 22),
      });
      expect(plan.mesas.map((m) => (m.numero, m.alumnoId)), [
        (102, 'nueva'),
        (103, 'tarde'),
        (104, 'dos'),
        (105, 'dos'),
      ]);
      expect(EditarArmado.pisadas(plan.armado), isEmpty);
    });

    test('sin hora de llegada, al final y por nombre', () {
      final plan = _planear(salon, alumnos, llegada: {
        'tarde': DateTime.utc(2026, 11, 10, 21),
      });
      expect(plan.mesas.map((m) => m.alumnoId), [
        'tarde',
        'dos',
        'dos',
        'nueva',
      ]);
    });

    test('las dos mesas de una familia quedan juntas', () {
      final plan = _planear(salon, alumnos, llegada: {
        'dos': DateTime.utc(2026, 11, 10, 20),
      });
      final suyas = plan.porAlumno['dos']!;
      expect(suyas, hasLength(2));
      final a = plan.armado;
      final paso = a.aUnidades(ArmarAMedida.lugarDe(salon)!);
      expect(
        a.mesa(suyas[0])!.distanciaA(a.mesa(suyas[1])!),
        closeTo(paso, 0.5),
      );
    });

    test('el sorteo se las entrega a todos, sin mover a nadie', () {
      final plan = _planear(salon, alumnos);
      final entrada = EntradaSorteoPlano(
        armado: plan.armado,
        config: plan.config,
        alumnos: alumnos,
      );
      final r = SorteoConPlano.sortear(entrada, random: Random(3));
      expect(SorteoConPlano.validar(entrada, r), isNull);
      expect(r.asignaciones.keys.toSet(), {'tarde', 'nueva', 'dos'});
      for (final e in plan.porAlumno.entries) {
        expect(r.asignaciones[e.key], containsAll(e.value));
      }
      expect(r.asignaciones['tarde'], contains(9));
      expect(r.asignaciones['dos'], contains(52));
      expect(r.asignaciones['dos'], hasLength(3));
    });

    test('muchas: ninguna se pisa y ninguna queda en el pasillo del medio', () {
      final muchas = [
        ..._sorteados(),
        for (var i = 0; i < 14; i++) _familia('n$i'),
      ];
      final plan = _planear(salon, muchas);
      expect(plan.mesas, hasLength(14));
      expect(
        plan.mesas.map((m) => m.numero),
        [for (var n = 102; n <= 115; n++) n],
      );
      expect(EditarArmado.pisadas(plan.armado), isEmpty);
    });
  });

  group('el número', () {
    test('no llena un hueco del medio', () {
      final sinLa50 = EditarArmado.sacar(salon, 50);
      final alumnos = [
        for (final a in _sorteados())
          if (a.id != 'f50') a,
        tarde,
      ];
      expect(_planear(sinLa50, alumnos).mesas.single.numero, 102);
    });

    test('no repite el de una mesa que se sacó ni el de una baja', () {
      final conMemoria = salon.copyWith(ultimoNumero: 110);
      expect(
        _planear(conMemoria, [..._sorteados(), tarde]).mesas.single.numero,
        111,
      );
      final conBaja = [
        ..._sorteados(),
        tarde,
        _familia('baja', mesas: [150], baja: true),
      ];
      expect(_planear(salon, conBaja).mesas.single.numero, 151);
    });

    test('tampoco el de una mesa fijada o libre', () {
      final config = ConfigPlano(
        fijadas: {120: const MesaFijada(alumnoId: 'otro')},
      );
      expect(
        _planear(salon, [..._sorteados(), tarde], config: config)
            .mesas
            .single
            .numero,
        121,
      );
    });
  });

  group('a quién no', () {
    test('quien tiene una mesa fijada esperándolo no recibe una nueva', () {
      final config = ConfigPlano(
        fijadas: {52: const MesaFijada(alumnoId: 'tarde', motivo: 'junior')},
      );
      final plan = _planear(salon, [..._sorteados(), tarde], config: config);
      expect(plan.vacio, isTrue);
      expect(plan.armado, same(salon));
      expect(plan.config, same(config));
    });

    test('quien ya tiene todas sus mesas, los de baja y los excluidos', () {
      final alumnos = [
        ..._sorteados(),
        _familia('completa', extras: 1, mesas: [9, 52]),
        _familia('baja', baja: true),
        _familia('sinpagar'),
      ];
      final plan = MesasNuevasAlFondo.planear(
        armado: salon,
        config: ConfigPlano.vacia,
        alumnos: alumnos,
        // El candado: a quien no pagó nada no se le sortea.
        pedidos: SorteoMesasMotor.pedidos(alumnos, sinMesa: {'sinpagar'}),
      );
      expect(plan.vacio, isTrue);
    });

    test('una familia con un número que no está en el plano no se toca', () {
      final rara = _familia('rara', extras: 1, mesas: [300]);
      expect(_planear(salon, [..._sorteados(), rara]).vacio, isTrue);
    });
  });

  group('cuándo se puede', () {
    test('antes del sorteo no: el salón se arma con las mesas que hacen falta',
        () {
      expect(
        MesasNuevasAlFondo.motivoSinMesasNuevas(salon, [_familia('a')]),
        contains('primero se sortea'),
      );
      expect(
        MesasNuevasAlFondo.motivoSinMesasNuevas(
          salon,
          [_familia('b', mesas: [3], baja: true)],
        ),
        isNotNull,
        reason: 'una baja que conserva su mesa no es un sorteo',
      );
    });

    test('en un armado del Canva no', () {
      expect(
        MesasNuevasAlFondo.motivoSinMesasNuevas(
          ArmadosPredefinidos.todos.first,
          [_familia('a', mesas: [1])],
        ),
        contains('Canva'),
      );
    });

    test('con el sorteo hecho y un salón a medida, sí', () {
      expect(
        MesasNuevasAlFondo.motivoSinMesasNuevas(salon, _sorteados()),
        isNull,
      );
    });
  });

  test('con la numeración al fondo, la 102 sigue al lado de la 101', () {
    final alFondo = _salon(fin: FinNumeracion.fondo);
    final plan = _planear(alFondo, [..._sorteados(), tarde]);
    final a = plan.armado;
    final paso = a.aUnidades(ArmarAMedida.lugarDe(alFondo)!);
    expect(plan.mesas.single.numero, 102);
    expect(
      a.mesa(102)!.distanciaA(a.mesa(101)!),
      closeTo(paso, 0.5),
      reason: 'la 101 es la de más afuera de la última fila',
    );
  });

  test('el plano no avisa "los números no siguen el salón" por la mesa nueva',
      () {
    // Se vio en la muestra del 11-nov: después de dar la 102 al fondo, el
    // plano decía "deshacé el sorteo para ordenarlos". El salto es a propósito.
    final alumnos = [..._sorteados(), tarde];
    final plan = _planear(salon, alumnos);
    final sentados = [
      for (final a in alumnos)
        a.id == 'tarde' ? _familia('tarde', extras: 1, mesas: [9, 102]) : a,
    ];
    final plano = PlanoDeLaFiesta.desde(
      armado: plan.armado,
      config: plan.config,
      alumnos: sentados,
    );
    expect(
      plano.avisos.where((a) => a.texto.contains('no siguen el salón')),
      isEmpty,
    );

    // Un salón con los números de verdad mezclados sigue avisando.
    final mezclado = plan.armado.copyWith(mesas: [
      for (final m in plan.armado.mesas)
        m.numero == 3
            ? MesaPlano(numero: 60, hoja: m.hoja, x: m.x, y: m.y)
            : m.numero == 60
                ? MesaPlano(numero: 3, hoja: m.hoja, x: m.x, y: m.y)
                : m,
    ]);
    expect(
      PlanoDeLaFiesta.desde(
        armado: mezclado,
        config: plan.config,
        alumnos: sentados,
      ).avisos.where((a) => a.texto.contains('no siguen el salón')),
      isNotEmpty,
    );
  });

  test('en un salón de dos hojas, la mesa nueva va en la del fondo', () {
    final dosHojas = ArmarAMedida.armar(
      const OpcionesAMedida(playon: _playon, cantidad: 101, partirEnFila: 5),
    ).armado;
    expect(dosHojas.hojas, hasLength(2));
    final plan = _planear(dosHojas, [..._sorteados(), tarde]);
    expect(plan.armado.mesa(102)!.hoja, 'B');
    expect(EditarArmado.pisadas(plan.armado), isEmpty);
  });
}
