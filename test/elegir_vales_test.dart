import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/widgets/elegir_vales.dart';

/// La pantalla de después de cobrar: TODO JUNTO o POR SEPARADO, con "vale por" e
/// IMPRIMIR por bebida, y un vale por papel (pedido del jefe, 3-nov).
const _evento = 'e0000000-0000-4000-8000-000000000001';

/// Lo que la impresora recibió: cada papel con sus líneas grandes y chicas, como texto.
class _Impresora {
  final papeles = <List<String>>[];
  bool anda = true;

  Future<bool> imprimir(List<LineaTicket> lineas) async {
    if (!anda) return false;
    papeles.add([
      for (final l in lineas)
        switch (l) {
          GrandeTicket() => l.texto,
          TextoTicket() => l.texto,
          _ => '',
        },
    ]);
    return true;
  }
}

void main() {
  final caja = CajaBarra.abrir(
    eventoId: _evento,
    operadorNombre: 'Marta',
    numeroCaja: 2,
    ahora: DateTime.utc(2026, 12, 5, 1),
  );
  final venta = VentaBarra.nueva(
    cajaBarraId: caja.id,
    eventoId: _evento,
    numero: 17,
    renglones: const [
      RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 10),
      RenglonVenta(productoId: 'b', nombre: 'Fernet con coca', precio: 6000, cantidad: 2),
      RenglonVenta(productoId: 'c', nombre: 'Agua sin gas', precio: 1000, cantidad: 3),
    ],
    medio: MedioBarra.efectivo,
    efectivo: 50000,
    ahora: DateTime.utc(2026, 12, 5, 2, 41),
  );

  Future<_Impresora> abrir(WidgetTester tester, {Size tamano = const Size(1024, 900)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final impresora = _Impresora();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElegirVales(venta: venta, caja: caja, fiesta: 'Puerto Viejo', imprimir: impresora.imprimir),
      ),
    ));
    return impresora;
  }

  Future<void> tocar(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('todo junto: un solo vale con todas las bebidas', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-todo-junto');
    await tocar(tester, 'imprimir-todo-junto');
    expect(impresora.papeles, hasLength(1));
    expect(impresora.papeles.single, containsAllInOrder(['10 CERVEZA LATA', '2 FERNET CON COCA', '3 AGUA SIN GAS']));
    expect(find.text('Vale impreso'), findsOneWidget);
    expect(find.byKey(const Key('imprimir-todo-junto')), findsNothing, reason: 'no se imprime dos veces');
  });

  testWidgets('por separado: "vale por 3" son 4 vales, y sale uno por vez con SIGUIENTE', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    await tester.enterText(find.byKey(const Key('vale-por-0')), '3');
    await tester.pump();
    expect(find.text('4 vales: 3 · 3 · 3 · 1'), findsOneWidget);

    await tocar(tester, 'imprimir-0');
    expect(impresora.papeles, hasLength(1), reason: 'un solo papel, no la tira');
    expect(impresora.papeles.last, containsAllInOrder(['VALE POR 3', 'CERVEZA LATA', '1 DE 4']));
    expect(find.text('Salió el vale 1 de 4: arrancalo'), findsOneWidget);

    for (var n = 2; n <= 4; n++) {
      await tocar(tester, 'siguiente-0');
      expect(impresora.papeles, hasLength(n));
    }
    expect(impresora.papeles.last, containsAllInOrder(['VALE POR 1', 'CERVEZA LATA', '4 DE 4']));
    expect(find.text('4 vales impresos'), findsOneWidget);
    expect(find.byKey(const Key('siguiente-0')), findsNothing);
    expect(find.text('Falta imprimir: fernet con coca, agua sin gas'), findsOneWidget);
  });

  testWidgets('sin "vale por", un vale con todas las de esa bebida', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    expect(find.text('1 vale de 3'), findsOneWidget);
    await tocar(tester, 'imprimir-2');
    expect(impresora.papeles.single, containsAllInOrder(['VALE POR 3', 'AGUA SIN GAS']));
    expect(impresora.papeles.single.any((r) => r.contains(' DE ')), isFalse);
    expect(find.text('Vale impreso'), findsOneWidget);
  });

  testWidgets('un "vale por" que no sirve no deja imprimir', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    for (final malo in ['0', '11']) {
      await tester.enterText(find.byKey(const Key('vale-por-0')), malo);
      await tester.pump();
      expect(find.text('Va de 1 a 10'), findsOneWidget, reason: malo);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('imprimir-0'))).onPressed, isNull);
    }
    expect(impresora.papeles, isEmpty);
  });

  testWidgets('con un vale impreso, la forma ya no se cambia', (tester) async {
    await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    await tocar(tester, 'imprimir-1');
    expect(find.text('Ya salió un vale: la forma no se cambia.'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('forma-todo-junto'))).onPressed, isNull);
  });

  testWidgets('si no sale, lo dice y el mismo vale se vuelve a mandar', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    await tester.enterText(find.byKey(const Key('vale-por-0')), '5');
    await tester.pump();
    impresora.anda = false;
    await tocar(tester, 'imprimir-0');
    expect(find.textContaining('No salió el vale'), findsOneWidget);
    impresora.anda = true;
    await tocar(tester, 'siguiente-0');
    expect(impresora.papeles.single, containsAllInOrder(['VALE POR 5', '1 DE 2']));
  });

  testWidgets('en un celular entra sin desbordar', (tester) async {
    await abrir(tester, tamano: const Size(360, 740));
    await tocar(tester, 'forma-por-separado');
    await tester.enterText(find.byKey(const Key('vale-por-0')), '3');
    await tester.pump();
    await tocar(tester, 'imprimir-0');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('SIGUIENTE (2 de 4)'), findsOneWidget);
  });
}
