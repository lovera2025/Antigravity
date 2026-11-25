import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/barra/datos/movimiento_de_stock.dart';
import 'package:arguello_events/features/barra/datos/stock_en_la_barra.dart';

/// Las dos tablas de la v83 (el stock por barra) en el motor de sincronización y en el
/// SQL de la nube. Mismo modelo que `sync_tablas_v79_test.dart`: las listas del motor
/// son privadas y se leen del texto del archivo.
///
/// Lo de la red del salón (`tablasDeLaRed`) y los repositorios va con su etapa: se
/// agrega acá cuando se programe.
void main() {
  sqfliteFfiInit();

  String leer(String ruta) => File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  final motor = leer('lib/core/services/sync_engine.dart');
  final cola = leer('lib/core/database/sync_queue.dart');
  final sql = leer('supabase/migrations/20261125120000_barra_stock.sql');

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
    return {for (final c in RegExp("'([a-z_]+)'").allMatches(m!.group(1)!)) c.group(1)!};
  }

  Set<String> columnasDelSql(String tabla) {
    final crear = RegExp('create table if not exists public\\.$tabla \\(([\\s\\S]*?)\\n\\);').firstMatch(sql);
    expect(crear, isNotNull, reason: '$tabla no está en el SQL');
    return {
      for (final l in crear!.group(1)!.split('\n'))
        if (l.trim().isNotEmpty) l.trim().split(' ').first,
    };
  }

  Future<Set<String>> columnasDeLaBase(String tabla) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LocalDatabase.crearTablasV83(db);
    final cols = {for (final c in await db.rawQuery('PRAGMA table_info($tabla)')) c['name'] as String};
    await db.close();
    return cols;
  }

  final ahora = DateTime.utc(2026, 12, 4, 23);
  final reparto = StockEnLaBarra.para(
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    productoId: 'f0000000-0000-4000-8000-000000000001',
    barra: 'Barra 1',
    arranque: 60,
    ahora: ahora,
  );
  final movimiento = MovimientoDeStock.conteo(
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    productoId: 'f0000000-0000-4000-8000-000000000001',
    lugar: 'Barra 1',
    contadas: 58,
    foto: const FotoDeStock(),
    ajuste: -2,
    motivo: 'Rota',
    ahora: ahora,
  );

  for (final (tabla, modelo) in [
    ('barra_stock_barras', reparto.toMap()),
    ('barra_stock_movimientos', movimiento.toMap()),
  ]) {
    group('$tabla en las listas del motor', () {
      test('sube y baja todas sus columnas: las del modelo, las de la base y las del SQL', () async {
        expect(columnasDelMotor(tabla), await columnasDeLaBase(tabla), reason: 'motor y base');
        expect(columnasDelMotor(tabla), modelo.keys.toSet(), reason: 'motor y modelo');
        expect(columnasDelSql(tabla), modelo.keys.toSet(), reason: 'SQL y modelo');
      });

      test('baja con lo del cobro (sin stock no se vende) y en la bajada general', () {
        expect(declaracion('_incrementalColumns', '}'), contains("'$tabla': 'updated_at'"));
        expect(declaracion('_tablasDelCobro', ']'), contains("'$tabla'"));
        expect(declaracion('_tablasDeCarga', ']'), isNot(contains("'$tabla'")));
        expect(motor, contains("_pullTable(db, '$tabla', 'updated_at')"));
      });

      test('sube después de la fiesta, como el precio', () {
        expect(motor, contains("table == '$tabla'"));
      });

      test('no se descarta de la cola ni está en ninguna lista que borre filas locales', () {
        expect(cola, isNot(contains("'$tabla'")));
        expect(declaracion('_tablasAReconciliar', ']'), isNot(contains("'$tabla'")));
        expect(declaracion('_hijasEnCascada', '}'), isNot(contains("'$tabla'")));
        expect(SyncEngine.tablasSinRevisarBorrados.keys, contains(tabla));
      });
    });
  }

  group('el SQL de la nube', () {
    final codigo = [
      for (final l in sql.split('\n'))
        if (!l.trimLeft().startsWith('--')) l,
    ].join('\n').toLowerCase();

    test('sin CHECK, sin clave foránea y sin índice único', () {
      expect(codigo, isNot(matches(RegExp(r'(?<!with )\bcheck\s*\('))));
      expect(codigo, isNot(contains('references')));
      expect(codigo, isNot(contains('unique')));
    });

    test('solo crea: no toca ninguna tabla que ya exista', () {
      expect(codigo, isNot(matches(RegExp(r'\b(drop table|delete from|update public\.|insert into)\b'))));
      expect(RegExp(r'alter table public\.(?!%i)').hasMatch(codigo), isFalse);
      expect(RegExp(r'create table (?!if not exists)').hasMatch(codigo), isFalse);
      expect(RegExp(r'create index (?!if not exists)').hasMatch(codigo), isFalse);
    });

    test('con la policy de los usuarios logueados y los dos disparadores', () {
      expect(sql, contains("array['barra_stock_barras', 'barra_stock_movimientos']"));
      expect(sql, contains("t || '_all_authenticated'"));
      expect(sql, contains('set_updated_at_ins_'));
      expect(sql, contains('set_updated_at_upd_'));
      expect(sql, contains('update_updated_at_column()'));
    });

    test('no entra a Realtime', () {
      expect(codigo, isNot(contains('supabase_realtime')));
    });
  });
}
