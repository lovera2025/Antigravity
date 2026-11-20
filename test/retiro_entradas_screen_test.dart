// La entrega de entradas entera, montada de verdad con los providers en memoria
// (`test/helpers/entrega_en_memoria.dart`): el mostrador de Entradas, "En caja", el
// aviso cuando la otra PC cobra, PASAR A CAJA, la línea en vivo y anular solo el
// jefe. Y que la oficina sigue igual.
//
// Desde el 20-nov-2026 lo sin cargo se entrega **en dos partes** (las pulseras VIP
// con cena y las generales), cada una por `EntregarParte`: estos tests entregan por
// el formulario de cada parte y miran los renglones que quedaron.
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
import 'package:arguello_events/models/entrega_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';
import 'helpers/revision_en_memoria.dart';

const _perez = EntregaEnMemoria.idPerez;
const _gomez = EntregaEnMemoria.idGomez;
const _lopez = EntregaEnMemoria.idLopez;

/// PÉREZ pagó entera su mesa adicional, pero debe $30.000 de la base: no retira
/// lo sin cargo, y lo de la mesa adicional sí se le vende (regla del 20-nov).
void _perezDebeOtraCosa(EntregaEnMemoria e) {
  final i = e.contratos.alumnos.indexWhere((a) => a.id == _perez);
  e.contratos.alumnos[i] = e.contratos.alumnos[i].copyWith(
    saldoDeudor: 30000,
    mesaExtraCuotasPagadas: 1,
  );
  e.contratos.pagos
    ..removeWhere((p) => p['contrato_alumno_id'] == _perez)
    ..add(pagoDeLaEntrega(_perez, 270000, 'Cuota Base (8/9)'))
    ..add(pagoDeLaEntrega(_perez, 70000, 'Mesa Extra 1'));
}

/// En el diálogo abierto: ENTREGAR de [parte], quién retira y CONFIRMAR. [numero]:
/// el primero de las generales, si vienen numeradas.
Future<void> _entregarParte(
  WidgetTester tester,
  ParteEntrega parte, {
  String quien = 'Padre',
  String nombre = 'Hugo López',
  String? numero,
}) async {
  await tester.tap(find.byKey(Key('entrega_entregar_${parte.clave}')));
  await _pasar(tester);
  if (numero != null) {
    await tester.tap(find.text('Vienen con número'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Del'), numero);
  }
  await tester.tap(find.text(quien));
  await tester.enterText(
    find.widgetWithText(TextField, 'Nombre y apellido de quien retira'),
    nombre,
  );
  await tester.tap(find.text('Escribió su nombre y apellido en la planilla de papel'));
  await tester.pump();
  await tester.ensureVisible(find.byKey(Key('entrega_confirmar_${parte.clave}')));
  await tester.tap(find.byKey(Key('entrega_confirmar_${parte.clave}')));
  await _pasar(tester);
}

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
  Size tamano = const Size(1300, 1000),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = tamano;
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
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsOneWidget);
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
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsOneWidget);
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
      await _entregarParte(tester, ParteEntrega.pulseras, quien: 'Madre', nombre: 'Marta Pérez');

      final r = m.e.renglonesDe(_perez).single;
      expect(r.parte, ParteEntrega.pulseras);
      expect(r.esEntrega, isTrue);
      expect(r.hechoPor, 'Carla', reason: 'queda anotado quién entregó');
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

    // Hasta la 6.9.2 se le vendían aunque debiera la mesa. Cambió a propósito el
    // 20-nov: se le vende solo lo que ya pagó entero, cosa por cosa.
    testWidgets('el jefe le vende lo que ya pagó entero aunque deba otra cosa: VENDER '
        'con la familia ya elegida', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await vender(e, lugar: 3);
      await _montar(tester, mostrador: false, jefe: true, entradas: e,
          preparar: _perezDebeOtraCosa);
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

    testWidgets('si debe la mesa adicional, no se le vende: "a confirmar"', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await _montar(tester, mostrador: false, jefe: true, entradas: e);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.byKey(const Key('entrega_venderle')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_a_confirmar'))).data,
        'La mesa adicional está a confirmar: falta pagarla en caja.',
      );
    });

    testWidgets('en el mostrador, sin el permiso de vender, dice quién se las vende',
        (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await _montar(tester, entradas: e, preparar: _perezDebeOtraCosa);
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
      await _montar(tester, vende: true, entradas: e, preparar: _perezDebeOtraCosa);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.byKey(const Key('entrega_venderle')), findsOneWidget);
    });

    // La segunda llave (etapa 7): el botón se decide al abrir el cartel. Si en
    // el medio le sacan "Vende entradas", tocarlo no abre VENDER.
    testWidgets('sin el permiso, VENDERLE ESAS ENTRADAS no abre VENDER aunque el botón '
        'ya estuviera', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      final m = await _montar(tester, vende: true, entradas: e, preparar: _perezDebeOtraCosa);
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
      await _entregarParte(tester, ParteEntrega.generales, numero: '5001');
      expect(find.textContaining('El 5001 ya se le dio a [BAJA] RÍOS, PEDRO'), findsOneWidget);
    });

    // Hasta la 6.9.2 este número no se entregaba ("El 3001 ya se le dio a
    // GOMEZ, LUIS"). Cambió a propósito el 20-nov: lo vendido sale del
    // talonario de las anticipadas, y las generales de los alumnos son otro.
    testWidgets('un número ya vendido se entrega igual: es otro talonario', (tester) async {
      final e = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
      await vender(e, familia: null, comprador: 'GOMEZ, LUIS', lugar: 0, sueltas: 2,
          numeros: '3001-3002');
      final m = await _montar(tester, mostrador: false, jefe: true, entradas: e);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await _entregarParte(tester, ParteEntrega.generales, numero: '3001');
      expect(find.textContaining('ya se le dio'), findsNothing);
      final r = m.e.renglonesDe(_lopez).single;
      expect(r.parte, ParteEntrega.generales);
      expect(r.tramos, const [TramoTalonario(3001, 3007)]);
    });

    testWidgets('un número ya entregado a otra familia sigue sin volver a darse',
        (tester) async {
      await _montar(tester, mostrador: false, jefe: true,
          entradas: EntradasEnMemoria()..conPrecio(idFiestaEntrega));
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await _entregarParte(tester, ParteEntrega.generales, numero: '1005');
      expect(find.textContaining('El 1005 ya se le dio a GÓMEZ, ANA'), findsOneWidget);
      expect(find.byKey(const Key('entrega_confirmar_generales')), findsOneWidget,
          reason: 'no se entregó');
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

    testWidgets('el jefe anula con motivo: la entrega de las 8 juntas (6.9.x), entera',
        (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      await _abrir(tester, 'GÓMEZ, ANA');
      await tester.tap(find.text('ANULAR ENTREGA'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Por qué se anula'),
        'Se equivocó de alumno',
      );
      await tester.tap(find.text('CONFIRMAR ANULACIÓN DE TODO'));
      await _pasar(tester);
      final r = m.e.entregas.filas[_gomez]!;
      expect(r.entregado, isFalse);
      expect(r.anuladoMotivo, 'Se equivocó de alumno');
      expect(m.e.estadoDe(_gomez).algoEntregado, isFalse);
      expect(find.textContaining('Entrega de GÓMEZ, ANA anulada.'), findsOneWidget);
    });
  });

  // 20-nov-2026: lo sin cargo llega en dos tandas y se entrega en dos partes.
  group('la entrega en dos partes', () {
    testWidgets('las pulseras un día y las generales otro: su ✓, el total de arriba '
        'y "✓ Todo entregado"', (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      // LÓPEZ no tiene acompañantes: 1 pulsera y 7 generales.
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_total_partes'))).data,
        'Pulseras VIP: 3 (entregadas 1) · Generales: 21 (entregadas 7)',
      );

      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await _entregarParte(tester, ParteEntrega.pulseras);
      // Una sola, en singular (revisión del 20-nov: decía "1 pulseras").
      expect(find.textContaining('✓ Entregada 1 pulsera VIP con cena a HUGO LÓPEZ'),
          findsOneWidget);
      expect(find.text('✓ Pulseras entregadas'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_total_partes'))).data,
        'Pulseras VIP: 3 (entregadas 2) · Generales: 21 (entregadas 7)',
      );
      // Una entrega a medias no escribe la fila de siempre.
      expect(m.e.entregas.filas[_lopez], isNull);

      await _abrir(tester, 'LÓPEZ, SOFÍA');
      expect(find.byKey(const Key('entrega_hecha_pulseras')), findsOneWidget);
      await _entregarParte(tester, ParteEntrega.generales);
      expect(find.text('✓ Todo entregado'), findsWidgets);
      expect(m.e.estadoDe(_lopez).todoEntregado, isTrue);
      // Con las dos partes, la fila completa: una 6.9.x la ve "Retiró".
      final fila = m.e.entregas.filas[_lopez]!;
      expect(fila.entregado, isTrue);
      expect(fila.vip, 1);
      expect(fila.generales, 7);
      expect(fila.tramos, isEmpty, reason: 'las generales vinieron sin número');
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_total_partes'))).data,
        'Pulseras VIP: 3 (entregadas 2) · Generales: 21 (entregadas 14)',
      );
    });

    // Revisión del 20-nov-2026: si al completar la fila la nube no contestaba,
    // la familia quedaba marcada y no se volvía a intentar en toda la noche.
    testWidgets('si la nube no contesta al completar la fila, se vuelve a intentar en '
        'la próxima lectura', (tester) async {
      final m = await _montar(
        tester,
        mostrador: false,
        jefe: true,
        preparar: (e) {
          // Cada parte la dio un equipo distinto: la fila de siempre no está.
          e.entregadaEnOtroEquipo(_lopez, ParteEntrega.pulseras, DateTime.utc(2026, 11, 18));
          e.entregadaEnOtroEquipo(_lopez, ParteEntrega.generales, DateTime.utc(2026, 11, 19));
          e.nubeQueNoContesta = 1;
        },
      );
      expect(m.e.entregas.filas[_lopez], isNull, reason: 'la nube no contestó');
      // Baja algo de otro equipo: se relee, y esta vez la nube contesta.
      m.e.motor.bajo.add({'contratos_alumnos'});
      await _pasar(tester);
      expect(m.e.entregas.filas[_lopez]?.entregado, isTrue);
    });

    testWidgets('la fila que dice "entregado" con las pulseras anuladas se pone al día',
        (tester) async {
      final m = await _montar(
        tester,
        mostrador: false,
        jefe: true,
        preparar: (e) {
          final g = e.entregadaEnOtroEquipo(
              _lopez, ParteEntrega.generales, DateTime.utc(2026, 11, 19));
          e.entregadaEnOtroEquipo(_lopez, ParteEntrega.pulseras, DateTime.utc(2026, 11, 18));
          // La tablet escribió la fila completa (reflejo de las generales)...
          final lopez = e.contratos.alumnos.firstWhere((a) => a.id == _lopez);
          e.entregas.filas[_lopez] = RetiroEntradas.nuevaEntrega(
            alumno: lopez,
            entradas: RetiroEntradas.entradasDe(lopez),
            tramos: const [],
            menores10: 0,
            parentesco: ParentescoRetiro.madre,
            nombre: 'MADRE, UNA',
            quien: 'Sofi',
            ahora: g.createdAt,
          );
          // ...y el jefe anuló las pulseras sin enterarse.
          e.anuladaEnOtroEquipo(_lopez, ParteEntrega.pulseras, DateTime.utc(2026, 11, 20));
        },
      );
      final fila = m.e.entregas.filas[_lopez]!;
      expect(fila.entregado, isFalse, reason: 'el plano y la 6.9.x ya no ven "Retiró"');
      expect(fila.anuladoMotivo, 'Solo las pulseras VIP con cena: eran de otro');
      expect(m.e.estadoDe(_lopez).generales.entregada, isTrue);
      expect(m.e.estadoDe(_lopez).pulseras.entregada, isFalse);
    });

    // Revisión del 20-nov-2026: en un celular, las cinco tarjetas de arriba en
    // una fila partían los rótulos a mitad de palabra ("Pulser / as VIP").
    testWidgets('en un celular las tarjetas van de a dos, sin repetir la línea de '
        'pulseras y generales', (tester) async {
      await _montar(tester, tamano: const Size(390, 900));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('entrega_tarjetas_celular')), findsOneWidget);
      expect(find.text('Retiraron todo'), findsOneWidget);
      expect(find.text('Con deuda'), findsOneWidget);
      expect(find.text('Pulseras VIP'), findsNothing);
      expect(find.text('Generales'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('entrega_total_partes'))).data,
        'Pulseras VIP: 3 (entregadas 1) · Generales: 21 (entregadas 7)',
      );
      // Cada tarjeta mide la mitad del ancho (con cinco en una fila, un quinto).
      final tarjeta = tester.getSize(find.ancestor(
        of: find.text('Retiraron todo'),
        matching: find.byType(SizedBox),
      ).first);
      expect(tarjeta.width, greaterThan(170));
    });

    testWidgets('sin internet: pregunta, guarda y avisa que no subió', (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      m.e.conexion.cambiar(AppConnectivity.offline);
      await _pasar(tester);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await _entregarParte(tester, ParteEntrega.pulseras);
      expect(find.text('Sin conexión'), findsOneWidget);
      await tester.tap(find.text('SEGUIR'));
      await _pasar(tester);
      expect(find.text('Entregado, pero todavía no subió'), findsOneWidget);
      expect(m.e.renglonesDe(_lopez), hasLength(1));
    });

    testWidgets('sin internet, si no sigue, no se guarda nada', (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      m.e.conexion.cambiar(AppConnectivity.offline);
      await _pasar(tester);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await _entregarParte(tester, ParteEntrega.pulseras);
      await tester.tap(find.text('CANCELAR'));
      await _pasar(tester);
      expect(m.e.renglonesDe(_lopez), isEmpty);
    });

    testWidgets('si otro equipo la entregó con el diálogo abierto, "Ya retiró" y no se '
        'guarda nada', (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      m.e.partes.renglones.add(EntregaEntradas.entrega(
        contratoAlumnoId: _lopez,
        eventoId: idFiestaEntrega,
        parte: ParteEntrega.pulseras,
        cantidad: 1,
        parentesco: ParentescoRetiro.madre,
        nombre: 'Sofía López',
        escribioEnPlanilla: true,
        hechoPor: 'Sofi',
        deviceId: 'tablet-2',
        ahora: DateTime.utc(2026, 11, 20, 12),
      ));
      await _entregarParte(tester, ParteEntrega.pulseras);
      expect(find.text('Ya retiró'), findsOneWidget);
      expect(find.textContaining('(lo registró Sofi)'), findsOneWidget);
      expect(m.e.renglonesDe(_lopez), hasLength(1));
    });

    testWidgets('si cambió la cuenta con el diálogo abierto, "Cambió algo"', (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      final i = m.e.contratos.alumnos.indexWhere((a) => a.id == _lopez);
      m.e.contratos.alumnos[i] = m.e.contratos.alumnos[i].copyWith(
        cantidadAcompanantes: 1,
        nombresAcompanantes: const ['LÓPEZ, MARTA'],
      );
      await _entregarParte(tester, ParteEntrega.pulseras);
      expect(find.text('Cambió algo'), findsOneWidget);
      expect(find.textContaining('hoy le corresponden 2 pulseras VIP con cena, no 1'),
          findsOneWidget);
      expect(m.e.renglonesDe(_lopez), isEmpty);
    });

    testWidgets('el jefe anula solo las generales: las pulseras siguen entregadas',
        (tester) async {
      final m = await _montar(tester, mostrador: false, jefe: true);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await _entregarParte(tester, ParteEntrega.pulseras);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await _entregarParte(tester, ParteEntrega.generales);
      await _abrir(tester, 'LÓPEZ, SOFÍA');
      await tester.tap(find.byKey(const Key('entrega_anular')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('entrega_anular_pulseras')));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Por qué se anula'),
        'Faltaba una general',
      );
      await tester.tap(find.text('CONFIRMAR ANULACIÓN'));
      await _pasar(tester);
      final e = m.e.estadoDe(_lopez);
      expect(e.pulseras.entregada, isTrue);
      expect(e.generales.entregada, isFalse);
      expect(e.generales.motivoAnulacion, 'Faltaba una general');
      expect(m.e.entregas.filas[_lopez]!.anuladoMotivo,
          'Solo las entradas generales: Faltaba una general');
      expect(find.text('✓ Pulseras entregadas'), findsOneWidget);
    });

    testWidgets('quien debe no tiene ENTREGAR, en ninguna de las dos partes', (tester) async {
      await _montar(tester, mostrador: false, jefe: true);
      await _abrir(tester, 'PÉREZ, JUAN');
      expect(find.byKey(const Key('entrega_entregar_pulseras')), findsNothing);
      expect(find.byKey(const Key('entrega_entregar_generales')), findsNothing);
      expect(find.text('IR A COBRAR'), findsOneWidget);
    });

    testWidgets('cada parte la dio un equipo y ninguno vio las dos: con internet, la '
        'fila de siempre se completa sola', (tester) async {
      EntregaEntradas renglon(ParteEntrega p, String quien, DateTime ahora) =>
          EntregaEntradas.entrega(
            contratoAlumnoId: _lopez,
            eventoId: idFiestaEntrega,
            parte: p,
            cantidad: p == ParteEntrega.pulseras ? 1 : 7,
            parentesco: ParentescoRetiro.padre,
            nombre: 'Hugo López',
            escribioEnPlanilla: true,
            hechoPor: quien,
            deviceId: quien,
            ahora: ahora,
          );
      final m = await _montar(
        tester,
        mostrador: false,
        jefe: true,
        preparar: (e) => e.partes.renglones.addAll([
          renglon(ParteEntrega.pulseras, 'pc', DateTime.utc(2026, 11, 19, 15)),
          renglon(ParteEntrega.generales, 'tablet', DateTime.utc(2026, 11, 20, 15)),
        ]),
      );
      await _pasar(tester);
      final fila = m.e.entregas.filas[_lopez]!;
      expect(fila.entregado, isTrue);
      expect(fila.entregadoAt, DateTime.utc(2026, 11, 20, 15),
          reason: 'como si la hubiera escrito quien entregó la última parte');
      expect(find.text('✓ Todo entregado'), findsWidgets);
    });

    testWidgets('el total de arriba y el menú de la planilla, por material', (tester) async {
      await _montar(tester, mostrador: false, jefe: true);
      await tester.tap(find.byKey(const Key('entrega_imprimir')));
      await _pasar(tester);
      for (final texto in [
        'Planilla de pulseras VIP (blanco y negro)',
        'Planilla de pulseras VIP (color)',
        'Planilla de generales (blanco y negro)',
        'Planilla de generales (color)',
      ]) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
    });
  });
}
