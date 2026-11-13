// El aviso del link del delegado (6.8.0): la alerta en el Centro de Comando y
// el punto en PLANILLAS. Salta cuando un delegado envía; nunca tiene reloj.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/dashboard/widgets/alertas_del_delegado.dart';
import 'package:arguello_events/features/delegado/datos/link_del_delegado.dart';
import 'package:arguello_events/features/delegado/delegado_providers.dart';
import 'package:arguello_events/features/eventos/widgets/grupo_fiesta_toolbar.dart';

import 'helpers/delegado_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

Future<void> _montar(WidgetTester tester, List<AvisoDelDelegado> avisos) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        avisosDelDelegadoProvider.overrideWith((ref) async => avisos),
      ],
      child: const MaterialApp(home: Scaffold(body: AlertasDelDelegado())),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _barra({required bool hayParaTraer, bool esJefe = true}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: GrupoFiestaToolbar(
            compacto: false,
            esJefe: esJefe,
            onPlano: () {},
            onSortear: () {},
            onDeshacer: () {},
            onRestaurar: null,
            onHistorial: () {},
            onPlanillaSorteo: () {},
            onPlanoImpreso: null,
            onPlanillaEntrega: () {},
            onPlanillaMora: null,
            alumnosConMora: 0,
            onEntradas: () {},
            onAcompanantesYMusica: () {},
            hayParaTraer: hayParaTraer,
          ),
        ),
      ),
    );

void main() {
  group('la alerta en el Centro de Comando', () {
    testWidgets('sin nada para traer no dibuja nada', (tester) async {
      await _montar(tester, const []);
      expect(find.byType(InkWell), findsNothing);
      expect(tester.getSize(find.byType(AlertasDelDelegado)).height, 0);
    });

    testWidgets('una por fiesta, con su texto, y se puede tocar', (tester) async {
      await _montar(tester, const [
        AvisoDelDelegado(
          eventoId: _fiesta,
          texto: 'Acompañantes y música para traer: Escuela Normal · envió '
              'LAURA GÓMEZ (2) · faltan 9 alumnos',
        ),
      ]);
      expect(find.byKey(const Key('alerta_delegado_$_fiesta')), findsOneWidget);
      expect(find.textContaining('envió LAURA GÓMEZ (2)'), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
    });
  });

  group('cuándo hay aviso', () {
    test('guardar no avisa; enviar sí; traer lo apaga', () async {
      final nube = DelegadoEnMemoria(
        eventoId: _fiesta,
        alumnos: [AlumnoDeMentira('a1', 'ÁLVAREZ, BRUNO', '6° A')],
      );
      final laura = await nube.conDelegado('Laura Gómez');
      await nube.guardar(
        clave: nube.clave!,
        sesion: laura,
        alumnoId: 'a1',
        acompanantes: [],
        musica: 'Tema',
      );
      expect(await nube.pendientes(), isEmpty);
      await nube.entregar(nube.clave!, laura);
      expect((await nube.pendientes()).single.eventoId, _fiesta);
      await nube.cambiar(_fiesta, 'traido', idsTraidos(['a1']));
      expect(await nube.pendientes(), isEmpty);
    });

    test('sin internet no hay avisos y no se rompe nada', () async {
      final nube = DelegadoEnMemoria(eventoId: _fiesta, alumnos: [])
        ..sinRed = true;
      final c = ProviderContainer(
        overrides: [
          linkDelDelegadoProvider.overrideWithValue(nube),
          connectivityServiceProvider.overrideWithValue(ConnectivityService()),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(avisosDelDelegadoProvider.future), isEmpty);
    });

    test('el aviso no tiene reloj: se pregunta al arrancar y al volver a la '
        'ventana', () {
      final proveedores =
          File('lib/features/delegado/delegado_providers.dart').readAsStringSync();
      expect(proveedores, isNot(contains('Timer')));
      expect(proveedores, isNot(contains('Stream.periodic')));
      final coordinador = File(
        'lib/features/common/widgets/operational_sync_coordinator.dart',
      ).readAsStringSync();
      expect(
        'ref.invalidate(avisosDelDelegadoProvider)'.allMatches(coordinador),
        hasLength(2),
      );
      expect(coordinador, isNot(contains('Timer.periodic')));
      // No va adentro de las estadísticas del inicio, que son sin internet.
      final stats = File(
        'lib/features/dashboard/providers/dashboard_provider.dart',
      ).readAsStringSync();
      expect(stats, isNot(contains('delegado')));
    });

    test('con algo de los delegados para traer no se dice "todo bajo '
        'control"', () {
      final inicio =
          File('lib/features/dashboard/dashboard_screen.dart').readAsStringSync();
      expect(inicio, contains('const AlertasDelDelegado()'));
      expect(inicio, contains('else if (!hayDelDelegado)'));
    });
  });

  group('el punto en PLANILLAS', () {
    testWidgets('con algo para traer lleva un punto, y su renglón lo dice', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_barra(hayParaTraer: true));
      final punto =
          tester.widget<Badge>(find.byKey(const Key('fiesta_planillas_punto')));
      expect(punto.isLabelVisible, isTrue);
      await tester.tap(find.byKey(const Key('fiesta_planillas')));
      await tester.pumpAndSettle();
      expect(
        find.text('Los delegados mandaron algo: traelo acá'),
        findsOneWidget,
      );
    });

    testWidgets('sin nada para traer no hay punto', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_barra(hayParaTraer: false));
      final punto =
          tester.widget<Badge>(find.byKey(const Key('fiesta_planillas_punto')));
      expect(punto.isLabelVisible, isFalse);
      await tester.tap(find.byKey(const Key('fiesta_planillas')));
      await tester.pumpAndSettle();
      expect(find.text('Excel o link para los delegados'), findsOneWidget);
    });

    testWidgets('sin modo jefe se ve que hay algo, y por qué no puede', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_barra(hayParaTraer: true, esJefe: false));
      await tester.tap(find.byKey(const Key('fiesta_planillas')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Los delegados mandaron algo.'),
        findsOneWidget,
      );
    });
  });
}
