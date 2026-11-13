import 'package:shared_preferences/shared_preferences.dart';

/// Dónde recuerda la página la sesión de este celular, por link.
///
/// La sesión es lo que hace que "este celular" sea siempre el mismo delegado:
/// la da la nube al entrar y se manda en cada pedido. Si se pierde (otro
/// navegador, datos borrados), la nube lo toma por un celular nuevo.
abstract class SesionesDelDelegado {
  Future<String?> leer(String clave);
  Future<void> guardar(String clave, String sesion);
}

/// En el navegador del celular (`localStorage`, por `shared_preferences`).
class SesionesEnElCelular implements SesionesDelDelegado {
  const SesionesEnElCelular();

  String _llave(String clave) => 'delegado:$clave';

  @override
  Future<String?> leer(String clave) async {
    try {
      return (await SharedPreferences.getInstance()).getString(_llave(clave));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> guardar(String clave, String sesion) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_llave(clave), sesion);
    } catch (_) {
      // Sin dónde guardar (una ventana privada): sigue adentro hasta que cierre.
    }
  }
}

/// En memoria: para las pruebas.
class SesionesEnMemoria implements SesionesDelDelegado {
  final Map<String, String> _porClave = {};

  @override
  Future<String?> leer(String clave) async => _porClave[clave];

  @override
  Future<void> guardar(String clave, String sesion) async =>
      _porClave[clave] = sesion;
}
