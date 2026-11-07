import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/barra/widgets/ventas_de_la_caja_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// La etapa 5 de la barra, en la pantalla de verdad: cada vale que sale queda anotado;
/// VENTAS reimprime con freno (la última venta, una vez, con motivo y COPIA), imprime lo
/// que no salió, saca el ticket con precios (sin logo) y anula con motivo.
const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late CajaBarra caja;
  late ProductoBarra cerveza, fernet, agua;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', DateTime.now().add(const Duration(days: 5)));
    prueba.eventos.add(fiesta);
    final b = prueba.barra;
    cerveza = b.producto('Cerveza lata', categoria: 'Cervezas');
    fernet = b.producto('Fernet con coca', categoria: 'Tragos');
    agua = b.producto('Agua sin gas', categoria: 'Sin alcohol');
    b.precio(fiesta.id, cerveza, 3500, orden: 0);
    b.precio(fiesta.id, fernet, 6000, orden: 1);
    b.precio(fiesta.id, agua, 1000, orden: 2, stock: 5, aviso: 1);
    caja = await b.abrirCaja(eventoId: fiesta.id, operadorId: _marta, operadorNombre: 'Marta', numeroCaja: 2);
  });

  Future<void> abrir(WidgetTester tester, {Size tamano = const Size(1280, 800)}) async {
    tester.view.physicalSize = tamano;
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

  Future<void> tocar(WidgetTester tester, Finder f, {int veces = 1}) async {
    for (var i = 0; i < veces; i++) {
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }
  }

  Finder porClave(String k) => find.byKey(Key(k));
  Finder producto(ProductoBarra p) => porClave('producto_${p.id}');

  /// 10 cervezas, 2 fernet y [aguas] aguas (hay 5 en stock), en efectivo.
  Future<void> cobrar(WidgetTester tester, {int aguas = 3}) async {
    await tocar(tester, producto(cerveza), veces: 10);
    await tocar(tester, producto(fernet), veces: 2);
    if (aguas > 0) await tocar(tester, producto(agua), veces: aguas);
    await tocar(tester, porClave('pagar_efectivo'));
    await tocar(tester, porClave('cobro_confirmar'));
  }

  /// Cobrar y sacar un solo vale con todo, y volver a VENDER.
  Future<VentaBarra> venderConTodoJunto(WidgetTester tester, {int aguas = 3}) async {
    await cobrar(tester, aguas: aguas);
    await tocar(tester, porClave('forma-todo-junto'));
    await tocar(tester, porClave('imprimir-todo-junto'));
    await tocar(tester, porClave('vales_listo'));
    return prueba.barra.ventasGuardadas.last;
  }

  /// Cobrar y salir sin ningún vale.
  Future<VentaBarra> venderSinVales(WidgetTester tester) async {
    await cobrar(tester);
    await tocar(tester, porClave('vales_listo'));
    await tocar(tester, porClave('vales_salir_igual'));
    return prueba.barra.ventasGuardadas.last;
  }

  Future<void> escribirMotivo(WidgetTester tester, String motivo) async {
    await tester.enterText(porClave('motivo_texto'), motivo);
    await tester.pumpAndSettle();
  }

  bool prendido(WidgetTester tester, String clave) =>
      tester.widget<ButtonStyleButton>(porClave(clave)).onPressed != null;

  String texto(WidgetTester tester, String clave) => tester.widget<Text>(porClave(clave)).data!;

  group('después de cobrar', () {
    testWidgets('cada vale que sale queda anotado, con quién, y se manda a subir', (tester) async {
      await abrir(tester);
      await cobrar(tester);
      await tocar(tester, porClave('forma-por-separado'));
      await tester.enterText(porClave('vale-por-0'), '3');
      await tester.pumpAndSettle();
      await tocar(tester, porClave('imprimir-0'));
      final anotado = prueba.barra.valesGuardados.single;
      expect(anotado.bebidas.single.cantidad, 3);
      expect(anotado.bebidas.single.nombre, 'Cerveza lata');
      expect(anotado.porSeparado, isTrue);
      expect(anotado.numeroVale, 1);
      expect(anotado.copiaNumero, 0);
      expect(anotado.hechoPor, 'Marta');
      expect(anotado.ventaId, prueba.barra.ventasGuardadas.single.id);
      expect(prueba.subidasDeLaBarra, ['barra_vales ${anotado.id}']);
    });

    testWidgets('un vale que no sale no se anota', (tester) async {
      prueba.papel.anda = false;
      await abrir(tester);
      await cobrar(tester);
      await tocar(tester, porClave('forma-todo-junto'));
      await tocar(tester, porClave('imprimir-todo-junto'));
      expect(prueba.barra.valesGuardados, isEmpty);
    });

    testWidgets('el ticket con precios, si lo piden: sin logo, para ahorrar papel', (tester) async {
      await abrir(tester);
      await cobrar(tester);
      await tocar(tester, porClave('vales_ticket'));
      final ticket = prueba.papel.enCrudo.single;
      expect(ticket.whereType<LogoTicket>(), isEmpty);
      expect(
        [for (final r in ticket.whereType<RenglonTicket>()) '${r.izquierda} | ${r.derecha}'],
        containsAll([r'10 x Cerveza lata | $ 35.000', r'TOTAL | $ 50.000']),
      );
      expect(texto(tester, 'vales_aviso_ticket'), 'Salió el ticket con precios.');
      expect(prueba.barra.valesGuardados, isEmpty, reason: 'el ticket no es un vale');
    });
  });

  group('VENTAS', () {
    testWidgets('la última venta se reimprime una vez, con motivo y COPIA', (tester) async {
      await abrir(tester);
      final venta = await venderConTodoJunto(tester);
      await tocar(tester, porClave('vender_ventas'));
      expect(find.byType(VentasDeLaCajaScreen), findsOneWidget);
      expect(texto(tester, 'vales_${venta.id}'), 'Salió 1 vale');

      await tocar(tester, porClave('reimprimir_${venta.id}'));
      expect(prendido(tester, 'motivo_reimprimir'), isFalse, reason: 'sin motivo no reimprime');
      await escribirMotivo(tester, 'se le mojó');
      await tocar(tester, porClave('motivo_reimprimir'));

      final copia = prueba.papel.papeles.last;
      expect(copia.first, '*** COPIA ***');
      expect(copia.last, '*** COPIA ***');
      expect(copia, containsAllInOrder(['10 CERVEZA LATA', '2 FERNET CON COCA', '3 AGUA SIN GAS']));
      expect(copia, contains('Copia 1 - Marta'));
      expect(copia, contains('Motivo: se le mojó'));
      expect(copia, contains('Se entrega solo con el jefe'));
      expect(prueba.papel.enCrudo.last.whereType<LogoTicket>(), isEmpty);

      final anotada = prueba.barra.valesGuardados.last;
      expect(anotada.copiaNumero, 1);
      expect(anotada.motivo, 'se le mojó');
      expect(anotada.hechoPor, 'Marta');
      expect(prueba.subidasDeLaBarra.last, 'barra_vales ${anotada.id}');

      expect(texto(tester, 'aviso_${venta.id}'), 'Salió la copia.');
      expect(prendido(tester, 'reimprimir_${venta.id}'), isFalse, reason: 'una sola vez');
      expect(texto(tester, 'por_que_no_reimprime_${venta.id}'), 'Ya se reimprimió: otra copia, solo el jefe');
      expect(texto(tester, 'vales_${venta.id}'), 'Salió 1 vale · 1 copia');
    });

    testWidgets('solo la última: una venta anterior no la reimprime la cajera', (tester) async {
      await abrir(tester);
      final primera = await venderConTodoJunto(tester);
      final segunda = await venderConTodoJunto(tester, aguas: 0);
      await tocar(tester, porClave('vender_ventas'));
      expect(prendido(tester, 'reimprimir_${segunda.id}'), isTrue);
      expect(prendido(tester, 'reimprimir_${primera.id}'), isFalse);
      expect(texto(tester, 'por_que_no_reimprime_${primera.id}'), 'Solo se reimprime la última venta');
      // La última arriba.
      expect(
        tester.getTopLeft(porClave('venta_${segunda.id}')).dy,
        lessThan(tester.getTopLeft(porClave('venta_${primera.id}')).dy),
      );
    });

    testWidgets('si la copia no sale, lo dice, no se anota, y se puede volver a mandar', (tester) async {
      await abrir(tester);
      final venta = await venderConTodoJunto(tester);
      await tocar(tester, porClave('vender_ventas'));
      prueba.papel.anda = false;
      await tocar(tester, porClave('reimprimir_${venta.id}'));
      await escribirMotivo(tester, 'se cortó');
      await tocar(tester, porClave('motivo_reimprimir'));
      expect(texto(tester, 'aviso_${venta.id}'), contains('No salió la copia'));
      expect(prueba.barra.valesGuardados.where((v) => v.esCopia), isEmpty);
      expect(prendido(tester, 'reimprimir_${venta.id}'), isTrue);

      prueba.papel.anda = true;
      await tocar(tester, porClave('reimprimir_${venta.id}'));
      await escribirMotivo(tester, 'se cortó');
      await tocar(tester, porClave('motivo_reimprimir'));
      expect(prueba.barra.valesGuardados.where((v) => v.esCopia), hasLength(1));
    });

    testWidgets('ANULAR con motivo: queda anotada, sube, y el stock vuelve', (tester) async {
      await abrir(tester);
      final venta = await venderConTodoJunto(tester);
      expect(find.text('Quedan 2'), findsOneWidget);
      await tocar(tester, porClave('vender_ventas'));
      await tocar(tester, porClave('anular_${venta.id}'));
      expect(prendido(tester, 'motivo_anular'), isFalse, reason: 'sin motivo no anula');
      await escribirMotivo(tester, 'se cobró dos veces');
      await tocar(tester, porClave('motivo_anular'));

      final a = prueba.barra.anulacionesGuardadas.single;
      expect(a.ventaId, venta.id);
      expect(a.motivo, 'se cobró dos veces');
      expect(a.hechoPor, 'Marta');
      expect(prueba.subidasDeLaBarra, contains('barra_anulaciones ${a.id}'));
      expect(texto(tester, 'anulada_${venta.id}'), 'ANULADA · se cobró dos veces');
      expect(porClave('reimprimir_${venta.id}'), findsNothing);
      expect(porClave('ticket_${venta.id}'), findsNothing);
      expect(porClave('anular_${venta.id}'), findsNothing);
      expect(prueba.barra.ventasGuardadas.single, venta, reason: 'la venta no se toca');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Quedan 5'), findsOneWidget, reason: 'una anulada no descuenta stock');
    });

    testWidgets('cancelar no anula', (tester) async {
      await abrir(tester);
      final venta = await venderConTodoJunto(tester);
      await tocar(tester, porClave('vender_ventas'));
      await tocar(tester, porClave('anular_${venta.id}'));
      await escribirMotivo(tester, 'no sé');
      await tocar(tester, find.text('CANCELAR'));
      expect(prueba.barra.anulacionesGuardadas, isEmpty);
      expect(porClave('anular_${venta.id}'), findsOneWidget);
    });

    testWidgets('IMPRIMIR LO QUE FALTA: los vales que nunca salieron, como originales', (tester) async {
      await abrir(tester);
      final venta = await venderSinVales(tester);
      await tocar(tester, porClave('vender_ventas'));
      expect(texto(tester, 'vales_${venta.id}'), 'No salió ningún vale');
      expect(prendido(tester, 'reimprimir_${venta.id}'), isFalse);
      await tocar(tester, porClave('faltan_${venta.id}'));
      expect(porClave('vales_venta_guardada'), findsNothing, reason: 'no es una venta recién cobrada');
      await tocar(tester, porClave('forma-todo-junto'));
      await tocar(tester, porClave('imprimir-todo-junto'));
      expect(prueba.papel.papeles.single, isNot(contains('*** COPIA ***')));
      expect(prueba.barra.valesGuardados.single.copiaNumero, 0);
      await tocar(tester, porClave('vales_listo'));
      expect(texto(tester, 'vales_${venta.id}'), 'Salió 1 vale');
      expect(porClave('faltan_${venta.id}'), findsNothing);
      expect(prendido(tester, 'reimprimir_${venta.id}'), isTrue);
    });

    testWidgets('lo que falta sigue donde quedó: lo que salió no vuelve a salir', (tester) async {
      await abrir(tester);
      await cobrar(tester);
      await tocar(tester, porClave('forma-por-separado'));
      await tester.enterText(porClave('vale-por-0'), '3');
      await tester.pumpAndSettle();
      await tocar(tester, porClave('imprimir-0'));
      await tocar(tester, porClave('vales_listo'));
      await tocar(tester, porClave('vales_salir_igual'));
      final venta = prueba.barra.ventasGuardadas.single;

      await tocar(tester, porClave('vender_ventas'));
      expect(texto(tester, 'vales_${venta.id}'), 'Salió 1 vale · faltan 12 sin vale');
      await tocar(tester, porClave('faltan_${venta.id}'));
      await tocar(tester, porClave('forma-todo-junto'));
      expect(
        texto(tester, 'lo-que-queda'),
        'Un vale con lo que queda: 7 cerveza lata, 2 fernet con coca, 3 agua sin gas',
      );
      await tocar(tester, porClave('imprimir-todo-junto'));
      expect(prueba.papel.papeles.last, contains('Caja 2 · Marta · N° 0001-2'),
          reason: 'sigue la numeración de la venta');
      expect(prueba.barra.valesGuardados.last.numeroVale, 2);
    });

    testWidgets('el ticket con precios desde VENTAS', (tester) async {
      await abrir(tester);
      final venta = await venderConTodoJunto(tester);
      await tocar(tester, porClave('vender_ventas'));
      await tocar(tester, porClave('ticket_${venta.id}'));
      expect(prueba.papel.enCrudo.last.whereType<LogoTicket>(), isEmpty);
      expect(texto(tester, 'aviso_${venta.id}'), 'Salió el ticket con precios.');
    });

    testWidgets('sin ventas lo dice', (tester) async {
      await abrir(tester);
      await tocar(tester, porClave('vender_ventas'));
      expect(porClave('ventas_vacio'), findsOneWidget);
    });

    for (final (nombre, tamano) in [
      ('un celular', const Size(360, 740)),
      ('una tablet', const Size(800, 1280)),
    ]) {
      testWidgets('en $nombre no se desborda', (tester) async {
        await abrir(tester, tamano: tamano);
        final venta = await venderConTodoJunto(tester);
        await tocar(tester, porClave('vender_ventas'));
        expect(tester.takeException(), isNull);
        await tocar(tester, porClave('anular_${venta.id}'));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
