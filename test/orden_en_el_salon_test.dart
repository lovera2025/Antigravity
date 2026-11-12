// "Cumplimiento debido" (6.7.1): al sortear con el tilde del cartel, cada
// familia recibe su mesa de la que mejor cumplió a la que peor, desde la
// pasarela hacia afuera; y con el sorteo ya hecho, las reacomoda sin que nadie
// pierda una mesa. Con familias inventadas y el sorteo de verdad.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/eventos/services/ultimos_sorteados.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/features/plano/services/orden_en_el_salon.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

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
List<ContratoAlumno> _alumnos({Map<int, String> mesas = const {}}) => [
      _f(1, mesa: mesas[1]),
      _f(2, mesa: mesas[2]),
      _f(3, conAdicional: true, mesa: mesas[3]),
      _f(4, mesa: mesas[4]),
      _f(5, mesa: mesas[5]),
    ];

Map<String, List<Map<String, dynamic>>> _pagos() => {
      _id(1): [_pago(4, 8, 270000)],
      _id(2): [..._alDia(7), _pago(11, 2, 30000)],
      _id(3): [..._alDia(7), _pago(6, 1, 50000, concepto: 'Mesa extra (1/1)')],
      _id(4): _alDia(7)..[1] = _pago(6, 20, 30000),
      _id(5): [],
    };

/// Lo pagado como lo deja el cartel del SORTEO: "solo lo pagado".
ExclusionSorteo _exclusion(
  List<ContratoAlumno> alumnos,
  Map<String, List<Map<String, dynamic>>> pagos,
) =>
    exclusionSorteo(
      candidatos: candidatosPorPago(alumnos, pagosPorAlumno(alumnos, pagos)),
      soloPagado: true,
    );

OrdenParaElSorteo calcular({
  ConfigPlano config = ConfigPlano.vacia,
  List<ContratoAlumno>? alumnos,
  Map<String, List<Map<String, dynamic>>>? pagos,
  bool conPaso = true,
  RecorridoDelOrden recorrido = RecorridoDelOrden.columnas,
  bool alFinal = false,
  int juntas = 0,
  ModoSorteo modo = ModoSorteo.entera,
}) {
  final a = alumnos ?? _alumnos();
  final p = pagos ?? _pagos();
  return OrdenEnElSalon.paraElSorteo(
    eventoId: _evento,
    armado: salonDePrueba(conPasarela: conPaso, conEscenario: conPaso),
    config: config,
    alumnos: a,
    pagos: p,
    hoyAr: _hoy,
    ahora: _ahora,
    exclusion: _exclusion(a, p),
    modo: modo,
    recorrido: recorrido,
    adicionalesAlFinal: alFinal,
    juntasConLaPrincipal: juntas,
    por: 'Jefe',
  );
}

Map<int, List<int>> _lugares(OrdenParaElSorteo o) => {
      for (var n = 1; n <= 20; n++)
        if (o.lugares[_id(n)] != null) n: o.lugares[_id(n)]!,
    };

/// Sortea de verdad con el orden puesto y exige el control final.
ResultadoSorteoPlano _sortear(OrdenParaElSorteo o, {int semilla = 1}) {
  final e = OrdenEnElSalon.entrada(o, armado: salonDePrueba());
  expect(SorteoConPlano.preparar(e).entra, isTrue);
  final r = SorteoConPlano.sortear(e, random: Random(semilla));
  expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
  expect(OrdenEnElSalon.noCumple(o, r), isNull, reason: 'semilla $semilla');
  return r;
}

void main() {
  test('la familia con adicional paga tiene dos mesas', () {
    expect(SalonMesas.mesas(_alumnos()[2]), 2);
  });

  group('con el salón vacío', () {
    test('el que mejor cumplió, pegado a la pasarela; la adicional, detrás', () {
      final o = calcular();
      expect(o.sePuede, isTrue);
      // El salón, de mejor a peor: 2, 3, 7, 6, 10, 11 y después las de afuera.
      expect(_lugares(o), {
        1: [2],
        2: [3],
        3: [7, 8], // la 8 está detrás de la 7
        4: [6],
      });
      expect(o.ubicadas, 4);
      expect(o.cambian, 0);
    });

    test('quien no pagó nada de la base no entra', () {
      final o = calcular();
      expect(o.lugares.containsKey(_id(5)), isFalse);
      expect(o.exclusionDelSorteo.sinMesa, contains(_id(5)));
    });

    test('las mesas se fijan solo para el sorteo: no se guardan', () {
      final o = calcular();
      final delSorteo = o.configDelSorteo!;
      expect(delSorteo.fijadas.keys.toSet(), {2, 3, 7, 8, 6});
      expect(delSorteo.fijadas.values.every((f) => f.esPorOrden), isTrue);
      expect(o.configAGuardar!.fijadas, isEmpty);
    });

    test('queda guardado quién, dónde y por qué', () {
      final orden = calcular().configAGuardar!.frente!;
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

    test('por filas: la fila del escenario primero', () {
      final o = calcular(recorrido: RecorridoDelOrden.filas);
      // El salón, de mejor a peor: 2, 3, 1, 4 y después la segunda fila.
      expect(_lugares(o), {
        1: [2],
        2: [3],
        3: [1, 8], // la 1 no tiene nada detrás: la más cercana de su lado
        4: [4],
      });
      expect(o.configAGuardar!.frente!.recorrido, RecorridoDelOrden.filas);
    });

    test('la adicional sin pagar no se ubica: solo la del contrato', () {
      final pagos = _pagos()..[_id(3)] = _alDia(7);
      final o = calcular(pagos: pagos);
      expect(o.lugares[_id(3)], hasLength(1));
      expect(o.exclusionDelSorteo.soloBase, contains(_id(3)));
    });

    test('adicionales al final: primero las principales de todos', () {
      final o = calcular(alFinal: true);
      // F3 tiene su principal en su lugar (la 7) y la adicional después de
      // la última principal (la 6): la que sigue en el salón es la 10.
      expect(_lugares(o), {
        1: [2],
        2: [3],
        3: [7, 10],
        4: [6],
      });
      // Con una pegada a la principal, queda como siempre.
      expect(_lugares(calcular(alFinal: true, juntas: 1))[3], [7, 8]);
    });

    test('lo fijado a mano y lo libre no se tocan', () {
      final o = calcular(
        config: ConfigPlano(
          fijadas: {2: MesaFijada(alumnoId: _id(4), motivo: 'Silla de ruedas')},
          libres: const {3: MesaLibre()},
        ),
      );
      // F4 se queda con la suya y sale del orden; nadie va a la 3.
      expect(o.lugares.containsKey(_id(4)), isFalse);
      expect(o.lugares[_id(1)], [7]);
      expect(o.lugares.values.expand((l) => l), isNot(contains(3)));
      expect(o.configDelSorteo!.fijadas[2]!.motivo, 'Silla de ruedas');
      expect(o.configAGuardar!.fijadas.keys, [2]);
      expect(o.configAGuardar!.libres.keys, [3]);
      // Y el sorteo le entrega a F4 su fijada.
      expect(_sortear(o).asignaciones[_id(4)], [2]);
    });

    test('calcular otra vez da lo mismo: los empates no cambian', () {
      final muchos = [for (var i = 1; i <= 10; i++) _f(i)];
      final pagos = {for (var i = 1; i <= 10; i++) _id(i): _alDia(7)};
      final uno = calcular(alumnos: muchos, pagos: pagos);
      final otro = calcular(alumnos: muchos.reversed.toList(), pagos: pagos);
      expect(_lugares(otro), _lugares(uno));
      expect(uno.ubicadas, 10);
    });

    test('si faltan mesas, las últimas familias quedan sin lugar', () {
      final muchos = [for (var i = 1; i <= 14; i++) _f(i)];
      final pagos = {for (var i = 1; i <= 14; i++) _id(i): _alDia(7)};
      final o = calcular(alumnos: muchos, pagos: pagos);
      expect(o.ubicadas, 12);
      final e = OrdenEnElSalon.entrada(o, armado: salonDePrueba());
      expect(SorteoConPlano.preparar(e).entra, isFalse);
    });

    test('sin pasarela ni escenario no se puede', () {
      final o = calcular(conPaso: false);
      expect(o.sePuede, isFalse);
      expect(o.problema, contains('pasarela'));
    });

    test('sin nadie para ubicar no se puede', () {
      expect(calcular(pagos: const {}).sePuede, isFalse);
    });

    test('por división todavía no se puede', () {
      final o = calcular(modo: ModoSorteo.bloques);
      expect(o.sePuede, isFalse);
      expect(o.problema, contains('por división'));
    });
  });

  group('el sorteo de siempre lo entrega', () {
    test('cada familia recibe la mesa que le tocó, y nadie más', () {
      final o = calcular();
      for (var semilla = 1; semilla <= 40; semilla++) {
        final r = _sortear(o, semilla: semilla);
        expect(r.asignaciones[_id(1)], [2]);
        expect(r.asignaciones[_id(2)], [3]);
        expect(r.asignaciones[_id(3)]!.toSet(), {7, 8});
        expect(r.asignaciones[_id(4)], [6]);
        expect(r.asignaciones.containsKey(_id(5)), isFalse);
      }
    });

    test('por filas y con las adicionales al final, también', () {
      final o = calcular(recorrido: RecorridoDelOrden.filas, alFinal: true);
      for (var semilla = 1; semilla <= 40; semilla++) {
        final r = _sortear(o, semilla: semilla);
        for (final e in o.lugares.entries) {
          expect(r.asignaciones[e.key]!.toSet(), e.value.toSet());
        }
      }
    });

    test('si el sorteo le diera otra mesa, se nota', () {
      final o = calcular();
      final mal = ResultadoSorteoPlano(asignaciones: {
        _id(1): [3],
        _id(2): [2],
        _id(3): [7, 8],
        _id(4): [6],
      });
      expect(OrdenEnElSalon.noCumple(o, mal), isNotNull);
    });
  });

  group('con el sorteo ya hecho, reacomoda', () {
    // Un sorteo común dejó a cada una en cualquier lado.
    final sentados = {1: '12', 2: '9', 3: '5, 4', 4: '1'};

    test('queda igual que sorteando así con el salón vacío', () {
      final o = calcular(alumnos: _alumnos(mesas: sentados));
      expect(o.sePuede, isTrue);
      expect(_lugares(o), _lugares(calcular()));
      expect(o.cambian, 4);
      for (var semilla = 1; semilla <= 40; semilla++) {
        final r = _sortear(o, semilla: semilla);
        expect(r.asignaciones[_id(1)], [2]);
        expect(r.asignaciones[_id(3)]!.toSet(), {7, 8});
      }
    });

    test('quien ya está en su lugar no cuenta como cambio', () {
      final o = calcular(
        alumnos: _alumnos(mesas: {1: '2', 2: '3', 3: '7, 8', 4: '1'}),
      );
      expect(o.cambian, 1);
    });

    test('nadie pierde una mesa que ya tiene, aunque no la haya pagado', () {
      // F3 tiene sus dos mesas y la adicional sin pagar.
      final pagos = _pagos()..[_id(3)] = _alDia(7);
      final o = calcular(alumnos: _alumnos(mesas: sentados), pagos: pagos);
      expect(o.lugares[_id(3)], hasLength(2));
      expect(o.exclusionDelSorteo.soloBase, isNot(contains(_id(3))));
      expect(_sortear(o).asignaciones[_id(3)], hasLength(2));
    });

    test('quien tiene mesa sin haber pagado la base se reacomoda, al final',
        () {
      final o = calcular(alumnos: _alumnos(mesas: {...sentados, 5: '11'}));
      expect(o.lugares[_id(5)], hasLength(1));
      expect(o.configAGuardar!.frente!.lugares.last.alumnoId, _id(5));
      expect(o.exclusionDelSorteo.sinMesa, isNot(contains(_id(5))));
      expect(_sortear(o).asignaciones[_id(5)], o.lugares[_id(5)]);
    });

    test('la mesa fijada a mano y ya entregada queda donde está', () {
      final o = calcular(
        alumnos: _alumnos(mesas: {...sentados, 4: '2'}),
        config: ConfigPlano(
          fijadas: {2: MesaFijada(alumnoId: _id(4), motivo: 'Silla de ruedas')},
        ),
      );
      expect(o.lugares.containsKey(_id(4)), isFalse);
      expect(o.lugares.values.expand((l) => l), isNot(contains(2)));
      final r = _sortear(o);
      expect(r.asignaciones.containsKey(_id(4)), isFalse,
          reason: 'no se le dio nada nuevo');
    });

    test('quien recibió una mesa nueva al fondo se reacomoda como las demás',
        () {
      final o = calcular(
        alumnos: _alumnos(mesas: sentados),
        config: ConfigPlano(
          fijadas: {
            1: MesaFijada(alumnoId: _id(4), motivo: MesasNuevasAlFondo.motivo),
          },
        ),
      );
      expect(o.lugares[_id(4)], [6]);
      expect(o.configAGuardar!.fijadas, isEmpty);
    });

    test('con el sorteo hecho por división todavía no se puede', () {
      final o = calcular(
        alumnos: _alumnos(mesas: sentados),
        config: const ConfigPlano(
          bloques: [BloqueDivision('5a', 1, 2)],
        ),
      );
      expect(o.sePuede, isFalse);
      expect(o.problema, contains('por división'));
    });

    test('deshacer solo ese sorteo devuelve a cada una a su mesa de antes', () {
      final antes = _alumnos(mesas: sentados);
      final o = calcular(alumnos: antes);
      final r = _sortear(o);
      final numeros = {
        for (final e in r.asignaciones.entries) e.key: e.value.join(', '),
      };
      final registro = SorteoMesasRegistro(
        id: 'r1',
        eventoId: _evento,
        tipo: TipoRegistroSorteo.sorteo,
        resultado: numeros,
        antes: UltimosSorteados.antesDe(antes, numeros),
        reacomodo: true,
        createdAt: _ahora,
      );
      // El renglón va y vuelve con la marca.
      final leido = SorteoMesasRegistro.fromMap(registro.toMap());
      expect(leido.reacomodo, isTrue);
      final despues = [
        for (final a in antes)
          numeros[a.id] == null ? a : a.copyWith(numeroMesa: numeros[a.id]),
      ];
      final u = UltimosSorteados.de([leido], despues)!;
      expect(u.noSeTocan, isEmpty);
      expect(u.aGuardar, {
        _id(1): '12',
        _id(2): '9',
        _id(3): '5, 4',
        _id(4): '1',
      });
    });

    test('si a otra familia la mudaron a una mesa de antes, no se deshace a '
        'medias', () {
      final antes = _alumnos(mesas: sentados);
      final o = calcular(alumnos: antes);
      final numeros = {
        for (final e in _sortear(o).asignaciones.entries)
          e.key: e.value.join(', '),
      };
      final registro = SorteoMesasRegistro(
        id: 'r1',
        eventoId: _evento,
        tipo: TipoRegistroSorteo.sorteo,
        resultado: numeros,
        antes: UltimosSorteados.antesDe(antes, numeros),
        reacomodo: true,
        createdAt: _ahora,
      );
      // Después del reacomodo, F5 recibió a mano la 12, que era de F1.
      final despues = [
        for (final a in antes)
          a.id == _id(5)
              ? a.copyWith(numeroMesa: '12')
              : a.copyWith(numeroMesa: numeros[a.id]),
      ];
      final u = UltimosSorteados.de([registro], despues)!;
      expect(u.aGuardar, isEmpty);
      expect(u.noSeTocan, hasLength(4));
      expect(u.noSeTocan.first.motivo,
          'su mesa de antes ya la tiene otra familia');
    });
  });

  group('lo que dejó el tilde de la 6.7.0', () {
    final vieja = ConfigPlano(
      fijadas: {
        2: MesaFijada(alumnoId: _id(1), motivo: MesaFijada.motivoPorOrden),
        9: MesaFijada(alumnoId: _id(4), motivo: 'Silla de ruedas'),
      },
      frente: OrdenDelPlano(
        prendido: true,
        lugares: [
          LugarPorOrden(
              alumnoId: _id(1), puesto: 1, grupo: 1, mesas: const [2], frase: ''),
        ],
      ),
    );

    test('las mesas que fijaba antes de sortear se limpian solas', () {
      final limpia = OrdenEnElSalon.sinFijadasDelOrden(vieja)!;
      expect(limpia.fijadas.keys, [9]);
      expect(OrdenEnElSalon.sinFijadasDelOrden(limpia), isNull);
      expect(OrdenEnElSalon.sinFijadasDelOrden(ConfigPlano.vacia), isNull);
    });

    test('un sorteo entero sin el tilde apaga el porqué', () {
      final c = OrdenEnElSalon.apagado(vieja)!;
      expect(c.frente!.prendido, isFalse);
      expect(c.frente!.lugares, isEmpty);
      expect(OrdenEnElSalon.apagado(c), isNull);
      expect(OrdenEnElSalon.apagado(ConfigPlano.vacia), isNull);
    });

    test('el porqué vale mientras alguna familia sigue en su mesa', () {
      expect(OrdenEnElSalon.vigente(vieja, _alumnos()), isFalse,
          reason: 'nadie tiene mesa: no se sorteó, o se deshizo');
      expect(OrdenEnElSalon.vigente(vieja, _alumnos(mesas: {1: '2'})), isTrue);
      expect(OrdenEnElSalon.vigente(vieja, _alumnos(mesas: {1: '5'})), isFalse);
      expect(
        OrdenEnElSalon.vigente(ConfigPlano.vacia, _alumnos(mesas: {1: '2'})),
        isFalse,
      );
    });
  });

  group('viaja con el plano', () {
    test('lo guardado va y vuelve con el orden', () {
      final c = calcular().configAGuardar!;
      final vuelta = ConfigPlano.fromJson(c.toJson());
      expect(vuelta.fijadas, isEmpty);
      final o = vuelta.frente!;
      expect(o.prendido, isTrue);
      expect(o.el, _ahora);
      expect([for (final l in o.lugares) '${l.puesto}:${l.mesas.join('+')}'],
          ['1:2', '2:3', '3:7+8', '4:6']);
      expect(o.lugares.first.frase, c.frente!.lugares.first.frase);
    });

    test('el recorrido va y vuelve; por columnas no escribe la clave', () {
      final columnas = calcular().configAGuardar!;
      expect(columnas.toJson(), isNot(contains('recorrido')));
      final filas = calcular(recorrido: RecorridoDelOrden.filas).configAGuardar!;
      expect(filas.toJson(), contains('"recorrido":"filas"'));
      expect(ConfigPlano.fromJson(filas.toJson()).frente!.recorrido,
          RecorridoDelOrden.filas);
      // Una clave que no se conoce es "por columnas": nunca un plano roto.
      expect(
        ConfigPlano.fromJson('{"frente": {"general": true, "recorrido": "x"}}')
            .frente!
            .recorrido,
        RecorridoDelOrden.columnas,
      );
    });

    test('una fiesta que nunca lo usó no lleva la clave', () {
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
