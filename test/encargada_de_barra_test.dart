import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/barra/widgets/las_cajas_screen.dart';
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

void main() {
  final hoy = DateTime.now();
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late CajaBarra marta;
  late VentaBarra fernetDeMarta, sillaDeMarta;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_romi, 'Romi', '7777'));
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', hoy.add(const Duration(days: 2)));
    prueba.eventos.add(fiesta);
    final b = prueba.barra;
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
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        // En la tablet: la barra del equipo, sin modo jefe y sin la central.
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        centralSePrendeAcaProvider.overrideWithValue(false),
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
}
