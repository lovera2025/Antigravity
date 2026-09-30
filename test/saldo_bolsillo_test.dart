import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/mi_empresa/bolsa_personal_helpers.dart';

/// Lo que queda en MI BOLSILLO. El 29-sep, al partir un retiro entre efectivo y
/// banco, el bolsillo pasó de $0 a $20,3M: se sumaba solo el medio positivo.
void main() {
  test('apartado del banco y gastado en efectivo: el total no inventa plata', () {
    // Los números del 29-sep, antes de partir también el gasto de $69M.
    final s = saldoBolsillo(
      apartadoEfectivo: 58966503.42,
      apartadoTransferencia: 23266034.17,
      gastadoEfectivo: 79232537.59,
      gastadoTransferencia: 3000000,
    );
    expect(s.total, closeTo(0, 0.001));
    expect(s.efectivo, 0);
    expect(s.transferencia, closeTo(0, 0.001));
  });

  test('con plata sin gastar, cada medio dice lo suyo', () {
    final s = saldoBolsillo(
      apartadoEfectivo: 100,
      apartadoTransferencia: 50,
      gastadoEfectivo: 30,
      gastadoTransferencia: 0,
    );
    expect(s.total, 120);
    expect(s.efectivo, 70);
    expect(s.transferencia, 50);
  });

  test('un medio nunca dice más de lo que queda en total', () {
    final s = saldoBolsillo(
      apartadoEfectivo: 0,
      apartadoTransferencia: 100,
      gastadoEfectivo: 80,
      gastadoTransferencia: 0,
    );
    expect(s.total, 20);
    expect(s.efectivo, 0);
    expect(s.transferencia, 20);
  });

  test('gastado de más: todo en cero, nunca negativo', () {
    final s = saldoBolsillo(
      apartadoEfectivo: 10,
      apartadoTransferencia: 0,
      gastadoEfectivo: 50,
      gastadoTransferencia: 0,
    );
    expect(s.total, 0);
    expect(s.efectivo, 0);
    expect(s.transferencia, 0);
  });
}
