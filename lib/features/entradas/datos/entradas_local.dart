import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/instalacion_id.dart';
import '../../../models/entradas_retiro.dart' show TramoTalonario;
import 'entradas_repositorio.dart';

/// La venta de entradas en este equipo — la base de la PC o de la tablet, y la
/// cola de subida (v80; las entradas para rendir, v82).
///
/// Todo lo que escribe va con su entrada en la cola, **en la misma
/// transacción**: sube solo cuando hay internet. **Nada se borra:** una caja se
/// cierra, y una venta se anula con otra fila.
///
/// **No toca ninguna tabla que no sea de las de entradas** (las cinco de
/// [tablas] y [tablaParaRendir]). Una venta de
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

  /// Las cinco de la v80, en el orden en que conviene crearlas y subirlas.
  static const tablas = [
    tablaConfig,
    tablaCajas,
    tablaVentas,
    tablaAnulaciones,
    tablaVerificaciones,
  ];

  /// Las entradas para rendir (v82, 20-nov-2026). **No entra en [tablas]**: esa
  /// lista es la de la v80 (`test/sync_tablas_v80_test.dart` exige cinco) y esta
  /// tabla es de otra versión de la base.
  static const tablaParaRendir = 'entradas_para_rendir';

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
    final enLaBase = await _laDeEsteEquipoONull(txn, caja);
    if (enLaBase == null) {
      throw StateError('la caja de entradas no está en este equipo');
    }
    return enLaBase;
  }

  /// La caja como está en la base de este equipo, o null si no está.
  ///
  /// **Mira que esté en la base, no en qué equipo se abrió** (como siempre hizo
  /// [vender]): las cajas también bajan de la nube, así que una abierta en la
  /// tablet puede estar en la base de la PC. La caja que se abrió acá la da
  /// [cajaAbierta], que es de donde la sacan las pantallas.
  Future<CajaEntradas?> _laDeEsteEquipoONull(DatabaseExecutor txn, CajaEntradas caja) async {
    final filas = await txn.query(
      tablaCajas,
      where: 'id = ?',
      whereArgs: [caja.id],
      limit: 1,
    );
    return filas.isEmpty ? null : CajaEntradas.fromMap(filas.first);
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
    return db.transaction(
      (txn) => _venderEn(
        txn,
        equipo: equipo,
        caja: caja,
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
        quien: quien,
      ),
    );
  }

  /// El cuerpo de [vender], **dentro de una transacción que ya está abierta**:
  /// lo usan [vender] y [rendir] (20-nov-2026), así la venta de una rendición se
  /// guarda con las mismas reglas (caja de este equipo y abierta, el número que
  /// sigue) y en la misma transacción que sus renglones.
  Future<VentaEntradas> _venderEn(
    DatabaseExecutor txn, {
    required String? equipo,
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

  @override
  Future<int> cambiosSinSubir() async {
    try {
      final db = await _abrir();
      final filas = await db.rawQuery(
        'SELECT COUNT(DISTINCT tabla || registro_id) AS n FROM _sync_queue '
        'WHERE tabla IN (?, ?, ?, ?, ?)',
        // Las entradas para rendir también (20-nov-2026): un bloque dado o una
        // devolución sin subir no puede dejar la línea en "Todo subido".
        [
          tablaCajas,
          tablaAnulaciones,
          tablaVerificaciones,
          tablaConfig,
          tablaParaRendir,
        ],
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

  // ── Las entradas para rendir (v82, 20-nov-2026) ────────────────────────────
  //
  // Solo se agregan renglones a `entradas_para_rendir`; la plata de una
  // rendición es una venta común de `entradas_ventas`. Lo que frena (cuántas le
  // quedan, qué números ya no tiene) se vuelve a contar dentro de la misma
  // transacción que escribe: la pantalla puede tener la cuenta vieja.

  @override
  Future<List<MovimientoParaRendir>> paraRendir(String eventoId) async => [
        for (final f in await _leer(
          tablaParaRendir,
          where: 'evento_id = ?',
          whereArgs: [eventoId],
          orderBy: 'created_at, id',
        ))
          MovimientoParaRendir.fromMap(f),
      ];

  /// El bloque como está en la base de este equipo: el precio y el nombre que
  /// valen son los de acá, no los que trae la pantalla.
  Future<MovimientoParaRendir> _bloqueDeLaBase(
    DatabaseExecutor txn,
    MovimientoParaRendir bloque,
  ) async {
    final filas = await txn.query(
      tablaParaRendir,
      where: 'id = ?',
      whereArgs: [bloque.id],
      limit: 1,
    );
    if (filas.isEmpty) {
      throw StateError('el bloque para rendir no está en este equipo');
    }
    final enLaBase = MovimientoParaRendir.fromMap(filas.first);
    if (!enLaBase.esDio) {
      throw StateError('lo que se quiere rendir no es un bloque dado');
    }
    return enLaBase;
  }

  Future<List<MovimientoParaRendir>> _movimientosDelBloque(
    DatabaseExecutor txn,
    String bloqueId,
  ) async =>
      [
        for (final f in await txn.query(
          tablaParaRendir,
          where: 'bloque_id = ?',
          whereArgs: [bloqueId],
          orderBy: 'created_at, id',
        ))
          MovimientoParaRendir.fromMap(f),
      ];

  /// Las ventas de lo rendido que se anularon en VENTAS: esas entradas vuelven
  /// a quedar a cargo de quien las llevó.
  Future<Set<String>> _ventasAnuladas(
    DatabaseExecutor txn,
    List<MovimientoParaRendir> movimientos,
  ) async {
    final ventas = {
      for (final m in movimientos)
        if (m.esVendio && m.ventaId != null) m.ventaId!,
    }.toList();
    if (ventas.isEmpty) return const <String>{};
    final filas = await txn.query(
      tablaAnulaciones,
      columns: ['venta_id'],
      where: 'venta_id IN (${List.filled(ventas.length, '?').join(', ')})',
      whereArgs: ventas,
    );
    return {for (final f in filas) '${f['venta_id']}'};
  }

  /// Lo que hoy cuenta de [bloque] y cuántas le quedan, contado en [txn].
  Future<({List<MovimientoParaRendir> vigentes, int quedan})> _cuentaDelBloque(
    DatabaseExecutor txn,
    MovimientoParaRendir bloque,
  ) async {
    final movimientos = await _movimientosDelBloque(txn, bloque.id);
    final anuladas = await _ventasAnuladas(txn, movimientos);
    return (
      vigentes: MovimientoParaRendir.vigentesDe(
        bloque,
        movimientos,
        ventasAnuladas: anuladas,
      ),
      quedan: MovimientoParaRendir.quedanSinRendir(
        bloque,
        movimientos,
        ventasAnuladas: anuladas,
      ),
    );
  }

  /// Un número de [tramos] que ya volvió o se dio por perdido (en [vigentes]):
  /// ese ya no lo tiene. Null si no hay ninguno.
  static int? _yaNoLoTiene(
    List<MovimientoParaRendir> vigentes,
    List<TramoTalonario> tramos,
  ) {
    for (final m in vigentes) {
      if (!m.esDevolvio && !m.esNoVolvieron) continue;
      for (final suyo in m.tramos) {
        for (final t in tramos) {
          if (t.seCruzaCon(suyo)) return max(t.desde, suyo.desde);
        }
      }
    }
    return null;
  }

  @override
  Future<MovimientoParaRendir> darParaRendir({
    required String eventoId,
    required String personaNombre,
    String? personaContacto,
    String? contratoAlumnoId,
    required int cantidad,
    required List<TramoTalonario> numeros,
    required double precio,
    required String nombrePrecio,
    String? nota,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    final dio = MovimientoParaRendir.dio(
      eventoId: eventoId,
      personaNombre: personaNombre,
      personaContacto: personaContacto,
      contratoAlumnoId: contratoAlumnoId,
      cantidad: cantidad,
      tramos: numeros,
      precio: precio,
      nombrePrecio: nombrePrecio,
      nota: nota,
      hechoPor: quien,
      deviceId: equipo,
      ahora: _reloj(),
    );
    return db.transaction((txn) async {
      await _guardar(txn, tablaParaRendir, dio.id, dio.toMap());
      return dio;
    });
  }

  @override
  Future<RendicionDeEntradas> rendir({
    CajaEntradas? caja,
    required MovimientoParaRendir bloque,
    required int vendidas,
    int devueltas = 0,
    List<TramoTalonario> numerosDevueltos = const [],
    MedioBarra medio = MedioBarra.efectivo,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    required String quien,
  }) async {
    Never no(String por) => throw ArgumentError('la rendición no cierra: $por');
    if (vendidas < 0 || devueltas < 0) no('las cantidades van de 0 en adelante');
    if (vendidas + devueltas < 1) no('no vendió ni devolvió nada');
    final numeros = numerosDevueltos.fold<int>(0, (s, t) => s + t.cantidad);
    if (numeros != devueltas) {
      no('devuelve $devueltas y vienen $numeros números');
    }
    if (vendidas > 0 && caja == null) no('lo vendido se cobra con la caja abierta');
    if (vendidas == 0 && (efectivo != 0 || transferencia != 0 || recargo != 0)) {
      no('si solo devuelve, no entra plata');
    }
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final enLaBase = await _bloqueDeLaBase(txn, bloque);
      // La caja y la fiesta, como están en la base, no como las trae la
      // pantalla (20-nov-2026): una caja de otra fiesta no cobra lo de esta.
      // Para cobrar, la caja tiene que estar en la base de este equipo y
      // abierta (lo frena [_venderEn], igual que en [vender]; que sea la que se
      // abrió acá lo da [cajaAbierta], de donde la saca VENDER). Si solo
      // devuelve, el renglón lleva la caja solo si está en la base y abierta;
      // si no, va sin caja: nunca apuntando a una caja que no existe.
      final cajaEnLaBase = caja == null ? null : await _laDeEsteEquipoONull(txn, caja);
      if (cajaEnLaBase != null && cajaEnLaBase.eventoId != enLaBase.eventoId) {
        no('la caja es de otra fiesta');
      }
      final cajaQueRecibe =
          cajaEnLaBase != null && cajaEnLaBase.abierta ? cajaEnLaBase.id : null;
      // Primero lo que se pide (si no cierra, ArgumentError); después la cuenta
      // del momento (si cambió algo, StateError). Nada se escribió todavía.
      final devolvio = devueltas == 0
          ? null
          : MovimientoParaRendir.devolvio(
              enLaBase,
              tramos: numerosDevueltos,
              cajaEntradasId: cajaQueRecibe,
              hechoPor: quien,
              deviceId: equipo,
              ahora: _reloj(),
            );
      final cuenta = await _cuentaDelBloque(txn, enLaBase);
      if (vendidas + devueltas > cuenta.quedan) {
        throw StateError(
          'cambió algo: a ${enLaBase.personaNombre} le quedan ${cuenta.quedan} '
          'sin rendir y se quieren rendir ${vendidas + devueltas}',
        );
      }
      final yaNo = _yaNoLoTiene(cuenta.vigentes, numerosDevueltos);
      if (yaNo != null) {
        throw StateError('cambió algo: el $yaNo ya no lo tiene ${enLaBase.personaNombre}');
      }
      VentaEntradas? venta;
      MovimientoParaRendir? vendio;
      if (vendidas > 0) {
        final precio = enLaBase.precio;
        if (precio == null || precio <= 0) {
          throw StateError('el bloque para rendir no tiene precio');
        }
        // Al precio y con el nombre del día en que se las llevó, sin descuento
        // ni comisión: rinde toda la plata. A nombre de quien rinde, **sin
        // familia** (si no, las contaría como compradas por ella) y sin
        // números (los lleva el bloque). Con la caja de la base: si no está
        // acá o está cerrada, [_venderEn] no cobra.
        venta = await _venderEn(
          txn,
          equipo: equipo,
          caja: cajaEnLaBase ?? caja!,
          contratoAlumnoId: null,
          compradorNombre: enLaBase.personaNombre ?? '',
          renglones: [
            RenglonEntradas.suelta(
              nombre: '${enLaBase.nombrePrecio ?? 'Entrada'} · para rendir',
              precioLista: precio,
              descuentoPct: 0,
              cantidad: vendidas,
            ),
          ],
          medio: medio,
          efectivo: efectivo,
          transferencia: transferencia,
          recibe: recibe,
          recargo: recargo,
          recargoPct: recargoPct,
          numeros: null,
          quien: quien,
        );
        vendio = MovimientoParaRendir.vendio(
          enLaBase,
          cantidad: vendidas,
          ventaId: venta.id,
          cajaEntradasId: venta.cajaEntradasId,
          hechoPor: quien,
          deviceId: equipo,
          ahora: _reloj(),
        );
        await _guardar(txn, tablaParaRendir, vendio.id, vendio.toMap());
      }
      if (devolvio != null) {
        await _guardar(txn, tablaParaRendir, devolvio.id, devolvio.toMap());
      }
      return RendicionDeEntradas(venta: venta, vendio: vendio, devolvio: devolvio);
    });
  }

  @override
  Future<MovimientoParaRendir> noVolvieron(
    MovimientoParaRendir bloque, {
    required int cantidad,
    List<TramoTalonario> numeros = const [],
    required String motivo,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    return db.transaction((txn) async {
      final enLaBase = await _bloqueDeLaBase(txn, bloque);
      final perdidas = MovimientoParaRendir.noVolvieron(
        enLaBase,
        cantidad: cantidad,
        tramos: numeros,
        motivo: motivo,
        hechoPor: quien,
        deviceId: equipo,
        ahora: _reloj(),
      );
      final cuenta = await _cuentaDelBloque(txn, enLaBase);
      if (cantidad > cuenta.quedan) {
        throw StateError(
          'cambió algo: a ${enLaBase.personaNombre} le quedan ${cuenta.quedan} '
          'sin rendir y se quieren dar por perdidas $cantidad',
        );
      }
      final yaNo = _yaNoLoTiene(cuenta.vigentes, numeros);
      if (yaNo != null) {
        throw StateError('cambió algo: el $yaNo ya no lo tiene ${enLaBase.personaNombre}');
      }
      await _guardar(txn, tablaParaRendir, perdidas.id, perdidas.toMap());
      return perdidas;
    });
  }

  @override
  Future<MovimientoParaRendir> anularDeParaRendir(
    MovimientoParaRendir movimiento, {
    required String motivo,
    required String quien,
  }) async {
    final db = await _abrir();
    final equipo = await _equipo();
    final ahora = _reloj();
    // Arma la anulación antes de abrir la transacción: sin motivo, o sobre algo
    // que no se anula acá (lo vendido), ni la mira.
    final nueva = MovimientoParaRendir.anulo(
      movimiento,
      motivo: motivo,
      hechoPor: quien,
      deviceId: equipo,
      ahora: ahora,
    );
    return db.transaction((txn) async {
      final ya = await txn.query(
        tablaParaRendir,
        where: 'id = ?',
        whereArgs: [nueva.id],
        limit: 1,
      );
      // Anular dos veces (o desde dos equipos) devuelve la que ya había: solo
      // se agregan filas, y el id es fijo.
      if (ya.isNotEmpty) return MovimientoParaRendir.fromMap(ya.first);
      final filas = await txn.query(
        tablaParaRendir,
        where: 'id = ?',
        whereArgs: [movimiento.id],
        limit: 1,
      );
      if (filas.isEmpty) {
        throw StateError('lo que se quiere anular no está en este equipo');
      }
      final enLaBase = MovimientoParaRendir.fromMap(filas.first);
      if (enLaBase.esDio) {
        // Un bloque se anula solo si no le queda nada en pie: lo rendido se
        // anula antes en VENTAS, y lo devuelto o perdido, acá.
        final cuenta = await _cuentaDelBloque(txn, enLaBase);
        if (cuenta.vigentes.isNotEmpty) {
          throw StateError(
            'el bloque de ${enLaBase.personaNombre} tiene movimientos: '
            'anulá primero lo que tiene',
          );
        }
      }
      final anulo = MovimientoParaRendir.anulo(
        enLaBase,
        motivo: motivo,
        hechoPor: quien,
        deviceId: equipo,
        ahora: ahora,
      );
      await _guardar(txn, tablaParaRendir, anulo.id, anulo.toMap());
      return anulo;
    });
  }
}
