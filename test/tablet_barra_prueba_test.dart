// Las ventanas de prueba de la barra en red (etapa 9): la de la PC sigue todo adentro de
// esta PC salvo con `red=todas`, y el celular usa la red de la app tal cual, sin nube.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/features/dashboard/widgets/actualizar_app.dart';

import '../tool/central_barra_prueba.dart';
import '../tool/salon_de_barra_prueba.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('la ventana de la PC, sin red=todas: todo adentro de esta PC', () async {
    final salon = armarSalon(puertoBusqueda: 45555);
    addTearDown(salon.dispose);
    for (final e in salon.todos) {
      expect(e.container.read(escuchaCentralBarraProvider), InternetAddress.loopbackIPv4, reason: e.nombre);
      expect(e.container.read(puertoCentralBarraProvider), 0, reason: e.nombre);
      expect(e.container.read(puertoBusquedaBarraProvider), 45555, reason: e.nombre);
      expect(await e.container.read(destinosBusquedaBarraProvider)(), [InternetAddress.loopbackIPv4]);
    }
  });

  test('con red=todas, la notebook escucha por el wifi en los puertos de la app y las '
      'tablets de la ventana la buscan en esta PC', () async {
    final salon = armarSalon(puertoBusqueda: 45555, redDeVerdad: true);
    addTearDown(salon.dispose);
    final notebook = salon.notebook.container;
    expect(notebook.read(escuchaCentralBarraProvider), InternetAddress.anyIPv4);
    expect(notebook.read(puertoCentralBarraProvider), kPuertoCentralBarra);
    expect(notebook.read(puertoBusquedaBarraProvider), kPuertoBusquedaBarra);
    for (final t in [salon.tabletA, salon.tabletB]) {
      expect(t.container.read(puertoBusquedaBarraProvider), kPuertoBusquedaBarra);
      expect(await t.container.read(destinosBusquedaBarraProvider)(), [InternetAddress.loopbackIPv4]);
    }
  });

  EquipoDePrueba celular() => armarEquipo(
        id: 'celular-de-prueba',
        nombre: 'CELULAR',
        catalogo: catalogoDePrueba(),
        eventos: fiestasDePrueba(),
        red: RedDePrueba.delSalon,
        cajera: 'Lucía',
        pin: '3333',
      );

  test('el celular: la red de la app y sin salir a buscar versiones', () async {
    final c = celular().container;
    addTearDown(c.dispose);
    expect(c.read(escuchaCentralBarraProvider), InternetAddress.anyIPv4);
    expect(c.read(puertoBusquedaBarraProvider), kPuertoBusquedaBarra);
    expect(c.read(destinosBusquedaBarraProvider), same(destinosDeLaRed));
    expect(await c.read(versionNuevaEnLaTabletProvider.future), isNull);
  });

  testWidgets('el celular abre en el PIN de su cajera', (tester) async {
    final c = celular().container;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: CajeraDePrueba()),
    ));
    await tester.pump();
    expect(find.byType(RoleGateScreen), findsOneWidget);
    expect(find.byKey(const Key('entrada_version_nueva')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    c.dispose();
  });
}
