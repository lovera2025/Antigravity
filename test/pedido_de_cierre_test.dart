// El cierre de una caja de barra con el OK de la encargada (11-nov-2026): la regla, sin
// pantalla ni base. La cajera pide cerrar, la encargada acepta o pide que cuente de
// nuevo, y la caja la cierra la tablet de la cajera.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/pedido_de_cierre.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';

void main() {
  final abrio = DateTime.utc(2026, 12, 5, 1);
  final pidio = DateTime.utc(2026, 12, 5, 8);

  CajaBarra caja(int numero) => CajaBarra.abrir(
        eventoId: _evento,
        operadorNombre: 'Caja $numero',
        numeroCaja: numero,
        cambioInicial: 20000,
        ahora: abrio,
      );

  PasoDelCierre pedir(CajaBarra c, {double contado = 27000, DateTime? cuando, String? nota}) =>
      PasoDelCierre.pedir(
        caja: c,
        efectivoContado: contado,
        nota: nota,
        hechoPor: c.operadorNombre,
        ahora: cuando ?? pidio,
      );

  PasoDelCierre responder(
    PasoDelCierre pedido,
    TipoPasoDelCierre tipo, {
    DateTime? cuando,
    String quien = 'Romi',
    String? nota,
  }) =>
      PasoDelCierre.responder(
        pedido: pedido,
        tipo: tipo,
        nota: nota,
        hechoPor: quien,
        ahora: cuando ?? pidio.add(const Duration(minutes: 1)),
      );

  group('en qué está el cierre de una caja', () {
    test('sin pedido, nada', () {
      final e = PedidoDeCierre.de(caja(2).id, const []);
      expect(e.pedido, isNull);
      expect(e.esperando, isFalse);
      expect(e.aceptado, isFalse);
    });

    test('pidió cerrar: espera a la encargada, con lo que contó', () {
      final c = caja(2);
      final p = pedir(c, contado: 26500, nota: 'faltó un billete');
      final e = PedidoDeCierre.de(c.id, [p]);
      expect(e.esperando, isTrue);
      expect(e.pedido!.efectivoContado, 26500);
      expect(e.pedido!.nota, 'faltó un billete');
      expect(e.pedido!.tipo, TipoPasoDelCierre.pedido);
    });

    test('la encargada aceptó', () {
      final c = caja(2);
      final p = pedir(c);
      final e = PedidoDeCierre.de(c.id, [p, responder(p, TipoPasoDelCierre.ok)]);
      expect(e.esperando, isFalse);
      expect(e.aceptado, isTrue);
      expect(e.respuesta!.hechoPor, 'Romi');
    });

    test('la encargada pide que cuente de nuevo; el pedido nuevo vuelve a esperar', () {
      final c = caja(2);
      final p1 = pedir(c);
      final no = responder(p1, TipoPasoDelCierre.recontar);
      expect(PedidoDeCierre.de(c.id, [p1, no]).hayQueRecontar, isTrue);
      final p2 = pedir(c, contado: 27500, cuando: pidio.add(const Duration(minutes: 5)));
      final e = PedidoDeCierre.de(c.id, [p1, no, p2]);
      expect(e.esperando, isTrue, reason: 'manda el último pedido');
      expect(e.pedido!.efectivoContado, 27500);
    });

    test('la respuesta de un pedido viejo no contesta el nuevo', () {
      final c = caja(2);
      final p1 = pedir(c);
      final cancelo = responder(p1, TipoPasoDelCierre.cancelado, quien: 'Caja 2');
      final p2 = pedir(c, cuando: pidio.add(const Duration(minutes: 5)));
      // El ok al primero llega tarde: el segundo sigue esperando.
      final okViejo = responder(p1, TipoPasoDelCierre.ok);
      expect(PedidoDeCierre.de(c.id, [p1, cancelo, p2, okViejo]).esperando, isTrue);
    });

    test('si la cajera volvió a vender, el ok que llegó al mismo tiempo no cierra', () {
      final c = caja(2);
      final p = pedir(c);
      final ok = responder(p, TipoPasoDelCierre.ok);
      final cancelo = responder(p, TipoPasoDelCierre.cancelado,
          quien: 'Caja 2', cuando: pidio.add(const Duration(minutes: 2)));
      final e = PedidoDeCierre.de(c.id, [p, ok, cancelo]);
      expect(e.aceptado, isFalse);
      expect(e.respuesta!.tipo, TipoPasoDelCierre.cancelado);
    });

    test('dos respuestas de la encargada: vale la primera', () {
      final c = caja(2);
      final p = pedir(c);
      final no = responder(p, TipoPasoDelCierre.recontar, cuando: pidio.add(const Duration(seconds: 30)));
      final si = responder(p, TipoPasoDelCierre.ok, cuando: pidio.add(const Duration(seconds: 50)));
      expect(PedidoDeCierre.de(c.id, [p, si, no]).hayQueRecontar, isTrue);
    });

    test('los relojes de las tablets no coinciden: el ok vale aunque diga una hora anterior', () {
      final c = caja(2);
      final p = pedir(c);
      final ok = responder(p, TipoPasoDelCierre.ok, cuando: pidio.subtract(const Duration(minutes: 7)));
      expect(PedidoDeCierre.de(c.id, [p, ok]).aceptado, isTrue);
    });

    test('una fila de un tipo que esta versión no conoce no contesta nada', () {
      final c = caja(2);
      final p = pedir(c);
      final rara = PasoDelCierre.fromMap(
        responder(p, TipoPasoDelCierre.ok).toMap()..['tipo'] = 'algo_nuevo',
      );
      expect(rara.tipo, isNull);
      expect(PedidoDeCierre.de(c.id, [p, rara]).esperando, isTrue);
    });

    test('lo de otra caja no entra', () {
      final dos = caja(2);
      final tres = caja(3);
      final p = pedir(tres);
      expect(PedidoDeCierre.de(dos.id, [p, responder(p, TipoPasoDelCierre.ok)]).pedido, isNull);
    });
  });

  group('lo que le salta a la encargada', () {
    test('los pedidos en pie de las cajas abiertas, por número de caja', () {
      final uno = caja(1);
      final dos = caja(2);
      final tres = caja(3);
      final cuatro = caja(4);
      final cerrada = cuatro.cerrada(efectivoContado: 20000, diferencia: 0, ahora: pidio);
      final p3 = pedir(tres);
      final p1 = pedir(uno);
      final p2 = pedir(dos);
      final p4 = pedir(cuatro);
      final enPie = PedidoDeCierre.enPie(
        [tres, cerrada, dos, uno],
        [p3, p1, p2, p4, responder(p2, TipoPasoDelCierre.ok)],
      );
      // La 2 ya tiene su ok, y la 4 ya cerró.
      expect([for (final e in enPie) e.caja.numeroCaja], [1, 3]);
      expect(enPie.first.pedido.id, p1.id);
    });

    test('las que cerraron sin el OK, para que el jefe las mire', () {
      final dos = caja(2);
      final tres = caja(3);
      final p2 = pedir(dos);
      final p3 = pedir(tres);
      final sinOk = responder(p2, TipoPasoDelCierre.sinOk, quien: 'Caja 2', nota: 'no había encargada');
      expect(
        PedidoDeCierre.cerraronSinOk([p2, p3, sinOk, responder(p3, TipoPasoDelCierre.ok)]),
        {dos.id},
      );
    });
  });

  group('cerrar sin esperar', () {
    test('recién a los 3 minutos, por el reloj de la tablet que pidió', () {
      final p = pedir(caja(2));
      expect(kEsperaDelOkDeCierre, const Duration(minutes: 3));
      expect(PedidoDeCierre.yaPuedeCerrarSinEsperar(p, pidio.add(const Duration(seconds: 179))), isFalse);
      expect(PedidoDeCierre.yaPuedeCerrarSinEsperar(p, pidio.add(const Duration(minutes: 3))), isTrue);
      expect(
        PedidoDeCierre.faltaParaCerrarSinEsperar(p, pidio.add(const Duration(minutes: 1))),
        const Duration(minutes: 2),
      );
      expect(
        PedidoDeCierre.faltaParaCerrarSinEsperar(p, pidio.add(const Duration(minutes: 9))),
        Duration.zero,
      );
    });
  });

  group('lo que queda escrito en la caja', () {
    test('quién aceptó, con la nota de la cajera adelante', () {
      expect(
        PedidoDeCierre.notaConElOk(notaDeLaCajera: ' faltó un billete ', acepto: 'Romi'),
        'faltó un billete · Aceptó: Romi',
      );
      expect(PedidoDeCierre.notaConElOk(acepto: 'Romi'), 'Aceptó: Romi');
      expect(PedidoDeCierre.notaConElOk(acepto: ' '), 'Aceptó: la encargada');
    });

    test('que cerró sin el OK, con el motivo', () {
      expect(
        PedidoDeCierre.notaSinElOk(motivo: 'no había encargada esta noche'),
        'Cerró sin el OK de la encargada: no había encargada esta noche',
      );
    });
  });

  group('un paso que no cierra es un error del programa', () {
    test('una respuesta no es otro pedido, y solo se contesta un pedido', () {
      final p = pedir(caja(2));
      expect(() => responder(p, TipoPasoDelCierre.pedido), throwsArgumentError);
      final ok = responder(p, TipoPasoDelCierre.ok);
      expect(() => responder(ok, TipoPasoDelCierre.recontar), throwsArgumentError);
      expect(() => pedir(caja(2), contado: -1), throwsArgumentError);
    });
  });
}
