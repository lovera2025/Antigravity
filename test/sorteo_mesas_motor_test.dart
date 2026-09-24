import 'dart:math';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';

ContratoAlumno alumno(
  String id, {
  int extras = 0,
  double precioMesa = 70000,
  String? mesa,
  bool baja = false,
  int sillas = 0,
  double? precioSillas,
  int acompanantes = 0,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e1',
      nombreAlumno: baja ? '[BAJA] $id' : id,
      cantidadAcompanantes: acompanantes,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: extras > 0 ? precioMesa * extras : 0,
      mesaExtraCantidad: extras,
      numeroMesa: mesa,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: precioSillas ?? sillas * 8000.0,
    );

/// Los tamaños reales de las 9 instituciones (23-sep-2026): mesas por alumno →
/// cuántos alumnos. Con PONCE, SILVERO y GONZALES ya en 3 mesas.
const Map<String, Map<int, int>> kInstitucionesReales = {
  'Puerto Viejo': {1: 14, 2: 6, 5: 1},
  'Técnica Pinaroli': {1: 68, 2: 12, 3: 2},
  'Buena Vista': {1: 52, 2: 1},
  'Normal Iloza': {1: 100, 2: 16},
  'Gregoria Morales': {1: 37, 2: 2},
  'Güemez de Tejada': {1: 61, 2: 5},
  'Colegio Nacional': {1: 101, 2: 11, 3: 1},
  'Rotonda': {1: 37, 2: 5, 3: 2},
  'Sagrado Corazón': {1: 87, 2: 15},
};

List<ContratoAlumno> institucion(Map<int, int> tamanios) {
  final out = <ContratoAlumno>[];
  var i = 0;
  for (final e in tamanios.entries) {
    for (var k = 0; k < e.value; k++) {
      out.add(alumno('a${(i++).toString().padLeft(3, '0')}', extras: e.key - 1));
    }
  }
  return out;
}

/// Sortea con la capacidad mínima que propone el diálogo y verifica todo.
Map<String, List<int>> sortearYVerificar(
  List<ContratoAlumno> alumnos, {
  Map<String, int> separaciones = const {},
  int margen = 0,
  required int semilla,
}) {
  final pedidos =
      SorteoMesasMotor.pedidos(alumnos, separaciones: separaciones);
  final ocupadas = SorteoMesasMotor.ocupadas(alumnos);
  final minima =
      SorteoMesasMotor.capacidadMinima(pedidos: pedidos, ocupadas: ocupadas);
  final capacidad = minima + margen;
  expect(
    SorteoMesasMotor.esFactible(
      pedidos: pedidos,
      ocupadas: ocupadas,
      capacidad: capacidad,
    ),
    isTrue,
    reason: 'la capacidad propuesta tiene que alcanzar (semilla $semilla)',
  );
  final asignaciones = SorteoMesasMotor.sortear(
    pedidos: pedidos,
    ocupadas: ocupadas,
    capacidad: capacidad,
    random: Random(semilla),
  );
  expect(
    SorteoMesasMotor.validar(
      pedidos: pedidos,
      ocupadas: ocupadas,
      capacidad: capacidad,
      asignaciones: asignaciones,
    ),
    isNull,
    reason: 'la red de seguridad no tiene que activarse (semilla $semilla)',
  );
  return asignaciones;
}

void main() {
  group('numerosMesaDesdeTexto', () {
    test('lee el formato del sorteo y lo cargado a mano', () {
      Set<int> n(String? t) => MesasExtraUtils.numerosMesaDesdeTexto(t);
      expect(n('12, 13, 14'), {12, 13, 14});
      expect(n('40-42'), {40, 41, 42});
      expect(n('40 - 42'), {40, 41, 42});
      expect(n('40 al 42'), {40, 41, 42});
      expect(n('40 y 41'), {40, 41});
      expect(n('40/41'), {40, 41});
      expect(n('40; 41'), {40, 41});
      expect(n('Mesa 7'), {7});
      expect(n('12-14 (2 extra)'), {12, 13, 14});
      expect(n('4-400'), {4, 400}, reason: 'un rango absurdo no se expande');
      expect(n(''), <int>{});
      expect(n(null), <int>{});
      expect(n('A'), <int>{});
    });
  });

  group('SorteoMesasMotor: casos puntuales', () {
    test('las mesas de un alumno quedan juntas y nadie repite número', () {
      final alumnos = [
        alumno('a', extras: 2),
        alumno('b'),
        alumno('c', extras: 1),
        alumno('d'),
      ];
      for (var s = 0; s < 50; s++) {
        final r = sortearYVerificar(alumnos, semilla: s);
        expect(r['a']!.length, 3);
        expect(SorteoMesasMotor.tramosDe(r['a']!).length, 1);
        expect(r['c']!.length, 2);
        final todos = r.values.expand((e) => e).toList();
        expect(todos.toSet().length, todos.length);
      }
    });

    test('capacidad justa en un salón limpio: el mínimo es la demanda', () {
      final alumnos = institucion({1: 12, 3: 3});
      final pedidos = SorteoMesasMotor.pedidos(alumnos);
      expect(
        SorteoMesasMotor.capacidadMinima(pedidos: pedidos, ocupadas: {}),
        21,
      );
    });

    test('separadas: bloque + sueltas que no se tocan', () {
      final alumnos = [
        alumno('sep', extras: 2),
        for (var i = 0; i < 10; i++) alumno('s$i'),
      ];
      for (var s = 0; s < 50; s++) {
        final r = sortearYVerificar(
          alumnos,
          separaciones: const {'sep': 1},
          semilla: s,
        );
        final tramos = SorteoMesasMotor.tramosDe(r['sep']!)
            .map((t) => t.length)
            .toList()
          ..sort();
        expect(tramos, [1, 2]);
      }
    });

    test('todas separadas: ninguna pegada a otra', () {
      final alumnos = [
        alumno('sep', extras: 4),
        for (var i = 0; i < 6; i++) alumno('s$i'),
      ];
      for (var s = 0; s < 50; s++) {
        final r = sortearYVerificar(
          alumnos,
          separaciones: const {'sep': 4},
          semilla: s,
        );
        final nums = r['sep']!;
        for (var i = 1; i < nums.length; i++) {
          expect(nums[i] - nums[i - 1], greaterThan(1));
        }
      }
    });

    test('un alumno solo con todas separadas entra con su hueco de guarda', () {
      final alumnos = [alumno('solo', extras: 2)];
      final pedidos = SorteoMesasMotor.pedidos(
        alumnos,
        separaciones: const {'solo': 2},
      );
      final minima =
          SorteoMesasMotor.capacidadMinima(pedidos: pedidos, ocupadas: {});
      expect(minima, 5, reason: '1 _ 3 _ 5');
      sortearYVerificar(alumnos, separaciones: const {'solo': 2}, semilla: 1);
    });

    test('respeta lo ocupado, incluidos los números de alumnos de baja', () {
      final alumnos = [
        alumno('conMesa', mesa: '1, 2'),
        alumno('baja', mesa: '4', baja: true),
        alumno('nuevo1'),
        alumno('nuevo2', extras: 1),
      ];
      for (var s = 0; s < 30; s++) {
        final r = sortearYVerificar(alumnos, semilla: s);
        expect(r.containsKey('conMesa'), isFalse);
        expect(r.containsKey('baja'), isFalse);
        final nuevos = [...r['nuevo1']!, ...r['nuevo2']!];
        expect(nuevos.any((n) => n == 1 || n == 2 || n == 4), isFalse);
      }
    });

    test('aprovecha los huecos: un alumno nuevo después del sorteo', () {
      // Salón de 10 ya sorteado, con el 6 liberado por una baja definitiva.
      final alumnos = [
        for (final n in [1, 2, 3, 4, 5, 7, 8, 9, 10]) alumno('x$n', mesa: '$n'),
        alumno('llegoTarde'),
      ];
      final pedidos = SorteoMesasMotor.pedidos(alumnos);
      final ocupadas = SorteoMesasMotor.ocupadas(alumnos);
      expect(
        SorteoMesasMotor.capacidadMinima(pedidos: pedidos, ocupadas: ocupadas),
        10,
        reason: 'el salón ya llega a la 10, y el hueco del 6 alcanza',
      );
      final r = sortearYVerificar(alumnos, semilla: 3);
      expect(r['llegoTarde'], [6]);
    });

    test('completar: compró una mesa extra después del sorteo', () {
      final alumnos = [
        alumno('compro', extras: 1, mesa: '5'),
        alumno('otro', mesa: '7'),
      ];
      final r = sortearYVerificar(alumnos, margen: 5, semilla: 2);
      expect(r['compro'], [5, 6], reason: 'pegada a la suya y sin mover el 5');
      expect(r.containsKey('otro'), isFalse);
    });

    test('completar sin lugar al lado: la libre más cercana', () {
      final alumnos = [
        alumno('compro', extras: 1, mesa: '5'),
        alumno('izq', mesa: '4'),
        alumno('der', mesa: '6'),
      ];
      final r = sortearYVerificar(alumnos, margen: 2, semilla: 2);
      expect(r['compro']!.contains(5), isTrue);
      expect(r['compro']!.length, 2);
    });

    test('un número que no se entiende no se toca', () {
      final alumnos = [alumno('raro', mesa: 'A'), alumno('nuevo')];
      final pedidos = SorteoMesasMotor.pedidos(alumnos);
      expect(pedidos.map((p) => p.alumnoId), ['nuevo']);
    });

    test('al que le sobran mesas no se lo toca', () {
      final alumnos = [alumno('sobra', mesa: '1, 2')];
      expect(SorteoMesasMotor.pedidos(alumnos), isEmpty);
    });

    test('capacidad menor al mínimo: no es factible y sortear se niega', () {
      final alumnos = institucion({1: 5, 2: 2});
      final pedidos = SorteoMesasMotor.pedidos(alumnos);
      expect(
        SorteoMesasMotor.esFactible(
          pedidos: pedidos,
          ocupadas: {},
          capacidad: 8,
        ),
        isFalse,
      );
      expect(
        () => SorteoMesasMotor.sortear(
          pedidos: pedidos,
          ocupadas: {},
          capacidad: 8,
        ),
        throwsStateError,
      );
    });
  });

  group('SorteoMesasMotor.validar: la red de seguridad detecta todo', () {
    final pedidos = [
      const PedidoSorteo(alumnoId: 'a', mesas: 2),
      const PedidoSorteo(alumnoId: 'b', mesas: 1),
      const PedidoSorteo(alumnoId: 'c', mesas: 3, separadas: 1),
      const PedidoSorteo(alumnoId: 'd', mesas: 2, actuales: [9]),
    ];
    String? v(Map<String, List<int>> r, {Set<int> ocupadas = const {9}}) =>
        SorteoMesasMotor.validar(
          pedidos: pedidos,
          ocupadas: ocupadas,
          capacidad: 12,
          asignaciones: r,
        );

    final bien = {
      'a': [1, 2],
      'b': [3],
      'c': [5, 6, 11],
      'd': [9, 10],
    };

    test('un resultado correcto pasa', () => expect(v(bien), isNull));
    test('número repetido', () {
      expect(v({...bien, 'b': [2]}), contains('dos veces'));
    });
    test('número ya ocupado', () {
      expect(v({...bien, 'b': [4]}, ocupadas: {4, 9}), contains('ocupado'));
    });
    test('cantidad incorrecta', () {
      expect(v({...bien, 'a': [1]}), contains('le corresponden'));
    });
    test('fuera del salón', () {
      expect(v({...bien, 'b': [13]}), contains('fuera del salón'));
    });
    test('juntas que no quedaron juntas', () {
      expect(v({...bien, 'a': [1, 3]}), contains('juntas'));
    });
    test('separada pegada al bloque', () {
      expect(v({...bien, 'c': [5, 6, 7]}), contains('pegadas'));
    });
    test('se movió un número que ya tenía', () {
      expect(v({...bien, 'd': [10, 11]}), contains('ya tenía'));
    });
  });

  group('SorteoMesasMotor: estrés con las instituciones reales', () {
    for (final e in kInstitucionesReales.entries) {
      test('${e.key}: capacidad justa, con y sin separadas', () {
        for (var s = 0; s < 40; s++) {
          final rng = Random(s);
          final alumnos = institucion(e.value);
          final separaciones = <String, int>{};
          if (s.isOdd) {
            for (final a in alumnos) {
              final m = SalonMesas.mesas(a);
              if (m > 1 && rng.nextDouble() < 0.5) {
                separaciones[a.id] = 1 + rng.nextInt(m - 1);
              }
            }
          }
          sortearYVerificar(
            alumnos,
            separaciones: separaciones,
            margen: s % 5 == 0 ? rng.nextInt(10) : 0,
            semilla: s,
          );
        }
      });

      test('${e.key}: con mesas cargadas a mano y alumnos a completar', () {
        for (var s = 0; s < 25; s++) {
          final rng = Random(1000 + s);
          final base = institucion(e.value);
          final total =
              base.fold<int>(0, (acc, a) => acc + SalonMesas.mesas(a));
          // Unos cuantos ya tienen mesa a mano, en lugares al azar; a algunos
          // les falta una porque compraron una extra después.
          final usados = <int>{};
          final alumnos = <ContratoAlumno>[];
          for (final a in base) {
            if (rng.nextDouble() < 0.15) {
              final n = 1 + rng.nextInt(total + 20);
              if (usados.add(n)) {
                final extraDespues = rng.nextDouble() < 0.3;
                alumnos.add(
                  alumno(
                    a.id,
                    extras: SalonMesas.mesasExtra(a) + (extraDespues ? 1 : 0),
                    mesa: '$n',
                  ),
                );
                continue;
              }
            }
            alumnos.add(a);
          }
          final separaciones = <String, int>{
            for (final a in alumnos)
              if (a.numeroMesa == null &&
                  SalonMesas.mesas(a) > 1 &&
                  rng.nextBool())
                a.id: 1,
          };
          sortearYVerificar(
            alumnos,
            separaciones: separaciones,
            semilla: 2000 + s,
          );
        }
      });
    }
  });

  group('SorteoMesasMotor: salones difíciles a propósito', () {
    // Lo peor que puede pasar: muchos bloques grandes, pocos de una mesa para
    // rellenar huecos, separadas por todos lados, mesas ya cargadas a mano y la
    // capacidad justa. 2000 salones distintos; ninguno puede trabarse.
    test('2000 salones al azar con capacidad justa', () {
      final rng = Random(20260923);
      for (var s = 0; s < 2000; s++) {
        final cantidad = 1 + rng.nextInt(40);
        final alumnos = <ContratoAlumno>[];
        final usados = <int>{};
        for (var i = 0; i < cantidad; i++) {
          final extras = rng.nextDouble() < 0.6 ? 1 + rng.nextInt(4) : 0;
          String? mesa;
          if (rng.nextDouble() < 0.1) {
            final n = 1 + rng.nextInt(cantidad * 3 + 1);
            if (usados.add(n)) mesa = '$n';
          }
          alumnos.add(
            alumno(
              'x$i',
              extras: extras,
              mesa: mesa,
              baja: mesa != null && rng.nextDouble() < 0.2,
            ),
          );
        }
        final separaciones = <String, int>{
          for (final a in alumnos)
            if (SalonMesas.mesas(a) > 1 && rng.nextDouble() < 0.5)
              a.id: 1 + rng.nextInt(SalonMesas.mesas(a) - 1),
        };
        sortearYVerificar(
          alumnos,
          separaciones: separaciones,
          semilla: s,
        );

        // Más capacidad nunca puede dejar de entrar: el salón real puede tener
        // más mesas que el mínimo, y el botón tiene que seguir habilitado.
        if (s % 4 == 0) {
          final pedidos =
              SorteoMesasMotor.pedidos(alumnos, separaciones: separaciones);
          final ocupadas = SorteoMesasMotor.ocupadas(alumnos);
          final minima = SorteoMesasMotor.capacidadMinima(
            pedidos: pedidos,
            ocupadas: ocupadas,
          );
          for (var c = minima; c <= minima + 15; c++) {
            expect(
              SorteoMesasMotor.esFactible(
                pedidos: pedidos,
                ocupadas: ocupadas,
                capacidad: c,
              ),
              isTrue,
              reason: 'salón $s: entra con $minima pero no con $c',
            );
          }
        }
      }
    });
  });

  group('SalonMesas: lo que se muestra', () {
    test('texto de mesas: juntas, separadas, sin mesa', () {
      expect(SalonMesas.textoMesas(alumno('a', extras: 2, mesa: '12, 13, 14')),
          '12-14 (2 extra)');
      expect(SalonMesas.textoMesas(alumno('a', extras: 2, mesa: '12, 13, 40')),
          '12-13 + 40 (separada)');
      expect(SalonMesas.textoMesas(alumno('a', mesa: '7')), '7');
      expect(SalonMesas.textoMesas(alumno('a')), '-');
    });

    test('aviso cuando las mesas no coinciden con la cuenta', () {
      expect(SalonMesas.avisoMesas(alumno('a', extras: 1, mesa: '5')),
          'le falta 1 mesa');
      expect(SalonMesas.avisoMesas(alumno('a', mesa: '5, 6, 7')),
          'le sobran 2 mesas');
      expect(SalonMesas.avisoMesas(alumno('a', extras: 1, mesa: '5, 6')), isNull);
      expect(SalonMesas.avisoMesas(alumno('a', extras: 1)), isNull);
    });

    test('sillas: solo las que figuran en la cuenta', () {
      expect(SalonMesas.sillasExtra(alumno('a', sillas: 2)), 2);
      expect(
        SalonMesas.sillasExtra(alumno('caceres', sillas: 2, precioSillas: 0)),
        0,
        reason: 'con precio 0 no están en su cuenta',
      );
      expect(SalonMesas.textoSillas(alumno('caceres', sillas: 2, precioSillas: 0)),
          '-');
    });

    test('máximo 2 sillas extra por mesa', () {
      expect(SalonMesas.maxSillasExtra(alumno('a')), 2);
      expect(SalonMesas.maxSillasExtra(alumno('a', extras: 1)), 4);
      expect(SalonMesas.maxSillasExtra(alumno('a', extras: 2)), 6);
    });

    test('reparto de sillas: de a 2 por mesa, primero el bloque', () {
      final quiroz = alumno('q', extras: 1, mesa: '12, 13', sillas: 4);
      expect(SalonMesas.textoRepartoSillas(quiroz), '12 (+2) · 13 (+2)');
      final nicolini = alumno('n', extras: 1, mesa: '30, 31', sillas: 3);
      expect(SalonMesas.textoRepartoSillas(nicolini), '30 (+2) · 31 (+1)');
      final separada = alumno('s', extras: 2, mesa: '40, 12, 13', sillas: 3);
      expect(SalonMesas.textoRepartoSillas(separada), '12 (+2) · 13 (+1)');
      expect(SalonMesas.textoRepartoSillas(alumno('x', sillas: 2)),
          '2 sillas extra');
      expect(SalonMesas.textoRepartoSillas(alumno('x')), '-');
    });

    test('personas por mesa: 8 asientos por mesa más las sillas extra', () {
      OcupacionAsientos oc(int personas, {int mesas = 1, int sillas = 0}) =>
          OcupacionAsientos(
            personas: personas,
            mesas: mesas,
            sillasExtra: sillas,
          );
      expect(oc(3).entran, isTrue);
      expect(oc(3).asientos, 8);
      expect(oc(8).entran, isTrue);
      expect(oc(10).sugerencia, 'Faltan 2 asientos: sumá 2 sillas extra');
      expect(oc(10, sillas: 2).entran, isTrue);
      expect(oc(11).sugerencia, 'No entran en 1 mesa: hace falta una mesa extra');
      expect(oc(9, sillas: 2).entran, isTrue);
      final familia = alumno('f', acompanantes: 2);
      expect(SalonMesas.ocupacion(familia).texto, '3 de 8 lugares');
    });

    test('precio habitual: la moda, y nada si hay empate', () {
      final evento = [
        alumno('a', extras: 1),
        alumno('b', extras: 1),
        alumno('c', extras: 1, precioMesa: 140000),
      ];
      expect(PreciosHabituales.de(evento).mesaExtra, 70000);
      expect(
        PreciosHabituales.de([
          alumno('a', extras: 1),
          alumno('c', extras: 1, precioMesa: 140000),
        ]).mesaExtra,
        isNull,
      );
    });

    test('avisos antes de sortear', () {
      final evento = [
        alumno('ok1', extras: 1, sillas: 2),
        alumno('ok2', extras: 1, sillas: 2),
        alumno('ok3', extras: 1),
        alumno('ponce', extras: 1, precioMesa: 140000),
        alumno('esmay', extras: 1, sillas: 2, precioSillas: 36000),
        alumno('demas', sillas: 3),
        alumno('falta', extras: 1, mesa: '9'),
        alumno('raro', mesa: 'A'),
        alumno('caceres', extras: 1, sillas: 2, precioSillas: 0),
        alumno('baja', extras: 1, precioMesa: 140000, baja: true),
      ];
      final tipos = {
        for (final a in SalonMesas.avisos(evento)) a.alumnoId: a.tipo,
      };
      expect(tipos['ponce'], TipoAvisoSalon.precioMesa);
      expect(tipos['esmay'], TipoAvisoSalon.precioSillas);
      expect(tipos['demas'], TipoAvisoSalon.sillasDeMas);
      expect(tipos['falta'], TipoAvisoSalon.mesasNoCoinciden);
      expect(tipos['raro'], TipoAvisoSalon.numeroIlegible);
      expect(tipos.containsKey('caceres'), isFalse,
          reason: 'sus sillas sin precio no están en la cuenta');
      expect(tipos.containsKey('baja'), isFalse);
      expect(tipos.containsKey('ok1'), isFalse);
    });

    test('aviso por pagos a una mesa extra que no figura', () {
      final a = alumno('pago2', extras: 1);
      final avisos = SalonMesas.avisos(
        [a],
        pagosPorContrato: {
          'pago2': [
            {
              'concepto': 'Mesa Extra 2 (1/7)',
              'monto_gross': 10000.0,
              'anulado': 0,
            },
          ],
        },
      );
      expect(avisos.single.tipo, TipoAvisoSalon.pagosDeOtraMesa);
    });
  });
}
