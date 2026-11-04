import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/widgets/operational_sync_coordinator.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// VENDER y el cobro de verdad, con la barra y la impresora en memoria: tocar los
/// productos, el buscador, los tres botones de pago, el recargo por transferencia, el
/// mixto por cualquiera de las dos casillas, el cambio y los vales. En celular, tablet
/// y PC, sin desbordes.
const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late CajaBarra caja;
  late ProductoBarra cerveza, fernet, agua;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', DateTime.now().add(const Duration(days: 5)));
    prueba.eventos.add(fiesta);
    final b = prueba.barra;
    cerveza = b.producto('Cerveza lata', categoria: 'Cervezas');
    fernet = b.producto('Fernet con coca', categoria: 'Tragos');
    agua = b.producto('Agua sin gas', categoria: 'Sin alcohol');
    b.precio(fiesta.id, cerveza, 3500, orden: 0);
    b.precio(fiesta.id, fernet, 6000, orden: 1);
    b.precio(fiesta.id, agua, 1000, orden: 2, stock: 5, aviso: 1);
    caja = await b.abrirCaja(eventoId: fiesta.id, operadorId: _marta, operadorNombre: 'Marta', numeroCaja: 2);
  });

  Future<void> abrir(WidgetTester tester, {Size tamano = const Size(1280, 800)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [...operadores.reemplazos, ...prueba.reemplazos],
      child: MaterialApp(home: VenderScreen(fiesta: fiesta, caja: caja)),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(VenderScreen)));
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          operadores.operadores.lista.single,
          const PermisosEfectivos(barra: true),
        );
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder f, {int veces = 1}) async {
    for (var i = 0; i < veces; i++) {
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }
  }

  Finder producto(ProductoBarra p) => find.byKey(Key('producto_${p.id}'));
  String total(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('vender_total'))).data!;

  /// 10 cervezas, 2 fernet y 3 aguas: $ 50.000.
  Future<void> armarLaCuenta(WidgetTester tester) async {
    await tocar(tester, producto(cerveza), veces: 10);
    await tocar(tester, producto(fernet), veces: 2);
    await tocar(tester, producto(agua), veces: 3);
    expect(total(tester), r'$ 50.000');
  }

  Future<void> escribir(WidgetTester tester, String key, String texto) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.enterText(find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText)).first, texto);
    await tester.pumpAndSettle();
  }

  String textoDe(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  group('en cada tamaño', () {
    for (final (nombre, tamano) in [
      ('un celular', const Size(360, 740)),
      ('un celular acostado', const Size(740, 360)),
      ('una tablet parada', const Size(800, 1280)),
      ('una tablet acostada o una PC', const Size(1280, 800)),
    ]) {
      testWidgets('en $nombre no se desborda y los tres botones de pago se ven', (tester) async {
        await abrir(tester, tamano: tamano);
        await tocar(tester, producto(cerveza), veces: 2);
        expect(tester.takeException(), isNull);
        for (final m in ['efectivo', 'transferencia', 'mixto']) {
          final b = find.byKey(Key('pagar_$m'));
          expect(b, findsOneWidget, reason: m);
          expect(b.hitTestable(), findsOneWidget, reason: '$m se toca sin desplazar');
        }
        await tocar(tester, find.byKey(const Key('pagar_mixto')));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('cobro_confirmar')), findsOneWidget);
      });
    }
  });

  testWidgets('tocar suma; menos, quitar y VACIAR', (tester) async {
    await abrir(tester);
    for (final m in ['efectivo', 'transferencia', 'mixto']) {
      expect(tester.widget<ButtonStyleButton>(find.byKey(Key('pagar_$m'))).onPressed, isNull,
          reason: 'con la cuenta vacía no se cobra');
    }
    await tocar(tester, producto(cerveza), veces: 3);
    await tocar(tester, producto(agua));
    expect(total(tester), r'$ 11.500');
    await tocar(tester, find.byKey(Key('restar_${cerveza.id}')));
    expect(total(tester), r'$ 8.000');
    await tocar(tester, find.byKey(Key('quitar_${agua.id}')));
    expect(total(tester), r'$ 7.000');
    await tocar(tester, find.byKey(const Key('vender_vaciar')));
    expect(total(tester), r'$ 0');
  });

  testWidgets('el buscador y las categorías', (tester) async {
    await abrir(tester);
    await tester.enterText(find.byKey(const Key('vender_buscar')), 'fernét');
    await tester.pumpAndSettle();
    expect(producto(fernet), findsOneWidget);
    expect(producto(cerveza), findsNothing);
    await tester.enterText(find.byKey(const Key('vender_buscar')), 'nada de esto');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vender_sin_resultados')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('vender_buscar')), '');
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(const Key('vender_categoria_Sin alcohol')));
    expect(producto(agua), findsOneWidget);
    expect(producto(cerveza), findsNothing);
    await tocar(tester, find.byKey(const Key('vender_categoria_todo')));
    expect(producto(cerveza), findsOneWidget);
  });

  String stock(WidgetTester tester, ProductoBarra p) => textoDe(tester, 'stock_${p.id}');
  Finder pregunta() => find.byKey(const Key('sin_stock'));

  testWidgets('Quedan baja con la cuenta; sin stock pregunta antes, y se puede vender igual', (tester) async {
    await abrir(tester);
    expect(stock(tester, agua), 'Quedan 5');
    await tocar(tester, producto(agua), veces: 2);
    expect(stock(tester, agua), 'Quedan 3', reason: 'lo que ya está en la cuenta también cuenta');
    await tocar(tester, producto(agua), veces: 3);
    expect(stock(tester, agua), 'Sin stock');
    expect(pregunta(), findsNothing, reason: 'las 5 cargadas se venden sin preguntar');
    expect(total(tester), r'$ 5.000');

    await tocar(tester, producto(agua));
    expect(pregunta(), findsOneWidget);
    expect(find.text('No queda agua sin gas'), findsOneWidget);
    await tocar(tester, find.text('NO'));
    expect(total(tester), r'$ 5.000', reason: 'con NO no se suma');

    await tocar(tester, producto(agua));
    expect(pregunta(), findsOneWidget, reason: 'con NO vuelve a preguntar');
    await tocar(tester, find.byKey(const Key('sin_stock_vender_igual')));
    expect(total(tester), r'$ 6.000');
    await tocar(tester, producto(agua));
    expect(pregunta(), findsNothing, reason: 'dijo que sí: en esta cuenta no pregunta más');
    expect(total(tester), r'$ 7.000');

    await tocar(tester, find.byKey(const Key('vender_vaciar')));
    expect(stock(tester, agua), 'Quedan 5');
    await tocar(tester, producto(agua), veces: 5);
    expect(pregunta(), findsNothing);
    await tocar(tester, producto(agua));
    expect(pregunta(), findsOneWidget, reason: 'una cuenta nueva vuelve a preguntar');
  });

  testWidgets('el + de la cuenta también pregunta sin stock', (tester) async {
    await abrir(tester);
    await tocar(tester, producto(agua), veces: 5);
    await tocar(tester, find.byKey(Key('sumar_${agua.id}')));
    expect(pregunta(), findsOneWidget);
    await tocar(tester, find.text('NO'));
    expect(total(tester), r'$ 5.000');
  });

  testWidgets('el + y el − de la tarjeta', (tester) async {
    await abrir(tester);
    expect(find.byKey(Key('tarjeta_sumar_${cerveza.id}')), findsNothing, reason: 'fuera de la cuenta, sin botones');
    await tocar(tester, producto(cerveza));
    expect(find.byKey(Key('tarjeta_restar_${cerveza.id}')), findsOneWidget);
    await tocar(tester, find.byKey(Key('tarjeta_sumar_${cerveza.id}')));
    expect(total(tester), r'$ 7.000');
    await tocar(tester, find.byKey(Key('tarjeta_restar_${cerveza.id}')), veces: 2);
    expect(total(tester), r'$ 0');
    expect(find.byKey(Key('tarjeta_sumar_${cerveza.id}')), findsNothing);
  });

  testWidgets('el stock es de toda la fiesta: descuenta lo que venden las otras cajas al bajar', (tester) async {
    await abrir(tester);
    expect(stock(tester, agua), 'Quedan 5');
    final b = prueba.barra;
    final otra = await b.abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'a0000000-0000-4000-8000-000000000002',
      operadorNombre: 'Tati',
      numeroCaja: 3,
    );
    Future<void> venderEnLaOtra(int aguas) => b.vender(
          caja: otra,
          renglones: [RenglonVenta(productoId: agua.id, nombre: agua.nombre, precio: 1000, cantidad: aguas)],
          medio: MedioBarra.efectivo,
          efectivo: 1000.0 * aguas,
          quien: 'Tati',
        );
    Future<void> bajo() async {
      ProviderScope.containerOf(tester.element(find.byType(VenderScreen)))
          .read(operationalSyncRevisionProvider.notifier)
          .bump();
      await tester.pumpAndSettle();
    }

    await venderEnLaOtra(2);
    await tester.pumpAndSettle();
    expect(stock(tester, agua), 'Quedan 5', reason: 'hasta que baja, no se entera');
    await bajo();
    expect(stock(tester, agua), 'Quedan 3');

    await venderEnLaOtra(3);
    await bajo();
    expect(stock(tester, agua), 'Agotado');
    await tocar(tester, producto(agua));
    expect(pregunta(), findsOneWidget, reason: 'agotado por otra caja, también pregunta');
  });

  testWidgets('EFECTIVO: lo que entrega, el vuelto, y la venta se guarda con los vales', (tester) async {
    await abrir(tester);
    await armarLaCuenta(tester);
    await tocar(tester, find.byKey(const Key('pagar_efectivo')));
    expect(find.text('Pagar en efectivo'), findsOneWidget);
    expect(find.byKey(const Key('cobro_recargo')), findsNothing, reason: 'en efectivo no hay recargo');
    await escribir(tester, 'cobro_recibe', '60000');
    expect(find.text('60.000'), findsOneWidget, reason: 'los puntos aparecen al escribir');
    expect(textoDe(tester, 'cobro_vuelto'), r'$ 10.000');
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));

    final v = prueba.barra.ventasGuardadas.single;
    expect(v.medio, MedioBarra.efectivo);
    expect(v.total, 50000);
    expect(v.recibe, 60000);
    expect(v.vuelto, 10000);
    expect(v.recargo, 0);
    expect(v.hechoPor, 'Marta');
    expect(prueba.subidas, [v.id], reason: 'sube enseguida');
    expect(find.text('Vales · N° 0001'), findsOneWidget);
    expect(textoDe(tester, 'vales_vuelto'), r'Vuelto $ 10.000');
  });

  testWidgets('EFECTIVO justo: sin anotar lo que entrega, se confirma', (tester) async {
    await abrir(tester);
    await tocar(tester, producto(cerveza));
    await tocar(tester, find.byKey(const Key('pagar_efectivo')));
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));
    expect(prueba.barra.ventasGuardadas.single.recibe, isNull);
  });

  testWidgets('si entrega menos, no confirma y dice por qué', (tester) async {
    await abrir(tester);
    await tocar(tester, producto(cerveza));
    await tocar(tester, find.byKey(const Key('pagar_efectivo')));
    await escribir(tester, 'cobro_recibe', '2000');
    expect(textoDe(tester, 'cobro_falta'), 'Entrega menos que el total');
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('cobro_confirmar'))).onPressed, isNull);
  });

  testWidgets('TRANSFERENCIA: con el 5 % puesto, sin comprobante que tildar', (tester) async {
    await abrir(tester);
    await armarLaCuenta(tester);
    await tocar(tester, find.byKey(const Key('pagar_transferencia')));
    expect(find.textContaining('comprobante'), findsNothing);
    expect(textoDe(tester, 'cobro_transfiere'), r'$ 52.500');
    expect(textoDe(tester, 'cobro_recargo_cuenta'), r'$ 50.000 + 5 % = $ 52.500');
    expect(textoDe(tester, 'cobro_a_cobrar'), r'$ 52.500');
    await escribir(tester, 'cobro_recargo_pct', '10');
    expect(textoDe(tester, 'cobro_transfiere'), r'$ 55.000');
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));

    final v = prueba.barra.ventasGuardadas.single;
    expect(v.medio, MedioBarra.transferencia);
    expect(v.total, 50000);
    expect(v.transferencia, 55000);
    expect(v.recargo, 5000);
    expect(v.recargoPct, 10);
    expect(prueba.recargo.pct, 10, reason: 'este equipo recuerda el % de la última vez');
  });

  testWidgets('TRANSFERENCIA: el recargo en pesos, y el check lo apaga', (tester) async {
    await abrir(tester);
    await armarLaCuenta(tester);
    await tocar(tester, find.byKey(const Key('pagar_transferencia')));
    await tocar(tester, find.text(r'$').last);
    await escribir(tester, 'cobro_recargo_pesos', '2000');
    expect(textoDe(tester, 'cobro_transfiere'), r'$ 52.000');
    await tocar(tester, find.byKey(const Key('cobro_recargo')));
    expect(textoDe(tester, 'cobro_transfiere'), r'$ 50.000');
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));
    final v = prueba.barra.ventasGuardadas.single;
    expect(v.recargo, 0);
    expect(v.transferencia, 50000);
    expect(prueba.recargo.prendido, isFalse);
  });

  testWidgets('MIXTO: el efectivo completa la transferencia, ya con el recargo', (tester) async {
    await abrir(tester);
    await armarLaCuenta(tester);
    await tocar(tester, find.byKey(const Key('pagar_mixto')));
    expect(textoDe(tester, 'cobro_falta'), 'Poné cuánto es en efectivo y cuánto por transferencia');
    await escribir(tester, 'cobro_mixto_efectivo', '20000');
    expect(find.text('31.500'), findsOneWidget, reason: 'la transferencia ya con el 5 %');
    expect(textoDe(tester, 'cobro_a_cobrar'), r'$ 51.500');
    await escribir(tester, 'cobro_recibe', '25000');
    expect(textoDe(tester, 'cobro_vuelto'), r'$ 5.000');
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));

    final v = prueba.barra.ventasGuardadas.single;
    expect(v.medio, MedioBarra.mixto);
    expect(v.efectivo, 20000);
    expect(v.transferencia, 31500);
    expect(v.recargo, 1500);
    expect(v.vuelto, 5000);
  });

  testWidgets('MIXTO: se puede escribir por la transferencia, y el efectivo se acomoda', (tester) async {
    await abrir(tester);
    await armarLaCuenta(tester);
    await tocar(tester, find.byKey(const Key('pagar_mixto')));
    await escribir(tester, 'cobro_mixto_transferencia', '31500');
    expect(find.text('20.000'), findsOneWidget);
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));
    final v = prueba.barra.ventasGuardadas.single;
    expect(v.efectivo, 20000);
    expect(v.transferencia, 31500);
  });

  testWidgets('VOLVER no guarda nada y deja la cuenta', (tester) async {
    await abrir(tester);
    await tocar(tester, producto(cerveza));
    await tocar(tester, find.byKey(const Key('pagar_efectivo')));
    await tocar(tester, find.byKey(const Key('cobro_volver')));
    expect(prueba.barra.ventasGuardadas, isEmpty);
    expect(total(tester), r'$ 3.500');
  });

  testWidgets('los vales salen de la venta, y LISTO vuelve con la cuenta vacía', (tester) async {
    await abrir(tester);
    await armarLaCuenta(tester);
    await tocar(tester, find.byKey(const Key('pagar_efectivo')));
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));
    await tocar(tester, find.byKey(const Key('forma-todo-junto')));
    await tocar(tester, find.byKey(const Key('imprimir-todo-junto')));
    expect(prueba.papel.papeles.single, containsAllInOrder(['10 CERVEZA LATA', '2 FERNET CON COCA', '3 AGUA SIN GAS']));
    await tocar(tester, find.byKey(const Key('vales_listo')));
    expect(find.byType(VenderScreen), findsOneWidget);
    expect(total(tester), r'$ 0');
    expect(find.text('Quedan 2'), findsOneWidget, reason: 'el stock ya descuenta lo vendido');
  });

  testWidgets('LISTO con bebidas sin vale pregunta antes', (tester) async {
    await abrir(tester);
    await tocar(tester, producto(cerveza));
    await tocar(tester, find.byKey(const Key('pagar_efectivo')));
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));
    await tocar(tester, find.byKey(const Key('vales_listo')));
    expect(find.text('Quedan bebidas sin vale. ¿Volver a vender igual?'), findsOneWidget);
    await tocar(tester, find.byKey(const Key('vales_salir_igual')));
    expect(find.byType(VenderScreen), findsOneWidget);
  });

  testWidgets('sin impresora la venta igual queda, y los vales avisan', (tester) async {
    prueba.papel.anda = false;
    await abrir(tester);
    await tocar(tester, producto(cerveza));
    await tocar(tester, find.byKey(const Key('pagar_efectivo')));
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));
    expect(prueba.barra.ventasGuardadas, hasLength(1));
    await tocar(tester, find.byKey(const Key('forma-todo-junto')));
    await tocar(tester, find.byKey(const Key('imprimir-todo-junto')));
    expect(find.textContaining('No salió el vale'), findsOneWidget);
  });

  testWidgets('si la base no guarda, lo dice y la cuenta queda', (tester) async {
    prueba.barra.venderFalla = true;
    await abrir(tester);
    await tocar(tester, producto(cerveza));
    await tocar(tester, find.byKey(const Key('pagar_efectivo')));
    await tocar(tester, find.byKey(const Key('cobro_confirmar')));
    expect(find.text('No se guardó la venta. Probá de nuevo.'), findsOneWidget);
    expect(total(tester), r'$ 3.500');
    expect(prueba.subidas, isEmpty);
  });

  testWidgets('el cambio se pone después, con su ícono', (tester) async {
    await abrir(tester);
    await tocar(tester, find.byKey(const Key('vender_cambio')));
    await tester.enterText(find.byKey(const Key('cambio_monto')), '20000');
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(const Key('cambio_guardar')));
    expect(prueba.barra.cajasGuardadas.single.cambioInicial, 20000);
  });

  testWidgets('al abrir se prepara la impresora, y el ícono dice cómo está', (tester) async {
    await abrir(tester);
    expect(prueba.papel.preparadas, 1);
    expect(find.byIcon(Icons.print), findsOneWidget);
  });

  testWidgets('en el celular, la cuenta se despliega tocando el total', (tester) async {
    await abrir(tester, tamano: const Size(360, 740));
    await tocar(tester, producto(cerveza), veces: 2);
    expect(find.byKey(Key('renglon_${cerveza.id}')), findsNothing);
    await tocar(tester, find.byKey(const Key('vender_ver_cuenta')));
    expect(find.byKey(Key('renglon_${cerveza.id}')), findsOneWidget);
    await tocar(tester, find.byKey(Key('sumar_${cerveza.id}')));
    expect(total(tester), r'$ 10.500');
    expect(tester.takeException(), isNull);
  });
}
