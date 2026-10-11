// Arnés manual: dibuja la hoja de la nota de un alumno y guarda PNG para
// mirarla sin levantar la app ni tocar la base.
//
//   flutter test tool/nota_operativa_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen, como se ven en una notebook (1366 × 768):
//   Nota_pendiente.png — una nota pendiente, escrita un día y tocada otro;
//   Nota_resuelta.png — una nota ya marcada como hecha;
//   Nota_nueva.png — la hoja vacía, para escribir una;
//   Nota_pendiente_ventana.png — la misma nota, como ventana al centro.
//
// La hoja es la de la app; el alumno y los textos son inventados.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/eventos/widgets/nota_operativa_bottom_sheet.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/nota_operativa_contrato.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

final _alumno = ContratoAlumno(
  id: 'c0000000-0000-4000-8000-000000000001',
  eventoId: 'e',
  nombreAlumno: 'ACOSTA, VALENTINA',
  cantidadAcompanantes: 0,
  montoTotalPactado: 300000,
  saldoDeudor: 0,
);

NotaOperativaContrato _nota(
  String texto, {
  required DateTime escrita,
  DateTime? tocada,
  bool resuelta = false,
}) =>
    NotaOperativaContrato(
      id: 'n',
      contratoAlumnoId: _alumno.id,
      texto: texto,
      resuelto: resuelta,
      createdAt: escrita,
      updatedAt: tocada ?? escrita,
    );

/// Carga las letras que la app instalada ya bajó en esta PC.
///
/// Oswald y los pesos gruesos de Outfit no vienen con la app: `google_fonts`
/// los baja la primera vez y los guarda con el nombre que después pide
/// (`Oswald_700_` y una huella, `.ttf`). Los tests no tienen internet, así que sin esto
/// los títulos de la hoja salen como bloques.
Future<int> _cargarLetrasBajadas() async {
  final sep = Platform.pathSeparator;
  final carpeta = Directory(
    '${Platform.environment['APPDATA']}${sep}Junior Eventos${sep}Junior Eventos',
  );
  if (!carpeta.existsSync()) return 0;
  final nombre = RegExp(r'^([A-Za-z]+_[a-z0-9]+)_[0-9a-f]{64}\.ttf$');
  var cargadas = 0;
  for (final f in carpeta.listSync().whereType<File>()) {
    final m = nombre.firstMatch(f.uri.pathSegments.last);
    if (m == null) continue;
    final bytes = f.readAsBytesSync();
    final loader = FontLoader(m.group(1)!)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    cargadas++;
  }
  return cargadas;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin esto `google_fonts` intenta bajar las letras y la prueba se cuelga.
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() async {
    final n = await _cargarLetrasBajadas();
    print(n == 0
        ? '── Sin las letras bajadas por la app: los títulos salen como bloques.'
        : '── Letras de la app instalada: $n');
  });

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('nota_operativa').path;

  Future<void> sacar(
    WidgetTester tester, {
    required String archivo,
    NotaOperativaContrato? nota,
    bool comoVentana = false,
  }) async {
    await cargarFuentesPlano();
    // Los íconos de Material, que en los tests no vienen cargados.
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();

    const tam = Size(1366, 768);
    final clave = GlobalKey();
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                backgroundColor: const Color(0xFFF4F2EE),
                body: TextButton(
                  onPressed: () => showNotaOperativaSheet(
                    context: context,
                    ref: ref,
                    alumno: _alumno,
                    existente: nota,
                    onChanged: () {},
                    comoVentana: comoVentana,
                  ),
                  child: const Text(' '),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // `google_fonts` avisa, tarde y por fuera de la prueba, por cada letra que
    // no encuentra entre los archivos de la app. Acá ya están cargadas a mano:
    // la hoja se abre en una zona propia, que se queda con esos avisos.
    await runZonedGuarded(
      () async {
        await tester.tap(find.byType(TextButton).first);
        await tester.pumpAndSettle();
      },
      (error, stack) {},
    );

    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$archivo')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  }

  testWidgets('una nota pendiente, escrita un día y tocada otro',
      (tester) async {
    await sacar(
      tester,
      archivo: 'Nota_pendiente.png',
      nota: _nota(
        'Le quedaron \$300 a favor: no había cambio. Descontarlos de la '
        'próxima cuota.',
        // 13/05/2026 20:16 y 10/06/2026 09:35, hora de Argentina.
        escrita: DateTime.utc(2026, 5, 13, 23, 16),
        tocada: DateTime.utc(2026, 6, 10, 12, 35),
      ),
    );
  });

  testWidgets('una nota ya resuelta', (tester) async {
    await sacar(
      tester,
      archivo: 'Nota_resuelta.png',
      nota: _nota(
        'Pasa el viernes a pagar las dos cuotas juntas.',
        escrita: DateTime.utc(2026, 9, 2, 22, 0),
        tocada: DateTime.utc(2026, 9, 5, 14, 10),
        resuelta: true,
      ),
    );
  });

  testWidgets('la hoja vacía, para escribir una', (tester) async {
    await sacar(tester, archivo: 'Nota_nueva.png');
  });

  testWidgets('la misma nota pendiente, como ventana al centro',
      (tester) async {
    await sacar(
      tester,
      archivo: 'Nota_pendiente_ventana.png',
      comoVentana: true,
      nota: _nota(
        'Le quedaron \$300 a favor: no había cambio. Descontarlos de la '
        'próxima cuota.',
        escrita: DateTime.utc(2026, 5, 13, 23, 16),
        tocada: DateTime.utc(2026, 6, 10, 12, 35),
      ),
    );
  });
}
