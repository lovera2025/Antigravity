import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/barra/datos/vale_barra.dart';
import 'package:arguello_events/models/silla_puerta.dart';

/// La tabla de la v78 (las sillas que se suman la noche de la fiesta) en el motor
/// de sincronización, en el SQL de la nube y en su repositorio. Mismo modelo que
/// `sync_tablas_v75_test.dart`: las listas del motor son privadas y se leen del
/// texto del archivo.
void main() {
  sqfliteFfiInit();

  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  final motor = leer('lib/core/services/sync_engine.dart');
  final cola = leer('lib/core/database/sync_queue.dart');
  final sql = leer('supabase/migrations/20261105120000_sillas_puerta.sql');
  final repositorio =
      leer('lib/features/recepcion/repositories/sillas_puerta_repository.dart');

  String declaracion(String nombre, String cierre) {
    final i = motor.indexOf(RegExp('static const [^;]*\\b$nombre = '));
    expect(i, greaterThanOrEqualTo(0), reason: 'no encontré $nombre');
    final f = motor.indexOf('\n  $cierre;', i);
    expect(f, greaterThan(i), reason: 'no encontré el final de $nombre');
    return motor.substring(i, f);
  }

  Set<String> columnasDelMotor(String tabla) {
    final m = RegExp("'$tabla': \\[(.*?)\\]", dotAll: true).firstMatch(motor);
    expect(m, isNotNull, reason: '$tabla no está en las columnas del motor');
    return {
      for (final c in RegExp("'([a-z_]+)'").allMatches(m!.group(1)!)) c.group(1)!,
    };
  }

  final ahora = DateTime.utc(2026, 11, 14, 23, 5);
  final silla = SillaPuerta(
    id: 's0000000-0000-4000-8000-000000000001',
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    contratoAlumnoId: 'c0000000-0000-4000-8000-000000000001',
    mesa: 12,
    vale: '0012',
    anotadoPor: 'Pato',
    createdAt: ahora,
    updatedAt: ahora,
  );

  group('sillas_puerta en las listas del motor', () {
    test('sube y baja todas sus columnas: las del modelo y las de la base',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV78(db);
      final enLaBase = {
        for (final c in await db.rawQuery('PRAGMA table_info(sillas_puerta)'))
          c['name'] as String,
      };
      await db.close();
      expect(columnasDelMotor('sillas_puerta'), enLaBase, reason: 'motor y base');
      expect(columnasDelMotor('sillas_puerta'), silla.toMap().keys.toSet(),
          reason: 'motor y modelo');
    });

    test('baja con lo del cobro (la red de 5 minutos) y en la bajada general', () {
      expect(declaracion('_incrementalColumns', '}'),
          contains("'sillas_puerta': 'updated_at'"));
      expect(declaracion('_tablasDelCobro', ']'), contains("'sillas_puerta'"));
      expect(declaracion('_tablasDeCarga', ']'), isNot(contains("'sillas_puerta'")));
      expect(motor, contains("_pullTable(db, 'sillas_puerta', 'updated_at')"));
    });

    test('baja al abrir el evento en Recepción, para trabajar sin internet', () {
      expect(SyncEngine.tablasDeLaPuerta, contains('sillas_puerta'));
    });

    test('es hija del alumno: sube después del contrato', () {
      expect(motor, contains("if (table == 'sillas_puerta') return 4;"));
    });

    test('una silla encolada no se descarta nunca: no es hija en la limpieza de la cola',
        () {
      // `_cleanOrphanQueueEntries` saca de la cola las hijas de un padre que se
      // borra: una silla anotada sin internet se perdería sin subir.
      expect(cola, isNot(contains("'sillas_puerta'")));
    });

    test('no está en ninguna lista que borre filas locales', () {
      expect(declaracion('_tablasAReconciliar', ']'),
          isNot(contains("'sillas_puerta'")));
      expect(declaracion('_hijasEnCascada', '}'),
          isNot(contains("'sillas_puerta'")));
      expect(SyncEngine.tablasSinRevisarBorrados.keys, contains('sillas_puerta'));
    });
  });

  group('el SQL de la nube', () {
    test('tiene cada columna que manda la app', () {
      final crear = RegExp(
        r'create table if not exists public\.sillas_puerta \(([\s\S]*?)\n\);',
      ).firstMatch(sql);
      expect(crear, isNotNull);
      final columnas = {
        for (final l in crear!.group(1)!.split('\n'))
          if (l.trim().isNotEmpty) l.trim().split(' ').first,
      };
      expect(columnas, silla.toMap().keys.toSet());
    });

    test('sin CHECK, sin clave foránea y sin índice único', () {
      // Sin los comentarios: ahí se explica por qué no van.
      final codigo = [
        for (final l in sql.split('\n'))
          if (!l.trimLeft().startsWith('--')) l,
      ].join('\n').toLowerCase();
      // `with check (...)` es de la policy, no un CHECK de la tabla.
      expect(codigo, isNot(matches(RegExp(r'(?<!with )\bcheck\s*\('))));
      expect(codigo, isNot(contains('references')));
      expect(codigo, isNot(contains('unique')));
    });

    test('con la policy de los usuarios logueados y los dos disparadores', () {
      expect(sql, contains("array['sillas_puerta']"));
      expect(sql, contains("t || '_all_authenticated'"));
      expect(sql, contains('set_updated_at_ins_'));
      expect(sql, contains('set_updated_at_upd_'));
      expect(sql, contains('update_updated_at_column()'));
    });

    test('no entra a Realtime', () {
      final codigo = [
        for (final l in sql.split('\n'))
          if (!l.trimLeft().startsWith('--')) l,
      ].join('\n').toLowerCase();
      expect(codigo, isNot(contains('supabase_realtime')));
    });
  });

  test('el repositorio no borra nunca', () {
    expect(repositorio, isNot(contains('.delete(')));
    expect(repositorio, isNot(contains('SyncOperation.delete')));
  });

  // ── barra_vales: los vales que salieron de cada venta, y sus copias ─────────

  final sqlVales = leer('supabase/migrations/20261107100000_barra_vales.sql');
  final barraLocal = leer('lib/features/barra/datos/barra_local.dart');
  final vale = ValeBarra(
    id: 'f0000000-0000-4000-8000-000000000001',
    ventaId: 'd0000000-0000-4000-8000-000000000001',
    cajaBarraId: 'b0000000-0000-4000-8000-000000000001',
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    numeroVale: 2,
    bebidas: const [BebidaDelVale(3, 'Cerveza lata')],
    porSeparado: true,
    copiaNumero: 1,
    motivo: 'se le mojó',
    hechoPor: 'Marta',
    deviceId: 'tablet-1',
    createdAt: '2026-12-01T23:05:00.000Z',
    updatedAt: '2026-12-01T23:05:00.000Z',
  );

  group('barra_vales en las listas del motor', () {
    test('sube y baja todas sus columnas: las del modelo y las de la base',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV78(db);
      final enLaBase = {
        for (final c in await db.rawQuery('PRAGMA table_info(barra_vales)'))
          c['name'] as String,
      };
      await db.close();
      expect(columnasDelMotor('barra_vales'), enLaBase, reason: 'motor y base');
      expect(columnasDelMotor('barra_vales'), vale.toMap().keys.toSet(),
          reason: 'motor y modelo');
    });

    test('baja con lo del cobro (el jefe mira las cajas en vivo) y en la bajada general', () {
      expect(declaracion('_incrementalColumns', '}'),
          contains("'barra_vales': 'updated_at'"));
      expect(declaracion('_tablasDelCobro', ']'), contains("'barra_vales'"));
      expect(declaracion('_tablasDeCarga', ']'), isNot(contains("'barra_vales'")));
      expect(motor, contains("_pullTable(db, 'barra_vales', 'updated_at')"));
    });

    test('sube después de su venta', () {
      expect(motor, contains("if (table == 'barra_vales') return 5;"));
    });

    test('un vale encolado no se descarta nunca: no es hija en la limpieza de la cola', () {
      expect(cola, isNot(contains("'barra_vales'")));
    });

    test('no está en ninguna lista que borre filas locales', () {
      expect(declaracion('_tablasAReconciliar', ']'), isNot(contains("'barra_vales'")));
      expect(declaracion('_hijasEnCascada', '}'), isNot(contains("'barra_vales'")));
      expect(SyncEngine.tablasSinRevisarBorrados.keys, contains('barra_vales'));
    });

    test('el repositorio de la barra no borra nunca', () {
      expect(barraLocal, isNot(contains('.delete(')));
      expect(barraLocal, isNot(contains('SyncOperation.delete')));
    });
  });

  group('el SQL de los vales', () {
    test('tiene cada columna que manda la app', () {
      final crear = RegExp(
        r'create table if not exists public\.barra_vales \(([\s\S]*?)\n\);',
      ).firstMatch(sqlVales);
      expect(crear, isNotNull);
      final columnas = {
        for (final l in crear!.group(1)!.split('\n'))
          if (l.trim().isNotEmpty) l.trim().split(' ').first,
      };
      expect(columnas, vale.toMap().keys.toSet());
    });

    test('sin CHECK, sin clave foránea y sin índice único', () {
      final codigo = [
        for (final l in sqlVales.split('\n'))
          if (!l.trimLeft().startsWith('--')) l,
      ].join('\n').toLowerCase();
      expect(codigo, isNot(matches(RegExp(r'(?<!with )\bcheck\s*\('))));
      expect(codigo, isNot(contains('references')));
      expect(codigo, isNot(contains('unique')));
      expect(codigo, isNot(contains('supabase_realtime')));
    });

    test('con la policy de los usuarios logueados y los dos disparadores', () {
      expect(sqlVales, contains("array['barra_vales']"));
      expect(sqlVales, contains("t || '_all_authenticated'"));
      expect(sqlVales, contains('set_updated_at_ins_'));
      expect(sqlVales, contains('set_updated_at_upd_'));
      expect(sqlVales, contains('update_updated_at_column()'));
    });

    test('lo que manda la app pasa por lo que acepta la nube: casillas como 0 y 1, '
        'las bebidas como texto', () {
      final m = vale.toMap();
      expect(m['por_separado'], 1);
      expect(m['bebidas'], isA<String>());
      expect(ValeBarra.fromMap(m).bebidas, vale.bebidas);
    });
  });
}
