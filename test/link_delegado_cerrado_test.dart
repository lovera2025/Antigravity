// El link del delegado, cerrado (6.8.0). Quien abre el link no tiene usuario:
// **no lee ni escribe ninguna tabla**, va por las funciones de
// `supabase/migrations/20261113120000_link_delegado.sql` y, desde la 6.9.2,
// `20261118120000_link_delegado_reabrir.sql` (todos corrigen todo, Enviar no
// cierra, el historial). Las reglas de esas funciones se prueban contra los
// mismos archivos, en un Postgres de prueba
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
  final sql1 = _leer('supabase/migrations/20261113120000_link_delegado.sql');
  final sql2 =
      _leer('supabase/migrations/20261118120000_link_delegado_reabrir.sql');
  // Los dos archivos, en el orden en que se corren.
  final sql = '$sql1\n$sql2';
  final codigo = _sinComentarios(sql);
  final codigo2 = _sinComentarios(sql2);
  final pagina = _leer('lib/features/delegado/datos/nube_del_delegado.dart');
  final programa = _leer('lib/features/delegado/datos/link_del_delegado.dart');
  final funciones = _funciones(sql);

  /// El cuerpo de cada definición de [f] (si la segunda parte la reescribe, las
  /// dos): desde su `function` hasta el final.
  List<String> definiciones(String f) => [
        for (final m
            in 'create or replace function public.$f('.allMatches(codigo))
          codigo.substring(m.start, codigo.indexOf(r'$$;', m.start)),
      ];

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
    // 6.9.2: la lista ALUMNOS de la ventana y el historial.
    'delegado_alumnos_estado',
    'delegado_historial',
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
      // Con las reglas de hoy: los de la segunda parte.
      for (final motivo in [
        'vacio', 'tope', 'largo', 'formato', 'alumno',
        'nombre', 'entrar', 'apagado', 'sacado', 'nada',
      ]) {
        expect(codigo2, contains("'motivo', '$motivo'"), reason: motivo);
        expect(laPagina, contains("'$motivo'"), reason: motivo);
      }
    });

    test('todos corrigen todo: guardar ya no frena por quien envió, por lo de '
        'otro ni por lo que está en el programa', () {
      final guardar = definiciones('delegado_guardar').last;
      for (final traba in ['entregado', 'otro', 'ya_cargado']) {
        expect(guardar, isNot(contains("'motivo', '$traba'")), reason: traba);
      }
      // Las que quedan: la fecha, el link cerrado y quien fue sacado.
      for (final traba in ['vencido', 'apagado', 'sacado']) {
        expect(guardar, contains("'motivo', '$traba'"), reason: traba);
      }
      // Y la página tampoco las espera.
      final laPagina =
          _leer('lib/features/delegado/pagina/pagina_del_delegado.dart');
      expect(laPagina, isNot(contains("'ya_cargado'")));
      expect(laPagina, isNot(contains("'otro'")));
    });

    test('la segunda parte no cambia la firma ni lo que devuelve ninguna '
        'función que ya existía', () {
      // Las PCs con la versión anterior las siguen llamando igual.
      final firma = RegExp(
        r'create or replace function public\.(\w+)\(([^)]*)\)\s*returns\s+(table\s*\([^)]*\)|\w+)',
      );
      Map<String, String> firmas(String texto) => {
            for (final m in firma.allMatches(texto))
              m.group(1)!: '${m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim()} '
                  '-> ${m.group(3)!.replaceAll(RegExp(r'\s+'), ' ')}',
          };
      final antes = firmas(sql1);
      final ahora = firmas(sql2);
      final repetidas = ahora.keys.toSet().intersection(antes.keys.toSet());
      expect(repetidas, isNotEmpty);
      for (final f in repetidas) {
        expect(ahora[f], antes[f], reason: f);
      }
      // Y no le da nada nuevo a quien no tiene usuario.
      expect(codigo2, isNot(contains('to anon')));
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

    test('las cuatro tablas están cerradas: con RLS, sin políticas y sin '
        'permisos para nadie', () {
      for (final t in [
        'links_delegado',
        'celulares_delegado',
        'cargas_delegado',
        'cambios_delegado',
      ]) {
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
        expect(definiciones(f), isNotEmpty, reason: f);
        for (final cuerpo in definiciones(f)) {
          expect(
            cuerpo,
            contains("auth.role() is distinct from 'authenticated'"),
            reason: f,
          );
        }
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
        for (final entera in definiciones(f)) {
          final cuerpo = entera.substring(0, entera.indexOf(r'as $$'));
          expect(cuerpo, contains('security definer'), reason: f);
          expect(cuerpo, contains('set search_path = public'), reason: f);
        }
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
      for (final t in [
        'links_delegado',
        'celulares_delegado',
        'cargas_delegado',
        'cambios_delegado',
      ]) {
        expect(sql, contains('drop table if exists public.$t;'), reason: t);
      }
      for (final f in funciones.keys) {
        expect(
          sql,
          contains('-- ROLLBACK: drop function if exists public.$f('),
          reason: f,
        );
      }
      for (final archivo in [sql1, sql2]) {
        expect(archivo, contains('── 6. Verificación'));
        expect(archivo, contains('ANTES y DESPUÉS'));
      }
      // En la segunda parte, cada función que se reescribe dice a qué vuelve, y
      // la columna nueva tiene su vuelta atrás.
      expect(
        'ROLLBACK: (vuelve la del archivo 20261113120000_link_delegado.sql)'
            .allMatches(sql2)
            .length,
        _funciones(sql2).keys.toSet().intersection(_funciones(sql1).keys.toSet()).length,
      );
      expect(
        sql2,
        contains('-- ROLLBACK: alter table public.cargas_delegado drop column if exists enviado_at;'),
      );
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
