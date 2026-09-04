import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../features/totem/totem_orientation.dart';

class KioskLauncher {
  static int? _totemWindowId;

  /// Qué evento está proyectando la ventana ahora mismo. Se necesita porque el
  /// `eventoId` viaja en los argumentos de creación de la ventana y, sin esto,
  /// no había forma de saber si el que pide Recepción es otro.
  static String? _totemEventoId;

  /// Apertura en curso. `_totemWindowId` recién se asigna cuando `createWindow`
  /// resuelve, así que dos clics seguidos alcanzaban para abrir dos tótems.
  static Future<void>? _enCurso;

  /// Abre la ventana del tótem.
  ///
  /// [orientacion] define la forma inicial de la ventana. Si no se pasa, se usa
  /// la que quedó guardada para ese evento, y si nunca se eligió una, abre
  /// **vertical**: el tótem se lleva a una pantalla parada, y hasta ahora nacía
  /// en 1280x720 apaisado, con lo cual el layout vertical que ya existía en el
  /// código no se activaba nunca. Desde la propia ventana se puede girar.
  ///
  /// Si la ventana ya está abierta con otro evento, **se lo cambia en caliente**
  /// en vez de ignorarlo.
  static Future<void> launch(
    String eventoId, {
    TotemOrientation? orientacion,
  }) {
    return _enCurso ??= _launchInterno(eventoId, orientacion: orientacion)
        .whenComplete(() => _enCurso = null);
  }

  static Future<void> _launchInterno(
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
        // La ventana sigue viva. Antes acá se hacía `show()` y nada más, así que
        // el salón seguía proyectando el evento anterior para siempre.
        await setEvento(eventoId);
        WindowController.fromWindowId(_totemWindowId!).show();
        return;
      } else {
        // Ventana fue cerrada manualmente pero el ID quedó guardado
        _totemWindowId = null;
        _totemEventoId = null;
        debugPrint('KIOSK: Ventana zombi detectada y limpiada.');
      }
    }

    debugPrint('KIOSK: Lanzando modo tótem nativo para evento $eventoId');

    final window = await DesktopMultiWindow.createWindow(jsonEncode({
      'eventoId': eventoId,
      'orientacion': inicial.name,
    }));

    _totemWindowId = window.windowId;
    _totemEventoId = eventoId;

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

  /// Único camino para hablarle a la ventana del tótem: centraliza el try/catch
  /// y el nuleo del id, que antes estaba copiado en cada notificación.
  ///
  /// [reintentos] existe para el arranque: el handler del lado del tótem se
  /// registra en su `initState`, un rato después de que `createWindow` resolvió.
  /// Un mensaje que llegue en esa ventana fallaría, y sin reintentos se
  /// interpretaría como "la ventana murió".
  static Future<void> _invocar(
    String metodo, [
    dynamic args,
    int reintentos = 0,
  ]) async {
    if (_totemWindowId == null) return;

    for (var intento = 0; intento <= reintentos; intento++) {
      try {
        await DesktopMultiWindow.invokeMethod(_totemWindowId!, metodo, args);
        return;
      } catch (e) {
        if (intento == reintentos) {
          debugPrint('KIOSK: Error al notificar "$metodo" (ventana cerrada): $e');
          _totemWindowId = null;
          _totemEventoId = null;
          return;
        }
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  /// Cambia en caliente el evento que proyecta el tótem, sin recrear la ventana:
  /// recrearla haría parpadear la pantalla del salón y perdería la posición, el
  /// tamaño y la orientación que el operador ya dejó acomodadas.
  static Future<void> setEvento(String eventoId) async {
    if (_totemWindowId == null || _totemEventoId == eventoId) return;
    _totemEventoId = eventoId;
    await _invocar('set_evento', eventoId, 3);
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
        _totemEventoId = null;
      }
    }
  }

  /// Envía un mensaje de refresco general al Tótem.
  static Future<void> notifyUpdate() => _invocar('refresh');

  /// Notifica que se ha vaciado o reseteado la lista de invitados
  static Future<void> notifyListReset() => _invocar('list_reset');

  /// Notifica un check-in específico para que el tótem reaccione al instante.
  static Future<void> notifyGuestCheckin(Map<String, dynamic> guestJson) =>
      _invocar('guest_checkin', jsonEncode(guestJson));

  /// Notifica que se borró un invitado, para que desaparezca del tótem al
  /// instante sin esperar a que la nube replique.
  static Future<void> notifyGuestRemoved(String invitadoId) =>
      _invocar('guest_removed', invitadoId);

  /// Notifica que cambió la identidad visual del evento.
  ///
  /// Viaja el JSON completo y no un simple "refrescá" porque `SharedPreferences`
  /// cachea en memoria **por proceso**: que la ventana principal escriba la
  /// caché no sirve del otro lado. Así el tótem la reescribe en su propio
  /// proceso y el cambio se ve aunque no haya red.
  static Future<void> notifyConfigUpdated(Map<String, dynamic> configJson) =>
      _invocar('config_updated', jsonEncode(configJson));

  static bool get isTotemActive => _totemWindowId != null;

  /// Evento que el tótem está proyectando, o `null` si no hay ventana abierta.
  static String? get totemEventoId => _totemEventoId;
}
