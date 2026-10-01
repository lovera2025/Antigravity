import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';

void main() {
  group('Normal 2A, página 3 (la numeración del jefe)', () {
    final a = ArmadosPredefinidos.normal2aPagina3();

    test('78 mesas, del 1 al 78, sin pasto', () {
      expect(a.numeros, List.generate(78, (i) => i + 1));
      expect(a.cantidadPasto, 0);
    });

    test('las mesas quedan donde las puso el jefe', () {
      void en(int n, double x, double y) {
        final m = a.mesa(n)!;
        expect((m.x, m.y), (x, y), reason: 'mesa $n');
      }

      en(1, 760, 350); // junto al escenario
      en(5, 316, 350);
      en(6, 316, 470);
      en(15, 316, 585);
      en(30, 760, 930);
      en(31, 760, 1045);
      en(32, 873, 1045);
      en(36, 873, 585);
      en(37, 980, 585);
      en(41, 980, 1045);
      en(42, 1085, 1045);
      en(47, 1085, 470);
      en(48, 1188, 470);
      en(53, 1188, 1045);
      en(54, 1278, 930);
      en(58, 1278, 470);
      en(74, 1673, 930);
      en(78, 1673, 470);
    });

    test('toda la serpentina va pegada: no hay cortes', () {
      expect(a.cortes, isEmpty);
    });

    test('tiene el ingreso para el camino del tótem', () {
      expect(a.ingreso, isNotNull);
    });
  });

  group('Normal 2A, páginas 4 y 5', () {
    final a = ArmadosPredefinidos.normal2aPaginas45();

    test('100 mesas en una hoja', () {
      expect(a.numeros, List.generate(100, (i) => i + 1));
      expect(a.hojas.map((h) => h.id), ['A']);
    });

    test('las dos del medio quedan sueltas: cortes en 49 y 51', () {
      expect(a.cortes, {49, 51});
      expect(a.pegadas(50, 51), isTrue);
    });

    test('ningún bloque de colores del jefe cruza un corte', () {
      const bloques = [(1, 24), (25, 49), (50, 51), (52, 54), (55, 80), (81, 100)];
      for (final (desde, hasta) in bloques) {
        for (var n = desde; n < hasta; n++) {
          expect(a.pegadas(n, n + 1), isTrue, reason: '$n-${n + 1}');
        }
      }
    });

    test('25 y 49 quedan del lado de adentro, 31 en la columna de más', () {
      expect(a.mesa(25)!.x, a.mesa(49)!.x);
      expect(a.mesa(31)!.x, lessThan(a.mesa(30)!.x));
    });
  });

  group('Normal 2A + 2B (hoja B provisoria)', () {
    final a = ArmadosPredefinidos.normal2a2b();

    test('alcanza para la Normal: más de 132 mesas', () {
      expect(a.numeros.length, greaterThanOrEqualTo(132));
      expect(a.numeros, List.generate(a.numeros.length, (i) => i + 1));
    });

    test('la hoja B arranca en la 101, con corte al cambiar de hoja', () {
      expect(a.mesa(100)!.hoja, 'A');
      expect(a.mesa(101)!.hoja, 'B');
      expect(a.cortes, contains(100));
    });

    test('cada fila de la hoja B suma 14 (6 + 2 + 6)', () {
      expect(ArmadosPredefinidos.normal2a2b(filasHojaB: 1).numeros.length, 114);
    });
  });

  group('Técnica 1A + 1B', () {
    final a = ArmadosPredefinidos.tecnica1a1b();

    test('130 comunes y 20 de pasto, del 131 al 150', () {
      expect(a.cantidadComunes, 130);
      expect(a.pasto, {for (var n = 131; n <= 150; n++) n});
      expect(a.numeros, List.generate(150, (i) => i + 1));
    });

    test('la 1A llega hasta la 82 y la 1B va del 83 al 130', () {
      expect(a.mesa(82)!.hoja, 'A');
      expect(a.mesa(83)!.hoja, 'B');
      expect(a.mesa(130)!.hoja, 'B');
    });

    test('cortes: las mesas del medio, el cambio de hoja y el pasto', () {
      expect(a.cortes, {
        40, 42, // las dos del medio de la 1A
        82, // de la 1A a la 1B
        87, 89, 99, 101, 111, 113, 123, 125, // las del medio de la 1B
        130, // de las comunes al pasto
        133, 140, 147, // el pasto cambia de hoja y de costado
      });
    });

    test('el pasto siempre empieza después de un corte', () {
      expect(a.pegadas(130, 131), isFalse);
    });
  });

  group('todos los armados de fábrica', () {
    for (final a in ArmadosPredefinidos.todos) {
      test('${a.clave}: sin problemas', () {
        expect(a.problemas(), isEmpty);
      });

      test('${a.clave}: entre cortes, los consecutivos están pegados', () {
        for (final n in a.numeros) {
          if (!a.existe(n + 1) || a.cortes.contains(n)) continue;
          expect(a.pegadas(n, n + 1), isTrue, reason: '$n-${n + 1}');
        }
      });

      test('${a.clave}: ida y vuelta por JSON', () {
        final json = jsonEncode(a.toJson());
        final b = ArmadoSalon.fromJson(jsonDecode(json) as Map<String, dynamic>);
        expect(jsonEncode(b.toJson()), json);
        expect(b.cortes, a.cortes);
      });

      test('${a.clave}: la clave se encuentra', () {
        expect(ArmadosPredefinidos.porClave(a.clave)?.clave, a.clave);
      });

      test('${a.clave}: mide en la escala del Canva y no lleva borde', () {
        expect(a.metrosPorUnidad, kMetrosPorUnidadCanva);
        expect(a.distanciaPegadas, isNull);
        expect(a.diametroMesaM, closeTo(1.448, 0.001));
        for (final h in a.hojas) {
          expect(h.contorno, isNull, reason: 'hoja ${h.id}');
        }
      });
    }
  });

  group('las medidas del armado', () {
    test('en el Canva, de centro a centro hay 2 m', () {
      final a = ArmadosPredefinidos.normal2aPaginas45();
      // 1 y 2 son vecinas de fila: 105 unidades.
      expect(a.distanciaM(1, 2), closeTo(2.0, 1e-9));
      expect(a.aMetros(105), closeTo(2.0, 1e-9));
      expect(a.aUnidades(2.0), closeTo(105, 1e-9));
    });

    test('entre hojas distintas no hay distancia', () {
      final a = ArmadosPredefinidos.normal2a2b();
      expect(a.distanciaM(100, 101), isNull);
      expect(a.distanciaM(1, 999), isNull);
    });

    test('un armado guardado sin escala se lee con la del Canva', () {
      final json = ArmadosPredefinidos.normal2aPagina3().toJson()
        ..remove('m_u');
      final a = ArmadoSalon.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(a.metrosPorUnidad, kMetrosPorUnidadCanva);
      expect(a.cortes, isEmpty);
    });

    test('una escala o un borde mal escritos no rompen', () {
      final json = ArmadosPredefinidos.normal2aPagina3().toJson()
        ..['m_u'] = 'dos'
        ..['pegadas_u'] = -4;
      (json['hojas'] as List).first['borde'] = [
        [1, 2],
        'x',
      ];
      final a = ArmadoSalon.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(a.metrosPorUnidad, kMetrosPorUnidadCanva);
      expect(a.distanciaPegadas, isNull);
      expect(a.hojas.first.contorno, isNull);
    });

    test('con su propia distancia de pegadas, los cortes salen de ahí', () {
      ArmadoSalon armar(double? pegadas) => ArmadoSalon(
            clave: 'x',
            nombre: 'x',
            distanciaPegadas: pegadas,
            hojas: const [
              HojaPlano(id: 'A', titulo: '', caja: RectPlano(0, 0, 900, 300)),
            ],
            mesas: const [
              MesaPlano(numero: 1, hoja: 'A', x: 100, y: 100),
              MesaPlano(numero: 2, hoja: 'A', x: 300, y: 100),
            ],
          );
      // A 200 unidades: con la regla del Canva (4,2 radios = 159,6) hay corte.
      expect(armar(null).cortes, {1});
      expect(armar(210).cortes, isEmpty);
    });
  });

  group('el borde del hormigón', () {
    const borde = ContornoPlano([
      (x: 100, y: 0),
      (x: 300, y: 0),
      (x: 400, y: 200),
      (x: 0, y: 200),
    ]);

    test('sabe qué queda adentro', () {
      expect(borde.contiene(200, 100), isTrue);
      expect(borde.contiene(20, 20), isFalse);
      expect(borde.contieneCirculo(200, 100, 38), isTrue);
      // Adentro, pero el círculo cruza el costado inclinado.
      expect(borde.contiene(70, 100), isTrue);
      expect(borde.contieneCirculo(70, 100, 38), isFalse);
      expect(borde.distanciaAlBorde(200, 30), closeTo(30, 1e-9));
    });

    test('ida y vuelta por JSON, con la hoja', () {
      const h = HojaPlano(
        id: 'A',
        titulo: 'Playón',
        caja: RectPlano(0, 0, 400, 200),
        contorno: borde,
      );
      final vuelta = HojaPlano.fromJson(
        jsonDecode(jsonEncode(h.toJson())) as Map<String, dynamic>,
      );
      expect(vuelta.contorno!.puntos, borde.puntos);
    });

    test('una mesa fuera del hormigón es un problema; la del pasto, no', () {
      ArmadoSalon con(MesaPlano m) => ArmadoSalon(
            clave: 'x',
            nombre: 'x',
            hojas: const [
              HojaPlano(
                id: 'A',
                titulo: '',
                caja: RectPlano(0, 0, 400, 200),
                contorno: borde,
              ),
            ],
            mesas: [m],
          );
      expect(con(const MesaPlano(numero: 1, hoja: 'A', x: 200, y: 100)).problemas(),
          isEmpty);
      expect(
        con(const MesaPlano(numero: 1, hoja: 'A', x: 60, y: 60)).problemas().single,
        contains('fuera del hormigón'),
      );
      expect(
        con(const MesaPlano(numero: 1, hoja: 'A', x: 60, y: 60, pasto: true))
            .problemas(),
        isEmpty,
      );
    });
  });

  group('problemas()', () {
    test('avisa mesas que se pisan, repetidas o fuera de la hoja', () {
      final a = ArmadoSalon(
        clave: 'x',
        nombre: 'x',
        hojas: const [HojaPlano(id: 'A', titulo: '', caja: RectPlano(0, 0, 500, 500))],
        mesas: const [
          MesaPlano(numero: 1, hoja: 'A', x: 100, y: 100),
          MesaPlano(numero: 2, hoja: 'A', x: 130, y: 100),
          MesaPlano(numero: 2, hoja: 'A', x: 300, y: 300),
          MesaPlano(numero: 3, hoja: 'A', x: 490, y: 300),
          MesaPlano(numero: 4, hoja: 'Z', x: 200, y: 200),
        ],
        sectores: const [
          SectorPlano(
            tipo: TipoSector.pista,
            texto: 'Pista',
            hoja: 'A',
            caja: RectPlano(280, 280, 100, 100),
          ),
        ],
      );
      final p = a.problemas().join('\n');
      expect(p, contains('se pisan'));
      expect(p, contains('dos veces'));
      expect(p, contains('se sale'));
      expect(p, contains('hoja que no existe'));
      expect(p, contains('tapa la mesa'));
    });
  });
}
