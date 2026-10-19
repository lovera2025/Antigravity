// Lo que se borra en una PC tiene que desaparecer también en la otra (6.1.1).
//
// El 19-oct-2026 el jefe, desde su PC, borró con la escobita un pago de $60.000
// del 28/05 de DE CARLO, MICAELA ESTEFANIA (pactado $296.100). La PC del
// operario, prendida y cobrando, nunca se enteró: el borrado viajaba solo por
// el aviso al instante (el pulso), que con la PC ocupada se tiraba, y la
// revisión de cada 10 minutos no miraba los pagos. Al cobrarle la entrega de
// ese día, la PC del operario contó los dos pagos y subió un saldo de $176.100
// en vez de $236.100. Lo mismo dejaba renglones de presupuesto borrados en la
// otra PC (en la de la casa había 23).
//
// Corre contra una base SQLite temporal y una nube simulada: no sale nada de la
// PC.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/services/borrados_de_otra_pc.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';

const _alumno = '1308f6f9-ea42-4b73-a329-ca3080394a58';
const _evento = 'eeeeeeee-0000-4000-8000-00000000000c';

/// El pago que el jefe borró: sigue en esta PC.
const _borrado = '39bdd923-9ffd-4e02-9cea-d99f7655a9d2';

/// La entrega de ese día, que está en las dos.
const _deHoy = 'e27b01aa-0000-4000-8000-000000000001';

/// Un cobro de esta PC que todavía no subió.
const _sinSubir = 'aaaaaaaa-0000-4000-8000-000000000002';

/// Un pago de otra PC que acá todavía no bajó.
const _sinBajar = 'bbbbbbbb-0000-4000-8000-000000000003';

class _Conexion extends ConnectivityService {
  _Conexion(this.estado);
  final AppConnectivity estado;
  @override
  AppConnectivity get currentStatus => estado;
  @override
  Future<bool> wakeUpCloud() async => true;
}

Map<String, Object?> _contrato({double saldo = 176100}) => {
      'id': _alumno,
      'evento_id': _evento,
      'nombre_alumno': 'DE CARLO, MICAELA ESTEFANIA',
      'monto_total_pactado': 296100,
      'saldo_deudor': saldo,
      'cuotas_pagadas': 0,
      'total_cuotas': 1,
      'dia_vencimiento_mensual': 10,
      'created_at': '2026-03-30T03:00:00+00:00',
      'mora_pendiente_tracked': 0,
      'mora_cobrada_offset': 0,
      'mora_tracked_ajuste': 0,
    };

Map<String, Object?> _pago(String id, String fecha, String concepto) => {
      'id': id,
      'contrato_alumno_id': _alumno,
      'fecha_pago': fecha,
      'created_at': fecha,
      'updated_at': fecha,
      'concepto': concepto,
      'monto': 60000,
      'monto_gross': 60000,
      'medio_pago': 'Efectivo',
      'anulado': 0,
    };

final _pagoBorrado = _pago(
  _borrado,
  '2026-05-28T21:53:18.442593+00:00',
  '2 Cuotas (Cuota Base)',
);
final _pagoDeHoy = _pago(
  _deHoy,
  '2026-10-19T21:09:41.688135+00:00',
  'Entrega parcial — Cuota Base (1/1)',
);

/// La nube: qué tiene cada tabla, y lo que pasa mientras contesta.
class _Nube {
  final filas = <String, List<Map<String, Object?>>>{};
  final pedidas = <String>[];

  /// Una cuenta que no coincide con lo que se devuelve: una foto incompleta.
  final cuentaDe = <String, int>{};

  /// Lo que pasa en la PC mientras la nube contesta esa tabla.
  final alPedir = <String, Future<void> Function()>{};

  /// Pedidos que se quedan esperando: así la PC queda ocupada.
  final frenadas = <String, Completer<void>>{};

  http.Client get cliente => MockClient((req) async {
        final tabla = req.url.pathSegments.last;
        pedidas.add('${req.method} $tabla');
        final freno = frenadas[tabla];
        if (freno != null) await freno.future;
        final antes = alPedir[tabla];
        if (antes != null) await antes();

        final q = req.url.queryParameters;
        var lista = List<Map<String, Object?>>.from(filas[tabla] ?? const []);
        for (final e in q.entries) {
          if (!e.value.startsWith('eq.')) continue;
          final v = e.value.substring(3);
          lista = lista.where((f) => f[e.key]?.toString() == v).toList();
        }
        final total = cuentaDe[tabla] ?? lista.length;
        final desde = int.tryParse(q['offset'] ?? '') ?? 0;
        final tope = int.tryParse(q['limit'] ?? '');
        var pagina = lista.skip(desde).toList();
        if (tope != null) pagina = pagina.take(tope).toList();
        final headers = {
          'content-type': 'application/json',
          'content-range': pagina.isEmpty
              ? '*/$total'
              : '$desde-${desde + pagina.length - 1}/$total',
        };
        if (req.method == 'HEAD') {
          return http.Response('', 200, headers: headers, request: req);
        }
        return http.Response(
          jsonEncode(pagina),
          200,
          headers: headers,
          request: req,
        );
      });
}

Future<Set<String>> _pagosEnLaPc() async {
  final db = await LocalDatabase.instance;
  final filas = await db.query('pagos_contrato_alumno', columns: ['id']);
  return {for (final f in filas) f['id'] as String};
}

Future<double> _saldoEnLaPc() async {
  final db = await LocalDatabase.instance;
  final filas = await db.query(
    'contratos_alumnos',
    columns: ['saldo_deudor'],
    where: 'id = ?',
    whereArgs: [_alumno],
  );
  return (filas.first['saldo_deudor'] as num).toDouble();
}

Future<List<Map<String, Object?>>> _cola() async {
  final db = await LocalDatabase.instance;
  return db.query('_sync_queue');
}

Future<String> _constancia() async {
  final base = File(await LocalDatabase.dbPath);
  final f = File(
    '${base.parent.path}${Platform.pathSeparator}${BorradosConstancia.archivo}',
  );
  return f.existsSync() ? f.readAsStringSync() : '';
}

void main() {
  group('qué se revisa', () {
    test('toda tabla que se baja está en una lista o en la otra', () {
      final revisadas = SyncEngine.tablasQueSeRevisan.toSet();
      final sinRevisar = SyncEngine.tablasSinRevisarBorrados.keys.toSet();
      final bajadas = SyncEngine.tablasQueSeBajan;

      expect(
        bajadas.difference(revisadas).difference(sinRevisar),
        isEmpty,
        reason: 'una tabla nueva que se baje tiene que decir si se le revisa '
            'lo borrado en otra PC, y si no, por qué',
      );
      expect(revisadas.intersection(sinRevisar), isEmpty);
      expect(revisadas.difference(bajadas), isEmpty);
      expect(revisadas.length, SyncEngine.tablasQueSeRevisan.length,
          reason: 'sin repetidas');
    });

    test('lo que se borra a mano se revisa', () {
      // Cada `SyncQueue.enqueue` con un borrado de una tabla escrita a mano, y
      // las tablas que borra la escobita de Mi Empresa (`mapeoTablas`).
      final borradas = <String>{};
      final enqueue = RegExp(
        r"tabla:\s*'([a-z_]+)',\s*operacion:\s*SyncOperation\.delete",
      );
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final texto = f.readAsStringSync();
        borradas.addAll(enqueue.allMatches(texto).map((m) => m.group(1)!));
      }

      final finanzas = File(
        'lib/features/mi_empresa/repositories/finanzas_repository.dart',
      ).readAsStringSync();
      final mapeo = RegExp(r'final mapeoTablas = \{([\s\S]*?)\};')
          .firstMatch(finanzas)!
          .group(1)!;
      borradas.addAll(
        RegExp(r"'[a-z_]+':\s*'([a-z_]+)'")
            .allMatches(mapeo)
            .map((m) => m.group(1)!),
      );
      borradas.addAll(
        RegExp(r"_eliminarFilaSync\('([a-z_]+)'")
            .allMatches(finanzas)
            .map((m) => m.group(1)!),
      );

      // Que la lectura encontró lo que tiene que encontrar.
      expect(borradas, containsAll(['pagos_contrato_alumno', 'egresos']));

      final revisadas = SyncEngine.tablasQueSeRevisan.toSet();
      final faltan = borradas
          .where(SyncEngine.tablasQueSeBajan.contains)
          .where((t) => !revisadas.contains(t) && t != 'invitados')
          .toList();
      expect(
        faltan,
        isEmpty,
        reason: 'si se borra a mano y no se revisa, en la otra PC queda para '
            'siempre (así le quedó a DE CARLO el pago que se borró)',
      );
    });
  });

  group('comparar los pagos de un alumno', () {
    test('sobra lo que la nube no tiene, menos lo que espera subir', () {
      final r = compararPagosDelAlumno(
        locales: {_borrado, _deHoy, _sinSubir},
        pendientes: {_sinSubir},
        enLaNube: {_deHoy, _sinBajar},
        fotoCompleta: true,
      );
      expect(r.deMas, {_borrado});
      expect(r.faltan, {_sinBajar});
    });

    test('sin foto completa no sobra ni falta nada', () {
      final r = compararPagosDelAlumno(
        locales: {_borrado, _deHoy},
        pendientes: const {},
        enLaNube: {_deHoy},
        fotoCompleta: false,
      );
      expect(r.deMas, isEmpty);
      expect(r.faltan, isEmpty);
    });
  });

  group('la constancia', () {
    test('un pago dice de quién era, cuánto, de qué día y qué era', () {
      final r = renglonDeLoBorrado(
        'pagos_contrato_alumno',
        _pagoBorrado,
        alumno: 'DE CARLO, MICAELA ESTEFANIA',
      );
      expect(r, contains('PAGO'));
      expect(r, contains('DE CARLO, MICAELA ESTEFANIA'));
      expect(r, contains('60.000'));
      expect(r, contains('28/05/2026'));
      expect(r, contains('"2 Cuotas (Cuota Base)"'));
    });

    test('el bloque dice cuándo y por qué camino se enteró', () {
      final t = BorradosConstancia.textoDe(
        ['PAGO · A', 'PAGO · B'],
        DateTime(2026, 10, 19, 18, 9),
        CaminoDelBorrado.aviso,
      );
      expect(t, startsWith('19/10/2026 18:09'));
      expect(t, contains('por el aviso de la otra PC'));
      expect(t, contains('2 cosa(s)'));
    });
  });

  group('una PC con un pago que se borró en otra', () {
    late Directory docs;
    late _Nube nube;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('borrados_otra_pc');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path,
      );
      nube = _Nube();

      // Esta PC: el alumno con el saldo que subió contando los dos pagos, y
      // los dos pagos.
      final db = await LocalDatabase.instance;
      await db.insert('contratos_alumnos', _contrato());
      await db.insert('pagos_contrato_alumno', _pagoBorrado);
      await db.insert('pagos_contrato_alumno', _pagoDeHoy);

      // La nube: el alumno, y solo el pago de hoy.
      nube.filas['contratos_alumnos'] = [_contrato(saldo: 236100)];
      nube.filas['pagos_contrato_alumno'] = [_pagoDeHoy];
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    SupabaseClient cliente() {
      final c = SupabaseClient('https://nube.test', 'anon-de-test',
          httpClient: nube.cliente);
      c.auth.stopAutoRefresh();
      addTearDown(c.dispose);
      return c;
    }

    SyncEngine motor({AppConnectivity estado = AppConnectivity.online}) {
      final m = SyncEngine(connectivity: _Conexion(estado), supabase: cliente());
      addTearDown(m.dispose);
      return m;
    }

    test(
        'al abrir el alumno se saca el pago y la cuenta vuelve a \$236.100, '
        'sin mandar ningún borrado', () async {
      final m = motor();

      expect(await m.revisarPagosDelAlumno(_alumno), 1);

      expect(await _pagosEnLaPc(), {_deHoy});
      expect(await _saldoEnLaPc(), 236100);
      final cola = await _cola();
      expect(
        cola.where((e) => e['operacion'] == SyncOperation.delete.name),
        isEmpty,
        reason: 'en la nube ya no está: mandar un borrado sería inventarlo',
      );
      final subida = cola.singleWhere((e) => e['tabla'] == 'contratos_alumnos');
      expect(
        (jsonDecode(subida['payload'] as String) as Map)['saldo_deudor'],
        236100,
        reason: 'esta PC le había pisado el saldo a la nube: sube el bueno',
      );
      final constancia = await _constancia();
      expect(constancia, contains('al abrir el alumno'));
      expect(constancia, contains('DE CARLO, MICAELA ESTEFANIA'));
    });

    test('el historial de pagos ya viene sin el pago borrado', () async {
      final m = motor();
      final repo = ContratosRepository(
        cliente(),
        _Conexion(AppConnectivity.online),
        revisarPagosEnLaNube: (id, rehacer) =>
            m.revisarPagosDelAlumno(id, rehacerCuenta: rehacer),
      );

      final historial = await repo.getHistorialPagosAlumno(_alumno);

      expect([for (final p in historial) p['id']], [_deHoy]);
    });

    test('antes de cobrar, la cuenta no cuenta el pago borrado', () async {
      final m = motor();
      final repo = ContratosRepository(
        cliente(),
        _Conexion(AppConnectivity.online),
        revisarPagosEnLaNube: (id, rehacer) =>
            m.revisarPagosDelAlumno(id, rehacerCuenta: rehacer),
      );

      await repo.recalcularProgresoContrato(_alumno);

      expect(await _pagosEnLaPc(), {_deHoy});
      expect(
        await _saldoEnLaPc(),
        236100,
        reason: 'con el pago adentro daba \$176.100 y eso subía',
      );
    });

    test('un cobro que espera subir no se toca', () async {
      final db = await LocalDatabase.instance;
      await db.insert(
        'pagos_contrato_alumno',
        _pago(_sinSubir, '2026-10-19T22:00:00+00:00', 'Cuota Base (1/1)'),
      );
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: _sinSubir,
        payload: {'id': _sinSubir},
      );

      expect(await motor().revisarPagosDelAlumno(_alumno), 1);

      expect(await _pagosEnLaPc(), {_deHoy, _sinSubir});
    });

    test('con una foto incompleta no se toca nada', () async {
      nube.cuentaDe['pagos_contrato_alumno'] = 3;

      expect(await motor().revisarPagosDelAlumno(_alumno), 0);

      expect(await _pagosEnLaPc(), {_borrado, _deHoy});
    });

    test('si la nube no devuelve ni el alumno, no se toca nada', () async {
      // Una sesión vencida lee cero en todo: no es que le borraron todo.
      nube.filas.clear();

      expect(await motor().revisarPagosDelAlumno(_alumno), 0);

      expect(await _pagosEnLaPc(), {_borrado, _deHoy});
    });

    test('si le borraron el único pago y el alumno se ve, se saca', () async {
      final db = await LocalDatabase.instance;
      await db.delete('pagos_contrato_alumno', where: 'id = ?', whereArgs: [_deHoy]);
      nube.filas['pagos_contrato_alumno'] = [];

      expect(await motor().revisarPagosDelAlumno(_alumno), 1);

      expect(await _pagosEnLaPc(), isEmpty);
    });

    test('sin internet no consulta ni saca nada, y no demora', () async {
      final m = motor(estado: AppConnectivity.offline);

      expect(await m.revisarPagosDelAlumno(_alumno), 0);

      expect(nube.pedidas, isEmpty);
      expect(await _pagosEnLaPc(), {_borrado, _deHoy});
    });

    test('si le falta bajar un pago, saca el borrado pero no rehace la cuenta',
        () async {
      nube.filas['pagos_contrato_alumno'] = [
        _pagoDeHoy,
        _pago(_sinBajar, '2026-10-19T22:30:00+00:00', 'Cuota Base (1/1)'),
      ];

      expect(await motor().revisarPagosDelAlumno(_alumno), 1);

      expect(await _pagosEnLaPc(), {_deHoy});
      expect(
        (await _cola()).where((e) => e['tabla'] == 'contratos_alumnos'),
        isEmpty,
        reason: 'sin el pago que falta, la cuenta daría que debe de más, y '
            'subiría',
      );
    });

    test('la revisión de cada 10 minutos lo saca igual', () async {
      await motor().revisarLoBorradoEnOtraPc();

      expect(await _pagosEnLaPc(), {_deHoy});
      expect(await _saldoEnLaPc(), 236100);
      expect(await _constancia(), contains('por la revisión de lo borrado'));
    });

    test('un cobro que sube en el medio de la revisión no se toma por borrado',
        () async {
      // Esta PC cobró y el cobro está en la cola. Mientras la revisión lee la
      // nube, el cobro sube y sale de la cola, pero la página de la nube ya se
      // había leído sin él. Si la revisión mirara la cola después de la nube,
      // como hasta la 6.1.0, no lo vería en ningún lado y lo borraría.
      final db = await LocalDatabase.instance;
      await db.delete('pagos_contrato_alumno', where: 'id = ?', whereArgs: [_borrado]);
      await db.insert(
        'pagos_contrato_alumno',
        _pago(_sinSubir, '2026-10-19T22:00:00+00:00', 'Cuota Base (1/1)'),
      );
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: _sinSubir,
        payload: {'id': _sinSubir},
      );
      nube.alPedir['pagos_contrato_alumno'] = () async {
        await db.delete(
          '_sync_queue',
          where: 'registro_id = ?',
          whereArgs: [_sinSubir],
        );
      };

      await motor().revisarLoBorradoEnOtraPc();

      expect(await _pagosEnLaPc(), {_deHoy, _sinSubir});
    });

    test('la cuenta de cada ciclo: si en la nube hay menos, lo saca', () async {
      await motor().contarParaVerBorrados();

      expect(await _pagosEnLaPc(), {_deHoy});
      expect(await _constancia(), contains('porque en la nube había menos'));
    });

    test('la cuenta de cada ciclo no hace nada si las cuentas dan', () async {
      nube.filas['pagos_contrato_alumno'] = [_pagoBorrado, _pagoDeHoy];

      await motor().contarParaVerBorrados();

      expect(await _pagosEnLaPc(), {_borrado, _deHoy});
      expect(
        nube.pedidas.where((p) => p == 'GET pagos_contrato_alumno'),
        isEmpty,
        reason: 'con las cuentas iguales no se bajan los ids',
      );
    });

    test('el aviso que llega con la PC ocupada se aplica igual', () async {
      // La nube vacía: así la revisión que corre con la bajada no puede sacar
      // nada (cero contra algo es sesión o permisos), y lo único que saca el
      // pago es el aviso.
      nube.filas.clear();
      final freno = Completer<void>();
      nube.frenadas['clientes'] = freno;
      final m = motor();

      final bajada = m.pullRemote();
      m.recibirPulso({
        'payload': {
          'origen': 'pc-del-jefe',
          'tablas': <String>[],
          'borrados': {
            'pagos_contrato_alumno': [_borrado],
          },
        },
      });
      // El aviso se atiende a los 400 ms: la PC sigue ocupada bajando.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(await _pagosEnLaPc(), {_borrado, _deHoy});

      freno.complete();
      await bajada;
      await Future<void>.delayed(const Duration(seconds: 4));

      expect(
        await _pagosEnLaPc(),
        {_deHoy},
        reason: 'hasta la 6.1.0 el aviso se tiraba y el pago quedaba para '
            'siempre',
      );
      expect(await _constancia(), contains('por el aviso de la otra PC'));
    });
  });
}
