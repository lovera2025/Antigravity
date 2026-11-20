import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import '../../../models/evento.dart';
import '../../eventos/services/retiro_entradas.dart';
import 'pdf_service.dart';

/// La planilla de entrega en papel, una por material (PLANILLA de VENDER y la
/// impresora de la entrega): arma el PDF y lo abre. **Las ventanas de prueba la
/// reemplazan** para que no escriban en la carpeta de PDF del programa
/// instalado (revisión del 20-nov-2026: la de la venta de entradas la dejaba
/// ahí, y el recorrido con el mouse pasa por VENDER).
typedef ImprimirPlanillaDeEntrega = Future<void> Function(
  Evento evento,
  List<ContratoAlumno> alumnos, {
  required ParteEntrega material,
  required Map<String, EntradasRetiro> retiros,
  List<EntregaEntradas> renglones,
  required Map<String, DeudaAlumno> deudas,
  bool blancoYNegro,
});

final imprimirPlanillaDeEntregaProvider = Provider<ImprimirPlanillaDeEntrega>(
  (ref) => PdfService.generarPlanillaEntrega,
);
