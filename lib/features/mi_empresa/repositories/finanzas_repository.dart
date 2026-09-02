import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../main.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import '../../eventos/services/mora_tracked_recovery.dart';
import '../models/ingreso_detallado.dart';

class FinanzasRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;

  FinanzasRepository(this._supabase, this._connectivity, this._syncEngine);

  /// ISO desde SQLite/Supabase → instante UTC canónico (sin conversión AR aquí:
  /// [ArTime.toAr] se aplica en UI y en [ArTime.mismoMes]/[ArTime.mismoDia]).
  static DateTime _parseFechaPagoUtc(dynamic raw) {
    if (raw == null) return ArTime.nowUtc();
    final p = DateTime.tryParse(raw.toString());
    if (p == null) return ArTime.nowUtc();
    return p.isUtc ? p : p.toUtc();
  }

  /// Obtiene un historial cronológico de ingresos fusionando datos de SQLite:
  /// - transacciones (Eventos Particulares)
  /// - pagos_contrato_alumno (Eventos Masivos)
  Future<List<IngresoDetallado>> obtenerIngresosDetallados({
    DateTime? mes,
    String? eventoId,
  }) async {
    final db = await LocalDatabase.instance;

    // 1. Consulta Ingresos Particulares (transacciones + join eventos/clientes)
    String sqlTrans = '''
      SELECT 
        t.id, t.monto, t.concepto, t.fecha_pago, t.evento_id, t.medio_pago,
        ev.tipo as evento_tipo, ev.cliente_id,
        c.nombre_completo as cliente_nombre
      FROM transacciones t
      JOIN eventos ev ON t.evento_id = ev.id
      JOIN clientes c ON ev.cliente_id = c.id
      WHERE COALESCE(t.anulado, 0) = 0
    ''';

    List<dynamic> paramsTrans = [];
    if (eventoId != null) {
      sqlTrans += ' AND t.evento_id = ?';
      paramsTrans.add(eventoId);
    }

    // 2. Consulta Ingresos Masivos (pagos_contrato_alumno + join contratos/eventos)
    String sqlMasivos = '''
      SELECT
        p.id, p.monto, p.concepto, p.fecha_pago as created_at, p.medio_pago,
        p.sesion_caja_id, p.contrato_alumno_id, p.line_kind,
        ca.nombre_alumno, ca.evento_id, ca.institucion,
        ev.tipo as evento_tipo
      FROM pagos_contrato_alumno p
      JOIN contratos_alumnos ca ON p.contrato_alumno_id = ca.id
      JOIN eventos ev ON ca.evento_id = ev.id
      WHERE COALESCE(p.anulado, 0) = 0
    ''';

    List<dynamic> paramsMasivos = [];
    if (eventoId != null) {
      sqlMasivos += ' AND ca.evento_id = ?';
      paramsMasivos.add(eventoId);
    }

    // 3. Pagos por préstamo / alquiler de ítems (sin evento)
    const sqlAlquiler = '''
      SELECT 
        pay.id, pay.monto, pay.concepto, pay.fecha_pago, pay.medio_pago,
        pr.id as prestamo_id, pr.cliente_id,
        c.nombre_completo as cliente_nombre
      FROM pagos_prestamo_alquiler pay
      JOIN prestamos_alquiler pr ON pay.prestamo_id = pr.id
      JOIN clientes c ON pr.cliente_id = c.id
      WHERE COALESCE(pay.anulado, 0) = 0
    ''';

    // Ejecutar consultas en paralelo
    final results = await Future.wait([
      db.rawQuery(sqlTrans, paramsTrans),
      db.rawQuery(sqlMasivos, paramsMasivos),
      db.rawQuery(sqlAlquiler, []),
    ]);

    final List<Map<String, dynamic>> transData = results[0]
        .cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> masivoData = results[1]
        .cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> alquilerData = results[2]
        .cast<Map<String, dynamic>>();

    List<IngresoDetallado> todos = [];

    // Mapeo Transacciones Particulares
    for (var r in transData) {
      final fechaRaw = r['fecha_pago'];
      final DateTime fecha = fechaRaw != null
          ? _parseFechaPagoUtc(fechaRaw)
          : ArTime.nowUtc();

      if (mes != null && !ArTime.mismoMes(fecha, mes)) continue;

      todos.add(
        IngresoDetallado(
          id: r['id'].toString(),
          fuente: 'Particular',
          fecha: fecha,
          monto: double.tryParse(r['monto'].toString()) ?? 0,
          concepto: r['concepto']?.toString() ?? 'Pago Registrado',
          alumnoOCliente: r['cliente_nombre'] ?? 'Cliente Particular',
          nombreEvento: r['evento_tipo'] ?? 'Evento Particular',
          eventoId: r['evento_id']?.toString(),
          clienteId: r['cliente_id']?.toString(),
          medioPago: r['medio_pago']?.toString(),
        ),
      );
    }

    // Mapeo Pagos Masivos
    for (var r in masivoData) {
      final fechaRaw = r['created_at'];
      final DateTime fecha = fechaRaw != null
          ? _parseFechaPagoUtc(fechaRaw)
          : ArTime.nowUtc();

      if (mes != null && !ArTime.mismoMes(fecha, mes)) continue;

      todos.add(
        IngresoDetallado(
          id: r['id'].toString(),
          fuente: 'Masivo',
          fecha: fecha,
          monto: double.tryParse(r['monto'].toString()) ?? 0,
          concepto: r['concepto']?.toString() ?? 'Abono de Cuota / Contrato',
          alumnoOCliente: r['nombre_alumno'] ?? 'Alumno Desconocido',
          nombreEvento: r['evento_tipo'] ?? 'Evento Masivo',
          eventoId: r['evento_id']?.toString(),
          medioPago: r['medio_pago']?.toString(),
          sesionCajaId: r['sesion_caja_id']?.toString(),
          contratoAlumnoId: r['contrato_alumno_id']?.toString(),
          institucion: r['institucion']?.toString(),
          lineKind: r['line_kind']?.toString(),
        ),
      );
    }

    for (var r in alquilerData) {
      final fechaRaw = r['fecha_pago'];
      final DateTime fecha = fechaRaw != null
          ? _parseFechaPagoUtc(fechaRaw)
          : ArTime.nowUtc();

      if (mes != null && !ArTime.mismoMes(fecha, mes)) continue;

      todos.add(
        IngresoDetallado(
          id: r['id'].toString(),
          fuente: 'Alquiler',
          fecha: fecha,
          monto: double.tryParse(r['monto'].toString()) ?? 0,
          concepto: r['concepto']?.toString() ?? 'Pago alquiler ítems',
          alumnoOCliente: r['cliente_nombre'] ?? 'Cliente',
          nombreEvento: 'Alquiler ítems',
          clienteId: r['cliente_id']?.toString(),
          prestamoId: r['prestamo_id']?.toString(),
          medioPago: r['medio_pago']?.toString(),
        ),
      );
    }

    todos.sort((a, b) => a.compareTo(b));
    return todos;
  }

  /// Ingresos de una o varias sesiones de caja, filtrando **en el SQL**.
  ///
  /// [obtenerIngresosDetallados] trae toda la historia de la base y deja que el
  /// consumidor descarte lo que no le sirve. Para el cierre de una sesión eso es
  /// leer decenas de miles de filas para mostrar diez, y el costo crece con los
  /// años del negocio en vez de con el tamaño de la sesión.
  ///
  /// Solo consulta `pagos_contrato_alumno`: `transacciones` y
  /// `pagos_prestamo_alquiler` no tienen columna `sesion_caja_id`, así que no
  /// pueden pertenecer a una sesión de caja.
  Future<List<IngresoDetallado>> obtenerIngresosDeSesiones(
    Set<String> sesionIds,
  ) async {
    if (sesionIds.isEmpty) return [];
    final db = await LocalDatabase.instance;
    final ph = List.filled(sesionIds.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT
        p.id, p.monto, p.concepto, p.fecha_pago as created_at, p.medio_pago,
        p.sesion_caja_id, p.contrato_alumno_id, p.line_kind,
        ca.nombre_alumno, ca.evento_id, ca.institucion,
        ev.tipo as evento_tipo
      FROM pagos_contrato_alumno p
      JOIN contratos_alumnos ca ON p.contrato_alumno_id = ca.id
      JOIN eventos ev ON ca.evento_id = ev.id
      WHERE COALESCE(p.anulado, 0) = 0
        AND p.sesion_caja_id IN ($ph)
    ''', sesionIds.toList());

    final out = rows.map((r) {
      final fechaRaw = r['created_at'];
      return IngresoDetallado(
        id: r['id'].toString(),
        fuente: 'Masivo',
        fecha: fechaRaw != null
            ? _parseFechaPagoUtc(fechaRaw)
            : ArTime.nowUtc(),
        monto: double.tryParse(r['monto'].toString()) ?? 0,
        concepto: r['concepto']?.toString() ?? 'Abono de Cuota / Contrato',
        alumnoOCliente: r['nombre_alumno']?.toString() ?? 'Alumno Desconocido',
        nombreEvento: r['evento_tipo']?.toString() ?? 'Evento Masivo',
        eventoId: r['evento_id']?.toString(),
        medioPago: r['medio_pago']?.toString(),
        sesionCajaId: r['sesion_caja_id']?.toString(),
        contratoAlumnoId: r['contrato_alumno_id']?.toString(),
        institucion: r['institucion']?.toString(),
        lineKind: r['line_kind']?.toString(),
      );
    }).toList();
    out.sort((a, b) => a.compareTo(b));
    return out;
  }

  /// Caché de RPC compartida por todas las instancias (proyección cloud).
  static Map<String, dynamic>? _cacheProyeccion;
  static DateTime? _lastCacheTime;

  /// Invalidar tras sync Pull u otros eventos que cambian datos base de la proyección.
  static void invalidateProyeccionCache() {
    _cacheProyeccion = null;
    _lastCacheTime = null;
  }

  /// Obtiene la proyección financiera (Cloud RPC) con caché corta (2 min).
  Future<Map<String, dynamic>?> obtenerProyeccionFinanciera() async {
    if (_cacheProyeccion != null && _lastCacheTime != null) {
      if (DateTime.now().difference(_lastCacheTime!) <
          const Duration(minutes: 2)) {
        return _cacheProyeccion;
      }
    }

    try {
      final res = await _supabase.rpc('obtener_proyeccion_financiera');
      if (res is List && res.isNotEmpty) {
        _cacheProyeccion = res.first as Map<String, dynamic>;
        _lastCacheTime = DateTime.now();
        return _cacheProyeccion;
      }
    } catch (e) {
      debugPrint('⚠️ RPC Proyección fallido: $e');
      if (_cacheProyeccion != null) return _cacheProyeccion;
    }
    return null;
  }

  // `subscribeToChanges` se retiró el 2026-09-02.
  //
  // Escuchaba siete tablas sin filtro, y la consumían DOS lugares a la vez
  // (finanzas_provider y cierre_caja_provider), o sea que la app se suscribía
  // dos veces a lo mismo. Realtime consulta el slot de replicación cada 100 ms
  // mientras haya un cliente conectado, y el costo de cada consulta escala con
  // la cantidad de suscripciones vivas: entre todos los canales, eso se comía
  // el 89,5% del CPU de la base y el 99,7% de los bloques leídos, agotando el
  // Disk IO Budget del proyecto.
  //
  // Era redundante: OperationalSyncCoordinator ya baja esas mismas tablas cada
  // 10 segundos. El refresco ahora llega por ahí.

  /// Busca registros vinculados a un nombre en Clientes y Contratos Alumnos (Purga Inteligente).
  Future<Map<String, List<Map<String, dynamic>>>> buscarVinculadosPorNombre(
    String nombre,
  ) async {
    final db = await LocalDatabase.instance;
    final Map<String, List<Map<String, dynamic>>> resultados = {
      'clientes': [],
      'eventos': [],
      'transacciones': [],
      'contratos': [],
      'pagos': [],
      'egresos': [],
      'invitados': [],
      'accesos': [],
      'presupuestos': [],
      'solicitudes': [],
      'prestamos_alquiler': [],
      'pagos_alquiler': [],
    };

    // 1. Buscar Clientes
    final clientes = await db.query(
      'clientes',
      where: 'nombre_completo LIKE ?',
      whereArgs: ['%$nombre%'],
    );
    resultados['clientes'] = clientes;

    if (clientes.isNotEmpty) {
      final clienteIds = clientes.map((c) => c['id']).toList();
      final placeholders = clienteIds.map((_) => '?').join(',');

      // Eventos de estos clientes
      final eventos = await db.query(
        'eventos',
        where: "cliente_id IN ($placeholders)",
        whereArgs: clienteIds,
      );
      resultados['eventos'] = eventos;

      if (eventos.isNotEmpty) {
        final eventoIds = eventos.map((e) => e['id']).toList();
        final evPlaceholders = eventoIds.map((_) => '?').join(',');

        resultados['transacciones'] = await db.query(
          'transacciones',
          where: "evento_id IN ($evPlaceholders)",
          whereArgs: eventoIds,
        );
        resultados['egresos'] = await db.query(
          'egresos',
          where: "evento_id IN ($evPlaceholders)",
          whereArgs: eventoIds,
        );

        final contratos = await db.query(
          'contratos_alumnos',
          where: "evento_id IN ($evPlaceholders)",
          whereArgs: eventoIds,
        );
        resultados['contratos']!.addAll(contratos);

        final invitados = await db.query(
          'invitados',
          where: "evento_id IN ($evPlaceholders)",
          whereArgs: eventoIds,
        );
        resultados['invitados']!.addAll(invitados);

        if (invitados.isNotEmpty) {
          final invitadoIds = invitados.map((i) => i['id']).toList();
          final invPlaceholders = invitadoIds.map((_) => '?').join(',');
          resultados['accesos'] = await db.query(
            'accesos',
            where: "invitado_id IN ($invPlaceholders)",
            whereArgs: invitadoIds,
          );
        }

        if (contratos.isNotEmpty) {
          final contratoIds = contratos.map((c) => c['id']).toList();
          final cPlaceholders = contratoIds.map((_) => '?').join(',');
          resultados['pagos']!.addAll(
            await db.query(
              'pagos_contrato_alumno',
              where: "contrato_alumno_id IN ($cPlaceholders)",
              whereArgs: contratoIds,
            ),
          );
        }
      }

      // Presupuestos del cliente
      resultados['presupuestos'] = await db.query(
        'presupuestos',
        where: "cliente_id IN ($placeholders)",
        whereArgs: clienteIds,
      );

      final prestamos = await db.query(
        'prestamos_alquiler',
        where: "cliente_id IN ($placeholders)",
        whereArgs: clienteIds,
      );
      resultados['prestamos_alquiler'] = prestamos;
      if (prestamos.isNotEmpty) {
        final pids = prestamos.map((e) => e['id']).toList();
        final ph = pids.map((_) => '?').join(',');
        resultados['pagos_alquiler'] = await db.query(
          'pagos_prestamo_alquiler',
          where: 'prestamo_id IN ($ph)',
          whereArgs: pids,
        );
      }
    }

    // 2. Buscar Solicitudes de Cotización por nombre
    resultados['solicitudes'] = await db.query(
      'solicitudes_cotizacion',
      where: 'cliente_nombre LIKE ?',
      whereArgs: ['%$nombre%'],
    );

    // 3. Buscar Alumnos directos (por si no es el cliente)
    final alumnosDirectos = await db.query(
      'contratos_alumnos',
      where: 'nombre_alumno LIKE ?',
      whereArgs: ['%$nombre%'],
    );
    for (var a in alumnosDirectos) {
      if (!resultados['contratos']!.any((c) => c['id'] == a['id'])) {
        resultados['contratos']!.add(a);
        final pagos = await db.query(
          'pagos_contrato_alumno',
          where: 'contrato_alumno_id = ?',
          whereArgs: [a['id']],
        );
        resultados['pagos']!.addAll(pagos);
      }
    }

    return resultados;
  }

  /// Elimina registros específicos tanto en Cloud como en Local (SyncQueue).
  /// Devuelve IDs de contratos cuyos pagos se borraron y que siguen existiendo
  /// (para recalcular saldos/mesas tras la purga).
  Future<Set<String>> eliminarRegistrosVinculados(
    Map<String, List<String>> idsParaBorrar,
  ) async {
    final db = await LocalDatabase.instance;

    final pagoAlquilerIds = List<String>.from(
      idsParaBorrar['pagos_alquiler'] ?? [],
    );
    final prestamoAlquilerIds = List<String>.from(
      idsParaBorrar['prestamos_alquiler'] ?? [],
    );

    final pagosIds = List<String>.from(idsParaBorrar['pagos'] ?? []);
    final contratosBorrados = (idsParaBorrar['contratos'] ?? []).toSet();
    final contratosARecalcular = <String>{};

    if (pagosIds.isNotEmpty) {
      final placeholders = List.filled(pagosIds.length, '?').join(',');
      final filasPagos = await db.rawQuery(
        'SELECT contrato_alumno_id FROM pagos_contrato_alumno WHERE id IN ($placeholders)',
        pagosIds,
      );
      for (final row in filasPagos) {
        final cid = row['contrato_alumno_id'] as String?;
        if (cid != null && cid.isNotEmpty && !contratosBorrados.contains(cid)) {
          contratosARecalcular.add(cid);
        }
      }
    }

    for (final id in pagoAlquilerIds) {
      await _eliminarFilaSync('pagos_prestamo_alquiler', id);
    }

    for (final pid in prestamoAlquilerIds) {
      await _eliminarPrestamoAlquilerCascade(pid);
    }

    // Orden de eliminación para respetar FK: accesos -> invitados -> pagos -> contratos -> transacciones -> egresos -> presupuesto_servicios -> presupuestos -> solicitudes -> eventos_servicios -> eventos -> clientes
    final orden = [
      'accesos',
      'invitados',
      'pagos',
      'contratos',
      'transacciones',
      'egresos',
      'presupuesto_servicios',
      'presupuestos',
      'solicitudes',
      'eventos_servicios',
      'eventos',
      'clientes',
    ];
    final mapeoTablas = {
      'accesos': 'accesos',
      'invitados': 'invitados',
      'pagos': 'pagos_contrato_alumno',
      'contratos': 'contratos_alumnos',
      'transacciones': 'transacciones',
      'egresos': 'egresos',
      'presupuesto_servicios': 'presupuesto_servicios',
      'presupuestos': 'presupuestos',
      'solicitudes': 'solicitudes_cotizacion',
      'eventos_servicios': 'eventos_servicios',
      'eventos': 'eventos',
      'clientes': 'clientes',
    };

    for (var key in orden) {
      final ids = idsParaBorrar[key];
      if (ids == null || ids.isEmpty) continue;
      final tabla = mapeoTablas[key]!;

      for (var id in ids) {
        // 1. Borrar local
        await db.delete(tabla, where: 'id = ?', whereArgs: [id]);

        // Manejo especial para tablas que requieren borrado por FK antes de borrar al padre en la misma purga
        if (key == 'presupuestos') {
          await db.delete(
            'presupuesto_servicios',
            where: 'presupuesto_id = ?',
            whereArgs: [id],
          );
        }
        if (key == 'eventos') {
          await db.delete(
            'eventos_servicios',
            where: 'evento_id = ?',
            whereArgs: [id],
          );
        }

        // 2. Encolar eliminación para sincronizar con la nube
        await SyncQueue.enqueue(
          tabla: tabla,
          operacion: SyncOperation.delete,
          registroId: id,
          payload: {},
        );
      }
    }

    return contratosARecalcular;
  }

  Future<void> _eliminarFilaSync(String tabla, String id) async {
    final db = await LocalDatabase.instance;
    await db.delete(tabla, where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(
      tabla: tabla,
      operacion: SyncOperation.delete,
      registroId: id,
      payload: {},
    );
  }

  /// Borra líneas, pagos y cabecera del préstamo (local, remoto y cola).
  Future<void> _eliminarPrestamoAlquilerCascade(String prestamoId) async {
    final db = await LocalDatabase.instance;

    final pagos = await db.query(
      'pagos_prestamo_alquiler',
      where: 'prestamo_id = ?',
      whereArgs: [prestamoId],
    );
    for (final row in pagos) {
      final pid = row['id'].toString();
      await _eliminarFilaSync('pagos_prestamo_alquiler', pid);
    }

    final lineas = await db.query(
      'prestamo_alquiler_lineas',
      where: 'prestamo_id = ?',
      whereArgs: [prestamoId],
    );
    for (final row in lineas) {
      final lid = row['id'].toString();
      await _eliminarFilaSync('prestamo_alquiler_lineas', lid);
    }

    await _eliminarFilaSync('prestamos_alquiler', prestamoId);
  }

  static const Set<String> _tablasMedioPagoCorregible = {
    'pagos_contrato_alumno',
    'transacciones',
    'pagos_prestamo_alquiler',
  };

  /// Búsqueda local de cobros por nombre de alumno/cliente o concepto (mínimo 2 caracteres).
  /// Cada mapa incluye: `tabla`, `id`, `monto`, `medio_pago`, `fecha_pago`, `concepto`, `titulo`, `subtitulo`.
  Future<List<Map<String, dynamic>>> buscarPagosParaCorregirMedio(
    String consulta,
  ) async {
    final q = consulta.trim();
    if (q.length < 2) return [];
    final like = '%$q%';
    final db = await LocalDatabase.instance;

    final masivo = await db.rawQuery(
      '''
SELECT 'pagos_contrato_alumno' AS tabla, p.id AS id,
  p.monto AS monto, p.medio_pago AS medio_pago, p.fecha_pago AS fecha_pago, p.concepto AS concepto,
  ca.nombre_alumno AS titulo, ev.tipo AS subtitulo
FROM pagos_contrato_alumno p
INNER JOIN contratos_alumnos ca ON ca.id = p.contrato_alumno_id
INNER JOIN eventos ev ON ev.id = ca.evento_id
WHERE (ca.nombre_alumno LIKE ? OR IFNULL(p.concepto,'') LIKE ?)
AND COALESCE(p.anulado, 0) = 0
ORDER BY p.fecha_pago DESC LIMIT 80
''',
      [like, like],
    );

    final particular = await db.rawQuery(
      '''
SELECT 'transacciones' AS tabla, t.id AS id,
  t.monto AS monto, t.medio_pago AS medio_pago, t.fecha_pago AS fecha_pago, t.concepto AS concepto,
  c.nombre_completo AS titulo, ev.tipo AS subtitulo
FROM transacciones t
INNER JOIN eventos ev ON ev.id = t.evento_id
INNER JOIN clientes c ON c.id = ev.cliente_id
WHERE (c.nombre_completo LIKE ? OR IFNULL(t.concepto,'') LIKE ?)
AND COALESCE(t.anulado, 0) = 0
ORDER BY t.fecha_pago DESC LIMIT 80
''',
      [like, like],
    );

    final alquiler = await db.rawQuery(
      '''
SELECT 'pagos_prestamo_alquiler' AS tabla, pay.id AS id,
  pay.monto AS monto, pay.medio_pago AS medio_pago, pay.fecha_pago AS fecha_pago, pay.concepto AS concepto,
  c.nombre_completo AS titulo, 'Alquiler ítems' AS subtitulo
FROM pagos_prestamo_alquiler pay
INNER JOIN prestamos_alquiler pr ON pr.id = pay.prestamo_id
INNER JOIN clientes c ON c.id = pr.cliente_id
WHERE (c.nombre_completo LIKE ? OR IFNULL(pay.concepto,'') LIKE ?)
AND COALESCE(pay.anulado, 0) = 0
ORDER BY pay.fecha_pago DESC LIMIT 80
''',
      [like, like],
    );

    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final row in [...masivo, ...particular, ...alquiler]) {
      final tabla = row['tabla']?.toString() ?? '';
      final id = row['id']?.toString() ?? '';
      final key = '$tabla|$id';
      if (id.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      merged.add(Map<String, dynamic>.from(row));
    }
    merged.sort((a, b) {
      final fa =
          DateTime.tryParse(a['fecha_pago']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final fb =
          DateTime.tryParse(b['fecha_pago']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return fb.compareTo(fa);
    });
    return merged;
  }

  /// Actualiza solo [medio_pago] en SQLite y encola sync (sin tocar montos ni fechas).
  Future<void> actualizarMedioPagoRegistro({
    required String tabla,
    required String id,
    required String medioPago,
  }) async {
    if (!_tablasMedioPagoCorregible.contains(tabla)) {
      throw ArgumentError('Tabla no permitida: $tabla');
    }
    final medio = medioPago.toLowerCase().trim();
    if (medio != 'efectivo' && medio != 'transferencia') {
      throw ArgumentError('medio_pago debe ser efectivo o transferencia');
    }
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      tabla,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No existe el registro en la base local');
    }
    if (((rows.first['anulado'] as num?)?.toInt() ?? 0) != 0) {
      throw StateError(
        'El cobro está anulado; no se puede cambiar el medio de pago.',
      );
    }
    await db.update(
      tabla,
      {'medio_pago': medio},
      where: 'id = ?',
      whereArgs: [id],
    );
    await SyncQueue.enqueue(
      tabla: tabla,
      operacion: SyncOperation.update,
      registroId: id,
      payload: {'id': id, 'medio_pago': medio},
    );
  }

  /// Actualiza solo [fecha_pago] en SQLite y encola sync.
  Future<void> actualizarFechaPagoRegistro({
    required String tabla,
    required String id,
    required DateTime nuevaFecha,
  }) async {
    if (!_tablasMedioPagoCorregible.contains(tabla)) {
      throw ArgumentError('Tabla no permitida: $tabla');
    }
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      tabla,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No existe el registro en la base local');
    }
    if (((rows.first['anulado'] as num?)?.toInt() ?? 0) != 0) {
      throw StateError('El cobro está anulado; no se puede cambiar la fecha.');
    }

    final isoDate = nuevaFecha.toUtc().toIso8601String();

    await db.update(
      tabla,
      {'fecha_pago': isoDate},
      where: 'id = ?',
      whereArgs: [id],
    );
    await SyncQueue.enqueue(
      tabla: tabla,
      operacion: SyncOperation.update,
      registroId: id,
      payload: {'id': id, 'fecha_pago': isoDate},
    );
  }

  /// Marca el cobro como anulado (no borra la fila). Excluye el monto de saldos y reportes.
  /// Devuelve el `contrato_alumno_id` si [tabla] es masivos, para llamar a [ContratosRepository.recalcularProgresoContrato].
  Future<String?> anularPagoConMotivo({
    required String tabla,
    required String id,
    required String motivo,
  }) async {
    if (!_tablasMedioPagoCorregible.contains(tabla)) {
      throw ArgumentError('Tabla no permitida: $tabla');
    }
    final m = motivo.trim();
    if (m.length < 8) {
      throw ArgumentError('Describí el motivo con al menos 8 caracteres.');
    }
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      tabla,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No existe el registro en la base local');
    }
    final row = rows.first;
    if (((row['anulado'] as num?)?.toInt() ?? 0) != 0) {
      throw StateError('Este cobro ya fue anulado.');
    }
    final now = ArTime.nowUtcIso();
    final updates = <String, dynamic>{
      'anulado': 1,
      'motivo_anulacion': m,
      'fecha_anulacion': now,
    };
    await db.update(tabla, updates, where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(
      tabla: tabla,
      operacion: SyncOperation.update,
      registroId: id,
      payload: {'id': id, ...updates},
    );
    if (tabla == 'pagos_contrato_alumno') {
      final lk = (row['line_kind'] as String?)?.trim();
      final concepto = row['concepto'] as String? ?? '';
      final esInteres =
          lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(concepto);
      if (esInteres) {
        final cid = row['contrato_alumno_id']?.toString();
        if (cid != null && cid.isNotEmpty) {
          final cRows = await db.query(
            'contratos_alumnos',
            where: 'id = ?',
            whereArgs: [cid],
            limit: 1,
          );
          if (cRows.isNotEmpty) {
            final contrato = ContratoAlumno.fromJson(cRows.first);
            final pagos = await db.query(
              'pagos_contrato_alumno',
              where: 'contrato_alumno_id = ?',
              whereArgs: [cid],
            );
            final objetivo = MoraTrackedRecovery.objetivoDesdeHistorial(
              contrato: contrato,
              pagos: pagos,
            );
            final nowUtc = ArTime.nowUtcIso();
            await db.update(
              'contratos_alumnos',
              {
                'mora_pendiente_tracked': objetivo.tracked,
                'mora_cobrada_offset': objetivo.offset,
                'updated_at': nowUtc,
              },
              where: 'id = ?',
              whereArgs: [cid],
            );
            await SyncQueue.enqueue(
              tabla: 'contratos_alumnos',
              operacion: SyncOperation.update,
              registroId: cid,
              payload: {
                'id': cid,
                'mora_pendiente_tracked': objetivo.tracked,
                'mora_cobrada_offset': objetivo.offset,
              },
            );
          }
        }
      }
      return row['contrato_alumno_id']?.toString();
    }
    return null;
  }
}

final finanzasRepositoryProvider = Provider<FinanzasRepository>((ref) {
  return FinanzasRepository(
    ref.watch(supabaseProvider),
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
