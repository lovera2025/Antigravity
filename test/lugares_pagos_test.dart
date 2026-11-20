// A PAGAR por cosa pagada (regla del usuario, 20-nov-2026): cada mesa adicional
// cuyo precio está pago entero habilita sus entradas aunque la familia deba otra
// cosa; la que no, no se vende ("a confirmar: falta pagarla en caja"). Las
// sillas extra igual, silla por silla. Vale para lo que tenía al sorteo (con
// descuento) y para lo agregado después (sin descuento, al precio del día). Y lo
// sin descuento se cuenta sin cobrar dos veces: menos las sueltas a su nombre y
// menos lo comprado de más con descuento en la 6.9.0 y la 6.9.1.
//
// Todo puro: sin pantalla, sin base, sin reloj. Qué está pago sale de los pagos,
// nunca de los campos del contrato.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/entradas/cuentas/lugares_de_la_familia.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/eventos/services/adicional_a_confirmar.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/services/lugares_pagos.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _id = 'c0000000-0000-4000-8000-000000000001';
const _otra = 'c0000000-0000-4000-8000-000000000002';

final _ahora = DateTime.utc(2026, 11, 20, 15);
final _hoy = DateTime.utc(2026, 11, 20, 12);

const _mesa = 70000.0;
const _silla = 8000.0;

/// Un alumno con [extras] mesas adicionales de $70.000 y [sillas] sillas extra
/// de $8.000, con [acompanantes] acompañantes. [saldo] es lo que dice la ficha.
ContratoAlumno _alumno({
  String id = _id,
  int extras = 0,
  int sillas = 0,
  int acompanantes = 0,
  double saldo = 0,
  bool conMesas = true,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _fiesta,
      nombreAlumno: 'ALUMNO, DE PRUEBA',
      cantidadAcompanantes: acompanantes,
      montoTotalPactado: 300000 + _mesa * extras + _silla * sillas,
      saldoDeudor: saldo,
      totalCuotas: 9,
      cuotasPagadas: 9,
      mesaExtraPrecio: _mesa * extras,
      mesaExtraCantidad: extras,
      mesaExtraCuotas: 1,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: _silla * sillas,
      sillasExtraCuotas: 1,
      numeroMesa: conMesas
          ? MesasExtraUtils.formatearAsignacionMesas(
              [for (var i = 0; i <= extras; i++) 12 + i])
          : null,
      createdAt: DateTime(2026, 2, 1),
    );

Map<String, dynamic> _pago(double monto, String concepto, {int anulado = 0}) => {
      'contrato_alumno_id': _id,
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'anulado': anulado,
    };

/// Los pagos: la base entera salvo [base], y lo de las mesas y las sillas.
List<Map<String, dynamic>> _pagos({
  double base = 300000,
  double mesas = 0,
  double sillas = 0,
}) =>
    [
      if (base > 0) _pago(base, 'Cuota Base (9/9)'),
      if (mesas > 0) _pago(mesas, 'Mesa Extra 1'),
      if (sillas > 0) _pago(sillas, 'Sillas extra (1/1)'),
    ];

/// Lo que la familia [id] tenía al sorteo: [mesas] (con la del contrato) y
/// [sillas].
FotoDeLosLugares _alSorteo(int mesas, int sillas, {String id = _id}) =>
    FotoDeLosLugares.anotada({id: LugaresCargados(mesas, sillas)});

VentaEntradas _vendida({
  String? familia = _id,
  int deLugar = 0,
  int sueltas = 0,
}) =>
    VentaEntradas.nueva(
      cajaEntradasId: 'caja',
      eventoId: _fiesta,
      numero: 1,
      contratoAlumnoId: familia,
      compradorNombre: 'COMPRADORA, UNA',
      renglones: [
        if (deLugar > 0)
          RenglonEntradas.lugar(
            nombre: 'Entrada de lugar adicional (50 %)',
            precioLista: 10000,
            descuentoPct: 50,
            cantidad: deLugar,
          ),
        if (sueltas > 0)
          RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: sueltas),
      ],
      medio: MedioBarra.efectivo,
      efectivo: 5000.0 * deLugar + 10000.0 * sueltas,
      ahora: _ahora,
    );

LugaresDeLaFamilia _lugares(
  ContratoAlumno a, {
  required Iterable<Map<String, dynamic>>? pagos,
  FotoDeLosLugares? foto,
  List<VentaEntradas> ventas = const [],
  List<AnulacionEntradas> anulaciones = const [],
}) =>
    LugaresDeLaFamilia.de(
      a,
      ventas: ventas,
      anulaciones: anulaciones,
      aPagar: APagarDeLaFamilia.de(a, pagos: pagos, foto: foto),
    );

ConfigEntradas _config({double? anticipada, String? hasta}) =>
    ConfigEntradas.vacia(_fiesta, ahora: _ahora).conPrecios(
      valorEntrada: 10000,
      precioAnticipada: anticipada,
      anticipadaHasta: hasta,
      descuentoLugaresPct: 50,
      recargoPct: 0,
      descuentoAMano: false,
    );

PedidoDeEntradas _pedidoDe(LugaresDeLaFamilia l, {ConfigEntradas? config}) =>
    PedidoDeEntradas.nuevo(config: config ?? _config(), hoyAr: _hoy)
        .paraLaFamilia(_id, l)
        .conComprador('COMPRADORA, UNA');

void main() {
  group('una sola cuenta', () {
    test('las entradas de cada línea suman lo mismo que la entrega', () {
      for (final extras in [0, 1, 2, 3]) {
        for (final sillas in [0, 1, 3]) {
          for (final acompanantes in [0, 2, 9, 17]) {
            for (final foto in [null, _alSorteo(2, 1), _alSorteo(1, 0)]) {
              final a = _alumno(extras: extras, sillas: sillas, acompanantes: acompanantes);
              final e = RetiroEntradas.entradasDe(a, foto: foto);
              final p = APagarDeLaFamilia.de(a, pagos: _pagos(), foto: foto);
              final caso = 'extras $extras, sillas $sillas, acomp. $acompanantes, foto $foto';
              expect(p.conDescuento, e.conDescuento, reason: caso);
              expect(p.sinDescuento, e.sinDescuento, reason: caso);
              expect(p.lineas.fold<int>(0, (s, l) => s + l.entradas), e.aComprar,
                  reason: caso);
              expect(e.cosas.fold<int>(0, (s, c) => s + c.entradas), e.aComprar,
                  reason: caso);
            }
          }
        }
      }
    });
  });

  group('cada mesa adicional, por lo que tiene pago', () {
    test('una adicional paga entera y otra no: se venden las de la paga', () {
      // Dos adicionales de $70.000 (mesas 12, 13 y 14) y $70.000 pagados: la
      // primera está paga entera, la segunda no.
      final a = _alumno(extras: 2);
      final p = APagarDeLaFamilia.de(a, pagos: _pagos(mesas: 70000));
      expect(p.lineas, hasLength(2));
      expect(p.lineas[0].mesa, 1);
      expect(p.lineas[0].pagaEntera, isTrue);
      expect(p.lineas[0].habilitadas, 8);
      expect(p.lineas[1].mesa, 2);
      expect(p.lineas[1].numeroEnElSalon, 14);
      expect(p.lineas[1].pagaEntera, isFalse);
      expect(p.lineas[1].habilitadas, 0);
      expect(p.lineas[1].aConfirmar, 8);

      final l = _lugares(a, pagos: _pagos(mesas: 70000));
      expect(l.leCorresponden, 16);
      expect(l.pagas, 8);
      expect(l.quedan, 8);
      expect(l.textoAConfirmar,
          'La mesa adicional 14 está a confirmar: falta pagarla en caja.');

      final pedido = _pedidoDe(l);
      expect(pedido.deLugar, 8, reason: 'viene con las de lo pago');
      expect(pedido.conDeLugar(16).deLugar, 8, reason: 'lo que no está pago no se vende');
      expect(pedido.falta, isNull);
    });

    test('pagada a medias no se vende, aunque falte poco', () {
      final a = _alumno(extras: 1);
      final l = _lugares(a, pagos: _pagos(mesas: 69000));
      expect(l.quedan, 0);
      expect(l.textoAConfirmar,
          'La mesa adicional está a confirmar: falta pagarla en caja.');
      expect(_pedidoDe(l).falta,
          'La mesa adicional está a confirmar: falta pagarla en caja.');
    });

    test('la adicional paga se vende aunque el contrato tenga deuda', () {
      // Debe $100.000 de la base, pero la mesa adicional está paga entera.
      final a = _alumno(extras: 1, saldo: 100000);
      final pagos = _pagos(base: 200000, mesas: 70000);
      final deuda = RetiroEntradas.deudaDe(a, pagos: pagos, moraCobradaHistorial: 0);
      expect(deuda.pagoTodo, isFalse);
      expect(RetiroEntradas.bloqueo(a, deuda), BloqueoRetiro.debe,
          reason: 'las 8 sin cargo, no: eso es con el contrato entero saldado');

      final l = _lugares(a, pagos: pagos);
      expect(l.quedan, 8, reason: 'A PAGAR va por cosa: la mesa está paga');
      expect(l.textoAConfirmar, isNull);
      final pedido = _pedidoDe(l);
      expect(pedido.deLugarQueVan, 8);
      expect(pedido.falta, isNull);
    });

    test('lo pagado sale de los pagos: un pago anulado no cuenta, y los campos '
        'del contrato no mandan', () {
      final a = _alumno(extras: 1).copyWith(mesaExtraPagado: 70000, mesaExtraCuotasPagadas: 1);
      final l = _lugares(a, pagos: [
        ..._pagos(),
        _pago(70000, 'Mesa Extra 1', anulado: 1),
      ]);
      expect(l.quedan, 0, reason: 'la ficha dice paga, pero los pagos no');
      expect(l.textoAConfirmar, isNotNull);
    });

    test('pagasEnteras también antes del sorteo, sin número de mesa', () {
      final a = _alumno(extras: 2, conMesas: false);
      expect(AdicionalesDeLaFamilia.pagasEnteras(a, _pagos(mesas: 140000)), 2);
      expect(AdicionalesDeLaFamilia.pagasEnteras(a, _pagos(mesas: 139999)), 1);
      expect(AdicionalesDeLaFamilia.pagasEnteras(a, null), 0);
      // La puerta no la marca (sin mesa no hay nada que confirmar ahí).
      expect(AdicionalesDeLaFamilia.aConfirmar(a, _pagos()), isEmpty);
    });
  });

  group('las sillas extra, silla por silla', () {
    test('sillas pagas a medias: se venden las pagas enteras', () {
      final a = _alumno(sillas: 3);
      // $20.000 de $24.000: dos sillas enteras y la mitad de la tercera.
      final p = APagarDeLaFamilia.de(a, pagos: _pagos(sillas: 20000));
      expect(APagarDeLaFamilia.sillasPagas(a, _pagos(sillas: 20000)), 2);
      final sillas = p.lineas.single;
      expect(sillas.cosa, CosaAPagar.sillas);
      expect(sillas.cantidad, 3);
      expect(sillas.pagas, 2);
      expect(sillas.habilitadas, 2);

      final l = _lugares(a, pagos: _pagos(sillas: 20000));
      expect(l.quedan, 2);
      expect(l.textoAConfirmar,
          'Una de las sillas extra está a confirmar: falta pagarla en caja.');
      expect(_pedidoDe(l).conDeLugar(3).deLugarQueVan, 2);
    });

    test('un precio que no da justo: las tres pagas con el total', () {
      // $25.000 por tres sillas: $8.333,33 cada una, redondeado al centavo como
      // el reparto de las mesas.
      final a = _alumno(sillas: 3).copyWith(sillasExtraPrecioTotal: 25000);
      expect(APagarDeLaFamilia.sillasPagas(a, _pagos(sillas: 25000)), 3);
      expect(APagarDeLaFamilia.sillasPagas(a, _pagos(sillas: 16666.66)), 2);
      expect(APagarDeLaFamilia.sillasPagas(a, _pagos(sillas: 16000)), 1);
    });
  });

  group('nada pago, o sin los pagos', () {
    test('nada pago: no se le vende nada, y dice qué falta pagar', () {
      final a = _alumno(extras: 1, sillas: 2);
      final l = _lugares(a, pagos: _pagos());
      expect(l.leCorresponden, 10);
      expect(l.quedan, 0);
      expect(l.quedanTodas, 0);
      const falta =
          'La mesa adicional y las 2 sillas extra están a confirmar: falta pagarlas en caja.';
      expect(l.textoAConfirmar, falta);
      expect(l.porQueNoSeVende, falta);
      final pedido = _pedidoDe(l);
      expect(pedido.cantidad, 0);
      expect(pedido.falta, falta, reason: 'va antes que el nombre de quien compra');
      expect(pedido.conComprador('').falta, falta);
    });

    test('sin los pagos (null) no se habilita nada', () {
      final a = _alumno(extras: 2, sillas: 2);
      final p = APagarDeLaFamilia.de(a, pagos: null);
      expect(p.conDescuento, 18);
      expect(p.conDescuentoPagas, 0);
      expect(p.sinDescuentoPagas, 0);
      expect(APagarDeLaFamilia.sillasPagas(a, null), 0);
      final l = _lugares(a, pagos: null);
      expect(l.quedanTodas, 0);
      expect(_pedidoDe(l).conDeLugar(5).deLugarQueVan, 0);
    });

    test('sin mesa adicional ni sillas: no tiene nada que comprar', () {
      final l = _lugares(_alumno(), pagos: _pagos());
      expect(l.porQueNoSeVende, startsWith('No tiene entradas para comprar'));
      final pedido = _pedidoDe(l).conSueltas(3);
      expect(pedido.sueltas, 0, reason: 'las entradas para otra gente van por afuera');
      expect(pedido.falta, l.porQueNoSeVende);
    });
  });

  group('lo agregado después del sorteo, sin descuento', () {
    // Al sorteo tenía una mesa adicional; después agregó otra y dos sillas.
    final a = _alumno(extras: 2, sillas: 2);
    final foto = _alSorteo(2, 0);

    test('pago: se vende al precio del día, con su tope', () {
      final pagos = _pagos(mesas: 140000, sillas: 16000);
      final p = APagarDeLaFamilia.de(a, pagos: pagos, foto: foto);
      expect([for (final l in p.lineas) (l.cosa, l.conDescuento, l.habilitadas)], [
        (CosaAPagar.mesa, true, 8),
        (CosaAPagar.mesa, false, 8),
        (CosaAPagar.sillas, false, 2),
      ]);
      final l = _lugares(a, pagos: pagos, foto: foto);
      expect(l.quedan, 8);
      expect(l.sinDescuento, 10);
      expect(l.quedanSinDescuento, 10);

      final pedido = _pedidoDe(l);
      expect(pedido.deLugar, 8);
      expect(pedido.sueltas, 10, reason: 'viene con todo lo que le queda sin descuento');
      expect(pedido.conSueltas(15).sueltas, 10, reason: 'el tope');
      expect(pedido.conSueltas(4).sueltasQueVan, 4);
      expect(pedido.renglones.last.precio, 10000, reason: 'la General, sin descuento');
      expect(pedido.total, 8 * 5000 + 10 * 10000);
    });

    test('con la anticipada, lo sin descuento va a la anticipada; lo con '
        'descuento, sobre la General', () {
      final l = _lugares(a, pagos: _pagos(mesas: 140000, sillas: 16000), foto: foto);
      final pedido =
          _pedidoDe(l, config: _config(anticipada: 8000, hasta: '2026-11-28'));
      expect(pedido.renglones.first.precio, 5000);
      expect(pedido.renglones.last.nombre, 'Entrada anticipada');
      expect(pedido.renglones.last.precio, 8000);
    });

    test('no pago: la mesa agregada espera, y las sillas a medias también', () {
      // Pagó solo la primera mesa (la que tenía al sorteo) y una silla.
      final pagos = _pagos(mesas: 70000, sillas: 8000);
      final l = _lugares(a, pagos: pagos, foto: foto);
      expect(l.quedan, 8);
      expect(l.quedanSinDescuento, 1);
      expect(l.textoAConfirmar,
          'La mesa adicional 14 y una de las sillas extra están a confirmar: '
          'falta pagarlas en caja.');
      expect(_pedidoDe(l).conSueltas(5).sueltasQueVan, 1);
    });
  });

  group('sin cobrar dos veces', () {
    test('ya compró parte: le queda el resto de lo pago', () {
      final a = _alumno(extras: 2);
      final l = _lugares(a, pagos: _pagos(mesas: 140000), ventas: [_vendida(deLugar: 5)]);
      expect(l.compradas, 5);
      expect(l.quedan, 11);
    });

    test('compró antes de pagar (la 6.9.x lo vendía igual): pagarla no le da '
        'más, y no dice "a confirmar"', () {
      final a = _alumno(extras: 1);
      final ventas = [_vendida(deLugar: 8)];
      final sinPagar = _lugares(a, pagos: _pagos(), ventas: ventas);
      expect(sinPagar.quedan, 0);
      expect(sinPagar.textoAConfirmar, isNull);
      expect(sinPagar.porQueNoSeVende,
          'Ya compró todas las entradas de sus lugares adicionales.');
      final pagada = _lugares(a, pagos: _pagos(mesas: 70000), ventas: ventas);
      expect(pagada.quedan, 0);
    });

    test('compró de más con descuento con la 6.9.0: eso tapa lo sin descuento', () {
      // Al sorteo tenía una adicional; después agregó otra. La 6.9.0 le vendió
      // las 16 con descuento.
      final a = _alumno(extras: 2);
      final foto = _alSorteo(2, 0);
      final pagos = _pagos(mesas: 140000);
      final todas = _lugares(a, pagos: pagos, foto: foto, ventas: [_vendida(deLugar: 16)]);
      expect(todas.leCorresponden, 8);
      expect(todas.compradas, 16);
      expect(todas.compradasDeMas, 8);
      expect(todas.quedan, 0);
      expect(todas.quedanSinDescuento, 0, reason: 'esas 8 ya están compradas');
      expect(todas.porQueNoSeVende,
          'Ya compró todas las entradas de sus lugares adicionales.');

      final algunas = _lugares(a, pagos: pagos, foto: foto, ventas: [_vendida(deLugar: 12)]);
      expect(algunas.compradasDeMas, 4);
      expect(algunas.quedanSinDescuento, 4);
    });

    test('las sueltas a su nombre cuentan; las anuladas, las de otra familia y '
        'las de afuera, no', () {
      final a = _alumno(extras: 1);
      final foto = _alSorteo(1, 0);
      final anulada = _vendida(sueltas: 2);
      final l = _lugares(
        a,
        pagos: _pagos(mesas: 70000),
        foto: foto,
        ventas: [
          _vendida(sueltas: 3),
          anulada,
          _vendida(familia: _otra, sueltas: 4),
          _vendida(familia: null, sueltas: 5),
        ],
        anulaciones: [AnulacionEntradas.de(anulada, motivo: 'error', devueltas: true, ahora: _ahora)],
      );
      expect(l.sinDescuento, 8);
      expect(l.sueltasCompradas, 3);
      expect(l.quedanSinDescuento, 5);
      expect(_pedidoDe(l).sueltas, 5);
    });

    test('alguien de afuera: las sueltas no tienen tope', () {
      final p = PedidoDeEntradas.nuevo(config: _config(), hoyAr: _hoy).conSueltas(30);
      expect(p.sueltas, 30);
      expect(p.sueltasQueVan, 30);
    });

    test('lo que venía de alguien de afuera no pasa al elegir una familia: va '
        'con su tope', () {
      const l = LugaresDeLaFamilia(
        leCorresponden: 0,
        pagas: 0,
        compradas: 0,
        sinDescuento: 8,
        pagasSinDescuento: 2,
      );
      final p = PedidoDeEntradas.nuevo(config: _config(), hoyAr: _hoy)
          .conSueltas(6)
          .paraLaFamilia(_id, l)
          .conComprador('COMPRADORA, UNA');
      expect(p.sueltasQueVan, 2);
      expect(p.cantidad, 2);
      expect(p.conSueltas(6).cantidad, 2);
      // Y la venta que arma lleva eso, a nombre de la familia.
      final v = p.venta(
        caja: CajaEntradas.abrir(eventoId: _fiesta, operadorNombre: 'F1', ahora: _ahora),
        numero: 1,
        cobro: p.cobroPor(MedioBarra.efectivo),
        ahora: _ahora,
      );
      expect(v.contratoAlumnoId, _id);
      expect(v.cuantas(TipoRenglonEntradas.suelta), 2);
    });
  });

  group('más de 8 VIP', () {
    test('ocupan lugares de la adicional: esas no se pagan y bajan A PAGAR', () {
      // El egresado y 9 acompañantes: 10 con cena, 2 más que la mesa del
      // contrato. Dos adicionales, la primera paga.
      final a = _alumno(extras: 2, acompanantes: 9);
      final e = RetiroEntradas.entradasDe(a);
      expect(e.vip, 10);
      expect(e.generales, 0);
      final p = APagarDeLaFamilia.de(a, pagos: _pagos(mesas: 70000));
      expect(p.lineas[0].entradas, 6, reason: '2 lugares los ocupan los VIP');
      expect(p.lineas[0].habilitadas, 6);
      expect(p.lineas[1].entradas, 8);
      expect(p.lineas[1].habilitadas, 0);
      expect(_lugares(a, pagos: _pagos(mesas: 70000)).quedan, 6);
    });

    test('si los VIP llenan la adicional, esa no tiene nada que comprar', () {
      // 17 con cena: 9 de más llenan la primera adicional y uno de la segunda.
      final a = _alumno(extras: 2, acompanantes: 16);
      final p = APagarDeLaFamilia.de(a, pagos: _pagos());
      expect(p.lineas[0].entradas, 0);
      expect(p.lineas[0].aConfirmar, 0);
      expect(p.lineas[1].entradas, 7);
      expect(p.porPagar.single.mesa, 2);
    });
  });
}
