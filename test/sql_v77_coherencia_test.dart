import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// El SQL de la nube de la v77 (la barra) tiene que aceptar exactamente lo que manda
/// la app. Si la nube rechaza una fila (una columna que no existe, un NOT NULL que
/// llega vacío, un CHECK), el motor de sync la reencola y queda trabada para siempre:
/// una venta que no sube. Mismo modelo que `sql_v76_coherencia_test.dart`.
const _archivo = 'supabase/migrations/20261103140000_barra.sql';
const _evento = 'e0000000-0000-4000-8000-000000000001';
const _operador = 'a0000000-0000-4000-8000-000000000001';
const _tablas = [
  'barra_productos',
  'barra_precios',
  'barra_cajas',
  'barra_ventas',
  'barra_anulaciones',
];

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
    // Con default también: la app manda todas las columnas, y un null explícito en
    // una NOT NULL la nube lo rechaza aunque tenga default.
    columnas[nombre] = l.contains('not null') || l.contains('primary key');
  }
  return columnas;
}

void main() {
  final sql = File(_archivo)
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .toLowerCase();
  final ahora = DateTime.utc(2026, 12, 4, 23, 41);

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

  final producto = ProductoBarra.nuevo(nombre: 'Cerveza lata', ahora: ahora);
  final caja = CajaBarra.abrir(
    eventoId: _evento,
    operadorId: _operador,
    operadorNombre: 'Marta',
    numeroCaja: 2,
    ahora: ahora,
  );
  final venta = VentaBarra.nueva(
    cajaBarraId: caja.id,
    eventoId: _evento,
    numero: 17,
    renglones: [
      RenglonVenta(productoId: producto.id, nombre: producto.nombre, precio: 3500, cantidad: 2),
    ],
    medio: MedioBarra.efectivo,
    efectivo: 7000,
    recibe: 10000,
    ahora: ahora,
  );

  test('barra_productos: la nube acepta la fila que manda la app', () {
    laNubeAcepta('barra_productos', producto.toMap());
    laNubeAcepta('barra_productos', producto.conImagen('https://x/y.jpg').toMap());
  });

  test('barra_precios: con stock y sin stock', () {
    laNubeAcepta(
      'barra_precios',
      PrecioBarra.para(eventoId: _evento, productoId: producto.id, precio: 3500, ahora: ahora)
          .toMap(),
    );
    laNubeAcepta(
      'barra_precios',
      PrecioBarra.para(
        eventoId: _evento,
        productoId: producto.id,
        precio: 3500,
        stockInicial: 240,
        avisoStock: 24,
        ahora: ahora,
      ).toMap(),
    );
  });

  test('barra_cajas: abierta y cerrada', () {
    laNubeAcepta('barra_cajas', caja.toMap());
    laNubeAcepta(
      'barra_cajas',
      caja.cerrada(efectivoContado: 50000, diferencia: -500, ahora: ahora).toMap(),
    );
  });

  test('barra_ventas: la nube acepta la venta que manda la app', () {
    laNubeAcepta('barra_ventas', venta.toMap());
  });

  test('barra_anulaciones: la nube acepta la anulación', () {
    laNubeAcepta(
      'barra_anulaciones',
      AnulacionBarra.de(venta, motivo: 'se cobró dos veces', ahora: ahora).toMap(),
    );
  });

  test('los ids y las claves son uuid en la nube, como los manda la app', () {
    for (final (tabla, columna) in [
      ('barra_productos', 'id'),
      ('barra_precios', 'evento_id'),
      ('barra_precios', 'producto_id'),
      ('barra_cajas', 'operador_id'),
      ('barra_ventas', 'caja_barra_id'),
      ('barra_anulaciones', 'venta_id'),
    ]) {
      final inicio = sql.indexOf('create table if not exists public.$tabla (');
      final cuerpo = sql.substring(inicio, sql.indexOf('\n);', inicio));
      expect(RegExp('\\n  $columna uuid').hasMatch(cuerpo), isTrue, reason: '$tabla.$columna');
    }
    expect(caja.operadorId!.length, 36);
  });

  test('sin CHECK, sin clave foránea y sin índice único: nada puede trabar la subida', () {
    for (final tabla in _tablas) {
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
    for (final tabla in _tablas) {
      expect(sql, contains('rollback: drop table if exists public.$tabla;'));
    }
    expect(sql, contains('alter table public.barra_productos disable row level security'));
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
        ..._tablas,
        'update_updated_at_column',
        '%i',
        '%1\$i',
      });
    });

    test('el bucle de RLS y disparadores recorre solo las tablas nuevas', () {
      expect(
        codigo,
        contains("foreach t in array array['barra_productos', 'barra_precios', "
            "'barra_cajas', 'barra_ventas', 'barra_anulaciones']"),
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
