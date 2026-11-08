// La ventana de prueba de BARRA en la web (tool/barra_web_prueba.dart) anda: abre a
// 390 px con la noche inventada, sin base ni nube, como en el iPhone. Si deja de
// compilar o de mostrar la noche, salta acá.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/helpers/noche_de_barra.dart';
import '../tool/barra_web_prueba.dart';

void main() {
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> abrir(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final noche = await nocheDeBarra(fotos: false);
    await tester.pumpWidget(PruebaDeLaBarraEnLaWeb(noche));
    await asentar(tester);
  }

  String texto(WidgetTester tester, String clave) => tester.widget<Text>(find.byKey(Key(clave))).data!;

  testWidgets('abre en CAJAS de la noche de PINAROLI, como en el iPhone, sin impresora', (tester) async {
    await abrir(tester);
    expect(tester.takeException(), isNull);
    expect(texto(tester, 'jefe_fiesta_nombre'), 'TÉCNICA PINAROLI');
    expect(texto(tester, 'jefe_fiesta_fecha'), 'viernes 4 de diciembre · anoche');
    expect(texto(tester, 'jefe_kpi_ventas_valor'), '59', reason: '60 ventas, una anulada');
    expect(texto(tester, 'jefe_kpi_cajas_valor'), '2 abiertas');
    expect(find.byKey(const Key('jefe_impresora')), findsNothing);
    expect(find.byKey(const Key('jefe_cajas_releer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('jefe_pestana_precios')));
    await asentar(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('jefe_lista_imprimir')), findsNothing);
    expect(find.byKey(const Key('jefe_lista_pdf')), findsOneWidget);

    await tester.tap(find.byKey(const Key('prueba_modo_jefe')));
    await asentar(tester);
    expect(find.byKey(const Key('jefe_sin_modo_jefe')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
