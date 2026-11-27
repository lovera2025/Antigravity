import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/cuentas/cuenta_del_proveedor.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/jefe/ganancia_del_jefe.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/leer_pdf.dart';
import 'helpers/operadores_en_memoria.dart';

/// **GANANCIA** del jefe (maqueta aprobada el 27-nov-2026, forma A): arriba LE DEBO AL
/// PROVEEDOR, la cuenta una sola vez, la tabla de lo que se le paga cosa por cosa, la
/// ganancia de cada producto plegada, VER POR FIESTA e IMPRIMIR (A4, con botón). Solo el
/// jefe.
void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento viernes, sabado, otra;
  late ProductoBarra lata, fernetConCoca, botellaFernet, coca;
  final impresos = <({String periodo, bool conProductos, int leDebo})>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    impresos.clear();
    operadores = OperadoresEnPrueba();
    prueba = BarraEnPrueba();
    viernes = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    sabado = fiestaDePrueba(BarraEnPrueba.id(2), 'GUEMEZ', DateTime(2026, 12, 5, 22));
    otra = fiestaDePrueba(BarraEnPrueba.id(3), 'ROTONDA', DateTime(2026, 12, 12, 22));
    prueba.eventos.addAll([viernes, sabado, otra]);
    final b = prueba.barra;
    lata = b.producto('Cerveza lata', categoria: 'Cervezas');
    fernetConCoca = b.producto('Fernet con coca', categoria: 'Tragos');
    botellaFernet = b.producto('Fernet 750', categoria: 'Botellas');
    coca = b.producto('Coca-Cola 2,25', categoria: 'Botellas');
    final antes = DateTime(2026, 11, 20);
    for (final f in [viernes, sabado]) {
      b.precio(f.id, lata, 5000);
      b.precio(f.id, fernetConCoca, 10000);
      for (final (id, lista, cc) in [(lata.id, 1500.0, null), (botellaFernet.id, 11740.0, 750), (coca.id, 3000.0, 2250)]) {
        await b.guardarCosto(
          CostoBarra.para(eventoId: f.id, productoId: id, precioLista: lista, contenidoCc: cc, ahora: antes),
          quien: 'Jefe',
        );
      }
      for (final (id, cc) in [(botellaFernet.id, 200), (coca.id, 500)]) {
        await b.guardarReceta(
          RecetaBarra.para(
            eventoId: f.id,
            productoId: fernetConCoca.id,
            ingredienteId: id,
            cantidad: cc,
            unidad: UnidadDeReceta.cc,
            ahora: antes,
          ),
          quien: 'Jefe',
        );
      }
    }
    RenglonVenta r(ProductoBarra p, double precio, int n) =>
        RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: n);
    // El viernes: 2 latas y un Fernet con coca. El sábado: 1 lata.
    b.reloj = () => DateTime.utc(2026, 12, 5, 2);
    final c1 = await b.abrirCaja(eventoId: viernes.id, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
    await b.vender(caja: c1, renglones: [r(lata, 5000, 2)], medio: MedioBarra.efectivo, efectivo: 10000, quien: 'Marta');
    await b.vender(caja: c1, renglones: [r(fernetConCoca, 10000, 1)], medio: MedioBarra.efectivo, efectivo: 10000, quien: 'Marta');
    b.reloj = () => DateTime.utc(2026, 12, 6, 2);
    final c2 = await b.abrirCaja(eventoId: sabado.id, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
    await b.vender(caja: c2, renglones: [r(lata, 5000, 1)], medio: MedioBarra.efectivo, efectivo: 5000, quien: 'Marta');
  });

  Future<void> abrir(WidgetTester tester, {bool esJefe = true, Size tamano = const Size(1280, 1400)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        esRolJefeProvider.overrideWithValue(esJefe),
        enLaWebProvider.overrideWithValue(false),
        relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 11, 20, 15)),
        imprimirGananciaProvider.overrideWithValue(
          (c, {required periodo, required conProductos, context}) async =>
              impresos.add((periodo: periodo, conProductos: conProductos, leDebo: c.leDebo)),
        ),
      ],
      child: MaterialApp(
        home: BarraJefeScreen(pestanaInicial: esJefe ? PestanaBarraJefe.ganancia : PestanaBarraJefe.catalogo),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String texto(WidgetTester tester, String clave) => tester.widget<Text>(find.byKey(Key(clave))).data!;

  Future<void> tocar(WidgetTester tester, Finder f) async {
    // En el celular lo de abajo de la lista no está armado: se desliza hasta verlo.
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.descendant(of: find.byKey(const Key('jefe_ganancia')), matching: find.byType(Scrollable)).first,
      );
    }
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('arriba LE DEBO AL PROVEEDOR, y la cuenta una sola vez, de las fiestas que se rinden juntas',
      (tester) async {
    await abrir(tester);
    expect(texto(tester, 'jefe_ganancia_periodo'), 'Vie 4/12 al sáb 5/12 · 2 fiestas',
        reason: 'la elegida y las de los días que siguen; ROTONDA (el 12) no entra');
    // 3 latas a $1.500 + un Fernet con coca: 200 cc de 11.740/750 ($3.130,67) y 500 cc de 3.000/2.250
    // ($666,67). Cada botella se redondea a su centavo: así la tabla suma justo el total.
    expect(texto(tester, 'jefe_ganancia_le_debo'), r'$ 8.297,34');
    expect(texto(tester, 'jefe_ganancia_se_vendio'), r'$ 25.000');
    expect(texto(tester, 'jefe_ganancia_ganancia'), r'$ 16.702,66');
    expect(find.text('LE DEBO AL PROVEEDOR'), findsOneWidget);
  });

  testWidgets('una sola tabla, por lo que entrega el proveedor: latas y botellas, con de dónde sale', (tester) async {
    await abrir(tester);
    Finder en(ProductoBarra p, String t) => find.descendant(
          of: find.byKey(Key('jefe_ganancia_uso_${p.id}')),
          matching: find.text(t),
        );
    expect(en(lata, '3'), findsOneWidget);
    expect(en(lata, '3 vendidas'), findsOneWidget);
    expect(en(lata, r'$ 1.500'), findsOneWidget);
    expect(en(lata, r'$ 4.500'), findsOneWidget);
    expect(en(botellaFernet, '0,27 botellas'), findsOneWidget, reason: '200 cc de 750');
    expect(en(botellaFernet, '200 cc en los tragos'), findsOneWidget);
    expect(find.byKey(Key('jefe_ganancia_uso_${fernetConCoca.id}')), findsNothing,
        reason: 'el trago no se le compra al proveedor: van sus botellas');
    expect(find.byKey(Key('jefe_ganancia_producto_${lata.id}')), findsNothing, reason: 'la ganancia por producto viene plegada');
    await tocar(tester, find.byKey(const Key('jefe_ganancia_por_producto')));
    expect(
      find.descendant(of: find.byKey(Key('jefe_ganancia_producto_${fernetConCoca.id}')), matching: find.text(r'$ 6.202,66')),
      findsOneWidget,
    );
  });

  test('lo que no se le compra a nadie (precio de lista 0, la silla) no va en la tabla del proveedor', () {
    expect(deLoQueSePaga(const UsoDelProveedor(productoId: 's', nombre: 'Silla', sueltas: 3, lista: 0)), isFalse);
    expect(deLoQueSePaga(const UsoDelProveedor(productoId: 'l', nombre: 'Lata', sueltas: 3, lista: 150000)), isTrue);
    expect(deLoQueSePaga(const UsoDelProveedor(productoId: 'x', nombre: 'Sin lista', sueltas: 3, faltaLaLista: true)), isTrue,
        reason: 'lo que falta cargar sí aparece, con "falta"');
    expect(deLoQueSePaga(const UsoDelProveedor(productoId: 'n', nombre: 'Nada', lista: 100)), isFalse, reason: 'no se usó');
  });

  testWidgets('VER POR FIESTA y CAMBIAR las fiestas', (tester) async {
    await abrir(tester);
    await tocar(tester, find.byKey(const Key('jefe_ganancia_ver_por_fiesta')));
    expect(find.byKey(Key('jefe_ganancia_fiesta_${viernes.id}')), findsOneWidget);
    expect(find.byKey(Key('jefe_ganancia_fiesta_${sabado.id}')), findsOneWidget);
    await tocar(tester, find.byKey(const Key('jefe_ganancia_cambiar')));
    await tocar(tester, find.byKey(Key('jefe_ganancia_elegir_${sabado.id}')));
    await tocar(tester, find.byKey(const Key('jefe_ganancia_elegir_listo')));
    expect(texto(tester, 'jefe_ganancia_periodo'), 'Vie 4/12 · 1 fiesta');
    expect(texto(tester, 'jefe_ganancia_le_debo'), r'$ 6.797,34');
  });

  testWidgets('IMPRIMIR: con botón, y con la ganancia por producto si está abierta', (tester) async {
    await abrir(tester);
    expect(impresos, isEmpty, reason: 'nada sale solo');
    await tocar(tester, find.byKey(const Key('jefe_ganancia_imprimir')));
    expect(impresos.single, (periodo: 'Vie 4/12 al sáb 5/12 · 2 fiestas', conProductos: false, leDebo: 829734));
    await tocar(tester, find.byKey(const Key('jefe_ganancia_por_producto')));
    await tocar(tester, find.byKey(const Key('jefe_ganancia_imprimir')));
    expect(impresos.last.conProductos, isTrue);
  });

  testWidgets('si a algo le falta el precio de lista lo dice, y IR A PRECIOS lleva ahí', (tester) async {
    prueba.barra.costosGuardados.removeWhere((c) => c.productoId == lata.id);
    await abrir(tester);
    expect(texto(tester, 'jefe_ganancia_falta_lista'), contains('Cerveza lata le falta el precio de lista'));
    await tocar(tester, find.byKey(const Key('jefe_ganancia_ir_a_precios')));
    expect(find.byKey(Key('jefe_lista_${lata.id}')), findsOneWidget, reason: 'está en PRECIOS, con la casilla');
  });

  testWidgets('sin modo jefe, GANANCIA ni aparece', (tester) async {
    await abrir(tester, esJefe: false);
    expect(find.byKey(const Key('jefe_pestana_ganancia')), findsNothing);
    expect(find.byKey(const Key('jefe_pestana_cajas')), findsOneWidget);
  });

  testWidgets('la encargada de barra no ve GANANCIA: solo el jefe', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        esRolJefeProvider.overrideWithValue(false),
        enLaWebProvider.overrideWithValue(false),
        relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 11, 20, 15)),
        rolEnLaBarraProvider.overrideWithValue(RolEnLaBarra.encargada),
      ],
      child: const MaterialApp(home: BarraJefeScreen(pestanaInicial: PestanaBarraJefe.ganancia)),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jefe_pestana_ganancia')), findsNothing);
    expect(find.byKey(const Key('jefe_ganancia')), findsNothing, reason: 'ni pidiéndola de entrada');
    expect(find.byKey(const Key('jefe_ganancia_le_debo')), findsNothing);
  });

  test('solo el jefe ve el costo y la ganancia', () {
    for (final rol in RolEnLaBarra.values) {
      expect(ReglasDeLaBarra.veElCostoYLaGanancia(rol), rol == RolEnLaBarra.jefe, reason: rol.name);
    }
    expect(ReglasDeLaBarra.veElCostoYLaGanancia(null), isFalse);
  });

  testWidgets('en un celular no se desborda', (tester) async {
    await abrir(tester, tamano: const Size(390, 844));
    expect(tester.takeException(), isNull);
    await tocar(tester, find.byKey(const Key('jefe_ganancia_por_producto')));
    expect(tester.takeException(), isNull);
  });

  test('el papel A4 dice lo mismo que la pantalla', () async {
    final cuenta = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: viernes.id,
        nombre: 'TÉCNICA PINAROLI',
        fecha: viernes.fechaEvento,
        cajas: await prueba.barra.cajas(viernes.id),
        ventas: await prueba.barra.ventas(viernes.id),
        precios: await prueba.barra.precios(viernes.id),
        listas: {for (final c in await prueba.barra.costos(viernes.id)) c.productoId: c.precioLista},
        contenidos: {for (final c in await prueba.barra.costos(viernes.id)) c.productoId: c.contenidoCc},
        recetas: await prueba.barra.recetas(viernes.id),
      ),
    ], nombres: {for (final p in await prueba.barra.productos()) p.id: p.nombre});
    final bytes = await GananciaPdf.armar(cuenta, periodo: 'Vie 4/12 · 1 fiesta', conProductos: true);
    final palabras = [for (final p in palabrasDelPdf(bytes)) p.texto];
    for (final w in ['GANANCIA', 'DEBO', 'PROVEEDOR', r'6.797,34', 'Cerveza', 'lata', 'GANÉ']) {
      expect(palabras, contains(w), reason: 'el papel dice "$w"');
    }
  });
}
