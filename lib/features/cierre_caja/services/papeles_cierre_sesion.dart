import '../../caja_sesiones/models/sesion_caja.dart';
import '../../common/services/pdf_service.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../mi_empresa/repositories/finanzas_repository.dart';
import '../models/turno_caja.dart';
import '../repositories/cierre_caja_repository.dart';
import 'datos_cierre_sesion.dart';

/// Emite el papel del cierre de una sesión: **un archivo, una hoja A4**, con el
/// resumen y el arqueo arriba y el detalle por alumno abajo.
///
/// Se llama con la sesión **ya cerrada** (con su `cerradaAt` y su arqueo) y lee
/// todo de SQLite, así que funciona igual después de que el operario se
/// deslogueó. Los repos vienen por parámetro y no por `ref` para que quien lo
/// llame pueda capturarlos antes del logout.
Future<void> emitirPapelesDeCierre({
  required SesionCaja cerrada,
  required FinanzasRepository finanzasRepo,
  required EgresosRepository egresosRepo,
  required CierreCajaRepository cierreRepo,
  String? emitidoPor,
}) async {
  final datos = await cargarDatosCierreSesion(
    sesionIds: {cerrada.id},
    finanzasRepo: finanzasRepo,
    egresosRepo: egresosRepo,
  );
  // La anotación y la guía de cambio se piden acá y no en cargarDatosCierreSesion
  // porque son datos de presentación del papel, no plata que haya que clasificar.
  String? anotacion;
  double guiaSaldo = 0;
  try {
    anotacion = await cierreRepo.obtenerAnotacionTexto(cerrada.id);
    final guia = await cierreRepo.obtenerGuiaCambioSesiones({cerrada.id});
    guiaSaldo = guia.saldoActual;
  } catch (_) {
    // Son adornos del papel: si fallan, la hoja sale igual con lo que importa.
  }

  await PdfService.generarHojaCierreSesionPdf(
    sesion: cerrada,
    datos: datos,
    turno: turnoDeSesion(cerrada),
    emitidoPor: emitidoPor,
    anotacion: (anotacion ?? '').trim().isEmpty ? null : anotacion!.trim(),
    guiaCambioSaldo: guiaSaldo,
  );
}
