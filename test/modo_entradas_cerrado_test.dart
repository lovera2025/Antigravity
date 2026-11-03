import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Quien entra solo a Entradas ve Entradas: no hay camino al panel, al cobro ni a
/// editar un alumno. La pantalla lee el archivo, igual que
/// `solo_modo_jefe_test.dart`: lo que se cuida es que nadie agregue el camino.
void main() {
  String leer(String ruta) => File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  const pantalla = 'lib/features/entradas/entradas_home_screen.dart';

  test('la pantalla no lleva al panel ni a la pantalla de la fiesta', () {
    final fuente = leer(pantalla);
    for (final prohibido in [
      'dashboard_screen',
      'DashboardScreen',
      'detalle_evento_masivo',
      'DetalleEventoMasivo',
      'operadores_caja_screen',
      'cierre_caja',
    ]) {
      expect(fuente, isNot(contains(prohibido)), reason: prohibido);
    }
  });

  test('cobrar y editar al alumno, desde acá, solo dicen qué hacer', () {
    final fuente = leer(pantalla);
    for (final prohibido in [
      'registrarPago',
      'sesionCajaIdParaCobro',
      'modal_alumno_premium',
      'mostrarModalPago',
      'contratosRepositoryProvider',
    ]) {
      expect(fuente, isNot(contains(prohibido)), reason: prohibido);
    }
    final i = fuente.indexOf('onCobrar:');
    final f = fuente.indexOf('),\n      ),\n    );', i);
    final callbacks = fuente.substring(i, f);
    expect(callbacks, contains('_decir(context, _queCobre(ref, a))'));
    expect(RegExp(r'onEditarAlumno: \(a\) => _decir\(').hasMatch(callbacks), isTrue);
  });

  test('cobrar exige caja o jefe: Entradas no entra en ninguno de los dos', () {
    final rol = leer('lib/features/caja_sesiones/providers/app_role_provider.dart');
    final i = rol.indexOf('Future<String> sesionCajaIdParaCobro()');
    final cuerpo = rol.substring(i, rol.indexOf('\n  }\n', i));
    expect(cuerpo, contains('if (state.esCaja) {'));
    expect(cuerpo, contains('if (state.esJefe) {'));
    expect(cuerpo, isNot(contains('esEntradas')));
    expect(cuerpo, contains('throw const SinCajaAbiertaException('));
  });

  test('el modo jefe se apaga al entrar a Entradas', () {
    final rol = leer('lib/features/caja_sesiones/providers/app_role_provider.dart');
    final i = rol.indexOf('Future<void> entrarComoEntradas(');
    final cuerpo = rol.substring(i, rol.indexOf('\n  }\n', i));
    expect(cuerpo, contains('adminAuthProvider.notifier).logout()'));
    expect(cuerpo, isNot(contains('sesRepo')), reason: 'no abre ni mira cajas');
    expect(cuerpo, isNot(contains('_startHeartbeat')));
  });
}
