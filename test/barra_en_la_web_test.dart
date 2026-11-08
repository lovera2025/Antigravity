import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BARRA del jefe en la web del iPhone (etapa 8) lee y escribe **directo en la nube**:
/// en la web no hay base ni cola de subida. Esto lee los archivos y falla si vuelve lo
/// que la rompería:
/// - `barraDelJefeProvider` tiene que elegir `BarraNube` con la llave de la web, y
///   **con `supabaseProvider`, nunca `Supabase.instance`** (la ventana del tótem inyecta
///   el suyo);
/// - las fiestas de la web salen de `BarraNube.eventos()`, no de la base;
/// - en la web nada "sube" por la cola;
/// - las pantallas del jefe preguntan por `enLaWebProvider`, no por `kIsWeb`: los tests
///   no pueden cambiar `kIsWeb`, y lo que no se puede probar no se prueba.
void main() {
  String leer(String ruta) => File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  test('la barra del jefe elige la nube con la llave de la web, por supabaseProvider', () {
    final fuente = leer('lib/features/barra/providers/barra_del_jefe_provider.dart');
    expect(fuente, contains('final enLaWebProvider'));
    final provider = fuente.substring(fuente.indexOf('final barraDelJefeProvider'));
    expect(provider, contains('enLaWebProvider'));
    expect(provider, contains('BarraNube('));
    expect(provider, contains('supabaseProvider'));
    expect(fuente, isNot(contains('Supabase.instance')));
  });

  test('las fiestas de la web vienen de la nube, y nada sube por la cola', () {
    final fuente = leer('lib/features/barra/providers/barra_providers.dart');
    final eventos = fuente.substring(
      fuente.indexOf('final eventosDeLaBarraProvider'),
      fuente.indexOf('final fiestasDeLaBarraProvider'),
    );
    expect(eventos, contains('BarraNube'), reason: 'en la web no hay base de dónde leer las fiestas');
    final subir = fuente.substring(fuente.indexOf('final subirDeLaBarraProvider'));
    expect(subir.substring(0, subir.indexOf('return (tabla, registroId) async {\n    if')),
        contains('enLaWebProvider'),
        reason: 'en la web, subir no hace nada: BarraNube ya escribió');
  });

  test('BarraNube no usa Supabase.instance', () {
    expect(leer('lib/features/barra/datos/barra_nube.dart'), isNot(contains('Supabase.instance')));
  });

  test('las pantallas del jefe preguntan por enLaWebProvider, nunca por kIsWeb', () {
    final archivos = Directory('lib/features/barra/jefe')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in archivos) {
      expect(leer(f.path), isNot(contains('kIsWeb')), reason: f.path);
    }
  });
}
