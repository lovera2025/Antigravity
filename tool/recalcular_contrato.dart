// Recalcula saldo/cuotas desde suma de monto_gross (excluye mora y cargo canal).
//
//   dart run tool/recalcular_contrato.dart --dry-run --evento "SAGRADO CORAZON"
//   dart run tool/recalcular_contrato.dart --nombre "CHAMORRO"
//   dart run tool/recalcular_contrato.dart --evento "COLEGIO NACIONAL"

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

String _resolveDbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

bool _cuentaPlan(Map<String, Object?> p, {required String clase}) {
  if ((p['anulado'] as int? ?? 0) != 0) return false;
  final lk = (p['line_kind'] as String?)?.trim() ?? '';
  final cl = (p['concepto'] as String? ?? '').toLowerCase();
  if (lk == 'interes_mora' ||
      lk == 'cargo_canal_ref' ||
      cl.contains('interes mora') ||
      cl.contains('interés mora') ||
      cl.contains('mora remanente') ||
      cl.contains('cargo canal')) {
    return false;
  }
  if (clase == 'mesa') return cl.contains('mesa');
  if (clase == 'sillas') return cl.contains('silla');
  return !cl.contains('mesa') && !cl.contains('silla');
}

double _grossClase(List<Map<String, Object?>> pagos, String clase) {
  var sum = 0.0;
  for (final p in pagos) {
    if (!_cuentaPlan(p, clase: clase)) continue;
    final mg = (p['monto_gross'] as num?)?.toDouble() ??
        (p['monto'] as num?)?.toDouble() ??
        0.0;
    sum += mg;
  }
  return double.parse(sum.toStringAsFixed(4));
}

int? _numeroCuotaDesdeConcepto(String concepto) {
  final m = RegExp(r'\((\d+)/').firstMatch(concepto.toLowerCase());
  return m != null ? int.tryParse(m.group(1)!) : null;
}

/// Revierte monto_gross inflado por la auditoría vieja (no descuentos reales).
List<Map<String, Object?>> _sanejarGrossInfladoAuditoria({
  required Database db,
  required List<Map<String, Object?>> pagos,
  required double cuotaPura,
  required String nombreAlumno,
  required bool dryRun,
}) {
  final out = pagos.map((p) => Map<String, Object?>.from(p)).toList();

  for (var i = 0; i < out.length; i++) {
    final p = out[i];
    if ((p['anulado'] as int? ?? 0) != 0) continue;
    if (!_cuentaPlan(p, clase: 'base')) continue;

    final net = (p['monto'] as num?)?.toDouble() ?? 0;
    final gross = (p['monto_gross'] as num?)?.toDouble() ?? net;
    if (gross <= net + 0.01) continue;

    final concepto = p['concepto'] as String? ?? '';
    final cl = concepto.toLowerCase();
    var revertir = false;

    if (cl.contains('completada')) {
      revertir = true;
    } else {
      final n = _numeroCuotaDesdeConcepto(concepto);
      if (n != null && (gross - cuotaPura).abs() < 0.02) {
        final hayAbonoPrevio = out.take(i).any((prev) {
          if ((prev['anulado'] as int? ?? 0) != 0) return false;
          final pc = (prev['concepto'] as String? ?? '').toLowerCase();
          if (!(pc.contains('abono') ||
              pc.contains('entrega parcial') ||
              pc.contains('adelanto') ||
              pc.contains('parcial'))) {
            return false;
          }
          return _numeroCuotaDesdeConcepto(pc) == n;
        });
        if (hayAbonoPrevio) revertir = true;
      }
    }

    if (revertir) {
      print(
        '  $nombreAlumno — gross revertido: $concepto | '
        '\$${gross.toStringAsFixed(2)} → \$${net.toStringAsFixed(2)}',
      );
      out[i]['monto_gross'] = net;
      if (!dryRun) {
        db.execute(
          'UPDATE pagos_contrato_alumno SET monto_gross = ? WHERE id = ?',
          [net, p['id']],
        );
      }
    }
  }
  return out;
}

void main(List<String> args) {
  final dbPath = _resolveDbPath();
  if (!File(dbPath).existsSync()) {
    stderr.writeln('No se encontró: $dbPath');
    exit(1);
  }

  final dryRun = args.contains('--dry-run');
  final nombreIdx = args.indexOf('--nombre');
  final idIdx = args.indexOf('--id');
  final eventoIdx = args.indexOf('--evento');

  final db = sqlite3.open(dbPath);
  try {
    List<Map<String, Object?>> contratos;

    if (idIdx >= 0 && idIdx + 1 < args.length) {
      contratos = db.select(
        'SELECT * FROM contratos_alumnos WHERE id = ?',
        [args[idIdx + 1]],
      );
    } else if (nombreIdx >= 0 && nombreIdx + 1 < args.length) {
      contratos = db.select(
        'SELECT * FROM contratos_alumnos WHERE nombre_alumno LIKE ?',
        ['%${args[nombreIdx + 1]}%'],
      );
    } else if (eventoIdx >= 0 && eventoIdx + 1 < args.length) {
      final eventos = db.select('''
        SELECT e.id FROM eventos e
        JOIN clientes c ON c.id = e.cliente_id
        WHERE c.nombre_completo LIKE ?
      ''', ['%${args[eventoIdx + 1]}%']);
      if (eventos.isEmpty) {
        stderr.writeln('Sin eventos.');
        exit(1);
      }
      final ids = eventos.map((e) => e['id'] as String).toList();
      final ph = List.filled(ids.length, '?').join(',');
      contratos = db.select(
        'SELECT * FROM contratos_alumnos WHERE evento_id IN ($ph) '
        "AND nombre_alumno NOT LIKE '[BAJA]%'",
        ids,
      );
    } else {
      stderr.writeln(
        'Uso: dart run tool/recalcular_contrato.dart --nombre "APELLIDO"\n'
        '     dart run tool/recalcular_contrato.dart --evento "COLEGIO NACIONAL"',
      );
      exit(1);
    }

    var cambios = 0;
    for (final c in contratos) {
      final id = c['id'] as String;
      final nombre = c['nombre_alumno'] as String? ?? '';
      final saldoAntes = (c['saldo_deudor'] as num?)?.toDouble() ?? 0;
      final pactado = (c['monto_total_pactado'] as num?)?.toDouble() ?? 0;
      final tCuotas = (c['total_cuotas'] as int?) ?? 9;
      final mesaP = (c['mesa_extra_precio'] as num?)?.toDouble() ?? 0;
      final sillasP = (c['sillas_extra_precio_total'] as num?)?.toDouble() ?? 0;
      final totalBase = (pactado - mesaP - sillasP).clamp(0.0, double.infinity);
      final cuotaPura = tCuotas > 0
          ? double.parse((totalBase / tCuotas).toStringAsFixed(2))
          : totalBase;

      final pagosRaw = db.select(
        'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id = ? '
        'ORDER BY fecha_pago ASC, rowid ASC',
        [id],
      );

      final pagos = _sanejarGrossInfladoAuditoria(
        db: db,
        pagos: pagosRaw,
        cuotaPura: cuotaPura,
        nombreAlumno: nombre,
        dryRun: dryRun,
      );

      final gb = _grossClase(pagos, 'base');
      final gm = _grossClase(pagos, 'mesa');
      final gs = _grossClase(pagos, 'sillas');
      final recaudado = gb + gm + gs;
      final saldoNuevo =
          double.parse((pactado - recaudado).clamp(0.0, double.infinity).toStringAsFixed(2));
      final cuotasNuevas = cuotaPura > 0
          ? ((gb + 0.1) / cuotaPura).floor().clamp(0, tCuotas)
          : 0;

      final cuotasAntes = c['cuotas_pagadas'] as int? ?? 0;
      final hayCambio = (saldoAntes - saldoNuevo).abs() > 0.01 ||
          cuotasAntes != cuotasNuevas;

      if (hayCambio) {
        cambios++;
        final modo = dryRun ? 'REVISAR' : 'CORREGIDO';
        print(
          '$nombre [$modo]: saldo \$${saldoAntes.toStringAsFixed(2)} → '
          '\$${saldoNuevo.toStringAsFixed(2)} | cuotas $cuotasAntes → $cuotasNuevas',
        );
        if (!dryRun) {
          db.execute(
            'UPDATE contratos_alumnos SET saldo_deudor = ?, cuotas_pagadas = ?, '
            'mesa_extra_pagado = ?, sillas_extra_pagado = ? WHERE id = ?',
            [saldoNuevo, cuotasNuevas, gm, gs, id],
          );
        }
      } else {
        print('$nombre: OK (\$${saldoNuevo.toStringAsFixed(2)})');
      }
    }
    print(
      dryRun
          ? '\nContratos con descuadre (sin escribir): $cambios / ${contratos.length}'
          : '\nContratos actualizados: $cambios / ${contratos.length}',
    );
  } finally {
    db.dispose();
  }
}
