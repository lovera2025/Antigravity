// Unifica nombres de institución + Reg 30/03/2026 en masivos activos (sin exclusiones).
//
//   flutter test tool/unificar_nombres_reg_masivos_test.dart
//   flutter test tool/unificar_nombres_reg_masivos_test.dart --dart-define=APPLY=1

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';

String _resolveDbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

Future<void> _enqueue(
  Database db, {
  required String tabla,
  required String registroId,
  required Map<String, dynamic> payload,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final existing = await db.query(
    '_sync_queue',
    where: 'tabla = ? AND registro_id = ?',
    whereArgs: [tabla, registroId],
  );
  if (existing.isNotEmpty) {
    final merged = <String, dynamic>{
      ...jsonDecode(existing.first['payload'] as String) as Map<String, dynamic>,
      ...payload,
    };
    await db.update(
      '_sync_queue',
      {
        'payload': jsonEncode(merged),
        'created_at': now,
        'intentos': 0,
        'ultimo_error': null,
        'operacion': 'update',
      },
      where: 'tabla = ? AND registro_id = ?',
      whereArgs: [tabla, registroId],
    );
  } else {
    await db.insert('_sync_queue', {
      'tabla': tabla,
      'operacion': 'update',
      'registro_id': registroId,
      'payload': jsonEncode(payload),
      'created_at': now,
      'intentos': 0,
    });
  }
}

void main() {
  final apply = const String.fromEnvironment('APPLY') == '1';

  test('unificar nombres + Reg masivos activos', () async {
    sqfliteFfiInit();
    final dbPath = _resolveDbPath();
    expect(File(dbPath).existsSync(), isTrue, reason: 'Falta $dbPath');
    final db = await databaseFactoryFfi.openDatabase(dbPath);

    final regIso = MoraCuotaCalculator.regArAUtcIso(DateTime(2026, 3, 30));
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    final eventos = await db.rawQuery('''
      SELECT e.id, e.tipo, e.estado, e.encabezado_evento,
             c.nombre_completo AS cliente_nombre,
             (SELECT COUNT(*) FROM contratos_alumnos ca WHERE ca.evento_id = e.id) AS alumnos
      FROM eventos e
      LEFT JOIN clientes c ON c.id = e.cliente_id
      WHERE e.modalidad = 'masivo'
        AND UPPER(COALESCE(e.estado, '')) NOT IN ('FINALIZADO', 'CANCELADO')
      ORDER BY COALESCE(c.nombre_completo, e.tipo) COLLATE NOCASE
    ''');

    print('\n=== ${eventos.length} eventos masivos activos ===');
    print('DB: $dbPath');
    print('Modo: ${apply ? "APLICAR" : "dry-run"}');
    print('Reg objetivo: $regIso\n');

    var eventosNombrados = 0;
    var contratosInst = 0;
    var contratosReg = 0;

    for (final ev in eventos) {
      final eventoId = ev['id'] as String;
      final nombre = (ev['cliente_nombre'] as String?)?.trim() ?? '';
      final enc = (ev['encabezado_evento'] as String?)?.trim() ?? '';
      final alumnos = (ev['alumnos'] as int?) ?? 0;
      print(
        '• $nombre | estado=${ev['estado']} | alumnos=$alumnos | '
        'encabezado=${enc.isEmpty ? "(vacío)" : enc}',
      );
      if (nombre.isEmpty) {
        print('  ⚠ sin cliente_nombre — skip');
        continue;
      }

      if (enc != nombre) {
        eventosNombrados++;
        if (apply) {
          await db.update(
            'eventos',
            {'encabezado_evento': nombre, 'updated_at': nowUtc},
            where: 'id = ?',
            whereArgs: [eventoId],
          );
          await _enqueue(
            db,
            tabla: 'eventos',
            registroId: eventoId,
            payload: {'id': eventoId, 'encabezado_evento': nombre},
          );
        }
      }

      final contratos = await db.query(
        'contratos_alumnos',
        columns: ['id', 'institucion', 'created_at', 'nombre_alumno'],
        where: 'evento_id = ?',
        whereArgs: [eventoId],
      );

      var instEvt = 0;
      var regEvt = 0;
      for (final ca in contratos) {
        final nombreAlumno = (ca['nombre_alumno'] as String?) ?? '';
        if (nombreAlumno.toUpperCase().startsWith('[BAJA]')) continue;

        final contratoId = ca['id'] as String;
        final instActual = (ca['institucion'] as String?)?.trim() ?? '';
        final regActual = (ca['created_at'] as String?) ?? '';
        final updates = <String, Object?>{'updated_at': nowUtc};
        final syncPayload = <String, dynamic>{'id': contratoId};

        if (instActual != nombre) {
          updates['institucion'] = nombre;
          syncPayload['institucion'] = nombre;
          instEvt++;
        }
        if (!regActual.startsWith('2026-03-30')) {
          updates['created_at'] = regIso;
          syncPayload['created_at'] = regIso;
          regEvt++;
        }
        if (updates.length == 1) continue;

        if (apply) {
          await db.update(
            'contratos_alumnos',
            updates,
            where: 'id = ?',
            whereArgs: [contratoId],
          );
          await _enqueue(
            db,
            tabla: 'contratos_alumnos',
            registroId: contratoId,
            payload: syncPayload,
          );
        }
      }
      contratosInst += instEvt;
      contratosReg += regEvt;
      print('  → instituciones a unificar: $instEvt | Reg a setear: $regEvt');
    }

    print('\nResumen: eventos=$eventosNombrados | inst=$contratosInst | reg=$contratosReg');

    if (apply) {
      final recalibrados = await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        encolarSync: true,
        soloEventosMasivosActivos: true,
      );
      final exenciones =
          await MoraTrackedRecovery.repararExencionDesdeHistorial(
        db: db,
        soloEventosMasivosActivos: true,
      );
      print('Mora: tracked=$recalibrados | exenciones=$exenciones');
    } else {
      print('(dry-run: no se escribió nada; usá --dart-define=APPLY=1)');
    }

    await db.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
