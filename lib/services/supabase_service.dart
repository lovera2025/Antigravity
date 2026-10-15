import 'package:supabase_flutter/supabase_flutter.dart';

/// El cliente de la nube con que habla el tótem del salón (`TotemDisplay`).
///
/// En la ventana del tótem es uno propio y anónimo (`main.dart`, rama
/// `multi_window`); en la web, el de siempre.
///
/// Hasta la 6.0.0 acá también se leía y se cambiaba la lista de la puerta
/// (`invitados`) y se anotaba en `accesos`, sin usuario. Desde la sección 8 eso
/// va por las funciones de la nube: el tótem por `ListaDelTotem` y la página
/// del QR por `SupabaseInvitadosRepository`.
class SupabaseService {
  final SupabaseClient client;

  SupabaseService({SupabaseClient? client})
      : client = client ?? Supabase.instance.client;
}
