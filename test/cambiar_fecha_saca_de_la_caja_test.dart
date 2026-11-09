// Cambiar la fecha de un cobro a otro día lo saca de la caja abierta en la que se cargó
// (regla del usuario, 7-nov-2026): esa plata no entró ese día. Pasó con ENRIQUE, MAXIMO:
// lo pagó el 23-oct, se cargó el 7-nov en la caja del modo jefe, se le puso el 23 en
// Mi Empresa y seguía en el cierre del 7.
//
// Corre contra una base SQLite **temporal** (como anular_varios_cobros_test.dart). Nunca
// toca la base de producción ni la nube.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/cierre_caja/services/fecha_y_caja.dart';
import 'package:arguello_events/features/mi_empresa/repositories/finanzas_repository.dart';

String uid(String nombre) {
  final base = nombre.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final r = base.padRight(32, '0').substring(0, 32);
  return '${r.substring(0, 8)}-${r.substring(8, 12)}-${r.substring(12, 16)}'
      '-${r.substring(16, 20)}-${r.substring(20, 32)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late FinanzasRepository repo;

  /// El sábado 7 de noviembre a las 9:30 de Argentina.
  final ahora = DateTime.utc(2026, 11, 7, 12, 30);

  /// El 23 de octubre a las 9:26 de Argentina, la hora del cobro.
  final elVeintitres = DateTime.utc(2026, 10, 23, 12, 26);

  setUp(() async {
    docs = Directory.systemTemp.createTempSync('fecha_y_caja');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    final supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
    final connectivity = ConnectivityService();
    repo = FinanzasRepository(
      supabase,
      connectivity,
      SyncEngine(connectivity: connectivity, supabase: supabase),
    );

    final db = await LocalDatabase.instance;
    // La fiesta y los alumnos: las líneas de un cobro se buscan con ellos.
    await db.insert('eventos', {
      'id': uid('evento'),
      'cliente_id': uid('cliente'),
      'tipo': 'Egresados Test',
      'fecha_evento': '2026-12-04',
      'modalidad': 'masivo',
    });
    for (final nombre in ['enrique', 'sofia']) {
      await db.insert('contratos_alumnos', {
        'id': uid(nombre),
        'evento_id': uid('evento'),
        'nombre_alumno': 'TEST ${nombre.toUpperCase()}',
        'monto_total_pactado': 360000,
        'saldo_deudor': 300000,
        'cuotas_pagadas': 1,
        'total_cuotas': 9,
        'mora_pendiente_tracked': 0,
        'mora_cobrada_offset': 0,
        'created_at': DateTime.utc(2026, 3, 30, 12).toIso8601String(),
      });
    }
    for (final (op, pin) in [('jefe', '0000'), ('marta', '1111')]) {
      await db.insert('operadores_caja', {
        'id': uid(op),
        'nombre': op,
        'pin': pin,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
    }
    // La base no deja dos cajas abiertas del mismo operador.
    Future<void> caja(String id, String abierta, {String? cerrada, String operador = 'jefe'}) =>
        db.insert('sesiones_caja', {
          'id': uid(id),
          'operador_id': uid(operador),
          'abierta_at': abierta,
          'cerrada_at': cerrada,
          'created_at': abierta,
          'updated_at': cerrada ?? abierta,
        });
    // La del modo jefe de hoy, abierta desde las 9:26.
    await caja('hoy', '2026-11-07T12:26:14Z');
    // La de anoche: abrió el 6 a las 22:00 y cerró el 7 a las 2:00.
    await caja('anoche', '2026-11-07T01:00:00Z', cerrada: '2026-11-07T05:00:00Z');
    // Una abierta anoche a las 22:00 que sigue abierta (la fiesta no terminó).
    await caja('noche', '2026-11-07T01:00:00Z', operador: 'marta');

    Future<void> pago(String id, String sesion, String fecha) => db.insert('pagos_contrato_alumno', {
          'id': uid(id),
          'contrato_alumno_id': uid('enrique'),
          'monto': 50000,
          'monto_gross': 50000,
          'concepto': 'Entrega parcial — Cuota Base (1/1)',
          'fecha_pago': fecha,
          'created_at': fecha,
          'medio_pago': 'efectivo',
          'anulado': 0,
          'sesion_caja_id': sesion.isEmpty ? null : uid(sesion),
        });
    await pago('enrique', 'hoy', '2026-11-07T12:26:16Z');
    await pago('cerrado', 'anoche', '2026-11-07T03:10:00Z');
    await pago('madrugada', 'noche', '2026-11-07T04:30:00Z');
    await pago('sincaja', '', '2026-11-07T12:00:00Z');

    // Un cobro de plan con mora de SOFÍA: la cuota y el interés, en el mismo segundo;
    // y otro cobro suyo, una hora después, que no es el mismo.
    Future<void> linea(String id, String concepto, String fecha) => db.insert('pagos_contrato_alumno', {
          'id': uid(id),
          'contrato_alumno_id': uid('sofia'),
          'monto': 20000,
          'monto_gross': 20000,
          'concepto': concepto,
          'fecha_pago': fecha,
          'created_at': fecha,
          'medio_pago': 'efectivo',
          'anulado': 0,
          'sesion_caja_id': uid('hoy'),
        });
    await linea('sofia-cuota', 'Cuota Base (3/9)', '2026-11-07T12:40:00.100Z');
    await linea('sofia-mora', 'Interés mora cuota 3 (vto Oct 2026)', '2026-11-07T12:40:00.300Z');
    await linea('sofia-otro', 'Cuota Base (4/9)', '2026-11-07T13:40:00Z');
  });

  tearDown(() async {
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> fila(String id) async {
    final db = await LocalDatabase.instance;
    return (await db.query('pagos_contrato_alumno', where: 'id = ?', whereArgs: [uid(id)])).first;
  }

  Future<Map<String, dynamic>> lo(String id) async {
    final db = await LocalDatabase.instance;
    final cola = await db.query('_sync_queue', where: 'registro_id = ?', whereArgs: [uid(id)]);
    return jsonDecode(cola.single['payload'] as String) as Map<String, dynamic>;
  }

  test('ENRIQUE: pasarlo al 23-oct lo saca de la caja abierta de hoy, y sube así', () async {
    final r = await repo.actualizarFechaPagoRegistro(
      tabla: 'pagos_contrato_alumno',
      id: uid('enrique'),
      nuevaFecha: elVeintitres,
      reloj: () => ahora,
    );
    expect(r.caja, CajaTrasCambioDeFecha.salioDeLaCaja);
    final f = await fila('enrique');
    expect(f['sesion_caja_id'], isNull);
    expect(f['fecha_pago'], elVeintitres.toIso8601String());
    final subida = await lo('enrique');
    expect(subida.containsKey('sesion_caja_id'), isTrue, reason: 'la caja vacía tiene que llegar a la nube');
    expect(subida['sesion_caja_id'], isNull);
    expect(subida['fecha_pago'], elVeintitres.toIso8601String());
  });

  test('cambiarle la hora, el mismo día, lo deja en su caja', () async {
    final r = await repo.actualizarFechaPagoRegistro(
      tabla: 'pagos_contrato_alumno',
      id: uid('enrique'),
      nuevaFecha: DateTime.utc(2026, 11, 7, 20),
      reloj: () => ahora,
    );
    expect(r.caja, CajaTrasCambioDeFecha.igual);
    expect((await fila('enrique'))['sesion_caja_id'], uid('hoy'));
    expect((await lo('enrique')).containsKey('sesion_caja_id'), isFalse);
  });

  test('una caja abierta a la noche sigue hasta la madrugada: el día de antes es suyo', () async {
    final r = await repo.actualizarFechaPagoRegistro(
      tabla: 'pagos_contrato_alumno',
      id: uid('madrugada'),
      nuevaFecha: DateTime.utc(2026, 11, 7, 2), // el 6 a las 23:00
      reloj: () => ahora,
    );
    expect(r.caja, CajaTrasCambioDeFecha.igual);
    expect((await fila('madrugada'))['sesion_caja_id'], uid('noche'));
  });

  test('una caja ya cerrada no se toca: el arqueo se hizo con esa plata', () async {
    final r = await repo.actualizarFechaPagoRegistro(
      tabla: 'pagos_contrato_alumno',
      id: uid('cerrado'),
      nuevaFecha: elVeintitres,
      reloj: () => ahora,
    );
    expect(r.caja, CajaTrasCambioDeFecha.quedaEnCajaCerrada);
    final f = await fila('cerrado');
    expect(f['sesion_caja_id'], uid('anoche'));
    expect(f['fecha_pago'], elVeintitres.toIso8601String(), reason: 'la fecha igual cambia');
  });

  test('un cobro sin caja solo cambia de fecha', () async {
    final r = await repo.actualizarFechaPagoRegistro(
      tabla: 'pagos_contrato_alumno',
      id: uid('sincaja'),
      nuevaFecha: elVeintitres,
      reloj: () => ahora,
    );
    expect(r.caja, CajaTrasCambioDeFecha.igual);
    expect((await fila('sincaja'))['fecha_pago'], elVeintitres.toIso8601String());
  });

  test('todo el cobro junto: la cuota y su mora cambian de fecha y salen de la caja, '
      'el otro cobro no', () async {
    final r = await repo.actualizarFechaPagoRegistro(
      tabla: 'pagos_contrato_alumno',
      id: uid('sofia-cuota'),
      nuevaFecha: elVeintitres,
      reloj: () => ahora,
    );
    expect(r.caja, CajaTrasCambioDeFecha.salioDeLaCaja);
    expect(r.lineas, 2);
    expect(r.contratoId, uid('sofia'), reason: 'para revisarle la mora en el momento');
    for (final l in ['sofia-cuota', 'sofia-mora']) {
      final f = await fila(l);
      expect(f['fecha_pago'], elVeintitres.toIso8601String(), reason: l);
      expect(f['sesion_caja_id'], isNull, reason: l);
      expect((await lo(l))['sesion_caja_id'], isNull, reason: '$l sube sin caja');
    }
    final otro = await fila('sofia-otro');
    expect(otro['fecha_pago'], '2026-11-07T13:40:00Z');
    expect(otro['sesion_caja_id'], uid('hoy'));
  });

  test('el diálogo revisa la mora del alumno en el momento y no deja fechas futuras', () {
    final dialogo = File('lib/features/mi_empresa/widgets/corregir_medio_pago_dialog.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(dialogo, contains('revisarMora(soloContratos: {contrato})'));
    expect(dialogo, contains('lastDate: hoy,'));
    expect(dialogo, contains('if (fecha != null && _unSoloCobro)'));
    // La fecha elegida es de la línea tildada: si se tilda otro cobro, se borra.
    expect(dialogo, contains('!ids.contains(_fechaPara)'));
    // Anular cobro por error, lo mismo: la mora de los que tocó, en el momento.
    final anular = File('lib/features/mi_empresa/widgets/anular_cobro_cuota_dialog.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(anular, contains('revisarMora(soloContratos: contratos)'));
  });

  group('los días de una caja, en hora de Argentina', () {
    test('de la apertura al cierre, o hasta ahora', () {
      final abierta = DateTime.utc(2026, 11, 7, 1); // el 6 a las 22:00
      bool es(DateTime d, {DateTime? cerrada}) =>
          diaEsDeLaCaja(dia: d, abiertaAt: abierta, cerradaAt: cerrada, ahora: ahora);
      expect(es(DateTime.utc(2026, 11, 6, 15)), isTrue, reason: 'el 6 a la tarde');
      expect(es(DateTime.utc(2026, 11, 7, 15)), isTrue, reason: 'el 7, sigue abierta');
      expect(es(DateTime.utc(2026, 11, 5, 15)), isFalse);
      expect(es(DateTime.utc(2026, 11, 7, 15), cerrada: DateTime.utc(2026, 11, 7, 2)), isFalse,
          reason: 'cerró el 6 a las 23:00');
    });
  });
}
