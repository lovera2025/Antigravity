import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/user_role_cache.dart';
import '../models/user_role_state.dart';

export '../models/user_role_state.dart';

/// Provider que consulta el rol y permisos (Supabase + caché local para sin red).
final userRoleProvider = FutureProvider.autoDispose<UserRoleState>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    return const UserRoleState(isLoading: false);
  }

  final connectivity = ref.read(connectivityServiceProvider);

  if (connectivity.currentStatus == AppConnectivity.offline) {
    final cached = await UserRoleCache.load(user.id);
    if (cached != null) {
      debugPrint('📦 Rol desde caché (sin conexión)');
      return cached;
    }
    debugPrint('⚠️ Sin red y sin caché de rol; acceso mínimo');
    return const UserRoleState(isAdmin: false, isLoading: false);
  }

  try {
    final state = await _fetchRoleFromSupabase(supabase, user.id).timeout(
      const Duration(seconds: 12),
    );
    await UserRoleCache.save(state, user.id);
    return state;
  } catch (e) {
    debugPrint('❌ Error fetching user role: $e');
    final cached = await UserRoleCache.load(user.id);
    if (cached != null) {
      debugPrint('📦 Rol desde caché (red o timeout)');
      return cached;
    }
    return const UserRoleState(isAdmin: false, isLoading: false);
  }
});

Future<UserRoleState> _fetchRoleFromSupabase(
  SupabaseClient supabase,
  String userId,
) async {
  final perfilRes = await supabase
      .from('perfiles')
      .select('rol, nombre')
      .eq('id', userId)
      .maybeSingle();

  if (perfilRes == null) {
    debugPrint('⚠️ Usuario sin perfil: $userId');
    return const UserRoleState(isAdmin: false, isLoading: false);
  }

  final rol = perfilRes['rol'] as String?;
  final nombre = perfilRes['nombre'] as String?;
  final isAdmin = rol == 'Admin';

  debugPrint('👤 Rol del usuario: $rol (isAdmin=$isAdmin)');

  if (isAdmin) {
    return UserRoleState(
      isAdmin: true,
      nombre: nombre,
      permisos: UserPermissions.admin(),
      isLoading: false,
    );
  }

  UserPermissions permisos = const UserPermissions();
  try {
    final permRes = await supabase
        .from('permisos_usuario')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (permRes != null) {
      permisos = UserPermissions.fromJson(permRes);
    }
  } catch (e) {
    debugPrint('⚠️ No se pudo leer permisos_usuario: $e');
  }

  return UserRoleState(
    isAdmin: false,
    nombre: nombre,
    permisos: permisos,
    isLoading: false,
  );
}
