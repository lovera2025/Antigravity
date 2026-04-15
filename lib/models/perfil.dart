enum RolUsuario { admin, asesor }

class Perfil {
  final String id;
  final RolUsuario rol;
  final String? nombre;

  Perfil({
    required this.id,
    required this.rol,
    this.nombre,
  });

  factory Perfil.fromJson(Map<String, dynamic> json) {
    return Perfil(
      id: json['id'],
      rol: json['rol'] == 'Admin' ? RolUsuario.admin : RolUsuario.asesor,
      nombre: json['nombre'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rol': rol == RolUsuario.admin ? 'Admin' : 'Asesor',
      'nombre': nombre,
    };
  }
}
