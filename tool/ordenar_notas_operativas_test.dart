// Saca de esta PC las 31 notas operativas que estaban acá y no en la nube.
// Revisadas con el usuario el 11-oct-2026, una por una.
//
// Qué eran. Al contar la nube antes de publicar la 6.0.0 apareció que
// `notas_operativas_contrato` tenía 56 filas acá y 26 en Supabase, con la cola
// de subida vacía. Las 31 de diferencia eran dos cosas distintas:
//
//   • 17 que nunca subieron. Son las de la auditoría del 4-sep
//     (`reencolar_notas_sin_subir.dart`, que no se llegó a aplicar): notas de
//     mayo a agosto que solo se veían en esta PC.
//   • 14 que alguien borró desde otra PC. El 4-sep estaban en la nube y hoy no.
//     Una nota se borra de una sola forma —el botón Eliminar, con "¿Borrar
//     nota?"— y acá quedaron porque esta PC estaba cerrada: el borrado viaja por
//     el aviso entre PCs, y la reconciliación de borrados no mira las notas.
//
// Qué decidió el usuario. Se le propuso subir 8 de las que nunca subieron (las
// de saldos a favor y cuentas a arreglar) y contestó que no: "eso ya pasó, esas
// fechas ya pasaron, para mí hay que borrar esas notas". **No sube ninguna: se
// borran las 31 de esta PC.** De la nube no se borra nada, porque ninguna está.
//
// Son listas fijas y no "todo lo que falte en la nube" a propósito: una nota
// que falta en la nube puede ser una que nunca subió, y esas no se borran sin
// mirarlas. Ver "Nada se borra de la base local" en CLAUDE.md.
//
// Uso:
//   flutter test tool/ordenar_notas_operativas_test.dart               (DRY-RUN)
//   ... --dart-define=APPLY=1   (escribe: con la app CERRADA)
//
// Aborta SIN ESCRIBIR NADA si alguna nota ya no está, si es de otro alumno, si
// su texto cambió desde la revisión, o si hay algo suyo en la cola de subida.
// Antes de aplicar hay que mirar en Supabase que ninguno de los 31 ids esté en
// la nube: esta herramienta no la puede consultar.
// APPLY: copia de data.db, y al lado un .txt con las 31 notas enteras; después,
// una sola transacción. No toca ninguna otra tabla ni encola nada.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Nota {
  final String id;
  final String alumno;

  /// Cómo empezaba el texto el día de la revisión.
  final String empieza;
  const _Nota(this.id, this.alumno, this.empieza);
}

/// Nunca subieron a la nube: solo se veían en esta PC.
const _nuncaSubieron = <_Nota>[
  _Nota('eb1b8a12-8b19-49cb-8d15-4e35ab8aa5f5', 'MENDEZ, GUILLERMO', 'A FAVOR \$50'),
  _Nota('1d3a2371-b391-4361-87fe-21bdc6bd0c9a', 'MACIEL, JOSE SANTIAGO', 'queda 50 pesos a favor nuest'),
  _Nota('86a33596-e3f9-4439-ae86-538557768209', 'FABBRO, NAHIARA MELINA', 'dijo que dejaba los 900 de m'),
  _Nota('5b362d2b-7233-4658-9feb-b3e6628f7fbe', 'ARRIETA, BRENDA ANAHI', 'Arreglo de cuenta'),
  _Nota('338d769a-8346-4bd9-9b3a-b6c3e9a6e70c', 'MOREIRA, FACUNDO N', 'Ahora pasa a hablar por el n'),
  _Nota('63b1c31b-75ed-4fd3-868d-5e74acfd3624', 'ARANDA, BRISA ABIGAIL', 'ARREGLA ESTA CUENTA, SACALE '),
  _Nota('65c651a3-a632-4339-b68e-c609583eadad', 'AYALA, PRISCILA', 'le quedo 300 a favor'),
  _Nota('c35ed6fa-6c5e-41fb-ae09-38dcc981f36c', 'VEGA, LUANA', 'ya abono la mora expone la a'),
  _Nota('dafc1e36-0bc8-4b10-98e1-a3669933e309', 'QUIRICO, BRUNO', 'Quedaron 50 pesos para la pr'),
  _Nota('12c991d2-9067-48e3-bafe-c07807992741', 'ORTIZ, NICOLAS', 'VENDRA O AVISARÁ HOY A LA TA'),
  _Nota('bb0e7c72-239c-43f1-bc90-059c11b36927', 'FERNANDEZ, LUANA VICTORIA', '\$26.900 gracias al adelanto '),
  _Nota('91aeac5c-cda4-4ba3-b131-5e2c237a73ee', 'ERCHEGO, BRISA AILÉN', 'REVISAR'),
  _Nota('ee5bae9c-c746-4652-9f24-97b297f647a6', 'GODOY, ROCIO MARIAN', 'INCLUYE REVISION'),
  _Nota('4b1911a4-00cf-4cd9-95f9-3443745797d2', 'GONZALEZ, LUCRECIA MAGALI', 'REVISAR'),
  _Nota('27ca3881-caba-48fb-9204-25d951ede07a', 'VERA, BRENDA MADELEIN', 'REVISAR'),
  _Nota('456dfddb-f027-4fb9-ba84-aadb2668120e', 'QUIROZ, JOAQUIN ANDRES', 'REVISAR'),
  _Nota('cc98fc5c-7f54-44b4-8425-44fbd6d478a9', 'MAIDANA, DAIARA SOLANGE', 'REVISAR'),
];

/// Ya las había borrado alguien desde otra PC.
const _yaBorradas = <_Nota>[
  _Nota('7deff39c-1f2b-4ee3-9aaf-658930150fee', 'MORATO, DIEGO BENJAMIN', 'CUOTA BASE "PADRE APARTE PAG'),
  _Nota('2fac9eea-0112-4b55-a042-6951143fa43b', 'VELASQUEZ, VICTOR SAMUEL', 'descuento por hijo a ver'),
  _Nota('66f3fc54-a68b-4cf4-ad10-b3f42ef69be8', 'SOSA, DALMA', 'Queda \$700 a favor..... no h'),
  _Nota('99e1dcdd-1076-44b7-be86-019a3d5c2bd2', 'JUAREZ, CELESTE MARIANELA', 'Posible confirmacion de mesa'),
  _Nota('2f893a91-d6e6-44d1-86b8-dbff05c2512b', 'BARRIOS, RICARDO JAVIER', 'Vino a hablar para pagar por'),
  _Nota('08ac0377-013f-4d0f-b4eb-b340107e4884', 'DIAZ LLANO, AGUSTIN EZEQUIEL', 'falta 1500 para la completar'),
  _Nota('89e3b28e-f496-4986-b486-2f84968d5173', 'BENITEZ GUARDERES, SANTINO', 'sacar mora remanente a este '),
  _Nota('14b963cd-c401-485d-8f92-bdd1d283ef9b', 'GONZALES DURAN, BRIANT ELIAS', 'Pasa a abonar dos cuotas jun'),
  _Nota('8272b586-8e95-4038-94f2-bcdb276c9c74', 'SANCHEZ, PRISCILA ARIANA', 'Dejo dicho que pasaba a la t'),
  _Nota('6a5747e4-9ae8-4246-97f8-f80fe3201ec5', 'DELGADO, JESUS VALENTINO BENJAMIN', 'posibilidad restructuracion '),
  _Nota('c7f44718-79a9-4c48-ab75-50105ae74ec9', 'CHAVEZ, LUCIA BELEN', 'VIERNES PASAN A ABONAR TODO.'),
  _Nota('d439e0c8-93a1-448c-8039-a6fc9aba0e10', 'ZINI, GEREMIAS JOSE', 'quedo en \$428.000-- ella ent'),
  _Nota('784ecdfa-439a-4b7f-847f-e32b67a0e5f1', 'PINAT, VICTORIA AGOSTINA', 'queda 100 a favor'),
  _Nota('2e00903b-428c-4512-b4d0-7218c387a7a8', 'OVELAR, ENZO LEONEL', 'PASA EL 18 DE SEPTIEMBRE--- '),
];

class _Freno implements Exception {
  final String motivo;
  _Freno(this.motivo);
  @override
  String toString() => motivo;
}

String _unRenglon(String? t) => (t ?? '').split(RegExp(r'\s+')).join(' ').trim();

Future<int> _contar(DatabaseExecutor db, String sql) async =>
    ((await db.rawQuery(sql)).first.values.first as num).toInt();

class _Plan {
  final List<String> aBorrar;
  final int notasAntes;
  final List<String> lineas;

  /// Las 31 notas enteras, para dejarlas escritas antes de borrarlas.
  final String respaldo;
  _Plan(this.aBorrar, this.notasAntes, this.lineas, this.respaldo);
}

Future<_Plan> _planificar(DatabaseExecutor db) async {
  final todas = [..._nuncaSubieron, ..._yaBorradas];
  if ({for (final n in todas) n.id}.length != todas.length) {
    throw _Freno('Hay un id repetido en las listas.');
  }

  final enCola = await db.query(
    '_sync_queue',
    columns: ['registro_id'],
    where: 'registro_id IN (${List.filled(todas.length, '?').join(',')})',
    whereArgs: [for (final n in todas) n.id],
  );
  if (enCola.isNotEmpty) {
    throw _Freno('${enCola.length} de estas notas tienen un cambio sin subir. '
        'Primero "Subir pendientes".');
  }

  final filas = <String, Map<String, dynamic>>{};
  for (final n in todas) {
    final rows = await db.rawQuery(
      'SELECT n.*, c.nombre_alumno FROM notas_operativas_contrato n '
      'LEFT JOIN contratos_alumnos c ON c.id = n.contrato_alumno_id '
      'WHERE n.id = ?',
      [n.id],
    );
    if (rows.isEmpty) {
      throw _Freno('${n.alumno}: la nota ya no está en esta base.');
    }
    final r = rows.first;
    final nombre = (r['nombre_alumno'] as String? ?? '').trim();
    if (nombre != n.alumno) {
      throw _Freno('${n.id}: es de "$nombre" y se revisó como ${n.alumno}.');
    }
    final texto = _unRenglon(r['texto'] as String?);
    if (!texto.startsWith(n.empieza)) {
      throw _Freno('${n.alumno}: la nota cambió desde la revisión '
          '("$texto"). No se toca.');
    }
    filas[n.id] = Map<String, dynamic>.from(r);
  }

  final notasAntes =
      await _contar(db, 'SELECT COUNT(*) FROM notas_operativas_contrato');

  String renglon(_Nota n) {
    final r = filas[n.id]!;
    final texto = _unRenglon(r['texto'] as String?);
    final corto = texto.length > 70 ? '${texto.substring(0, 70)}…' : texto;
    final resuelta = (r['resuelto'] as num? ?? 0) != 0 ? ' (resuelta)' : '';
    return '  · ${n.alumno} — ${'${r['created_at']}'.substring(0, 10)}'
        '$resuelta — $corto';
  }

  final lineas = <String>[
    'SE BORRAN DE ESTA PC (${_nuncaSubieron.length}): nunca subieron a la nube',
    for (final n in _nuncaSubieron) renglon(n),
    '',
    'SE BORRAN DE ESTA PC (${_yaBorradas.length}): ya las borró alguien desde '
        'otra PC',
    for (final n in _yaBorradas) renglon(n),
    '',
    'Notas en esta PC: $notasAntes → ${notasAntes - todas.length}. '
        'A la nube no sube ninguna y de la nube no se borra ninguna.',
  ];

  final respaldo = StringBuffer()
    ..writeln('Notas operativas sacadas de esta PC el '
        '${DateTime.now().toIso8601String().substring(0, 16)}')
    ..writeln();
  for (final n in todas) {
    final r = filas[n.id]!;
    respaldo
      ..writeln('${n.alumno}  (nota ${n.id}, alumno ${r['contrato_alumno_id']})')
      ..writeln('  escrita: ${r['created_at']} · tocada: ${r['updated_at']} · '
          'resuelta: ${(r['resuelto'] as num? ?? 0) != 0 ? 'sí' : 'no'}')
      ..writeln('  ${'${r['texto']}'.replaceAll('\n', '\n  ')}')
      ..writeln();
  }

  return _Plan(
    [for (final n in todas) n.id],
    notasAntes,
    lineas,
    respaldo.toString(),
  );
}

Future<void> _aplicar(DatabaseExecutor txn, _Plan plan) async {
  for (final id in plan.aBorrar) {
    final n = await txn.delete(
      'notas_operativas_contrato',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (n != 1) throw _Freno('$id: no se pudo borrar (filas: $n).');
  }
  final quedan =
      await _contar(txn, 'SELECT COUNT(*) FROM notas_operativas_contrato');
  if (quedan != plan.notasAntes - plan.aBorrar.length) {
    throw _Freno('Quedaron $quedan notas y tenían que quedar '
        '${plan.notasAntes - plan.aBorrar.length}.');
  }
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

  test('las 31 notas que estaban en esta PC y no en la nube', () async {
    sqfliteFfiInit();
    final home = Platform.environment['USERPROFILE'] ?? '';
    final sep = Platform.pathSeparator;
    final dbPath = '$home${sep}Documents${sep}Junior Eventos${sep}data.db';

    print('DB: $dbPath');
    print(apply ? 'Modo: APLICAR\n' : 'Modo: DRY-RUN (no escribe nada)\n');

    String? copia;
    if (apply) {
      if (await _appAbierta()) {
        fail('La app está abierta. Cerrala (en esta PC) y volvé a correr.');
      }
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      copia = '$dbPath.bak.notas.$stamp';
      await File(dbPath).copy(copia);
      print('Copia: $copia\n');
    }

    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: !apply),
    );
    try {
      final plan = apply
          ? await db.transaction((txn) async {
              final p = await _planificar(txn);
              // Las notas enteras quedan escritas antes de borrar la primera.
              File('$copia.txt').writeAsStringSync(p.respaldo);
              await _aplicar(txn, p);
              return p;
            })
          : await _planificar(db);
      print('${plan.lineas.join('\n')}\n');
      print(apply
          ? 'Aplicado. Las 31 notas enteras quedaron en $copia.txt'
          : 'DRY-RUN OK: no se escribió nada.');
    } on _Freno catch (e) {
      fail('FRENO, no se escribió nada: $e');
    } finally {
      await db.close();
    }
  });
}
