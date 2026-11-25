// Las pantallas de la barra por noche (25-nov-2026): LAS CAJAS una noche por vez, el
// "Quedan" de VENDER, BARRA del cierre de caja, la fiesta que sigue a la vista y abrir la
// caja de esta noche aunque haya quedado abierta una de prueba. Con la barra en memoria.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/cajas_de_la_fiesta.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/cierre_caja/widgets/sector_barra.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

const _marta = 'a0000000-0000-4000-8000-000000000001';
const _romi = 'a0000000-0000-4000-8000-000000000002';

/// Un momento en hora de Argentina (UTC-3).
DateTime ar(int mes, int dia, [int hora = 0, int minuto = 0]) => DateTime.utc(2026, mes, dia, hora + 3, minuto);

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento tecnica;
  late ProductoBarra fernet;
  late DateTime ahora;
  late CajaBarra deLaPrueba, caja1, caja2;

  RenglonVenta renglon(int n) => RenglonVenta(productoId: fernet.id, nombre: fernet.nombre, precio: 6000, cantidad: n);

  Future<VentaBarra> vender(CajaBarra c, int n, DateTime cuando) async {
    prueba.barra.reloj = () => cuando;
    return prueba.barra.vender(caja: c, renglones: [renglon(n)], medio: MedioBarra.efectivo, efectivo: 6000.0 * n, quien: 'x');
  }

  Future<CajaBarra> abrirCaja(String operador, String nombre, int numero, DateTime cuando, {String? sede}) async {
    prueba.barra.reloj = () => cuando;
    return prueba.barra.abrirCaja(
      eventoId: tecnica.id,
      operadorId: operador,
      operadorNombre: nombre,
      numeroCaja: numero,
      sede: sede,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    operadores.operadores.lista.add(operadorDePrueba(_romi, 'Romi', '7777'));
    operadores.permisos.poner(_romi, const PermisosEfectivos(barra: true, encargadaBarra: true));
    prueba = BarraEnPrueba();
    tecnica = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    prueba.eventos.add(tecnica);
    fernet = prueba.barra.producto('Fernet con coca', categoria: 'Tragos');
    prueba.barra.precio(tecnica.id, fernet, 6000, stock: 10, aviso: 2);
    // La prueba del 20/11: la Caja 1 de Lucas vendió 5 fernets y cerró con $ 1.000 de más.
    deLaPrueba = await abrirCaja('lucas', 'Lucas', 1, ar(11, 20, 19), sede: 'Barra 1');
    await vender(deLaPrueba, 5, ar(11, 20, 20));
    prueba.barra.reloj = () => ar(11, 20, 23);
    await prueba.barra.cerrarCaja(deLaPrueba, efectivoContado: 31000, diferencia: 1000, quien: 'Lucas');
    // La noche de la fiesta: otra Caja 1 (Marta) y la Caja 2 (Sofía), que vende de madrugada.
    caja1 = await abrirCaja(_marta, 'Marta', 1, ar(12, 4, 18), sede: 'Barra 1');
    caja2 = await abrirCaja('sofia', 'Sofía', 2, ar(12, 4, 18, 10), sede: 'Barra 2');
    await vender(caja1, 2, ar(12, 4, 23));
    await vender(caja2, 1, ar(12, 5, 2, 30));
    ahora = ar(12, 5, 2, 45);
  });

  Future<void> montar(WidgetTester tester, Widget pantalla, {Size tamano = const Size(1280, 900)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        esRolJefeProvider.overrideWithValue(true),
        relojDeLaBarraProvider.overrideWithValue(() => ahora),
      ],
      child: MaterialApp(home: Scaffold(body: pantalla)),
    ));
    await tester.pumpAndSettle();
  }

  String texto(WidgetTester tester, String clave) => tester.widget<Text>(find.byKey(Key(clave))).data!;

  group('LAS CAJAS, una noche por vez', () {
    testWidgets('viene en la de esta noche: los totales y el stock sin la prueba del 20/11', (tester) async {
      await montar(tester, CajasDeLaFiestaVista(fiesta: tecnica));
      expect(texto(tester, 'jefe_kpi_total_valor'), r'$ 18.000', reason: '3 fernets de esta noche, no los 5 de la prueba');
      expect(texto(tester, 'jefe_kpi_ventas_valor'), '2');
      expect(find.byKey(Key('jefe_caja_${caja1.id}')), findsOneWidget);
      expect(find.byKey(Key('jefe_caja_${caja2.id}')), findsOneWidget);
      expect(find.byKey(Key('jefe_caja_${deLaPrueba.id}')), findsNothing);
      expect(find.byKey(const Key('jefe_kpi_diferencia')), findsNothing, reason: 'ninguna cerrada esta noche');
      expect(find.text('Quedan 7 de 10'), findsOneWidget, reason: 'el stock de esta noche');
      expect(texto(tester, 'jefe_caja_horario_${caja1.id}'), 'Marta · Barra 1 · abierta desde las 18:00');
      // Arriba, las noches para tocar.
      expect(find.text('Esta noche · Vie 04/12 · 2 cajas'), findsOneWidget);
      expect(find.text('Vie 20/11 · 1 caja'), findsOneWidget);
      expect(find.byKey(const Key('jefe_noche_otra')), findsNothing);
    });

    testWidgets('tocar otra noche: sus cajas, con su fecha, y lo dice en ámbar', (tester) async {
      await montar(tester, CajasDeLaFiestaVista(fiesta: tecnica));
      await tester.tap(find.byKey(const Key('jefe_noche_2026-11-20')));
      await tester.pumpAndSettle();
      expect(texto(tester, 'jefe_kpi_total_valor'), r'$ 30.000');
      expect(texto(tester, 'jefe_kpi_diferencia_valor'), r'Sobran $ 1.000');
      expect(find.byKey(Key('jefe_caja_${caja1.id}')), findsNothing);
      expect(texto(tester, 'jefe_caja_horario_${deLaPrueba.id}'), 'Lucas · Barra 1 · Vie 20/11 · de 19:00 a 23:00');
      expect(find.byKey(const Key('jefe_noche_otra')), findsOneWidget);
      expect(find.text('Quedan 5 de 10'), findsOneWidget, reason: 'el stock de esa noche');
      // LO VENDIDO DE LA FIESTA dice de qué noche es.
      await tester.tap(find.byKey(const Key('jefe_vendido_fiesta')));
      await tester.pumpAndSettle();
      final papel = find.byKey(const Key('jefe_vendido_fiesta_papel'));
      expect(find.descendant(of: papel, matching: find.text('La caja del 20/11')), findsOneWidget);
    });

    testWidgets('la noche de la fiesta, antes de abrir cajas, no muestra las de prueba', (tester) async {
      prueba.barra.cajasGuardadas.removeWhere((c) => c.id == caja1.id || c.id == caja2.id);
      ahora = ar(12, 4, 17);
      await montar(tester, CajasDeLaFiestaVista(fiesta: tecnica));
      expect(find.byKey(const Key('jefe_sin_cajas_esta_noche')), findsOneWidget);
      expect(find.text('Vie 20/11 · 1 caja'), findsOneWidget, reason: 'la prueba, arriba para tocar');
    });

    testWidgets('en el celular de la encargada no se desborda con las noches arriba', (tester) async {
      await montar(tester, CajasDeLaFiestaVista(fiesta: tecnica), tamano: const Size(360, 740));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('jefe_noche_2026-11-20')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('VENDER: el "Quedan" cuenta solo lo vendido esta noche', (tester) async {
    await montar(tester, VenderScreen(fiesta: tecnica, caja: caja1));
    expect(find.text('Quedan 7'), findsOneWidget, reason: '10 cargados, 3 vendidos esta noche (no 8 con la prueba)');
  });

  group('BARRA del cierre de caja', () {
    testWidgets('las cajas de la noche del cierre; las otras noches arriba', (tester) async {
      await montar(tester, const SingleChildScrollView(child: SectorBarraDelCierre(isDark: false)));
      expect(texto(tester, 'cierre_barra_noche'), 'Las cajas del viernes 4 de diciembre');
      expect(find.byKey(Key('cierre_barra_caja_${caja1.id}')), findsOneWidget);
      expect(find.byKey(Key('cierre_barra_caja_${deLaPrueba.id}')), findsNothing);
    });

    testWidgets('un cierre de otro día muestra las cajas de ese día', (tester) async {
      await montar(
        tester,
        SingleChildScrollView(child: SectorBarraDelCierre(isDark: false, diaDelCierre: DateTime(2026, 11, 20))),
      );
      expect(texto(tester, 'cierre_barra_noche'), 'Las cajas del viernes 20 de noviembre');
      expect(find.byKey(Key('cierre_barra_caja_${deLaPrueba.id}')), findsOneWidget);
      expect(find.byKey(Key('cierre_barra_caja_${caja1.id}')), findsNothing);
    });
  });

  group('el inicio de la barra', () {
    Future<ProviderContainer> entrar(WidgetTester tester, String quien, PermisosEfectivos permisos,
        {void Function(BuildContext, Evento, CajaBarra)? alAbrir}) async {
      await montar(tester, BarraHomeScreen(onCajaLista: alAbrir ?? (_, _, _) {}));
      final c = ProviderScope.containerOf(tester.element(find.byType(BarraHomeScreen)));
      await c.read(appRoleProvider.notifier).entrarComoBarra(
            operadores.operadores.lista.firstWhere((o) => o.id == quien),
            permisos,
          );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('pasado el mediodía, la fiesta sigue a la vista de la encargada mientras queden cajas de esa noche',
        (tester) async {
      ahora = ar(12, 5, 14);
      await entrar(tester, _romi, const PermisosEfectivos(barra: true, encargadaBarra: true));
      expect(texto(tester, 'barra_caja_abierta_${tecnica.id}'), '04/12/2026 · Siguen abiertas cajas de esa noche');
      expect(find.byKey(Key('barra_las_cajas_${tecnica.id}')), findsOneWidget, reason: 'LAS CAJAS, para dar el OK');
      // Tocar la fiesta no le abre una caja nueva en una fiesta que ya pasó.
      await tester.tap(find.byKey(Key('barra_fiesta_${tecnica.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Abrir tu caja'), findsNothing);
      expect(find.byKey(const Key('barra_fiesta_pasada_sin_caja')), findsOneWidget);
    });

    testWidgets('cerradas las cajas de esa noche, la fiesta se va (la de prueba abierta no la retiene)', (tester) async {
      for (final c in [caja1, caja2]) {
        await prueba.barra.cerrarCaja(c, efectivoContado: 0, diferencia: 0, quien: 'x');
      }
      // Una caja de prueba de otra noche que quedó abierta no cuenta.
      await abrirCaja('lucas', 'Lucas', 3, ar(11, 21, 19));
      ahora = ar(12, 5, 14);
      await entrar(tester, _romi, const PermisosEfectivos(barra: true, encargadaBarra: true));
      expect(find.byKey(Key('barra_fiesta_${tecnica.id}')), findsNothing);
    });

    testWidgets('con una caja suya de prueba abierta de otra noche, abre la de hoy y la vieja queda aparte',
        (tester) async {
      prueba.barra.cajasGuardadas.removeWhere((c) => c.id == caja1.id || c.id == caja2.id);
      final vieja = await abrirCaja(_marta, 'Marta', 1, ar(11, 21, 19));
      ahora = ar(12, 4, 19);
      prueba.barra.reloj = () => ahora;
      CajaBarra? lista;
      await entrar(tester, _marta, const PermisosEfectivos(barra: true), alAbrir: (_, _, c) => lista = c);
      await tester.tap(find.byKey(Key('barra_fiesta_${tecnica.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Abrir tu caja'), findsOneWidget, reason: 'no retoma la caja de prueba del 21/11');
      await tester.tap(find.byKey(const Key('caja_numero_1')));
      await tester.pump();
      expect(find.byKey(const Key('caja_numero_ocupada')), findsNothing,
          reason: 'la Caja 1 de prueba de otra noche no avisa');
      await tester.tap(find.byKey(const Key('caja_barra_2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('caja_abrir')));
      await tester.pumpAndSettle();
      expect(lista, isNotNull);
      expect(lista!.id, isNot(vieja.id));
      expect(lista!.sede, 'Barra 2');
      expect(DiaDeOperacion.deLaCaja(lista!), const DiaDeOperacion(2026, 12, 4));
      expect(prueba.barra.cajasGuardadas.firstWhere((c) => c.id == vieja.id).abierta, isTrue,
          reason: 'nada se borra: la de prueba sigue en su día');
    });

    testWidgets('la barra elegida queda para la próxima caja de este equipo', (tester) async {
      await SharedPreferences.getInstance().then((p) => p.setString('barra.barra_del_equipo_v1', 'Barra 2'));
      prueba.barra.cajasGuardadas.removeWhere((c) => c.id == caja1.id);
      ahora = ar(12, 4, 19);
      prueba.barra.reloj = () => ahora;
      CajaBarra? lista;
      await entrar(tester, _marta, const PermisosEfectivos(barra: true), alAbrir: (_, _, c) => lista = c);
      await tester.tap(find.byKey(Key('barra_fiesta_${tecnica.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('caja_numero_3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('caja_abrir')));
      await tester.pumpAndSettle();
      expect(lista?.sede, 'Barra 2', reason: 'venía elegida la de la vez anterior');
    });
  });
}
