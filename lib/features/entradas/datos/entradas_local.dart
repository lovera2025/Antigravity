import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/instalacion_id.dart';
import 'entradas_repositorio.dart';

/// La venta de entradas en este equipo — la base de la PC o de la tablet, y la
/// cola de subida (v80).
///
/// Todo lo que escribe va con su entrada en la cola, **en la misma
/// transacción**: sube solo cuando hay internet. **Nada se borra:** una caja se
/// cierra, y una venta se anula con otra fila.
///
/// **No toca ninguna tabla que no sea de las cinco de entradas.** Una venta de
/// entradas no es un pago de cuota: ni `pagos_contrato_alumno`, ni
/// `sesiones_caja`, ni `contratos_alumnos`
/// (`test/venta_entradas_no_toca_test.dart` lee este archivo).
///
/// Leer sin las tablas (una base que todavía no migró) no tira: da la lista
/// vacía.
class EntradasLocal implements EntradasDeLaCaja, EntradasDelJefe {
  EntradasLocal({
    Future<Database> Function()? abrir,
    Future<String?> Function()? equipo,
    DateTime Function()? reloj,
  })  : _abrir = abrir ?? (() => LocalDatabase.instance),
        _equipo = equipo ?? InstalacionId.inicializar,
        _reloj = reloj ?? DateTime.now;

  final Future<Database> Function() _abrir;
  final Future<String?> Function() _equipo;
  final DateTime Function() _reloj;

  static const tablaConfig = 'entradas_config';
  static const tablaCajas = 'entradas_cajas';
  static const tablaVentas = 'entradas_ventas';
  static const tablaAnulaciones = 'entradas_anulaciones';
  static const tablaVerificaciones = 'entradas_verificaciones';

  /// Las cinco, en el orden en que conviene crearlas y subirlas.
  static const tablas = [
    tablaConfig,
    tablaCajas,
    tablaVentas,
    tablaAnulaciones,
    tablaVerificaciones,
  ];

  Future<List<Map<String, Object?>>> _leer(
    String tabla, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    try {
      final db = await _abrir();
      return await db.query(
        tabla,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
      );
    } catch (e) {
      debugPrint('⚠️ Entradas: $tabla sin leer: $e');
      return const [];
    }
  }

  Future<void> _guardar(
    DatabaseExecutor db,
    String tabla,
    String id,
    Map<String, dynamic> fila,
  ) async {
    await db.insert(tabla, fila, conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueue.enqueue(
      executor: db,
      tabla: tabla,
      operacion: SyncOperation.insert,
      registroId: id,
      payload: fila,
    );
  }

  /// Cuándo nació la fila que ya había: guardar de nuevo no le cambia la fecha.
  Future<String?> _nacio(DatabaseExecutor db, String tabla, String id) async {
    final filas = await db.query(
      tabla,
      columns: ['created_at'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first['created_at'] as String?;
  }

  // ── El precio de la fiesta ─────────────────────────────────────────────────

  @override
  Future<ConfigEntradas?> config(String eventoId) async {
    final filas = await _leer(
      tablaConfig,
      where: 'evento_id = ?',
      whereArgs: [eventoId],
      orderBy: 'updated_at DESC',
    );
    return filas.isEmpty ? null : ConfigEntradas.fromMap(filas.first);
  }

  @override
  Future<ConfigEntradas> guardarConfig(
    ConfigEntradas config, {
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final ya = await txn.query(
        tablaConfig,
        where: 'id = ?',
        whereArgs: [config.id],
        limit: 1,
      );
      if (ya.isNotEmpty) {
        final guardada = ConfigEntradas.fromMap(ya.first);
        // Guardar sin cambiar nada no escribe.
        if (guardada.mismosPreciosQue(config)) return guardada;
      }
      final sellada = config.sellada(
        hechoPor: quien,
        deviceId: equipo,
        createdAt: await _nacio(txn, tablaConfig, config.id),
        ahora: _reloj(),
      );
      await _guardar(txn, tablaConfig, sellada.id, sellada.toMap());
      return sellada;
    });
  }

  // ── Las cajas ──────────────────────────────────────────────────────────────

  @override
  Future<List<CajaEntradas>> cajas(String eventoId) async => [
        for (final f in await _leer(
          tablaCajas,
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'abierta_at, id',
        ))
          CajaEntradas.fromMap(f),
      ];

  @override
  Future<CajaEntradas?> cajaAbierta({
    required String eventoId,
    String? operadorId,
  }) async {
    final equipo = await _equipo();
    final filas = await _leer(
      tablaCajas,
      where: operadorId == null
          ? 'evento_id = ? AND cerrada_at IS NULL AND operador_id IS NULL'
          : 'evento_id = ? AND cerrada_at IS NULL AND operador_id = ?',
      whereArgs: [eventoId, ?operadorId],
      orderBy: 'abierta_at DESC',
    );
    for (final f in filas) {
      final caja = CajaEntradas.fromMap(f);
      // Solo la de este equipo: una caja vive donde se abrió.
      if (caja.deviceId == equipo) return caja;
    }
    return null;
  }

  @override
  Future<CajaEntradas> abrirCaja({
    required String eventoId,
    String? operadorId,
    String? operadorNombre,
    double cambioInicial = 0,
  }) async {
    final ya = await cajaAbierta(eventoId: eventoId, operadorId: operadorId);
    if (ya != null) return ya;
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final ahora = _reloj();
      final caja = CajaEntradas.abrir(
        eventoId: eventoId,
        operadorId: operadorId,
        operadorNombre: operadorNombre,
        cambioInicial: cambioInicial,
        ahora: ahora,
      ).sellada(hechoPor: operadorNombre, deviceId: equipo, ahora: ahora);
      await _guardar(txn, tablaCajas, caja.id, caja.toMap());
      return caja;
    });
  }

  Future<CajaEntradas> _laDeEsteEquipo(DatabaseExecutor txn, CajaEntradas caja) async {
    final filas = await txn.query(
      tablaCajas,
      where: 'id = ?',
      whereArgs: [caja.id],
      limit: 1,
    );
    if (filas.isEmpty) {
      throw StateError('la caja de entradas no está en este equipo');
    }
    return CajaEntradas.fromMap(filas.first);
  }

  @override
  Future<CajaEntradas> cerrarCaja(
    CajaEntradas caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final enLaBase = await _laDeEsteEquipo(txn, caja);
      // Una caja cerrada no se vuelve a cerrar ni se corrige.
      if (!enLaBase.abierta) return enLaBase;
      final ahora = _reloj();
      final cerrada = enLaBase
          .cerrada(
            efectivoContado: efectivoContado,
            diferencia: diferencia,
            nota: nota,
            ahora: ahora,
          )
          .sellada(hechoPor: quien, deviceId: equipo, ahora: ahora);
      await _guardar(txn, tablaCajas, cerrada.id, cerrada.toMap());
      return cerrada;
    });
  }

  @override
  Future<CajaEntradas> anotarCierre(
    CajaEntradas caja, {
    String? nota,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final enLaBase = await _laDeEsteEquipo(txn, caja);
      if (enLaBase.abierta) return enLaBase;
      final conNota = enLaBase
          .conNota(nota)
          .sellada(hechoPor: quien, deviceId: equipo, ahora: _reloj());
      await _guardar(txn, tablaCajas, conNota.id, conNota.toMap());
      return conNota;
    });
  }

  // ── Las ventas ─────────────────────────────────────────────────────────────

  @override
  Future<VentaEntradas> vender({
    required CajaEntradas caja,
    String? contratoAlumnoId,
    required String compradorNombre,
    String? compradorDni,
    required List<RenglonEntradas> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    String? numeros,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final enLaBase = await _laDeEsteEquipo(txn, caja);
      if (!enLaBase.abierta) {
        throw StateError('la caja de entradas está cerrada');
      }
      // El número, dentro de la misma transacción: dos ventas seguidas no
      // pueden llevar el mismo.
      final ultimo = await txn.rawQuery(
        'SELECT MAX(numero) AS n FROM $tablaVentas WHERE caja_entradas_id = ?',
        [caja.id],
      );
      final numero = ((ultimo.first['n'] as num?)?.toInt() ?? 0) + 1;
      final venta = VentaEntradas.nueva(
        cajaEntradasId: caja.id,
        eventoId: caja.eventoId,
        numero: numero,
        contratoAlumnoId: contratoAlumnoId,
        compradorNombre: compradorNombre,
        compradorDni: compradorDni,
        renglones: renglones,
        medio: medio,
        efectivo: efectivo,
        transferencia: transferencia,
        recibe: recibe,
        recargo: recargo,
        recargoPct: recargoPct,
        numeros: numeros,
        hechoPor: quien,
        deviceId: equipo,
        ahora: _reloj(),
      );
      await _guardar(txn, tablaVentas, venta.id, venta.toMap());
      return venta;
    });
  }

  @override
  Future<List<VentaEntradas>> ventas(String eventoId) async => [
        for (final f in await _leer(
          tablaVentas,
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'created_at, numero',
        ))
          VentaEntradas.fromMap(f),
      ];

  @override
  Future<List<VentaEntradas>> ventasDeLaCaja(String cajaId) async => [
        for (final f in await _leer(
          tablaVentas,
          where: 'caja_entradas_id = ?',
          whereArgs: [cajaId],
          orderBy: 'numero',
        ))
          VentaEntradas.fromMap(f),
      ];

  @override
  Future<int> ventasSinSubir() async {
    try {
      final db = await _abrir();
      final filas = await db.rawQuery(
        'SELECT COUNT(DISTINCT registro_id) AS n FROM _sync_queue WHERE tabla = ?',
        [tablaVentas],
      );
      return (filas.first['n'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Las anulaciones ────────────────────────────────────────────────────────

  @override
  Future<List<AnulacionEntradas>> anulaciones(String eventoId) async => [
        for (final f in await _leer(
          tablaAnulaciones,
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'created_at',
        ))
          AnulacionEntradas.fromMap(f),
      ];

  @override
  Future<List<AnulacionEntradas>> anulacionesDeLaCaja(String cajaId) async => [
        for (final f in await _leer(
          tablaAnulaciones,
          where: 'caja_entradas_id = ?',
          whereArgs: [cajaId],
          orderBy: 'created_at',
        ))
          AnulacionEntradas.fromMap(f),
      ];

  @override
  Future<AnulacionEntradas> anular(
    VentaEntradas venta, {
    required String motivo,
    required bool devueltas,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    final nueva = AnulacionEntradas.de(
      venta,
      motivo: motivo,
      devueltas: devueltas,
      hechoPor: quien,
      deviceId: equipo,
      ahora: _reloj(),
    );
    return db.transaction((txn) async {
      final ya = await txn.query(
        tablaAnulaciones,
        where: 'id = ?',
        whereArgs: [nueva.id],
        limit: 1,
      );
      // Anular dos veces devuelve la que ya había: solo se agregan filas.
      if (ya.isNotEmpty) return AnulacionEntradas.fromMap(ya.first);
      await _guardar(txn, tablaAnulaciones, nueva.id, nueva.toMap());
      return nueva;
    });
  }

  // ── "Pago verificado" ──────────────────────────────────────────────────────

  @override
  Future<List<VerificacionEntradas>> verificaciones(String eventoId) async => [
        for (final f in await _leer(
          tablaVerificaciones,
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'created_at',
        ))
          VerificacionEntradas.fromMap(f),
      ];

  @override
  Future<VerificacionEntradas> verificar(
    VentaEntradas venta, {
    required bool verificado,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final fila = VerificacionEntradas.de(
        venta,
        verificado: verificado,
        hechoPor: quien,
        deviceId: equipo,
        createdAt: await _nacio(
          txn,
          tablaVerificaciones,
          VerificacionEntradas.de(venta, verificado: verificado, ahora: _reloj()).id,
        ),
        ahora: _reloj(),
      );
      await _guardar(txn, tablaVerificaciones, fila.id, fila.toMap());
      return fila;
    });
  }
}
