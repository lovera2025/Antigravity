import '../../models/egreso.dart';
import '../cierre_caja/models/turno_caja.dart';

/// Prefijos en [Egreso.proveedor] para distinguir origen del gasto personal.
const String kPrefijoGastoPersonalEmpresa = '[empresa]';
const String kPrefijoGastoPersonalPendiente = '[pendiente]';

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
String proveedorGastoPersonalVisible(String? proveedor) {
  var p = (proveedor ?? '').trim();
  if (p.startsWith(kPrefijoGastoPersonalEmpresa)) {
    p = p.substring(kPrefijoGastoPersonalEmpresa.length).trim();
  } else if (p.startsWith(kPrefijoGastoPersonalPendiente)) {
    p = p.substring(kPrefijoGastoPersonalPendiente.length).trim();
  }
  return p.isEmpty ? 'Gasto personal' : p;
}

/// Egresos que restan saldo empresa en el HUD / caja contable.
bool finanzasEgresoAfectaCajaEmpresa(Egreso e) {
  final cat = (e.categoria ?? '').trim();
  if (cat == kCategoriaGastoPersonal) {
    return gastoPersonalEsDesdeEmpresa(e);
  }
  return true;
}

/// Gastos personales que consumen retiro pendiente (no impactan empresa otra vez).
bool finanzasGastoPersonalConsumePendiente(Egreso e) {
  if ((e.categoria ?? '').trim() != kCategoriaGastoPersonal) return false;
  return gastoPersonalEsDesdePendiente(e) || gastoPersonalEsLegacySinPrefijo(e);
}
