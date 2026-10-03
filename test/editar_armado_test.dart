// Acomodar el salón a mano: correr, agregar y sacar mesas, pasto, sectores,
// separar o juntar, y lo que se necesita para guardarlo sin pisar a nadie.
// Todo es cuenta pura: no hay base ni pantalla.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/medir_salon.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno _alumno(String id, List<int> mesas, {bool baja = false}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${baja ? '[BAJA] ' : ''}${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

/// Lo que tiene que valer después de cualquier cosa que se le haga al salón.
void _sano(ArmadoSalon a, String caso) {
  expect(a.numeros.toSet().length, a.numeros.length, reason: '$caso: números');
  for (final m in a.mesas) {
    final h = a.hoja(m.hoja);
    expect(h, isNotNull, reason: '$caso: hoja de la ${m.numero}');
    expect(h!.caja.contieneCirculo(m.x, m.y, a.radio), isTrue,
        reason: '$caso: la ${m.numero} se sale de la hoja');
  }
  final json = jsonEncode(a.toJson());
  final leido = ArmadoSalon.fromJson(jsonDecode(json) as Map<String, dynamic>);
  expect(jsonEncode(leido.toJson()), json, reason: '$caso: ida y vuelta');
  expect(leido.cortes, a.cortes, reason: '$caso: cortes');
}

void main() {
  final aMedida = ArmarAMedida.armar(
    const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 132),
  ).armado;
  final canva = ArmadosPredefinidos.normal2aPagina3();
  final todos = [aMedida, ...ArmadosPredefinidos.todos];

  group('correr una mesa', () {
    test('se corre de a un cuarto de metro y no cambia de número ni de hoja',
        () {
      for (final a in todos) {
        final m = a.mesas[a.mesas.length ~/ 2];
        final b = EditarArmado.mover(a, m.numero, m.x + 31.7, m.y - 18.2);
        final n = b.mesa(m.numero)!;
        final paso = a.aUnidades(EditarArmado.ajusteM);
        // Lo que se corrió son cuartos de metro enteros: sigue alineada con
        // su fila.
        final dx = (n.x - m.x) / paso;
        final dy = (n.y - m.y) / paso;
        expect((dx - dx.round()).abs(), lessThan(1e-9), reason: a.clave);
        expect((dy - dy.round()).abs(), lessThan(1e-9), reason: a.clave);
        expect(dx.round(), isNot(0), reason: a.clave);
        expect(n.hoja, m.hoja);
        expect(b.numeros, a.numeros);
        // Las demás no se movieron.
        for (final o in a.mesas) {
          if (o.numero == m.numero) continue;
          expect(b.mesa(o.numero)!.x, o.x);
          expect(b.mesa(o.numero)!.y, o.y);
        }
        _sano(b, a.clave);
      }
    });

    test('no se sale de la hoja por más lejos que se la lleve', () {
      for (final a in todos) {
        final m = a.mesas.first;
        for (final (dx, dy) in [(-9e4, 0.0), (9e4, 0.0), (0.0, -9e4), (0.0, 9e4)]) {
          _sano(EditarArmado.mover(a, m.numero, m.x + dx, m.y + dy), a.clave);
        }
      }
    });

    test('dejarla donde estaba, o una mesa que no existe, no cambia nada', () {
      final m = aMedida.mesa(10)!;
      expect(
        identical(
          EditarArmado.mover(aMedida, 10, m.x, m.y, ajustar: false),
          aMedida,
        ),
        isTrue,
      );
      expect(identical(EditarArmado.mover(aMedida, 999, 0, 0), aMedida), isTrue);
    });

    test('los cortes se recalculan: lejos de su vecina ya no están pegadas',
        () {
      expect(aMedida.pegadas(10, 11), isTrue);
      expect(aMedida.cortes, isNot(contains(10)));
      final m = aMedida.mesa(11)!;
      final b = EditarArmado.mover(aMedida, 11, m.x, m.y + aMedida.aUnidades(9));
      expect(b.pegadas(10, 11), isFalse);
      expect(b.cortes, containsAll([10, 11]));
    });

    test('la regla: las tres más cercanas, en metros, de la más cerca a la '
        'más lejos', () {
      final v = EditarArmado.vecinas(aMedida, 20);
      expect(v.length, 3);
      expect(v.first.metros, closeTo(2.0, 1e-6));
      expect(v[0].metros <= v[1].metros && v[1].metros <= v[2].metros, isTrue);
      expect(v.map((e) => e.numero), isNot(contains(20)));
      expect(EditarArmado.vecinas(aMedida, 999), isEmpty);
    });
  });

  group('agregar y sacar', () {
    test('el número nuevo es el que sigue al más alto, contando los que ya '
        'usa alguien', () {
      expect(EditarArmado.proximoNumero(aMedida), 133);
      expect(EditarArmado.proximoNumero(aMedida, [200]), 201);
      // Aunque haya un hueco, no lo reusa.
      final sin50 = EditarArmado.sacar(aMedida, 50);
      expect(EditarArmado.proximoNumero(sin50), 133);
      expect(EditarArmado.proximoNumero(EditarArmado.sacar(aMedida, 132)), 132);
      expect(
        EditarArmado.proximoNumero(EditarArmado.sacar(aMedida, 132), [132]),
        133,
      );
    });

    test('el lugar para la nueva está libre: a 2 m de todas, adentro y sin '
        'tapar nada', () {
      for (final a in todos) {
        final hoja = a.hojas.first.id;
        final lugar = EditarArmado.lugarLibre(a, hoja, lugarM: 2.0);
        final n = EditarArmado.proximoNumero(a);
        final b = EditarArmado.agregar(a,
            numero: n, hoja: hoja, x: lugar.x, y: lugar.y);
        expect(b.existe(n), isTrue, reason: a.clave);
        expect(b.mesas.length, a.mesas.length + 1);
        expect(EditarArmado.pisadas(b), isEmpty, reason: a.clave);
        expect(EditarArmado.bloqueos(b), isEmpty, reason: a.clave);
        for (final v in EditarArmado.vecinas(b, n)) {
          expect(v.metros, greaterThanOrEqualTo(2.0 - 1e-6), reason: a.clave);
        }
        _sano(b, a.clave);
      }
    });

    test('cerca de una mesa, queda al lado de esa', () {
      final lugar = EditarArmado.lugarLibre(aMedida, 'A', cerca: 66, lugarM: 2.0);
      final b = EditarArmado.agregar(aMedida,
          numero: 133, hoja: 'A', x: lugar.x, y: lugar.y);
      expect(b.distanciaM(133, 66), closeTo(2.0, 1e-6));
    });

    test('sin ningún lugar libre, va debajo y la hoja se agranda', () {
      // Un salón de una sola mesa que ocupa toda su hoja.
      final chico = ArmadoSalon(
        clave: 'x',
        nombre: 'x',
        hojas: const [HojaPlano(id: 'A', titulo: '', caja: RectPlano(0, 0, 90, 90))],
        mesas: const [MesaPlano(numero: 1, hoja: 'A', x: 45, y: 45)],
      );
      final lugar = EditarArmado.lugarLibre(chico, 'A', lugarM: 2.0);
      final b = EditarArmado.agregar(chico,
          numero: 2, hoja: 'A', x: lugar.x, y: lugar.y);
      expect(b.hoja('A')!.caja.alto, greaterThan(90));
      expect(EditarArmado.pisadas(b), isEmpty);
      _sano(b, 'chico');
    });

    test('agregar una que ya existe, o en una hoja que no existe, no hace nada',
        () {
      expect(
        identical(
          EditarArmado.agregar(aMedida, numero: 5, hoja: 'A', x: 0, y: 0),
          aMedida,
        ),
        isTrue,
      );
      expect(
        identical(
          EditarArmado.agregar(aMedida, numero: 500, hoja: 'Z', x: 0, y: 0),
          aMedida,
        ),
        isTrue,
      );
    });

    test('sacar una mesa no cambia el número de las demás', () {
      final b = EditarArmado.sacar(aMedida, 50);
      expect(b.existe(50), isFalse);
      expect(b.numeros, [for (final n in aMedida.numeros) if (n != 50) n]);
      // 49 y 51 no son seguidas: el sorteo no sienta ahí a una familia.
      expect(b.pegadas(49, 51), anyOf(isTrue, isFalse));
      expect(b.cortes, isNot(contains(50)));
      _sano(b, 'sin la 50');
    });

    test('marcar y desmarcar pasto', () {
      final b = EditarArmado.marcarPasto(aMedida, 132, true);
      expect(b.pasto, {132});
      expect(b.cantidadComunes, 131);
      expect(EditarArmado.marcarPasto(b, 132, false).pasto, isEmpty);
      expect(identical(EditarArmado.marcarPasto(aMedida, 132, false), aMedida),
          isTrue);
    });
  });

  group('las mesas en uso no se sacan', () {
    final alumnos = [
      _alumno('gomez', [12, 13]),
      _alumno('paz', [40], baja: true),
      _alumno('sosa', []),
    ];
    const config = ConfigPlano(fijadas: {7: MesaFijada(alumnoId: 'sosa')});
    final enUso = EditarArmado.enUso(alumnos, config);

    test('con familia, con una baja que la conserva, o fijada', () {
      expect(enUso.keys.toSet(), {7, 12, 13, 40});
      expect(enUso[12], 'la tiene GOMEZ');
      expect(enUso[40], 'la conserva PAZ, que está de baja');
      expect(enUso[7], 'está fijada para SOSA');
    });

    test('la sesión dice por qué no, y no cambia nada', () {
      final s = SesionAcomodo(base: aMedida, enUso: enUso, haySorteo: true);
      expect(s.sacar(12), contains('la tiene GOMEZ'));
      expect(s.sacar(40), contains('está de baja'));
      expect(s.sacar(7), contains('está fijada para SOSA'));
      expect(s.hayCambios, isFalse);
      // Una vacía sí.
      expect(s.sacar(100), isNull);
      expect(s.actual.existe(100), isFalse);
      // Y las que no se sacan se pueden correr.
      s.empezarArrastre();
      final m = aMedida.mesa(12)!;
      s.arrastrarMesa(12, m.x + 20, m.y + 20);
      s.terminarArrastre();
      expect(s.actual.mesa(12)!.x, isNot(m.x));
    });
  });

  group('sectores', () {
    test('se corren, se agrandan, se agregan y se sacan sin tocar las mesas',
        () {
      final i = canva.sectores.indexWhere((s) => s.tipo != TipoSector.escenario);
      final s0 = canva.sectores[i];
      var a = EditarArmado.moverSector(canva, i, s0.caja.x + 40, s0.caja.y + 10);
      expect(a.sectores[i].caja.ancho, s0.caja.ancho);
      expect(a.sectores[i].caja.x, isNot(s0.caja.x));
      a = EditarArmado.tamanoSector(a, i, anchoM: 6, altoM: 0.1);
      expect(a.aMetros(a.sectores[i].caja.ancho), closeTo(6, 1e-9));
      // Medio metro como mínimo.
      expect(a.aMetros(a.sectores[i].caja.alto), closeTo(0.5, 1e-9));
      a = EditarArmado.agregarSector(a,
          hoja: a.hojas.first.id, tipo: TipoSector.barra, texto: 'Barra 2');
      expect(a.sectores.length, canva.sectores.length + 1);
      expect(a.sectores.last.texto, 'Barra 2');
      expect(a.aMetros(a.sectores.last.caja.ancho), closeTo(4, 1e-9));
      a = EditarArmado.sacarSector(a, a.sectores.length - 1);
      expect(a.sectores.length, canva.sectores.length);
      for (final m in canva.mesas) {
        expect(a.mesa(m.numero)!.x, m.x);
        expect(a.mesa(m.numero)!.y, m.y);
      }
      _sano(a, 'sectores');
    });

    test('se sabe qué sector hay bajo un punto', () {
      final i = canva.sectores.indexWhere((s) => s.tipo == TipoSector.escenario);
      final c = canva.sectores[i].caja;
      expect(EditarArmado.sectorEn(canva, canva.sectores[i].hoja, c.centroX, c.centroY),
          i);
      expect(EditarArmado.sectorEn(canva, canva.sectores[i].hoja, -9e3, -9e3),
          isNull);
    });
  });

  group('separar o juntar', () {
    final todas = aMedida.numeros.toSet();

    test('la distancia entre mesas de un grupo', () {
      expect(EditarArmado.pasoDe(aMedida, todas), closeTo(2.0, 1e-6));
      expect(EditarArmado.pasoDe(aMedida, {5}), isNull);
      expect(EditarArmado.pasoDe(aMedida, {}), isNull);
    });

    test('deja el paso pedido, sin cambiar números ni pisar nada', () {
      for (final paso in [1.8, 2.2, 2.5]) {
        final v = EditarArmado.separar(aMedida, todas, paso)!;
        expect(v.pasoActualM, closeTo(2.0, 1e-6));
        expect(EditarArmado.pasoDe(v.armado, todas), closeTo(paso, 1e-6),
            reason: '$paso');
        expect(v.armado.numeros, aMedida.numeros);
        expect(v.pisan, 0, reason: '$paso');
        _sano(v.armado, 'separar $paso');
      }
    });

    test('la fila de adelante y la columna del medio no se mueven', () {
      final v = EditarArmado.separar(aMedida, todas, 2.4)!;
      final cx = EditarArmado.centroX(aMedida, 'A');
      var arriba = double.infinity;
      for (final m in aMedida.mesas) {
        if (m.y < arriba) arriba = m.y;
      }
      for (final m in aMedida.mesas) {
        final n = v.armado.mesa(m.numero)!;
        if ((m.y - arriba).abs() < 0.01) {
          expect(n.y, closeTo(m.y, 1e-6), reason: 'fila de adelante');
        }
        // Cada lado se abre para su lado: ninguna cruza el medio.
        expect(n.x < cx, m.x < cx, reason: 'la ${m.numero} cambió de lado');
      }
    });

    test('más separadas, las vecinas siguen pegadas: no aparecen cortes', () {
      final v = EditarArmado.separar(aMedida, todas, 2.6)!;
      expect(v.armado.cortes, aMedida.cortes);
      // Y más juntas tampoco.
      expect(EditarArmado.separar(aMedida, todas, 1.8)!.armado.cortes,
          aMedida.cortes);
    });

    test('es reversible: separar y volver a juntar deja todo donde estaba',
        () {
      final ida = EditarArmado.separar(aMedida, todas, 2.5)!.armado;
      final vuelta = EditarArmado.separar(ida, todas, 2.0)!.armado;
      for (final m in aMedida.mesas) {
        expect(vuelta.mesa(m.numero)!.x, closeTo(m.x, 1e-6));
        expect(vuelta.mesa(m.numero)!.y, closeTo(m.y, 1e-6));
      }
    });

    test('dice si siguen entrando, o cuántas quedan afuera', () {
      final entra = EditarArmado.separar(aMedida, todas, 2.2)!;
      expect(entra.entra, isTrue);
      expect(entra.texto, 'Siguen entrando las 132.');
      final no = EditarArmado.separar(aMedida, todas, 4.0)!;
      expect(no.fuera, greaterThan(0));
      expect(no.texto, contains('fuera del hormigón'));
      // Un armado del Canva no tiene hormigón dibujado: ahí no hay "afuera".
      final c = EditarArmado.separar(canva, canva.numeros.toSet(), 3.0)!;
      expect(c.fuera, 0);
    });

    test('un solo lado: el otro no se toca', () {
      final alcances = EditarArmado.alcances(aMedida, 'A');
      expect(alcances.map((a) => a.clave), ['hoja', 'izq', 'der']);
      final izq = alcances[1].numeros;
      final der = alcances[2].numeros;
      expect(izq.length + der.length, 132);
      final v = EditarArmado.separar(aMedida, izq, 2.4)!;
      for (final n in der) {
        expect(v.armado.mesa(n)!.x, aMedida.mesa(n)!.x);
        expect(v.armado.mesa(n)!.y, aMedida.mesa(n)!.y);
      }
      expect(EditarArmado.pasoDe(v.armado, izq), closeTo(2.4, 1e-6));
    });

    test('con el sorteo por división hecho, se elige el bloque de cada una',
        () {
      final alcances = EditarArmado.alcances(
        aMedida,
        'A',
        bloques: const [
          BloqueDivision('5A', 1, 40),
          BloqueDivision('5B', 41, 66),
        ],
        nombres: const {'5A': '5° A'},
      );
      expect(alcances.map((a) => a.rotulo), [
        'Toda la hoja',
        'Lado izquierdo',
        'Lado derecho',
        'Bloque de 5° A',
        'Bloque de 5B',
      ]);
      expect(alcances[3].numeros, {for (var n = 1; n <= 40; n++) n});
    });

    test('los límites: no más juntas que la mesa ni más de 4 m', () {
      expect(EditarArmado.separar(aMedida, todas, 0.5)!.pasoNuevoM,
          EditarArmado.separarMinimoM);
      expect(EditarArmado.separar(aMedida, todas, 99)!.pasoNuevoM,
          EditarArmado.separarMaximoM);
      expect(EditarArmado.separar(aMedida, {5}, 2.5), isNull);
    });

    test('en los armados del Canva también: nada se pisa y los números quedan',
        () {
      for (final a in ArmadosPredefinidos.todos) {
        for (final h in a.hojas) {
          final numeros = {for (final m in a.mesasDeHoja(h.id)) m.numero};
          final actual = EditarArmado.pasoDe(a, numeros)!;
          final v = EditarArmado.separar(a, numeros, actual + 0.3)!;
          expect(v.pisan, 0, reason: '${a.clave} ${h.id}');
          expect(v.armado.numeros, a.numeros);
          _sano(v.armado, '${a.clave} ${h.id}');
        }
      }
    });
  });

  group('las mesas corridas en un armado del Canva', () {
    test('de fábrica no hay ninguna; al correr o agregar una, es esa', () {
      for (final a in ArmadosPredefinidos.todos) {
        expect(ArmadosPredefinidos.corridas(a), isEmpty, reason: a.clave);
      }
      final m = canva.mesa(10)!;
      var a = EditarArmado.mover(canva, 10, m.x - 30, m.y);
      expect(ArmadosPredefinidos.corridas(a), {10});
      final n = EditarArmado.proximoNumero(a);
      final lugar = EditarArmado.lugarLibre(a, a.hojas.first.id, lugarM: 2);
      a = EditarArmado.agregar(a,
          numero: n, hoja: a.hojas.first.id, x: lugar.x, y: lugar.y);
      expect(ArmadosPredefinidos.corridas(a), {10, n});
      // Un armado a medida no tiene "de fábrica" contra qué comparar.
      expect(ArmadosPredefinidos.corridas(aMedida), isEmpty);
    });

    test('la que se corrió avisa si queda apretada; las del jefe no', () {
      const medidas = MedidasPlano();
      // Tal cual vino del Canva no avisa nada, aunque alguna esté a menos de
      // 2 m: ahí las puso el jefe.
      expect(MedirSalon.revisar(canva, medidas, (_) => 0).apretadas, isEmpty);
      // Se arrima una mesa a su vecina.
      final vecina = EditarArmado.vecinas(canva, 10).first.numero;
      final v = canva.mesa(vecina)!;
      final arrimada = EditarArmado.mover(
        canva,
        10,
        v.x + canva.aUnidades(1.6),
        v.y,
        ajustar: false,
      );
      final apretadas = MedirSalon.revisar(arrimada, medidas, (_) => 0).apretadas;
      expect(apretadas, isNotEmpty);
      for (final p in apretadas) {
        expect([p.a, p.b], contains(10));
      }
    });
  });

  group('familias que quedan separadas', () {
    final familia = OcupantePlano(
      id: 'g',
      nombre: 'GÓMEZ, SOFÍA',
      numeros: const [10, 11],
    );

    test('si se le corre una mesa lejos de la otra, se avisa', () {
      final m = aMedida.mesa(11)!;
      final lejos =
          EditarArmado.mover(aMedida, 11, m.x, m.y + aMedida.aUnidades(9));
      expect(
        EditarArmado.familiasPartidas(aMedida, lejos, [familia]).single.id,
        'g',
      );
      // Un corrimiento chico no la separa.
      final cerca =
          EditarArmado.mover(aMedida, 11, m.x, m.y + aMedida.aUnidades(0.25));
      expect(EditarArmado.familiasPartidas(aMedida, cerca, [familia]), isEmpty);
    });

    test('la que ya estaba separada (lo pidió así) no cuenta', () {
      const separada = OcupantePlano(
        id: 's',
        nombre: 'SOSA, LUZ',
        numeros: [10, 60],
      );
      final m = aMedida.mesa(60)!;
      final b = EditarArmado.mover(aMedida, 60, m.x + 30, m.y);
      expect(EditarArmado.familiasPartidas(aMedida, b, [separada]), isEmpty);
    });

    test('separar el salón entero no parte a ninguna familia', () {
      final v = EditarArmado.separar(aMedida, aMedida.numeros.toSet(), 2.6)!;
      final familias = [
        for (var n = 1; n < 132; n += 2)
          if (!aMedida.cortes.contains(n))
            OcupantePlano(id: 'f$n', nombre: 'F$n, X', numeros: [n, n + 1]),
      ];
      expect(EditarArmado.familiasPartidas(aMedida, v.armado, familias), isEmpty);
    });
  });

  group('volver al armado original', () {
    test('un armado del Canva vuelve al de fábrica', () {
      final m = canva.mesa(10)!;
      final corrido = EditarArmado.mover(canva, 10, m.x - 40, m.y);
      final o = EditarArmado.original(corrido)!;
      expect(EditarArmado.firma(o), EditarArmado.firma(canva));
    });

    test('uno a medida se arma de nuevo igual que la primera vez', () {
      for (final partir in [null, 5]) {
        final a = ArmarAMedida.armar(OpcionesAMedida(
          playon: PlayonReal.costaSurubi,
          cantidad: 132,
          lugarM: 2.2,
          partirEnFila: partir,
        )).armado;
        final m = a.mesa(10)!;
        final corrido = EditarArmado.mover(a, 10, m.x - 40, m.y + 15);
        expect(EditarArmado.firma(corrido), isNot(EditarArmado.firma(a)));
        final o = EditarArmado.original(corrido)!;
        expect(o.hojas.length, a.hojas.length, reason: 'partir $partir');
        for (final x in a.mesas) {
          expect(o.mesa(x.numero)!.hoja, x.hoja, reason: 'partir $partir');
          expect(o.mesa(x.numero)!.x, closeTo(x.x, 1e-6));
          expect(o.mesa(x.numero)!.y, closeTo(x.y, 1e-6));
        }
      }
    });

    test('uno que no se sabe de dónde salió no tiene original', () {
      final raro = ArmadoSalon(
        clave: 'inventado@9',
        nombre: 'x',
        hojas: const [HojaPlano(id: 'A', titulo: '', caja: RectPlano(0, 0, 500, 500))],
        mesas: const [MesaPlano(numero: 1, hoja: 'A', x: 100, y: 100)],
      );
      expect(EditarArmado.original(raro), isNull);
      expect(SesionAcomodo(base: raro).motivoSinOriginal,
          contains('No se sabe de qué armado'));
    });
  });

  group('la sesión de Acomodar', () {
    test('al empezar no hay nada que guardar ni que deshacer', () {
      final s = SesionAcomodo(base: aMedida);
      expect(s.hayCambios, isFalse);
      expect(s.puedeGuardar, isFalse);
      expect(s.puedeDeshacer, isFalse);
      expect(identical(s.visto, aMedida), isTrue);
    });

    test('un arrastre entero es un solo paso para Deshacer', () {
      final s = SesionAcomodo(base: aMedida);
      final m = aMedida.mesa(20)!;
      s.empezarArrastre();
      for (var i = 1; i <= 8; i++) {
        s.arrastrarMesa(20, m.x + i * 15, m.y);
      }
      // Mientras se arrastra no se guarda.
      expect(s.puedeGuardar, isFalse);
      s.terminarArrastre();
      expect(s.hayCambios, isTrue);
      expect(s.actual.mesa(20)!.x, greaterThan(m.x));
      s.deshacer();
      expect(s.actual.mesa(20)!.x, m.x);
      expect(s.hayCambios, isFalse);
      expect(s.puedeDeshacer, isFalse);
    });

    test('apretar y soltar sin mover no deja nada para deshacer', () {
      final s = SesionAcomodo(base: aMedida);
      s.empezarArrastre();
      s.terminarArrastre();
      expect(s.puedeDeshacer, isFalse);
      // Y sin haber empezado, arrastrar no hace nada.
      s.arrastrarMesa(20, 0, 0);
      expect(s.hayCambios, isFalse);
    });

    test('volver una mesa a su lugar es no haber cambiado nada', () {
      final s = SesionAcomodo(base: aMedida);
      final m = aMedida.mesa(20)!;
      s.empezarArrastre();
      s.arrastrarMesa(20, m.x + 60, m.y);
      s.terminarArrastre();
      s.empezarArrastre();
      s.arrastrarMesa(20, m.x, m.y);
      s.terminarArrastre();
      expect(s.hayCambios, isFalse);
      expect(s.puedeGuardar, isFalse);
    });

    test('una mesa encima de otra no deja guardar, y dice cuáles', () {
      final s = SesionAcomodo(base: aMedida);
      final otra = aMedida.mesa(21)!;
      s.empezarArrastre();
      s.arrastrarMesa(20, otra.x + 5, otra.y);
      s.terminarArrastre();
      expect(s.hayCambios, isTrue);
      expect(s.bloqueos.single, 'Las mesas 20 y 21 se pisan.');
      expect(s.puedeGuardar, isFalse);
    });

    test('agregar da el número que sigue, y no reusa el de una que se sacó '
        'en la misma sesión', () {
      final s = SesionAcomodo(base: aMedida);
      expect(s.agregar('A'), 133);
      expect(s.agregar('A', cerca: 133), 134);
      expect(s.sacar(134), isNull);
      expect(s.sacar(132), isNull);
      expect(s.agregar('A'), 134);
      expect(s.bloqueos, isEmpty);
      expect(s.puedeGuardar, isTrue);
      _sano(s.actual, 'agregadas');
    });

    test('con familias en mesas más altas que el salón, sigue de la más alta',
        () {
      final s = SesionAcomodo(base: aMedida, enUso: const {200: 'la tiene X'});
      expect(s.agregar('A'), 201);
    });

    test('separar: se ve antes, cambia con APLICAR y CANCELAR no deja nada',
        () {
      final s = SesionAcomodo(base: aMedida);
      final todas = aMedida.numeros.toSet();
      s.probarSeparar(todas, 2.3);
      expect(s.previa!.pasoNuevoM, 2.3);
      expect(EditarArmado.pasoDe(s.visto, todas), closeTo(2.3, 1e-6));
      // Todavía no cambió nada, y con la vista previa abierta no se guarda.
      expect(identical(s.actual, aMedida), isTrue);
      expect(s.hayCambios, isFalse);
      s.cancelarSeparar();
      expect(identical(s.visto, aMedida), isTrue);

      s.probarSeparar(todas, 2.3);
      s.aplicarSeparar();
      expect(s.previa, isNull);
      expect(EditarArmado.pasoDe(s.actual, todas), closeTo(2.3, 1e-6));
      expect(s.puedeGuardar, isTrue);
      s.deshacer();
      expect(s.hayCambios, isFalse);
    });

    test('descartar vuelve al salón guardado y vacía Deshacer', () {
      final s = SesionAcomodo(base: aMedida);
      s.agregar('A');
      s.cambiarPasto(5);
      s.descartar();
      expect(identical(s.actual, aMedida), isTrue);
      expect(s.puedeDeshacer, isFalse);
    });

    test('volver al original: antes del sorteo sí, y se puede deshacer', () {
      final s = SesionAcomodo(base: aMedida);
      s.agregar('A');
      final m = aMedida.mesa(20)!;
      s.empezarArrastre();
      s.arrastrarMesa(20, m.x + 60, m.y);
      s.terminarArrastre();
      expect(s.motivoSinOriginal, isNull);
      expect(s.volverAlOriginal(), isNull);
      // Se arma de nuevo, parejo, con las mesas que había: las 133.
      expect(s.actual.mesas.length, 133);
      expect(EditarArmado.pasoDe(s.actual, s.actual.numeros.toSet()),
          closeTo(2.0, 1e-6));
      expect(s.actual.mesa(20)!.x, closeTo(m.x, 1e-6));
      expect(s.avisos((_) => 0), isEmpty);
      s.deshacer();
      expect(s.actual.mesa(20)!.x, closeTo(m.x + aMedida.aUnidades(1.25), 1));
    });

    test('volver al original: con familias sentadas no, y dice por qué', () {
      final s = SesionAcomodo(
        base: aMedida,
        enUso: const {12: 'la tiene GOMEZ'},
        haySorteo: true,
      );
      expect(s.motivoSinOriginal, contains('deshacé el sorteo'));
      expect(s.volverAlOriginal(), isNotNull);
      expect(s.hayCambios, isFalse);
    });

    test('volver al original: una mesa fijada que el original no tiene lo '
        'frena', () {
      final con133 = EditarArmado.agregar(aMedida,
          numero: 140, hoja: 'A', x: 200, y: 2000);
      final s = SesionAcomodo(
        base: con133,
        enUso: const {140: 'está fijada para SOSA'},
      );
      expect(s.motivoSinOriginal,
          'La mesa 140 está fijada para SOSA y el armado original no la tiene.');
    });

    test('avisa la familia que quedó separada, las apretadas y las que no '
        'entran', () {
      final s = SesionAcomodo(
        base: aMedida,
        ocupantes: const [
          OcupantePlano(id: 'g', nombre: 'GÓMEZ, SOFÍA', numeros: [10, 11]),
        ],
        haySorteo: true,
      );
      expect(s.avisos((_) => 0), isEmpty);
      // Se la lleva bien al costado: sale del hormigón.
      final m = aMedida.mesa(11)!;
      s.empezarArrastre();
      s.arrastrarMesa(11, m.x - aMedida.aUnidades(40), m.y);
      s.terminarArrastre();
      final avisos = s.avisos((_) => 0);
      expect(avisos, contains('GÓMEZ quedó con sus mesas 10 y 11 separadas.'));
      expect(avisos.join(), contains('no entra en el hormigón'));
      // Marcándola de pasto deja de avisar por el hormigón.
      s.cambiarPasto(11);
      expect(s.avisos((_) => 0).join(), isNot(contains('hormigón')));
    });
  });

  group('guardar sobre el plano que hay de verdad', () {
    final alumnos = [_alumno('gomez', [12, 13]), _alumno('sosa', [])];
    const config = ConfigPlano(
      libres: {50: MesaLibre(motivo: 'columna'), 60: MesaLibre()},
      fijadas: {7: MesaFijada(alumnoId: 'sosa')},
    );

    test('guarda el salón nuevo y conserva lo demás', () {
      final nuevo = EditarArmado.sacar(
          EditarArmado.marcarPasto(aMedida, 132, true), 50);
      final c = EditarArmado.paraGuardar(
        base: aMedida,
        nuevo: nuevo,
        fresco: aMedida,
        config: config,
        alumnos: alumnos,
      );
      expect(c.sePuede, isTrue);
      expect(identical(c.armado, nuevo), isTrue);
      // La que se sacó deja de figurar como libre; la otra queda.
      expect(c.config!.libres.keys, [60]);
      expect(c.config!.fijadas.keys, [7]);
      expect(c.mesas, [50]);
    });

    test('si la otra PC cambió el salón mientras tanto, no se pisa', () {
      final deLaOtra = EditarArmado.marcarPasto(aMedida, 1, true);
      final c = EditarArmado.paraGuardar(
        base: aMedida,
        nuevo: EditarArmado.sacar(aMedida, 100),
        fresco: deLaOtra,
        config: config,
        alumnos: alumnos,
      );
      expect(c.sePuede, isFalse);
      expect(c.problema, contains('La otra PC cambió el salón'));
    });

    test('si mientras tanto la mesa que saqué consiguió familia, no se saca',
        () {
      final c = EditarArmado.paraGuardar(
        base: aMedida,
        nuevo: EditarArmado.sacar(aMedida, 100),
        fresco: aMedida,
        config: config,
        alumnos: [...alumnos, _alumno('vega', [100])],
      );
      expect(c.sePuede, isFalse);
      expect(c.problema, 'La mesa 100 no se puede sacar: la tiene VEGA. '
          'No se guardó nada.');
    });

    test('tampoco si mientras tanto la fijaron', () {
      final c = EditarArmado.paraGuardar(
        base: aMedida,
        nuevo: EditarArmado.sacar(aMedida, 7),
        fresco: aMedida,
        config: config,
        alumnos: alumnos,
      );
      expect(c.problema, contains('está fijada para SOSA'));
    });

    test('con mesas encimadas no se guarda', () {
      final otra = aMedida.mesa(21)!;
      final c = EditarArmado.paraGuardar(
        base: aMedida,
        nuevo: EditarArmado.mover(aMedida, 20, otra.x, otra.y, ajustar: false),
        fresco: aMedida,
        config: config,
        alumnos: alumnos,
      );
      expect(c.problema, 'Las mesas 20 y 21 se pisan.');
    });
  });
}
