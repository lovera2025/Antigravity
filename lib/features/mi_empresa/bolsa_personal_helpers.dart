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

/// Gastos personales que consumen retiro pendiente (no impactan empresa otra vez).
bool finanzasGastoPersonalConsumePendiente(Egreso e) {
  if ((e.categoria ?? '').trim() != kCategoriaGastoPersonal) return false;
  return gastoPersonalEsDesdePendiente(e) || gastoPersonalEsLegacySinPrefijo(e);
}
