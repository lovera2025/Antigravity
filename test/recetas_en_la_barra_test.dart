import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// Los tragos con receta en la barra de verdad (WhatsApp del jefe, 26-nov-2026): el vodka
/// lleva un Speed, y cada vodka vendido baja un Speed del stock. El fernet y la coca van
/// en cc: no se cuentan en la barra. Nadie ve la receta ni ningún costo.
const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late CajaBarra caja;
  late ProductoBarra speed, vodka, fernetConCoca, vodkaEnBotella;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA', DateTime.now().add(const Duration(days: 5)));
    prueba.eventos.add(fiesta);
    final b = prueba.barra;
    speed = b.producto('Speed 250', categoria: 'Sin alcohol');
    vodka = b.producto('Vodka con Speed', categoria: 'Tragos');
    fernetConCoca = b.producto('Fernet con coca', categoria: 'Tragos');
    vodkaEnBotella = b.producto('Vodka 1 L', categoria: 'Para los tragos');
    b.precio(fiesta.id, speed, 3500, orden: 0, stock: 3);
    b.precio(fiesta.id, vodka, 10000, orden: 1);
    b.precio(fiesta.id, fernetConCoca, 10000, orden: 2);
    final ahora = DateTime.now();
    b.recetasGuardadas.addAll([
      RecetaBarra.para(
        eventoId: fiesta.id,
        productoId: vodka.id,
        ingredienteId: speed.id,
        cantidad: 1,
        unidad: UnidadDeReceta.unidad,
        ahora: ahora,
      ),
      RecetaBarra.para(
        eventoId: fiesta.id,
        productoId: vodka.id,
        ingredienteId: vodkaEnBotella.id,
        cantidad: 500,
        unidad: UnidadDeReceta.cc,
        ahora: ahora,
      ),
    ]);
    caja = await b.abrirCaja(eventoId: fiesta.id, operadorId: _marta, operadorNombre: 'Marta', numeroCaja: 2);
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
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

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  String? quedan(WidgetTester tester, ProductoBarra p) {
    final f = find.byKey(Key('stock_${p.id}'));
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  testWidgets('el vodka dice cuántos quedan según el Speed, y los dos bajan juntos con la cuenta', (tester) async {
    await abrir(tester);
    expect(quedan(tester, speed), 'Quedan 3');
    expect(quedan(tester, vodka), 'Quedan 3', reason: 'alcanza para tantos vodkas como Speed haya');
    expect(quedan(tester, fernetConCoca), isNull, reason: 'el fernet y la coca van en cc: no se cuentan');

    await tocar(tester, find.byKey(Key('producto_${vodka.id}')));
    expect(quedan(tester, speed), 'Quedan 2', reason: 'el vodka de la cuenta se lleva un Speed');
    expect(quedan(tester, vodka), 'Quedan 2');

    await tocar(tester, find.byKey(Key('producto_${speed.id}')));
    expect(quedan(tester, speed), 'Quedan 1');
    expect(quedan(tester, vodka), 'Quedan 1', reason: 'el Speed suelto también se lleva uno');
  });

  testWidgets('un vodka ya vendido bajó un Speed; anulado, lo devuelve', (tester) async {
    final b = prueba.barra;
    final venta = await b.vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: vodka.id, nombre: vodka.nombre, precio: 10000, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 20000,
      quien: 'Marta',
    );
    await abrir(tester);
    expect(quedan(tester, speed), 'Quedan 1');
    expect(quedan(tester, vodka), 'Quedan 1');

    await b.anular(venta, motivo: 'se equivocó', quien: 'Romi');
    await tester.pumpWidget(const SizedBox());
    await abrir(tester);
    expect(quedan(tester, speed), 'Quedan 3');
  });

  // 28-nov-2026, el recorrido con el mouse: con receta, el stock que el jefe le cargó al
  // trago mismo se ignoraba (VENDER no decía "Quedan" y LAS CAJAS sí lo contaba).
  void stockDelVodka(int? stock, {int? speeds = 3}) {
    final b = prueba.barra;
    b.preciosGuardados.removeWhere((p) => p.productoId == vodka.id || p.productoId == speed.id);
    b.precio(fiesta.id, speed, 3500, orden: 0, stock: speeds);
    b.precio(fiesta.id, vodka, 10000, orden: 1, stock: stock);
  }

  testWidgets('el stock propio del vodka también cuenta: queda lo menor', (tester) async {
    stockDelVodka(2);
    await abrir(tester);
    expect(quedan(tester, vodka), 'Quedan 2', reason: 'hay 3 Speed, pero el jefe cargó 2 vodkas');
    await tocar(tester, find.byKey(Key('producto_${vodka.id}')));
    expect(quedan(tester, vodka), 'Quedan 1');
    expect(quedan(tester, speed), 'Quedan 2', reason: 'el vodka de la cuenta se lleva un Speed');
  });

  testWidgets('con el Speed sin stock, el vodka dice lo que le cargó el jefe', (tester) async {
    stockDelVodka(4, speeds: null);
    await abrir(tester);
    expect(quedan(tester, speed), isNull);
    expect(quedan(tester, vodka), 'Quedan 4');
  });

  testWidgets('sin Speed, el vodka dice que no queda y pregunta antes, como cualquier producto', (tester) async {
    await abrir(tester);
    for (var i = 0; i < 3; i++) {
      await tocar(tester, find.byKey(Key('producto_${speed.id}')));
    }
    expect(quedan(tester, vodka), 'Agotado', reason: 'sin vodkas en la cuenta: agotado');
    await tocar(tester, find.byKey(Key('producto_${vodka.id}')));
    expect(find.byKey(const Key('sin_stock')), findsOneWidget);
  });

  test('toda cuenta del stock de la barra recibe las ventas con lo que va adentro de los tragos', () {
    // Las cuentas de la plata (el cierre, VENTAS) no: lo de adentro de un trago no se cobra.
    final llamadas = RegExp(r'(StockDeLaBarra|StockPorBarra)\.(deLaNoche|de)\(');
    var vistas = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final ruta = f.path.replaceAll('\\', '/');
      if (ruta.endsWith('cuentas/stock_de_la_barra.dart') || ruta.endsWith('cuentas/stock_por_barra.dart')) {
        continue;
      }
      final fuente = f.readAsStringSync().replaceAll('\r\n', '\n');
      for (final m in llamadas.allMatches(fuente)) {
        final cuerpo = fuente.substring(m.end, (m.end + 600).clamp(0, fuente.length));
        final ventas = RegExp(r'\bventas: ([^\n]*)').firstMatch(cuerpo);
        expect(ventas, isNotNull, reason: '$ruta: no encontré las ventas');
        expect(ventas!.group(1), contains('paraElStock('), reason: '$ruta: ${ventas.group(0)}');
        vistas++;
      }
    }
    expect(vistas, greaterThanOrEqualTo(3), reason: 'CAJAS, VENDER y GANANCIA');
  });

  test('ninguna pantalla de la cajera, la encargada o el repositor nombra el costo', () {
    for (final ruta in [
      'lib/features/barra/widgets/vender_screen.dart',
      'lib/features/barra/widgets/cobrar_hoja.dart',
      'lib/features/barra/widgets/ventas_de_la_caja_screen.dart',
      'lib/features/barra/widgets/cerrar_caja_barra_screen.dart',
      'lib/features/barra/widgets/las_cajas_screen.dart',
      'lib/features/barra/widgets/catalogo_y_precios_screen.dart',
      'lib/features/barra/jefe/cajas_de_la_fiesta.dart',
    ]) {
      final codigo = File(ruta)
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final prohibido in ['CostoBarra', 'precioLista', 'barra_costos', 'CuentaDelProveedor', 'contenidoCc']) {
        expect(codigo.contains(prohibido), isFalse, reason: '$ruta nombra $prohibido');
      }
    }
  });
}
