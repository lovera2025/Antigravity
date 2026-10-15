// Personalizar tótem sin nube: la config guardada y lo que se guarda, en
// memoria. Lo usan `test/personalizar_totem_test.dart` y
// `tool/totem_muestra_test.dart`, puestos por los mismos providers que usa la
// app.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/features/totem/providers/clave_totem_provider.dart';
import 'package:arguello_events/features/totem/providers/totem_config_provider.dart';
import 'package:arguello_events/features/totem/services/clave_totem.dart';
import 'package:arguello_events/features/totem/repositories/totem_config_repository.dart';
import 'package:arguello_events/features/totem/widgets/totem_config_sheet.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'puerta_en_memoria.dart';

/// Anota lo que se guarda, en vez de subirlo a la nube.
class RepoTotemEnMemoria extends Fake implements TotemConfigRepository {
  final guardadas = <TotemConfig>[];

  /// Si guardar falla, como sin internet.
  bool fallar = false;

  @override
  Future<TotemConfig> guardar(TotemConfig cfg) async {
    if (fallar) {
      throw Exception('SocketException: Failed host lookup: supabase.co');
    }
    guardadas.add(cfg);
    return cfg;
  }
}

/// Una foto de 1 × 1, transparente: la que "elige" el selector en los tests.
final fotoDePrueba = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// El selector de archivos, que devuelve [fotoDePrueba] como `foto.png`.
Future<FilePickerResult?> elegirFotoDePrueba() async => FilePickerResult([
      PlatformFile(
        name: 'foto.png',
        size: fotoDePrueba.length,
        bytes: fotoDePrueba,
      ),
    ]);

/// La clave del tótem que "da la nube" en los tests.
const claveDePrueba = '0123456789abcdef0123456789abcdef';

/// El texto del botón que abre Personalizar en [anfitrionPersonalizar].
const abrirPersonalizar = 'Abrir Personalizar';

/// Una pantalla con un botón que abre Personalizar del evento, como la paleta
/// de Recepción. Como Recepción, ya está mirando la config del evento cuando
/// se abre.
Widget anfitrionPersonalizar({
  required String eventoId,
  required TotemConfig guardada,
  required RepoTotemEnMemoria repo,
  ThemeData? tema,
}) =>
    ProviderScope(
      overrides: [
        eventosActivosProvider.overrideWith(
          (ref) async => [
            eventoDePrueba(eventoMasivo, 'masivo'),
            eventoDePrueba(eventoParticular, 'particular'),
          ],
        ),
        totemConfigProvider(eventoId)
            .overrideWith((ref) => Stream.value(guardada)),
        totemConfigRepositoryProvider.overrideWithValue(repo),
        // El link del tótem por el navegador, sin pedirle la clave a la nube.
        claveTotemProvider.overrideWithValue(
          ClaveTotem(pedirALaNube: (_) async => claveDePrueba),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // Outfit, como la app (`main.dart`): con la letra de prueba cada letra
        // mide lo que su tamaño, y un texto parece el doble de ancho.
        theme: tema ??
            ThemeData(
              brightness: Brightness.dark,
              fontFamily: FuentesTotem.linea,
              useMaterial3: true,
            ),
        home: Scaffold(
          backgroundColor: const Color(0xFF0E0E10),
          body: _Anfitrion(eventoId: eventoId),
        ),
      ),
    );

class _Anfitrion extends ConsumerWidget {
  final String eventoId;

  const _Anfitrion({required this.eventoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(totemConfigValueProvider(eventoId));
    ref.watch(eventosActivosProvider);
    return Center(
      child: FilledButton(
        onPressed: () =>
            showTotemConfigSheet(context: context, eventoId: eventoId),
        child: const Text(abrirPersonalizar),
      ),
    );
  }
}
