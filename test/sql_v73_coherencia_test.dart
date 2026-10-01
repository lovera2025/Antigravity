import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// El SQL de la nube de la v73 tiene que aceptar exactamente lo que manda la
/// app. Si la nube rechaza una fila (una columna que no existe, un NOT NULL que
/// llega vacío, un CHECK que no coincide), el motor de sync la toma como un
/// padre que falta, reencola el evento y la fila queda trabada para siempre.
///
/// Este test lee el archivo SQL y lo compara con `toMap()`.
const _archivo = 'supabase/migrations/20260926120000_planos_y_cambios_de_mesa.sql';

/// Columnas de `create table if not exists public.<tabla> (...)`, con si son
/// NOT NULL.
Map<String, bool> _columnas(String sql, String tabla) {
  final inicio = sql.indexOf('create table if not exists public.$tabla (');
  expect(inicio, isNot(-1), reason: 'no está la tabla $tabla');
  final fin = sql.indexOf('\n);', inicio);
  final cuerpo = sql.substring(sql.indexOf('(', inicio) + 1, fin);
  final columnas = <String, bool>{};
  for (final linea in cuerpo.split('\n')) {
    final l = linea.trim();
    if (l.isEmpty || l.startsWith('--') || l.startsWith('constraint')) continue;
    if (l.startsWith('references')) continue;
    final nombre = l.split(RegExp(r'\s+')).first;
    columnas[nombre] = l.contains('not null') || l.contains('primary key');
  }
  return columnas;
}

void main() {
  final sql = File(_archivo).readAsStringSync().toLowerCase();
  final ahora = DateTime.utc(2026, 9, 26);

  void comparar(String tabla, Map<String, dynamic> fila) {
    final cols = _columnas(sql, tabla);
    expect(fila.keys.toSet(), cols.keys.toSet(),
        reason: '$tabla: las columnas de la app y las de la nube');
    for (final e in cols.entries) {
      if (e.value) {
        expect(fila[e.key], isNotNull, reason: '$tabla.${e.key} es NOT NULL');
      }
    }
  }

  test('planos_evento: la nube acepta la fila que manda la app', () {
    for (final e in EstiloPlano.values) {
      for (final m in ModoSorteo.values) {
        final p = PlanoEvento.nuevo(
          eventoId: 'e0000000-0000-4000-8000-000000000001',
          armado: ArmadosPredefinidos.tecnica1a1b(),
          estilo: e,
          modo: m,
          ahora: ahora,
        );
        comparar('planos_evento', p.toMap());
      }
    }
  });

  test('mesas_movimientos: la nube acepta la fila que manda la app', () {
    for (final t in TipoMovimientoMesas.values) {
      final m = MovimientoMesas(
        id: 'b0000000-0000-4000-8000-000000000001',
        eventoId: 'e0000000-0000-4000-8000-000000000001',
        tipo: t,
        antes: const {'a': '1'},
        despues: const {'a': null},
        motivo: 'motivo',
        createdAt: ahora,
      );
      comparar('mesas_movimientos', m.toMap());
    }
  });

  test('sin CHECK en las tablas nuevas: no hay nada que pueda trabar la subida',
      () {
    for (final t in ['planos_evento', 'mesas_movimientos']) {
      final inicio = sql.indexOf('create table if not exists public.$t (');
      final fin = sql.indexOf('\n);', inicio);
      expect(sql.substring(inicio, fin), isNot(contains('check')), reason: t);
    }
  });

  test('una fila por fiesta también en la nube', () {
    expect(sql, contains('unique (evento_id)'));
  });

  test('cada sentencia que crea algo tiene su ROLLBACK escrito', () {
    expect(sql, contains('rollback: drop table if exists public.planos_evento'));
    expect(
      sql,
      contains('rollback: drop table if exists public.mesas_movimientos'),
    );
    // Deshacer solo la sección 3 sin apagar la RLS deja las tablas cerradas
    // para la app: nada sube, y la otra PC no se entera.
    expect(sql, contains('alter table public.<tabla> disable row level security'));
  });

  test('la verificación también mira la policy de cada tabla', () {
    expect(sql, contains('select tablename, policyname from pg_policies'));
  });

  group('lo que el SQL ejecuta de verdad (sin los comentarios)', () {
    // Los tests de arriba buscan en todo el archivo, comentarios incluidos.
    // Acá se mira solo lo que corre: es lo que toca la base de producción.
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
        'planos_evento',
        'mesas_movimientos',
        // Solo como destino de la clave foránea.
        'eventos',
        // La función del disparador, que ya existe.
        'update_updated_at_column',
        // `format('... public.%I ...', t)`: las dos tablas del bucle.
        '%i',
        '%1\$i',
      });
      expect(
        RegExp(r'references public\.eventos\(id\)').allMatches(codigo).length,
        2,
        reason: '`eventos` aparece solo en las dos claves foráneas',
      );
      expect(
        RegExp(r'public\.eventos').allMatches(codigo).length,
        2,
        reason: '`eventos` no aparece en ninguna otra sentencia',
      );
    });

    test('el bucle de RLS y disparadores recorre solo las dos tablas nuevas',
        () {
      expect(
        codigo,
        contains("foreach t in array array['planos_evento', 'mesas_movimientos']"),
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
      expect(
        RegExp(r'\bupdate\s+public\.').hasMatch(codigo),
        isFalse,
        reason: 'ningún UPDATE de filas',
      );
    });

    test('todo lo que crea lleva "if not exists" o se puede repetir', () {
      expect(
        RegExp(r'create (table|index) (?!if not exists)').hasMatch(codigo),
        isFalse,
      );
      // Los disparadores se crean con su `drop trigger if exists` antes.
      expect(
        RegExp(r'drop trigger if exists').allMatches(codigo).length,
        RegExp(r'create trigger').allMatches(codigo).length,
      );
    });
  });
}
