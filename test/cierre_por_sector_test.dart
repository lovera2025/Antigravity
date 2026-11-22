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
import 'package:arguello_events/features/cierre_caja/providers/caja_de_entregas_provider.dart';
import 'package:arguello_events/features/cierre_caja/services/sector_del_cierre.dart';
import 'package:arguello_events/features/cierre_caja/widgets/sector_barra.dart';
import 'package:arguello_events/features/cierre_caja/widgets/sector_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart'
    hide MedioBarra;
import 'package:arguello_events/features/entradas/pdf/cierre_caja_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/cierre_en_memoria.dart';
import 'helpers/entradas_en_memoria.dart';
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

  // ENTRADAS (6.9.0, sección 9.2 del spec del 13-nov): por fiesta, una línea por caja.
  group('ENTRADAS', () {
    Future<void> abrirEntradas(
      WidgetTester tester,
      EntradasEnMemoria entradas, {
      Size tamano = const Size(1100, 900),
      bool enLaWeb = false,
      List<DatosDelCierreDeEntradas>? papeles,
    }) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...prueba.reemplazos,
          // PAPEL DEL CIERRE (22-nov-2026): se anota, no se abre.
          abrirCierreDeEntradasProvider.overrideWithValue((datos, {context}) async {
            papeles?.add(datos);
          }),
          // En la web no hay base del equipo: la pantalla no la tiene que leer.
          if (!enLaWeb) ...entradas.reemplazos,
          if (enLaWeb) entradasEnEsteEquipoProvider.overrideWithValue(false),
          barraDelJefeProvider.overrideWithValue(prueba.barra),
          relojDelJefeProvider.overrideWithValue(() => hoy),
          // La caja de entregas, vacía: sin esto leería la base del equipo.
          cajaDeEntregasDeLaFiestaProvider.overrideWith((ref, id) async => cajaDeEntregasVacia),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SectorEntradasDelCierre(isDark: false)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    RenglonEntradas sueltas(int n, {double descuento = 0}) => RenglonEntradas.suelta(
          nombre: 'Entrada',
          precioLista: 10000,
          descuentoPct: descuento,
          cantidad: n,
        );

    /// Carla, abierta: $ 5.000 de cambio, 2 en efectivo y 1 con el 50 % a mano por
    /// transferencia. Maxi, cerrada con $ 500 de menos: 3 en efectivo, una venta
    /// anulada antes de cerrar y otra después.
    Future<(CajaEntradas, CajaEntradas)> dosCajas(EntradasEnMemoria e) async {
      e.conPrecio(pinaroli.id);
      final carla = await e.abrirCaja(
          eventoId: pinaroli.id, operadorId: 'carla', operadorNombre: 'Carla', cambioInicial: 5000);
      final maxi = await e.abrirCaja(
          eventoId: pinaroli.id, operadorId: 'maxi', operadorNombre: 'Maxi', cambioInicial: 2000);
      await e.vender(
          caja: carla, compradorNombre: 'A', renglones: [sueltas(2)],
          medio: MedioBarra.efectivo, efectivo: 20000, quien: 'Carla');
      await e.vender(
          caja: carla, compradorNombre: 'B', renglones: [sueltas(1, descuento: 50)],
          medio: MedioBarra.transferencia, transferencia: 5000, quien: 'Carla');
      await e.vender(
          caja: maxi, compradorNombre: 'C', renglones: [sueltas(3)],
          medio: MedioBarra.efectivo, efectivo: 30000, quien: 'Maxi');
      final antes = await e.vender(
          caja: maxi, compradorNombre: 'D', renglones: [sueltas(1)],
          medio: MedioBarra.efectivo, efectivo: 10000, quien: 'Maxi');
      final despues = await e.vender(
          caja: maxi, compradorNombre: 'E', renglones: [sueltas(1)],
          medio: MedioBarra.efectivo, efectivo: 10000, quien: 'Maxi');
      await e.anular(antes, motivo: 'error', devueltas: true, quien: 'Jefe');
      // Tenía que haber 2.000 + 30.000 + 10.000 = 42.000; contó 41.500.
      final cerrada = await e.cerrarCaja(maxi,
          efectivoContado: 41500, diferencia: -500, quien: 'Maxi');
      e.adelantar(const Duration(hours: 3));
      await e.anular(despues, motivo: 'pagó dos veces', devueltas: true, quien: 'Jefe');
      return (carla, cerrada);
    }

    testWidgets('sin precio en la fiesta lo dice', (tester) async {
      await abrirEntradas(tester, EntradasEnMemoria());
      expect(texto(tester, 'cierre_entradas_fiesta'), 'TÉCNICA PINAROLI');
      expect(texto(tester, 'cierre_entradas_sin_precio'),
          'Esta fiesta todavía no tiene precio de entrada: se pone en ENTRADAS → PRECIOS.');
      // La caja de entregas va igual: lo sin cargo no necesita caja ni precio
      // (20-nov-2026).
      expect(find.byKey(const Key('cierre_entregas')), findsOneWidget);
      expect(find.byKey(const Key('cierre_entregas_vacio')), findsOneWidget);
    });

    // Revisión del 15-nov: con la lista de BARRA podía abrir en un particular.
    testWidgets('abre en el evento masivo, aunque antes haya un particular', (tester) async {
      prueba.eventos.add(fiestaDePrueba(
          BarraEnPrueba.id(9), 'CASAMIENTO', DateTime(2026, 12, 4, 12),
          modalidad: 'particular'));
      await abrirEntradas(tester, EntradasEnMemoria()..conPrecio(pinaroli.id));
      expect(texto(tester, 'cierre_entradas_fiesta'), 'TÉCNICA PINAROLI');
    });

    testWidgets('con precio y sin cajas lo dice', (tester) async {
      await abrirEntradas(tester, EntradasEnMemoria()..conPrecio(pinaroli.id));
      expect(texto(tester, 'cierre_entradas_sin_cajas'),
          'Todavía no se abrió ninguna caja de entradas en esta fiesta.');
      expect(find.textContaining('fuera de la app'), findsNothing);
    });

    testWidgets('dos cajas: una abierta y una cerrada, los totales y lo anulado después',
        (tester) async {
      final e = EntradasEnMemoria();
      final (carla, maxi) = await dosCajas(e);
      await abrirEntradas(tester, e);
      expect(texto(tester, 'cierre_entradas_caja_${carla.id}'), 'Carla · abierta');
      expect(texto(tester, 'cierre_entradas_caja_${maxi.id}'), 'Maxi');
      expect(texto(tester, 'cierre_entradas_diferencia_${maxi.id}'), r'Faltan $ 500');
      expect(find.text('abierta'), findsOneWidget, reason: 'la diferencia de Carla');
      expect(find.byKey(const Key('cierre_entradas_total')), findsOneWidget);
      // Lo vendido: 20.000 + 5.000 + 30.000, sin las dos anuladas.
      expect(find.text(r'$ 55.000'), findsOneWidget);
      expect(find.text('6 entradas · 6 sueltas y 0 de lugares'), findsOneWidget);
      // La anulada después del cierre va aparte.
      expect(find.byKey(const Key('cierre_entradas_anulado_despues')), findsOneWidget);
      expect(find.text('1 abierta'), findsOneWidget);
      expect(find.text('1 cerrada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 22-nov-2026: el papel del cierre no sale solo y al cerrar se puede salir
    // sin sacarlo; acá se saca después, solo el de una caja cerrada, con lo
    // anotado al cerrar.
    testWidgets('PAPEL DEL CIERRE: solo en la caja cerrada, con lo que se anotó al cerrar',
        (tester) async {
      final e = EntradasEnMemoria();
      final (carla, maxi) = await dosCajas(e);
      e.escrituras = 0;
      final papeles = <DatosDelCierreDeEntradas>[];
      await abrirEntradas(tester, e, papeles: papeles);
      expect(find.byKey(Key('cierre_entradas_papel_${carla.id}')), findsNothing,
          reason: 'la caja abierta todavía no tiene cierre');
      expect(find.byKey(Key('cierre_entradas_papel_${maxi.id}')), findsOneWidget);
      await tester.tap(find.byKey(Key('cierre_entradas_papel_${maxi.id}')));
      await tester.pumpAndSettle();
      final papel = papeles.single;
      expect(papel.caja.id, maxi.id);
      expect(papel.caja.efectivoContado, 41500);
      expect(papel.caja.diferencia, -500);
      expect(papel.cuentas.entradas, 3, reason: 'solo lo de su caja, sin las anuladas');
      expect(papel.fiesta, 'TÉCNICA PINAROLI');
      expect(e.escrituras, 0, reason: 'el papel no escribe nada');
    });

    testWidgets('en la web no puede abrir la base del equipo: lo dice', (tester) async {
      final e = EntradasEnMemoria();
      await dosCajas(e);
      await abrirEntradas(tester, e, enLaWeb: true);
      expect(texto(tester, 'cierre_entradas_web'), kEntradasDesdeLaPc);
      expect(find.byKey(const Key('cierre_entradas_total')), findsNothing);
    });

    testWidgets('en un celular no se desborda: la tabla se desliza de costado', (tester) async {
      final e = EntradasEnMemoria();
      await dosCajas(e);
      await abrirEntradas(tester, e, tamano: const Size(360, 740));
      expect(tester.takeException(), isNull);
    });
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
        'RETIRO, ENTRADAS con su fiesta, y vuelve a COBROS', (tester) async {
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
      expect(find.byKey(const Key('cierre_entradas_fiesta')), findsOneWidget);
      expect(find.byKey(const Key('cierre_entradas_sin_precio')), findsOneWidget);
      expect(find.text('REGISTRAR RETIRO'), findsNothing);

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
