// Muestras de la venta de entradas (6.9.0), sin base ni nube, para mirarlas:
//
//   flutter test tool/venta_entradas_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen, con el tema claro de la app:
//   • Entradas_1_precios.png: PRECIOS, en modo jefe;
//   • Entradas_2_inicio.png: el inicio de quien vende, con un solo botón, VENDER
//     (20-nov-2026);
//   • Entradas_3_abrir_caja.png: abrir la caja, con su cambio;
//   • Entradas_4_vender.png y Entradas_5_vender_celular.png: VENDER, con una
//     familia que ya pagó su mesa adicional (GRATIS y A PAGAR);
//   • Entradas_4a a 4k: VENDER desde el 20-nov-2026: la lista con el filtro (en
//     la PC, con "Todos" y en el celular), una familia que debe, entregar las
//     pulseras (en la PC y en el celular) y las pulseras entregadas, las sillas
//     con una a confirmar, alguien de afuera y VENDER sin caja;
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
//   • Entradas_18 y 19: la entrega con lo vendido a la vista, y el cartel de una
//     familia que debe su mesa adicional (desde el 20-nov-2026 lo de esa mesa
//     espera el pago: ya no ofrece VENDERLE ESAS ENTRADAS).
//
// Lo de la 6.9.3 (20-nov-2026), con la noche de la ventana de prueba
// (`sumarLaNoche`: una familia de cada caso) y el 20-nov, con la anticipada vigente:
//   • Entradas_2b: el inicio de quien vende, en el celular (un solo botón, VENDER);
//   • Entradas_30 a 30d: PRECIOS con ANTICIPADA vigente y con GENERAL, en la PC y
//     en el celular;
//   • Entradas_31 a 31e: la lista de VENDER con el filtro (puede retirar, debe, ya
//     retiró), en la PC y en el celular;
//   • Entradas_32_<caso>: la tarjeta de cada caso (pagó todo con mesa adicional,
//     debe una cuota con la adicional paga, debe solo mora, la adicional sin pagar,
//     la silla agregada después del sorteo, 3 acompañantes, uno sin nombre, sin
//     adicional, ya retiró), en la PC y en el celular (_celular);
//   • Entradas_33: los formularios de las dos partes (pulseras, y generales con
//     número), en la PC y en el celular;
//   • Entradas_34: las dos partes entregadas ("✓ Todo entregado");
//   • Entradas_35: "pagó todo: ya podés entregar", la familia que pagó en la caja;
//   • Entradas_36: la entrega del jefe con las partes de cada familia.
// La planilla por material es otra muestra: tool/planilla_entrega_muestra_test.dart.
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
import 'package:arguello_events/features/eventos/repositories/sorteos_mesas_repository.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

import '../test/helpers/entradas_en_memoria.dart';
import '../test/helpers/entrega_en_memoria.dart';
import '../test/helpers/tema_de_la_app.dart';
import 'venta_entradas_prueba.dart' show NocheDeLaVenta, sumarLaNoche;

const _salida = String.fromEnvironment('salida', defaultValue: '');

// Los alumnos que suma la muestra de VENDER a los tres de siempre.
const _conDos = 'a0000000-0000-4000-8000-000000000301';
const _conMesa = 'a0000000-0000-4000-8000-000000000302';
const _conSillas = 'a0000000-0000-4000-8000-000000000303';
const _conMora = 'a0000000-0000-4000-8000-000000000304';
const _conFicha = 'a0000000-0000-4000-8000-000000000305';

/// Un alumno más en la fiesta de la muestra, con la base de $300.000 pagada
/// ([pagado]), [extras] mesas adicionales de $70.000 pagadas y [sillas] sillas
/// de $8.000 ([sillasPagas] de ellas pagadas). La ficha dice lo que dan los
/// pagos, salvo [saldoFicha].
void alumnoDeMuestra(
  EntregaEnMemoria e, {
  required String id,
  required String nombre,
  required List<int> mesas,
  int extras = 0,
  int sillas = 0,
  int sillasPagas = 0,
  int acompanantes = 0,
  List<String> nombres = const [],
  double pagado = 300000,
  double? saldoFicha,
  double mora = 0,
}) {
  final total = 300000 + 70000.0 * extras + 8000.0 * sillas;
  final pagos = pagado + 70000.0 * extras + 8000.0 * sillasPagas;
  e.contratos.alumnos.add(ContratoAlumno(
    id: id,
    eventoId: idFiestaEntrega,
    nombreAlumno: nombre,
    cantidadAcompanantes: acompanantes,
    nombresAcompanantes: nombres,
    montoTotalPactado: total,
    saldoDeudor: saldoFicha ?? (total - pagos),
    totalCuotas: 9,
    cuotasPagadas: 9,
    mesaExtraPrecio: 70000.0 * extras,
    mesaExtraCantidad: extras,
    mesaExtraCuotas: 1,
    sillasExtraCantidad: sillas,
    sillasExtraPrecioTotal: 8000.0 * sillas,
    sillasExtraCuotas: 1,
    moraPendienteTracked: mora,
    numeroMesa: MesasExtraUtils.formatearAsignacionMesas(mesas),
    cursoDivision: '5° B',
    createdAt: DateTime(2026, 2, 1),
  ));
  if (pagado > 0) e.contratos.pagos.add(pagoDeLaEntrega(id, pagado, 'Cuota Base (9/9)'));
  if (extras > 0) e.contratos.pagos.add(pagoDeLaEntrega(id, 70000.0 * extras, 'Mesa Extra 1'));
  if (sillasPagas > 0) {
    e.contratos.pagos.add(pagoDeLaEntrega(id, 8000.0 * sillasPagas, 'Sillas extra (1/1)'));
  }
}

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
    void Function(EntregaEnMemoria)? preparar,
    bool asentar = true,
    DateTime? hoy,
    bool conAnticipada = true,
  }) async {
    await letras();
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final e = EntregaEnMemoria();
    preparar?.call(e);
    final entradas = EntradasEnMemoria();
    if (conAnticipada) {
      entradas.conPrecio(idFiestaEntrega, anticipada: 8000, hasta: '2026-11-28');
    } else {
      entradas.conPrecio(idFiestaEntrega);
    }
    final comprobantes = <DatosDelComprobante>[];
    cierres.clear();
    final c = ProviderContainer(overrides: [
      ...e.reemplazos(jefe: jefe),
      ...entradas.reemplazos,
      // Sin [hoy], el 30-nov: la anticipada ya no rige y se ve el precio de siempre.
      hoyEnArgentinaProvider
          .overrideWithValue(() => hoy ?? DateTime.utc(2026, 11, 30, 12)),
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

  // ── VENDER desde el 20-nov-2026: la lista, GRATIS en dos partes y A PAGAR ──

  /// Una fiesta con un poco de todo (nombres inventados): con acompañantes, con
  /// mesa adicional paga, con sillas (una agregada después del sorteo y sin
  /// pagar), que debe la mora, y con la ficha distinta de los pagos.
  void unaFiestaConDeTodo(EntregaEnMemoria e) {
    alumnoDeMuestra(e,
        id: _conDos,
        nombre: 'ACOSTA, LUCÍA',
        mesas: const [16],
        acompanantes: 2,
        nombres: const ['ACOSTA, MARTA', 'ACOSTA, RUBÉN']);
    alumnoDeMuestra(e,
        id: _conMesa,
        nombre: 'BENÍTEZ, TOMÁS',
        mesas: const [17, 18],
        extras: 1,
        acompanantes: 1,
        nombres: const ['BENÍTEZ, CLARA']);
    alumnoDeMuestra(e,
        id: _conSillas,
        nombre: 'CABRAL, JULIETA',
        mesas: const [19],
        sillas: 3,
        sillasPagas: 2,
        acompanantes: 2,
        nombres: const ['CABRAL, ANA']);
    alumnoDeMuestra(e, id: _conMora, nombre: 'DÍAZ, NICOLÁS', mesas: const [20], mora: 12500);
    alumnoDeMuestra(e,
        id: _conFicha, nombre: 'ESPÍNDOLA, ROCÍO', mesas: const [21], pagado: 0, saldoFicha: 0);
  }

  /// Al sorteo CABRAL tenía la mesa y 2 sillas (la tercera la agregó después), y
  /// BENÍTEZ ya tenía su mesa adicional.
  final fotoDeLaMuestra = FotoDeLosLugares.anotada({
    _conSillas: const LugaresCargados(1, 2),
    _conMesa: const LugaresCargados(2, 0),
  });

  Future<void> elegir(WidgetTester tester, String id, {String? filtro}) async {
    if (filtro != null) await tocar(tester, filtro);
    await tester.ensureVisible(find.byKey(Key('vender_familia_$id')));
    await tester.pump();
    await tester.tap(find.byKey(Key('vender_familia_$id')));
    await tester.pumpAndSettle();
  }

  for (final (nombre, tamano, filtro) in [
    ('Entradas_4a_vender_lista.png', const Size(1100, 900), null),
    ('Entradas_4b_vender_lista_todos.png', const Size(1100, 1100), 'vender_filtro_todos'),
    ('Entradas_4c_vender_lista_celular.png', const Size(390, 1250), 'vender_filtro_todos'),
  ]) {
    testWidgets('VENDER · $nombre', (tester) async {
      final (clave, _, _, _) = await montar(
        tester,
        tamano: tamano,
        preparar: unaFiestaConDeTodo,
        extra: [fotoDeLosLugaresProvider.overrideWithValue((_) async => fotoDeLaMuestra)],
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      if (filtro != null) await tocar(tester, filtro);
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, nombre);
    });
  }

  testWidgets('VENDER · una familia que debe', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      tamano: const Size(1100, 950),
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await elegir(tester, EntregaEnMemoria.idPerez, filtro: 'vender_filtro_debe');
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Entradas_4d_vender_debe.png');
  });

  for (final (nombre, tamano) in [
    ('Entradas_4e_vender_entregar_pulseras.png', const Size(1100, 1250)),
    ('Entradas_4f_vender_entregar_pulseras_celular.png', const Size(390, 1800)),
  ]) {
    testWidgets('VENDER · $nombre', (tester) async {
      final (clave, _, _, _) = await montar(
        tester,
        tamano: tamano,
        preparar: unaFiestaConDeTodo,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      await elegir(tester, _conDos);
      await tocar(tester, 'vender_entregar_pulseras');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, nombre);
    });
  }

  testWidgets('VENDER · las pulseras entregadas', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      tamano: const Size(1100, 950),
      preparar: unaFiestaConDeTodo,
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await elegir(tester, _conDos);
    await tocar(tester, 'vender_entregar_pulseras');
    await tester.pumpAndSettle();
    final formulario = find.byKey(const Key('vender_formulario_pulseras'));
    Finder adentro(Finder f) => find.descendant(of: formulario, matching: f);
    await tester.tap(adentro(find.text('Madre')));
    await tester.enterText(
      adentro(find.widgetWithText(TextField, 'Nombre y apellido de quien retira')),
      'Marta Acosta',
    );
    final planilla =
        adentro(find.text('Escribió su nombre y apellido en la planilla de papel'));
    await tester.ensureVisible(planilla);
    await tester.pump();
    await tester.tap(planilla);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('entrega_confirmar_pulseras')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('entrega_confirmar_pulseras')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('vender_linea_texto')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Entradas_4g_vender_pulseras_entregadas.png');
  });

  testWidgets('VENDER · las sillas, con una a confirmar', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      tamano: const Size(1100, 1200),
      preparar: unaFiestaConDeTodo,
      extra: [fotoDeLosLugaresProvider.overrideWithValue((_) async => fotoDeLaMuestra)],
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await elegir(tester, _conSillas, filtro: 'vender_filtro_debe');
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Entradas_4h_vender_sillas.png');
  });

  for (final (nombre, tamano) in [
    ('Entradas_4i_vender_afuera.png', const Size(1100, 800)),
    ('Entradas_4j_vender_afuera_celular.png', const Size(390, 1100)),
  ]) {
    testWidgets('VENDER · $nombre', (tester) async {
      final (clave, _, _, _) = await montar(
        tester,
        tamano: tamano,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      await tester.tap(find.text('Alguien de afuera'));
      await tester.pump();
      await tocar(tester, 'vender_sueltas_mas', veces: 2);
      await poner(tester, 'vender_comprador', 'RUIZ, MARTA');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await guardar(tester, clave, nombre);
    });
  }

  testWidgets('VENDER · sin caja: lo sin cargo se entrega igual', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      conCaja: false,
      tamano: const Size(1100, 950),
      pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
    );
    await tester.tap(find.byKey(const Key('abrir_caja_volver')));
    await tester.pumpAndSettle();
    await elegir(tester, EntregaEnMemoria.idLopez);
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Entradas_4k_vender_sin_caja.png');
  });

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

  // ── La 6.9.3 (20-nov-2026): VENDER con la entrega adentro ───────────────────

  /// El día de la noche de la ventana de prueba: la anticipada rige hasta el 28.
  final hoyDeLaNoche = DateTime.utc(2026, 11, 20, 12);

  /// Lo que cada familia de la noche tenía al sorteo, para la nota de PRECIOS.
  final fotoDeLaNoche = FotoDeLosLugares.anotada({
    EntregaEnMemoria.idPerez: const LugaresCargados(2, 0),
    NocheDeLaVenta.acosta: const LugaresCargados(2, 0),
    NocheDeLaVenta.benitez: const LugaresCargados(2, 0),
  }, sorteoEl: NocheDeLaVenta.sorteoEl);

  /// En la tarjeta: ENTREGAR de [parte], quién retira y la planilla, sin
  /// confirmar. [numero]: las generales vienen numeradas desde ese.
  Future<void> llenarParte(WidgetTester tester, ParteEntrega parte, {String? numero}) async {
    await tester.ensureVisible(find.byKey(Key('vender_entregar_${parte.clave}')));
    await tester.pumpAndSettle();
    await tocar(tester, 'vender_entregar_${parte.clave}');
    await tester.pumpAndSettle();
    final formulario = find.byKey(Key('vender_formulario_${parte.clave}'));
    Finder adentro(Finder f) => find.descendant(of: formulario, matching: f);
    if (numero != null) {
      await tester.ensureVisible(adentro(find.text('Vienen con número')));
      await tester.pumpAndSettle();
      await tester.tap(adentro(find.text('Vienen con número')));
      await tester.pumpAndSettle();
      await tester.enterText(adentro(find.widgetWithText(TextField, 'Del')), numero);
      await tester.pump();
    }
    await tester.ensureVisible(adentro(find.text('Madre')));
    await tester.pumpAndSettle();
    await tester.tap(adentro(find.text('Madre')));
    await tester.enterText(
      adentro(find.widgetWithText(TextField, 'Nombre y apellido de quien retira')),
      'Marta Acosta',
    );
    final planilla =
        adentro(find.text('Escribió su nombre y apellido en la planilla de papel'));
    await tester.ensureVisible(planilla);
    await tester.pumpAndSettle();
    await tester.tap(planilla);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> confirmarParte(WidgetTester tester, ParteEntrega parte) async {
    await tester.ensureVisible(find.byKey(Key('entrega_confirmar_${parte.clave}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('entrega_confirmar_${parte.clave}')));
    await tester.pumpAndSettle();
  }

  for (final (nombre, tamano, conAnticipada) in [
    ('Entradas_30_precios_anticipada.png', const Size(900, 1050), true),
    ('Entradas_30b_precios_anticipada_celular.png', const Size(390, 1500), true),
    ('Entradas_30c_precios_general.png', const Size(900, 950), false),
    ('Entradas_30d_precios_general_celular.png', const Size(390, 1300), false),
  ]) {
    testWidgets('PRECIOS · $nombre', (tester) async {
      final (clave, _, _, _) = await montar(
        tester,
        jefe: true,
        hoy: hoyDeLaNoche,
        conAnticipada: conAnticipada,
        tamano: tamano,
        preparar: sumarLaNoche,
        pantalla: Scaffold(
          body: PreciosDeEntradasDialog(
            eventoId: idFiestaEntrega,
            fiesta: 'PUERTO VIEJO',
            quien: 'Jefe',
            fechaFiesta: fiestaDeLaEntrega.fechaEvento,
            lugares: fotoDeLaNoche,
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, nombre);
    });
  }

  testWidgets('el inicio de quien vende, en el celular', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      hoy: hoyDeLaNoche,
      tamano: const Size(390, 480),
      pantalla: const EntradasHomeScreen(),
    );
    expect(find.text('ENTREGAR'), findsNothing);
    expect(find.text('VENDER'), findsOneWidget);
    await guardar(tester, clave, 'Entradas_2b_inicio_celular.png');
  });

  for (final (nombre, tamano, filtro) in [
    ('Entradas_31_lista_puede.png', const Size(1100, 950), null),
    ('Entradas_31b_lista_debe.png', const Size(1100, 850), 'vender_filtro_debe'),
    ('Entradas_31c_lista_ya_retiro.png', const Size(1100, 700), 'vender_filtro_ya'),
    ('Entradas_31d_lista_puede_celular.png', const Size(390, 1500), null),
    ('Entradas_31e_lista_debe_celular.png', const Size(390, 1250), 'vender_filtro_debe'),
  ]) {
    testWidgets('VENDER de la noche · $nombre', (tester) async {
      final (clave, _, _, _) = await montar(
        tester,
        hoy: hoyDeLaNoche,
        tamano: tamano,
        preparar: sumarLaNoche,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      if (filtro != null) await tocar(tester, filtro);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, nombre);
    });
  }

  for (final (caso, id, filtro) in [
    ('acosta_pago_todo', NocheDeLaVenta.acosta, null),
    ('benitez_debe_cuota', NocheDeLaVenta.benitez, 'vender_filtro_debe'),
    ('diaz_debe_mora', NocheDeLaVenta.diaz, 'vender_filtro_debe'),
    ('perez_adicional_sin_pagar', EntregaEnMemoria.idPerez, 'vender_filtro_debe'),
    ('ferreyra_silla_despues', NocheDeLaVenta.ferreyra, null),
    ('herrera_tres_acompanantes', NocheDeLaVenta.herrera, null),
    ('ibarra_uno_sin_nombre', NocheDeLaVenta.ibarra, null),
    ('lopez_sin_adicional', EntregaEnMemoria.idLopez, null),
    ('gomez_ya_retiro', EntregaEnMemoria.idGomez, 'vender_filtro_ya'),
  ]) {
    for (final (sufijo, tamano) in [
      ('', const Size(1100, 1350)),
      ('_celular', const Size(390, 2300)),
    ]) {
      testWidgets('VENDER · la tarjeta: $caso$sufijo', (tester) async {
        final (clave, _, _, _) = await montar(
          tester,
          hoy: hoyDeLaNoche,
          tamano: tamano,
          preparar: sumarLaNoche,
          pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
        );
        await elegir(tester, id, filtro: filtro);
        await tester.ensureVisible(find.byKey(const Key('vender_linea_texto')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'nada se desborda');
        await guardar(tester, clave, 'Entradas_32_$caso$sufijo.png');
      });
    }
  }

  for (final (parte, numero) in [
    (ParteEntrega.pulseras, null),
    (ParteEntrega.generales, '5001'),
  ]) {
    for (final (sufijo, tamano) in [
      ('', const Size(1100, 1500)),
      ('_celular', const Size(390, 2600)),
    ]) {
      testWidgets('VENDER · el formulario de ${parte.clave}$sufijo', (tester) async {
        final (clave, _, _, _) = await montar(
          tester,
          hoy: hoyDeLaNoche,
          tamano: tamano,
          preparar: sumarLaNoche,
          pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
        );
        await elegir(tester, NocheDeLaVenta.acosta);
        await llenarParte(tester, parte, numero: numero);
        await tester.ensureVisible(find.byKey(const Key('vender_linea_texto')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'nada se desborda');
        await guardar(tester, clave, 'Entradas_33_formulario_${parte.clave}$sufijo.png');
      });
    }
  }

  for (final (sufijo, tamano) in [
    ('', const Size(1100, 1250)),
    ('_celular', const Size(390, 2100)),
  ]) {
    testWidgets('VENDER · las dos partes entregadas$sufijo', (tester) async {
      final (clave, e, _, _) = await montar(
        tester,
        hoy: hoyDeLaNoche,
        tamano: tamano,
        preparar: sumarLaNoche,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      await elegir(tester, NocheDeLaVenta.acosta);
      await llenarParte(tester, ParteEntrega.pulseras);
      await confirmarParte(tester, ParteEntrega.pulseras);
      await llenarParte(tester, ParteEntrega.generales, numero: '5001');
      await confirmarParte(tester, ParteEntrega.generales);
      expect(e.estadoDe(NocheDeLaVenta.acosta).todoEntregado, isTrue);
      // El aviso verde se va: queda lo que se ve en la tarjeta.
      ScaffoldMessenger.of(tester.element(find.byType(VenderEntradasScreen)))
          .removeCurrentSnackBar();
      await tester.ensureVisible(find.byKey(const Key('vender_linea_texto')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, 'Entradas_34_todo_entregado$sufijo.png');
    });
  }

  for (final (sufijo, tamano) in [
    ('', const Size(1100, 950)),
    ('_celular', const Size(390, 1500)),
  ]) {
    testWidgets('VENDER · pagó en la caja: ya podés entregar$sufijo', (tester) async {
      final (clave, e, _, _) = await montar(
        tester,
        hoy: hoyDeLaNoche,
        tamano: tamano,
        preparar: sumarLaNoche,
        pantalla: VenderEntradasScreen(evento: fiestaDeLaEntrega),
      );
      await elegir(tester, NocheDeLaVenta.diaz, filtro: 'vender_filtro_debe');
      await tocar(tester, 'vender_mandar_a_caja');
      await tester.pumpAndSettle();
      // La caja de otra PC le cobra la mora: la ficha baja sin mora.
      final i = e.contratos.alumnos.indexWhere((a) => a.id == NocheDeLaVenta.diaz);
      e.contratos.alumnos[i] = e.contratos.alumnos[i].copyWith(moraPendienteTracked: 0);
      e.motor.bajo.add({'contratos_alumnos', 'pagos_contrato_alumno'});
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vender_pago_texto_${NocheDeLaVenta.diaz}')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'nada se desborda');
      await guardar(tester, clave, 'Entradas_35_pago_en_caja$sufijo.png');
    });
  }

  testWidgets('la entrega del jefe, con las partes de cada familia', (tester) async {
    final (clave, _, _, _) = await montar(
      tester,
      jefe: true,
      asentar: false,
      hoy: hoyDeLaNoche,
      tamano: const Size(1300, 1150),
      preparar: (e) {
        sumarLaNoche(e);
        e.entregadaEnOtroEquipo(
            NocheDeLaVenta.acosta, ParteEntrega.pulseras, DateTime.utc(2026, 11, 18, 15));
        e.entregadaEnOtroEquipo(
            NocheDeLaVenta.herrera, ParteEntrega.pulseras, DateTime.utc(2026, 11, 19, 16));
        e.entregadaEnOtroEquipo(
            NocheDeLaVenta.herrera, ParteEntrega.generales, DateTime.utc(2026, 11, 20, 11));
      },
      pantalla: RetiroEntradasScreen(
        evento: fiestaDeLaEntrega,
        onCobrar: (_) async {},
        onEditarAlumno: (_) async {},
      ),
    );
    expect(tester.takeException(), isNull, reason: 'nada se desborda');
    await guardar(tester, clave, 'Entradas_36_entrega_jefe.png');
  });
}
