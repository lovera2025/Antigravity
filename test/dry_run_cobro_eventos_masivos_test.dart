import 'dart:io';

import 'package:arguello_events/features/eventos/services/dry_run_cobro_simulator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

String? _localDbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'];
  if (home == null) return null;
  final path = '$home${Platform.pathSeparator}Documents'
      '${Platform.pathSeparator}Junior Eventos'
      '${Platform.pathSeparator}data.db';
  return File(path).existsSync() ? path : null;
}

void main() {
  final dbPath = _localDbPath();
  if (dbPath == null) {
    test(
      'dry-run eventos masivos (omitido: sin data.db local)',
      () {},
      skip: 'No hay data.db en Documents/Junior Eventos',
    );
    return;
  }

  group('dry-run cobro eventos masivos (READONLY)', () {
    late Database db;

    setUpAll(() {
      db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    });

    tearDownAll(() {
      db.dispose();
    });

    test('todos los eventos masivos: cuota/mesa/silla → PDF coherente', () {
      final eventos = db.select('''
        SELECT e.id, e.tipo, e.fecha_evento, c.nombre_completo AS cliente
        FROM eventos e
        LEFT JOIN clientes c ON c.id = e.cliente_id
        WHERE e.modalidad = 'masivo'
        ORDER BY e.fecha_evento ASC
      ''');

      expect(
        eventos.isNotEmpty,
        isTrue,
        reason: 'Debe haber al menos un evento masivo cargado',
      );

      final fallos = <String>[];
      var escenariosOk = 0;
      var escenariosTotal = 0;

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

        for (final c in res.contratos) {
          for (final e in c.escenarios) {
            escenariosTotal++;
            if (e.ok) escenariosOk++;
          }
        }

        if (!res.ok) {
          fallos.addAll(res.fallos.map((f) => '$etiqueta: $f'));
        }
      }

      expect(
        fallos,
        isEmpty,
        reason: fallos.isEmpty
            ? null
            : '${fallos.length} fallo(s):\n${fallos.take(15).join('\n')}',
      );
      expect(escenariosTotal, greaterThan(0));
      expect(escenariosOk, escenariosTotal);
    });
  });
}
