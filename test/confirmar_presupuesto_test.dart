// Presupuesto → evento particular (6.2.1). Un cliente preguntó "dónde están
// los detalles que puse", y en la revisión apareció además que un presupuesto
// confirmado se podía convertir en evento dos veces.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/eventos/presupuestos_screen.dart';
import 'package:arguello_events/features/eventos/repositories/presupuestos_repository.dart';
import 'package:arguello_events/models/presupuesto.dart';

const _cliente = 'c0000000-0000-4000-8000-000000000001';
const _presu = 'p0000000-0000-4000-8000-000000000001';
const _dj = 's0000000-0000-4000-8000-000000000001';
const _luces = 's0000000-0000-4000-8000-000000000002';
const _barra = 's0000000-0000-4000-8000-000000000003';
const _dulce = 's0000000-0000-4000-8000-000000000004';
const _l1 = 'l0000000-0000-4000-8000-000000000001';
const _l2 = 'l0000000-0000-4000-8000-000000000002';
const _l3 = 'l0000000-0000-4000-8000-000000000003';
const _l4 = 'l0000000-0000-4000-8000-000000000004';

Future<Database> _base() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 74,
      onCreate: LocalDatabase.onCreateParaTest,
    ),
  );
}

/// Un presupuesto aprobado de XV con un combo, un renglón con 1,5 y un extra,
/// cada uno con su detalle escrito.
Future<void> _cargar(Database db, {String? fecha = '2026-11-14', bool conCliente = true}) async {
  if (conCliente) {
    await db.insert('clientes', {'id': _cliente, 'nombre_completo': 'Laura Gómez', 'telefono': '379 412-0000'});
  }
  for (final s in [
    {'id': _dj, 'nombre': 'DJ'},
    {'id': _luces, 'nombre': 'Iluminación'},
    {'id': _barra, 'nombre': 'Barra libre'},
    {'id': _dulce, 'nombre': 'Mesa dulce'},
  ]) {
    await db.insert('servicios', s);
  }
  await db.insert('presupuestos', {
    'id': _presu,
    'cliente_id': _cliente,
    'tipo_evento': '15_años',
    'lugar': 'Quinta Los Aromos',
    'detalle_anclaje': 'Temática pastel, 120 invitados',
    'fecha_vencimiento': '2026-12-01',
    'fecha_evento': fecha,
    'estado': 'aprobado',
    'nombre_festejado': 'Sofía',
    'created_at': '2026-10-01T12:00:00Z',
  });
  final lineas = [
    {'id': _l1, 'servicio_id': _dj, 'precio_final': 500000.0, 'cantidad': 1.0, 'grupo': 'Combo Fiesta', 'combo_orden': 0, 'detalle_servicio': '5 hs con pantalla LED'},
    {'id': _l2, 'servicio_id': _luces, 'precio_final': 0.0, 'cantidad': 1.0, 'grupo': 'Combo Fiesta', 'combo_orden': 1, 'detalle_servicio': 'Robóticas y luz cálida'},
    {'id': _l3, 'servicio_id': _barra, 'precio_final': 300000.0, 'cantidad': 1.5, 'detalle_servicio': 'Fernet, cerveza y gaseosas'},
    {'id': _l4, 'servicio_id': _dulce, 'precio_final': 150000.0, 'cantidad': 1.0, 'es_extra': 1, 'detalle_servicio': 'Para 120 personas'},
  ];
  for (final l in lineas) {
    await db.insert('presupuesto_servicios', {'presupuesto_id': _presu, ...l});
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _base());
  tearDown(() => db.close());

  test('crea el evento con todo lo que se cargó y queda en la cola', () async {
    await _cargar(db);
    final r = await PresupuestosRepository.confirmarEn(db, _presu);
    expect(r.yaExistia, isFalse);

    final ev = (await db.query('eventos', where: 'id = ?', whereArgs: [r.eventoId])).single;
    expect(ev['presupuesto_id'], _presu);
    expect(ev['fecha_evento'], '2026-11-14');
    expect(ev['observaciones'], 'Temática pastel, 120 invitados');
    expect(ev['cliente_id'], _cliente);

    final renglones = await db.query('eventos_servicios', where: 'evento_id = ?', whereArgs: [r.eventoId], orderBy: 'id');
    expect(renglones.map((e) => e['id']), [_l1, _l2, _l3, _l4]);
    final porId = {for (final e in renglones) e['id']: e};
    expect(porId[_l1]!['detalle_servicio'], '5 hs con pantalla LED');
    expect(porId[_l1]!['grupo'], 'Combo Fiesta');
    expect(porId[_l2]!['combo_orden'], 1);
    expect(porId[_l3]!['cantidad'], 1.5);
    expect(porId[_l4]!['es_extra'], 1);

    final estado = (await db.query('presupuestos', where: 'id = ?', whereArgs: [_presu])).single['estado'];
    expect(estado, 'confirmado');

    final cola = await db.query('_sync_queue');
    final tablas = cola.map((e) => e['tabla']).toList();
    expect(tablas.where((t) => t == 'eventos'), hasLength(1));
    expect(tablas.where((t) => t == 'eventos_servicios'), hasLength(4));
    final presuEnCola = cola.singleWhere((e) => e['tabla'] == 'presupuestos');
    expect(jsonDecode(presuEnCola['payload'] as String)['estado'], 'confirmado');
  });

  test('confirmar dos veces devuelve el mismo evento y no muda nada', () async {
    await _cargar(db);
    final primero = await PresupuestosRepository.confirmarEn(db, _presu);
    final segundo = await PresupuestosRepository.confirmarEn(db, _presu);

    expect(segundo.yaExistia, isTrue);
    expect(segundo.eventoId, primero.eventoId);
    expect(await db.query('eventos'), hasLength(1));
    final renglones = await db.query('eventos_servicios');
    expect(renglones, hasLength(4));
    expect(renglones.every((e) => e['evento_id'] == primero.eventoId), isTrue);
  });

  test('si el evento existía pero el presupuesto no decía confirmado, lo arregla', () async {
    await _cargar(db);
    final r = await PresupuestosRepository.confirmarEn(db, _presu);
    await db.update('presupuestos', {'estado': 'aprobado'}, where: 'id = ?', whereArgs: [_presu]);

    final otra = await PresupuestosRepository.confirmarEn(db, _presu);
    expect(otra.eventoId, r.eventoId);
    expect(otra.yaExistia, isTrue);
    final estado = (await db.query('presupuestos', where: 'id = ?', whereArgs: [_presu])).single['estado'];
    expect(estado, 'confirmado');
    expect(await db.query('eventos'), hasLength(1));
  });

  test('una falla a la mitad no deja nada', () async {
    await _cargar(db);
    // Un renglón con un id que la base rechaza a mitad de camino: el evento ya
    // se insertó cuando falla, y la transacción tiene que deshacerlo.
    await db.execute('''
      CREATE TRIGGER falla_al_tercero BEFORE INSERT ON eventos_servicios
      WHEN NEW.id = '$_l3' BEGIN SELECT RAISE(ABORT, 'falla de prueba'); END
    ''');
    await expectLater(PresupuestosRepository.confirmarEn(db, _presu), throwsA(anything));

    expect(await db.query('eventos'), isEmpty);
    expect(await db.query('eventos_servicios'), isEmpty);
    expect(await db.query('_sync_queue'), isEmpty);
    final estado = (await db.query('presupuestos', where: 'id = ?', whereArgs: [_presu])).single['estado'];
    expect(estado, 'aprobado');
  });

  test('sin fecha no crea; con la fecha elegida, sí', () async {
    await _cargar(db, fecha: null);
    await expectLater(
      PresupuestosRepository.confirmarEn(db, _presu),
      throwsA(isA<PresupuestoSinFechaException>()),
    );
    expect(await db.query('eventos'), isEmpty);

    final r = await PresupuestosRepository.confirmarEn(db, _presu, fechaEvento: DateTime(2026, 12, 5));
    final ev = (await db.query('eventos', where: 'id = ?', whereArgs: [r.eventoId])).single;
    expect(ev['fecha_evento'], '2026-12-05');
  });

  test('presupuesto que no está en esta PC: error, nada de "creado con éxito"', () async {
    await expectLater(
      PresupuestosRepository.confirmarEn(db, _presu),
      throwsA(isA<PresupuestoNoEncontradoException>()),
    );
  });

  test('sin el cliente en esta PC no crea', () async {
    await _cargar(db, conCliente: false);
    await expectLater(
      PresupuestosRepository.confirmarEn(db, _presu),
      throwsA(isA<PresupuestoSinClienteException>()),
    );
    expect(await db.query('eventos'), isEmpty);
  });

  test('sin ítems no crea', () async {
    await _cargar(db);
    await db.delete('presupuesto_servicios');
    await expectLater(
      PresupuestosRepository.confirmarEn(db, _presu),
      throwsA(isA<PresupuestoSinItemsException>()),
    );
  });

  group('la tarjeta del presupuesto', () {
    Presupuesto conEstado(String estado) => Presupuesto.fromJson({
          'id': _presu,
          'cliente_id': _cliente,
          'tipo_evento': '15_años',
          'fecha_vencimiento': '2026-12-01',
          'estado': estado,
        });

    test('confirmado → VER EVENTO; aprobado → CREAR EVENTO', () {
      expect(accionDelPresupuesto(conEstado('confirmado')), AccionPresupuesto.verEvento);
      expect(accionDelPresupuesto(conEstado('aprobado')), AccionPresupuesto.crearEvento);
    });

    test('un confirmado se sigue viendo aprobado y vuelve como confirmado', () {
      final p = conEstado('confirmado');
      expect(p.estado, EstadoPresupuesto.aprobado);
      expect(p.confirmado, isTrue);
      expect(p.toJson()['estado'], 'confirmado');
      expect(conEstado('aprobado').toJson()['estado'], 'aprobado');
    });
  });
}
