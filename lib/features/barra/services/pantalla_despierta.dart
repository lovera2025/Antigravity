import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// La pantalla de la tablet no se apaga mientras VENDER está abierta (6.4.0).
///
/// La tablet va enchufada en la barra; sin esto, entre venta y venta la pantalla
/// se apagaba y la cajera tenía que destrabarla. Es un canal propio
/// (`MainActivity.kt`, `junior_eventos/pantalla`), como el del kiosco en Windows:
/// no hace falta un paquete para una línea. En la PC y en la web no hace nada.
class PantallaDespierta {
  static const canal = MethodChannel('junior_eventos/pantalla');

  /// Para probarlo como en la tablet. Solo los tests lo cambian.
  @visibleForTesting
  static bool? enAndroidEnLaPrueba;

  static bool get _enAndroid =>
      enAndroidEnLaPrueba ?? (!kIsWeb && Platform.isAndroid);

  /// Cuántas pantallas abiertas la piden: VENDER, LAS CAJAS (25-nov-2026) y la tele.
  /// Se apaga recién cuando la última la suelta: si la encargada abre LAS CAJAS encima
  /// de otra que la pide y vuelve, la pantalla sigue prendida.
  static var _piden = 0;

  /// Para las pruebas: vuelve a cero.
  @visibleForTesting
  static void olvidar() => _piden = 0;

  /// Pide ([despierta] true) o suelta (false) "no apagar la pantalla"; cada pantalla
  /// la pide al abrir y la suelta al cerrar. Nunca falla: si el canal no contesta, la
  /// tablet se apaga como siempre y nada más.
  static Future<void> mantener(bool despierta) async {
    if (!_enAndroid) return;
    final antes = _piden > 0;
    _piden = despierta ? _piden + 1 : (_piden > 0 ? _piden - 1 : 0);
    final ahora = _piden > 0;
    // Solo cuando cambia: la segunda pantalla que la pide no vuelve a llamar, y la
    // primera que la suelta tampoco.
    if (antes == ahora) return;
    try {
      await canal.invokeMethod<void>('despierta', ahora);
    } catch (e) {
      debugPrint('Pantalla despierta: $e');
    }
  }
}
