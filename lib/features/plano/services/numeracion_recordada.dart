import '../../../models/plano_evento.dart';
import '../modelo/numeracion.dart';

/// La última numeración que se eligió en Acomodar, en cualquier fiesta
/// (6.5.1, pedido del usuario el 11-nov-2026: "si yo configuro que quiero al
/// fondo, ya debe quedar guardado para cada fiesta, salvo que yo cambie
/// después").
///
/// **No hay tabla ni preferencia nueva.** Cada elección queda anotada en la
/// `config` del plano de su fiesta (`numeracion` y `numeracion_el`), que ya se
/// sincroniza entre las PCs; la recordada es la más nueva de todos los planos
/// que esta PC tiene en su base. Por eso vale en las tres PCs: llega cuando
/// baja ese plano, como cualquier cambio del salón.
///
/// A quién se le aplica lo decide `SesionAcomodo`: solo a una fiesta que
/// **nunca eligió**, sin familias con mesa y en un salón a medida, y los
/// números cambian recién cuando el jefe guarda. Nada cambia solo.
class NumeracionRecordada {
  final FinNumeracion fin;

  /// Cuándo se eligió. Null: una elección de antes de que se anotara el
  /// momento; cuenta como la más vieja.
  final DateTime? el;

  const NumeracionRecordada(this.fin, this.el);

  /// La elección más nueva entre las configs de todas las fiestas, o null si
  /// nunca nadie eligió nada: ahí todo sigue como siempre.
  static NumeracionRecordada? de(Iterable<ConfigPlano> configs) {
    NumeracionRecordada? r;
    for (final c in configs) {
      if (!c.eligioNumeracion) continue;
      final el = c.numeracionEl;
      if (r == null || _esPosterior(el, r.el)) {
        r = NumeracionRecordada(c.numeracion, el);
      }
    }
    return r;
  }

  static bool _esPosterior(DateTime? a, DateTime? b) =>
      a != null && (b == null || a.isAfter(b));

  @override
  bool operator ==(Object other) =>
      other is NumeracionRecordada && other.fin == fin && other.el == el;

  @override
  int get hashCode => Object.hash(fin, el);

  @override
  String toString() => 'NumeracionRecordada(${fin.name}, $el)';
}
