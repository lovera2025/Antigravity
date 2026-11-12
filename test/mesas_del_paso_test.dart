// Las mesas del salón, de la mejor a la peor según el paso de los egresados
// (6.7.0): la columna pegada a la pasarela de punta a punta, después la que
// sigue hacia afuera.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/mesas_del_paso.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/salon_de_prueba.dart';

void main() {
  group('el salón de prueba', () {
    test('primero las pegadas a la pasarela, de punta a punta; después las de '
        'afuera', () {
      final p = MesasDelPaso.de(salonDePrueba())!;
      expect(p.enOrden, [2, 3, 7, 6, 10, 11, 1, 4, 8, 5, 9, 12]);
      expect(p.enLaLinea(1), 6);
      expect(p.enLaLinea(2), 6);
    });

    test('por filas: cada fila entera, cruzando la pasarela, y la siguiente de '
        'vuelta', () {
      final p = MesasDelPaso.de(
        salonDePrueba(),
        recorrido: RecorridoDelOrden.filas,
      )!;
      // El salón de prueba está numerado fila por fila: es 1, 2, 3, 4… sin
      // que la pasarela interrumpa (pedido del usuario, 12-nov-2026).
      expect(p.enOrden, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      // El lugar de cada mesa no depende del recorrido: cambia solo el orden.
      final columnas = MesasDelPaso.de(salonDePrueba())!;
      for (final n in p.enOrden) {
        final a = p.lugar(n)!, b = columnas.lugar(n)!;
        expect([a.linea, a.fila, a.lado], [b.linea, b.fila, b.lado]);
        expect(p.detras(n), columnas.detras(n));
      }
    });

    test('por filas, el pasto y las otras hojas también van al final', () {
      final p = MesasDelPaso.de(
        salonDePrueba(
          otras: const [
            MesaPlano(numero: 20, hoja: 'A', x: 50, y: 110, pasto: true),
            MesaPlano(numero: 30, hoja: 'B', x: 30, y: 10),
          ],
          otrasHojas: const [
            HojaPlano(id: 'B', titulo: 'B', caja: RectPlano(0, 0, 100, 40)),
          ],
        ),
        recorrido: RecorridoDelOrden.filas,
      )!;
      // Primero las doce de la hoja del paso; la otra hoja sigue, y el pasto
      // cierra.
      expect(p.enOrden.take(12), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      expect(p.enOrden.skip(12), [30, 20]);
    });

    test('la línea, la fila y el lado de cada mesa', () {
      final p = MesasDelPaso.de(salonDePrueba())!;
      final dos = p.lugar(2)!;
      expect([dos.linea, dos.fila, dos.lado], [1, 1, 0]);
      final cinco = p.lugar(5)!;
      expect([cinco.linea, cinco.fila, cinco.lado], [2, 2, 1]);
    });

    test('detrás: la misma fila y el mismo lado, una línea más afuera', () {
      final p = MesasDelPaso.de(salonDePrueba())!;
      expect(p.detras(2), 1);
      expect(p.detras(3), 4);
      expect(p.detras(7), 8);
      expect(p.detras(11), 12);
      expect(p.detras(1), isNull, reason: 'es la última de su fila');
    });

    test('la más cercana no cruza la pasarela', () {
      final p = MesasDelPaso.de(salonDePrueba())!;
      // La 2 tiene la 3 a 40 del otro lado y la 7 a 20 del suyo.
      expect(p.laMasCercana(2, [3, 7, 12]), 7);
      // Sin ninguna de su lado, la que haya.
      expect(p.laMasCercana(2, [3, 12]), 3);
      expect(p.laMasCercana(2, const []), isNull);
    });

    test('no mira los números: renumerado, el orden es el de los lugares', () {
      final base = salonDePrueba();
      // Los mismos lugares, con los números al revés.
      final otro = ArmadoSalon(
        clave: base.clave,
        nombre: base.nombre,
        radio: base.radio,
        hojas: base.hojas,
        sectores: base.sectores,
        mesas: [
          for (final m in base.mesas)
            MesaPlano(numero: 13 - m.numero, hoja: m.hoja, x: m.x, y: m.y),
        ],
      );
      expect(
        MesasDelPaso.de(otro)!.enOrden,
        [for (final n in MesasDelPaso.de(base)!.enOrden) 13 - n],
      );
    });

    test('una mesa corrida a mano sigue en su fila', () {
      final base = salonDePrueba();
      final corrida = ArmadoSalon(
        clave: base.clave,
        nombre: base.nombre,
        radio: base.radio,
        hojas: base.hojas,
        sectores: base.sectores,
        mesas: [
          for (final m in base.mesas)
            m.numero == 7 ? m.copyWith(x: 28, y: 43) : m,
        ],
      );
      expect(MesasDelPaso.de(corrida)!.enOrden,
          MesasDelPaso.de(base)!.enOrden);
    });

    test('sin pasarela, el eje sale del medio del escenario', () {
      final p = MesasDelPaso.de(salonDePrueba(conPasarela: false))!;
      expect(p.enOrden, [2, 3, 7, 6, 10, 11, 1, 4, 8, 5, 9, 12]);
    });

    test('sin escenario, las filas se cuentan desde la punta de la pasarela', () {
      final p = MesasDelPaso.de(salonDePrueba(conEscenario: false))!;
      expect(p.enOrden.take(6), [2, 3, 7, 6, 10, 11]);
    });

    test('sin pasarela ni escenario no hay paso', () {
      expect(
        MesasDelPaso.de(
          salonDePrueba(conPasarela: false, conEscenario: false),
        ),
        isNull,
      );
    });

    test('una mesa sobre el eje, donde la pasarela ya terminó, es primera '
        'línea', () {
      final p = MesasDelPaso.de(salonDePrueba(otras: const [
        MesaPlano(numero: 13, hoja: 'A', x: 50, y: 80),
        MesaPlano(numero: 14, hoja: 'A', x: 30, y: 80),
        MesaPlano(numero: 15, hoja: 'A', x: 70, y: 80),
      ]))!;
      expect(p.lugar(13)!.linea, 1);
      expect(p.lugar(13)!.fila, 4);
      // La de la izquierda queda detrás de la del medio; la de la derecha es
      // la primera de su lado.
      expect(p.detras(13), 14);
      expect(p.lugar(15)!.linea, 1);
    });

    test('el pasto y las otras hojas van al final, por número', () {
      final p = MesasDelPaso.de(salonDePrueba(
        otras: const [
          MesaPlano(numero: 20, hoja: 'A', x: 50, y: 110, pasto: true),
          MesaPlano(numero: 31, hoja: 'B', x: 10, y: 10),
          MesaPlano(numero: 30, hoja: 'B', x: 30, y: 10),
        ],
        otrasHojas: const [
          HojaPlano(id: 'B', titulo: 'B', caja: RectPlano(0, 0, 100, 40)),
        ],
      ))!;
      expect(p.enOrden.skip(12), [20, 30, 31]);
      expect(p.lugar(20), isNull);
      expect(p.detras(31), isNull);
    });
  });

  group('los salones de verdad', () {
    final salones = {
      'a medida, 63 mesas': ArmarAMedida.armar(
        const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 63),
      ).armado,
      'a medida, 101 mesas': ArmarAMedida.armar(
        const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 101),
      ).armado,
      'Normal, página 3': ArmadosPredefinidos.normal2aPagina3(),
      'Normal, dos hojas': ArmadosPredefinidos.normal2a2b(),
      'Técnica': ArmadosPredefinidos.tecnica1a1b(),
    };
    for (final caso in salones.entries) {
      test('${caso.key}: están todas, una vez, y las líneas van de adentro '
          'hacia afuera', () {
        final a = caso.value;
        final p = MesasDelPaso.de(a)!;
        expect(p.enOrden.toSet(), {for (final m in a.mesas) m.numero});
        expect(p.enOrden.length, a.mesas.length);
        // En el orden, la línea nunca baja; y adentro de una línea, la fila
        // tampoco.
        LugarEnElPaso? anterior;
        for (final n in p.enOrden) {
          final l = p.lugar(n);
          if (l == null) continue;
          if (anterior != null) {
            expect(l.linea, greaterThanOrEqualTo(anterior.linea));
            if (l.linea == anterior.linea) {
              expect(l.fila, greaterThanOrEqualTo(anterior.fila));
            }
          }
          anterior = l;
        }
        // Lo de detrás de una mesa es de su fila y su lado, una línea más.
        for (final n in p.enOrden) {
          final d = p.detras(n);
          if (d == null) continue;
          expect(p.lugar(d)!.fila, p.lugar(n)!.fila);
          expect(p.lugar(d)!.lado, p.lugar(n)!.lado);
          expect(p.lugar(d)!.linea, p.lugar(n)!.linea + 1);
        }
        // Hay primera línea, y no más de dos mesas de primera línea por fila.
        expect(p.enLaLinea(1), greaterThan(0));
        final porFila = <int, int>{};
        for (final n in p.enOrden) {
          final l = p.lugar(n);
          if (l != null && l.linea == 1) {
            porFila[l.fila] = (porFila[l.fila] ?? 0) + 1;
          }
        }
        expect(porFila.values.every((c) => c <= 2), isTrue);
      });

      test('${caso.key}, por filas: están todas, una vez, por el camino de la '
          'numeración "Fila por fila"', () {
        final a = caso.value;
        final p = MesasDelPaso.de(a, recorrido: RecorridoDelOrden.filas)!;
        expect(p.enOrden.toSet(), {for (final m in a.mesas) m.numero});
        expect(p.enOrden.length, a.mesas.length);
        // El mismo salón, numerado fila por fila: el orden es 1, 2, 3, 4…
        final numerado =
            ArmarAMedida.ordenarNumeros(a, fin: FinNumeracion.filas).armado;
        final n = numerado.mesas.length;
        expect(
          MesasDelPaso.de(numerado, recorrido: RecorridoDelOrden.filas)!.enOrden,
          [for (var i = 1; i <= n; i++) i],
        );
        // El pasto queda al final.
        final pasto = a.pasto;
        if (pasto.isNotEmpty) {
          expect(
            p.enOrden.skip(p.enOrden.length - pasto.length).toSet(),
            pasto.toSet(),
          );
        }
      });
    }

    test('en un salón armado "Fila por fila", por filas es 1, 2, 3, 4…', () {
      final a = ArmarAMedida.armar(
        const OpcionesAMedida(
          playon: PlayonReal.costaSurubi,
          cantidad: 75,
          fin: FinNumeracion.filas,
        ),
      ).armado;
      final p = MesasDelPaso.de(a, recorrido: RecorridoDelOrden.filas)!;
      expect(p.enOrden, [for (var i = 1; i <= 75; i++) i]);
      // La primera fila cruza la pasarela: tiene mesas de los dos lados antes
      // de pasar a la segunda.
      final primera = p.enOrden.takeWhile((n) => p.lugar(n)!.fila == 1);
      expect({for (final n in primera) p.lugar(n)!.lado}, {0, 1});
    });
  });
}
