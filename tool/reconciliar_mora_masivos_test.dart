// Audita/corrige mora tracked — ejecutar con flutter test harness.
// Uso: flutter test tool/reconciliar_mora_masivos_test.dart
//      flutter test tool/reconciliar_mora_masivos_test.dart --dart-define=APPLY=1
//
// ⚠️ NO CORRER CON APPLY=1 SIN LEER ESTO (revisado 11/08/2026)
//
// El replay de `objetivoDesdeHistorial` no coincide con lo que hace la app
// desde v4.6.6 (04/08/2026), que habilitó el pago PARCIAL de mora. Marca como
// desviados los 33 contratos que cobraron mora después de esa fecha — el 100%
// de los posteriores, ninguno de los anteriores. Eso no es data corrupta: es
// que el replay quedó viejo.
//
// Aplicarlo tal cual sube el offset de esos contratos y anula su crédito FIFO,
// con lo que a seis familias se les reclama mora QUE YA PAGARON. Ejemplo:
// ZARATE (GUEMEZ DE TEJADA) pagó $38.500 el 06/08 y volvería a deber $18.550.
//
// Queda sin resolver cuál es el modelo correcto: para ZARATE la ficha dice $0,
// esta herramienta $18.550, y la cuenta a mano ~$3.500 (5 días nuevos al 1%
// diario). Ninguna de las dos primeras da bien. Ese cobro tampoco actualizó
// `mora_exenta_hasta`, así que algo del guardado no llegó.
//
// ── LO QUE HACE QUE ESTO NO SE PUEDA ARREGLAR SIN MÁS ────────────────────────
//
// El replay ancla todo el cronograma en `created_at`: la cuota N vence el
// último día del mes `alta + N`. Y esa fecha se movió a mano.
//
// En su momento se otorgaron perdones corriendo la fecha de alta hacia adelante
// (alta más tarde = vencimientos más tarde = menos mora), y después se
// normalizaron casi todas al 30/03/2026. Medido sobre la base al 11/08/2026,
// de 639 contratos masivos activos:
//
//     249 con hora real de creación (11:15:41.213926) →  7 desviados  (2,8%)
//     390 con alta redonda 03:00:00.000 = puesta a mano → 26 desviados (6,7%)
//     las 390 editadas caen todas el mismo día: 2026-03-30
//
// Los de alta tocada tienen 2,4x más chance de figurar desviados. Un alumno que
// pagó en mayo lo hizo bajo un cronograma que hoy ya no existe, y el replay
// recalcula ese cobro con el alta actual: compara contra una historia que nunca
// pasó. La fecha vieja no quedó guardada en ningún lado.
//
// O sea: no alcanza con modelar mejor la mora parcial. Para reconstruir el
// historial haría falta saber qué alta tenía cada contrato en cada cobro, y ese
// dato no está. Mientras no se registre el alta vigente al momento de cada pago
// —o se guarde el desglose de mora aplicado en cada cobro— esta herramienta no
// puede distinguir un dato corrupto de un perdón viejo.
//
// Antes de aplicar: resolver eso. No es un ajuste del replay.
// Contexto y casos fijados en test/mora_offset_pago_parcial_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

String _resolveDbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

void main() {
  final apply = const String.fromEnvironment('APPLY') == '1';

  test('reconciliar mora masivos', () async {
    sqfliteFfiInit();
    final dbPath = _resolveDbPath();
    final db = await databaseFactoryFfi.openDatabase(dbPath);

    final contratos = await db.rawQuery('''
      SELECT c.*, cl.nombre_completo AS evento_nombre
      FROM contratos_alumnos c
      JOIN eventos e ON e.id = c.evento_id
      LEFT JOIN clientes cl ON cl.id = e.cliente_id
      WHERE e.modalidad = 'masivo'
        AND e.estado IN ('Confirmado', 'Planificacion')
        AND c.nombre_alumno NOT LIKE '[BAJA]%'
      ORDER BY cl.nombre_completo COLLATE NOCASE, c.nombre_alumno COLLATE NOCASE
    ''');

    print('\n=== AUDITORÍA MORA — ${contratos.length} contratos ===');
    print('DB: $dbPath');
    print('Modo: ${apply ? "APLICAR" : "solo lectura"}\n');

    var conDiferencia = 0;

    for (final row in contratos) {
      final c = ContratoAlumno.fromJson(row);
      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [c.id],
      );

      final objetivo = MoraTrackedRecovery.objetivoDesdeHistorial(
        contrato: c,
        pagos: pagos,
      );

      final diffTracked = (objetivo.tracked - c.moraPendienteTracked).abs();
      final diffOffset = (objetivo.offset - c.moraCobradaOffset).abs();
      if (diffTracked <= 0.01 && diffOffset <= 0.01) continue;

      conDiferencia++;
      final moraHist = pagos
          .where((p) => (p['anulado'] as int? ?? 0) == 0)
          .where((p) {
            final lk = (p['line_kind'] as String?)?.trim() ?? '';
            final cl = (p['concepto'] as String? ?? '').toLowerCase();
            return lk == 'interes_mora' ||
                cl.contains('mora') ||
                cl.contains('interés') ||
                cl.contains('interes');
          })
          .fold<double>(0, (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0));

      final operativaDb = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: moraHist,
      );
      final operativaObj = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c.copyWith(
          moraPendienteTracked: objetivo.tracked,
          moraCobradaOffset: objetivo.offset,
        ),
        moraCobradaHistorial: moraHist,
      );

      print('${row['evento_nombre']} / ${c.nombreAlumno}');
      print(
        '  tracked: \$${c.moraPendienteTracked.toStringAsFixed(2)} → '
        '\$${objetivo.tracked.toStringAsFixed(2)}',
      );
      print(
        '  offset:  \$${c.moraCobradaOffset.toStringAsFixed(2)} → '
        '\$${objetivo.offset.toStringAsFixed(2)}',
      );
      print(
        '  mora operativa: \$${operativaDb.toStringAsFixed(2)} → '
        '\$${operativaObj.toStringAsFixed(2)}',
      );
      print('');
    }

    var corregidos = 0;
    if (apply) {
      corregidos = await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        encolarSync: false,
        soloEventosMasivosActivos: true,
      );
    }

    print('=== RESUMEN ===');
    print('Con diferencia: $conDiferencia');
    if (apply) print('Corregidos (reconciliarTodos): $corregidos');
    await db.close();
  });
}
