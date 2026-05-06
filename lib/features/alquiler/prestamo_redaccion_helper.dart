import 'package:intl/intl.dart';

import '../../models/prestamo_alquiler.dart';
import '../common/utils/currency_extensions.dart';

/// Redacción contextual determinística (sin API externa) para el PDF de préstamo.
class PrestamoRedaccionHelper {
  static String disclaimerPredeterminado() {
    return 'El depositario se responsabiliza por la custodia y buen uso de los ítems entregados. '
        'Ante pérdida, rotura o deterioro imputable, deberá reintegrar su valor de reposición o '
        'el costo de reparación que determine Junior Eventos, sin perjuicio de otros reclamos. '
        'La no devolución en la fecha acordada podrá generar cargos adicionales por día o fracción.';
  }

  static String generarCuerpo({
    required String nombreCliente,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required List<PrestamoAlquilerLinea> lineas,
    required double subtotalNeto,
    required double montoIva,
    required double total,
    required bool aplicaIva,
    required double alicuotaIva,
  }) {
    final fmt = DateFormat('dd/MM/yyyy');
    final detalle = lineas.map((l) {
      final q = l.cantidad == l.cantidad.roundToDouble()
          ? l.cantidad.toStringAsFixed(0)
          : l.cantidad.toStringAsFixed(2);
      final pu = l.precioUnitario.toCurrency();
      final sub = l.lineaTotal.toCurrency();
      return '$q × ${l.descripcion} a $pu c/u (subtotal $sub)';
    }).join('; ');

    final montoCierre = StringBuffer()
      ..write('El valor total del presente préstamo asciende a ${total.toCurrency()}');
    if (aplicaIva && montoIva > 0) {
      montoCierre.write(
        ', conformado por un subtotal de ${subtotalNeto.toCurrency()} más IVA ${alicuotaIva.toStringAsFixed(0)}% (${montoIva.toCurrency()}).',
      );
    } else {
      montoCierre.write(' (${subtotalNeto.toCurrency()}, sin IVA).');
    }

    return 'Por el presente documento, Junior Eventos entrega en préstamo a $nombreCliente el siguiente '
        'equipamiento y/o mobiliario: $detalle. El período convenido de uso abarca desde el ${fmt.format(fechaInicio)} '
        'hasta el ${fmt.format(fechaFin)}, debiendo el depositario devolver los bienes en igual estado de conservación, '
        'salvo el desgaste normal de uso adecuado. ${montoCierre.toString()} Cualquier aclaración operativa queda registrada en este acta.';
  }
}
