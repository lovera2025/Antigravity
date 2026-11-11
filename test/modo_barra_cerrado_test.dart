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
    'lib/features/barra/widgets/vales_de_la_venta_screen.dart',
    'lib/features/barra/widgets/ventas_de_la_caja_screen.dart',
    'lib/features/barra/widgets/cerrar_caja_barra_screen.dart',
    // 6.4.0: LAS CAJAS de la encargada (y la vista del jefe que lleva adentro) y la
    // impresora, que se abre desde el inicio de la barra.
    'lib/features/barra/widgets/las_cajas_screen.dart',
    'lib/features/barra/jefe/cajas_de_la_fiesta.dart',
    'lib/features/barra/widgets/elegir_impresora_screen.dart',
    // 6.5.0: el inicio de la barra en la web (la encargada, desde un iPhone).
    'lib/features/barra/widgets/barra_home_web.dart',
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
    expect(cuerpo.indexOf('.vender('), lessThan(cuerpo.indexOf('ValesDeLaVentaScreen(')));
    expect(cuerpo, isNot(contains('imprimir')), reason: 'los vales se imprimen después, en su pantalla');
  });

  test('contar a ciegas: antes de cerrar, la pantalla no muestra ninguna plata de la caja', () {
    final c = leer('lib/features/barra/widgets/cerrar_caja_barra_screen.dart');
    final i = c.indexOf('Widget _contar() {');
    final contar = c.substring(i, c.indexOf('\n  }\n', i));
    for (final prohibido in ['efectivoEsperado', '_cuentas', 'pesos(', '_ventas', 'PapelEnPantalla']) {
      expect(contar, isNot(contains(prohibido)), reason: 'el paso de contar muestra $prohibido');
    }
  });

  // 11-nov-2026: la caja se cierra cuando la encargada acepta. Mientras espera, la
  // cajera sigue a ciegas: los totales los ve solo la encargada, con su PIN.
  test('esperando el OK de la encargada, la pantalla tampoco muestra ninguna plata de la caja', () {
    final c = leer('lib/features/barra/widgets/cerrar_caja_barra_screen.dart');
    final i = c.indexOf('Widget _esperar(PasoDelCierre pedido) {');
    expect(i, greaterThan(0));
    final esperar = c.substring(i, c.indexOf('\n  }\n', i));
    for (final prohibido in [
      'efectivoEsperado',
      'efectivoContado',
      '_cuentas',
      'pesos(',
      '_ventas',
      'PapelEnPantalla',
    ]) {
      expect(esperar, isNot(contains(prohibido)), reason: 'la espera muestra $prohibido');
    }
  });

  test('los totales del cierre los ve solo quien manda en la barra, y la caja la cierra su equipo', () {
    final ok = leer('lib/features/barra/widgets/ok_del_cierre.dart');
    // El aviso no le aparece a una cajera común, y aceptar pregunta de nuevo.
    expect('mandaEnLaBarraProvider'.allMatches(ok).length, greaterThanOrEqualTo(2));
    // El aparato de la encargada solo agrega su respuesta: nunca cierra la caja de otra.
    expect(ok, isNot(contains('cerrarCaja(')));
    expect(ok, isNot(contains("'barra_cajas'")));
    // En la tablet de la cajera, el PIN tiene que ser de una encargada.
    final c = leer('lib/features/barra/widgets/cerrar_caja_barra_screen.dart');
    final i = c.indexOf('Future<void> _laEncargadaEstaAca() async {');
    final cuerpo = c.substring(i, c.indexOf('\n  }\n', i));
    expect(cuerpo.indexOf('permisos.encargadaBarra'), greaterThan(0));
    expect(cuerpo.indexOf('permisos.encargadaBarra'), lessThan(cuerpo.indexOf('mostrarOkDelCierre(')));
  });

  test('VENTAS ve solo las ventas de su caja, y anula desde la caja (no con lo del jefe)', () {
    final v = leer('lib/features/barra/widgets/ventas_de_la_caja_screen.dart');
    expect(v, contains('ventasDeLaCaja(widget.caja.id)'));
    expect(v, isNot(contains('.ventas(')), reason: 'las de la fiesta son de todas las cajas');
    expect(v, isNot(contains('barraDelJefeProvider')));
  });
}
