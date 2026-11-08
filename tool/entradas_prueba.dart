// Ventana de prueba del mostrador de Entradas (6.4.0, Entradas 4 y 5): a la izquierda,
// Carla, que entró con su PIN solo a entregar; a la derecha, "la otra PC", que cobra.
// Sin base ni nube: los alumnos, sus pagos y las entregas viven en memoria
// (`test/helpers/entrega_en_memoria.dart`), y cada cobro llega como el pulso.
//
//   flutter run -d windows -t tool/entradas_prueba.dart
//
// - PUERTO VIEJO: PÉREZ debe su mesa adicional ($ 70.000). Tocarlo dice "que pase por
//   caja"; ENTENDIDO lo deja en "En caja".
// - En la otra PC, COBRAR $ 30.000 (una parte) o COBRAR TODO: a la izquierda salta
//   "pagó una parte" o "pagó: ya podés entregar", con el sonido del sistema.
// - CORTAR INTERNET: la línea de arriba lo dice.
// - CON COBROS: Carla también tiene Cobros, y aparece PASAR A CAJA.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/currency_extensions.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';

import '../test/helpers/entrega_en_memoria.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  runApp(const _Prueba());
  unawaited(_agrandar());
}

Future<void> _agrandar() async {
  try {
    await windowManager.ensureInitialized();
    for (var i = 0; i < 50 && !await windowManager.isVisible(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await windowManager.setTitle('Prueba del mostrador de Entradas · Carla y la otra PC');
    await windowManager.maximize();
  } catch (_) {}
}

class _Prueba extends StatefulWidget {
  const _Prueba();

  @override
  State<_Prueba> createState() => _PruebaState();
}

class _PruebaState extends State<_Prueba> {
  final _e = EntregaEnMemoria();
  late ProviderContainer _c;
  bool _conCobros = false;
  int _vuelta = 0;

  @override
  void initState() {
    super.initState();
    _armar();
  }

  void _armar() {
    _c = ProviderContainer(overrides: [
      ..._e.reemplazos(),
      fiestasQueVienenProvider.overrideWith((ref) async => [fiestaDeLaEntrega]),
    ]);
    unawaited(_c.read(appRoleProvider.notifier).entrarComoEntradas(
          _e.operador(cobros: _conCobros),
          PermisosEfectivos(entradas: true, cobros: _conCobros),
        ));
  }

  void _cambiarCobros() {
    final viejo = _c;
    setState(() {
      _conCobros = !_conCobros;
      _vuelta++;
      _armar();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => viejo.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: UncontrolledProviderScope(
              key: ValueKey(_vuelta),
              container: _c,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: const _Carla(),
              ),
            ),
          ),
          const VerticalDivider(width: 6, thickness: 6, color: Colors.black),
          SizedBox(
            width: 380,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: _OtraPc(
                e: _e,
                conCobros: _conCobros,
                onCobros: _cambiarCobros,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carla: Entradas, y si pasa a la caja, una pantalla que lo dice.
class _Carla extends ConsumerWidget {
  const _Carla();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    if (app.esEntradas) return const EntradasHomeScreen();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              app.esCaja ? 'Carla pasó a la caja (acá cobraría)' : 'Fuera',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 16),
            if (app.esCaja)
              FilledButton(
                onPressed: () => ref.read(appRoleProvider.notifier).pasarAEntradas(),
                child: const Text('VOLVER A ENTRADAS'),
              ),
          ],
        ),
      ),
    );
  }
}

/// La otra PC: la caja que cobra. Cada cobro cambia la cuenta y avisa como el pulso.
class _OtraPc extends StatefulWidget {
  final EntregaEnMemoria e;
  final bool conCobros;
  final VoidCallback onCobros;

  const _OtraPc({required this.e, required this.conCobros, required this.onCobros});

  @override
  State<_OtraPc> createState() => _OtraPcState();
}

class _OtraPcState extends State<_OtraPc> {
  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final enLinea = e.conexion.currentStatus == AppConnectivity.online;
    return Scaffold(
      backgroundColor: const Color(0xFFEFF3FA),
      appBar: AppBar(title: const Text('LA OTRA PC · CAJA')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final a in e.contratos.alumnos)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.nombreAlumno, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Saldo de la ficha: ${a.saldoDeudor.toCurrency()}'),
                    if (a.saldoDeudor > 0)
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => setState(
                              () => e.cobrar(a.id, a.saldoDeudor >= 30000 ? 30000 : a.saldoDeudor),
                            ),
                            child: const Text('COBRAR \$ 30.000'),
                          ),
                          FilledButton(
                            onPressed: () => setState(() => e.cobrar(a.id, a.saldoDeudor)),
                            child: const Text('COBRAR TODO'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => setState(() => e.conexion
                .cambiar(enLinea ? AppConnectivity.offline : AppConnectivity.online)),
            child: Text(enLinea ? 'CORTAR INTERNET (en la PC de Carla)' : 'VOLVER EL INTERNET'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: widget.onCobros,
            child: Text(widget.conCobros
                ? 'CARLA SIN COBROS (empieza de nuevo)'
                : 'CARLA CON COBROS (empieza de nuevo)'),
          ),
        ],
      ),
    );
  }
}
