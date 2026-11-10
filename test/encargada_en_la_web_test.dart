import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_web.dart';
import 'package:arguello_events/features/barra/widgets/las_cajas_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/modo_jefe_caja.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/operadores_caja_repository.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/permisos_operador_repository.dart';
import 'package:arguello_events/features/caja_sesiones/services/entrada_de_operador.dart';
import 'package:arguello_events/features/caja_sesiones/services/operador_por_la_nube.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_de_la_nube_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// La Encargada de barra con su PIN **en la web del iPhone** (6.5.0). En el navegador no
/// hay base del equipo: el PIN se le pregunta a la nube, entra solo la encargada, y lo
/// que ve es LAS CAJAS (anula con motivo, a su nombre). No vende ni imprime, y nunca
/// arma el panel.
const _romi = 'a0000000-0000-4000-8000-000000000007';
const _marta = 'a0000000-0000-4000-8000-000000000008';
const _maxi = 'a0000000-0000-4000-8000-000000000001';
const _ana = 'a0000000-0000-4000-8000-000000000002';

/// El mismo reparto que el router de la app (`_RoleRouter`, en `main.dart`).
class _Router extends ConsumerWidget {
  const _Router();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (destinoDeEntrada(ref.watch(appRoleProvider))) {
      DestinoDeEntrada.elegir => const RoleGateScreen(),
      DestinoDeEntrada.barra => const BarraHomeScreen(),
      DestinoDeEntrada.entradas => const Scaffold(body: Text('ENTRADAS')),
      DestinoDeEntrada.panel => const Scaffold(body: Text('PANEL')),
    };
  }
}

void main() {
  late OperadoresDeLaNubeEnMemoria nube;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late CajaBarra caja;
  late VentaBarra fernet;

  /// Lo que hay en la web: la nube, y **nada del equipo** (si algo lo toca, falla).
  List<Override> enLaWeb() => [
        enLaWebProvider.overrideWithValue(true),
        operadoresDeLaNubeProvider.overrideWithValue(nube),
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        eventosDeLaBarraProvider.overrideWith((ref) async => prueba.eventos),
        relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 12, 4, 20)),
        operadoresCajaRepositoryProvider.overrideWith(
          (ref) => throw StateError('en la web no hay base: operadores'),
        ),
        permisosOperadorRepositoryProvider.overrideWith(
          (ref) => throw StateError('en la web no hay base: permisos'),
        ),
        barraDeLaCajaProvider.overrideWith(
          (ref) => throw StateError('en la web no hay barra del equipo'),
        ),
        papelDeLaBarraProvider.overrideWith(
          (ref) => throw StateError('en la web no hay impresora'),
        ),
        accesosBarraProvider.overrideWith(
          (ref) => throw StateError('en la web no hay puesta al día'),
        ),
      ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    nube = OperadoresDeLaNubeEnMemoria()
      ..poner(_romi, 'Romi', '7777', barra: 2)
      ..poner(_marta, 'Marta', '2222', barra: 1)
      ..poner(_maxi, 'Maxi', '1234', conFila: false)
      ..poner(_ana, 'Ana', '5555', entradas: 1);
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', DateTime(2026, 12, 4, 22));
    prueba.eventos.addAll([
      fiesta,
      fiestaDePrueba(BarraEnPrueba.id(2), 'LA DE OCTUBRE', DateTime(2026, 10, 30, 22)),
    ]);
    final b = prueba.barra;
    final producto = b.producto('Fernet con coca');
    b.precio(fiesta.id, producto, 6000);
    caja = await b.abrirCaja(
      eventoId: fiesta.id,
      operadorId: _marta,
      operadorNombre: 'Marta',
      numeroCaja: 2,
      cambioInicial: 15000,
    );
    fernet = await b.vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: producto.id, nombre: producto.nombre, precio: 6000, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 12000,
      quien: 'Marta',
    );
    await b.anotarVale(ValeBarra.salio(
      venta: fernet,
      bebidas: [BebidaDelVale(2, producto.nombre)],
      porSeparado: false,
      hechoPor: 'Marta',
      ahora: DateTime(2026, 12, 4, 23),
    ));
  });

  group('de quién es el PIN, según la nube', () {
    test('la encargada: activo booleano y un 2 en barra', () async {
      final r = await operadorPorLaNube(nube, '7777');
      expect(r!.operador.nombre, 'Romi');
      expect(r.operador.activo, isTrue);
      expect(r.permisos.encargadaBarra, isTrue);
      expect(r.permisos.tiene(PermisoOperador.barra), isTrue);
    });

    test('sin fila de permisos es de Cobros solo, como en la PC', () async {
      final r = await operadorPorLaNube(nube, '1234');
      expect(r!.permisos, PermisosEfectivos.soloCobros);
    });

    test('un PIN que no es de nadie da null', () async {
      expect(await operadorPorLaNube(nube, '9999'), isNull);
    });

    test('dado de baja no entra, venga el activo como booleano o como número', () async {
      nube
        ..poner('a0000000-0000-4000-8000-000000000011', 'Baja', '3001', activo: false, barra: 2)
        ..poner('a0000000-0000-4000-8000-000000000012', 'Baja', '3002', activo: 0, barra: 2)
        ..poner('a0000000-0000-4000-8000-000000000013', 'Sigue', '3003', activo: 1, barra: 2);
      expect(await operadorPorLaNube(nube, '3001'), isNull);
      expect(await operadorPorLaNube(nube, '3002'), isNull);
      expect((await operadorPorLaNube(nube, '3003'))!.operador.nombre, 'Sigue');
    });

    test('el mismo PIN en uno de baja y uno activo: entra el activo', () async {
      nube
        ..poner('a0000000-0000-4000-8000-000000000021', 'La de antes', '4000', activo: false, barra: 2)
        ..poner('a0000000-0000-4000-8000-000000000022', 'La de ahora', '4000', barra: 2);
      expect((await operadorPorLaNube(nube, '4000'))!.operador.nombre, 'La de ahora');
    });

    test('el operador del modo jefe no entra con PIN', () async {
      nube.poner(kOperadorModoJefeId, kOperadorModoJefeNombre, '6000', barra: 2);
      expect(await operadorPorLaNube(nube, '6000'), isNull);
    });

    test('un PIN vacío no le pregunta nada a la nube', () async {
      expect(await operadorPorLaNube(nube, '   '), isNull);
      expect(nube.consultas, 0);
    });

    test('si la nube falla, el error sube: no es un PIN incorrecto', () async {
      nube.falla = StateError('sin internet');
      await expectLater(operadorPorLaNube(nube, '7777'), throwsStateError);
    });
  });

  group('qué se despliega en la web', () {
    test('la encargada entra derecho a la barra, tenga o no otros permisos', () {
      final sola = OpcionesDeEntrada.de(const PermisosEfectivos(encargadaBarra: true), enLaWeb: true);
      expect(sola.aviso, isNull);
      expect(sola.directo, PermisoOperador.barra);
      final conTodo = OpcionesDeEntrada.de(
        const PermisosEfectivos(cobros: true, entradas: true, encargadaBarra: true),
        enLaWeb: true,
      );
      expect(conTodo.directo, PermisoOperador.barra);
      expect(conTodo.paraElegir, isEmpty, reason: 'en la web no se elige Cobros ni Entradas');
    });

    test('la cajera, Cobros y Entradas no entran: se les dice que usen la app', () {
      for (final p in const [
        PermisosEfectivos(barra: true),
        PermisosEfectivos.soloCobros,
        PermisosEfectivos(entradas: true),
        PermisosEfectivos(cobros: true, entradas: true, barra: true),
      ]) {
        final o = OpcionesDeEntrada.de(p, enLaWeb: true);
        expect(o.aviso, kDesdeElNavegadorNo);
        expect(o.directo, isNull);
        expect(o.paraElegir, isEmpty);
      }
    });

    test('sin permisos, lo de siempre', () {
      expect(OpcionesDeEntrada.de(const PermisosEfectivos(), enLaWeb: true).aviso, kTeFaltanPermisos);
    });
  });

  group('el rol, en la web', () {
    late ProviderContainer c;
    AppRoleNotifier rol() => c.read(appRoleProvider.notifier);

    setUp(() {
      c = ProviderContainer(overrides: enLaWeb());
      addTearDown(c.dispose);
    });

    test('el PIN se busca en la nube, sin tocar la base del equipo', () async {
      final r = await rol().buscarOperador('7777');
      expect(r!.operador.nombre, 'Romi');
      expect(r.permisos.encargadaBarra, isTrue);
      expect(nube.consultas, 1);
    });

    test('un PIN equivocado da null', () async {
      expect(await rol().buscarOperador('9999'), isNull);
    });

    test('sin internet no dice "PIN incorrecto": avisa que no pudo comprobarlo', () async {
      nube.falla = StateError('sin internet');
      await expectLater(rol().buscarOperador('7777'), throwsA(isA<SinNubeParaElPin>()));
    });

    test('adentro, es la encargada y manda en las cajas; sin caja de cuotas', () async {
      final r = (await rol().buscarOperador('7777'))!;
      await rol().entrarComoBarra(r.operador, r.permisos);
      final app = c.read(appRoleProvider);
      expect(app.esEncargadaDeBarra, isTrue);
      expect(c.read(mandaEnLaBarraProvider), isTrue);
      expect(c.read(esRolJefeProvider), isFalse);
      expect(destinoDeEntrada(app), DestinoDeEntrada.barra);
      expect(app.sesionActiva, isNull);
    });
  });

  group('en el iPhone, de punta a punta', () {
    Future<ProviderContainer> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: enLaWeb(),
        child: const MaterialApp(home: _Router()),
      ));
      await tester.pump();
      return ProviderScope.containerOf(tester.element(find.byType(_Router)));
    }

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

    Future<void> tocar(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('Romi pone su PIN y entra derecho a la barra: las fiestas, sin vender ni '
        'imprimir', (tester) async {
      final c = await abrir(tester);
      await ponerPin(tester, '7777');
      await tester.pumpAndSettle();
      expect(find.byType(BarraHomeEnLaWeb), findsOneWidget);
      expect(find.text('BARRA · ROMI'), findsOneWidget);
      expect(find.byKey(const Key('barra_impresora')), findsNothing);
      expect(find.byKey(const Key('barra_web_ayuda')), findsOneWidget);
      expect(find.text('LAS QUE VIENEN'), findsOneWidget);
      expect(find.text('LAS ÚLTIMAS'), findsOneWidget);
      expect(find.textContaining('viernes 4 de diciembre · hoy'), findsOneWidget);
      expect(find.byKey(Key('barra_fiesta_${BarraEnPrueba.id(2)}')), findsOneWidget);
      expect(find.text('PANEL'), findsNothing);
      expect(c.read(appRoleProvider).esEncargadaDeBarra, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toca la fiesta, ve LAS CAJAS y anula una venta con motivo, a su nombre',
        (tester) async {
      await abrir(tester);
      await ponerPin(tester, '7777');
      await tester.pumpAndSettle();
      await tocar(tester, find.byKey(Key('barra_fiesta_${fiesta.id}')));
      expect(find.byType(LasCajasScreen), findsOneWidget);
      expect(find.byKey(const Key('jefe_pestana_catalogo')), findsNothing);
      expect(find.byKey(const Key('jefe_pestana_precios')), findsNothing);
      expect(find.text('PRENDER LA CENTRAL'), findsNothing);
      await tocar(tester, find.byKey(Key('jefe_caja_${caja.id}')));
      expect(find.byKey(Key('jefe_reimprimir_${fernet.id}')), findsNothing,
          reason: 'en el navegador no hay impresora');
      await tocar(tester, find.byKey(Key('jefe_anular_${fernet.id}')));
      await tester.enterText(find.byKey(const Key('motivo_texto')), 'se cobró dos veces');
      await tester.pumpAndSettle();
      await tocar(tester, find.byKey(const Key('motivo_anular')));
      final a = prueba.barra.anulacionesGuardadas.single;
      expect(a.ventaId, fernet.id);
      expect(a.motivo, 'se cobró dos veces');
      expect(a.hechoPor, 'Romi');
      expect(prueba.subidasDeLaBarra, isEmpty, reason: 'en la web no hay cola: ya está en la nube');
      expect(find.byKey(Key('jefe_anulada_${fernet.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la cajera de barra no entra: se le dice que use la app', (tester) async {
      final c = await abrir(tester);
      await ponerPin(tester, '2222');
      expect(find.text(kDesdeElNavegadorNo), findsOneWidget);
      expect(find.text('OPERADOR'), findsOneWidget);
      expect(c.read(appRoleProvider).kind, AppRoleKind.none);
    });

    testWidgets('ni Cobros ni Entradas entran desde el navegador', (tester) async {
      final c = await abrir(tester);
      for (final pin in ['1234', '5555']) {
        await ponerPin(tester, pin);
        expect(find.text(kDesdeElNavegadorNo), findsOneWidget, reason: pin);
        expect(c.read(appRoleProvider).kind, AppRoleKind.none, reason: pin);
      }
      expect(find.text('PANEL'), findsNothing);
      expect(find.text('ENTRADAS'), findsNothing);
    });

    testWidgets('un PIN equivocado lo dice', (tester) async {
      await abrir(tester);
      await ponerPin(tester, '9999');
      expect(find.text('PIN incorrecto o operador inactivo'), findsOneWidget);
    });

    testWidgets('sin internet lo dice, y no como PIN incorrecto', (tester) async {
      await abrir(tester);
      nube.falla = StateError('sin internet');
      await ponerPin(tester, '7777');
      expect(find.text(kSinNubeParaElPin), findsOneWidget);
      expect(find.text('PIN incorrecto o operador inactivo'), findsNothing);
      // Vuelve internet: el mismo PIN entra.
      nube.falla = null;
      await ponerPin(tester, '7777');
      await tester.pumpAndSettle();
      expect(find.text('BARRA · ROMI'), findsOneWidget);
    });

    testWidgets('si la nube no contesta, a los 8 segundos lo dice y se puede reintentar',
        (tester) async {
      await abrir(tester);
      nube.colgada = true;
      await ponerPin(tester, '7777');
      expect(find.text(kSinNubeParaElPin), findsNothing);
      await tester.pump(kEsperaDelPinEnLaNube);
      await tester.pump();
      expect(find.text(kSinNubeParaElPin), findsOneWidget);
      expect(find.text('OPERADOR'), findsOneWidget);
    });

    testWidgets('SALIR vuelve a la entrada', (tester) async {
      final c = await abrir(tester);
      await ponerPin(tester, '7777');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('barra_salir')));
      await tester.pumpAndSettle();
      expect(c.read(appRoleProvider).kind, AppRoleKind.none);
      expect(find.text('OPERADOR'), findsOneWidget);
    });

    testWidgets('la segunda llave: una cajera que llegara a la barra en la web no ve fiestas',
        (tester) async {
      final c = await abrir(tester);
      await c.read(appRoleProvider.notifier).entrarComoBarra(
            operadorDePrueba(_marta, 'Marta', '2222'),
            const PermisosEfectivos(barra: true),
          );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('barra_web_solo_encargada')), findsOneWidget);
      expect(find.byKey(Key('barra_fiesta_${fiesta.id}')), findsNothing);
      expect(find.byKey(const Key('barra_salir')), findsOneWidget);
    });

    testWidgets('si no se pueden leer las fiestas, lo dice y deja probar de nuevo',
        (tester) async {
      var falla = true;
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          for (final o in enLaWeb().sublist(0, 3)) o,
          eventosDeLaBarraProvider.overrideWith(
            (ref) async => falla ? throw StateError('sin internet') : prueba.eventos,
          ),
          relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 12, 4, 20)),
        ],
        child: const MaterialApp(home: _Router()),
      ));
      await tester.pump();
      await ponerPin(tester, '7777');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('barra_web_sin_fiestas_error')), findsOneWidget);
      falla = false;
      await tester.tap(find.text('PROBAR DE NUEVO'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('barra_fiesta_${fiesta.id}')), findsOneWidget);
    });
  });

  group('lo que vive en los archivos', () {
    String leer(String ruta) => File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

    test('el PIN por la nube va por supabaseProvider, nunca por el singleton', () {
      final f = leer('lib/features/caja_sesiones/services/operador_por_la_nube.dart');
      expect(f, contains('supabaseProvider'));
      expect(f, isNot(contains('Supabase.instance')));
    });

    test('buscarOperador pregunta por la llave de la web antes de tocar la base', () {
      final rol = leer('lib/features/caja_sesiones/providers/app_role_provider.dart');
      final i = rol.indexOf('Future<OperadorYPermisos?> buscarOperador(String pin) async {');
      final cuerpo = rol.substring(i, rol.indexOf('\n  }\n', i));
      expect(cuerpo, contains('ref.read(enLaWebProvider)'));
      expect(
        cuerpo.indexOf('ref.read(enLaWebProvider)'),
        lessThan(cuerpo.indexOf('_operadorDelPin(pin)')),
      );
      expect(rol, isNot(contains('kIsWeb')));
    });

    test('la pantalla de entrada le pasa la llave de la web a las opciones', () {
      final gate = leer('lib/features/caja_sesiones/widgets/role_gate_screen.dart');
      expect(gate, contains('enLaWeb: ref.read(enLaWebProvider)'));
      expect(gate, contains('on SinNubeParaElPin'));
      expect(gate, isNot(contains('kIsWeb')));
    });

    test('el inicio de la barra elige la pantalla de la web antes de mirar nada del equipo', () {
      final home = leer('lib/features/barra/widgets/barra_home_screen.dart');
      final i = home.indexOf('Widget build(BuildContext context) {');
      final cuerpo = home.substring(i);
      final web = cuerpo.indexOf('if (ref.watch(enLaWebProvider)) return const BarraHomeEnLaWeb();');
      expect(web, greaterThan(0));
      for (final delEquipo in ['fiestasDeLaBarraProvider', 'puestaAlDiaBarraProvider']) {
        expect(web, lessThan(cuerpo.indexOf(delEquipo)), reason: delEquipo);
      }
    });

    test('la barra de la web no tiene nada del equipo: ni caja, ni impresora, ni vender', () {
      final web = leer('lib/features/barra/widgets/barra_home_web.dart');
      for (final prohibido in [
        'barraDeLaCajaProvider',
        'barraDeEsteEquipoProvider',
        'puestaAlDiaBarraProvider',
        'impresoraDeLaBarraProvider',
        'papelDeLaBarraProvider',
        'ElegirImpresoraScreen',
        'VenderScreen',
        'abrirCaja',
        'kIsWeb',
        'Supabase.instance',
      ]) {
        expect(web, isNot(contains(prohibido)), reason: prohibido);
      }
      expect(web, contains('LasCajasScreen('));
      expect(web, contains('esEncargadaDeBarra'));
    });
  });
}
