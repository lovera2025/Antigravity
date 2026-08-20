import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/app_update_checker.dart';
import '../../../core/services/app_update_downloader.dart';

enum AppUpdateDownloadResult { success, cancelled, error }

class AppUpdateDownloadDialog extends StatefulWidget {
  const AppUpdateDownloadDialog({
    super.key,
    required this.info,
    this.downloader,
  });

  final AppUpdateInfo info;
  final AppUpdateDownloader? downloader;

  @override
  State<AppUpdateDownloadDialog> createState() =>
      _AppUpdateDownloadDialogState();
}

class _AppUpdateDownloadDialogState extends State<AppUpdateDownloadDialog> {
  late final AppUpdateDownloader _downloader;
  var _cancelled = false;
  var _received = 0;
  int? _total;
  String? _error;

  @override
  void initState() {
    super.initState();
    _downloader = widget.downloader ?? AppUpdateDownloader();
    unawaited(_run());
  }

  Future<void> _run() async {
    final url = widget.info.setupDownloadUrl?.trim() ?? '';
    if (url.isEmpty) {
      if (!mounted) return;
      setState(() => _error = 'No hay un instalador válido para bajar.');
      return;
    }
    try {
      await _downloader.downloadAndLaunch(
        url: url,
        latestVersion: widget.info.latestVersion,
        onProgress: (received, total) {
          if (!mounted || _cancelled) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      Navigator.pop(context, AppUpdateDownloadResult.success);
    } on AppUpdateDownloadCancelled {
      if (mounted) {
        Navigator.pop(context, AppUpdateDownloadResult.cancelled);
      }
    } on AppUpdateDownloadException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo descargar el instalador. Probá de nuevo.');
    }
  }

  void _cancel() {
    if (_cancelled || _error != null) return;
    setState(() => _cancelled = true);
    _downloader.abort();
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final fraction = (total != null && total > 0)
        ? (_received / total).clamp(0.0, 1.0)
        : null;
    return PopScope(
      canPop: _error != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AlertDialog(
        title: Text(
          _error != null
              ? 'No se pudo actualizar'
              : 'Descargando ${widget.info.latestVersion}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Text(_error!)
            else ...[
              LinearProgressIndicator(value: fraction),
              const SizedBox(height: 12),
              Text(_progressLabel(fraction, total)),
            ],
          ],
        ),
        actions: [
          if (_error != null)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, AppUpdateDownloadResult.error),
              child: const Text('CERRAR'),
            )
          else
            TextButton(
              onPressed: _cancel,
              child: const Text('CANCELAR'),
            ),
        ],
      ),
    );
  }

  String _progressLabel(double? fraction, int? total) {
    if (total != null && total > 0 && fraction != null) {
      return '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)}% · '
          '${_fmtBytes(_received)} de ${_fmtBytes(total)}';
    }
    if (_received > 0) return _fmtBytes(_received);
    return 'Conectando…';
  }

  static String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
