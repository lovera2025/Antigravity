// Setea mora_pendiente_tracked en un contrato.
//
//   dart run tool/set_mora_tracked.dart --nombre "BORDA" --evento "COLEGIO NACIONAL" --monto 8700

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

String _resolveDbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

void main(List<String> args) {
  final dbPath = _resolveDbPath();
  if (!File(dbPath).existsSync()) {
    stderr.writeln('No se encontró: $dbPath');
    exit(1);
  }

  final nombreIdx = args.indexOf('--nombre');
  final eventoIdx = args.indexOf('--evento');
  final montoIdx = args.indexOf('--monto');

  if (nombreIdx < 0 ||
      eventoIdx < 0 ||
      montoIdx < 0 ||
      nombreIdx + 1 >= args.length ||
      eventoIdx + 1 >= args.length ||
      montoIdx + 1 >= args.length) {
    stderr.writeln(
      'Uso: dart run tool/set_mora_tracked.dart --nombre "BORDA" '
      '--evento "COLEGIO NACIONAL" --monto 8700',
    );
    exit(1);
  }

  final nombre = args[nombreIdx + 1];
  final evento = args[eventoIdx + 1];
  final monto = double.parse(args[montoIdx + 1]);

  final db = sqlite3.open(dbPath);
  try {
    final eventos = db.select('''
      SELECT e.id FROM eventos e
      JOIN clientes c ON c.id = e.cliente_id
      WHERE c.nombre_completo LIKE ?
    ''', ['%$evento%']);
    if (eventos.isEmpty) {
      stderr.writeln('Sin eventos para: $evento');
      exit(1);
    }
    final eventoId = eventos.first['id'] as String;
    final contratos = db.select(
      'SELECT id, nombre_alumno, mora_pendiente_tracked, saldo_deudor '
      'FROM contratos_alumnos WHERE evento_id = ? AND nombre_alumno LIKE ?',
      [eventoId, '%$nombre%'],
    );
    if (contratos.isEmpty) {
      stderr.writeln('Sin contratos para: $nombre');
      exit(1);
    }
    for (final c in contratos) {
      final id = c['id'] as String;
      final antes = (c['mora_pendiente_tracked'] as num?)?.toDouble() ?? 0;
      db.execute(
        'UPDATE contratos_alumnos SET mora_pendiente_tracked = ? WHERE id = ?',
        [monto, id],
      );
      print(
        '${c['nombre_alumno']}: tracked \$${antes.toStringAsFixed(2)} → '
        '\$${monto.toStringAsFixed(2)} | saldo \$${(c['saldo_deudor'] as num?)?.toStringAsFixed(2)}',
      );
    }
  } finally {
    db.dispose();
  }
}
