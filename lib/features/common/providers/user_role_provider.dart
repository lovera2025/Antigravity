import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Permisos granulares para un usuario Asesor.
class UserPermissions {
  final bool puedeEventos;
  final bool puedeClientes;
  final bool puedeCatalogo;
  final bool puedeRecepcion;
  final bool puedeTotem;
  final bool puedeFinanzas;
  final bool puedeQr;

  const UserPermissions({
    this.puedeEventos = false,
    this.puedeClientes = false,
    this.puedeCatalogo = false,
    this.puedeRecepcion = true,
    this.puedeTotem = false,
    this.puedeFinanzas = false,
    this.puedeQr = false,
  });

  /// Admin tiene acceso a todo.
  factory UserPermissions.admin() => const UserPermissions(
        puedeEventos: true,
        puedeClientes: true,
        puedeCatalogo: true,
        puedeRecepcion: true,
        puedeTotem: true,
        puedeFinanzas: true,
        puedeQr: true,
      );

  factory UserPermissions.fromJson(Map<String, dynamic> json) {
    return UserPermissions(
      puedeEventos: json['puede_eventos'] ?? false,
      puedeClientes: json['puede_clientes'] ?? false,
      puedeCatalogo: json['puede_catalogo'] ?? false,
      puedeRecepcion: json['puede_recepcion'] ?? true,
      puedeTotem: json['puede_totem'] ?? false,
      puedeFinanzas: json['puede_finanzas'] ?? false,
      puedeQr: json['puede_qr'] ?? false,
    );
  }
}

/// Estado completo del rol del usuario actual.
class UserRoleState {
  final bool isAdmin;
  final String? nombre;
  final UserPermissions permisos;
  final bool isLoading;

  const UserRoleState({
    this.isAdmin = false,
    this.nombre,
    this.permisos = const UserPermissions(),
    this.isLoading = true,
  });

  factory UserRoleState.loading() => const UserRoleState(isLoading: true);
}

/// Provider que consulta el rol y permisos del usuario desde Supabase.
final userRoleProvider = FutureProvider.autoDispose<UserRoleState>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    return const UserRoleState(isLoading: false);
  }

  try {
    // 1. Consultar perfil (rol)
    final perfilRes = await supabase
        .from('perfiles')
        .select('rol, nombre')
        .eq('id', user.id)
        .maybeSingle();

    if (perfilRes == null) {
      // Sin perfil → tratar como Asesor sin permisos
      debugPrint('⚠️ Usuario sin perfil: ${user.id}');
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

    // 2. Si es Asesor, intentar consultar permisos (puede no existir la tabla)
    UserPermissions permisos = const UserPermissions();
    try {
      final permRes = await supabase
          .from('permisos_usuario')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (permRes != null) {
        permisos = UserPermissions.fromJson(permRes);
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo leer permisos_usuario (tabla puede no existir): $e');
      // Continuar con permisos por defecto (solo recepción)
    }

    return UserRoleState(
      isAdmin: false,
      nombre: nombre,
      permisos: permisos,
      isLoading: false,
    );
  } catch (e) {
    debugPrint('❌ Error fetching user role: $e');
    // En caso de error crítico (no se pudo leer perfil), asesor con mínimo acceso
    return const UserRoleState(isAdmin: false, isLoading: false);
  }
});
