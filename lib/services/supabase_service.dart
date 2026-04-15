import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/invitado.dart';
import '../models/evento.dart';
import '../models/acceso_log.dart';

class RecepcionException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  RecepcionException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'RecepcionException: $message ${code != null ? '(code: $code)' : ''}';
}

class SupabaseService {
  final SupabaseClient client;

  SupabaseService({SupabaseClient? client})
      : client = client ?? Supabase.instance.client;

  // ── INVITADOS (Check-in) ────────────────────────────────────────────────────

  Stream<List<Invitado>> streamInvitados(String eventoId) {
    try {
      return client
          .from('invitados')
          .stream(primaryKey: ['id'])
          .eq('evento_id', eventoId)
          .order('nombre_completo', ascending: true)
          .map((rows) {
            try {
              return rows.map((json) => Invitado.fromJson(json)).toList();
            } catch (e) {
              debugPrint('Error parsing invitados stream: $e');
              return <Invitado>[];
            }
          })
          .handleError((error) {
            debugPrint('Stream error: $error');
            throw RecepcionException(
              'Error en conexión realtime',
              originalError: error,
            );
          });
    } catch (e) {
      debugPrint('Error creating stream: $e');
      throw RecepcionException(
        'No se pudo establecer conexión realtime',
        originalError: e,
      );
    }
  }

  Future<void> marcarIngresado(String id) async {
    try {
      final response = await client
          .from('invitados')
          .update({
            'estado_ingreso': 'ingresado',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .select();

      if (response.isEmpty) {
        throw RecepcionException(
          'No se encontró el invitado',
          code: 'NOT_FOUND',
        );
      }
    } on PostgrestException catch (e) {
      debugPrint('Postgres error marking ingresado: $e');
      throw RecepcionException(
        'Error al actualizar estado: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      debugPrint('Error marking ingresado: $e');
      throw RecepcionException(
        'Error al marcar ingreso',
        originalError: e,
      );
    }
  }

  Future<List<Invitado>> fetchInvitados(String eventoId) async {
    try {
      final response = await client
          .from('invitados')
          .select()
          .eq('evento_id', eventoId)
          .order('nombre_completo', ascending: true);

      return (response as List)
          .map((json) => Invitado.fromJson(json))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Postgres error fetching invitados: $e');
      throw RecepcionException(
        'Error al cargar invitados: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      debugPrint('Error fetching invitados: $e');
      throw RecepcionException(
        'Error al cargar invitados',
        originalError: e,
      );
    }
  }

  Future<void> crearInvitado({
    required String eventoId,
    required String nombreCompleto,
    required String dni,
    String? numeroMesa,
  }) async {
    try {
      await client.from('invitados').insert({
        'evento_id': eventoId,
        'nombre_completo': nombreCompleto,
        'dni': dni,
        'numero_mesa': numeroMesa,
        'estado_ingreso': 'pendiente',
        'intentos_fallidos': 0,
      });
    } on PostgrestException catch (e) {
      debugPrint('Postgres error creating invitado: $e');
      throw RecepcionException(
        'Error al crear invitado: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      debugPrint('Error creating invitado: $e');
      throw RecepcionException(
        'Error al crear invitado',
        originalError: e,
      );
    }
  }

  Future<void> eliminarInvitado(String id) async {
    try {
      await client.from('invitados').delete().eq('id', id);
    } on PostgrestException catch (e) {
      debugPrint('Postgres error deleting invitado: $e');
      throw RecepcionException(
        'Error al eliminar invitado: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      debugPrint('Error deleting invitado: $e');
      throw RecepcionException(
        'Error al eliminar invitado',
        originalError: e,
      );
    }
  }

  // ── EVENTOS (para selector) ─────────────────────────────────────────────────

  Future<List<Evento>> fetchEventosActivos() async {
    try {
      final response = await client
          .from('eventos')
          .select('*, clientes(*)')
          .neq('estado', 'Finalizado')
          .neq('estado', 'Cancelado')
          .order('fecha_evento', ascending: true);

      return (response as List)
          .map((json) => Evento.fromJson(json))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Postgres error fetching eventos: $e');
      throw RecepcionException(
        'Error al cargar eventos: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      debugPrint('Error fetching eventos: $e');
      throw RecepcionException(
        'Error al cargar eventos',
        originalError: e,
      );
    }
  }

  Future<Evento?> fetchEvento(String id) async {
    try {
      final response = await client
          .from('eventos')
          .select('*, clientes(*)')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Evento.fromJson(response);
    } on PostgrestException catch (e) {
      debugPrint('Postgres error fetching evento: $e');
      throw RecepcionException(
        'Error al cargar evento: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      debugPrint('Error fetching evento: $e');
      throw RecepcionException(
        'Error al cargar evento',
        originalError: e,
      );
    }
  }

  // ── STATS (para testing screen) ─────────────────────────────────────────────

  Future<Map<String, int>> fetchEstadisticasEvento(String eventoId) async {
    try {
      final response = await client
          .from('invitados')
          .select('estado_ingreso')
          .eq('evento_id', eventoId);

      final data = response as List;
      final total = data.length;
      final ingresados = data.where((i) => i['estado_ingreso'] == 'ingresado').length;
      final pendientes = total - ingresados;

      return {
        'total': total,
        'ingresados': ingresados,
        'pendientes': pendientes,
      };
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      return {'total': 0, 'ingresados': 0, 'pendientes': 0};
    }
  }

  // ── HEALTH CHECK ────────────────────────────────────────────────────────────

  Future<bool> healthCheck() async {
    try {
      await client.from('eventos').select('id').limit(1);
      return true;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }

  // ── VALIDACIÓN DNI Y ACCESOS ────────────────────────────────────────────────

  Future<Map<String, dynamic>> validarDniYMarcarIngreso({
    required String invitadoId,
    required String dniIngresado,
    String? marcadoPor,
  }) async {
    try {
      // 1. Buscar invitado
      final invitadoResponse = await client
          .from('invitados')
          .select()
          .eq('id', invitadoId)
          .single();

      final invitado = Invitado.fromJson(invitadoResponse);

      // 2. Verificar si ya está bloqueado (3 intentos fallidos)
      if (invitado.intentosFallidos >= 3) {
        return {
          'success': false,
          'error': 'bloqueado',
          'message': 'Demasiados intentos fallidos. Contacte al operador.',
        };
      }

      // 3. Validar DNI
      final dniValido = invitado.dni == dniIngresado;

      if (dniValido) {
        // DNI correcto: marcar como ingresado y resetear intentos
        await client
            .from('invitados')
            .update({
              'estado_ingreso': 'ingresado',
              'intentos_fallidos': 0,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', invitadoId);

        // Registrar acceso exitoso
        await _registrarAcceso(
          invitadoId: invitadoId,
          eventoId: invitado.eventoId,
          dniIngresado: dniIngresado,
          valido: true,
          marcadoPor: marcadoPor,
        );

        return {
          'success': true,
          'invitado': invitado.toJson(),
        };
      } else {
        // DNI incorrecto: incrementar intentos fallidos
        final nuevosIntentos = invitado.intentosFallidos + 1;
        await client
            .from('invitados')
            .update({
              'intentos_fallidos': nuevosIntentos,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', invitadoId);

        // Registrar intento fallido
        await _registrarAcceso(
          invitadoId: invitadoId,
          eventoId: invitado.eventoId,
          dniIngresado: dniIngresado,
          valido: false,
          marcadoPor: marcadoPor,
        );

        return {
          'success': false,
          'error': 'dni_incorrecto',
          'message': 'DNI incorrecto. Intento $nuevosIntentos de 3.',
          'intentos': nuevosIntentos,
        };
      }
    } on PostgrestException catch (e) {
      debugPrint('Postgres error validating DNI: $e');
      throw RecepcionException(
        'Error al validar DNI: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      debugPrint('Error validating DNI: $e');
      throw RecepcionException(
        'Error al validar DNI',
        originalError: e,
      );
    }
  }

  Future<void> _registrarAcceso({
    required String invitadoId,
    required String eventoId,
    required String dniIngresado,
    required bool valido,
    String? marcadoPor,
  }) async {
    try {
      // Enmascarar DNI para privacidad (guardar solo últimos 3 dígitos)
      final dniEnmascarado = dniIngresado.length > 3
          ? '***${dniIngresado.substring(dniIngresado.length - 3)}'
          : '***';

      await client.from('accesos').insert({
        'invitado_id': invitadoId,
        'evento_id': eventoId,
        'dni_ingresado': dniEnmascarado,
        'valido': valido,
        'marcado_por': marcadoPor,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error registering access: $e');
    }
  }

  Future<void> resetearIntentosInvitado(String invitadoId) async {
    try {
      await client
          .from('invitados')
          .update({
            'intentos_fallidos': 0,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', invitadoId);
    } catch (e) {
      debugPrint('Error resetting attempts: $e');
      throw RecepcionException('Error al resetear intentos');
    }
  }

  Stream<List<AccesoLog>> streamAccesos(String eventoId) {
    try {
      return client
          .from('accesos')
          .stream(primaryKey: ['id'])
          .eq('evento_id', eventoId)
          .order('timestamp', ascending: false)
          .map((rows) {
            try {
              return rows.map((json) => AccesoLog.fromJson(json)).toList();
            } catch (e) {
              debugPrint('Error parsing accesos stream: $e');
              return <AccesoLog>[];
            }
          });
    } catch (e) {
      debugPrint('Error creating accesos stream: $e');
      throw RecepcionException('No se pudo establecer conexión realtime');
    }
  }
}

