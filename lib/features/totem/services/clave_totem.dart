import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La clave del tótem de un evento (sección 8 de la 6.0.0).
///
/// Con los permisos de la lista de la puerta cerrados, el tótem no lee la
/// tabla: lee por la función `totem_lista`, que pide esta clave
/// (`supabase/migrations/20261016120000_puerta_funciones.sql`). **No está en
/// el QR de los invitados**: la lleva la ventana del tótem, que se la pide a la
/// principal por el puente, y el link del tótem por el navegador.
///
/// Se le pide a la nube con usuario (`totem_clave`, que la crea si no hay) y
/// queda guardada en la PC: la clave de un evento no cambia. Sin internet y
/// sin haberla pedido antes no hay clave, y el tótem sigue con lo de la PC,
/// como sin internet.
class ClaveTotem {
  ClaveTotem({required this.pedirALaNube});

  /// `totem_clave` en la nube. Puede tirar (sin internet, sin sesión).
  final Future<String?> Function(String eventoId) pedirALaNube;

  final _enMemoria = <String, String>{};

  static const _prefijo = 'clave_totem_v1_';

  /// La clave del evento, o null si no se pudo conseguir.
  Future<String?> de(String eventoId) async {
    if (eventoId.length != 36) return null;
    final ya = _enMemoria[eventoId];
    if (ya != null) return ya;

    final guardada = await _leer(eventoId);
    if (guardada != null) return _enMemoria[eventoId] = guardada;

    try {
      final nueva = (await pedirALaNube(eventoId))?.trim();
      if (nueva == null || nueva.isEmpty) return null;
      await _guardar(eventoId, nueva);
      return _enMemoria[eventoId] = nueva;
    } catch (e) {
      debugPrint('No se pudo pedir la clave del tótem: $e');
      return null;
    }
  }

  /// La que estaba guardada no anduvo (la nube dijo que no es la del evento):
  /// la próxima vez se pide de nuevo.
  Future<void> olvidar(String eventoId) async {
    _enMemoria.remove(eventoId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefijo$eventoId');
    } catch (e) {
      debugPrint('ClaveTotem.olvidar: $e');
    }
  }

  Future<String?> _leer(String eventoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('$_prefijo$eventoId')?.trim();
      return v == null || v.isEmpty ? null : v;
    } catch (e) {
      debugPrint('ClaveTotem._leer: $e');
      return null;
    }
  }

  Future<void> _guardar(String eventoId, String clave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefijo$eventoId', clave);
    } catch (e) {
      debugPrint('ClaveTotem._guardar: $e');
    }
  }
}

/// El link del tótem por el navegador, con la clave: para una tele con
/// navegador (Personalizar tótem → "En otra pantalla, por el navegador").
String linkDelTotemWeb({
  required String base,
  required String eventoId,
  required String clave,
}) =>
    '$base/?totem&evento=$eventoId&clave=$clave';
