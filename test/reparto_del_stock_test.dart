// STOCK POR BARRA, el reparto del jefe (28-nov-2026): con cuánto arranca cada barra y
// desde cuánto se avisa. Montada de verdad, con la barra en memoria. Lo que se puede lo
// dice la cuenta (`StockPorBarra.errorDelReparto`), y guardar pide el modo jefe.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/reparto_del_stock.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// El modo jefe de la prueba, que se puede cerrar con la pantalla abierta.
class _ModoJefe extends Notifier<bool> {
  @override
  bool build() => true;

  void poner(bool v) => state = v;
}

final _modoJefe = NotifierProvider<_ModoJefe, bool>(_ModoJefe.new);

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late ProductoBarra speed, cerveza, agua;
  final ahora = DateTime.utc(2026, 12, 5, 2, 30);

  BarraEnMemoria b() => prueba.barra;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    prueba.eventos.add(fiesta);
    speed = b().producto('Speed');
    cerveza = b().producto('Cerveza lata');
    agua = b().producto('Agua');
    b().precio(fiesta.id, speed, 5000, stock: 96);
    b().precio(fiesta.id, cerveza, 4000, stock: 240);
    // El agua no tiene el stock cargado: no se reparte.
    b().precio(fiesta.id, agua, 2500);
  });

  Future<ProviderContainer> abrir(WidgetTester tester, {bool esJefe = true}) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Con otra clave cada vez: volver a abrir es entrar de nuevo, con todo leído otra vez.
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        esRolJefeProvider.overrideWith((ref) => ref.watch(_modoJefe)),
        relojDelJefeProvider.overrideWithValue(() => ahora),
        relojDeLaBarraProvider.overrideWithValue(() => ahora),
        enLaWebProvider.overrideWithValue(false),
      ],
      child: MaterialApp(home: RepartoDelStockScreen(fiesta: fiesta)),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(RepartoDelStockScreen)));
    c.read(_modoJefe.notifier).poner(esJefe);
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> escribir(WidgetTester tester, String clave, String texto) async {
    await tester.ensureVisible(find.byKey(Key(clave)));
    await tester.enterText(find.byKey(Key(clave)), texto);
    await tester.pumpAndSettle();
  }

  Future<void> guardar(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('reparto_guardar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reparto_guardar')));
    await tester.pumpAndSettle();
  }

  String texto(WidgetTester tester, String clave) => tester.widget<Text>(find.byKey(Key(clave))).data!;

  bool guardarApagado(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('reparto_guardar'))).onPressed == null;

  List<StockEnLaBarra> activos() => [for (final r in b().repartosGuardados) if (r.activo) r];

  testWidgets('salen los productos con el stock general cargado; el que no lo tiene, no', (tester) async {
    await abrir(tester);
    expect(texto(tester, 'reparto_general_${speed.id}'), 'Stock general: 96');
    expect(texto(tester, 'reparto_deposito_${speed.id}'), 'Queda en el depósito: 96');
    expect(find.byKey(Key('reparto_producto_${cerveza.id}')), findsOneWidget);
    expect(find.byKey(Key('reparto_producto_${agua.id}')), findsNothing);
    expect(guardarApagado(tester), isTrue, reason: 'sin cambios no hay nada que guardar');
  });

  testWidgets('se reparte: lo que no se reparte queda en el depósito, y se guarda a nombre del '
      'jefe', (tester) async {
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '24');
    await escribir(tester, 'reparto_arranque_${speed.id}_2', '24');
    await escribir(tester, 'reparto_aviso_${speed.id}_1', '6');
    expect(texto(tester, 'reparto_deposito_${speed.id}'), 'Queda en el depósito: 48');
    await guardar(tester);
    expect(texto(tester, 'reparto_dicho'), 'Guardado: el reparto ya está en las barras.');
    final filas = activos()..sort((x, y) => x.barra.compareTo(y.barra));
    expect([for (final r in filas) (r.barra, r.arranque, r.aviso, r.hechoPor)],
        [('Barra 1', 24, 6, 'Jefe'), ('Barra 2', 24, null, 'Jefe')]);
    expect(prueba.subidasDeLaBarra.where((x) => x.startsWith('barra_stock_barras ')), hasLength(2));
    expect(guardarApagado(tester), isTrue, reason: 'ya no hay cambios');
  });

  testWidgets('no se reparte más de lo que hay', (tester) async {
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '60');
    await escribir(tester, 'reparto_arranque_${speed.id}_2', '60');
    expect(texto(tester, 'reparto_deposito_${speed.id}'), 'Queda en el depósito: -24');
    expect(texto(tester, 'reparto_error_${speed.id}'), 'Hay 96: no se puede repartir 120.');
    expect(guardarApagado(tester), isTrue);
    expect(b().repartosGuardados, isEmpty);
  });

  testWidgets('cambiar solo el aviso reescribe la misma fila', (tester) async {
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '24');
    await guardar(tester);
    final id = activos().single.id;
    await escribir(tester, 'reparto_aviso_${speed.id}_1', '8');
    await guardar(tester);
    expect(b().repartosGuardados, hasLength(1));
    expect((activos().single.id, activos().single.arranque, activos().single.aviso), (id, 24, 8));
    // Y sacarle el aviso.
    await escribir(tester, 'reparto_aviso_${speed.id}_1', '');
    await guardar(tester);
    expect(activos().single.aviso, isNull);
  });

  testWidgets('borrar el arranque saca esa barra del reparto, sin borrar la fila; si ya vendió, '
      'no se puede', (tester) async {
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '24');
    await escribir(tester, 'reparto_arranque_${speed.id}_2', '24');
    await guardar(tester);
    // La Barra 1 vende: ya no sale del reparto.
    final caja = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'm',
      operadorNombre: 'Marta',
      numeroCaja: 1,
      sede: 'Barra 1',
    );
    await b().vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: speed.id, nombre: 'Speed', precio: 5000, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 10000,
      quien: 'Marta',
    );
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '');
    expect(texto(tester, 'reparto_error_${speed.id}'),
        'La Barra 1 ya vendió o movió este producto: no se puede sacar del reparto.');
    expect(guardarApagado(tester), isTrue);
    // La Barra 2 no vendió nada: sí.
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '24');
    await escribir(tester, 'reparto_arranque_${speed.id}_2', '');
    await guardar(tester);
    expect(b().repartosGuardados, hasLength(2), reason: 'no se borra');
    expect([for (final r in activos()) r.barra], ['Barra 1']);
  });

  testWidgets('una barra que ya usó parte de su arranque no puede arrancar con menos de lo usado',
      (tester) async {
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '24');
    await guardar(tester);
    final caja = await b().abrirCaja(
      eventoId: fiesta.id,
      operadorId: 'm',
      operadorNombre: 'Marta',
      numeroCaja: 1,
      sede: 'Barra 1',
    );
    await b().vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: speed.id, nombre: 'Speed', precio: 5000, cantidad: 10)],
      medio: MedioBarra.efectivo,
      efectivo: 50000,
      quien: 'Marta',
    );
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '5');
    expect(texto(tester, 'reparto_error_${speed.id}'),
        'La Barra 1 ya usó 10 de su arranque: no puede arrancar con menos de 10.');
    expect(guardarApagado(tester), isTrue);
  });

  testWidgets('un producto que el repositor ya contó no cambia de reparto', (tester) async {
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '24');
    await guardar(tester);
    await b().anotarMovimientoDeStock(
      MovimientoDeStock.conteo(
        eventoId: fiesta.id,
        productoId: speed.id,
        lugar: 'Barra 1',
        contadas: 22,
        foto: const FotoDeStock(),
        ajuste: -2,
        motivo: 'Rota',
        ahora: ahora,
      ),
      quien: 'Nico',
    );
    await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '30');
    expect(texto(tester, 'reparto_error_${speed.id}'), startsWith('Este producto ya se contó'));
    expect(guardarApagado(tester), isTrue);
  });

  testWidgets('sin modo jefe se ve, pero no se cambia nada', (tester) async {
    await abrir(tester, esJefe: false);
    expect(find.byKey(const Key('reparto_sin_modo_jefe')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(Key('reparto_arranque_${speed.id}_1'))).enabled, isFalse);
    expect(guardarApagado(tester), isTrue);
  });

  testWidgets('la segunda llave: si el modo jefe se cierra con lo escrito, no se guarda', (tester) async {
    final c = await abrir(tester);
    await escribir(tester, 'reparto_arranque_${speed.id}_1', '24');
    // El botón sigue en pantalla un cuadro; la llave de adentro es la que frena.
    final boton = tester.widget<FilledButton>(find.byKey(const Key('reparto_guardar')));
    c.read(_modoJefe.notifier).poner(false);
    boton.onPressed!();
    await tester.pumpAndSettle();
    expect(b().repartosGuardados, isEmpty);
    expect(guardarApagado(tester), isTrue);
  });

  testWidgets('sin ningún producto con el stock cargado, dice dónde se carga', (tester) async {
    b().preciosGuardados.clear();
    b().precio(fiesta.id, agua, 2500);
    await abrir(tester);
    expect(find.byKey(const Key('reparto_sin_stock')), findsOneWidget);
    expect(find.byKey(const Key('reparto_guardar')), findsNothing);
  });

  testWidgets('no muestra plata', (tester) async {
    await abrir(tester);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.data ?? '', isNot(contains(r'$')));
    }
  });
}
