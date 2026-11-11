import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/instalacion_id.dart';
import '../../../core/utils/uuid_utils.dart';
import '../central/filas_de_la_red.dart';
import 'barra_repositorio.dart';

/// La barra en este equipo — la base de la PC o de la tablet, y la cola de subida.
///
/// Todo lo que escribe va con su entrada en la cola, en la misma transacción: sube
/// solo cuando hay internet. **Nada se borra:** un producto se da de baja, una caja
/// se cierra y una venta se anula con otra fila.
///
/// **Lo que llega de otra caja por la red del salón** ([guardarDeOtroEquipo]) se guarda
/// sin la cola: lo sube el equipo que lo hizo.
///
/// Leer sin las tablas (una base que todavía no migró) no tira: da la lista vacía.
class BarraLocal implements BarraDelJefe, BarraDeLaCaja, BarraDeLaRed {
  BarraLocal({
    Future<Database> Function()? abrir,
    Future<String?> Function()? equipo,
    DateTime Function()? reloj,
  })  : _abrir = abrir ?? (() => LocalDatabase.instance),
        _equipo = equipo ?? InstalacionId.inicializar,
        _reloj = reloj ?? DateTime.now;

  final Future<Database> Function() _abrir;
  final Future<String?> Function() _equipo;
  final DateTime Function() _reloj;

  Future<List<Map<String, Object?>>> _leer(
    String tabla, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    try {
      final db = await _abrir();
      return await db.query(tabla, where: where, whereArgs: whereArgs, orderBy: orderBy);
    } catch (e) {
      debugPrint('⚠️ Barra: $tabla sin leer: $e');
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

  // ── El catálogo y los precios ──────────────────────────────────────────────

  @override
  Future<List<ProductoBarra>> productos({bool conBajas = false}) async => [
        for (final f in await _leer(
          'barra_productos',
          where: conBajas ? null : 'activo = 1',
          orderBy: 'orden, nombre COLLATE NOCASE',
        ))
          ProductoBarra.fromMap(f),
      ];

  @override
  Future<ProductoBarra> guardarProducto(
    ProductoBarra producto, {
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final sellado = producto.sellado(
        hechoPor: quien,
        deviceId: equipo,
        createdAt: await _nacio(txn, 'barra_productos', producto.id),
        ahora: _reloj(),
      );
      await _guardar(txn, 'barra_productos', sellado.id, sellado.toMap());
      return sellado;
    });
  }

  @override
  Future<List<PrecioBarra>> precios(String eventoId, {bool conBajas = false}) async => [
        for (final f in await _leer(
          'barra_precios',
          where: conBajas ? 'evento_id = ?' : 'evento_id = ? AND activo = 1',
          whereArgs: [eventoId],
          orderBy: 'orden',
        ))
          PrecioBarra.fromMap(f),
      ];

  @override
  Future<Set<String>> fiestasConPrecio() async => {
        for (final f in await _leer(
          'barra_precios',
          where: 'activo = 1',
        ))
          f['evento_id'] as String,
      };

  @override
  Future<int> ventasSinSubir() async {
    try {
      final db = await _abrir();
      final filas = await db.rawQuery(
        "SELECT COUNT(DISTINCT registro_id) AS n FROM _sync_queue WHERE tabla = 'barra_ventas'",
      );
      return (filas.first['n'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('⚠️ Barra: no se pudieron contar las ventas sin subir: $e');
      return 0;
    }
  }

  @override
  Future<PrecioBarra> guardarPrecio(PrecioBarra precio, {required String quien}) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final sellado = precio.sellado(
        hechoPor: quien,
        deviceId: equipo,
        createdAt: await _nacio(txn, 'barra_precios', precio.id),
        ahora: _reloj(),
      );
      await _guardar(txn, 'barra_precios', sellado.id, sellado.toMap());
      return sellado;
    });
  }

  @override
  Future<RecargoBarra?> recargo(String eventoId) async {
    final filas = await _leer(
      'barra_recargos',
      where: 'id = ?',
      whereArgs: [UuidUtils.barraRecargoId(eventoId)],
    );
    return filas.isEmpty ? null : RecargoBarra.fromMap(filas.first);
  }

  @override
  Future<RecargoBarra> guardarRecargo(RecargoBarra recargo, {required String quien}) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final sellado = recargo.sellado(
        hechoPor: quien,
        deviceId: equipo,
        createdAt: await _nacio(txn, 'barra_recargos', recargo.id),
        ahora: _reloj(),
      );
      await _guardar(txn, 'barra_recargos', sellado.id, sellado.toMap());
      return sellado;
    });
  }

  // ── Las cajas ──────────────────────────────────────────────────────────────

  @override
  Future<List<CajaBarra>> cajas(String eventoId) async => [
        for (final f in await _leer(
          'barra_cajas',
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'numero_caja, abierta_at',
        ))
          CajaBarra.fromMap(f),
      ];

  @override
  Future<List<CajaBarra>> cajasAbiertas(String eventoId) async => [
        for (final f in await _leer(
          'barra_cajas',
          where: 'evento_id = ? AND cerrada_at IS NULL',
          whereArgs: [eventoId],
          orderBy: 'numero_caja, abierta_at',
        ))
          CajaBarra.fromMap(f),
      ];

  @override
  Future<CajaBarra?> cajaAbierta({
    required String eventoId,
    required String operadorId,
  }) async {
    final equipo = await _equipo();
    final filas = await _leer(
      'barra_cajas',
      where: 'evento_id = ? AND operador_id = ? AND device_id = ? AND cerrada_at IS NULL',
      whereArgs: [eventoId, operadorId, equipo],
      orderBy: 'abierta_at DESC',
    );
    return filas.isEmpty ? null : CajaBarra.fromMap(filas.first);
  }

  @override
  Future<CajaBarra> abrirCaja({
    required String eventoId,
    required String operadorId,
    required String operadorNombre,
    required int numeroCaja,
    String? sede,
    double cambioInicial = 0,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      // Adentro de la transacción: dos toques seguidos no abren dos cajas.
      final ya = await txn.query(
        'barra_cajas',
        where: 'evento_id = ? AND operador_id = ? AND device_id = ? AND cerrada_at IS NULL',
        whereArgs: [eventoId, operadorId, equipo],
        orderBy: 'abierta_at DESC',
        limit: 1,
      );
      if (ya.isNotEmpty) return CajaBarra.fromMap(ya.first);
      final ahora = _reloj();
      final caja = CajaBarra.abrir(
        eventoId: eventoId,
        operadorId: operadorId,
        operadorNombre: operadorNombre,
        numeroCaja: numeroCaja,
        sede: sede,
        cambioInicial: cambioInicial,
        ahora: ahora,
      ).sellada(hechoPor: operadorNombre, deviceId: equipo, ahora: ahora);
      await _guardar(txn, 'barra_cajas', caja.id, caja.toMap());
      return caja;
    });
  }

  @override
  Future<CajaBarra> ponerCambio(CajaBarra caja, double cambio, {required String quien}) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final filas = await txn.query(
        'barra_cajas',
        where: 'id = ?',
        whereArgs: [caja.id],
        limit: 1,
      );
      if (filas.isEmpty) {
        throw StateError('la caja ${caja.numeroCaja} no está en este equipo');
      }
      final enLaBase = CajaBarra.fromMap(filas.first);
      if (!enLaBase.abierta) return enLaBase;
      final ahora = _reloj();
      final conCambio =
          enLaBase.conCambio(cambio).sellada(hechoPor: quien, deviceId: equipo, ahora: ahora);
      await _guardar(txn, 'barra_cajas', conCambio.id, conCambio.toMap());
      return conCambio;
    });
  }

  @override
  Future<CajaBarra> cerrarCaja(
    CajaBarra caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final filas = await txn.query(
        'barra_cajas',
        where: 'id = ?',
        whereArgs: [caja.id],
        limit: 1,
      );
      if (filas.isEmpty) {
        throw StateError('la caja ${caja.numeroCaja} no está en este equipo');
      }
      final enLaBase = CajaBarra.fromMap(filas.first);
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
      await _guardar(txn, 'barra_cajas', cerrada.id, cerrada.toMap());
      return cerrada;
    });
  }

  @override
  Future<CajaBarra> anotarCierre(CajaBarra caja, {String? nota, required String quien}) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final filas = await txn.query(
        'barra_cajas',
        where: 'id = ?',
        whereArgs: [caja.id],
        limit: 1,
      );
      if (filas.isEmpty) {
        throw StateError('la caja ${caja.numeroCaja} no está en este equipo');
      }
      final enLaBase = CajaBarra.fromMap(filas.first);
      if (enLaBase.abierta) return enLaBase;
      final conNota =
          enLaBase.conNota(nota).sellada(hechoPor: quien, deviceId: equipo, ahora: _reloj());
      await _guardar(txn, 'barra_cajas', conNota.id, conNota.toMap());
      return conNota;
    });
  }

  // ── Las ventas ─────────────────────────────────────────────────────────────

  @override
  Future<VentaBarra> vender({
    required CajaBarra caja,
    required List<RenglonVenta> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final filas = await txn.query(
        'barra_cajas',
        columns: ['cerrada_at'],
        where: 'id = ?',
        whereArgs: [caja.id],
        limit: 1,
      );
      if (filas.isEmpty) {
        throw StateError('la caja ${caja.numeroCaja} no está en este equipo');
      }
      if (filas.first['cerrada_at'] != null) {
        throw StateError('la caja ${caja.numeroCaja} está cerrada');
      }
      // El número, dentro de la misma transacción: dos ventas seguidas no pueden
      // llevar el mismo.
      final ultimo = await txn.rawQuery(
        'SELECT MAX(numero) AS n FROM barra_ventas WHERE caja_barra_id = ?',
        [caja.id],
      );
      final numero = ((ultimo.first['n'] as num?)?.toInt() ?? 0) + 1;
      final venta = VentaBarra.nueva(
        cajaBarraId: caja.id,
        eventoId: caja.eventoId,
        numero: numero,
        renglones: renglones,
        medio: medio,
        efectivo: efectivo,
        transferencia: transferencia,
        recibe: recibe,
        recargo: recargo,
        recargoPct: recargoPct,
        hechoPor: quien,
        deviceId: equipo,
        ahora: _reloj(),
      );
      await _guardar(txn, 'barra_ventas', venta.id, venta.toMap());
      return venta;
    });
  }

  @override
  Future<List<VentaBarra>> ventas(String eventoId) async => [
        for (final f in await _leer(
          'barra_ventas',
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'created_at, numero',
        ))
          VentaBarra.fromMap(f),
      ];

  @override
  Future<List<VentaBarra>> ventasDeLaCaja(String cajaId) async => [
        for (final f in await _leer(
          'barra_ventas',
          where: 'caja_barra_id = ?',
          whereArgs: [cajaId],
          orderBy: 'numero',
        ))
          VentaBarra.fromMap(f),
      ];

  // ── Las anulaciones ────────────────────────────────────────────────────────

  @override
  Future<List<AnulacionBarra>> anulaciones(String eventoId) async => [
        for (final f in await _leer(
          'barra_anulaciones',
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'created_at',
        ))
          AnulacionBarra.fromMap(f),
      ];

  @override
  Future<List<AnulacionBarra>> anulacionesDeLaCaja(String cajaId) async => [
        for (final f in await _leer(
          'barra_anulaciones',
          where: 'caja_barra_id = ?',
          whereArgs: [cajaId],
          orderBy: 'created_at',
        ))
          AnulacionBarra.fromMap(f),
      ];

  @override
  Future<AnulacionBarra> anular(
    VentaBarra venta, {
    required String motivo,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    final nueva = AnulacionBarra.de(
      venta,
      motivo: motivo,
      hechoPor: quien,
      deviceId: equipo,
      ahora: _reloj(),
    );
    return db.transaction((txn) async {
      final ya = await txn.query(
        'barra_anulaciones',
        where: 'id = ?',
        whereArgs: [nueva.id],
        limit: 1,
      );
      if (ya.isNotEmpty) return AnulacionBarra.fromMap(ya.first);
      await _guardar(txn, 'barra_anulaciones', nueva.id, nueva.toMap());
      return nueva;
    });
  }

  // ── Los vales que salieron ─────────────────────────────────────────────────

  @override
  Future<ValeBarra> anotarVale(ValeBarra vale) async {
    final db = await _abrir();
    final fila = vale.toMap()..['device_id'] = await _equipo();
    await db.transaction((txn) => _guardar(txn, 'barra_vales', vale.id, fila));
    return ValeBarra.fromMap(fila);
  }

  @override
  Future<List<ValeBarra>> valesDeLaCaja(String cajaId) async => [
        for (final f in await _leer(
          'barra_vales',
          where: 'caja_barra_id = ?',
          whereArgs: [cajaId],
          orderBy: 'created_at',
        ))
          ValeBarra.fromMap(f),
      ];

  @override
  Future<List<ValeBarra>> vales(String eventoId) async => [
        for (final f in await _leer(
          'barra_vales',
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'created_at',
        ))
          ValeBarra.fromMap(f),
      ];

  // ── El cierre con el OK de la encargada (v79) ──────────────────────────────

  @override
  Future<PasoDelCierre> anotarPasoDelCierre(PasoDelCierre paso) async {
    final db = await _abrir();
    final conEquipo = paso.conEquipo(await _equipo());
    await db.transaction(
      (txn) => _guardar(txn, 'barra_cierres', conEquipo.id, conEquipo.toMap()),
    );
    return conEquipo;
  }

  @override
  Future<List<PasoDelCierre>> pasosDelCierre(String eventoId) async => [
        for (final f in await _leer(
          'barra_cierres',
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'created_at, id',
        ))
          PasoDelCierre.fromMap(f),
      ];

  // ── La red del salón (la central de la barra) ─────────────────────────────

  /// Las columnas de cada tabla en esta base: una fila de un equipo con otra versión
  /// puede traer una de más, y se le saca antes de guardarla.
  final _columnas = <String, Set<String>>{};

  Future<Set<String>> _columnasDe(DatabaseExecutor db, String tabla) async {
    final ya = _columnas[tabla];
    if (ya != null) return ya;
    final filas = await db.rawQuery('PRAGMA table_info($tabla)');
    return _columnas[tabla] = {for (final f in filas) f['name'] as String};
  }

  @override
  Future<bool> guardarDeOtroEquipo(String tabla, Map<String, Object?> fila) async {
    if (!tablasDeLaRed.contains(tabla)) return false;
    final id = fila['id'];
    if (id is! String || id.length != 36) return false;
    final db = await _abrir();
    return db.transaction((txn) async {
      // Lo de este equipo que todavía no subió manda: es lo último que se hizo acá.
      final enLaCola = await txn.query(
        '_sync_queue',
        columns: ['id'],
        where: 'tabla = ? AND registro_id = ?',
        whereArgs: [tabla, id],
        limit: 1,
      );
      if (enLaCola.isNotEmpty) return false;
      final columnas = await _columnasDe(txn, tabla);
      final limpia = {
        for (final e in fila.entries)
          if (columnas.contains(e.key)) e.key: e.value,
      };
      final ya = await txn.query(tabla, where: 'id = ?', whereArgs: [id], limit: 1);
      if (ya.isNotEmpty && !cambiaLaFila(nueva: limpia, vieja: ya.first)) return false;
      await txn.insert(tabla, limpia, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  @override
  Future<Map<String, List<Map<String, Object?>>>> filasDeLaFiesta(String eventoId) async => {
        for (final tabla in tablasDeLaRed)
          tabla: [
            for (final f in await _leer(tabla, where: 'evento_id = ?', whereArgs: [eventoId]))
              Map<String, Object?>.from(f),
          ],
      };

  @override
  Future<Map<String, Object?>?> filaDeLaRed(String tabla, String id) async {
    if (!tablasDeLaRed.contains(tabla)) return null;
    final filas = await _leer(tabla, where: 'id = ?', whereArgs: [id]);
    return filas.isEmpty ? null : Map<String, Object?>.from(filas.first);
  }

  @override
  Future<PendientesDeLaBarra> pendientesDeLaBarra() async {
    try {
      final db = await _abrir();
      final filas = await db.rawQuery(
        "SELECT tabla, COUNT(DISTINCT registro_id) AS n FROM _sync_queue WHERE tabla LIKE 'barra_%' GROUP BY tabla",
      );
      var ventas = 0, otros = 0;
      for (final f in filas) {
        final n = (f['n'] as num?)?.toInt() ?? 0;
        if (f['tabla'] == 'barra_ventas') {
          ventas += n;
        } else {
          otros += n;
        }
      }
      return PendientesDeLaBarra(ventas: ventas, otros: otros);
    } catch (e) {
      debugPrint('⚠️ Barra: no se pudo contar lo que espera subir: $e');
      return PendientesDeLaBarra.nada;
    }
  }
}
