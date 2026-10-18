import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/medir_salon.dart';

/// Las cuentas del salón primero (6.1.0, etapa 1 de
/// `docs/PLAN_SALON_PRIMERO_2026-10-16.md`): el salón vacío, estirar los
/// sectores y el playón con sus manijas, el escenario desatado y acomodar las
/// mesas dentro del borde real sin pisar ningún sector. Sin pantalla.
void main() {
  const surubi = PlayonReal.costaSurubi;

  /// Lo que tiene que cumplir cualquier salón acomodado.
  void revisar(ArmadoAMedida r, String caso, {double lugar = 2.0}) {
    final a = r.armado;
    expect(a.numeros, List.generate(a.mesas.length, (i) => i + 1),
        reason: caso);
    expect(r.puestas, math.min(r.pedidas, r.capacidad), reason: caso);
    expect(r.faltan, r.pedidas - r.puestas, reason: caso);
    expect(a.problemas(), isEmpty, reason: caso);
    expect(MedirSalon.fueraDelHormigon(a, (_) => lugar), isEmpty,
        reason: caso);
    expect(MedirSalon.apretadas(a, (_) => lugar), isEmpty, reason: caso);
    for (final n in a.numeros) {
      if (!a.existe(n + 1) || a.cortes.contains(n)) continue;
      expect(a.pegadas(n, n + 1), isTrue, reason: '$caso, $n-${n + 1}');
    }
  }

  /// Ninguna mesa pisa un sector que no es la pasarela (con su despeje).
  void sinPisar(ArmadoSalon a, String caso) {
    for (final s in a.sectores) {
      if (s.tipo == TipoSector.pasarela) continue;
      final despeje = a.aUnidades(s.tipo == TipoSector.escenario
          ? 0.5
          : ArmarAMedida.despejeSectorM);
      for (final m in a.mesas) {
        final dx = math.max(math.max(s.caja.x - m.x, 0.0), m.x - s.caja.derecha);
        final dy = math.max(math.max(s.caja.y - m.y, 0.0), m.y - s.caja.abajo);
        expect(math.sqrt(dx * dx + dy * dy),
            greaterThanOrEqualTo(a.radio + despeje - 1e-6),
            reason: '$caso: la mesa ${m.numero} pisa ${s.texto}');
      }
    }
  }

  SectorPlano sector(ArmadoSalon a, TipoSector t) =>
      a.sectores.firstWhere((s) => s.tipo == t);

  /// El salón vacío con un sector más, de [anchoM] × [altoM] metros, con su
  /// esquina de arriba a la izquierda a ([xM], [yM]) metros de la del borde.
  ArmadoSalon conSector(
    ArmadoSalon a,
    TipoSector tipo,
    String texto, {
    required double xM,
    required double yM,
    required double anchoM,
    required double altoM,
  }) {
    final b = a.hojas.first.contorno!.puntos;
    final x0 = b.map((p) => p.x).reduce(math.min);
    final y0 = b.map((p) => p.y).reduce(math.min);
    return a.copyWith(sectores: [
      ...a.sectores,
      SectorPlano(
        tipo: tipo,
        texto: texto,
        hoja: 'A',
        caja: RectPlano(
          x0 + a.aUnidades(xM),
          y0 + a.aUnidades(yM),
          a.aUnidades(anchoM),
          a.aUnidades(altoM),
        ),
      ),
    ]);
  }

  group('el salón vacío', () {
    final v = ArmarAMedida.vacio(surubi);
    final medida = ArmarAMedida.armar(
      const OpcionesAMedida(playon: surubi, cantidad: 132),
    ).armado;

    test('el playón, el escenario al frente y el Ingreso al fondo, sin mesas',
        () {
      expect(v.clave, ArmarAMedida.claveVacio);
      expect(v.mesas, isEmpty);
      expect(v.hojas.map((h) => h.id), ['A']);
      expect(v.hojas.first.contorno!.puntos,
          medida.hojas.first.contorno!.puntos);
      expect(sector(v, TipoSector.escenario).caja,
          sector(medida, TipoSector.escenario).caja);
      final ingreso = sector(v, TipoSector.ingreso).caja;
      final borde = v.hojas.first.contorno!.puntos;
      expect(v.aMetros(ingreso.ancho), closeTo(4, 1e-9));
      expect(v.aMetros(ingreso.alto), closeTo(2, 1e-9));
      // Al medio y a medio metro del fondo.
      expect(ingreso.centroX, closeTo((borde[2].x + borde[3].x) / 2, 1e-6));
      expect(v.aMetros(borde[2].y - ingreso.abajo), closeTo(0.5, 1e-6));
      expect(v.problemas(), isEmpty);
    });

    test('se sabe de qué playón salió y a qué distancia van las mesas', () {
      final p = ArmarAMedida.playonDe(v)!;
      expect(p.frenteM, closeTo(surubi.frenteM, 1e-6));
      expect(p.fondoM, closeTo(surubi.fondoM, 1e-6));
      expect(p.profundidadM, closeTo(surubi.profundidadM, 1e-6));
      expect(ArmarAMedida.lugarDe(v), 2.0);
    });

    test('ida y vuelta por JSON, igual', () {
      final json = jsonEncode(v.toJson());
      final vuelta =
          ArmadoSalon.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(jsonEncode(vuelta.toJson()), json);
    });

    test('volver al armado original: el salón vacío como salió', () {
      final armado = ArmarAMedida.acomodar(
        conSector(v, TipoSector.pista, 'Pista',
            xM: 10, yM: 15, anchoM: 8, altoM: 8),
        cantidad: 60,
      ).armado;
      final original = EditarArmado.original(armado)!;
      expect(original.mesas, isEmpty);
      expect(original.sectores.map((s) => s.tipo),
          [TipoSector.escenario, TipoSector.ingreso]);
      final p = original.hojas.first.contorno!.puntos;
      final q = v.hojas.first.contorno!.puntos;
      for (var k = 0; k < 4; k++) {
        expect(p[k].x, closeTo(q[k].x, 1e-6));
        expect(p[k].y, closeTo(q[k].y, 1e-6));
      }
    });
  });

  group('acomodar da lo mismo que armar sobre el mismo playón', () {
    for (final o in const [
      OpcionesAMedida(playon: surubi, cantidad: 132),
      // Con una y dos de menos: a la última fila le sobra un número impar en
      // alguno de los dos, y se ve de qué lado se empieza a recortar.
      OpcionesAMedida(playon: surubi, cantidad: 131),
      OpcionesAMedida(playon: surubi, cantidad: 130),
      OpcionesAMedida(playon: surubi, cantidad: 132, pasarelaM: 0),
      OpcionesAMedida(playon: surubi, cantidad: 100, lugarM: 2.5),
      OpcionesAMedida(playon: surubi, cantidad: 500),
      OpcionesAMedida(
        playon: PlayonReal(frenteM: 30, fondoM: 30, profundidadM: 30),
        cantidad: 80,
      ),
      OpcionesAMedida(
        playon: PlayonReal(frenteM: 40, fondoM: 28, profundidadM: 35),
        cantidad: 120,
        pasarelaM: 0,
      ),
    ]) {
      final caso = '${o.playon.frenteM}/${o.playon.fondoM}/'
          '${o.playon.profundidadM}, ${o.cantidad} a ${o.lugarM} m, '
          'pasarela ${o.pasarelaM}';
      test(caso, () {
        final r = ArmarAMedida.armar(o);
        final base = r.armado.copyWith(mesas: const []);
        final ac = ArmarAMedida.acomodar(base,
            cantidad: o.cantidad, lugarM: o.lugarM);
        expect(ac.capacidad, r.capacidad);
        expect(ac.puestas, r.puestas);
        expect(ac.mesasPorFila, r.mesasPorFila);
        // Mesa por mesa: el número, la hoja y dónde.
        for (final m in r.armado.mesas) {
          final n = ac.armado.mesa(m.numero)!;
          expect(n.hoja, m.hoja, reason: 'mesa ${m.numero}');
          expect(n.x, closeTo(m.x, 1e-6), reason: 'mesa ${m.numero}');
          expect(n.y, closeTo(m.y, 1e-6), reason: 'mesa ${m.numero}');
        }
      });
    }
  });

  group('acomodar esquiva los sectores', () {
    final v = ArmarAMedida.vacio(surubi);
    final libre = ArmarAMedida.acomodar(v, cantidad: 400);

    test('el salón vacío: entran 132 y ninguna pisa el Ingreso', () {
      final r = ArmarAMedida.acomodar(v, cantidad: 132);
      expect(r.puestas, 132);
      revisar(r, 'vacío');
      sinPisar(r.armado, 'vacío');
    });

    for (final (nombre, xM, yM) in [
      ('al medio', 11.0, 15.0),
      ('a la izquierda', 0.0, 12.0),
      ('pegada al escenario', 11.0, 0.0),
    ]) {
      test('una pista de 8 × 8 m $nombre', () {
        final a = conSector(v, TipoSector.pista, 'Pista',
            xM: xM, yM: yM, anchoM: 8, altoM: 8);
        final r = ArmarAMedida.acomodar(a, cantidad: 400);
        expect(r.capacidad, lessThan(libre.capacidad));
        revisar(r, 'pista $nombre');
        sinPisar(r.armado, 'pista $nombre');
      });
    }

    test('una barra y la pista a la vez', () {
      final a = conSector(
        conSector(v, TipoSector.pista, 'Pista',
            xM: 11, yM: 15, anchoM: 8, altoM: 8),
        TipoSector.barra,
        'Barra',
        xM: 1,
        yM: 25,
        anchoM: 2,
        altoM: 8,
      );
      final r = ArmarAMedida.acomodar(a, cantidad: 110);
      revisar(r, 'barra y pista');
      sinPisar(r.armado, 'barra y pista');
    });

    test('si no entran, dice cuántas faltan', () {
      final a = conSector(v, TipoSector.pista, 'Pista',
          xM: 5, yM: 5, anchoM: 20, altoM: 25);
      final r = ArmarAMedida.acomodar(a, cantidad: 300);
      expect(r.capacidad, lessThan(300));
      expect(r.puestas, r.capacidad);
      expect(r.faltan, 300 - r.capacidad);
      revisar(r, 'no entran');
      sinPisar(r.armado, 'no entran');
    });
  });

  group('acomodar sobre un playón movido a mano', () {
    final v = ArmarAMedida.vacio(surubi);

    test('un rectángulo', () {
      final rect = EditarArmado.estirarPlayon(v, 'A', Manija.o, -8, 0);
      final r = ArmarAMedida.acomodar(
        EditarArmado.estirarPlayon(rect, 'A', Manija.e, 8, 0),
        cantidad: 400,
      );
      revisar(r, 'rectángulo');
      sinPisar(r.armado, 'rectángulo');
    });

    test('torcido: un costado corrido, más mesas de ese lado', () {
      final a = EditarArmado.estirarPlayon(v, 'A', Manija.se, 6, 0);
      final r = ArmarAMedida.acomodar(a, cantidad: 400);
      revisar(r, 'torcido');
      final cx = sector(a, TipoSector.escenario).caja.centroX;
      final der = r.armado.mesas.where((m) => m.x > cx).length;
      final izq = r.armado.mesas.where((m) => m.x < cx).length;
      expect(der, greaterThan(izq));
    });

    test('el escenario corrido a un costado: hay filas de los dos lados', () {
      final i = v.sectores.indexWhere((s) => s.tipo == TipoSector.escenario);
      final a = EditarArmado.moverSector(
        v,
        i,
        v.sectores[i].caja.x,
        v.sectores[i].caja.y + v.aUnidades(20),
      );
      final r = ArmarAMedida.acomodar(a, cantidad: 400);
      revisar(r, 'escenario al medio');
      sinPisar(r.armado, 'escenario al medio');
      final esc = sector(a, TipoSector.escenario).caja;
      expect(r.armado.mesas.any((m) => m.y < esc.y), isTrue);
      expect(r.armado.mesas.any((m) => m.y > esc.abajo), isTrue);
    });
  });

  group('estirar un sector con sus manijas', () {
    final v = conSector(ArmarAMedida.vacio(surubi), TipoSector.pista, 'Pista',
        xM: 10, yM: 10, anchoM: 6, altoM: 4);
    final i = v.sectores.length - 1;
    final c = v.sectores[i].caja;
    double m(double u) => v.aMetros(u);

    test('el lado de la derecha: solo ese lado, de a medio metro', () {
      final n = EditarArmado.estirarSector(v, i, Manija.e, 1.3, 9).sectores[i];
      expect(n.caja.x, c.x);
      expect(n.caja.y, c.y);
      expect(m(n.caja.ancho), closeTo(7.5, 1e-9));
      expect(m(n.caja.alto), closeTo(4, 1e-9));
    });

    test('el de la izquierda corre la x y agranda', () {
      final n = EditarArmado.estirarSector(v, i, Manija.o, -2, 0).sectores[i];
      expect(m(c.x - n.caja.x), closeTo(2, 1e-9));
      expect(n.caja.derecha, closeTo(c.derecha, 1e-9));
      expect(m(n.caja.ancho), closeTo(8, 1e-9));
    });

    test('una esquina mueve sus dos lados', () {
      final n = EditarArmado.estirarSector(v, i, Manija.se, 1, 1.5).sectores[i];
      expect(n.caja.x, c.x);
      expect(n.caja.y, c.y);
      expect(m(n.caja.ancho), closeTo(7, 1e-9));
      expect(m(n.caja.alto), closeTo(5.5, 1e-9));
    });

    test('nunca menos de medio metro, aunque se pase del otro lado', () {
      final n = EditarArmado.estirarSector(v, i, Manija.e, -20, 0).sectores[i];
      expect(n.caja.x, c.x);
      expect(m(n.caja.ancho), closeTo(0.5, 1e-9));
      final arriba =
          EditarArmado.estirarSector(v, i, Manija.n, 0, 30).sectores[i];
      expect(arriba.caja.abajo, closeTo(c.abajo, 1e-9));
      expect(m(arriba.caja.alto), closeTo(0.5, 1e-9));
    });

    test('se cuenta desde donde estaba al empezar a arrastrar', () {
      final paso1 = EditarArmado.estirarSector(v, i, Manija.e, 1, 0);
      final paso2 = EditarArmado.estirarSector(paso1, i, Manija.e, 2, 0,
          desde: c);
      expect(m(paso2.sectores[i].caja.ancho), closeTo(8, 1e-9));
    });
  });

  group('el playón con sus manijas', () {
    final v = ArmarAMedida.vacio(surubi);
    final b = v.hojas.first.contorno!.puntos;
    double m(double u) => v.aMetros(u);

    test('moverlo entero: el hormigón se corre, lo de arriba no', () {
      final n = EditarArmado.moverPlayon(v, 'A', 3.2, -1);
      final p = n.hojas.first.contorno!.puntos;
      for (var k = 0; k < 4; k++) {
        expect(m(p[k].x - b[k].x), closeTo(3, 1e-9));
        expect(m(p[k].y - b[k].y), closeTo(-1, 1e-9));
      }
      expect(n.sectores.map((s) => s.caja), v.sectores.map((s) => s.caja));
    });

    test('sin tope: la hoja crece para que entre', () {
      final n = EditarArmado.moverPlayon(v, 'A', 80, 60);
      final caja = n.hojas.first.caja;
      for (final p in n.hojas.first.contorno!.puntos) {
        expect(p.x, lessThanOrEqualTo(caja.derecha));
        expect(p.y, lessThanOrEqualTo(caja.abajo));
      }
    });

    test('el fondo, más profundo', () {
      final n = EditarArmado.estirarPlayon(v, 'A', Manija.s, 0, 5);
      expect(ArmarAMedida.playonDe(n)!.profundidadM, closeTo(44, 1e-6));
      expect(ArmarAMedida.playonDe(n)!.frenteM, closeTo(30, 1e-6));
    });

    test('un costado, más ancho', () {
      final n = EditarArmado.estirarPlayon(v, 'A', Manija.e, 4, 0);
      final p = ArmarAMedida.playonDe(n)!;
      expect(p.frenteM, closeTo(34, 1e-6));
      expect(p.fondoM, closeTo(50, 1e-6));
    });

    test('una esquina mueve solo ese punto', () {
      final n = EditarArmado.estirarPlayon(v, 'A', Manija.ne, 2, -1);
      final p = n.hojas.first.contorno!.puntos;
      expect(m(p[1].x - b[1].x), closeTo(2, 1e-9));
      expect(m(p[1].y - b[1].y), closeTo(-1, 1e-9));
      expect(p[0], b[0]);
      expect(p[2], b[2]);
      expect(p[3], b[3]);
    });

    test('ningún lado queda de menos de medio metro', () {
      final n = EditarArmado.estirarPlayon(v, 'A', Manija.e, -60, 0);
      final p = n.hojas.first.contorno!.puntos;
      expect(m(p[1].x - p[0].x), closeTo(0.5, 1e-9));
      expect(m(p[2].x - p[3].x), greaterThanOrEqualTo(0.5 - 1e-9));
      final s = EditarArmado.estirarPlayon(v, 'A', Manija.s, 0, -60);
      final q = s.hojas.first.contorno!.puntos;
      expect(m(q[3].y - q[0].y), closeTo(0.5, 1e-9));
    });
  });

  group('el escenario ya no se ata al frente del playón', () {
    test('cambiar el playón en Medidas no le cambia el tamaño', () {
      final v = ArmarAMedida.vacio(surubi);
      const otro = PlayonReal(frenteM: 40, fondoM: 50, profundidadM: 42);
      final n = ArmarAMedida.conPlayon(v, otro);
      expect(ArmarAMedida.playonDe(n)!.frenteM, closeTo(40, 1e-6));
      final antes = sector(v, TipoSector.escenario).caja;
      final despues = sector(n, TipoSector.escenario).caja;
      expect(despues.ancho, closeTo(antes.ancho, 1e-9));
      expect(despues.alto, closeTo(antes.alto, 1e-9));
    });
  });
}
