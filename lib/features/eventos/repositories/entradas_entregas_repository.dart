import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../main.dart';
import '../../../models/entrega_entradas.dart';

/// La entrega de entradas en dos partes (`entradas_entregas`, v81) — SQLite +
/// cola → Supabase.
///
/// **Solo agrega renglones: nunca edita ni borra uno.** Cada renglón va con su
/// entrada en la cola, en la misma transacción, y sube solo cuando hay
/// internet. Un renglón que ya está (el mismo id, bajado de la nube o copiado
/// por otro equipo) no se vuelve a escribir: un renglón nunca cambia.
///
/// Quien decide qué se agrega es `EntregarParte`: este repositorio solo guarda
/// y lee.
class EntradasEntregasRepository {
  EntradasEntregasRepository(
    this._supabase, {
    Future<Database> Function()? abrir,
  }) : _abrir = abrir ?? (() => LocalDatabase.instance);

  final SupabaseClient? _supabase;
  final Future<Database> Function() _abrir;

  static const tabla = 'entradas_entregas';

  /// Agrega [renglones] y los encola, todo en una transacción.
  Future<void> agregar(List<EntregaEntradas> renglones) async {
    if (renglones.isEmpty) return;
    final db = await _abrir();
    await db.transaction((txn) => agregarEn(txn, renglones));
  }

  /// Lo mismo, dentro de una transacción que ya está abierta: así una entrega
  /// guarda sus renglones y la fila completa de `entradas_retiro` juntos.
  Future<void> agregarEn(
    DatabaseExecutor txn,
    List<EntregaEntradas> renglones,
  ) async {
    for (final r in renglones) {
      if (await _yaEsta(txn, r.id)) continue;
      final fila = r.toMap();
      await txn.insert(tabla, fila);
      await SyncQueue.enqueue(
        executor: txn,
        tabla: tabla,
        operacion: SyncOperation.insert,
        registroId: r.id,
        payload: fila,
      );
    }
  }

  Future<bool> _yaEsta(DatabaseExecutor db, String id) async {
    final filas = await db.query(
      tabla,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return filas.isNotEmpty;
  }

  /// Los renglones de estos alumnos, cada uno con los suyos del más viejo al
  /// más nuevo (`EntregaEntradas.enOrden`).
  Future<Map<String, List<EntregaEntradas>>> deContratos(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final db = await _abrir();
    final unicos = ids.toSet().toList();
    final renglones = <EntregaEntradas>[];
    // De a 400: SQLite admite un máximo de variables por consulta.
    for (var i = 0; i < unicos.length; i += 400) {
      final parte = unicos.sublist(i, min(i + 400, unicos.length));
      final marcas = List.filled(parte.length, '?').join(',');
      final filas = await db.rawQuery(
        'SELECT * FROM $tabla WHERE contrato_alumno_id IN ($marcas)',
        parte,
      );
      renglones.addAll(filas.map(EntregaEntradas.fromMap));
    }
    return EntregaEntradas.porAlumno(renglones);
  }

  /// Cuántas familias tienen algo de su entrega esperando subir desde este
  /// equipo: un renglón de `entradas_entregas` o la fila de `entradas_retiro`.
  /// Va por familia, no por renglón: una entrega que completó las dos partes
  /// encola el renglón y la fila, y es una sola entrega. Para la línea de VENDER
  /// (20-nov-2026: decía "Todo subido" con una entrega sin subir). Si no se
  /// puede contar, 0.
  Future<int> familiasSinSubir() async {
    try {
      final db = await _abrir();
      final filas = await db.rawQuery('''
        SELECT COUNT(DISTINCT alumno) AS n FROM (
          SELECT e.contrato_alumno_id AS alumno FROM _sync_queue q
            JOIN $tabla e ON e.id = q.registro_id
            WHERE q.tabla = '$tabla'
          UNION
          SELECT r.contrato_alumno_id AS alumno FROM _sync_queue q
            JOIN entradas_retiro r ON r.id = q.registro_id
            WHERE q.tabla = 'entradas_retiro'
        )
      ''');
      return (filas.first['n'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Los renglones de una fiesta, del más viejo al más nuevo.
  Future<List<EntregaEntradas>> delEvento(String eventoId) async {
    final db = await _abrir();
    final filas = await db.query(
      tabla,
      where: 'evento_id = ?',
      whereArgs: [eventoId],
    );
    return filas.map(EntregaEntradas.fromMap).toList()
      ..sort(EntregaEntradas.enOrden);
  }

  /// Lo que dice la nube de la entrega de este alumno, justo antes de entregar:
  /// si otro equipo entregó una parte hace un minuto, todavía puede no haber
  /// bajado.
  ///
  /// Los renglones que esta PC no tiene los deja guardados igual que lo haría
  /// la bajada (sin encolarlos: ya están en la nube), así la pantalla los
  /// muestra ya. Los que ya tiene no se tocan: un renglón nunca cambia.
  /// Tira si no hay red: quien llama decide qué avisar.
  Future<List<EntregaEntradas>> traerDeLaNube(String contratoAlumnoId) async {
    final cliente = _supabase;
    if (cliente == null) throw StateError('Sin nube en este equipo');
    final filas = await cliente
        .from(tabla)
        .select()
        .eq('contrato_alumno_id', contratoAlumnoId)
        .timeout(const Duration(seconds: 6));
    final renglones = [
      for (final f in filas) EntregaEntradas.fromMap(Map<String, dynamic>.from(f)),
    ]..sort(EntregaEntradas.enOrden);
    try {
      final db = await _abrir();
      await db.transaction((txn) async {
        for (final r in renglones) {
          if (await _yaEsta(txn, r.id)) continue;
          // Solo las columnas que esta versión conoce: lo mismo que deja la
          // bajada con su lista de columnas.
          await txn.insert(tabla, r.toMap());
        }
      });
    } catch (e) {
      // Lo que dice la nube igual se devuelve: guardarlo acá es para que la
      // pantalla lo vea antes, y la bajada lo trae de todos modos.
      debugPrint('⚠️ Entregas de la nube sin guardar en esta PC: $e');
    }
    return renglones;
  }
}

final entradasEntregasRepositoryProvider =
    Provider<EntradasEntregasRepository>(
  (ref) => EntradasEntregasRepository(ref.watch(supabaseProvider)),
);
