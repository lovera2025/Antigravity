// El día de operación de la barra (25-nov-2026): la noche de cada caja, con el corte al
// mediodía en hora de Argentina, y todas las cuentas de una noche sin las cajas de prueba
// de otro día. Sin pantalla ni base.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/dia_de_operacion.dart';
import 'package:arguello_events/features/barra/cuentas/stock_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/vales_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/modelo_ticket.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/services/barras_del_salon.dart';
import 'package:arguello_events/features/barra/services/fiestas_de_la_barra.dart';
import 'package:arguello_events/features/barra/services/fiestas_del_jefe.dart';
import 'package:arguello_events/features/recepcion/services/vales_anulados.dart';

import 'helpers/barra_en_memoria.dart' show fiestaDePrueba;

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

/// Un momento en hora de Argentina (UTC-3), como lo vería la cajera en el reloj.
DateTime ar(int anio, int mes, int dia, [int hora = 0, int minuto = 0]) =>
    DateTime.utc(anio, mes, dia, hora + 3, minuto);

CajaBarra caja(int numero, DateTime abierta, {String? sede}) =>
    CajaBarra.abrir(eventoId: _fiesta, numeroCaja: numero, sede: sede, ahora: abierta);

const _fernet = 'p-fernet';
const _cerveza = 'p-cerveza';

VentaBarra venta(CajaBarra c, int numero, DateTime cuando, {String producto = _fernet, int cantidad = 1, double precio = 6000}) =>
    VentaBarra.nueva(
      cajaBarraId: c.id,
      eventoId: _fiesta,
      numero: numero,
      renglones: [RenglonVenta(productoId: producto, nombre: producto, precio: precio, cantidad: cantidad)],
      medio: MedioBarra.efectivo,
      efectivo: precio * cantidad,
      ahora: cuando,
    );

void main() {
  group('DiaDeOperacion: la noche de un momento', () {
    test('el mediodía es el corte: a las 11:59 sigue la noche anterior, a las 12 empieza la nueva', () {
      expect(DiaDeOperacion.de(ar(2026, 12, 5, 11, 59)), const DiaDeOperacion(2026, 12, 4));
      expect(DiaDeOperacion.de(ar(2026, 12, 5, 12)), const DiaDeOperacion(2026, 12, 5));
    });

    test('la medianoche no corta: la caja de la tarde sigue hasta las 8 de la mañana', () {
      for (final hora in [18, 21, 23]) {
        expect(DiaDeOperacion.de(ar(2026, 12, 4, hora, 59)), const DiaDeOperacion(2026, 12, 4), reason: '$hora');
      }
      for (final hora in [0, 1, 5, 8]) {
        expect(DiaDeOperacion.de(ar(2026, 12, 5, hora, 30)), const DiaDeOperacion(2026, 12, 4), reason: '$hora');
      }
    });

    test('el cambio de mes y de año', () {
      expect(DiaDeOperacion.de(ar(2026, 12, 1, 3)), const DiaDeOperacion(2026, 11, 30));
      expect(DiaDeOperacion.de(ar(2026, 11, 30, 22)), const DiaDeOperacion(2026, 11, 30));
      expect(DiaDeOperacion.de(ar(2027, 1, 1, 6)), const DiaDeOperacion(2026, 12, 31));
      expect(DiaDeOperacion.de(ar(2027, 3, 1, 2)), const DiaDeOperacion(2027, 2, 28));
      expect(const DiaDeOperacion(2026, 11, 30).siguiente, const DiaDeOperacion(2026, 12, 1));
      expect(const DiaDeOperacion(2026, 12, 31).siguiente, const DiaDeOperacion(2027, 1, 1));
    });

    test('en hora de Argentina, venga el momento en la zona que venga', () {
      // Las 02:00 UTC del 5 son las 23:00 del 4 en Argentina; las 15:00 UTC, el mediodía.
      expect(DiaDeOperacion.de(DateTime.utc(2026, 12, 5, 2)), const DiaDeOperacion(2026, 12, 4));
      expect(DiaDeOperacion.de(DateTime.utc(2026, 12, 5, 14, 59)), const DiaDeOperacion(2026, 12, 4));
      expect(DiaDeOperacion.de(DateTime.utc(2026, 12, 5, 15)), const DiaDeOperacion(2026, 12, 5));
      expect(DiaDeOperacion.deIso('2026-12-05T04:30:00.000Z'), const DiaDeOperacion(2026, 12, 4));
      expect(DiaDeOperacion.deIso('2026-12-05T01:30:00-03:00'), const DiaDeOperacion(2026, 12, 4));
    });

    test('la noche de una caja es la de cuando se abrió; sin fecha que se entienda, va aparte', () {
      expect(DiaDeOperacion.deLaCaja(caja(1, ar(2026, 12, 4, 18))), const DiaDeOperacion(2026, 12, 4));
      final rara = CajaBarra.fromMap({'id': 'x', 'evento_id': _fiesta, 'numero_caja': 1, 'abierta_at': 'ayer'});
      expect(DiaDeOperacion.deLaCaja(rara), DiaDeOperacion.sinFecha);
      expect(DiaDeOperacion.sinFecha.corto, 'Sin fecha');
    });

    test('cómo se dice', () {
      const d = DiaDeOperacion(2026, 12, 4);
      expect(d.diaYMes, '4/12');
      expect(d.corto, 'Vie 04/12');
      expect(d.conDiaDeLaSemana, 'Vie 04/12/2026');
      expect(d.largo, 'viernes 4 de diciembre');
      expect(DiaDeOperacion.delCalendario(DateTime(2026, 12, 4, 22)), d);
    });
  });

  group('CajasPorDia: las cajas de la fiesta, separadas por noche', () {
    final prueba1 = caja(1, ar(2026, 11, 20, 19));
    final prueba2 = caja(2, ar(2026, 11, 20, 19, 30));
    final noche1 = caja(1, ar(2026, 12, 4, 18));
    final noche2 = caja(2, ar(2026, 12, 4, 18, 10));
    final porDia = CajasPorDia.de([noche2, prueba1, noche1, prueba2]);

    test('los días, del más viejo al más nuevo, y las cajas de cada uno', () {
      expect(porDia.dias, [const DiaDeOperacion(2026, 11, 20), const DiaDeOperacion(2026, 12, 4)]);
      expect(porDia.idsDelDia(const DiaDeOperacion(2026, 12, 4)), {noche1.id, noche2.id});
      expect(porDia.idsDelDia(const DiaDeOperacion(2026, 11, 20)), {prueba1.id, prueba2.id});
      expect(porDia.delDia(const DiaDeOperacion(2026, 12, 5)), isEmpty);
    });

    test('las ventas van con su caja, aunque sean de madrugada o pasado el mediodía', () {
      final deMadrugada = venta(noche1, 40, ar(2026, 12, 5, 4, 30));
      final pasadoElMediodia = venta(noche1, 41, ar(2026, 12, 5, 12, 30));
      expect(porDia.diaDeLaVenta(deMadrugada), const DiaDeOperacion(2026, 12, 4));
      expect(porDia.diaDeLaVenta(pasadoElMediodia), const DiaDeOperacion(2026, 12, 4),
          reason: 'la caja abrió el 4: la venta es de esa noche');
      // Una venta cuya caja todavía no llegó a este equipo: la noche de su hora.
      final huerfana = venta(caja(9, ar(2026, 12, 4, 20)), 1, ar(2026, 12, 5, 1));
      expect(porDia.diaDeLaVenta(huerfana), const DiaDeOperacion(2026, 12, 4));
    });

    test('con qué noche se abre: esta noche, o la última con cajas', () {
      expect(porDia.inicial(ahora: ar(2026, 12, 5, 2)), const DiaDeOperacion(2026, 12, 4));
      expect(porDia.inicial(ahora: ar(2026, 12, 10, 15)), const DiaDeOperacion(2026, 12, 4),
          reason: 'días después: la última con cajas');
      expect(porDia.inicial(ahora: ar(2026, 11, 25, 15)), const DiaDeOperacion(2026, 12, 4),
          reason: 'cajas "de después" (un reloj corrido): esas son las de ahora');
    });

    test('la noche de la fiesta, antes de abrir la primera caja, se ve vacía: no con las de prueba', () {
      final soloPrueba = CajasPorDia.de([prueba1, prueba2]);
      expect(
        soloPrueba.inicial(ahora: ar(2026, 12, 4, 17), fechaDeLaFiesta: DateTime(2026, 12, 4, 22)),
        const DiaDeOperacion(2026, 12, 4),
      );
      expect(soloPrueba.inicial(ahora: ar(2026, 11, 25, 17)), const DiaDeOperacion(2026, 11, 20),
          reason: 'otro día cualquiera: la última con cajas');
      expect(CajasPorDia.de(const []).inicial(ahora: ar(2026, 11, 25, 17)), const DiaDeOperacion(2026, 11, 25));
    });

    test('el día preferido (el del cierre de caja) manda si tuvo cajas', () {
      expect(porDia.inicial(ahora: ar(2026, 12, 5, 2), preferido: const DiaDeOperacion(2026, 11, 20)),
          const DiaDeOperacion(2026, 11, 20));
      expect(porDia.inicial(ahora: ar(2026, 12, 5, 9), preferido: const DiaDeOperacion(2026, 12, 5)),
          const DiaDeOperacion(2026, 12, 4), reason: 'el cierre de la mañana: la de anoche');
    });

    test('al abrir otra caja, avisa solo por las abiertas de esta noche', () {
      final abiertas = abiertasDeEstaNoche([prueba1, noche2], ar(2026, 12, 4, 20));
      expect(abiertas.map((c) => c.id), [noche2.id], reason: 'la Caja 1 de prueba del 20/11 no avisa');
    });

    test('la fiesta sigue a la vista mientras queden cajas abiertas de su noche', () {
      final fecha = DateTime(2026, 12, 4, 22);
      expect(quedanCajasDeSuNoche([prueba1, noche1], fecha), isTrue);
      final cerrada = noche1.cerrada(efectivoContado: 0, diferencia: 0, ahora: ar(2026, 12, 5, 7));
      expect(quedanCajasDeSuNoche([prueba1, cerrada], fecha), isFalse,
          reason: 'una caja de prueba de otro día que quedó abierta no cuenta');
    });
  });

  group('las cuentas de una noche, con cajas de dos días', () {
    // La noche de prueba del 20/11: la Caja 1 vendió 5 fernets, se cerró con $ 1.000 de más.
    final prueba = caja(1, ar(2026, 11, 20, 19));
    final ventasPrueba = [venta(prueba, 1, ar(2026, 11, 20, 20), cantidad: 5)];
    final pruebaCerrada = prueba.cerrada(efectivoContado: 31000, diferencia: 1000, ahora: ar(2026, 11, 20, 23));
    // La noche de la fiesta: la Caja 1 (otra, con el mismo número) y la Caja 2.
    final c1 = caja(1, ar(2026, 12, 4, 18));
    final c2 = caja(2, ar(2026, 12, 4, 18, 10));
    final ventasFiesta = [
      venta(c1, 1, ar(2026, 12, 4, 23), cantidad: 2),
      venta(c1, 2, ar(2026, 12, 5, 2, 30), cantidad: 1), // de madrugada
      venta(c2, 1, ar(2026, 12, 5, 6), producto: _cerveza, precio: 3500, cantidad: 4),
    ];
    final c2Cerrada = c2.cerrada(efectivoContado: 13500, diferencia: -500, ahora: ar(2026, 12, 5, 7));
    final cajas = [pruebaCerrada, c1, c2Cerrada];
    final ventas = [...ventasPrueba, ...ventasFiesta];
    final precios = [
      PrecioBarra.para(eventoId: _fiesta, productoId: _fernet, precio: 6000, stockInicial: 10, avisoStock: 2, ahora: ar(2026, 11, 1)),
      PrecioBarra.para(eventoId: _fiesta, productoId: _cerveza, precio: 3500, stockInicial: 24, ahora: ar(2026, 11, 1)),
    ];
    final datos = CajasDeLaFiesta(
      eventoId: _fiesta,
      porDia: CajasPorDia.de(cajas),
      ventas: ventas,
      anulaciones: const [],
      vales: const [],
      precios: precios,
      nombres: const {_fernet: 'Fernet', _cerveza: 'Cerveza'},
      categorias: const {_fernet: 'Tragos', _cerveza: 'Cervezas'},
    );
    const fiesta = DiaDeOperacion(2026, 12, 4);
    const pruebaDia = DiaDeOperacion(2026, 11, 20);

    test('TOTAL VENDIDO, VENTAS y CAJAS: solo las de esa noche', () {
      final r = datos.delDia(fiesta).resumen;
      expect(r.dia, fiesta);
      expect(r.cajas.map((x) => x.caja.id), [c1.id, c2.id]);
      expect(r.ventas, 3);
      expect(r.total, 6000 * 3 + 3500 * 4.0);
      expect(r.abiertas, 1);
      final p = datos.delDia(pruebaDia).resumen;
      expect(p.ventas, 1);
      expect(p.total, 30000);
    });

    test('la DIFERENCIA de la noche no suma la de la prueba', () {
      expect(datos.delDia(fiesta).resumen.diferencia, -500);
      expect(datos.delDia(pruebaDia).resumen.diferencia, 1000);
    });

    test('LO VENDIDO DE LA FIESTA: las bebidas de esa noche, y el papel dice de qué noche', () {
      final cuentas = datos.delDia(fiesta).resumen.deLaFiesta!;
      expect({for (final p in cuentas.porProducto) p.productoId: p.unidades}, {_fernet: 3, _cerveza: 4});
      final papel = ModeloTicket.deLoVendido(cuentas, fiesta: 'TÉCNICA', cajas: 2, ahora: ar(2026, 12, 5, 8), dia: fiesta);
      expect([for (final l in papel) if (l is TextoTicket) l.texto], contains('Las 2 cajas del 4/12'));
    });

    test('el STOCK de la noche descuenta solo lo vendido esa noche', () {
      final stock = {for (final s in datos.delDia(fiesta).stock) s.stock.productoId: s.stock};
      expect(stock[_fernet]!.vendido, 3, reason: 'sin los 5 de la prueba');
      expect(stock[_fernet]!.queda, 7);
      expect(stock[_cerveza]!.queda, 20);
      final deLaPrueba = StockDeLaBarra.deLaNoche(
        eventoId: _fiesta,
        precios: precios,
        ventas: ventas,
        anulaciones: const [],
        cajas: datos.porDia,
        dia: pruebaDia,
      );
      expect(deLaPrueba[_fernet]!.vendido, 5);
    });

    test('el vale de madrugada dice el día de la fiesta, no el del reloj', () {
      final v = ventasFiesta[1];
      final papel = ModeloTicket.deVale(
        const Vale(bebidas: [BebidaDelVale(1, 'Fernet')], porSeparado: false),
        venta: v,
        caja: c1,
        fiesta: 'TÉCNICA',
      );
      final textos = [for (final l in papel) if (l is TextoTicket) l.texto];
      expect(textos, contains('Vie 04/12/2026 - 02:30'));
      expect(textos.any((t) => t.contains('Sáb 05/12')), isFalse);
    });
  });

  test('los vales anulados de la puerta: dos "Caja 1" de días distintos no se confunden', () {
    final prueba = caja(1, ar(2026, 11, 20, 19));
    final fiesta = caja(1, ar(2026, 12, 4, 18));
    final v17Prueba = venta(prueba, 17, ar(2026, 11, 20, 21));
    final v17Fiesta = venta(fiesta, 17, ar(2026, 12, 5, 1));
    final anuladaPrueba = AnulacionBarra.de(v17Prueba, motivo: 'prueba', ahora: ar(2026, 11, 20, 22));
    // Antes: la Caja 1 N° 17 anulada en la prueba y la de la fiesta sin anular → "no se sabe".
    final enLaFiesta = ValesAnulados.de(
      cajas: [prueba, fiesta],
      ventas: [v17Prueba, v17Fiesta],
      anulaciones: [anuladaPrueba],
      ahora: ar(2026, 12, 5, 2),
    );
    expect(enLaFiesta.estaAnulado('1-17'), isFalse, reason: 'la de esta noche no se anuló');
    // Y si la de la fiesta se anula, se marca aunque la de prueba no lo esté.
    final anuladaFiesta = AnulacionBarra.de(v17Fiesta, motivo: 'se cobró dos veces', ahora: ar(2026, 12, 5, 2));
    final soloLaFiesta = ValesAnulados.de(
      cajas: [prueba, fiesta],
      ventas: [v17Prueba, v17Fiesta],
      anulaciones: [anuladaFiesta],
      ahora: ar(2026, 12, 5, 3),
    );
    expect(soloLaFiesta.estaAnulado('1-17'), isTrue);
  });

  group('la madrugada y dos noches seguidas', () {
    final viernes = fiestaDePrueba('e0000000-0000-4000-8000-000000000011', 'VIERNES', DateTime(2026, 12, 4, 22));
    final sabado = fiestaDePrueba('e0000000-0000-4000-8000-000000000012', 'SÁBADO', DateTime(2026, 12, 5, 22));

    test('BARRA del jefe abre en la fiesta de esta noche, no en la de anoche', () {
      expect(FiestasDelJefe.de([viernes, sabado], ar(2026, 12, 5, 20)).laQueAbre?.id, sabado.id);
      expect(FiestasDelJefe.de([viernes, sabado], ar(2026, 12, 5, 9)).laQueAbre?.id, viernes.id,
          reason: 'a la mañana, la de anoche');
    });

    test('la fiesta que ya pasó sigue en la lista de la barra mientras haya cajas de su noche', () {
      final ahora = ar(2026, 12, 5, 14);
      expect(fiestasParaLaBarra([viernes, sabado], {viernes.id, sabado.id}, ahora).map((e) => e.id), [sabado.id]);
      expect(
        fiestasParaLaBarra([viernes, sabado], {viernes.id, sabado.id}, ahora, conCajaAbierta: {viernes.id})
            .map((e) => e.id),
        [sabado.id, viernes.id],
        reason: 'la de anoche va al final',
      );
    });

    test('la central vuelve sola: la misma noche, la de la fiesta, o con cajas abiertas de esa noche', () {
      final guardada = CentralGuardada(eventoId: _fiesta, desde: ar(2026, 12, 4, 17), barra: 'Barra 1');
      expect(sigueLaNoche(guardada: guardada, ahora: ar(2026, 12, 5, 7)), isTrue, reason: 'de madrugada');
      expect(sigueLaNoche(guardada: guardada, ahora: ar(2026, 12, 5, 13)), isFalse,
          reason: 'pasado el mediodía, sin cajas abiertas');
      final abierta = caja(1, ar(2026, 12, 4, 18));
      expect(sigueLaNoche(guardada: guardada, ahora: ar(2026, 12, 5, 13), cajas: [abierta]), isTrue,
          reason: 'la caja de esa noche sigue abierta pasado el mediodía');
      expect(
        sigueLaNoche(guardada: guardada, ahora: ar(2026, 12, 5, 13), cajas: [caja(1, ar(2026, 11, 20, 19))]),
        isFalse,
        reason: 'una de prueba de otra noche no la trae',
      );
      final deLaManana = CentralGuardada(eventoId: _fiesta, desde: ar(2026, 12, 4, 11));
      expect(sigueLaNoche(guardada: deLaManana, ahora: ar(2026, 12, 4, 19), fechaDeLaFiesta: DateTime(2026, 12, 4)),
          isTrue, reason: 'prendida para probar a la mañana: vuelve la noche de la fiesta');
    });
  });

  group('una central por barra', () {
    test('la barra se lee de la sede, como sea que esté escrita', () {
      expect(barraDe('Barra 1'), 'Barra 1');
      expect(barraDe(' barra 2 '), 'Barra 2');
      expect(barraDe('Barra del fondo'), isNull);
      expect(barraDe(null), isNull);
    });

    test('la caja se engancha a la de su barra; a la otra, solo si la suya no aparece', () {
      const eleccion = EleccionDeCentral.deLaCaja(barra: 'Barra 2');
      const b1 = DondeEstaLaCentral('192.168.0.10', 8797, barra: 'Barra 1', equipo: 'nb1');
      const b2 = DondeEstaLaCentral('192.168.0.11', 8797, barra: 'Barra 2', equipo: 'nb2');
      const vieja = DondeEstaLaCentral('192.168.0.12', 8797);
      expect(eleccion.sirve(b2, buscando: Duration.zero), isTrue);
      expect(eleccion.sirve(b1, buscando: const Duration(seconds: 3)), isFalse);
      expect(eleccion.sirve(b1, buscando: const Duration(seconds: 11)), isTrue,
          reason: 'la notebook de su barra no aparece: la otra se pasa todo con ella');
      expect(eleccion.sirve(vieja, buscando: Duration.zero), isTrue, reason: 'una central de antes, sin barra');
      expect(const EleccionDeCentral.deLaCaja().sirve(b1, buscando: Duration.zero), isTrue,
          reason: 'la encargada, sin barra, toma cualquiera');
    });

    test('entre centrales: nunca consigo misma, y de cada par se engancha una sola', () {
      const nb1 = DondeEstaLaCentral('192.168.0.10', 8797, barra: 'Barra 1', equipo: 'a-notebook');
      const nb2 = DondeEstaLaCentral('192.168.0.11', 8797, barra: 'Barra 2', equipo: 'b-notebook');
      expect(const EleccionDeCentral.otraCentral('a-notebook').sirve(nb1, buscando: Duration.zero), isFalse);
      expect(const EleccionDeCentral.otraCentral('a-notebook').sirve(nb2, buscando: Duration.zero), isTrue);
      expect(const EleccionDeCentral.otraCentral('b-notebook').sirve(nb1, buscando: Duration.zero), isFalse,
          reason: 'la otra punta no se engancha también: un solo camino');
      expect(
        const EleccionDeCentral.otraCentral('a-notebook')
            .sirve(const DondeEstaLaCentral('192.168.0.12', 8797), buscando: Duration.zero),
        isFalse,
        reason: 'una central sin id (de antes) no sabe engancharse',
      );
    });
  });
}
