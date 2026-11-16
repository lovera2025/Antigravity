// Las familias con adicional en los huecos del salón justo (16-nov-2026): cada
// una junta, en mesas seguidas o una detrás de la otra, y las menos posibles
// una detrás de la otra. Cuenta pura, sin base ni pantalla.
//
// El salón de la ventana de prueba (35 mesas "Fila por fila"):
//   1  2  3  4  5 | 6  7  8  9 10
//  20 19 18 17 16 |15 14 13 12 11
//  21 22 23 24 25 |26 27 28 29 30
//        35 34 33 |32 31
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/familias_en_los_huecos.dart';
import 'package:arguello_events/features/plano/services/mesas_juntas.dart';

ArmadoSalon _salon(int mesas) => ArmarAMedida.armar(
      OpcionesAMedida(
        playon: const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
        cantidad: mesas,
        fin: FinNumeracion.filas,
      ),
    ).armado;

/// Las de la ventana de prueba que tienen adicional: cuatro de 2 y una de 3.
const List<FamiliaParaUbicar> _conAdicional = [
  (id: 'a1', mesas: 2),
  (id: 'a2', mesas: 2),
  (id: 'a3', mesas: 2),
  (id: 'a4', mesas: 2),
  (id: 'b1', mesas: 3),
];

/// Detrás de las 24 de una sola mesa: de la 25 a la 35.
final _detrasDeLasUnas = [for (var n = 25; n <= 35; n++) n];

void main() {
  final a = _salon(35);

  void comprobar(AcomodoEnLosHuecos r, List<FamiliaParaUbicar> familias) {
    final usadas = <int>[];
    for (final f in familias) {
      final suyas = r.mesas[f.id]!;
      expect(suyas, hasLength(f.mesas), reason: f.id);
      expect(MesasJuntas.juntas(a, suyas), isTrue, reason: '${f.id} $suyas');
      usadas.addAll(suyas);
    }
    expect(usadas.toSet(), hasLength(usadas.length), reason: 'una mesa dos veces');
    expect(
      r.mesas.values.where((m) => MesasJuntas.usaUnaDetrasDeLaOtra(a, m)).length,
      r.unaDetrasDeLaOtra,
    );
  }

  test('el salón justo: entran todas, con una sola una detrás de la otra', () {
    final r = FamiliasEnLosHuecos.acomodar(
      armado: a,
      libres: _detrasDeLasUnas,
      familias: _conAdicional,
    )!;
    comprobar(r, _conAdicional);
    expect(r.unaDetrasDeLaOtra, 1);
    // La 25 queda sola contra la pasarela: la tapa una familia con la 33.
    final quien = r.mesas.entries.firstWhere((x) => x.value.contains(25));
    expect(quien.value, [25, 33]);
  });

  test('sin el hueco, ninguna una detrás de la otra', () {
    // De la 26 a la 35 entran en mesas seguidas: 26-27, 28-29-30, 31-32,
    // 33-34 y la 35 vacía.
    final r = FamiliasEnLosHuecos.acomodar(
      armado: a,
      libres: [for (var n = 26; n <= 35; n++) n],
      familias: [
        (id: 'a1', mesas: 2),
        (id: 'a2', mesas: 2),
        (id: 'a3', mesas: 2),
        (id: 'b1', mesas: 3),
      ],
    )!;
    expect(r.unaDetrasDeLaOtra, 0);
    for (final m in r.mesas.values) {
      expect(MesasJuntas.usaUnaDetrasDeLaOtra(a, m), isFalse, reason: '$m');
    }
  });

  test('nunca a los dos lados de la pasarela ni en diagonal', () {
    expect(
      FamiliasEnLosHuecos.acomodar(
        armado: a,
        libres: [25, 26],
        familias: const [(id: 'x', mesas: 2)],
      ),
      isNull,
    );
    expect(
      FamiliasEnLosHuecos.acomodar(
        armado: a,
        libres: [25, 34],
        familias: const [(id: 'x', mesas: 2)],
      ),
      isNull,
    );
  });

  test('sin azar da siempre lo mismo, y la primera de la lista toma el primer '
      'lugar (Cumplimiento debido)', () {
    final uno = FamiliasEnLosHuecos.acomodar(
      armado: a,
      libres: _detrasDeLasUnas,
      familias: _conAdicional,
    )!;
    final otro = FamiliasEnLosHuecos.acomodar(
      armado: a,
      libres: _detrasDeLasUnas,
      familias: _conAdicional,
    )!;
    expect(otro.mesas, uno.mesas);
    final r = FamiliasEnLosHuecos.acomodar(
      armado: a,
      libres: [for (var n = 26; n <= 32; n++) n],
      familias: const [(id: 'mejor', mesas: 2), (id: 'peor', mesas: 2)],
    )!;
    expect(r.mesas['mejor'], [26, 27]);
  });

  test('con azar, cada sorteo distinto y siempre bien', () {
    final vistos = <String>{};
    for (var semilla = 0; semilla < 40; semilla++) {
      final r = FamiliasEnLosHuecos.acomodar(
        armado: a,
        libres: _detrasDeLasUnas,
        familias: _conAdicional,
        rng: Random(semilla),
        desde: 1,
      )!;
      comprobar(r, _conAdicional);
      expect(r.unaDetrasDeLaOtra, 1, reason: 'semilla $semilla');
      vistos.add('${[for (final f in _conAdicional) r.mesas[f.id]]}');
    }
    expect(vistos.length, greaterThan(5));
  });

  test('si no entran, null; sin familias, nada', () {
    expect(
      FamiliasEnLosHuecos.acomodar(
        armado: a,
        libres: [25, 33],
        familias: _conAdicional,
      ),
      isNull,
    );
    expect(
      FamiliasEnLosHuecos.acomodar(
        armado: a,
        libres: [28, 29],
        familias: const [(id: 'x', mesas: 0)],
      ),
      isNull,
    );
    final nada = FamiliasEnLosHuecos.acomodar(
      armado: a,
      libres: _detrasDeLasUnas,
      familias: const [],
    )!;
    expect(nada.mesas, isEmpty);
  });

  test('siempre las menos familias una detrás de la otra: contra la cuenta a '
      'mano, en 300 pedazos de salón al azar', () {
    // La cuenta a mano: todas las maneras de darle a cada familia mesas
    // juntas y libres, y de esas, la que menos usa una detrás de la otra.
    int? menosPosibles(List<int> libres, List<int> tamanios) {
      int? mejor;
      final usadas = <int>{};
      void probar(int f, int detras) {
        if (mejor != null && detras >= mejor!) return;
        if (f == tamanios.length) {
          mejor = detras;
          return;
        }
        final k = tamanios[f];
        final vistas = <String>{};
        void crecer(List<int> grupo) {
          if (grupo.length == k) {
            final clave = ([...grupo]..sort()).join(',');
            if (!vistas.add(clave)) return;
            usadas.addAll(grupo);
            probar(
              f + 1,
              detras + (MesasJuntas.usaUnaDetrasDeLaOtra(a, grupo) ? 1 : 0),
            );
            usadas.removeAll(grupo);
            return;
          }
          for (final n in libres) {
            if (usadas.contains(n) || grupo.contains(n)) continue;
            if (grupo.isNotEmpty &&
                !grupo.any((g) => MesasJuntas.unidas(a, g, n))) {
              continue;
            }
            crecer([...grupo, n]);
          }
        }

        crecer([]);
      }

      probar(0, 0);
      return mejor;
    }

    final rng = Random(16);
    var comparados = 0;
    for (var vuelta = 0; vuelta < 300; vuelta++) {
      // Un pedazo del fondo del salón (de la 16 a la 35) sin algunas mesas.
      final libres = [
        for (var n = 16; n <= 35; n++)
          if (rng.nextDouble() < 0.6) n,
      ];
      final tamanios = <int>[];
      var quedan = libres.length - rng.nextInt(2);
      while (quedan >= 2 && tamanios.length < 4) {
        final k = 2 + rng.nextInt(min(2, quedan - 1));
        tamanios.add(k);
        quedan -= k;
      }
      if (tamanios.isEmpty) continue;
      final esperado = menosPosibles(libres, tamanios);
      final r = FamiliasEnLosHuecos.acomodar(
        armado: a,
        libres: libres,
        familias: [
          for (final (i, k) in tamanios.indexed) (id: 'f$i', mesas: k),
        ],
      );
      expect(r?.unaDetrasDeLaOtra, esperado,
          reason: 'libres $libres, familias $tamanios');
      if (esperado != null && esperado > 0) comparados++;
    }
    expect(comparados, greaterThan(10),
        reason: 'pocos casos con alguna una detrás de la otra');
  });

  test('un salón grande no tarda, entre o no entre', () {
    // 81 mesas. La última fila queda pasando la pasarela, corrida hacia el
    // medio: la 79 solo toca a otra en diagonal, así que la tapa una familia
    // de una sola mesa. Cada lado tiene un número impar de mesas: hace falta
    // una de una mesa más en cada uno.
    final grande = _salon(81);
    final libres = [for (final m in grande.mesas) m.numero];
    expect(MesasJuntas.grupos(grande, [73, 79]), hasLength(2));
    final reloj = Stopwatch()..start();
    final r = FamiliasEnLosHuecos.acomodar(
      armado: grande,
      libres: libres,
      familias: [
        for (var i = 0; i < 39; i++) (id: 'f$i', mesas: 2),
        for (var i = 0; i < 3; i++) (id: 's$i', mesas: 1),
      ],
      rng: Random(3),
    );
    reloj.stop();
    expect(r, isNotNull);
    expect(reloj.elapsed, lessThan(const Duration(seconds: 5)));
    for (final m in r!.mesas.values) {
      expect(MesasJuntas.juntas(grande, m), isTrue, reason: '$m');
    }
    // Todas de 2 y una sola de 1: no entra (la 79 se lleva la de 1 y del otro
    // lado queda un número impar). Lo dice sin colgarse.
    final reloj2 = Stopwatch()..start();
    final no = FamiliasEnLosHuecos.acomodar(
      armado: grande,
      libres: libres,
      familias: [
        for (var i = 0; i < 40; i++) (id: 'g$i', mesas: 2),
        (id: 'sola', mesas: 1),
      ],
    );
    reloj2.stop();
    expect(no, isNull);
    expect(reloj2.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
