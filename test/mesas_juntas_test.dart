// Cuándo las mesas de una familia están juntas (16-nov-2026): seguidas y
// pegadas, como siempre, o una detrás de la otra del mismo lado de la
// pasarela. Nunca a los dos lados de la pasarela ni en diagonal.
//
// El salón: el de la ventana de prueba, 35 mesas "Fila por fila" en el playón de
// Costa Surubí. Filas de 5 y 5, con la pasarela entre la 5.ª y la 6.ª:
//   1  2  3  4  5 | 6  7  8  9 10
//  20 19 18 17 16 |15 14 13 12 11
//  21 22 23 24 25 |26 27 28 29 30
//        35 34 33 |32 31
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/mesas_juntas.dart';

ArmadoSalon _salon() => ArmarAMedida.armar(
      OpcionesAMedida(
        playon: const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
        cantidad: 35,
        fin: FinNumeracion.filas,
      ),
    ).armado;

void main() {
  final a = _salon();

  test('el salón de la prueba es el que dice el dibujo de arriba', () {
    double x(int n) => a.mesa(n)!.x;
    double y(int n) => a.mesa(n)!.y;
    expect(y(25), y(26));
    expect(x(25), x(33));
    expect(y(33), greaterThan(y(25)));
    expect(x(24), x(34));
    expect(a.cortes, contains(25), reason: 'la 25 y la 26: la pasarela');
  });

  test('una detrás de la otra: la mesa de atrás, del mismo lado', () {
    expect(MesasJuntas.unaDetrasDeLaOtra(a, 25, 33), isTrue);
    expect(MesasJuntas.unaDetrasDeLaOtra(a, 33, 25), isTrue);
    expect(MesasJuntas.unaDetrasDeLaOtra(a, 24, 34), isTrue);
  });

  test('nunca a los dos lados de la pasarela, en diagonal ni la misma', () {
    expect(MesasJuntas.unaDetrasDeLaOtra(a, 25, 26), isFalse);
    expect(MesasJuntas.seguidas(a, 25, 26), isFalse);
    expect(MesasJuntas.unidas(a, 25, 26), isFalse);
    expect(MesasJuntas.unaDetrasDeLaOtra(a, 25, 34), isFalse,
        reason: 'en diagonal');
    expect(MesasJuntas.unaDetrasDeLaOtra(a, 25, 25), isFalse);
    expect(MesasJuntas.unaDetrasDeLaOtra(a, 21, 25), isFalse,
        reason: 'en la misma fila pero lejos');
  });

  test('seguidas: números seguidos y pegadas, como el sorteo de siempre', () {
    expect(MesasJuntas.seguidas(a, 28, 29), isTrue);
    expect(MesasJuntas.seguidas(a, 29, 28), isTrue);
    expect(MesasJuntas.seguidas(a, 30, 31), isFalse,
        reason: 'la 30 y la 31 no se tocan');
  });

  test('juntas y en grupos', () {
    expect(MesasJuntas.juntas(a, [25, 33]), isTrue);
    expect(MesasJuntas.usaUnaDetrasDeLaOtra(a, [25, 33]), isTrue);
    expect(MesasJuntas.juntas(a, [28, 29, 30]), isTrue);
    expect(MesasJuntas.usaUnaDetrasDeLaOtra(a, [28, 29, 30]), isFalse);
    expect(MesasJuntas.juntas(a, [25, 26]), isFalse);
    expect(MesasJuntas.juntas(a, [25, 34]), isFalse);
    expect(MesasJuntas.juntas(a, [7]), isTrue);
    expect(MesasJuntas.grupos(a, [26, 33, 25]), [
      [25, 33],
      [26],
    ]);
    expect(MesasJuntas.juntas(a, [24, 25, 33]), isTrue);
  });

  test('la cápsula: el tramo de siempre, o el recorrido por la de atrás', () {
    expect(MesasJuntas.capsulas(a, [28, 29, 30]), [
      [28, 29, 30],
    ]);
    expect(MesasJuntas.capsulas(a, [25, 33]), [
      [25, 33],
    ]);
    // La 24 y la 25 seguidas, y la 33 detrás de la 25: una sola línea.
    expect(MesasJuntas.capsulas(a, [24, 25, 33]), [
      [24, 25, 33],
    ]);
    expect(MesasJuntas.capsulas(a, [7]), isEmpty);
  });
}
