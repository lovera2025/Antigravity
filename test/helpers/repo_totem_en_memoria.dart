// El repositorio de Personalizar tótem en memoria, **sin `flutter_test`**: lo
// usan los tests (por `personalizar_en_memoria.dart`) y las ventanas de prueba
// (`tool/central_puerta_prueba.dart`, `tool/totem_salon_prueba.dart`), que en
// Windows no pueden traer `flutter_test`. Así Personalizar no va a la nube ni a
// las preferencias del programa instalado.
import 'dart:typed_data';

import 'package:arguello_events/features/totem/repositories/totem_config_repository.dart';
import 'package:arguello_events/models/totem_config.dart';

/// Anota lo que se guarda, en vez de subirlo a la nube.
class RepoTotemEnMemoria implements TotemConfigRepository {
  final guardadas = <TotemConfig>[];

  /// Si guardar falla, como sin internet.
  bool fallar = false;

  /// Si lo de la nube ya no es lo que Personalizar abrió (lo cambió otra PC, o
  /// se abrió antes de terminar de leer).
  bool cambioEnLaNube = false;

  /// Cuántas veces se preguntó antes de guardar.
  var preguntas = 0;

  @override
  Future<bool> sigueComoSeAbrio(TotemConfig abierta) async {
    preguntas++;
    if (fallar) {
      throw Exception('SocketException: Failed host lookup: supabase.co');
    }
    return !cambioEnLaNube;
  }

  /// Las fotos que se borraron.
  var fotosBorradas = 0;

  @override
  Future<void> borrarImagen(String eventoId) async => fotosBorradas++;

  @override
  Future<TotemConfig> guardar(TotemConfig cfg) async {
    if (fallar) {
      throw Exception('SocketException: Failed host lookup: supabase.co');
    }
    guardadas.add(cfg);
    return cfg;
  }

  /// Los fondos que se subieron, y cuántas veces se borró.
  final fondosSubidos = <Uint8List>[];
  var fondosBorrados = 0;

  @override
  Future<String> subirFondo({
    required String eventoId,
    required Uint8List bytes,
    required String extension,
  }) async {
    fondosSubidos.add(bytes);
    return 'https://nube.test/totem/$eventoId/fondo.$extension'
        '?v=${fondosSubidos.length}';
  }

  @override
  Future<void> borrarFondo(String eventoId) async => fondosBorrados++;

  /// Los segundos de la llegada que se subieron a mano.
  final tiemposSubidos = <(int, int)>[];

  @override
  Future<void> guardarTiempos(
    String eventoId, {
    required int nombre,
    required int camino,
  }) async {
    if (fallar) {
      throw Exception('SocketException: Failed host lookup: supabase.co');
    }
    tiemposSubidos.add((nombre, camino));
  }

  /// Lo que estas pruebas no usan (leer de la nube, la foto): no se llama.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'RepoTotemEnMemoria: ${invocation.memberName} no está en memoria',
      );
}
