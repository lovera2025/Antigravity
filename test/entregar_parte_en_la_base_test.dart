// La entrega en dos partes (`EntregarParte`) sobre una base SQLite de verdad
// (en memoria, con el esquema entero de la v81: `LocalDatabase.onCreateParaTest`)
// y los repositorios de verdad: `EntradasEntregasRepository` y
// `EntradasRetiroRepository.guardarEn`, en una sola transacción, como
// `entregar_parte_de_la_app.dart`.
//
// `entregar_parte_test.dart` prueba las reglas con equipos en memoria; acá se
// prueba lo que solo una base dice: que cada renglón y la fila completa quedan
// escritos con su entrada en la cola, que lo escrito se vuelve a leer igual
// (columnas, booleanos, números del talonario, horas), que una entrega de las 8
// juntas hecha con la 6.9.x cuenta como las dos partes, y que guardar es todo o
// nada. Nada sube: todo queda en la cola. Sin internet la tablet no escribe la
// fila completa (puede no saber de una anulación que no bajó): la escribe
// `completarLaFila` cuando vuelve la red.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_entregas_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_retiro_repository.dart';
import 'package:arguello_events/features/eventos/services/entrega_por_partes.dart';
import 'package:arguello_events/features/eventos/services/entregar_parte.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

import 'helpers/entrega_por_partes_en_memoria.dart' show RelojDeLaEntrega;

const _evento = 'e0000000-0000-4000-8000-000000000001';

final _ana = ContratoAlumno(
  id: 'c0000000-0000-4000-8000-00000000000a',
  eventoId: _evento,
  nombreAlumno: 'GÓMEZ, ANA',
  cantidadAcompanantes: 2,
  nombresAcompanantes: const ['MAMÁ', 'PAPÁ'],
  montoTotalPactado: 300000,
  saldoDeudor: 0,
  totalCuotas: 9,
  cuotasPagadas: 9,
  numeroMesa: MesasExtraUtils.formatearAsignacionMesas(const [12]),
  createdAt: DateTime(2026, 2, 1),
);

final _pagoEntero = <Map<String, dynamic>>[
  {
    'monto': 300000.0,
    'monto_gross': 300000.0,
    'concepto': 'Cuota Base (9/9)',
    'anulado': 0,
    'fecha_pago': '2026-08-10',
  },
];

DatosDeLaParte _pulseras() => const DatosDeLaParte(
      parte: ParteEntrega.pulseras,
      cantidad: 3,
      parentesco: ParentescoRetiro.madre,
      nombre: 'MADRE, UNA',
      escribioEnPlanilla: true,
    );

DatosDeLaParte _generales({List<TramoTalonario> tramos = const []}) =>
    DatosDeLaParte(
      parte: ParteEntrega.generales,
      cantidad: 5,
      tramos: tramos,
      menores10: 1,
      parentesco: ParentescoRetiro.padre,
      nombre: 'PADRE, UNO',
      escribioEnPlanilla: true,
    );

/// Una tablet con su base SQLite: lee y guarda por los repositorios de
/// verdad, y no sube nada (todo queda en la cola). Con internet, la nube no
/// tiene nada de esta familia todavía.
class _TabletConSuBase implements PuertosDeLaEntrega {
  _TabletConSuBase(this.db, this.reloj);

  final Database db;
  final RelojDeLaEntrega reloj;

  late final entregas = EntradasEntregasRepository(null, abrir: () async => db);

  // Solo se usa `guardarEn`, que no habla con la nube: el cliente no se llama.
  late final retiros = EntradasRetiroRepository(
    SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba'),
  );

  @override
  bool hayInternet = true;

  @override
  Future<LoDeLaNube> deLaNube(String contratoAlumnoId) async {
    if (!hayInternet) throw StateError('sin internet');
    return const LoDeLaNube(retiro: null, renglones: []);
  }

  Future<Map<String, EntradasRetiro>> filas() async => {
        for (final r in await db.query('entradas_retiro'))
          (r['contrato_alumno_id'] as String): EntradasRetiro.fromMap(r),
      };

  @override
  Future<LoDeLaFiesta> leer(String eventoId) async {
    final porAlumno = await entregas.deContratos([_ana.id]);
    return LoDeLaFiesta(
      alumnos: [_ana],
      retiros: await filas(),
      renglones: [for (final l in porAlumno.values) ...l],
    );
  }

  @override
  Future<CuentaDelAlumno> cuentaDe(ContratoAlumno alumno) async =>
      CuentaDelAlumno(pagos: _pagoEntero, moraCobradaHistorial: 0);

  /// Lo mismo que `_PuertosDeLaApp.guardar`: los renglones y la fila, juntos.
  @override
  Future<void> guardar(
    List<EntregaEntradas> renglones, {
    EntradasRetiro? retiro,
  }) =>
      db.transaction((txn) async {
        await entregas.agregarEn(txn, renglones);
        if (retiro != null) await retiros.guardarEn(txn, retiro);
      });

  @override
  Future<bool> subir({
    required List<String> renglones,
    String? retiro,
    required DateTime desde,
  }) async =>
      false;

  @override
  Future<String?> equipo() async => 'tablet-1';

  @override
  DateTime ahora() => reloj.ahora();

  /// Lo que dice esta base de la entrega de Ana.
  Future<EstadoDeLaEntrega> estado() async => EstadoDeLaEntrega.deAlumno(
        _ana,
        retiro: (await filas())[_ana.id],
        renglones: (await entregas.deContratos([_ana.id]))[_ana.id] ?? const [],
      );

  Future<List<Map<String, Object?>>> cola(String tabla) =>
      db.query('_sync_queue', where: 'tabla = ?', whereArgs: [tabla]);

  Future<int> cuantas(String tabla) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $tabla')).single['n']! as int;
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late _TabletConSuBase tablet;
  late int preguntasSinInternet;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 81,
        onCreate: LocalDatabase.onCreateParaTest,
      ),
    );
    tablet = _TabletConSuBase(db, RelojDeLaEntrega());
    preguntasSinInternet = 0;
  });

  tearDown(() => db.close());

  Future<ResultadoDeLaEntrega> entregar(DatosDeLaParte datos) =>
      EntregarParte(tablet).entregar(
        eventoId: _evento,
        contratoAlumnoId: _ana.id,
        datos: datos,
        quien: 'Carla',
        seguirSinInternet: () async {
          preguntasSinInternet++;
          return true;
        },
      );

  Future<ResultadoDeAnular> anular(Set<ParteEntrega> partes, {bool esJefe = true}) =>
      EntregarParte(tablet).anularParte(
        eventoId: _evento,
        contratoAlumnoId: _ana.id,
        partes: partes,
        motivo: 'se anotaron mal los números',
        quien: 'Jefe',
        esJefe: esJefe,
      );

  test('las pulseras un día: un renglón en la base y en la cola, y la fila de '
      'la entrega no se escribe (sin internet)', () async {
    tablet.hayInternet = false;
    final r = await entregar(_pulseras());
    expect(r, isA<Entregada>());
    expect((r as Entregada).subio, isFalse, reason: 'sin internet, espera en la cola');
    expect(preguntasSinInternet, 1);

    expect(await tablet.cuantas('entradas_entregas'), 1);
    expect(await tablet.cuantas('entradas_retiro'), 0,
        reason: 'una entrega a medias no escribe la fila');

    final cola = await tablet.cola('entradas_entregas');
    expect(cola, hasLength(1));
    expect(cola.single['registro_id'], r.renglon.id);
    expect(await tablet.cola('entradas_retiro'), isEmpty);

    // Lo escrito se vuelve a leer igual.
    final leido = (await tablet.entregas.deContratos([_ana.id]))[_ana.id]!.single;
    expect(leido.id, r.renglon.id);
    expect(leido.parte, ParteEntrega.pulseras);
    expect(leido.esEntrega, isTrue);
    expect(leido.cantidad, 3);
    expect(leido.retiroNombre, 'MADRE, UNA');
    expect(leido.escribioEnPlanilla, isTrue);
    expect(leido.hechoPor, 'Carla');
    expect(leido.deviceId, 'tablet-1');
    expect(leido.createdAt, r.renglon.createdAt);

    final e = await tablet.estado();
    expect(e.pulseras.entregada, isTrue);
    expect(e.generales.falta, isTrue);
  });

  test('las generales otro día: el segundo renglón y la fila completa, en la '
      'misma transacción, con su entrada en la cola', () async {
    await entregar(_pulseras());
    final r = await entregar(
      _generales(tramos: const [TramoTalonario(1043, 1047)]),
    ) as Entregada;
    expect(r.todoEntregado, isTrue);
    expect(r.conFilaCompleta, isTrue);

    expect(await tablet.cuantas('entradas_entregas'), 2);
    expect(await tablet.cuantas('entradas_retiro'), 1);
    expect(await tablet.cola('entradas_entregas'), hasLength(2));
    final colaFila = await tablet.cola('entradas_retiro');
    expect(colaFila, hasLength(1));
    expect(colaFila.single['registro_id'], UuidUtils.entradasRetiroId(_ana.id));

    // La fila, leída de la base, es la que ve una PC con la 6.9.x: "Retiró".
    final fila = (await tablet.filas())[_ana.id]!;
    expect(fila.entregado, isTrue);
    expect(fila.vip, 3);
    expect(fila.generales, 5);
    expect(fila.tramos, const [TramoTalonario(1043, 1047)]);
    expect(RetiroEntradas.cambioLaCuenta(fila, RetiroEntradas.entradasDe(_ana)), isFalse);

    // Y esta versión la sigue leyendo por los renglones.
    final e = await tablet.estado();
    expect(e.todoEntregado, isTrue);
    expect(e.generales.tramos, const [TramoTalonario(1043, 1047)]);
    expect(e.generales.menores10, 1);
    expect(e.pulseras.deLaFila, isFalse);

    // Otra vez: ya está, y la base no cambia.
    expect(await entregar(_pulseras()), isA<YaEntregadaEnOtroEquipo>());
    expect(await tablet.cuantas('entradas_entregas'), 2);
  });

  test('sin internet, las dos partes quedan en la base pero la fila completa '
      'no: la escribe completarLaFila cuando vuelve la red', () async {
    tablet.hayInternet = false;
    await entregar(_pulseras());
    final r = await entregar(_generales()) as Entregada;
    expect(r.todoEntregado, isTrue);
    expect(r.conFilaCompleta, isFalse);
    expect(await tablet.cuantas('entradas_entregas'), 2);
    expect(await tablet.cuantas('entradas_retiro'), 0);
    expect((await tablet.estado()).todoEntregado, isTrue,
        reason: 'esta versión ya la ve entregada, por los renglones');

    // Sin red, completarla no hace nada.
    expect(
      await EntregarParte(tablet).completarLaFila(
        eventoId: _evento,
        contratoAlumnoId: _ana.id,
      ),
      ResultadoDeLaFila.sinNube,
    );
    expect(await tablet.cuantas('entradas_retiro'), 0);

    // Vuelve la red: la fila se escribe, con su entrada en la cola.
    tablet.hayInternet = true;
    expect(
      await EntregarParte(tablet).completarLaFila(
        eventoId: _evento,
        contratoAlumnoId: _ana.id,
      ),
      ResultadoDeLaFila.escrita,
    );
    final fila = (await tablet.filas())[_ana.id]!;
    expect(fila.entregado, isTrue);
    expect(fila.vip, 3);
    expect(fila.generales, 5);
    expect(await tablet.cola('entradas_retiro'), hasLength(1));
    expect(await tablet.cuantas('entradas_entregas'), 2,
        reason: 'completar la fila no agrega renglones');
  });

  test('las generales sin número también quedan bien guardadas', () async {
    await entregar(_pulseras());
    final r = await entregar(_generales()) as Entregada;
    expect(r.todoEntregado, isTrue);
    final e = await tablet.estado();
    expect(e.generales.entregada, isTrue);
    expect(e.generales.tramos, isEmpty);
    expect((await tablet.filas())[_ana.id]!.tramos, isEmpty);
  });

  test('una entrega de las 8 juntas hecha con la 6.9.x cuenta como las dos '
      'partes: no se entrega nada más', () async {
    // La fila que deja una PC con la 6.9.x, sin ningún renglón.
    final vieja = RetiroEntradas.nuevaEntrega(
      alumno: _ana,
      entradas: RetiroEntradas.entradasDe(_ana),
      tramos: const [TramoTalonario(2001, 2005)],
      menores10: 0,
      parentesco: ParentescoRetiro.madre,
      nombre: 'MADRE, UNA',
      quien: 'Oficina',
      ahora: DateTime.utc(2026, 11, 15, 12),
    );
    await db.insert('entradas_retiro', vieja.toMap());

    final e = await tablet.estado();
    expect(e.todoEntregado, isTrue);
    expect(e.pulseras.deLaFila, isTrue);
    expect(e.generales.deLaFila, isTrue);

    expect(await entregar(_pulseras()), isA<YaEntregadaEnOtroEquipo>());
    expect(await entregar(_generales()), isA<YaEntregadaEnOtroEquipo>());
    expect(await tablet.cuantas('entradas_entregas'), 0);
    expect(await tablet.cola('entradas_retiro'), isEmpty);
  });

  test('el jefe anula las generales: otro renglón, la fila queda anulada para '
      'la 6.9.x, y las pulseras siguen entregadas', () async {
    await entregar(_pulseras());
    await entregar(_generales(tramos: const [TramoTalonario(1043, 1047)]));

    final r = await anular({ParteEntrega.generales});
    expect(r, isA<Anulada>());

    expect(await tablet.cuantas('entradas_entregas'), 3,
        reason: 'anular es otro renglón: nada se edita ni se borra');
    final e = await tablet.estado();
    expect(e.pulseras.entregada, isTrue);
    expect(e.generales.falta, isTrue);
    expect(e.generales.anulada, isTrue);

    final fila = (await tablet.filas())[_ana.id]!;
    expect(fila.entregado, isFalse, reason: 'una 6.9.x ya no la ve "Retiró"');
    expect(await tablet.cola('entradas_retiro'), hasLength(1),
        reason: 'la misma fila, encolada otra vez: la cola reescribe su entrada');
  });

  test('sin modo jefe no se anula: la base no cambia', () async {
    await entregar(_pulseras());
    await entregar(_generales());
    final antes = await tablet.cuantas('entradas_entregas');
    final colaAntes = (await tablet.cola('entradas_entregas')).length;

    expect(await anular({ParteEntrega.generales}, esJefe: false), isA<NoSeAnulo>());
    expect(await tablet.cuantas('entradas_entregas'), antes);
    expect((await tablet.cola('entradas_entregas')).length, colaAntes);
    expect((await tablet.estado()).todoEntregado, isTrue);
  });

  test('guardar es todo o nada: si la cola falla, no queda ni el renglón ni '
      'la fila', () async {
    await entregar(_pulseras());
    // La cola no se puede escribir (la tapamos): la transacción entera se
    // tiene que deshacer.
    await db.execute('ALTER TABLE _sync_queue RENAME TO _sync_queue_tapada');
    await expectLater(entregar(_generales()), throwsA(anything));
    await db.execute('ALTER TABLE _sync_queue_tapada RENAME TO _sync_queue');

    expect(await tablet.cuantas('entradas_entregas'), 1);
    expect(await tablet.cuantas('entradas_retiro'), 0);
    final e = await tablet.estado();
    expect(e.pulseras.entregada, isTrue);
    expect(e.generales.falta, isTrue);
  });
}
