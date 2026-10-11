import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/registro_sorteo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
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

SorteoMesasRegistro _registro(
  TipoRegistroSorteo tipo,
  Map<String, String> resultado, {
  required DateTime cuando,
  String? quien = 'Jefe',
}) =>
    SorteoMesasRegistro(
      id: 'r${cuando.millisecondsSinceEpoch}',
      eventoId: 'e',
      tipo: tipo,
      resultado: resultado,
      hechoPor: quien,
      createdAt: cuando,
    );

void main() {
  // 12/11/2026 21:40 en Argentina.
  final sorteo = DateTime.utc(2026, 11, 13, 0, 40);

  test('sin registro no dice nada', () {
    final r = RegistroSorteo.resumir(const [], [_alumno('a', '12')]);
    expect(r.ultimo, isNull);
    expect(r.cambiosAMano, 0);
    expect(RegistroSorteo.lineaParaPlanilla(r), isNull);
  });

  test('un sorteo que nadie tocó: sin cambios a mano', () {
    final registros = [
      _registro(
        TipoRegistroSorteo.sorteo,
        {'a': '12, 13', 'b': '14'},
        cuando: sorteo,
      ),
    ];
    final r = RegistroSorteo.resumir(registros, [
      _alumno('a', '12-13'),
      _alumno('b', '14'),
      _alumno('c', null),
    ]);
    expect(r.cambiosAMano, 0);
    expect(
      RegistroSorteo.lineaParaPlanilla(r),
      'Sorteo del 12/11/2026 21:40 hs · Jefe',
    );
  });

  test('si alguien cambió mesas a mano después, se cuentan', () {
    final registros = [
      _registro(
        TipoRegistroSorteo.sorteo,
        {'a': '12', 'b': '14'},
        cuando: sorteo,
      ),
    ];
    final r = RegistroSorteo.resumir(registros, [
      _alumno('a', '12'),
      _alumno('b', '30'), // la cambiaron
      _alumno('c', '31'), // se la pusieron a mano, no salió del sorteo
    ]);
    expect(r.cambiosAMano, 2);
    expect(
      RegistroSorteo.lineaParaPlanilla(r),
      'Sorteo del 12/11/2026 21:40 hs · Jefe · 2 cambios a mano después',
    );
  });

  test('un segundo sorteo que completa a alguien cuenta como sorteo', () {
    final registros = [
      _registro(TipoRegistroSorteo.sorteo, {'a': '12'}, cuando: sorteo),
      _registro(
        TipoRegistroSorteo.sorteo,
        {'a': '12, 13'},
        cuando: sorteo.add(const Duration(days: 3)),
      ),
    ];
    final r = RegistroSorteo.resumir(registros, [_alumno('a', '12, 13')]);
    expect(r.cambiosAMano, 0);
  });

  test('deshacer saca los números: sin mesa no es un cambio a mano', () {
    final registros = [
      _registro(TipoRegistroSorteo.sorteo, {'a': '12'}, cuando: sorteo),
      _registro(
        TipoRegistroSorteo.deshacer,
        {'a': '12'},
        cuando: sorteo.add(const Duration(hours: 1)),
        quien: 'María',
      ),
    ];
    final r = RegistroSorteo.resumir(registros, [_alumno('a', null)]);
    expect(r.cambiosAMano, 0);
    expect(
      RegistroSorteo.lineaParaPlanilla(r),
      'Sorteo deshecho el 12/11/2026 22:40 hs · María',
    );
  });

  test('restaurar vuelve a dejar los números', () {
    final registros = [
      _registro(TipoRegistroSorteo.sorteo, {'a': '12'}, cuando: sorteo),
      _registro(
        TipoRegistroSorteo.deshacer,
        {'a': '12'},
        cuando: sorteo.add(const Duration(hours: 1)),
      ),
      _registro(
        TipoRegistroSorteo.restaurar,
        {'a': '12'},
        cuando: sorteo.add(const Duration(hours: 2)),
      ),
    ];
    final r = RegistroSorteo.resumir(registros, [_alumno('a', '12')]);
    expect(r.cambiosAMano, 0);
    expect(r.ultimo!.tipo, TipoRegistroSorteo.restaurar);
  });

  test('el orden sale de la fecha, no de cómo vino la lista', () {
    final registros = [
      _registro(
        TipoRegistroSorteo.deshacer,
        {'a': '12'},
        cuando: sorteo.add(const Duration(hours: 1)),
      ),
      _registro(TipoRegistroSorteo.sorteo, {'a': '12'}, cuando: sorteo),
    ];
    final r = RegistroSorteo.resumir(registros, [_alumno('a', null)]);
    expect(r.ultimo!.tipo, TipoRegistroSorteo.deshacer);
    expect(r.cambiosAMano, 0);
  });

  group('con los que faltaban ya sorteados', () {
    // 20/11/2026 18:05 en Argentina.
    final faltaban = DateTime.utc(2026, 11, 20, 21, 5);
    final primero = _registro(
      TipoRegistroSorteo.sorteo,
      {'a': '12', 'b': '14', 'c': '15'},
      cuando: sorteo,
    );
    final segundo = _registro(
      TipoRegistroSorteo.sorteo,
      {'d': '20'},
      cuando: faltaban,
      quien: 'María',
    );
    final alumnos = [
      _alumno('a', '12'),
      _alumno('b', '14'),
      _alumno('c', '15'),
      _alumno('d', '20'),
    ];

    test('arriba van los dos sorteos, cada uno con sus familias', () {
      final r = RegistroSorteo.resumir([primero, segundo], alumnos);
      expect(r.enPie, [primero, segundo]);
      expect(
        RegistroSorteo.lineaParaPlanilla(r),
        'Sorteo del 12/11/2026 21:40 hs · Jefe · 3 familias\n'
        'Los que faltaban: 20/11/2026 18:05 hs · María · 1 familia',
      );
    });

    test('los cambios a mano se dicen al final', () {
      final r = RegistroSorteo.resumir(
        [primero, segundo],
        [...alumnos.take(3), _alumno('d', '31')],
      );
      expect(
        RegistroSorteo.lineaParaPlanilla(r),
        'Sorteo del 12/11/2026 21:40 hs · Jefe · 3 familias\n'
        'Los que faltaban: 20/11/2026 18:05 hs · María · 1 familia'
        ' · 1 cambio a mano después',
      );
    });

    test('con más de dos, nombra el primero y el último y cuenta el resto',
        () {
      final tercero = _registro(
        TipoRegistroSorteo.sorteo,
        {'e': '21', 'f': '22'},
        cuando: faltaban.add(const Duration(days: 1)),
      );
      final r = RegistroSorteo.resumir(
        [primero, segundo, tercero],
        [...alumnos, _alumno('e', '21'), _alumno('f', '22')],
      );
      expect(
        RegistroSorteo.lineaParaPlanilla(r),
        'Sorteo del 12/11/2026 21:40 hs · Jefe · 3 familias\n'
        'Los que faltaban: 21/11/2026 18:05 hs · Jefe · 2 familias'
        ' (antes, otro sorteo: 1 familia)',
      );
    });

    test('si se deshizo solo a los últimos, vuelve a nombrar el que quedó',
        () {
      final deshacer = SorteoMesasRegistro(
        id: 'z',
        eventoId: 'e',
        tipo: TipoRegistroSorteo.deshacer,
        resultado: const {'d': '20'},
        quedan: const {},
        hechoPor: 'Jefe',
        createdAt: faltaban.add(const Duration(hours: 1)),
      );
      final r = RegistroSorteo.resumir(
        [primero, segundo, deshacer],
        [...alumnos.take(3), _alumno('d', null)],
      );
      expect(r.ultimo, deshacer);
      expect(r.enPie, [primero]);
      expect(r.cambiosAMano, 0);
      // El papel muestra las mesas del primer sorteo: es el que nombra.
      expect(
        RegistroSorteo.lineaParaPlanilla(r),
        'Sorteo del 12/11/2026 21:40 hs · Jefe',
      );
    });
  });

  test('el renglón va y vuelve de la base igual', () {
    final original = _registro(
      TipoRegistroSorteo.sorteo,
      {'a': '12, 13', 'b': '14'},
      cuando: sorteo,
    );
    final vuelta = SorteoMesasRegistro.fromMap(original.toMap());
    expect(vuelta.resultado, original.resultado);
    expect(vuelta.tipo, TipoRegistroSorteo.sorteo);
    expect(vuelta.hechoPor, 'Jefe');
    expect(vuelta.createdAt.toUtc(), sorteo);
    expect(original.toMap()['alumnos'], 2);
  });
}
