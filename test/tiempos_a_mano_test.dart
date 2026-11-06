// Los segundos de la llegada cambiados a mano la noche de la fiesta
// (`tiempos_a_mano.dart` y su provider): se aplican en el momento, quedan en la
// PC sin internet, se suben cuando se puede y Personalizar los olvida al guardar.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart'
    show AlumnosDeLaPuerta;
import 'package:arguello_events/features/totem/providers/tiempos_a_mano_provider.dart';
import 'package:arguello_events/features/totem/providers/totem_config_provider.dart';
import 'package:arguello_events/features/totem/repositories/totem_config_repository.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/services/puente_ficha.dart';
import 'package:arguello_events/features/totem/services/tiempos_a_mano.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/personalizar_en_memoria.dart';
import 'helpers/puerta_en_memoria.dart';

ProviderContainer _contenedor(
  RepoTotemEnMemoria repo, {
  TotemConfig cfg = const TotemConfig(eventoId: eventoMasivo),
}) {
  final c = ProviderContainer(
    overrides: [
      totemConfigRepositoryProvider.overrideWithValue(repo),
      totemConfigProvider(eventoMasivo).overrideWith((ref) => Stream.value(cfg)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Deja correr lo que quedó pendiente (el disco, la subida).
Future<void> _esperar() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('los segundos', () {
    test('se acotan a los topes y van y vuelven', () {
      final t = TiemposAMano(nombre: 99, camino: 1);
      expect(t.nombre, TotemConfig.llegadaNombreMaximo);
      expect(t.camino, TotemConfig.llegadaCaminoMinimo);
      expect(TiemposAMano.fromJson(t.toJson()), t);
      expect(TiemposAMano.fromJson('basura'), isNull);
      expect(TiemposAMano.fromJson(const {'n': 'x', 'c': 3}), isNull);
    });

    test('se ponen encima de la config, sin tocar lo demás', () {
      const cfg = TotemConfig(eventoId: eventoMasivo, titulo: 'PROMO');
      final con = TiemposAMano(nombre: 6, camino: 15).aplicarA(cfg);
      expect(con.llegadaNombreSeg, 6);
      expect(con.llegadaCaminoSeg, 15);
      expect(con.titulo, 'PROMO');
      expect(TiemposAMano.de(cfg), TiemposAMano(nombre: 4, camino: 8));
    });
  });

  group('esa noche', () {
    test('ponerlos cambia la config del tótem en el momento y los sube', () async {
      final repo = RepoTotemEnMemoria();
      final c = _contenedor(repo);
      c.listen(totemConfigDeLaNocheProvider(eventoMasivo), (_, _) {});
      await _esperar();
      expect(c.read(totemConfigDeLaNocheProvider(eventoMasivo)).llegadaNombreSeg, 4);

      await c
          .read(tiemposAManoProvider(eventoMasivo).notifier)
          .poner(TiemposAMano(nombre: 6, camino: 10));
      await _esperar();
      final cfg = c.read(totemConfigDeLaNocheProvider(eventoMasivo));
      expect(cfg.llegadaNombreSeg, 6);
      expect(cfg.llegadaCaminoSeg, 10);
      expect(repo.tiemposSubidos, [(6, 10)]);
      final guardado = jsonDecode(
        (await SharedPreferences.getInstance())
            .getString(TiemposDeLaNoche.clave(eventoMasivo))!,
      );
      expect(guardado['subido'], isTrue);
    });

    test('sin internet quedan en la PC; al abrir de nuevo están y se suben',
        () async {
      final sinRed = RepoTotemEnMemoria()..fallar = true;
      final c = _contenedor(sinRed);
      await c
          .read(tiemposAManoProvider(eventoMasivo).notifier)
          .poner(TiemposAMano(nombre: 3, camino: 20));
      await _esperar();
      expect(c.read(tiemposAManoProvider(eventoMasivo)),
          TiemposAMano(nombre: 3, camino: 20));
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(TiemposDeLaNoche.clave(eventoMasivo))!)['subido'],
        isFalse,
      );

      // Se reinicia la notebook, ahora con internet.
      final conRed = RepoTotemEnMemoria();
      final otra = _contenedor(conRed);
      expect(otra.read(tiemposAManoProvider(eventoMasivo)), isNull);
      await _esperar();
      expect(otra.read(tiemposAManoProvider(eventoMasivo)),
          TiemposAMano(nombre: 3, camino: 20));
      expect(conRed.tiemposSubidos, [(3, 20)]);
    });

    test('olvidarlos vuelve a lo de Personalizar', () async {
      final c = _contenedor(
        RepoTotemEnMemoria(),
        cfg: const TotemConfig(eventoId: eventoMasivo, llegadaNombreSeg: 5),
      );
      c.listen(totemConfigDeLaNocheProvider(eventoMasivo), (_, _) {});
      final n = c.read(tiemposAManoProvider(eventoMasivo).notifier);
      await n.poner(TiemposAMano(nombre: 9, camino: 9));
      await _esperar();
      expect(c.read(totemConfigDeLaNocheProvider(eventoMasivo)).llegadaNombreSeg, 9);
      await n.olvidar();
      await _esperar();
      expect(c.read(totemConfigDeLaNocheProvider(eventoMasivo)).llegadaNombreSeg, 5);
      expect(
        (await SharedPreferences.getInstance())
            .getString(TiemposDeLaNoche.clave(eventoMasivo)),
        isNull,
      );
    });

    test('lo que se toca antes de terminar de leer el disco manda', () async {
      SharedPreferences.setMockInitialValues({
        TiemposDeLaNoche.clave(eventoMasivo):
            jsonEncode({'n': 2, 'c': 3, 'subido': true}),
      });
      final c = _contenedor(RepoTotemEnMemoria());
      await c
          .read(tiemposAManoProvider(eventoMasivo).notifier)
          .poner(TiemposAMano(nombre: 7, camino: 7));
      await _esperar();
      expect(c.read(tiemposAManoProvider(eventoMasivo)),
          TiemposAMano(nombre: 7, camino: 7));
    });
  });

  group('la ventana del tótem', () {
    test('la ficha los lleva y van y vuelven por el puente', () async {
      final ficha = await armarFichaTotem(
        eventoMasivo,
        leerEvento: (_) async => eventoDePrueba(eventoMasivo, 'masivo'),
        leerAlumnos: (_) async => AlumnosDeLaPuerta(alumnosDeLaFicha(), const {}),
        leerPlano: (_) async => ArmadosPredefinidos.normal2aPagina3(),
        leerTiempos: (_) => TiemposAMano(nombre: 5, camino: 12),
      );
      final vuelta = FichaTotem.decodificar(ficha.codificar())!;
      expect(vuelta.tiempos, TiemposAMano(nombre: 5, camino: 12));
      // La ficha de cada minuto con el mismo salón conserva los segundos.
      expect(vuelta.conPlanoDe(vuelta).tiempos, vuelta.tiempos);
      // Sin segundos a mano, no van.
      expect(FichaTotem.decodificar(ficha.conTiempos(null).codificar())!.tiempos,
          isNull);
    });
  });
}
