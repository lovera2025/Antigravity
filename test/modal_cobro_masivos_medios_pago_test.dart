import 'dart:io';

import 'package:arguello_events/features/eventos/services/dry_run_cobro_simulator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'helpers/modal_cobro_medios_pago_readonly.dart';

String? _localDbPath() {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null) return null;
  final path = '$home${Platform.pathSeparator}Documents'
      '${Platform.pathSeparator}Junior Eventos'
      '${Platform.pathSeparator}data.db';
  return File(path).existsSync() ? path : null;
}

/// Eventos masivos activos = no Finalizado ni Cancelado (misma lista que la app).
List<Map<String, dynamic>> _eventosMasivosActivos(Database db) {
  return db.select('''
    SELECT e.id, e.tipo, e.fecha_evento, e.estado,
           c.nombre_completo AS cliente
    FROM eventos e
    LEFT JOIN clientes c ON c.id = e.cliente_id
    WHERE e.modalidad = 'masivo'
      AND (e.estado IS NULL
           OR e.estado NOT IN ('Finalizado', 'Cancelado'))
    ORDER BY e.fecha_evento ASC, c.nombre_completo COLLATE NOCASE ASC
  ''');
}

void main() {
  final dbPath = _localDbPath();
  if (dbPath == null) {
    test(
      'modal cobro masivos medios pago (omitido: sin data.db local)',
      () {},
      skip: 'No hay data.db en Documents/Junior Eventos',
    );
    return;
  }

  group('modal cobro masivos — medios de pago / PDF / UI (READONLY)', () {
    late Database db;

    setUpAll(() {
      db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    });

    tearDownAll(() {
      db.dispose();
    });

    test('eventos masivos activos: Efectivo / Transferencia / Mixto + PDF + UI', () {
      final eventos = _eventosMasivosActivos(db);

      expect(
        eventos.isNotEmpty,
        isTrue,
        reason: 'Debe haber eventos masivos activos en la base local',
      );

      // Referencia operativa: en producción suelen ser 9 eventos activos.
      expect(
        eventos.length,
        greaterThanOrEqualTo(1),
        reason: 'Encontrados ${eventos.length} evento(s) masivo(s) activo(s)',
      );

      final fallos = <String>[];
      var eventosOk = 0;
      var contratosProbados = 0;
      var escenariosMedioPago = 0;
      var escenariosUi = 0;

      for (final ev in eventos) {
        final eventoId = ev['id'] as String;
        final cliente = (ev['cliente'] as String?)?.trim() ?? '';
        final fecha = ev['fecha_evento'] as String? ?? '';
        final estado = ev['estado'] as String? ?? '';
        final etiqueta = cliente.isNotEmpty ? '$fecha · $cliente' : fecha;

        final cRows = db.select(
          'SELECT * FROM contratos_alumnos WHERE evento_id = ?',
          [eventoId],
        );
        final contratos =
            cRows.map((r) => ContratoAlumno.fromJson(r)).toList();
        final ids = contratos.map((c) => c.id).toList();
        final pagosPorContrato = <String, List<Map<String, dynamic>>>{};

        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          final pagos = db.select(
            'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN ($placeholders)',
            ids,
          );
          for (final p in pagos) {
            final cid = p['contrato_alumno_id'] as String;
            pagosPorContrato.putIfAbsent(cid, () => []).add(p);
          }
        }

        final res = simularEventoDryRun(
          eventoId: eventoId,
          etiqueta: etiqueta,
          contratos: contratos,
          pagosPorContrato: pagosPorContrato,
        );

        var eventoFallo = false;

        if (!res.ok) {
          eventoFallo = true;
          fallos.addAll(
            res.fallos.map((f) => '[$estado] $etiqueta → $f'),
          );
        }

        for (final c in res.contratos) {
          contratosProbados++;

          for (final e in c.escenarios.where((x) => x.ok && x.netPlan > 0.01)) {
            escenariosMedioPago++;
            final mf = validarMediosPagoEscenario(escenario: e);
            if (mf.isNotEmpty) {
              eventoFallo = true;
              fallos.addAll(
                mf.map((f) => '${c.nombre} [$etiqueta]: $f'),
              );
            }
          }

          final alumno = contratos.firstWhere((x) => x.id == c.contratoId);
          final pagos = pagosPorContrato[c.contratoId] ?? const [];
          final uf = validarUiPostCobroSecuencial(
            alumno: alumno,
            pagos: pagos,
          );
          if (uf.isNotEmpty) {
            escenariosUi++;
            eventoFallo = true;
            fallos.addAll(
              uf.map((f) => '${c.nombre} [$etiqueta]: $f'),
            );
          } else if (c.escenarios.any(
            (e) => e.ok && e.nombre == 'cuota_base_1' && e.grossPlan > 0.01,
          )) {
            escenariosUi++;
          }
        }

        if (!eventoFallo) eventosOk++;

        // Log informativo (visible con `flutter test --reporter expanded`).
        // ignore: avoid_print
        print(
          '${eventoFallo ? 'FAIL' : 'OK '} $etiqueta ($estado) — '
          'alumnos deuda: ${res.contratosActivos} | '
          'escenarios: ${res.contratos.fold<int>(0, (s, c) => s + c.escenarios.length)}',
        );
      }

      // ignore: avoid_print
      print(
        '\n=== RESUMEN READONLY ===\n'
        'Eventos masivos activos: ${eventos.length}\n'
        'Eventos OK: $eventosOk / ${eventos.length}\n'
        'Contratos con deuda probados: $contratosProbados\n'
        'Escenarios medio de pago (×3): $escenariosMedioPago\n'
        'Simulaciones UI post-cobro: $escenariosUi\n'
        'Modo: solo lectura — sin escrituras en DB',
      );

      expect(
        fallos,
        isEmpty,
        reason: fallos.isEmpty
            ? null
            : '${fallos.length} fallo(s):\n${fallos.take(20).join('\n')}',
      );
      expect(eventosOk, eventos.length);
      expect(escenariosMedioPago, greaterThan(0));
    });

    test('cada evento activo expone al menos un escenario de cobro aplicable', () {
      final eventos = _eventosMasivosActivos(db);
      final sinEscenarios = <String>[];

      for (final ev in eventos) {
        final eventoId = ev['id'] as String;
        final cliente = (ev['cliente'] as String?)?.trim() ?? '';
        final fecha = ev['fecha_evento'] as String? ?? '';
        final etiqueta = cliente.isNotEmpty ? '$fecha · $cliente' : fecha;

        final cRows = db.select(
          'SELECT * FROM contratos_alumnos WHERE evento_id = ?',
          [eventoId],
        );
        final contratos =
            cRows.map((r) => ContratoAlumno.fromJson(r)).toList();
        final conDeuda = contratos.where((c) => c.saldoDeudor > 0.01).length;

        if (conDeuda == 0) continue;

        final ids = contratos.map((c) => c.id).toList();
        final pagosPorContrato = <String, List<Map<String, dynamic>>>{};
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          final pagos = db.select(
            'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN ($placeholders)',
            ids,
          );
          for (final p in pagos) {
            pagosPorContrato
                .putIfAbsent(p['contrato_alumno_id'] as String, () => [])
                .add(p);
          }
        }

        final res = simularEventoDryRun(
          eventoId: eventoId,
          etiqueta: etiqueta,
          contratos: contratos,
          pagosPorContrato: pagosPorContrato,
        );

        final totalEsc = res.contratos.fold<int>(
          0,
          (s, c) => s + c.escenarios.where((e) => e.ok && e.netPlan > 0.01).length,
        );
        if (totalEsc == 0) {
          sinEscenarios.add('$etiqueta ($conDeuda alumnos con deuda)');
        }
      }

      expect(
        sinEscenarios,
        isEmpty,
        reason: sinEscenarios.isEmpty
            ? null
            : 'Eventos con deuda pero sin escenario de modal:\n'
                '${sinEscenarios.join('\n')}',
      );
    });
  });
}
