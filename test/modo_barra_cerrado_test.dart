import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Quien entra a la Barra ve la barra: no hay camino al panel, a la caja de cuotas ni
/// a un alumno. Las pantallas se leen, como en `modo_entradas_cerrado_test.dart`: lo
/// que se cuida es que nadie agregue el camino.
void main() {
  String leer(String ruta) => File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  const pantallas = [
    'lib/features/barra/widgets/barra_home_screen.dart',
    'lib/features/barra/widgets/vender_screen.dart',
    'lib/features/barra/widgets/cobrar_hoja.dart',
    'lib/features/barra/widgets/elegir_vales.dart',
    'lib/features/barra/widgets/abrir_caja_barra_dialog.dart',
  ];

  test('las pantallas de la barra no llevan al panel, a la fiesta ni a cobrar cuotas', () {
    for (final ruta in pantallas) {
      final fuente = leer(ruta);
      for (final prohibido in [
        'dashboard_screen',
        'DashboardScreen',
        'detalle_evento_masivo',
        'DetalleEventoMasivo',
        'operadores_caja_screen',
        'cierre_caja',
        'registrarPago',
        'sesionCajaIdParaCobro',
        'mostrarModalPago',
        'contratosRepositoryProvider',
        'sesionesCajaRepositoryProvider',
      ]) {
        expect(fuente, isNot(contains(prohibido)), reason: '$ruta: $prohibido');
      }
    }
  });

  test('entrar a la Barra no abre ni mira la caja de cuotas, y apaga el modo jefe', () {
    final rol = leer('lib/features/caja_sesiones/providers/app_role_provider.dart');
    final i = rol.indexOf('Future<void> entrarComoBarra(');
    final cuerpo = rol.substring(i, rol.indexOf('\n  }\n', i));
    expect(cuerpo, contains('adminAuthProvider.notifier).logout()'));
    expect(cuerpo, isNot(contains('sesRepo')));
    expect(cuerpo, isNot(contains('_startHeartbeat')));
  });

  test('cobrar cuotas exige caja o jefe: la Barra no entra en ninguno', () {
    final rol = leer('lib/features/caja_sesiones/providers/app_role_provider.dart');
    final i = rol.indexOf('Future<String> sesionCajaIdParaCobro()');
    final cuerpo = rol.substring(i, rol.indexOf('\n  }\n', i));
    expect(cuerpo, isNot(contains('esBarra')));
  });

  test('la Barra va a su pantalla, antes que nada', () {
    final rol = leer('lib/features/caja_sesiones/providers/app_role_provider.dart');
    final i = rol.indexOf('DestinoDeEntrada destinoDeEntrada(');
    final cuerpo = rol.substring(i, rol.indexOf('\n}\n', i));
    final lineas = cuerpo.split('\n').where((l) => l.trim().startsWith('if (')).toList();
    expect(lineas.first.trim(), 'if (app.esBarra) return DestinoDeEntrada.barra;');
  });

  test('vender guarda la venta antes de imprimir: sin impresora, igual queda', () {
    final v = leer('lib/features/barra/widgets/vender_screen.dart');
    final guardar = v.indexOf('Future<void> _guardar(CobroBarra cobro)');
    final cuerpo = v.substring(guardar, v.indexOf('\n  }\n', guardar));
    expect(cuerpo.indexOf('.vender('), lessThan(cuerpo.indexOf('_ValesDeLaVenta(')));
    expect(cuerpo, isNot(contains('imprimir')), reason: 'los vales se imprimen después, en su pantalla');
  });
}
