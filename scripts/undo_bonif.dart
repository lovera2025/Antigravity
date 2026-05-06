import 'dart:io';

void main() {
  final file = File('lib/features/eventos/detalle_evento_particular_screen.dart');
  var content = file.readAsStringSync();

  content = content.replaceAll(RegExp(r'final totalPresupuestoElBase = _servicios\.fold<double>\(0, \(sum, item\) => sum \+ \(item\.precioFinalAcordado \* item\.cantidad\)\);\s*final double bonificacionEl = widget\.evento\.bonificacionGlobalPct \?\? 0;\s*final totalPresupuestoEl = totalPresupuestoElBase \* \(1 - \(bonificacionEl / 100\)\);'), 'final totalPresupuestoEl = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));');

  content = content.replaceAll(RegExp(r'final totalPresupuestoBase = _servicios\.fold<double>\(0, \(sum, item\) => sum \+ \(item\.precioFinalAcordado \* item\.cantidad\)\);\s*final double bonificacion = widget\.evento\.bonificacionGlobalPct \?\? 0;\s*final totalPresupuesto = totalPresupuestoBase \* \(1 - \(bonificacion / 100\)\);'), 'final totalPresupuesto = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));');

  content = content.replaceAll(RegExp(r'final presupuestoTotalBase = _servicios\.fold<double>\(0, \(sum, item\) => sum \+ \(item\.precioFinalAcordado \* item\.cantidad\)\);\s*final double bonificacion = widget\.evento\.bonificacionGlobalPct \?\? 0;\s*final presupuestoTotal = presupuestoTotalBase \* \(1 - \(bonificacion / 100\)\);'), 'final presupuestoTotal = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));');

  content = content.replaceAll(RegExp(r'final double totalPresupuestoBase = _servicios\.fold\(0, \(sum, s\) => sum \+ \(s\.precioFinalAcordado \* s\.cantidad\)\);\s*final double bonificacion = widget\.evento\.bonificacionGlobalPct \?\? 0;\s*final double totalPresupuesto = totalPresupuestoBase \* \(1 - \(bonificacion / 100\)\);'), 'final double totalPresupuesto = _servicios.fold(0, (sum, s) => sum + (s.precioFinalAcordado * s.cantidad));');

  file.writeAsStringSync(content);
  print('Reverted correctly using RegExp!');
}
