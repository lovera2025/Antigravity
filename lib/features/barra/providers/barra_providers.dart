import 'dart:async';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../models/evento.dart';
import '../../common/services/pdf_service.dart';
import '../../common/utils/subir_ya.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../../eventos/repositories/eventos_repository.dart';
import '../datos/barra_local.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/canal_universal_ble.dart';
import '../impresion/impresora_bluetooth.dart';
import '../impresion/papel_pdf.dart';
import '../impresion/ticket_esc_pos.dart';
import '../services/barra_sin_internet.dart';
import '../services/fiestas_de_la_barra.dart';
import '../services/papel_de_la_barra.dart';

/// La barra de este equipo: la base y la cola de subida. Los tests la reemplazan.
final barraDeLaCajaProvider = Provider<BarraDeLaCaja>((ref) => BarraLocal());

/// Todos los eventos de este equipo. Los tests lo reemplazan.
final eventosDeLaBarraProvider = FutureProvider<List<Evento>>((ref) async {
  ref.watch(operationalSyncRevisionProvider);
  return ref.read(eventosRepositoryProvider).getAll();
});

/// Las fiestas que la cajera puede elegir: con precios en este equipo y por hacer. Se
/// vuelve a leer cuando baja algo de la nube: en una tablet recién preparada, los
/// precios llegan después de abrir esto.
final fiestasDeLaBarraProvider = FutureProvider<List<Evento>>((ref) async {
  ref.watch(operationalSyncRevisionProvider);
  final eventos = await ref.watch(eventosDeLaBarraProvider.future);
  final conPrecio = await ref.read(barraDeLaCajaProvider).fiestasConPrecio();
  return fiestasParaLaBarra(eventos, conPrecio, DateTime.now());
});

/// La impresora de este equipo, una sola mientras dure la app: se conecta sola a la
/// recordada.
final impresoraDeLaBarraProvider = Provider<ImpresoraBluetooth>(
  (ref) => ImpresoraBluetooth(CanalUniversalBle(), recordada: const ImpresoraRecordada()),
);

/// Por dónde salen los papeles de la barra. Los tests lo reemplazan por uno en memoria.
final papelDeLaBarraProvider = Provider<PapelDeLaBarra>(
  (ref) => PapelPorBluetooth(ref.watch(impresoraDeLaBarraProvider)),
);

/// Sube ya una venta recién guardada, si hay internet: así el jefe la ve enseguida.
/// Sin internet queda en la cola y sube sola al volver. Los tests lo reemplazan.
final subirVentaProvider = Provider<Future<void> Function(VentaBarra venta)>((ref) {
  return (venta) async {
    if (ref.read(connectivityServiceProvider).currentStatus == AppConnectivity.offline) return;
    try {
      await ref.read(subidaInmediataProvider).subir(
            tabla: 'barra_ventas',
            registroId: venta.id,
            desde: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
          );
    } catch (_) {}
  };
});

/// Sube ya una fila de la barra que no es una venta (una anulación, un vale que salió),
/// si hay internet: así el jefe la ve enseguida, y una anulación llega a la puerta. Sin
/// internet queda en la cola. Los tests lo reemplazan.
final subirDeLaBarraProvider =
    Provider<Future<void> Function(String tabla, String registroId)>((ref) {
  return (tabla, registroId) async {
    if (ref.read(connectivityServiceProvider).currentStatus == AppConnectivity.offline) return;
    try {
      await ref.read(subidaInmediataProvider).subir(
            tabla: tabla,
            registroId: registroId,
            desde: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
          );
    } catch (_) {}
  };
});

/// Guarda un papel de la barra como PDF de 58 mm (`PapelPdf`, con las letras de la app)
/// y lo entrega: en Windows con el menú de ver o guardar, en Android para compartir. Los
/// tests lo reemplazan.
typedef GuardarPdfDeLaBarra = Future<void> Function(
  List<LineaTicket> lineas, {
  required String titulo,
  required String nombre,
  BuildContext? context,
});

final guardarPdfDeLaBarraProvider = Provider<GuardarPdfDeLaBarra>((ref) {
  return (lineas, {required titulo, required nombre, context}) async {
    final bytes = await PapelPdf.armar(
      lineas,
      titulo: titulo,
      fuentes: await PdfService.fuentesOutfit(),
    );
    if (context != null && !context.mounted) return;
    await PdfService.entregarPdf(bytes, nombre, context: context);
  };
});

/// Con qué se pone al día la barra en este equipo. Los tests lo reemplazan.
final accesosBarraProvider = Provider<AccesosBarra>((ref) {
  final barra = ref.watch(barraDeLaCajaProvider);
  final motor = ref.watch(syncEngineProvider);
  return AccesosBarra(
    bajar: motor.bajarParaLaBarra,
    contarFiestas: () async => (await barra.fiestasConPrecio()).length,
    contarSinSubir: barra.ventasSinSubir,
  );
});

/// "Lista para trabajar sin internet" de la barra: se pone al día mientras la cajera
/// tiene abierta su pantalla, y sigue a la conexión.
final puestaAlDiaBarraProvider = Provider.autoDispose<PuestaAlDiaBarra>((ref) {
  final conexion = ref.watch(connectivityServiceProvider);
  final puesta = PuestaAlDiaBarra(
    accesos: ref.watch(accesosBarraProvider),
    hayInternet: conexion.currentStatus != AppConnectivity.offline,
  );
  unawaited(puesta.arrancar());
  final sub = conexion.stream.listen(
    (estado) => puesta.conexion(estado != AppConnectivity.offline),
  );
  ref.onDispose(() {
    sub.cancel();
    puesta.dispose();
  });
  return puesta;
});

/// Con qué arranca el recargo de un cobro: **el que puso el jefe para la fiesta**
/// (decidido el 3-nov; en 0, apagado) y, si no lo puso, el último que usó el equipo.
/// La cajera lo puede cambiar en ese cobro; el siguiente vuelve a arrancar acá.
({bool prendido, double pct}) recargoDeArranque(
  RecargoBarra? deLaFiesta,
  ({bool prendido, double pct}) recordado,
) {
  if (deLaFiesta == null) return recordado;
  if (deLaFiesta.prendido) return (prendido: true, pct: deLaFiesta.pct);
  return (prendido: false, pct: recordado.pct);
}

/// El recargo por transferencia como lo dejó este equipo la última vez: prendido o no,
/// y el porcentaje. Vale cuando el jefe no puso el de la fiesta ([recargoDeArranque]);
/// la primera vez, 5 %.
class RecargoRecordado {
  static const _prendido = 'barra.recargo.prendido';
  static const _pct = 'barra.recargo.pct';
  static const pctDeArranque = 5.0;

  const RecargoRecordado();

  Future<({bool prendido, double pct})> leer() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (
        prendido: p.getBool(_prendido) ?? true,
        pct: p.getDouble(_pct) ?? pctDeArranque,
      );
    } catch (_) {
      return (prendido: true, pct: pctDeArranque);
    }
  }

  Future<void> guardar({required bool prendido, required double pct}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prendido, prendido);
      await p.setDouble(_pct, pct);
    } catch (_) {}
  }
}

final recargoRecordadoProvider = Provider<RecargoRecordado>((ref) => const RecargoRecordado());
