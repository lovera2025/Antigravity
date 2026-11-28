import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/models/como_lo_nombran.dart';

/// **`como_lo_nombran` (v85, el locutor) en el motor y en la nube**, como
/// `test/sync_tablas_v78_test.dart` con las sillas de la noche: las mismas columnas en el
/// modelo, la base, el motor y el SQL; baja con lo del cobro y para la puerta sin
/// internet; no está en ninguna lista que borre; el SQL sin CHECK, sin clave foránea y
/// sin único, con su policy y sus dos disparadores, fuera de Realtime.
void main() {
  sqfliteFfiInit();

  String leer(String ruta) => File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  final motor = leer('lib/core/services/sync_engine.dart');
  final cola = leer('lib/core/database/sync_queue.dart');
  final sql = leer('supabase/migrations/20261128120000_como_lo_nombran.sql');
  final repositorio = leer('lib/features/recepcion/repositories/como_lo_nombran_repository.dart');

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

  final fila = ComoLoNombran.para(
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    contratoAlumnoId: 'c0000000-0000-4000-8000-000000000001',
    alumno: 'Ani',
    alumnoCargado: 'CEIBO, ANA',
    cambiadoPor: 'Juli',
    ahora: DateTime.utc(2026, 12, 5, 1),
  );

  group('como_lo_nombran en las listas del motor', () {
    test('sube y baja todas sus columnas: las del modelo y las de la base', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV85(db);
      final enLaBase = {
        for (final c in await db.rawQuery('PRAGMA table_info(como_lo_nombran)')) c['name'] as String,
      };
      await db.close();
      expect(columnasDelMotor('como_lo_nombran'), enLaBase, reason: 'motor y base');
      expect(columnasDelMotor('como_lo_nombran'), fila.toMap().keys.toSet(), reason: 'motor y modelo');
    });

    test('baja con lo del cobro (la red de 5 minutos) y en la bajada general', () {
      expect(declaracion('_incrementalColumns', '}'), contains("'como_lo_nombran': 'updated_at'"));
      expect(declaracion('_tablasDelCobro', ']'), contains("'como_lo_nombran'"));
      expect(motor, contains("_pullTable(db, 'como_lo_nombran', 'updated_at')"));
    });

    test('baja al abrir el evento en Recepción, para la noche sin internet', () {
      expect(SyncEngine.tablasDeLaPuerta, contains('como_lo_nombran'));
    });

    test('es hija del alumno: sube después del contrato', () {
      expect(motor, contains("if (table == 'como_lo_nombran') return 4;"));
    });

    test('lo encolado no se descarta nunca, y no está en ninguna lista que borre', () {
      expect(cola, isNot(contains("'como_lo_nombran'")));
      expect(declaracion('_tablasAReconciliar', ']'), isNot(contains("'como_lo_nombran'")));
      expect(declaracion('_hijasEnCascada', '}'), isNot(contains("'como_lo_nombran'")));
      expect(SyncEngine.tablasSinRevisarBorrados.keys, contains('como_lo_nombran'));
      expect(repositorio, isNot(contains('.delete(')), reason: 'el repositorio no borra');
    });
  });

  group('el SQL de la nube', () {
    test('tiene cada columna que manda la app', () {
      final crear = RegExp(r'create table if not exists public\.como_lo_nombran \(([\s\S]*?)\n\);').firstMatch(sql);
      expect(crear, isNotNull);
      final columnas = {
        for (final l in crear!.group(1)!.split('\n'))
          if (l.trim().isNotEmpty) l.trim().split(' ').first,
      };
      expect(columnas, fila.toMap().keys.toSet());
    });

    test('sin CHECK, sin clave foránea y sin índice único; con su policy y sus dos disparadores; fuera de Realtime',
        () {
      final codigo = [
        for (final l in sql.split('\n'))
          if (!l.trimLeft().startsWith('--')) l,
      ].join('\n').toLowerCase();
      expect(codigo, isNot(matches(RegExp(r'(?<!with )\bcheck\s*\('))));
      expect(codigo, isNot(contains('references')));
      expect(codigo, isNot(contains('unique')));
      expect(codigo, contains("array['como_lo_nombran']"));
      expect(codigo, contains('enable row level security'));
      expect(codigo, contains('set_updated_at_ins_'));
      expect(codigo, contains('set_updated_at_upd_'));
      expect(codigo, isNot(contains('supabase_realtime')));
      expect(codigo, isNot(contains('contratos_alumnos')), reason: 'no toca la ficha de la oficina');
    });
  });
}
