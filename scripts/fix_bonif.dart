import 'dart:io';

void main() {
  final file = File('lib/features/eventos/detalle_evento_particular_screen.dart');
  var content = file.readAsStringSync();

  content = content.replaceAll(
    'final totalPresupuestoEl = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));',
    'final totalPresupuestoElBase = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));\\n    final double bonificacionEl = widget.evento.bonificacionGlobalPct ?? 0;\\n    final totalPresupuestoEl = totalPresupuestoElBase * (1 - (bonificacionEl / 100));'
  );

  content = content.replaceAll(
    'final totalPresupuesto = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));',
    'final totalPresupuestoBase = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));\\n    final double bonificacion = widget.evento.bonificacionGlobalPct ?? 0;\\n    final totalPresupuesto = totalPresupuestoBase * (1 - (bonificacion / 100));'
  );

  content = content.replaceAll(
    'final presupuestoTotal = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));',
    'final presupuestoTotalBase = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));\\n    final double bonificacion = widget.evento.bonificacionGlobalPct ?? 0;\\n    final presupuestoTotal = presupuestoTotalBase * (1 - (bonificacion / 100));'
  );

  content = content.replaceAll(
    'final double totalPresupuesto = _servicios.fold(0, (sum, s) => sum + (s.precioFinalAcordado * s.cantidad));',
    'final double totalPresupuestoBase = _servicios.fold(0, (sum, s) => sum + (s.precioFinalAcordado * s.cantidad));\\n    final double bonificacion = widget.evento.bonificacionGlobalPct ?? 0;\\n    final double totalPresupuesto = totalPresupuestoBase * (1 - (bonificacion / 100));'
  );

  file.writeAsStringSync(content.replaceAll('\\n', '\n'));
  print('Replaced correctly!');
}
