// El link del delegado, cerrado (6.8.0). Quien abre el link no tiene usuario:
// **no lee ni escribe ninguna tabla**, va por las funciones de
// `supabase/migrations/20261113120000_link_delegado.sql`. Las reglas de esas
// funciones se prueban contra el mismo archivo, en un Postgres de prueba
// (`tool/delegado_sandbox/pruebas.mjs`); acá se cuida que el programa y el SQL
// digan lo mismo, y que nada vuelva a abrirse sin que un test lo note.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/delegado/datos/nube_del_delegado.dart';
import 'package:arguello_events/features/eventos/services/planilla_delegado.dart';

String _leer(String ruta) => File(ruta).readAsStringSync();

/// Sin los renglones que son solo comentario.
String _sinComentarios(String sql) => sql
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('--'))
    .join('\n');

/// Las funciones que llama un archivo, con los parámetros que manda.
Map<String, Set<String>> _llamadas(String dart) {
  final r = <String, Set<String>>{};
  final rpc = RegExp(r"\.rpc\(\s*'(\w+)'");
  for (final m in rpc.allMatches(dart)) {
    final hasta = dart.indexOf(')));', m.end);
    final otra = dart.indexOf('.rpc(', m.end);
    final fin = [
      if (hasta >= 0) hasta,
      if (otra >= 0) otra,
      dart.length,
    ].reduce((a, b) => a < b ? a : b);
    r[m.group(1)!] = {
      for (final p in RegExp(r"'(p_\w+)'").allMatches(dart.substring(m.end, fin)))
        p.group(1)!,
    };
  }
  return r;
}

/// Los parámetros de cada función del SQL.
Map<String, Set<String>> _funciones(String sql) => {
      for (final m in RegExp(
        r'create or replace function public\.(\w+)\(([^)]*)\)',
      ).allMatches(sql))
        m.group(1)!: {
          for (final p in RegExp(r'\b(p_\w+)\s').allMatches('${m.group(2)} '))
            p.group(1)!,
        },
    };

void main() {
  final sql = _leer('supabase/migrations/20261113120000_link_delegado.sql');
  final codigo = _sinComentarios(sql);
  final pagina = _leer('lib/features/delegado/datos/nube_del_delegado.dart');
  final programa = _leer('lib/features/delegado/datos/link_del_delegado.dart');
  final funciones = _funciones(sql);

  const delDelegado = {
    'delegado_lista',
    'delegado_entrar',
    'delegado_guardar',
    'delegado_entregar',
  };
  const delJefe = {
    'delegado_link_crear',
    'delegado_link',
    'delegado_link_cambiar',
    'delegado_cargas',
    'delegado_pendientes',
  };

  group('el SQL y lo que llama el programa', () {
    test('la página llama solo a las funciones del delegado, con sus '
        'parámetros', () {
      final llamadas = _llamadas(pagina);
      expect(llamadas.keys.toSet(), delDelegado);
      for (final e in llamadas.entries) {
        expect(e.value, funciones[e.key], reason: e.key);
      }
    });

    test('el programa llama solo a las funciones del jefe, con sus '
        'parámetros', () {
      final llamadas = _llamadas(programa);
      expect(llamadas.keys.toSet(), delJefe);
      for (final e in llamadas.entries) {
        expect(e.value, funciones[e.key], reason: e.key);
      }
    });

    test('toda llamada lleva `params`, también la que no manda ninguno', () {
      // Sin `params` la librería manda `null` de cuerpo, no `{}`: así el aviso
      // del inicio no llegaba nunca (lo encontró la prueba de punta a punta).
      for (final fuente in [pagina, programa]) {
        for (final m in RegExp(r"\.rpc\(\s*'(\w+)'").allMatches(fuente)) {
          final resto = fuente.substring(m.end, m.end + 40);
          expect(resto, contains('params:'), reason: m.group(1));
        }
      }
    });

    test('los topes del programa son los de la nube', () {
      expect(kMaxAcompanantes, 2);
      expect(codigo, contains('jsonb_array_length(v_nombres) > $kMaxAcompanantes'));
      expect(codigo, contains('char_length(e) > $kMaxLetrasAcompananteDelegado'));
      expect(codigo, contains('char_length(v_musica) > $kMaxLetrasMusicaDelegado'));
      expect(codigo, contains('p_cupo < 1 or p_cupo > $kMaxDelegadosPorLink'));
    });

    test('los motivos que la página sabe decir existen en el SQL', () {
      final laPagina =
          _leer('lib/features/delegado/pagina/pagina_del_delegado.dart');
      for (final motivo in [
        'vacio', 'tope', 'largo', 'formato', 'alumno', 'ya_cargado', 'otro',
        'nombre', 'entrar', 'apagado', 'sacado',
      ]) {
        expect(codigo, contains("'motivo', '$motivo'"), reason: motivo);
        expect(laPagina, contains("'$motivo'"), reason: motivo);
      }
    });
  });

  group('nada sin usuario toca una tabla', () {
    for (final ruta in Directory('lib/features/delegado')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart'))) {
      test(ruta, () {
        final t = _leer(ruta);
        expect(t, isNot(contains('.from(')), reason: 'lee una tabla');
        expect(t, isNot(contains('.channel(')), reason: 'escucha un canal');
        expect(t, isNot(contains('Supabase.instance')),
            reason: 'tiene que leer supabaseProvider');
      });
    }

    test('la página no usa el reloj del celular: el límite lo dice la nube', () {
      for (final f in Directory('lib/features/delegado/pagina')
          .listSync()
          .whereType<File>()) {
        final t = _leer(f.path);
        expect(t, isNot(contains('DateTime.now()')), reason: f.path);
        expect(t, isNot(contains('DateTime(')), reason: f.path);
      }
    });

    test('las tres tablas están cerradas: con RLS, sin políticas y sin '
        'permisos para nadie', () {
      for (final t in ['links_delegado', 'celulares_delegado', 'cargas_delegado']) {
        expect(codigo, contains('alter table public.$t'), reason: t);
        expect(
          RegExp('alter table public\\.$t\\s+enable row level security')
              .hasMatch(codigo),
          isTrue,
          reason: t,
        );
        expect(
          RegExp('revoke all on table public\\.$t\\s+from anon, authenticated')
              .hasMatch(codigo),
          isTrue,
          reason: t,
        );
      }
      expect(codigo, isNot(contains('create policy')));
      expect(codigo.toLowerCase(), isNot(contains('grant select')));
      expect(codigo.toLowerCase(), isNot(contains('grant all')));
    });

    test('lo del jefe pide usuario, y un anónimo no lo puede ejecutar', () {
      for (final f in delJefe) {
        final desde = codigo.indexOf('function public.$f(');
        final hasta = codigo.indexOf(r'$$;', desde);
        expect(
          codigo.substring(desde, hasta),
          contains("auth.role() is distinct from 'authenticated'"),
          reason: f,
        );
        expect(
          RegExp('revoke all on function public\\.$f\\([^)]*\\)\\s+from public, anon;')
              .hasMatch(codigo),
          isTrue,
          reason: f,
        );
        expect(
          RegExp('grant execute on function public\\.$f\\([^)]*\\)\\s+to authenticated;')
              .hasMatch(codigo),
          isTrue,
          reason: f,
        );
      }
    });

    test('lo de adentro no lo ejecuta nadie de afuera', () {
      for (final f in funciones.keys.toSet().difference({...delDelegado, ...delJefe})) {
        expect(
          RegExp('revoke all on function public\\.$f\\([^)]*\\)\\s+from public, anon, authenticated;')
              .hasMatch(codigo),
          isTrue,
          reason: f,
        );
      }
    });

    test('las funciones van como security definer y con search_path', () {
      for (final f in {...delDelegado, ...delJefe}) {
        final desde = codigo.indexOf('function public.$f(');
        final cuerpo = codigo.substring(desde, codigo.indexOf(r'as $$', desde));
        expect(cuerpo, contains('security definer'), reason: f);
        expect(cuerpo, contains('set search_path = public'), reason: f);
      }
    });
  });

  group('el SQL solo agrega', () {
    test('no escribe en los alumnos ni en las fiestas, ni toca nada que ya '
        'exista', () {
      final minusculas = codigo.toLowerCase();
      for (final tabla in ['contratos_alumnos', 'eventos', 'invitados']) {
        expect(
          RegExp('(insert\\s+into|update|delete\\s+from|alter\\s+table|drop\\s+table)'
                  '\\s+(public\\.)?$tabla\\b')
              .hasMatch(minusculas),
          isFalse,
          reason: tabla,
        );
      }
      expect(minusculas, isNot(contains('drop ')));
      expect(minusculas, isNot(contains('truncate')));
      // Ni CHECK, ni Realtime, ni extensiones.
      expect(minusculas, isNot(contains(' check (')));
      expect(minusculas, isNot(contains('supabase_realtime')));
      expect(minusculas, isNot(contains('create extension')));
    });

    test('cada tabla y cada función lleva su ROLLBACK arriba, y el archivo '
        'termina con la verificación', () {
      for (final t in ['links_delegado', 'celulares_delegado', 'cargas_delegado']) {
        expect(sql, contains('drop table if exists public.$t;'), reason: t);
      }
      for (final f in funciones.keys) {
        expect(
          sql,
          contains('-- ROLLBACK: drop function if exists public.$f('),
          reason: f,
        );
      }
      expect(sql, contains('── 6. Verificación'));
      expect(sql, contains('ANTES y DESPUÉS'));
    });

    test('el link tiene su ruta en la web y ninguna otra la pisa', () {
      final main = _leer('lib/main.dart');
      expect(main, contains("currentUrl.contains('delegado')"));
      expect(main, contains('DelegadoApp(clave:'));
      // La clave es hexadecimal: no puede traer la palabra de otra ruta.
      expect(codigo, contains("replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')"));
    });
  });
}
