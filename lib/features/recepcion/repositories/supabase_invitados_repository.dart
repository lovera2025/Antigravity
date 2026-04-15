import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/invitado.dart';

/// Repositorio de Invitados — Strictly Cloud (Supabase).
/// 
/// Usado para rutas públicas web (Tótem QR, Lista pública) 
/// donde no hay acceso a SQLite local.
class SupabaseInvitadosRepository {
  final SupabaseClient _supabase;

  SupabaseInvitadosRepository(this._supabase);

  Future<List<Invitado>> getByEvento(String eventoId) async {
    // Blindaje de ID
    if (eventoId.length != 36) return [];
    
    final response = await _supabase
        .from('invitados')
        .select()
        .eq('evento_id', eventoId)
        .order('nombre_completo');
    
    return (response as List).map((e) => Invitado.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> validarDniYMarcarIngreso({
    required String invitadoId,
    required String dniIngresado,
  }) async {
    // 1. Obtener invitado actual
    final response = await _supabase
        .from('invitados')
        .select()
        .eq('id', invitadoId)
        .maybeSingle();

    if (response == null) {
      return {'success': false, 'error': 'not_found', 'message': 'Invitado no encontrado'};
    }

    final invitado = Invitado.fromJson(response);

    if (invitado.estadoIngreso == EstadoIngreso.ingresado) {
      return {'success': false, 'error': 'ya_ingresado', 'message': 'Este invitado ya ingresó'};
    }

    if (invitado.intentosFallidos >= 3) {
      return {'success': false, 'error': 'bloqueado', 'message': 'Acceso bloqueado por seguridad'};
    }

    if (invitado.dni.isEmpty) {
      return {'success': false, 'error': 'no_dni', 'message': 'No tienes DNI registrado. Consulta en recepción.'};
    }

    if (invitado.dni != dniIngresado) {
      // Registrar intento fallido en la nube
      final nuevosIntentos = invitado.intentosFallidos + 1;
      await _supabase.from('invitados').update({
        'intentos_fallidos': nuevosIntentos,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', invitadoId);

      if (nuevosIntentos >= 3) {
        return {'success': false, 'error': 'bloqueado', 'message': 'DNI incorrecto. Acceso bloqueado.'};
      }
      return {'success': false, 'error': 'dni_incorrecto', 'message': 'DNI incorrecto. Quedan ${3 - nuevosIntentos} intentos.'};
    }

    // Todo bien - Marcar ingreso y resetear intentos
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.from('invitados').update({
      'estado_ingreso': 'ingresado',
      'intentos_fallidos': 0,
      'updated_at': now,
    }).eq('id', invitadoId);

    return {'success': true};
  }
}
