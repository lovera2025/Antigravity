import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/user_role_cache.dart';
import '../../../main.dart' show supabaseProvider;
import '../models/user_role_state.dart';

export '../models/user_role_state.dart';

/// Provider que consulta el rol y permisos (Supabase + caché local para sin red).
///
/// Sin internet, o con la red del salón sin salida a internet, el rol sale de
/// lo recordado en la PC: con eso se entra con la sesión vencida
/// (`sesionParaEntrar`). Lee [supabaseProvider] para que el test lo pruebe con
/// la red cortada.
final userRoleProvider = FutureProvider.autoDispose<UserRoleState>((ref) async {
  final supabase = ref.watch(supabaseProvider);
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

  final consulta = _fetchRoleFromSupabase(supabase, user.id)
      .timeout(const Duration(seconds: 12))
      .then((state) async {
    await UserRoleCache.save(state, user.id);
    return state;
  });

  // Con el rol recordado en la PC, la nube se espera poco. Con la red del
  // salón sin salida a internet (un router solo) la PC cree que hay internet,
  // y la consulta tardaba los 12 s enteros: "Verificando permisos..." antes de
  // poder entrar. Si contesta tarde, lo recordado queda al día para la próxima.
  final cached = await UserRoleCache.load(user.id);
  if (cached != null) {
    try {
      return await consulta.timeout(kEsperaDelRolRecordado);
    } catch (e) {
      debugPrint('📦 Rol desde caché (la nube no contestó a tiempo: $e)');
      consulta.ignore();
      return cached;
    }
  }

  try {
    return await consulta;
  } catch (e) {
    debugPrint('❌ Error fetching user role: $e');
    return const UserRoleState(isAdmin: false, isLoading: false);
  }
});

/// Cuánto se espera a la nube para el rol cuando la PC ya lo tiene recordado.
const kEsperaDelRolRecordado = Duration(seconds: 3);

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
