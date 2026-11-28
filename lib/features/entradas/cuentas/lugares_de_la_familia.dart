import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../eventos/services/lugares_pagos.dart';
import '../../eventos/services/retiro_entradas.dart' show BloqueoRetiro;
import '../datos/anulacion_entradas.dart';
import '../datos/venta_entradas.dart';

/// La anulación de cada venta anulada (id de la venta → su anulación). Una
/// venta que no está acá cuenta.
Map<String, AnulacionEntradas> anulacionesPorVenta(
  Iterable<AnulacionEntradas> anulaciones,
) =>
    {for (final a in anulaciones) a.ventaId: a};

/// Cuántas entradas de [tipo] compró cada familia (id del alumno → cantidad),
/// en ventas **no anuladas**.
Map<String, int> _porFamilia(
  Iterable<VentaEntradas> ventas,
  Iterable<AnulacionEntradas> anulaciones,
  TipoRenglonEntradas tipo,
) {
  final anuladas = anulacionesPorVenta(anulaciones);
  final out = <String, int>{};
  for (final v in ventas) {
    final familia = v.contratoAlumnoId;
    if (familia == null || anuladas.containsKey(v.id)) continue;
    final n = v.cuantas(tipo);
    if (n > 0) out[familia] = (out[familia] ?? 0) + n;
  }
  return out;
}

/// Cuántas entradas de sus lugares adicionales ya compró cada familia (id del
/// alumno → cantidad), en ventas **no anuladas**. Es lo que muestra la entrega
/// al lado de cada una: "8 al 50 % (compró 3)".
Map<String, int> compradasPorFamilia(
  Iterable<VentaEntradas> ventas,
  Iterable<AnulacionEntradas> anulaciones,
) =>
    _porFamilia(ventas, anulaciones, TipoRenglonEntradas.lugar);

/// Cuántas entradas sueltas (al precio del día) compró cada familia a su
/// nombre, en ventas **no anuladas**. Son las de lo que agregó después del
/// sorteo: en una venta de familia las sueltas son eso. En una venta de la
/// 6.9.x también pudieron ser entradas para otra gente (no tenían tope), y el
/// renglón no lo distingue: se cuentan igual, porque pagaron el mismo precio
/// del día y así nunca se cobra dos veces (lo que falte se vende como a
/// alguien de afuera, al mismo precio).
Map<String, int> sueltasPorFamilia(
  Iterable<VentaEntradas> ventas,
  Iterable<AnulacionEntradas> anulaciones,
) =>
    _porFamilia(ventas, anulaciones, TipoRenglonEntradas.suelta);

/// Las entradas de la mesa adicional y las sillas extra de una familia: cuántas
/// le corresponden, cuántas están pagas, cuántas ya compró y cuántas le quedan,
/// con descuento (lo que tenía al sorteo) y sin descuento (lo que agregó
/// después).
///
/// **Se le vende solo lo pago entero, cosa por cosa** (regla del usuario,
/// 20-nov-2026): la mesa adicional o la silla extra que ya pagó entera, aunque
/// deba otra cosa; la que no, espera ("a confirmar"). Qué está pago lo dice
/// [APagarDeLaFamilia], que sale de los pagos.
///
/// **No se guarda en ningún lado: se cuenta cada vez**, de la cuenta del alumno,
/// sus pagos y las ventas. Así no hay dos lugares que digan cosas distintas.
class LugaresDeLaFamilia {
  /// Las de los lugares adicionales que ya tenía al sorteo
  /// (`EntradasDeAlumno.conDescuento`), pagos o no: las únicas con el
  /// descuento.
  final int leCorresponden;

  /// De [leCorresponden], las de lo que ya está pago entero.
  final int pagas;

  /// Las que ya compró con el descuento (renglones de lugar), en ventas que
  /// cuentan.
  final int compradas;

  /// Las de lo que agregó **después del sorteo** (17-nov-2026), pago o no: no
  /// llevan el descuento. Se venden al precio del día (la anticipada mientras
  /// rige).
  final int sinDescuento;

  /// De [sinDescuento], las de lo que ya está pago entero.
  final int pagasSinDescuento;

  /// Las sueltas que ya compró a su nombre, en ventas que cuentan.
  final int sueltasCompradas;

  /// Qué espera el pago, en palabras ("La mesa adicional está a confirmar:
  /// falta pagarla en caja."). Lo arma [APagarDeLaFamilia.textoAConfirmar].
  final String? textoDeLoQueFalta;

  /// Por qué hoy no se le vende nada, aunque tenga cosas pagas: su cuenta de la
  /// entrega la tiene que revisar el jefe (la ficha distinta de los pagos, sin
  /// mesa, las mesas que no coinciden, no entran). Null si se le vende. Lo
  /// decide `APagarDeLaFamilia.porQueNoSeVendeCon`, la misma regla del diálogo
  /// de la entrega (revisión del 20-nov-2026).
  final String? frenada;

  const LugaresDeLaFamilia({
    required this.leCorresponden,
    required this.pagas,
    required this.compradas,
    this.sinDescuento = 0,
    this.pagasSinDescuento = 0,
    this.sueltasCompradas = 0,
    this.textoDeLoQueFalta,
    this.frenada,
  });

  /// Quien no es una familia de la fiesta: no le corresponde ninguna.
  static const ninguno =
      LugaresDeLaFamilia(leCorresponden: 0, pagas: 0, compradas: 0);

  /// [aPagar]: lo suyo cosa por cosa, con qué está pago (lo arma VENDER, que
  /// tiene los pagos, con `APagarDeLaFamilia.de`). Sin los pagos, nada está
  /// pago y no se le vende nada.
  ///
  /// [bloqueo]: cómo está su cuenta de la entrega (`RetiroEntradas.bloqueo`), y
  /// [todoEntregado], si ya retiró lo sin cargo: con la cuenta para revisar no
  /// se le vende nada ([frenada]).
  factory LugaresDeLaFamilia.de(
    ContratoAlumno alumno, {
    required Iterable<VentaEntradas> ventas,
    required Iterable<AnulacionEntradas> anulaciones,
    required APagarDeLaFamilia aPagar,
    required BloqueoRetiro bloqueo,
    bool todoEntregado = false,
  }) {
    assert(aPagar.alumnoId == alumno.id, 'lo de A PAGAR es de otro alumno');
    return LugaresDeLaFamilia(
      leCorresponden: aPagar.conDescuento,
      pagas: aPagar.conDescuentoPagas,
      compradas: compradasPorFamilia(ventas, anulaciones)[alumno.id] ?? 0,
      sinDescuento: aPagar.sinDescuento,
      pagasSinDescuento: aPagar.sinDescuentoPagas,
      sueltasCompradas: sueltasPorFamilia(ventas, anulaciones)[alumno.id] ?? 0,
      textoDeLoQueFalta: aPagar.textoAConfirmar,
      frenada: APagarDeLaFamilia.porQueNoSeVendeCon(
        bloqueo,
        todoEntregado: todoEntregado,
      ),
    );
  }

  /// Las de lo pago con descuento que todavía no compró, sin mirar si está
  /// [frenada].
  int get _quedanPagas => max(0, pagas - compradas);

  /// Lo mismo, sin descuento.
  int get _quedanPagasSinDescuento =>
      max(0, pagasSinDescuento - sueltasCompradas - compradasDeMas);

  /// Las que todavía puede comprar con el descuento: **las de lo pago, menos
  /// las que ya compró**. Nunca baja de cero (si le sacaron una silla después
  /// de comprar, quedan 0). Con la cuenta para revisar ([frenada]), ninguna.
  int get quedan => frenada != null ? 0 : _quedanPagas;

  /// Las que compró con el descuento por encima de las que hoy le
  /// corresponden. Pasa con lo vendido por la 6.9.0 y la 6.9.1 (y por la 6.9.2
  /// antes de que el jefe aceptara la lista de PRECIOS), que vendían todo con
  /// descuento: lo agregado después del sorteo también. **Ya está comprado**,
  /// así que se descuenta de lo sin descuento.
  int get compradasDeMas => max(0, compradas - leCorresponden);

  /// Las que todavía puede comprar sin descuento: **las de lo pago sin
  /// descuento, sin cobrar dos veces**: menos las sueltas que ya compró a su
  /// nombre y menos lo que compró de más con descuento. Nunca baja de cero. Con
  /// la cuenta para revisar ([frenada]), ninguna.
  int get quedanSinDescuento => frenada != null ? 0 : _quedanPagasSinDescuento;

  /// Todo lo que le queda para comprar hoy.
  int get quedanTodas => quedan + quedanSinDescuento;

  /// Cuántas le quedan de cada línea de A PAGAR ([lineas], las de
  /// `APagarDeLaFamilia.lineas`, en su orden) y cuántas de cada una siguen "a
  /// confirmar", para que VENDER muestre un renglón por mesa adicional y por
  /// sillas (20-nov-2026).
  ///
  /// **No es otra cuenta: es [quedan], [quedanSinDescuento] y [esperanElPago]
  /// repartidas línea por línea.** Lo que ya compró se descuenta primero de lo
  /// pago de cada línea, de la primera a la última (como lo pagado, que también
  /// cubre primero las primeras): lo con descuento de las líneas con descuento,
  /// y las sueltas (más lo comprado de más con descuento, [compradasDeMas]) de
  /// las sin descuento. **Lo comprado que sobra tapa lo "a confirmar"** de cada
  /// línea (revisión del 20-nov-2026): quien compró las de su mesa adicional con
  /// la 6.9.0, antes de pagarla, no tiene nada a confirmar (pagarla no le da
  /// más), y la línea no tiene que decir "A confirmar" mientras abajo dice "Ya
  /// compró todas".
  ///
  /// Los [quedan] de las líneas con descuento suman [quedan]; los de las otras,
  /// [quedanSinDescuento]. Los [aConfirmar] de todas suman [esperanElPago].
  ({List<int> quedan, List<int> aConfirmar}) porLinea(List<LineaAPagar> lineas) {
    var yaCon = compradas;
    var yaSin = sueltasCompradas + compradasDeMas;
    int usar(LineaAPagar l, int cuantas) {
      final ya = l.conDescuento ? yaCon : yaSin;
      final usadas = min(ya, cuantas);
      if (l.conDescuento) {
        yaCon -= usadas;
      } else {
        yaSin -= usadas;
      }
      return usadas;
    }

    final quedan = [
      for (final l in lineas) l.habilitadas - usar(l, l.habilitadas),
    ];
    final aConfirmar = [
      for (final l in lineas) l.aConfirmar - usar(l, l.aConfirmar),
    ];
    return (
      quedan: frenada != null ? [for (final _ in lineas) 0] : quedan,
      aConfirmar: aConfirmar,
    );
  }

  /// Las de lo que agregó después del sorteo que todavía no compró, **pagas o
  /// no**: lo que le falta comprar sin descuento. En 0, ya compró todo lo suyo
  /// (el aviso de VENDER la muestra apagada, 27-nov-2026).
  int get faltanSinDescuento =>
      max(0, sinDescuento - sueltasCompradas - compradasDeMas);

  /// Las que se le habilitarían si pagara lo que falta: las "a confirmar".
  /// Lo que ya compró antes de pagar (la 6.9.x lo vendía igual) no se cuenta
  /// dos veces: si ya lo compró, pagarlo no le habilita nada más.
  int get esperanElPago =>
      (max(0, leCorresponden - compradas) - _quedanPagas) +
      (faltanSinDescuento - _quedanPagasSinDescuento);

  /// Qué espera el pago, o null si nada (o si ya lo compró).
  String? get textoAConfirmar => esperanElPago <= 0
      ? null
      : textoDeLoQueFalta ??
          'Hay lugares adicionales a confirmar: falta pagarlos en caja.';

  /// Por qué a esta familia no se le puede vender nada hoy, en palabras de
  /// quien vende. Null si le queda algo. Con la cuenta para revisar, eso
  /// primero ([frenada]).
  String? get porQueNoSeVende {
    final freno = frenada;
    if (freno != null && leCorresponden + sinDescuento > 0) return freno;
    if (quedanTodas > 0) return null;
    if (leCorresponden + sinDescuento == 0) {
      return 'No tiene entradas para comprar: la mesa del contrato trae las '
          'suyas. Para otras entradas, elegí "Alguien de afuera".';
    }
    return textoAConfirmar ??
        'Ya compró todas las entradas de sus lugares adicionales.';
  }
}
