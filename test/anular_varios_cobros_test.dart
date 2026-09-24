// Anular y corregir varios cobros a la vez: todos o ninguno.
//
// Corre contra una base SQLite **temporal** (se redirige el directorio de
// documentos, igual que registrar_pagos_lote_test.dart). Nunca toca la base de
// producción ni la nube.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
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
  const motivo = 'se cobró dos veces por error';

  setUp(() async {
    docs = Directory.systemTemp.createTempSync('anular_varios');
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
    await db.insert('eventos', {
      'id': uid('evento'),
      'cliente_id': uid('cliente'),
      'tipo': 'Egresados Test',
      'fecha_evento': '2026-12-05',
      'modalidad': 'masivo',
    });
    for (final nombre in ['ana', 'beto']) {
      await db.insert('contratos_alumnos', {
        'id': uid(nombre),
        'evento_id': uid('evento'),
        'nombre_alumno': 'TEST ${nombre.toUpperCase()}',
        'monto_total_pactado': 360000,
        'saldo_deudor': 300000,
        'cuotas_pagadas': 1,
        'total_cuotas': 9,
        'mora_pendiente_tracked': 0,
        'mora_cobrada_offset': 1200,
        'created_at': DateTime.utc(2026, 3, 30, 12).toIso8601String(),
      });
    }
    Future<void> pago(
      String id,
      String contrato,
      String concepto,
      double monto,
      String fecha, {
      String? lineKind,
      String sesion = 'ses-1',
    }) => db.insert('pagos_contrato_alumno', {
      'id': uid(id),
      'contrato_alumno_id': uid(contrato),
      'monto': monto,
      'monto_gross': monto,
      'concepto': concepto,
      'fecha_pago': fecha,
      'created_at': fecha,
      'medio_pago': 'efectivo',
      'anulado': 0,
      'sesion_caja_id': uid(sesion),
      'line_kind': ?lineKind,
    });
    // Un cobro de ANA: cuota, mesa e interés de mora, en el mismo segundo.
    await pago('ana-cuota', 'ana', 'Cuota Base (2/9)', 40000, '2026-09-20T14:00:00.100Z');
    await pago('ana-mesa', 'ana', 'Mesa Extra (2/7)', 10000, '2026-09-20T14:00:00.200Z');
    await pago(
      'ana-mora',
      'ana',
      'Interés mora cuota 2 (vto Ago 2026)',
      1200,
      '2026-09-20T14:00:00.300Z',
      lineKind: 'interes_mora',
    );
    // Otro cobro de ANA, una hora después: no es el mismo.
    await pago('ana-tarde', 'ana', 'Cuota Base (3/9)', 40000, '2026-09-20T15:00:00Z');
    // Otro alumno.
    await pago('beto-cuota', 'beto', 'Cuota Base (2/9)', 40000, '2026-09-20T14:00:00.150Z');
  });

  tearDown(() async {
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> fila(String id) async {
    final db = await LocalDatabase.instance;
    return (await db.query(
      'pagos_contrato_alumno',
      where: 'id = ?',
      whereArgs: [uid(id)],
    )).first;
  }

  Future<List<Map<String, Object?>>> cola() async {
    final db = await LocalDatabase.instance;
    return db.query('_sync_queue', orderBy: 'id');
  }

  ({String tabla, String id}) p(String id) =>
      (tabla: 'pagos_contrato_alumno', id: uid(id));

  test('anula varios de distintos alumnos en una vez', () async {
    final contratos = await repo.anularPagosConMotivo(
      [p('ana-cuota'), p('ana-mesa'), p('beto-cuota')],
      motivo,
    );

    expect(contratos, {uid('ana'), uid('beto')});
    for (final id in ['ana-cuota', 'ana-mesa', 'beto-cuota']) {
      final f = await fila(id);
      expect(f['anulado'], 1, reason: id);
      expect(f['motivo_anulacion'], motivo);
      expect(f['fecha_anulacion'], isNotNull);
    }
    expect((await fila('ana-tarde'))['anulado'], 0);

    final encolados = await cola();
    expect(
      encolados.map((e) => e['registro_id']).toSet(),
      {uid('ana-cuota'), uid('ana-mesa'), uid('beto-cuota')},
      reason: 'sin mora anulada, el contrato no se encola acá',
    );
  });

  test('si uno ya estaba anulado no se anula ninguno', () async {
    await repo.anularPagosConMotivo([p('beto-cuota')], motivo);
    final colaAntes = await cola();

    await expectLater(
      repo.anularPagosConMotivo([p('ana-cuota'), p('beto-cuota')], motivo),
      throwsA(isA<StateError>()),
    );

    expect((await fila('ana-cuota'))['anulado'], 0);
    expect(await cola(), colaAntes);
  });

  test('si uno no existe no se anula ninguno', () async {
    await expectLater(
      repo.anularPagosConMotivo([p('ana-cuota'), p('no-existe')], motivo),
      throwsA(isA<StateError>()),
    );
    expect((await fila('ana-cuota'))['anulado'], 0);
    expect(await cola(), isEmpty);
  });

  test('motivo corto: no toca nada', () async {
    await expectLater(
      repo.anularPagosConMotivo([p('ana-cuota')], 'corto'),
      throwsA(isA<ArgumentError>()),
    );
    expect((await fila('ana-cuota'))['anulado'], 0);
    expect(await cola(), isEmpty);
  });

  test('con interés de mora, el tracked del contrato se recalcula y se encola una vez',
      () async {
    await repo.anularPagosConMotivo(
      [p('ana-cuota'), p('ana-mesa'), p('ana-mora')],
      motivo,
    );
    final encolados = await cola();
    final delContrato = encolados
        .where((e) => e['tabla'] == 'contratos_alumnos')
        .toList();
    expect(delContrato, hasLength(1));
    final payload =
        jsonDecode(delContrato.single['payload'] as String) as Map;
    expect(payload.keys, containsAll(['mora_pendiente_tracked', 'mora_cobrada_offset']));
  });

  test('de a uno sigue funcionando igual que antes', () async {
    final cid = await repo.anularPagoConMotivo(
      tabla: 'pagos_contrato_alumno',
      id: uid('ana-cuota'),
      motivo: motivo,
    );
    expect(cid, uid('ana'));
    expect((await fila('ana-cuota'))['anulado'], 1);
    await expectLater(
      repo.anularPagoConMotivo(
        tabla: 'pagos_contrato_alumno',
        id: uid('ana-cuota'),
        motivo: motivo,
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'Este cobro ya fue anulado.'),
      ),
    );
  });

  test('las otras líneas del mismo cobro: mismo contrato, sesión y segundos', () async {
    final hermanas = await repo.lineasDelMismoCobro(uid('ana-cuota'));
    expect(
      hermanas.map((h) => h['id']).toSet(),
      {uid('ana-mesa'), uid('ana-mora')},
    );
    expect(hermanas.first['titulo'], 'TEST ANA');
  });

  test('las líneas ya anuladas no se ofrecen', () async {
    await repo.anularPagosConMotivo([p('ana-mora')], motivo);
    final hermanas = await repo.lineasDelMismoCobro(uid('ana-cuota'));
    expect(hermanas.map((h) => h['id']).toSet(), {uid('ana-mesa')});
  });

  test('corregir el medio de varios: todos o ninguno', () async {
    await repo.corregirMedioPagoVarios(
      [p('ana-cuota'), p('beto-cuota')],
      'Transferencia',
    );
    expect((await fila('ana-cuota'))['medio_pago'], 'transferencia');
    expect((await fila('beto-cuota'))['medio_pago'], 'transferencia');

    await repo.anularPagosConMotivo([p('ana-mesa')], motivo);
    final colaAntes = await cola();
    await expectLater(
      repo.corregirMedioPagoVarios([p('ana-tarde'), p('ana-mesa')], 'transferencia'),
      throwsA(isA<StateError>()),
    );
    expect((await fila('ana-tarde'))['medio_pago'], 'efectivo');
    expect(await cola(), colaAntes);
  });
}
