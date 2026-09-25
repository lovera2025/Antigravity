import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import 'salon_mesas.dart';

/// En qué está el reparto de las sillas extra de un alumno.
enum EstadoRepartoSillas {
  /// No tiene sillas extra: no hay nada que repartir.
  noAplica,

  /// Hay una sola forma de repartirlas, así que no hace falta llamar a nadie.
  unicaOpcion,

  /// La familia eligió, y la elección vale para su cuenta de hoy.
  elegido,

  /// Hay más de una forma y falta que la familia elija. También cuando eligió
  /// para otra cuenta: compró otra silla o cambiaron sus mesas.
  aConfirmar,

  /// Tiene más sillas de las que entran en sus mesas (2 por mesa): hay que
  /// revisar la cuenta antes de repartir.
  revisar,
}

/// Una forma de repartir: cuántas sillas van a la mesa principal y cuántas a
/// las adicionales (las mesas extra, de a 2 por mesa).
class OpcionReparto {
  final int principal;
  final int adicionales;

  const OpcionReparto(this.principal, this.adicionales);

  /// "2P · 1A", "2P", "2A".
  String get texto => [
        if (principal > 0) '${principal}P',
        if (adicionales > 0) '${adicionales}A',
      ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is OpcionReparto &&
      other.principal == principal &&
      other.adicionales == adicionales;

  @override
  int get hashCode => Object.hash(principal, adicionales);

  @override
  String toString() => texto;
}

/// Cómo reparte cada familia sus sillas extra entre sus mesas.
///
/// Todo sale de la cuenta ([SalonMesas]) y de lo que la familia eligió
/// ([SillasReparto]). La planilla, la columna Mesa y el filtro usan esto mismo,
/// para decir siempre lo mismo.
class RepartoDeSillas {
  RepartoDeSillas._();

  /// Las formas válidas de repartir [sillas] entre [mesas] mesas —la principal y
  /// las adicionales—, con hasta 2 por mesa. Primero la que carga más la
  /// principal, que es el reparto de siempre.
  ///
  /// Vacía si no hay sillas, no hay mesas, o no entran.
  static List<OpcionReparto> opciones({required int sillas, required int mesas}) {
    if (sillas <= 0 || mesas <= 0) return const [];
    const tope = SalonMesas.maxSillasExtraPorMesa;
    final entranEnAdicionales = tope * (mesas - 1);
    final desde = max(0, sillas - entranEnAdicionales);
    final hasta = min(tope, sillas);
    return [
      for (var p = hasta; p >= desde; p--) OpcionReparto(p, sillas - p),
    ];
  }

  static List<OpcionReparto> opcionesDe(ContratoAlumno a) => opciones(
        sillas: SalonMesas.sillasExtra(a),
        mesas: SalonMesas.mesas(a),
      );

  /// La elección guardada, si sigue valiendo para la cuenta de hoy. `null` si
  /// no eligió, o si eligió con otra cantidad de sillas o de mesas.
  static OpcionReparto? elegidoVigente(ContratoAlumno a, SillasReparto? guardado) {
    if (guardado == null) return null;
    final sillas = SalonMesas.sillasExtra(a);
    final mesas = SalonMesas.mesas(a);
    if (guardado.sillasExtra != sillas || guardado.mesas != mesas) return null;
    final opcion = OpcionReparto(
      guardado.sillasPrincipal,
      sillas - guardado.sillasPrincipal,
    );
    return opciones(sillas: sillas, mesas: mesas).contains(opcion)
        ? opcion
        : null;
  }

  static EstadoRepartoSillas estado(ContratoAlumno a, SillasReparto? guardado) {
    if (SalonMesas.sillasExtra(a) == 0) return EstadoRepartoSillas.noAplica;
    final ops = opcionesDe(a);
    if (ops.isEmpty) return EstadoRepartoSillas.revisar;
    if (ops.length == 1) return EstadoRepartoSillas.unicaOpcion;
    return elegidoVigente(a, guardado) != null
        ? EstadoRepartoSillas.elegido
        : EstadoRepartoSillas.aConfirmar;
  }

  /// El reparto con el que se arma la planilla: el elegido, la única opción o,
  /// mientras falte elegir, el de siempre (la principal primero). `null` si no
  /// tiene sillas extra o si no entran.
  static OpcionReparto? vigente(ContratoAlumno a, SillasReparto? guardado) {
    final ops = opcionesDe(a);
    if (ops.isEmpty) return null;
    return elegidoVigente(a, guardado) ?? ops.first;
  }

  /// Si hay que llamar a la familia para que elija.
  static bool faltaElegir(ContratoAlumno a, SillasReparto? guardado) =>
      estado(a, guardado) == EstadoRepartoSillas.aConfirmar;
}
