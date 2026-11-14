import '../../barra/cuentas/pesos.dart';
import '../datos/entradas_repositorio.dart';
import 'lugares_de_la_familia.dart';

/// Las cuentas de una caja de entradas: cuántas se vendieron y de qué tipo,
/// cómo se cobraron y cuánto efectivo tiene que haber. Es lo que ve quien vende
/// después de contar a ciegas, y lo que ve el jefe por caja y por fiesta.
///
/// **Una venta anulada no cuenta, tampoco en el efectivo que tiene que haber:**
/// se supone que esa plata se devolvió (como en la barra). Lo anulado va
/// aparte.
///
/// Las cuentas van en centavos enteros.
class CierreDeEntradas {
  final double cambioInicial;

  /// Las ventas que cuentan: sin las anuladas.
  final int ventas;
  final int anuladas;
  final int mixtos;

  /// Cuántas ventas que cuentan tuvieron algo por transferencia (las mixtas
  /// también): las que hay que mirar en la cuenta.
  final int conTransferencia;

  /// Lo cobrado que cuenta. La transferencia va con los recargos adentro.
  final double efectivo;
  final double transferencia;

  /// De lo cobrado por transferencia, lo que fue recargo: no es de ninguna
  /// entrada.
  final double recargos;
  final double efectivoAnulado;
  final double transferenciaAnulada;

  /// De lo anulado, lo que el jefe anuló **después de cerrada la caja**. El
  /// cierre no se corrige: esto va en una línea aparte.
  final double efectivoAnuladoDespues;
  final double transferenciaAnuladaDespues;

  /// Las sueltas (a precio de lista, con el descuento a mano si lo hubo).
  final int sueltas;
  final double plataSueltas;

  /// Las de la mesa adicional y las sillas extra, con el descuento de la fiesta.
  final int deLugar;
  final double plataDeLugar;

  /// Lo que no se pudo leer de los renglones (un tipo que esta versión no
  /// conoce, o una venta cuyos renglones no dan su total): se cuenta por la
  /// cantidad y el total de la venta.
  final int otras;
  final double plataOtras;

  /// La plata que no entró por los **descuentos a mano**, y en cuántas ventas.
  final double descuentos;
  final int conDescuento;

  const CierreDeEntradas({
    required this.cambioInicial,
    required this.ventas,
    required this.anuladas,
    required this.mixtos,
    required this.efectivo,
    required this.transferencia,
    required this.efectivoAnulado,
    required this.transferenciaAnulada,
    this.conTransferencia = 0,
    this.recargos = 0,
    this.efectivoAnuladoDespues = 0,
    this.transferenciaAnuladaDespues = 0,
    this.sueltas = 0,
    this.plataSueltas = 0,
    this.deLugar = 0,
    this.plataDeLugar = 0,
    this.otras = 0,
    this.plataOtras = 0,
    this.descuentos = 0,
    this.conDescuento = 0,
  });

  /// Las cuentas de [caja]: de [ventas] se miran solo las suyas.
  factory CierreDeEntradas.de(
    CajaEntradas caja,
    Iterable<VentaEntradas> ventas,
    Iterable<AnulacionEntradas> anulaciones,
  ) =>
      CierreDeEntradas._contar(
        soloDe: caja.id,
        cambioInicial: caja.cambioInicial,
        cierres: {caja.id: caja.cerradaAt},
        ventas: ventas,
        anulaciones: anulaciones,
      );

  /// **Todas las cajas de la fiesta juntas.** [ventas] son las de la fiesta:
  /// se cuentan todas. El cambio es la suma del de cada caja.
  factory CierreDeEntradas.deLaFiesta(
    Iterable<CajaEntradas> cajas,
    Iterable<VentaEntradas> ventas,
    Iterable<AnulacionEntradas> anulaciones,
  ) =>
      CierreDeEntradas._contar(
        soloDe: null,
        cambioInicial:
            deCentavos(cajas.fold(0, (s, c) => s + centavos(c.cambioInicial))),
        cierres: {for (final c in cajas) c.id: c.cerradaAt},
        ventas: ventas,
        anulaciones: anulaciones,
      );

  /// [soloDe] null: las de todas las cajas. [cierres] dice cuándo se cerró
  /// cada caja (null: sigue abierta).
  factory CierreDeEntradas._contar({
    required String? soloDe,
    required double cambioInicial,
    required Map<String, String?> cierres,
    required Iterable<VentaEntradas> ventas,
    required Iterable<AnulacionEntradas> anulaciones,
  }) {
    final anuladas = anulacionesPorVenta(anulaciones);
    var cuentan = 0, nAnuladas = 0, mixtos = 0, conTransferencia = 0;
    var efectivo = 0, transferencia = 0, recargos = 0;
    var efAnulado = 0, trAnulada = 0, efDespues = 0, trDespues = 0;
    var sueltas = 0, deLugar = 0, otras = 0;
    var plataSueltas = 0, plataDeLugar = 0, plataOtras = 0;
    var descuentos = 0, conDescuento = 0;

    for (final v in ventas) {
      if (soloDe != null && v.cajaEntradasId != soloDe) continue;
      final anulacion = anuladas[v.id];
      if (anulacion != null) {
        nAnuladas++;
        efAnulado += centavos(v.efectivo);
        trAnulada += centavos(v.transferencia);
        if (_despuesDelCierre(anulacion, cierres[v.cajaEntradasId])) {
          efDespues += centavos(v.efectivo);
          trDespues += centavos(v.transferencia);
        }
        continue;
      }
      cuentan++;
      if (v.medio == MedioBarra.mixto) mixtos++;
      if (centavos(v.transferencia) > 0) conTransferencia++;
      efectivo += centavos(v.efectivo);
      transferencia += centavos(v.transferencia);
      recargos += centavos(v.recargo);
      if (centavos(v.descuento) > 0) {
        descuentos += centavos(v.descuento);
        conDescuento++;
      }

      // Por tipo, solo si los renglones dan lo que dice la venta. Si no (no se
      // pudieron leer, o los escribió una versión más nueva), la venta entera
      // va a "otras": así las entradas y la plata suman siempre lo vendido.
      final enRenglones = v.renglones.fold(0, (s, r) => s + r.cantidad);
      final plataEnRenglones =
          v.renglones.fold(0, (s, r) => s + centavos(r.subtotal));
      if (enRenglones != v.cantidad || plataEnRenglones != centavos(v.total)) {
        otras += v.cantidad;
        plataOtras += centavos(v.total);
        continue;
      }
      for (final r in v.renglones) {
        switch (r.tipo) {
          case TipoRenglonEntradas.suelta:
            sueltas += r.cantidad;
            plataSueltas += centavos(r.subtotal);
          case TipoRenglonEntradas.lugar:
            deLugar += r.cantidad;
            plataDeLugar += centavos(r.subtotal);
          case TipoRenglonEntradas.otro:
            otras += r.cantidad;
            plataOtras += centavos(r.subtotal);
        }
      }
    }
    return CierreDeEntradas(
      cambioInicial: cambioInicial,
      ventas: cuentan,
      anuladas: nAnuladas,
      mixtos: mixtos,
      conTransferencia: conTransferencia,
      efectivo: deCentavos(efectivo),
      transferencia: deCentavos(transferencia),
      recargos: deCentavos(recargos),
      efectivoAnulado: deCentavos(efAnulado),
      transferenciaAnulada: deCentavos(trAnulada),
      efectivoAnuladoDespues: deCentavos(efDespues),
      transferenciaAnuladaDespues: deCentavos(trDespues),
      sueltas: sueltas,
      plataSueltas: deCentavos(plataSueltas),
      deLugar: deLugar,
      plataDeLugar: deCentavos(plataDeLugar),
      otras: otras,
      plataOtras: deCentavos(plataOtras),
      descuentos: deCentavos(descuentos),
      conDescuento: conDescuento,
    );
  }

  /// Si [anulacion] se hizo con la caja ya cerrada (el criterio del cierre de
  /// cobros: el momento de la anulación contra el del cierre). Una caja
  /// abierta, o un momento que no se entiende, no.
  static bool _despuesDelCierre(AnulacionEntradas anulacion, String? cerradaAt) {
    final cerrada = DateTime.tryParse(cerradaAt ?? '');
    final anulada = DateTime.tryParse(anulacion.createdAt);
    return cerrada != null && anulada != null && anulada.isAfter(cerrada);
  }

  /// Las entradas vendidas que cuentan.
  int get entradas => sueltas + deLugar + otras;

  /// Lo que valen las entradas vendidas, sin los recargos.
  double get vendido => deCentavos(
      centavos(plataSueltas) + centavos(plataDeLugar) + centavos(plataOtras));

  /// Lo cobrado que cuenta, en efectivo y por transferencia (con los recargos).
  double get total => deCentavos(centavos(efectivo) + centavos(transferencia));

  /// El cambio con que abrió más el efectivo de lo vendido.
  double get efectivoEsperado =>
      deCentavos(centavos(cambioInicial) + centavos(efectivo));

  /// Lo contado menos lo esperado: positivo sobra, negativo falta.
  double diferenciaCon(double contado) =>
      deCentavos(centavos(contado) - centavos(efectivoEsperado));

  /// "Anulado después del cierre: $X".
  double get anuladoDespues => deCentavos(
      centavos(efectivoAnuladoDespues) + centavos(transferenciaAnuladaDespues));

  bool get hayAnuladoDespues => centavos(anuladoDespues) > 0;
}

/// Una caja de entradas en el resumen del jefe: la caja como está guardada y
/// sus cuentas.
///
/// **La diferencia de una caja cerrada es la que se anotó al cerrar**, no una
/// cuenta de ahora: si el jefe anula una venta después, el cierre no se
/// corrige (va "Anulado después del cierre", en [cuentas]).
class ResumenDeCajaEntradas {
  final CajaEntradas caja;
  final CierreDeEntradas cuentas;

  const ResumenDeCajaEntradas(this.caja, this.cuentas);

  double? get contado => caja.efectivoContado;
  double? get diferencia => caja.diferencia;

  /// Una por caja, la que abrió primero arriba.
  static List<ResumenDeCajaEntradas> porCaja(
    Iterable<CajaEntradas> cajas,
    Iterable<VentaEntradas> ventas,
    Iterable<AnulacionEntradas> anulaciones,
  ) {
    final listaVentas = ventas.toList();
    final listaAnulaciones = anulaciones.toList();
    final ordenadas = cajas.toList()
      ..sort((a, b) => a.abiertaAt.compareTo(b.abiertaAt));
    return [
      for (final c in ordenadas)
        ResumenDeCajaEntradas(
          c,
          CierreDeEntradas.de(c, listaVentas, listaAnulaciones),
        ),
    ];
  }
}
