// Prueba de humo del blindaje que habilita el borrado, contra Supabase real.
//
//   flutter test tool/probar_reconciliacion_test.dart
//
// Es **solo lectura**: no borra ni escribe nada. Vive en `tool/` porque usa la
// red y no puede correr en la suite normal.
//
// Verifica lo que ningún test unitario puede: la forma real de la respuesta del
// servidor, que es de donde salieron los dos sustos de esta versión.
//
// ## El susto grande
//
// La reconciliación borra local lo que no está en la nube. Para que eso sea
// seguro hay que estar seguro de haber leído TODA la nube, y el primer blindaje
// fue contar: traer los ids paginando y contrastarlos contra `count`.
//
// No alcanza. **Sin sesión, PostgREST no tira error: devuelve cero filas, y el
// `count` también da cero.** Los dos números coinciden, el chequeo canta "foto
// completa", y comparar eso contra la base local dice que sobra todo. La
// protección de contar convertía un problema de permisos en un borrado total.
//
// Esa es la misma trampa que vació los presupuestos —creer que "no vino"
// significa "no existe"— una capa más adentro, y por eso este archivo la fija
// contra el servidor de verdad y no contra una maqueta.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/sync_engine.dart';

const _url = 'https://bucnrydgojyzntgesxqb.supabase.co';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA';

/// El mismo paginado que usa `_idsCompletosDeLaNube`.
Future<Set<String>> idsPaginados(SupabaseClient c, String tabla) async {
  const tamanio = 1000;
  final ids = <String>{};
  var desde = 0;
  while (true) {
    final pagina =
        await c.from(tabla).select('id').range(desde, desde + tamanio - 1);
    final filas = (pagina as List).cast<Map<String, dynamic>>();
    for (final f in filas) {
      final id = (f['id'] as String?)?.trim() ?? '';
      if (id.isNotEmpty) ids.add(id);
    }
    if (filas.length < tamanio) break;
    desde += tamanio;
  }
  return ids;
}

void main() {
  late SupabaseClient cliente;

  setUpAll(() => cliente = SupabaseClient(_url, _anonKey));
  tearDownAll(() async => cliente.dispose());

  test('count devuelve un entero comparable', () async {
    // Si devolviera un objeto en vez de un int, `ids.length != conteo` daría
    // siempre true, la reconciliación se declararía "sin foto completa" para
    // siempre y no borraría nunca nada. Falla hacia el lado seguro, así que
    // nadie se enteraría de que la función quedó muerta.
    final conteo = await cliente.from('servicios').count(CountOption.exact);

    expect(conteo, isA<int>());
    expect(conteo, greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('paginar y contar coinciden sobre una tabla legible', () async {
    // `servicios` es de las seis que se reconcilian y la única que se puede leer
    // sin sesión (es el catálogo público de `?cotizar`).
    final ids = await idsPaginados(cliente, 'servicios');
    final conteo = await cliente.from('servicios').count(CountOption.exact);

    expect(ids.length, conteo);
    expect(
      fotoDeLaNubeEsCreible(enLaNube: ids.length, local: ids.length),
      isTrue,
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('sin sesión la nube se ve VACÍA, y el blindaje lo rechaza', () async {
    // Éste es el test que importa. `eventos` tiene 25 filas y
    // `contratos_alumnos` 643; sin sesión las dos se leen como cero, sin un solo
    // error. Es exactamente lo que pasaría en la app si la sesión venciera.
    for (final tabla in ['eventos', 'contratos_alumnos', 'prestamos_alquiler']) {
      final ids = await idsPaginados(cliente, tabla);
      final conteo = await cliente.from(tabla).count(CountOption.exact);

      expect(
        ids.length,
        conteo,
        reason: '$tabla: los dos dan cero, y por eso contar no alcanza',
      );

      // Y acá es donde se frena. Con filas locales, una nube vacía no es un
      // borrado: es una lectura que no funcionó.
      expect(
        fotoDeLaNubeEsCreible(enLaNube: ids.length, local: 200),
        isFalse,
        reason: '$tabla: sin esto, la reconciliación vaciaría la base local',
      );

      expect(
        filasAPodar(
          fotoCompleta: fotoDeLaNubeEsCreible(enLaNube: ids.length, local: 200),
          idsLocales: {for (var i = 0; i < 200; i++) 'fila-$i'},
          idsEnLaNube: ids,
          idsPendientes: const {},
        ),
        isEmpty,
        reason: '$tabla: y por lo tanto no se borra una sola fila',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
