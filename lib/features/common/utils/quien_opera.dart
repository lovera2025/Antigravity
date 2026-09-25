import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../caja_sesiones/models/modo_jefe_caja.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../providers/user_role_provider.dart';

/// El nombre que queda anotado en lo que se registra (una entrega, un sorteo,
/// un reparto de sillas): quién estaba operando.
///
/// Primero la caja, que es lo que el jefe ya reconoce en los cierres: el
/// operador que la abrió, o "Jefe" en modo jefe. Sin caja, el nombre del perfil
/// del usuario logueado, y si no hay perfil, su mail.
String quienOperaDe({
  required AppRoleState app,
  String? nombrePerfil,
  String? email,
}) {
  if (app.esJefe) return 'Jefe';
  final operador = app.operador;
  if (operador != null) {
    if (esOperadorModoJefeId(operador.id)) return 'Jefe';
    final nombre = operador.nombre.trim();
    if (nombre.isNotEmpty) return nombre;
  }
  final perfil = nombrePerfil?.trim() ?? '';
  if (perfil.isNotEmpty) return perfil;
  final mail = email?.trim() ?? '';
  if (mail.isNotEmpty) return mail;
  return 'Sin identificar';
}

String quienOpera(WidgetRef ref) => quienOperaDe(
      app: ref.read(appRoleProvider),
      nombrePerfil: ref.read(userRoleProvider).asData?.value.nombre,
      email: ref.read(supabaseProvider).auth.currentUser?.email,
    );
