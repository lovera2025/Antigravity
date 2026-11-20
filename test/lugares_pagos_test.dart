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
  BloqueoRetiro bloqueo = BloqueoRetiro.ninguno,
  bool todoEntregado = false,
}) =>
    LugaresDeLaFamilia.de(
      a,
      ventas: ventas,
      anulaciones: anulaciones,
      aPagar: APagarDeLaFamilia.de(a, pagos: pagos, foto: foto),
      bloqueo: bloqueo,
      todoEntregado: todoEntregado,
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

    // Revisión del 20-nov-2026: con las adicionales "Al final" (la 12 sola
    // adelante, la 67 y la 68 juntas al fondo), el número salía del tramo más
    // largo y el texto nombraba a la mesa del contrato como la que faltaba.
    test('la mesa del contrato es la 12 aunque las adicionales 67-68 formen un '
        'tramo más largo: falta pagar la 68', () {
      final a = _alumno(extras: 2).copyWith(
        numeroMesa: MesasExtraUtils.formatearAsignacionMesas(const [12, 67, 68]),
      );
      final p = APagarDeLaFamilia.de(a, pagos: _pagos(mesas: 70000));
      expect(p.lineas[0].numeroEnElSalon, 67);
      expect(p.lineas[1].numeroEnElSalon, 68);
      expect(p.lineas[1].pagaEntera, isFalse);
      expect(_lugares(a, pagos: _pagos(mesas: 70000)).textoAConfirmar,
          'La mesa adicional 68 está a confirmar: falta pagarla en caja.');
      // Y la puerta dice lo mismo: es la misma cuenta.
      expect(AdicionalesDeLaFamilia.mesas(a, _pagos(mesas: 70000)), {68});
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

  // Revisión del 20-nov-2026: lo que VENDER muestra en cada línea de A PAGAR
  // (`porLinea`) no tenía test propio, y lo comprado de más no tapaba el "a
  // confirmar" de la línea.
  group('línea por línea', () {
    /// Lo de cada línea suma lo mismo que la cuenta de la familia.
    void sumaLoMismo(LugaresDeLaFamilia l, List<LineaAPagar> lineas) {
      final (:quedan, :aConfirmar) = l.porLinea(lineas);
      var con = 0, sin = 0;
      for (var i = 0; i < lineas.length; i++) {
        if (lineas[i].conDescuento) {
          con += quedan[i];
        } else {
          sin += quedan[i];
        }
        expect(quedan[i], inInclusiveRange(0, lineas[i].habilitadas));
        expect(aConfirmar[i], inInclusiveRange(0, lineas[i].aConfirmar));
      }
      expect(con, l.quedan);
      expect(sin, l.quedanSinDescuento);
      expect(aConfirmar.fold<int>(0, (s, n) => s + n), l.esperanElPago);
    }

    test('lo comprado se descuenta de la primera línea paga y sigue en la otra', () {
      final a = _alumno(extras: 2, sillas: 2);
      final pagos = _pagos(mesas: 140000, sillas: 16000);
      final p = APagarDeLaFamilia.de(a, pagos: pagos);
      final l = _lugares(a, pagos: pagos, ventas: [_vendida(deLugar: 10)]);
      final (:quedan, :aConfirmar) = l.porLinea(p.lineas);
      expect(quedan, [0, 6, 2]);
      expect(aConfirmar, [0, 0, 0]);
      sumaLoMismo(l, p.lineas);
    });

    test('lo comprado de más con descuento (la 6.9.0) pasa a la línea sin descuento',
        () {
      // Al sorteo tenía la mesa del contrato y una adicional; la segunda la
      // agregó después. Las dos pagas. La 6.9.0 le vendió 11 con descuento: 8 de
      // la primera y 3 de más, que tapan la línea sin descuento.
      final a = _alumno(extras: 2);
      final pagos = _pagos(mesas: 140000);
      final foto = _alSorteo(2, 0);
      final p = APagarDeLaFamilia.de(a, pagos: pagos, foto: foto);
      final l = _lugares(a, pagos: pagos, foto: foto, ventas: [_vendida(deLugar: 11)]);
      expect(l.compradasDeMas, 3);
      final (:quedan, :aConfirmar) = l.porLinea(p.lineas);
      expect(quedan, [0, 5]);
      expect(aConfirmar, [0, 0]);
      sumaLoMismo(l, p.lineas);
    });

    test('compró las de su mesa adicional antes de pagarla: la línea no queda "a '
        'confirmar"', () {
      final a = _alumno(extras: 1);
      final p = APagarDeLaFamilia.de(a, pagos: _pagos());
      final l = _lugares(a, pagos: _pagos(), ventas: [_vendida(deLugar: 8)]);
      final (:quedan, :aConfirmar) = l.porLinea(p.lineas);
      expect(p.lineas.single.aConfirmar, 8, reason: 'la mesa no está paga');
      expect(quedan, [0]);
      expect(aConfirmar, [0], reason: 'ya las compró: pagarla no le da más');
      sumaLoMismo(l, p.lineas);
    });

    test('compró 3 antes de pagarla: quedan 5 a confirmar en esa línea', () {
      final a = _alumno(extras: 1);
      final p = APagarDeLaFamilia.de(a, pagos: _pagos());
      final l = _lugares(a, pagos: _pagos(), ventas: [_vendida(deLugar: 3)]);
      final (:quedan, :aConfirmar) = l.porLinea(p.lineas);
      expect(quedan, [0]);
      expect(aConfirmar, [5]);
      sumaLoMismo(l, p.lineas);
    });

    test('lo comprado de más tapa también una línea sin descuento sin pagar', () {
      // La mesa adicional la agregó después del sorteo y no la pagó; la 6.9.0 le
      // vendió las 8 con descuento.
      final a = _alumno(extras: 1);
      final foto = _alSorteo(1, 0);
      final p = APagarDeLaFamilia.de(a, pagos: _pagos(), foto: foto);
      final l = _lugares(a, pagos: _pagos(), foto: foto, ventas: [_vendida(deLugar: 8)]);
      expect(l.compradasDeMas, 8);
      final (:quedan, :aConfirmar) = l.porLinea(p.lineas);
      expect(quedan, [0]);
      expect(aConfirmar, [0]);
      sumaLoMismo(l, p.lineas);
    });

    test('sueltas y lugar repartidos en varias líneas, con cosas sin pagar', () {
      // Al sorteo: la mesa del contrato, una adicional y 1 silla. Después: otra
      // adicional y 2 sillas. Pagó las dos mesas y 2 de las 3 sillas.
      final a = _alumno(extras: 2, sillas: 3);
      final foto = _alSorteo(2, 1);
      final pagos = _pagos(mesas: 140000, sillas: 16000);
      final p = APagarDeLaFamilia.de(a, pagos: pagos, foto: foto);
      for (final ventas in [
        <VentaEntradas>[],
        [_vendida(deLugar: 4)],
        [_vendida(deLugar: 9, sueltas: 2)],
        [_vendida(deLugar: 9), _vendida(sueltas: 9)],
      ]) {
        sumaLoMismo(_lugares(a, pagos: pagos, foto: foto, ventas: ventas), p.lineas);
      }
    });
  });

  // Revisión del 20-nov-2026: VENDER le vendía a una familia que el diálogo de
  // la entrega frenaba. Una sola regla para las dos pantallas.
  group('con la cuenta para revisar no se le vende', () {
    test('qué bloqueo frena la venta', () {
      for (final (b, seVende) in [
        (BloqueoRetiro.ninguno, true),
        (BloqueoRetiro.debe, true),
        (BloqueoRetiro.cuentaNoCoincide, false),
        (BloqueoRetiro.sinMesa, false),
        (BloqueoRetiro.mesasNoCoinciden, false),
        (BloqueoRetiro.noEntran, false),
      ]) {
        expect(APagarDeLaFamilia.seVendeCon(b), seVende, reason: b.name);
        // Con lo sin cargo ya entregado se le vende, como el diálogo desde la
        // 6.9.0.
        expect(APagarDeLaFamilia.seVendeCon(b, todoEntregado: true), isTrue,
            reason: b.name);
      }
    });

    // Revisión independiente del 20-nov-2026: en `RetiroEntradas.bloqueo` la
    // deuda va primero y tapaba los otros frenos. A una familia que debía una
    // cuota y no tenía número de mesa se le vendían las 8 de una adicional que
    // no estaba en el salón. A PAGAR usa `bloqueoDeLaVenta`, sin la deuda.
    test('quien debe y tiene las mesas mal cargadas tampoco compra: la deuda no '
        'tapa los otros frenos', () {
      // Debe $100.000 de la base y tiene la adicional paga entera.
      final pagos = _pagos(base: 200000, mesas: 70000);
      for (final (a, frena, texto) in [
        (
          _alumno(extras: 1, saldo: 100000, conMesas: false),
          BloqueoRetiro.sinMesa,
          'Hasta que tenga su mesa no se le vende: pedile al jefe que lo revise.',
        ),
        (
          // La adicional cargada, sin su número en el salón.
          _alumno(extras: 1, saldo: 100000)
              .copyWith(numeroMesa: MesasExtraUtils.formatearAsignacionMesas([12])),
          BloqueoRetiro.mesasNoCoinciden,
          'Hasta que el jefe revise sus mesas no se le vende: pedile que lo revise.',
        ),
      ]) {
        final deuda = RetiroEntradas.deudaDe(a, pagos: pagos, moraCobradaHistorial: 0);
        expect(deuda.noCoincide, isFalse, reason: 'la ficha coincide con los pagos');
        expect(deuda.pagoTodo, isFalse);
        // Para lo sin cargo, lo que frena es la deuda (a caja).
        expect(RetiroEntradas.bloqueo(a, deuda), BloqueoRetiro.debe);
        // Para A PAGAR, las mesas.
        expect(RetiroEntradas.bloqueoDeLaVenta(a, deuda), frena, reason: frena.name);
        final l = _lugares(
          a,
          pagos: pagos,
          bloqueo: RetiroEntradas.bloqueoDeLaVenta(a, deuda),
        );
        expect(l.frenada, texto);
        expect(l.quedanTodas, 0, reason: frena.name);
        expect(_pedidoDe(l).conDeLugar(8).deLugarQueVan, 0, reason: frena.name);
      }
    });

    test('quien debe, con sus mesas bien, compra lo que ya pagó entero', () {
      final a = _alumno(extras: 1, saldo: 100000);
      final pagos = _pagos(base: 200000, mesas: 70000);
      final deuda = RetiroEntradas.deudaDe(a, pagos: pagos, moraCobradaHistorial: 0);
      expect(RetiroEntradas.bloqueo(a, deuda), BloqueoRetiro.debe);
      expect(RetiroEntradas.bloqueoDeLaVenta(a, deuda), BloqueoRetiro.ninguno);
      expect(RetiroEntradas.bloqueoDeLaVenta(a, null), BloqueoRetiro.ninguno);
      final l = _lugares(a, pagos: pagos, bloqueo: RetiroEntradas.bloqueoDeLaVenta(a, deuda));
      expect(l.frenada, isNull);
      expect(l.quedan, 8);
    });

    test('con las mesas mal cargadas: nada le queda, y el porqué llega al pedido', () {
      final a = _alumno(extras: 1);
      final pagos = _pagos(mesas: 70000);
      final l = _lugares(a, pagos: pagos, bloqueo: BloqueoRetiro.mesasNoCoinciden);
      const texto =
          'Hasta que el jefe revise sus mesas no se le vende: pedile que lo revise.';
      expect(l.frenada, texto);
      expect(l.quedan, 0);
      expect(l.quedanTodas, 0);
      expect(l.porQueNoSeVende, texto);
      expect(l.esperanElPago, 0, reason: 'la mesa está paga: no espera el pago');
      final p = APagarDeLaFamilia.de(a, pagos: pagos);
      expect(l.porLinea(p.lineas).quedan, [0]);
      final pedido = _pedidoDe(l).conDeLugar(8);
      expect(pedido.deLugarQueVan, 0);
      expect(pedido.falta, texto);
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
