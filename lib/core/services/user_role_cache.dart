import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/common/models/user_role_state.dart';

/// Persiste el [UserRoleState] en disco para poder mostrar el panel sin red
/// (misma lógica online; solo lectura de respaldo).
class UserRoleCache {
  static const _keyPrefix = 'user_role_v1_';

  static String _key(String userId) => '$_keyPrefix$userId';

  static Future<void> save(UserRoleState state, String userId) async {
    if (state.isLoading) return;
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'is_admin': state.isAdmin,
      'nombre': state.nombre,
      'permisos': {
        'puede_eventos': state.permisos.puedeEventos,
        'puede_clientes': state.permisos.puedeClientes,
        'puede_catalogo': state.permisos.puedeCatalogo,
        'puede_recepcion': state.permisos.puedeRecepcion,
        'puede_totem': state.permisos.puedeTotem,
        'puede_finanzas': state.permisos.puedeFinanzas,
        'puede_qr': state.permisos.puedeQr,
        'puede_cierre_caja': state.permisos.puedeCierreCaja,
      },
    };
    await prefs.setString(_key(userId), jsonEncode(map));
  }

  static Future<UserRoleState?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final isAdmin = map['is_admin'] as bool? ?? false;
      final nombre = map['nombre'] as String?;
      final permisosMap = map['permisos'] as Map<String, dynamic>?;
      final permisos = permisosMap != null
          ? UserPermissions.fromJson(permisosMap)
          : (isAdmin ? UserPermissions.admin() : const UserPermissions());
      return UserRoleState(
        isAdmin: isAdmin,
        nombre: nombre,
        permisos: isAdmin ? UserPermissions.admin() : permisos,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('UserRoleCache.load: $e');
      return null;
    }
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }

  /// Cierra sesión en Supabase y borra el rol en caché para ese usuario.
  static Future<void> signOut(SupabaseClient supabase) async {
    final uid = supabase.auth.currentUser?.id;
    await supabase.auth.signOut();
    if (uid != null) {
      await clear(uid);
    }
  }
}
