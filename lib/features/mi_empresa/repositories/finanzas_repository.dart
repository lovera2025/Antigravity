import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../main.dart';
import '../../../core/database/local_database.dart';
import '../models/ingreso_detallado.dart';

class FinanzasRepository {
  final SupabaseClient _supabase;

  FinanzasRepository(this._supabase);

  /// Obtiene un historial cronológico de ingresos fusionando datos de SQLite:
  /// - transacciones (Eventos Particulares)
  /// - pagos_contrato_alumno (Eventos Masivos)
  Future<List<IngresoDetallado>> obtenerIngresosDetallados({DateTime? mes, String? eventoId}) async {
    final db = await LocalDatabase.instance;
    
    // 1. Consulta Ingresos Particulares (transacciones + join eventos/clientes)
    String sqlTrans = '''
      SELECT 
        t.id, t.monto, t.concepto, t.fecha_pago, t.evento_id,
        ev.tipo as evento_tipo, ev.cliente_id,
        c.nombre_completo as cliente_nombre
      FROM transacciones t
      JOIN eventos ev ON t.evento_id = ev.id
      JOIN clientes c ON ev.cliente_id = c.id
    ''';
    
    List<dynamic> paramsTrans = [];
    if (eventoId != null) {
      sqlTrans += ' WHERE t.evento_id = ?';
      paramsTrans.add(eventoId);
    }

    // 2. Consulta Ingresos Masivos (pagos_contrato_alumno + join contratos/eventos)
    String sqlMasivos = '''
      SELECT 
        p.id, p.monto, p.concepto, p.fecha_pago as created_at,
        ca.nombre_alumno, ca.evento_id,
        ev.tipo as evento_tipo
      FROM pagos_contrato_alumno p
      JOIN contratos_alumnos ca ON p.contrato_alumno_id = ca.id
      JOIN eventos ev ON ca.evento_id = ev.id
    ''';

    List<dynamic> paramsMasivos = [];
    if (eventoId != null) {
      sqlMasivos += ' WHERE ca.evento_id = ?';
      paramsMasivos.add(eventoId);
    }

    // Ejecutar consultas en paralelo
    final results = await Future.wait([
      db.rawQuery(sqlTrans, paramsTrans),
      db.rawQuery(sqlMasivos, paramsMasivos),
    ]);

    final List<Map<String, dynamic>> transData = results[0].cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> masivoData = results[1].cast<Map<String, dynamic>>();

    List<IngresoDetallado> todos = [];

    // Mapeo Transacciones Particulares
    for (var r in transData) {
      final fechaRaw = r['fecha_pago'];
      DateTime fecha = fechaRaw != null ? DateTime.parse(fechaRaw.toString()) : DateTime.now();

      if (mes != null && (fecha.year != mes.year || fecha.month != mes.month)) continue;

      todos.add(IngresoDetallado(
        id: r['id'].toString(),
        fuente: 'Particular',
        fecha: fecha,
        monto: double.tryParse(r['monto'].toString()) ?? 0,
        concepto: r['concepto']?.toString() ?? 'Pago Registrado',
        alumnoOCliente: r['cliente_nombre'] ?? 'Cliente Particular',
        nombreEvento: r['evento_tipo'] ?? 'Evento Particular',
        eventoId: r['evento_id']?.toString(),
        clienteId: r['cliente_id']?.toString(),
      ));
    }

    // Mapeo Pagos Masivos
    for (var r in masivoData) {
      final fechaRaw = r['created_at'];
      DateTime fecha = fechaRaw != null ? DateTime.parse(fechaRaw.toString()) : DateTime.now();

      if (mes != null && (fecha.year != mes.year || fecha.month != mes.month)) continue;

      todos.add(IngresoDetallado(
        id: r['id'].toString(),
        fuente: 'Masivo',
        fecha: fecha,
        monto: double.tryParse(r['monto'].toString()) ?? 0,
        concepto: r['concepto']?.toString() ?? 'Abono de Cuota / Contrato',
        alumnoOCliente: r['nombre_alumno'] ?? 'Alumno Desconocido',
        nombreEvento: r['evento_tipo'] ?? 'Evento Masivo',
        eventoId: r['evento_id']?.toString(),
      ));
    }

    todos.sort((a, b) => a.compareTo(b));
    return todos;
  }

  Map<String, dynamic>? _cacheProyeccion;
  DateTime? _lastCacheTime;

  /// Obtiene la proyección financiera (Cloud RPC) con optimización de caché instantánea.
  Future<Map<String, dynamic>?> obtenerProyeccionFinanciera() async {
    // Si tenemos caché de menos de 2 minutos, retornamos al instante (Eficiencia Élite)
    if (_cacheProyeccion != null && _lastCacheTime != null) {
      if (DateTime.now().difference(_lastCacheTime!) < const Duration(minutes: 2)) {
        debugPrint('⚡ Finanzas: Retornando proyección desde caché instantánea');
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
      // En caso de error, si hay caché aunque sea vieja, la usamos como fallback
      if (_cacheProyeccion != null) return _cacheProyeccion;
    }
    return null;
  }

  /// Escucha cambios remotos para disparar refrescos locales.
  RealtimeChannel subscribeToChanges(void Function() onUpdate) {
    final channel = _supabase.channel('public:finanzas_dashboard_changes');
    
    channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'transacciones',
        callback: (_) => onUpdate(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'pagos_contrato_alumno',
        callback: (_) => onUpdate(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'egresos',
        callback: (_) => onUpdate(),
      )
      .subscribe();

    return channel;
  }

  /// Busca registros vinculados a un nombre en Clientes y Contratos Alumnos (Purga Inteligente).
  Future<Map<String, List<Map<String, dynamic>>>> buscarVinculadosPorNombre(String nombre) async {
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
    };

    // 1. Buscar Clientes
    final clientes = await db.query('clientes', where: 'nombre_completo LIKE ?', whereArgs: ['%$nombre%']);
    resultados['clientes'] = clientes;

    if (clientes.isNotEmpty) {
      final clienteIds = clientes.map((c) => c['id']).toList();
      final placeholders = clienteIds.map((_) => '?').join(',');
      
      // Eventos de estos clientes
      final eventos = await db.query('eventos', where: "cliente_id IN ($placeholders)", whereArgs: clienteIds);
      resultados['eventos'] = eventos;

      if (eventos.isNotEmpty) {
        final eventoIds = eventos.map((e) => e['id']).toList();
        final evPlaceholders = eventoIds.map((_) => '?').join(',');

        resultados['transacciones'] = await db.query('transacciones', where: "evento_id IN ($evPlaceholders)", whereArgs: eventoIds);
        resultados['egresos'] = await db.query('egresos', where: "evento_id IN ($evPlaceholders)", whereArgs: eventoIds);
        
        final contratos = await db.query('contratos_alumnos', where: "evento_id IN ($evPlaceholders)", whereArgs: eventoIds);
        resultados['contratos']!.addAll(contratos);

        final invitados = await db.query('invitados', where: "evento_id IN ($evPlaceholders)", whereArgs: eventoIds);
        resultados['invitados']!.addAll(invitados);

        if (invitados.isNotEmpty) {
          final invitadoIds = invitados.map((i) => i['id']).toList();
          final invPlaceholders = invitadoIds.map((_) => '?').join(',');
          resultados['accesos'] = await db.query('accesos', where: "invitado_id IN ($invPlaceholders)", whereArgs: invitadoIds);
        }

        if (contratos.isNotEmpty) {
          final contratoIds = contratos.map((c) => c['id']).toList();
          final cPlaceholders = contratoIds.map((_) => '?').join(',');
          resultados['pagos']!.addAll(await db.query('pagos_contrato_alumno', where: "contrato_alumno_id IN ($cPlaceholders)", whereArgs: contratoIds));
        }
      }

      // Presupuestos del cliente
      resultados['presupuestos'] = await db.query('presupuestos', where: "cliente_id IN ($placeholders)", whereArgs: clienteIds);
    }

    // 2. Buscar Solicitudes de Cotización por nombre
    resultados['solicitudes'] = await db.query('solicitudes_cotizacion', where: 'cliente_nombre LIKE ?', whereArgs: ['%$nombre%']);

    // 3. Buscar Alumnos directos (por si no es el cliente)
    final alumnosDirectos = await db.query('contratos_alumnos', where: 'nombre_alumno LIKE ?', whereArgs: ['%$nombre%']);
    for (var a in alumnosDirectos) {
      if (!resultados['contratos']!.any((c) => c['id'] == a['id'])) {
        resultados['contratos']!.add(a);
        final pagos = await db.query('pagos_contrato_alumno', where: 'contrato_alumno_id = ?', whereArgs: [a['id']]);
        resultados['pagos']!.addAll(pagos);
      }
    }

    return resultados;
  }

  /// Elimina registros específicos tanto en Cloud como en Local (SyncQueue).
  Future<void> eliminarRegistrosVinculados(Map<String, List<String>> idsParaBorrar) async {
    final db = await LocalDatabase.instance;

    // Orden de eliminación para respetar FK: accesos -> invitados -> pagos -> contratos -> transacciones -> egresos -> presupuesto_servicios -> presupuestos -> solicitudes -> eventos_servicios -> eventos -> clientes
    final orden = ['accesos', 'invitados', 'pagos', 'contratos', 'transacciones', 'egresos', 'presupuesto_servicios', 'presupuestos', 'solicitudes', 'eventos_servicios', 'eventos', 'clientes'];
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
        // 1. Borrar remoto (si hay red)
        try {
          await _supabase.from(tabla).delete().eq('id', id);
        } catch (e) {
          debugPrint('⚠️ Error eliminando remoto ($tabla:$id): $e');
        }

        // 2. Borrar local
        await db.delete(tabla, where: 'id = ?', whereArgs: [id]);

        // Manejo especial para tablas que requieren borrado por FK antes de borrar al padre en la misma purga
        if (key == 'presupuestos') {
          await db.delete('presupuesto_servicios', where: 'presupuesto_id = ?', whereArgs: [id]);
          try { await _supabase.from('presupuesto_servicios').delete().eq('presupuesto_id', id); } catch (_) {}
        }
        if (key == 'eventos') {
          await db.delete('eventos_servicios', where: 'evento_id = ?', whereArgs: [id]);
          try { await _supabase.from('eventos_servicios').delete().eq('evento_id', id); } catch (_) {}
        }
        
        // 3. Limpiar cola de sync
        await db.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: [tabla, id]);
      }
    }
  }
}

final finanzasRepositoryProvider = Provider<FinanzasRepository>((ref) {
  return FinanzasRepository(ref.watch(supabaseProvider));
});
