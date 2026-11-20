// La línea de arriba de VENDER: "Todo subido" solo cuando no queda nada de este
// equipo en la cola (pedido del usuario, 20-nov-2026: "si sube, que suba de
// verdad"; antes contaba solo las ventas).
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/entradas/cuentas/linea_de_subida.dart';

void main() {
  String linea(PendientesDeEntradas p, {bool internet = true}) =>
      lineaDeSubidaDeEntradas(hayInternet: internet, pendientes: p).texto;

  test('sin nada en la cola: "Todo subido", y sin internet "nada por subir"', () {
    expect(linea(PendientesDeEntradas.nada), 'Todo subido');
    expect(linea(PendientesDeEntradas.nada, internet: false),
        'Sin internet · nada por subir');
    expect(
      lineaDeSubidaDeEntradas(hayInternet: true, pendientes: PendientesDeEntradas.nada)
          .atencion,
      isFalse,
    );
  });

  test('solo ventas, como siempre', () {
    expect(linea(const PendientesDeEntradas(ventas: 1)), '1 venta subiendo');
    expect(linea(const PendientesDeEntradas(ventas: 3), internet: false),
        'Sin internet · 3 ventas por subir');
  });

  test('una entrega sin subir ya no dice "Todo subido"', () {
    const p = PendientesDeEntradas(entregas: 1);
    expect(linea(p), '1 entrega subiendo');
    expect(linea(p, internet: false), 'Sin internet · 1 entrega por subir');
    expect(lineaDeSubidaDeEntradas(hayInternet: true, pendientes: p).atencion, isTrue);
  });

  test('la caja cerrada sin subir tampoco: "1 cambio"', () {
    expect(linea(const PendientesDeEntradas(otros: 1), internet: false),
        'Sin internet · 1 cambio por subir');
  });

  test('todo junto, con comas y la última con "y"', () {
    expect(PendientesDeEntradas(ventas: 2, entregas: 1).enPalabras,
        '2 ventas y 1 entrega');
    expect(
      const PendientesDeEntradas(ventas: 2, entregas: 3, otros: 1).enPalabras,
      '2 ventas, 3 entregas y 1 cambio',
    );
    expect(const PendientesDeEntradas(entregas: 2, otros: 2).enPalabras,
        '2 entregas y 2 cambios');
  });
}
