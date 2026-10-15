// "En otra pantalla, por el navegador", al pie de Personalizar tótem (sección 8):
// el link del tótem web con su clave, para copiar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/widgets/link_totem_navegador.dart';

const _ev = 'e0000000-0000-4000-8000-00000000000a';
const _base = 'https://arguello-events.vercel.app';

void main() {
  String? copiado;

  setUp(() {
    copiado = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiado = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  Future<void> montar(WidgetTester tester, Future<String?> Function() clave) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: LinkTotemNavegador(
                eventoId: _ev,
                base: _base,
                pedirClave: clave,
              ),
            ),
          ),
        ),
      );

  testWidgets('muestra el link con la clave y lo copia', (tester) async {
    await montar(tester, () async => 'abc123');
    await tester.pump();
    const link = '$_base/?totem&evento=$_ev&clave=abc123';
    expect(find.text(LinkTotemNavegador.titulo), findsOneWidget);
    expect(find.text(link), findsOneWidget);

    await tester.tap(find.text(LinkTotemNavegador.copiar));
    await tester.pump();
    expect(copiado, link);
    expect(find.text(LinkTotemNavegador.copiado), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text(LinkTotemNavegador.copiar), findsOneWidget);
  });

  testWidgets('sin internet lo dice y deja probar de nuevo', (tester) async {
    String? clave;
    var pedidas = 0;
    await montar(tester, () async {
      pedidas++;
      return clave;
    });
    await tester.pump();
    expect(find.text(LinkTotemNavegador.sinInternet), findsOneWidget);
    expect(find.text(LinkTotemNavegador.copiar), findsNothing);

    clave = 'abc123';
    await tester.tap(find.text(LinkTotemNavegador.reintentar));
    await tester.pump();
    expect(pedidas, 2);
    expect(find.text('$_base/?totem&evento=$_ev&clave=abc123'), findsOneWidget);
  });

  testWidgets('si pedir la clave falla, es lo mismo que sin internet',
      (tester) async {
    await montar(tester, () async => throw StateError('sin sesión'));
    await tester.pump();
    expect(find.text(LinkTotemNavegador.sinInternet), findsOneWidget);
    expect(copiado, isNull);
  });
}
