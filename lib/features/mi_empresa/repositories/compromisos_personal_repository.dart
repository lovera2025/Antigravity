import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../main.dart';
import '../../../models/egreso.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../egresos/services/egreso_concepto_sugerencias.dart';
import '../models/compromiso_personal.dart';

/// Se quiso borrar una cuenta que ya tiene pagos aplicados.
///
/// Borrarla dejaría esos egresos apuntando a la nada, y la plata salió igual:
/// no hay forma de deshacerlo. Para esos casos existe cancelar.
class CompromisoConPagosException implements Exception {
  const CompromisoConPagosException();

  static const String mensaje =
      'Esta cuenta ya tiene pagos registrados, así que no se puede borrar. '
      'Si querés darla por terminada sin pagarla, cancelala.';

  @override
  String toString() => mensaje;
}

/// Cuentas pendientes con una persona: lo que el negocio le debe por un trabajo
/// o un producto, y lo que se le fue pagando.
///
/// Offline-first como el resto: se lee de SQLite y se escribe local + cola.
class CompromisosPersonalRepository {
  // ignore: unused_field
  final SupabaseClient _supabase;
  // ignore: unused_field
  final ConnectivityService _connectivity;
  final Ref _ref;

  CompromisosPersonalRepository(this._supabase, this._connectivity, this._ref);

  // ── LECTURA ────────────────────────────────────────────────────────────────

  /// Todas las cuentas con su saldo ya resuelto.
  ///
  /// El saldo sale de sumar los egresos que apuntan a cada cuenta — no hay
  /// columna de saldo que pueda quedar vieja. Se traen las dos tablas enteras y
  /// se agrupan en memoria: son chicas y así cada pago llega como [Egreso]
  /// completo, con su medio de pago y su origen, listo para mostrar.
  Future<List<CompromisoConSaldo>> listarConSaldo() async {
    final db = await LocalDatabase.instance;

    final filas = await db.query(
      'compromisos_personal',
      orderBy: 'fecha_inicio DESC',
    );
    if (filas.isEmpty) return const [];

    final pagosFilas = await db.query(
      'egresos',
      where: "compromiso_id IS NOT NULL AND TRIM(compromiso_id) != ''",
    );

    final pagosPorCuenta = <String, List<Egreso>>{};
    for (final f in pagosFilas) {
      final e = Egreso.fromJson(Map<String, dynamic>.from(f));
      final cid = (e.compromisoId ?? '').trim();
      if (cid.isEmpty) continue;
      pagosPorCuenta.putIfAbsent(cid, () => []).add(e);
    }

    final out = <CompromisoConSaldo>[];
    for (final f in filas) {
      final compromiso = CompromisoPersonal.fromMap(Map<String, dynamic>.from(f));
      final pagos = pagosPorCuenta[compromiso.id] ?? const <Egreso>[];
      final ordenados = List<Egreso>.from(pagos)
        ..sort((a, b) {
          final fa = a.fecha;
          final fb = b.fecha;
          if (fa == null && fb == null) return 0;
          if (fa == null) return 1;
          if (fb == null) return -1;
          return fb.compareTo(fa);
        });
      out.add(
        CompromisoConSaldo(
          compromiso: compromiso,
          pagado: pagos.fold<double>(0, (s, e) => s + e.monto),
          pagos: ordenados,
        ),
      );
    }

    // Las que siguen debiendo arriba, de mayor deuda a menor; las saldadas y
    // canceladas al final, que es donde el jefe las va a buscar solo si quiere.
    out.sort((a, b) {
      if (a.sigueAbierto != b.sigueAbierto) return a.sigueAbierto ? -1 : 1;
      return b.saldo.compareTo(a.saldo);
    });
    return out;
  }

  /// Deuda total abierta, para el subtítulo de la sección.
  Future<double> totalPendiente() async {
    final cuentas = await listarConSaldo();
    return cuentas
        .where((c) => c.sigueAbierto)
        .fold<double>(0, (s, c) => s + c.saldo);
  }

  // ── ESCRITURA ──────────────────────────────────────────────────────────────

  Future<String> crear({
    required String persona,
    required String tipo,
    required double montoTotal,
    String? concepto,
    DateTime? fechaInicio,
    String? nota,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    final ahora = ArTime.nowUtc();

    final compromiso = CompromisoPersonal(
      id: id,
      // El mismo canonizador que usa el formulario de pagos, para que "Juan" y
      // "juan" no abran dos cuentas distintas de la misma persona.
      persona: persona.trim(),
      tipo: tipo,
      concepto: concepto?.trim(),
      montoTotal: montoTotal,
      fechaInicio: fechaInicio?.toUtc() ?? ahora,
      nota: nota?.trim(),
      createdAt: ahora,
      updatedAt: ahora,
    );
    final data = compromiso.toMap();

    // 1. Guardar localmente
    await db.insert('compromisos_personal', data);

    // 2. Encolar para sincronización
    await SyncQueue.enqueue(
      tabla: 'compromisos_personal',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: data,
    );

    debugPrint('✅ Cuenta pendiente creada: $id (${compromiso.persona})');
    return id;
  }

  /// Registra un pago contra una cuenta.
  ///
  /// El pago **es un egreso**, no una fila aparte: así el flujo de caja, la
  /// salud financiera, el cierre de sesión y la liquidación por operador lo ven
  /// sin trabajo extra, y no hay dos fuentes de verdad para la misma plata.
  /// La categoría queda en `Personal` salga del negocio o del bolsillo — de eso
  /// se ocupa `origen_fondos`— para que la liquidación lo cuente en los dos casos.
  Future<String> registrarPago({
    required String compromisoId,
    required String persona,
    required double monto,
    required String origenFondos,
    String? medioPago,
    DateTime? fecha,
    String? sesionCajaId,
  }) async {
    if (compromisoId.length != 36) {
      throw ArgumentError('compromisoId inválido: $compromisoId');
    }
    final egresos = _ref.read(egresosRepositoryProvider);
    final egresoId = await egresos.registrarEgresoSinEvento(
      monto: monto,
      proveedor: persona.trim(),
      categoria: kCategoriaPersonal,
      fecha: fecha,
      medioPago: medioPago,
      sesionCajaId: sesionCajaId,
      compromisoId: compromisoId,
      origenFondos: origenFondos,
    );
    debugPrint(
      '✅ Pago $egresoId aplicado a la cuenta $compromisoId (desde $origenFondos)',
    );
    return egresoId;
  }

  Future<void> cambiarEstado(String id, String estado) async {
    if (id.length != 36) return;
    final db = await LocalDatabase.instance;
    final ahora = ArTime.nowUtcIso();

    await db.update(
      'compromisos_personal',
      {'estado': estado, 'updated_at': ahora},
      where: 'id = ?',
      whereArgs: [id],
    );

    // Se re-lee la fila entera para encolar el registro completo, no el parcial.
    final filas = await db.query(
      'compromisos_personal',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (filas.isEmpty) return;

    await SyncQueue.enqueue(
      tabla: 'compromisos_personal',
      operacion: SyncOperation.update,
      registroId: id,
      payload: Map<String, dynamic>.from(filas.first),
    );
  }

  Future<void> cancelar(String id) =>
      cambiarEstado(id, kEstadoCompromisoCancelado);

  Future<void> reabrir(String id) => cambiarEstado(id, kEstadoCompromisoActivo);

  /// Borra una cuenta que nunca recibió un pago.
  ///
  /// Con pagos aplicados lanza [CompromisoConPagosException]: esos egresos
  /// quedarían apuntando a la nada y la plata salió igual. Para eso está
  /// cancelar.
  Future<void> eliminar(String id) async {
    if (id.length != 36) return;
    final db = await LocalDatabase.instance;

    final pagos = await db.query(
      'egresos',
      columns: ['id'],
      where: 'compromiso_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (pagos.isNotEmpty) {
      throw const CompromisoConPagosException();
    }

    await db.delete('compromisos_personal', where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(
      tabla: 'compromisos_personal',
      operacion: SyncOperation.delete,
      registroId: id,
      payload: {'id': id},
    );
  }
}

final compromisosPersonalRepositoryProvider =
    Provider<CompromisosPersonalRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return CompromisosPersonalRepository(supabase, connectivity, ref);
});
