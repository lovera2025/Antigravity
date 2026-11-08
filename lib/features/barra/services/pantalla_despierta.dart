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

  /// Prende o apaga "no apagar la pantalla". Nunca falla: si el canal no
  /// contesta, la tablet se apaga como siempre y nada más.
  static Future<void> mantener(bool despierta) async {
    if (!_enAndroid) return;
    try {
      await canal.invokeMethod<void>('despierta', despierta);
    } catch (e) {
      debugPrint('Pantalla despierta: $e');
    }
  }
}
