import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/caja_sesiones/models/sesion_caja.dart';

/// Corte de día de las cajas y lectura del latido.
///
/// Con la app cerrada no corre nada, así que el autocierre es una detección
/// diferida: lo que hace que el resultado sea el mismo abra al otro día o tres
/// días después es el **sello** a las 23:59 del día al que pertenece la sesión.
void main() {
  group('ArTime.finDeDiaArUtc', () {
    test('sella a las 23:59:59 AR del día de la sesión', () {
      // 4 de agosto 18:00 AR = 4 de agosto 21:00 UTC.
      final abierta = DateTime.utc(2026, 8, 4, 21);
      final sello = ArTime.finDeDiaArUtc(abierta);
      final ar = ArTime.toAr(sello);

      expect(ar.year, 2026);
      expect(ar.month, 8);
      expect(ar.day, 4);
      expect(ar.hour, 23);
      expect(ar.minute, 59);
      expect(ar.second, 59);
    });

    test('no depende de cuándo se detecte el cambio de día', () {
      final abierta = DateTime.utc(2026, 8, 4, 21);
      // Se detecte al otro día o tres días después, el sello es el mismo.
      expect(
        ArTime.finDeDiaArUtc(abierta),
        ArTime.finDeDiaArUtc(abierta),
      );
      expect(ArTime.toAr(ArTime.finDeDiaArUtc(abierta)).day, 4);
    });

    test('una sesión abierta de madrugada AR se sella en su propio día', () {
      // 5 de agosto 00:30 AR = 5 de agosto 03:30 UTC.
      final abierta = DateTime.utc(2026, 8, 5, 3, 30);
      expect(ArTime.toAr(ArTime.finDeDiaArUtc(abierta)).day, 5);
    });

    test('arToUtc es el inverso exacto de toAr', () {
      final utc = DateTime.utc(2026, 8, 4, 21, 37, 11);
      expect(ArTime.arToUtc(ArTime.toAr(utc)), utc);
    });

    test('el cruce de medianoche UTC no adelanta el día AR', () {
      // 4 de agosto 22:00 AR = 5 de agosto 01:00 UTC: sigue siendo el día 4.
      final abierta = DateTime.utc(2026, 8, 5, 1);
      expect(ArTime.toAr(abierta).day, 4);
      expect(ArTime.toAr(ArTime.finDeDiaArUtc(abierta)).day, 4);
    });

    test('mismoDia distingue días AR, no días UTC', () {
      final hoy22hsAr = DateTime.utc(2026, 8, 5, 1); // 4/8 22:00 AR
      final hoy20hsAr = DateTime.utc(2026, 8, 4, 23); // 4/8 20:00 AR
      expect(ArTime.mismoDia(hoy22hsAr, hoy20hsAr), isTrue);
    });
  });

  group('lectura del latido', () {
    SesionCaja sesion({Duration? desde, DateTime? cerrada, String? nota}) {
      final base = DateTime.utc(2026, 8, 4, 12);
      return SesionCaja(
        id: 's1',
        operadorId: 'op1',
        abiertaAt: base,
        cerradaAt: cerrada,
        cambioInicial: 0,
        lastHeartbeat: desde == null ? base : base.add(desde),
        createdAt: base,
        updatedAt: base,
        notaCierre: nota,
      );
    }

    final ahora = DateTime.utc(2026, 8, 4, 13);

    test('latido más fresco que el período: se puede afirmar que está en uso', () {
      final s = sesion(desde: const Duration(minutes: 60) - const Duration(seconds: 40));
      expect(s.enUsoAhora(ahora: ahora), isTrue);
      expect(s.sinSenales(ahora: ahora), isFalse);
    });

    test('latido de 3 minutos NO significa "abierta en otra PC"', () {
      final s = sesion(desde: const Duration(minutes: 57));
      expect(
        s.enUsoAhora(ahora: ahora),
        isFalse,
        reason: 'el latido se publica cada 60 s: 3 min es demasiado viejo',
      );
      expect(
        s.sinSenales(ahora: ahora),
        isFalse,
        reason: 'tampoco se puede afirmar que quedó abierta: no se sabe',
      );
    });

    test('sin señales por horas: quedó abierta sin cerrar', () {
      final s = sesion(desde: const Duration(minutes: -120));
      expect(s.sinSenales(ahora: ahora), isTrue);
      expect(s.enUsoAhora(ahora: ahora), isFalse);
    });

    test('reloj del otro equipo adelantado no se lee como "del futuro"', () {
      final s = sesion(desde: const Duration(hours: 5));
      expect(s.antiguedadLatido(ahora: ahora), Duration.zero);
      expect(
        s.enUsoAhora(ahora: ahora),
        isTrue,
        reason: 'ante un reloj desfasado se peca de prudente, no de acusador',
      );
    });

    test('una sesión cerrada no está en uso ni pendiente de señales', () {
      final s = sesion(cerrada: DateTime.utc(2026, 8, 4, 23, 59, 59));
      expect(s.enUsoAhora(ahora: ahora), isFalse);
      expect(s.sinSenales(ahora: ahora), isFalse);
    });
  });

  group('clasificación del cierre', () {
    SesionCaja cerradaCon({String? nota, double? arqueo}) => SesionCaja(
      id: 's1',
      operadorId: 'op1',
      abiertaAt: DateTime.utc(2026, 8, 4, 12),
      cerradaAt: DateTime.utc(2026, 8, 4, 23, 59, 59),
      cambioInicial: 0,
      arqueoCierre: arqueo,
      notaCierre: nota,
      createdAt: DateTime.utc(2026, 8, 4, 12),
      updatedAt: DateTime.utc(2026, 8, 4, 12),
    );

    test('el cierre por cambio de día se marca como automático', () {
      expect(cerradaCon(nota: kNotaCierreCambioDiaCaja).cierreAutomatico, isTrue);
      expect(cerradaCon(nota: kNotaCierreCambioDiaJefe).cierreAutomatico, isTrue);
      expect(cerradaCon(nota: kNotaCierreTomadaOtraPc).cierreAutomatico, isTrue);
    });

    test('las notas de versiones anteriores también quedan clasificadas', () {
      expect(
        cerradaCon(nota: 'Cerrada al iniciar jornada (modo jefe)')
            .cierreAutomatico,
        isTrue,
      );
    });

    test('un cierre hecho a mano no se marca como automático', () {
      expect(
        cerradaCon(nota: 'Cerré con la plata contada', arqueo: 50000)
            .cierreAutomatico,
        isFalse,
      );
      expect(cerradaCon(nota: null, arqueo: 50000).cierreAutomatico, isFalse);
    });

    test('sinArqueo marca al que cerró sin contar la plata', () {
      expect(cerradaCon(arqueo: null).sinArqueo, isTrue);
      expect(cerradaCon(arqueo: 50000).sinArqueo, isFalse);
    });
  });
}
