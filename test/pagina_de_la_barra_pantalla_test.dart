import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/pagina/catalogo_de_la_pagina.dart';
import 'package:arguello_events/features/barra/pagina/cliente_de_la_pagina.dart';
import 'package:arguello_events/features/barra/pagina/pagina_de_la_barra.dart';
import 'package:arguello_events/features/barra/repositor/stock_de_las_barras_screen.dart';
import 'package:arguello_events/features/barra/widgets/las_cajas_screen.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart' show GuardadoDelCelular;

import 'helpers/barra_en_memoria.dart';

/// **La página del iPhone en pantalla** (28-nov-2026): la de verdad, contra una central
/// de verdad en esta PC. El PIN, LAS CAJAS de la encargada (anular desde el iPhone), STOCK
/// del repositor, la franja de arriba y SALIR.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';

class _Navegador implements GuardadoDelCelular {
  final datos = <String, String>{};

  @override
  Future<String?> leer(String clave) async => datos[clave];

  @override
  Future<void> guardar(String clave, String? valor) async {
    if (valor == null) {
      datos.remove(clave);
    } else {
      datos[clave] = valor;
    }
  }
}

/// La notebook, que puede tardar en guardar lo de la página (la respuesta no llega a
/// tiempo) o no guardarlo.
class _NotebookQueTarda extends BarraEnMemoria {
  Completer<void>? traba;
  var guarda = true;

  @override
  Future<bool> guardarDeLaPagina(String tabla, Map<String, Object?> fila) async {
    final t = traba;
    if (t != null) await t.future;
    if (!guarda) return false;
    return super.guardarDeLaPagina(tabla, fila);
  }
}

void main() {
  late _NotebookQueTarda notebook;
  late CentralBarra central;
  late int puerto;
  late CajaBarra caja;
  late VentaBarra venta;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final personas = QuienEsQuienEnMemoria()
      ..persona('op-romi', 'Romi', pin: '7777', rol: RolEnLaBarra.encargada)
      ..persona('op-nico', 'Nico', pin: '5555', rol: RolEnLaBarra.repositor);
    notebook = _NotebookQueTarda()..equipo = 'notebook';
    notebook.reloj = () => DateTime.now().toUtc();
    final speed = notebook.producto('Speed', categoria: 'Energizantes');
    notebook.precio(_fiesta, speed, 4000, stock: 48);
    caja = await notebook.abrirCaja(eventoId: _fiesta, operadorId: 'op-marta', operadorNombre: 'Marta', numeroCaja: 1);
    venta = await notebook.vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: speed.id, nombre: 'Speed', precio: 4000, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 8000,
      quien: 'Marta',
    );
    central = CentralBarra(
      eventoId: _fiesta,
      barra: notebook,
      quienEsQuien: personas,
      barraDelSalon: 'Barra 1',
      fiestaParaLaPagina: () async =>
          fiestaParaLaPagina(fiestaDePrueba(_fiesta, 'TÉCNICA PINAROLI', DateTime.now().add(const Duration(hours: 2)))),
      catalogoParaLaPagina: () => catalogoParaLaPagina(notebook, _fiesta),
    );
  });

  tearDown(() async {
    await central.cerrar();
  });

  /// Deja correr la red de verdad y la pantalla, hasta que [listo].
  Future<void> esperar(WidgetTester tester, bool Function() listo, {String que = ''}) async {
    for (var i = 0; i < 250 && !listo(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(listo(), isTrue, reason: que);
  }

  Future<ClienteDeLaPagina> abrir(WidgetTester tester,
      {Size tamano = const Size(390, 844), Duration esperaDeRespuesta = const Duration(seconds: 10)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    });
    final cliente = ClienteDeLaPagina(
      servidor: Uri.parse('http://127.0.0.1:$puerto/'),
      guardado: _Navegador(),
      abrir: IOWebSocketChannel.connect,
      latido: const Duration(seconds: 30),
      esperaDeRespuesta: esperaDeRespuesta,
    );
    await tester.runAsync(cliente.iniciar);
    await tester.pumpWidget(PaginaDeLaBarraApp(cliente: cliente));
    await tester.pump();
    return cliente;
  }

  Future<void> cerrar(WidgetTester tester, ClienteDeLaPagina cliente) async {
    await tester.pumpWidget(const SizedBox());
    cliente.dispose();
    await tester.pump(const Duration(minutes: 1));
  }

  Future<void> ponerPin(WidgetTester tester, ClienteDeLaPagina cliente, String pin) async {
    await tester.enterText(find.byKey(const Key('pagina_pin')), pin);
    await tester.tap(find.byKey(const Key('pagina_entrar')));
    await tester.pump();
    await esperar(tester, () => cliente.estado != EstadoDeLaPagina.entrando, que: 'que conteste la notebook');
  }

  testWidgets('la encargada pone su PIN, ve LAS CAJAS y anula desde el iPhone sin el vale', (tester) async {
    // Alta: la lista de ventas de la caja se arma a medida que se ve.
    final cliente = await abrir(tester, tamano: const Size(430, 2400));
    expect(find.byKey(const Key('pagina_pin')), findsOneWidget);
    expect(find.text('ENTRAR'), findsOneWidget);
    await ponerPin(tester, cliente, '7777');
    await esperar(tester, () => find.byType(LasCajasScreen).evaluate().isNotEmpty, que: 'LAS CAJAS');
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.byKey(const Key('pagina_franja'))).data, contains('Romi · Barra 1'));

    await esperar(tester, () => find.byKey(Key('jefe_caja_${caja.id}')).evaluate().isNotEmpty, que: 'la caja de Marta');
    // Lo que dice es cierto: le llega todo por el wifi de la notebook, no cada 30 s.
    expect(tester.widget<Text>(find.byKey(const Key('jefe_en_vivo'))).data, contains('Al día con la notebook'));
    await tester.tap(find.byKey(Key('jefe_caja_${caja.id}')));
    await tester.pump(const Duration(milliseconds: 300));
    await esperar(tester, () => find.byKey(Key('jefe_anular_${venta.id}')).evaluate().isNotEmpty, que: 'la venta');
    await tester.ensureVisible(find.byKey(Key('jefe_anular_${venta.id}')));
    await tester.tap(find.byKey(Key('jefe_anular_${venta.id}')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('motivo_texto')), 'se la tomó');
    await tester.tap(find.byKey(const Key('anular_vale_no_volvio')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('motivo_anular')));
    await esperar(tester, () => notebook.anulacionesGuardadas.isNotEmpty, que: 'la anulación en la notebook');
    expect(notebook.anulacionesGuardadas.single.valeVolvio, isFalse);
    expect(notebook.anulacionesGuardadas.single.hechoPor, 'Romi');
    await esperar(tester, () => find.byKey(Key('jefe_anulada_${venta.id}')).evaluate().isNotEmpty,
        que: 'ANULADA en la página');
    expect(tester.takeException(), isNull);
    await cerrar(tester, cliente);
  });

  testWidgets('el repositor pone su PIN y ve STOCK', (tester) async {
    final cliente = await abrir(tester);
    await ponerPin(tester, cliente, '5555');
    await esperar(tester, () => find.byType(StockDeLasBarrasScreen).evaluate().isNotEmpty, que: 'STOCK');
    expect(find.byType(LasCajasScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await cerrar(tester, cliente);
  });

  testWidgets('un PIN que no es de la barra lo dice, y SALIR vuelve al PIN', (tester) async {
    final cliente = await abrir(tester);
    await ponerPin(tester, cliente, '1234');
    expect(find.byKey(const Key('pagina_problema')), findsOneWidget);
    await ponerPin(tester, cliente, '7777');
    await esperar(tester, () => find.byType(LasCajasScreen).evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('pagina_salir')));
    await tester.pump();
    await esperar(tester, () => find.byKey(const Key('pagina_pin')).evaluate().isNotEmpty, que: 'el PIN de nuevo');
    await cerrar(tester, cliente);
  });

  testWidgets('si se corta la notebook, la franja lo dice en rojo', (tester) async {
    final cliente = await abrir(tester);
    await ponerPin(tester, cliente, '7777');
    await esperar(tester, () => find.byType(LasCajasScreen).evaluate().isNotEmpty);
    await tester.runAsync(central.cerrar);
    await esperar(tester, () => cliente.estado == EstadoDeLaPagina.sinConexion, que: 'sin conexión');
    expect(tester.widget<Text>(find.byKey(const Key('pagina_franja'))).data, contains('Sin conexión con la notebook'));
    expect(find.byType(LasCajasScreen), findsOneWidget, reason: 'sigue viendo lo que tenía');
    await cerrar(tester, cliente);
    central = CentralBarra(eventoId: _fiesta, barra: notebook, quienEsQuien: QuienEsQuienEnMemoria());
  });

  /// La encargada anula la venta de Marta desde LAS CAJAS (sin el vale).
  Future<void> anularDesdeElIphone(WidgetTester tester) async {
    await esperar(tester, () => find.byKey(Key('jefe_caja_${caja.id}')).evaluate().isNotEmpty, que: 'la caja de Marta');
    await tester.tap(find.byKey(Key('jefe_caja_${caja.id}')));
    await tester.pump(const Duration(milliseconds: 300));
    await esperar(tester, () => find.byKey(Key('jefe_anular_${venta.id}')).evaluate().isNotEmpty, que: 'la venta');
    await tester.ensureVisible(find.byKey(Key('jefe_anular_${venta.id}')));
    await tester.tap(find.byKey(Key('jefe_anular_${venta.id}')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('motivo_texto')), 'se la tomó');
    await tester.tap(find.byKey(const Key('anular_vale_no_volvio')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('motivo_anular')));
    await tester.pump();
  }

  testWidgets('sin respuesta a tiempo: dice que no lo repita, la franja dice "por confirmar", SALIR avisa, y al llegar '
      'la respuesta queda ANULADA', (tester) async {
    final cliente =
        await abrir(tester, tamano: const Size(430, 2400), esperaDeRespuesta: const Duration(milliseconds: 400));
    await ponerPin(tester, cliente, '7777');
    await esperar(tester, () => find.byType(LasCajasScreen).evaluate().isNotEmpty, que: 'LAS CAJAS');
    notebook.traba = Completer<void>();
    await anularDesdeElIphone(tester);
    await esperar(tester, () => find.textContaining('No lo repitas').evaluate().isNotEmpty, que: 'el aviso tal cual');
    expect(find.textContaining('Probá de nuevo'), findsNothing, reason: 'repetirlo podía anotarlo dos veces');
    expect(tester.widget<Text>(find.byKey(const Key('pagina_por_confirmar'))).data, '1 por confirmar');

    await tester.tap(find.byKey(const Key('pagina_salir')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Falta confirmar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pagina_esperar')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LasCajasScreen), findsOneWidget, reason: 'ESPERAR no sale');

    await tester.runAsync(() async => notebook.traba!.complete());
    await esperar(tester, () => cliente.porConfirmar == 0, que: 'que la respuesta tardía lo confirme');
    expect(notebook.anulacionesGuardadas, hasLength(1));
    await esperar(tester, () => find.byKey(Key('jefe_anulada_${venta.id}')).evaluate().isNotEmpty,
        que: 'ANULADA en la página');
    expect(find.byKey(const Key('pagina_por_confirmar')), findsNothing);
    await tester.tap(find.byKey(const Key('pagina_salir')));
    await tester.pump();
    expect(find.text('Falta confirmar'), findsNothing, reason: 'sin nada por confirmar sale derecho');
    await esperar(tester, () => find.byKey(const Key('pagina_pin')).evaluate().isNotEmpty, que: 'el PIN de nuevo');
    expect(tester.takeException(), isNull);
    await cerrar(tester, cliente);
  });

  testWidgets('SALIR IGUAL con algo por confirmar: sale, y lo dice cuando vuelve a entrar', (tester) async {
    final cliente =
        await abrir(tester, tamano: const Size(430, 2400), esperaDeRespuesta: const Duration(milliseconds: 400));
    await ponerPin(tester, cliente, '7777');
    await esperar(tester, () => find.byType(LasCajasScreen).evaluate().isNotEmpty, que: 'LAS CAJAS');
    notebook.traba = Completer<void>();
    await anularDesdeElIphone(tester);
    await esperar(tester, () => cliente.porConfirmar == 1, que: 'por confirmar');
    await tester.tap(find.byKey(const Key('pagina_salir')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('pagina_salir_igual')));
    await tester.pump();
    await esperar(tester, () => find.byKey(const Key('pagina_pin')).evaluate().isNotEmpty, que: 'el PIN de nuevo');
    expect(cliente.porConfirmar, 0);
    expect(cliente.noSeAnotaron.single, contains('se salió antes de que se confirmara'));
    await tester.runAsync(() async => notebook.traba!.complete());
    notebook.traba = null;
    await ponerPin(tester, cliente, '7777');
    await esperar(tester, () => find.byKey(const Key('pagina_no_se_anotaron')).evaluate().isNotEmpty,
        que: 'la franja roja al volver a entrar');
    expect(find.textContaining('Una anulación'), findsWidgets);
    await cerrar(tester, cliente);
  });

  testWidgets('lo por confirmar que la notebook al final no guarda: la franja roja lo dice hasta ENTENDIDO',
      (tester) async {
    final cliente =
        await abrir(tester, tamano: const Size(430, 2400), esperaDeRespuesta: const Duration(milliseconds: 400));
    await ponerPin(tester, cliente, '7777');
    await esperar(tester, () => find.byType(LasCajasScreen).evaluate().isNotEmpty, que: 'LAS CAJAS');
    notebook
      ..traba = Completer<void>()
      ..guarda = false;
    await anularDesdeElIphone(tester);
    // Primero se le acaba la espera a la pantalla; después contesta la notebook.
    await esperar(tester, () => find.textContaining('No lo repitas').evaluate().isNotEmpty, que: 'el aviso');
    await tester.runAsync(() async => notebook.traba!.complete());
    await esperar(tester, () => find.byKey(const Key('pagina_no_se_anotaron')).evaluate().isNotEmpty,
        que: 'la franja roja');
    expect(find.text('Una anulación no se anotó: No se pudo guardar en la notebook.'), findsOneWidget);
    expect(cliente.porConfirmar, 0);
    expect(notebook.anulacionesGuardadas, isEmpty);
    await tester.tap(find.byKey(const Key('pagina_entendido')));
    await tester.pump();
    expect(find.byKey(const Key('pagina_no_se_anotaron')), findsNothing);
    expect(tester.takeException(), isNull);
    await cerrar(tester, cliente);
  });
}
