// "En caja": las familias que el mostrador de Entradas mandó a pagar, y quién ya
// pagó cuando las cuentas se vuelven a leer. Sin pantalla.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/entradas/services/en_caja.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';

import 'helpers/entrega_en_memoria.dart';

DeudaAlumno _debe(double saldo) => DeudaAlumno(saldoFicha: saldo, saldoPagos: saldo, mora: 0);

void main() {
  final perez = alumnoDeLaEntrega(id: 'p', nombre: 'PÉREZ, JUAN', extras: 1, saldo: 70000);
  final gomez = alumnoDeLaEntrega(id: 'g', nombre: 'GÓMEZ, ANA', extras: 1, saldo: 70000);

  test('mandar dos veces a la misma familia no la repite', () {
    final c = const EnCaja().mandar(perez, _debe(70000)).mandar(perez, _debe(70000));
    expect(c.familias, hasLength(1));
    expect(c.esperando.single.debia, 70000);
  });

  test('cuando paga todo pasa a "pagó", una sola vez', () {
    var c = const EnCaja().mandar(perez, _debe(70000)).mandar(gomez, _debe(70000));
    final r = c.conDeudas({'p': _debe(0), 'g': _debe(70000)});
    expect(r.recienPagaron.map((f) => f.alumnoId), ['p']);
    c = r.enCaja;
    expect(c.pagaron.single.alumnoId, 'p');
    expect(c.esperando.single.alumnoId, 'g');

    // La relectura siguiente no vuelve a sonar.
    expect(c.conDeudas({'p': _debe(0), 'g': _debe(70000)}).recienPagaron, isEmpty);
  });

  test('pagó una parte: sigue esperando, con lo que falta', () {
    final c = const EnCaja().mandar(perez, _debe(70000)).conDeudas({'p': _debe(40000)}).enCaja;
    final f = c.esperando.single;
    expect(f.pagoUnaParte, isTrue);
    expect(f.debe, 40000);
    expect(f.debia, 70000);
  });

  test('centavos de redondeo no cuentan como un pago', () {
    final c = const EnCaja().mandar(perez, _debe(70000)).conDeudas({'p': _debe(69999.995)}).enCaja;
    expect(c.esperando.single.pagoUnaParte, isFalse);
  });

  test('un alumno que ya no está sale de la lista', () {
    final c = const EnCaja().mandar(perez, _debe(70000)).conDeudas(const {}).enCaja;
    expect(c.vacia, isTrue);
  });

  test('sacar la deja afuera', () {
    final c = const EnCaja().mandar(perez, _debe(70000)).mandar(gomez, _debe(70000)).sacar('p');
    expect(c.familias.map((f) => f.alumnoId), ['g']);
  });
}
