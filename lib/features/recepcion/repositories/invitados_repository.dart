import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/kiosk_launcher.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../models/invitado.dart';



/// Repositorio de Invitados — Offline-First.
///
/// Crítico para el Tótem Nativo: lee de SQLite local
/// para respuesta instantánea sin depender de la nube.
class InvitadosRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;
  final _changesController = StreamController<String>.broadcast();

  InvitadosRepository(this._supabase, this._connectivity);

  // Set in memory to prevent unnecessary pulls when the db is explicitly empty
  final _hasInitialPull = <String>{};

  /// Canales usados solo para **emitir** broadcasts al tótem.
  ///
  /// Memoizado porque `RealtimeClient.channel()` agrega un canal nuevo a su
  /// lista en cada llamada: sin esto se filtrarían durante una fiesta larga.
  final _emisores = <String, RealtimeChannel>{};

  RealtimeChannel _canalEmisor(String eventoId) =>
      _activeChannels[eventoId] ??
      (_emisores[eventoId] ??= _supabase.channel('totem_$eventoId'));

  /// Le avisa al tótem por Realtime.
  ///
  /// Antes cada emisor chequeaba `_activeChannels[eventoId] != null` y, si no
  /// había canal, el aviso se perdía en silencio — justo el caso del check-in
  /// hecho desde el celular del invitado, cuando nadie tiene el panel abierto.
  /// `sendBroadcastMessage` no necesita suscripción: si el socket no está
  /// disponible, el cliente cae solo al endpoint REST de broadcast.
  Future<void> _emitir(
    String eventoId,
    String evento,
    Map<String, dynamic> payload,
  ) async {
    // Mismo blindaje que el resto del repo: un UUID inválido le saca un 22P02
    // a Supabase.
    if (eventoId.length != 36) return;
    try {
      await _canalEmisor(eventoId)
          .sendBroadcastMessage(event: evento, payload: payload);
    } catch (e) {
      debugPrint('⚠️ Broadcast "$evento" falló: $e');
    }
  }

  // ── LECTURA ────────────────────────────────────────────────────────────────

  /// Obtiene todos los invitados de un evento desde SQLite.
  Future<List<Invitado>> getByEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('invitados',
      where: 'evento_id = ?',
      whereArgs: [eventoId],
      orderBy: 'nombre_completo COLLATE NOCASE ASC',
    );

    if (rows.isEmpty && _connectivity.currentStatus == AppConnectivity.online && !_hasInitialPull.contains(eventoId)) {
      await _pullByEvento(db, eventoId);
      _hasInitialPull.add(eventoId);
      final freshRows = await db.query('invitados',
        where: 'evento_id = ?', whereArgs: [eventoId], orderBy: 'nombre_completo COLLATE NOCASE ASC');
      return freshRows.map((r) => Invitado.fromJson(r)).toList();
    }
    
    if (rows.isNotEmpty) {
      _hasInitialPull.add(eventoId);
    }

    return rows.map((r) => Invitado.fromJson(r)).toList();
  }

  /// Busca invitado por DNI en un evento específico.
  Future<Invitado?> buscarPorDni(String eventoId, String dni) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('invitados',
      where: 'evento_id = ? AND dni = ?',
      whereArgs: [eventoId, dni],
    );
    if (rows.isEmpty) return null;
    return Invitado.fromJson(rows.first);
  }

  /// Busca invitados por nombre (parcial) en un evento.
  Future<List<Invitado>> buscarPorNombre(String eventoId, String nombre) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('invitados',
      where: 'evento_id = ? AND nombre_completo LIKE ?',
      whereArgs: [eventoId, '%$nombre%'],
      orderBy: 'nombre_completo COLLATE NOCASE ASC',
    );
    return rows.map((r) => Invitado.fromJson(r)).toList();
  }

  /// Estadísticas rápidas de un evento.
  Future<Map<String, int>> getEstadisticas(String eventoId) async {
    final db = await LocalDatabase.instance;
    final total = await db.rawQuery(
      'SELECT COUNT(*) as count FROM invitados WHERE evento_id = ?', [eventoId]);
    final ingresados = await db.rawQuery(
      "SELECT COUNT(*) as count FROM invitados WHERE evento_id = ? AND estado_ingreso = 'ingresado'", [eventoId]);

    final totalCount = (total.first['count'] as int?) ?? 0;
    final ingresadosCount = (ingresados.first['count'] as int?) ?? 0;

    return {
      'total': totalCount,
      'ingresados': ingresadosCount,
      'pendientes': totalCount - ingresadosCount,
    };
  }

  // ── ESCRITURA ─────────────────────────────────────────────────────────────

  /// Agrega un invitado.
  Future<String> agregar({
    required String eventoId,
    required String nombreCompleto,
    String? dni,
    String? numeroMesa,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    final now = DateTime.now().toUtc().toIso8601String();

    final data = {
      'id': id,
      'evento_id': eventoId,
      'nombre_completo': nombreCompleto,
      'dni': dni ?? '',
      'numero_mesa': numeroMesa,
      'estado_ingreso': 'pendiente',
      'intentos_fallidos': 0,
      'updated_at': now,
      'created_at': now,
    };

    await db.insert('invitados', data, conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueue.enqueue(tabla: 'invitados', operacion: SyncOperation.insert, registroId: id, payload: data);

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately(data, SyncOperation.insert, id);
    }

    _notifyChanges(eventoId);
    return id;
  }

  /// Agrega múltiples invitados de una sola vez (para importar de archivo).
  Future<int> agregarBatch({
    required String eventoId,
    required List<Map<String, String>> invitados,
  }) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    int count = 0;

    // Usamos una sola transacción para todo el batch
    await db.transaction((txn) async {
      for (final inv in invitados) {
        final nombre = inv['nombre_completo']?.trim() ?? '';
        if (nombre.isEmpty) continue;

        final id = UuidUtils.generate();
        final data = {
          'id': id,
          'evento_id': eventoId,
          'nombre_completo': nombre,
          'dni': inv['dni']?.trim() ?? '',
          'numero_mesa': inv['numero_mesa']?.trim().isNotEmpty == true ? inv['numero_mesa']!.trim() : null,
          'estado_ingreso': 'pendiente',
          'intentos_fallidos': 0,
          'updated_at': now,
          'created_at': now,
        };

        // IMPORTANTE: Se usa 'txn' para evitar deadlocks
        await txn.insert('invitados', data, conflictAlgorithm: ConflictAlgorithm.replace);
        await SyncQueue.enqueue(
          tabla: 'invitados', 
          operacion: SyncOperation.insert, 
          registroId: id, 
          payload: data,
          executor: txn, // Pasar transacción
        );

        count++;
      }
    });

    _notifyChanges(eventoId);
    return count;
  }

  /// Elimina un invitado.
  Future<void> eliminar(String id) async {
    final db = await LocalDatabase.instance;
    
    // Buscar eventoId antes de borrar para notificar
    final row = await db.query('invitados', columns: ['evento_id'], where: 'id = ?', whereArgs: [id]);
    final eventoId = row.isNotEmpty ? row.first['evento_id'] as String : null;

    await db.delete('invitados', where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(tabla: 'invitados', operacion: SyncOperation.delete, registroId: id, payload: {'id': id});

    // Sacarlo del tótem al instante, igual que se hace con el check-in.
    // Sin esto el nombre queda proyectado en la pantalla del salón hasta que
    // la nube replique el borrado.
    if (KioskLauncher.isTotemActive) {
      KioskLauncher.notifyGuestRemoved(id);
    }

    if (eventoId != null) {
      // Broadcast para tótems remotos y web, que no comparten esta PC.
      unawaited(_emitir(eventoId, 'guest_removed', {'id': id}));
      _notifyChanges(eventoId);
    }

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately({'id': id}, SyncOperation.delete, id);
    }
  }

  /// Marca un invitado como ingresado (check-in).
  Future<void> marcarIngreso(String invitadoId) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update('invitados', {
      'estado_ingreso': 'ingresado',
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [invitadoId]);

    await SyncQueue.enqueue(
      tabla: 'invitados',
      operacion: SyncOperation.update,
      registroId: invitadoId,
      payload: {'id': invitadoId, 'estado_ingreso': 'ingresado', 'updated_at': now},
    );

    // Notificar cambios para que el stream se actualice (Tótem, etc)
    final row = await db.query('invitados', where: 'id = ?', whereArgs: [invitadoId]);
    if (row.isNotEmpty) {
      final invitado = Invitado.fromJson(row.first);
      
      // Si hay un tótem activo en esta misma PC, le avisamos por el puente local
      // para que la reacción sea instantánea (cero latencia de nube)
      if (KioskLauncher.isTotemActive) {
        KioskLauncher.notifyGuestCheckin(invitado.toJson());
      }
      
      // Sincronización Realtime instantánea para Tótems remotos y Web (Broadcast).
      // Evita esperar la replicación de Postgres. Va sin `await`: el check-in en
      // la puerta es lo más sensible a latencia de toda la app y el fallback
      // REST agrega un viaje HTTP.
      unawaited(_emitir(invitado.eventoId, 'checkin', invitado.toJson()));

      _notifyChanges(invitado.eventoId);
    }

    if (_connectivity.currentStatus == AppConnectivity.online) {
      Future.microtask(() async {
        try {
          await _supabase.from('invitados')
              .update({'estado_ingreso': 'ingresado', 'updated_at': now})
              .eq('id', invitadoId);
          final dbInner = await LocalDatabase.instance;
          await dbInner.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: ['invitados', invitadoId]);
        } catch (e) {
          debugPrint('⚠️ Sync check-in fallido: $e');
        }
      });
    }
  }

  /// Deshace un check-in, volviendo el invitado a pendiente.
  Future<void> deshacerIngreso(String invitadoId) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update('invitados', {
      'estado_ingreso': 'pendiente',
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [invitadoId]);

    await SyncQueue.enqueue(
      tabla: 'invitados',
      operacion: SyncOperation.update,
      registroId: invitadoId,
      payload: {'id': invitadoId, 'estado_ingreso': 'pendiente', 'updated_at': now},
    );

    final row = await db.query('invitados', where: 'id = ?', whereArgs: [invitadoId]);
    if (row.isNotEmpty) {
      final invitado = Invitado.fromJson(row.first);

      // Se usa el mismo aviso que el borrado a propósito: para el tótem el
      // efecto es idéntico —el nombre sale de "YA LLEGARON"— y
      // `_handleGuestRemoved` saca el id de `_processedIds`, así que si lo
      // vuelven a marcar la bienvenida se anima de nuevo, que es lo correcto.
      // Sin esto, deshacer un ingreso tardaba hasta 60 s en verse en el salón.
      if (KioskLauncher.isTotemActive) {
        KioskLauncher.notifyGuestRemoved(invitadoId);
      }
      unawaited(_emitir(invitado.eventoId, 'guest_removed', {'id': invitadoId}));

      _notifyChanges(invitado.eventoId);
    }

    if (_connectivity.currentStatus == AppConnectivity.online) {
      Future.microtask(() async {
        try {
          await _supabase.from('invitados')
              .update({'estado_ingreso': 'pendiente', 'updated_at': now})
              .eq('id', invitadoId);
          final dbInner = await LocalDatabase.instance;
          await dbInner.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: ['invitados', invitadoId]);
        } catch (e) {
          debugPrint('⚠️ Sync deshacer check-in fallido: $e');
        }
      });
    }
  }

  /// Deshace TODOS los ingresos de un evento (vuelven a pendiente). Ideal para limpiar pruebas.
  Future<void> resetearIngresosGlobal(String eventoId) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now().toUtc().toIso8601String();

    final rows = await db.query(
      'invitados',
      columns: ['id'],
      where: 'evento_id = ? AND estado_ingreso = ?',
      whereArgs: [eventoId, 'ingresado'],
    );

    if (rows.isEmpty) return; // Nada que resetear

    await db.transaction((txn) async {
      await txn.update(
        'invitados',
        {'estado_ingreso': 'pendiente', 'updated_at': now},
        where: 'evento_id = ? AND estado_ingreso = ?',
        whereArgs: [eventoId, 'ingresado'],
      );

      for (final row in rows) {
        final id = row['id'] as String;
        await SyncQueue.enqueue(
          tabla: 'invitados',
          operacion: SyncOperation.update,
          registroId: id,
          payload: {'id': id, 'estado_ingreso': 'pendiente', 'updated_at': now},
          executor: txn,
        );
      }
    });

    // Volvieron todos a pendiente: para el tótem equivale a vaciar la lista.
    if (KioskLauncher.isTotemActive) KioskLauncher.notifyListReset();
    unawaited(_emitir(eventoId, 'list_reset', {'evento_id': eventoId}));

    _notifyChanges(eventoId);

    if (_connectivity.currentStatus == AppConnectivity.online) {
      Future.microtask(() async {
        try {
          await _supabase.from('invitados')
              .update({'estado_ingreso': 'pendiente', 'updated_at': now})
              .eq('evento_id', eventoId)
              .eq('estado_ingreso', 'ingresado');
          
          final dbInner = await LocalDatabase.instance;
          await dbInner.transaction((txn) async {
            for (final row in rows) {
              await txn.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: ['invitados', row['id']]);
            }
          });
        } catch (e) {
          debugPrint('⚠️ Sync reset global fallido: $e');
        }
      });
    }
  }

  /// Vacía completamente la lista de invitados de un evento (Elimina todos).
  Future<void> vaciarEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    
    // Obtener todos los IDs para registrarlos en la cola de sync
    final rows = await db.query(
      'invitados',
      columns: ['id'],
      where: 'evento_id = ?',
      whereArgs: [eventoId],
    );

    if (rows.isEmpty) return;

    await db.transaction((txn) async {
      await txn.delete('invitados', where: 'evento_id = ?', whereArgs: [eventoId]);
      for (final row in rows) {
        final id = row['id'] as String;
        await SyncQueue.enqueue(
          tabla: 'invitados',
          operacion: SyncOperation.delete,
          registroId: id,
          payload: {'id': id},
          executor: txn,
        );
      }
    });

    // El aviso vive acá y no en la pantalla que llamó: hay varias superficies
    // que vacían listas, y la que se olvide la línea deja el salón proyectando
    // gente que ya no existe.
    if (KioskLauncher.isTotemActive) KioskLauncher.notifyListReset();
    unawaited(_emitir(eventoId, 'list_reset', {'evento_id': eventoId}));

    _notifyChanges(eventoId);

    if (_connectivity.currentStatus == AppConnectivity.online) {
      Future.microtask(() async {
        try {
          await _supabase.from('invitados').delete().eq('evento_id', eventoId);
          final dbInner = await LocalDatabase.instance;
          await dbInner.transaction((txn) async {
            for (final row in rows) {
              await txn.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: ['invitados', row['id']]);
            }
          });
        } catch (e) {
          debugPrint('⚠️ Sync vaciar evento fallido: $e');
        }
      });
    }
  }

  /// Registra un intento fallido de check-in por DNI.
  Future<void> registrarIntentoFallido(String invitadoId) async {
    final db = await LocalDatabase.instance;
    await db.rawUpdate(
      'UPDATE invitados SET intentos_fallidos = intentos_fallidos + 1 WHERE id = ?',
      [invitadoId],
    );

    final row = await db.query('invitados', columns: ['evento_id'], where: 'id = ?', whereArgs: [invitadoId]);
    if (row.isNotEmpty) {
      _notifyChanges(row.first['evento_id'] as String);
    }
  }

  /// Resetea los intentos fallidos de un invitado.
  Future<void> resetearIntentos(String invitadoId) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update('invitados', {
      'intentos_fallidos': 0,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [invitadoId]);

    await SyncQueue.enqueue(
      tabla: 'invitados',
      operacion: SyncOperation.update,
      registroId: invitadoId,
      payload: {'id': invitadoId, 'intentos_fallidos': 0, 'updated_at': now},
    );

    final row = await db.query('invitados', columns: ['evento_id'], where: 'id = ?', whereArgs: [invitadoId]);
    if (row.isNotEmpty) {
      _notifyChanges(row.first['evento_id'] as String);
    }

    if (_connectivity.currentStatus == AppConnectivity.online) {
      Future.microtask(() async {
        try {
          await _supabase.from('invitados')
              .update({'intentos_fallidos': 0, 'updated_at': now})
              .eq('id', invitadoId);
          final dbInner = await LocalDatabase.instance;
          await dbInner.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: ['invitados', invitadoId]);
        } catch (e) {
          debugPrint('⚠️ Sync reset fallido: $e');
        }
      });
    }
  }

  /// Valida el DNI de un invitado y marca el ingreso si es correcto (Lógica del Tótem).
  Future<Map<String, dynamic>> validarDniYMarcarIngreso({
    required String invitadoId,
    required String dniIngresado,
  }) async {
    final db = await LocalDatabase.instance;
    final row = await db.query('invitados',
      where: 'id = ?',
      whereArgs: [invitadoId],
    );
    
    if (row.isEmpty) {
      return {'success': false, 'error': 'not_found', 'message': 'Invitado no encontrado'};
    }
    
    final invitado = Invitado.fromJson(row.first);
    
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
      await registrarIntentoFallido(invitadoId);
      final nuevosIntentos = invitado.intentosFallidos + 1;
      if (nuevosIntentos >= 3) {
        return {'success': false, 'error': 'bloqueado', 'message': 'DNI incorrecto. Acceso bloqueado.'};
      }
      return {'success': false, 'error': 'dni_incorrecto', 'message': 'DNI incorrecto. Quedan ${3 - nuevosIntentos} intentos.'};
    }
    
    // Todo bien
    await marcarIngreso(invitadoId);
    await resetearIntentos(invitadoId);
    
    return {'success': true};
  }

  // ── SYNC ──────────────────────────────────────────────────────────────────

  Future<void> _pullByEvento(Database db, String eventoId) async {
    // Blindaje: Si el ID no es un UUID válido de 36 caracteres, abortamos para evitar error 22P02 en Supabase
    if (eventoId.length != 36) {
      debugPrint('🚫 Abortando pull de invitados: ID malformado ($eventoId)');
      return;
    }
    try {
      final response = await _supabase.from('invitados')
          .select()
          .eq('evento_id', eventoId)
          .order('nombre_completo');

      final baseLocalIds = await db.query('invitados', columns: ['id'], where: 'evento_id = ?', whereArgs: [eventoId]);
      final localIds = baseLocalIds.map((r) => r['id'] as String).toSet();
      
      // Bloquear registros que tienen modificaciones locales pendientes
      final syncOps = await db.query('_sync_queue', columns: ['registro_id'], where: "tabla = 'invitados'");
      final lockedIds = syncOps.map((r) => r['registro_id'] as String).toSet();
      
      final remoteIds = <String>{};

      final batch = db.batch();
      for (final row in (response as List)) {
        final id = row['id'] as String;
        remoteIds.add(id);

        if (lockedIds.contains(id)) {
          // Registro protegido: Tiene cambios locales (ej. check-in reciente) que aún no confirmaron en la nube.
          continue;
        }

        batch.insert('invitados', {
          'id': id,
          'evento_id': row['evento_id'],
          'nombre_completo': row['nombre_completo'],
          'dni': row['dni'] ?? '',
          'numero_mesa': row['numero_mesa'],
          'estado_ingreso': row['estado_ingreso'] ?? 'pendiente',
          'intentos_fallidos': row['intentos_fallidos'] ?? 0,
          'updated_at': row['updated_at'],
          'created_at': row['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      
      // Borrar registros locales que ya no existen en Supabase (ej. eliminados desde otro equipo)
      final toDelete = localIds.difference(remoteIds).difference(lockedIds);
      for (final id in toDelete) {
        batch.delete('invitados', where: 'id = ?', whereArgs: [id]);
      }
      
      await batch.commit(noResult: true);
      debugPrint('📥 Invitados: ${response.length} sincronizados para evento $eventoId');
    } catch (e) {
      debugPrint('⚠️ Error pull invitados: $e');
    }
  }

  /// Fuerza un refresh de invitados de un evento desde la nube.
  Future<void> forceRefresh(String eventoId) async {
    final db = await LocalDatabase.instance;
    await _pullByEvento(db, eventoId);
  }

  // ── STREAM ────────────────────────────────────────────────────────────────

  // Mapa para rastrear canales activos por eventoId y evitar zombies.
  final _activeChannels = <String, RealtimeChannel>{};
  final _channelSubscribers = <String, int>{};
  
  // Map de Timers para debounce de forceRefresh por cada evento
  final _realtimeDebounceTimers = <String, Timer>{};

  /// Stream de cambios realtime para invitados.
  RealtimeChannel subscribeToChanges(String eventoId, void Function() onUpdate) {
    // Usamos el mismo nombre de canal que usa el Tótem nativo/web
    final channel = _supabase.channel('totem_$eventoId');
    
    // 1. Escuchar cambios lentos (nube Postgres) para sincronización global.
    //
    // El filtro por evento se agregó el 2026-09-02: sin él, un check-in en
    // cualquier evento disparaba el forceRefresh de todos los demás abiertos, y
    // Realtime tenía que evaluar cada fila del WAL contra esta suscripción.
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'invitados',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'evento_id',
        value: eventoId,
      ),
      callback: (payload) {
        _realtimeDebounceTimers[eventoId]?.cancel();
        _realtimeDebounceTimers[eventoId] = Timer(const Duration(milliseconds: 500), () {
          forceRefresh(eventoId).then((_) => onUpdate());
        });
      },
    );

    // 2. Escuchar Broadcasts instantáneos (Tótem -> Recepción) evitando delay de Postgres
    channel.onBroadcast(
      event: 'checkin',
      callback: (payload) {
        debugPrint('⚡ Broadcast de check-in recibido. Refrescando UI instantáneamente.');
        onUpdate();
      },
    );

    channel.subscribe();
    return channel;
  }

  void _syncImmediately(Map<String, dynamic> data, SyncOperation op, String id) {
    // Blindaje final: No intentar sync si el ID es malformado
    if (id.length != 36 || (data['evento_id'] != null && (data['evento_id'] as String).length != 36)) {
      debugPrint('🚫 Sync: Saltando sync inmediato para ID malformado ($id)');
      return;
    }

    Future.microtask(() async {
      try {
        switch (op) {
          case SyncOperation.insert:
            await _supabase.from('invitados').upsert(data);
            break;
          case SyncOperation.update:
            final updateData = Map<String, dynamic>.from(data)..remove('id');
            await _supabase.from('invitados').update(updateData).eq('id', id);
            break;
          case SyncOperation.delete:
            await _supabase.from('invitados').delete().eq('id', id);
            break;
        }
        final db = await LocalDatabase.instance;
        await db.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: ['invitados', id]);
      } catch (e) {
        debugPrint('⚠️ Sync invitado fallido: $e');
      }
    });
  }


  /// Observa los invitados de un evento, emitiendo una nueva lista cuando hay cambios locales o remotos.
  /// Gestiona el ciclo de vida del canal Realtime: lo crea al iniciar y lo cierra al cancelar si no quedan listeners.
  Stream<List<Invitado>> watchByEvento(String eventoId) async* {
    if (!_activeChannels.containsKey(eventoId)) {
      final channel = subscribeToChanges(eventoId, () {
        _notifyChanges(eventoId);
      });
      _activeChannels[eventoId] = channel;
      _channelSubscribers[eventoId] = 0;
    }
    
    _channelSubscribers[eventoId] = (_channelSubscribers[eventoId] ?? 0) + 1;

    try {
      // Emitir la lista inicial
      yield await getByEvento(eventoId);

      // Escuchar el controlador de cambios locales
      await for (final id in _changesController.stream) {
        if (id == eventoId) {
          yield await getByEvento(eventoId);
        }
      }
    } finally {
      // Limpiar el canal cuando el stream es cancelado (dispose del widget)
      if (_channelSubscribers.containsKey(eventoId)) {
        _channelSubscribers[eventoId] = (_channelSubscribers[eventoId]! - 1);
        if (_channelSubscribers[eventoId]! <= 0) {
          if (_activeChannels.containsKey(eventoId)) {
            await _supabase.removeChannel(_activeChannels[eventoId]!);
            _activeChannels.remove(eventoId);
          }
          _channelSubscribers.remove(eventoId);
        }
      }
    }
  }

  void _notifyChanges(String eventoId) {
    if (!_changesController.isClosed) {
      _changesController.add(eventoId);
    }
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final invitadosRepositoryProvider = Provider<InvitadosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return InvitadosRepository(supabase, connectivity);
});
