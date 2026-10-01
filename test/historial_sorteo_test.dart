// El Historial de las mesas de una fiesta: sorteos, cambios con motivo, mesas
// fijas y libres, y lo que se tocó a mano sin dejar registro.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/registro_sorteo.dart';
import 'package:arguello_events/features/plano/services/historial_sorteo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

ContratoAlumno alumno(String id, String? mesa, {bool baja = false}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${baja ? '[BAJA] ' : ''}${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa: mesa,
    );

void main() {
  final dia = DateTime.utc(2026, 11, 13);
  DateTime hora(int h) => dia.add(Duration(hours: h));

  final sorteo = SorteoMesasRegistro(
    id: 's1',
    eventoId: 'e',
    tipo: TipoRegistroSorteo.sorteo,
    resultado: const {'gomez': '12, 13', 'sosa': '40, 41', 'vega': '60'},
    hechoPor: 'Jefe',
    createdAt: hora(1),
  );
  final cambio = MovimientoMesas(
    id: 'm1',
    eventoId: 'e',
    tipo: TipoMovimientoMesas.intercambio,
    antes: const {'gomez': '12, 13', 'sosa': '40, 41'},
    despues: const {'gomez': '40, 41', 'sosa': '12, 13'},
    motivo: 'Pidieron estar con los primos',
    avisos: const ['Son de divisiones distintas: 5° A y 5° B.'],
    hechoPor: 'Operador',
    createdAt: hora(2),
  );
  final mudanza = MovimientoMesas(
    id: 'm2',
    eventoId: 'e',
    tipo: TipoMovimientoMesas.mover,
    antes: const {'vega': '60'},
    despues: const {'vega': '70'},
    motivo: 'Columna',
    hechoPor: 'Jefe',
    createdAt: hora(3),
  );

  group('lo que debería haber hoy', () {
    test('los sorteos y los cambios, mezclados por fecha', () {
      expect(RegistroSorteo.esperado([sorteo]), {
        'gomez': {12, 13},
        'sosa': {40, 41},
        'vega': {60},
      });
      expect(RegistroSorteo.esperado([sorteo], [mudanza, cambio]), {
        'gomez': {40, 41},
        'sosa': {12, 13},
        'vega': {70},
      });
    });

    test('un sorteo deshecho después del cambio borra todo', () {
      final deshecho = SorteoMesasRegistro(
        id: 's2',
        eventoId: 'e',
        tipo: TipoRegistroSorteo.deshacer,
        resultado: const {'gomez': '40, 41', 'sosa': '12, 13', 'vega': '60'},
        createdAt: hora(5),
      );
      expect(RegistroSorteo.esperado([sorteo, deshecho], [cambio]), isEmpty);
    });

    test('a la misma hora, el sorteo va antes que el cambio', () {
      final junto = MovimientoMesas(
        id: 'm9',
        eventoId: 'e',
        tipo: TipoMovimientoMesas.mover,
        antes: const {'vega': '60'},
        despues: const {'vega': '70'},
        motivo: 'x',
        createdAt: hora(1),
      );
      expect(RegistroSorteo.esperado([sorteo], [junto])['vega'], {70});
    });
  });

  group('la línea de la planilla', () {
    test('cuenta los cambios con motivo y, aparte, los hechos a mano', () {
      final r = RegistroSorteo.resumir(
        [sorteo],
        [
          alumno('gomez', '40, 41'),
          alumno('sosa', '12, 13'),
          // A VEGA la cambiaron en Editar alumno: no hay renglón.
          alumno('vega', '75'),
        ],
        movimientos: [cambio],
      );
      expect(r.cambiosConMotivo, 1);
      expect(r.cambiosAMano, 1);
      expect(
        RegistroSorteo.lineaParaPlanilla(r),
        endsWith(' · Jefe · 1 cambio con motivo · 1 cambio a mano después'),
      );
    });

    test('un cambio que se deshizo no cuenta', () {
      final deshacer = MovimientoMesas(
        id: 'm3',
        eventoId: 'e',
        tipo: TipoMovimientoMesas.deshacer,
        antes: cambio.despues,
        despues: cambio.antes,
        motivo: 'Deshace',
        deshaceId: 'm1',
        createdAt: hora(4),
      );
      final r = RegistroSorteo.resumir(
        [sorteo],
        [alumno('gomez', '12, 13'), alumno('sosa', '40, 41'), alumno('vega', '60')],
        movimientos: [cambio, deshacer],
      );
      expect(r.cambiosConMotivo, 0);
      expect(r.cambiosAMano, 0);
      expect(RegistroSorteo.cambiosEnPie([cambio, deshacer]), isEmpty);
      expect(RegistroSorteo.cambiosEnPie([cambio, mudanza]).map((m) => m.id),
          ['m1', 'm2']);
    });

    test('un cambio de un sorteo que después se deshizo ya no cuenta', () {
      // Sorteo, un cambio con motivo, se deshace el sorteo y se sortea de
      // nuevo: las mesas ya no son las que dejó aquel cambio.
      final deshecho = SorteoMesasRegistro(
        id: 's2',
        eventoId: 'e',
        tipo: TipoRegistroSorteo.deshacer,
        resultado: const {'gomez': '40, 41', 'sosa': '12, 13', 'vega': '60'},
        createdAt: hora(5),
      );
      final otro = SorteoMesasRegistro(
        id: 's3',
        eventoId: 'e',
        tipo: TipoRegistroSorteo.sorteo,
        resultado: const {'gomez': '1, 2', 'sosa': '3, 4', 'vega': '5'},
        hechoPor: 'Jefe',
        createdAt: hora(6),
      );
      final r = RegistroSorteo.resumir(
        [sorteo, deshecho, otro],
        [alumno('gomez', '1, 2'), alumno('sosa', '3, 4'), alumno('vega', '5')],
        movimientos: [cambio],
      );
      expect(r.cambiosConMotivo, 0);
      expect(r.cambiosAMano, 0);
      expect(RegistroSorteo.lineaParaPlanilla(r), isNot(contains('cambio')));
    });

    test('sin ningún sorteo registrado, solo se mira a quienes se movió', () {
      // Mesas cargadas a mano de siempre: mover a una familia no convierte a
      // las demás en "cambiadas a mano".
      final r = RegistroSorteo.resumir(
        const [],
        [alumno('gomez', '12'), alumno('sosa', '13'), alumno('vega', '70')],
        movimientos: [mudanza],
      );
      expect(r.cambiosAMano, 0);
      expect(r.cambiosConMotivo, 1);
      // Si a la que se movió después la tocaron a mano, eso sí se ve.
      final tocada = RegistroSorteo.resumir(
        const [],
        [alumno('gomez', '12'), alumno('vega', '99')],
        movimientos: [mudanza],
      );
      expect(tocada.cambiosAMano, 1);
    });

    test('sin movimientos, dice lo mismo que antes', () {
      final r = RegistroSorteo.resumir([sorteo], [
        alumno('gomez', '12, 13'),
        alumno('sosa', '40, 41'),
        alumno('vega', '60'),
      ]);
      expect(r.cambiosConMotivo, 0);
      expect(RegistroSorteo.lineaParaPlanilla(r), isNot(contains('motivo')));
    });
  });

  group('el Historial', () {
    final alumnos = [
      alumno('gomez', '40, 41'),
      alumno('sosa', '12, 13'),
      alumno('vega', '70'),
    ];

    test('lo más nuevo arriba, con quién, por qué y el antes y el después', () {
      final h = HistorialSorteo.armar(
        registros: [sorteo],
        movimientos: [cambio, mudanza],
        config: ConfigPlano.vacia,
        alumnos: alumnos,
      );
      expect(h.renglones.map((r) => r.tipo), [
        TipoRenglonHistorial.mover,
        TipoRenglonHistorial.cambio,
        TipoRenglonHistorial.sorteo,
      ]);
      final m = h.renglones[0];
      expect(m.titulo, 'VEGA pasó a otras mesas');
      expect(m.detalle, ['VEGA: 60 → 70', 'Motivo: Columna']);
      expect(m.quien, 'Jefe');
      final c = h.renglones[1];
      expect(c.titulo, 'Cambiaron de lugar: GOMEZ y SOSA');
      expect(c.detalle, [
        'GOMEZ: 12, 13 → 40, 41',
        'SOSA: 40, 41 → 12, 13',
        'Motivo: Pidieron estar con los primos',
        'Son de divisiones distintas: 5° A y 5° B.',
      ]);
      expect(h.renglones[2].titulo, 'Sorteo: 3 familias');
      expect(h.sinRegistro, isEmpty);
      expect(h.vacio, isFalse);
    });

    test('un cambio que sigue en pie se puede deshacer; uno ya deshecho, no', () {
      final deshacer = MovimientoMesas(
        id: 'm3',
        eventoId: 'e',
        tipo: TipoMovimientoMesas.deshacer,
        antes: mudanza.despues,
        despues: mudanza.antes,
        motivo: 'Deshace: Columna',
        deshaceId: 'm2',
        createdAt: hora(4),
      );
      final h = HistorialSorteo.armar(
        registros: [sorteo],
        movimientos: [cambio, mudanza, deshacer],
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('gomez', '40, 41'),
          alumno('sosa', '12, 13'),
          alumno('vega', '60'),
        ],
      );
      final porId = {
        for (final r in h.renglones)
          if (r.movimiento != null) r.movimiento!.id: r,
      };
      expect(porId['m1']!.sePuedeDeshacer, isTrue);
      expect(porId['m2']!.deshecho, isTrue);
      expect(porId['m2']!.sePuedeDeshacer, isFalse);
      // El deshacer es un renglón más, y no se deshace.
      final d = h.renglones.first;
      expect(d.tipo, TipoRenglonHistorial.deshacer);
      expect(d.titulo, 'Se deshizo un cambio: VEGA');
      expect(d.detalle, ['VEGA: 70 → 60', 'El cambio era por: Deshace: Columna']);
      expect(d.movimiento, isNull);
      expect(d.sePuedeDeshacer, isFalse);
    });

    test('si después cambió algo, dice por qué ya no se puede deshacer', () {
      final h = HistorialSorteo.armar(
        registros: [sorteo],
        movimientos: [cambio],
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('gomez', '40, 41'),
          alumno('sosa', '80, 81'),
          alumno('vega', '60'),
        ],
      );
      final r = h.renglones.first;
      expect(r.sePuedeDeshacer, isFalse);
      expect(r.noSeDeshacePorque, contains('Las mesas de SOSA cambiaron'));
    });

    test('las mesas fijas y libres, con su motivo y quién', () {
      final h = HistorialSorteo.armar(
        registros: const [],
        movimientos: const [],
        config: ConfigPlano(
          fijadas: {
            20: MesaFijada(alumnoId: 'gomez', motivo: 'Silla de ruedas', por: 'Jefe', cuando: hora(0)),
            21: MesaFijada(alumnoId: 'gomez', motivo: 'Silla de ruedas', por: 'Jefe', cuando: hora(0)),
            30: const MesaFijada(alumnoId: 'fantasma'),
          },
          libres: {50: MesaLibre(motivo: 'Columna', por: 'Operador', cuando: hora(1))},
        ),
        alumnos: alumnos,
      );
      expect(h.renglones.map((r) => r.titulo), [
        'Mesa 50 libre: el sorteo no la da',
        'Mesas 20, 21 fijadas para GOMEZ',
        // Sin fecha, al final.
        'Mesa 30 fijada para Una familia que ya no está',
      ]);
      expect(h.renglones[1].detalle, ['Motivo: Silla de ruedas']);
      expect(h.renglones[1].quien, 'Jefe');
      // Sin sorteos ni cambios no hay contra qué comparar.
      expect(h.sinRegistro, isEmpty);
    });

    test('lo que se cambió a mano, sin registro', () {
      final h = HistorialSorteo.armar(
        registros: [sorteo],
        movimientos: const [],
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('gomez', '12-13'),
          alumno('sosa', '44'),
          alumno('vega', null),
          alumno('nuevo', '90'),
        ],
      );
      expect(
        [for (final c in h.sinRegistro) (c.nombre, c.hoy, c.segunElRegistro)],
        [
          ('NUEVO, ALUMNO', '90', 'sin mesa'),
          ('SOSA, ALUMNO', '44', '40, 41'),
          ('VEGA, ALUMNO', 'sin mesa', '60'),
        ],
      );
    });

    test('sin sorteo registrado, no marca a todo el salón como sin registro',
        () {
      final h = HistorialSorteo.armar(
        registros: const [],
        movimientos: [mudanza],
        config: ConfigPlano.vacia,
        alumnos: [alumno('gomez', '12'), alumno('sosa', '13'), alumno('vega', '70')],
      );
      expect(h.sinRegistro, isEmpty);
    });

    test('una mesa libre a la que habría que volver frena el deshacer', () {
      final h = HistorialSorteo.armar(
        registros: [sorteo],
        movimientos: [mudanza],
        config: const ConfigPlano(libres: {60: MesaLibre()}),
        alumnos: alumnos,
      );
      final r = h.renglones.firstWhere((r) => r.movimiento?.id == 'm2');
      expect(r.sePuedeDeshacer, isFalse);
      expect(r.noSeDeshacePorque, contains('se dejó libre después'));
    });

    test('una fiesta sin nada: vacío', () {
      final h = HistorialSorteo.armar(
        registros: const [],
        movimientos: const [],
        config: ConfigPlano.vacia,
        alumnos: [alumno('gomez', '12')],
      );
      expect(h.vacio, isTrue);
    });
  });
}
