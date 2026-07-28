// Dry-run de la reconciliación de mora_pendiente_tracked. SOLO LECTURA.
//
// Compara el tracked guardado en el SQLite local contra el que resulta de
// re-simular el historial de pagos con las reglas actuales (carry-over v54).
// No escribe nada: abre la base con OpenMode.readOnly y nunca toca SyncQueue.
//
// Corre bajo el SDK de Flutter porque MoraTrackedRecovery arrastra
// sync_queue.dart → package:flutter/foundation.dart:
//
//   flutter test scripts/dry_run_mora_tracked.dart
//   MORA_ALUMNO=BERNEL flutter test scripts/dry_run_mora_tracked.dart
//   $env:MORA_ALUMNO='BORDA'; flutter test scripts/dry_run_mora_tracked.dart
import 'dart:io';

import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';
// sqlite3 llega como dependencia transitiva; se usa igual en
// test/modal_cobro_masivos_medios_pago_test.dart por su OpenMode.readOnly.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';

/// Misma ruta que resuelve LocalDatabase.dbPath (Documentos/Junior Eventos).
/// La carpeta vieja sin espacio queda como fallback para PCs sin migrar.
String? _localDbPath() {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null) return null;
  final sep = Platform.pathSeparator;
  for (final carpeta in ['Junior Eventos', 'JuniorEventos']) {
    final path = '$home${sep}Documents$sep$carpeta${sep}data.db';
    if (File(path).existsSync()) return path;
  }
  return null;
}

String _fmt(double v) {
  final neg = v < 0;
  final entero = v.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) buf.write('.');
    buf.write(entero[i]);
  }
  return '${neg ? '-' : ''}$buf';
}

String _pad(String s, int n) =>
    s.length >= n ? s.substring(0, n) : s.padRight(n);
String _padL(String s, int n) =>
    s.length >= n ? s.substring(0, n) : s.padLeft(n);

List<Map<String, dynamic>> _rows(ResultSet rs) =>
    rs.map((r) => Map<String, dynamic>.from(r)).toList();

void main() {
  final dbPath = _localDbPath();
  if (dbPath == null) {
    test(
      'dry-run mora tracked (omitido: sin data.db local)',
      () {},
      skip: 'No hay data.db en Documents/Junior Eventos',
    );
    return;
  }

  test('dry-run mora tracked (READONLY, no escribe nada)', () {
    final filtro = (Platform.environment['MORA_ALUMNO'] ?? '').toUpperCase();
    final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    // ignore: avoid_print
    print('DB (solo lectura): $dbPath\n');

    try {
      // Por defecto, el universo de reconciliarTodos(soloEventosMasivosActivos:
      // true). Con MORA_TODOS=1, el universo REAL que toca el post-pull de
      // SyncEngine: todos los contratos, sin filtro.
      final todos = (Platform.environment['MORA_TODOS'] ?? '') == '1';
      final contratos = _rows(db.select(todos
          ? 'SELECT * FROM contratos_alumnos'
          : '''
        SELECT c.*
        FROM contratos_alumnos c
        INNER JOIN eventos e ON e.id = c.evento_id
        WHERE e.modalidad = 'masivo'
          AND e.estado IN ('Confirmado', 'Planificacion')
          AND c.nombre_alumno NOT LIKE '[BAJA]%'
      '''));
      if (todos) {
        // ignore: avoid_print
        print('Universo: TODOS los contratos (${contratos.length}) — el que '
            'recorre SyncEngine._pullFromCloud en cada sync.\n');
      }

      if (filtro.isNotEmpty) {
        _volcarHistorial(db, contratos, filtro);
        return;
      }

      _tablaComparativa(db, contratos);
    } finally {
      db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

List<Map<String, dynamic>> _pagosDe(Database db, String contratoId) => _rows(
      db.select(
        'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id = ? '
        'ORDER BY fecha_pago',
        [contratoId],
      ),
    );

void _tablaComparativa(Database db, List<Map<String, dynamic>> contratos) {
  final filas = <_Fila>[];

  for (final row in contratos) {
    final contrato = ContratoAlumno.fromJson(row);
    final pagos = _pagosDe(db, contrato.id);

    final objetivo = MoraTrackedRecovery.objetivoDesdeHistorial(
      contrato: contrato,
      pagos: pagos,
    );
    final actual = contrato.moraPendienteTracked;
    final diff = objetivo.tracked - actual;
    if (diff.abs() <= 0.01) continue;

    final moraPagada = pagos
        .where((x) => ((x['anulado'] as num?)?.toInt() ?? 0) == 0)
        .where((x) => MoraTrackedRecovery.tieneMoraEnHistorial([x]))
        .fold<double>(0, (s, x) => s + ((x['monto'] as num?)?.toDouble() ?? 0));

    filas.add(_Fila(
      alumno: contrato.nombreAlumno,
      institucion: contrato.institucion ?? '',
      trackedActual: actual,
      trackedNuevo: objetivo.tracked,
      diferencia: diff,
      cuotas: contrato.cuotasPagadas,
      saldo: contrato.saldoDeudor,
      recon: MoraTrackedRecovery.necesitaReconciliar(contrato, pagos),
      // Perdón resucitado: ficha en cero hoy y el replay la reconstruye.
      perdon: actual <= 0.01 &&
          objetivo.tracked > 0.01 &&
          MoraTrackedRecovery.tienePagosCuotaBaseEnHistorial(pagos),
      // Ya se cobró mora y aun así queda remanente: puede venir de un criterio
      // de mora viejo, no del carry-over perdido (el caso Borda).
      revisar: moraPagada > 0.01 && objetivo.tracked > 0.01,
      moraPagada: moraPagada,
    ));
  }

  filas.sort((a, b) => b.diferencia.compareTo(a.diferencia));

  void ln(String s) {
    // ignore: avoid_print
    print(s);
  }

  ln('${_pad('ALUMNO', 32)}${_pad('INSTITUCIÓN', 22)}'
      '${_padL('ACTUAL', 9)}${_padL('NUEVO', 9)}${_padL('DIF', 9)}'
      '${_padL('MORA PAG', 10)}${_padL('CUO', 5)}${_padL('SALDO', 10)}'
      '  RECON FICHA0 REVISAR');
  ln('─' * 130);

  var totalDif = 0.0;
  var totalNuevo = 0.0;
  var sinRecon = 0;
  var conPerdon = 0;
  var aRevisar = 0;
  for (final f in filas) {
    totalDif += f.diferencia;
    totalNuevo += f.trackedNuevo;
    if (!f.recon) sinRecon++;
    if (f.perdon) conPerdon++;
    if (f.revisar) aRevisar++;
    ln('${_pad(f.alumno, 32)}${_pad(f.institucion, 22)}'
        '${_padL(_fmt(f.trackedActual), 9)}${_padL(_fmt(f.trackedNuevo), 9)}'
        '${_padL(_fmt(f.diferencia), 9)}${_padL(_fmt(f.moraPagada), 10)}'
        '${_padL('${f.cuotas}', 5)}${_padL(_fmt(f.saldo), 10)}'
        '  ${_pad(f.recon ? 'sí' : 'NO', 6)}${_pad(f.perdon ? 'sí' : '-', 7)}'
        '${f.revisar ? 'sí' : '-'}');
  }

  ln('─' * 130);
  ln('Contratos con diferencia: ${filas.length}');
  ln('Tracked nuevo total:      \$${_fmt(totalNuevo)}');
  ln('Diferencia total:         \$${_fmt(totalDif)}');
  ln('');
  ln('RECON=NO   → necesitaReconciliar() da false: el fix NO los alcanza '
      '($sinRecon)');
  ln('FICHA0=sí  → ficha hoy en 0 que el replay reconstruye ($conPerdon). NO '
      'implica perdón: el bug del carry-over dejaba el tracked en 0 cada vez '
      'que el último cobro liquidaba una cuota al día.');
  ln('REVISAR=sí → ya se cobró mora en su historial y aun así queda remanente: '
      'revisar a mano ($aRevisar)');
  ln('');
  ln('Nada fue escrito: base abierta en readOnly, sin SyncQueue.');
}

void _volcarHistorial(
  Database db,
  List<Map<String, dynamic>> contratos,
  String filtro,
) {
  void ln(String s) {
    // ignore: avoid_print
    print(s);
  }

  final match = contratos
      .where((r) =>
          (r['nombre_alumno']?.toString() ?? '').toUpperCase().contains(filtro))
      .toList();
  if (match.isEmpty) {
    ln('Sin coincidencias para "$filtro".');
    return;
  }

  for (final row in match) {
    final contrato = ContratoAlumno.fromJson(row);
    final pagos = _pagosDe(db, contrato.id);
    final objetivo = MoraTrackedRecovery.objetivoDesdeHistorial(
      contrato: contrato,
      pagos: pagos,
    );

    ln('═' * 96);
    ln('${contrato.nombreAlumno}  (${contrato.institucion ?? '-'})');
    ln('  id            : ${contrato.id}');
    ln('  Reg           : ${contrato.createdAt}');
    ln('  pactado       : ${_fmt(contrato.montoTotalPactado)}   '
        'mesa: ${_fmt(contrato.mesaExtraPrecio)}   '
        'sillas: ${_fmt(contrato.sillasExtraPrecioTotal)}');
    ln('  cuotas        : ${contrato.cuotasPagadas}/${contrato.totalCuotas}   '
        'saldo: ${_fmt(contrato.saldoDeudor)}');
    ln('  tracked actual: ${_fmt(contrato.moraPendienteTracked)}   '
        'offset: ${_fmt(contrato.moraCobradaOffset)}');
    ln('  exenta hasta  : ${contrato.moraExentaHasta}   '
        'reinicia: ${contrato.moraExencionReinicia}');
    ln('  tracked NUEVO : ${_fmt(objetivo.tracked)}   '
        'offset nuevo: ${_fmt(objetivo.offset)}');
    ln('  necesitaReconciliar: '
        '${MoraTrackedRecovery.necesitaReconciliar(contrato, pagos)}');
    ln('  ── pagos ${'─' * 60}');
    for (final pg in pagos) {
      final anulado = ((pg['anulado'] as num?)?.toInt() ?? 0) != 0;
      ln('   ${_pad(pg['fecha_pago']?.toString() ?? '', 30)}'
          '${_padL(_fmt((pg['monto'] as num?)?.toDouble() ?? 0), 9)}  '
          '${_pad(pg['line_kind']?.toString() ?? '', 16)}'
          '${anulado ? '[ANULADO] ' : ''}${pg['concepto']}');
    }
  }
}

class _Fila {
  _Fila({
    required this.alumno,
    required this.institucion,
    required this.trackedActual,
    required this.trackedNuevo,
    required this.diferencia,
    required this.cuotas,
    required this.saldo,
    required this.recon,
    required this.perdon,
    required this.revisar,
    required this.moraPagada,
  });

  final String alumno;
  final String institucion;
  final double trackedActual;
  final double trackedNuevo;
  final double diferencia;
  final int cuotas;
  final double saldo;
  final bool recon;
  final bool perdon;
  final bool revisar;
  final double moraPagada;
}
