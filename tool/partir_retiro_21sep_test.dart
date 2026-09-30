// El retiro de $49.000.000 del 21-sep ("Retiro bolsillo personal") se parte en
// efectivo y transferencia. Acordado con el usuario el 29-sep.
//
// Se cargó entero en efectivo porque el formulario "Traer del negocio" venía con
// Efectivo elegido y solo controlaba contra el total. Ese día la app tenía
// $28.733.965,83 en efectivo y $22,5M en el banco: desde ahí el efectivo del
// negocio dio negativo. Se parte con lo que había:
//   - el renglón existente queda en $28.733.965,83, en efectivo;
//   - un renglón nuevo, igual en todo (fecha, concepto, categoría, quién lo
//     cargó), por $20.266.034,17 en transferencia.
// Suman los mismos $49.000.000. No cambian el total del negocio, lo apartado ni
// MI BOLSILLO: solo cuánto de eso fue efectivo y cuánto banco. Es una
// estimación; si el resumen del banco dice otro monto, se ajusta.
//
// Uso:
//   flutter test tool/partir_retiro_21sep_test.dart                  (DRY-RUN)
//   ... --dart-define=APPLY=1   (escribe: con la app CERRADA y después de las 20 hs)
//
// Aborta SIN ESCRIBIR NADA si el retiro no es el revisado o si tiene algo en la
// cola de subida. APPLY: copia de data.db, una sola transacción, UPDATE + INSERT
// + encolado. Ningún DELETE. Después: abrir la app y "Subir pendientes".

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _id = 'c8641969-7383-4624-be2b-de200ed17719';
const _fecha = '2026-09-21T13:06:52.465028+00:00';
const _total = 49000000.0;
const _efectivo = 28733965.83;
const _transferencia = 20266034.17;

class _Freno implements Exception {
  final String motivo;
  _Freno(this.motivo);
  @override
  String toString() => motivo;
}

bool _igual(num a, num b) => (a - b).abs() <= 0.01;

String _p(num v) {
  final entero = v.truncate().abs().toString();
  final cent = ((v.abs() - v.abs().truncate()) * 100).round();
  final b = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) b.write('.');
    b.write(entero[i]);
  }
  return '\$$b,${cent.toString().padLeft(2, '0')}';
}

Future<double> _sumaRetiros(DatabaseExecutor db) async {
  final r = await db.rawQuery(
    "SELECT COALESCE(SUM(monto), 0) AS s FROM egresos WHERE categoria LIKE 'Retiro due%'",
  );
  return (r.first['s'] as num).toDouble();
}

class _Plan {
  final Map<String, dynamic> existente;
  final Map<String, dynamic> nuevo;
  _Plan(this.existente, this.nuevo);
}

Future<_Plan> _planificar(DatabaseExecutor db) async {
  final rows = await db.query('egresos', where: 'id = ?', whereArgs: [_id]);
  if (rows.length != 1) throw _Freno('No está el retiro $_id.');
  final r = Map<String, dynamic>.from(rows.single);
  if (!_igual((r['monto'] as num), _total) ||
      '${r['medio_pago']}'.toLowerCase() != 'efectivo' ||
      r['proveedor'] != 'Retiro bolsillo personal' ||
      !'${r['categoria']}'.startsWith('Retiro due') ||
      r['fecha'] != _fecha ||
      r['sesion_caja_id'] != null) {
    throw _Freno('El retiro no es el revisado: ${r['monto']} '
        '${r['medio_pago']} "${r['proveedor']}" ${r['fecha']}. No se toca.');
  }
  final enCola = await db.query(
    '_sync_queue',
    where: 'registro_id = ?',
    whereArgs: [_id],
  );
  if (enCola.isNotEmpty) {
    throw _Freno('El retiro tiene cambios sin subir. Primero "Subir pendientes".');
  }
  if (!_igual(_efectivo + _transferencia, _total)) {
    throw _Freno('Las dos partes no suman el retiro.');
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
  if (n != 1) throw _Freno('No se pudo actualizar el retiro.');
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

  test('el retiro de \$49M del 21-sep se parte en efectivo y transferencia',
      () async {
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
      final copia = '$dbPath.bak.retiro.$stamp';
      await File(dbPath).copy(copia);
      print('Copia: $copia\n');
    }

    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: !apply),
    );
    try {
      final retirosAntes = await _sumaRetiros(db);
      var retirosDespues = retirosAntes;
      final plan = apply
          ? await db.transaction((txn) async {
              final p = await _planificar(txn);
              await _aplicar(txn, p);
              retirosDespues = await _sumaRetiros(txn);
              // Dentro de la transacción: si no cierra, se deshace todo.
              if (!_igual(retirosAntes, retirosDespues)) {
                throw _Freno('El total de retiros cambió: no se aplica.');
              }
              return p;
            })
          : await _planificar(db);

      print('Retiro del 21-sep ($_id), "Retiro bolsillo personal":');
      print('  antes:   ${_p(_total)} en efectivo, un renglón');
      print('  después: ${_p(_efectivo)} en efectivo (el mismo renglón)');
      print('         + ${_p(_transferencia)} en transferencia '
          '(renglón nuevo ${plan.nuevo['id']}, misma fecha, concepto, '
          'categoría y usuario)');
      print('  total de "Aparté para mí": ${_p(retirosAntes)} → '
          '${_p(retirosDespues)} (igual)');
      print('  efectivo del negocio: sube ${_p(_transferencia)}; '
          'banco: baja ${_p(_transferencia)}; el saldo no cambia.\n');
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
