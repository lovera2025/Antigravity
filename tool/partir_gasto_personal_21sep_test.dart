// El gasto personal de $69.000.000 del 21-sep se parte en efectivo y
// transferencia, igual que el retiro de ese día (`partir_retiro_21sep_test.dart`).
//
// Al partir el retiro de $49M ($28.733.965,83 en efectivo + $20.266.034,17 por
// transferencia), MI BOLSILLO pasó de $0 a $20.266.034,17: el bolsillo se cuenta
// por medio y un medio negativo cuenta como cero. En efectivo quedaba −$20,3M
// (se gastó más efectivo del que se apartó) y en transferencia +$20,3M (se
// apartó del banco y no figuraba gastado). Esos $20,3M del banco son parte de
// los $69M que se gastaron ese día, así que el gasto se parte igual:
//   - el renglón existente queda en $48.733.965,83, en efectivo;
//   - un renglón nuevo, igual en todo, por $20.266.034,17 en transferencia.
// El bolsillo vuelve a $0 en los dos medios. El negocio no cambia: el gasto
// salió del bolsillo, no del negocio.
//
// Uso:
//   flutter test tool/partir_gasto_personal_21sep_test.dart                  (DRY-RUN)
//   ... --dart-define=APPLY=1   (escribe: con la app CERRADA y después de las 20 hs)
//
// Aborta SIN ESCRIBIR NADA si el gasto no es el revisado, si tiene algo en la
// cola de subida o si el bolsillo no quedaría en cero. APPLY: copia de data.db,
// una sola transacción, UPDATE + INSERT + encolado. Ningún DELETE.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _id = 'fb8e840b-cbcb-483a-a662-99ab37b8506a';
const _fecha = '2026-09-21T13:07:17.192061+00:00';
const _total = 69000000.0;
const _efectivo = 48733965.83;
const _transferencia = 20266034.17;

class _Freno implements Exception {
  final String motivo;
  _Freno(this.motivo);
  @override
  String toString() => motivo;
}

bool _igual(num a, num b) => (a - b).abs() <= 0.01;

String _p(num v) {
  final neg = v < 0;
  final a = v.abs();
  final entero = a.truncate().toString();
  final cent = ((a - a.truncate()) * 100).round();
  final b = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) b.write('.');
    b.write(entero[i]);
  }
  return '${neg ? '-' : ''}\$$b,${cent.toString().padLeft(2, '0')}';
}

/// El bolsillo como lo cuenta la app (`finanzas_provider.dart`): por medio,
/// lo apartado menos lo gastado desde lo apartado.
Future<({double ef, double tr})> _bolsillo(DatabaseExecutor db) async {
  Future<double> suma(String where) async {
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(monto), 0) AS s FROM egresos WHERE $where',
    );
    return (r.first['s'] as num).toDouble();
  }

  const tr = "LOWER(TRIM(COALESCE(medio_pago, ''))) = 'transferencia'";
  const retiro = "categoria LIKE 'Retiro due%'";
  // Gasto personal desde lo apartado: todo lo que no lleva el prefijo [empresa].
  const gasto =
      "TRIM(categoria) = 'Gasto personal' AND TRIM(COALESCE(proveedor, '')) NOT LIKE '[empresa]%'";
  const bolsillo = "COALESCE(origen_fondos, '') = 'bolsillo'";
  final ef = await suma('$retiro AND NOT $tr') -
      await suma('$gasto AND NOT $tr') -
      await suma('$bolsillo AND NOT $tr');
  final t = await suma('$retiro AND $tr') -
      await suma('$gasto AND $tr') -
      await suma('$bolsillo AND $tr');
  return (ef: ef, tr: t);
}

String _textoBolsillo(({double ef, double tr}) b) {
  double c(double v) => v > 0 ? v : 0;
  return 'efectivo ${_p(b.ef)} · transferencia ${_p(b.tr)} → la app muestra '
      '${_p(c(b.ef) + c(b.tr))}';
}

class _Plan {
  final Map<String, dynamic> existente;
  final Map<String, dynamic> nuevo;
  _Plan(this.existente, this.nuevo);
}

Future<_Plan> _planificar(DatabaseExecutor db) async {
  final rows = await db.query('egresos', where: 'id = ?', whereArgs: [_id]);
  if (rows.length != 1) throw _Freno('No está el gasto $_id.');
  final r = Map<String, dynamic>.from(rows.single);
  if (!_igual((r['monto'] as num), _total) ||
      '${r['medio_pago']}'.toLowerCase() != 'efectivo' ||
      r['proveedor'] != '[pendiente] Gasto personal' ||
      r['categoria'] != 'Gasto personal' ||
      r['fecha'] != _fecha ||
      r['origen_fondos'] != null) {
    throw _Freno('El gasto no es el revisado: ${r['monto']} '
        '${r['medio_pago']} "${r['proveedor']}" ${r['fecha']}. No se toca.');
  }
  final enCola = await db.query(
    '_sync_queue',
    where: 'registro_id = ?',
    whereArgs: [_id],
  );
  if (enCola.isNotEmpty) {
    throw _Freno('El gasto tiene cambios sin subir. Primero "Subir pendientes".');
  }
  if (!_igual(_efectivo + _transferencia, _total)) {
    throw _Freno('Las dos partes no suman el gasto.');
  }

  final ahora = DateTime.now().toUtc().toIso8601String();
  final existente = Map<String, dynamic>.from(r)
    ..['monto'] = _efectivo
    ..['updated_at'] = ahora;
  final nuevo = Map<String, dynamic>.from(r)
    ..['id'] = UuidUtils.generate()
    ..['monto'] = _transferencia
    ..['medio_pago'] = 'Transferencia'
    ..['updated_at'] = ahora;
  return _Plan(existente, nuevo);
}

Future<void> _aplicar(DatabaseExecutor txn, _Plan plan) async {
  final n = await txn.update(
    'egresos',
    {
      'monto': plan.existente['monto'],
      'updated_at': plan.existente['updated_at'],
    },
    where: 'id = ?',
    whereArgs: [_id],
  );
  if (n != 1) throw _Freno('No se pudo actualizar el gasto.');
  await SyncQueue.enqueue(
    executor: txn,
    tabla: 'egresos',
    operacion: SyncOperation.update,
    registroId: _id,
    payload: plan.existente,
  );
  await txn.insert('egresos', plan.nuevo);
  await SyncQueue.enqueue(
    executor: txn,
    tabla: 'egresos',
    operacion: SyncOperation.insert,
    registroId: plan.nuevo['id'] as String,
    payload: plan.nuevo,
  );
}

Future<bool> _appAbierta() async {
  final r = await Process.run(
    'tasklist',
    ['/FI', 'IMAGENAME eq arguello_events.exe', '/NH'],
  );
  return (r.stdout as String).toLowerCase().contains('arguello_events.exe');
}

void main() {
  final apply = const String.fromEnvironment('APPLY') == '1';

  test('el gasto personal de \$69M del 21-sep se parte en efectivo y '
      'transferencia', () async {
    sqfliteFfiInit();
    final home = Platform.environment['USERPROFILE'] ?? '';
    final sep = Platform.pathSeparator;
    final dbPath = '$home${sep}Documents${sep}Junior Eventos${sep}data.db';

    print('DB: $dbPath');
    print(apply ? 'Modo: APLICAR\n' : 'Modo: DRY-RUN (no escribe nada)\n');

    if (apply) {
      if (await _appAbierta()) {
        fail('La app está abierta. Cerrala (en esta PC) y volvé a correr.');
      }
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final copia = '$dbPath.bak.gasto.$stamp';
      await File(dbPath).copy(copia);
      print('Copia: $copia\n');
    }

    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: !apply),
    );
    try {
      final antes = await _bolsillo(db);
      var despues = (
        ef: antes.ef + _transferencia,
        tr: antes.tr - _transferencia,
      );
      final plan = apply
          ? await db.transaction((txn) async {
              final p = await _planificar(txn);
              await _aplicar(txn, p);
              despues = await _bolsillo(txn);
              if (!_igual(despues.ef, 0) || !_igual(despues.tr, 0)) {
                throw _Freno('El bolsillo no quedaría en cero: no se aplica.');
              }
              return p;
            })
          : await _planificar(db);
      if (!apply && (!_igual(despues.ef, 0) || !_igual(despues.tr, 0))) {
        throw _Freno('El bolsillo no quedaría en cero: '
            '${_textoBolsillo(despues)}.');
      }

      print('Gasto personal del 21-sep ($_id):');
      print('  antes:   ${_p(_total)} en efectivo, un renglón');
      print('  después: ${_p(_efectivo)} en efectivo (el mismo renglón)');
      print('         + ${_p(_transferencia)} en transferencia '
          '(renglón nuevo ${plan.nuevo['id']}, misma fecha, concepto y usuario)');
      print('  MI BOLSILLO antes:   ${_textoBolsillo(antes)}');
      print('  MI BOLSILLO después: ${_textoBolsillo(despues)}');
      print('  el negocio no cambia: el gasto salió del bolsillo.\n');
      print(apply
          ? 'Aplicado. Abrí la app y tocá "Subir pendientes": el contador tiene '
              'que quedar en 0.'
          : 'DRY-RUN OK: no se escribió nada.');
    } on _Freno catch (e) {
      fail('FRENO: $e');
    } finally {
      await db.close();
    }
  });
}
