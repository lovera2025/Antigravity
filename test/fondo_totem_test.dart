// Los fondos animados de las cuatro apariencias del tótem (`fondo_totem.dart`):
// que cada shader compile y dibuje, y que si no carga quede el degradé.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';

/// El color promedio de lo que dibujó [clave]: si el shader no dibujó nada,
/// queda negro.
Future<double> _brillo(WidgetTester tester, GlobalKey clave) async {
  late double brillo;
  await tester.runAsync(() async {
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await boundary.toImage();
    final datos = (await imagen.toByteData())!;
    var suma = 0;
    for (var i = 0; i < datos.lengthInBytes; i += 4) {
      suma += datos.getUint8(i) + datos.getUint8(i + 1) + datos.getUint8(i + 2);
    }
    brillo = suma / (datos.lengthInBytes / 4) / 3;
  });
  return brillo;
}

Future<GlobalKey> _montar(WidgetTester tester, EstiloTotem estilo) async {
  final clave = GlobalKey();
  tester.view.physicalSize = const Size(270, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: clave,
      child: FondoTotem(
        estilo: estilo,
        color: const Color(0xFFD4AF37),
        tiempoFijo: 3,
      ),
    ),
  );
  await tester.pump();
  return clave;
}

void main() {
  tearDown(FondoTotem.olvidar);

  for (final estilo in EstiloTotem.values) {
    testWidgets('${estilo.nombre}: el shader compila y dibuja', (tester) async {
      await tester.runAsync(FondoTotem.precargar);
      expect(FondoTotem.tieneShader(estilo), isTrue,
          reason: 'el shader de ${estilo.nombre} no cargó');
      final clave = await _montar(tester, estilo);
      expect(await _brillo(tester, clave), greaterThan(3));
    });
  }

  testWidgets('si el shader no carga, queda el degradé del color', (tester) async {
    FondoTotem.cargar = (_) async => throw StateError('esta PC no puede');
    await tester.runAsync(FondoTotem.precargar);
    expect(FondoTotem.tieneShader(EstiloTotem.neon), isFalse);
    final clave = await _montar(tester, EstiloTotem.neon);
    expect(tester.takeException(), isNull);
    expect(await _brillo(tester, clave), greaterThan(3));
  });

  test('cada apariencia tiene su archivo de shader', () {
    expect(
      EstiloTotem.values.map((e) => e.shader),
      [
        'shaders/totem_neon.frag',
        'shaders/totem_cristal.frag',
        'shaders/totem_poster.frag',
        'shaders/totem_gala.frag',
      ],
    );
  });
}
