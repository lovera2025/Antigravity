// Ventana de prueba: la entrada con el PIN, OPERADORES y la pantalla de Entradas de
// verdad, con operadores inventados, **sin tocar la base de la PC ni la nube**. Lo que
// se guarda se queda en esta ventana y al cerrarla se olvida todo.
//
//   flutter run -d windows -t tool/operadores_prueba.dart
//
// No corre `main.dart`: no abre la base ni inicia sesión. Los PIN inventados están en
// la barra de arriba. El panel de la app va reemplazado por uno mínimo, que tiene lo
// que importa acá: OPERADORES, ENTRADAS y CERRAR.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/operadores_caja_screen.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/models/evento.dart';

import '../test/helpers/operadores_en_memoria.dart';

void main() {
  // En memoria: el PIN maestro de siempre, sin tocar las preferencias de la PC.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final prueba = OperadoresEnPrueba();
  prueba.operadores.lista.addAll([
    operadorDePrueba('a0000000-0000-4000-8000-000000000001', 'Maxi (de hoy, sin fila)', '1111'),
    operadorDePrueba('a0000000-0000-4000-8000-000000000002', 'Ana (solo Entradas)', '2222'),
    operadorDePrueba('a0000000-0000-4000-8000-000000000003', 'Sol (Cobros y Entradas)', '3333'),
    operadorDePrueba('a0000000-0000-4000-8000-000000000004', 'Leo (sin permisos)', '4444'),
    operadorDePrueba('a0000000-0000-4000-8000-000000000005', 'Tati (los tres)', '5555'),
  ]);
  prueba.permisos
    ..poner('a0000000-0000-4000-8000-000000000002', const PermisosEfectivos(entradas: true))
    ..poner(
      'a0000000-0000-4000-8000-000000000003',
      const PermisosEfectivos(cobros: true, entradas: true),
    )
    ..poner('a0000000-0000-4000-8000-000000000004', const PermisosEfectivos())
    ..poner(
      'a0000000-0000-4000-8000-000000000005',
      const PermisosEfectivos(cobros: true, entradas: true, barra: true),
    );

  runApp(ProviderScope(
    overrides: [
      ...prueba.reemplazos,
      fiestasQueVienenProvider.overrideWith(
        (ref) async => [
          for (final (id, nombre, dia) in [
            ('uno', 'PUERTO VIEJO', 1),
            ('dos', 'TÉCNICA', 1),
            ('tres', 'BUENA VISTA', 12),
          ])
            Evento(
              id: id,
              clienteId: 'c',
              tipo: 'Recepción',
              fechaEvento: DateTime(2026, 12, dia),
              estado: EstadoEvento.confirmado,
              modalidad: 'masivo',
              encabezadoEvento: nombre,
            ),
        ],
      ),
    ],
    child: const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Arriba(),
    ),
  ));
}

class _Arriba extends ConsumerWidget {
  const _Arriba();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    return Column(
      children: [
        const Material(
          color: Color(0xFFFFF3CD),
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Ventana de prueba: nada se guarda de verdad.   PIN: jefe 2026 · '
                'Maxi 1111 · Ana 2222 · Sol 3333 · Leo 4444 · Tati 5555',
              ),
            ),
          ),
        ),
        Expanded(
          child: switch (destinoDeEntrada(app)) {
            DestinoDeEntrada.elegir => const RoleGateScreen(),
            DestinoDeEntrada.entradas => EntradasHomeScreen(
                onAbrirFiesta: (context, e) => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    content: Text(
                      'Acá abre la entrega de entradas de ${e.encabezadoEvento}.',
                    ),
                  ),
                ),
              ),
            DestinoDeEntrada.panel => const _PanelMinimo(),
          },
        ),
      ],
    );
  }
}

class _PanelMinimo extends ConsumerWidget {
  const _PanelMinimo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    final notifier = ref.read(appRoleProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(app.esJefe ? 'PANEL · MODO JEFE' : 'PANEL · ${app.operador?.nombre}'),
      ),
      body: Center(
        child: Wrap(
          spacing: 12,
          children: [
            if (app.esJefe)
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const OperadoresCajaScreen()),
                ),
                child: const Text('OPERADORES'),
              ),
            if (app.esCaja && app.permisos.entradas)
              FilledButton(
                onPressed: notifier.pasarAEntradas,
                child: const Text('ENTRADAS'),
              ),
            OutlinedButton(
              onPressed: notifier.logoutApp,
              child: const Text('SALIR'),
            ),
          ],
        ),
      ),
    );
  }
}
