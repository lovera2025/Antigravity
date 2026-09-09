// Nada se borra de la base local, salvo que alguien lo haya borrado a mano.
//
// `_pullTable` terminaba cada bajada de `presupuesto_servicios` y de
// `eventos_servicios` comparando lo que había llegado contra todas las filas
// locales de la tabla, y borrando las que no estuvieran en esa lista. La idea
// original era buena: la migración v35 reasignó UUIDs y quedaron líneas
// duplicadas conviviendo, así que había que limpiar.
//
// El problema es que la comparación corría también en el pull incremental, donde
// lo que llega no es la tabla sino el delta de los últimos diez segundos. Alguien
// tocaba dos presupuestos en una PC, la otra bajaba esas 22 líneas, y el prune
// borraba las 203 restantes. Como el monto del presupuesto no existe como dato
// —es la suma de sus líneas— todos los demás presupuestos aparecían en $0, en la
// pantalla, sin un solo error en el log.
//
// La nube nunca se tocó: los DELETE a Supabase salen solo de la cola. Se rompía
// la copia local, y por eso el "pull completo forzado" la devolvía entera. Y por
// eso también la PC que más sincronizaba era la que más perdía.
//
// Es el segundo incidente con la misma firma: el encabezado de
// `marcador_pull_seguro_test.dart` ya cuenta cómo `presupuesto_servicios` quedó
// con 18 de 203 filas. Aquel arreglo era correcto y resolvió su parte; este
// prune producía el mismo síntoma por otro camino.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/sync_engine.dart';

void main() {
  group('filasAPodar', () {
    // Los números del incidente: 225 líneas en la nube, 22 tocadas, 203 que
    // simplemente no cambiaron.
    final todasLasLineas = {
      for (var i = 0; i < 225; i++) 'linea-$i',
    };
    final elDeltaDeLasQueSeTocaron = {
      for (var i = 0; i < 22; i++) 'linea-$i',
    };

    test('un pull incremental no borra nada, aunque el delta sea de una fila', () {
      final aPodar = filasAPodar(
        fotoCompleta: false,
        idsLocales: todasLasLineas,
        idsEnLaNube: {'linea-7'},
        idsPendientes: const {},
      );

      expect(
        aPodar,
        isEmpty,
        reason: 'lo que no vino en el delta no está de más: no cambió',
      );
    });

    test('el delta de los 2 presupuestos tocados no vacía los otros', () {
      final aPodar = filasAPodar(
        fotoCompleta: false,
        idsLocales: todasLasLineas,
        idsEnLaNube: elDeltaDeLasQueSeTocaron,
        idsPendientes: const {},
      );

      expect(
        aPodar,
        isEmpty,
        reason: 'así quedaban 203 presupuestos en \$0',
      );
    });

    test('con la foto completa sí borra, y solo lo que la nube no tiene', () {
      final enLaNube = Set<String>.from(todasLasLineas)..remove('linea-42');

      final aPodar = filasAPodar(
        fotoCompleta: true,
        idsLocales: todasLasLineas,
        idsEnLaNube: enLaNube,
        idsPendientes: const {},
      );

      expect(
        aPodar,
        {'linea-42'},
        reason: 'es el duplicado de la v35, que es para lo que existe el prune',
      );
    });

    test('lo que está en la cola no se borra ni con la foto completa', () {
      // Recién creado en esta PC: todavía no subió, así que la nube no lo tiene.
      // No es basura, es lo último que cargó alguien.
      final aPodar = filasAPodar(
        fotoCompleta: true,
        idsLocales: {...todasLasLineas, 'linea-nueva'},
        idsEnLaNube: todasLasLineas,
        idsPendientes: {'linea-nueva'},
      );

      expect(aPodar, isEmpty);
    });

    test('una foto completa sin diferencias no borra nada', () {
      final aPodar = filasAPodar(
        fotoCompleta: true,
        idsLocales: todasLasLineas,
        idsEnLaNube: todasLasLineas,
        idsPendientes: const {},
      );

      expect(aPodar, isEmpty);
    });

    test('una base local vacía no borra nada, venga lo que venga', () {
      final aPodar = filasAPodar(
        fotoCompleta: true,
        idsLocales: const {},
        idsEnLaNube: todasLasLineas,
        idsPendientes: const {},
      );

      expect(aPodar, isEmpty);
    });

    test('una nube vacía contra una base con filas no es una foto creíble', () {
      // El agujero que dejaba abierto contar y comparar: si la sesión vence o
      // RLS niega la tabla, PostgREST no tira error — devuelve cero filas, y el
      // `count` también da cero. Los dos números coinciden, el chequeo canta
      // "foto completa", y entonces sobra TODO lo local.
      //
      // Se descubrió corriendo la prueba de humo contra Supabase con la clave
      // anónima sin sesión: leyó 0 filas de tres tablas que tienen cientos.
      expect(
        fotoDeLaNubeEsCreible(enLaNube: 0, local: 225),
        isFalse,
        reason: 'eso es sesión o permisos, no que alguien borró 225 renglones',
      );

      // Y lo que sí es legítimo sigue pasando.
      expect(fotoDeLaNubeEsCreible(enLaNube: 0, local: 0), isTrue);
      expect(fotoDeLaNubeEsCreible(enLaNube: 225, local: 225), isTrue);
      expect(
        fotoDeLaNubeEsCreible(enLaNube: 224, local: 225),
        isTrue,
        reason: 'un borrado de verdad tiene que poder cruzar',
      );
    });

    test('una foto que llegó truncada no autoriza a borrar', () {
      // El caso que blinda la reconciliación de borrados: quien trae la lista de
      // ids de la nube tiene que verificar que trajo todo. PostgREST corta en
      // 1000 filas por defecto, y `contratos_alumnos` ya va en 643. Si la página
      // vuelve cortada y alguien la pasa como foto completa, esto borra en masa.
      final llegoLaPrimeraPagina = {
        for (var i = 0; i < 100; i++) 'linea-$i',
      };

      final aPodar = filasAPodar(
        fotoCompleta: false, // el llamador contó y no le cerró
        idsLocales: todasLasLineas,
        idsEnLaNube: llegoLaPrimeraPagina,
        idsPendientes: const {},
      );

      expect(
        aPodar,
        isEmpty,
        reason: 'sin foto completa y verificada, no se poda',
      );
    });
  });
}
