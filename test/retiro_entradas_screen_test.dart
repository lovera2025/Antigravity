// La entrega de entradas entera, montada de verdad con los providers en memoria
// (`test/helpers/entrega_en_memoria.dart`): el mostrador de Entradas, "En caja", el
// aviso cuando la otra PC cobra, PASAR A CAJA, la línea en vivo y anular solo el
// jefe. Y que la oficina sigue igual.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/services/en_caja.dart';
import 'package:arguello_events/features/entradas/widgets/vender_entradas_screen.dart';
import 'package:arguello_events/features/entradas/widgets/ventas_de_entradas_screen.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';
import 'helpers/revision_en_memoria.dart';

const _perez = EntregaEnMemoria.idPerez;
const _gomez = EntregaEnMemoria.idGomez;

class _Montada {
  final EntregaEnMemoria e;
  final ProviderContainer c;
  final List<String> cobrosDeLaOficina;
  _Montada(this.e, this.c, this.cobrosDeLaOficina);

  EnCaja get enCaja => c.read(enCajaProvider(idFiestaEntrega));
}

Future<_Montada> _montar(
  WidgetTester tester, {
  bool mostrador = true,
  bool cobros = false,
  bool jefe = false,
  bool vende = false,
  EntradasEnMemoria? entradas,
  void Function(EntregaEnMemoria)? preparar,
  RevisionEnMemoria Function(EntregaEnMemoria)? revision,
  // El momento de ahora en Argentina, para lo que depende del día (PRECIOS).
  DateTime? hoy,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1300, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntregaEnMemoria();
  preparar?.call(e);
  // Siempre una venta de entradas en memoria: sin ella, lo que la pantalla lee
  // de la venta caería en la base de verdad del equipo.
  final c = ProviderContainer(overrides: [
    ...e.reemplazos(jefe: mostrador ? null : jefe),
    ...(entradas ?? EntradasEnMemoria()).reemplazos,
    if (revision != null) revision(e).reemplazo,
    if (hoy != null) hoyEnArgentinaProvider.overrideWithValue(() => hoy),
  ]);
  addTearDown(c.dispose);
  final cobrosDeLaOficina = <String>[];
  if (mostrador) {
    await c.read(appRoleProvider.notifier).entrarComoEntradas(
          e.operador(cobros: cobros),
          PermisosEfectivos(entradas: true, cobros: cobros, vendeEntradas: vende),
        );
  }
  Future<void> anotar(ContratoAlumno a) async => cobrosDeLaOficina.add(a.id);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: mostrador
          ? RetiroEntradasScreen.mostrador(evento: fiestaDeLaEntrega)
          : RetiroEntradasScreen(
              evento: fiestaDeLaEntrega,
              onCobrar: anotar,
              onEditarAlumno: anotar,
            ),
    ),
  ));
  await _pasar(tester);
  return _Montada(e, c, cobrosDeLaOficina);
}

/// Sin `pumpAndSettle`: la pantalla relee cada 15 s.
Future<void> _pasar(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _abrir(WidgetTester tester, String nombre) async {
  await tester.tap(find.text(nombre).first);
  await _pasar(tester);
}

void main() {
  group('PRECIOS, en ENTRADAS de la fiesta (6.9.0)', () {
    TextButton boton(WidgetTester tester) =>
        tester.widget<TextButton>(find.byKey(const Key('entradas_precios')));

    testWidgets('sin modo jefe se ve, apagado y con el motivo', (tester) async {
      await _montar(tester, mostrador: false, entradas: EntradasEnMemoria());
      expect(find.text('PRECIOS'), findsOneWidget);
      expect(boton(tester).onPressed, isNull);
      expect(find.byTooltip(kSoloEnModoJefe), findsWidgets);
    });

    testWidgets('en modo jefe abre los precios de esa fiesta y los guarda',
        (tester) async {
      final entradas = EntradasEnMemoria();
      await _montar(tester, mostrador: false, jefe: true, entradas: entradas);
      expect(boton(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('entradas_precios')));
      await _pasar(tester);
      expect(find.text('Precios de las entradas'), findsOneWidget);
      // 6.9.3: primero se elige qué se vende ahora, y recién ahí sus precios.
      expect(find.byKey(const Key('precio_valor')), findsNothing);
      await tester.tap(find.byKey(const Key('precio_se_vende_general')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('precio_valor')), '10000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('precios_guardar')));
      await _pasar(tester);
      expect(find.text('Precios de las entradas'), findsNothing);
      final guardada = entradas.configs[idFiestaEntrega]!;
      expect(guardada.valorEntrada, 10000);
      expect(guardada.precioAnticipada, isNull);
      expect(guardada.hechoPor, isNotEmpty);
    });

    testWidgets('PRECIOS propone que la anticipada valga hasta el día anterior '
        'a la fiesta', (tester) async {
      await _montar(
        tester,
        mostrador: false,
        jefe: true,
        entradas: EntradasEnMemoria(),
        hoy: DateTime.utc(2026, 11, 20, 12),
      );
      await tester.tap(find.byKey(const Key('entradas_precios')));
      await _pasar(tester);
      await tester.tap(find.byKey(const Key('precio_se_vende_anticipada')));
      await tester.pump();
      // La fiesta de la entrega es el 4-dic-2026.
      expect(
        tester.widget<TextField>(find.byKey(const Key('precio_hasta'))).controller!.text,
        '03/12/2026',
      );
    });

    testWidgets('en el mostrador no está: quien entrega no ve los precios',
        (tester) async {
      await _montar(tester, entradas: EntradasEnMemoria());
      expect(find.byKey(const Key('entradas_precios')), findsNothing);
      expect(find.byKey(const Key('entradas_vender')), findsNothing);
    });
  });

  // 17-nov-2026: el descuento de los lugares es para lo que la familia tenía
  // cargado al sorteo. En una fiesta sorteada antes de esa regla, el jefe
  // acepta la lista en PRECIOS; hasta entonces ENTRADAS se lo recuerda.
  group('los lugares agregados después del sorteo', () {
    // 12/11/2026 21:40 en Argentina.
    final sorteoEl = DateTime.utc(2026, 11, 13, 0, 40);

    /// PÉREZ tenía la mesa 12 en el sorteo; la 13 se la dio sola el programa
    /// dos días después, sin ningún pago de mesa: vino después.
    void sorteadaSinAnotar(EntregaEnMemoria e, {Map<String, String>? lugares}) {
      e.sorteos.registros.addAll([
        SorteoMesasRegistro(
          id: 'sorteo',
          eventoId: idFiestaEntrega,
          tipo: TipoRegistroSorteo.sorteo,
          resultado: const {_perez: '12', EntregaEnMemoria.idLopez: '14', _gomez: '15'},
          antes: const {},
          lugares: lugares,
          hechoPor: 'Jefe',
          createdAt: sorteoEl,
        ),
        SorteoMesasRegistro(
          id: 'auto',
          eventoId: idFiestaEntrega,
          tipo: TipoRegistroSorteo.sorteo,
          resultado: const {_perez: '12, 13'},
          antes: const {_perez: '12'},
          automatico: true,
          createdAt: sorteoEl.add(const Duration(days: 2)),
        ),
      ]);
    }

    RevisionEnMemoria revision(EntregaEnMemoria e) => RevisionEnMemoria(
          alumnosDeLaFiesta: e.contratos.alumnos,
          registrosDeLaFiesta: e.sorteos.registros,
        );

    final recordatorio = find.byKey(const Key('entradas_falta_revisar_lugares'));

    testWidgets('en modo jefe, la fiesta sorteada sin la lista aceptada lo '
        'recuerda arriba', (tester) async {
      await _montar(tester, mostrador: false, jefe: true, preparar: sorteadaSinAnotar);
      expect(recordatorio, findsOneWidget);
      expect(find.textContaining('todos van con descuento'), findsOneWidget);
    });

    testWidgets('sin modo jefe no se ve', (tester) async {
      await _montar(tester, mostrador: false, preparar: sorteadaSinAnotar);
      expect(recordatorio, findsNothing);
    });

    testWidgets('en el mostrador no se ve', (tester) async {
      await _montar(tester, preparar: sorteadaSinAnotar);
      expect(recordatorio, findsNothing);
    });

    testWidgets('sin sorteo, o con los lugares ya anotados, no hay nada que '
        'recordar', (tester) async {
      await _montar(tester, mostrador: false, jefe: true);
      expect(recordatorio, findsNothing);
      await _montar(
        tester,
        mostrador: false,
        jefe: true,
        preparar: (e) => sorteadaSinAnotar(e, lugares: const {}),
      );
      expect(recordatorio, findsNothing);
    });

    testWidgets('de punta a punta: ABRIR PRECIOS, REVISAR LA LISTA, ACEPTAR; '
        'PRECIOS dice qué sorteo rige, el recordatorio se va y lo de PÉREZ '
        'pasa a "sin descuento"', (tester) async {
      late RevisionEnMemoria m;
      final montada = await _montar(
        tester,
        mostrador: false,
        jefe: true,
        preparar: sorteadaSinAnotar,
        revision: (e) => m = revision(e),
      );
      // Antes de aceptar, todo va con descuento.
      expect(find.textContaining('sin descuento'), findsNothing);

      await tester.tap(find.byKey(const Key('entradas_revisar_lugares')));
      await _pasar(tester);
      expect(find.text('Precios de las entradas'), findsOneWidget);
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('precio_revisar_lugares')));
      await _pasar(tester);
      expect(find.text('Lugares agregados después del sorteo'), findsOneWidget);
      expect(find.text('PÉREZ, JUAN · 1 mesa adicional (8 entradas)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('revision_aceptar')));
      await _pasar(tester);
      expect(find.text('Lugares agregados después del sorteo'), findsNothing);
      expect(m.guardados.single.registroId, 'sorteo');
      expect(m.guardados.single.lugares, isEmpty);
      expect(montada.e.sorteos.registros.first.lugares, isNotNull);

      // PRECIOS sigue abierto y ya dice qué rige.
      expect(find.text('Precios de las entradas'), findsOneWidget);
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('precio_lugares_anotados'))).data,
        contains('al sorteo del 12/11/2026 21:40 hs'),
      );

      await tester.tap(find.byKey(const Key('precios_cancelar')));
      await _pasar(tester);
      expect(recordatorio, findsNothing);
      expect(find.textContaining('8 sin descuento'), findsWidgets);
    });

    testWidgets('cancelar la lista deja todo como estaba', (tester) async {
      late RevisionEnMemoria m;
      await _montar(
        tester,
        mostrador: false,
        jefe: true,
        preparar: sorteadaSinAnotar,
        revision: (e) => m = revision(e),
      );
      await tester.tap(find.byKey(const Key('entradas_precios')));
      await _pasar(tester);
      await tester.tap(find.byKey(const Key('precio_revisar_lugares')));
      await _pasar(tester);
      await tester.tap(find.byKey(const Key('revision_cancelar')));
      await _pasar(tester);
      expect(m.guardados, isEmpty);
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('precios_cancelar')));
      await _pasar(tester);
      expect(recordatorio, findsOneWidget);
      expect(find.textContaining('sin descuento'), findsNothing);
    });
  });

  group('VENDER, en ENTRADAS de la fiesta (6.9.0)', () {
    TextButton boton(WidgetTester tester) =>
        tester.widget<TextButton>(find.byKey(const Key('entradas_vender')));

    testWidgets('sin el permiso ni el modo jefe se ve, apagado y con el motivo',
        (tester) async {
      await _montar(tester, mostrador: false, entradas: EntradasEnMemoria());
      expect(boton(tester).onPressed, isNull);
      expect(
        find.byTooltip('Con el permiso "Vende entradas" o en modo jefe'),
        findsOneWidget,
      );
    });

    testWidgets('en modo jefe abre la caja de entradas de esa fiesta', (tester) async {
      final entradas = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await _montar(tester, mostrador: false, jefe: true, entradas: entradas);
      expect(boton(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('entradas_vender')));
      await _pasar(tester);
      await _pasar(tester);
      expect(find.byType(VenderEntradasScreen), findsOneWidget);
      // Sin caja abierta, VENDER la pide.
      expect(find.text('Abrir la caja de entradas'), findsOneWidget);
    });
  });

  group('VENTAS, en ENTRADAS de la fiesta (6.9.0)', () {
    TextButton boton(WidgetTester tester) =>
        tester.widget<TextButton>(find.byKey(const Key('entradas_ventas')));
    // PRECIOS tiene el mismo motivo: se mira el del botón de VENTAS.
    String? motivo(WidgetTester tester) => tester
        .widget<Tooltip>(find.ancestor(
          of: find.byKey(const Key('entradas_ventas')),
          matching: find.byType(Tooltip),
        ))
        .message;

    testWidgets('sin modo jefe se ve, apagado y con el motivo', (tester) async {
      await _montar(tester, mostrador: false, entradas: EntradasEnMemoria());
      expect(find.text('VENTAS'), findsOneWidget);
      expect(boton(tester).onPressed, isNull);
      expect(motivo(tester), kSoloEnModoJefe);
    });

    testWidgets('en modo jefe abre las ventas de toda la fiesta, sin elegir caja',
        (tester) async {
      final entradas = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await _montar(tester, mostrador: false, jefe: true, entradas: entradas);
      expect(boton(tester).onPressed, isNotNull);
      expect(motivo(tester), 'Las ventas de entradas de esta fiesta');
      await tester.tap(find.byKey(const Key('entradas_ventas')));
      await _pasar(tester);
      await _pasar(tester);
      final ventas =
          tester.widget<VentasDeEntradasScreen>(find.byType(VentasDeEntradasScreen));
      expect(ventas.caja, isNull);
      expect(
        tester.widget<Text>(find.byKey(const Key('ventas_alcance'))).data,
        contains('Todas las cajas'),
      );
    });

    testWidgets('en el mostrador no está', (tester) async {
      await _montar(tester, entradas: EntradasEnMemoria());
      expect(find.byKey(const Key('entradas_ventas')), findsNothing);
    });
  });

  // Con "gomez" no aparecía "GÓMEZ": el buscador del mostrador comparaba letra
  // por letra (revisión del 13-nov).
  testWidgets('el buscador del mostrador encuentra sin acentos y en cualquier orden',
      (tester) async {
    await _montar(tester);
    Future<void> buscar(String texto) async {
      await tester.enterText(find.byType(TextField).first, texto);
      await _pasar(tester);
    }

    await buscar('gomez');
    expect(find.text('GÓMEZ, ANA'), findsOneWidget);
    expect(find.text('PÉREZ, JUAN'), findsNothing);

    await buscar('juan perez');
    expect(find.text('PÉREZ, JUAN'), findsOneWidget);
    expect(find.text('GÓMEZ, ANA'), findsNothing);

    await buscar('LÓPEZ');
    expect(find.text('LÓPEZ, SOFÍA'), findsOneWidget);

    await buscar('');
    for (final nombre in ['PÉREZ, JUAN', 'LÓPEZ, SOFÍA', 'GÓMEZ, ANA']) {
      expect(find.text(nombre), findsOneWidget);
    }
  });

  group('el mostrador, sin Cobros', () {
    testWidgets('si debe: "que pase por caja", sin cobrar ni editar, y queda en En caja',
        (tester) async {
      final m = await _montar(tester);
      expect(find.byKey(const Key('entrega_en_caja')), findsNothing);

      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.textContaining('Que pase por caja a saldar todo'), findsOneWidget);
      expect(find.text('IR A COBRAR'), findsNothing);
      expect(find.text('EDITAR ALUMNO'), findsNothing);
      expect(find.text('PASAR A CAJA'), findsNothing);

      await tester.tap(find.byKey(const Key('entrega_a_la_caja')));
      await _pasar(tester);
      expect(m.enCaja.contiene(_perez), isTrue);
      expect(find.byKey(const Key('entrega_en_caja')), findsOneWidget);
      expect(find.textContaining('PÉREZ, JUAN · debe \$ 70.000'), findsOneWidget);
    });

    testWidgets('cuando la otra PC cobra todo, salta "pagó: ya podés entregar"',
        (tester) async {
      final m = await _montar(tester);
      await _abrir(tester, 'PÉREZ, JUAN');
      await tester.tap(find.byKey(const Key('entrega_a_la_caja')));
      await _pasar(tester);

      m.e.cobrar(_perez, 70000);
      await _pasar(tester);
      expect(find.text('PÉREZ, JUAN pagó: ya podés entregar'), findsOneWidget);
      expect(find.byKey(const Key('entrega_en_caja')), findsNothing);

      await tester.tap(find.byKey(const Key('entrega_entregar_$_perez')));
      await _pasar(tester);
      expect(find.text('CONFIRMAR ENTREGA'), findsOneWidget);
    });

    testWidgets('un pago de una parte dice cuánto falta', (tester) async {
      final m = await _montar(tester);
      await _abrir(tester, 'PÉREZ, JUAN');
      await tester.tap(find.byKey(const Key('entrega_a_la_caja')));
      await _pasar(tester);

      m.e.cobrar(_perez, 30000);
      await _pasar(tester);
      expect(
        find.textContaining('PÉREZ, JUAN · pagó una parte · faltan \$ 40.000'),
        findsOneWidget,
      );
      expect(find.textContaining('pagó: ya podés entregar'), findsNothing);
    });

    testWidgets('con su diálogo abierto, al pagar se vuelve a abrir con los datos nuevos',
        (tester) async {
      final m = await _montar(tester);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.textContaining('Que pase por caja'), findsOneWidget);

      m.e.cobrar(_perez, 70000);
      await _pasar(tester);
      expect(find.textContaining('Que pase por caja'), findsNothing);
      expect(find.text('CONFIRMAR ENTREGA'), findsOneWidget);
    });

    testWidgets('entregar a una familia de En caja la saca de la lista', (tester) async {
      final m = await _montar(tester);
      await _abrir(tester, 'PÉREZ, JUAN');
      await tester.tap(find.byKey(const Key('entrega_a_la_caja')));
      await _pasar(tester);
      m.e.cobrar(_perez, 70000);
      await _pasar(tester);
      await tester.tap(find.byKey(const Key('entrega_entregar_$_perez')));
      await _pasar(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Del').first, '2001');
      await tester.tap(find.text('Madre'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre y apellido de quien retira'),
        'Marta Pérez',
      );
      await tester.tap(find.text('Escribió su nombre y apellido en la planilla de papel'));
      await tester.pump();
      await tester.tap(find.text('CONFIRMAR ENTREGA'));
      await _pasar(tester);

      final r = m.e.entregas.filas[_perez]!;
      expect(r.entregado, isTrue);
      expect(r.entregadoPor, 'Carla', reason: 'queda anotado quién entregó');
      expect(m.enCaja.contiene(_perez), isFalse);
      expect(find.byKey(const Key('entrega_pago_$_perez')), findsNothing);
    });

    testWidgets('ANULAR se ve apagado, con el motivo', (tester) async {
      await _montar(tester);
      await _abrir(tester, 'GÓMEZ, ANA');
      final boton = tester.widget<OutlinedButton>(
        find.byKey(const Key('entrega_anular_apagado')),
      );
      expect(boton.onPressed, isNull);
      expect(find.text(kSoloEnModoJefe), findsOneWidget);
      expect(find.text('CONFIRMAR ANULACIÓN'), findsNothing);
    });

    testWidgets('la línea dice si se está en vivo con la caja', (tester) async {
      final m = await _montar(tester);
      expect(find.text('En vivo con la caja'), findsOneWidget);
      m.e.conexion.cambiar(AppConnectivity.offline);
      await _pasar(tester);
      expect(
        find.text('Sin internet: lo que se cobre en la caja no llega hasta que vuelva'),
        findsOneWidget,
      );
      m.e.conexion.cambiar(AppConnectivity.online);
      await _pasar(tester);
      expect(find.text('En vivo con la caja'), findsOneWidget);
    });
  });

  group('el mostrador, con Cobros', () {
    testWidgets('PASAR A CAJA va a la caja y la familia queda en En caja', (tester) async {
      final m = await _montar(tester, cobros: true);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.text('PASAR A CAJA'), findsOneWidget);
      expect(find.text('IR A COBRAR'), findsNothing);

      await tester.tap(find.byKey(const Key('entrega_pasar_a_caja')));
      await _pasar(tester);
      expect(m.c.read(appRoleProvider).esCaja, isTrue);
      expect(m.enCaja.contiene(_perez), isTrue);
    });
  });

  // 6.9.0, sección 9.3 del spec del 13-nov: la entrega sin cargo con lo vendido
  // a la vista, y VENDERLE ESAS ENTRADAS.
  group('lo vendido, a la vista en la entrega', () {
    /// Una venta en la caja de Carla: [lugar] entradas de los lugares de
    /// [familia] y [sueltas] sueltas, con [numeros].
    Future<void> vender(
      EntradasEnMemoria e, {
      String? familia = _perez,
      String comprador = 'PÉREZ, MARTA',
      int lugar = 3,
      int sueltas = 0,
      String? numeros,
    }) async {
      final caja = e.listaCajas.isEmpty
          ? await e.abrirCaja(
              eventoId: idFiestaEntrega, operadorId: 'carla', operadorNombre: 'Carla')
          : e.listaCajas.first;
      await e.vender(
        caja: caja,
        contratoAlumnoId: familia,
        compradorNombre: comprador,
        renglones: [
          if (lugar > 0)
            RenglonEntradas.lugar(
              nombre: 'Entrada de lugar adicional (50 %)',
              precioLista: 10000,
              descuentoPct: 50,
              cantidad: lugar,
            ),
          if (sueltas > 0)
            RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: sueltas),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 5000.0 * lugar + 10000.0 * sueltas,
        numeros: numeros,
        quien: 'Carla',
      );
    }

    testWidgets('con precio: cuántas del 50 % se vendieron, y cuántas compró cada familia',
        (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await vender(e, lugar: 3);
      await _montar(tester, mostrador: false, jefe: true, entradas: e);
      expect(find.text('Al 50 %'), findsOneWidget);
      expect(find.text('3 vendidas de 8'), findsOneWidget);
      expect(find.textContaining('8 al 50 % (compró 3)'), findsOneWidget);
    });

    testWidgets('una venta anulada no cuenta', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await vender(e, lugar: 3);
      await e.anular(e.listaVentas.single,
          motivo: 'error', devueltas: true, quien: 'Jefe');
      await _montar(tester, mostrador: false, jefe: true, entradas: e);
      expect(find.text('0 vendidas de 8'), findsOneWidget);
      expect(find.textContaining('(compró'), findsNothing);
    });

    testWidgets('sin precio en la fiesta se ve como siempre', (tester) async {
      await _montar(tester, mostrador: false, jefe: true, entradas: EntradasEnMemoria());
      expect(find.text('Al 50 %, aparte'), findsOneWidget);
      expect(find.textContaining('vendidas de'), findsNothing);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.byKey(const Key('entrega_compro')), findsNothing);
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
    });

    testWidgets('el jefe se las vende desde la entrega, aunque la familia deba: VENDER '
        'con la familia ya elegida', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await vender(e, lugar: 3);
      await _montar(tester, mostrador: false, jefe: true, entradas: e);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.textContaining('Debe'), findsWidgets, reason: 'debe: no se le entrega');
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_compro'))).data,
        'Ya compró 3: le quedan 5.',
      );
      await tester.tap(find.byKey(const Key('entrega_venderle')));
      await _pasar(tester);
      await _pasar(tester);
      final venta = tester.widget<VenderEntradasScreen>(find.byType(VenderEntradasScreen));
      expect(venta.familiaId, _perez);
    });

    testWidgets('en el mostrador, sin el permiso de vender, dice quién se las vende',
        (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await _montar(tester, entradas: e);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_compro'))).data,
        'Todavía no compró ninguna.',
      );
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
      expect(find.text('Se las vende quien tiene la caja de entradas.'), findsOneWidget);
    });

    testWidgets('en el mostrador, con "Vende entradas", también se las vende', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await _montar(tester, vende: true, entradas: e);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.byKey(const Key('entrega_venderle')), findsOneWidget);
    });

    // La segunda llave (etapa 7): el botón se decide al abrir el cartel. Si en
    // el medio le sacan "Vende entradas", tocarlo no abre VENDER.
    testWidgets('sin el permiso, VENDERLE ESAS ENTRADAS no abre VENDER aunque el botón '
        'ya estuviera', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      final m = await _montar(tester, vende: true, entradas: e);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.byKey(const Key('entrega_venderle')), findsOneWidget);
      await m.c.read(appRoleProvider.notifier).entrarComoEntradas(
            m.e.operador(),
            const PermisosEfectivos(entradas: true),
          );
      await tester.tap(find.byKey(const Key('entrega_venderle')));
      await _pasar(tester);
      await _pasar(tester);
      expect(find.byType(VenderEntradasScreen), findsNothing);
    });

    // Revisión del 15-nov: los números de un alumno que pasó a baja temporal
    // después de retirar siguen teniendo dueño.
    testWidgets('un número entregado a un alumno que después pasó a baja no se vuelve a dar',
        (tester) async {
      await _montar(
        tester,
        mostrador: false,
        jefe: true,
        entradas: EntradasEnMemoria()..conPrecio(idFiestaEntrega),
        preparar: (e) {
          final baja = alumnoDeLaEntrega(
            id: 'a0000000-0000-4000-8000-000000000199',
            nombre: '[BAJA] RÍOS, PEDRO',
            mesas: const [16],
          );
          e.contratos.alumnos.add(baja);
          e.entregas.filas[baja.id] = RetiroEntradas.nuevaEntrega(
            alumno: baja,
            entradas: RetiroEntradas.entradasDe(baja),
            tramos: const [TramoTalonario(5001, 5007)],
            menores10: 0,
            parentesco: ParentescoRetiro.padre,
            nombre: 'Pedro Ríos',
            quien: 'Jefe',
            ahora: DateTime.utc(2026, 11, 7, 18),
          );
        },
      );
      expect(find.textContaining('RÍOS'), findsNothing, reason: 'la baja no se lista');
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await tester.enterText(find.widgetWithText(TextField, 'Del'), '5001');
      await tester.tap(find.text('Padre'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre y apellido de quien retira'),
        'Hugo López',
      );
      await tester.tap(find.text('Escribió su nombre y apellido en la planilla de papel'));
      await tester.pump();
      await tester.tap(find.text('CONFIRMAR ENTREGA'));
      await _pasar(tester);
      expect(find.textContaining('El 5001 ya se le dio a [BAJA] RÍOS, PEDRO'), findsOneWidget);
    });

    testWidgets('un número del talonario ya vendido no se entrega sin cargo', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await vender(e, familia: null, comprador: 'GOMEZ, LUIS', lugar: 0, sueltas: 2,
          numeros: '3001-3002');
      await _montar(tester, mostrador: false, jefe: true, entradas: e);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await tester.enterText(find.widgetWithText(TextField, 'Del'), '3001');
      await tester.tap(find.text('Padre'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre y apellido de quien retira'),
        'Hugo López',
      );
      await tester.tap(find.text('Escribió su nombre y apellido en la planilla de papel'));
      await tester.pump();
      await tester.tap(find.text('CONFIRMAR ENTREGA'));
      await _pasar(tester);
      expect(find.textContaining('El 3001 ya se le dio a GOMEZ, LUIS'), findsOneWidget);
      expect(find.text('CONFIRMAR ENTREGA'), findsOneWidget, reason: 'no se entregó');
    });
  });

  group('la oficina', () {
    testWidgets('sigue igual: IR A COBRAR abre el cobro de siempre, sin En caja ni la línea',
        (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      expect(find.byKey(const Key('entrega_en_vivo')), findsNothing);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.text('IR A COBRAR'), findsOneWidget);
      expect(find.textContaining('Que pase por caja'), findsNothing);
      await tester.tap(find.text('IR A COBRAR'));
      await _pasar(tester);
      expect(m.cobrosDeLaOficina, contains(_perez));
    });

    testWidgets('sin modo jefe, ANULAR se ve apagado', (tester) async {
      await _montar(tester, mostrador: false, jefe: false);
      await _abrir(tester, 'GÓMEZ, ANA');
      expect(find.byKey(const Key('entrega_anular_apagado')), findsOneWidget);
      expect(find.text(kSoloEnModoJefe), findsOneWidget);
    });

    testWidgets('el jefe anula con motivo', (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      await _abrir(tester, 'GÓMEZ, ANA');
      await tester.tap(find.text('ANULAR ENTREGA'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Por qué se anula'),
        'Se equivocó de alumno',
      );
      await tester.tap(find.text('CONFIRMAR ANULACIÓN'));
      await _pasar(tester);
      final r = m.e.entregas.filas[_gomez]!;
      expect(r.entregado, isFalse);
      expect(r.anuladoMotivo, 'Se equivocó de alumno');
    });
  });
}
