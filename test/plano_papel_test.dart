// Las cuentas del plano impreso: qué parte de la hoja va al papel, qué dice la
// leyenda y dónde entra el nombre de cada división.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/plano_papel.dart';
import 'package:arguello_events/models/plano_evento.dart';

OcupantePlano familia(
  String id,
  List<int> numeros, {
  String? division = '5° A',
  Map<int, int> sillas = const {},
}) =>
    OcupantePlano(
      id: id,
      nombre: '${id.toUpperCase()}, ALUMNO',
      numeros: numeros,
      division: division,
      sillasExtraPorMesa: sillas,
    );

/// Una grilla de [filas] × [columnas] mesas a 105 unidades, numeradas por
/// filas desde 1.
ArmadoSalon grilla(int filas, int columnas, {Set<int> pasto = const {}}) =>
    ArmadoSalon(
      clave: 'grilla@1',
      nombre: 'Grilla',
      hojas: [
        HojaPlano(
          id: 'A',
          titulo: 'Salón',
          caja: RectPlano(0, 0, 200.0 + columnas * 105, 200.0 + filas * 105),
        ),
      ],
      mesas: [
        for (var f = 0; f < filas; f++)
          for (var c = 0; c < columnas; c++)
            MesaPlano(
              numero: f * columnas + c + 1,
              hoja: 'A',
              x: 150.0 + c * 105,
              y: 150.0 + f * 105,
              pasto: pasto.contains(f * columnas + c + 1),
            ),
      ],
    );

void main() {
  group('lo que va al papel', () {
    test('a medida: se recorta a donde hay mesas, sin dejar ninguna afuera', () {
      final armado = ArmarAMedida.armar(
        const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 132),
      ).armado;
      final hoja = armado.hojas.single;
      final marco = PlanoPapel.marco(armado, 'A');

      expect(marco.alto, lessThan(hoja.caja.alto * 0.75));
      for (final m in armado.mesas) {
        expect(
          marco.contieneCirculo(m.x, m.y, armado.radio),
          isTrue,
          reason: 'la mesa ${m.numero} quedó afuera',
        );
      }
      for (final s in armado.sectores) {
        expect(marco.x, lessThanOrEqualTo(s.caja.x));
        expect(marco.y, lessThanOrEqualTo(s.caja.y));
        expect(marco.derecha, greaterThanOrEqualTo(s.caja.derecha));
      }
      // Lo que quedó afuera se dice en metros: el playón mide 39 de fondo.
      final fuera = PlanoPapel.hormigonFueraM(armado, 'A', marco);
      expect(fuera, greaterThan(5));
      expect(fuera, lessThan(39));
    });

    test('a medida y casi lleno: va el hormigón entero', () {
      final opciones = const OpcionesAMedida(
        playon: PlayonReal.costaSurubi,
        cantidad: 1,
      );
      final lleno = ArmarAMedida.armar(
        opciones.conCantidad(ArmarAMedida.capacidad(opciones)),
      ).armado;
      final marco = PlanoPapel.marco(lleno, 'A');
      expect(marco, lleno.hojas.single.caja);
      expect(PlanoPapel.hormigonFueraM(lleno, 'A', marco), 0);
    });

    test('un armado del Canva se ajusta a lo dibujado y no pierde nada', () {
      for (final armado in ArmadosPredefinidos.todos) {
        for (final hoja in armado.hojas) {
          final marco = PlanoPapel.marco(armado, hoja.id);
          expect(marco.ancho, lessThanOrEqualTo(hoja.caja.ancho + 0.01));
          expect(marco.alto, lessThanOrEqualTo(hoja.caja.alto + 0.01));
          for (final m in armado.mesasDeHoja(hoja.id)) {
            expect(
              marco.contieneCirculo(m.x, m.y, armado.radio),
              isTrue,
              reason: '${armado.clave} ${hoja.id}: la mesa ${m.numero}',
            );
          }
          expect(PlanoPapel.hormigonFueraM(armado, hoja.id, marco), 0);
        }
      }
    });

    test('una hoja que no existe o vacía no rompe', () {
      final armado = grilla(2, 2);
      expect(PlanoPapel.marco(armado, 'Z').ancho, greaterThan(0));
      final vacia = ArmadoSalon(
        clave: 'v',
        nombre: 'v',
        hojas: const [
          HojaPlano(id: 'A', titulo: '', caja: RectPlano(0, 0, 500, 300)),
        ],
        mesas: const [],
      );
      expect(PlanoPapel.marco(vacia, 'A'), const RectPlano(0, 0, 500, 300));
    });
  });

  group('la leyenda', () {
    test('por bloques: cada división con su rango, en el orden del salón', () {
      final armado = grilla(4, 5);
      final estado = EstadoPlano.desde(
        armado: armado,
        ocupantes: [
          for (var n = 1; n <= 8; n++) familia('a$n', [n]),
          for (var n = 9; n <= 14; n++) familia('b$n', [n], division: '5° B'),
        ],
      );
      final d = PlanoPapel.divisiones(estado);
      expect(d.map((x) => x.texto), ['5° A: 1-8', '5° B: 9-14']);
      expect(d.map((x) => x.indice), [0, 1]);
      expect(d.first.mesas, 8);
    });

    test('salpicadas por el salón: dice cuántas, no una lista de tramos', () {
      final armado = grilla(4, 5);
      final estado = EstadoPlano.desde(
        armado: armado,
        ocupantes: [
          for (final n in [1, 3, 5, 7, 9]) familia('a$n', [n]),
          for (final n in [2, 4, 6, 8]) familia('b$n', [n], division: '5° B'),
        ],
      );
      final d = PlanoPapel.divisiones(estado);
      expect(d.first.numeros, isNull);
      expect(d.first.texto, '5° A: 5 mesas');
      expect(d.last.texto, '5° B: 4 mesas');
    });

    test('"Sin curso asignado" va al final, y una fijada cuenta', () {
      final armado = grilla(4, 5);
      final estado = EstadoPlano.desde(
        armado: armado,
        ocupantes: [
          familia('x', [1], division: null),
          familia('a', [2, 3]),
        ],
        fijadas: {10: familia('f', const [], division: '5° B')},
      );
      final d = PlanoPapel.divisiones(estado);
      expect(d.map((x) => x.nombre), ['5° A', '5° B', 'Sin curso asignado']);
      expect(d.last.indice, isNull);
      expect(d[1].texto, '5° B: 10');
    });

    test('un salón sin familias no tiene leyenda de divisiones', () {
      final armado = grilla(2, 2);
      expect(
        PlanoPapel.divisiones(EstadoPlano.desde(armado: armado)),
        isEmpty,
      );
    });
  });

  group('lo que cuenta el encabezado', () {
    test('mesas, familias, fijadas, libres y el pasto', () {
      final armado = grilla(4, 5, pasto: {19, 20});
      final estado = EstadoPlano.desde(
        armado: armado,
        ocupantes: [
          familia('a', [1, 2], sillas: {1: 2}),
          familia('b', [19]),
        ],
        libres: {5},
        fijadas: {7: familia('f', const [])},
      );
      final r = PlanoPapel.resumen(armado, estado);
      expect(r.mesas, 18);
      expect(r.pasto, 2);
      expect(r.conFamilia, 3);
      expect(r.fijadas, 1);
      expect(r.libres, 1);
      expect(r.familiasEnPasto, 1);
      expect(r.sillasExtra, 2);
      expect(
        r.texto,
        '18 mesas · 2 de pasto · 3 con familia · 1 fijada · 1 libre · '
        '1 familia en el pasto',
      );
    });

    test('lo que está en cero no se nombra', () {
      final armado = grilla(2, 3);
      expect(
        PlanoPapel.resumen(armado, EstadoPlano.desde(armado: armado)).texto,
        '6 mesas',
      );
    });

    test('dos familias con la misma mesa: una para revisar', () {
      final armado = grilla(2, 3);
      final estado = EstadoPlano.desde(
        armado: armado,
        ocupantes: [familia('a', [1]), familia('b', [1])],
      );
      expect(PlanoPapel.resumen(armado, estado).conflictos, 1);
      expect(PlanoPapel.resumen(armado, estado).texto, contains('1 para revisar'));
    });
  });

  group('el lugar entre mesas', () {
    test('en una grilla, el paso es el de la grilla', () {
      final armado = grilla(3, 4);
      expect(PlanoPapel.pasoVertical(armado, 'A'), 105);
      expect(PlanoPapel.pasoHorizontal(armado, 'A'), 105);
    });

    test('una sola fila no tiene mesa abajo; una sola columna, al lado', () {
      expect(PlanoPapel.pasoVertical(grilla(1, 4), 'A'), isNull);
      expect(PlanoPapel.pasoHorizontal(grilla(4, 1), 'A'), isNull);
    });
  });

  group('el nombre de cada división sobre su bloque', () {
    // Dos bloques de 2 filas × 5 columnas: 1-10 y 11-20.
    final armado = grilla(4, 5);
    const bloques = [BloqueDivision('5A', 1, 10), BloqueDivision('5B', 11, 20)];
    final marco = armado.hojas.single.caja;

    List<EtiquetaPapel> etiquetas(
      EstadoPlano estado, {
      double alto = 24,
      double despeje = 36,
    }) {
      bool llevaApellido(int n) {
        final i = estado.info(n);
        return i.principal && i.ocupante != null;
      }

      return PlanoPapel.etiquetas(
        armado: armado,
        hoja: 'A',
        estado: estado,
        bloques: bloques,
        marco: marco,
        ocupa: 37,
        despeje: despeje,
        alto: alto,
        ancho: (t) => 12.0 * t.length + 14,
        llevaApellido: llevaApellido,
        anchoApellido: 90,
        altoApellido: 14,
      );
    }

    EstadoPlano conDobles() => EstadoPlano.desde(
          armado: armado,
          ocupantes: [
            // La segunda mesa de cada una (la 3 y la 13) queda sin apellido.
            familia('a1', [2, 3]),
            for (final n in [1, 4, 5, 6, 7, 8, 9, 10]) familia('a$n', [n]),
            familia('b1', [12, 13], division: '5° B'),
            for (final n in [11, 14, 15, 16, 17, 18, 19, 20])
              familia('b$n', [n], division: '5° B'),
          ],
        );

    test('va debajo de una mesa sin apellido, con el nombre como se escribe', () {
      final estado = conDobles();
      final e = etiquetas(estado);
      expect(e.map((x) => x.texto), ['5° A', '5° B']);
      final mesa3 = armado.mesa(3)!;
      final mesa13 = armado.mesa(13)!;
      expect(e[0].caja.centroX, mesa3.x);
      expect(e[0].caja.y, greaterThan(mesa3.y));
      expect(e[1].caja.centroX, mesa13.x);
      expect(e[1].caja.y, greaterThan(mesa13.y));
    });

    test('no pisa ninguna mesa ni se sale de lo que se ve', () {
      for (final e in etiquetas(conDobles())) {
        for (final m in armado.mesas) {
          expect(
            e.caja.solapeConCirculo(m.x, m.y, 36),
            lessThanOrEqualTo(0.5),
            reason: '"${e.texto}" pisa la mesa ${m.numero}',
          );
        }
        expect(e.caja.x, greaterThanOrEqualTo(marco.x));
        expect(e.caja.abajo, lessThanOrEqualTo(marco.abajo));
      }
    });

    test('si a una división no le entra, la hoja sale sin etiquetas', () {
      // En el bloque de 5° B todas las mesas llevan apellido: no hay hueco.
      final estado = EstadoPlano.desde(
        armado: armado,
        ocupantes: [
          familia('a1', [2, 3]),
          for (final n in [1, 4, 5, 6, 7, 8, 9, 10]) familia('a$n', [n]),
          for (var n = 11; n <= 20; n++) familia('b$n', [n], division: '5° B'),
        ],
      );
      expect(etiquetas(estado), isEmpty);
    });

    test('una etiqueta más alta que el hueco entre filas no se pone', () {
      // Entre filas quedan 105 - 2 × 36 = 33 unidades.
      expect(etiquetas(conDobles(), alto: 40), isEmpty);
    });

    test('sin sorteo por bloques no hay etiquetas', () {
      expect(
        PlanoPapel.etiquetas(
          armado: armado,
          hoja: 'A',
          estado: conDobles(),
          bloques: const [],
          marco: marco,
          ocupa: 37,
          despeje: 36,
          alto: 24,
          ancho: (t) => 60,
          llevaApellido: (_) => false,
          anchoApellido: 90,
          altoApellido: 14,
        ),
        isEmpty,
      );
    });

    test('un bloque que no está en esta hoja no cuenta', () {
      final estado = conDobles();
      final e = PlanoPapel.etiquetas(
        armado: armado,
        hoja: 'A',
        estado: estado,
        bloques: [...bloques, const BloqueDivision('5C', 200, 240)],
        marco: marco,
        ocupa: 37,
        despeje: 36,
        alto: 24,
        ancho: (t) => 12.0 * t.length + 14,
        llevaApellido: (n) {
          final i = estado.info(n);
          return i.principal && i.ocupante != null;
        },
        anchoApellido: 90,
        altoApellido: 14,
      );
      expect(e.map((x) => x.texto), ['5° A', '5° B']);
    });
  });
}
