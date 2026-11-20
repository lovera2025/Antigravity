// Las cuentas de la venta de entradas (etapa 2 del spec del 13-nov, sección 5):
// el precio de hoy, las de los lugares adicionales, lo que decide VENDER y la
// venta que cierra. Todo puro: sin pantalla, sin base, sin reloj.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/barra/cuentas/cobro_barra.dart';
import 'package:arguello_events/features/barra/cuentas/pesos.dart';
import 'package:arguello_events/features/entradas/cuentas/lugares_de_la_familia.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/cuentas/precio_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/eventos/services/lugares_pagos.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _otraFiesta = 'e0000000-0000-4000-8000-000000000002';
const _familia = 'c0000000-0000-4000-8000-000000000001';
const _otraFamilia = 'c0000000-0000-4000-8000-000000000002';

final _ahora = DateTime.utc(2026, 11, 20, 15);

/// Un día cualquiera de Argentina, al mediodía.
DateTime _dia(int mes, int dia) => DateTime.utc(2026, mes, dia, 12);

/// El precio de la fiesta como lo guarda PRECIOS. Los $10.000 son un ejemplo.
ConfigEntradas _config({
  double? valor = 10000,
  double? anticipada,
  String? hasta,
  double lugaresPct = 50,
  double recargo = 0,
  bool aMano = false,
  String fiesta = _fiesta,
}) =>
    ConfigEntradas.vacia(fiesta, ahora: _ahora).conPrecios(
      valorEntrada: valor,
      precioAnticipada: anticipada,
      anticipadaHasta: hasta,
      descuentoLugaresPct: lugaresPct,
      recargoPct: recargo,
      descuentoAMano: aMano,
    );

CajaEntradas _caja({String fiesta = _fiesta}) => CajaEntradas.abrir(
      eventoId: fiesta,
      operadorNombre: 'F1',
      ahora: _ahora,
    );

/// Un alumno con [extras] mesas adicionales y [sillas] sillas extra, las dos
/// con su precio en la cuenta (sin precio no cuentan como lugares).
ContratoAlumno _alumno({
  String id = _familia,
  int extras = 0,
  int sillas = 0,
  List<String> acompanantes = const [],
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _fiesta,
      nombreAlumno: 'ALUMNO, DE PRUEBA',
      cantidadAcompanantes: acompanantes.length,
      nombresAcompanantes: acompanantes,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: 0,
      totalCuotas: 9,
      cuotasPagadas: 9,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      mesaExtraCuotas: 1,
      mesaExtraCuotasPagadas: extras > 0 ? 1 : 0,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      sillasExtraCuotas: 1,
      sillasExtraCuotasPagadas: sillas > 0 ? 1 : 0,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas(
          [for (var i = 0; i <= extras; i++) 12 + i]),
      createdAt: DateTime(2026, 2, 1),
    );

/// Los pagos de [a] con todo pago: la base, sus mesas adicionales y sus sillas.
List<Map<String, dynamic>> _todoPago(ContratoAlumno a) => [
      {'concepto': 'Cuota Base (9/9)', 'monto': 300000.0, 'monto_gross': 300000.0, 'anulado': 0},
      if (a.mesaExtraPrecio > 0)
        {'concepto': 'Mesa Extra 1', 'monto': a.mesaExtraPrecio, 'monto_gross': a.mesaExtraPrecio, 'anulado': 0},
      if (a.sillasExtraPrecioTotal > 0)
        {
          'concepto': 'Sillas extra',
          'monto': a.sillasExtraPrecioTotal,
          'monto_gross': a.sillasExtraPrecioTotal,
          'anulado': 0,
        },
    ];

/// Lo de [a] con todo pago (el detalle de lo pago a medias está en
/// `test/lugares_pagos_test.dart`).
LugaresDeLaFamilia _lugaresDe(
  ContratoAlumno a, {
  required List<VentaEntradas> ventas,
  List<AnulacionEntradas> anulaciones = const [],
}) =>
    LugaresDeLaFamilia.de(
      a,
      ventas: ventas,
      anulaciones: anulaciones,
      aPagar: APagarDeLaFamilia.de(a, pagos: _todoPago(a)),
      bloqueo: BloqueoRetiro.ninguno,
    );

/// Una venta ya hecha de [deLugar] entradas de lugares y [sueltas] sueltas.
VentaEntradas _vendida({
  String? familia = _familia,
  int deLugar = 0,
  int sueltas = 0,
}) {
  final renglones = [
    if (deLugar > 0)
      RenglonEntradas.lugar(
        nombre: 'Entrada de lugar adicional (50 %)',
        precioLista: 10000,
        descuentoPct: 50,
        cantidad: deLugar,
      ),
    if (sueltas > 0)
      RenglonEntradas.suelta(
          nombre: 'Entrada', precioLista: 10000, cantidad: sueltas),
  ];
  return VentaEntradas.nueva(
    cajaEntradasId: 'caja',
    eventoId: _fiesta,
    numero: 1,
    contratoAlumnoId: familia,
    compradorNombre: 'COMPRADORA, UNA',
    renglones: renglones,
    medio: MedioBarra.efectivo,
    efectivo: 5000.0 * deLugar + 10000.0 * sueltas,
    ahora: _ahora,
  );
}

AnulacionEntradas _anulada(VentaEntradas v, {bool devueltas = true}) =>
    AnulacionEntradas.de(v, motivo: 'se equivocó', devueltas: devueltas, ahora: _ahora);

/// Un pedido listo para confirmar: 2 sueltas para alguien de afuera.
PedidoDeEntradas _pedido({
  ConfigEntradas? config,
  DateTime? hoy,
  bool esJefe = false,
}) =>
    PedidoDeEntradas.nuevo(
      config: config ?? _config(),
      hoyAr: hoy ?? _dia(11, 20),
      esJefe: esJefe,
    ).conComprador('COMPRADORA, UNA').conSueltas(2);

/// Un repositorio que solo anota lo que le mandan a vender.
class _RepoQueAnota implements EntradasDeLaCaja {
  VentaEntradas? guardada;
  String? quien;

  @override
  Future<VentaEntradas> vender({
    required CajaEntradas caja,
    String? contratoAlumnoId,
    required String compradorNombre,
    String? compradorDni,
    required List<RenglonEntradas> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    String? numeros,
    required String quien,
  }) async {
    this.quien = quien;
    return guardada = VentaEntradas.nueva(
      cajaEntradasId: caja.id,
      eventoId: caja.eventoId,
      numero: 17,
      contratoAlumnoId: contratoAlumnoId,
      compradorNombre: compradorNombre,
      compradorDni: compradorDni,
      renglones: renglones,
      medio: medio,
      efectivo: efectivo,
      transferencia: transferencia,
      recibe: recibe,
      recargo: recargo,
      recargoPct: recargoPct,
      numeros: numeros,
      ahora: _ahora,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('el precio de hoy', () {
    test('sin precio, null: la fiesta no se vende', () {
      expect(PrecioDeEntradas.deHoy(null, _dia(11, 20)), isNull);
      expect(PrecioDeEntradas.deHoy(_config(valor: null), _dia(11, 20)), isNull);
      expect(PrecioDeEntradas.deLugar(null), isNull);
      expect(PrecioDeEntradas.deLugar(_config(valor: null)), isNull);
    });

    test('con un solo precio, ese', () {
      final c = _config();
      expect(PrecioDeEntradas.deHoy(c, _dia(11, 20)), 10000);
      expect(PrecioDeEntradas.rigeLaAnticipada(c, _dia(11, 20)), isFalse);
    });

    test('el último día de la anticipada rige; al otro día, el valor', () {
      final c = _config(anticipada: 8000, hasta: '2026-11-28');
      expect(PrecioDeEntradas.deHoy(c, _dia(11, 27)), 8000);
      expect(PrecioDeEntradas.deHoy(c, DateTime.utc(2026, 11, 28, 23, 59)), 8000,
          reason: 'el último día rige entero');
      expect(PrecioDeEntradas.deHoy(c, DateTime.utc(2026, 11, 29, 0, 0)), 10000);
      expect(PrecioDeEntradas.deHoy(c, _dia(12, 1)), 10000,
          reason: 'diciembre es después de noviembre, también como texto');
    });

    test('a medianoche de Argentina, no de UTC', () {
      final c = _config(anticipada: 8000, hasta: '2026-11-28');
      // La 1:30 del 29 en UTC son las 22:30 del 28 en Argentina.
      final todaviaEl28 = ArTime.toAr(DateTime.utc(2026, 11, 29, 1, 30));
      expect(ConfigEntradas.diaDe(todaviaEl28), '2026-11-28');
      expect(PrecioDeEntradas.deHoy(c, todaviaEl28), 8000);
      // Las 3:00 del 29 en UTC son las 0:00 del 29 en Argentina.
      final yaEl29 = ArTime.toAr(DateTime.utc(2026, 11, 29, 3, 0));
      expect(PrecioDeEntradas.deHoy(c, yaEl29), 10000);
    });

    test('una anticipada sin fecha no rige nunca', () {
      final c = ConfigEntradas(
        id: 'x',
        eventoId: _fiesta,
        valorEntrada: 10000,
        precioAnticipada: 8000,
        createdAt: 'x',
        updatedAt: 'x',
      );
      expect(PrecioDeEntradas.rigeLaAnticipada(c, _dia(1, 1)), isFalse);
      expect(PrecioDeEntradas.deHoy(c, _dia(1, 1)), 10000);
    });

    test('el precio del lugar sale del valor de la entrada, no de la anticipada', () {
      final c = _config(anticipada: 8000, hasta: '2026-11-28');
      expect(PrecioDeEntradas.deHoy(c, _dia(11, 20)), 8000);
      expect(PrecioDeEntradas.deLugar(c), 5000, reason: 'el 50 % de 10.000');
      expect(PrecioDeEntradas.deLugar(_config(lugaresPct: 40)), 6000);
      expect(PrecioDeEntradas.deLugar(_config(valor: 9999)), 5000,
          reason: 'en pesos enteros');
    });
  });

  group('las de los lugares adicionales', () {
    // Una mesa adicional y 6 sillas extra: 22 lugares, 8 sin cargo y 14 al 50 %.
    final alumno = _alumno(extras: 1, sillas: 6);

    test('14 que le corresponden y 3 compradas: le quedan 11', () {
      final l = _lugaresDe(alumno, ventas: [_vendida(deLugar: 3)]);
      expect(l.leCorresponden, 14);
      expect(l.compradas, 3);
      expect(l.quedan, 11);
    });

    test('una venta anulada las devuelve', () {
      final v = _vendida(deLugar: 3);
      final l = _lugaresDe(
        alumno,
        ventas: [v, _vendida(deLugar: 2)],
        anulaciones: [_anulada(v, devueltas: false)],
      );
      expect(l.compradas, 2);
      expect(l.quedan, 12);
    });

    test('no cuentan las sueltas, ni las de otra familia, ni las de afuera', () {
      final l = _lugaresDe(
        alumno,
        ventas: [
          _vendida(sueltas: 4),
          _vendida(familia: _otraFamilia, deLugar: 5),
          _vendida(familia: null, sueltas: 2),
        ],
      );
      expect(l.compradas, 0);
      expect(l.quedan, 14);
      expect(l.sueltasCompradas, 4, reason: 'las sueltas a su nombre van aparte');
    });

    test('nunca quedan menos de cero', () {
      // Le sacaron las sillas después de comprar.
      final l = _lugaresDe(
        _alumno(extras: 0, sillas: 2),
        ventas: [_vendida(deLugar: 5)],
      );
      expect(l.leCorresponden, 2);
      expect(l.quedan, 0);
    });

    test('compradasPorFamilia: lo que muestra la entrega', () {
      final anulada = _vendida(deLugar: 8);
      expect(
        compradasPorFamilia(
          [
            _vendida(deLugar: 3),
            _vendida(deLugar: 1, sueltas: 2),
            _vendida(familia: _otraFamilia, deLugar: 5),
            anulada,
          ],
          [_anulada(anulada)],
        ),
        {_familia: 4, _otraFamilia: 5},
      );
    });

    test('no se le venden más de las que le quedan', () {
      final l = _lugaresDe(alumno, ventas: [_vendida(deLugar: 3)]);
      final p = _pedido().conSueltas(0).paraLaFamilia(_familia, l);
      expect(p.deLugar, 11, reason: 'viene con todas las que le quedan');
      expect(p.conDeLugar(20).deLugar, 11);
      expect(p.conDeLugar(-3).deLugar, 0);
      expect(p.conDeLugar(4).deLugarQueVan, 4);
      // Alguien de afuera no lleva ninguna.
      expect(p.paraAlguienDeAfuera().deLugar, 0);
      expect(p.paraAlguienDeAfuera().conDeLugar(5).deLugar, 0);
    });
  });

  group('lo que decide VENDER', () {
    // 14 con descuento (3 compradas) y 2 sin descuento, todo pago: a la familia
    // se le venden las 11 y las 2 (sueltas, al precio del día).
    const lugares = LugaresDeLaFamilia(
      leCorresponden: 14,
      pagas: 14,
      compradas: 3,
      sinDescuento: 2,
      pagasSinDescuento: 2,
    );

    test('los renglones, con su nombre y el precio de ese momento', () {
      final p = _pedido().paraLaFamilia(_familia, lugares).conDeLugar(8);
      expect(p.renglones, [
        RenglonEntradas.lugar(
          nombre: 'Entrada de lugar adicional (50 %)',
          precioLista: 10000,
          descuentoPct: 50,
          cantidad: 8,
        ),
        RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 2),
      ]);
      expect(p.cantidad, 10);
      expect(p.total, 60000);
      expect(pesos(p.total), r'$ 60.000');
    });

    test('con la anticipada, la suelta se llama anticipada y la de lugar no baja', () {
      final p = _pedido(config: _config(anticipada: 8000, hasta: '2026-11-28'))
          .paraLaFamilia(_familia, lugares)
          .conDeLugar(1);
      expect(p.renglones.last.nombre, 'Entrada anticipada');
      expect(p.renglones.last.precio, 8000);
      expect(p.renglones.first.precio, 5000);
    });

    test('el nombre del lugar dice lo que paga del valor', () {
      expect(PedidoDeEntradas.nombreDeLugar(50), 'Entrada de lugar adicional (50 %)');
      expect(PedidoDeEntradas.nombreDeLugar(40), 'Entrada de lugar adicional (60 %)');
      expect(PedidoDeEntradas.nombreDeLugar(37.5), 'Entrada de lugar adicional (62,5 %)');
    });

    test('el descuento a mano, solo con permiso', () {
      final sinPermiso = _pedido().conDescuento(20);
      expect(sinPermiso.puedeDescontar, isFalse);
      expect(sinPermiso.descuentoQueVa, 0);
      expect(sinPermiso.total, 20000);
      expect(sinPermiso.descontado, 0);

      final elJefeLoDejo = _pedido(config: _config(aMano: true)).conDescuento(20);
      expect(elJefeLoDejo.puedeDescontar, isTrue);
      expect(elJefeLoDejo.total, 16000);
      expect(elJefeLoDejo.descontado, 4000);

      final enModoJefe = _pedido(esJefe: true).conDescuento(20);
      expect(enModoJefe.total, 16000);

      // De 0 a 100, nada más.
      expect(_pedido(esJefe: true).conDescuento(150).descuentoPct, 100);
      expect(_pedido(esJefe: true).conDescuento(-5).descuentoPct, 0);
    });

    test('el descuento a mano no toca las de los lugares', () {
      final p = _pedido(esJefe: true)
          .paraLaFamilia(_familia, lugares)
          .conDeLugar(2)
          .conDescuento(10);
      expect(p.renglones.first.precio, 5000);
      expect(p.renglones.last.precio, 9000);
      expect(p.descontado, 2000, reason: 'solo lo de las sueltas es a mano');
    });

    test('por qué falta, en el orden de la pantalla', () {
      final sinPrecio = _pedido(config: _config(valor: null));
      expect(sinPrecio.falta,
          'El jefe todavía no puso el precio de la entrada de esta fiesta');
      expect(
        PedidoDeEntradas.nuevo(config: null, hoyAr: _dia(11, 20)).falta,
        'El jefe todavía no puso el precio de la entrada de esta fiesta',
      );

      expect(_pedido().conComprador('').falta,
          'Escribí nombre y apellido de quien compra');
      expect(_pedido().conComprador('  Compradora  ').falta,
          'Escribí nombre y apellido de quien compra',
          reason: 'una sola palabra no es nombre y apellido');

      expect(_pedido().conSueltas(0).falta, 'Elegí cuántas entradas lleva');

      expect(
        _pedido().conTramos(const [TramoTalonario(1, 5)]).falta,
        'Son 5 números y la venta lleva 2 entradas.',
      );

      final listo = _pedido().conTramos(const [TramoTalonario(1, 2)]);
      expect(listo.falta, isNull);
      expect(listo.puedeConfirmar, isTrue);
    });

    test('el recargo es el de la fiesta', () {
      expect(_pedido().recargoPrendido, isFalse);
      expect(_pedido().cobroPor(MedioBarra.transferencia).recargo, 0);
      final conRecargo = _pedido(config: _config(recargo: 5));
      expect(conRecargo.recargoPrendido, isTrue);
      expect(conRecargo.cobroPor(MedioBarra.transferencia).recargo, 1000);
    });
  });

  group('la venta cierra', () {
    void cierra(VentaEntradas v) => expect(
          centavos(v.efectivo) + centavos(v.transferencia),
          centavos(v.total) + centavos(v.recargo),
        );

    test('en efectivo, con lo que entrega y el vuelto', () {
      final p = _pedido();
      final v = p.venta(
        caja: _caja(),
        numero: 17,
        cobro: p.cobroPor(MedioBarra.efectivo).conRecibe(50000),
        ahora: _ahora,
      );
      cierra(v);
      expect(v.numero, 17);
      expect(v.medio, MedioBarra.efectivo);
      expect(v.efectivo, 20000);
      expect(v.transferencia, 0);
      expect(v.recibe, 50000);
      expect(v.vuelto, 30000);
      expect(v.cantidad, 2);
      expect(v.contratoAlumnoId, isNull);
      expect(v.numeros, isNull);
    });

    test('por transferencia con recargo: lo transferido lo lleva adentro', () {
      final p = _pedido(config: _config(recargo: 5));
      final v = p.venta(
        caja: _caja(),
        numero: 1,
        cobro: p.cobroPor(MedioBarra.transferencia),
        ahora: _ahora,
      );
      cierra(v);
      expect(v.total, 20000);
      expect(v.recargo, 1000);
      expect(v.recargoPct, 5);
      expect(v.transferencia, 21000);
      expect(v.cobrado, 21000);
      expect(v.recibe, isNull);
    });

    test('mixto con recargo: el recargo va solo sobre lo transferido', () {
      final p = _pedido(config: _config(recargo: 10));
      final cobro = p.cobroPor(MedioBarra.mixto).conEfectivoDelMixto(5000);
      final v = p.venta(caja: _caja(), numero: 1, cobro: cobro, ahora: _ahora);
      cierra(v);
      expect(v.medio, MedioBarra.mixto);
      expect(v.efectivo, 5000);
      expect(v.recargo, 1500);
      expect(v.transferencia, 16500);
    });

    test('una familia, con sus números del talonario', () {
      final p = _pedido()
          .paraLaFamilia(
              _familia,
              const LugaresDeLaFamilia(
                leCorresponden: 14,
                pagas: 14,
                compradas: 3,
                sinDescuento: 2,
                pagasSinDescuento: 2,
              ))
          .conDeLugar(8)
          .conDni(' 30111222 ')
          .conTramos(const [TramoTalonario(1043, 1050), TramoTalonario(1101, 1102)]);
      final v = p.venta(
        caja: _caja(),
        numero: 3,
        cobro: p.cobroPor(MedioBarra.efectivo),
        ahora: _ahora,
        hechoPor: 'F1',
        deviceId: 'pc-1',
      );
      cierra(v);
      expect(v.contratoAlumnoId, _familia);
      expect(v.compradorDni, '30111222');
      expect(v.numeros, '1043-1050,1101-1102');
      expect(v.cuantas(TipoRenglonEntradas.lugar), 8);
      expect(v.cuantas(TipoRenglonEntradas.suelta), 2);
      expect(v.total, 60000);
      expect(v.descuento, 0, reason: 'el 50 % de los lugares no es un descuento a mano');
      expect(v.hechoPor, 'F1');
    });

    test('con el 100 % de descuento vale 0 y se guarda igual', () {
      final p = _pedido(esJefe: true).conDescuento(100);
      expect(p.esSinCargo, isTrue);
      final v = p.venta(
        caja: _caja(),
        numero: 1,
        cobro: p.cobroPor(MedioBarra.efectivo),
        ahora: _ahora,
      );
      cierra(v);
      expect(v.total, 0);
      expect(v.descuento, 20000);
    });

    test('lo que no se puede confirmar no se arma', () {
      Object? alArmar(PedidoDeEntradas p) {
        try {
          p.venta(
            caja: _caja(),
            numero: 1,
            cobro: p.cobroPor(MedioBarra.efectivo),
            ahora: _ahora,
          );
          return null;
        } catch (e) {
          return e;
        }
      }

      expect(alArmar(_pedido()), isNull);
      expect(alArmar(_pedido().conSueltas(0)), isArgumentError);
      expect(alArmar(_pedido().conComprador('Una')), isArgumentError);
      expect(alArmar(_pedido(config: _config(valor: null))), isArgumentError);
      expect(alArmar(_pedido().conTramos(const [TramoTalonario(1, 9)])),
          isArgumentError);
    });

    test('un cobro por otro total, o la caja de otra fiesta, tiran', () {
      final p = _pedido();
      expect(
        () => p.venta(
          caja: _caja(),
          numero: 1,
          cobro: CobroBarra.de(15000, recargo: false),
          ahora: _ahora,
        ),
        throwsArgumentError,
      );
      expect(
        () => p.venta(
          caja: _caja(fiesta: _otraFiesta),
          numero: 1,
          cobro: p.cobroPor(MedioBarra.efectivo),
          ahora: _ahora,
        ),
        throwsArgumentError,
      );
      // Un mixto sin las dos partes no cierra.
      expect(
        () => p.venta(
          caja: _caja(),
          numero: 1,
          cobro: p.cobroPor(MedioBarra.mixto),
          ahora: _ahora,
        ),
        throwsArgumentError,
      );
    });

    test('cada caso que no cierra tira (5.3 del spec)', () {
      VentaEntradas armar({
        String comprador = 'COMPRADORA, UNA',
        String? familia,
        List<RenglonEntradas>? renglones,
        double efectivo = 20000,
      }) =>
          VentaEntradas.nueva(
            cajaEntradasId: 'caja',
            eventoId: _fiesta,
            numero: 1,
            contratoAlumnoId: familia,
            compradorNombre: comprador,
            renglones: renglones ??
                [
                  RenglonEntradas.suelta(
                      nombre: 'Entrada', precioLista: 10000, cantidad: 2),
                ],
            medio: MedioBarra.efectivo,
            efectivo: efectivo,
            ahora: _ahora,
          );

      expect(armar().total, 20000);
      // Sin renglones, o una cantidad menor que 1.
      expect(() => armar(renglones: const []), throwsArgumentError);
      expect(
        () => armar(renglones: [
          RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 0),
        ]),
        throwsArgumentError,
      );
      // Sin nombre y apellido.
      expect(() => armar(comprador: '   '), throwsArgumentError);
      // Un renglón de lugar sin familia.
      expect(
        () => armar(
          renglones: [
            RenglonEntradas.lugar(
                nombre: 'De lugar', precioLista: 10000, descuentoPct: 50, cantidad: 4),
          ],
        ),
        throwsArgumentError,
      );
      // El efectivo no da el total.
      expect(() => armar(efectivo: 19000), throwsArgumentError);
      // Un descuento a mano fuera de 0 a 100.
      expect(
        () => armar(
          efectivo: 0,
          renglones: const [
            RenglonEntradas(
              tipoClave: 'suelta',
              nombre: 'Entrada',
              precioLista: 10000,
              descuentoPct: 120,
              precio: -2000,
              cantidad: 2,
            ),
          ],
        ),
        throwsArgumentError,
      );
      // Un precio que no es el de lista con su descuento.
      expect(
        () => armar(
          efectivo: 18000,
          renglones: const [
            RenglonEntradas(
              tipoClave: 'suelta',
              nombre: 'Entrada',
              precioLista: 10000,
              precio: 9000,
              cantidad: 2,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('al repositorio va lo mismo que arma el pedido', () async {
      final p = _pedido(config: _config(recargo: 5))
          .paraLaFamilia(
              _familia,
              const LugaresDeLaFamilia(
                leCorresponden: 4,
                pagas: 4,
                compradas: 0,
                sinDescuento: 2,
                pagasSinDescuento: 2,
              ))
          .conTramos(const [TramoTalonario(10, 15)]);
      final caja = _caja();
      final cobro = p.cobroPor(MedioBarra.mixto).conEfectivoDelMixto(10000);
      final repo = _RepoQueAnota();

      final guardada = await p.guardarEn(repo, caja: caja, cobro: cobro, quien: 'F1');
      final armada = p.venta(caja: caja, numero: 17, cobro: cobro, ahora: _ahora);

      expect(repo.quien, 'F1');
      // Todo igual, menos el id (cada venta nace con el suyo).
      final a = guardada.toMap()..remove('id');
      final b = armada.toMap()..remove('id');
      expect(a, b);
      expect(guardada.cantidad, 6);
      expect(guardada.recargo, 1500);
    });

    test('guardar no llama al repositorio si la venta no cierra', () async {
      final repo = _RepoQueAnota();
      final p = _pedido().conComprador('');
      expect(
        () => p.guardarEn(repo,
            caja: _caja(), cobro: p.cobroPor(MedioBarra.efectivo), quien: 'F1'),
        throwsArgumentError,
      );
      expect(repo.guardada, isNull);
    });
  });
}
