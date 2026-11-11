import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/cuentas/pedido_de_cierre.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/barra/widgets/cerrar_caja_barra_screen.dart';
import 'package:arguello_events/features/barra/widgets/ok_del_cierre.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// La etapa 6 de la barra, de punta a punta en la pantalla de verdad: desde el inicio, la
/// cajera entra a su caja, toca el candado, cuenta **a ciegas** (sin ver ninguna plata),
/// confirma, y recién ahí ve lo esperado, la diferencia y el cierre entero como el papel,
/// con el historial. Sale el papel por la térmica (sin historial), se guarda el PDF, se
/// agrega una nota, y al volver la caja ya no está abierta.
///
/// Desde el 11-nov-2026 **la caja se cierra cuando la encargada acepta**: entre contar y
/// el cierre, la cajera espera el OK (sin ver ninguna plata).
const _marta = 'a0000000-0000-4000-8000-000000000001';
const _romi = 'a0000000-0000-4000-8000-000000000002';
const _lucas = 'a0000000-0000-4000-8000-000000000003';

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late CajaBarra caja;
  late VentaBarra cervezas, fernet, anulada;

  /// La hora de la tablet de la cajera: las ventas son de las 2, y pide cerrar a las 8.
  late DateTime ahora;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    // Romi es la encargada de barra; Lucas, otro cajero.
    operadores.operadores.lista.add(operadorDePrueba(_romi, 'Romi', '7777'));
    operadores.operadores.lista.add(operadorDePrueba(_lucas, 'Lucas', '4444'));
    operadores.permisos.poner(_romi, const PermisosEfectivos(barra: true, encargadaBarra: true));
    operadores.permisos.poner(_lucas, const PermisosEfectivos(barra: true));
    ahora = DateTime.utc(2026, 12, 5, 8);
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', DateTime.now().add(const Duration(days: 5)));
    prueba.eventos.add(fiesta);
    final b = prueba.barra;
    final cerveza = b.producto('Cerveza lata', categoria: 'Cervezas');
    final fer = b.producto('Fernet con coca', categoria: 'Tragos');
    final agua = b.producto('Agua sin gas', categoria: 'Sin alcohol');
    b.precio(fiesta.id, cerveza, 3500);
    b.precio(fiesta.id, fer, 6000);
    b.precio(fiesta.id, agua, 1000);
    final abierta = await b.abrirCaja(eventoId: fiesta.id, operadorId: _marta, operadorNombre: 'Marta', numeroCaja: 2);
    caja = await b.ponerCambio(abierta, 20000, quien: 'Marta');
    RenglonVenta r(ProductoBarra p, double precio, int n) =>
        RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: n);
    cervezas = await b.vender(
      caja: caja,
      renglones: [r(cerveza, 3500, 2)],
      medio: MedioBarra.efectivo,
      efectivo: 7000,
      quien: 'Marta',
    );
    fernet = await b.vender(
      caja: caja,
      renglones: [r(fer, 6000, 1)],
      medio: MedioBarra.transferencia,
      transferencia: 6000,
      quien: 'Marta',
    );
    anulada = await b.vender(
      caja: caja,
      renglones: [r(agua, 1000, 3)],
      medio: MedioBarra.efectivo,
      efectivo: 3000,
      quien: 'Marta',
    );
    await b.anular(anulada, motivo: 'se cobró dos veces', quien: 'Marta');
    // Esperado: 20.000 de cambio + 7.000 en efectivo (la anulada no cuenta) = 27.000.
  });

  /// Entra Marta, la cajera. Con [encargada], Marta es además la encargada de barra.
  Future<void> abrir(
    WidgetTester tester, {
    Size tamano = const Size(1280, 800),
    bool encargada = false,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        // El aviso de la encargada lee la barra del equipo: la de la prueba, nunca la base.
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        ahoraEnLaBarraProvider.overrideWithValue(() => ahora),
        sonarPedidoDeCierreProvider.overrideWithValue(() {}),
      ],
      child: const MaterialApp(home: BarraHomeScreen()),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(BarraHomeScreen)));
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          operadores.operadores.lista.first,
          PermisosEfectivos(barra: true, encargadaBarra: encargada),
        );
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Finder porClave(String k) => find.byKey(Key(k));
  bool prendido(WidgetTester tester, String clave) =>
      tester.widget<ButtonStyleButton>(porClave(clave)).onPressed != null;
  String texto(WidgetTester tester, String clave) => tester.widget<Text>(porClave(clave)).data!;
  CajaBarra guardada() => prueba.barra.cajasGuardadas.single;

  /// Del inicio a la pantalla de contar.
  Future<void> irACerrar(WidgetTester tester) async {
    await tocar(tester, porClave('barra_fiesta_${fiesta.id}'));
    expect(find.byType(VenderScreen), findsOneWidget, reason: 'retoma su caja abierta');
    await tocar(tester, porClave('vender_cerrar'));
    expect(find.byType(CerrarCajaBarraScreen), findsOneWidget);
  }

  List<PasoDelCierre> pasos() => prueba.barra.pasosGuardados;
  PasoDelCierre elPedido() => pasos().lastWhere((p) => p.esPedido);

  /// Pasa la vuelta del vigía: la tablet mira su base cada pocos segundos.
  Future<void> unaVuelta(WidgetTester tester) async {
    await tester.pump(kMirarPedidosDeCierre + const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  /// La encargada contesta **desde su aparato**: su fila le llega a esta tablet por la
  /// red del salón (o baja de la nube), y la tablet la ve en la vuelta siguiente.
  Future<void> contestaLaEncargada(WidgetTester tester, TipoPasoDelCierre tipo) async {
    final respuesta = PasoDelCierre.responder(
      pedido: elPedido(),
      tipo: tipo,
      hechoPor: 'Romi',
      // El reloj del otro aparato no coincide con el de esta tablet.
      ahora: DateTime.utc(2026, 12, 5, 7, 40),
    ).conEquipo('tablet-de-romi');
    expect(await prueba.barra.guardarDeOtroEquipo('barra_cierres', respuesta.toMap()), isTrue);
    await unaVuelta(tester);
  }

  /// Cuenta y pide el cierre: queda esperando a la encargada.
  Future<void> contarYPedir(WidgetTester tester, String contado) async {
    await tester.enterText(porClave('cierre_contado'), contado);
    await tester.pumpAndSettle();
    await tocar(tester, porClave('cierre_cerrar'));
    await tocar(tester, porClave('cierre_confirmar'));
  }

  /// Cuenta, pide el cierre y la encargada acepta desde su aparato.
  Future<void> contarYCerrar(WidgetTester tester, String contado) async {
    await contarYPedir(tester, contado);
    expect(porClave('cierre_esperando'), findsOneWidget);
    await contestaLaEncargada(tester, TipoPasoDelCierre.ok);
  }

  testWidgets('de punta a punta: contar a ciegas, cerrar, ver el cierre, nota, papel, PDF y volver',
      (tester) async {
    await abrir(tester);
    await irACerrar(tester);

    // 1. A ciegas: ninguna plata de la caja a la vista.
    for (final plata in ['27.000', '20.000', '7.000', '6.000', '13.000']) {
      expect(find.textContaining(plata), findsNothing, reason: 'antes de contar se ve $plata');
    }
    expect(prendido(tester, 'cierre_cerrar'), isFalse, reason: 'sin un número no se cierra');

    await tester.enterText(porClave('cierre_contado'), '26500');
    await tester.pumpAndSettle();
    await tocar(tester, porClave('cierre_cerrar'));
    expect(texto(tester, 'cierre_contado_grande'), r'$ 26.500', reason: 'confirma viendo el número grande');
    expect(guardada().abierta, isTrue, reason: 'todavía no cerró');
    expect(texto(tester, 'cierre_que_pasa'), contains('se le pide el cierre a la encargada'));
    await tocar(tester, porClave('cierre_confirmar'));

    // 2. Espera a la encargada: el pedido quedó anotado y sube, la caja sigue abierta y
    // la cajera sigue sin ver ninguna plata.
    expect(texto(tester, 'cierre_esperando_titulo'), 'Esperá a la encargada');
    expect(guardada().abierta, isTrue, reason: 'se cierra recién con el OK');
    expect(elPedido().efectivoContado, 26500);
    expect(elPedido().cajaBarraId, caja.id);
    expect(elPedido().hechoPor, 'Marta');
    expect(prueba.subidasDeLaBarra, contains('barra_cierres ${elPedido().id}'));
    for (final plata in ['27.000', '26.500', '20.000', '7.000', '6.000', '13.000']) {
      expect(find.textContaining(plata), findsNothing, reason: 'esperando se ve $plata');
    }
    await unaVuelta(tester);
    expect(guardada().abierta, isTrue, reason: 'sin respuesta no pasa nada');
    expect(porClave('cierre_esperando'), findsOneWidget);

    // La encargada acepta desde su aparato: esta tablet cierra la caja.
    await contestaLaEncargada(tester, TipoPasoDelCierre.ok);

    // 3. Cerrada, con lo contado y la diferencia, quién aceptó, y sube.
    expect(guardada().abierta, isFalse);
    expect(guardada().notaCierre, 'Aceptó: Romi');
    expect(guardada().efectivoContado, 26500);
    expect(guardada().diferencia, -500);
    expect(prueba.subidasDeLaBarra, contains('barra_cajas ${caja.id}'));

    // El papel de la térmica: el cierre CORTO, por categoría y sin el historial
    // (11-nov): no lleva un renglón por bebida, así no crece con las ventas.
    final papel = prueba.papel.papeles.last;
    expect(papel, containsAllInOrder(['JUNIOR EVENTOS', 'CIERRE DE CAJA - BARRA', r'Faltan $ 500']));
    expect(papel, isNot(contains('HISTORIAL')));
    final izquierdas = [
      for (final r in prueba.papel.enCrudo.last.whereType<RenglonTicket>()) r.izquierda,
    ];
    expect(izquierdas, containsAllInOrder(['2 x Cervezas', '1 x Tragos', 'Ventas']));
    expect(izquierdas, isNot(contains('2 x Cerveza lata')));
    expect(izquierdas, isNot(contains('1 x Fernet con coca')));
    // En la pantalla sí está cada bebida: el detalle se mira ahí.
    expect(
      find.descendant(of: porClave('cierre_papel'), matching: find.text('2 x Cerveza lata')),
      findsOneWidget,
    );
    expect(prueba.papel.enCrudo.last.whereType<LogoTicket>(), isEmpty);
    expect(texto(tester, 'cierre_aviso'), 'Caja cerrada. Salió el papel del cierre.');

    // En la pantalla: lo esperado, la diferencia y el papel con el historial.
    expect(texto(tester, 'cierre_esperado'), r'Tenía que haber $ 27.000');
    expect(texto(tester, 'cierre_diferencia'), r'Faltan $ 500');
    expect(find.descendant(of: porClave('cierre_papel'), matching: find.text('HISTORIAL')), findsOneWidget);
    expect(
      find.descendant(of: porClave('cierre_papel'), matching: find.textContaining('ANULADA')),
      findsOneWidget,
      reason: 'la anulada, marcada en el historial',
    );

    // La nota: lo único que cambia después.
    await tocar(tester, porClave('cierre_anotar'));
    await tester.enterText(porClave('motivo_texto'), 'faltó un billete de 500');
    await tester.pumpAndSettle();
    await tocar(tester, porClave('nota_guardar'));
    // La nota de la cajera va adelante, y quién aceptó no se pierde.
    expect(guardada().notaCierre, 'faltó un billete de 500 · Aceptó: Romi');
    expect(guardada().efectivoContado, 26500, reason: 'lo contado no cambia');
    expect(guardada().diferencia, -500);
    expect(
      find.descendant(of: porClave('cierre_papel'), matching: find.textContaining('Nota: faltó un billete de 500')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: porClave('cierre_papel'), matching: find.textContaining('Aceptó: Romi')),
      findsOneWidget,
    );

    await tocar(tester, porClave('cierre_imprimir'));
    expect(prueba.papel.papeles.last.join(' '), contains('Nota: faltó un billete de 500'));
    expect(prueba.papel.papeles.last.join(' '), contains('Aceptó: Romi'));

    // El PDF: con el historial.
    await tocar(tester, porClave('cierre_pdf'));
    final pdf = prueba.pdfs.single;
    expect(pdf.nombre, startsWith('cierre_barra_PUERTO_VIEJO_caja2_'));
    expect(pdf.nombre, endsWith('.pdf'));
    expect(pdf.lineas.whereType<TextoTicket>().map((t) => t.texto), contains('HISTORIAL'));

    // LISTO: VENDER también se va, y la caja ya no se retoma.
    await tocar(tester, porClave('cierre_listo'));
    expect(find.byType(VenderScreen), findsNothing);
    expect(find.byType(BarraHomeScreen), findsOneWidget);
    await tocar(tester, porClave('barra_fiesta_${fiesta.id}'));
    expect(porClave('caja_abrir'), findsOneWidget, reason: 'pide abrir otra caja');
  });

  testWidgets('volver a contar no cierra nada', (tester) async {
    await abrir(tester);
    await irACerrar(tester);
    await tester.enterText(porClave('cierre_contado'), '27000');
    await tester.pumpAndSettle();
    await tocar(tester, porClave('cierre_cerrar'));
    await tocar(tester, find.text('VOLVER A CONTAR'));
    expect(guardada().abierta, isTrue);
    expect(prueba.papel.papeles, isEmpty);
    expect(prueba.subidasDeLaBarra, isEmpty);
  });

  testWidgets('justo: lo dice; y con el cambio puesto después de abrir, cuenta igual', (tester) async {
    await abrir(tester);
    await irACerrar(tester);
    await contarYCerrar(tester, '27000');
    expect(texto(tester, 'cierre_diferencia'), 'Justo, sin diferencia');
    expect(guardada().diferencia, 0);
  });

  testWidgets('sin impresora la caja igual se cierra, y lo dice', (tester) async {
    prueba.papel.anda = false;
    await abrir(tester);
    await irACerrar(tester);
    await contarYCerrar(tester, '27500');
    expect(guardada().abierta, isFalse);
    expect(guardada().diferencia, 500);
    expect(texto(tester, 'cierre_aviso'), contains('Caja cerrada. No salió el papel.'));
    expect(texto(tester, 'cierre_diferencia'), r'Sobran $ 500');
  });

  testWidgets('cerrada, volver atrás es como LISTO: vuelve al inicio', (tester) async {
    await abrir(tester);
    await irACerrar(tester);
    await contarYCerrar(tester, '27000');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(VenderScreen), findsNothing);
    expect(find.byType(BarraHomeScreen), findsOneWidget);
  });

  testWidgets('antes de cerrar, volver atrás vuelve a VENDER con la caja abierta', (tester) async {
    await abrir(tester);
    await irACerrar(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(VenderScreen), findsOneWidget);
    expect(guardada().abierta, isTrue);
  });

  for (final (nombre, tamano) in [
    ('un celular', const Size(360, 740)),
    ('una tablet parada', const Size(800, 1280)),
    ('una tablet acostada', const Size(1280, 800)),
  ]) {
    testWidgets('en $nombre no se desborda, contando y con el cierre', (tester) async {
      await abrir(tester, tamano: tamano);
      await irACerrar(tester);
      expect(tester.takeException(), isNull);
      await contarYCerrar(tester, '26500');
      expect(tester.takeException(), isNull);
      expect(porClave('cierre_papel'), findsOneWidget);
    });
  }

  // ── El OK de la encargada (11-nov-2026) ─────────────────────────────────────

  group('la caja se cierra cuando la encargada acepta', () {
    testWidgets('si pide que cuente de nuevo, vuelve a contar sin ver ninguna plata', (tester) async {
      await abrir(tester);
      await irACerrar(tester);
      await contarYPedir(tester, '26500');
      await contestaLaEncargada(tester, TipoPasoDelCierre.recontar);
      expect(porClave('cierre_esperando'), findsNothing);
      expect(texto(tester, 'cierre_aviso'), 'La encargada pide que cuentes de nuevo.');
      expect(guardada().abierta, isTrue);
      expect(tester.widget<TextField>(porClave('cierre_contado')).controller!.text, isEmpty);
      for (final plata in ['27.000', '26.500', '20.000']) {
        expect(find.textContaining(plata), findsNothing, reason: 'al recontar se ve $plata');
      }
      // Cuenta de nuevo: es otro pedido, y ese sí se acepta.
      ahora = ahora.add(const Duration(minutes: 4));
      await contarYCerrar(tester, '27000');
      expect(guardada().abierta, isFalse);
      expect(guardada().efectivoContado, 27000);
      expect(pasos().where((p) => p.esPedido), hasLength(2));
    });

    testWidgets('VOLVER A VENDER cancela el pedido y la caja sigue abierta', (tester) async {
      await abrir(tester);
      await irACerrar(tester);
      await contarYPedir(tester, '27000');
      await tocar(tester, porClave('cierre_volver_a_vender'));
      expect(find.byType(VenderScreen), findsOneWidget);
      expect(find.byType(CerrarCajaBarraScreen), findsNothing);
      expect(guardada().abierta, isTrue);
      expect(pasos().last.tipo, TipoPasoDelCierre.cancelado);
      expect(pasos().last.pedidoId, elPedido().id);
      // Un ok que llega tarde ya no cierra nada.
      await contestaLaEncargada(tester, TipoPasoDelCierre.ok);
      expect(guardada().abierta, isTrue);
    });

    testWidgets('esperando, volver atrás es VOLVER A VENDER: el pedido no queda en pie', (tester) async {
      await abrir(tester);
      await irACerrar(tester);
      await contarYPedir(tester, '27000');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(VenderScreen), findsOneWidget);
      expect(pasos().last.tipo, TipoPasoDelCierre.cancelado);
    });

    testWidgets('CERRAR SIN ESPERAR: recién a los 3 minutos, con motivo, y queda marcado', (tester) async {
      await abrir(tester);
      await irACerrar(tester);
      await contarYPedir(tester, '26500');
      expect(prendido(tester, 'cierre_sin_esperar'), isFalse);
      expect(texto(tester, 'cierre_sin_esperar_cuando'), 'Se puede en 3:00, si la encargada no contesta.');

      ahora = ahora.add(const Duration(minutes: 2));
      await unaVuelta(tester);
      expect(prendido(tester, 'cierre_sin_esperar'), isFalse);
      expect(texto(tester, 'cierre_sin_esperar_cuando'), 'Se puede en 1:00, si la encargada no contesta.');

      ahora = ahora.add(const Duration(minutes: 1));
      await unaVuelta(tester);
      expect(prendido(tester, 'cierre_sin_esperar'), isTrue);
      await tocar(tester, porClave('cierre_sin_esperar'));
      expect(guardada().abierta, isTrue, reason: 'sin motivo no cierra');
      await tester.enterText(porClave('motivo_texto'), 'no hay encargada esta noche');
      await tester.pumpAndSettle();
      await tocar(tester, porClave('sin_ok_cerrar'));

      expect(guardada().abierta, isFalse);
      expect(guardada().efectivoContado, 26500);
      expect(guardada().diferencia, -500);
      expect(guardada().notaCierre, 'Cerró sin el OK de la encargada: no hay encargada esta noche');
      expect(pasos().last.tipo, TipoPasoDelCierre.sinOk);
      expect(PedidoDeCierre.cerraronSinOk(pasos()), {caja.id});
      expect(texto(tester, 'cierre_diferencia'), r'Faltan $ 500');
    });

    testWidgets('LA ENCARGADA ESTÁ ACÁ: con su PIN ve los totales y acepta en esta tablet', (tester) async {
      await abrir(tester);
      await irACerrar(tester);
      await contarYPedir(tester, '26500');

      // Un PIN que no es de nadie, y el de un cajero común: ninguno sirve.
      await tocar(tester, porClave('cierre_encargada_aca'));
      await tester.enterText(porClave('pin_encargada'), '0000');
      await tocar(tester, porClave('pin_seguir'));
      expect(texto(tester, 'cierre_aviso'), 'Ese PIN no es de nadie.');
      await tocar(tester, porClave('cierre_encargada_aca'));
      await tester.enterText(porClave('pin_encargada'), '4444');
      await tocar(tester, porClave('pin_seguir'));
      expect(texto(tester, 'cierre_aviso'), 'Ese PIN no es de una encargada de barra.');
      expect(find.byType(OkDelCierreDialog), findsNothing);
      expect(guardada().abierta, isTrue);

      // El de la encargada: ahí sí se ven los totales.
      await tocar(tester, porClave('cierre_encargada_aca'));
      await tester.enterText(porClave('pin_encargada'), '7777');
      await tocar(tester, porClave('pin_seguir'));
      expect(texto(tester, 'ok_cierre_titulo'), 'La Caja 2 (Marta) pide cerrar');
      expect(texto(tester, 'ok_cierre_ventas'), '2 ventas');
      expect(texto(tester, 'ok_cierre_esperado'), r'$ 27.000');
      expect(texto(tester, 'ok_cierre_conto'), r'$ 26.500');
      expect(texto(tester, 'ok_cierre_diferencia'), r'Faltan $ 500');
      expect(texto(tester, 'ok_cierre_transferencia'), r'$ 6.000');
      expect(texto(tester, 'ok_cierre_total'), r'$ 13.000');
      await tocar(tester, porClave('ok_cierre_aceptar'));

      expect(guardada().abierta, isFalse);
      expect(guardada().notaCierre, 'Aceptó: Romi');
      expect(pasos().last.tipo, TipoPasoDelCierre.ok);
      expect(pasos().last.hechoPor, 'Romi');
      expect(prueba.subidasDeLaBarra, contains('barra_cierres ${pasos().last.id}'));
    });

    testWidgets('la encargada, con su PIN en esta tablet, también puede pedir que cuente de nuevo', (tester) async {
      await abrir(tester);
      await irACerrar(tester);
      await contarYPedir(tester, '20000');
      await tocar(tester, porClave('cierre_encargada_aca'));
      await tester.enterText(porClave('pin_encargada'), '7777');
      await tocar(tester, porClave('pin_seguir'));
      await tocar(tester, porClave('ok_cierre_recontar'));
      expect(guardada().abierta, isTrue);
      expect(pasos().last.tipo, TipoPasoDelCierre.recontar);
      expect(texto(tester, 'cierre_aviso'), 'La encargada pide que cuentes de nuevo.');
    });

    testWidgets('si vuelve a entrar con el pedido en pie, sigue esperando', (tester) async {
      // La app se cerró mientras esperaba: el pedido está en la base.
      await prueba.barra.anotarPasoDelCierre(PasoDelCierre.pedir(
        caja: caja,
        efectivoContado: 27000,
        hechoPor: 'Marta',
        ahora: ahora,
      ));
      await abrir(tester);
      await irACerrar(tester);
      expect(porClave('cierre_esperando'), findsOneWidget);
      expect(porClave('cierre_contado'), findsNothing);
      await contestaLaEncargada(tester, TipoPasoDelCierre.ok);
      expect(guardada().abierta, isFalse);
      expect(guardada().efectivoContado, 27000);
    });

    testWidgets('si vendió después de pedir el cierre, ese conteo no sirve: cuenta de nuevo', (tester) async {
      await prueba.barra.anotarPasoDelCierre(PasoDelCierre.pedir(
        caja: caja,
        efectivoContado: 27000,
        hechoPor: 'Marta',
        ahora: ahora,
      ));
      // Una venta más tarde que el pedido (la app se había cerrado y siguió vendiendo).
      prueba.barra.reloj = () => ahora.add(const Duration(minutes: 10));
      final cerveza = prueba.barra.productosGuardados.first;
      await prueba.barra.vender(
        caja: caja,
        renglones: [RenglonVenta(productoId: cerveza.id, nombre: cerveza.nombre, precio: 3500, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 3500,
        quien: 'Marta',
      );
      await abrir(tester);
      await irACerrar(tester);
      await contestaLaEncargada(tester, TipoPasoDelCierre.ok);
      expect(guardada().abierta, isTrue, reason: 'no cierra con un conteo viejo');
      expect(texto(tester, 'cierre_aviso'), 'Hubo ventas después de pedir el cierre: contá de nuevo.');
      expect(pasos().last.tipo, TipoPasoDelCierre.cancelado);
    });

    /// Lucas, en otra tablet, contó y pide cerrar su Caja 3: el pedido llegó a este equipo.
    Future<CajaBarra> lucasPideCerrar() async {
      final suCaja = CajaBarra.abrir(
        eventoId: fiesta.id,
        operadorId: _lucas,
        operadorNombre: 'Lucas',
        numeroCaja: 3,
        ahora: DateTime.utc(2026, 12, 5, 1),
      );
      await prueba.barra.guardarDeOtroEquipo('barra_cajas', suCaja.toMap());
      final pedido = PasoDelCierre.pedir(
        caja: suCaja,
        efectivoContado: 0,
        hechoPor: 'Lucas',
        ahora: DateTime.utc(2026, 12, 5, 8),
      ).conEquipo('tablet-de-lucas');
      await prueba.barra.guardarDeOtroEquipo('barra_cierres', pedido.toMap());
      return suCaja;
    }

    testWidgets('vendiendo, a una cajera común no le aparece el pedido de otra caja', (tester) async {
      final deLucas = await lucasPideCerrar();
      await abrir(tester);
      await tocar(tester, porClave('barra_fiesta_${fiesta.id}'));
      expect(find.byType(VenderScreen), findsOneWidget);
      await unaVuelta(tester);
      expect(porClave('aviso_cierres'), findsNothing);
      expect(porClave('aviso_cierre_${deLucas.id}'), findsNothing);
    });

    testWidgets('vendiendo, a la encargada le salta el pedido de la otra caja y lo acepta ahí', (tester) async {
      final deLucas = await lucasPideCerrar();
      await abrir(tester, encargada: true);
      await tocar(tester, porClave('barra_fiesta_${fiesta.id}'));
      expect(find.byType(VenderScreen), findsOneWidget);
      expect(find.text('La Caja 3 (Lucas) pide cerrar'), findsOneWidget);
      await tocar(tester, porClave('aviso_cierre_ver_${deLucas.id}'));
      expect(texto(tester, 'ok_cierre_titulo'), 'La Caja 3 (Lucas) pide cerrar');
      await tocar(tester, porClave('ok_cierre_aceptar'));
      expect(pasos().last.tipo, TipoPasoDelCierre.ok);
      expect(pasos().last.cajaBarraId, deLucas.id);
      expect(pasos().last.hechoPor, 'Marta', reason: 'en esta prueba la encargada es Marta');
      expect(porClave('aviso_cierre_${deLucas.id}'), findsNothing);
      // Su propia caja sigue abierta: aceptar la de otra no cierra la suya.
      expect(prueba.barra.cajasGuardadas.firstWhere((c) => c.id == caja.id).abierta, isTrue);
    });

    testWidgets('la encargada con su propia caja cierra sin pedirle el OK a nadie', (tester) async {
      await abrir(tester, encargada: true);
      await irACerrar(tester);
      await tester.enterText(porClave('cierre_contado'), '27000');
      await tester.pumpAndSettle();
      await tocar(tester, porClave('cierre_cerrar'));
      expect(texto(tester, 'cierre_que_pasa'), contains('La caja se cierra con ese número'));
      await tocar(tester, porClave('cierre_confirmar'));
      expect(guardada().abierta, isFalse);
      expect(pasos(), isEmpty, reason: 'sin pedido');
      expect(guardada().notaCierre, isNull);
      expect(texto(tester, 'cierre_diferencia'), 'Justo, sin diferencia');
    });

    for (final (nombre, tamano) in [
      ('un celular', const Size(360, 740)),
      ('una tablet acostada', const Size(1280, 800)),
    ]) {
      testWidgets('en $nombre no se desborda esperando, ni con los totales de la encargada', (tester) async {
        await abrir(tester, tamano: tamano);
        await irACerrar(tester);
        await contarYPedir(tester, '26500');
        expect(tester.takeException(), isNull);
        await tocar(tester, porClave('cierre_encargada_aca'));
        await tester.enterText(porClave('pin_encargada'), '7777');
        await tocar(tester, porClave('pin_seguir'));
        expect(find.byType(OkDelCierreDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tocar(tester, porClave('ok_cierre_despues'));
        expect(guardada().abierta, isTrue, reason: 'DESPUÉS no contesta nada');
        expect(porClave('cierre_esperando'), findsOneWidget);
      });
    }
  });

  test('las ventas de la prueba son de la caja', () {
    expect({cervezas.cajaBarraId, fernet.cajaBarraId, anulada.cajaBarraId}, {caja.id});
  });
}
