import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/entradas/cuentas/linea_de_subida.dart';
import 'package:arguello_events/features/entradas/datos/entradas_local.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;

import 'helpers/nube_de_prueba.dart' show RedDePrueba;

/// La tabla de la v82 (las entradas para rendir) en el motor de sincronización,
/// en el SQL de la nube y en la base: **la nube y la PC dicen lo mismo** (regla
/// 56 de `docs/SPEC_entradas_para_rendir_2026-11-20.md`). Mismo modelo que
/// `sync_tablas_v81_test.dart`: las listas del motor son privadas y se leen del
/// texto del archivo. Y al final, el motor de verdad contra una nube de mentira:
/// lo que se da y se rinde sube entero y después de su venta, y lo que baja
/// queda igual en la base. No sale nada de la PC.
void main() {
  sqfliteFfiInit();

  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  final motor = leer('lib/core/services/sync_engine.dart');
  final cola = leer('lib/core/database/sync_queue.dart');
  final sql = leer('supabase/migrations/20261121120000_entradas_para_rendir.sql');
  const tabla = 'entradas_para_rendir';

  String sinComentarios(String texto) => [
        for (final l in texto.split('\n'))
          if (!l.trimLeft().startsWith('--')) l,
      ].join('\n');

  String declaracion(String nombre, String cierre) {
    final i = motor.indexOf(RegExp('static const [^;]*\\b$nombre = '));
    expect(i, greaterThanOrEqualTo(0), reason: 'no encontré $nombre');
    final f = motor.indexOf('\n  $cierre;', i);
    expect(f, greaterThan(i), reason: 'no encontré el final de $nombre');
    return motor.substring(i, f);
  }

  Set<String> columnasDelMotor(String tabla) {
    final m = RegExp("'$tabla': \\[(.*?)\\]", dotAll: true).firstMatch(motor);
    expect(m, isNotNull, reason: '$tabla no está en las columnas del motor');
    return {
      for (final c in RegExp("'([a-z_0-9]+)'").allMatches(m!.group(1)!)) c.group(1)!,
    };
  }

  /// Cada columna del `create table` de la nube, con lo que dice al lado
  /// ("uuid not null", "integer not null default 0").
  Map<String, String> columnasDelSql(String tabla) {
    final crear = RegExp(
      'create table if not exists public\\.$tabla \\(([\\s\\S]*?)\\n\\);',
    ).firstMatch(sql);
    expect(crear, isNotNull, reason: '$tabla no está en el SQL');
    return {
      for (final l in crear!.group(1)!.split('\n'))
        if (l.trim().isNotEmpty)
          l.trim().split(' ').first:
              l.trim().replaceFirst(RegExp(r',$'), '').split(' ').skip(1).join(' '),
    };
  }

  final ahora = DateTime.utc(2026, 11, 21, 15);
  const evento = 'e0000000-0000-4000-8000-000000000001';
  const alumno = 'c0000000-0000-4000-8000-000000000001';
  const venta = 'f0000000-0000-4000-8000-000000000001';
  const caja = 'b0000000-0000-4000-8000-000000000001';

  // Un renglón de cada clase, armados como los arma la app.
  final dio = MovimientoParaRendir.dio(
    eventoId: evento,
    personaNombre: '  Juan   Pérez ',
    cantidad: 20,
    tramos: const [TramoTalonario(1201, 1220)],
    precio: 8000,
    nombrePrecio: 'Entrada anticipada',
    hechoPor: 'Jefe',
    deviceId: 'pc-1',
    ahora: ahora,
  );
  final deUnAlumno = MovimientoParaRendir.dio(
    eventoId: evento,
    personaNombre: 'PÉREZ, ANA',
    personaContacto: '3794 000000',
    contratoAlumnoId: alumno,
    cantidad: 5,
    tramos: const [TramoTalonario(1301, 1303), TramoTalonario(1401, 1402)],
    precio: 10000,
    nombrePrecio: 'Entrada general',
    nota: 'para la familia del abuelo',
    hechoPor: 'Jefe',
    deviceId: 'pc-1',
    ahora: ahora,
  );
  final vendio = MovimientoParaRendir.vendio(
    dio,
    cantidad: 15,
    ventaId: venta,
    cajaEntradasId: caja,
    hechoPor: 'Carla',
    deviceId: 'tablet-1',
    ahora: ahora.add(const Duration(days: 3)),
  );
  final devolvio = MovimientoParaRendir.devolvio(
    dio,
    tramos: const [TramoTalonario(1216, 1220)],
    hechoPor: 'Carla',
    deviceId: 'tablet-1',
    ahora: ahora.add(const Duration(days: 3)),
  );
  final noVolvieron = MovimientoParaRendir.noVolvieron(
    deUnAlumno,
    cantidad: 1,
    motivo: 'la perdió',
    hechoPor: 'Jefe',
    deviceId: 'pc-1',
    ahora: ahora.add(const Duration(days: 4)),
  );
  final anulo = MovimientoParaRendir.anulo(
    devolvio,
    motivo: 'no las trajo',
    hechoPor: 'Jefe',
    deviceId: 'pc-1',
    ahora: ahora.add(const Duration(days: 5)),
  );
  final todos = {
    'dio': dio,
    'dio de un alumno': deUnAlumno,
    'vendio': vendio,
    'devolvio': devolvio,
    'no_volvieron': noVolvieron,
    'anulo': anulo,
  };

  /// La tabla de la sección 3 de la SPEC: el tipo en la PC, el de la nube y si
  /// es obligatoria (en las dos dice lo mismo).
  const tipos = {
    'id': ('TEXT', 'uuid', true),
    'evento_id': ('TEXT', 'uuid', true),
    'bloque_id': ('TEXT', 'uuid', true),
    'que': ('TEXT', 'text', true),
    'persona_nombre': ('TEXT', 'text', false),
    'persona_contacto': ('TEXT', 'text', false),
    'contrato_alumno_id': ('TEXT', 'uuid', false),
    'cantidad': ('INTEGER', 'integer', true),
    'numeros': ('TEXT', 'text', false),
    'precio': ('REAL', 'numeric', false),
    'nombre_precio': ('TEXT', 'text', false),
    'con_pulseras': ('INTEGER', 'integer', true),
    'venta_id': ('TEXT', 'uuid', false),
    'caja_entradas_id': ('TEXT', 'uuid', false),
    'anula_id': ('TEXT', 'uuid', false),
    'motivo': ('TEXT', 'text', false),
    'nota': ('TEXT', 'text', false),
    'hecho_por': ('TEXT', 'text', false),
    'device_id': ('TEXT', 'text', false),
    'created_at': ('TEXT', 'timestamptz', true),
    'updated_at': ('TEXT', 'timestamptz', true),
  };

  group('la nube y la PC dicen lo mismo', () {
    test('el modelo, la base, el motor y el SQL tienen las mismas columnas',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV82(db);
      final enLaBase = {
        for (final c in await db.rawQuery('PRAGMA table_info($tabla)'))
          c['name'] as String,
      };
      await db.close();
      final delModelo = dio.toMap().keys.toSet();
      expect(delModelo, hasLength(21));
      expect(delModelo, tipos.keys.toSet(), reason: 'la tabla de la SPEC');
      for (final m in todos.entries) {
        expect(m.value.toMap().keys.toSet(), delModelo, reason: m.key);
      }
      expect(enLaBase, delModelo, reason: 'base y modelo');
      expect(columnasDelMotor(tabla), delModelo, reason: 'motor y modelo');
      expect(columnasDelSql(tabla).keys.toSet(), delModelo, reason: 'SQL y modelo');
      expect(EntradasLocal.tablaParaRendir, tabla);
    });

    test('cada columna con su tipo, y obligatoria en las dos o en ninguna',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV82(db);
      final pragma = {
        for (final c in await db.rawQuery('PRAGMA table_info($tabla)'))
          c['name'] as String: c,
      };
      await db.close();
      final nube = columnasDelSql(tabla);
      for (final e in tipos.entries) {
        final (pc, enLaNube, obligatoria) = e.value;
        final c = pragma[e.key]!;
        expect(c['type'], pc, reason: '${e.key} en la PC');
        final linea = nube[e.key]!;
        expect(linea.split(' ').first, enLaNube, reason: '${e.key} en la nube: $linea');
        if (e.key == 'id') {
          expect(c['pk'], 1);
          expect(linea, 'uuid primary key');
          continue;
        }
        expect(c['notnull'] == 1, obligatoria, reason: '${e.key} en la PC');
        expect(linea.contains('not null'), obligatoria, reason: '${e.key} en la nube');
      }
      // Las dos casillas de números arrancan en 0 en los dos lados: una fila que
      // llega sin ellas no se traba.
      for (final col in ['cantidad', 'con_pulseras']) {
        expect(pragma[col]!['dflt_value'], '0', reason: col);
        expect(nube[col], 'integer not null default 0', reason: col);
      }
    });

    test('los mismos índices en la PC y en la nube, y ninguno único', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV82(db);
      final indices = await db.rawQuery('PRAGMA index_list($tabla)');
      final enLaPc = <String>{};
      for (final i in indices) {
        if (i['origin'] == 'pk') continue; // el del id
        expect(i['unique'], 0, reason: '${i['name']} no puede ser único');
        for (final c in await db.rawQuery("PRAGMA index_info('${i['name']}')")) {
          enLaPc.add(c['name'] as String);
        }
      }
      await db.close();
      final enLaNube = {
        for (final m in RegExp('on public\\.$tabla\\(([a-z_]+)')
            .allMatches(sinComentarios(sql)))
          m.group(1)!,
      };
      expect(enLaPc, {'evento_id', 'bloque_id', 'venta_id', 'updated_at'});
      expect(enLaNube, enLaPc);
    });

    // En la nube son uuid: un `''` ahí traba la fila en la cola para siempre.
    test('los vínculos van en null o con un id de verdad, nunca vacíos', () {
      final deUuid = {
        for (final e in columnasDelSql(tabla).entries)
          if (e.value.startsWith('uuid')) e.key,
      };
      expect(deUuid, {
        'id',
        'evento_id',
        'bloque_id',
        'contrato_alumno_id',
        'venta_id',
        'caja_entradas_id',
        'anula_id',
      });
      for (final m in todos.entries) {
        final fila = m.value.toMap();
        for (final col in deUuid) {
          final v = fila[col];
          expect(v == null || (v is String && v.length == 36), isTrue,
              reason: '${m.key}.$col = "$v"');
        }
      }
      final sinVinculos = dio.toMap();
      for (final col in ['contrato_alumno_id', 'venta_id', 'caja_entradas_id', 'anula_id']) {
        expect(sinVinculos[col], isNull, reason: col);
      }
      // Y uno vacío que llega de algún lado se lee null.
      final conVacios = MovimientoParaRendir.fromMap({
        ...vendio.toMap(),
        'contrato_alumno_id': '',
        'anula_id': '',
      });
      expect(conVacios.toMap()['contrato_alumno_id'], isNull);
      expect(conVacios.toMap()['anula_id'], isNull);
    });

    test('va y vuelve de la base igual, cada clase de renglón', () {
      for (final m in todos.entries) {
        expect(MovimientoParaRendir.fromMap(m.value.toMap()).toMap(), m.value.toMap(),
            reason: m.key);
      }
      final f = dio.toMap();
      expect(f['que'], 'dio');
      expect(f['bloque_id'], dio.id);
      expect(f['numeros'], '1201-1220');
      expect(f['precio'], 8000);
      expect(f['con_pulseras'], 0, reason: 'la pulsera no se vende');
      expect(vendio.toMap()['bloque_id'], dio.id);
      expect(anulo.toMap()['anula_id'], devolvio.id);
      expect(anulo.toMap()['numeros'], isNull, reason: 'un anulo no lleva números');
    });

    test('y de la nube también: los números como vienen, las fechas con zona', () {
      final deLaNube = Map<String, dynamic>.from(deUnAlumno.toMap())
        ..['precio'] = 10000
        ..['cantidad'] = 5.0
        ..['con_pulseras'] = 0
        ..['created_at'] = '2026-11-21T15:00:00+00:00';
      final r = MovimientoParaRendir.fromMap(deLaNube);
      expect(r.precio, 10000.0);
      expect(r.cantidad, 5);
      expect(r.conPulseras, isFalse);
      expect(r.tramos, deUnAlumno.tramos);
      expect(r.contratoAlumnoId, alumno);
    });

    test('un renglón que esta versión no conoce vuelve igual', () {
      final raro = MovimientoParaRendir.fromMap({...dio.toMap(), 'que': 'presto'});
      expect(raro.que, isNull);
      expect(raro.toMap()['que'], 'presto');
    });
  });

  group('en las listas del motor', () {
    test('baja, en la bajada general y por su marca de tiempo', () {
      final incrementales = declaracion('_incrementalColumns', '}');
      expect(incrementales, contains("'$tabla': 'updated_at'"));
      expect(motor, contains("_pullTable(db, '$tabla', 'updated_at')"));
      expect(SyncEngine.tablasQueSeBajan, contains(tabla));
    });

    test('baja con lo del cobro: es plata, como la venta', () {
      expect(SyncEngine.tablasDelCobro, contains(tabla));
      expect(SyncEngine.tablasDeCarga, isNot(contains(tabla)));
      expect(SyncEngine.tablasDelCobro, contains('entradas_ventas'));
    });

    test('baja con "Lista para trabajar sin internet": la tablet frena números y rinde sin red',
        () {
      expect(SyncEngine.tablasDeLaPuerta, contains(tabla));
      expect(SyncEngine.tablasDeLaPuerta, contains('entradas_ventas'));
      expect(SyncEngine.tablasDeLaPuerta, contains('entradas_anulaciones'));
    });

    test('sube después de su venta', () {
      expect(motor, contains("if (table == '$tabla') return 5;"));
      expect(motor, contains("if (table == 'entradas_ventas') return 4;"));
    });

    test('un renglón encolado no se descarta nunca: no es hija en la limpieza de la cola',
        () {
      expect(cola, isNot(contains("'$tabla'")));
    });

    test('no está en ninguna lista que borre filas locales, y dice por qué', () {
      final reconciliar = declaracion('_tablasAReconciliar', ']');
      final cascada = declaracion('_hijasEnCascada', '}');
      expect(reconciliar, isNot(contains("'$tabla'")));
      expect(cascada, isNot(contains("'$tabla'")));
      expect(SyncEngine.tablasQueSeRevisan, isNot(contains(tabla)));
      final motivo = SyncEngine.tablasSinRevisarBorrados[tabla];
      expect(motivo, contains('solo se agregan renglones'));
      expect(motivo, contains('anular es otro renglón'));
    });

    test('no es una de las cinco de la venta de la v80', () {
      expect(EntradasLocal.tablas, hasLength(5));
      expect(EntradasLocal.tablas, isNot(contains(tabla)));
    });
  });

  group('el SQL de la nube', () {
    final codigo = sinComentarios(sql).toLowerCase();

    test('sin CHECK, sin clave foránea y sin índice único', () {
      // `with check (...)` es de la policy, no un CHECK de la tabla.
      expect(codigo, isNot(matches(RegExp(r'(?<!with )\bcheck\s*\('))));
      expect(codigo, isNot(contains('references')));
      expect(codigo, isNot(contains('unique')));
    });

    test('solo crea: no toca ninguna tabla que ya exista', () {
      expect(
        codigo,
        isNot(matches(RegExp(r'\b(drop table|delete from|update public\.|insert into|alter table public\.(?!%i))\b'))),
      );
      expect(RegExp(r'create table (?!if not exists)').hasMatch(codigo), isFalse);
      expect(RegExp(r'create index (?!if not exists)').hasMatch(codigo), isFalse);
      final nombradas = {
        for (final m in RegExp(r'public\.([a-z_]+)').allMatches(codigo)) m.group(1)!,
      }..remove('update_updated_at_column');
      expect(nombradas, {tabla});
      for (final ajena in [
        'contratos_alumnos',
        'pagos_contrato_alumno',
        'sesiones_caja',
        'entradas_retiro',
        'entradas_ventas',
        'entradas_entregas',
      ]) {
        expect(codigo, isNot(contains(ajena)), reason: ajena);
      }
    });

    test('índices por fiesta, por bloque, por venta y por fecha de cambio', () {
      expect(codigo, contains('on public.$tabla(evento_id)'));
      expect(codigo, contains('on public.$tabla(bloque_id)'));
      expect(codigo, contains('on public.$tabla(venta_id)'));
      expect(codigo, contains('on public.$tabla(updated_at desc)'));
    });

    test('con la policy de los usuarios logueados y los dos disparadores de updated_at',
        () {
      final lista = RegExp(r'array\[([\s\S]*?)\]').firstMatch(sql)!.group(1)!;
      final conRls = {
        for (final m in RegExp(r"'([a-z_]+)'").allMatches(lista)) m.group(1)!,
      };
      expect(conRls, {tabla});
      expect(sql, contains('enable row level security'));
      expect(sql, contains("t || '_all_authenticated'"));
      expect(sql, contains("auth.role() = ''authenticated''"));
      expect(sql, contains('before insert on public.%1\$I'));
      expect(sql, contains('before update on public.%1\$I'));
      expect(sql, contains('set_updated_at_ins_'));
      expect(sql, contains('set_updated_at_upd_'));
      expect(sql, contains('update_updated_at_column()'));
    });

    test('no entra a Realtime', () {
      expect(codigo, isNot(contains('supabase_realtime')));
      expect(codigo, isNot(contains('publication')));
    });

    test('trae su ROLLBACK, y al final las consultas de antes y después', () {
      expect(sql, contains('-- ROLLBACK: drop table if exists public.$tabla;'));
      expect(sql, contains('drop policy if exists "${tabla}_all_authenticated"'));
      expect(sql, contains('(select count(*) from public.contratos_alumnos)'));
      expect(sql, contains('(select count(*) from public.pagos_contrato_alumno)'));
      expect(sql, contains('(select count(*) from public.entradas_ventas)'));
      expect(sql, contains("and tablename = '$tabla'"));
    });
  });

  // El motor de verdad, sobre una base temporal y una nube de mentira que anota
  // lo que le mandan. Si la tabla faltara en alguna lista del motor, acá se ve
  // como se vería en la PC: no baja, baja sin una columna, o sube antes que la
  // venta que nombra.
  group('con el motor, contra una nube de mentira', () {
    late Directory docs;
    late _Nube nube;
    late EntradasLocal entradas;
    late DateTime reloj;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('sync_v82');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path,
      );
      nube = _Nube();
      reloj = ahora;
      entradas = EntradasLocal(
        equipo: () async => 'pc-1',
        reloj: () => reloj = reloj.add(const Duration(seconds: 1)),
      );
      await LocalDatabase.instance;
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    SyncEngine elMotor() {
      final cliente = SupabaseClient('https://nube.test', 'anon-de-test',
          httpClient: nube.cliente);
      cliente.auth.stopAutoRefresh();
      addTearDown(cliente.dispose);
      final m = SyncEngine(
        connectivity: RedDePrueba(),
        supabase: cliente,
        conCanalDelPulso: false,
      );
      addTearDown(m.dispose);
      return m;
    }

    test('dar y rendir suben enteros, después de la venta, y VENDER queda en "Todo subido"',
        () async {
      final db = await LocalDatabase.instance;
      final laCaja = await entradas.abrirCaja(
        eventoId: evento,
        operadorId: 'a0000000-0000-4000-8000-000000000001',
        operadorNombre: 'Carla',
      );
      // El bloque se encola **antes** que la venta: solo la prioridad del motor
      // lo deja subir después.
      final bloque = await entradas.darParaRendir(
        eventoId: evento,
        personaNombre: 'Juan Pérez',
        cantidad: 20,
        numeros: const [TramoTalonario(1201, 1220)],
        precio: 8000,
        nombrePrecio: 'Entrada anticipada',
        quien: 'Jefe',
      );
      final r = await entradas.rendir(
        caja: laCaja,
        bloque: bloque,
        vendidas: 15,
        devueltas: 5,
        numerosDevueltos: const [TramoTalonario(1216, 1220)],
        efectivo: 15 * 8000.0,
        quien: 'Carla',
      );
      expect(await entradas.ventasSinSubir(), 1);
      expect(await entradas.cambiosSinSubir(), 4,
          reason: 'la caja, el bloque, lo vendido y lo devuelto');

      final m = elMotor();
      await m.flushPending();

      final subidas = nube.subidas;
      final aRendir = [
        for (final s in subidas)
          if (s.tabla == tabla) s,
      ];
      expect([for (final s in aRendir) s.fila['id']],
          unorderedEquals([bloque.id, r.vendio!.id, r.devolvio!.id]));
      final locales = {
        for (final f in await db.query(tabla)) f['id']: MovimientoParaRendir.fromMap(f).toMap(),
      };
      for (final s in aRendir) {
        expect(s.fila.keys.toSet(), tipos.keys.toSet(), reason: 'sube con todas sus columnas');
        expect(MovimientoParaRendir.fromMap(s.fila).toMap(), locales[s.fila['id']],
            reason: 'sube lo mismo que quedó en la base');
        for (final col in ['contrato_alumno_id', 'venta_id', 'caja_entradas_id', 'anula_id']) {
          expect(s.fila[col], isNot(''), reason: col);
        }
      }
      final orden = [for (final s in subidas) s.tabla];
      final laVenta = orden.indexOf('entradas_ventas');
      expect(laVenta, greaterThanOrEqualTo(0));
      expect(orden.indexOf(tabla), greaterThan(laVenta),
          reason: 'ningún renglón para rendir sube antes que la venta con la plata');

      expect(await SyncQueue.pendingCount, 0);
      expect(m.ultimoPulsoArmado?['tablas'], contains(tabla),
          reason: 'el aviso le dice a la otra PC que la baje');
      final linea = lineaDeSubidaDeEntradas(
        hayInternet: true,
        pendientes: PendientesDeEntradas(
          ventas: await entradas.ventasSinSubir(),
          otros: await entradas.cambiosSinSubir(),
        ),
      );
      expect(linea.texto, 'Todo subido');
    });

    test('baja con "Lista para trabajar sin internet" y queda igual en la base, '
        'aunque la nube traiga una columna de más', () async {
      Map<String, Object?> comoLaNube(MovimientoParaRendir m) => {
            ...m.toMap(),
            'precio': m.precio?.round(),
            'created_at': '2026-11-21T15:00:00+00:00',
            'updated_at': '2026-11-21T15:00:00+00:00',
            'columna_de_una_version_nueva': 'algo',
          };
      nube.filas[tabla] = [comoLaNube(deUnAlumno), comoLaNube(noVolvieron)];

      final m = elMotor();
      expect(await m.bajarParaLaPuerta(), isTrue);
      expect(nube.pedidas, contains('GET $tabla'));

      final db = await LocalDatabase.instance;
      final enLaBase = {
        for (final f in await db.query(tabla)) f['id'] as String: f,
      };
      expect(enLaBase.keys.toSet(), {deUnAlumno.id, noVolvieron.id});
      for (final esperado in [deUnAlumno, noVolvieron]) {
        final fila = enLaBase[esperado.id]!;
        expect(fila.containsKey('columna_de_una_version_nueva'), isFalse);
        final leido = MovimientoParaRendir.fromMap(fila);
        final igual = MovimientoParaRendir.fromMap(comoLaNube(esperado));
        expect(leido.toMap(), igual.toMap());
      }
      final bajado = MovimientoParaRendir.fromMap(enLaBase[deUnAlumno.id]!);
      expect(bajado.precio, 10000.0);
      expect(bajado.tramos, deUnAlumno.tramos);
      expect(bajado.contratoAlumnoId, alumno);
      // Lo que bajó de otro equipo no vuelve a subir.
      expect(await SyncQueue.pendingCount, 0);
    });
  });
}

/// La nube de las pruebas de punta a punta: contesta como PostgREST y anota lo
/// que le suben, con la fila entera, en orden.
class _Nube {
  final filas = <String, List<Map<String, Object?>>>{};
  final pedidas = <String>[];
  final subidas = <({String tabla, Map<String, dynamic> fila})>[];

  http.Client get cliente => MockClient((req) async {
        final tabla = req.url.pathSegments.last;
        pedidas.add('${req.method} $tabla');
        if (req.method == 'POST' || req.method == 'PATCH') {
          final cuerpo = jsonDecode(req.body);
          for (final f in cuerpo is List ? cuerpo : [cuerpo]) {
            subidas.add((tabla: tabla, fila: Map<String, dynamic>.from(f as Map)));
          }
          return http.Response('', req.method == 'POST' ? 201 : 204, request: req);
        }
        final pagina = filas[tabla] ?? const [];
        return http.Response(
          jsonEncode(pagina),
          200,
          headers: {
            'content-type': 'application/json',
            'content-range': pagina.isEmpty ? '*/0' : '0-${pagina.length - 1}/${pagina.length}',
          },
          request: req,
        );
      });
}
