// La ventana de prueba de la venta de entradas (tool/venta_entradas_prueba.dart)
// anda: la tablet de Carla y la PC del jefe, cada una con su base, y lo que hace
// una le llega a la otra como en la app (spec 11.7: una vende y cierra, la otra ve
// la venta y el cierre; una familia compra las de sus lugares y la entrega lo
// muestra). Si deja de compilar o los lados dejan de hablarse, salta acá. El
// detalle de cada pantalla está en sus propias pruebas.
//
// **Desde el 20-nov-2026 Carla ve un solo botón, VENDER**, y adentro entrega lo sin
// cargo en dos partes y vende lo que se paga. La noche trae una familia de cada caso
// (`sumarLaNoche`), y estas pruebas la recorren como con el mouse: el inicio, abrir la
// caja, el filtro, las pulseras, las generales con números, A PAGAR con el número
// que sigue, el cobro, y lo que el jefe ve del otro lado; quien debe no retira pero
// compra lo pago, y quien paga en la caja se destraba solo.
//
// **Desde el 22-nov-2026, lo que le importa al usuario, de punta a punta**: (a) la
// mesa adicional de un alumno con el descuento del sorteo (ACOSTA); (b) alguien de
// afuera, con el número del talonario, en efectivo y por transferencia; (c) las
// entradas para rendir: el jefe da en la PC, Carla rinde en la tablet, la plata
// entra en su caja y en su cierre, el jefe anula la rendición en VENTAS, y sin
// internet de cada lado (rendir lo mismo en los dos da "rindió de más"). Ningún
// papel sale solo: cada uno con su botón (`PapelesDeLaPrueba`). Y PRECIOS ofrece
// la otra fiesta.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/cierre_caja/providers/caja_de_entregas_provider.dart';
import 'package:arguello_events/features/common/services/imprimir_planilla_de_entrega.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/entradas/cuentas/cierre_de_entradas.dart';
import 'package:arguello_events/features/entradas/cuentas/numeros_de_entradas.dart'
    show kTalonarioObligatorio;
import 'package:arguello_events/features/entradas/cuentas/para_rendir.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/pdf/para_rendir_pdf.dart';
import 'package:arguello_events/features/entradas/widgets/para_rendir_screen.dart';
import 'package:arguello_events/features/entradas/widgets/vender_entradas_screen.dart';
import 'package:arguello_events/features/entradas/widgets/ventas_de_entradas_screen.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

import '../tool/venta_entradas_prueba.dart';
import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';

const _perez = EntregaEnMemoria.idPerez;
const _lopez = EntregaEnMemoria.idLopez;
const _gomez = EntregaEnMemoria.idGomez;
const _acosta = NocheDeLaVenta.acosta;
const _benitez = NocheDeLaVenta.benitez;
const _diaz = NocheDeLaVenta.diaz;
const _ferreyra = NocheDeLaVenta.ferreyra;
const _herrera = NocheDeLaVenta.herrera;
const _ibarra = NocheDeLaVenta.ibarra;

void main() {
  late LadosDeLaVenta lados;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    lados = await armarLados(
      demoraDeSubida: Duration.zero,
      hoy: () => DateTime.utc(2026, 11, 20, 12),
      relojDelJefe: () => DateTime(2026, 11, 20, 12),
    );
  });
  tearDown(() => lados.dispose());

  /// Sin `pumpAndSettle`: la entrega relee cada 15 s.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> abrir(WidgetTester tester, {double alto = 1000}) async {
    tester.view.physicalSize = Size(2000, alto);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PruebaDeLaVenta(lados));
    await asentar(tester);
  }

  Future<void> tocar(WidgetTester tester, String clave) async {
    await tester.ensureVisible(find.byKey(Key(clave)));
    await tester.pump();
    await tester.tap(find.byKey(Key(clave)));
    await asentar(tester);
  }

  Future<void> poner(WidgetTester tester, String clave, String texto) async {
    await tester.ensureVisible(find.byKey(Key(clave)));
    await tester.pump();
    await tester.enterText(find.byKey(Key(clave)), texto);
    await asentar(tester);
  }

  String texto(WidgetTester tester, String clave) {
    final t = tester.widget<Text>(find.byKey(Key(clave)));
    return t.data ?? t.textSpan!.toPlainText();
  }

  /// El texto de un chip de VENDER (`ChipDeVender`).
  String chip(WidgetTester tester, String clave) => tester
      .widget<Text>(find.descendant(of: find.byKey(Key(clave)), matching: find.byType(Text)))
      .data!;

  /// Lo que se ve del lado del jefe (la entrega de la fiesta).
  Finder enElJefe(String texto) => find.descendant(
        of: find.byType(RetiroEntradasScreen),
        matching: find.textContaining(texto),
      );

  /// Carla abre su caja (si no la tiene) y le vende a PÉREZ [n] de sus lugares, por la
  /// base de la tablet, como lo haría VENDER.
  Future<VentaEntradas> venderAPerez(WidgetTester tester, int n) async {
    late VentaEntradas venta;
    await tester.runAsync(() async {
      final caja = await lados.tablet.abrirCaja(
        eventoId: idFiestaEntrega,
        operadorId: lados.operadora.id,
        operadorNombre: 'Carla',
        cambioInicial: 5000,
      );
      venta = await lados.tablet.vender(
        caja: caja,
        contratoAlumnoId: _perez,
        compradorNombre: 'PEREZ, MARTA',
        renglones: [
          RenglonEntradas.lugar(
            nombre: PedidoDeEntradas.nombreDeLugar(50),
            precioLista: 10000,
            descuentoPct: 50,
            cantidad: n,
          ),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 5000.0 * n,
        quien: 'Carla',
      );
    });
    await asentar(tester);
    return venta;
  }

  /// Desde el inicio de Carla: VENDER y abrir la caja con $ 5.000 de cambio.
  Future<void> entrarAVender(WidgetTester tester) async {
    await tocar(tester, 'vender_$idFiestaEntrega');
    expect(find.text('Abrir la caja de entradas'), findsOneWidget);
    await poner(tester, 'abrir_caja_cambio', '5000');
    await tocar(tester, 'abrir_caja_abrir');
    expect(find.byType(VenderEntradasScreen), findsOneWidget);
  }

  /// Elige al alumno [id] de la lista de VENDER, con el filtro [filtro].
  Future<void> elegir(WidgetTester tester, String id, {String? filtro}) async {
    if (filtro != null) await tocar(tester, filtro);
    await tocar(tester, 'vender_familia_$id');
    expect(find.byKey(const Key('vender_familia_elegida')), findsOneWidget);
  }

  /// Vuelve de la tarjeta a la lista.
  Future<void> aLaLista(WidgetTester tester) => tocar(tester, 'vender_cambiar_familia');

  /// ENTREGAR de [parte], quién retira y CONFIRMAR, en la tarjeta de VENDER.
  /// [numero]: el primero de las generales, si vienen numeradas.
  Future<void> entregarParte(
    WidgetTester tester,
    ParteEntrega parte, {
    String quien = 'Madre',
    required String nombre,
    String? numero,
  }) async {
    await tocar(tester, 'vender_entregar_${parte.clave}');
    final formulario = find.byKey(Key('vender_formulario_${parte.clave}'));
    Finder adentro(Finder f) => find.descendant(of: formulario, matching: f);
    if (numero != null) {
      await tester.ensureVisible(adentro(find.text('Vienen con número')));
      await tester.pump();
      await tester.tap(adentro(find.text('Vienen con número')));
      await asentar(tester);
      await tester.enterText(adentro(find.widgetWithText(TextField, 'Del')), numero);
      await asentar(tester);
    }
    await tester.ensureVisible(adentro(find.text(quien)));
    await tester.pump();
    await tester.tap(adentro(find.text(quien)));
    await tester.enterText(
      adentro(find.widgetWithText(TextField, 'Nombre y apellido de quien retira')),
      nombre,
    );
    final planilla = adentro(find.text('Escribió su nombre y apellido en la planilla de papel'));
    await tester.ensureVisible(planilla);
    await tester.pump();
    await tester.tap(planilla);
    await asentar(tester);
    await tocar(tester, 'entrega_confirmar_${parte.clave}');
  }

  /// En A PAGAR: quien compra, EFECTIVO y CONFIRMAR en la hoja del cobro.
  Future<void> cobrarEnEfectivo(WidgetTester tester, String comprador) async {
    await poner(tester, 'vender_comprador', comprador);
    // El número del talonario es obligatorio (22-nov-2026): si no vino
    // propuesto (la primera venta de la caja), lo escribe Carla.
    final del = find.byKey(const Key('vender_del'));
    if (tester.widget<TextField>(del).controller!.text.trim().isEmpty) {
      await poner(tester, 'vender_del', '7001');
    }
    expect(find.byKey(const Key('vender_falta')), findsNothing);
    await tocar(tester, 'vender_efectivo');
    await tocar(tester, 'cobro_confirmar');
  }

  /// Lo que Carla vendió en la tablet.
  List<VentaEntradas> ventasDeCarla() => [
        for (final v in lados.tablet.listaVentas)
          if (v.hechoPor == 'Carla') v,
      ];

  /// La caja de entradas que Carla abrió en la tablet.
  CajaEntradas cajaDeCarla() =>
      lados.tablet.listaCajas.firstWhere((c) => c.operadorNombre == 'Carla');

  /// Las entradas para rendir de la fiesta, contadas con lo que tiene [base] (la
  /// de la tablet o la de la PC): la cuenta de la app, sin pantalla.
  ParaRendir paraRendirEn(EntradasDeUnEquipo base) => ParaRendir.de(
        movimientos: base.listaParaRendir,
        ventas: base.listaVentas,
        anulaciones: base.listaAnulaciones,
      );

  /// Cierra la pantalla [pantalla] en el lado donde está. Cada lado es su propia
  /// app: `pageBack` no sabría de cuál de los dos es la flecha.
  Future<void> cerrarPantalla(WidgetTester tester, Type pantalla) async {
    Navigator.of(tester.element(find.byType(pantalla))).pop();
    // La animación de la salida dura más que [asentar]: mientras tanto tapa los
    // botones de abajo.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// El jefe, en ENTRADAS de la fiesta → PARA RENDIR → DAR ENTRADAS PARA RENDIR:
  /// 20 a PÉREZ, JUAN, de afuera, del 1201 al 1220, al precio de hoy (la
  /// anticipada). Se llama como un alumno de la fiesta a propósito: lo de afuera
  /// no es de ninguna familia. Queda en PARA RENDIR.
  Future<void> elJefeLeDaAJuan(WidgetTester tester) async {
    await tocar(tester, 'entradas_para_rendir');
    expect(find.byType(ParaRendirScreen), findsOneWidget);
    await tocar(tester, 'para_rendir_dar');
    await poner(tester, 'dar_nombre', 'Pérez, Juan');
    await poner(tester, 'dar_del', '1201');
    expect(texto(tester, 'dar_al_calculado'), 'al 1220');
    expect(texto(tester, 'dar_precio_texto'),
        r'A $ 8.000 cada una · Entrada anticipada · el precio de hoy (PRECIOS), queda fijo');
    await tocar(tester, 'dar_dar');
    expect(texto(tester, 'dar_confirmar_texto'),
        r'A PÉREZ, JUAN, del 1201 al 1220, a $ 8.000 cada una (entrada anticipada, queda fijo).');
    await tocar(tester, 'dar_confirmar_si');
    expect(texto(tester, 'para_rendir_hecho'),
        'Se le dieron 20 entradas a PÉREZ, JUAN (del 1201 al 1220) para rendir.');
  }

  /// En VENDER (de la tablet o de la PC): RENDIR de PÉREZ, JUAN, que vendió 15
  /// y devuelve 5 (los últimos, propuestos: del 1216 al 1220), y se le cobra
  /// en efectivo con la hoja del cobro.
  Future<void> rindeJuan(WidgetTester tester) async {
    await tocar(tester, 'vender_rendir');
    // Es el único con algo para rendir: viene elegido.
    expect(texto(tester, 'rendir_tarjeta_texto'),
        allOf(contains('del 1201 al 1220'), endsWith('le quedan 20')));
    for (var i = 0; i < 15; i++) {
      await tocar(tester, 'rendir_vendio_mas');
    }
    for (var i = 0; i < 5; i++) {
      await tocar(tester, 'rendir_devuelve_mas');
    }
    expect(texto(tester, 'rendir_le_quedan'), '0');
    expect(tester.widget<TextField>(find.byKey(const Key('rendir_del'))).controller!.text,
        '1216');
    expect(texto(tester, 'rendir_al_calculado'), 'al 1220');
    expect(texto(tester, 'rendir_a_cobrar'), r'A cobrar: 15 × $ 8.000');
    expect(texto(tester, 'rendir_total'), r'$ 120.000');
    await tocar(tester, 'rendir_efectivo');
    await tocar(tester, 'cobro_confirmar');
    expect(texto(tester, 'vender_rendicion_guardada_texto'),
        r'Rendición guardada · PÉREZ, JUAN · vendió 15 · devolvió 5 · le quedan 0 · $ 120.000');
  }

  /// En VENDER de Carla: "Alguien de afuera".
  Future<void> aAlguienDeAfuera(WidgetTester tester) async {
    final boton = find.descendant(
      of: find.byKey(const Key('vender_a_quien')),
      matching: find.text('Alguien de afuera'),
    );
    await tester.ensureVisible(boton);
    await tester.pump();
    await tester.tap(boton);
    await asentar(tester);
  }

  /// Si el botón de [clave] está apagado.
  bool apagado(WidgetTester tester, String clave) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).onPressed == null;

  testWidgets('abre sin excepción, y cada lado mide su ancho', (tester) async {
    await abrir(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(EntradasHomeScreen), findsOneWidget);
    expect(find.byKey(const Key('vender_$idFiestaEntrega')), findsOneWidget);
    expect(find.byType(RetiroEntradasScreen), findsOneWidget);
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(EntradasHomeScreen))).width,
      800,
    );
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(RetiroEntradasScreen))).width,
      2000 - 800 - 6,
    );
    // La noche arranca con la caja de Maxi cerrada, $ 500 de menos.
    await tocar(tester, 'prueba_jefe_cierre');
    await tocar(tester, 'cierre_sector_entradas');
    expect(
      tester
          .widget<Text>(find.byKey(Key('cierre_entradas_diferencia_${lados.cajaDeMaxi.id}')))
          .data,
      contains('500'),
    );
    await tocar(tester, 'prueba_ancho_carla');
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(EntradasHomeScreen))).width,
      390,
    );
    expect(tester.takeException(), isNull);
  });

  // 20-nov-2026: quien tiene "Vende entradas" ve un solo botón por fiesta. Hasta la
  // 6.9.2 eran dos, ENTREGAR y VENDER.
  testWidgets('el inicio de Carla tiene un solo botón, VENDER, también en el celular',
      (tester) async {
    await abrir(tester);
    for (final celular in [false, true]) {
      if (celular) await tocar(tester, 'prueba_ancho_carla');
      final inicio = find.byType(EntradasHomeScreen);
      // VENDER y, arriba, SALIR (sin Cobros no hay PASAR A CAJA).
      expect(
        find.descendant(
          of: inicio,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
        findsNWidgets(2),
      );
      expect(find.byKey(const Key('vender_$idFiestaEntrega')), findsOneWidget);
      expect(find.byKey(const Key('entregar_$idFiestaEntrega')), findsNothing);
      expect(find.descendant(of: inicio, matching: find.text('ENTREGAR')), findsNothing);
    }
    // La tarjeta entera también abre VENDER.
    await tocar(tester, 'fiesta_$idFiestaEntrega');
    expect(find.byType(VenderEntradasScreen), findsOneWidget);
  });

  testWidgets('Carla le vende 3 de sus lugares a PÉREZ y el jefe lo ve: en la entrega, '
      'en VENTAS y en el cierre de caja', (tester) async {
    await abrir(tester);
    // 20-nov-2026: la noche trae más familias. Con descuento: PÉREZ, ACOSTA y
    // BENÍTEZ, 8 cada una; FERREYRA agregó una silla después del sorteo (hasta
    // esa fecha la noche tenía solo a PÉREZ: "0 vendidas de 8").
    expect(enElJefe('0 vendidas de 24'), findsOneWidget);
    expect(enElJefe('Al 50 % · 1 sin descuento'), findsOneWidget);
    final venta = await venderAPerez(tester, 3);
    expect(lados.tablet.pendientes, isEmpty, reason: 'subió');
    expect(lados.pc.listaVentas.map((v) => v.id), contains(venta.id));
    expect(enElJefe('3 vendidas de 24'), findsOneWidget);
    await tester.scrollUntilVisible(
      enElJefe('8 al 50 % (compró 3)'),
      200,
      scrollable: find.descendant(
        of: find.byType(RetiroEntradasScreen),
        matching: find.byType(Scrollable),
      ).last,
    );
    expect(enElJefe('8 al 50 % (compró 3)'), findsOneWidget);

    await tocar(tester, 'entradas_ventas');
    expect(find.byKey(Key('venta_${venta.id}')), findsOneWidget);
    await tester.pageBack();
    await asentar(tester);

    await tocar(tester, 'prueba_jefe_cierre');
    await tocar(tester, 'cierre_sector_entradas');
    expect(find.text('Carla · abierta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin internet el jefe no ve la venta; al volver, sí, y Carla queda en '
      '"Todo subido"', (tester) async {
    await abrir(tester);
    await tocar(tester, 'prueba_internet');
    expect(lados.hayInternet, isFalse);
    await venderAPerez(tester, 3);
    expect(lados.tablet.pendientes, hasLength(2), reason: 'la caja y la venta');
    expect(lados.pc.listaVentas.where((v) => v.contratoAlumnoId == _perez), isEmpty);
    // Aunque el jefe relea, no está.
    lados.nube.pc.bajo({'entradas_ventas'});
    await asentar(tester);
    expect(enElJefe('0 vendidas de 24'), findsOneWidget);

    // Carla, en VENDER: la línea lo dice, con la caja que abrió sin internet
    // (20-nov-2026: "Todo subido" es que no queda nada, no solo las ventas).
    await tocar(tester, 'vender_$idFiestaEntrega');
    await asentar(tester);
    expect(
      texto(tester, 'vender_linea_texto'),
      'Caja abierta · Carla · Sin internet · 1 venta y 1 cambio por subir',
    );

    await tocar(tester, 'prueba_internet');
    await asentar(tester);
    expect(lados.hayInternet, isTrue);
    expect(lados.tablet.pendientes, isEmpty);
    expect(enElJefe('3 vendidas de 24'), findsOneWidget);
    expect(texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
  });

  // Revisión del 20-nov-2026 ("si sube, que suba de verdad"): una entrega hecha sin
  // internet también cuenta en la línea, y en la ventana de prueba se tiene que ver.
  testWidgets('sin internet, una entrega queda "por subir" en la línea; al volver, '
      '"Todo subido"', (tester) async {
    await abrir(tester, alto: 1400);
    await entrarAVender(tester);
    await tocar(tester, 'prueba_internet');
    expect(lados.hayInternet, isFalse);
    await elegir(tester, _acosta);
    await entregarParte(tester, ParteEntrega.pulseras, nombre: 'Marta Acosta');
    // Sin internet pregunta antes de seguir.
    await tester.tap(find.text('SEGUIR'));
    await asentar(tester);
    if (find.text('ENTENDIDO').evaluate().isNotEmpty) {
      await tester.tap(find.text('ENTENDIDO'));
      await asentar(tester);
    }
    expect(texto(tester, 'vender_linea_texto'), contains('1 entrega'));
    expect(texto(tester, 'vender_linea_texto'), contains('Sin internet'));

    await tocar(tester, 'prueba_internet');
    await asentar(tester);
    expect(lados.hayInternet, isTrue);
    expect(texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
  });

  testWidgets('Carla cierra su caja y el cierre de caja del jefe la muestra cerrada',
      (tester) async {
    await abrir(tester);
    await venderAPerez(tester, 3);
    await tocar(tester, 'prueba_jefe_cierre');
    await tocar(tester, 'cierre_sector_entradas');
    expect(find.text('Carla · abierta'), findsOneWidget);

    final caja = lados.tablet.listaCajas.firstWhere((c) => c.operadorNombre == 'Carla');
    await tester.runAsync(() => lados.tablet.cerrarCaja(
          caja,
          efectivoContado: 20000,
          diferencia: 0,
          quien: 'Carla',
        ));
    await asentar(tester);
    expect(find.text('Carla · abierta'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(Key('cierre_entradas_diferencia_${caja.id}'))).data,
      'Justo',
    );
  });

  testWidgets('IMPRIMIR de la caja de entregas queda en la prueba: no va a la carpeta del '
      'programa', (tester) async {
    await abrir(tester);
    // Antes de tocar nada: el papel no es el de la app (ese escribiría en la
    // carpeta de verdad, también en `flutter test`).
    expect(lados.jefe.read(imprimirEntregasSinCargoProvider),
        isNot(same(PdfService.generarEntregasSinCargo)));
    expect(lados.carla.read(imprimirPlanillaDeEntregaProvider),
        isNot(same(PdfService.generarPlanillaEntrega)));
    await tocar(tester, 'prueba_jefe_cierre');
    await tocar(tester, 'cierre_sector_entradas');
    await tocar(tester, 'cierre_entregas_imprimir');
    expect(lados.papeles.entregasSinCargo, [null]);
  });

  // Regla 60, de verdad y no solo el texto (22-nov-2026): la constancia de las
  // entradas para rendir de cada lado queda en la prueba. Si a un lado le faltara
  // el reemplazo, se llamaría a la de la app; con un contexto que ya no está, la
  // de la app arma el papel y no lo entrega (no escribe nada), así que la
  // constancia no llega a la prueba y esto falla sin tocar la carpeta del programa.
  testWidgets('la constancia de las entradas para rendir queda en la prueba en los dos '
      'lados: no va a la carpeta del programa', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final yaNoEsta = tester.element(find.byType(SizedBox));
    await tester.pumpWidget(const Placeholder());
    expect(yaNoEsta.mounted, isFalse);
    final otra = EntradasEnMemoria();
    final dio = await otra.darParaRendir(
      eventoId: idFiestaEntrega,
      personaNombre: 'PEREZ, JUAN',
      cantidad: 20,
      numeros: const [TramoTalonario(1201, 1220)],
      precio: 8000,
      nombrePrecio: PedidoDeEntradas.nombreAnticipada,
      quien: 'Jefe',
    );
    final datos = DatosDeLaConstancia(
      bloque: ParaRendir.de(movimientos: [dio], ventas: const [], anulaciones: const [])
          .bloque(dio.id)!,
      fiesta: 'INSTITUTO SAN LORENZO',
    );
    await tester.runAsync(() async {
      // El jefe es el que llega a PARA RENDIR; Carla, por si algún día.
      for (final lado in [lados.jefe, lados.carla]) {
        await lado.read(abrirConstanciaParaRendirProvider)(datos, context: yaNoEsta);
      }
    });
    expect(lados.papeles.constancias, hasLength(2), reason: 'una de cada lado');
    expect(lados.papeles.constancias, everyElement(same(datos)));
    expect(lados.papeles.archivos, isEmpty, reason: 'sin carpeta, la prueba no escribe');
  });

  testWidgets('con MODO JEFE en NO, PRECIOS, VENTAS y VENDER se apagan, y el cierre '
      'queda en COBROS', (tester) async {
    await abrir(tester);
    bool apagado(String clave) =>
        tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).onPressed == null;
    expect(apagado('entradas_precios'), isFalse);
    expect(apagado('entradas_ventas'), isFalse);
    expect(apagado('entradas_vender'), isFalse);
    await tocar(tester, 'prueba_modo_jefe');
    expect(apagado('entradas_precios'), isTrue);
    expect(apagado('entradas_ventas'), isTrue);
    expect(apagado('entradas_vender'), isTrue);
    await tocar(tester, 'prueba_jefe_cierre');
    expect(find.byKey(const Key('cierre_sector_entradas')), findsNothing);
  });

  // 22-nov-2026: PRECIOS, guardado, pregunta si se ponen los mismos precios en
  // otras fiestas. En la ventana ofrece BAHÍA SERENA, inventada (sin el reemplazo
  // leía los eventos de la base, cerrada en la prueba, y el cartel no salía).
  testWidgets('PRECIOS del jefe: al guardar ofrece BAHÍA SERENA, y NO, SOLO ESTA la deja '
      'sin precio en los dos equipos', (tester) async {
    await abrir(tester);
    final otra = otraFiestaDeLosPrecios.id;
    await tocar(tester, 'entradas_precios');
    await tocar(tester, 'precios_guardar');
    expect(find.text('¿Poner estos precios también en otras fiestas?'), findsOneWidget);
    expect(find.byKey(Key('precios_otras_$otra')), findsOneWidget);
    expect(find.byKey(const Key('precios_otras_$idFiestaEntrega')), findsNothing,
        reason: 'la de acá no se ofrece');
    expect(texto(tester, 'precios_otras_${otra}_hoy'), 'Hoy: Sin precio');
    expect(apagado(tester, 'precios_otras_poner'), isTrue, reason: 'ninguna viene tildada');
    expect(lados.pc.configs[idFiestaEntrega]!.precioAnticipada, 8000,
        reason: 'PUERTO VIEJO ya quedó guardada');

    final escrituras = lados.pc.escrituras;
    await tocar(tester, 'precios_otras_no');
    expect(find.text('¿Poner estos precios también en otras fiestas?'), findsNothing);
    expect(find.text('Precios de las entradas'), findsNothing, reason: 'PRECIOS se cierra');
    expect(lados.pc.escrituras, escrituras);
    expect(lados.pc.configs[otra], isNull);
    expect(lados.tablet.configs[otra], isNull);
    expect(lados.pc.pendientes, isEmpty, reason: 'lo de PUERTO VIEJO subió');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Carla, con el mouse: abre la caja, le vende a PÉREZ y saca el comprobante '
      'con su botón', (tester) async {
    await abrir(tester);
    // PÉREZ debe su mesa adicional: desde el 20-nov-2026 lo de A PAGAR se vende
    // solo si está pago entero. La paga antes, en la caja de cuotas.
    lados.cobrarTodo(_perez);
    await asentar(tester);
    await entrarAVender(tester);
    await poner(tester, 'vender_buscar', 'perez');
    await tocar(tester, 'vender_familia_$_perez');
    // Desde el 20-nov-2026, A PAGAR tiene un renglón por mesa adicional (antes,
    // uno solo para todos sus lugares: 'vender_lugar').
    for (var i = 0; i < 5; i++) {
      await tocar(tester, 'vender_linea_mesa_1_menos');
    }
    await cobrarEnEfectivo(tester, 'PEREZ, MARTA');
    // Ningún papel sale solo (22-nov-2026): IMPRIMIR EL COMPROBANTE.
    expect(lados.papeles.comprobantes, isEmpty);
    await tocar(tester, 'vender_ver_comprobante');
    expect(lados.papeles.comprobantes, hasLength(1));
    expect(lados.papeles.comprobantes.single.venta.cantidad, 3);
    expect(lados.papeles.comprobantes.single.copia, isFalse);
    expect(enElJefe('3 vendidas de 24'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('la noche, como con el mouse (20-nov-2026)', () {
    testWidgets('cada familia en su grupo del filtro, con lo que le toca', (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);
      // Abre en "puede retirar": los que pagaron todo su contrato.
      expect(chip(tester, 'vender_filtro_puede'), 'Pagó todo: puede retirar (5)');
      expect(chip(tester, 'vender_filtro_debe'), 'Debe: a caja (3)');
      expect(chip(tester, 'vender_filtro_ya'), 'Ya retiró (1)');
      expect(chip(tester, 'vender_filtro_todos'), 'Todos (9)');
      expect(find.byKey(const Key('vender_filtro_revisar')), findsNothing,
          reason: 'nadie para revisar');
      for (final id in [_acosta, _ferreyra, _herrera, _ibarra, _lopez]) {
        expect(find.byKey(Key('vender_familia_$id')), findsOneWidget, reason: id);
      }
      for (final id in [_perez, _benitez, _diaz, _gomez]) {
        expect(find.byKey(Key('vender_familia_$id')), findsNothing, reason: id);
      }
      expect(texto(tester, 'vender_resumen_$_acosta'),
          '3 VIP con cena + 5 generales · A pagar 8 con 50 %');
      expect(texto(tester, 'vender_resumen_$_ferreyra'),
          '1 VIP con cena + 7 generales · A pagar 1 sin descuento');
      expect(texto(tester, 'vender_resumen_$_herrera'),
          '4 VIP con cena + 4 generales · nada a pagar');
      expect(texto(tester, 'vender_resumen_$_ibarra'),
          '3 VIP con cena + 5 generales · nada a pagar');
      expect(texto(tester, 'vender_resumen_$_lopez'),
          '1 VIP con cena + 7 generales · nada a pagar');
      // Arriba, cuántas pulseras y generales tienen que llegar (GÓMEZ ya retiró
      // las 8 juntas con la 6.9.x: cuentan como las dos partes).
      expect(
        texto(tester, 'vender_total_fiesta'),
        'Total de la fiesta · Pulseras VIP: 17 (entregadas 1) · Generales: 55 '
        '(entregadas 7)',
      );

      await tocar(tester, 'vender_filtro_debe');
      expect(chip(tester, 'vender_estado_$_perez'), r'Debe $ 70.000');
      expect(chip(tester, 'vender_estado_$_benitez'), r'Debe $ 33.333');
      expect(chip(tester, 'vender_estado_$_diaz'), r'Debe $ 12.500');
      expect(texto(tester, 'vender_resumen_$_perez'),
          '1 VIP con cena + 7 generales · A pagar: 8 a confirmar');
      expect(texto(tester, 'vender_resumen_$_benitez'),
          '2 VIP con cena + 6 generales · A pagar 8 con 50 %');
      expect(texto(tester, 'vender_resumen_$_diaz'),
          '1 VIP con cena + 7 generales · nada a pagar');

      await tocar(tester, 'vender_filtro_ya');
      expect(chip(tester, 'vender_estado_$_gomez'), '✓ Retiró');

      // En la tarjeta: los nombres de los acompañantes, el que falta y el aviso
      // del máximo.
      await elegir(tester, _herrera, filtro: 'vender_filtro_puede');
      expect(texto(tester, 'vender_parte_titulo_pulseras'), 'Pulseras VIP con cena · 4');
      expect(texto(tester, 'vender_mas_de_dos'),
          'Tiene 3 acompañantes con cena (el máximo es 2): confirmalo con el jefe.');
      await aLaLista(tester);
      await elegir(tester, _ibarra);
      expect(texto(tester, 'vender_parte_detalle_pulseras'),
          'El egresado · IBARRA, JOSÉ · 1 sin nombre');
      expect(texto(tester, 'vender_parte_titulo_generales'), 'Entradas generales · 5');
      expect(find.byKey(const Key('vender_mas_de_dos')), findsNothing);
      await aLaLista(tester);
      await elegir(tester, _lopez);
      expect(texto(tester, 'vender_nada_a_pagar'),
          'Nada: no tiene mesa adicional ni sillas extra.');
      await aLaLista(tester);
      // La silla que agregó después del sorteo: sin descuento, al precio del día
      // (la anticipada, que rige hasta el 28-nov).
      await elegir(tester, _ferreyra);
      expect(chip(tester, 'vender_linea_sillas_despues_chip'), 'Sin descuento');
      expect(texto(tester, 'vender_linea_sillas_despues_precio'),
          r'$ 8.000 c/u · precio del día (anticipada)');
      expect(texto(tester, 'vender_total'), r'$ 8.000');
      await aLaLista(tester);
      await elegir(tester, _gomez, filtro: 'vender_filtro_ya');
      expect(find.byKey(const Key('vender_todo_entregado')), findsOneWidget);
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsNothing);
      expect(find.byKey(const Key('vender_entregar_generales')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ACOSTA pagó todo: las pulseras, las generales con números, y A PAGAR '
        'con el cobro; el jefe lo ve del otro lado', (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);
      await elegir(tester, _acosta);
      expect(texto(tester, 'vender_gratis_titulo'), 'GRATIS · SE ENTREGA');
      expect(texto(tester, 'vender_parte_titulo_pulseras'), 'Pulseras VIP con cena · 3');
      expect(texto(tester, 'vender_parte_detalle_pulseras'),
          'El egresado · ACOSTA, MARTA · ACOSTA, RUBÉN');
      expect(texto(tester, 'vender_parte_titulo_generales'), 'Entradas generales · 5');

      // Llegaron las pulseras.
      await entregarParte(tester, ParteEntrega.pulseras, nombre: 'Marta Acosta');
      expect(lados.entrega.estadoDe(_acosta).pulseras.entregada, isTrue);
      expect(find.byKey(const Key('vender_entregada_pulseras')), findsOneWidget);
      expect(chip(tester, 'vender_familia_estado'), 'Pagó todo · ✓ pulseras');
      expect(lados.entrega.entregas.filas[_acosta], isNull,
          reason: 'a medias, la fila de siempre no se toca');
      // Del otro lado: el jefe ve la parte entregada.
      expect(enElJefe('Pulseras ✓ Madre MARTA ACOSTA'), findsOneWidget);
      expect(enElJefe('Pulseras VIP: 17 (entregadas 4)'), findsOneWidget);

      // Otro día llegaron las generales, numeradas: del 5001 al 5005.
      await entregarParte(tester, ParteEntrega.generales, nombre: 'Marta Acosta', numero: '5001');
      final estado = lados.entrega.estadoDe(_acosta);
      expect(estado.todoEntregado, isTrue);
      expect(estado.generales.tramos, const [TramoTalonario(5001, 5005)]);
      expect(find.byKey(const Key('vender_todo_entregado')), findsOneWidget);
      expect(chip(tester, 'vender_familia_estado'), '✓ Retiró');
      expect(lados.entrega.entregas.filas[_acosta]?.entregado, isTrue,
          reason: 'con las dos partes, la fila completa (la 6.9.x y el plano la ven)');
      expect(enElJefe('Generales: 55 (entregadas 12)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RetiroEntradasScreen),
          matching: find.text('✓ Todo entregado'),
        ),
        findsNWidgets(2),
        reason: 'GÓMEZ y ACOSTA',
      );

      // A PAGAR: su mesa adicional, paga entera, con el 50 %. Es la primera venta de
      // la caja: el número lo escribe Carla.
      expect(chip(tester, 'vender_linea_mesa_1_chip'), 'Con descuento 50 %');
      expect(texto(tester, 'vender_linea_mesa_1_cantidad'), '8');
      expect(texto(tester, 'vender_total'), r'$ 40.000');
      expect(texto(tester, 'vender_talonario_titulo'),
          'Talonario de las anticipadas · las 8 que paga');
      await poner(tester, 'vender_del', '2001');
      expect(texto(tester, 'vender_al_calculado'), 'al 2008');
      await cobrarEnEfectivo(tester, 'ACOSTA, MARTA');
      final venta = ventasDeCarla().single;
      expect(venta.numeros, '2001-2008');
      expect(venta.total, 40000);
      expect(venta.contratoAlumnoId, _acosta);
      // Lo que importa (22-nov-2026): la mesa que tenía al sorteo, con el
      // descuento de PRECIOS, en efectivo.
      expect(venta.medio, MedioBarra.efectivo);
      expect(venta.efectivo, 40000);
      expect(venta.renglones.single.descuentoPct, 50);
      expect(lados.papeles.comprobantes, isEmpty, reason: 'ningún papel se abre solo');
      await tocar(tester, 'vender_ver_comprobante');
      expect(lados.papeles.comprobantes.single.venta.id, venta.id);
      expect(lados.papeles.comprobantes.single.alumno, 'ACOSTA, LUCÍA');
      expect(lados.papeles.comprobantes.single.copia, isFalse);
      // VER DE NUEVO: el mismo, como COPIA.
      await tocar(tester, 'vender_ver_comprobante');
      expect(lados.papeles.comprobantes, hasLength(2));
      expect(lados.papeles.comprobantes.last.copia, isTrue);
      // El jefe: la venta, en su entrega y en VENTAS.
      expect(lados.pc.listaVentas.map((v) => v.id), contains(venta.id));
      expect(enElJefe('8 vendidas de 24'), findsOneWidget);
      await tocar(tester, 'entradas_ventas');
      expect(find.byKey(Key('venta_${venta.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BENÍTEZ debe una cuota: no retira lo sin cargo, va a la caja, y compra '
        'lo de su mesa adicional (paga) con el número que sigue', (tester) async {
      await abrir(tester, alto: 1400);
      // Antes, Carla ya vendió del 2001 al 2008 en su caja.
      await tester.runAsync(() async {
        final caja = await lados.tablet.abrirCaja(
          eventoId: idFiestaEntrega,
          operadorId: lados.operadora.id,
          operadorNombre: 'Carla',
          cambioInicial: 5000,
        );
        await lados.tablet.vender(
          caja: caja,
          compradorNombre: 'RUIZ, ANA',
          renglones: [
            RenglonEntradas.suelta(nombre: 'Entrada anticipada', precioLista: 8000, cantidad: 8),
          ],
          medio: MedioBarra.efectivo,
          efectivo: 64000,
          numeros: '2001-2008',
          quien: 'Carla',
        );
      });
      await asentar(tester);
      await tocar(tester, 'vender_$idFiestaEntrega');
      expect(find.text('Abrir la caja de entradas'), findsNothing, reason: 'la retoma');

      await elegir(tester, _benitez, filtro: 'vender_filtro_debe');
      expect(texto(tester, 'vender_gratis_titulo'), 'GRATIS · TODAVÍA NO SE ENTREGA');
      expect(
        texto(tester, 'vender_gratis_debe'),
        r'Debe $ 33.333 de su contrato: cuotas y extras $ 33.333. Primero pasa por '
        'caja a saldar todo. Cuando pague, se destraba solo.',
      );
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsNothing);
      expect(find.byKey(const Key('vender_entregar_generales')), findsNothing);
      expect(find.byKey(const Key('vender_mandar_a_caja')), findsOneWidget);

      // Su mesa adicional está paga entera: esas sí. El número viene propuesto: el
      // que sigue a la última venta de la caja.
      expect(texto(tester, 'vender_linea_mesa_1_cantidad'), '8');
      expect(tester.widget<TextField>(find.byKey(const Key('vender_del'))).controller!.text,
          '2009');
      expect(texto(tester, 'vender_al_calculado'), 'al 2016');
      await cobrarEnEfectivo(tester, 'BENÍTEZ, CLARA');
      final venta = ventasDeCarla().firstWhere((v) => v.contratoAlumnoId == _benitez);
      expect(venta.numeros, '2009-2016');
      expect(venta.cuantas(TipoRenglonEntradas.lugar), 8);
      expect(lados.entrega.estadoDe(_benitez).algoEntregado, isFalse);
      expect(enElJefe('8 vendidas de 24'), findsOneWidget);

      // Sigue debiendo: a la caja.
      await tocar(tester, 'vender_mandar_a_caja');
      expect(find.byKey(const Key('vender_en_caja_$_benitez')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DÍAZ debe solo la mora: va a la caja, paga, y se destraba solo',
        (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);
      await elegir(tester, _diaz, filtro: 'vender_filtro_debe');
      expect(
        texto(tester, 'vender_gratis_debe'),
        r'Debe $ 12.500 de su contrato: mora $ 12.500. Primero pasa por caja a '
        'saldar todo. Cuando pague, se destraba solo.',
      );
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsNothing);
      await tocar(tester, 'vender_mandar_a_caja');
      expect(find.byKey(const Key('vender_familia_elegida')), findsNothing,
          reason: 'vuelve a la lista');
      expect(find.byKey(const Key('vender_en_caja_$_diaz')), findsOneWidget);

      // La caja de cuotas le cobra, del lado del jefe.
      await tocar(tester, 'prueba_caja_cobra');
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text(r'Debe $ 12.500')),
        findsOneWidget,
      );
      await tocar(tester, 'prueba_cobrar_$_diaz');
      await tocar(tester, 'prueba_caja_cerrar');
      expect(lados.deudaDe(_diaz).pagoTodo, isTrue);

      // En VENDER salta solo.
      expect(texto(tester, 'vender_pago_texto_$_diaz'),
          'DÍAZ, NICOLÁS pagó todo: ya podés entregar');
      await tocar(tester, 'vender_pago_abrir_$_diaz');
      expect(texto(tester, 'vender_gratis_titulo'), 'GRATIS · SE ENTREGA');
      await entregarParte(tester, ParteEntrega.pulseras, quien: 'Padre', nombre: 'Hugo Díaz');
      expect(lados.entrega.estadoDe(_diaz).pulseras.entregada, isTrue);
      expect(find.byKey(const Key('vender_en_caja_$_diaz')), findsNothing,
          reason: 'entregado, sale de "En caja"');
      expect(tester.takeException(), isNull);
    });

    testWidgets('PÉREZ debe su mesa adicional: "a confirmar"; la paga en la caja y se '
        'habilita sola, lo sin cargo también', (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);
      await elegir(tester, _perez, filtro: 'vender_filtro_debe');
      expect(texto(tester, 'vender_linea_mesa_1_a_confirmar'),
          'A confirmar: falta pagarla en caja.');
      expect(find.byKey(const Key('vender_linea_mesa_1_mas')), findsNothing);
      expect(find.byKey(const Key('vender_comprador')), findsNothing,
          reason: 'sin nada para comprar no se cobra');

      // La caja de cuotas (otra PC) le cobra la mesa adicional.
      expect(lados.cobrarTodo(_perez), 70000);
      await asentar(tester);

      expect(texto(tester, 'vender_linea_mesa_1_cantidad'), '8');
      expect(find.byKey(const Key('vender_linea_mesa_1_mas')), findsOneWidget);
      expect(texto(tester, 'vender_gratis_titulo'), 'GRATIS · SE ENTREGA');
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // Lo que le importa al usuario de la venta de entradas, de punta a punta entre
  // los dos equipos (22-nov-2026): (a) la mesa adicional de un alumno con el
  // descuento del sorteo, en el grupo de arriba (ACOSTA); (b) alguien de afuera;
  // (c) las entradas para rendir, también sin internet. En todos, ningún papel
  // sale solo: cada uno con su botón.
  group('alguien de afuera y las entradas para rendir, entre los dos equipos (22-nov-2026)',
      () {
    testWidgets('(b) Carla le vende a alguien de afuera: con el número del talonario, en '
        'efectivo y por transferencia (esta, sin internet); el jefe las ve', (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);
      await aAlguienDeAfuera(tester);
      await tocar(tester, 'vender_sueltas_mas');
      await tocar(tester, 'vender_sueltas_mas');
      await poner(tester, 'vender_comprador', 'GÓMEZ, CARLA');
      // La primera venta de la caja: el número no viene propuesto y es obligatorio.
      expect(tester.widget<TextField>(find.byKey(const Key('vender_del'))).controller!.text,
          isEmpty);
      expect(texto(tester, 'vender_falta'), kTalonarioObligatorio);
      expect(apagado(tester, 'vender_efectivo'), isTrue);
      // El 3001 lo vendió Maxi en su caja: no se repite.
      await poner(tester, 'vender_del', '3001');
      expect(texto(tester, 'vender_falta'), contains('3001'));
      expect(apagado(tester, 'vender_efectivo'), isTrue);
      await poner(tester, 'vender_del', '6001');
      expect(find.byKey(const Key('vender_falta')), findsNothing);
      expect(texto(tester, 'vender_al_calculado'), 'al 6002');
      expect(texto(tester, 'vender_total'), r'$ 16.000', reason: r'2 anticipadas de $ 8.000');
      await tocar(tester, 'vender_efectivo');
      await tocar(tester, 'cobro_confirmar');

      final enEfectivo = ventasDeCarla().single;
      expect(enEfectivo.contratoAlumnoId, isNull, reason: 'no es de ninguna familia');
      expect(enEfectivo.compradorNombre, 'GÓMEZ, CARLA');
      expect(enEfectivo.numeros, '6001-6002');
      expect(enEfectivo.cantidad, 2);
      expect(enEfectivo.total, 16000);
      expect(enEfectivo.medio, MedioBarra.efectivo);
      expect(enEfectivo.efectivo, 16000);
      // El comprobante, con su botón; la segunda vez, la COPIA.
      expect(lados.papeles.comprobantes, isEmpty, reason: 'ningún papel se abre solo');
      await tocar(tester, 'vender_ver_comprobante');
      expect(lados.papeles.comprobantes.single.venta.id, enEfectivo.id);
      expect(lados.papeles.comprobantes.single.alumno, isNull);
      expect(lados.papeles.comprobantes.single.copia, isFalse);
      await tocar(tester, 'vender_ver_comprobante');
      expect(lados.papeles.comprobantes.last.copia, isTrue);
      // El jefe: le llegó, y no le suma a ninguna familia.
      expect(lados.tablet.pendientes, isEmpty);
      expect(lados.pc.listaVentas.map((v) => v.id), contains(enEfectivo.id));
      expect(enElJefe('0 vendidas de 24'), findsOneWidget);

      // La segunda, por transferencia y sin internet: queda en la tablet.
      await tocar(tester, 'prueba_internet');
      await aAlguienDeAfuera(tester);
      await tocar(tester, 'vender_sueltas_mas');
      await poner(tester, 'vender_comprador', 'RUIZ, PEDRO');
      expect(tester.widget<TextField>(find.byKey(const Key('vender_del'))).controller!.text,
          '6003', reason: 'el que sigue al último que vendió esta caja');
      await tocar(tester, 'vender_transferencia');
      expect(texto(tester, 'cobro_transfiere'), r'$ 8.000');
      await tocar(tester, 'cobro_confirmar');
      final porTransferencia = ventasDeCarla().firstWhere((v) => v.id != enEfectivo.id);
      expect(porTransferencia.compradorNombre, 'RUIZ, PEDRO');
      expect(TramoTalonario.deTexto(porTransferencia.numeros),
          const [TramoTalonario(6003, 6003)]);
      expect(porTransferencia.medio, MedioBarra.transferencia);
      expect(porTransferencia.transferencia, 8000);
      expect(porTransferencia.efectivo, 0);
      expect(lados.tablet.pendientes.map((p) => p.tabla), ['entradas_ventas']);
      expect(lados.pc.listaVentas.map((v) => v.id), isNot(contains(porTransferencia.id)));
      expect(texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · Sin internet · 1 venta por subir');
      await tocar(tester, 'vender_ver_comprobante');
      expect(lados.papeles.comprobantes.last.venta.id, porTransferencia.id);
      expect(lados.papeles.comprobantes.last.copia, isFalse);

      // Vuelve el internet: sube, y el jefe la tiene en VENTAS.
      await tocar(tester, 'prueba_internet');
      expect(lados.tablet.pendientes, isEmpty);
      expect(lados.pc.listaVentas.map((v) => v.id), contains(porTransferencia.id));
      expect(texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
      await tocar(tester, 'entradas_ventas');
      expect(find.byKey(Key('venta_${enEfectivo.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${porTransferencia.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(c) el jefe le da 20 a PÉREZ, JUAN en la PC; Carla, en la tablet, le '
        'cobra 15 y le recibe 5; la plata entra en su caja y en su cierre', (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);
      expect(find.byKey(const Key('vender_para_rendir')), findsNothing,
          reason: 'nadie tiene entradas para rendir');

      await elJefeLeDaAJuan(tester);
      // La constancia para firmar no sale sola: IMPRIMIR LA CONSTANCIA.
      expect(lados.papeles.constancias, isEmpty, reason: 'ningún papel se abre solo');
      await tocar(tester, 'para_rendir_hecho_constancia');
      final constancia = lados.papeles.constancias.single;
      expect(constancia.bloque.persona, 'PÉREZ, JUAN');
      expect(constancia.bloque.esDeUnAlumno, isFalse);
      expect(TramoTalonario.legible(constancia.bloque.tramos), '1201 al 1220');
      expect(constancia.bloque.precioDeCadaUna, 8000);
      expect(constancia.reimpresa, isFalse);

      // Subió: la tablet lo tiene, y VENDER de Carla lo dice, sin plata.
      expect(lados.pc.pendientes, isEmpty);
      final dio = lados.tablet.listaParaRendir.single;
      expect(dio.esDio, isTrue);
      expect(dio.contratoAlumnoId, isNull,
          reason: 'de afuera, aunque se llame como un alumno de la fiesta');
      expect(texto(tester, 'vender_para_rendir_texto'), 'Entradas para rendir: 1 persona');

      await rindeJuan(tester);
      final venta = ventasDeCarla().single;
      expect(venta.compradorNombre, 'PÉREZ, JUAN');
      expect(venta.contratoAlumnoId, isNull);
      expect(venta.cantidad, 15);
      expect(venta.total, 120000);
      expect(venta.medio, MedioBarra.efectivo);
      expect(venta.cajaEntradasId, cajaDeCarla().id, reason: 'la plata, en la caja de Carla');
      expect(find.byKey(const Key('vender_para_rendir')), findsNothing,
          reason: 'ya no le queda ninguna');
      // El comprobante de la rendición, con su botón; la segunda vez, la COPIA.
      expect(lados.papeles.comprobantes, isEmpty, reason: 'ningún papel se abre solo');
      await tocar(tester, 'vender_ver_comprobante_rendicion');
      final comprobante = lados.papeles.comprobantes.single;
      expect(comprobante.venta.id, venta.id);
      expect(comprobante.copia, isFalse);
      expect(comprobante.rendicion!.persona, 'PÉREZ, JUAN');
      expect(comprobante.rendicion!.devolvio, 5);
      expect(comprobante.rendicion!.numerosDevueltos, const [TramoTalonario(1216, 1220)]);
      await tocar(tester, 'vender_ver_comprobante_rendicion');
      expect(lados.papeles.comprobantes.last.copia, isTrue);

      // El jefe: le llegó, y PARA RENDIR dice que rindió todo.
      expect(lados.tablet.pendientes, isEmpty);
      expect(lados.pc.listaVentas.map((v) => v.id), contains(venta.id));
      final enLaPc = paraRendirEn(lados.pc);
      expect(enLaPc.bloques.single.rindioTodo, isTrue);
      expect(enLaPc.bloques.single.plataRendida, 120000);
      expect(chip(tester, 'para_rendir_estado_${enLaPc.porPersona.single.clave}'),
          '✓ rindió todo');
      // Lo de alguien de afuera no es de ninguna familia (PÉREZ, JUAN alumno sigue
      // sin vender nada de lo suyo).
      await cerrarPantalla(tester, ParaRendirScreen);
      expect(enElJefe('0 vendidas de 24'), findsOneWidget);

      // El cierre de Carla, a ciegas: 5.000 de cambio y 120.000 de la rendición.
      await tocar(tester, 'vender_cerrar');
      await poner(tester, 'cierre_contado', '125000');
      await tocar(tester, 'cierre_cerrar');
      await tocar(tester, 'cierre_confirmar');
      expect(texto(tester, 'cierre_esperado'), r'$ 125.000');
      expect(lados.papeles.cierres, isEmpty, reason: 'ningún papel se abre solo');
      await tocar(tester, 'cierre_imprimir');
      expect(lados.papeles.cierres.single.cuentas.efectivoEsperado, 125000);
      expect(lados.papeles.cierres.single.cuentas.efectivo, 120000);
      await tocar(tester, 'cierre_listo');

      // El jefe, en el cierre de caja: la de Carla, cerrada y justa, con su papel.
      final caja = cajaDeCarla();
      expect(caja.abierta, isFalse);
      await tocar(tester, 'prueba_jefe_cierre');
      await tocar(tester, 'cierre_sector_entradas');
      expect(
        tester.widget<Text>(find.byKey(Key('cierre_entradas_diferencia_${caja.id}'))).data,
        'Justo',
      );
      await tocar(tester, 'cierre_entradas_papel_${caja.id}');
      expect(lados.papeles.cierres, hasLength(2));
      expect(lados.papeles.cierres.last.caja.id, caja.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(c) en VENTAS el jefe anula la rendición: las 15 vuelven a quedar a cargo '
        'de PÉREZ, JUAN, también en la tablet, y salen de la caja de Carla', (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);
      await elJefeLeDaAJuan(tester);
      await rindeJuan(tester);
      final venta = ventasDeCarla().single;
      await cerrarPantalla(tester, ParaRendirScreen);

      await tocar(tester, 'entradas_ventas');
      expect(chip(tester, 'rendicion_${venta.id}'), 'RENDICIÓN · de PÉREZ, JUAN');
      await tocar(tester, 'anular_${venta.id}');
      expect(texto(tester, 'anular_rendicion'),
          'Es una rendición: las 15 vuelven a quedar a cargo de PÉREZ, JUAN para rendir.');
      expect(find.byKey(const Key('anular_pregunta')), findsNothing,
          reason: 'no pregunta si devolvieron: los números los lleva el bloque');
      await poner(tester, 'anular_motivo', 'la plata no era de estas');
      await tocar(tester, 'anular_confirmar');
      final anulacion = lados.pc.listaAnulaciones.singleWhere((a) => a.ventaId == venta.id);
      expect(anulacion.devueltas, isFalse);
      expect(texto(tester, 'anulada_${venta.id}'), contains('las 15 dejaron de contar'));

      // Subió: en la tablet también, y VENDER de Carla vuelve a avisar.
      expect(lados.pc.pendientes, isEmpty);
      expect(lados.tablet.listaAnulaciones.map((a) => a.id), contains(anulacion.id));
      expect(paraRendirEn(lados.tablet).bloques.single.sinRendir, 15);
      expect(texto(tester, 'vender_para_rendir_texto'), 'Entradas para rendir: 1 persona');
      // La plata ya no cuenta en la caja de Carla: queda el cambio.
      final caja = cajaDeCarla();
      expect(
        CierreDeEntradas.de(
          caja,
          [for (final v in lados.tablet.listaVentas) if (v.cajaEntradasId == caja.id) v],
          [for (final a in lados.tablet.listaAnulaciones) if (a.cajaEntradasId == caja.id) a],
        ).efectivoEsperado,
        5000,
      );

      // En PARA RENDIR del jefe: le quedan 15.
      await cerrarPantalla(tester, VentasDeEntradasScreen);
      await tocar(tester, 'entradas_para_rendir');
      final clave = paraRendirEn(lados.pc).porPersona.single.clave;
      expect(chip(tester, 'para_rendir_estado_$clave'), 'sin rendir 15');
      expect(tester.takeException(), isNull);
    });

    testWidgets('(c) sin internet de cada lado: lo que da el jefe y lo que rinde Carla '
        'se quedan en su equipo hasta que vuelve el internet', (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);

      // El jefe da sin internet: queda en la PC y la tablet no lo ve.
      await tocar(tester, 'prueba_internet');
      await elJefeLeDaAJuan(tester);
      expect(lados.pc.pendientes.map((p) => p.tabla), ['entradas_para_rendir']);
      expect(lados.tablet.listaParaRendir, isEmpty);
      expect(find.byKey(const Key('vender_para_rendir')), findsNothing);
      // Vuelve: sube, y VENDER de Carla lo dice.
      await tocar(tester, 'prueba_internet');
      expect(lados.pc.pendientes, isEmpty);
      expect(texto(tester, 'vender_para_rendir_texto'), 'Entradas para rendir: 1 persona');

      // Carla rinde sin internet: la venta, lo vendido y lo devuelto quedan en la
      // tablet, y el jefe sigue viendo las 20 sin rendir.
      await tocar(tester, 'prueba_internet');
      await rindeJuan(tester);
      expect(
        lados.tablet.pendientes.map((p) => p.tabla),
        unorderedEquals(['entradas_ventas', 'entradas_para_rendir', 'entradas_para_rendir']),
      );
      expect(texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · Sin internet · 1 venta y 2 cambios por subir');
      final clave = paraRendirEn(lados.pc).porPersona.single.clave;
      expect(paraRendirEn(lados.pc).bloques.single.sinRendir, 20);
      expect(chip(tester, 'para_rendir_estado_$clave'), 'sin rendir 20');

      // Vuelve: sube, y el jefe ve que rindió todo.
      await tocar(tester, 'prueba_internet');
      expect(lados.tablet.pendientes, isEmpty);
      expect(paraRendirEn(lados.pc).bloques.single.rindioTodo, isTrue);
      expect(chip(tester, 'para_rendir_estado_$clave'), '✓ rindió todo');
      expect(texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
      expect(tester.takeException(), isNull);
    });

    testWidgets('(c) rendir lo mismo en los dos equipos sin internet da "rindió de más"; el '
        'jefe anula lo que sobra y queda justo en los dos', (tester) async {
      await abrir(tester, alto: 1400);
      await entrarAVender(tester);
      await elJefeLeDaAJuan(tester);
      await cerrarPantalla(tester, ParaRendirScreen);
      await tocar(tester, 'prueba_internet');

      // Carla, en la tablet, le rinde 15 y le recibe 5.
      await rindeJuan(tester);
      // Vuelve a su inicio: los dos VENDER tienen los mismos botones.
      await cerrarPantalla(tester, VenderEntradasScreen);
      // El jefe, en la PC y sin saber nada, le rinde lo mismo con su caja.
      await tocar(tester, 'entradas_vender');
      expect(find.text('Abrir la caja de entradas'), findsOneWidget);
      await poner(tester, 'abrir_caja_cambio', '0');
      await tocar(tester, 'abrir_caja_abrir');
      expect(texto(tester, 'vender_para_rendir_texto'), 'Entradas para rendir: 1 persona');
      await rindeJuan(tester);
      // Cada equipo, solo, ve justo lo que rindió.
      expect(paraRendirEn(lados.tablet).bloques.single.rindioDeMas, 0);
      expect(paraRendirEn(lados.pc).bloques.single.rindioDeMas, 0);
      expect(lados.papeles.comprobantes, isEmpty,
          reason: 'ningún comprobante se abrió solo, en ningún equipo');

      // Vuelve el internet: los dos tienen las dos rendiciones.
      await tocar(tester, 'prueba_internet');
      for (final base in [lados.tablet, lados.pc]) {
        expect(base.listaVentas.where(ParaRendir.esVentaDeRendicion), hasLength(2));
        expect(paraRendirEn(base).bloques.single.rindioDeMas, 20,
            reason: '15 y 5, dos veces, de las 20 que se llevó');
      }
      // PARA RENDIR del jefe lo avisa: nada se corrige solo.
      await cerrarPantalla(tester, VenderEntradasScreen);
      await tocar(tester, 'entradas_para_rendir');
      final clave = paraRendirEn(lados.pc).porPersona.single.clave;
      expect(chip(tester, 'para_rendir_estado_$clave'), 'rindió de más: revisar');
      expect(find.textContaining('rindió de más, revisar'), findsWidgets);

      // Como dice el aviso: anula en VENTAS la venta que sobra (la de la PC).
      final sobra = lados.pc.listaVentas
          .firstWhere((v) => ParaRendir.esVentaDeRendicion(v) && v.hechoPor != 'Carla');
      await cerrarPantalla(tester, ParaRendirScreen);
      await tocar(tester, 'entradas_ventas');
      await tocar(tester, 'anular_${sobra.id}');
      expect(texto(tester, 'anular_rendicion'),
          'Es una rendición: las 15 dejan de contar como vendidas. PÉREZ, JUAN rindió 20 '
          'de más, así que no le queda ninguna sin rendir.');
      await poner(tester, 'anular_motivo', 'se cobró dos veces');
      await tocar(tester, 'anular_confirmar');
      // Queda lo devuelto dos veces: ese "devolvió" se anula en PARA RENDIR.
      expect(paraRendirEn(lados.pc).bloques.single.rindioDeMas, 5);
      final devolvioDeMas = lados.pc.listaParaRendir
          .singleWhere((m) => m.esDevolvio && m.deviceId == 'pc-oficina');
      await cerrarPantalla(tester, VentasDeEntradasScreen);
      await tocar(tester, 'entradas_para_rendir');
      await tocar(tester, 'para_rendir_persona_$clave');
      await tocar(tester, 'para_rendir_anular_${devolvioDeMas.id}');
      await poner(tester, 'motivo_texto', 'se anotó dos veces');
      await tocar(tester, 'para_rendir_anular_confirmar');
      expect(chip(tester, 'para_rendir_estado_$clave'), '✓ rindió todo');
      expect(find.textContaining('rindió de más, revisar'), findsNothing);

      // A la tablet le llega: rindió justo, con la plata de Carla.
      expect(lados.pc.pendientes, isEmpty);
      final enLaTablet = paraRendirEn(lados.tablet).bloques.single;
      expect(enLaTablet.rindioTodo, isTrue);
      expect(enLaTablet.vendidas, 15);
      expect(enLaTablet.devueltas, 5);
      expect(enLaTablet.plataRendida, 120000);
      expect(tester.takeException(), isNull);
    });
  });

  test('la caja cobra todo lo que debe cada familia, y nadie queda debiendo', () {
    expect(
      {for (final a in lados.familiasQueDeben) a.id},
      {_perez, _benitez, _diaz},
    );
    expect(lados.cobrarTodo(_perez), 70000);
    expect(lados.cobrarTodo(_benitez), closeTo(33333, 0.01));
    expect(lados.cobrarTodo(_diaz), 12500);
    expect(lados.familiasQueDeben, isEmpty);
  });

  test('cortar el internet avisa a la línea de VENDER, y volver sube todo', () async {
    var avisos = 0;
    final sub = lados.entrega.conexion.stream.listen((_) => avisos++);
    addTearDown(sub.cancel);
    lados.cambiarInternet();
    lados.cambiarInternet();
    await Future<void>.delayed(Duration.zero);
    expect(avisos, 2);
    expect(lados.entrega.conexion.currentStatus, AppConnectivity.online);
  });
}
