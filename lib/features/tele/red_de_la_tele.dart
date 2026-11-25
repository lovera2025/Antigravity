import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// El puerto por el que la Tele 2 pregunta "¿dónde está la Tele 1 de esta
/// fiesta?" (la tele es el tótem, 24-nov-2026). La barra usa el 8777.
const kPuertoBusquedaTele = 8778;

/// Lo que la tele le pide a Android por un canal propio (`MainActivity.kt`,
/// `junior_eventos/red`): como el de la pantalla despierta de la barra, sin un
/// paquete para dos líneas. En la PC y en la web no hace nada.
class RedDeLaTele {
  static const canal = MethodChannel('junior_eventos/red');

  /// Para probarlo como en la tele. Solo los tests lo cambian.
  @visibleForTesting
  static bool? enAndroidEnLaPrueba;

  static bool get _enAndroid =>
      enAndroidEnLaPrueba ?? (!kIsWeb && Platform.isAndroid);

  /// La Tele 1 oye la pregunta de la Tele 2, que va a toda la red: Android la
  /// tira si no se le pide el bloqueo del multicast. Nunca falla: sin él, la
  /// dirección de la Tele 1 se escribe en la Tele 2 con el control.
  static Future<void> oirLaRed(bool oir) async {
    if (!_enAndroid) return;
    try {
      await canal.invokeMethod<void>('multicast', oir);
    } catch (e) {
      debugPrint('La tele no pudo ${oir ? 'prender' : 'apagar'} el multicast: $e');
    }
  }
}

/// La página del celular de la puerta en una tele o una tablet (24-nov-2026).
///
/// En la PC la deja el instalador al lado del programa (`{app}\puesto`). En
/// Android viene adentro del APK (Gradle la mete en los archivos propios de
/// Android, `android/app/build.gradle.kts`), y la central sirve archivos de una
/// carpeta: al abrir el modo tele se copia una vez por versión a la carpeta de
/// la app ([preparar]). Sin la página, la central contesta "no está" y el
/// celular no abre: por eso la tele lo dice ([hay]).
class PaginaDelCelularEnAndroid {
  static Directory? _carpeta;

  /// La carpeta lista, o null si no se preparó o el APK no la trae.
  static Directory? get carpeta => _carpeta;

  static bool get hay => _carpeta != null;

  /// Para las pruebas: una carpeta que hace de la de la tele.
  @visibleForTesting
  static set carpetaEnLaPrueba(Directory? c) => _carpeta = c;

  /// Lo que tiene que tener la página para que el celular la dibuje: sin
  /// `FontManifest.json` no hay letras ni íconos, y sin internet no dibuja nada
  /// (la 6.6.0).
  static const archivosQueNoPuedenFaltar = [
    'index.html',
    'main.dart.js',
    'assets/FontManifest.json',
  ];

  static bool estaEntera(Directory carpeta) => archivosQueNoPuedenFaltar.every(
        (a) => File([carpeta.path, ...a.split('/')].join(Platform.pathSeparator))
            .existsSync(),
      );

  /// La copia del APK a la carpeta de la app, si todavía no está la de esta
  /// versión. Nunca falla: sin la página, [carpeta] queda null.
  static Future<void> preparar() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final base = await getApplicationSupportDirectory();
      final destino = Directory('${base.path}${Platform.pathSeparator}puesto');
      final ok = await RedDeLaTele.canal
          .invokeMethod<bool>('copiarPuesto', destino.path);
      _carpeta = ok == true && estaEntera(destino) ? destino : null;
    } catch (e) {
      debugPrint('La página del celular no se pudo preparar: $e');
      _carpeta = null;
    }
  }
}
