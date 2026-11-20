import 'dart:math';

import '../../../models/contrato_alumno.dart';
import 'adicional_a_confirmar.dart';
import 'cobro_abono_acumulado.dart';
import 'lugares_al_sorteo.dart';
import 'mesas_extra_utils.dart';
import 'retiro_entradas.dart';
import 'salon_mesas.dart';

/// De qué es una línea de A PAGAR.
enum CosaAPagar { mesa, sillas }

/// Una línea de A PAGAR en VENDER: una mesa adicional, o las sillas extra (las
/// que tenía al sorteo en una línea y las que agregó después en otra), con
/// cuántas entradas se compran por ella y cuántas de esas se le pueden vender
/// hoy.
class LineaAPagar {
  final CosaAPagar cosa;

  /// La mesa adicional: 1 es la primera, la que sigue a la del contrato. Null
  /// en las sillas.
  final int? mesa;

  /// El número de esa mesa en el salón, si ya lo tiene (el mismo que dice la
  /// puerta: "Mesa adicional 15"). Null en las sillas, o antes del sorteo.
  final int? numeroEnElSalon;

  /// La familia la tenía al sorteo: sus entradas van con el descuento de
  /// PRECIOS (sobre la General). Si no, la agregó después: sin descuento, al
  /// precio del día.
  final bool conDescuento;

  /// Cuántas cosas son: 1 mesa, o las sillas de la línea.
  final int cantidad;

  /// De esas, cuántas están pagas enteras.
  final int pagas;

  /// Las entradas que se compran por esta línea: 8 por mesa y 1 por silla,
  /// menos los lugares que ocupan los VIP que no entran en la mesa del
  /// contrato (su cena ya está en la cuenta: esas no se pagan). Puede ser 0.
  final int entradas;

  /// De [entradas], las de lo que ya está pago entero: **las únicas que se le
  /// venden**.
  final int habilitadas;

  const LineaAPagar({
    required this.cosa,
    this.mesa,
    this.numeroEnElSalon,
    required this.conDescuento,
    required this.cantidad,
    required this.pagas,
    required this.entradas,
    required this.habilitadas,
  });

  bool get pagaEntera => pagas >= cantidad;

  /// Las entradas que esperan que se pague lo suyo: "a confirmar".
  int get aConfirmar => entradas - habilitadas;

  @override
  String toString() => 'LineaAPagar(${cosa.name}${mesa == null ? '' : ' $mesa'}, '
      '${conDescuento ? 'con' : 'sin'} descuento, $pagas/$cantidad pagas, '
      '$habilitadas de $entradas)';
}

/// Lo que una familia compra aparte en VENDER (A PAGAR), **cosa por cosa**:
/// cada mesa adicional y sus sillas extra, separando lo que tenía al sorteo
/// (con descuento) de lo que agregó después (sin descuento).
///
/// **La regla (20-nov-2026, del usuario):** las 8 de la mesa del contrato van
/// sin cargo solo con el contrato entero saldado (eso es la entrega, no esto).
/// Lo de A PAGAR va por cosa: cada mesa adicional cuyo precio está pago entero
/// habilita sus entradas **aunque la familia deba otra cosa**; la que no está
/// paga entera no se vende ("a confirmar: falta pagarla en caja"). Las sillas
/// extra igual, silla por silla.
///
/// **Qué está pago sale de los pagos, nunca de los campos del contrato**
/// (`mesa_extra_pagado` y compañía pueden no coincidir con los pagos): lo de
/// las mesas, con [AdicionalesDeLaFamilia.pagasEnteras]; lo de las sillas,
/// con [grossHistoricoClaseCobro] repartido silla por silla con el precio de
/// cada una. **Sin los pagos (null) no se habilita nada.**
///
/// Cuántas entradas trae cada cosa no se cuenta acá: sale de
/// `EntradasDeAlumno.cosas`, la misma cuenta de la entrega y la planilla.
///
/// Vive en `eventos/services/` porque lee los pagos: la venta de entradas no
/// los nombra (`test/venta_entradas_no_toca_test.dart`). VENDER arma esto y se
/// lo pasa a `LugaresDeLaFamilia`, que pone el tope.
class APagarDeLaFamilia {
  /// El alumno de la cuenta.
  final String alumnoId;

  /// Las líneas, en el orden en que se leen: primero lo que tenía al sorteo
  /// (cada mesa adicional y después sus sillas), y después lo que agregó.
  final List<LineaAPagar> lineas;

  /// Todas sus mesas adicionales y sillas extra, pagas o no: para decir
  /// "la mesa adicional" o "una de las mesas adicionales".
  final int mesasAdicionales;
  final int sillasExtra;

  const APagarDeLaFamilia._({
    required this.alumnoId,
    required this.lineas,
    required this.mesasAdicionales,
    required this.sillasExtra,
  });

  /// [pagos]: los del alumno. **Null: todavía no se leyeron, y no se habilita
  /// nada.** Una lista vacía es que no pagó nada.
  ///
  /// [foto]: lo que cada familia tenía al sorteo (`FotoDeLosLugares`). Sin
  /// ella, todo lo suyo va con descuento, como en la entrega.
  factory APagarDeLaFamilia.de(
    ContratoAlumno a, {
    required Iterable<Map<String, dynamic>>? pagos,
    FotoDeLosLugares? foto,
  }) {
    final cosas = RetiroEntradas.entradasDe(a, foto: foto).cosas;
    final mesasPagas = AdicionalesDeLaFamilia.pagasEnteras(a, pagos);
    final sillasPagas = APagarDeLaFamilia.sillasPagas(a, pagos);
    // Las pagas son siempre las primeras: lo pagado se reparte de la primera a
    // la última, y las que tenía al sorteo van primero.
    bool paga(CosaAparte c) => c.n <= (c.esMesa ? mesasPagas : sillasPagas);
    final numeros = [for (final t in SalonMesas.tramos(a)) ...t];
    final lineas = <LineaAPagar>[];
    for (final conDescuento in const [true, false]) {
      for (final c in cosas) {
        if (!c.esMesa || c.alSorteo != conDescuento) continue;
        final esPaga = paga(c);
        lineas.add(LineaAPagar(
          cosa: CosaAPagar.mesa,
          mesa: c.n,
          // La adicional k es el número k de la familia (el 0 es la del
          // contrato), como en la puerta (`AdicionalesDeLaFamilia.aConfirmar`).
          numeroEnElSalon: c.n < numeros.length ? numeros[c.n] : null,
          conDescuento: conDescuento,
          cantidad: 1,
          pagas: esPaga ? 1 : 0,
          entradas: c.entradas,
          habilitadas: esPaga ? c.entradas : 0,
        ));
      }
      final sillas = [
        for (final c in cosas)
          if (!c.esMesa && c.alSorteo == conDescuento) c,
      ];
      if (sillas.isEmpty) continue;
      final pagas = sillas.where(paga).toList();
      lineas.add(LineaAPagar(
        cosa: CosaAPagar.sillas,
        conDescuento: conDescuento,
        cantidad: sillas.length,
        pagas: pagas.length,
        entradas: sillas.fold(0, (s, c) => s + c.entradas),
        habilitadas: pagas.fold(0, (s, c) => s + c.entradas),
      ));
    }
    return APagarDeLaFamilia._(
      alumnoId: a.id,
      lineas: List.unmodifiable(lineas),
      mesasAdicionales: SalonMesas.mesasExtra(a),
      sillasExtra: SalonMesas.sillasExtra(a),
    );
  }

  /// Cuántas de sus sillas extra están pagas enteras. Lo pagado de las sillas
  /// se reparte silla por silla, de la primera a la última, con el precio de
  /// cada una: la misma cuenta que las mesas
  /// ([MesasExtraUtils.repartirPagadoFifo]). Así las pagas son siempre las
  /// primeras. **Sin los pagos (null), ninguna.**
  static int sillasPagas(
    ContratoAlumno a,
    Iterable<Map<String, dynamic>>? pagos,
  ) {
    if (pagos == null) return 0;
    final n = SalonMesas.sillasExtra(a);
    final unit = SalonMesas.precioUnitarioSilla(a);
    if (n < 1 || unit == null) return 0;
    var pagas = 0;
    for (final s in MesasExtraUtils.repartirPagadoFifo(
      cantidad: n,
      precioUnitario: unit,
      cuotasPlan: max(1, a.sillasExtraCuotas),
      pagadoTotal: grossHistoricoClaseCobro(pagos, CobroConceptoClase.sillas),
    )) {
      if (!s.liquidada) break;
      pagas++;
    }
    return pagas;
  }

  int _suma(bool conDescuento, int Function(LineaAPagar l) cuanto) => lineas
      .where((l) => l.conDescuento == conDescuento)
      .fold(0, (s, l) => s + cuanto(l));

  /// Las de lo que tenía al sorteo, pagas o no (`EntradasDeAlumno.conDescuento`).
  int get conDescuento => _suma(true, (l) => l.entradas);

  /// De esas, las de lo pago entero.
  int get conDescuentoPagas => _suma(true, (l) => l.habilitadas);

  /// Las de lo que agregó después del sorteo, pagas o no
  /// (`EntradasDeAlumno.sinDescuento`).
  int get sinDescuento => _suma(false, (l) => l.entradas);

  /// De esas, las de lo pago entero.
  int get sinDescuentoPagas => _suma(false, (l) => l.habilitadas);

  /// Las líneas con entradas que esperan el pago.
  List<LineaAPagar> get porPagar => [
        for (final l in lineas)
          if (l.aConfirmar > 0) l,
      ];

  /// "La mesa adicional está a confirmar: falta pagarla en caja.", con lo que
  /// todavía no está pago entero. Null si no hay nada esperando el pago. Sin
  /// plata ni nombres de conceptos: lo lee quien vende, con la familia
  /// adelante.
  String? get textoAConfirmar {
    final mesas = [
      for (final l in porPagar)
        if (l.cosa == CosaAPagar.mesa) l,
    ];
    final sillas = porPagar
        .where((l) => l.cosa == CosaAPagar.sillas)
        .fold(0, (s, l) => s + l.aConfirmar);
    final partes = [
      if (mesas.isNotEmpty) _queMesas(mesas),
      if (sillas > 0) _queSillas(sillas),
    ];
    if (partes.isEmpty) return null;
    final plural = partes.length > 1 || partes.single.plural;
    final sujeto = partes.length == 1
        ? partes.single.texto
        : '${partes[0].texto} y ${_enMinuscula(partes[1].texto)}';
    return plural
        ? '$sujeto están a confirmar: falta pagarlas en caja.'
        : '$sujeto está a confirmar: falta pagarla en caja.';
  }

  ({String texto, bool plural}) _queMesas(List<LineaAPagar> mesas) {
    final k = mesas.length;
    if (k >= mesasAdicionales) {
      return k == 1
          ? (texto: 'La mesa adicional', plural: false)
          : (texto: 'Las $k mesas adicionales', plural: true);
    }
    // Algunas sí están pagas: se dice cuáles, con su número del salón si lo
    // tienen todas.
    final numeros = [for (final m in mesas) m.numeroEnElSalon];
    if (numeros.every((n) => n != null)) {
      return k == 1
          ? (texto: 'La mesa adicional ${numeros.single}', plural: false)
          : (texto: 'Las mesas adicionales ${_enLista(numeros.cast<int>())}', plural: true);
    }
    return k == 1
        ? (texto: 'Una de las mesas adicionales', plural: false)
        : (texto: '$k de las mesas adicionales', plural: true);
  }

  ({String texto, bool plural}) _queSillas(int j) {
    if (j >= sillasExtra) {
      return j == 1
          ? (texto: 'La silla extra', plural: false)
          : (texto: 'Las $j sillas extra', plural: true);
    }
    return j == 1
        ? (texto: 'Una de las sillas extra', plural: false)
        : (texto: '$j de las sillas extra', plural: true);
  }

  static String _enLista(List<int> n) => n.length == 1
      ? '${n.single}'
      : '${n.sublist(0, n.length - 1).join(', ')} y ${n.last}';

  static String _enMinuscula(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}
