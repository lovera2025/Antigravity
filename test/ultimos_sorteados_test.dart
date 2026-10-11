import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/registro_sorteo.dart';
import 'package:arguello_events/features/eventos/services/ultimos_sorteados.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

ContratoAlumno _alumno(String id, String? mesa) => ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa: mesa,
    );

// 12/11/2026 21:40 en Argentina.
final _base = DateTime.utc(2026, 11, 13, 0, 40);

SorteoMesasRegistro _registro(
  TipoRegistroSorteo tipo,
  Map<String, String> resultado, {
  required int dia,
  Map<String, String>? antes,
  Map<String, String>? quedan,
}) =>
    SorteoMesasRegistro(
      id: 'r$dia',
      eventoId: 'e',
      tipo: tipo,
      resultado: resultado,
      antes: antes,
      quedan: quedan,
      hechoPor: 'Jefe',
      createdAt: _base.add(Duration(days: dia)),
    );

SorteoMesasRegistro _sorteo(
  Map<String, String> resultado, {
  required int dia,
  Map<String, String>? antes = const {},
}) =>
    _registro(TipoRegistroSorteo.sorteo, resultado, dia: dia, antes: antes);

/// El renglón que deja "deshacer solo los últimos", como lo arma la pantalla.
SorteoMesasRegistro _deshacerUltimos(UltimosSorteados u, {required int dia}) =>
    _registro(
      TipoRegistroSorteo.deshacer,
      u.tenian,
      dia: dia,
      quedan: u.quedan,
    );

/// Los alumnos después de guardar lo que dice el plan.
List<ContratoAlumno> _aplicar(
  List<ContratoAlumno> alumnos,
  Map<String, String?> numeros,
) =>
    [
      for (final a in alumnos)
        numeros.containsKey(a.id) ? _alumno(a.id, numeros[a.id]) : a,
    ];

void main() {
  group('los sorteos en pie', () {
    test('sin registro no hay ninguno', () {
      expect(UltimosSorteados.sorteosEnPie(const []), isEmpty);
      expect(UltimosSorteados.de(const [], [_alumno('a', '12')]), isNull);
    });

    test('cada sorteo se apila, en orden de fecha', () {
      final primero = _sorteo({'a': '1'}, dia: 0);
      final segundo = _sorteo({'b': '2'}, dia: 3);
      expect(
        UltimosSorteados.sorteosEnPie([segundo, primero]),
        [primero, segundo],
      );
    });

    test('deshacer todo los saca a todos', () {
      final registros = [
        _sorteo({'a': '1'}, dia: 0),
        _sorteo({'b': '2'}, dia: 3),
        _registro(TipoRegistroSorteo.deshacer, {'a': '1', 'b': '2'}, dia: 4),
      ];
      expect(UltimosSorteados.sorteosEnPie(registros), isEmpty);
    });

    test('deshacer solo los últimos saca el de arriba', () {
      final primero = _sorteo({'a': '1'}, dia: 0);
      final registros = [
        primero,
        _sorteo({'b': '2'}, dia: 3),
        _registro(
          TipoRegistroSorteo.deshacer,
          {'b': '2'},
          dia: 4,
          quedan: const {},
        ),
      ];
      expect(UltimosSorteados.sorteosEnPie(registros), [primero]);
    });

    test('una restauración vuelve a apilar', () {
      final restaurado = _registro(
        TipoRegistroSorteo.restaurar,
        {'a': '1'},
        dia: 2,
      );
      final registros = [
        _sorteo({'a': '1'}, dia: 0),
        _registro(TipoRegistroSorteo.deshacer, {'a': '1'}, dia: 1),
        restaurado,
      ];
      expect(UltimosSorteados.sorteosEnPie(registros), [restaurado]);
    });
  });

  group('deshacer solo los últimos', () {
    // El primer sorteo sentó a `a` y `b`. Después se sorteó a los que
    // faltaban: `c` (nuevo) y `a`, que compró otra mesa.
    final primero = _sorteo({'a': '12', 'b': '14'}, dia: 0);
    final faltaban = _sorteo(
      {'a': '12, 13', 'c': '20'},
      dia: 3,
      antes: {'a': '12'},
    );
    final registros = [primero, faltaban];
    final alumnos = [
      _alumno('a', '12, 13'),
      _alumno('b', '14'),
      _alumno('c', '20'),
      _alumno('d', null),
    ];

    test('el nuevo queda sin mesa y al que compró otra se le saca solo esa',
        () {
      final u = UltimosSorteados.de(registros, alumnos)!;
      expect(u.sorteo, faltaban);
      expect(u.familias, {'a', 'c'});
      expect(u.aGuardar, {'a': '12', 'c': null});
      expect(u.tenian, {'a': '12, 13', 'c': '20'});
      expect(u.quedan, {'a': '12'});
      expect(u.noSeTocan, isEmpty);
      expect(u.eraElUnico, isFalse);
      expect(u.deshacerSoloCambiaAlgo, isTrue);
      expect(u.planillaSolaCambiaAlgo, isTrue);
    });

    test('los del primer sorteo no aparecen en lo que se guarda', () {
      final u = UltimosSorteados.de(registros, alumnos)!;
      expect(u.aGuardar.containsKey('b'), isFalse);
      expect(u.otrosConMesa, 1);
    });

    test('después de deshacerlos, el registro explica las mesas de hoy', () {
      final u = UltimosSorteados.de(registros, alumnos)!;
      final despues = _aplicar(alumnos, u.aGuardar);
      final conDeshacer = [...registros, _deshacerUltimos(u, dia: 4)];

      expect(RegistroSorteo.resumir(conDeshacer, despues).cambiosAMano, 0);
      expect(UltimosSorteados.sorteosEnPie(conDeshacer), [primero]);
      // Lo que queda en pie es el primer sorteo, que es de todos los que
      // tienen mesa: ya no hay "solo los últimos" que ofrecer.
      final otraVez = UltimosSorteados.de(conDeshacer, despues)!;
      expect(otraVez.sorteo, primero);
      expect(otraVez.deshacerSoloCambiaAlgo, isFalse);
      expect(otraVez.eraElUnico, isTrue);
    });

    test('el deshacer parcial va y vuelve de la base igual', () {
      final u = UltimosSorteados.de(registros, alumnos)!;
      final vuelta = SorteoMesasRegistro.fromMap(
        _deshacerUltimos(u, dia: 4).toMap(),
      );
      expect(vuelta.esDeshacerDeUltimos, isTrue);
      expect(vuelta.resultado, {'a': '12, 13', 'c': '20'});
      expect(vuelta.quedan, {'a': '12'});
      expect(vuelta.alumnos, 2);
    });

    test('a quien mudaron de mesa después no se lo toca, y se lo nombra', () {
      final mudados = _aplicar(alumnos, {'c': '31'});
      final u = UltimosSorteados.de(registros, mudados)!;
      expect(u.aGuardar, {'a': '12'});
      expect(u.noSeTocan.single.alumnoId, 'c');
      expect(u.noSeTocan.single.nombre, 'ALUMNO c');
      expect(
        u.noSeTocan.single.motivo,
        'le cambiaron la mesa después de ese sorteo',
      );
    });

    test('a quien ya le sacaron la mesa a mano tampoco', () {
      final u = UltimosSorteados.de(
        registros,
        _aplicar(alumnos, {'c': null}),
      )!;
      expect(u.aGuardar, {'a': '12'});
      expect(u.noSeTocan.single.motivo, 'ya no tiene mesa');
    });

    test('si todos cambiaron después, no hay nada que deshacer solo', () {
      final u = UltimosSorteados.de(
        registros,
        _aplicar(alumnos, {'a': '40', 'c': '41'}),
      )!;
      expect(u.aGuardar, isEmpty);
      expect(u.noSeTocan, hasLength(2));
      expect(u.deshacerSoloCambiaAlgo, isFalse);
    });

    test('quien ya no está en la fiesta no cuenta ni se nombra', () {
      final sinC = alumnos.where((a) => a.id != 'c').toList();
      final u = UltimosSorteados.de(registros, sinC)!;
      expect(u.familias, {'a'});
      expect(u.aGuardar, {'a': '12'});
      expect(u.noSeTocan, isEmpty);
    });

    test('"12-13" y "12, 13" son lo mismo: se revierte igual', () {
      final u = UltimosSorteados.de(
        registros,
        _aplicar(alumnos, {'a': '12-13'}),
      )!;
      expect(u.aGuardar['a'], '12');
      expect(u.tenian['a'], '12-13');
    });
  });

  group('una mesa cargada a mano antes del sorteo', () {
    // `a` tenía la 12 escrita a mano (el registro nunca la vio) y el sorteo de
    // los que faltaban le sumó la 13.
    final primero = _sorteo({'b': '14'}, dia: 0);

    test('con lo que tenía anotado, vuelve su mesa con sus mismas palabras',
        () {
      final faltaban = _sorteo(
        {'a': '12, 13'},
        dia: 3,
        antes: {'a': '12 (pedida)'},
      );
      final u = UltimosSorteados.de(
        [primero, faltaban],
        [_alumno('a', '12, 13'), _alumno('b', '14')],
      )!;
      expect(u.aGuardar, {'a': '12 (pedida)'});
      expect(u.quedan, {'a': '12 (pedida)'});
    });

    test('si lo anotado no es parte de lo que dejó el sorteo, no se toca', () {
      final faltaban = _sorteo({'a': '12, 13'}, dia: 3, antes: {'a': '50'});
      final u = UltimosSorteados.de(
        [primero, faltaban],
        [_alumno('a', '12, 13'), _alumno('b', '14')],
      )!;
      expect(u.aGuardar, isEmpty);
      expect(
        u.noSeTocan.single.motivo,
        'no quedó anotado qué mesa tenía antes',
      );
    });
  });

  group('un sorteo que no anotó lo que tenía cada uno', () {
    final primero = _sorteo({'a': '12', 'b': '14'}, dia: 0, antes: null);
    final faltaban = _sorteo({'a': '12, 13', 'c': '20'}, dia: 3, antes: null);
    final alumnos = [
      _alumno('a', '12, 13'),
      _alumno('b', '14'),
      _alumno('c', '20'),
    ];

    test('lo saca de repasar el registro hasta ese sorteo', () {
      final u = UltimosSorteados.de([primero, faltaban], alumnos)!;
      expect(u.aGuardar, {'a': '12', 'c': null});
      expect(u.quedan, {'a': '12'});
    });

    test('cuenta los cambios con motivo de antes, no los de después', () {
      MovimientoMesas mover(String id, String de, String a, int dia) =>
          MovimientoMesas(
            id: 'm$dia',
            eventoId: 'e',
            tipo: TipoMovimientoMesas.mover,
            antes: {id: de},
            despues: {id: a},
            motivo: 'pedido',
            createdAt: _base.add(Duration(days: dia)),
          );
      // Entre los dos sorteos, `a` pasó de la 12 a la 30; el segundo sorteo le
      // sumó la 31.
      final segundo = _sorteo({'a': '30, 31'}, dia: 3, antes: null);
      final u = UltimosSorteados.de(
        [primero, segundo],
        [_alumno('a', '30, 31'), _alumno('b', '14')],
        movimientos: [mover('a', '12', '30', 1), mover('b', '14', '15', 5)],
      )!;
      expect(u.aGuardar, {'a': '30'});
    });
  });

  group('cuándo hay algo que elegir', () {
    test('un solo sorteo que es de todos: deshacer es deshacer todo', () {
      final u = UltimosSorteados.de(
        [_sorteo({'a': '1', 'b': '2'}, dia: 0)],
        [_alumno('a', '1'), _alumno('b', '2'), _alumno('c', null)],
      )!;
      expect(u.eraElUnico, isTrue);
      expect(u.deshacerSoloCambiaAlgo, isFalse);
      expect(u.planillaSolaCambiaAlgo, isFalse);
    });

    test('un solo sorteo con mesas cargadas a mano aparte: sí hay diferencia',
        () {
      final u = UltimosSorteados.de(
        [_sorteo({'a': '1'}, dia: 0)],
        [_alumno('a', '1'), _alumno('b', '50')],
      )!;
      expect(u.eraElUnico, isTrue);
      expect(u.aGuardar, {'a': null});
      expect(u.deshacerSoloCambiaAlgo, isTrue);
      expect(u.planillaSolaCambiaAlgo, isTrue);
    });

    test('si el último solo completó a una familia, deshacerlo cambia algo '
        'aunque la planilla sea la misma', () {
      final u = UltimosSorteados.de(
        [
          _sorteo({'a': '12'}, dia: 0),
          _sorteo({'a': '12, 13'}, dia: 3, antes: {'a': '12'}),
        ],
        [_alumno('a', '12, 13')],
      )!;
      expect(u.otrosConMesa, 0);
      expect(u.deshacerSoloCambiaAlgo, isTrue);
      expect(u.planillaSolaCambiaAlgo, isFalse);
    });
  });

  group('lo que se anota al sortear', () {
    test('solo las familias del sorteo que ya tenían mesa', () {
      final antes = UltimosSorteados.antesDe(
        [
          _alumno('a', ' 12 '),
          _alumno('b', '14'),
          _alumno('c', null),
          _alumno('d', '  '),
        ],
        {'a': '12, 13', 'c': '20', 'd': '21'},
      );
      expect(antes, {'a': '12'});
    });

    test('un sorteo va y vuelve de la base con lo que tenía cada uno', () {
      final original = _sorteo(
        {'a': '12, 13', 'c': '20'},
        dia: 3,
        antes: {'a': '12'},
      );
      final vuelta = SorteoMesasRegistro.fromMap(original.toMap());
      expect(vuelta.resultado, {'a': '12, 13', 'c': '20'});
      expect(vuelta.antes, {'a': '12'});
      expect(vuelta.quedan, isNull);
      expect(vuelta.esDeshacerDeUltimos, isFalse);
      // Lo anotado no cuenta como una familia más.
      expect(original.toMap()['alumnos'], 2);
    });

    test('anotar que nadie tenía mesa no es lo mismo que no anotar', () {
      final anotado = SorteoMesasRegistro.fromMap(
        _sorteo({'a': '1'}, dia: 0).toMap(),
      );
      final sinAnotar = SorteoMesasRegistro.fromMap(
        _sorteo({'a': '1'}, dia: 0, antes: null).toMap(),
      );
      expect(anotado.antes, isEmpty);
      expect(sinAnotar.antes, isNull);
    });

    test('una clave reservada que esta versión no conoce no es una familia',
        () {
      final r = SorteoMesasRegistro.fromMap({
        'id': 'r',
        'evento_id': 'e',
        'tipo': 'sorteo',
        'resultado': '{"a": "1", "_otra": {"a": "9"}}',
        'created_at': _base.toIso8601String(),
      });
      expect(r.resultado, {'a': '1'});
    });
  });
}
