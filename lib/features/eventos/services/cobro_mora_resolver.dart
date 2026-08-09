import '../../../models/contrato_alumno.dart';
import 'mora_concepto_rotulo.dart';
import 'mora_cuota_calculator.dart';
import 'mora_tracked_origen.dart';

/// Todo lo que un cobro decide sobre la mora: lo que se persiste, lo que se
/// imprime y lo que se muestra. Sale de una sola pasada.
class ResolucionMoraCobro {
  /// Estado de mora que queda en la ficha.
  final EstadoMoraPostCobro estado;

  /// Contrato con ese estado aplicado, listo para la UI y para persistir.
  final ContratoAlumno contratoPatch;

  /// Mora que sigue debiendo después de este cobro. Es el número del aviso
  /// rojo del recibo **y** el que queda en la ficha: sale del mismo cálculo.
  final double moraPendientePost;

  /// De qué cuotas viene esa mora, en una línea. Vacío si no queda nada.
  final String moraPendienteOrigen;

  /// Desglose por cuota vencida impaga que sostiene [moraPendientePost].
  final List<MoraCuotaDetalle> desglosePost;

  /// Remanente de cuotas ya liquidadas incluido en [moraPendientePost].
  final double trackedPost;

  /// La mora dejó de estar suspendida: hay que descongelar la referencia.
  final bool limpiarMoraReferencia;

  const ResolucionMoraCobro({
    required this.estado,
    required this.contratoPatch,
    required this.moraPendientePost,
    required this.moraPendienteOrigen,
    required this.desglosePost,
    required this.trackedPost,
    required this.limpiarMoraReferencia,
  });

  /// El cobro dejó la mora en cero.
  bool get quedaSaldada => moraPendientePost <= 0.01;
}

/// Resuelve la mora de un cobro masivo: estado post-cobro, contrato parcheado y
/// el aviso que va impreso en el recibo.
///
/// Vive acá afuera y no dentro del `onPressed` del modal por un motivo concreto.
/// Mientras fue un tramo suelto de un closure de cientos de líneas, ningún test
/// lo alcanzaba, y así se emitió el recibo Nº 0661293D (BERNEL, 07/08/2026): el
/// contrato simulado para el papel llevaba el tracked y el offset nuevos pero no
/// la exención que ese mismo cobro otorgaba, y el aviso rojo reclamó $2.100 de
/// la cuota 4 — la misma mora que el recibo estaba cobrando dos renglones
/// más arriba. Como función con nombre, el orden queda fijado por un test.
///
/// [contratoPre] es el contrato **antes** del cobro (de ahí salen el desglose y
/// el tracked que se van a cancelar) y [contratoPost] el mismo contrato con el
/// plan ya aplicado (saldo y cuotas nuevas), todavía sin tocar la mora.
ResolucionMoraCobro resolverMoraDeCobro({
  required ContratoAlumno contratoPre,
  required ContratoAlumno contratoPost,
  required double moraCobradaHistorial,
  required double moraEsteCobro,
  required int cuotasBaseLiquidadasEnCobro,
  required int cuotasBasePagadasPostCobro,
  required double saldoDeudorPost,
  required DateTime fechaCobroAr,
  required String Function(double) formatoMonto,

  /// De qué cuotas salió el tracked, si se pudo reconstruir. Sin esto el aviso
  /// solo puede decir "de cuotas ya pagadas".
  List<MoraPendientePreviaDetalle> trackedDetalle = const [],
}) {
  final remanenteMora = contratoPre.moraPendienteTracked.clamp(
    0.0,
    double.infinity,
  );

  // Estado PRE-cobro: es contra esto que se mide lo que el cobro cancela.
  // Todo se ancla a [fechaCobroAr] —no a "ahora"— para que el recibo y la ficha
  // hablen del mismo día aunque el guardado tarde, y para que esto se pueda
  // probar con una fecha fija.
  final desgloseBruto = MoraCuotaCalculator.calcularDesglose(
    contratoPre,
    fechaCobroAr,
  );
  final desgloseNeto = MoraCuotaCalculator.desglosePendiente(
    desgloseBruto,
    MoraCuotaCalculator.moraCobradaParaFifo(
      moraCobradaHistorial: moraCobradaHistorial,
      moraCobradaOffset: contratoPre.moraCobradaOffset,
    ),
  );
  final desgloseNetoTotal = desgloseNeto.fold<double>(
    0,
    (s, d) => s + d.interesBruto,
  );

  final estado = MoraCuotaCalculator.postCobroTrackedOffset(
    moraPendienteTrackedActual: remanenteMora,
    moraCobradaOffsetActual: contratoPre.moraCobradaOffset,
    moraEsteCobro: moraEsteCobro,
    cuotasBaseLiquidadasEnCobro: cuotasBaseLiquidadasEnCobro,
    cuotasBasePagadasPostCobro: cuotasBasePagadasPostCobro,
    moraDesglosePreCobro: desgloseBruto,
    moraDesgloseNetoPreCobro: desgloseNeto,
    moraDesgloseNetoTotal: desgloseNetoTotal,
    saldoDeudorPost: saldoDeudorPost,
    fechaCobroAr: fechaCobroAr,
    exencionActual: contratoPre.moraExentaHasta,
    reiniciaActual: contratoPre.moraExencionReinicia,
  );

  // Acá está el orden que importa: la mora que queda se mide sobre el estado
  // COMPLETO (con exención), no sobre uno a medias. Aplicar el estado y medir
  // son dos pasos del mismo bloque justamente para que no se puedan separar.
  final contratoSim = estado.aplicarA(
    contratoPost,
    moraFechaReferencia: contratoPre.moraFechaReferencia,
  );
  final detallePost = MoraCuotaCalculator.moraPendienteOperativaDetallada(
    contrato: contratoSim,
    moraCobradaHistorial: moraCobradaHistorial + moraEsteCobro,
    ahoraAr: fechaCobroAr,
  );

  final limpiarMoraReferencia =
      MoraCuotaCalculator.debeDescongelarMoraReferencia(
        contrato: contratoPre,
        moraPendienteOperativaPost: detallePost.total,
        saldoDeudorPost: saldoDeudorPost,
      );

  return ResolucionMoraCobro(
    estado: estado,
    // El descongelamiento recién se puede decidir después de medir, así que el
    // contrato definitivo se arma acá, no arriba.
    contratoPatch: estado.aplicarA(
      contratoPost,
      moraFechaReferencia: contratoPre.moraFechaReferencia,
      limpiarMoraReferencia: limpiarMoraReferencia,
    ),
    moraPendientePost: detallePost.total,
    moraPendienteOrigen: MoraConceptoRotulo.origenMoraPendienteLinea(
      desglose: detallePost.desglose,
      tracked: detallePost.tracked,
      trackedDetalle: trackedDetalle,
      formatoMonto: formatoMonto,
    ),
    desglosePost: detallePost.desglose,
    trackedPost: detallePost.tracked,
    limpiarMoraReferencia: limpiarMoraReferencia,
  );
}
