import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/barra/widgets/cerrar_caja_barra_screen.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// La etapa 6 de la barra, de punta a punta en la pantalla de verdad: desde el inicio, la
/// cajera entra a su caja, toca el candado, cuenta **a ciegas** (sin ver ninguna plata),
/// confirma, y recién ahí ve lo esperado, la diferencia y el cierre entero como el papel,
/// con el historial. Sale el papel por la térmica (sin historial), se guarda el PDF, se
/// agrega una nota, y al volver la caja ya no está abierta.
const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento fiesta;
  late CajaBarra caja;
  late VentaBarra cervezas, fernet, anulada;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    prueba = BarraEnPrueba();
    fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', DateTime.now().add(const Duration(days: 5)));
    prueba.eventos.add(fiesta);
    final b = prueba.barra;
    final cerveza = b.producto('Cerveza lata');
    final fer = b.producto('Fernet con coca');
    final agua = b.producto('Agua sin gas');
    b.precio(fiesta.id, cerveza, 3500);
    b.precio(fiesta.id, fer, 6000);
    b.precio(fiesta.id, agua, 1000);
    final abierta = await b.abrirCaja(eventoId: fiesta.id, operadorId: _marta, operadorNombre: 'Marta', numeroCaja: 2);
    caja = await b.ponerCambio(abierta, 20000, quien: 'Marta');
    RenglonVenta r(ProductoBarra p, double precio, int n) =>
        RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: n);
    cervezas = await b.vender(
      caja: caja,
      renglones: [r(cerveza, 3500, 2)],
      medio: MedioBarra.efectivo,
      efectivo: 7000,
      quien: 'Marta',
    );
    fernet = await b.vender(
      caja: caja,
      renglones: [r(fer, 6000, 1)],
      medio: MedioBarra.transferencia,
      transferencia: 6000,
      quien: 'Marta',
    );
    anulada = await b.vender(
      caja: caja,
      renglones: [r(agua, 1000, 3)],
      medio: MedioBarra.efectivo,
      efectivo: 3000,
      quien: 'Marta',
    );
    await b.anular(anulada, motivo: 'se cobró dos veces', quien: 'Marta');
    // Esperado: 20.000 de cambio + 7.000 en efectivo (la anulada no cuenta) = 27.000.
  });

  Future<void> abrir(WidgetTester tester, {Size tamano = const Size(1280, 800)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [...operadores.reemplazos, ...prueba.reemplazos],
      child: const MaterialApp(home: BarraHomeScreen()),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(BarraHomeScreen)));
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

  Finder porClave(String k) => find.byKey(Key(k));
  bool prendido(WidgetTester tester, String clave) =>
      tester.widget<ButtonStyleButton>(porClave(clave)).onPressed != null;
  String texto(WidgetTester tester, String clave) => tester.widget<Text>(porClave(clave)).data!;
  CajaBarra guardada() => prueba.barra.cajasGuardadas.single;

  /// Del inicio a la pantalla de contar.
  Future<void> irACerrar(WidgetTester tester) async {
    await tocar(tester, porClave('barra_fiesta_${fiesta.id}'));
    expect(find.byType(VenderScreen), findsOneWidget, reason: 'retoma su caja abierta');
    await tocar(tester, porClave('vender_cerrar'));
    expect(find.byType(CerrarCajaBarraScreen), findsOneWidget);
  }

  Future<void> contarYCerrar(WidgetTester tester, String contado) async {
    await tester.enterText(porClave('cierre_contado'), contado);
    await tester.pumpAndSettle();
    await tocar(tester, porClave('cierre_cerrar'));
    await tocar(tester, porClave('cierre_confirmar'));
  }

  testWidgets('de punta a punta: contar a ciegas, cerrar, ver el cierre, nota, papel, PDF y volver',
      (tester) async {
    await abrir(tester);
    await irACerrar(tester);

    // 1. A ciegas: ninguna plata de la caja a la vista.
    for (final plata in ['27.000', '20.000', '7.000', '6.000', '13.000']) {
      expect(find.textContaining(plata), findsNothing, reason: 'antes de contar se ve $plata');
    }
    expect(prendido(tester, 'cierre_cerrar'), isFalse, reason: 'sin un número no se cierra');

    await tester.enterText(porClave('cierre_contado'), '26500');
    await tester.pumpAndSettle();
    await tocar(tester, porClave('cierre_cerrar'));
    expect(texto(tester, 'cierre_contado_grande'), r'$ 26.500', reason: 'confirma viendo el número grande');
    expect(guardada().abierta, isTrue, reason: 'todavía no cerró');
    await tocar(tester, porClave('cierre_confirmar'));

    // 2. Cerrada, con lo contado y la diferencia, y sube.
    expect(guardada().abierta, isFalse);
    expect(guardada().efectivoContado, 26500);
    expect(guardada().diferencia, -500);
    expect(prueba.subidasDeLaBarra, contains('barra_cajas ${caja.id}'));

    // El papel de la térmica: el cierre, sin el historial.
    final papel = prueba.papel.papeles.last;
    expect(papel, containsAllInOrder(['JUNIOR EVENTOS', 'CIERRE DE CAJA - BARRA', r'Faltan $ 500']));
    expect(papel, isNot(contains('HISTORIAL')));
    expect(
      [for (final r in prueba.papel.enCrudo.last.whereType<RenglonTicket>()) r.izquierda],
      containsAllInOrder(['2 x Cerveza lata', '1 x Fernet con coca', 'Ventas']),
    );
    expect(prueba.papel.enCrudo.last.whereType<LogoTicket>(), isEmpty);
    expect(texto(tester, 'cierre_aviso'), 'Caja cerrada. Salió el papel del cierre.');

    // En la pantalla: lo esperado, la diferencia y el papel con el historial.
    expect(texto(tester, 'cierre_esperado'), r'Tenía que haber $ 27.000');
    expect(texto(tester, 'cierre_diferencia'), r'Faltan $ 500');
    expect(find.descendant(of: porClave('cierre_papel'), matching: find.text('HISTORIAL')), findsOneWidget);
    expect(
      find.descendant(of: porClave('cierre_papel'), matching: find.textContaining('ANULADA')),
      findsOneWidget,
      reason: 'la anulada, marcada en el historial',
    );

    // La nota: lo único que cambia después.
    await tocar(tester, porClave('cierre_anotar'));
    await tester.enterText(porClave('motivo_texto'), 'faltó un billete de 500');
    await tester.pumpAndSettle();
    await tocar(tester, porClave('nota_guardar'));
    expect(guardada().notaCierre, 'faltó un billete de 500');
    expect(guardada().efectivoContado, 26500, reason: 'lo contado no cambia');
    expect(guardada().diferencia, -500);
    expect(find.descendant(of: porClave('cierre_papel'), matching: find.text('Nota: faltó un billete de 500')),
        findsOneWidget);

    await tocar(tester, porClave('cierre_imprimir'));
    expect(prueba.papel.papeles.last, contains('Nota: faltó un billete de 500'));

    // El PDF: con el historial.
    await tocar(tester, porClave('cierre_pdf'));
    final pdf = prueba.pdfs.single;
    expect(pdf.nombre, startsWith('cierre_barra_PUERTO_VIEJO_caja2_'));
    expect(pdf.nombre, endsWith('.pdf'));
    expect(pdf.lineas.whereType<TextoTicket>().map((t) => t.texto), contains('HISTORIAL'));

    // LISTO: VENDER también se va, y la caja ya no se retoma.
    await tocar(tester, porClave('cierre_listo'));
    expect(find.byType(VenderScreen), findsNothing);
    expect(find.byType(BarraHomeScreen), findsOneWidget);
    await tocar(tester, porClave('barra_fiesta_${fiesta.id}'));
    expect(porClave('caja_abrir'), findsOneWidget, reason: 'pide abrir otra caja');
  });

  testWidgets('volver a contar no cierra nada', (tester) async {
    await abrir(tester);
    await irACerrar(tester);
    await tester.enterText(porClave('cierre_contado'), '27000');
    await tester.pumpAndSettle();
    await tocar(tester, porClave('cierre_cerrar'));
    await tocar(tester, find.text('VOLVER A CONTAR'));
    expect(guardada().abierta, isTrue);
    expect(prueba.papel.papeles, isEmpty);
    expect(prueba.subidasDeLaBarra, isEmpty);
  });

  testWidgets('justo: lo dice; y con el cambio puesto después de abrir, cuenta igual', (tester) async {
    await abrir(tester);
    await irACerrar(tester);
    await contarYCerrar(tester, '27000');
    expect(texto(tester, 'cierre_diferencia'), 'Justo, sin diferencia');
    expect(guardada().diferencia, 0);
  });

  testWidgets('sin impresora la caja igual se cierra, y lo dice', (tester) async {
    prueba.papel.anda = false;
    await abrir(tester);
    await irACerrar(tester);
    await contarYCerrar(tester, '27500');
    expect(guardada().abierta, isFalse);
    expect(guardada().diferencia, 500);
    expect(texto(tester, 'cierre_aviso'), contains('Caja cerrada. No salió el papel.'));
    expect(texto(tester, 'cierre_diferencia'), r'Sobran $ 500');
  });

  testWidgets('cerrada, volver atrás es como LISTO: vuelve al inicio', (tester) async {
    await abrir(tester);
    await irACerrar(tester);
    await contarYCerrar(tester, '27000');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(VenderScreen), findsNothing);
    expect(find.byType(BarraHomeScreen), findsOneWidget);
  });

  testWidgets('antes de cerrar, volver atrás vuelve a VENDER con la caja abierta', (tester) async {
    await abrir(tester);
    await irACerrar(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(VenderScreen), findsOneWidget);
    expect(guardada().abierta, isTrue);
  });

  for (final (nombre, tamano) in [
    ('un celular', const Size(360, 740)),
    ('una tablet parada', const Size(800, 1280)),
    ('una tablet acostada', const Size(1280, 800)),
  ]) {
    testWidgets('en $nombre no se desborda, contando y con el cierre', (tester) async {
      await abrir(tester, tamano: tamano);
      await irACerrar(tester);
      expect(tester.takeException(), isNull);
      await contarYCerrar(tester, '26500');
      expect(tester.takeException(), isNull);
      expect(porClave('cierre_papel'), findsOneWidget);
    });
  }

  test('las ventas de la prueba son de la caja', () {
    expect({cervezas.cajaBarraId, fernet.cajaBarraId, anulada.cajaBarraId}, {caja.id});
  });
}
