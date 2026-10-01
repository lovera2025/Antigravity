import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/repositories/mesas_movimientos_repository.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// Las dos tablas de la v73 en el motor de sincronización.
///
/// Las listas del motor son privadas, así que se leen del texto del archivo,
/// igual que `sql_v73_coherencia_test` lee el SQL. Importa porque una tabla
/// que falte en una lista no cruza nunca, una columna que falte se pierde en
/// silencio, y una tabla que aparezca en una lista que borra pierde filas.
void main() {
  sqfliteFfiInit();
  const evento = 'e0000000-0000-4000-8000-000000000001';
  const tablas = ['planos_evento', 'mesas_movimientos'];

  final motor = File('lib/core/services/sync_engine.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final cola = File('lib/core/database/sync_queue.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  /// El texto de una lista o mapa `static const ... nombre = [ ... ];`.
  String declaracion(String nombre, String cierre) {
    final i = motor.indexOf(RegExp('static const [^;]*\\b$nombre = '));
    expect(i, greaterThanOrEqualTo(0), reason: 'no encontré $nombre');
    final f = motor.indexOf('\n  $cierre;', i);
    expect(f, greaterThan(i), reason: 'no encontré el final de $nombre');
    return motor.substring(i, f);
  }

  /// Las columnas que el motor deja pasar para una tabla (`_cleanForSqlite`).
  Set<String> columnasDelMotor(String tabla) {
    final m = RegExp("'$tabla': \\[(.*?)\\]", dotAll: true).firstMatch(motor);
    expect(m, isNotNull, reason: '$tabla no está en las columnas del motor');
    return {
      for (final c in RegExp("'([a-z_]+)'").allMatches(m!.group(1)!))
        c.group(1)!,
    };
  }

  final plano = PlanoEvento.nuevo(
    eventoId: evento,
    armado: ArmadosPredefinidos.normal2aPagina3(),
    estilo: EstiloPlano.gala,
    modo: ModoSorteo.bloques,
    ahora: DateTime.utc(2026, 9, 30),
  );
  final movimiento = MovimientoMesas(
    id: UuidUtils.generate(),
    eventoId: evento,
    tipo: TipoMovimientoMesas.intercambio,
    antes: const {'a': '12, 13', 'b': '30, 31'},
    despues: const {'a': '30, 31', 'b': '12, 13'},
    motivo: 'Pidieron estar cerca de la pista',
    deshaceId: UuidUtils.generate(),
    avisos: const ['a ya retiró entradas'],
    hechoPor: 'Jefe',
    createdAt: DateTime.utc(2026, 9, 30),
  );
  final filas = {
    'planos_evento': plano.toMap(),
    'mesas_movimientos': movimiento.toMap(),
  };

  group('las tablas de la v73 en las listas del motor', () {
    test('suben y bajan todas sus columnas: las del modelo y las de la base',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV73(db);
      for (final t in tablas) {
        final enLaBase = {
          for (final c in await db.rawQuery('PRAGMA table_info($t)'))
            c['name'] as String,
        };
        expect(columnasDelMotor(t), enLaBase, reason: '$t: motor y base');
        expect(columnasDelMotor(t), filas[t]!.keys.toSet(),
            reason: '$t: motor y modelo');
      }
      await db.close();
    });

    test('están en la bajada incremental y en la bajada general', () {
      final incrementales = declaracion('_incrementalColumns', '}');
      final deCarga = declaracion('_tablasDeCarga', ']');
      for (final t in tablas) {
        expect(incrementales, contains("'$t': 'updated_at'"), reason: t);
        expect(deCarga, contains("'$t'"), reason: t);
        expect(motor, contains("_pullTable(db, '$t', 'updated_at')"),
            reason: t);
      }
    });

    test('cuelgan del evento: suben después de él', () {
      for (final t in tablas) {
        expect(cola, contains("'$t': 'evento_id'"), reason: t);
      }
      expect(
        motor,
        contains(
          "if (table == 'planos_evento' || table == 'mesas_movimientos') "
          'return 2;',
        ),
      );
    });

    test('no están en ninguna lista que borre filas locales', () {
      final reconciliar = declaracion('_tablasAReconciliar', ']');
      final cascada = declaracion('_hijasEnCascada', '}');
      for (final t in tablas) {
        expect(reconciliar, isNot(contains("'$t'")), reason: t);
        expect(cascada, isNot(contains("'$t'")), reason: t);
      }
    });

    test('la bajada saltea un plano que no trae el id fijo', () {
      expect(
        motor,
        contains("if (table == 'planos_evento' && !planoTraeIdFijo(row))"),
      );
    });
  });

  group('un plano que baja de la nube', () {
    test('con el id fijo de su fiesta, pasa', () {
      expect(planoTraeIdFijo(plano.toMap()), isTrue);
    });

    test('con otro id (cargado a mano en la nube), no', () {
      expect(
        planoTraeIdFijo(plano.toMap()..['id'] = UuidUtils.generate()),
        isFalse,
      );
    });

    test('con el id de otra fiesta, tampoco', () {
      const otra = 'e0000000-0000-4000-8000-000000000002';
      expect(
        planoTraeIdFijo(plano.toMap()..['evento_id'] = otra),
        isFalse,
      );
    });

    test('sin id o sin fiesta, no', () {
      expect(planoTraeIdFijo({'evento_id': evento}), isFalse);
      expect(planoTraeIdFijo({'id': plano.id}), isFalse);
      expect(planoTraeIdFijo({'id': plano.id, 'evento_id': ''}), isFalse);
      expect(planoTraeIdFijo({'id': 7, 'evento_id': 7}), isFalse);
    });
  });

  group('lo trabado en la cola', () {
    SyncQueueEntry entrada(String tabla, int intentos) => SyncQueueEntry(
          tabla: tabla,
          operacion: SyncOperation.insert,
          registroId: '$tabla-$intentos',
          payload: const {},
          createdAt: DateTime.utc(2026, 9, 30),
          intentos: intentos,
        );

    // En el orden en que las procesa el motor: el plano va antes que el pago.
    final ordenadas = [
      entrada('planos_evento', intentosParaTrabado),
      entrada('contratos_alumnos', 0),
      entrada('pagos_contrato_alumno', intentosParaTrabado + 3),
      entrada('pagos_contrato_alumno', 9),
    ];

    test('cuando toca el reintento, se reintentan todos los trabados', () {
      // Antes se reintentaba uno solo cada cinco minutos: un plano que no
      // podía subir (el SQL de la nube sin correr) le sacaba el turno para
      // siempre a un pago trabado.
      expect(
        entradasDeEstaPasada(ordenadas, tocaReintentarTrabados: true),
        ordenadas,
      );
    });

    test('cuando no toca, van solo los frescos, sin perder el orden', () {
      final r = entradasDeEstaPasada(ordenadas, tocaReintentarTrabados: false);
      expect(r.map((e) => e.registroId), [
        'contratos_alumnos-0',
        'pagos_contrato_alumno-9',
      ]);
    });
  });

  group('un cambio de mesa', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE _sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tabla TEXT NOT NULL,
          operacion TEXT NOT NULL,
          registro_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          intentos INTEGER DEFAULT 0,
          ultimo_error TEXT
        )
      ''');
      await LocalDatabase.crearTablasV73(db);
    });

    tearDown(() => db.close());

    test('el renglón se guarda en la tabla real, se encola y vuelve igual',
        () async {
      await db.transaction(
        (txn) => MesasMovimientosRepository.registrarEn(txn, movimiento),
      );
      final guardado = await db.query('mesas_movimientos');
      expect(MovimientoMesas.fromMap(guardado.single).toMap(), movimiento.toMap());
      final enCola = await db.query('_sync_queue');
      expect(enCola.single['tabla'], 'mesas_movimientos');
      expect(enCola.single['registro_id'], movimiento.id);
    });

    test('sin motivo no entra: la base lo rechaza', () async {
      final sinMotivo = movimiento.toMap()..['motivo'] = null;
      await expectLater(
        db.insert('mesas_movimientos', sinMotivo),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
