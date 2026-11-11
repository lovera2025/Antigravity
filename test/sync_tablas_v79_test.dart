import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/barra/central/filas_de_la_red.dart';
import 'package:arguello_events/features/barra/datos/paso_del_cierre.dart';

/// La tabla de la v79 (`barra_cierres`: el pedido de cierre de una caja de barra y
/// el OK de la encargada) en el motor de sincronización, en la red del salón, en el
/// SQL de la nube y en su repositorio. Mismo modelo que `sync_tablas_v78_test.dart`:
/// las listas del motor son privadas y se leen del texto del archivo.
void main() {
  sqfliteFfiInit();

  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  final motor = leer('lib/core/services/sync_engine.dart');
  final cola = leer('lib/core/database/sync_queue.dart');
  final sql = leer('supabase/migrations/20261111120000_barra_cierres.sql');
  final barraLocal = leer('lib/features/barra/datos/barra_local.dart');
  final barraNube = leer('lib/features/barra/datos/barra_nube.dart');

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

  const paso = PasoDelCierre(
    id: 'd0000000-0000-4000-8000-000000000001',
    cajaBarraId: 'b0000000-0000-4000-8000-000000000001',
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    tipoClave: 'ok',
    pedidoId: 'd0000000-0000-4000-8000-000000000002',
    efectivoContado: 27000,
    nota: 'faltó un billete',
    hechoPor: 'Romi',
    deviceId: 'tablet-2',
    createdAt: '2026-12-05T08:05:00.000Z',
    updatedAt: '2026-12-05T08:05:00.000Z',
  );

  group('barra_cierres en las listas del motor', () {
    test('sube y baja todas sus columnas: las del modelo y las de la base',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV79(db);
      final enLaBase = {
        for (final c in await db.rawQuery('PRAGMA table_info(barra_cierres)'))
          c['name'] as String,
      };
      await db.close();
      expect(columnasDelMotor('barra_cierres'), enLaBase, reason: 'motor y base');
      expect(columnasDelMotor('barra_cierres'), paso.toMap().keys.toSet(),
          reason: 'motor y modelo');
    });

    test('va y vuelve de la base igual', () {
      final vuelta = PasoDelCierre.fromMap(paso.toMap());
      expect(vuelta.toMap(), paso.toMap());
      expect(vuelta.tipo, TipoPasoDelCierre.ok);
    });

    test('baja con lo del cobro (la cajera espera el OK) y en la bajada general', () {
      expect(declaracion('_incrementalColumns', '}'),
          contains("'barra_cierres': 'updated_at'"));
      expect(declaracion('_tablasDelCobro', ']'), contains("'barra_cierres'"));
      expect(declaracion('_tablasDeCarga', ']'), isNot(contains("'barra_cierres'")));
      expect(motor, contains("_pullTable(db, 'barra_cierres', 'updated_at')"));
    });

    test('sube después de su caja', () {
      expect(motor, contains("if (table == 'barra_cierres') return 5;"));
    });

    test('un pedido encolado no se descarta nunca: no es hija en la limpieza de la cola',
        () {
      expect(cola, isNot(contains("'barra_cierres'")));
    });

    test('no está en ninguna lista que borre filas locales', () {
      expect(declaracion('_tablasAReconciliar', ']'),
          isNot(contains("'barra_cierres'")));
      expect(declaracion('_hijasEnCascada', '}'),
          isNot(contains("'barra_cierres'")));
      expect(SyncEngine.tablasSinRevisarBorrados.keys, contains('barra_cierres'));
    });

    test('cruza por la red del salón: sin internet el OK tiene que llegar igual', () {
      expect(tablasDeLaRed, contains('barra_cierres'));
    });
  });

  group('el SQL de la nube', () {
    test('tiene cada columna que manda la app', () {
      final crear = RegExp(
        r'create table if not exists public\.barra_cierres \(([\s\S]*?)\n\);',
      ).firstMatch(sql);
      expect(crear, isNotNull);
      final columnas = {
        for (final l in crear!.group(1)!.split('\n'))
          if (l.trim().isNotEmpty) l.trim().split(' ').first,
      };
      expect(columnas, paso.toMap().keys.toSet());
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

    test('solo crea: no toca ninguna tabla que ya exista', () {
      final codigo = [
        for (final l in sql.split('\n'))
          if (!l.trimLeft().startsWith('--')) l,
      ].join('\n').toLowerCase();
      expect(codigo, isNot(contains('alter table public.barra_cajas')));
      expect(codigo, isNot(matches(RegExp(r'\b(drop table|delete from|update public\.|insert into)\b'))));
      expect(RegExp(r'create table (?!if not exists)').hasMatch(codigo), isFalse);
      expect(RegExp(r'create index (?!if not exists)').hasMatch(codigo), isFalse);
    });

    test('con la policy de los usuarios logueados y los dos disparadores', () {
      expect(sql, contains("array['barra_cierres']"));
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

  group('los repositorios', () {
    test('en el equipo solo se agregan filas, con la cola de subida', () {
      final i = barraLocal.indexOf('Future<PasoDelCierre> anotarPasoDelCierre(');
      expect(i, greaterThan(0));
      final cuerpo = barraLocal.substring(i, barraLocal.indexOf('\n  }\n', i));
      expect(cuerpo, contains("_guardar(txn, 'barra_cierres'"));
      expect(barraLocal, isNot(contains("delete('barra_cierres'")));
    });

    test('en la nube el orden va siempre con ascending: true, y no pisa una fila', () {
      final i = barraNube.indexOf("from('barra_cierres')");
      expect(i, greaterThan(0));
      final lectura = barraNube.substring(i, barraNube.indexOf(');', i));
      for (final m in RegExp(r'\.order\(([^)]*)\)').allMatches(lectura)) {
        expect(m.group(1), contains('ascending: true'));
      }
      expect(barraNube, contains("from('barra_cierres').upsert(conEquipo.toMap(), ignoreDuplicates: true)"));
    });
  });
}
