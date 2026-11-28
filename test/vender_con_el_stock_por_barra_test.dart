// VENDER con el stock repartido por barra (28-nov-2026, para la Técnica del 4-dic):
// "Quedan" es lo de la barra de esta caja; **con señal, sin stock no se vende**; **sin
// señal avisa en rojo y deja vender**; "está en camino" y "Se repusieron…" con su OK.
// La cuenta es `StockParaVender`; acá, también montada en la pantalla de verdad.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_barra.dart';
import 'package:arguello_events/features/barra/cuentas/dia_de_operacion.dart';
import 'package:arguello_events/features/barra/cuentas/recetas_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/stock_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/stock_para_vender.dart';
import 'package:arguello_events/features/barra/cuentas/stock_por_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/widgets/tarjeta_producto.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/widgets/operational_sync_coordinator.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late ProductoBarra speed, cerveza, agua, vodka;
  late CajaBarra caja, cajaDeLaDos;

  /// Si esta caja ve la central: lo cambia cada prueba.
  var conSenial = true;

  BarraEnMemoria b() => prueba.barra;
  DateTime ahora() => b().reloj();

  Future<void> reparto(ProductoBarra p, String barra, int arranque, {int? aviso}) => b().guardarReparto(
        StockEnLaBarra.para(
          eventoId: fiesta.id,
          productoId: p.id,
          barra: barra,
          arranque: arranque,
          aviso: aviso,
          ahora: ahora(),
        ),
        quien: 'Jefe',
      );

  Future<void> vender(CajaBarra c, ProductoBarra p, int cantidad) => b().vender(
        caja: c,
        renglones: [RenglonVenta(productoId: p.id, nombre: p.nombre, precio: 5000, cantidad: cantidad)],
        medio: MedioBarra.efectivo,
        efectivo: 5000.0 * cantidad,
        quien: 'Marta',
      );

  Future<MovimientoDeStock> reponer(ProductoBarra p, String barra, int cantidad) => b().anotarMovimientoDeStock(
        MovimientoDeStock.reposicion(
          eventoId: fiesta.id,
          productoId: p.id,
          barra: barra,
          cantidad: cantidad,
          ahora: ahora(),
        ),
        quien: 'Nico',
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    conSenial = true;
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime.now().add(const Duration(days: 5)));
    prueba.eventos.add(fiesta);
    speed = b().producto('Speed', categoria: 'Sin alcohol');
    cerveza = b().producto('Cerveza lata', categoria: 'Cervezas');
    agua = b().producto('Agua', categoria: 'Sin alcohol');
    vodka = b().producto('Vodka con speed', categoria: 'Tragos');
    b().precio(fiesta.id, speed, 5000, orden: 0, stock: 40);
    b().precio(fiesta.id, cerveza, 4000, orden: 1, stock: 100);
    // El agua no se repartió: sigue con el stock general de siempre.
    b().precio(fiesta.id, agua, 2500, orden: 2, stock: 2);
    b().precio(fiesta.id, vodka, 9000, orden: 3);
    await reparto(speed, 'Barra 1', 3, aviso: 2);
    await reparto(speed, 'Barra 2', 10);
    await reparto(cerveza, 'Barra 1', 20, aviso: 5);
    await reparto(cerveza, 'Barra 2', 20);
    caja = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: _marta,
      operadorNombre: 'Marta',
      numeroCaja: 2,
      sede: 'Barra 1',
    );
    cajaDeLaDos = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'l',
      operadorNombre: 'Lu',
      numeroCaja: 7,
      sede: 'Barra 2',
    );
  });

  Future<ProviderContainer> abrir(WidgetTester tester, {Size tamano = const Size(1280, 800), CajaBarra? de}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        hayCentralALaVistaProvider.overrideWithValue((_) => conSenial),
      ],
      child: MaterialApp(home: VenderScreen(fiesta: fiesta, caja: de ?? caja)),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(VenderScreen)));
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          operadores.operadores.lista.single,
          const PermisosEfectivos(barra: true),
        );
    await tester.pumpAndSettle();
    return c;
  }

  /// Llegó algo de otro equipo (por la central o la nube): VENDER relee.
  Future<void> llego(WidgetTester tester, ProviderContainer c) async {
    c.read(operationalSyncRevisionProvider.notifier).bump();
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
  TarjetaProducto tarjeta(WidgetTester tester, ProductoBarra p) => tester.widget<TarjetaProducto>(
        find.ancestor(of: producto(p), matching: find.byType(TarjetaProducto)).first,
      );
  int? quedan(WidgetTester tester, ProductoBarra p) => tarjeta(tester, p).quedan;
  int enLaCuenta(WidgetTester tester, ProductoBarra p) => tarjeta(tester, p).cantidad;
  String texto(WidgetTester tester, String clave) => tester.widget<Text>(find.byKey(Key(clave))).data!;

  group('"Quedan" es lo de la barra de esta caja', () {
    testWidgets('lo repartido se cuenta en su barra; lo que vendió la otra barra no descuenta', (tester) async {
      await vender(cajaDeLaDos, speed, 4);
      await vender(caja, speed, 1);
      await abrir(tester);
      expect(quedan(tester, speed), 2, reason: 'arrancó con 3 y esta barra vendió 1');
      expect(quedan(tester, cerveza), 20);
      // La caja de la Barra 2 ve lo suyo.
      await abrir(tester, de: cajaDeLaDos);
      expect(quedan(tester, speed), 6);
    });

    testWidgets('lo que no se repartió sigue con el stock general, entre todas las cajas', (tester) async {
      await vender(cajaDeLaDos, agua, 1);
      await abrir(tester);
      expect(quedan(tester, agua), 1);
      expect(quedan(tester, vodka), isNull, reason: 'sin stock cargado no se controla');
    });

    testWidgets('el aviso de "queda poco" es el de la barra', (tester) async {
      await abrir(tester);
      expect(tarjeta(tester, speed).enAviso, isFalse, reason: 'quedan 3, avisa desde 2');
      await tocar(tester, producto(speed));
      expect(quedan(tester, speed), 2);
      expect(tarjeta(tester, speed).enAviso, isTrue);
    });

    testWidgets('una caja sin barra no frena por barra: usa el stock general', (tester) async {
      final sinBarra = await b().abrirCaja(
        eventoId: fiesta.id,
        operadorId: 'x',
        operadorNombre: 'Eva',
        numeroCaja: 3,
      );
      await abrir(tester, de: sinBarra);
      expect(quedan(tester, speed), 40);
    });
  });

  group('con señal, sin stock no se vende', () {
    testWidgets('al tocar lo que no queda sale el aviso con un solo botón y no se suma', (tester) async {
      await vender(caja, speed, 3);
      await abrir(tester);
      expect(quedan(tester, speed), 0);
      await tocar(tester, producto(speed));
      expect(find.byKey(const Key('sin_stock_no_se_vende')), findsOneWidget);
      expect(texto(tester, 'sin_stock_no_se_vende_texto'), contains('Sin stock no se vende'));
      expect(find.text('No queda speed en Barra 1'), findsOneWidget);
      expect(find.byKey(const Key('sin_stock_vender_igual')), findsNothing, reason: 'no hay "vender igual"');
      expect(find.byKey(const Key('sin_stock_sin_senial_vender')), findsNothing);
      await tocar(tester, find.byKey(const Key('sin_stock_entendido')));
      expect(enLaCuenta(tester, speed), 0);
      // Y vuelve a frenar cada vez: no queda "permitido" para esta cuenta.
      await tocar(tester, producto(speed));
      expect(find.byKey(const Key('sin_stock_no_se_vende')), findsOneWidget);
    });

    testWidgets('no deja sumar más de lo que queda en la barra', (tester) async {
      await abrir(tester);
      await tocar(tester, producto(speed), veces: 3);
      expect(enLaCuenta(tester, speed), 3);
      await tocar(tester, producto(speed));
      expect(find.byKey(const Key('sin_stock_no_se_vende')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('sin_stock_entendido')));
      expect(enLaCuenta(tester, speed), 3);
    });

    testWidgets('si el repositor ya avisó que va, el aviso lo dice', (tester) async {
      await vender(caja, speed, 3);
      await b().avisarQueVa(eventoId: fiesta.id, productoId: speed.id, barra: 'Barra 1', quien: 'Nico');
      await abrir(tester);
      await tocar(tester, producto(speed));
      expect(texto(tester, 'sin_stock_no_se_vende_texto'), contains('Nico ya está en camino'));
    });

    testWidgets('lo que no se repartió pregunta como siempre y deja vender igual', (tester) async {
      await vender(caja, agua, 2);
      await abrir(tester);
      await tocar(tester, producto(agua));
      expect(find.byKey(const Key('sin_stock')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('sin_stock_vender_igual')));
      expect(enLaCuenta(tester, agua), 1);
    });

    testWidgets('al cobrar, si otra caja de la barra vendió las últimas, no cobra', (tester) async {
      await abrir(tester);
      await tocar(tester, producto(speed), veces: 3);
      // Mientras tanto, otra caja de la misma barra vendió 2.
      final otra = await b().abrirCaja(
        eventoId: fiesta.id,
        operadorId: 'o',
        operadorNombre: 'Sol',
        numeroCaja: 1,
        sede: 'Barra 1',
      );
      await vender(otra, speed, 2);
      final antes = (await b().ventas(fiesta.id)).length;
      await tocar(tester, find.byKey(const Key('pagar_efectivo')));
      expect(find.byKey(const Key('no_alcanza_el_stock')), findsOneWidget);
      expect(texto(tester, 'no_alcanza_el_stock_texto'), contains('Speed: queda 1.'));
      expect(find.byKey(const Key('cobro_confirmar')), findsNothing, reason: 'no llega a la hoja del cobro');
      await tocar(tester, find.byKey(const Key('no_alcanza_entendido')));
      expect((await b().ventas(fiesta.id)).length, antes, reason: 'no se guardó ninguna venta');
    });

    testWidgets('con stock, cobra como siempre', (tester) async {
      await abrir(tester);
      await tocar(tester, producto(speed), veces: 2);
      await tocar(tester, find.byKey(const Key('pagar_efectivo')));
      expect(find.byKey(const Key('no_alcanza_el_stock')), findsNothing);
      expect(find.byKey(const Key('cobro_confirmar')), findsOneWidget);
    });
  });

  group('sin señal, avisa en rojo y deja vender', () {
    testWidgets('dice que no sabe si repusieron; con HAY, VENDER se suma y no vuelve a preguntar', (tester) async {
      conSenial = false;
      await vender(caja, speed, 3);
      await abrir(tester);
      await tocar(tester, producto(speed));
      expect(find.byKey(const Key('sin_stock_sin_senial')), findsOneWidget);
      expect(find.byKey(const Key('sin_stock_no_se_vende')), findsNothing);
      final aviso = tester.widget<Text>(find.byKey(const Key('sin_stock_sin_senial_texto')));
      expect(aviso.data, contains('no sé si repusieron'));
      final rojo = Theme.of(tester.element(find.byKey(const Key('sin_stock_sin_senial_texto')))).colorScheme.error;
      expect(aviso.style!.color, rojo);
      await tocar(tester, find.byKey(const Key('sin_stock_sin_senial_vender')));
      expect(enLaCuenta(tester, speed), 1);
      await tocar(tester, producto(speed));
      expect(find.byKey(const Key('sin_stock_sin_senial')), findsNothing, reason: 'una vez por producto y por cuenta');
      expect(enLaCuenta(tester, speed), 2);
    });

    testWidgets('con NO HAY no se suma', (tester) async {
      conSenial = false;
      await vender(caja, speed, 3);
      await abrir(tester);
      await tocar(tester, producto(speed));
      await tocar(tester, find.text('NO HAY'));
      expect(enLaCuenta(tester, speed), 0);
    });

    testWidgets('sin señal se cobra aunque la cuenta pase lo que queda, y el stock queda en negativo', (tester) async {
      conSenial = false;
      await vender(caja, speed, 3);
      await abrir(tester);
      await tocar(tester, producto(speed));
      await tocar(tester, find.byKey(const Key('sin_stock_sin_senial_vender')));
      await tocar(tester, producto(speed));
      await tocar(tester, find.byKey(const Key('pagar_efectivo')));
      expect(find.byKey(const Key('no_alcanza_el_stock')), findsNothing);
      await tocar(tester, find.byKey(const Key('cobro_confirmar')));
      final stock = StockPorBarra.deLaNoche(
        eventoId: fiesta.id,
        precios: await b().precios(fiesta.id),
        repartos: await b().repartos(fiesta.id),
        movimientos: await b().movimientosDeStock(fiesta.id),
        ventas: await b().ventas(fiesta.id),
        anulaciones: await b().anulaciones(fiesta.id),
        cajas: CajasPorDia.de(await b().cajas(fiesta.id)),
        dia: DiaDeOperacion.deLaCaja(caja),
      );
      expect(stock.en('Barra 1', speed.id)!.queda, -2, reason: 'se descuenta de lo que se reponga');
    });

    testWidgets('cuando vuelve la señal y sigue sin stock, frena de nuevo', (tester) async {
      conSenial = false;
      await vender(caja, speed, 3);
      await abrir(tester);
      await tocar(tester, producto(speed));
      await tocar(tester, find.byKey(const Key('sin_stock_sin_senial_vender')));
      conSenial = true;
      await tocar(tester, producto(speed));
      expect(find.byKey(const Key('sin_stock_no_se_vende')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('sin_stock_entendido')));
      await tocar(tester, find.byKey(const Key('pagar_efectivo')));
      expect(find.byKey(const Key('no_alcanza_el_stock')), findsOneWidget, reason: 'con señal no cobra lo que no hay');
    });
  });

  group('lo del repositor llega al toque', () {
    testWidgets('"está en camino" aparece cuando avisa y se va cuando repone', (tester) async {
      final c = await abrir(tester);
      expect(find.byKey(Key('vender_en_camino_${speed.id}')), findsNothing);
      final aviso = await b().avisarQueVa(eventoId: fiesta.id, productoId: speed.id, barra: 'Barra 1', quien: 'Nico');
      await llego(tester, c);
      expect(texto(tester, 'vender_en_camino_${speed.id}'), 'Nico está en camino con speed');
      await b().anotarMovimientoDeStock(
        MovimientoDeStock.reposicion(
          eventoId: fiesta.id,
          productoId: speed.id,
          barra: 'Barra 1',
          cantidad: 12,
          respondeA: aviso.id,
          ahora: ahora(),
        ),
        quien: 'Nico',
      );
      await llego(tester, c);
      expect(find.byKey(Key('vender_en_camino_${speed.id}')), findsNothing);
    });

    testWidgets('el "voy en camino" a la otra barra no se muestra acá', (tester) async {
      await b().avisarQueVa(eventoId: fiesta.id, productoId: speed.id, barra: 'Barra 2', quien: 'Nico');
      await abrir(tester);
      expect(find.byKey(Key('vender_en_camino_${speed.id}')), findsNothing);
    });

    testWidgets('"Se repusieron…" sale al llegar la reposición, con cuánto queda, y se va con OK', (tester) async {
      await vender(caja, speed, 3);
      final c = await abrir(tester);
      expect(quedan(tester, speed), 0);
      final m = await reponer(speed, 'Barra 1', 12);
      await llego(tester, c);
      expect(texto(tester, 'vender_repuesto_${m.id}'), 'Se repusieron 12 speed en tu barra · quedan 12 · Nico');
      expect(quedan(tester, speed), 12);
      // Ya se puede vender sin ningún aviso.
      await tocar(tester, producto(speed));
      expect(find.byKey(const Key('sin_stock_no_se_vende')), findsNothing);
      expect(enLaCuenta(tester, speed), 1);
      await tocar(tester, find.byKey(Key('vender_repuesto_ok_${m.id}')));
      expect(find.byKey(Key('vender_repuesto_${m.id}')), findsNothing);
      // Y no vuelve a salir cuando baja otra cosa.
      await llego(tester, c);
      expect(find.byKey(Key('vender_repuesto_${m.id}')), findsNothing);
    });

    testWidgets('lo repuesto antes de abrir VENDER no se avisa, ni lo de la otra barra', (tester) async {
      final vieja = await reponer(speed, 'Barra 1', 5);
      final c = await abrir(tester);
      expect(find.byKey(Key('vender_repuesto_${vieja.id}')), findsNothing);
      final ajena = await reponer(speed, 'Barra 2', 5);
      await llego(tester, c);
      expect(find.byKey(Key('vender_repuesto_${ajena.id}')), findsNothing);
    });

    testWidgets('lo vendido sin stock se descuenta de lo repuesto: 24 − 5 = quedan 19', (tester) async {
      conSenial = false;
      await vender(caja, speed, 8); // 3 había: 5 de más
      final c = await abrir(tester);
      final m = await reponer(speed, 'Barra 1', 24);
      await llego(tester, c);
      expect(texto(tester, 'vender_repuesto_${m.id}'), contains('quedan 19'));
      expect(quedan(tester, speed), 19);
    });

    testWidgets('en un celular los avisos no desbordan', (tester) async {
      final c = await abrir(tester, tamano: const Size(360, 740));
      await b().avisarQueVa(eventoId: fiesta.id, productoId: cerveza.id, barra: 'Barra 1', quien: 'Nico');
      await reponer(speed, 'Barra 1', 12);
      await llego(tester, c);
      expect(tester.takeException(), isNull);
      expect(find.byKey(Key('vender_en_camino_${cerveza.id}')), findsOneWidget);
    });
  });

  group('la cuenta, sin pantalla (StockParaVender)', () {
    StockParaVender armar({
      Map<String, int> general = const {},
      Map<String, int> enLaBarra = const {},
      RecetasDeLaBarra recetas = RecetasDeLaBarra.ninguna,
      Map<String, int> vendidoEnLaBarra = const {},
    }) {
      final t = DateTime.utc(2026, 12, 5, 2);
      final precios = [
        for (final e in general.entries)
          PrecioBarra.para(eventoId: 'f', productoId: e.key, precio: 1000, stockInicial: e.value, ahora: t),
      ];
      final cajaUno = CajaBarra.abrir(
        eventoId: 'f',
        operadorId: 'm',
        operadorNombre: 'Marta',
        numeroCaja: 1,
        sede: 'Barra 1',
        ahora: t,
      );
      final ventas = [
        for (final e in vendidoEnLaBarra.entries)
          VentaBarra.nueva(
            cajaBarraId: cajaUno.id,
            eventoId: 'f',
            numero: 1,
            renglones: [RenglonVenta(productoId: e.key, nombre: e.key, precio: 1000, cantidad: e.value)],
            medio: MedioBarra.efectivo,
            efectivo: 1000.0 * e.value,
            ahora: t,
          ),
      ];
      final cajas = CajasPorDia.de([cajaUno]);
      final dia = DiaDeOperacion.de(t);
      return StockParaVender(
        general: StockDeLaBarra.deLaNoche(
          eventoId: 'f',
          precios: precios,
          ventas: recetas.paraElStock(ventas),
          anulaciones: const [],
          cajas: cajas,
          dia: dia,
        ),
        porBarra: StockPorBarra.deLaNoche(
          eventoId: 'f',
          precios: precios,
          repartos: [
            for (final e in enLaBarra.entries)
              StockEnLaBarra.para(eventoId: 'f', productoId: e.key, barra: 'Barra 1', arranque: e.value, ahora: t),
          ],
          movimientos: const [],
          ventas: recetas.paraElStock(ventas),
          anulaciones: const [],
          cajas: cajas,
          dia: dia,
        ),
        barra: 'Barra 1',
        recetas: recetas,
      );
    }

    CuentaBarra cuenta(Map<String, int> de) {
      var c = CuentaBarra.vacia;
      for (final e in de.entries) {
        for (var i = 0; i < e.value; i++) {
          c = c.sumar(productoId: e.key, nombre: e.key, precio: 1000);
        }
      }
      return c;
    }

    test('sin nada cargado no frena nada', () {
      expect(StockParaVender.nada.quedan('x', CuentaBarra.vacia), isNull);
      expect(StockParaVender.nada.alSumar('x', CuentaBarra.vacia, conSenial: true), FrenoDeStock.ninguno);
      expect(StockParaVender.nada.noAlcanzaPara(cuenta({'x': 9})), isEmpty);
    });

    test('lo repartido frena por la barra; lo demás, pregunta', () {
      final s = armar(general: {'speed': 40, 'agua': 1}, enLaBarra: {'speed': 2}, vendidoEnLaBarra: {'agua': 1});
      expect(s.alSumar('speed', cuenta({'speed': 1}), conSenial: true), FrenoDeStock.ninguno);
      expect(s.alSumar('speed', cuenta({'speed': 2}), conSenial: true), FrenoDeStock.noSeVende);
      expect(s.alSumar('speed', cuenta({'speed': 2}), conSenial: false), FrenoDeStock.sinSenial);
      expect(s.alSumar('agua', CuentaBarra.vacia, conSenial: true), FrenoDeStock.pregunta);
      expect(s.alSumar('agua', CuentaBarra.vacia, conSenial: false), FrenoDeStock.pregunta);
    });

    test('al cobrar dice de qué no alcanza y cuántas quedan, solo de lo repartido', () {
      final s = armar(
        general: {'speed': 40, 'agua': 1},
        enLaBarra: {'speed': 2},
        vendidoEnLaBarra: {'speed': 1},
      );
      expect(s.noAlcanzaPara(cuenta({'speed': 1, 'agua': 5})), isEmpty);
      expect(s.noAlcanzaPara(cuenta({'speed': 2})), {'speed': 1});
      final enCero = armar(general: {'speed': 40}, enLaBarra: {'speed': 2}, vendidoEnLaBarra: {'speed': 5});
      expect(enCero.quedaSolo('speed'), -3);
      expect(enCero.noAlcanzaPara(cuenta({'speed': 1})), {'speed': 0}, reason: 'nunca dice "quedan -3"');
    });
  });

  testWidgets('la cajera sigue sin ver plata ni nada del jefe en los avisos del stock', (tester) async {
    await vender(caja, speed, 3);
    final c = await abrir(tester);
    await b().avisarQueVa(eventoId: fiesta.id, productoId: speed.id, barra: 'Barra 1', quien: 'Nico');
    final m = await reponer(cerveza, 'Barra 1', 12);
    await llego(tester, c);
    for (final clave in ['vender_en_camino_${speed.id}', 'vender_repuesto_${m.id}']) {
      final t = texto(tester, clave);
      expect(t.contains(r'$'), isFalse, reason: t);
      expect(t.toLowerCase().contains('depósito'), isFalse, reason: t);
    }
  });
}
