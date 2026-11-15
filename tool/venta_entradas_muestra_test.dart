// Muestras de la venta de entradas (6.9.0), sin base ni nube, para mirarlas:
//
//   flutter test tool/venta_entradas_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen, con el tema claro de la app:
//   • Entradas_1_precios.png: PRECIOS, en modo jefe;
//   • Entradas_2_inicio.png: el inicio de quien vende, con ENTREGAR y VENDER;
//   • Entradas_3_abrir_caja.png: abrir la caja, con su cambio;
//   • Entradas_4_vender.png y Entradas_5_vender_celular.png: VENDER, con una
//     familia que debe;
//   • Entradas_6_cobro.png: la hoja del cobro (la de la barra), en mixto;
//   • Entradas_7_guardada.png: la venta guardada;
//   • Entradas_8_ventas_jefe.png, Entradas_9_ventas_vendedor.png y
//     Entradas_10_ventas_celular.png: VENTAS, con dos cajas, una venta
//     verificada, un número repetido y una anulada;
//   • Entradas_11_anular.png: el cartel de anular;
//   • Comprobante_0001.pdf y Comprobante_anulado.pdf: el comprobante;
//   • Historial_de_ventas.pdf: IMPRIMIR HISTORIAL, con las letras de la app.
//
// Los nombres y el precio de $ 10.000 son inventados.

// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/entradas/cuentas/historial_de_entradas.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/historial_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/widgets/precios_de_entradas_dialog.dart';
import 'package:arguello_events/features/entradas/widgets/vender_entradas_screen.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

import '../test/helpers/entradas_en_memoria.dart';
import '../test/helpers/entrega_en_memoria.dart';
import '../test/helpers/tema_de_la_app.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('venta_entradas_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  Future<void> letras() async {
    SharedPreferences.setMockInitialValues({});
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  }

  Future<void> guardar(WidgetTester tester, GlobalKey clave, String nombre) async {
    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 1);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final archivo = File('$carpeta${Platform.pathSeparator}$nombre')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${archivo.path}');
    });
  }

  /// Monta [pantalla] con el tema de la app, la entrega y la venta en memoria,
  /// y Carla adentro con "Vende entradas" (o el jefe).
  Future<(GlobalKey, EntregaEnMemoria, EntradasEnMemoria, List<DatosDelComprobante>)>
      montar(
    WidgetTester tester, {
    required Widget pantalla,
    required Size tamano,
    bool jefe = false,
    bool conCaja = true,
  }) async {
    await letras();
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final e = EntregaEnMemoria();
    final entradas = EntradasEnMemoria()
      ..conPrecio(idFiestaEntrega, anticipada: 8000, hasta: '2026-11-28');
    final comprobantes = <DatosDelComprobante>[];
    final c = ProviderContainer(overrides: [
      ...e.reemplazos(jefe: jefe),
      ...entradas.reemplazos,
      // El 30-nov la anticipada ya no rige: se ve el precio de siempre.
      hoyEnArgentinaProvider.overrideWithValue(() => DateTime.utc(2026, 11, 30, 12)),
      abrirComprobanteDeEntradasProvider.overrideWithValue(
        (datos, {context}) async => comprobantes.add(datos),
      ),
      fiestasQueVienenProvider.overrideWith((ref) async => [fiestaDeLaEntrega]),
    ]);
    addTearDown(c.dispose);
    final carla = e.operador();
    await c.read(appRoleProvider.notifier).entrarComoEntradas(
          carla,
          const PermisosEfectivos(entradas: true, vendeEntradas: true),
        );
    if (conCaja) {
      await entradas.abrirCaja(
        eventoId: idFiestaEntrega,
        operadorId: jefe ? null : carla.id,
        operadorNombre: 'Carla',
        cambioInicial: 5000,
      );
    }
    final clave = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaroDeLaApp(),
          home: pantalla,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (clave, e, entradas, comprobantes);
  }

  Future<void> poner(WidgetTester tester, String clave, String texto) async {
    await tester.enterText(find.byKey(Key(clave)), texto);
    await tester.pump();
  }

  Future<void> tocar(WidgetTester tester, String clave, {int veces = 1}) async {
    for (var i = 0; i < veces; i++) {
      await tester.tap(find.byKey(Key(clave)));
      await tester.pump();
    }
  }

  /// PÉREZ, JUAN (debe su mesa adicional): sus 8 de lugar y 2 sueltas.
  Future<void> armarUnaVenta(WidgetTester tester) async {
    await poner(tester, 'vender_buscar', 'perez');
    await tester.tap(find.byKey(const Key('vender_familia_${EntregaEnMemoria.idPerez}')));
    await tester.pump();
    await tocar(tester, 'vender_sueltas_mas', veces: 2);
    await poner(tester, 'vender_comprador', 'PEREZ, MARTA');
    await poner(tester, 'vender_dni', '30111222');
    await poner(tester, 'vender_del', '2000');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  testWidgets('PRECIOS', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      jefe: true,
      tamano: const Size(900, 900),
      pantalla: const Scaffold(
        body: PreciosDeEntradasDialog(
          eventoId: idFiestaEntrega,
          fiesta: 'PUERTO VIEJO',
          quien: 'Jefe',
        ),
      ),
    );
    await guardar(tester, clave, 'Entradas_1_precios.png');
  });

  testWidgets('el inicio de quien vende', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      tamano: const Size(1000, 420),
      pantalla: const EntradasHomeScreen(),
    );
    await guardar(tester, clave, 'Entradas_2_inicio.png');
  });

  testWidgets('abrir la caja', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      conCaja: false,
      tamano: const Size(900, 700),
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await poner(tester, 'abrir_caja_cambio', '5000');
    await guardar(tester, clave, 'Entradas_3_abrir_caja.png');
  });

  for (final (nombre, tamano) in [
    ('Entradas_4_vender.png', const Size(1100, 1000)),
    ('Entradas_5_vender_celular.png', const Size(390, 1250)),
  ]) {
    testWidgets('VENDER · $nombre', (tester) async {
      final (clave, _, _, _) = await montar(
        tester,
        tamano: tamano,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      await armarUnaVenta(tester);
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, nombre);
    });
  }

  /// Una noche con dos cajas: la de Carla (la que abrió [montar]) y la de Maxi.
  /// Una venta con el pago verificado, una mixta con un número que quedó en dos
  /// ventas, y una anulada.
  Future<void> unaNocheDeVentas(WidgetTester tester, EntradasEnMemoria entradas) async {
    await tester.runAsync(() async {
      final carla = entradas.listaCajas.single;
      final maxi = await entradas.abrirCaja(
        eventoId: idFiestaEntrega,
        operadorId: 'maxi',
        operadorNombre: 'Maxi',
        cambioInicial: 3000,
      );
      final perez = await entradas.vender(
        caja: carla,
        contratoAlumnoId: EntregaEnMemoria.idPerez,
        compradorNombre: 'PEREZ, MARTA',
        compradorDni: '30111222',
        renglones: [
          RenglonEntradas.lugar(
            nombre: PedidoDeEntradas.nombreDeLugar(50),
            precioLista: 10000,
            descuentoPct: 50,
            cantidad: 8,
          ),
          RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 2),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 60000,
        numeros: '2000-2009',
        quien: 'Carla',
      );
      await entradas.vender(
        caja: carla,
        compradorNombre: 'GOMEZ, LUIS',
        renglones: [
          RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 2),
        ],
        medio: MedioBarra.transferencia,
        transferencia: 20000,
        numeros: '2010-2011',
        quien: 'Carla',
      );
      await entradas.vender(
        caja: maxi,
        compradorNombre: 'RUIZ, ANA',
        renglones: [
          RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 3),
        ],
        medio: MedioBarra.mixto,
        efectivo: 10000,
        transferencia: 20000,
        numeros: '2011-2013',
        quien: 'Maxi',
      );
      final sosa = await entradas.vender(
        caja: maxi,
        compradorNombre: 'SOSA, DIEGO',
        renglones: [
          RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 1),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 10000,
        numeros: '2014',
        quien: 'Maxi',
      );
      await entradas.verificar(perez, verificado: true, quien: 'Jefe');
      await entradas.anular(sosa,
          motivo: 'se cargó dos veces', devueltas: true, quien: 'Jefe');
    });
  }

  for (final (nombre, tamano, jefe) in [
    ('Entradas_8_ventas_jefe.png', const Size(1100, 1000), true),
    ('Entradas_9_ventas_vendedor.png', const Size(1100, 800), false),
    ('Entradas_10_ventas_celular.png', const Size(390, 1250), true),
  ]) {
    testWidgets('VENTAS · $nombre', (tester) async {
      final (clave, _, entradas, _) = await montar(
        tester,
        jefe: jefe,
        tamano: tamano,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      await unaNocheDeVentas(tester, entradas);
      await tocar(tester, 'vender_ventas');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, nombre);
    });
  }

  testWidgets('el cartel de anular', (tester) async {
    final (clave, _, entradas, _) = await montar(
      tester,
      jefe: true,
      tamano: const Size(1100, 1000),
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await unaNocheDeVentas(tester, entradas);
    await tocar(tester, 'vender_ventas');
    await tester.pumpAndSettle();
    final gomez = entradas.listaVentas.firstWhere((v) => v.compradorNombre == 'GOMEZ, LUIS');
    await tester.tap(find.byKey(Key('anular_${gomez.id}')));
    await tester.pumpAndSettle();
    await poner(tester, 'anular_motivo', 'pagó con otra transferencia');
    await tester.tap(find.byKey(const Key('anular_devolvieron_no')));
    await tester.pumpAndSettle();
    await guardar(tester, clave, 'Entradas_11_anular.png');
  });

  testWidgets('el historial impreso', (tester) async {
    final (_, _, entradas, _) = await montar(
      tester,
      jefe: true,
      tamano: const Size(900, 600),
      pantalla: const SizedBox(),
    );
    await unaNocheDeVentas(tester, entradas);
    await tester.runAsync(() async {
      final h = HistorialDeEntradas.de(
        cajas: await entradas.cajas(idFiestaEntrega),
        ventas: await entradas.ventas(idFiestaEntrega),
        anulaciones: await entradas.anulaciones(idFiestaEntrega),
        verificaciones: await entradas.verificaciones(idFiestaEntrega),
      );
      final bytes = await HistorialEntradasPdf.armar(
        DatosDelHistorial(
          historial: h,
          fiesta: 'PUERTO VIEJO',
          fechaFiesta: fiestaDeLaEntrega.fechaEvento,
          alcance: 'Todas las cajas',
          emitido: DateTime.utc(2026, 11, 30, 15),
        ),
        fuentes: await PdfService.fuentesOutfit(),
        logo: await isotipoDeLosPapeles(),
      );
      File('$carpeta${Platform.pathSeparator}Historial_de_ventas.pdf')
          .writeAsBytesSync(bytes);
      print('── PDF en: $carpeta');
    });
  });

  testWidgets('el cobro, la venta guardada y el comprobante', (tester) async {
    final (clave, _, entradas, comprobantes) = await montar(
      tester,
      tamano: const Size(1100, 1000),
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await armarUnaVenta(tester);
    await tocar(tester, 'vender_mixto');
    await tester.pumpAndSettle();
    await poner(tester, 'cobro_mixto_efectivo', '20000');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await guardar(tester, clave, 'Entradas_6_cobro.png');

    await tester.tap(find.byKey(const Key('cobro_confirmar')));
    await tester.pumpAndSettle();
    await guardar(tester, clave, 'Entradas_7_guardada.png');

    // El comprobante de esa venta, con las letras de la app.
    final datos = comprobantes.single;
    await tester.runAsync(() async {
      final fuentes = await PdfService.fuentesOutfit();
      final logo = await isotipoDeLosPapeles();
      final bytes =
          await ComprobanteEntradasPdf.armar(datos, fuentes: fuentes, logo: logo);
      File('$carpeta${Platform.pathSeparator}Comprobante_0001.pdf')
          .writeAsBytesSync(bytes);
      final anulacion = await entradas.anular(
        datos.venta,
        motivo: 'se equivocó de familia',
        devueltas: false,
        quien: 'Jefe',
      );
      final anulado = await ComprobanteEntradasPdf.armar(
        DatosDelComprobante(
          venta: datos.venta,
          fiesta: datos.fiesta,
          fechaFiesta: datos.fechaFiesta,
          alumno: datos.alumno,
          mesa: datos.mesa,
          copia: true,
          anulacion: anulacion,
        ),
        fuentes: fuentes,
        logo: logo,
      );
      File('$carpeta${Platform.pathSeparator}Comprobante_anulado.pdf')
          .writeAsBytesSync(anulado);
      print('── PDF en: $carpeta');
    });
  });
}
