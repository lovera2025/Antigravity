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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/features/entradas/widgets/vender_entradas_screen.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

import '../tool/venta_entradas_prueba.dart';
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
    expect(find.byKey(const Key('vender_falta')), findsNothing);
    await tocar(tester, 'vender_efectivo');
    await tocar(tester, 'cobro_confirmar');
  }

  /// Lo que Carla vendió en la tablet.
  List<VentaEntradas> ventasDeCarla() => [
        for (final v in lados.tablet.listaVentas)
          if (v.hechoPor == 'Carla') v,
      ];

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

    // Carla, en VENDER: la línea lo dice.
    await tocar(tester, 'vender_$idFiestaEntrega');
    await asentar(tester);
    expect(
      texto(tester, 'vender_linea_texto'),
      'Caja abierta · Carla · Sin internet · 1 venta por subir',
    );

    await tocar(tester, 'prueba_internet');
    await asentar(tester);
    expect(lados.hayInternet, isTrue);
    expect(lados.tablet.pendientes, isEmpty);
    expect(enElJefe('3 vendidas de 24'), findsOneWidget);
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

  testWidgets('Carla, con el mouse: abre la caja, le vende a PÉREZ y sale el comprobante',
      (tester) async {
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
    expect(lados.papeles.comprobantes, hasLength(1));
    expect(lados.papeles.comprobantes.single.venta.cantidad, 3);
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
      expect(lados.papeles.comprobantes.single.venta.id, venta.id);
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
