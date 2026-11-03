import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';

/// El SQL de la nube de la v76 (los permisos de los operadores) tiene que aceptar
/// exactamente lo que manda la app. Si la nube rechaza una fila (una columna que no
/// existe, un NOT NULL que llega vacío, un CHECK), el motor de sync la reencola y
/// queda trabada para siempre. Mismo modelo que `sql_v75_coherencia_test.dart`.
const _archivo = 'supabase/migrations/20261103120000_permisos_operador.sql';
const _operador = 'a0000000-0000-4000-8000-000000000001';

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
  final sql = File(_archivo)
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .toLowerCase();

  void laNubeAcepta(String tabla, Map<String, dynamic> fila) {
    final cols = _columnas(sql, tabla);
    expect(fila.keys.toSet(), cols.keys.toSet(),
        reason: 'las columnas de la app y las de la nube, en $tabla');
    for (final e in cols.entries) {
      if (e.value) {
        expect(fila[e.key], isNotNull, reason: '$tabla.${e.key} es NOT NULL');
      }
    }
  }

  test('permisos_operador: la nube acepta la fila que manda la app', () {
    laNubeAcepta(
      'permisos_operador',
      PermisosOperador.para(
        operadorId: _operador,
        permisos: const PermisosEfectivos(entradas: true),
        ahora: DateTime.utc(2026, 11, 3, 12),
      ).toMap(),
    );
  });

  test('permisos_operador_cambios: la nube acepta el renglón que manda la app', () {
    final cambios = CambioDePermiso.entre(
      operadorId: _operador,
      antes: PermisosEfectivos.soloCobros,
      despues: const PermisosEfectivos(entradas: true),
      ahora: DateTime.utc(2026, 11, 3, 12),
    );
    expect(cambios, hasLength(2));
    for (final c in cambios) {
      laNubeAcepta('permisos_operador_cambios', c.toMap());
    }
  });

  test('sin CHECK, sin clave foránea y sin índice único: nada puede trabar la subida', () {
    for (final tabla in ['permisos_operador', 'permisos_operador_cambios']) {
      final inicio = sql.indexOf('create table if not exists public.$tabla (');
      final cuerpo = sql.substring(inicio, sql.indexOf('\n);', inicio));
      expect(cuerpo, isNot(contains('check')), reason: tabla);
      expect(cuerpo, isNot(contains('references')), reason: tabla);
      expect(cuerpo, isNot(contains('unique')), reason: tabla);
    }
    final codigo = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
    expect(codigo, isNot(contains('create unique index')));
  });

  test('lo que crea tiene su ROLLBACK escrito', () {
    expect(sql, contains('rollback: drop table if exists public.permisos_operador;'));
    expect(sql, contains('rollback: drop table if exists public.permisos_operador_cambios;'));
    expect(sql, contains('alter table public.permisos_operador disable row level security'));
    expect(sql, contains('alter table public.permisos_operador_cambios disable row level security'));
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
        'permisos_operador',
        'permisos_operador_cambios',
        'update_updated_at_column',
        '%i',
        '%1\$i',
      });
    });

    test('el bucle de RLS y disparadores recorre solo las tablas nuevas', () {
      expect(
        codigo,
        contains("foreach t in array array['permisos_operador', 'permisos_operador_cambios']"),
      );
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
