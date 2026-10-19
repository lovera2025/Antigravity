import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/predios_del_salon.dart';

/// El SQL de la nube de la v74 tiene que aceptar exactamente lo que manda la
/// app. Si la nube rechaza una fila (una columna que no existe, un NOT NULL que
/// llega vacío, un CHECK), el motor de sync la reencola y queda trabada para
/// siempre.
///
/// Este test lee el archivo SQL y lo compara con `toMap()`.
const _archivo = 'supabase/migrations/20261020120000_predios.sql';

Map<String, bool> _columnas(String sql, String tabla) {
  final inicio = sql.indexOf('create table if not exists public.$tabla (');
  expect(inicio, isNot(-1), reason: 'no está la tabla $tabla');
  final fin = sql.indexOf('\n);', inicio);
  final cuerpo = sql.substring(sql.indexOf('(', inicio) + 1, fin);
  final columnas = <String, bool>{};
  for (final linea in cuerpo.split('\n')) {
    final l = linea.trim();
    if (l.isEmpty || l.startsWith('--') || l.startsWith('constraint')) continue;
    final nombre = l.split(RegExp(r'\s+')).first;
    columnas[nombre] = l.contains('not null') || l.contains('primary key');
  }
  return columnas;
}

void main() {
  final sql = File(_archivo).readAsStringSync().toLowerCase();
  final ahora = DateTime.utc(2026, 10, 20);

  test('predios: la nube acepta la fila que manda la app', () {
    final nuevo = PrediosDelSalon.guardarComo(
      nombre: 'Buena Vista',
      armado: ArmarAMedida.vacio(PlayonReal.costaSurubi),
      playon: PlayonReal.costaSurubi,
      guardados: const [],
      hechoPor: null,
      ahora: ahora,
    ).predio!;
    final borrado = PrediosDelSalon.borrar(nuevo, hechoPor: 'Jefe', ahora: ahora);
    final cols = _columnas(sql, 'predios');
    for (final fila in [nuevo.toMap(), borrado.toMap()]) {
      expect(fila.keys.toSet(), cols.keys.toSet(),
          reason: 'las columnas de la app y las de la nube');
      for (final e in cols.entries) {
        if (e.value) {
          expect(fila[e.key], isNotNull, reason: 'predios.${e.key} es NOT NULL');
        }
      }
    }
  });

  test('sin CHECK y sin clave foránea: no hay nada que pueda trabar la subida',
      () {
    final inicio = sql.indexOf('create table if not exists public.predios (');
    final fin = sql.indexOf('\n);', inicio);
    final cuerpo = sql.substring(inicio, fin);
    expect(cuerpo, isNot(contains('check')));
    expect(cuerpo, isNot(contains('references')));
  });

  test('la sentencia que crea tiene su ROLLBACK escrito', () {
    expect(sql, contains('rollback: drop table if exists public.predios'));
    expect(sql, contains('alter table public.predios disable row level security'));
  });

  test('la verificación mira la policy y Realtime', () {
    expect(sql, contains('select tablename, policyname from pg_policies'));
    expect(sql, contains('from pg_publication_tables'));
  });

  group('lo que el SQL ejecuta de verdad (sin los comentarios)', () {
    final codigo = sql
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');

    test('no toca ninguna tabla que ya existe', () {
      final nombradas = {
        for (final m in RegExp(r'public\.([a-z_%0-9$]+)').allMatches(codigo))
          m.group(1)!,
      };
      expect(nombradas, {
        'predios',
        // La función del disparador, que ya existe.
        'update_updated_at_column',
        // `format('... public.%I ...', t)`: la tabla del bucle.
        '%i',
        '%1\$i',
      });
    });

    test('el bucle de RLS y disparadores recorre solo la tabla nueva', () {
      expect(codigo, contains("foreach t in array array['predios']"));
    });

    test('no borra, no modifica filas y no entra a Realtime', () {
      for (final prohibido in [
        'drop table',
        'delete from',
        'truncate',
        'insert into',
        'alter publication',
        'drop column',
        'add column',
      ]) {
        expect(codigo, isNot(contains(prohibido)), reason: prohibido);
      }
      expect(RegExp(r'\bupdate\s+public\.').hasMatch(codigo), isFalse);
    });

    test('todo lo que crea lleva "if not exists" o se puede repetir', () {
      expect(
        RegExp(r'create (table|index) (?!if not exists)').hasMatch(codigo),
        isFalse,
      );
      expect(
        RegExp(r'drop trigger if exists').allMatches(codigo).length,
        RegExp(r'create trigger').allMatches(codigo).length,
      );
    });
  });
}
