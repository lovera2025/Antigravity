// Las manijas y el arrastre de Personalizar (6.2.1), solos: agarrar una
// esquina agranda, agarrar el resto mueve.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/widgets/foto_en_personalizar.dart';

void main() {
  Future<({List<int> tamanos, List<(int, int)> lugares})> montar(
    WidgetTester tester,
  ) async {
    final tamanos = <int>[];
    final lugares = <(int, int)>[];
    var tamano = 100;
    var x = 0, y = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 400,
                height: 700,
                child: Align(
                  alignment: Alignment(x / 100, y / 100),
                  child: ArrastrarParaUbicar(
                    pantalla: const Size(400, 700),
                    x: x,
                    y: y,
                    onUbicacion: (nx, ny) => setState(() {
                      x = nx;
                      y = ny;
                      lugares.add((nx, ny));
                    }),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 60, height: 60),
                        ManijasParaAgrandar(
                          clave: 'texto',
                          tamano: tamano,
                          minimo: 50,
                          maximo: 200,
                          onTamano: (v) => setState(() {
                            tamano = v;
                            tamanos.add(v);
                          }),
                          child: SizedBox(
                            width: 1.5 * tamano,
                            height: 0.8 * tamano,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return (tamanos: tamanos, lugares: lugares);
  }

  testWidgets('agarrar una esquina agranda y no mueve', (tester) async {
    final r = await montar(tester);
    final manija = find.byKey(const ValueKey('manija_texto_1.0_1.0'));
    final gesto = await tester.startGesture(tester.getCenter(manija));
    // Con dos que compiten, el primer tramo (más que el margen de un dedo)
    // solo decide quién se lo queda; agranda lo que sigue.
    await gesto.moveBy(const Offset(30, 30));
    await tester.pump();
    await gesto.moveBy(const Offset(40, 40));
    await tester.pump();
    await gesto.up();
    expect(r.tamanos, isNotEmpty);
    expect(r.tamanos.last, greaterThan(100));
    expect(r.lugares, isEmpty);
  });

  testWidgets('agarrar el medio mueve y no agranda', (tester) async {
    final r = await montar(tester);
    final gesto = await tester.startGesture(
      tester.getCenter(find.byType(ArrastrarParaUbicar)),
    );
    await gesto.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesto.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesto.up();
    expect(r.lugares, isNotEmpty);
    expect(r.lugares.last.$2, greaterThan(0));
    expect(r.tamanos, isEmpty);
  });
}
