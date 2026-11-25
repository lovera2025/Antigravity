// DAR MESA (6.9.4): el jefe le da la mesa a quien no la tiene porque no pagó,
// uno por uno o a todos, y el número aparece al instante.
//
// El salón es el de la Técnica del 25-nov-2026, con nombres inventados: cuatro
// familias sin nada pagado con su mesa fijada por el jefe esperándolas (42, 47,
// 52 y 54), las mesas nuevas al fondo de la 102 a la 107, la 106 vacía (el jefe
// pasó a esa familia a la 51) y RIVAS con la 107, al que le falta la adicional.
// Cuenta pura: sin base ni pantalla.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/mesa_nueva_sola.dart';
import 'package:arguello_events/features/plano/services/mesa_que_da_el_jefe.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _playon = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8);
final _t0 = DateTime.utc(2026, 11, 10, 22, 42);

ContratoAlumno _familia(
  String id, {
  String? mesa,
  int extras = 0,
  bool baja = false,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${baja ? '[BAJA] ' : ''}${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 1,
      montoTotalPactado: 315000,
      saldoDeudor: 315000,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa: mesa,
      cursoDivision: '2DA',
    );

Map<String, dynamic> _pago(String concepto, double monto, DateTime cuando) => {
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'anulado': 0,
      'created_at': cuando.toIso8601String(),
      'fecha_pago': cuando.toIso8601String(),
    };

/// La Técnica, armada como pasó.
class _Tecnica {
  late final ArmadoSalon armado;
  late final ConfigPlano config;
  late final List<ContratoAlumno> alumnos;
  late final List<SorteoMesasRegistro> registros;
  final pagos = <String, List<Map<String, dynamic>>>{};

  /// [vaciaOcupada]: la 106 tiene familia (no hay vacía en el fondo).
  _Tecnica({
    bool vaciaOcupada = false,
    bool otraVacia = false,
    List<ContratoAlumno> extra = const [],
  }) {
    final salon = ArmarAMedida.armar(
      const OpcionesAMedida(playon: _playon, cantidad: 101),
    ).armado;
    // Las que llegaron después del sorteo: una mesa nueva al fondo cada una,
    // de la 102 a la 107, por orden de llegada.
    final tarde = {
      't102': 9,
      't103': 66,
      't104': 48,
      't105': 26,
      'ponce': 45,
    };
    final antesDeLasNuevas = [
      for (final e in tarde.entries)
        _familia(e.key, mesa: '${e.value}', extras: 1),
      // A RIVAS el programa le dio solo la del contrato: la adicional no
      // estaba paga.
      _familia('rivas'),
    ];
    final plan = MesasNuevasAlFondo.planear(
      armado: salon,
      config: ConfigPlano.vacia,
      alumnos: antesDeLasNuevas,
      pedidos: SorteoMesasMotor.pedidos(antesDeLasNuevas),
      llegada: {
        for (final (i, id) in [...tarde.keys, 'rivas'].indexed)
          id: _t0.add(Duration(hours: i + 1)),
      },
      por: 'El programa',
      ahora: _t0,
    );
    armado = plan.armado;
    final nuevas = plan.porAlumno;
    // Como pasó: a PONCE le tocó la 106 y a RIVAS la 107.
    if (nuevas['rivas']?.single != 107 || nuevas['ponce']?.single != 106) {
      throw StateError('el salón de prueba no salió como la Técnica: $nuevas');
    }

    // El jefe le dejó su mesa fijada a cuatro que no pagaron nada, y pasó a
    // PONCE de la 106 a la 51: la 106 quedó vacía.
    final fijadas = <int, MesaFijada>{
      for (final e in plan.config.fijadas.entries)
        if (e.key != 106) e.key: e.value,
      51: const MesaFijada(alumnoId: 'ponce', motivo: MesasNuevasAlFondo.motivo),
      42: const MesaFijada(alumnoId: 'luna', motivo: 'junior', por: 'Jefe'),
      47: const MesaFijada(alumnoId: 'morales', motivo: 'junior', por: 'Jefe'),
      52: const MesaFijada(alumnoId: 'navarro', motivo: 'junior', por: 'Jefe'),
      54: const MesaFijada(alumnoId: 'olivera', motivo: 'junior', por: 'Jefe'),
    };
    config = ConfigPlano(fijadas: fijadas);

    final propias = {9, 26, 45, 48, 66, 42, 47, 51, 52, 54};
    alumnos = [
      for (var n = 1; n <= 101; n++)
        if (!propias.contains(n) && !(otraVacia && n == 30))
          _familia('f$n', mesa: '$n'),
      for (final e in tarde.entries)
        _familia(
          e.key,
          mesa: e.key == 'ponce' ? '45, 51' : '${e.value}, ${nuevas[e.key]!.single}',
          extras: 1,
        ),
      _familia('rivas', mesa: '107', extras: 1),
      for (final id in ['luna', 'morales', 'navarro', 'olivera'])
        _familia(id),
      if (vaciaOcupada) _familia('otra', mesa: '106'),
      ...extra,
    ];
    pagos['rivas'] = [
      _pago('Cuota Base (1/9)', 200000, DateTime.utc(2026, 11, 24, 19)),
    ];
    registros = [
      SorteoMesasRegistro(
        id: 'sorteo',
        eventoId: 'e',
        tipo: TipoRegistroSorteo.sorteo,
        resultado: {for (final a in alumnos) a.id: a.numeroMesa ?? ''},
        hechoPor: 'Jefe',
        createdAt: _t0,
      ),
      for (final e in nuevas.entries)
        SorteoMesasRegistro(
          id: 'auto-${e.key}',
          eventoId: 'e',
          tipo: TipoRegistroSorteo.sorteo,
          resultado: {e.key: e.value.join(', ')},
          nuevas: {e.key: e.value.join(', ')},
          automatico: true,
          hechoPor: 'El programa',
          createdAt: _t0.add(const Duration(days: 1)),
        ),
      // Otra mesa del fondo que quedó vacía, lejos de RIVAS: la 30.
      if (otraVacia)
        SorteoMesasRegistro(
          id: 'auto-x30',
          eventoId: 'e',
          tipo: TipoRegistroSorteo.sorteo,
          resultado: const {'x30': '30'},
          nuevas: const {'x30': '30'},
          automatico: true,
          createdAt: _t0.add(const Duration(days: 2)),
        ),
    ];
  }

  PlanoEvento get plano => PlanoEvento.nuevo(
        eventoId: 'e',
        armado: armado,
        estilo: EstiloPlano.gala,
        modo: ModoSorteo.entera,
        ahora: _t0,
      ).copyWith(config: config, ahora: _t0);

  CuentaMesaNueva? dar(Set<String> elegidos, {int semilla = 0}) =>
      MesaQueDaElJefe.calcular(
        plano: plano,
        alumnos: alumnos,
        pagos: pagos,
        registros: registros,
        elegidos: elegidos,
        azar: Random(semilla),
        por: 'Jefe',
        ahora: DateTime.utc(2026, 11, 26, 12),
      );
}

const _losCinco = {'luna', 'morales', 'navarro', 'olivera', 'rivas'};

void main() {
  group('la Técnica', () {
    final t = _Tecnica();

    test('la 106 es la única mesa del fondo que quedó vacía', () {
      expect(
        MesasNuevasAlFondo.vaciasDelFondo(
          armado: t.armado,
          config: t.config,
          alumnos: t.alumnos,
          registros: t.registros,
        ),
        {106},
      );
    });

    test('a quiénes se les puede dar: los cinco, por apellido', () {
      expect(
        [for (final a in MesaQueDaElJefe.aQuienes(t.alumnos)) a.id],
        ['luna', 'morales', 'navarro', 'olivera', 'rivas'],
      );
    });

    test('DAR MESA A TODOS: cada uno su fijada, y RIVAS la 106 detrás de su 107',
        () {
      final c = t.dar(_losCinco)!;
      expect(c.asignaciones, {
        'luna': [42],
        'morales': [47],
        'navarro': [52],
        'olivera': [54],
        'rivas': [107, 106],
      });
      expect(
        MesasExtraUtils.formatearAsignacionMesas(c.asignaciones['rivas']!),
        '107, 106',
      );
      expect(c.dadas['rivas'], [106]);
      // Ninguna mesa nueva: la 106 ya estaba en el salón.
      expect(c.nuevas.armado.mesas, hasLength(t.armado.mesas.length));
      expect(c.nuevas.config.fijadas[106]?.alumnoId, 'rivas');
    });

    test('nadie más se mueve, y no queda ninguna mesa vacía', () {
      final c = t.dar(_losCinco)!;
      expect(c.asignaciones.keys.toSet(), _losCinco);
      final ocupadas = {
        for (final a in t.alumnos)
          ...(c.asignaciones[a.id] ??
              MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa)),
      };
      expect(
        [for (final m in c.nuevas.armado.mesas) if (!ocupadas.contains(m.numero)) m.numero],
        isEmpty,
      );
    });

    test('a uno solo: RIVAS recibe la 106 y su principal sigue siendo la 107',
        () {
      final c = t.dar({'rivas'})!;
      expect(c.asignaciones, {
        'rivas': [107, 106],
      });
      expect(c.antes['rivas'], [107]);
    });

    test('a uno de los que tenían su mesa fijada: recibe esa, sin mesas nuevas',
        () {
      final c = t.dar({'luna'})!;
      expect(c.asignaciones, {
        'luna': [42],
      });
      expect(c.nuevas.vacio, isTrue);
    });

    test('a quien ya tiene todas sus mesas no le da nada', () {
      expect(t.dar({'f1'}), isNull);
      expect(t.dar({}), isNull);
    });
  });

  test('sin una vacía en el fondo, la adicional es una nueva: 107 y 108', () {
    final t = _Tecnica(vaciaOcupada: true);
    final c = t.dar({'rivas'})!;
    expect(c.asignaciones['rivas'], [107, 108]);
    expect(c.nuevas.armado.existe(108), isTrue);
  });

  test('con más familias que vacías, el azar decide quién recibe la 106', () {
    // Dos familias sin mesa ni fijada, y una sola vacía.
    final recibieron106 = <String>{};
    for (var semilla = 0; semilla < 20; semilla++) {
      final t = _Tecnica(extra: [_familia('uno'), _familia('dos')]);
      final c = t.dar({'uno', 'dos'}, semilla: semilla)!;
      final dadas = [...c.asignaciones['uno']!, ...c.asignaciones['dos']!];
      expect(dadas..sort(), [106, 108], reason: 'semilla $semilla');
      recibieron106.add(
        c.asignaciones['uno']!.contains(106) ? 'uno' : 'dos',
      );
    }
    expect(recibieron106, {'uno', 'dos'});
  });

  test('antes del sorteo no se puede: se sortea', () {
    final t = _Tecnica();
    final sinMesa = [
      for (final a in t.alumnos) _familia(a.id, extras: a.mesaExtraCantidad),
    ];
    expect(MesaQueDaElJefe.aQuienes(sinMesa), isEmpty);
    expect(
      () => MesaQueDaElJefe.calcular(
        plano: t.plano,
        alumnos: sinMesa,
        pagos: t.pagos,
        registros: t.registros,
        elegidos: {'rivas'},
      ),
      throwsStateError,
    );
  });

  test('a quien no pagó nada y tiene una adicional se le dan las dos', () {
    // Sin la base paga, el sorteo de siempre le daría solo la del contrato:
    // DAR MESA destraba todas las que le faltan.
    final t = _Tecnica(extra: [_familia('doble', extras: 1)]);
    final c = t.dar({'doble'})!;
    expect(c.asignaciones['doble'], hasLength(2));
    expect(c.asignaciones['doble'], contains(106));
  });

  test('con dos vacías, a RIVAS le toca la de al lado aunque el azar ponga '
      'primero a una familia sin mesa', () {
    for (var semilla = 0; semilla < 20; semilla++) {
      final t = _Tecnica(otraVacia: true, extra: [_familia('sola')]);
      final c = t.dar({'sola', 'rivas'}, semilla: semilla)!;
      expect(c.asignaciones['rivas'], [107, 106], reason: 'semilla $semilla');
      expect(c.asignaciones['sola'], [30], reason: 'semilla $semilla');
    }
  });

  test('la mesa que el programa da solo no deja la adicional con un número '
      'más chico que la principal: RIVAS paga su adicional y recibe la 108', () {
    final t = _Tecnica();
    t.pagos['rivas'] = [
      ...t.pagos['rivas']!,
      _pago('Mesa Extra (1/1)', 70000, DateTime.utc(2026, 11, 25, 10)),
    ];
    final c = MesaNuevaSola.calcular(
      plano: t.plano,
      alumnos: t.alumnos,
      pagos: t.pagos,
      registros: t.registros,
      por: 'El programa',
      ahora: DateTime.utc(2026, 11, 25, 10, 1),
    )!;
    expect(c.asignaciones['rivas'], [107, 108]);
  });

  test('los de baja no aparecen para DAR MESA', () {
    final t = _Tecnica(extra: [_familia('ida', baja: true)]);
    expect(
      MesaQueDaElJefe.aQuienes(t.alumnos).any((a) => a.id == 'ida'),
      isFalse,
    );
  });

  group('la mesa que el programa da solo también usa la vacía', () {
    test('quien paga después del sorteo recibe la 106, no la 108', () {
      final nueva = _familia('nueva');
      final t = _Tecnica(extra: [nueva]);
      t.pagos['nueva'] = [
        _pago('Cuota Base (1/9)', 35000, DateTime.utc(2026, 11, 25, 10)),
      ];
      final c = MesaNuevaSola.calcular(
        plano: t.plano,
        alumnos: t.alumnos,
        pagos: t.pagos,
        registros: t.registros,
        por: 'El programa',
        ahora: DateTime.utc(2026, 11, 25, 10, 1),
      )!;
      expect(c.asignaciones, {
        'nueva': [106],
      });
    });

    test('el renglón de DAR MESA no cuenta como "el último sorteo"', () {
      final dar = SorteoMesasRegistro(
        id: 'dar',
        eventoId: 'e',
        tipo: TipoRegistroSorteo.sorteo,
        resultado: const {'rivas': '107, 106'},
        automatico: true,
        delJefe: true,
        hechoPor: 'Jefe',
        createdAt: DateTime.utc(2026, 11, 26),
      );
      final t = _Tecnica();
      expect(MesaNuevaSola.ultimoDelJefe([...t.registros, dar]), _t0);
    });
  });

  test('el renglón guarda que lo dio el jefe, y vuelve igual', () {
    final r = SorteoMesasRegistro(
      id: 'dar',
      eventoId: 'e',
      tipo: TipoRegistroSorteo.sorteo,
      resultado: const {'rivas': '107, 106'},
      antes: const {'rivas': '107'},
      nuevas: const {'rivas': '106'},
      automatico: true,
      delJefe: true,
      hechoPor: 'Jefe',
      createdAt: DateTime.utc(2026, 11, 26),
    );
    final vuelta = SorteoMesasRegistro.fromMap(r.toMap());
    expect(vuelta.delJefe, isTrue);
    expect(vuelta.automatico, isTrue);
    expect(vuelta.resultado, {'rivas': '107, 106'});
    expect(vuelta.nuevas, {'rivas': '106'});
    expect(
      SorteoMesasRegistro.fromMap({
        ...r.toMap(),
        'resultado': '{"rivas":"107"}',
      }).delJefe,
      isFalse,
    );
  });

  test('el control final del sorteo acepta lo que dio', () {
    final t = _Tecnica();
    final c = t.dar(_losCinco)!;
    final alumnos = [
      for (final a in t.alumnos)
        c.asignaciones.containsKey(a.id)
            ? a.copyWith(
                numeroMesa:
                    MesasExtraUtils.formatearAsignacionMesas(c.asignaciones[a.id]!),
              )
            : a,
    ];
    expect(SorteoMesasMotor.ocupadas(alumnos).length,
        SorteoMesasMotor.ocupadas(t.alumnos).length + 5);
    expect(
      SorteoConPlano.sortear(
        EntradaSorteoPlano(
          armado: c.nuevas.armado,
          config: c.nuevas.config,
          alumnos: alumnos,
        ),
        random: Random(0),
      ).asignaciones.values.expand((x) => x).toSet().intersection({42, 47, 52, 54, 106}),
      isEmpty,
      reason: 'nadie más recibe esas mesas en un sorteo de los que faltan',
    );
  });
}
