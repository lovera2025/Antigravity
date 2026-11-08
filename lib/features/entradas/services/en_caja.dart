import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/contrato_alumno.dart';
import '../../eventos/services/retiro_entradas.dart';

/// Una familia que el mostrador mandó a la caja porque debía.
class FamiliaEnCaja {
  final String alumnoId;
  final String nombre;

  /// Lo que debía cuando se la mandó.
  final double debia;

  /// Lo que debe según la última lectura.
  final double debe;

  /// Ya no debe nada: la entrega se destrabó.
  final bool pago;

  const FamiliaEnCaja({
    required this.alumnoId,
    required this.nombre,
    required this.debia,
    required this.debe,
    this.pago = false,
  });

  /// Pagó algo pero no todo: "pagó una parte · faltan $Y".
  bool get pagoUnaParte => !pago && debe < debia - RetiroEntradas.margen;

  FamiliaEnCaja con({required double debe, required bool pago}) => FamiliaEnCaja(
        alumnoId: alumnoId,
        nombre: nombre,
        debia: debia,
        debe: debe,
        pago: pago,
      );
}

/// Las familias que el mostrador de Entradas mandó a pagar a la caja, por fiesta.
///
/// Es memoria de esta sesión, no un dato: no se guarda ni viaja. Sirve para que,
/// cuando la caja (en otra PC o en esta) cobra y el pago baja, el mostrador avise
/// "PÉREZ pagó: ya podés entregar" sin que nadie tenga que buscarla de nuevo.
class EnCaja {
  /// En el orden en que se mandaron.
  final List<FamiliaEnCaja> familias;

  const EnCaja([this.familias = const []]);

  bool get vacia => familias.isEmpty;

  /// Las que todavía deben (la caja de "En caja").
  List<FamiliaEnCaja> get esperando => [for (final f in familias) if (!f.pago) f];

  /// Las que ya pagaron todo (los avisos verdes).
  List<FamiliaEnCaja> get pagaron => [for (final f in familias) if (f.pago) f];

  bool contiene(String alumnoId) => familias.any((f) => f.alumnoId == alumnoId);

  /// La manda a la caja con lo que debe hoy. Si ya estaba, la deja como estaba.
  EnCaja mandar(ContratoAlumno a, DeudaAlumno deuda) {
    if (contiene(a.id)) return this;
    return EnCaja([
      ...familias,
      FamiliaEnCaja(
        alumnoId: a.id,
        nombre: a.nombreAlumno.trim(),
        debia: deuda.total,
        debe: deuda.total,
        pago: deuda.pagoTodo,
      ),
    ]);
  }

  /// Ya se le entregó, o el operador la sacó con la ✕.
  EnCaja sacar(String alumnoId) =>
      EnCaja([for (final f in familias) if (f.alumnoId != alumnoId) f]);

  /// Con las deudas recién leídas. [recienPagaron] son las que pasaron a "pagó"
  /// en esta lectura: con esas suena el aviso, una sola vez.
  ({EnCaja enCaja, List<FamiliaEnCaja> recienPagaron}) conDeudas(
    Map<String, DeudaAlumno> deudas,
  ) {
    final nuevas = <FamiliaEnCaja>[];
    final recien = <FamiliaEnCaja>[];
    for (final f in familias) {
      final d = deudas[f.alumnoId];
      // Un alumno que ya no está (de baja, eliminado) sale de la lista.
      if (d == null) continue;
      final nueva = f.con(debe: d.total, pago: d.pagoTodo);
      if (nueva.pago && !f.pago) recien.add(nueva);
      nuevas.add(nueva);
    }
    return (enCaja: EnCaja(nuevas), recienPagaron: recien);
  }
}

/// "En caja" de cada fiesta. Sin `autoDispose`: sobrevive a salir de la entrega,
/// pasar a la caja a cobrar y volver con ENTRADAS.
final enCajaProvider =
    NotifierProvider.family<EnCajaDeLaFiesta, EnCaja, String>(EnCajaDeLaFiesta.new);

class EnCajaDeLaFiesta extends Notifier<EnCaja> {
  EnCajaDeLaFiesta(this.eventoId);

  final String eventoId;

  @override
  EnCaja build() => const EnCaja();

  void mandar(ContratoAlumno a, DeudaAlumno deuda) => state = state.mandar(a, deuda);

  void sacar(String alumnoId) => state = state.sacar(alumnoId);

  /// Devuelve las que acaban de pagar, para el sonido.
  List<FamiliaEnCaja> conDeudas(Map<String, DeudaAlumno> deudas) {
    if (state.vacia) return const [];
    final r = state.conDeudas(deudas);
    state = r.enCaja;
    return r.recienPagaron;
  }
}
