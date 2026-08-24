// El cobro masivo se guarda entero o no se guarda.
//
// Antes el modal hacía un `registrarPago` por línea —cada uno con su propia
// transacción— y después los `actualizarContrato` de mesas y mora. Si algo
// fallaba en el medio quedaban líneas persistidas, el modal decía "Reintentá" y
// el reintento las volvía a insertar: no hay deduplicación en ninguna parte y
// `recalcularProgresoContrato` recalcula el saldo desde los pagos, así que el
// alumno terminaba figurando como que pagó el doble.
//
// Estos tests corren contra una base SQLite **temporal**: se redirige el
// directorio de documentos a un temporal, así que `LocalDatabase` crea una
// data.db vacía ahí. Nunca se toca la base de producción.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';

/// Id con forma de UUID a partir de un nombre legible.
///
/// `SyncQueue.enqueue` descarta cualquier id que no mida 36 caracteres. Con
/// nombres sueltos la cola quedaba vacía y su comparación no probaba nada: los
/// tests pasaban sin haber mirado una sola fila de `_sync_queue`.
String uid(String nombre) {
  final base = nombre.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final r = base.padRight(32, '0').substring(0, 32);
  return '${r.substring(0, 8)}-${r.substring(8, 12)}-${r.substring(12, 16)}'
      '-${r.substring(16, 20)}-${r.substring(20, 32)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late ContratosRepository repo;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('lote_cobro');
    // `LocalDatabase.dbPath` cuelga de getApplicationDocumentsDirectory: al
    // redirigirlo, la base que se abre es una nueva y vacía en el temporal.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    repo = ContratosRepository(
      SupabaseClient('http://localhost:1', 'anon-de-test'),
      ConnectivityService(),
    );
  });

  tearDown(() async {
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<void> sembrarContrato(
    String nombre, {
    double pactado = 360000,
    double saldo = 360000,
    int cuotasPagadas = 0,
    double mesaPrecio = 0,
    double tracked = 0,
    double offset = 0,
  }) async {
    final db = await LocalDatabase.instance;
    await db.insert('contratos_alumnos', {
      'id': uid(nombre),
      'evento_id': 'evt-lote',
      'nombre_alumno': 'TEST $nombre',
      'monto_total_pactado': pactado,
      'saldo_deudor': saldo,
      'cuotas_pagadas': cuotasPagadas,
      'total_cuotas': 9,
      'mesa_extra_precio': mesaPrecio,
      'mesa_extra_cuotas': 1,
      'mora_pendiente_tracked': tracked,
      'mora_cobrada_offset': offset,
      'created_at': DateTime.utc(2026, 3, 30, 12).toIso8601String(),
    });
  }

  /// Estado final comparable: el contrato, sus pagos y lo que quedó encolado.
  ///
  /// Se sacan las columnas que por definición difieren entre dos corridas (ids
  /// generados y sellos de tiempo); lo que queda es lo que tiene que coincidir.
  Future<Map<String, Object?>> estadoFinal(String nombre) async {
    final db = await LocalDatabase.instance;
    final contratoId = uid(nombre);

    final contrato = Map<String, Object?>.from(
      (await db.query(
        'contratos_alumnos',
        where: 'id = ?',
        whereArgs: [contratoId],
      )).first,
    )
      ..remove('id')
      ..remove('nombre_alumno');

    final pagos =
        (await db.query(
              'pagos_contrato_alumno',
              where: 'contrato_alumno_id = ?',
              whereArgs: [contratoId],
              orderBy: 'concepto, monto',
            ))
            .map(
              (p) => Map<String, Object?>.from(p)
                ..remove('id')
                ..remove('contrato_alumno_id')
                ..remove('fecha_pago')
                ..remove('created_at')
                ..remove('updated_at'),
            )
            .toList();

    final colaContrato = await db.query(
      '_sync_queue',
      where: 'tabla = ? AND registro_id = ?',
      whereArgs: ['contratos_alumnos', contratoId],
    );
    Map<String, dynamic>? payloadContrato;
    if (colaContrato.isNotEmpty) {
      payloadContrato =
          jsonDecode(colaContrato.first['payload'] as String)
              as Map<String, dynamic>;
      payloadContrato.remove('id');
    }

    final idsPagos = (await db.query(
      'pagos_contrato_alumno',
      columns: ['id'],
      where: 'contrato_alumno_id = ?',
      whereArgs: [contratoId],
    )).map((r) => r['id'] as String).toSet();
    final colaPagos = (await db.query(
      '_sync_queue',
      where: 'tabla = ?',
      whereArgs: ['pagos_contrato_alumno'],
    )).where((r) => idsPagos.contains(r['registro_id'] as String)).length;

    return {
      'contrato': contrato,
      'pagos': pagos,
      'colaContrato': payloadContrato,
      'colaPagos': colaPagos,
    };
  }

  /// Lo que hacía el modal antes del lote: una transacción por línea, después
  /// el patch del contrato, y recién al final el recálculo.
  Future<void> caminoViejo(
    String nombre,
    List<PagoLoteLinea> lineas,
    Map<String, dynamic> patch,
    String? sesionCajaId,
  ) async {
    final contratoId = uid(nombre);
    for (final l in lineas) {
      await repo.registrarPago(
        contratoId: contratoId,
        monto: l.monto,
        concepto: l.concepto,
        montoADescontarDeSaldo: l.montoADescontarDeSaldo,
        descuentoPorcentaje: l.descuentoPorcentaje,
        cuotasLiquidadas: l.cuotasLiquidadas,
        medioPago: l.medioPago,
        lineKind: l.lineKind,
        moraPendienteAntesDeLote: l.moraPendienteAntesDeLote,
        sesionCajaId: sesionCajaId,
      );
    }
    if (patch.isNotEmpty) await repo.actualizarContrato(contratoId, patch);
    await repo.recalcularProgresoContrato(contratoId);
  }

  /// Un cobro realista: dos cuotas base, la mesa extra y el interés de mora.
  List<PagoLoteLinea> cobroCompleto({String medio = 'Efectivo'}) => [
    PagoLoteLinea(
      monto: 80000,
      concepto: 'Cuota Base',
      montoADescontarDeSaldo: 80000,
      cuotasLiquidadas: 2,
      medioPago: medio,
    ),
    PagoLoteLinea(
      monto: 70000,
      concepto: 'Mesa Extra',
      montoADescontarDeSaldo: 70000,
      cuotasLiquidadas: 1,
      medioPago: medio,
    ),
    PagoLoteLinea(
      monto: 8700,
      concepto: 'Interés mora cuota 1',
      montoADescontarDeSaldo: 0,
      cuotasLiquidadas: 0,
      medioPago: medio,
      lineKind: kLineKindInteresMora,
      moraPendienteAntesDeLote: 8700,
    ),
  ];

  const patchMora = {
    'mora_pendiente_tracked': 0.0,
    'mora_cobrada_offset': 8700.0,
    'mora_exencion_reinicia': 0,
  };

  group('registrarPagosLote deja el mismo estado que el camino viejo', () {
    test('cobro de cuotas + mesa + mora, en efectivo', () async {
      await sembrarContrato('VIEJO', mesaPrecio: 70000, tracked: 8700);
      await sembrarContrato('LOTE', mesaPrecio: 70000, tracked: 8700);

      await caminoViejo('VIEJO', cobroCompleto(), patchMora, 'sesion-1');
      await repo.registrarPagosLote(
        contratoId: uid('LOTE'),
        lineas: cobroCompleto(),
        contratoPatch: patchMora,
        sesionCajaId: 'sesion-1',
      );

      final viejo = await estadoFinal('VIEJO');
      // Guarda del arnés: si la cola no se llenó, la comparación de abajo no
      // estaría mirando nada.
      expect(viejo['colaContrato'], isNotNull);
      expect(viejo['colaPagos'], 3);
      expect(await estadoFinal('LOTE'), viejo);
    });

    test('cobro mixto: efectivo, transferencia y cargo de canal', () async {
      final lineas = [
        const PagoLoteLinea(
          monto: 50000,
          concepto: 'Cuota Base',
          montoADescontarDeSaldo: 50000,
          cuotasLiquidadas: 1,
          medioPago: 'Efectivo',
        ),
        const PagoLoteLinea(
          monto: 30000,
          concepto: 'Cuota Base',
          montoADescontarDeSaldo: 30000,
          cuotasLiquidadas: 1,
          medioPago: 'Transferencia',
        ),
        const PagoLoteLinea(
          monto: 1200,
          concepto: 'Costo por transferencia',
          montoADescontarDeSaldo: 0,
          cuotasLiquidadas: 0,
          medioPago: 'Transferencia',
          lineKind: kLineKindCargoCanal,
        ),
      ];
      await sembrarContrato('VIEJO');
      await sembrarContrato('LOTE');

      await caminoViejo('VIEJO', lineas, const {}, 'sesion-mixta');
      await repo.registrarPagosLote(
        contratoId: uid('LOTE'),
        lineas: lineas,
        sesionCajaId: 'sesion-mixta',
      );

      expect(await estadoFinal('LOTE'), await estadoFinal('VIEJO'));
    });

    test('cobro de sola mora sobre un plan ya saldado', () async {
      // El caso que la Entrega A destrabó: no quedan cuotas ni saldo, solo el
      // arrastre de mora en ficha.
      await sembrarContrato('VIEJO', saldo: 0, cuotasPagadas: 9, tracked: 1200);
      await sembrarContrato('LOTE', saldo: 0, cuotasPagadas: 9, tracked: 1200);
      final lineas = [
        const PagoLoteLinea(
          monto: 1200,
          concepto: 'Interés mora cuota 9',
          montoADescontarDeSaldo: 0,
          cuotasLiquidadas: 0,
          medioPago: 'Efectivo',
          lineKind: kLineKindInteresMora,
          moraPendienteAntesDeLote: 1200,
        ),
      ];
      const patch = {
        'mora_pendiente_tracked': 0.0,
        'mora_cobrada_offset': 1200.0,
      };

      await caminoViejo('VIEJO', lineas, patch, 'sesion-jefe');
      await repo.registrarPagosLote(
        contratoId: uid('LOTE'),
        lineas: lineas,
        contratoPatch: patch,
        sesionCajaId: 'sesion-jefe',
      );

      expect(await estadoFinal('LOTE'), await estadoFinal('VIEJO'));
    });
  });

  group('atomicidad', () {
    test('si el patch falla, no queda ni una línea ni una entrada de cola',
        () async {
      await sembrarContrato('ROLLBACK', mesaPrecio: 70000, tracked: 8700);
      final db = await LocalDatabase.instance;

      // Falla real a mitad del lote: las tres líneas ya se insertaron y el
      // patch rompe contra una columna que no existe. Sin transacción única,
      // los pagos quedarían escritos y el reintento los duplicaría.
      await expectLater(
        repo.registrarPagosLote(
          contratoId: uid('ROLLBACK'),
          lineas: cobroCompleto(),
          contratoPatch: const {'columna_que_no_existe': 1},
          sesionCajaId: 'sesion-1',
        ),
        throwsA(anything),
      );

      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [uid('ROLLBACK')],
      );
      expect(pagos, isEmpty, reason: 'quedaron pagos de un cobro que falló');

      final cola = await db.query('_sync_queue');
      expect(cola, isEmpty, reason: 'la cola de sync quedó con medio cobro');

      final contrato = (await db.query(
        'contratos_alumnos',
        where: 'id = ?',
        whereArgs: [uid('ROLLBACK')],
      )).first;
      expect(contrato['saldo_deudor'], 360000);
      expect(contrato['cuotas_pagadas'], 0);
      expect(contrato['mora_pendiente_tracked'], 8700);
    });

    test('el reintento después de una falla no duplica nada', () async {
      await sembrarContrato('REINTENTO', mesaPrecio: 70000, tracked: 8700);

      await expectLater(
        repo.registrarPagosLote(
          contratoId: uid('REINTENTO'),
          lineas: cobroCompleto(),
          contratoPatch: const {'columna_que_no_existe': 1},
          sesionCajaId: 'sesion-1',
        ),
        throwsA(anything),
      );
      // El operador reintenta, ahora sin el error.
      await repo.registrarPagosLote(
        contratoId: uid('REINTENTO'),
        lineas: cobroCompleto(),
        contratoPatch: patchMora,
        sesionCajaId: 'sesion-1',
      );

      await sembrarContrato('UNAVEZ', mesaPrecio: 70000, tracked: 8700);
      await repo.registrarPagosLote(
        contratoId: uid('UNAVEZ'),
        lineas: cobroCompleto(),
        contratoPatch: patchMora,
        sesionCajaId: 'sesion-1',
      );

      expect(await estadoFinal('REINTENTO'), await estadoFinal('UNAVEZ'));
    });
  });

  group('atribución de caja (modo jefe y modo operario)', () {
    test('cada línea del lote queda atada a la sesión que cobró', () async {
      await sembrarContrato('CAJA', mesaPrecio: 70000, tracked: 8700);
      await repo.registrarPagosLote(
        contratoId: uid('CAJA'),
        lineas: cobroCompleto(),
        contratoPatch: patchMora,
        sesionCajaId: 'sesion-operario-7',
      );

      final db = await LocalDatabase.instance;
      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [uid('CAJA')],
      );
      expect(pagos, hasLength(3));
      for (final p in pagos) {
        expect(
          p['sesion_caja_id'],
          'sesion-operario-7',
          reason: 'una línea sin sesión no aparece en ningún cierre',
        );
      }
    });

    test('sin sesión, ninguna línea inventa una', () async {
      await sembrarContrato('SINCAJA', mesaPrecio: 70000, tracked: 8700);
      await repo.registrarPagosLote(
        contratoId: uid('SINCAJA'),
        lineas: cobroCompleto(),
        contratoPatch: patchMora,
      );

      final db = await LocalDatabase.instance;
      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [uid('SINCAJA')],
      );
      expect(pagos, hasLength(3));
      for (final p in pagos) {
        expect(p['sesion_caja_id'], isNull);
      }
    });
  });
}
