/// Permisos granulares para un usuario Asesor.
class UserPermissions {
  final bool puedeEventos;
  final bool puedeClientes;
  final bool puedeCatalogo;
  final bool puedeRecepcion;
  final bool puedeTotem;
  final bool puedeFinanzas;
  final bool puedeQr;
  final bool puedeCierreCaja;

  const UserPermissions({
    this.puedeEventos = false,
    this.puedeClientes = false,
    this.puedeCatalogo = false,
    this.puedeRecepcion = true,
    this.puedeTotem = false,
    this.puedeFinanzas = false,
    this.puedeQr = false,
    this.puedeCierreCaja = false,
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
        puedeCierreCaja: true,
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
      puedeCierreCaja: json['puede_cierre_caja'] ?? false,
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
