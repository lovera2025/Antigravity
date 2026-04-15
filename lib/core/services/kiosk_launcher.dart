import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

class KioskLauncher {
  static int? _totemWindowId;

  static Future<void> launch(String eventoId) async {
    if (_totemWindowId != null) {
      final activeIds = await DesktopMultiWindow.getAllSubWindowIds();
      if (activeIds.contains(_totemWindowId)) {
        // La ventana sigue viva, la mostramos y notificamos
        WindowController.fromWindowId(_totemWindowId!).show();
        return;
      } else {
        // Ventana fue cerrada manualmente pero el ID quedó guardado
        _totemWindowId = null;
        debugPrint('KIOSK: Ventana zombi detectada y limpiada.');
      }
    }

    debugPrint('KIOSK: Lanzando modo tótem nativo para evento $eventoId');

    final window = await DesktopMultiWindow.createWindow(jsonEncode({
      'eventoId': eventoId,
    }));

    _totemWindowId = window.windowId;

    window
      ..setFrame(const Offset(100, 100) & const Size(1280, 720))
      ..center()
      ..setTitle('Tótem — Junior Eventos')
      ..show();
  }

  static Future<void> close() async {
    if (_totemWindowId != null) {
      final activeIds = await DesktopMultiWindow.getAllSubWindowIds();
      if (activeIds.contains(_totemWindowId)) {
        await WindowController.fromWindowId(_totemWindowId!).hide();
      }
    }
  }

  static Future<void> maximize() async {
    if (_totemWindowId != null) {
      final isMaximized = await DesktopMultiWindow.invokeMethod(_totemWindowId!, 'isMaximized') as bool? ?? false;
      if (isMaximized) {
        await DesktopMultiWindow.invokeMethod(_totemWindowId!, 'unmaximize');
      } else {
        await DesktopMultiWindow.invokeMethod(_totemWindowId!, 'maximize');
      }
    }
  }

  static Future<void> minimize() async {
    if (_totemWindowId != null) {
      await DesktopMultiWindow.invokeMethod(_totemWindowId!, 'minimize', '');
    }
  }

  static Future<void> focus() async {
    if (_totemWindowId != null) {
      final activeIds = await DesktopMultiWindow.getAllSubWindowIds();
      if (activeIds.contains(_totemWindowId)) {
        WindowController.fromWindowId(_totemWindowId!).show();
      } else {
        _totemWindowId = null;
      }
    }
  }

  /// Envía un mensaje de refresco general al Tótem.
  static Future<void> notifyUpdate() async {
    if (_totemWindowId != null) {
      try {
        await DesktopMultiWindow.invokeMethod(_totemWindowId!, 'refresh', null);
      } catch (e) {
        debugPrint('KIOSK: Error al notificar (ventana cerrada): $e');
        _totemWindowId = null;
      }
    }
  }

  /// Notifica que se ha vaciado o reseteado la lista de invitados
  static Future<void> notifyListReset() async {
    if (_totemWindowId != null) {
      try {
        await DesktopMultiWindow.invokeMethod(_totemWindowId!, 'list_reset', null);
      } catch (e) {
        debugPrint('KIOSK: Error al notificar reset (ventana cerrada): $e');
        _totemWindowId = null;
      }
    }
  }

  /// Notifica un check-in específico para que el tótem reaccione al instante.
  static Future<void> notifyGuestCheckin(Map<String, dynamic> guestJson) async {
    if (_totemWindowId != null) {
      try {
        await DesktopMultiWindow.invokeMethod(_totemWindowId!, 'guest_checkin', jsonEncode(guestJson));
      } catch (e) {
        debugPrint('KIOSK: Error al notificar checkin (ventana cerrada): $e');
        _totemWindowId = null;
      }
    }
  }

  static bool get isTotemActive => _totemWindowId != null;
}
