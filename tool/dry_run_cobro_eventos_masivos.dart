// Simulación de cobro (cuota / mesa / silla / mora) en eventos masivos.
// SOLO LECTURA: no inserta pagos ni modifica contratos.
//
// Uso:
//   dart run tool/dry_run_cobro_eventos_masivos.dart
//   dart run tool/dry_run_cobro_eventos_masivos.dart --db "C:\ruta\data.db"

import 'dart:io';

import 'package:arguello_events/features/eventos/services/dry_run_cobro_simulator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:sqlite3/sqlite3.dart';

String _resolveDbPath(List<String> args) {
  final i = args.indexOf('--db');
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

void main(List<String> args) {
  final dbPath = _resolveDbPath(args);
  final dbFile = File(dbPath);
  if (!dbFile.existsSync()) {
    stderr.writeln('No se encontró la base (solo lectura): $dbPath');
    exit(1);
  }

  stderr.writeln('DRY-RUN cobro masivos — DB abierta READONLY');
  stderr.writeln('Ruta: $dbPath');
  stderr.writeln('No se escribirá ningún dato.\n');

  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);

  try {
    final eventos = db.select('''
      SELECT e.id, e.tipo, e.fecha_evento, c.nombre_completo AS cliente
      FROM eventos e
      LEFT JOIN clientes c ON c.id = e.cliente_id
      WHERE e.modalidad = 'masivo'
      ORDER BY e.fecha_evento ASC, c.nombre_completo COLLATE NOCASE ASC
    ''');

    if (eventos.isEmpty) {
      print('No hay eventos masivos en la base.');
      exit(0);
    }

    print('=== DRY-RUN COBRO — ${eventos.length} evento(s) masivo(s) ===\n');

    var eventosOk = 0;
    var eventosFail = 0;
    var totalContratos = 0;
    var totalEscenarios = 0;
    var escenariosOk = 0;
    final todosFallos = <String>[];

    for (final ev in eventos) {
      final eventoId = ev['id'] as String;
      final cliente = (ev['cliente'] as String?)?.trim() ?? '';
      final tipo = ev['tipo'] as String? ?? '';
      final fecha = ev['fecha_evento'] as String? ?? '';
      final etiqueta = cliente.isNotEmpty ? '$fecha · $cliente' : '$fecha · $tipo';

      final cRows = db.select(
        'SELECT * FROM contratos_alumnos WHERE evento_id = ? ORDER BY nombre_alumno COLLATE NOCASE',
        [eventoId],
      );
      final contratos = cRows.map((r) => ContratoAlumno.fromJson(r)).toList();

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

      totalContratos += res.contratosProbados;
      for (final c in res.contratos) {
        for (final e in c.escenarios) {
          totalEscenarios++;
          if (e.ok) escenariosOk++;
        }
      }

      final icon = res.ok ? 'OK' : 'FAIL';
      print('[$icon] $etiqueta');
      print(
        '     Alumnos con deuda: ${res.contratosActivos} probados | '
        'total alumnos evento: ${contratos.length}',
      );

      if (res.ok) {
        eventosOk++;
        final escenariosEvento =
            res.contratos.fold<int>(0, (s, c) => s + c.escenarios.length);
        print('     Escenarios simulados: $escenariosEvento (cuota/mesa/silla/mora/combo)');
      } else {
        eventosFail++;
        for (final f in res.fallos.take(8)) {
          print('     ! $f');
          todosFallos.add('$etiqueta → $f');
        }
        if (res.fallos.length > 8) {
          print('     ! … y ${res.fallos.length - 8} más');
        }
      }
      print('');
    }

    print('=== RESUMEN ===');
    print('Eventos masivos: ${eventos.length}');
    print('Eventos OK: $eventosOk | con fallos: $eventosFail');
    print('Contratos con deuda probados: $totalContratos');
    print('Escenarios simulados: $escenariosOk / $totalEscenarios OK');
    print('Modo: READONLY — cero escrituras en pagos/contratos');

    if (todosFallos.isNotEmpty) {
      print('\nFallos (${todosFallos.length}):');
      for (final f in todosFallos) {
        print('  - $f');
      }
      exit(2);
    }

    print('\nTodo OK para jornada: preview → PDF → saldo post-cobro coherente.');
    exit(0);
  } finally {
    db.dispose();
  }
}
