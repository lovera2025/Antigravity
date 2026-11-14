import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../eventos/services/retiro_entradas.dart';
import '../datos/anulacion_entradas.dart';
import '../datos/venta_entradas.dart';

/// La anulación de cada venta anulada (id de la venta → su anulación). Una
/// venta que no está acá cuenta.
Map<String, AnulacionEntradas> anulacionesPorVenta(
  Iterable<AnulacionEntradas> anulaciones,
) =>
    {for (final a in anulaciones) a.ventaId: a};

/// Cuántas entradas de sus lugares adicionales ya compró cada familia (id del
/// alumno → cantidad), en ventas **no anuladas**. Es lo que muestra la entrega
/// al lado de cada una: "8 al 50 % (compró 3)".
Map<String, int> compradasPorFamilia(
  Iterable<VentaEntradas> ventas,
  Iterable<AnulacionEntradas> anulaciones,
) {
  final anuladas = anulacionesPorVenta(anulaciones);
  final out = <String, int>{};
  for (final v in ventas) {
    final familia = v.contratoAlumnoId;
    if (familia == null || anuladas.containsKey(v.id)) continue;
    final n = v.cuantas(TipoRenglonEntradas.lugar);
    if (n > 0) out[familia] = (out[familia] ?? 0) + n;
  }
  return out;
}

/// Las entradas de la mesa adicional y las sillas extra de una familia: cuántas
/// le corresponden comprar con el descuento de la fiesta, cuántas ya compró y
/// cuántas le quedan.
///
/// **No se guarda en ningún lado: se cuenta cada vez**, de la cuenta del alumno
/// y de las ventas. Así no hay dos lugares que digan cosas distintas.
class LugaresDeLaFamilia {
  /// Las de sus lugares adicionales (`EntradasDeAlumno.alCincuenta`).
  final int leCorresponden;

  /// Las que ya compró, en ventas que cuentan.
  final int compradas;

  const LugaresDeLaFamilia({
    required this.leCorresponden,
    required this.compradas,
  });

  /// Quien no es una familia de la fiesta: no le corresponde ninguna.
  static const ninguno = LugaresDeLaFamilia(leCorresponden: 0, compradas: 0);

  factory LugaresDeLaFamilia.de(
    ContratoAlumno alumno, {
    required Iterable<VentaEntradas> ventas,
    required Iterable<AnulacionEntradas> anulaciones,
  }) =>
      LugaresDeLaFamilia(
        leCorresponden: RetiroEntradas.entradasDe(alumno).alCincuenta,
        compradas: compradasPorFamilia(ventas, anulaciones)[alumno.id] ?? 0,
      );

  /// Las que todavía puede comprar con el descuento. **No se le venden más que
  /// estas**: si quiere más entradas, van sueltas, a precio de lista. Nunca
  /// baja de cero (si le sacaron una silla después de comprar, quedan 0).
  int get quedan => max(0, leCorresponden - compradas);
}
