// Congelar la mora (6.2.1). El ejemplo que confirmó el usuario ("sí, eso es"),
// tal cual: PÉREZ, JUAN, cuota de $30.000 ($300 por día), al 23/10 debe la
// cuota 4 ($25.200, 84 d), la 5 ($15.900, 53 d) y la 6 ($6.900, 23 d).
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _id = 'c0000000-0000-4000-8000-0000000000aa';

/// 9 cuotas de $30.000; inscripto el 30/3 (en AR): la cuota 1 vence el 30/4, la
/// 4 el 31/7, la 5 el 31/8, la 6 el 30/9 y la 7 el 31/10. Pagó 3.
ContratoAlumno _perez({int pagadas = 3}) => ContratoAlumno(
      id: _id,
      eventoId: 'e0000000-0000-4000-8000-000000000001',
      nombreAlumno: 'PÉREZ, JUAN',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 30000.0 * (9 - pagadas),
      cuotasPagadas: pagadas,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 30, 3),
    );

/// "cuota 4 · 84 d · $25200", una por renglón.
List<String> _renglones(ContratoAlumno c, DateTime dia) => [
      for (final d in MoraCuotaCalculator.calcularDesglose(c, dia))
        'cuota ${d.numeroCuota} · ${d.diasMora} d · \$${d.interesBruto.round()}',
    ];

final _oct23 = DateTime(2026, 10, 23);
final _nov2 = DateTime(2026, 11, 2);
final _nov3 = DateTime(2026, 11, 3);

void main() {
  tearDown(MoraCongelada.vaciar);

  group('la cuenta, con el ejemplo de PÉREZ', () {
    test('sin nada congelado, como siempre', () {
      expect(_renglones(_perez(), _oct23), [
        'cuota 4 · 84 d · \$25200',
        'cuota 5 · 53 d · \$15900',
        'cuota 6 · 23 d · \$6900',
      ]);
    });

    test('congela la 4 y la 5: 10 días después siguen igual y la 6 sube', () {
      MoraCongelada.poner(_id, MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: _oct23));
      expect(_renglones(_perez(), _nov2), [
        'cuota 4 · 84 d · \$25200',
        'cuota 5 · 53 d · \$15900',
        'cuota 6 · 33 d · \$9900',
        // La 7 venció el 31/10 y no está congelada.
        'cuota 7 · 2 d · \$600',
      ]);
    });

    test('Mantener: siguen desde \$25.200 y \$15.900 y vuelven a sumar desde ese día', () {
      final congelada = MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: _oct23);
      MoraCongelada.poner(_id, congelada.mantener(cuotas: {4, 5}, dia: _nov2));
      expect(_renglones(_perez(), _nov2).take(2), [
        'cuota 4 · 84 d · \$25200',
        'cuota 5 · 53 d · \$15900',
      ]);
      expect(_renglones(_perez(), _nov3).take(2), [
        'cuota 4 · 85 d · \$25500',
        'cuota 5 · 54 d · \$16200',
      ]);
    });

    test('Recalcular: \$28.200 y \$18.900, como si no se hubieran congelado', () {
      final congelada = MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: _oct23);
      final recalculada = congelada.recalcular(cuotas: {4, 5}, cuotasPagadas: 3, dia: _nov2);
      expect(recalculada.vacia, isTrue);
      MoraCongelada.poner(_id, recalculada);
      expect(_renglones(_perez(), _nov2).take(2), [
        'cuota 4 · 94 d · \$28200',
        'cuota 5 · 63 d · \$18900',
      ]);
    });

    test('con "Todas", la cuota que vence el 31/10 tampoco suma', () {
      MoraCongelada.poner(_id, MoraCongelada.nada.congelar(todas: true, dia: _oct23));
      expect(_renglones(_perez(), _nov2), [
        'cuota 4 · 84 d · \$25200',
        'cuota 5 · 53 d · \$15900',
        'cuota 6 · 23 d · \$6900',
      ]);
      // Y al descongelar con Mantener, la 7 arranca desde cero ese día.
      final mantenida = MoraCongelada.de(_id).mantener(dia: _nov2);
      MoraCongelada.poner(_id, mantenida);
      expect(_renglones(_perez(), DateTime(2026, 11, 5)).last, 'cuota 7 · 3 d · \$900');
    });

    test('la cuota próxima (la del estado de la fila) también se congela', () {
      MoraCongelada.poner(_id, MoraCongelada.nada.congelar(cuotas: {4}, dia: _oct23));
      final r = MoraCuotaCalculator.calcular(_perez(), _nov2);
      expect(r.proximaCuotaNumero, 4);
      expect(r.diasMora, 84);
      expect(r.interesAcumulado, closeTo(25200, 0.01));
    });

    test('un repaso a una fecha anterior al congelamiento da lo mismo que sin él', () {
      final sin = _renglones(_perez(), DateTime(2026, 10, 20));
      MoraCongelada.poner(_id, MoraCongelada.nada.congelar(todas: true, dia: _oct23));
      expect(_renglones(_perez(), DateTime(2026, 10, 20)), sin);
    });

    test('una cuota pagada mientras estaba congelada queda como se cobró al recalcular', () {
      // Congela todo el 23/10; el 28/10 paga la cuota 4 (con la mora congelada).
      final congelada = MoraCongelada.nada.congelar(todas: true, dia: _oct23);
      MoraCongelada.poner(_id, congelada);
      final alCobrar = _renglones(_perez(pagadas: 3), DateTime(2026, 10, 28)).first;
      expect(alCobrar, 'cuota 4 · 84 d · \$25200');

      // El 2/11 se recalcula: la 4 ya está pagada (4 pagadas).
      final recalculada = congelada.recalcular(cuotasPagadas: 4, dia: _nov2);
      MoraCongelada.poner(_id, recalculada);
      // El repaso de ese cobro (con la ficha de antes de pagar) da lo mismo...
      expect(_renglones(_perez(pagadas: 3), DateTime(2026, 10, 28)).first, alCobrar);
      // ...y la 5, que se debe, vuelve a la cuenta de siempre.
      expect(_renglones(_perez(pagadas: 4), _nov2).first, 'cuota 5 · 63 d · \$18900');
    });

    // El caso por el que se pidió (23-oct): un alumno que no pagó nada viene a
    // hacer un compromiso y se le congela el precio, con la mora que tenga.
    test('un alumno sin ningún pago que viene a comprometerse: "Todas" deja la mora quieta', () {
      final sinPagos = _perez(pagadas: 0);
      final alComprometerse = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: sinPagos,
        moraCobradaHistorial: 0,
        ahoraAr: _oct23,
      );
      // Cuotas 1 a 6 vencidas al 23/10: 176 + 145 + 115 + 84 + 53 + 23 días.
      expect(alComprometerse, closeTo(300.0 * (176 + 145 + 115 + 84 + 53 + 23), 0.01));

      MoraCongelada.poner(_id, MoraCongelada.nada.congelar(todas: true, dia: _oct23));
      final unMesDespues = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: sinPagos,
        moraCobradaHistorial: 0,
        ahoraAr: DateTime(2026, 11, 23),
      );
      // Igual: ni las vencidas suben ni la del 31/10 empieza a sumar.
      expect(unMesDespues, closeTo(alComprometerse, 0.01));
    });

    // Pedido del usuario (24-oct): "fijate las moras perdonadas, que no
    // resuciten". El perdón es la eximición (`moraExentaHasta`): la cuenta
    // arranca desde ahí, y congelar o recalcular no la toca.
    test('una mora perdonada no resucita al congelar ni al recalcular', () {
      // Perdonó todo hasta el 31/10: las cuotas vencidas cuentan desde ahí.
      final perdonado = ContratoAlumno(
        id: _id,
        eventoId: 'e0000000-0000-4000-8000-000000000001',
        nombreAlumno: 'PÉREZ, JUAN',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 180000,
        cuotasPagadas: 3,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 3),
        moraExentaHasta: DateTime(2026, 10, 31),
      );
      final sinCongelar = _renglones(perdonado, _nov2);
      expect(sinCongelar.first, 'cuota 4 · 2 d · \$600');

      final congelada = MoraCongelada.nada.congelar(todas: true, dia: _oct23);
      MoraCongelada.poner(_id, congelada);
      // Congelada desde antes del perdón: no corre nada.
      expect(_renglones(perdonado, _nov2), isEmpty);

      // Recalcular vuelve a la cuenta con el perdón, no a los 94 días de antes.
      MoraCongelada.poner(_id, congelada.recalcular(cuotasPagadas: 3, dia: _nov2));
      expect(_renglones(perdonado, _nov2), sinCongelar);
    });

    test('la mora a cobrar sale de la misma cuenta', () {
      MoraCongelada.poner(_id, MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: _oct23));
      final total = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: _perez(),
        moraCobradaHistorial: 0,
        ahoraAr: _nov2,
      );
      expect(total, closeTo(25200 + 15900 + 9900 + 600, 0.01));
    });
  });

  group('las pausas', () {
    test('las que se pisan se cuentan una vez', () {
      final m = MoraCongelada([
        PausaMora(cuota: 4, desde: DateTime(2026, 10, 1), hasta: DateTime(2026, 10, 11)),
        PausaMora(desde: DateTime(2026, 10, 5), hasta: DateTime(2026, 10, 15)),
      ]);
      expect(
        m.diasQuietos(cuota: 4, vencimientoEfectivo: DateTime(2026, 7, 31), al: DateTime(2026, 11, 1)),
        14,
      );
      // La 5 solo tiene la de "Todas".
      expect(
        m.diasQuietos(cuota: 5, vencimientoEfectivo: DateTime(2026, 8, 31), al: DateTime(2026, 11, 1)),
        10,
      );
    });

    test('antes de vencer no hay nada que congelar', () {
      final m = MoraCongelada([PausaMora(desde: DateTime(2026, 10, 23))]);
      expect(
        m.diasQuietos(cuota: 7, vencimientoEfectivo: DateTime(2026, 10, 31), al: DateTime(2026, 11, 2)),
        2,
      );
    });

    test('congelar dos veces la misma cuota no duplica', () {
      final una = MoraCongelada.nada.congelar(cuotas: {4}, dia: _oct23);
      final dos = una.congelar(cuotas: {4}, dia: _nov2);
      expect(dos.pausas, hasLength(1));
      expect(dos.cuotasCongeladas, {4});
      expect(dos.desde, _oct23);
    });

    test('Mantener el mismo día que se congeló no deja nada guardado', () {
      final m = MoraCongelada.nada.congelar(cuotas: {4}, dia: _oct23).mantener(cuotas: {4}, dia: _oct23);
      expect(m.vacia, isTrue);
    });

    test('vuelve igual del texto que va a la base', () {
      final m = MoraCongelada([
        PausaMora(cuota: 4, desde: _oct23, hasta: _nov2),
        PausaMora(desde: _nov3),
      ]);
      expect(MoraCongelada.fromJson(m.toJson()).pausas, m.pausas);
      expect(MoraCongelada.fromJson(null).vacia, isTrue);
      expect(MoraCongelada.fromJson('').vacia, isTrue);
    });

    test('el aviso: qué está congelado hoy', () {
      final m = MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: _oct23);
      expect(m.congeladaHoy(4), isTrue);
      expect(m.congeladaHoy(6), isFalse);
      expect(m.todasCongeladas, isFalse);
      final t = MoraCongelada.nada.congelar(todas: true, dia: _oct23);
      expect(t.congeladaHoy(9), isTrue);
      expect(t.todasCongeladas, isTrue);
    });

    test('el registro vacío no cambia nada', () {
      expect(MoraCongelada.de(_id).vacia, isTrue);
      MoraCongelada.cargar({_id: MoraCongelada.nada});
      expect(MoraCongelada.de(_id).vacia, isTrue);
    });
  });
}
