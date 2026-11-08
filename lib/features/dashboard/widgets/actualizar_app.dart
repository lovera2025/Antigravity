import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_update_checker.dart';
import 'app_update_download_dialog.dart';
import 'app_update_whats_new_dialog.dart';

/// En la tablet, si hay una versión nueva en GitHub: la pantalla del PIN lo dice
/// arriba. Una consulta cada vez que se abre esa pantalla (no una por día, como
/// en la PC): el jefe la abre antes de la fiesta para ver si está al día. En la
/// PC y en la web, nunca.
final versionNuevaEnLaTabletProvider =
    FutureProvider.autoDispose<AppUpdateInfo?>((ref) async {
  if (!AppUpdateChecker.enAndroid) return null;
  final info = await AppUpdateChecker().consultar();
  return (info != null && info.hayNueva) ? info : null;
});

/// Lo que se le dice a la tablet después de abrir la descarga del APK.
const kAvisoDescargaApk =
    'Se abrió la descarga. Cuando termine, tocá el archivo para instalar la versión nueva.';

/// Hay una versión nueva: las novedades y, si quiere, DESCARGAR.
///
/// En la PC baja el Setup y abre el instalador. En una tablet (6.4.0) abre el APK
/// en el navegador: lo baja y Android ofrece instalarlo (la primera vez pide
/// permitir "instalar apps desconocidas" al navegador). Lo usan el panel y, en
/// Android, la pantalla del PIN (`RoleGateScreen`), que es la primera de la tablet.
Future<void> mostrarDialogoActualizacion(
  BuildContext context,
  AppUpdateInfo info, {
  Future<bool> Function(Uri url)? abrirEnElNavegador,
}) async {
  final quiereDescargar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppUpdateWhatsNewDialog(
      version: info.latestVersion,
      notes: info.notes,
      showLater: true,
    ),
  );
  if (quiereDescargar != true || !context.mounted) return;
  await AppUpdateChecker.markWhatsNewSeen(info.latestVersion);
  if (!context.mounted) return;

  if (AppUpdateChecker.enAndroid) {
    final abrir = abrirEnElNavegador ??
        (url) => launchUrl(url, mode: LaunchMode.externalApplication);
    bool abrio;
    try {
      abrio = await abrir(Uri.parse(info.descargaEnAndroid));
    } catch (e) {
      debugPrint('No se pudo abrir la descarga del APK: $e');
      abrio = false;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          abrio
              ? kAvisoDescargaApk
              : 'No se pudo abrir la descarga. Probá de nuevo con internet.',
        ),
      ),
    );
    return;
  }

  final result = await showDialog<AppUpdateDownloadResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AppUpdateDownloadDialog(info: info),
  );
  if (!context.mounted) return;
  if (result == AppUpdateDownloadResult.success) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Se abrió el instalador. Seguí los pasos; puede pedir cerrar Junior Eventos.',
        ),
      ),
    );
  }
}

/// Primera apertura de una versión que todavía no se acusó. Sin MÁS TARDE.
Future<void> mostrarNovedadesSiPrimeraApertura(
  BuildContext context,
  AppUpdateChecker checker,
) async {
  final current = await checker.currentVersion();
  final seen = await AppUpdateChecker.whatsNewSeenVersion();
  if (!context.mounted) return;
  if (seen == current) return;
  final info = await checker.consultar();
  if (!context.mounted) return;
  if (info != null && info.hayNueva) return;
  final notes = (info != null && info.latestVersion == current)
      ? info.notes
      : 'Junior Eventos $current está lista.';
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AppUpdateWhatsNewDialog(
      version: current,
      notes: notes,
      alreadyInstalled: true,
    ),
  );
  if (accepted == true) {
    await AppUpdateChecker.markWhatsNewSeen(current);
  }
}
