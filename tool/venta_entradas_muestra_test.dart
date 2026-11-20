// Muestras de la venta de entradas (6.9.0), sin base ni nube, para mirarlas:
//
//   flutter test tool/venta_entradas_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen, con el tema claro de la app:
//   • Entradas_1_precios.png: PRECIOS, en modo jefe;
//   • Entradas_2_inicio.png: el inicio de quien vende, con ENTREGAR y VENDER;
//   • Entradas_3_abrir_caja.png: abrir la caja, con su cambio;
//   • Entradas_4_vender.png y Entradas_5_vender_celular.png: VENDER, con una
//     familia que ya pagó su mesa adicional;
//   • Entradas_6_cobro.png: la hoja del cobro (la de la barra), en mixto;
//   • Entradas_7_guardada.png: la venta guardada;
//   • Entradas_8_ventas_jefe.png, Entradas_9_ventas_vendedor.png y
//     Entradas_10_ventas_celular.png: VENTAS, con dos cajas, una venta
//     verificada, un número repetido y una anulada;
//   • Entradas_11_anular.png: el cartel de anular;
//   • Comprobante_0001.pdf y Comprobante_anulado.pdf: el comprobante;
//   • Historial_de_ventas.pdf: IMPRIMIR HISTORIAL, con las letras de la app;
//   • historial_1000/: el historial de una fiesta inventada con 1.000 entradas
//     (el del jefe y el de la caja de Carla, sin sumas) y las hojas 11 a 20 de
//     uno de 2.200, impresas por tandas;
//   • Entradas_12 a 15: CERRAR CAJA (contar a ciegas, confirmar, el cierre, y en
//     el celular) y Cierre_de_caja_entradas.pdf, su papel;
//   • Entradas_16 y 17: ENTRADAS en el cierre de caja (en la PC y en el celular);
//   • Entradas_18 y 19: la entrega con lo vendido a la vista, y VENDERLE ESAS
//     ENTRADAS en el cartel de una familia que debe.
//
// Los nombres y el precio de $ 10.000 son inventados.

// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/entradas/cuentas/historial_de_entradas.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart'
    show eventosDeLaBarraProvider;
import 'package:arguello_events/features/cierre_caja/widgets/sector_entradas.dart';
import 'package:arguello_events/features/entradas/pdf/cierre_caja_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';
import 'package:arguello_events/features/entradas/pdf/historial_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/widgets/imprimir_por_hojas.dart';
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

  /// Los papeles del cierre que se abrieron (CERRAR CAJA los abre solos).
  final cierres = <DatosDelCierreDeEntradas>[];

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
    List<Override> extra = const [],
    Future<void> Function(EntradasEnMemoria)? antes,
    bool asentar = true,
  }) async {
    await letras();
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final e = EntregaEnMemoria();
    final entradas = EntradasEnMemoria()
      ..conPrecio(idFiestaEntrega, anticipada: 8000, hasta: '2026-11-28');
    final comprobantes = <DatosDelComprobante>[];
    cierres.clear();
    final c = ProviderContainer(overrides: [
      ...e.reemplazos(jefe: jefe),
      ...entradas.reemplazos,
      // El 30-nov la anticipada ya no rige: se ve el precio de siempre.
      hoyEnArgentinaProvider.overrideWithValue(() => DateTime.utc(2026, 11, 30, 12)),
      abrirComprobanteDeEntradasProvider.overrideWithValue(
        (datos, {context}) async => comprobantes.add(datos),
      ),
      fiestasQueVienenProvider.overrideWith((ref) async => [fiestaDeLaEntrega]),
      abrirCierreDeEntradasProvider.overrideWithValue(
        (datos, {context}) async => cierres.add(datos),
      ),
      ...extra,
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
    if (antes != null) await antes(entradas);
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
    if (asentar) {
      await tester.pumpAndSettle();
    } else {
      // La entrega relee cada 15 s: sin pumpAndSettle.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
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

  /// PÉREZ, JUAN: paga su mesa adicional en la caja de cuotas (desde el
  /// 20-nov-2026 lo de A PAGAR se vende solo si está pago entero) y se lleva
  /// sus 8 de lugar.
  Future<void> armarUnaVenta(WidgetTester tester, EntregaEnMemoria e) async {
    e.cobrar(EntregaEnMemoria.idPerez, 70000);
    await tester.pumpAndSettle();
    await poner(tester, 'vender_buscar', 'perez');
    await tester.tap(find.byKey(const Key('vender_familia_${EntregaEnMemoria.idPerez}')));
    await tester.pump();
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
      final (clave, e, _, _) = await montar(
        tester,
        tamano: tamano,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      await armarUnaVenta(tester, e);
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

  // IMPRIMIR HISTORIAL con muchas hojas (la forma C, 15-nov): el cartel Todo
  // junto · Por hojas, de la pantalla de verdad.
  for (final (nombre, tamano, tocarTanda) in [
    ('Entradas_20_imprimir_por_hojas.png', const Size(1100, 1000), false),
    ('Entradas_21_imprimir_tanda_impresa.png', const Size(1100, 1000), true),
    ('Entradas_22_imprimir_por_hojas_celular.png', const Size(390, 900), false),
  ]) {
    testWidgets('IMPRIMIR HISTORIAL · $nombre', (tester) async {
      final (clave, _, entradas, _) = await montar(
        tester,
        jefe: true,
        tamano: tamano,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
        extra: [
          abrirHistorialDeEntradasProvider.overrideWithValue((datos, {context}) async {}),
        ],
      );
      await tester.runAsync(() async {
        final caja = entradas.listaCajas.single;
        for (var i = 0; i < 600; i++) {
          await entradas.vender(
            caja: caja,
            compradorNombre: 'COMPRADOR DE PRUEBA ${i + 1}',
            renglones: [
              RenglonEntradas.suelta(
                  nombre: PedidoDeEntradas.nombreSuelta, precioLista: 10000, cantidad: 1),
            ],
            medio: MedioBarra.efectivo,
            efectivo: 10000,
            numeros: '${5001 + i}',
            quien: 'Carla',
          );
        }
      });
      await tocar(tester, 'vender_ventas');
      await tester.pumpAndSettle();
      await tocar(tester, 'ventas_imprimir');
      await tester.pumpAndSettle();
      if (tocarTanda) {
        await tocar(tester, 'hojas_tanda_1');
        await tester.pumpAndSettle();
        await tocar(tester, 'ventas_imprimir');
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('hojas_cartel')), findsOneWidget);
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

  // ── El historial con muchas ventas (la forma C, 15-nov) ────────────────────

  /// Una fiesta inventada con unas [hasta] entradas vendidas en dos cajas, a lo
  /// largo de varios días (de 9 a 19 hs): lugares al 50 % con su familia,
  /// anticipadas, mixtos, transferencias con recargo, descuentos a mano,
  /// talonarios partidos, nombres largos, algunas anuladas y un número
  /// repetido. Los nombres son inventados.
  Future<(EntradasEnMemoria, Map<String, String>, CajaEntradas)> unaFiestaGrande(
    int hasta,
  ) async {
    const apellidos = [
      'ACOSTA', 'BENITEZ', 'CABRERA', 'DOMINGUEZ', 'ESCOBAR', 'FERREYRA', 'GIMENEZ',
      'HERRERA', 'IBARRA', 'JUAREZ', 'LEDESMA', 'MOLINA', 'NAVARRO', 'OJEDA', 'PAEZ',
      'QUIROGA', 'RAMIREZ', 'SOSA', 'TOLEDO', 'VERA', 'ZARATE', 'AGUIRRE', 'BRITEZ',
      'CACERES', 'DIAZ', 'FRANCO', 'GODOY', 'LUNA', 'MEDINA', 'ORTIZ', 'PERALTA', 'ROMERO',
    ];
    const nombres = [
      'ANA', 'LUIS', 'MARTA', 'JUAN', 'SOFIA', 'DIEGO', 'LAURA', 'PABLO', 'CARLA',
      'JORGE', 'NATALIA', 'RAMON', 'VALERIA', 'HUGO', 'GABRIELA', 'OSCAR', 'ROMINA',
    ];
    String persona(int i) =>
        '${apellidos[(i * 7) % apellidos.length]}, ${nombres[(i * 5) % nombres.length]}';
    String largo(int i) =>
        '${apellidos[i % apellidos.length]} ${apellidos[(i + 9) % apellidos.length]} '
        'DE LA FUENTE, MARIA DE LOS ANGELES';
    RenglonEntradas anticipadas(int n) => RenglonEntradas.suelta(
        nombre: PedidoDeEntradas.nombreAnticipada, precioLista: 8000, cantidad: n);
    RenglonEntradas lugar(int n) => RenglonEntradas.lugar(
        nombre: PedidoDeEntradas.nombreDeLugar(50),
        precioLista: 10000,
        descuentoPct: 50,
        cantidad: n);
    RenglonEntradas sueltas(int n, {double descuento = 0}) => RenglonEntradas.suelta(
        nombre: PedidoDeEntradas.nombreSuelta,
        precioLista: 10000,
        descuentoPct: descuento,
        cantidad: n);

    // El 17-nov a las 9 de Argentina.
    final entradas = EntradasEnMemoria(ahora: DateTime.utc(2026, 11, 17, 12));
    final carla = await entradas.abrirCaja(
      eventoId: idFiestaEntrega,
      operadorId: 'carla',
      operadorNombre: 'Carla',
    );
    final maxi = await entradas.abrirCaja(
      eventoId: idFiestaEntrega,
      operadorId: 'maxi',
      operadorNombre: 'Maxi',
    );
    final familias = <String, String>{};
    var hechas = 0;
    var talonario = 3001;
    var otroTalonario = 9001;
    String? paraRepetir;
    for (var i = 0; hechas < hasta; i++) {
      final ahora = entradas.reloj();
      final ar = ahora.subtract(const Duration(hours: 3));
      if (ar.hour >= 19) {
        // Al otro día, a las 9.
        entradas.adelantar(
          DateTime.utc(ar.year, ar.month, ar.day + 1, 12).difference(ahora),
        );
      }
      final renglones = switch (i % 5) {
        0 => [lugar(2 + i % 7)],
        1 => [anticipadas(2)],
        2 => [anticipadas(1), lugar(2)],
        3 => [sueltas(4, descuento: i % 23 == 3 ? 20 : 0)],
        _ => [anticipadas(3)],
      };
      final conLugar = renglones.any((r) => r.tipo == TipoRenglonEntradas.lugar);
      String? familia;
      if (conLugar || i % 4 == 0) {
        familia = 'fam$i';
        final mesa = 10 + i % 90;
        familias[familia] = '${persona(i + 3)} m.$mesa${i % 6 == 0 ? '-${mesa + 1}' : ''}';
      }
      final total = renglones.fold<double>(0, (s, r) => s + r.subtotal);
      final cuantas = renglones.fold<int>(0, (s, r) => s + r.cantidad);
      var medio = MedioBarra.efectivo;
      var efectivo = total;
      var transferencia = 0.0;
      var recargo = 0.0;
      double? recargoPct;
      if (i % 7 == 0) {
        medio = MedioBarra.mixto;
        efectivo = (total / 2).roundToDouble();
        transferencia = total - efectivo;
      } else if (i % 7 == 3) {
        medio = MedioBarra.transferencia;
        efectivo = 0;
        if (i % 14 == 3) {
          recargoPct = 10;
          recargo = (total * 0.1).roundToDouble();
        }
        transferencia = total + recargo;
      }
      String numeros;
      if (i == 150 && paraRepetir != null) {
        numeros = paraRepetir;
      } else if (i % 19 == 0 && cuantas > 1) {
        final mitad = cuantas ~/ 2;
        numeros = '$talonario-${talonario + mitad - 1}, '
            '$otroTalonario-${otroTalonario + cuantas - mitad - 1}';
        talonario += mitad;
        otroTalonario += cuantas - mitad;
      } else {
        numeros = cuantas == 1 ? '$talonario' : '$talonario-${talonario + cuantas - 1}';
        talonario += cuantas;
      }
      if (i == 40) paraRepetir = numeros;
      final caja = (i ~/ 25).isEven ? carla : maxi;
      final v = await entradas.vender(
        caja: caja,
        contratoAlumnoId: familia,
        compradorNombre: i % 17 == 0 ? largo(i) : persona(i),
        renglones: renglones,
        medio: medio,
        efectivo: efectivo,
        transferencia: transferencia,
        recargo: recargo,
        recargoPct: recargoPct,
        // Alguna sin el número del talonario (no es obligatorio).
        numeros: i % 37 == 11 ? null : numeros,
        quien: caja == carla ? 'Carla' : 'Maxi',
      );
      hechas += cuantas;
      if (i % 41 == 7) {
        await entradas.anular(
          v,
          motivo: i.isEven
              ? 'se cargó dos veces'
              : 'la familia pidió la devolución, pagó con otra transferencia',
          devueltas: i % 3 != 0,
          quien: 'Jefe',
        );
        hechas -= cuantas;
      } else if (medio != MedioBarra.efectivo && i % 3 != 0) {
        await entradas.verificar(v, verificado: true, quien: 'Jefe');
      }
      entradas.adelantar(Duration(minutes: 2 + (i * 3) % 9));
    }
    return (entradas, familias, carla);
  }

  HistorialDeEntradas historialDe(EntradasEnMemoria e, {String? caja}) => HistorialDeEntradas.de(
        cajas: e.listaCajas,
        ventas: e.listaVentas,
        anulaciones: e.listaAnulaciones,
        verificaciones: e.listaVerificaciones,
        soloDeLaCaja: caja,
      );

  testWidgets('el historial de 1.000 entradas, y uno largo impreso por hojas', (tester) async {
    await letras();
    await tester.runAsync(() async {
      final fuentes = await PdfService.fuentesOutfit();
      final logo = await isotipoDeLosPapeles();
      final dir = Directory('$carpeta${Platform.pathSeparator}historial_1000')
        ..createSync(recursive: true);
      Future<void> escribir(String nombre, DatosDelHistorial d) async {
        final bytes = await HistorialEntradasPdf.armar(d, fuentes: fuentes, logo: logo);
        File('${dir.path}${Platform.pathSeparator}$nombre').writeAsBytesSync(bytes);
        print('── $nombre (${d.historial.totales.entradas} entradas, '
            '${d.historial.ventas.length} ventas, ${HistorialEntradasPdf.hojas(d)} hojas en total)');
      }

      DatosDelHistorial datos(
        HistorialDeEntradas h,
        Map<String, String> familias, {
        String alcance = 'Todas las cajas',
        bool conPlata = true,
      }) =>
          DatosDelHistorial(
            historial: h,
            fiesta: 'PUERTO VIEJO',
            fechaFiesta: fiestaDeLaEntrega.fechaEvento,
            alcance: alcance,
            emitido: DateTime.utc(2026, 11, 30, 15),
            conPlata: conPlata,
            familias: familias,
          );

      final (mil, familias, carla) = await unaFiestaGrande(1000);
      await escribir('1_Historial_1000_entradas_el_jefe.pdf', datos(historialDe(mil), familias));
      await escribir(
        '2_Historial_la_caja_de_Carla_sin_sumas.pdf',
        datos(
          historialDe(mil, caja: carla.id),
          familias,
          alcance: 'La caja de Carla',
          conPlata: false,
        ),
      );

      final (grande, familiasGrande, _) = await unaFiestaGrande(2200);
      final todo = datos(historialDe(grande), familiasGrande);
      final total = HistorialEntradasPdf.hojas(todo);
      expect(total, greaterThan(kHojasParaPreguntar));
      final hasta = total < 20 ? total : 20;
      await escribir(
        '3_Historial_2200_entradas_hojas_11_a_$hasta.pdf',
        todo.soloLasHojas(11, hasta),
      );
      print('── PDF en: ${dir.path}');
    });
  });

  testWidgets('cerrar la caja: contar a ciegas, confirmar y el cierre', (tester) async {
    final (clave, _, entradas, _) = await montar(
      tester,
      tamano: const Size(1100, 900),
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await unaNocheDeVentas(tester, entradas);
    await tocar(tester, 'vender_cerrar');
    await tester.pumpAndSettle();
    await poner(tester, 'cierre_contado', '64500');
    await poner(tester, 'cierre_nota', 'un billete roto');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await guardar(tester, clave, 'Entradas_12_cerrar_contar.png');
    await tocar(tester, 'cierre_cerrar');
    await tester.pumpAndSettle();
    await guardar(tester, clave, 'Entradas_13_cerrar_confirmar.png');
    await tocar(tester, 'cierre_confirmar');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'nada se desborda');
    await guardar(tester, clave, 'Entradas_14_cerrada.png');

    // El papel del cierre, con las letras de la app.
    final datos = cierres.single;
    await tester.runAsync(() async {
      final bytes = await CierreCajaEntradasPdf.armar(
        datos,
        fuentes: await PdfService.fuentesOutfit(),
        logo: await isotipoDeLosPapeles(),
      );
      File('$carpeta${Platform.pathSeparator}Cierre_de_caja_entradas.pdf')
          .writeAsBytesSync(bytes);
      print('── PDF en: $carpeta');
    });
  });

  testWidgets('cerrar la caja en el celular', (tester) async {
    final (clave, _, entradas, _) = await montar(
      tester,
      tamano: const Size(390, 1100),
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await unaNocheDeVentas(tester, entradas);
    await tocar(tester, 'vender_cerrar');
    await tester.pumpAndSettle();
    await poner(tester, 'cierre_contado', '65000');
    await tocar(tester, 'cierre_cerrar');
    await tester.pumpAndSettle();
    await tocar(tester, 'cierre_confirmar');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'nada se desborda');
    await guardar(tester, clave, 'Entradas_15_cerrada_celular.png');
  });

  for (final (nombre, tamano) in [
    ('Entradas_16_cierre_por_sector.png', const Size(1100, 640)),
    ('Entradas_17_cierre_por_sector_celular.png', const Size(390, 900)),
  ]) {
    testWidgets('ENTRADAS en el cierre de caja · $nombre', (tester) async {
      final (clave, _, _, _) = await montar(
        tester,
        jefe: true,
        tamano: tamano,
        extra: [
          eventosDeLaBarraProvider.overrideWith((ref) async => [fiestaDeLaEntrega]),
          relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 11, 30, 12)),
        ],
        antes: (entradas) async {
          await unaNocheDeVentas(tester, entradas);
          await tester.runAsync(() async {
            final maxi =
                entradas.listaCajas.firstWhere((c) => c.operadorNombre == 'Maxi');
            await entradas.cerrarCaja(maxi,
                efectivoContado: 12500, diferencia: -500, quien: 'Maxi');
          });
        },
        pantalla: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: SectorEntradasDelCierre(isDark: false),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, nombre);
    });
  }

  testWidgets('la entrega con lo vendido a la vista', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      jefe: true,
      asentar: false,
      tamano: const Size(1300, 950),
      // PÉREZ, JUAN compró 3 de sus 8 al 50 %: le quedan 5.
      antes: (entradas) => tester.runAsync(() async {
        await entradas.vender(
          caja: entradas.listaCajas.single,
          contratoAlumnoId: EntregaEnMemoria.idPerez,
          compradorNombre: 'PEREZ, MARTA',
          renglones: [
            RenglonEntradas.lugar(
              nombre: PedidoDeEntradas.nombreDeLugar(50),
              precioLista: 10000,
              descuentoPct: 50,
              cantidad: 3,
            ),
          ],
          medio: MedioBarra.efectivo,
          efectivo: 15000,
          quien: 'Carla',
        );
      }),
      pantalla: RetiroEntradasScreen(
        evento: fiestaDeLaEntrega,
        onCobrar: (_) async {},
        onEditarAlumno: (_) async {},
      ),
    );
    await guardar(tester, clave, 'Entradas_18_entrega.png');
    await tester.tap(find.text('PÉREZ, JUAN').first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await guardar(tester, clave, 'Entradas_19_entrega_venderle.png');
  });

  testWidgets('el cobro, la venta guardada y el comprobante', (tester) async {
    final (clave, e, entradas, comprobantes) = await montar(
      tester,
      tamano: const Size(1100, 1000),
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await armarUnaVenta(tester, e);
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
