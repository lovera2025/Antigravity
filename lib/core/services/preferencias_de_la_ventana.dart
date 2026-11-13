import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Las preferencias que también usa la ventana del tótem (la config guardada
/// de cada evento y cómo quedó girada la tele), **sin que esa ventana escriba
/// el archivo**.
///
/// Cada ventana de Flutter es otro proceso de Dart, con su propia copia de las
/// preferencias en memoria. En Windows el paquete lee el archivo **una vez** y
/// cada escritura lo **reescribe entero** con esa copia. Hasta la 6.8.0, cuando
/// la ventana del tótem guardaba algo (GIRAR, la config que llegaba de la
/// nube), volvía el archivo a como estaba cuando ella se abrió: se perdía lo
/// que la principal había guardado después, entre otras cosas el código de la
/// central de los celulares y **la sesión**, que se renueva cada hora. Si el
/// programa se cerraba en ese momento, al otro día podía pedir la contraseña
/// (revisión del 13-nov).
///
/// Ahora hay un solo proceso que escribe: la ventana principal. La del tótem le
/// pasa lo que quiere guardar por el puente ([usarElPuente]) y se lo acuerda
/// ella misma en memoria, porque su copia del archivo es la del momento en que
/// se abrió.
class PreferenciasDeLaVentana {
  PreferenciasDeLaVentana._();

  /// Las claves que la ventana del tótem puede pedir que se guarden. La
  /// principal no guarda ninguna otra: lo que llega por el puente lo escribió
  /// otro proceso y se trata como dato.
  static const prefijosDelTotem = ['totem_config_v1_', 'totem_orient_v1_'];

  /// Lo más largo que se guarda por el puente (una config pesa unos 2 KB).
  static const largoMaximo = 64 * 1024;

  static Future<void> Function(String clave, String? valor)? _porElPuente;

  /// Lo que esta ventana guardó por el puente: se lee de acá antes que de su
  /// copia del archivo.
  static final _propias = <String, String?>{};

  /// En la ventana del tótem: guardar es pedírselo a la principal con [enviar].
  static void usarElPuente(
    Future<void> Function(String clave, String? valor) enviar,
  ) {
    _porElPuente = enviar;
  }

  /// Si esta ventana guarda por el puente (es la del tótem).
  static bool get porElPuente => _porElPuente != null;

  /// Como recién abierta. Solo para las pruebas.
  @visibleForTesting
  static void reiniciar() {
    _porElPuente = null;
    _propias.clear();
  }

  static Future<String?> leer(String clave) async {
    if (_propias.containsKey(clave)) return _propias[clave];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(clave);
  }

  /// Guarda [valor] en [clave]; con null, la saca.
  static Future<void> guardar(String clave, String? valor) async {
    final enviar = _porElPuente;
    if (enviar == null) {
      await escribirEnElArchivo(clave, valor);
      return;
    }
    _propias[clave] = valor;
    try {
      await enviar(clave, valor);
    } catch (e) {
      // No se escribe desde acá: mejor perder una preferencia que pisar el
      // archivo de la principal. Esta ventana se la acuerda mientras viva.
      debugPrint('La ventana del tótem no pudo pedir que se guarde $clave: $e');
    }
  }

  /// La escritura de verdad. **Solo corre en la ventana principal.**
  static Future<void> escribirEnElArchivo(String clave, String? valor) async {
    final prefs = await SharedPreferences.getInstance();
    if (valor == null) {
      await prefs.remove(clave);
    } else {
      await prefs.setString(clave, valor);
    }
  }

  /// En la ventana principal: guarda lo que pidió la del tótem, si es una de
  /// las suyas ([prefijosDelTotem]). Devuelve si lo guardó.
  static Future<bool> guardarLoDelTotem(Object? clave, Object? valor) async {
    if (clave is! String || (valor != null && valor is! String)) return false;
    final texto = valor as String?;
    if (texto != null && texto.length > largoMaximo) return false;
    final esDelTotem = prefijosDelTotem.any(
      // El prefijo y un id de evento, nada más.
      (p) => clave.startsWith(p) && clave.length == p.length + 36,
    );
    if (!esDelTotem) return false;
    await escribirEnElArchivo(clave, texto);
    return true;
  }
}
