import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/widgets/elegir_vales.dart';

/// La pantalla de después de cobrar: TODO JUNTO o POR SEPARADO; por separado, cada vale
/// lo arma la cajera escribiendo por cuánto, hasta que no quede nada (pedido del jefe,
/// 3-nov). Un vale por papel.
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

  Future<void> escribir(WidgetTester tester, int bebida, String texto) async {
    await tester.enterText(find.byKey(Key('vale-por-$bebida')), texto);
    await tester.pump();
  }

  bool apagado(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed == null;

  testWidgets('todo junto: un solo vale con todas las bebidas', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-todo-junto');
    await tocar(tester, 'imprimir-todo-junto');
    expect(impresora.papeles, hasLength(1));
    expect(impresora.papeles.single, containsAllInOrder(['10 CERVEZA LATA', '2 FERNET CON COCA', '3 AGUA SIN GAS']));
    expect(find.text('Vale impreso'), findsOneWidget);
    expect(find.byKey(const Key('imprimir-todo-junto')), findsNothing, reason: 'no se imprime dos veces');
  });

  testWidgets('por separado: cada vale por lo que se escribe, hasta que no queda nada', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    expect(find.text('Quedan 10'), findsOneWidget);

    await escribir(tester, 0, '3');
    expect(find.text('IMPRIMIR VALE POR 3'), findsOneWidget);
    await tocar(tester, 'imprimir-0');
    expect(impresora.papeles, hasLength(1), reason: 'un solo papel por IMPRIMIR');
    expect(impresora.papeles.last, containsAllInOrder(['Caja 2 · Marta · N° 0017-1', 'VALE POR 3', 'CERVEZA LATA']));
    expect(tester.widget<TextField>(find.byKey(const Key('vale-por-0'))).controller!.text, isEmpty,
        reason: 'la casilla queda vacía para el próximo');
    expect(find.text('Quedan 7 · Salió 1 vale: 3'), findsOneWidget);

    await escribir(tester, 0, '2');
    await tocar(tester, 'imprimir-0');
    expect(impresora.papeles.last, containsAllInOrder(['Caja 2 · Marta · N° 0017-2', 'VALE POR 2']));
    expect(find.text('Quedan 5 · Salieron 2 vales: 3 · 2'), findsOneWidget);

    // Vacía: un vale por todas las que quedan.
    expect(find.text('IMPRIMIR LAS 5'), findsOneWidget);
    await tocar(tester, 'imprimir-0');
    expect(impresora.papeles.last, contains('VALE POR 5'));
    expect(impresora.papeles, hasLength(3));
    expect(find.text('Todo en vales: 3 · 2 · 5'), findsOneWidget);
    expect(find.byKey(const Key('imprimir-0')), findsNothing);
    expect(find.text('Falta imprimir: fernet con coca, agua sin gas'), findsOneWidget);
  });

  testWidgets('los vales se numeran en toda la venta, aunque sean de bebidas distintas', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    await escribir(tester, 0, '4');
    await tocar(tester, 'imprimir-0');
    await escribir(tester, 1, '1');
    await tocar(tester, 'imprimir-1');
    await escribir(tester, 0, '1');
    await tocar(tester, 'imprimir-0');
    expect([for (final p in impresora.papeles) p[2]], [
      'Caja 2 · Marta · N° 0017-1',
      'Caja 2 · Marta · N° 0017-2',
      'Caja 2 · Marta · N° 0017-3',
    ]);
  });

  testWidgets('no deja pasar más de lo que queda', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    await escribir(tester, 0, '11');
    expect(find.text('Va de 1 a 10'), findsOneWidget);
    expect(apagado(tester, 'imprimir-0'), isTrue);
    await escribir(tester, 0, '0');
    expect(apagado(tester, 'imprimir-0'), isTrue);

    await escribir(tester, 0, '8');
    await tocar(tester, 'imprimir-0');
    await escribir(tester, 0, '3');
    expect(find.text('Va de 1 a 2'), findsOneWidget, reason: 'quedan 2');
    expect(apagado(tester, 'imprimir-0'), isTrue);
    expect(impresora.papeles, hasLength(1));
  });

  testWidgets('con un vale impreso, la forma ya no se cambia', (tester) async {
    await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    await tocar(tester, 'imprimir-1');
    expect(find.text('Ya salió un vale: la forma no se cambia.'), findsOneWidget);
    expect(apagado(tester, 'forma-todo-junto'), isTrue);
  });

  testWidgets('si no sale, lo dice y deja lo escrito para volver a mandarlo', (tester) async {
    final impresora = await abrir(tester);
    await tocar(tester, 'forma-por-separado');
    await escribir(tester, 0, '5');
    impresora.anda = false;
    await tocar(tester, 'imprimir-0');
    expect(find.textContaining('No salió el vale'), findsOneWidget);
    expect(find.text('Quedan 10'), findsOneWidget, reason: 'no se descuenta lo que no salió');
    impresora.anda = true;
    await tocar(tester, 'imprimir-0');
    expect(impresora.papeles.single, containsAllInOrder(['Caja 2 · Marta · N° 0017-1', 'VALE POR 5']));
    expect(find.text('Quedan 5 · Salió 1 vale: 5'), findsOneWidget);
  });

  testWidgets('en un celular entra sin desbordar', (tester) async {
    await abrir(tester, tamano: const Size(360, 740));
    await tocar(tester, 'forma-por-separado');
    await escribir(tester, 0, '3');
    await tocar(tester, 'imprimir-0');
    expect(tester.takeException(), isNull);
    expect(find.text('Quedan 7 · Salió 1 vale: 3'), findsOneWidget);
  });
}
