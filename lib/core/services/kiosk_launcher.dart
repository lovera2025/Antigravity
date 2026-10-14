import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../features/totem/totem_orientation.dart';

/// Lo que [KioskLauncher] necesita de las ventanas secundarias.
///
/// Existe para poder probarlo sin abrir ventanas de verdad: los tests ponen
/// una de mentira en [KioskLauncher.ventanas].
abstract class VentanasTotem {
  /// Le manda un mensaje a la ventana. Falla si no llegó.
  Future<dynamic> invocar(int id, String metodo, [dynamic args]);

  /// Las ventanas secundarias que siguen abiertas, escondidas o no.
  Future<List<int>> abiertas();

  /// Crea la ventana del tótem, la muestra y devuelve su id.
  Future<int> crear(
    String argumentos, {
    required Size tamanio,
    required String titulo,
  });

  Future<void> mostrar(int id);
  Future<void> esconder(int id);
}

class _VentanasDeVerdad implements VentanasTotem {
  const _VentanasDeVerdad();

  @override
  Future<dynamic> invocar(int id, String metodo, [dynamic args]) =>
      DesktopMultiWindow.invokeMethod(id, metodo, args);

  @override
  Future<List<int>> abiertas() => DesktopMultiWindow.getAllSubWindowIds();

  @override
  Future<int> crear(
    String argumentos, {
    required Size tamanio,
    required String titulo,
  }) async {
    final window = await DesktopMultiWindow.createWindow(argumentos);
    window
      ..setFrame(const Offset(100, 100) & tamanio)
      ..center()
      ..setTitle(titulo)
      ..show();
    return window.windowId;
  }

  @override
  Future<void> mostrar(int id) => WindowController.fromWindowId(id).show();

  @override
  Future<void> esconder(int id) => WindowController.fromWindowId(id).hide();
}

class KioskLauncher {
  static int? _totemWindowId;

  /// Qué evento está proyectando la ventana ahora mismo. Se necesita porque el
  /// `eventoId` viaja en los argumentos de creación de la ventana y, sin esto,
  /// no había forma de saber si el que pide Recepción es otro.
  static String? _totemEventoId;

  /// Apertura en curso. `_totemWindowId` recién se asigna cuando `createWindow`
  /// resuelve, así que dos clics seguidos alcanzaban para abrir dos tótems.
  static Future<void>? _enCurso;

  /// Por dónde se les habla a las ventanas. Solo los tests lo cambian.
  @visibleForTesting
  static VentanasTotem ventanas = const _VentanasDeVerdad();

  /// Lo que se espera entre un intento y el siguiente de un mismo mensaje.
  @visibleForTesting
  static Duration esperaEntreIntentos = const Duration(milliseconds: 600);

  /// Deja todo como al arrancar la app. Solo para los tests.
  @visibleForTesting
  static void reiniciar() {
    _totemWindowId = null;
    _totemEventoId = null;
    _enCurso = null;
    ventanas = const _VentanasDeVerdad();
    esperaEntreIntentos = const Duration(milliseconds: 600);
  }

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

    var id = _totemWindowId;
    List<int> abiertas;
    try {
      abiertas = await ventanas.abiertas();
    } catch (e) {
      // Con un tótem anotado y sin poder saber si vive, no se abre otro.
      if (id != null) rethrow;
      abiertas = const [];
    }

    if (id != null && !abiertas.contains(id)) {
      // Ventana fue cerrada manualmente pero el ID quedó guardado
      id = null;
      _totemWindowId = null;
      _totemEventoId = null;
      debugPrint('KIOSK: Ventana zombi detectada y limpiada.');
    }

    if (id == null && abiertas.isNotEmpty) {
      // Hay un tótem abierto que esta ventana no tiene anotado. El tótem es la
      // única ventana secundaria de la app, así que es ese: se lo adopta en vez
      // de abrir otro al lado.
      id = abiertas.first;
      _totemWindowId = id;
      _totemEventoId = null;
      debugPrint('KIOSK: Se adopta el tótem que seguía abierto ($id).');
    }

    if (id != null) {
      // Si quedaron dos de antes, se sigue con una. A la otra se la esconde y
      // se la pausa, que es lo mismo que hace `close()`: no se la destruye.
      for (final otra in abiertas) {
        if (otra == id) continue;
        try {
          await ventanas.invocar(otra, 'pausar');
          await ventanas.esconder(otra);
        } catch (e) {
          debugPrint('KIOSK: No se pudo esconder el tótem de más ($otra): $e');
        }
      }

      // La ventana sigue viva. Antes acá se hacía `show()` y nada más, así que
      // el salón seguía proyectando el evento anterior para siempre.
      await setEvento(eventoId);
      await ventanas.mostrar(id);
      await _invocar('reanudar');
      return;
    }

    debugPrint('KIOSK: Lanzando modo tótem nativo para evento $eventoId');

    _totemWindowId = await ventanas.crear(
      jsonEncode({
        'eventoId': eventoId,
        'orientacion': inicial.name,
      }),
      tamanio: _tamanioInicial(inicial),
      titulo: 'Tótem — Junior Eventos',
    );
    _totemEventoId = eventoId;
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
  /// y el olvido del id, que antes estaba copiado en cada notificación.
  ///
  /// **Un mensaje que no llega no quiere decir que la ventana murió.** Antes,
  /// con un solo aviso fallido se olvidaba la ventana: Recepción dejaba de
  /// avisarle por el resto de la noche y, si alguien la reabría, nacía una
  /// segunda al lado de la primera. Ahora se reintenta y, si igual no llega, se
  /// mira si la ventana sigue abierta: solo se la olvida si ya no existe.
  ///
  /// El reintento no saluda dos veces: del otro lado, un ingreso que ya se
  /// procesó se ignora.
  ///
  /// [reintentos] sube para el arranque: el handler del lado del tótem se
  /// registra en su `initState`, un rato después de que `createWindow` resolvió.
  static Future<void> _invocar(
    String metodo, [
    dynamic args,
    int reintentos = 1,
  ]) async {
    final id = _totemWindowId;
    if (id == null) return;

    for (var intento = 0; intento <= reintentos; intento++) {
      try {
        await ventanas.invocar(id, metodo, args);
        return;
      } catch (e) {
        if (intento == reintentos) {
          debugPrint('KIOSK: No llegó "$metodo" al tótem: $e');
          await _olvidarSiSeCerro(id);
          return;
        }
        await Future.delayed(esperaEntreIntentos);
      }
    }
  }

  /// Olvida la ventana [id] solo si ya no está entre las abiertas. Si no se
  /// puede saber, no la olvida: desconectar el tótem por una duda es peor que
  /// intentar hablarle una vez más.
  static Future<void> _olvidarSiSeCerro(int id) async {
    final List<int> abiertas;
    try {
      abiertas = await ventanas.abiertas();
    } catch (e) {
      debugPrint('KIOSK: No se pudo saber si el tótem sigue abierto: $e');
      return;
    }
    if (abiertas.contains(id)) return;
    if (_totemWindowId == id) {
      _totemWindowId = null;
      _totemEventoId = null;
      debugPrint('KIOSK: El tótem se cerró.');
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

  /// Esconde el tótem, no lo destruye: vuelve al instante y en el mismo lugar.
  /// Antes de esconderlo le pide que se pause, así escondido no sigue
  /// consultando la nube (ver `_pausado` en `totem_display.dart`).
  static Future<void> close() async {
    final id = _totemWindowId;
    if (id != null) {
      final activeIds = await ventanas.abiertas();
      if (activeIds.contains(id)) {
        await _invocar('pausar');
        await ventanas.esconder(id);
      }
    }
  }

  static Future<void> focus() async {
    if (_totemWindowId != null) {
      final activeIds = await ventanas.abiertas();
      final id = _totemWindowId;
      if (id != null && activeIds.contains(id)) {
        await ventanas.mostrar(id);
        await _invocar('reanudar');
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
