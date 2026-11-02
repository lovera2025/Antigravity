import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';

import 'helpers/salon_puerto_viejo.dart';


/// Cada mesa, con su número y su lugar: comparar armados con `firma` no sirve
/// (mesa por mesa, como pide el plan).
List<String> _mesaPorMesa(ArmadoSalon a) => [
      for (final m in a.mesas)
        '${m.numero} ${m.hoja} ${m.x} ${m.y} ${m.pasto ? 'pasto' : ''}',
    ];

/// Solo los lugares, sin los números.
Set<String> _lugares(ArmadoSalon a) => {
      for (final m in a.mesas) '${m.hoja} ${m.x} ${m.y} ${m.pasto}',
    };

/// Los mismos lugares con los números mezclados: lo que deja mover mesas a mano.
ArmadoSalon _mezclado(ArmadoSalon a, int semilla) {
  final numeros = [...a.numeros]..shuffle(Random(semilla));
  return a.copyWith(mesas: [
    for (var i = 0; i < a.mesas.length; i++)
      MesaPlano(
        numero: numeros[i],
        hoja: a.mesas[i].hoja,
        x: a.mesas[i].x,
        y: a.mesas[i].y,
        pasto: a.mesas[i].pasto,
      ),
  ]);
}

/// Un playón vacío con una pista de 8 × 8 m en el medio.
ArmadoSalon _conPista(PlayonReal p) {
  final v = ArmarAMedida.vacio(p);
  final b = v.hojas.first.contorno!.puntos;
  final cx = (b.map((q) => q.x).reduce(min) + b.map((q) => q.x).reduce(max)) / 2;
  final y0 = b.map((q) => q.y).reduce(min);
  return v.copyWith(sectores: [
    ...v.sectores,
    SectorPlano(
      tipo: TipoSector.pista,
      texto: 'Pista',
      hoja: 'A',
      caja: RectPlano(
        cx - v.aUnidades(4),
        y0 + v.aUnidades(p.profundidadM / 2 - 4),
        v.aUnidades(8),
        v.aUnidades(8),
      ),
    ),
  ]);
}

/// El mismo salón con el escenario en la mitad del playón: hay filas de los dos
/// lados.
ArmadoSalon _conEscenarioAlMedio(PlayonReal p) {
  final v = ArmarAMedida.vacio(p);
  final b = v.hojas.first.contorno!.puntos;
  final y0 = b.map((q) => q.y).reduce(min);
  return v.copyWith(sectores: [
    for (final s in v.sectores)
      s.tipo == TipoSector.escenario
          ? s.copyWith(
              caja: RectPlano(
                s.caja.x,
                y0 + v.aUnidades(p.profundidadM / 2),
                s.caja.ancho,
                s.caja.alto,
              ),
            )
          : s,
  ]);
}

const _playones = [
  PlayonReal(frenteM: 25, fondoM: 25, profundidadM: 30),
  PlayonReal(frenteM: 40, fondoM: 28, profundidadM: 35),
  PlayonReal(frenteM: 18, fondoM: 60, profundidadM: 50),
  PlayonReal(frenteM: 12, fondoM: 14, profundidadM: 9),
];

void main() {
  group('Puerto Viejo, como está en la nube', () {
    test('hoy tiene 13 saltos', () {
      final a = armadoDePuertoViejo();
      expect(a.mesas, hasLength(35));
      expect(a.cortes, hasLength(13));
    });

    test('queda del 1 al 35 con un solo salto: el paso de un lado al otro', () {
      final a = armadoDePuertoViejo();
      final r = ArmarAMedida.ordenarNumeros(a).armado;
      expect(r.numeros, [for (var n = 1; n <= 35; n++) n]);
      expect(r.cortes, {17});
      expect(r.ultimoNumero, 35);

      final cx = a.sectores
          .firstWhere((s) => s.tipo == TipoSector.escenario)
          .caja
          .centroX;
      for (final m in r.mesas) {
        expect(m.x < cx, m.numero <= 17, reason: 'la mesa ${m.numero}');
      }
    });

    test('la 1 queda contra el pasillo, en la fila del escenario', () {
      final r = ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado;
      expect(r.mesa(1)!.y, closeTo(1265, 0.01));
      expect(r.mesa(1)!.x, closeTo(1323.375, 0.01));
      expect(r.mesa(35)!.y, closeTo(1265, 0.01));
      expect(r.mesa(35)!.x, closeTo(1743.375, 0.01));
    });

    test('ninguna mesa se mueve, y nada más del salón cambia', () {
      final a = armadoDePuertoViejo();
      final r = ArmarAMedida.ordenarNumeros(a).armado;
      expect(_lugares(r), _lugares(a));
      expect(
        jsonEncode({...r.toJson(), 'mesas': null}),
        jsonEncode({...a.toJson(), 'mesas': null}),
      );
    });

    test('cambio lleva cada número viejo a la mesa que tenía', () {
      final a = armadoDePuertoViejo();
      final (armado: r, cambio: cambio) = ArmarAMedida.ordenarNumeros(a);
      expect(cambio, isNotEmpty);
      for (final m in a.mesas) {
        final nuevo = r.mesa(cambio[m.numero] ?? m.numero)!;
        expect(nuevo.x, m.x, reason: 'la que era la ${m.numero}');
        expect(nuevo.y, m.y, reason: 'la que era la ${m.numero}');
      }
      expect(cambio.values.toSet(), hasLength(cambio.length));
    });

    test('ordenarlo de nuevo no cambia nada', () {
      final r = ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado;
      final otra = ArmarAMedida.ordenarNumeros(r);
      expect(otra.cambio, isEmpty);
      expect(_mesaPorMesa(otra.armado), _mesaPorMesa(r));
    });

    test('una mesa corrida un poco a mano sigue en su fila', () {
      final a = armadoDePuertoViejo();
      final bien = ArmarAMedida.ordenarNumeros(a).armado;
      final corrida = a.mesa(13)!; // La fila 2 del lado izquierdo.
      final movido = a.copyWith(mesas: [
        for (final m in a.mesas)
          m.numero == 13 ? m.copyWith(y: m.y + a.aUnidades(0.5)) : m,
      ]);
      final r = ArmarAMedida.ordenarNumeros(movido).armado;
      final enBien = bien.mesas.firstWhere(
        (m) => m.x == corrida.x && m.y == corrida.y,
      );
      final enR = r.mesas.firstWhere(
        (m) => m.x == corrida.x && m.y == corrida.y + a.aUnidades(0.5),
      );
      expect(enR.numero, enBien.numero);
    });

    test('una mesa agregada en la columna sigue la serpentina', () {
      final a = armadoDePuertoViejo();
      final r = ArmarAMedida.ordenarNumeros(a.copyWith(mesas: [
        ...a.mesas,
        const MesaPlano(numero: 36, hoja: 'A', x: 1900.875, y: 2052.5),
      ])).armado;
      expect(r.numeros, [for (var n = 1; n <= 36; n++) n]);
      expect(r.cortes, {17});
      expect(r.mesa(18)!.y, 2052.5);
    });

    test('una mesa suelta lejos de todas no rompe las filas', () {
      final a = armadoDePuertoViejo();
      final suelta = a.copyWith(mesas: [
        ...a.mesas,
        const MesaPlano(numero: 36, hoja: 'A', x: 650, y: 2500),
      ]);
      final r = ArmarAMedida.ordenarNumeros(suelta).armado;
      expect(r.numeros, [for (var n = 1; n <= 36; n++) n]);
      expect(_lugares(r), _lugares(suelta));
      // Solo agrega el salto de ir y volver de ella, y el de lado a lado.
      expect(r.cortes.length, lessThanOrEqualTo(2));
    });
  });

  group('sobre un salón que ya está en orden', () {
    void noCambia(ArmadoSalon a, String que) {
      final r = ArmarAMedida.ordenarNumeros(a);
      expect(r.cambio, isEmpty, reason: que);
      expect(_mesaPorMesa(r.armado), _mesaPorMesa(a), reason: que);
    }

    void vuelveSolo(ArmadoSalon a, String que) {
      for (final semilla in [1, 2, 3]) {
        final r = ArmarAMedida.ordenarNumeros(_mezclado(a, semilla));
        expect(_mesaPorMesa(r.armado), _mesaPorMesa(a), reason: '$que, $semilla');
      }
    }

    void probar(ArmadoSalon a, String que) {
      noCambia(a, que);
      if (a.mesas.length > 1) vuelveSolo(a, que);
    }

    test('lo que da ACOMODAR, sin nada en el playón', () {
      for (final p in _playones) {
        final v = ArmarAMedida.vacio(p);
        for (final n in [1, 2, 7, 17, 35, 60]) {
          final a = ArmarAMedida.acomodar(v, cantidad: n).armado;
          probar(a, '${p.frenteM}/${p.fondoM}/${p.profundidadM}, $n mesas');
        }
      }
    });

    test('lo que da ACOMODAR, con una pista en el medio', () {
      for (final p in _playones.take(3)) {
        final v = _conPista(p);
        for (final n in [7, 17, 35, 60]) {
          final a = ArmarAMedida.acomodar(v, cantidad: n).armado;
          probar(a, 'pista ${p.frenteM}/${p.fondoM}, $n mesas');
        }
      }
    });

    test('lo que da ACOMODAR, a otra distancia entre mesas', () {
      final v = ArmarAMedida.vacio(_playones.first);
      for (final l in [1.5, 2.5, 3.0, 4.0]) {
        final a = ArmarAMedida.acomodar(v, cantidad: 30, lugarM: l).armado;
        probar(a, 'a $l m');
      }
    });

    test('con el escenario en el medio, con filas de los dos lados', () {
      for (final p in _playones.take(3)) {
        final v = _conEscenarioAlMedio(p);
        for (final n in [11, 30, 60]) {
          final a = ArmarAMedida.acomodar(v, cantidad: n).armado;
          probar(a, 'escenario al medio ${p.frenteM}/${p.fondoM}, $n mesas');
        }
      }
    });

    test('lo que da el armado a medida, con pasarela', () {
      for (final p in _playones.take(3)) {
        for (final n in [20, 41, 100]) {
          final a = ArmarAMedida.armar(
            OpcionesAMedida(playon: p, cantidad: n),
          ).armado;
          probar(a, 'pasarela ${p.frenteM}/${p.fondoM}, $n mesas');
        }
      }
    });

    test('el mismo orden entre dos hojas: la izquierda de las dos y la derecha de vuelta', () {
      final a = ArmarAMedida.armar(
        const OpcionesAMedida(
          playon: PlayonReal(frenteM: 34, fondoM: 52, profundidadM: 45),
          cantidad: 100,
          partirEnFila: 4,
        ),
      ).armado;
      expect(a.hojas, hasLength(2));
      probar(a, 'dos hojas');
    });
  });

  group('las del pasto', () {
    /// Un salón de 30 mesas con tres en el pasto, con números del medio.
    ArmadoSalon conPasto() {
      final a = ArmarAMedida.acomodar(
        ArmarAMedida.vacio(_playones.first),
        cantidad: 30,
      ).armado;
      return a.copyWith(mesas: [
        for (final m in a.mesas)
          {28, 29, 30}.contains(m.numero) ? m.copyWith(pasto: true) : m,
      ]);
    }

    test('van al final, con los números que siguen', () {
      final a = conPasto();
      final mezclado = _mezclado(a, 7);
      final r = ArmarAMedida.ordenarNumeros(mezclado).armado;
      expect(r.numeros, [for (var n = 1; n <= 30; n++) n]);
      expect(r.pasto, {28, 29, 30});
      expect(r.cantidadComunes, 27);
      expect(_lugares(r), _lugares(mezclado));
    });

    test('siguen pegadas entre sí si están seguidas', () {
      final r = ArmarAMedida.ordenarNumeros(_mezclado(conPasto(), 7)).armado;
      expect(r.pegadas(28, 29), isTrue);
      expect(r.pegadas(29, 30), isTrue);
    });
  });

  group('lo demás', () {
    test('sin mesas, el mismo armado y ningún cambio', () {
      final v = ArmarAMedida.vacio(_playones.first);
      final r = ArmarAMedida.ordenarNumeros(v);
      expect(identical(r.armado, v), isTrue);
      expect(r.cambio, isEmpty);
    });

    test('llena los huecos', () {
      final a = ArmarAMedida.acomodar(
        ArmarAMedida.vacio(_playones.first),
        cantidad: 12,
      ).armado;
      final conHueco = a.copyWith(
        mesas: [for (final m in a.mesas) if (m.numero != 5) m],
        ultimoNumero: 12,
      );
      final r = ArmarAMedida.ordenarNumeros(conHueco);
      expect(r.armado.numeros, [for (var n = 1; n <= 11; n++) n]);
      expect(r.armado.ultimoNumero, 11);
    });

    test('en orden pero con un número viejo recordado, vuelve a N', () {
      final a = ArmarAMedida.acomodar(
        ArmarAMedida.vacio(_playones.first),
        cantidad: 12,
      ).armado.copyWith(ultimoNumero: 20);
      final r = ArmarAMedida.ordenarNumeros(a);
      expect(r.cambio, isEmpty);
      expect(r.armado.ultimoNumero, 12);
    });

    test('una mesa de una hoja que no existe no se pierde', () {
      final a = armadoDePuertoViejo();
      final r = ArmarAMedida.ordenarNumeros(a.copyWith(mesas: [
        ...a.mesas,
        const MesaPlano(numero: 36, hoja: 'Z', x: 10, y: 10),
      ])).armado;
      expect(r.mesas, hasLength(36));
      expect(r.mesas.where((m) => m.hoja == 'Z'), hasLength(1));
    });

    test('el JSON no suma ninguna clave', () {
      final a = armadoDePuertoViejo();
      final r = ArmarAMedida.ordenarNumeros(a).armado;
      expect(r.toJson().keys.toSet(), a.toJson().keys.toSet());
      expect(
        (r.toJson()['mesas'] as List).first.keys.toSet(),
        (a.toJson()['mesas'] as List).first.keys.toSet(),
      );
    });
  });
}
