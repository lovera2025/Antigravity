import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/pedido_de_cierre.dart';
import 'package:arguello_events/features/barra/cuentas/pesos.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/barra/widgets/catalogo_y_precios_screen.dart';
import 'package:arguello_events/features/barra/widgets/las_cajas_screen.dart';
import 'package:arguello_events/features/barra/widgets/ok_del_cierre.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/services/entrada_de_operador.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// La Encargada de barra (6.4.0): entra por BARRA con su PIN, vende con su caja como
/// las demás y además ve LAS CAJAS de la fiesta (con cuánto cambio arrancó cada una y
/// las sillas vendidas) y anula o reimprime cualquier venta, con motivo. La cajera no.
/// En la tablet no aparece PRENDER LA CENTRAL.
const _romi = 'a0000000-0000-4000-8000-000000000007';

/// Este aparato ya habla (o no) con la central de la barra, sin abrir ninguna conexión.
class _ConCliente extends ClienteDeLaBarra {
  _ConCliente(this.cliente);

  final ClienteDeLaCentral? cliente;

  @override
  ClienteDeLaCentral? build() => cliente;
}

void main() {
  final hoy = DateTime.now();
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late CajaBarra marta;
  late VentaBarra fernetDeMarta, sillaDeMarta;

  /// Cuántas veces sonó el aviso de "una caja pide cerrar".
  var sonidos = 0;

  setUp(() async {
    sonidos = 0;
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_romi, 'Romi', '7777'));
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', hoy.add(const Duration(days: 2)));
    prueba.eventos.add(fiesta);
    final b = prueba.barra;
    // La noche de hoy (25-nov-2026: LAS CAJAS muestra una noche por vez): las cajas de
    // esta prueba se abren ahora.
    b.reloj = () => DateTime.now().toUtc();
    final fernet = b.producto('Fernet con coca');
    final silla = b.producto('Silla extra');
    b.precio(fiesta.id, fernet, 6000);
    b.precio(fiesta.id, silla, 8000);
    // Otra cajera, con su caja y su cambio.
    marta = await b.abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'marta',
      operadorNombre: 'Marta',
      numeroCaja: 2,
      cambioInicial: 15000,
    );
    fernetDeMarta = await b.vender(
      caja: marta,
      renglones: [RenglonVenta(productoId: fernet.id, nombre: fernet.nombre, precio: 6000, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 12000,
      quien: 'Marta',
    );
    sillaDeMarta = await b.vender(
      caja: marta,
      renglones: [RenglonVenta(productoId: silla.id, nombre: silla.nombre, precio: 8000, cantidad: 1)],
      medio: MedioBarra.transferencia,
      transferencia: 8000,
      quien: 'Marta',
    );
    for (final v in [fernetDeMarta, sillaDeMarta]) {
      await b.anotarVale(ValeBarra.salio(
        venta: v,
        bebidas: [for (final r in v.renglones) BebidaDelVale(r.cantidad, r.nombre)],
        porSeparado: false,
        hechoPor: 'Marta',
        ahora: DateTime(2026, 12, 4, 23),
      ));
    }
  });

  Future<void> abrir(
    WidgetTester tester, {
    required PermisosEfectivos permisos,
    Size tamano = const Size(1024, 800),
    bool enLaNotebook = false,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        // En la tablet: la barra del equipo, sin modo jefe y sin la central. En la
        // notebook de la barra, la central se prende (sin modo jefe: 26-nov-2026).
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        centralSePrendeAcaProvider.overrideWithValue(enLaNotebook),
        sonarPedidoDeCierreProvider.overrideWithValue(() => sonidos++),
      ],
      child: MaterialApp(home: BarraHomeScreen(onCajaLista: (_, _, _) {})),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(BarraHomeScreen)));
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          operadores.operadores.lista.single,
          permisos,
        );
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    // En el celular lo de abajo de una lista larga no está armado: se desliza hasta verlo.
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  bool apagado(WidgetTester tester, String clave) {
    final w = tester.widget(find.byKey(Key(clave)));
    return switch (w) {
      ButtonStyleButton b => b.onPressed == null,
      _ => fail('$clave no es un botón'),
    };
  }

  test('con el PIN, la encargada entra derecho a la barra, por el mismo botón', () {
    final sola = OpcionesDeEntrada.de(const PermisosEfectivos(encargadaBarra: true));
    expect(sola.directo, PermisoOperador.barra);
    final conCobros = OpcionesDeEntrada.de(
      const PermisosEfectivos(cobros: true, encargadaBarra: true),
    );
    expect(conCobros.paraElegir, [PermisoOperador.cobros, PermisoOperador.barra]);
  });

  test('es encargada solo adentro de la barra, y manda en las cajas', () {
    final container = ProviderContainer(overrides: operadores.reemplazos);
    addTearDown(container.dispose);
    expect(container.read(mandaEnLaBarraProvider), isFalse);
  });

  testWidgets('la cajera no ve LAS CAJAS', (tester) async {
    await abrir(tester, permisos: const PermisosEfectivos(barra: true));
    expect(find.byKey(Key('barra_las_cajas_${fiesta.id}')), findsNothing);
    expect(find.byKey(const Key('barra_impresora')), findsOneWidget, reason: 'la impresora sí');
  });

  testWidgets('la encargada ve LAS CAJAS: el cambio de cada una y las sillas vendidas, sin '
      'la central', (tester) async {
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    expect(find.byType(LasCajasScreen), findsOneWidget);
    expect(find.byKey(Key('jefe_caja_${marta.id}')), findsOneWidget);
    final cambio = find.byKey(Key('jefe_caja_cambio_${marta.id}'));
    expect(find.descendant(of: cambio, matching: find.text(r'$ 15.000')), findsOneWidget);
    final sillas = find.byKey(Key('jefe_caja_sillas_${marta.id}'));
    expect(find.descendant(of: sillas, matching: find.text('1')), findsOneWidget);
    expect(find.text('PRENDER LA CENTRAL'), findsNothing, reason: 'en la tablet no se prende');
    expect(find.byKey(const Key('jefe_pestana_catalogo')), findsNothing, reason: 'ni catálogo');
    expect(find.byKey(const Key('jefe_pestana_precios')), findsNothing, reason: 'ni precios');
    expect(tester.takeException(), isNull);
  });

  testWidgets('la encargada anula una venta de otra caja, con motivo, a su nombre',
      (tester) async {
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
    expect(apagado(tester, 'jefe_anular_${fernetDeMarta.id}'), isFalse);
    await tocar(tester, find.byKey(Key('jefe_anular_${fernetDeMarta.id}')));
    await tester.enterText(find.byKey(const Key('motivo_texto')), 'se cobró dos veces');
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(const Key('motivo_anular')));
    final a = prueba.barra.anulacionesGuardadas.single;
    expect(a.ventaId, fernetDeMarta.id);
    expect(a.motivo, 'se cobró dos veces');
    expect(a.hechoPor, 'Romi');
    expect(prueba.subidasDeLaBarra, contains('barra_anulaciones ${a.id}'));
    expect(find.byKey(Key('jefe_anulada_${fernetDeMarta.id}')), findsOneWidget);
  });

  testWidgets('la encargada reimprime cualquier venta, con COPIA y su nombre', (tester) async {
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
    await tocar(tester, find.byKey(Key('jefe_reimprimir_${fernetDeMarta.id}')));
    await tester.enterText(find.byKey(const Key('motivo_texto')), 'se le mojó');
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(const Key('motivo_reimprimir')));
    expect(prueba.papel.papeles.single, contains('*** COPIA ***'));
    final copia = prueba.barra.valesGuardados.where((v) => v.esCopia).single;
    expect(copia.hechoPor, 'Romi');
  });

  // ── El cierre con el OK de la encargada (11-nov-2026) ───────────────────────

  /// Marta contó y pide cerrar: su pedido llegó a este aparato.
  Future<PasoDelCierre> pideCerrar({double contado = 20500}) async {
    final pedido = PasoDelCierre.pedir(
      caja: marta,
      efectivoContado: contado,
      nota: 'faltó un billete',
      hechoPor: 'Marta',
      ahora: DateTime.utc(2026, 12, 5, 8),
    ).conEquipo('tablet-de-marta');
    expect(await prueba.barra.guardarDeOtroEquipo('barra_cierres', pedido.toMap()), isTrue);
    return pedido;
  }

  Future<void> unaVuelta(WidgetTester tester) async {
    await tester.pump(kMirarPedidosDeCierre + const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  String texto(WidgetTester tester, String clave) => tester.widget<Text>(find.byKey(Key(clave))).data!;

  testWidgets('a la encargada le salta "la Caja pide cerrar", ve los totales y acepta', (tester) async {
    final pedido = await pideCerrar();
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    expect(find.byKey(Key('aviso_cierre_${marta.id}')), findsOneWidget);
    expect(find.text('La Caja ${marta.numeroCaja} (Marta) pide cerrar'), findsOneWidget);
    expect(sonidos, 1);

    await tocar(tester, find.byKey(Key('aviso_cierre_ver_${marta.id}')));
    final cuentas = CierreDeBarra.de(marta, prueba.barra.ventasGuardadas, const []);
    expect(texto(tester, 'ok_cierre_esperado'), pesos(cuentas.efectivoEsperado));
    expect(texto(tester, 'ok_cierre_conto'), r'$ 20.500');
    expect(texto(tester, 'ok_cierre_diferencia'), diferenciaEnPalabras(cuentas.diferenciaCon(20500)));
    expect(texto(tester, 'ok_cierre_transferencia'), r'$ 8.000');
    expect(texto(tester, 'ok_cierre_total'), pesos(cuentas.total));
    expect(texto(tester, 'ok_cierre_nota'), 'Nota de la cajera: faltó un billete');

    await tocar(tester, find.byKey(const Key('ok_cierre_aceptar')));
    final ok = prueba.barra.pasosGuardados.last;
    expect(ok.tipo, TipoPasoDelCierre.ok);
    expect(ok.pedidoId, pedido.id);
    expect(ok.hechoPor, 'Romi');
    expect(prueba.subidasDeLaBarra, contains('barra_cierres ${ok.id}'));
    // El aparato de la encargada no toca la caja de Marta: la cierra su tablet.
    expect(prueba.barra.cajasGuardadas.firstWhere((c) => c.id == marta.id).abierta, isTrue);
    // Ya contestado, el aviso se va.
    expect(find.byKey(Key('aviso_cierre_${marta.id}')), findsNothing);
    expect(texto(tester, 'aviso_cierre_dicho'), contains('Aceptaste el cierre de la Caja ${marta.numeroCaja}'));
    await unaVuelta(tester);
    expect(sonidos, 1, reason: 'suena una vez por pedido');
  });

  testWidgets('el pedido que llega con LAS CAJAS abierta aparece solo, y puede pedir que cuente de nuevo',
      (tester) async {
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    expect(find.byKey(const Key('aviso_cierres')), findsNothing);
    final pedido = await pideCerrar();
    await unaVuelta(tester);
    expect(find.byKey(Key('aviso_cierre_${marta.id}')), findsOneWidget);
    expect(sonidos, 1);
    await unaVuelta(tester);
    expect(sonidos, 1);

    await tocar(tester, find.byKey(Key('aviso_cierre_ver_${marta.id}')));
    await tocar(tester, find.byKey(const Key('ok_cierre_recontar')));
    expect(prueba.barra.pasosGuardados.last.tipo, TipoPasoDelCierre.recontar);
    expect(prueba.barra.pasosGuardados.last.pedidoId, pedido.id);
    expect(find.byKey(Key('aviso_cierre_${marta.id}')), findsNothing);
  });

  testWidgets('DESPUÉS no contesta nada: el aviso sigue ahí', (tester) async {
    await pideCerrar();
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    await tocar(tester, find.byKey(Key('aviso_cierre_ver_${marta.id}')));
    await tocar(tester, find.byKey(const Key('ok_cierre_despues')));
    expect(prueba.barra.pasosGuardados, hasLength(1));
    expect(find.byKey(Key('aviso_cierre_${marta.id}')), findsOneWidget);
  });

  testWidgets('una caja que cerró sin el OK de la encargada queda marcada en LAS CAJAS', (tester) async {
    final pedido = await pideCerrar();
    final sinOk = PasoDelCierre.responder(
      pedido: pedido,
      tipo: TipoPasoDelCierre.sinOk,
      nota: 'no había encargada',
      hechoPor: 'Marta',
      ahora: DateTime.utc(2026, 12, 5, 8, 4),
    ).conEquipo('tablet-de-marta');
    await prueba.barra.guardarDeOtroEquipo('barra_cierres', sinOk.toMap());
    await prueba.barra.cerrarCaja(
      marta,
      efectivoContado: 20500,
      diferencia: -500,
      nota: PedidoDeCierre.notaSinElOk(motivo: 'no había encargada'),
      quien: 'Marta',
    );
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    expect(find.byKey(Key('jefe_caja_sin_ok_${marta.id}')), findsOneWidget);
    expect(find.byKey(const Key('aviso_cierres')), findsNothing, reason: 'cerrada, ya no pide nada');
  });

  testWidgets('en un celular, el aviso y los totales no se desbordan', (tester) async {
    await pideCerrar();
    await abrir(
      tester,
      permisos: const PermisosEfectivos(encargadaBarra: true),
      tamano: const Size(360, 740),
    );
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    expect(tester.takeException(), isNull);
    await tocar(tester, find.byKey(Key('aviso_cierre_ver_${marta.id}')));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ok_cierre_aceptar')), findsOneWidget);
  });

  testWidgets('en un celular, LAS CAJAS no se desborda', (tester) async {
    await abrir(
      tester,
      permisos: const PermisosEfectivos(encargadaBarra: true),
      tamano: const Size(360, 740),
    );
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    await tocar(tester, find.byKey(Key('jefe_caja_${marta.id}')));
    expect(tester.takeException(), isNull);
  });

  // 26-nov-2026 (noche): esa noche la notebook no se pone en modo jefe; la encargada
  // prende la central desde LAS CAJAS, y ve el catálogo y los precios de venta solo
  // mirando. Nunca el precio de lista, las recetas ni la ganancia.
  test('quién ve el catálogo y los precios, y quién el costo y la ganancia', () {
    expect(ReglasDeLaBarra.veCatalogoYPrecios(RolEnLaBarra.encargada), isTrue);
    expect(ReglasDeLaBarra.veCatalogoYPrecios(RolEnLaBarra.jefe), isTrue);
    expect(ReglasDeLaBarra.veCatalogoYPrecios(RolEnLaBarra.cajera), isFalse);
    expect(ReglasDeLaBarra.veCatalogoYPrecios(RolEnLaBarra.repositor), isFalse);
    expect(ReglasDeLaBarra.veCatalogoYPrecios(null), isFalse);
    expect(ReglasDeLaBarra.cambiaCatalogoYPrecios(RolEnLaBarra.encargada), isFalse);
    expect(ReglasDeLaBarra.veElCostoYLaGanancia(RolEnLaBarra.jefe), isTrue);
    for (final r in [RolEnLaBarra.encargada, RolEnLaBarra.cajera, RolEnLaBarra.repositor, null]) {
      expect(ReglasDeLaBarra.veElCostoYLaGanancia(r), isFalse, reason: '$r');
    }
  });

  testWidgets('en la notebook, la encargada prende la central sin modo jefe', (tester) async {
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true), enLaNotebook: true);
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    expect(find.text('PRENDER LA CENTRAL'), findsOneWidget);
    expect(find.byKey(const Key('jefe_pestana_catalogo')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la encargada ve el catálogo y los precios de venta, sin poder cambiarlos', (tester) async {
    await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
    await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
    await tocar(tester, find.byKey(const Key('las_cajas_catalogo_precios')));
    expect(find.byType(CatalogoYPreciosScreen), findsOneWidget);
    expect(find.text('Fernet con coca'), findsOneWidget);
    expect(find.text(r'$ 6.000'), findsOneWidget);
    expect(find.text(r'$ 8.000'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'nada para escribir');
    for (final no in ['GUARDAR CAMBIOS', 'COPIAR DE OTRA FIESTA', 'GANANCIA', 'Lista']) {
      expect(find.textContaining(no), findsNothing, reason: no);
    }
    expect(tester.takeException(), isNull);
  });

  // 28-nov-2026 (decisión del usuario: "que avise el 5 %"): sin elegir decía "Sin recargo"
  // y cada cobro arrancaba con el último de la tablet, la primera vez 5 %.
  for (final (pct, dice) in [
    (null, 'Recargo por transferencia sin elegir: cada tablet arranca con el último que usó (la primera vez, 5 %).'),
    (0.0, 'Sin recargo por transferencia en esta fiesta.'),
    (8.0, 'Recargo por transferencia: 8 %, sobre lo transferido.'),
  ]) {
    testWidgets('el recargo de la fiesta, a la vista de la encargada: ${pct ?? 'sin elegir'}', (tester) async {
      if (pct != null) {
        prueba.barra.recargosGuardados.add(RecargoBarra.para(eventoId: fiesta.id, pct: pct, ahora: DateTime.now()));
      }
      await abrir(tester, permisos: const PermisosEfectivos(encargadaBarra: true));
      await tocar(tester, find.byKey(Key('barra_las_cajas_${fiesta.id}')));
      await tocar(tester, find.byKey(const Key('las_cajas_catalogo_precios')));
      expect(tester.widget<Text>(find.byKey(const Key('catalogo_precios_recargo'))).data, dice);
    });
  }

  testWidgets('LAS CAJAS pregunta la regla: con otro rol, sin CATÁLOGO Y PRECIOS', (tester) async {
    for (final (rol, ve) in [
      (RolEnLaBarra.cajera, false),
      (RolEnLaBarra.repositor, false),
      (RolEnLaBarra.encargada, true),
    ]) {
      await tester.pumpWidget(ProviderScope(
        key: ValueKey(rol),
        overrides: [
          ...operadores.reemplazos,
          ...prueba.reemplazos,
          barraDelJefeProvider.overrideWithValue(prueba.barra),
          centralSePrendeAcaProvider.overrideWithValue(false),
          rolEnLaBarraProvider.overrideWithValue(rol),
        ],
        child: MaterialApp(home: LasCajasScreen(fiesta: fiesta)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('las_cajas_catalogo_precios')), ve ? findsOneWidget : findsNothing,
          reason: '$rol');
    }
  });

  // 28-nov-2026 (el hallazgo 2 de la revisión de los roles): en LAS CAJAS de la tablet
  // de la encargada no se veía cómo estaba la central ni lo que no le había aceptado.
  testWidgets('LAS CAJAS en la tablet de la encargada lleva la línea de la central (la de '
      'VENDER); sin central o en la web, no', (tester) async {
    for (final (caso, conCliente, enLaWeb, seVe) in [
      ('la tablet con la central', true, false, true),
      ('sin haberla buscado', false, false, false),
      ('la web', true, true, false),
    ]) {
      final cliente = conCliente
          ? ClienteDeLaCentral(
              eventoId: fiesta.id,
              equipo: 'tablet-romi',
              nombreCaja: 'Encargada · Romi',
              barra: prueba.barra,
              credencial: () async => null,
            )
          : null;
      await tester.pumpWidget(ProviderScope(
        key: ValueKey(caso),
        overrides: [
          ...operadores.reemplazos,
          ...prueba.reemplazos,
          barraDelJefeProvider.overrideWithValue(prueba.barra),
          centralSePrendeAcaProvider.overrideWithValue(false),
          rolEnLaBarraProvider.overrideWithValue(RolEnLaBarra.encargada),
          enLaWebProvider.overrideWithValue(enLaWeb),
          clienteDeLaBarraProvider.overrideWith(() => _ConCliente(cliente)),
        ],
        child: MaterialApp(home: LasCajasScreen(fiesta: fiesta)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('caja_subida')), seVe ? findsOneWidget : findsNothing, reason: caso);
      expect(find.byKey(const Key('las_cajas_titulo')), findsOneWidget, reason: caso);
    }
  });

  testWidgets('la cajera no tiene CATÁLOGO Y PRECIOS', (tester) async {
    await abrir(tester, permisos: const PermisosEfectivos(barra: true));
    expect(find.byKey(const Key('las_cajas_catalogo_precios')), findsNothing);
  });

  test('CATÁLOGO Y PRECIOS no nombra el costo ni la ganancia, ni guarda nada', () {
    final fuente = File('lib/features/barra/widgets/catalogo_y_precios_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final codigo = fuente.split('\n').where((l) => !l.trimLeft().startsWith('///')).join('\n');
    for (final prohibido in [
      'precioLista',
      'barra_costos',
      'CostoBarra',
      'CuentaDelProveedor',
      'receta',
      'guardar',
      'TextField',
      'esRolJefeProvider',
    ]) {
      expect(codigo.contains(prohibido), isFalse, reason: prohibido);
    }
    expect(codigo, contains('ReglasDeLaBarra.veCatalogoYPrecios'));
  });
}
