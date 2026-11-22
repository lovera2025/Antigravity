import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/entradas/datos/entradas_local.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';

/// Las cinco tablas de la v80 (la venta de entradas) en el motor de
/// sincronización, en el SQL de la nube y en la base: **la nube y la PC dicen lo
/// mismo**. Mismo modelo que `sync_tablas_v79_test.dart`: las listas del motor
/// son privadas y se leen del texto del archivo.
void main() {
  sqfliteFfiInit();

  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  final motor = leer('lib/core/services/sync_engine.dart');
  final cola = leer('lib/core/database/sync_queue.dart');
  final sql = leer('supabase/migrations/20261113200000_venta_de_entradas.sql');

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

  Set<String> columnasDelSql(String tabla) {
    final crear = RegExp(
      'create table if not exists public\\.$tabla \\(([\\s\\S]*?)\\n\\);',
    ).firstMatch(sql);
    expect(crear, isNotNull, reason: '$tabla no está en el SQL');
    return {
      for (final l in crear!.group(1)!.split('\n'))
        if (l.trim().isNotEmpty) l.trim().split(' ').first,
    };
  }

  final ahora = DateTime.utc(2026, 11, 20, 15);
  const evento = 'e0000000-0000-4000-8000-000000000001';

  final config = ConfigEntradas.vacia(evento, ahora: ahora).conPrecios(
    valorEntrada: 10000,
    precioAnticipada: 8000,
    anticipadaHasta: '2026-11-28',
    descuentoLugaresPct: 50,
    recargoPct: 0,
    descuentoAMano: true,
  );
  final caja = CajaEntradas.abrir(
    eventoId: evento,
    operadorId: 'a0000000-0000-4000-8000-000000000001',
    operadorNombre: 'F1',
    cambioInicial: 5000,
    ahora: ahora,
  ).sellada(hechoPor: 'F1', deviceId: 'pc-1', ahora: ahora);
  final venta = VentaEntradas.nueva(
    cajaEntradasId: caja.id,
    eventoId: evento,
    numero: 1,
    contratoAlumnoId: 'c0000000-0000-4000-8000-000000000001',
    compradorNombre: 'F2, COMPRADORA',
    compradorDni: '30111222',
    renglones: [
      RenglonEntradas.lugar(
        nombre: 'Entrada de lugar adicional (50 %)',
        precioLista: 10000,
        descuentoPct: 50,
        cantidad: 8,
      ),
      RenglonEntradas.suelta(nombre: 'Entrada general', precioLista: 10000, cantidad: 2),
    ],
    medio: MedioBarra.efectivo,
    efectivo: 60000,
    recibe: 60000,
    numeros: '1043-1052',
    hechoPor: 'F1',
    deviceId: 'pc-1',
    ahora: ahora,
  );
  final anulacion = AnulacionEntradas.de(
    venta,
    motivo: 'se cargó dos veces',
    devueltas: true,
    hechoPor: 'Jefe',
    deviceId: 'pc-1',
    ahora: ahora,
  );
  final verificacion = VerificacionEntradas.de(
    venta,
    verificado: true,
    hechoPor: 'Jefe',
    deviceId: 'pc-1',
    ahora: ahora,
  );

  final modelos = <String, Map<String, dynamic>>{
    'entradas_config': config.toMap(),
    'entradas_cajas': caja.toMap(),
    'entradas_ventas': venta.toMap(),
    'entradas_anulaciones': anulacion.toMap(),
    'entradas_verificaciones': verificacion.toMap(),
  };

  test('son las cinco, y el repositorio las nombra igual', () {
    expect(EntradasLocal.tablas.toSet(), modelos.keys.toSet());
  });

  group('la nube y la PC dicen lo mismo', () {
    for (final tabla in modelos.keys) {
      test('$tabla: el modelo, la base, el motor y el SQL tienen las mismas columnas',
          () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        await LocalDatabase.crearTablasV80(db);
        final enLaBase = {
          for (final c in await db.rawQuery('PRAGMA table_info($tabla)'))
            c['name'] as String,
        };
        await db.close();
        final delModelo = modelos[tabla]!.keys.toSet();
        expect(enLaBase, delModelo, reason: 'base y modelo');
        expect(columnasDelMotor(tabla), delModelo, reason: 'motor y modelo');
        expect(columnasDelSql(tabla), delModelo, reason: 'SQL y modelo');
      });
    }

    test('cada modelo va y vuelve de la base igual', () {
      expect(ConfigEntradas.fromMap(config.toMap()).toMap(), config.toMap());
      expect(CajaEntradas.fromMap(caja.toMap()).toMap(), caja.toMap());
      expect(VentaEntradas.fromMap(venta.toMap()).toMap(), venta.toMap());
      expect(AnulacionEntradas.fromMap(anulacion.toMap()).toMap(), anulacion.toMap());
      expect(VerificacionEntradas.fromMap(verificacion.toMap()).toMap(),
          verificacion.toMap());
    });

    test('y de la nube también: la plata como número y las casillas como 0 y 1', () {
      // La nube devuelve `numeric` como número (a veces entero) y las fechas con zona.
      final deLaNube = Map<String, dynamic>.from(venta.toMap())
        ..['total'] = 60000
        ..['efectivo'] = 60000
        ..['created_at'] = '2026-11-20T15:00:00+00:00';
      final v = VentaEntradas.fromMap(deLaNube);
      expect(v.total, 60000.0);
      expect(v.renglones, hasLength(2));
      expect(v.cuantas(TipoRenglonEntradas.lugar), 8);
      expect(ConfigEntradas.fromMap({...config.toMap(), 'descuento_a_mano': 1}).descuentoAMano,
          isTrue);
      expect(AnulacionEntradas.fromMap({...anulacion.toMap(), 'devueltas': 0}).devueltas,
          isFalse);
    });
  });

  group('en las listas del motor', () {
    test('todas bajan, en la bajada general y por su marca de tiempo', () {
      final incrementales = declaracion('_incrementalColumns', '}');
      for (final t in modelos.keys) {
        expect(incrementales, contains("'$t': 'updated_at'"), reason: t);
        expect(motor, contains("_pullTable(db, '$t', 'updated_at')"), reason: t);
        expect(SyncEngine.tablasQueSeBajan, contains(t));
      }
    });

    // Desde el 22-nov-2026 el precio también baja con lo del cobro: un precio
    // puesto en la oficina tiene que llegar enseguida a la tablet que vende.
    test('la plata y el precio bajan con lo del cobro; "Pago verificado", con lo de carga',
        () {
      const delCobro = [
        'entradas_cajas',
        'entradas_ventas',
        'entradas_anulaciones',
        'entradas_config',
        'sorteos_mesas',
      ];
      const deCarga = ['entradas_verificaciones'];
      for (final t in delCobro) {
        expect(SyncEngine.tablasDelCobro, contains(t), reason: t);
        expect(SyncEngine.tablasDeCarga, isNot(contains(t)), reason: t);
      }
      for (final t in deCarga) {
        expect(SyncEngine.tablasDeCarga, contains(t), reason: t);
        expect(SyncEngine.tablasDelCobro, isNot(contains(t)), reason: t);
      }
    });

    // Spec 7.3: la tablet que se prepara en la oficina vende sin internet. Con lo
    // entregado sin cargo, para no vender un número que ya tiene dueño.
    test('bajan con "Lista para trabajar sin internet", con lo entregado sin cargo', () {
      for (final t in modelos.keys) {
        expect(SyncEngine.tablasDeLaPuerta, contains(t), reason: t);
      }
      expect(SyncEngine.tablasDeLaPuerta, contains('entradas_retiro'));
    });

    test('suben de padres a hijas', () {
      expect(motor,
          contains("if (table == 'entradas_config' || table == 'entradas_cajas') return 2;"));
      expect(motor, contains("if (table == 'entradas_ventas') return 4;"));
      expect(motor, contains("if (table == 'entradas_anulaciones') return 5;"));
      expect(motor, contains("if (table == 'entradas_verificaciones') return 5;"));
    });

    test('una venta encolada no se descarta nunca: no son hijas en la limpieza de la cola',
        () {
      for (final t in modelos.keys) {
        expect(cola, isNot(contains("'$t'")), reason: t);
      }
    });

    test('no están en ninguna lista que borre filas locales, y dicen por qué', () {
      final reconciliar = declaracion('_tablasAReconciliar', ']');
      final cascada = declaracion('_hijasEnCascada', '}');
      for (final t in modelos.keys) {
        expect(reconciliar, isNot(contains("'$t'")), reason: t);
        expect(cascada, isNot(contains("'$t'")), reason: t);
        expect(SyncEngine.tablasSinRevisarBorrados[t], isNotNull, reason: t);
        expect(SyncEngine.tablasSinRevisarBorrados[t]!.trim(), isNotEmpty);
      }
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
        isNot(matches(RegExp(r'\b(drop table|delete from|update public\.|insert into)\b'))),
      );
      expect(RegExp(r'create table (?!if not exists)').hasMatch(codigo), isFalse);
      expect(RegExp(r'create index (?!if not exists)').hasMatch(codigo), isFalse);
      // Las únicas tablas que nombra el código son las cinco nuevas.
      final nombradas = {
        for (final m in RegExp(r'public\.([a-z_]+)').allMatches(codigo)) m.group(1)!,
      }..remove('update_updated_at_column');
      expect(nombradas, modelos.keys.toSet());
      for (final ajena in [
        'contratos_alumnos',
        'pagos_contrato_alumno',
        'sesiones_caja',
        'entradas_retiro',
      ]) {
        expect(codigo, isNot(contains(ajena)), reason: ajena);
      }
    });

    test('las cinco con la policy de los usuarios logueados y los dos disparadores', () {
      final lista = RegExp(r'array\[([\s\S]*?)\]').firstMatch(sql)!.group(1)!;
      final conRls = {
        for (final m in RegExp(r"'([a-z_]+)'").allMatches(lista)) m.group(1)!,
      };
      expect(conRls, modelos.keys.toSet());
      expect(sql, contains("t || '_all_authenticated'"));
      expect(sql, contains('set_updated_at_ins_'));
      expect(sql, contains('set_updated_at_upd_'));
      expect(sql, contains('update_updated_at_column()'));
    });

    test('ninguna entra a Realtime', () {
      expect(codigo, isNot(contains('supabase_realtime')));
    });

    test('cada tabla trae su ROLLBACK, y al final las consultas de antes y después', () {
      for (final t in modelos.keys) {
        expect(sql, contains('-- ROLLBACK: drop table if exists public.$t;'), reason: t);
      }
      expect(sql, contains('(select count(*) from public.contratos_alumnos)'));
      expect(sql, contains('(select count(*) from public.pagos_contrato_alumno)'));
    });
  });
}
