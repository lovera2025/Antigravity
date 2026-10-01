import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/medir_salon.dart';

/// Dos mesas en una hoja, a [separacion] unidades.
ArmadoSalon _dos(double separacion) => ArmadoSalon(
      clave: 'x',
      nombre: 'x',
      hojas: const [
        HojaPlano(id: 'A', titulo: '', caja: RectPlano(0, 0, 900, 300)),
      ],
      mesas: [
        const MesaPlano(numero: 1, hoja: 'A', x: 100, y: 100),
        MesaPlano(numero: 2, hoja: 'A', x: 100 + separacion, y: 100),
      ],
    );

void main() {
  group('el playón', () {
    test('Costa Surubí: 30 contra el escenario, 46 al fondo, 39 de fondo', () {
      const p = PlayonReal.costaSurubi;
      expect(p.superficieM2, 1482);
      expect(p.aproximado, isTrue);
      expect(p.anchoA(0), 30);
      expect(p.anchoA(39), 46);
      expect(p.anchoA(19.5), 38);
      // Fuera del hormigón no sigue abriéndose.
      expect(p.anchoA(100), 46);
      expect(p.anchoA(-5), 30);
      expect(p.aperturaPorMetro, closeTo(0.205, 0.001));
    });

    test('con cinta se miden los costados, no la profundidad', () {
      const p = PlayonReal.costaSurubi;
      // Cada costado se abre 8 m en 39 de fondo.
      expect(p.costadoM, closeTo(39.812, 0.001));
      final medido = PlayonReal.conCostado(
        frenteM: 30,
        fondoM: 46,
        costadoM: p.costadoM,
      )!;
      expect(medido.profundidadM, closeTo(39, 1e-9));
      expect(medido.aproximado, isFalse);
      // Un costado más corto que lo que se abre no cierra un trapecio.
      expect(
        PlayonReal.conCostado(frenteM: 10, fondoM: 50, costadoM: 15),
        isNull,
      );
    });

    test('ida y vuelta, y lo que no se puede leer da null', () {
      const p = PlayonReal(frenteM: 31.2, fondoM: 44, profundidadM: 40);
      expect(PlayonReal.fromMap(p.toMap()), p);
      expect(PlayonReal.fromMap(PlayonReal.costaSurubi.toMap()),
          PlayonReal.costaSurubi);
      expect(PlayonReal.fromMap(null), isNull);
      expect(PlayonReal.fromMap({'frente': 30, 'fondo': 46}), isNull);
      expect(
        PlayonReal.fromMap({'frente': 30, 'fondo': 46, 'profundidad': 9999}),
        isNull,
      );
    });
  });

  group('el lugar que pide cada mesa', () {
    test('2 m con ocho sillas, 2,15 con nueve y 2,3 con diez', () {
      const m = MedidasPlano();
      expect(m.lugarM(0), 2.0);
      expect(m.lugarM(1), closeTo(2.15, 1e-9));
      expect(m.lugarM(2), closeTo(2.3, 1e-9));
      // No hay mesas de más de diez sillas.
      expect(m.lugarM(7), closeTo(2.3, 1e-9));
      expect(m.lugarM(-1), 2.0);
    });
  });

  group('lo que ocupa un armado', () {
    test('la página 3, con 2 m por mesa', () {
      final a = ArmadosPredefinidos.normal2aPagina3();
      final o = MedirSalon.ocupa(a, lugarM: 2).single;
      // De la columna 316 a la 1673 y de la fila 350 a la 1045, más una mesa.
      expect(o.anchoM, closeTo((1673 - 316) * 2 / 105 + 2, 1e-9));
      expect(o.altoM, closeTo((1045 - 350) * 2 / 105 + 2, 1e-9));
      expect(MedirSalon.ocupaM2(a, lugarM: 2), closeTo(o.m2, 1e-9));
    });

    test('una hoja por renglón, y el pasto no cuenta', () {
      final t = ArmadosPredefinidos.tecnica1a1b();
      final o = MedirSalon.ocupa(t, lugarM: 2);
      expect(o.map((x) => x.hoja), ['A', 'B']);
      // Sin el pasto, el ancho es el de las columnas comunes (330 a 1640).
      expect(o.first.anchoM, closeTo((1640 - 330) * 2 / 105 + 2, 1e-9));
    });
  });

  group('mesas apretadas', () {
    test('a 2 m justos no avisa; a menos, sí, y dice cuánto falta', () {
      expect(MedirSalon.apretadas(_dos(105), (_) => 2.0), isEmpty);
      final p = MedirSalon.apretadas(_dos(100), (_) => 2.0).single;
      expect((p.a, p.b), (1, 2));
      // Piden lo mismo: están demasiado juntas las dos.
      expect(p.sinLugar, [1, 2]);
      expect(p.distanciaM, closeTo(100 * 2 / 105, 1e-9));
      expect(p.faltaM, closeTo(2 - 100 * 2 / 105, 1e-9));
    });

    test('una mesa con diez sillas pide más lugar que su vecina', () {
      double lugar(int n) => const MedidasPlano().lugarM(n == 1 ? 2 : 0);
      // A 2 m: entre una de 2,3 y una de 2 hacen falta 2,15.
      final p = MedirSalon.apretadas(_dos(105), lugar).single;
      expect(p.pideM, closeTo(2.15, 1e-9));
      expect(p.faltaM, closeTo(0.15, 1e-9));
      // La que no tiene su lugar es la de las diez sillas, no la vecina.
      expect(p.sinLugar, [1]);
      // A 2,2 m ya entran.
      expect(MedirSalon.apretadas(_dos(115.5), lugar), isEmpty);
    });

    test('en el Canva, entre mesas comunes no se avisa', () {
      final a = ArmadosPredefinidos.normal2aPagina3();
      // El bloque derecho de la página 3 está a menos de 2 m en el dibujo.
      expect(MedirSalon.apretadas(a, (_) => 2.0), isNotEmpty);
      expect(
        MedirSalon.apretadas(a, (_) => 2.0, soloSiPideMasDe: 2.0),
        isEmpty,
      );
      // Con sillas extra en la 10, avisa por ella y nada más.
      final pares = MedirSalon.apretadas(
        a,
        (n) => n == 10 ? 2.3 : 2.0,
        soloSiPideMasDe: 2.0,
      );
      expect(pares, isNotEmpty);
      expect(pares.every((p) => p.a == 10 || p.b == 10), isTrue);
    });

    test('las de otra hoja no se comparan', () {
      final a = ArmadosPredefinidos.normal2a2b();
      // La 101 de la hoja B está dibujada donde la 5 de la A.
      final pares = MedirSalon.apretadas(a, (_) => 2.0);
      expect(
        pares.every((p) => a.mesa(p.a)!.hoja == a.mesa(p.b)!.hoja),
        isTrue,
      );
    });
  });

  group('revisar con las medidas de la fiesta', () {
    const medidas = MedidasPlano();

    test('a medida y sin sillas extra, todas tienen su lugar', () {
      final a = ArmarAMedida.armar(
        const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 132),
      ).armado;
      expect(MedirSalon.revisar(a, medidas, (_) => 0).hay, isFalse);
      expect(SinLugar.ninguna.mesas, isEmpty);
    });

    test('con sillas extra, queda marcada esa mesa y no sus vecinas', () {
      final a = ArmarAMedida.armar(
        const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 132),
      ).armado;
      final r = MedirSalon.revisar(a, medidas, (n) => n == 30 ? 2 : 0);
      expect(r.hay, isTrue);
      expect(r.mesas, {30});
      // Los pares sí nombran a las vecinas, para decir contra cuál aprieta.
      expect(r.apretadas.length, greaterThan(1));
      expect(r.apretadas.every((p) => p.a == 30 || p.b == 30), isTrue);
    });

    test('más separadas, la de diez sillas ya entra', () {
      final a = ArmarAMedida.armar(
        const OpcionesAMedida(
          playon: PlayonReal.costaSurubi,
          cantidad: 132,
          lugarM: 2.2,
        ),
      ).armado;
      expect(MedirSalon.revisar(a, medidas, (n) => n == 30 ? 2 : 0).hay, isFalse);
    });

    test('en el Canva solo avisa por las que llevan sillas extra', () {
      final a = ArmadosPredefinidos.normal2aPagina3();
      expect(MedirSalon.revisar(a, medidas, (_) => 0).hay, isFalse);
      // La 10 tiene a la 9 a 2,10 m: con nueve sillas todavía entra (entre
      // las dos piden 2,075) y con diez ya no (2,15).
      expect(MedirSalon.revisar(a, medidas, (n) => n == 10 ? 1 : 0).hay, isFalse);
      expect(MedirSalon.revisar(a, medidas, (n) => n == 10 ? 2 : 0).mesas, {10});
    });
  });

  group('fuera del hormigón', () {
    final hecho = ArmarAMedida.armar(
      const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 60),
    ).armado;

    test('recién armado a medida, ninguna', () {
      expect(MedirSalon.fueraDelHormigon(hecho, (_) => 2.0), isEmpty);
    });

    test('una mesa corrida más allá del borde, sí', () {
      final primera = hecho.mesas.first;
      final corrido = hecho.copyWith(mesas: [
        primera.copyWith(x: 30),
        ...hecho.mesas.skip(1),
      ]);
      expect(MedirSalon.fueraDelHormigon(corrido, (_) => 2.0), [primera.numero]);
      // La misma, marcada como pasto, ya no cuenta.
      final pasto = hecho.copyWith(mesas: [
        primera.copyWith(x: 30, pasto: true),
        ...hecho.mesas.skip(1),
      ]);
      expect(MedirSalon.fueraDelHormigon(pasto, (_) => 2.0), isEmpty);
    });

    test('con más lugar, la que estaba contra el borde queda afuera', () {
      // El margen es de medio metro: con un círculo de 3,2 m ya no alcanza.
      expect(MedirSalon.fueraDelHormigon(hecho, (_) => 3.2), isNotEmpty);
    });

    test('los armados del Canva no tienen borde: nunca avisan', () {
      for (final a in ArmadosPredefinidos.todos) {
        expect(MedirSalon.fueraDelHormigon(a, (_) => 9.0), isEmpty);
      }
    });
  });

  group('la regla', () {
    test('elige el largo redondo más grande que entra', () {
      // Medio píxel por unidad: un metro son 26,25 px.
      final r = MedirSalon.reglaPara(0.5, kMetrosPorUnidadCanva);
      expect(r.metros, 5);
      expect(r.px, closeTo(131.25, 1e-9));
      // Muy de lejos, 20 m; muy de cerca, medio metro.
      expect(MedirSalon.reglaPara(0.1, kMetrosPorUnidadCanva).metros, 20);
      expect(MedirSalon.reglaPara(8, kMetrosPorUnidadCanva).metros, 0.5);
    });
  });

  group('los metros, escritos', () {
    test('con coma y sin ceros de más', () {
      expect(MedirSalon.metros(2), '2 m');
      expect(MedirSalon.metros(2.5), '2,5 m');
      expect(MedirSalon.metros(0.5), '0,5 m');
      expect(MedirSalon.metros(30), '30 m');
      expect(MedirSalon.metros(2.15, decimales: 2), '2,15 m');
      expect(MedirSalon.metros(2.3, decimales: 2), '2,3 m');
    });
  });
}
