import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/cierre_caja/cierre_caja_screen.dart';
import 'package:arguello_events/features/cierre_caja/services/sector_del_cierre.dart';
import 'package:arguello_events/features/cierre_caja/widgets/sector_barra.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/cierre_en_memoria.dart';
import 'helpers/noche_de_barra.dart';

/// El cierre de caja por sector (6.4.0, decidido el 5-nov): COBROS · BARRA · ENTRADAS
/// arriba, en modo jefe. BARRA va por fiesta, una línea por caja, solo para mirar; la
/// plata de cada sector no se mezcla.
void main() {
  late BarraEnPrueba prueba;
  late Evento pinaroli, rotonda;
  late CajaBarra marta, lucas;
  final hoy = DateTime(2026, 12, 5, 11); // la mañana siguiente a PINAROLI

  RenglonVenta renglon(ProductoBarra p, double precio, int cantidad) =>
      RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: cantidad);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prueba = BarraEnPrueba();
    pinaroli = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    rotonda = fiestaDePrueba(BarraEnPrueba.id(2), 'ROTONDA', DateTime(2026, 12, 12, 22));
    prueba.eventos.addAll([pinaroli, rotonda]);
    final b = prueba.barra;
    final fernet = b.producto('Fernet con Coca');
    final silla = b.producto('Silla extra');
    b.precio(pinaroli.id, fernet, 6000);
    b.precio(pinaroli.id, silla, 8000);
    marta = await b.abrirCaja(
      eventoId: pinaroli.id,
      operadorId: 'm',
      operadorNombre: 'Marta',
      numeroCaja: 1,
      cambioInicial: 20000,
    );
    await b.vender(
      caja: marta,
      renglones: [renglon(fernet, 6000, 3)],
      medio: MedioBarra.efectivo,
      efectivo: 18000,
      quien: 'Marta',
    );
    await b.vender(
      caja: marta,
      renglones: [renglon(silla, 8000, 2)],
      medio: MedioBarra.mixto,
      efectivo: 6000,
      transferencia: 10000,
      quien: 'Marta',
    );
    lucas = await b.abrirCaja(
      eventoId: pinaroli.id,
      operadorId: 'l',
      operadorNombre: 'Lucas',
      numeroCaja: 2,
      cambioInicial: 10000,
    );
    await b.vender(
      caja: lucas,
      renglones: [renglon(fernet, 6000, 4)],
      medio: MedioBarra.efectivo,
      efectivo: 24000,
      quien: 'Lucas',
    );
    lucas = await b.cerrarCaja(lucas, efectivoContado: 33500, diferencia: -500, quien: 'Lucas');
  });

  group('lo que decide', () {
    test('sin modo jefe, solo Cobros; con modo jefe, los tres', () {
      expect(sectoresDelCierre(modoJefe: false), [SectorDelCierre.cobros]);
      expect(
        sectoresDelCierre(modoJefe: true),
        [SectorDelCierre.cobros, SectorDelCierre.barra, SectorDelCierre.entradas],
      );
      expect([for (final s in SectorDelCierre.values) s.nombre], ['COBROS', 'BARRA', 'ENTRADAS']);
    });

    test('el resumen suma las sillas y el cambio de todas las cajas', () async {
      final b = prueba.barra;
      final r = ResumenDeCajas.de(
        cajas: await b.cajas(pinaroli.id),
        ventas: await b.ventas(pinaroli.id),
        anulaciones: await b.anulaciones(pinaroli.id),
      );
      expect(r.sillas, 2);
      expect(r.cambio, 30000);
      expect(r.mixtos, 1);
    });
  });

  Future<void> abrir(WidgetTester tester, {Size tamano = const Size(1100, 900)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...prueba.reemplazos,
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        relojDelJefeProvider.overrideWithValue(() => hoy),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SectorBarraDelCierre(isDark: false))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String texto(WidgetTester tester, String clave) =>
      tester.widget<Text>(find.byKey(Key(clave))).data!;

  testWidgets('BARRA: la fiesta de anoche, una línea por caja, los totales y las sillas',
      (tester) async {
    await abrir(tester);
    expect(texto(tester, 'cierre_barra_fiesta'), 'TÉCNICA PINAROLI');
    expect(find.text('viernes 4 de diciembre · anoche'), findsOneWidget,
        reason: 'la de anoche sigue al otro día');
    expect(texto(tester, 'cierre_barra_caja_${marta.id}'), 'Caja 1 · Marta · abierta');
    expect(texto(tester, 'cierre_barra_caja_${lucas.id}'), 'Caja 2 · Lucas');
    expect(find.text(r'$ 20.000'), findsOneWidget, reason: 'el cambio de Marta');
    expect(find.text(r'Faltan $ 500'), findsNWidgets(2), reason: 'la caja y el total');
    expect(find.byKey(const Key('cierre_barra_total')), findsOneWidget);
    expect(find.text(r'$ 30.000'), findsOneWidget, reason: 'el cambio de las dos');
    expect(find.text('2 vendidas'), findsOneWidget, reason: 'las sillas');
    expect(find.text(r'$ 58.000'), findsOneWidget, reason: 'lo vendido');
    expect(tester.takeException(), isNull);
  });

  testWidgets('CAMBIAR DE FIESTA: otra fiesta sin cajas lo dice', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('cierre_barra_cambiar_fiesta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('jefe_fiesta_${rotonda.id}')));
    await tester.pumpAndSettle();
    expect(texto(tester, 'cierre_barra_fiesta'), 'ROTONDA');
    expect(find.byKey(const Key('cierre_barra_sin_cajas')), findsOneWidget);
  });

  testWidgets('en un celular no se desborda: la tabla se desliza de costado', (tester) async {
    await abrir(tester, tamano: const Size(360, 740));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ENTRADAS: todavía no hay ventas', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SectorEntradasDelCierre(isDark: true))));
    expect(find.text('Todavía no hay ventas de entradas'), findsOneWidget);
  });

  group('la pantalla de verdad', () {
    Future<void> abrirCierre(WidgetTester tester, {required bool modoJefe}) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final noche = await tester.runAsync(() => nocheDeBarra(fotos: false));
      await tester.pumpWidget(ProviderScope(
        overrides: reemplazosDelCierre(noche!, modoJefe: modoJefe),
        child: const MaterialApp(home: CierreCajaScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('sin modo jefe, el cierre de siempre, sin las pestañas', (tester) async {
      await abrirCierre(tester, modoJefe: false);
      expect(find.byKey(const Key('cierre_sector')), findsNothing);
      expect(find.text('REGISTRAR RETIRO'), findsOneWidget);
    });

    testWidgets('en modo jefe: COBROS como siempre, BARRA con sus cajas y sin REGISTRAR '
        'RETIRO, ENTRADAS vacío, y vuelve a COBROS', (tester) async {
      await abrirCierre(tester, modoJefe: true);
      expect(find.byKey(const Key('cierre_sector')), findsOneWidget);
      expect(find.text('REGISTRAR RETIRO'), findsOneWidget);
      expect(find.text('MOVIMIENTOS DEL DÍA'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cierre_sector_barra')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cierre_barra_fiesta')), findsOneWidget);
      expect(find.byKey(const Key('cierre_barra_total')), findsOneWidget);
      expect(find.text('REGISTRAR RETIRO'), findsNothing, reason: 'el retiro es de Cobros');
      expect(find.text('MOVIMIENTOS DEL DÍA'), findsNothing);

      await tester.tap(find.byKey(const Key('cierre_sector_entradas')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cierre_entradas_vacio')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cierre_sector_cobros')));
      await tester.pumpAndSettle();
      expect(find.text('REGISTRAR RETIRO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('la pantalla del cierre: el selector solo en modo jefe, y los movimientos y la barra '
      'de abajo (REGISTRAR RETIRO, PDF) solo en COBROS', () {
    final f = File('lib/features/cierre_caja/cierre_caja_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(f, contains('final sectores = sectoresDelCierre(modoJefe: modoJefe);'));
    expect(f, contains('if (sectores.length > 1) ...['));
    expect(f, contains('bottomNavigationBar: esCobros ? _bottomBar(context, state, isDark) : null,'));
    final i = f.indexOf('if (esCobros) ...[');
    expect(i, greaterThanOrEqualTo(0));
    expect(f.indexOf("'MOVIMIENTOS SIN SESIÓN'"), greaterThan(i));
    expect(f.indexOf('_movimientoTile(context, m, isDark, muted)'), greaterThan(i));
    // La plata de la barra no entra en las cuentas de Cobros.
    for (final ruta in [
      'lib/features/cierre_caja/providers/cierre_caja_provider.dart',
      'lib/features/cierre_caja/services/datos_cierre_sesion.dart',
    ]) {
      expect(File(ruta).readAsStringSync(), isNot(contains('barra')), reason: ruta);
    }
  });
}
