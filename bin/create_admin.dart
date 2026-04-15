import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

const supabaseUrl = 'https://bucnrydgojyztntgesxqb.supabase.co';
const supabaseAnonKey = 'sb_publishable_-rqGT7VkvaCcmskUYK2ipw_PYglr9OH';

void main() async {
  // ignore: avoid_print
  print('Inicializando conexión con Supabase...');
  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  final email = 'arguelloadmin@test.com';
  final password = 'arguelloevents2026';

  try {
    // ignore: avoid_print
  print('Intentando crear usuario: \$email');
    final AuthResponse res = await supabase.auth.signUp(
      email: email,
      password: password,
    );
    
    if (res.user != null) {
      // ignore: avoid_print
  print('\\n=========================================');
      // ignore: avoid_print
  print('✅ USUARIO CREADO EXITOSAMENTE ✅');
      // ignore: avoid_print
  print('Email: \$email');
      // ignore: avoid_print
  print('Password: \$password');
      // ignore: avoid_print
  print('=========================================');
      // ignore: avoid_print
  print('Por favor, usa estas credenciales para entrar a tu app.');
      if (res.session == null) {
        // ignore: avoid_print
  print('\\n⚠️ AVISO: Supabase requiere confirmación de email.');
        // ignore: avoid_print
  print('Como no desactivaste "Confirm Email" en el panel, revisa tu bandeja.');
        // ignore: avoid_print
  print('Si prefieres entrar directo, desactiva "Confirm Email" en Autenticación > Providers > Email y vuelve a ejecutar este script o haz un login directo si el user se creó.');
      }
    } else {
      // ignore: avoid_print
  print('No se pudo crear el usuario (Respuesta vacía).');
    }
  } on AuthException catch (e) {
    if (e.message.contains('already registered')) {
      // ignore: avoid_print
  print('\\n=========================================');
      // ignore: avoid_print
  print('ℹ️  EL USUARIO YA EXISTE ℹ️');
      // ignore: avoid_print
  print('Email: \$email');
      // ignore: avoid_print
  print('Password: \$password');
      // ignore: avoid_print
  print('Puedes iniciar sesión con estos datos.');
      // ignore: avoid_print
  print('=========================================');
    } else {
      // ignore: avoid_print
  print('\\n❌ Error de Autenticación de Supabase: \${e.message}');
    }
  } catch (e) {
    // ignore: avoid_print
  print('\\n❌ Error Inesperado: \$e');
  }

  exit(0);
}
