import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/models/mora_congelada_alumno.dart';

/// El SQL de la nube de la v75 (la mora congelada) tiene que aceptar exactamente
/// lo que manda la app. Si la nube rechaza una fila (una columna que no existe,
/// un NOT NULL que llega vacío, un CHECK), el motor de sync la reencola y queda
/// trabada para siempre. Mismo modelo que `sql_v74_coherencia_test.dart`.
const _archivo = 'supabase/migrations/20261023210000_mora_congelada.sql';

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

  test('mora_congelada: la nube acepta la fila que manda la app', () {
    final congelada = MoraCongeladaAlumno.para(
      contratoAlumnoId: 'c0000000-0000-4000-8000-000000000001',
      eventoId: 'e0000000-0000-4000-8000-000000000001',
      mora: MoraCongelada.nada.congelar(todas: true, dia: DateTime(2026, 10, 23)),
      ahora: DateTime.utc(2026, 10, 23, 12),
    );
    final descongelada = MoraCongeladaAlumno.para(
      contratoAlumnoId: 'c0000000-0000-4000-8000-000000000001',
      mora: MoraCongelada.nada,
      ahora: DateTime.utc(2026, 11, 2, 12),
    );
    final cols = _columnas(sql, 'mora_congelada');
    for (final fila in [congelada.toMap(), descongelada.toMap()]) {
      expect(fila.keys.toSet(), cols.keys.toSet(),
          reason: 'las columnas de la app y las de la nube');
      for (final e in cols.entries) {
        if (e.value) {
          expect(fila[e.key], isNotNull, reason: 'mora_congelada.${e.key} es NOT NULL');
        }
      }
    }
  });

  test('sin CHECK, sin clave foránea y sin índice único: nada puede trabar la subida', () {
    final inicio = sql.indexOf('create table if not exists public.mora_congelada (');
    final fin = sql.indexOf('\n);', inicio);
    final cuerpo = sql.substring(inicio, fin);
    expect(cuerpo, isNot(contains('check')));
    expect(cuerpo, isNot(contains('references')));
    expect(cuerpo, isNot(contains('unique')));
    final codigo = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
    expect(codigo, isNot(contains('create unique index')));
  });

  test('la sentencia que crea tiene su ROLLBACK escrito', () {
    expect(sql, contains('rollback: drop table if exists public.mora_congelada'));
    expect(sql, contains('alter table public.mora_congelada disable row level security'));
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
        'mora_congelada',
        'update_updated_at_column',
        '%i',
        '%1\$i',
      });
    });

    test('el bucle de RLS y disparadores recorre solo la tabla nueva', () {
      expect(codigo, contains("foreach t in array array['mora_congelada']"));
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
