import '../../barra/datos/barra_repositorio.dart';
import 'sillas_de_la_puerta.dart' show valeNormalizado;

/// Los vales de la barra cuya venta se anuló (6.4.0, decisión del usuario del 6-nov).
///
/// La familia paga la silla en la barra y la puerta la suma con el número del vale
/// ("Caja 2 · N° 0017" → "2-17"). Si después la barra anula esa venta, la silla quedó
/// sin pagar: Recepción la marca en rojo ("vale anulado en la barra: revisar") y la
/// recepcionista la quita con motivo. **No se saca sola:** queda la huella.
///
/// El vale no lleva QR: solo la caja y el número. Se arma desde las cajas, las ventas y
/// las anulaciones de la fiesta que tiene esta PC; sin esos datos (sin internet, la web)
/// no hay ninguno, y la puerta sigue como siempre.
class ValesAnulados {
  /// "caja-número" de cada venta anulada.
  final Set<String> _anulados;

  const ValesAnulados._(this._anulados);

  static const ninguno = ValesAnulados._({});

  /// Desde la barra de la fiesta. **Si un mismo "caja-número" está en dos cajas (dos
  /// cajas con el mismo número) y una no está anulada, no se marca**: nunca acusar por
  /// error.
  factory ValesAnulados.de({
    required List<CajaBarra> cajas,
    required List<VentaBarra> ventas,
    required List<AnulacionBarra> anulaciones,
  }) {
    final numeroDeCaja = {for (final c in cajas) c.id: c.numeroCaja};
    final anuladas = {for (final a in anulaciones) a.ventaId};
    final porVale = <String, List<bool>>{};
    for (final v in ventas) {
      final caja = numeroDeCaja[v.cajaBarraId];
      if (caja == null) continue;
      porVale.putIfAbsent('$caja-${v.numero}', () => []).add(anuladas.contains(v.id));
    }
    return ValesAnulados._({
      for (final e in porVale.entries)
        if (e.value.every((anulada) => anulada)) e.key,
    });
  }

  /// Los que mandó la central ([toJson]).
  factory ValesAnulados.fromJson(Object? json) => json is List
      ? ValesAnulados._({for (final v in json) if (v is String) v})
      : ninguno;

  bool get vacio => _anulados.isEmpty;

  /// Si el vale de una silla es de una venta anulada. Cuentan la caja y el número
  /// ("2-17-1" es la venta 2-17); un vale sin la caja ("17") nunca, porque no se sabe de
  /// qué caja es.
  bool estaAnulado(String? vale) {
    final partes = valeNormalizado(vale)?.split('-');
    if (partes == null || partes.length < 2) return false;
    return _anulados.contains('${partes[0]}-${partes[1]}');
  }

  List<String> toJson() => [..._anulados]..sort();
}
