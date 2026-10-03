import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/medir_salon.dart';

const _surubi = PlayonReal.costaSurubi;

/// Lo que tiene que cumplir cualquier salón armado a medida.
void _revisar(ArmadoAMedida r, OpcionesAMedida o, String caso) {
  final a = r.armado;
  final lugar = o.lugarM < MedidasPlano.lugarMinimoM
      ? MedidasPlano.lugarMinimoM
      : o.lugarM;

  expect(a.numeros, List.generate(a.mesas.length, (i) => i + 1), reason: caso);
  expect(r.puestas, o.cantidad < r.capacidad ? o.cantidad : r.capacidad,
      reason: caso);
  expect(r.faltan, o.cantidad - r.puestas, reason: caso);
  expect(r.mesasPorFila.fold<int>(0, (s, n) => s + n), r.puestas, reason: caso);
  expect(a.problemas(), isEmpty, reason: caso);
  expect(MedirSalon.fueraDelHormigon(a, (_) => lugar), isEmpty, reason: caso);
  expect(MedirSalon.apretadas(a, (_) => lugar), isEmpty, reason: caso);
  expect(a.cantidadPasto, 0, reason: caso);
  for (final h in a.hojas) {
    expect(h.contorno, isNotNull, reason: '$caso, hoja ${h.id}');
  }
  for (final n in a.numeros) {
    if (!a.existe(n + 1) || a.cortes.contains(n)) continue;
    expect(a.pegadas(n, n + 1), isTrue, reason: '$caso, $n-${n + 1}');
  }

  final json = jsonEncode(a.toJson());
  final vuelta = ArmadoSalon.fromJson(jsonDecode(json) as Map<String, dynamic>);
  expect(jsonEncode(vuelta.toJson()), json, reason: caso);
  expect(vuelta.cortes, a.cortes, reason: caso);
  expect(vuelta.problemas(), isEmpty, reason: caso);
}

void main() {
  group('Costa Surubí, 132 mesas a 2 m', () {
    const o = OpcionesAMedida(playon: _surubi, cantidad: 132);
    final r = ArmarAMedida.armar(o);
    final a = r.armado;

    test('entran las 132, en una hoja, sin nada que arreglar', () {
      expect(r.puestas, 132);
      expect(r.faltan, 0);
      expect(a.hojas.map((h) => h.id), ['A']);
      expect(a.clave, ArmarAMedida.claveArmado);
      expect(a.descripcion, '132 mesas a 2 m');
      _revisar(r, o, 'surubí 132');
    });

    test('las mesas vecinas quedan a 2 m', () {
      expect(a.distanciaM(1, 2), closeTo(2.0, 1e-9));
      expect(a.diametroMesaM, closeTo(1.448, 0.001));
    });

    test('la serpentina se corta solo al pasar de un lado al otro', () {
      // La última fila queda incompleta y conserva las mesas de adentro: igual
      // sigue pegada a la anterior, de los dos lados.
      expect(r.mesasPorFila.last, lessThan(r.mesasPorFila[r.mesasPorFila.length - 2]));
      expect(a.cortes.length, 1, reason: '${a.cortes}');
      final corte = a.cortes.single;
      final centro = a.hojas.single.caja.centroX;
      expect(a.mesa(corte)!.x, lessThan(centro));
      expect(a.mesa(corte + 1)!.x, greaterThan(centro));
    });

    test('la 1 y la última quedan contra el escenario, una de cada lado', () {
      final hoja = a.hojas.single;
      final frente = hoja.contorno!.puntos.first.y;
      final primera = a.mesa(1)!;
      final ultima = a.mesa(132)!;
      // Medio metro de despeje más media mesa con sus sillas.
      expect(a.aMetros(primera.y - frente), closeTo(1.5, 1e-9));
      expect(ultima.y, primera.y);
      expect(primera.x, lessThan(hoja.caja.centroX));
      expect(ultima.x, greaterThan(hoja.caja.centroX));
      expect(
        a.mesas.where((m) => m.y == primera.y).length,
        r.mesasPorFila.first,
      );
    });

    test('la capacidad del playón es bastante más que 132', () {
      // ignore: avoid_print
      print('Costa Surubí a 2 m: entran hasta ${r.capacidad} mesas '
          '(filas: ${ArmarAMedida.armar(o.conCantidad(9999)).mesasPorFila})');
      expect(r.capacidad, ArmarAMedida.capacidad(o));
      expect(r.capacidad, greaterThan(230));
    });

    test('a 2,5 m también entran las 132', () {
      const o25 = OpcionesAMedida(playon: _surubi, cantidad: 132, lugarM: 2.5);
      final r25 = ArmarAMedida.armar(o25);
      // ignore: avoid_print
      print('Costa Surubí a 2,5 m: entran hasta ${r25.capacidad} mesas');
      expect(r25.faltan, 0);
      expect(r25.armado.distanciaM(1, 2), closeTo(2.5, 1e-9));
      _revisar(r25, o25, 'surubí 132 a 2,5');
    });
  });

  group('cuando no entran todas', () {
    test('pone las que entran y dice cuántas faltan', () {
      const o = OpcionesAMedida(playon: _surubi, cantidad: 9999, lugarM: 3);
      final r = ArmarAMedida.armar(o);
      expect(r.puestas, r.capacidad);
      expect(r.faltan, 9999 - r.capacidad);
      _revisar(r, o, 'surubí lleno a 3 m');
    });

    test('lleno, el salón es simétrico', () {
      final a = ArmarAMedida.armar(
        const OpcionesAMedida(playon: _surubi, cantidad: 9999),
      ).armado;
      final caja = a.hojas.single.caja;
      final centro = caja.centroX;
      final puntos = {
        for (final m in a.mesas) '${m.x.toStringAsFixed(3)}|${m.y}',
      };
      for (final m in a.mesas) {
        final espejo = (2 * centro - m.x).toStringAsFixed(3);
        expect(puntos, contains('$espejo|${m.y}'), reason: 'mesa ${m.numero}');
      }
    });

    test('un playón donde no entra ninguna no rompe', () {
      const o = OpcionesAMedida(
        playon: PlayonReal(frenteM: 5, fondoM: 5, profundidadM: 5),
        cantidad: 10,
        lugarM: 4,
      );
      final r = ArmarAMedida.armar(o);
      expect(r.puestas, 0);
      expect(r.faltan, 10);
      expect(r.capacidad, 0);
    });
  });

  group('la distancia entre mesas', () {
    test('no puede ser menos que la mesa: se queda en 1,5 m', () {
      const o = OpcionesAMedida(playon: _surubi, cantidad: 40, lugarM: 0.4);
      final r = ArmarAMedida.armar(o);
      expect(r.armado.distanciaM(1, 2), closeTo(1.5, 1e-9));
      _revisar(r, o, 'lugar chico');
    });

    test('más separadas entran menos', () {
      int entran(double lugar) => ArmarAMedida.capacidad(
            OpcionesAMedida(playon: _surubi, cantidad: 1, lugarM: lugar),
          );
      expect(entran(2.0), greaterThan(entran(2.5)));
      expect(entran(2.5), greaterThan(entran(3.0)));
    });

    test('usar todo el playón: la más holgada con la que entran todas', () {
      const o = OpcionesAMedida(playon: _surubi, cantidad: 132);
      final lugar = ArmarAMedida.lugarMasHolgado(o)!;
      // ignore: avoid_print
      print('132 mesas en todo el playón: a $lugar m');
      expect(lugar, greaterThan(2.5));
      int entran(double l) => ArmarAMedida.capacidad(
            OpcionesAMedida(playon: _surubi, cantidad: 132, lugarM: l),
          );
      expect(entran(lugar), greaterThanOrEqualTo(132));
      // Cinco centímetros más y ya no entran.
      expect(entran(lugar + 0.05), lessThan(132));
      final r = ArmarAMedida.armar(
        OpcionesAMedida(playon: _surubi, cantidad: 132, lugarM: lugar),
      );
      expect(r.faltan, 0);
    });

    test('si no entran ni apretadas, no hay distancia que sirva', () {
      expect(
        ArmarAMedida.lugarMasHolgado(
          const OpcionesAMedida(playon: _surubi, cantidad: 5000),
        ),
        isNull,
      );
    });
  });

  group('la pasarela', () {
    test('sin pasarela, el medio se llena desde la primera fila', () {
      const o = OpcionesAMedida(playon: _surubi, cantidad: 9999, pasarelaM: 0);
      final r = ArmarAMedida.armar(o);
      final a = r.armado;
      expect(a.sectores.where((s) => s.tipo == TipoSector.pasarela), isEmpty);
      final centro = a.hojas.single.caja.centroX;
      final primeraFila = a.mesas.map((m) => m.y).reduce((x, y) => x < y ? x : y);
      final cercanas = a.mesas
          .where((m) => m.y == primeraFila)
          .map((m) => a.aMetros((m.x - centro).abs()))
          .reduce((x, y) => x < y ? x : y);
      expect(cercanas, closeTo(1.0, 1e-9));
      expect(
        r.capacidad,
        greaterThan(ArmarAMedida.capacidad(
          const OpcionesAMedida(playon: _surubi, cantidad: 1),
        )),
      );
      _revisar(r, o, 'sin pasarela');
    });

    test('con pasarela, sus filas dejan libre el medio', () {
      final a = ArmarAMedida.armar(
        const OpcionesAMedida(playon: _surubi, cantidad: 9999),
      ).armado;
      final pasarela =
          a.sectores.singleWhere((s) => s.tipo == TipoSector.pasarela);
      final centro = a.hojas.single.caja.centroX;
      for (final m in a.mesas) {
        if (m.y - a.radio > pasarela.caja.abajo) continue;
        // Media pasarela (1,05) más el despeje (2,5) más media mesa (1).
        expect(a.aMetros((m.x - centro).abs()), greaterThanOrEqualTo(4.55 - 1e-6),
            reason: 'mesa ${m.numero}');
      }
    });
  });

  group('en dos hojas', () {
    const o = OpcionesAMedida(playon: _surubi, cantidad: 132, partirEnFila: 5);
    final r = ArmarAMedida.armar(o);
    final a = r.armado;

    test('las primeras filas van en la A y el resto en la B', () {
      expect(a.hojas.map((h) => h.id), ['A', 'B']);
      final enA = r.mesasPorFila.take(5).fold<int>(0, (s, n) => s + n);
      expect(a.mesasDeHoja('A').length, enA);
      expect(a.mesasDeHoja('B').length, 132 - enA);
      _revisar(r, o, 'dos hojas');
    });

    test('al cambiar de hoja hay corte', () {
      for (final n in a.numeros) {
        if (!a.existe(n + 1)) continue;
        if (a.mesa(n)!.hoja != a.mesa(n + 1)!.hoja) {
          expect(a.cortes, contains(n));
        }
      }
    });

    test('una fila de corte que no existe deja todo en una hoja', () {
      for (final fila in [0, -3, 99]) {
        final uno = ArmarAMedida.armar(
          OpcionesAMedida(playon: _surubi, cantidad: 132, partirEnFila: fila),
        ).armado;
        expect(uno.hojas.length, 1, reason: 'fila $fila');
      }
    });
  });

  group('en cualquier playón', () {
    const playones = [
      _surubi,
      PlayonReal(frenteM: 25, fondoM: 25, profundidadM: 30),
      // Se cierra hacia el fondo.
      PlayonReal(frenteM: 40, fondoM: 28, profundidadM: 35),
      PlayonReal(frenteM: 18, fondoM: 60, profundidadM: 50),
      PlayonReal(frenteM: 12, fondoM: 14, profundidadM: 9),
    ];
    const lugares = [1.8, 2.0, 2.2, 2.5, 3.0];
    const cantidades = [1, 2, 37, 132, 9999];

    for (final p in playones) {
      for (final pasarela in [2.1, 0.0]) {
        test('${p.frenteM} / ${p.fondoM} / ${p.profundidadM}, '
            '${pasarela > 0 ? 'con' : 'sin'} pasarela', () {
          for (final lugar in lugares) {
            for (final cantidad in cantidades) {
              for (final partir in [null, 3]) {
                final o = OpcionesAMedida(
                  playon: p,
                  cantidad: cantidad,
                  lugarM: lugar,
                  pasarelaM: pasarela,
                  partirEnFila: partir,
                );
                _revisar(
                  ArmarAMedida.armar(o),
                  o,
                  'lugar $lugar, $cantidad mesas, partir $partir',
                );
              }
            }
          }
        });
      }
    }
  });

  group('el borde del hormigón, con otro playón', () {
    const o = OpcionesAMedida(playon: _surubi, cantidad: 132);
    final a = ArmarAMedida.armar(o).armado;

    /// Dónde está cada mesa respecto del medio del escenario.
    Map<int, (double, double)> lugares(ArmadoSalon x) {
      final b = x.hojas.first.contorno!.puntos;
      final cx = (b[0].x + b[1].x) / 2;
      return {
        for (final m in x.mesas)
          m.numero: (
            double.parse((m.x - cx).toStringAsFixed(6)),
            double.parse(m.y.toStringAsFixed(6)),
          ),
      };
    }

    test('se sabe a qué distancia y con qué playón se armó', () {
      expect(ArmarAMedida.lugarDe(a), closeTo(2.0, 1e-9));
      final p = ArmarAMedida.playonDe(a)!;
      expect(p.frenteM, closeTo(30, 1e-6));
      expect(p.fondoM, closeTo(46, 1e-6));
      expect(p.profundidadM, closeTo(39, 1e-6));

      final a25 = ArmarAMedida.armar(
        const OpcionesAMedida(playon: _surubi, cantidad: 132, lugarM: 2.5),
      ).armado;
      expect(ArmarAMedida.lugarDe(a25), closeTo(2.5, 1e-9));
    });

    test('en dos hojas, el playón sale de las dos juntas', () {
      final dos = ArmarAMedida.armar(
        const OpcionesAMedida(playon: _surubi, cantidad: 132, partirEnFila: 5),
      ).armado;
      final p = ArmarAMedida.playonDe(dos)!;
      expect(p.frenteM, closeTo(30, 1e-6));
      expect(p.fondoM, closeTo(46, 1e-6));
      expect(p.profundidadM, closeTo(39, 1e-6));
    });

    test('un armado del Canva no tiene nada de esto, y no se toca', () {
      final canva = ArmadosPredefinidos.normal2aPagina3();
      expect(ArmarAMedida.lugarDe(canva), isNull);
      expect(ArmarAMedida.playonDe(canva), isNull);
      expect(
        identical(
          ArmarAMedida.conPlayon(
            canva,
            const PlayonReal(frenteM: 20, fondoM: 20, profundidadM: 20),
          ),
          canva,
        ),
        isTrue,
      );
    });

    test('con el mismo playón no cambia nada', () {
      expect(identical(ArmarAMedida.conPlayon(a, _surubi), a), isTrue);
      // Que esté marcado como aproximado o no, no cambia el dibujo.
      expect(
        identical(
          ArmarAMedida.conPlayon(a, _surubi.copyWith(aproximado: false)),
          a,
        ),
        isTrue,
      );
    });

    test('más grande: el borde crece, las mesas quedan donde estaban', () {
      const grande = PlayonReal(frenteM: 34, fondoM: 52, profundidadM: 45);
      final b = ArmarAMedida.conPlayon(a, grande);
      expect(b.numeros, a.numeros);
      expect(lugares(b), lugares(a));
      expect(b.cortes, a.cortes);
      final p = ArmarAMedida.playonDe(b)!;
      expect(p.frenteM, closeTo(34, 1e-6));
      expect(p.fondoM, closeTo(52, 1e-6));
      expect(p.profundidadM, closeTo(45, 1e-6));
      expect(b.problemas(), isEmpty);
      expect(MedirSalon.fueraDelHormigon(b, (_) => 2.0), isEmpty);
      // El escenario toma el frente nuevo.
      final escenario =
          b.sectores.firstWhere((s) => s.tipo == TipoSector.escenario);
      expect(b.aMetros(escenario.caja.ancho), closeTo(34, 1e-6));
      // Y la distancia entre mesas es la de antes.
      expect(ArmarAMedida.lugarDe(b), closeTo(2.0, 1e-9));
    });

    test('más chico: las mesas no se mueven, y las que quedan afuera avisan',
        () {
      const chico = PlayonReal(frenteM: 24, fondoM: 30, profundidadM: 20);
      final b = ArmarAMedida.conPlayon(a, chico);
      expect(b.numeros, a.numeros);
      expect(lugares(b), lugares(a));
      final afuera = MedirSalon.fueraDelHormigon(b, (_) => 2.0);
      expect(afuera, isNotEmpty);
      // Ninguna se sale del dibujo: el aviso es por el hormigón, no por la
      // hoja.
      expect(
        b.problemas().where((p) => p.contains('se sale de la hoja')),
        isEmpty,
      );
      expect(
        b.problemas().where((p) => p.contains('fuera del hormigón')),
        isNotEmpty,
      );
    });

    test('ida y vuelta: con el playón de antes vuelve a no haber avisos', () {
      const chico = PlayonReal(frenteM: 24, fondoM: 30, profundidadM: 20);
      final vuelta =
          ArmarAMedida.conPlayon(ArmarAMedida.conPlayon(a, chico), _surubi);
      expect(lugares(vuelta), lugares(a));
      expect(vuelta.problemas(), isEmpty);
      expect(MedirSalon.fueraDelHormigon(vuelta, (_) => 2.0), isEmpty);
    });

    test('en dos hojas, el corte entre hojas no se mueve', () {
      final dos = ArmarAMedida.armar(
        const OpcionesAMedida(playon: _surubi, cantidad: 132, partirEnFila: 5),
      ).armado;
      const grande = PlayonReal(frenteM: 34, fondoM: 52, profundidadM: 45);
      final b = ArmarAMedida.conPlayon(dos, grande);
      expect(b.hojas.map((h) => h.id), ['A', 'B']);
      expect(lugares(b), lugares(dos));
      expect(b.problemas(), isEmpty);
      double largoA(ArmadoSalon x) {
        final c = x.hojas.first.contorno!.puntos;
        return x.aMetros(c[3].y - c[0].y);
      }

      expect(largoA(b), closeTo(largoA(dos), 1e-6));
      final p = ArmarAMedida.playonDe(b)!;
      expect(p.profundidadM, closeTo(45, 1e-6));
    });

    test('en dos hojas, un playón más corto que el corte no rompe', () {
      final dos = ArmarAMedida.armar(
        const OpcionesAMedida(playon: _surubi, cantidad: 132, partirEnFila: 5),
      ).armado;
      const corto = PlayonReal(frenteM: 30, fondoM: 34, profundidadM: 6);
      final b = ArmarAMedida.conPlayon(dos, corto);
      expect(b.numeros, dos.numeros);
      // Todas las de la hoja B quedaron sin hormigón.
      final afuera = MedirSalon.fueraDelHormigon(b, (_) => 2.0).toSet();
      expect(afuera, containsAll([for (final m in b.mesasDeHoja('B')) m.numero]));
      final json = jsonEncode(b.toJson());
      final leido =
          ArmadoSalon.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(jsonEncode(leido.toJson()), json);
    });
  });
}
