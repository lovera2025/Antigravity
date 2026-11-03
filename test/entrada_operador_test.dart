import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/services/entrada_de_operador.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/features/common/utils/quien_opera.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/features/entradas/services/fiestas_que_vienen.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/operadores_en_memoria.dart';

const _maxi = 'a0000000-0000-4000-8000-000000000001';
const _ana = 'a0000000-0000-4000-8000-000000000002';
const _todo = PermisosEfectivos(cobros: true, entradas: true);

void main() {
  late OperadoresEnPrueba prueba;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prueba = OperadoresEnPrueba();
    prueba.operadores.lista.addAll([
      operadorDePrueba(_maxi, 'Maxi', '1234'),
      operadorDePrueba(_ana, 'Ana', '5555'),
    ]);
  });

  group('qué se despliega con el PIN', () {
    test('ninguno: te faltan permisos', () {
      final o = OpcionesDeEntrada.de(const PermisosEfectivos());
      expect(o.aviso, kTeFaltanPermisos);
      expect(o.directo, isNull);
      expect(o.paraElegir, isEmpty);
    });

    test('uno solo: entra derecho', () {
      expect(OpcionesDeEntrada.de(PermisosEfectivos.soloCobros).directo,
          PermisoOperador.cobros);
      expect(OpcionesDeEntrada.de(const PermisosEfectivos(entradas: true)).directo,
          PermisoOperador.entradas);
    });

    test('solo Barra: entra derecho a la barra', () {
      final o = OpcionesDeEntrada.de(const PermisosEfectivos(barra: true));
      expect(o.aviso, isNull);
      expect(o.directo, PermisoOperador.barra);
    });

    test('varios: elige, siempre en el mismo orden', () {
      final o = OpcionesDeEntrada.de(
        const PermisosEfectivos(cobros: true, entradas: true, barra: true),
      );
      expect(o.paraElegir, [
        PermisoOperador.cobros,
        PermisoOperador.entradas,
        PermisoOperador.barra,
      ]);
    });
  });

  group('adónde va cada uno', () {
    test('Entradas nunca arma el panel, tenga o no una caja abierta', () {
      expect(
        destinoDeEntrada(const AppRoleState(kind: AppRoleKind.entradas)),
        DestinoDeEntrada.entradas,
      );
    });

    test('sin elegir, o en la caja sin abrirla, a la pantalla de entrada', () {
      expect(destinoDeEntrada(const AppRoleState()), DestinoDeEntrada.elegir);
      expect(
        destinoDeEntrada(const AppRoleState(kind: AppRoleKind.caja)),
        DestinoDeEntrada.elegir,
      );
    });

    test('Barra nunca arma el panel', () {
      expect(
        destinoDeEntrada(const AppRoleState(kind: AppRoleKind.barra)),
        DestinoDeEntrada.barra,
      );
    });

    test('el jefe, al panel', () {
      expect(
        destinoDeEntrada(const AppRoleState(kind: AppRoleKind.jefe)),
        DestinoDeEntrada.panel,
      );
    });

    test('el router de la app decide con esto, y Entradas va a su pantalla', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final i = main.indexOf('class _RoleRouter');
      final router = main.substring(i);
      expect(router, contains('switch (destinoDeEntrada(appRole))'));
      expect(
        router,
        contains('DestinoDeEntrada.entradas => const EntradasHomeScreen()'),
      );
      expect(router, contains('DestinoDeEntrada.barra => const BarraHomeScreen()'));
      expect(RegExp('DashboardScreen').allMatches(router), hasLength(1));
    });
  });

  group('el rol, sin pantalla', () {
    late ProviderContainer c;
    AppRoleNotifier rol() => c.read(appRoleProvider.notifier);

    setUp(() {
      c = ProviderContainer(overrides: prueba.reemplazos);
      addTearDown(c.dispose);
    });

    test('un PIN que no es de nadie da null', () async {
      expect(await rol().buscarOperador('9999'), isNull);
    });

    test('los de hoy, sin fila, entran de Cobros', () async {
      final r = await rol().buscarOperador('1234');
      expect(r!.operador.nombre, 'Maxi');
      expect(r.permisos, PermisosEfectivos.soloCobros);
    });

    test('con el PIN en esta PC no va a la nube', () async {
      await rol().buscarOperador('1234');
      expect(prueba.subida.bajadas, 0);
    });

    test('un PIN recién creado en otra PC: baja y entra, sin que entre el jefe', () async {
      prueba.subida.alBajar = () {
        prueba.operadores.lista.add(operadorDePrueba(
          'a0000000-0000-4000-8000-000000000003',
          'Nueva',
          '7777',
        ));
      };
      final r = await rol().buscarOperador('7777');
      expect(prueba.subida.bajadas, 1);
      expect(r!.operador.nombre, 'Nueva');
    });

    test('sin internet no espera a la nube', () async {
      prueba.conexion.estado = AppConnectivity.offline;
      expect(await rol().buscarOperador('7777'), isNull);
      expect(prueba.subida.bajadas, 0);
    });

    test('Entradas no abre caja, y queda anotado quién entregó', () async {
      final op = prueba.operadores.lista.first;
      await rol().entrarComoEntradas(op, const PermisosEfectivos(entradas: true));
      final app = c.read(appRoleProvider);
      expect(app.esEntradas, isTrue);
      expect(app.sesionActiva, isNull);
      expect(app.pideAbrirCaja, isFalse);
      expect(prueba.sesiones.abiertas, isEmpty);
      expect(quienOperaDe(app: app), 'Maxi');
    });

    test('en modo Entradas no se puede cobrar', () async {
      final op = prueba.operadores.lista.first;
      await rol().entrarComoEntradas(op, _todo);
      expect(() => rol().sesionCajaIdParaCobro(), throwsA(isA<SinCajaAbiertaException>()));
    });

    test('entrar a Cobros sin caja la pide; con caja abierta la retoma', () async {
      final op = prueba.operadores.lista.first;
      await rol().entrarComoCaja(op, PermisosEfectivos.soloCobros);
      expect(c.read(appRoleProvider).pideAbrirCaja, isTrue);
      expect(destinoDeEntrada(c.read(appRoleProvider)), DestinoDeEntrada.elegir);

      await rol().abrirSesionCaja(cambioInicial: 0, etiqueta: 'Tarde');
      expect(c.read(appRoleProvider).pideAbrirCaja, isFalse);
      expect(destinoDeEntrada(c.read(appRoleProvider)), DestinoDeEntrada.panel);

      await rol().logoutApp();
      await rol().entrarComoCaja(op, PermisosEfectivos.soloCobros);
      expect(c.read(appRoleProvider).tieneSesionCaja, isTrue);
      expect(c.read(appRoleProvider).pideAbrirCaja, isFalse);
      await rol().logoutApp();
    });

    test('ENTRADAS, PASAR A CAJA y ENTRADAS, sin PIN y sin cerrar la caja', () async {
      final op = prueba.operadores.lista.first;
      await rol().entrarComoEntradas(op, _todo);
      await rol().pasarACaja();
      await rol().abrirSesionCaja(cambioInicial: 0, etiqueta: 'Tarde');
      expect(destinoDeEntrada(c.read(appRoleProvider)), DestinoDeEntrada.panel);

      rol().pasarAEntradas();
      expect(destinoDeEntrada(c.read(appRoleProvider)), DestinoDeEntrada.entradas);
      expect(prueba.sesiones.abiertas, hasLength(1), reason: 'la caja sigue abierta');

      await rol().pasarACaja();
      expect(c.read(appRoleProvider).tieneSesionCaja, isTrue);
      expect(destinoDeEntrada(c.read(appRoleProvider)), DestinoDeEntrada.panel);
      await rol().logoutApp();
    });

    test('quien no tiene el otro permiso no pasa', () async {
      final op = prueba.operadores.lista.first;
      await rol().entrarComoEntradas(op, const PermisosEfectivos(entradas: true));
      await rol().pasarACaja();
      expect(c.read(appRoleProvider).esEntradas, isTrue);

      await rol().entrarComoCaja(op, PermisosEfectivos.soloCobros);
      rol().pasarAEntradas();
      expect(c.read(appRoleProvider).esCaja, isTrue);
    });

    test('no abrir la caja: con Entradas vuelve ahí; si no, a la entrada', () async {
      final op = prueba.operadores.lista.first;
      await rol().entrarComoCaja(op, _todo);
      await rol().noAbrioLaCaja();
      expect(c.read(appRoleProvider).esEntradas, isTrue);

      await rol().entrarComoCaja(op, PermisosEfectivos.soloCobros);
      await rol().noAbrioLaCaja();
      expect(c.read(appRoleProvider).kind, AppRoleKind.none);
    });
  });

  group('la pantalla de entrada', () {
    Future<void> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: prueba.reemplazos,
        child: const MaterialApp(home: RoleGateScreen()),
      ));
      await tester.pump();
    }

    /// Sin `pumpAndSettle`: acá no está el router de la app que reemplaza esta
    /// pantalla, y el círculo de espera sigue girando.
    Future<void> pasar(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> ponerPin(WidgetTester tester, String pin) async {
      await tester.tap(find.byKey(const Key('entrar_operador')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), pin);
      await tester.tap(find.text('Entrar'));
      await pasar(tester);
    }

    ProviderContainer contenedor(WidgetTester tester) => ProviderScope.containerOf(
          tester.element(find.byType(RoleGateScreen)),
        );

    testWidgets('dice OPERADOR y ya no MODO CAJA', (tester) async {
      await abrir(tester);
      expect(find.text('OPERADOR'), findsOneWidget);
      expect(find.text('MODO CAJA'), findsNothing);
      expect(find.text('MODO JEFE'), findsOneWidget);
    });

    testWidgets('un PIN equivocado lo dice', (tester) async {
      await abrir(tester);
      await ponerPin(tester, '9999');
      expect(find.text('PIN incorrecto o operador inactivo'), findsOneWidget);
    });

    testWidgets('cargado sin permisos no entra: lo dice y vuelve a la entrada', (tester) async {
      prueba.permisos.poner(_maxi, const PermisosEfectivos());
      await abrir(tester);
      await ponerPin(tester, '1234');
      expect(find.text(kTeFaltanPermisos), findsOneWidget);
      expect(find.text('OPERADOR'), findsOneWidget);
      expect(contenedor(tester).read(appRoleProvider).kind, AppRoleKind.none);
    });

    testWidgets('solo Cobros: pide abrir la caja, como hoy', (tester) async {
      await abrir(tester);
      await ponerPin(tester, '1234');
      expect(find.textContaining('Abrir caja'), findsWidgets);
      expect(contenedor(tester).read(appRoleProvider).esCaja, isTrue);
    });

    testWidgets('solo Entradas: entra derecho, sin caja', (tester) async {
      prueba.permisos.poner(_ana, const PermisosEfectivos(entradas: true));
      await abrir(tester);
      await ponerPin(tester, '5555');
      final app = contenedor(tester).read(appRoleProvider);
      expect(app.esEntradas, isTrue);
      expect(find.textContaining('Abrir caja'), findsNothing);
    });

    testWidgets('con varios se despliegan los tres, todos prendidos', (tester) async {
      prueba.permisos.poner(
        _ana,
        const PermisosEfectivos(cobros: true, entradas: true, barra: true),
      );
      await abrir(tester);
      await ponerPin(tester, '5555');
      expect(find.text('Hola, Ana. ¿Qué vas a hacer?'), findsOneWidget);
      expect(find.text('COBROS'), findsOneWidget);
      expect(find.text('ENTRADAS'), findsOneWidget);
      expect(find.text('BARRA'), findsOneWidget);
      for (final p in ['cobros', 'entradas', 'barra']) {
        expect(
          tester.widget<ButtonStyleButton>(find.byKey(Key('entrada_$p'))).onPressed,
          isNotNull,
          reason: p,
        );
      }
      expect(contenedor(tester).read(appRoleProvider).kind, AppRoleKind.none);

      await tester.tap(find.byKey(const Key('entrada_entradas')));
      await pasar(tester);
      expect(contenedor(tester).read(appRoleProvider).esEntradas, isTrue);
    });

    testWidgets('BARRA entra a la barra, sin abrir la caja de cuotas', (tester) async {
      prueba.permisos.poner(_ana, const PermisosEfectivos(entradas: true, barra: true));
      await abrir(tester);
      await ponerPin(tester, '5555');
      await tester.tap(find.byKey(const Key('entrada_barra')));
      await pasar(tester);
      final app = contenedor(tester).read(appRoleProvider);
      expect(app.esBarra, isTrue);
      expect(app.pideAbrirCaja, isFalse);
      expect(prueba.sesiones.abiertas, isEmpty);
      expect(destinoDeEntrada(app), DestinoDeEntrada.barra);
    });

    testWidgets('solo Barra: entra derecho', (tester) async {
      prueba.permisos.poner(_ana, const PermisosEfectivos(barra: true));
      await abrir(tester);
      await ponerPin(tester, '5555');
      expect(contenedor(tester).read(appRoleProvider).esBarra, isTrue);
    });

    testWidgets('VOLVER deja elegir otra vez cómo entrar', (tester) async {
      prueba.permisos.poner(_ana, _todo);
      await abrir(tester);
      await ponerPin(tester, '5555');
      await tester.tap(find.byKey(const Key('entrada_volver')));
      await tester.pump();
      expect(find.text('OPERADOR'), findsOneWidget);
    });
  });

  group('la pantalla de Entradas', () {
    Evento fiesta(String id, DateTime fecha, {
      EstadoEvento estado = EstadoEvento.confirmado,
      String modalidad = 'masivo',
    }) =>
        Evento(
          id: id,
          clienteId: 'c',
          tipo: 'Recepción',
          fechaEvento: fecha,
          estado: estado,
          modalidad: modalidad,
          encabezadoEvento: 'ESCUELA $id',
        );

    test('los masivos que vienen: los de hoy sí, los pasados y cerrados no, por fecha', () {
      final hoy = DateTime(2026, 11, 3, 18);
      final lista = fiestasQueVienen([
        fiesta('c', DateTime(2026, 12, 12)),
        fiesta('a', DateTime(2026, 11, 3, 9)),
        fiesta('b', DateTime(2026, 12, 1)),
        fiesta('pasada', DateTime(2026, 11, 2)),
        fiesta('cancelada', DateTime(2026, 12, 2), estado: EstadoEvento.cancelado),
        fiesta('terminada', DateTime(2026, 12, 3), estado: EstadoEvento.finalizado),
        fiesta('particular', DateTime(2026, 12, 4), modalidad: 'particular'),
      ], hoy);
      expect(lista.map((e) => e.id), ['a', 'b', 'c']);
    });

    Future<ProviderContainer> abrir(
      WidgetTester tester, {
      required PermisosEfectivos permisos,
      void Function(BuildContext, Evento)? alAbrir,
    }) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...prueba.reemplazos,
          fiestasQueVienenProvider.overrideWith(
            (ref) async => [fiesta('uno', DateTime(2026, 12, 1))],
          ),
        ],
        child: MaterialApp(home: EntradasHomeScreen(onAbrirFiesta: alAbrir)),
      ));
      final c = ProviderScope.containerOf(tester.element(find.byType(EntradasHomeScreen)));
      await c
          .read(appRoleProvider.notifier)
          .entrarComoEntradas(prueba.operadores.lista.first, permisos);
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('dice quién es, lista la fiesta y la abre', (tester) async {
      Evento? abierta;
      await abrir(
        tester,
        permisos: const PermisosEfectivos(entradas: true),
        alAbrir: (_, e) => abierta = e,
      );
      expect(find.text('ENTRADAS · MAXI'), findsOneWidget);
      expect(find.textContaining('01/12/2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('fiesta_uno')));
      expect(abierta?.id, 'uno');
    });

    testWidgets('solo Entradas no ve PASAR A CAJA', (tester) async {
      await abrir(tester, permisos: const PermisosEfectivos(entradas: true));
      expect(find.byKey(const Key('pasar_a_caja')), findsNothing);
    });

    testWidgets('con Cobros también, PASAR A CAJA lo lleva sin PIN', (tester) async {
      final c = await abrir(tester, permisos: _todo);
      await tester.tap(find.byKey(const Key('pasar_a_caja')));
      await tester.pumpAndSettle();
      expect(c.read(appRoleProvider).esCaja, isTrue);
      expect(c.read(appRoleProvider).pideAbrirCaja, isTrue);
    });

    testWidgets('SALIR vuelve a la entrada', (tester) async {
      final c = await abrir(tester, permisos: _todo);
      await tester.tap(find.byKey(const Key('entradas_salir')));
      await tester.pumpAndSettle();
      expect(c.read(appRoleProvider).kind, AppRoleKind.none);
    });

    testWidgets('en un celular, con un nombre largo y los dos botones, no se desborda',
        (tester) async {
      prueba.operadores.lista.insert(
        0,
        operadorDePrueba(
          'a0000000-0000-4000-8000-000000000009',
          'MARIA DE LOS ANGELES FERNANDEZ DE LA TORRE',
          '8888',
        ),
      );
      await abrir(tester, permisos: _todo);
      tester.view.physicalSize = const Size(360, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('pasar_a_caja')), findsOneWidget);
      expect(find.byKey(const Key('entradas_salir')), findsOneWidget);
    });
  });

  group('lo que vive en otros archivos', () {
    String leer(String ruta) => File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

    test('lo entregado en modo Entradas y lo vendido en la barra suben solos', () {
      expect(
        leer('lib/features/common/widgets/operational_sync_coordinator.dart'),
        contains('role.esJefe || role.esCaja || role.esEntradas || role.esBarra'),
      );
    });

    test('la tablet preparada en la oficina se lleva los PIN', () {
      final i = leer('lib/core/services/sync_engine.dart');
      final lista = i.substring(i.indexOf('tablasDeLaPuerta = ['), i.indexOf('];', i.indexOf('tablasDeLaPuerta = [')));
      expect(lista, contains("'operadores_caja'"));
      expect(lista, contains("'permisos_operador'"));
    });

    test('quien está en la caja y tiene Entradas ve ENTRADAS en el menú', () {
      final d = leer('lib/features/dashboard/dashboard_screen.dart');
      expect(d, contains("ref.read(appRoleProvider).permisos.entradas"));
      expect(d, contains('pasarAEntradas()'));
    });
  });
}
