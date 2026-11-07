// El latido de la caja (6.3.3: cada 5 minutos) y los dos umbrales que salen de
// él van juntos. Si se cambia uno solo, la otra PC pone en duda una caja que
// se está usando, o da por viva una que quedó abierta en una PC apagada.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/caja_sesiones/models/sesion_caja.dart';

void main() {
  test('el período, "en uso" y "sin señales" van en ese orden, con margen', () {
    expect(kLatidoSesionPeriodo, const Duration(minutes: 5));
    expect(kLatidoSesionPeriodo < kLatidoSesionVivo, isTrue);
    expect(kLatidoSesionVivo < kLatidoSesionMuerto, isTrue);
    expect(kLatidoSesionVivo > kLatidoSesionPeriodo * 2, isTrue,
        reason: 'si se pierde un latido, la caja sigue "en uso"');
    expect(kLatidoSesionMuerto >= kLatidoSesionPeriodo * 3, isTrue);
  });

  test('el latido usa el período de acá', () {
    final s = File('lib/features/caja_sesiones/providers/app_role_provider.dart')
        .readAsStringSync();
    expect(s, contains('Timer.periodic(kLatidoSesionPeriodo'));
  });

  group('lo que la otra PC dice de una caja abierta', () {
    final ahora = DateTime.utc(2026, 11, 10, 15);
    SesionCaja abiertaCon(Duration latidoHace) => SesionCaja(
          id: 'aaaaaaaa-0000-4000-8000-000000000001',
          operadorId: 'bbbbbbbb-0000-4000-8000-000000000001',
          abiertaAt: ahora.subtract(const Duration(hours: 2)),
          cambioInicial: 0,
          lastHeartbeat: ahora.subtract(latidoHace),
          createdAt: ahora.subtract(const Duration(hours: 2)),
          updatedAt: ahora.subtract(latidoHace),
        );

    test('con un latido perdido (9 minutos) sigue en uso', () {
      final s = abiertaCon(const Duration(minutes: 9));
      expect(s.enUsoAhora(ahora: ahora), isTrue);
      expect(s.sinSenales(ahora: ahora), isFalse);
    });

    test('a los 12 minutos no se sabe; a los 21, quedó abierta', () {
      expect(abiertaCon(const Duration(minutes: 12)).enUsoAhora(ahora: ahora), isFalse);
      expect(abiertaCon(const Duration(minutes: 12)).sinSenales(ahora: ahora), isFalse);
      expect(abiertaCon(const Duration(minutes: 21)).sinSenales(ahora: ahora), isTrue);
    });
  });
}
