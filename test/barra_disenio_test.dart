import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/estilos/disenio_barra.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// Los dos diseños de VENDER (Noche dorada y Mostrador, elegidos por el usuario con las
/// maquetas del 3-nov): que ninguno se desborde, que cada equipo recuerde el suyo, que
/// se elija desde el ícono, y la foto o la inicial de cada producto.
const _marta = 'a0000000-0000-4000-8000-000000000001';

/// Un PNG de 1×1: una foto que se puede pintar sin leer archivos.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, //
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, //
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

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
    b.precio(fiesta.id, agua, 1000, orden: 2, stock: 1, aviso: 1);
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

  Finder producto(ProductoBarra p) => find.byKey(Key('producto_${p.id}'));
  String total(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('vender_total'))).data!;
  DisenioBarra disenioEnPantalla(WidgetTester tester) =>
      TemaBarra.of(tester.element(producto(cerveza))).disenio;

  group('en cada tamaño y con cada diseño', () {
    for (final d in DisenioBarra.values) {
      for (final (nombre, tamano) in [
        ('un celular', const Size(360, 740)),
        ('un celular acostado', const Size(740, 360)),
        ('una tablet parada', const Size(800, 1280)),
        ('una tablet acostada o una PC', const Size(1280, 800)),
      ]) {
        testWidgets('${d.nombre}, en $nombre: no se desborda y los tres pagos se ven', (tester) async {
          prueba.disenio.disenio = d;
          await abrir(tester, tamano: tamano);
          expect(disenioEnPantalla(tester), d);
          await tocar(tester, producto(cerveza), veces: 2);
          await tocar(tester, producto(agua));
          expect(tester.takeException(), isNull);
          for (final m in ['efectivo', 'transferencia', 'mixto']) {
            expect(find.byKey(Key('pagar_$m')).hitTestable(), findsOneWidget, reason: m);
          }
          await tocar(tester, find.byKey(const Key('pagar_efectivo')));
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('cobro_confirmar')), findsOneWidget);
        });
      }
    }
  });

  group('cada equipo recuerda el suyo', () {
    testWidgets('sin nada recordado, Noche dorada', (tester) async {
      await abrir(tester);
      expect(disenioEnPantalla(tester), DisenioBarra.nocheDorada);
    });

    testWidgets('con Mostrador recordado, abre en Mostrador', (tester) async {
      prueba.disenio.disenio = DisenioBarra.mostrador;
      await abrir(tester);
      expect(disenioEnPantalla(tester), DisenioBarra.mostrador);
    });

    test('una clave que no se conoce va a Noche dorada', () {
      expect(DisenioBarra.deClave('neon'), DisenioBarra.nocheDorada);
      expect(DisenioBarra.deClave(null), DisenioBarra.nocheDorada);
      expect(DisenioBarra.deClave('mostrador'), DisenioBarra.mostrador);
    });

    test('se guarda y se lee en el equipo', () async {
      SharedPreferences.setMockInitialValues({});
      const r = DisenioRecordado();
      expect(await r.leer(), DisenioBarra.nocheDorada);
      await r.guardar(DisenioBarra.mostrador);
      expect(await r.leer(), DisenioBarra.mostrador);
    });
  });

  testWidgets('se elige desde el ícono, se guarda y la pantalla cambia sin perder la cuenta', (tester) async {
    await abrir(tester);
    await tocar(tester, producto(fernet));
    await tocar(tester, find.byKey(const Key('vender_disenio')));
    expect(find.byKey(const Key('elegir_disenio')), findsOneWidget);
    await tocar(tester, find.byKey(const Key('disenio_mostrador')));
    expect(prueba.disenio.disenio, DisenioBarra.mostrador);
    expect(prueba.disenio.guardados, 1);
    expect(disenioEnPantalla(tester), DisenioBarra.mostrador);
    expect(total(tester), r'$ 6.000', reason: 'cambiar el diseño no toca la cuenta');
  });

  group('la tarjeta', () {
    testWidgets('sin foto, la inicial; con foto, la foto', (tester) async {
      prueba.imagen = (p) => p.id == fernet.id ? MemoryImage(_png) : null;
      await abrir(tester);
      expect(find.byKey(Key('foto_${fernet.id}')), findsOneWidget);
      expect(find.descendant(of: producto(fernet), matching: find.byKey(const Key('inicial'))), findsNothing);
      expect(find.descendant(of: producto(cerveza), matching: find.byKey(const Key('inicial'))), findsOneWidget);
      expect(find.text('CL'), findsOneWidget, reason: 'Cerveza lata: C y L');
    });

    testWidgets('una foto que no se puede leer deja la inicial, sin romper nada', (tester) async {
      prueba.imagen = (_) => MemoryImage(Uint8List.fromList([1, 2, 3]));
      await abrir(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.descendant(of: producto(cerveza), matching: find.byKey(const Key('inicial'))), findsOneWidget);
    });

    testWidgets('agotada, se ve apagada; vendida igual, "Sin stock"', (tester) async {
      await abrir(tester);
      Opacity opacidad(ProductoBarra p) =>
          tester.widget<Opacity>(find.ancestor(of: producto(p), matching: find.byType(Opacity)).first);
      expect(opacidad(agua).opacity, 1);
      await tocar(tester, producto(agua));
      expect(tester.widget<Text>(find.byKey(Key('stock_${agua.id}'))).data, 'Sin stock');
      expect(opacidad(agua).opacity, 1, reason: 'está en la cuenta: no se apaga');
      await tocar(tester, find.byKey(const Key('vender_vaciar')));
      expect(opacidad(agua).opacity, 1);
    });

    testWidgets('Noche dorada: el − n + aparece solo con el producto en la cuenta', (tester) async {
      await abrir(tester);
      expect(find.byKey(Key('tarjeta_sumar_${cerveza.id}')), findsNothing);
      await tocar(tester, producto(cerveza));
      await tocar(tester, find.byKey(Key('tarjeta_sumar_${cerveza.id}')));
      expect(total(tester), r'$ 7.000');
    });

    testWidgets('Mostrador: el − n + está siempre, y el − no hace nada en cero', (tester) async {
      prueba.disenio.disenio = DisenioBarra.mostrador;
      await abrir(tester);
      expect(find.byKey(Key('tarjeta_sumar_${cerveza.id}')), findsOneWidget);
      await tocar(tester, find.byKey(Key('tarjeta_restar_${cerveza.id}')));
      expect(total(tester), r'$ 0');
      await tocar(tester, find.byKey(Key('tarjeta_sumar_${cerveza.id}')), veces: 2);
      expect(total(tester), r'$ 7.000');
      await tocar(tester, find.byKey(Key('tarjeta_restar_${cerveza.id}')));
      expect(total(tester), r'$ 3.500');
    });
  });

  group('los pagos', () {
    Offset centro(WidgetTester tester, String m) => tester.getCenter(find.byKey(Key('pagar_$m')));

    testWidgets('Mostrador en la tablet: tres barras, una debajo de otra', (tester) async {
      prueba.disenio.disenio = DisenioBarra.mostrador;
      await abrir(tester, tamano: const Size(1280, 800));
      final e = centro(tester, 'efectivo'), t = centro(tester, 'transferencia'), m = centro(tester, 'mixto');
      expect(e.dx, t.dx);
      expect(t.dx, m.dx);
      expect(e.dy < t.dy && t.dy < m.dy, isTrue);
      expect(find.text('Mercado Pago · QR'), findsOneWidget);
    });

    testWidgets('Mostrador en el celular: en fila', (tester) async {
      prueba.disenio.disenio = DisenioBarra.mostrador;
      await abrir(tester, tamano: const Size(360, 740));
      final e = centro(tester, 'efectivo'), m = centro(tester, 'mixto');
      expect(e.dy, m.dy);
      expect(e.dx < m.dx, isTrue);
    });

    testWidgets('Noche dorada en la tablet: en fila', (tester) async {
      await abrir(tester, tamano: const Size(1280, 800));
      expect(centro(tester, 'efectivo').dy, centro(tester, 'mixto').dy);
    });
  });
}
