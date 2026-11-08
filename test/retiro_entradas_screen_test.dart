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
import 'package:arguello_events/features/entradas/services/en_caja.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

import 'helpers/entrega_en_memoria.dart';

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
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1300, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntregaEnMemoria();
  final c = ProviderContainer(overrides: e.reemplazos(jefe: mostrador ? null : jefe));
  addTearDown(c.dispose);
  final cobrosDeLaOficina = <String>[];
  if (mostrador) {
    await c.read(appRoleProvider.notifier).entrarComoEntradas(
          e.operador(cobros: cobros),
          PermisosEfectivos(entradas: true, cobros: cobros),
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
