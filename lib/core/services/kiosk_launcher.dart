import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../features/totem/totem_orientation.dart';

class KioskLauncher {
  static int? _totemWindowId;

  /// Abre la ventana del tótem.
  ///
  /// [orientacion] define la forma inicial de la ventana. Si no se pasa, se usa
  /// la que quedó guardada para ese evento, y si nunca se eligió una, abre
  /// **vertical**: el tótem se lleva a una pantalla parada, y hasta ahora nacía
  /// en 1280x720 apaisado, con lo cual el layout vertical que ya existía en el
  /// código no se activaba nunca. Desde la propia ventana se puede girar.
  static Future<void> launch(
    String eventoId, {
    TotemOrientation? orientacion,
  }) async {
    final guardada = await TotemOrientationStore.load(eventoId);
    final inicial = orientacion ??
        (guardada == TotemOrientation.auto
            ? TotemOrientation.vertical
            : guardada);

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
      'orientacion': inicial.name,
    }));

    _totemWindowId = window.windowId;

    window
      ..setFrame(const Offset(100, 100) & _tamanioInicial(inicial))
      ..center()
      ..setTitle('Tótem — Junior Eventos')
      ..show();
  }

  /// Tamaño de arranque. Es una aproximación razonable para cualquier monitor;
  /// apenas la ventana está viva, el tótem la reajusta a la pantalla real.
  static Size _tamanioInicial(TotemOrientation orientacion) {
    return switch (orientacion) {
      TotemOrientation.vertical => const Size(608, 1080),
      TotemOrientation.horizontal => const Size(1280, 720),
      TotemOrientation.auto => const Size(1280, 720),
    };
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

  /// Notifica que se borró un invitado, para que desaparezca del tótem al
  /// instante sin esperar a que la nube replique.
  static Future<void> notifyGuestRemoved(String invitadoId) async {
    if (_totemWindowId != null) {
      try {
        await DesktopMultiWindow.invokeMethod(
            _totemWindowId!, 'guest_removed', invitadoId);
      } catch (e) {
        debugPrint('KIOSK: Error al notificar borrado (ventana cerrada): $e');
        _totemWindowId = null;
      }
    }
  }

  static bool get isTotemActive => _totemWindowId != null;
}
