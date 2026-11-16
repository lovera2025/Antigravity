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
///
/// **Y lo que lee de la tele también se lo pregunta a la principal** (revisión
/// final de la 6.9.0): con la tele abierta desde la tarde para otra fiesta, la
/// config de la fiesta de la noche la guardaba la principal después, y la tele,
/// sin internet, la buscaba en su copia vieja y salía con la de fábrica. Si la
/// principal no contesta, se lee lo que esta ventana guardó o su copia, como antes.
///
/// **Lo que esta ventana guardó y le llegó a la principal no le gana a la
/// principal** (revisión del 15-nov): la tele en otra fiesta no se entera de que
/// el jefe cambió la de la noche, y sin internet salía con lo que ella había
/// guardado a la tarde. Solo lo que no le llegó ([_sinEntregar]) se lee de acá
/// primero: la principal no lo tiene.
class PreferenciasDeLaVentana {
  PreferenciasDeLaVentana._();

  /// Las claves que la ventana del tótem puede pedir que se guarden. La
  /// principal no guarda ninguna otra: lo que llega por el puente lo escribió
  /// otro proceso y se trata como dato.
  static const prefijosDelTotem = ['totem_config_v1_', 'totem_orient_v1_'];

  /// Lo más largo que se guarda por el puente (una config pesa unos 2 KB).
  static const largoMaximo = 64 * 1024;

  static Future<void> Function(String clave, String? valor)? _porElPuente;

  /// Cómo le pregunta la ventana del tótem a la principal: lo que tiene guardado
  /// en [clave] (`contesto` false si no contestó).
  static Future<({bool contesto, String? valor})> Function(String clave)? _leerPorElPuente;

  /// Lo que esta ventana guardó por el puente: se lee de acá antes que de su
  /// copia del archivo.
  static final _propias = <String, String?>{};

  /// Las de [_propias] que todavía no le llegaron a la principal (o no le
  /// llegaron nunca): esas las tiene solo esta ventana.
  static final _sinEntregar = <String>{};

  /// En la ventana del tótem: guardar es pedírselo a la principal con [enviar].
  static void usarElPuente(
    Future<void> Function(String clave, String? valor) enviar, {
    Future<({bool contesto, String? valor})> Function(String clave)? leer,
  }) {
    _porElPuente = enviar;
    _leerPorElPuente = leer;
  }

  /// Si esta ventana guarda por el puente (es la del tótem).
  static bool get porElPuente => _porElPuente != null;

  /// Como recién abierta. Solo para las pruebas.
  @visibleForTesting
  static void reiniciar() {
    _porElPuente = null;
    _leerPorElPuente = null;
    _propias.clear();
    _sinEntregar.clear();
  }

  static Future<String?> leer(String clave) async {
    if (_sinEntregar.contains(clave)) return _propias[clave];
    final preguntar = _leerPorElPuente;
    if (preguntar != null && esDelTotem(clave)) {
      try {
        final r = await preguntar(clave);
        if (r.contesto) return r.valor;
      } catch (e) {
        debugPrint('La ventana del tótem no pudo preguntar $clave: $e');
      }
    }
    if (_propias.containsKey(clave)) return _propias[clave];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(clave);
  }

  /// Si [clave] es una de las preferencias de la tele ([prefijosDelTotem]): el
  /// prefijo y un id de evento, nada más.
  static bool esDelTotem(Object? clave) =>
      clave is String &&
      prefijosDelTotem.any((p) => clave.startsWith(p) && clave.length == p.length + 36);

  /// En la ventana principal: lo que tiene guardado en [clave], si es una de las
  /// de la tele. Lee el archivo de esta ventana, que es la única que escribe.
  static Future<String?> leerLoDelTotem(Object? clave) async {
    if (!esDelTotem(clave)) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(clave as String);
  }

  /// Guarda [valor] en [clave]; con null, la saca.
  static Future<void> guardar(String clave, String? valor) async {
    final enviar = _porElPuente;
    if (enviar == null) {
      await escribirEnElArchivo(clave, valor);
      return;
    }
    _propias[clave] = valor;
    _sinEntregar.add(clave);
    try {
      await enviar(clave, valor);
      // Otro guardado de la misma clave pudo salir mientras tanto: ese decide.
      if (_propias[clave] == valor) {
        _sinEntregar.remove(clave);
      }
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
    if (!esDelTotem(clave)) return false;
    await escribirEnElArchivo(clave, texto);
    return true;
  }
}
