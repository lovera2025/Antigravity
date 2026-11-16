// Quien vende en la barra o en Entradas sale del programa (lo cierra, se apaga
// la tablet) y vuelve a entrar con su PIN: sigue con la misma caja, con sus
// ventas, sin abrir otra. La caja vive en la tablet donde se abrió: desde otra
// no se la lleva (pregunta del usuario, 15-nov).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/operador_caja.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/widgets/vender_entradas_screen.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Cierra el programa: se va todo lo que estaba en memoria y queda solo lo
  /// guardado en la tablet.
  Future<void> cerrarElPrograma(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  group('la barra', () {
    late OperadoresEnPrueba operadores;
    late BarraEnPrueba prueba;
    late Evento fiesta;
    late ProductoBarra cerveza;

    setUp(() {
      operadores = OperadoresEnPrueba();
      operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
      prueba = BarraEnPrueba();
      fiesta = fiestaDePrueba(
        BarraEnPrueba.id(1),
        'PUERTO VIEJO',
        DateTime.now().add(const Duration(days: 2)),
      );
      prueba.eventos.add(fiesta);
      cerveza = prueba.barra.producto('Cerveza lata');
      prueba.barra.precio(fiesta.id, cerveza, 3500);
    });

    /// Abre el programa, entra Marta y toca la fiesta. Devuelve las cajas con
    /// las que se abrió VENDER.
    Future<List<CajaBarra>> entrarYTocarLaFiesta(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final abiertas = <CajaBarra>[];
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [...operadores.reemplazos, ...prueba.reemplazos],
        child: MaterialApp(
          home: BarraHomeScreen(onCajaLista: (_, _, caja) => abiertas.add(caja)),
        ),
      ));
      final c = ProviderScope.containerOf(tester.element(find.byType(BarraHomeScreen)));
      await c.read(appRoleProvider.notifier).entrarComoBarra(
            operadores.operadores.lista.single,
            const PermisosEfectivos(barra: true),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('barra_fiesta_${fiesta.id}')));
      await tester.pumpAndSettle();
      return abiertas;
    }

    testWidgets('cierra el programa, vuelve a entrar con su PIN y sigue con la misma caja',
        (tester) async {
      var abiertas = await entrarYTocarLaFiesta(tester);
      expect(find.text('Abrir tu caja'), findsOneWidget, reason: 'la primera vez la abre');
      await tester.tap(find.byKey(const Key('caja_numero_2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('caja_abrir')));
      await tester.pumpAndSettle();
      final caja = abiertas.single;
      final venta = await prueba.barra.vender(
        caja: caja,
        renglones: [
          RenglonVenta(productoId: cerveza.id, nombre: cerveza.nombre, precio: 3500, cantidad: 1),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 3500,
        quien: 'Marta',
      );

      await cerrarElPrograma(tester);

      abiertas = await entrarYTocarLaFiesta(tester);
      expect(find.text('Abrir tu caja'), findsNothing, reason: 'no pide abrir otra');
      expect(abiertas.single.id, caja.id, reason: 'es la misma caja');
      expect(abiertas.single.numeroCaja, 2);
      expect(prueba.barra.cajasGuardadas, hasLength(1));
      expect([for (final v in await prueba.barra.ventasDeLaCaja(caja.id)) v.id], [venta.id],
          reason: 'con sus ventas');
    });

    testWidgets('desde otra tablet no se la lleva: ahí abre otra, y la primera sigue abierta',
        (tester) async {
      await prueba.barra.abrirCaja(
        eventoId: fiesta.id,
        operadorId: _marta,
        operadorNombre: 'Marta',
        numeroCaja: 2,
      );
      prueba.barra.equipo = 'tablet-2';
      final abiertas = await entrarYTocarLaFiesta(tester);
      expect(find.text('Abrir tu caja'), findsOneWidget);
      expect(abiertas, isEmpty);
      prueba.barra.equipo = 'tablet-1';
      expect(await prueba.barra.cajaAbierta(eventoId: fiesta.id, operadorId: _marta), isNotNull,
          reason: 'la primera sigue abierta en su tablet');
    });
  });

  group('Entradas', () {
    /// Abre el programa sobre [entradas] (lo guardado en esa tablet), entra
    /// [carla] con "Vende entradas" y abre VENDER.
    Future<void> entrarYVender(
      WidgetTester tester,
      EntregaEnMemoria e,
      EntradasEnMemoria entradas,
      OperadorCaja carla,
    ) async {
      tester.view.physicalSize = const Size(1100, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        ...e.reemplazos(),
        ...entradas.reemplazos,
        hoyEnArgentinaProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 12)),
        abrirComprobanteDeEntradasProvider.overrideWithValue((datos, {context}) async {}),
      ]);
      addTearDown(c.dispose);
      await c.read(appRoleProvider.notifier).entrarComoEntradas(
            carla,
            const PermisosEfectivos(entradas: true, vendeEntradas: true),
          );
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: VenderEntradasScreen(evento: fiestaDeLaEntrega)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('cierra el programa, vuelve a entrar con su PIN y sigue con la misma caja',
        (tester) async {
      final e = EntregaEnMemoria();
      final entradas = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      final carla = e.operador();
      // Lo que quedó guardado en la tablet antes de cerrar el programa.
      final caja = await entradas.abrirCaja(
        eventoId: idFiestaEntrega,
        operadorId: carla.id,
        operadorNombre: 'Carla',
        cambioInicial: 5000,
      );
      final venta = await entradas.vender(
        caja: caja,
        compradorNombre: 'GOMEZ, ANA',
        renglones: [RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 2)],
        medio: MedioBarra.efectivo,
        efectivo: 20000,
        quien: 'Carla',
      );
      await cerrarElPrograma(tester);

      await entrarYVender(tester, e, entradas, carla);
      expect(find.text('Abrir la caja de entradas'), findsNothing, reason: 'no pide abrir otra');
      expect(entradas.listaCajas, hasLength(1));
      await tester.tap(find.byKey(const Key('vender_ventas')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('venta_${venta.id}')), findsOneWidget, reason: 'con sus ventas');
    });

    testWidgets('desde otra tablet no se la lleva: ahí pide abrir otra', (tester) async {
      final e = EntregaEnMemoria();
      final enLaPrimera = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      final carla = e.operador();
      await enLaPrimera.abrirCaja(
        eventoId: idFiestaEntrega,
        operadorId: carla.id,
        operadorNombre: 'Carla',
      );
      // La otra tablet ya bajó todo: tiene la caja de la primera, abierta.
      final otra = EntradasEnMemoria(equipo: 'tablet-2')..conPrecio(idFiestaEntrega);
      otra.listaCajas.addAll(enLaPrimera.listaCajas);

      await entrarYVender(tester, e, otra, carla);
      expect(find.text('Abrir la caja de entradas'), findsOneWidget);
      expect(otra.listaCajas.single.abierta, isTrue, reason: 'la primera sigue abierta');
    });
  });
}
