import 'dart:io';

import 'package:http/http.dart' as http;

/// Baja el Setup de GitHub a temp y lo abre con ShellExecute (UAC).
class AppUpdateDownloader {
  AppUpdateDownloader({
    http.Client? httpClient,
    Future<void> Function(String path)? launchSetup,
  })  : _http = httpClient,
        _launchSetup = launchSetup;

  final http.Client? _http;
  final Future<void> Function(String path)? _launchSetup;
  http.Client? _activeClient;

  void abort() {
    _activeClient?.close();
  }

  Future<void> downloadAndLaunch({
    required String url,
    required String latestVersion,
    required void Function(int received, int? total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw AppUpdateDownloadException('No hay un instalador válido para bajar.');
    }

    final client = _http ?? http.Client();
    _activeClient = client;
    final ownsClient = _http == null;
    IOSink? sink;
    File? file;
    try {
      if (isCancelled()) {
        throw const AppUpdateDownloadCancelled();
      }
      final request = http.Request('GET', uri);
      request.headers['Accept'] = 'application/octet-stream';
      request.headers['User-Agent'] = 'JuniorEventos-Updater';
      final response = await client.send(request).timeout(
            const Duration(seconds: 30),
          );
      if (isCancelled()) {
        throw const AppUpdateDownloadCancelled();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppUpdateDownloadException(
          'No se pudo descargar el instalador (${response.statusCode}).',
        );
      }

      final ver = latestVersion.trim().replaceFirst(RegExp(r'^[vV]'), '');
      file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'Setup-Junior-Eventos-v$ver.exe',
      );
      sink = file.openWrite();
      var received = 0;
      final total = response.contentLength;
      await for (final chunk in response.stream) {
        if (isCancelled()) {
          throw const AppUpdateDownloadCancelled();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, (total != null && total > 0) ? total : null);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (isCancelled()) {
        throw const AppUpdateDownloadCancelled();
      }
      if (!await _isWindowsPe(file)) {
        await _tryDelete(file);
        throw AppUpdateDownloadException(
          'Lo que se descargó no es el instalador. Probá de nuevo.',
        );
      }

      final launcher = _launchSetup ?? launchInstallerWithShellExecute;
      await launcher(file.path);
    } on AppUpdateDownloadCancelled {
      if (file != null) await _tryDelete(file);
      rethrow;
    } on AppUpdateDownloadException {
      rethrow;
    } on SocketException {
      throw AppUpdateDownloadException(
        'Sin conexión. Revisá internet e intentá de nuevo.',
      );
    } on HttpException {
      throw AppUpdateDownloadException(
        'No se pudo descargar el instalador. Probá de nuevo.',
      );
    } catch (e) {
      if (isCancelled() || e is AppUpdateDownloadCancelled) {
        if (file != null) await _tryDelete(file);
        throw const AppUpdateDownloadCancelled();
      }
      throw AppUpdateDownloadException(
        'No se pudo descargar el instalador. Probá de nuevo.',
      );
    } finally {
      await sink?.close();
      _activeClient = null;
      if (ownsClient) client.close();
    }
  }

  /// `CreateProcess` no eleva; `start` usa ShellExecute y dispara el UAC.
  static Future<void> launchInstallerWithShellExecute(String path) async {
    await Process.start(
      'cmd',
      ['/c', 'start', '', path],
      mode: ProcessStartMode.detached,
    );
  }

  static Future<bool> _isWindowsPe(File file) async {
    try {
      final raf = await file.open();
      try {
        if (raf.lengthSync() < 2) return false;
        final b0 = raf.readByteSync();
        final b1 = raf.readByteSync();
        return b0 == 0x4D && b1 == 0x5A;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> _tryDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class AppUpdateDownloadException implements Exception {
  AppUpdateDownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AppUpdateDownloadCancelled implements Exception {
  const AppUpdateDownloadCancelled();
}
