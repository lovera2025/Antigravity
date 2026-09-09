import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quién es esta PC, para que no se escuche a sí misma.
///
/// El pulso de sincronización es un broadcast: lo recibe **todo el mundo**,
/// incluida la máquina que lo mandó. Sin un identificador, cada PC reaccionaría
/// a su propio aviso y saldría a bajar lo que acaba de subir.
///
/// ## Por qué esta clave y no una nueva
///
/// `caja_device_id` ya existía, la usa `sesiones_caja.device_id` para saber si
/// una caja quedó abierta en otro dispositivo. Crear un id paralelo habría hecho
/// que la misma PC tuviera dos nombres según quién preguntara, y en una máquina
/// que ya venía usándose la caja seguiría respondiendo con el viejo. Es la misma
/// instalación: un solo id.
///
/// Lo que sí cambia es **cuándo se crea**. Antes se generaba perezosamente, y
/// solo dentro del flujo de caja: en una PC que se usa nada más que como jefe
/// podía no existir nunca. Ahora se resuelve en el arranque.
///
/// ## Lo que este id NO es
///
/// No es una identidad estable ni confiable: vive en `SharedPreferences` y se
/// regenera si alguien las borra o reinstala. El código que ya lo usaba asume
/// eso (ver `estadoCajaEnOtroDispositivo`, que contempla el id regenerado), y el
/// pulso también tiene que asumirlo. El peor caso de un id nuevo es que la PC
/// deje de reconocer sus propios mensajes por un rato y baje de más — molesto,
/// nunca peligroso.
class InstalacionId {
  static const _clave = 'caja_device_id';

  static String? _valor;

  /// El id de esta instalación, o `null` si todavía no se resolvió.
  ///
  /// Nulo significa "no sé quién soy": quien filtre por origen tiene que tratar
  /// ese caso como **no ignorar nada**. Bajar de más es inocuo; ignorar un aviso
  /// ajeno creyéndolo propio, no.
  static String? get valor => _valor;

  /// Lee el id guardado, o crea uno. Idempotente: llamarla de nuevo no lo rota.
  static Future<String> inicializar() async {
    final cacheado = _valor;
    if (cacheado != null) return cacheado;

    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_clave);
      if (id == null || id.isEmpty) {
        id = 'pc-${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString(_clave, id);
        debugPrint('🆔 Instalación nueva: $id');
      }
      _valor = id;
      return id;
    } catch (e) {
      // Sin `SharedPreferences` la app tiene que seguir andando igual: el pulso
      // baja de más y nada más.
      debugPrint('⚠️ No pude resolver el id de instalación: $e');
      rethrow;
    }
  }
}
