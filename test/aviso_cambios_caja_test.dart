// Que el cierre de caja se entere en el momento de lo que cambia en la otra PC
// —sobre todo de un cobro que el jefe anuló— sin refrescar por nada.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/cierre_caja/services/aviso_cambios_caja.dart';
import 'package:arguello_events/features/cierre_caja/services/cobro_agrupado.dart';
import 'package:arguello_events/features/mi_empresa/models/ingreso_detallado.dart';

IngresoDetallado linea(
  String id, {
  String alumno = 'PEREZ, JUAN',
  String contrato = 'c-perez',
  double monto = 10000,
  DateTime? fecha,
  String medio = 'efectivo',
}) => IngresoDetallado(
  id: id,
  fuente: 'Masivo',
  fecha: fecha ?? DateTime.utc(2026, 9, 24, 14),
  monto: monto,
  concepto: 'Cuota Base (3/9)',
  alumnoOCliente: alumno,
  nombreEvento: 'Egresados',
  medioPago: medio,
  contratoAlumnoId: contrato,
);

void main() {
  group('qué tablas despiertan al cierre', () {
    test('un cobro anulado sí', () {
      expect(cambiosTocanElCierre({'pagos_contrato_alumno'}), isTrue);
      expect(cambiosTocanElCierre({'contratos_alumnos', 'egresos'}), isTrue);
    });

    test('lo que no es plata de caja no', () {
      expect(cambiosTocanElCierre({'presupuestos', 'servicios'}), isFalse);
      expect(cambiosTocanElCierre({'contratos_alumnos'}), isFalse);
      expect(cambiosTocanElCierre({}), isFalse);
    });
  });

  test('lineasQueSeFueron: solo las que estaban y ya no están', () {
    final antes = [linea('a'), linea('b'), linea('c')];
    final despues = [linea('a'), linea('c'), linea('nueva')];
    expect(lineasQueSeFueron(antes, despues).map((i) => i.id), ['b']);
    expect(lineasQueSeFueron(antes, antes), isEmpty);
  });

  group('texto del aviso', () {
    test('nada anulado, nada que decir', () {
      expect(textoAvisoAnulados([], delDia: false), isNull);
    });

    test('las líneas de un mismo cobro cuentan como un cobro', () {
      final t = DateTime.utc(2026, 9, 24, 14);
      final texto = textoAvisoAnulados([
        linea('cuota', monto: 40000, fecha: t),
        linea('mesa', monto: 10000, fecha: t.add(const Duration(milliseconds: 40))),
      ], delDia: false);
      expect(texto, startsWith('El jefe anuló 1 cobro de esta sesión: PEREZ, JUAN · '));
      expect(texto, contains('50.000'));
    });

    test('dos alumnos, vista del día', () {
      final texto = textoAvisoAnulados([
        linea('x', monto: 30000),
        linea('y', alumno: 'GOMEZ, ANA', contrato: 'c-gomez', monto: 20000),
      ], delDia: true);
      expect(texto, startsWith('El jefe anuló 2 cobros del día: '));
      expect(texto, contains('PEREZ, JUAN'));
      expect(texto, contains('GOMEZ, ANA'));
    });
  });

  group('anulado después del cierre', () {
    final cierre = DateTime.utc(2026, 9, 24, 21);
    Map<String, dynamic> anulado(double monto, String cuando,
            {String sesion = 's1', String medio = 'efectivo'}) =>
        {
          'monto': monto,
          'medio_pago': medio,
          'sesion_caja_id': sesion,
          'anulado': 1,
          'fecha_anulacion': cuando,
        };

    test('solo cuenta lo anulado después de cerrar', () {
      final r = anuladoDespuesDelCierre(
        pagosAnulados: [
          anulado(10000, '2026-09-24T20:00:00Z'), // antes: ya salió del arqueo
          anulado(15000, '2026-09-24T22:00:00Z'),
          anulado(5000, '2026-09-25T10:00:00Z', medio: 'transferencia'),
        ],
        cierrePorSesion: {'s1': cierre},
      );
      expect(r.efectivo, 15000);
      expect(r.transferencia, 5000);
      expect(r.hayAlgo, isTrue);
    });

    test('sesión abierta u otra sesión: nada', () {
      final r = anuladoDespuesDelCierre(
        pagosAnulados: [anulado(10000, '2026-09-25T10:00:00Z', sesion: 's2')],
        cierrePorSesion: {'s1': cierre},
      );
      expect(r.hayAlgo, isFalse);
    });
  });

  group('filaEsNovedad', () {
    test('fila nueva es novedad', () {
      expect(
        filaEsNovedad(existeLocal: false, versionLocal: null, versionNube: 'x'),
        isTrue,
      );
    });

    test('la misma hora escrita distinto no es novedad', () {
      expect(
        filaEsNovedad(
          existeLocal: true,
          versionLocal: '2026-09-17T14:22:33.385096+00:00',
          versionNube: '2026-09-17 14:22:33.385096+00',
        ),
        isFalse,
      );
    });

    test('la otra PC la cambió', () {
      expect(
        filaEsNovedad(
          existeLocal: true,
          versionLocal: '2026-09-17T14:22:33.385096+00:00',
          versionNube: '2026-09-24T09:00:00+00:00',
        ),
        isTrue,
      );
    });

    test('sin fecha legible compara el texto', () {
      expect(
        filaEsNovedad(existeLocal: true, versionLocal: null, versionNube: null),
        isFalse,
      );
      expect(
        filaEsNovedad(existeLocal: true, versionLocal: null, versionNube: 'algo'),
        isTrue,
      );
    });
  });

  group('esDelMismoCobro', () {
    Map<String, dynamic> p(String fecha, {String? sesion = 's1', String c = 'c1'}) => {
      'contrato_alumno_id': c,
      'sesion_caja_id': sesion,
      'fecha_pago': fecha,
    };

    test('mismo contrato, sesión y segundos', () {
      expect(
        esDelMismoCobro(p('2026-09-24T14:00:00.100Z'), p('2026-09-24T14:00:03Z')),
        isTrue,
      );
    });

    test('otro contrato, otra sesión o una hora después: no', () {
      final base = p('2026-09-24T14:00:00Z');
      expect(esDelMismoCobro(base, p('2026-09-24T14:00:00Z', c: 'c2')), isFalse);
      expect(esDelMismoCobro(base, p('2026-09-24T14:00:00Z', sesion: 's2')), isFalse);
      expect(esDelMismoCobro(base, p('2026-09-24T15:00:00Z')), isFalse);
    });

    test('sin sesión las dos: vale igual', () {
      expect(
        esDelMismoCobro(
          p('2026-06-25T21:21:14Z', sesion: null),
          p('2026-06-25T21:21:14.030Z', sesion: null),
        ),
        isTrue,
      );
    });
  });

  group('el latido de la caja no despierta a la otra PC', () {
    test('solo latido: sin pulso', () {
      expect(
        esSoloLatido('sesiones_caja', SyncOperation.update, {
          'id': 's1',
          'last_heartbeat': '2026-09-24T12:00:00Z',
          'updated_at': '2026-09-24T12:00:00Z',
        }),
        isTrue,
      );
    });

    test('latido fusionado con un cierre: con pulso', () {
      expect(
        esSoloLatido('sesiones_caja', SyncOperation.update, {
          'id': 's1',
          'last_heartbeat': '2026-09-24T12:00:00Z',
          'cerrada_at': '2026-09-24T12:00:00Z',
          'arqueo_cierre': 150000,
        }),
        isFalse,
      );
    });

    test('otra tabla u otra operación: con pulso', () {
      final p = {'id': 's1', 'last_heartbeat': 'x'};
      expect(esSoloLatido('pagos_contrato_alumno', SyncOperation.update, p), isFalse);
      expect(esSoloLatido('sesiones_caja', SyncOperation.insert, p), isFalse);
    });
  });
}
