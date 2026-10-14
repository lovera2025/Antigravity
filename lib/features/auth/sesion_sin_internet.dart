import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Con qué sesión se entra al programa: la que trae el aviso de Supabase o,
/// si el aviso es un error o todavía no llegó, la guardada en la PC
/// ([guardada], `supabase.auth.currentSession`). Null: al login.
///
/// **Sin internet y con la sesión vencida, entra** (sección 5 de la 6.0.0).
/// Es lo de todos los días: el permiso de Supabase dura una hora, así que el
/// programa abierto al otro día arranca siempre con la sesión vencida. La
/// librería intenta renovarla, no puede por falta de internet y avisa un
/// error, pero **no la borra**: la deja para renovarla cuando vuelva internet,
/// y se entra con ella. El rol sale de lo recordado en la PC
/// (`UserRoleCache`). Se va al login solo si no hay ninguna: nadie inició
/// sesión en esta PC, o el servidor la rechazó (alguien cerró la sesión).
///
/// `test/sesion_sin_internet_test.dart` lo prueba con la librería de verdad y
/// la red cortada.
Session? sesionParaEntrar(
  AsyncSnapshot<AuthState> aviso,
  Session? guardada,
) {
  final session = aviso.data?.session;
  if (session != null) return session;
  if (aviso.hasError) return guardada;
  if (aviso.connectionState == ConnectionState.waiting) return guardada;
  return null;
}
