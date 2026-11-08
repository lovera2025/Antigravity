import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Cada cosa que escribe la caja tiene que salir a la red del salón (la central de la
/// barra): si no, las otras cajas no la ven y "Quedan" queda mal. Esto lee la interfaz de
/// la caja y el envoltorio, y falla si aparece una escritura que no avisa.
void main() {
  String leer(String ruta) => File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  test('cada escritura de la caja avisa a la red', () {
    final interfaz = leer('lib/features/barra/datos/barra_repositorio.dart');
    final caja = interfaz.substring(interfaz.indexOf('abstract interface class BarraDeLaCaja'));
    // Lo que no lee: lo que devuelve una sola cosa y no empieza con "ventas", "cajas"...
    final metodos = RegExp(r'Future<(\w+)\??> (\w+)\(').allMatches(caja).map((m) => m.group(2)!).toSet();
    const soloLeen = {'recargo', 'cajaAbierta', 'ventasSinSubir'};
    final escrituras = {
      for (final m in metodos)
        if (!soloLeen.contains(m) && !RegExp(r'^(ventas|anulaciones|vales|productos|precios|fiestas|cajas)').hasMatch(m)) m,
    };
    expect(escrituras, containsAll(['abrirCaja', 'vender', 'ponerCambio', 'anular', 'anotarVale', 'cerrarCaja', 'anotarCierre']));

    final envoltorio = leer('lib/features/barra/central/barra_con_la_red.dart');
    for (final m in escrituras) {
      final desde = envoltorio.indexOf(RegExp('> $m\\('));
      expect(desde, greaterThan(0), reason: '$m no está en BarraConLaRed');
      final hasta = envoltorio.indexOf('@override', desde);
      final cuerpo = envoltorio.substring(desde, hasta < 0 ? envoltorio.length : hasta);
      expect(cuerpo, contains('_avisar('), reason: '$m escribe y no avisa a la central');
    }
  });

  test('la barra de este equipo pasa por la red del salón', () {
    final providers = leer('lib/features/barra/providers/barra_del_jefe_provider.dart');
    expect(providers, contains('BarraConLaRed('));
    final caja = leer('lib/features/barra/providers/barra_providers.dart');
    expect(caja, contains('barraDeLaCajaProvider = Provider<BarraDeLaCaja>((ref) => ref.watch(barraDeEsteEquipoProvider))'));
  });
}
