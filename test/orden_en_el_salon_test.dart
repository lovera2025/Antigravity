// El salón "por orden" (6.7.0): al prenderlo, cada familia queda con su mesa
// fijada, de la que mejor cumplió a la que peor, desde la pasarela hacia
// afuera; y el SORTEO de siempre se las entrega. Con familias inventadas.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/orden_en_el_salon.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/salon_de_prueba.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';

String _id(int n) => 'c0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// 9 cuotas de $30.000, alta el 30/3: la cuota 1 vence el 30/4.
ContratoAlumno _f(int n, {bool conAdicional = false, String? mesa}) =>
    ContratoAlumno(
      id: _id(n),
      eventoId: _evento,
      nombreAlumno: 'F$n, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000 + (conAdicional ? 50000 : 0),
      mesaExtraPrecio: conAdicional ? 50000 : 0,
      mesaExtraCantidad: conAdicional ? 1 : 0,
      saldoDeudor: 270000,
      totalCuotas: 9,
      numeroMesa: mesa,
      createdAt: DateTime.utc(2026, 3, 30, 3),
    );

var _n = 0;

Map<String, dynamic> _pago(int mes, int dia, double monto,
    {String concepto = 'Cuota Base'}) {
  final fecha = DateTime.utc(2026, mes, dia, 15);
  _n++;
  return {
    'id': 'p$_n',
    'concepto': concepto,
    'monto': monto,
    'monto_gross': monto,
    'fecha_pago': fecha.toIso8601String(),
    'created_at': fecha.add(Duration(seconds: _n)).toIso8601String(),
    'anulado': 0,
  };
}

/// Las [cuantas] primeras cuotas, cada una el día de su vencimiento.
List<Map<String, dynamic>> _alDia(int cuantas) => [
      for (final (mes, dia) in const [
        (4, 30), (5, 31), (6, 30), (7, 31), (8, 31), (9, 30), (10, 31),
      ].take(cuantas))
        _pago(mes, dia, 30000),
    ];

final _hoy = DateTime(2026, 11, 12);
final _ahora = DateTime.utc(2026, 11, 12, 18);

/// F1 canceló en abril; F2 está al día y adelantó una; F3 está al día y tiene
/// una mesa adicional paga; F4 pagó tarde; F5 no pagó nada de la base.
final _alumnos = [
  _f(1),
  _f(2),
  _f(3, conAdicional: true),
  _f(4),
  _f(5),
];

Map<String, List<Map<String, dynamic>>> _pagos() => {
      _id(1): [_pago(4, 8, 270000)],
      _id(2): [..._alDia(7), _pago(11, 2, 30000)],
      _id(3): [..._alDia(7), _pago(6, 1, 50000, concepto: 'Mesa extra (1/1)')],
      _id(4): _alDia(7)..[1] = _pago(6, 20, 30000),
      _id(5): [],
    };

CambioDeConfig prender({
  ConfigPlano config = ConfigPlano.vacia,
  List<ContratoAlumno>? alumnos,
  Map<String, List<Map<String, dynamic>>>? pagos,
  bool conPaso = true,
  RecorridoDelOrden recorrido = RecorridoDelOrden.columnas,
}) =>
    OrdenEnElSalon.prender(
      eventoId: _evento,
      armado: salonDePrueba(conPasarela: conPaso, conEscenario: conPaso),
      config: config,
      alumnos: alumnos ?? _alumnos,
      pagos: pagos ?? _pagos(),
      hoyAr: _hoy,
      ahora: _ahora,
      recorrido: recorrido,
      por: 'Jefe',
    );

Map<int, String> _de(ConfigPlano c) =>
    {for (final e in c.fijadas.entries) e.key: e.value.alumnoId};

void main() {
  test('la familia con adicional paga tiene dos mesas', () {
    expect(SalonMesas.mesas(_alumnos[2]), 2);
  });

  group('prender', () {
    test('el que mejor cumplió, pegado a la pasarela; la adicional, detrás', () {
      final c = prender();
      expect(c.sePuede, isTrue);
      // El salón, de mejor a peor: 2, 3, 7, 6, 10, 11 y después las de afuera.
      expect(_de(c.config!), {
        2: _id(1),
        3: _id(2),
        7: _id(3),
        8: _id(3), // detrás de la 7
        6: _id(4),
      });
      expect(c.config!.fijadas.values.every((f) => f.esPorOrden), isTrue);
      expect(c.config!.fijadas.values.map((f) => f.motivo).toSet(),
          {'Por orden'});
    });

    test('por filas: la fila del escenario primero, de la pasarela hacia '
        'afuera', () {
      final c = prender(recorrido: RecorridoDelOrden.filas);
      expect(c.sePuede, isTrue);
      // El salón, de mejor a peor: 2, 3, 1, 4 y después la segunda fila.
      expect(_de(c.config!), {
        2: _id(1),
        3: _id(2),
        1: _id(3),
        8: _id(3), // la 1 no tiene nada detrás: la más cercana de su lado
        4: _id(4),
      });
      expect(c.config!.frente!.recorrido, RecorridoDelOrden.filas);
      // El orden de las familias es el mismo: cambia solo qué mesa va primero.
      expect(
        [for (final l in c.config!.frente!.lugares) l.alumnoId],
        [for (final l in prender().config!.frente!.lugares) l.alumnoId],
      );
    });

    test('prendido, elegir el otro recorrido lo reparte de nuevo', () {
      final columnas = prender().config!;
      final filas = prender(
        config: columnas,
        recorrido: RecorridoDelOrden.filas,
      ).config!;
      expect(_de(filas),
          _de(prender(recorrido: RecorridoDelOrden.filas).config!));
      expect(filas.fijadas.values.every((f) => f.esPorOrden), isTrue);
      // Y de vuelta.
      expect(_de(prender(config: filas).config!), _de(columnas));
    });

    test('ninguna mesa cambia de número: el armado no se toca', () {
      expect(prender().armado, isNull);
    });

    test('queda guardado quién, dónde y por qué', () {
      final orden = prender().config!.frente!;
      expect(orden.prendido, isTrue);
      expect(orden.por, 'Jefe');
      expect(orden.el, _ahora);
      expect([for (final l in orden.lugares) l.puesto], [1, 2, 3, 4]);
      expect([for (final l in orden.lugares) l.alumnoId],
          [_id(1), _id(2), _id(3), _id(4)]);
      expect(orden.lugares[2].mesas, [7, 8]);
      expect(orden.lugares[0].frase,
          'Nunca pagó tarde y terminó de pagar el 8 de abril.');
      expect(orden.lugares[3].frase,
          'Pagó tarde 1 cuota: 20 días de atraso en total.');
      expect(orden.lugares.map((l) => l.grupo), [1, 1, 1, 2]);
    });

    test('quien no pagó nada de la base no entra: el sorteo no le da mesa', () {
      final c = prender().config!;
      expect(c.fijadas.values.any((f) => f.alumnoId == _id(5)), isFalse);
      expect(c.frente!.lugares.any((l) => l.alumnoId == _id(5)), isFalse);
    });

    test('la adicional sin pagar no se ubica: solo la del contrato', () {
      final pagos = _pagos()..[_id(3)] = _alDia(7);
      final c = prender(pagos: pagos).config!;
      expect(c.fijadasPorAlumno[_id(3)], hasLength(1));
    });

    test('lo fijado a mano y lo libre no se tocan', () {
      const aMano = MesaFijada(alumnoId: 'x', motivo: 'Silla de ruedas');
      final c = prender(
        config: ConfigPlano(
          fijadas: {2: MesaFijada(alumnoId: _id(4), motivo: 'Silla de ruedas')},
          libres: const {3: MesaLibre()},
        ),
      ).config!;
      expect(aMano.esPorOrden, isFalse);
      // F4 se queda con la suya y sale del orden; nadie va a la 3.
      expect(c.fijadas[2]!.alumnoId, _id(4));
      expect(c.fijadas[2]!.motivo, 'Silla de ruedas');
      expect(c.fijadas.containsKey(3), isFalse);
      expect(c.frente!.lugares.any((l) => l.alumnoId == _id(4)), isFalse);
      expect(c.fijadas[7]!.alumnoId, _id(1));
      expect(c.libres.keys, [3]);
    });

    test('prender otra vez da lo mismo: los empates no cambian', () {
      final muchos = [for (var i = 1; i <= 10; i++) _f(i)];
      final pagos = {for (var i = 1; i <= 10; i++) _id(i): _alDia(7)};
      final uno = prender(alumnos: muchos, pagos: pagos).config!;
      final otro = prender(
        config: uno,
        alumnos: muchos.reversed.toList(),
        pagos: pagos,
      ).config!;
      expect(_de(otro), _de(uno));
      expect(uno.fijadas, hasLength(10));
    });

    test('si faltan mesas, las últimas familias quedan sin lugar', () {
      final muchos = [for (var i = 1; i <= 14; i++) _f(i)];
      final pagos = {for (var i = 1; i <= 14; i++) _id(i): _alDia(7)};
      final orden = prender(alumnos: muchos, pagos: pagos).config!.frente!;
      expect(orden.lugares.where((l) => l.mesas.isNotEmpty), hasLength(12));
      expect(orden.lugares.skip(12).every((l) => l.mesas.isEmpty), isTrue);
    });

    test('con familias ya con mesa no se puede', () {
      final c = prender(alumnos: [..._alumnos.skip(1), _f(1, mesa: '4')]);
      expect(c.sePuede, isFalse);
      expect(c.problema, contains('deshacer el sorteo'));
    });

    test('prendido y ya sorteado, cambiar el recorrido tampoco se puede', () {
      final prendido = prender().config!;
      final c = prender(
        config: prendido,
        alumnos: [_f(1, mesa: '2'), ..._alumnos.skip(1)],
        recorrido: RecorridoDelOrden.filas,
      );
      expect(c.sePuede, isFalse);
      expect(c.problema, startsWith('Ya se sorteó con esto tildado'));
    });

    test('sin pasarela ni escenario no se puede', () {
      final c = prender(conPaso: false);
      expect(c.sePuede, isFalse);
      expect(c.problema, contains('pasarela'));
    });

    test('sin nadie con algo pagado no se puede', () {
      expect(prender(pagos: const {}).sePuede, isFalse);
    });

    test('con el sorteo por división todavía no se puede', () {
      final c = OrdenEnElSalon.prender(
        eventoId: _evento,
        armado: salonDePrueba(),
        config: ConfigPlano.vacia,
        alumnos: _alumnos,
        pagos: _pagos(),
        hoyAr: _hoy,
        ahora: _ahora,
        modo: ModoSorteo.bloques,
      );
      expect(c.sePuede, isFalse);
      expect(c.problema, contains('por división'));
    });
  });

  group('apagar', () {
    test('saca lo que puso el orden y deja lo fijado a mano', () {
      final prendido = prender(
        config: ConfigPlano(
          fijadas: {2: MesaFijada(alumnoId: _id(4), motivo: 'Silla de ruedas')},
        ),
      ).config!;
      final c = OrdenEnElSalon.apagar(config: prendido, alumnos: _alumnos);
      expect(c.sePuede, isTrue);
      expect(_de(c.config!), {2: _id(4)});
      expect(c.config!.frente!.prendido, isFalse);
      expect(c.config!.frente!.lugares, isEmpty);
    });

    test('el recorrido elegido queda: el botón lo recuerda', () {
      final prendido = prender(recorrido: RecorridoDelOrden.filas).config!;
      final c = OrdenEnElSalon.apagar(config: prendido, alumnos: _alumnos);
      expect(c.config!.fijadas, isEmpty);
      expect(c.config!.frente!.recorrido, RecorridoDelOrden.filas);
      expect(
        ConfigPlano.fromJson(c.config!.toJson()).frente!.recorrido,
        RecorridoDelOrden.filas,
      );
    });

    test('con el sorteo hecho no se puede: lo guardado queda', () {
      final prendido = prender().config!;
      final c = OrdenEnElSalon.apagar(
        config: prendido,
        alumnos: [_f(1, mesa: '2'), ..._alumnos.skip(1)],
      );
      expect(c.sePuede, isFalse);
    });
  });

  group('el sorteo de siempre lo entrega', () {
    test('cada familia recibe la mesa que le fijó el orden, y nadie más', () {
      final pagos = _pagos();
      final config = prender(pagos: pagos).config!;
      final exclusion = exclusionSorteo(
        candidatos:
            candidatosPorPago(_alumnos, pagosPorAlumno(_alumnos, pagos)),
        soloPagado: true,
      );
      final e = EntradaSorteoPlano(
        armado: salonDePrueba(),
        config: config,
        alumnos: _alumnos,
        exclusion: exclusion,
      );
      expect(SorteoConPlano.preparar(e).entra, isTrue);
      for (var semilla = 1; semilla <= 40; semilla++) {
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        expect(r.asignaciones[_id(1)], [2]);
        expect(r.asignaciones[_id(2)], [3]);
        expect(r.asignaciones[_id(3)]!.toSet(), {7, 8});
        expect(r.asignaciones[_id(4)], [6]);
        expect(r.asignaciones.containsKey(_id(5)), isFalse);
      }
    });

    test('por filas también: cada familia recibe la mesa que le fijó el orden',
        () {
      final pagos = _pagos();
      final config =
          prender(pagos: pagos, recorrido: RecorridoDelOrden.filas).config!;
      final e = EntradaSorteoPlano(
        armado: salonDePrueba(),
        config: config,
        alumnos: _alumnos,
        exclusion: exclusionSorteo(
          candidatos:
              candidatosPorPago(_alumnos, pagosPorAlumno(_alumnos, pagos)),
          soloPagado: true,
        ),
      );
      expect(SorteoConPlano.preparar(e).entra, isTrue);
      for (var semilla = 1; semilla <= 40; semilla++) {
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        expect(r.asignaciones[_id(1)], [2]);
        expect(r.asignaciones[_id(2)], [3]);
        expect(r.asignaciones[_id(3)]!.toSet(), {1, 8});
        expect(r.asignaciones[_id(4)], [4]);
        expect(r.asignaciones.containsKey(_id(5)), isFalse);
      }
    });

    test('quien paga entre el tilde y el sorteo entra, en una mesa que quedó '
        'libre', () {
      final pagos = _pagos();
      final config = prender(pagos: pagos).config!;
      // F5 paga su primera cuota después de prender el orden.
      pagos[_id(5)] = [_pago(11, 12, 30000)];
      final e = EntradaSorteoPlano(
        armado: salonDePrueba(),
        config: config,
        alumnos: _alumnos,
        exclusion: exclusionSorteo(
          candidatos:
              candidatosPorPago(_alumnos, pagosPorAlumno(_alumnos, pagos)),
          soloPagado: true,
        ),
      );
      final r = SorteoConPlano.sortear(e, random: Random(3));
      expect(SorteoConPlano.validar(e, r), isNull);
      expect(r.asignaciones[_id(1)], [2]);
      final suya = r.asignaciones[_id(5)]!.single;
      expect(config.fijadas.containsKey(suya), isFalse);
    });
  });

  group('viaja con el plano', () {
    test('la config va y vuelve con el orden y sus fijadas', () {
      final c = prender().config!;
      final vuelta = ConfigPlano.fromJson(c.toJson());
      expect(_de(vuelta), _de(c));
      expect(vuelta.fijadas.values.every((f) => f.esPorOrden), isTrue);
      final o = vuelta.frente!;
      expect(o.prendido, isTrue);
      expect(o.el, _ahora);
      expect([for (final l in o.lugares) '${l.puesto}:${l.mesas.join('+')}'],
          ['1:2', '2:3', '3:7+8', '4:6']);
      expect(o.lugares.first.frase, c.frente!.lugares.first.frase);
    });

    test('el recorrido va y vuelve; por columnas no escribe la clave', () {
      final columnas = prender().config!;
      expect(columnas.toJson(), isNot(contains('recorrido')));
      expect(ConfigPlano.fromJson(columnas.toJson()).frente!.recorrido,
          RecorridoDelOrden.columnas);
      final filas = prender(recorrido: RecorridoDelOrden.filas).config!;
      expect(filas.toJson(), contains('"recorrido":"filas"'));
      final vuelta = ConfigPlano.fromJson(filas.toJson());
      expect(vuelta.frente!.recorrido, RecorridoDelOrden.filas);
      expect(_de(vuelta), _de(filas));
      // Una clave que no se conoce es "por columnas": nunca un plano roto.
      expect(
        ConfigPlano.fromJson('{"frente": {"general": true, "recorrido": "x"}}')
            .frente!
            .recorrido,
        RecorridoDelOrden.columnas,
      );
    });

    test('una fiesta que nunca lo prendió no lleva la clave', () {
      expect(ConfigPlano.vacia.frente, isNull);
      expect(ConfigPlano.vacia.toJson(), isNot(contains('frente')));
      expect(ConfigPlano.fromJson(ConfigPlano.vacia.toJson()).frente, isNull);
    });

    test('un "frente" mal escrito no rompe el plano', () {
      final c = ConfigPlano.fromJson('{"frente": "cualquier cosa"}');
      expect(c.frente, isNull);
      final d = ConfigPlano.fromJson(
          '{"frente": {"general": true, "orden": [{"a": 5}, {"a": "x", "p": 1}]}}');
      expect(d.frente!.prendido, isTrue);
      expect(d.frente!.lugares, hasLength(1));
    });
  });
}
