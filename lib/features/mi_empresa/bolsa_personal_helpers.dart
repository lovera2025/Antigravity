import '../../models/egreso.dart';
import '../cierre_caja/models/turno_caja.dart';

// Los prefijos viven en el modelo (`egreso.dart`) junto a
// [Egreso.proveedorVisible], que es quien los saca para mostrar. Se re-exportan
// para no romper los imports que ya los tomaban de acá.
export '../../models/egreso.dart'
    show kPrefijoGastoPersonalEmpresa, kPrefijoGastoPersonalPendiente;

bool gastoPersonalEsDesdeEmpresa(Egreso e) {
  final p = (e.proveedor ?? '').trim();
  return p.startsWith(kPrefijoGastoPersonalEmpresa);
}

bool gastoPersonalEsDesdePendiente(Egreso e) {
  final p = (e.proveedor ?? '').trim();
  return p.startsWith(kPrefijoGastoPersonalPendiente);
}

/// Gasto personal legacy (sin prefijo): pagado desde retiro pendiente, no resta empresa otra vez.
bool gastoPersonalEsLegacySinPrefijo(Egreso e) {
  if ((e.categoria ?? '').trim() != kCategoriaGastoPersonal) return false;
  final p = (e.proveedor ?? '').trim();
  return !p.startsWith(kPrefijoGastoPersonalEmpresa) &&
      !p.startsWith(kPrefijoGastoPersonalPendiente);
}

String empaquetarProveedorGastoEmpresa(String concepto) {
  final c = concepto.trim();
  if (c.startsWith(kPrefijoGastoPersonalEmpresa)) return c;
  return '$kPrefijoGastoPersonalEmpresa $c';
}

String empaquetarProveedorGastoPendiente(String concepto) {
  final c = concepto.trim();
  if (c.startsWith(kPrefijoGastoPersonalPendiente)) return c;
  return '$kPrefijoGastoPersonalPendiente $c';
}

/// Texto visible al usuario (sin prefijo técnico).
///
/// Preferir [Egreso.proveedorVisible] cuando se tiene el egreso entero: esta
/// versión existe para los casos en que solo se cuenta con el string suelto.
String proveedorGastoPersonalVisible(String? proveedor) =>
    Egreso(id: '', eventoId: '', monto: 0, proveedor: proveedor)
        .proveedorVisible ??
    'Gasto personal';

/// Egresos que restan saldo empresa en el HUD / caja contable.
bool finanzasEgresoAfectaCajaEmpresa(Egreso e) {
  // Salió del bolsillo del dueño: al negocio ya le restó el día que se retiró
  // esa plata. Contarlo otra vez sería restar dos veces la misma salida.
  //
  // `origen_fondos` es NULL en todo lo histórico y NULL no entra acá, así que
  // esta rama no cambia ni un peso de lo ya registrado.
  if (e.salioDelBolsillo) return false;

  final cat = (e.categoria ?? '').trim();
  if (cat == kCategoriaGastoPersonal) {
    return gastoPersonalEsDesdeEmpresa(e);
  }
  return true;
}

/// Lo que queda en el bolsillo del dueño, en total y por medio.
///
/// El total es lo apartado menos lo gastado, sin mirar el medio. Por medio es
/// lo mismo, pero nunca menos de cero ni más que el total. Si se apartó del
/// banco y se gastó en efectivo, un medio da negativo y el otro positivo. Antes
/// el total era la suma de los dos después de llevar el negativo a cero, y eso
/// inventaba plata: el 29-sep, al partir un retiro entre efectivo y banco, MI
/// BOLSILLO pasó de $0 a $20,3M sin que nadie apartara nada.
({double total, double efectivo, double transferencia}) saldoBolsillo({
  required double apartadoEfectivo,
  required double apartadoTransferencia,
  required double gastadoEfectivo,
  required double gastadoTransferencia,
}) {
  double entre0yTotal(double v, double total) =>
      v < 0 ? 0 : (v > total ? total : v);
  final total = (apartadoEfectivo +
          apartadoTransferencia -
          gastadoEfectivo -
          gastadoTransferencia)
      .clamp(0.0, double.infinity);
  return (
    total: total,
    efectivo: entre0yTotal(apartadoEfectivo - gastadoEfectivo, total),
    transferencia:
        entre0yTotal(apartadoTransferencia - gastadoTransferencia, total),
  );
}

/// Gastos personales que consumen retiro pendiente (no impactan empresa otra vez).
bool finanzasGastoPersonalConsumePendiente(Egreso e) {
  if ((e.categoria ?? '').trim() != kCategoriaGastoPersonal) return false;
  return gastoPersonalEsDesdePendiente(e) || gastoPersonalEsLegacySinPrefijo(e);
}
