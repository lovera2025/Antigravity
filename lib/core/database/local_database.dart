import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/sqflite.dart' show databaseFactory;
import 'package:sqflite/sqflite.dart' as sqflite_mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/pago_interes_mora.dart';
import '../utils/ar_time.dart';
import '../utils/uuid_utils.dart';
import '../../models/contrato_alumno.dart';
import '../../features/eventos/services/cobro_abono_acumulado.dart';
import '../../features/eventos/services/cronograma_cuotas_utils.dart';
import '../../features/eventos/services/mora_cuota_calculator.dart';
import '../../features/eventos/services/mora_tracked_recovery.dart';
import '../../features/eventos/utils/evento_presentacion.dart';
import 'sync_queue.dart';

/// Base de datos local SQLite — persistencia offline.
///
/// Almacena en: Mis Documentos/Junior Eventos/data.db
/// Esquema espejo de Supabase para sincronización bidireccional.
class LocalDatabase {
  static Database? _db;
  static const String _dbName = 'data.db';
  static const int _version = 66;

  /// Singleton de acceso a la base de datos.
  static Future<Database> get instance async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<String> get dbPath async {
    // Almacenar en Mis Documentos/Junior Eventos/
    final docsDir = await getApplicationDocumentsDirectory();
    final oldDir = Directory(
      '${docsDir.path}${Platform.pathSeparator}JuniorEventos',
    );
    final appDir = Directory(
      '${docsDir.path}${Platform.pathSeparator}Junior Eventos',
    );

    // Migración automática: mover data.db de la carpeta vieja a la nueva si existe.
    final oldDb = File('${oldDir.path}${Platform.pathSeparator}$_dbName');
    final newDb = File('${appDir.path}${Platform.pathSeparator}$_dbName');
    if (await oldDb.exists() && !await newDb.exists()) {
      if (!await appDir.exists()) await appDir.create(recursive: true);
      await oldDb.rename(newDb.path);
      debugPrint('📦 DB migrada: JuniorEventos → Junior Eventos');
    }

    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return '${appDir.path}${Platform.pathSeparator}$_dbName';
  }

  static Future<Database> _initDb() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite local no está soportado en entorno Web.');
    }

    final path = await dbPath;
    debugPrint('📦 SQLite DB path: $path');

    // Escritorio: FFI. Android/iOS: plugin nativo `sqflite` (misma API que en PC).
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqflite_ffi.sqfliteFfiInit();
      databaseFactory = sqflite_ffi.databaseFactoryFfi;
      return sqflite_ffi.openDatabase(
        path,
        version: _version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }

    return sqflite_mobile.openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    debugPrint('🔧 Creando esquema SQLite v$version...');

    // ── Clientes ──────────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE clientes (
        id TEXT PRIMARY KEY,
        nombre_completo TEXT NOT NULL,
        telefono TEXT,
        email TEXT,
        is_archived INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── Eventos ───────────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE eventos (
        id TEXT PRIMARY KEY,
        cliente_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        fecha_evento TEXT NOT NULL,
        cantidad_cuotas INTEGER DEFAULT 1,
        modalidad TEXT NOT NULL DEFAULT 'particular',
        estado TEXT DEFAULT 'Planificacion',
        pin_operador TEXT,
        observaciones TEXT,
        titulo_festejado TEXT,
        nombre_festejado TEXT,
        encabezado_evento TEXT,
        bonificacion_global_pct REAL,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (cliente_id) REFERENCES clientes(id)
      )
    ''');

    // ── Servicios (Catálogo) ──────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE servicios (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        categoria TEXT DEFAULT 'General',
        costo_base REAL DEFAULT 0.0,
        margen_ganancia REAL DEFAULT 0.0,
        costo_interno REAL DEFAULT 0.0,
        evento_id TEXT,
        is_archived INTEGER DEFAULT 0,
        updated_at TEXT
      )
    ''');

    // ── Eventos ↔ Servicios ──────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE eventos_servicios (
        id TEXT NOT NULL,
        evento_id TEXT NOT NULL,
        servicio_id TEXT NOT NULL,
        precio_final_acordado REAL NOT NULL,
        cantidad REAL DEFAULT 1.0,
        grupo TEXT,
        combo_orden INTEGER DEFAULT 0,
        detalle_servicio TEXT,
        es_extra INTEGER DEFAULT 0,
        updated_at TEXT,
        PRIMARY KEY (id),
        FOREIGN KEY (evento_id) REFERENCES eventos(id),
        FOREIGN KEY (servicio_id) REFERENCES servicios(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_es_evento ON eventos_servicios(evento_id)',
    );

    // ── Transacciones (Ingresos) ─────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE transacciones (
        id TEXT PRIMARY KEY,
        evento_id TEXT NOT NULL,
        monto REAL NOT NULL,
        concepto TEXT,
        fecha_pago TEXT,
        created_by TEXT,
        medio_pago TEXT,
        anulado INTEGER DEFAULT 0,
        motivo_anulacion TEXT,
        fecha_anulacion TEXT,
        updated_at TEXT,
        FOREIGN KEY (evento_id) REFERENCES eventos(id)
      )
    ''');

    // ── Egresos ──────────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE egresos (
        id TEXT PRIMARY KEY,
        evento_id TEXT,
        monto REAL NOT NULL,
        proveedor TEXT,
        categoria TEXT,
        fecha TEXT,
        created_by TEXT,
        medio_pago TEXT,
        sesion_caja_id TEXT,
        updated_at TEXT,
        FOREIGN KEY (evento_id) REFERENCES eventos(id)
      )
    ''');

    // ── Contratos Alumnos ────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE contratos_alumnos (
        id TEXT PRIMARY KEY,
        evento_id TEXT NOT NULL,
        nombre_alumno TEXT NOT NULL,
        institucion TEXT,
        cantidad_acompanantes INTEGER DEFAULT 0,
        monto_total_pactado REAL NOT NULL,
        saldo_deudor REAL NOT NULL,
        cuotas_pagadas INTEGER DEFAULT 0,
        total_cuotas INTEGER DEFAULT 9,
        nombres_acompanantes TEXT,
        dia_vencimiento_mensual INTEGER DEFAULT 10,
        mesa_extra_precio REAL DEFAULT 0.0,
        mesa_extra_cuotas INTEGER DEFAULT 1,
        mesa_extra_cuotas_pagadas INTEGER DEFAULT 0,
        sillas_extra_cantidad INTEGER DEFAULT 0,
        sillas_extra_cuotas INTEGER DEFAULT 1,
        sillas_extra_precio_total REAL DEFAULT 0.0,
        sillas_extra_cuotas_pagadas INTEGER DEFAULT 0,
        mesa_extra_pagado REAL DEFAULT 0.0,
        mesa_extra_cantidad INTEGER DEFAULT 0,
        mesas_extra_estado TEXT,
        sillas_extra_pagado REAL DEFAULT 0.0,
        curso_division TEXT,
        musica_elegida TEXT,
        numero_mesa TEXT,
        telefono TEXT,
        porcentaje_descuento REAL DEFAULT 0.0,
        created_at TEXT,
        contrato_firmado INTEGER DEFAULT 0,
        mora_pendiente_tracked REAL DEFAULT 0.0,
        mora_cobrada_offset REAL DEFAULT 0.0,
        mora_fecha_referencia TEXT,
        mora_exenta_hasta TEXT,
        mora_exencion_reinicia INTEGER DEFAULT 1,
        baja_temporal_desde TEXT,
        updated_at TEXT,
        FOREIGN KEY (evento_id) REFERENCES eventos(id)
      )
    ''');

    // ── Pagos Contrato Alumno ────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE pagos_contrato_alumno (
        id TEXT PRIMARY KEY,
        contrato_alumno_id TEXT NOT NULL,
        monto REAL NOT NULL,
        monto_gross REAL,
        descuento_porcentaje REAL DEFAULT 0.0,
        concepto TEXT DEFAULT 'Cuota Base',
        fecha_pago TEXT,
        created_at TEXT,
        medio_pago TEXT,
        line_kind TEXT,
        anulado INTEGER DEFAULT 0,
        motivo_anulacion TEXT,
        fecha_anulacion TEXT,
        sesion_caja_id TEXT,
        updated_at TEXT,
        FOREIGN KEY (contrato_alumno_id) REFERENCES contratos_alumnos(id)
      )
    ''');

    // ── Operadores / sesiones de caja ────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS operadores_caja (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        pin TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sesiones_caja (
        id TEXT PRIMARY KEY,
        operador_id TEXT NOT NULL,
        abierta_at TEXT NOT NULL,
        cerrada_at TEXT,
        cambio_inicial REAL NOT NULL DEFAULT 0,
        nota_apertura TEXT,
        etiqueta TEXT,
        arqueo_cierre REAL,
        nota_cierre TEXT,
        device_id TEXT,
        last_heartbeat TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (operador_id) REFERENCES operadores_caja(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sesiones_caja_abierta ON sesiones_caja(cerrada_at, abierta_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sesiones_caja_operador ON sesiones_caja(operador_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sesiones_caja_operador_unica_abierta '
      'ON sesiones_caja(operador_id) WHERE cerrada_at IS NULL',
    );

    // ── Invitados ────────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE invitados (
        id TEXT PRIMARY KEY,
        evento_id TEXT NOT NULL,
        nombre_completo TEXT NOT NULL,
        dni TEXT,
        numero_mesa TEXT,
        estado_ingreso TEXT DEFAULT 'pendiente',
        intentos_fallidos INTEGER DEFAULT 0,
        updated_at TEXT,
        created_at TEXT,
        FOREIGN KEY (evento_id) REFERENCES eventos(id)
      )
    ''');

    // ── Accesos (Log de check-in) ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE accesos (
        id TEXT PRIMARY KEY,
        invitado_id TEXT NOT NULL,
        evento_id TEXT NOT NULL,
        dni_ingresado TEXT,
        valido INTEGER DEFAULT 0,
        marcado_por TEXT,
        timestamp TEXT,
        FOREIGN KEY (invitado_id) REFERENCES invitados(id),
        FOREIGN KEY (evento_id) REFERENCES eventos(id)
      )
    ''');

    // ── Solicitudes Cotización ────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE solicitudes_cotizacion (
        id TEXT PRIMARY KEY,
        cliente_nombre TEXT NOT NULL,
        cliente_celular TEXT NOT NULL,
        servicios_seleccionados TEXT,
        estado TEXT DEFAULT 'pendiente',
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── Rentabilidad ──────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS calculos_rentabilidad (
        id TEXT PRIMARY KEY,
        evento_id TEXT,
        presupuesto_id TEXT,
        precio_venta REAL NOT NULL,
        honorario_adrian_monto REAL DEFAULT 0,
        honorario_adrian_pct REAL DEFAULT 0,
        honorario_modo TEXT DEFAULT 'monto',
        costos_variables_json TEXT,
        costos_fijos_json TEXT,
        resultado REAL,
        notas TEXT,
        created_at TEXT,
        created_by TEXT,
        updated_at TEXT
      )
    ''');

    // ── Sync Queue (Cola de sincronización) ──────────────────────────────────
    await db.execute('''
      CREATE TABLE _sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tabla TEXT NOT NULL,
        operacion TEXT NOT NULL,
        registro_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        intentos INTEGER DEFAULT 0,
        ultimo_error TEXT
      )
    ''');

    // ── Presupuestos (Flujo Independiente) ──────────────────────────────────
    await db.execute('''
      CREATE TABLE presupuestos (
        id TEXT PRIMARY KEY,
        cliente_id TEXT NOT NULL,
        tipo_evento TEXT NOT NULL,
        lugar TEXT,
        detalle_anclaje TEXT,
        fecha_vencimiento TEXT NOT NULL,
        fecha_evento TEXT,
        estado TEXT DEFAULT 'activo',
        instagram TEXT,
        telefono TEXT,
        vendedor_nombre TEXT,
        titulo_festejado TEXT,
        nombre_festejado TEXT,
        encabezado_evento TEXT,
        notificado_vencimiento INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (cliente_id) REFERENCES clientes(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE presupuesto_servicios (
        id TEXT NOT NULL,
        presupuesto_id TEXT NOT NULL,
        servicio_id TEXT NOT NULL,
        precio_final REAL NOT NULL,
        cantidad REAL DEFAULT 1.0,
        grupo TEXT,
        combo_orden INTEGER DEFAULT 0,
        detalle_servicio TEXT,
        es_extra INTEGER DEFAULT 0,
        updated_at TEXT,
        PRIMARY KEY (id),
        FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
        FOREIGN KEY (servicio_id) REFERENCES servicios(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_ps_presupuesto ON presupuesto_servicios(presupuesto_id)',
    );

    // ── Préstamo / alquiler de ítems ─────────────────────────────────────────
    await db.execute('''
      CREATE TABLE prestamos_alquiler (
        id TEXT PRIMARY KEY,
        cliente_id TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        aplica_iva INTEGER NOT NULL DEFAULT 0,
        alicuota_iva REAL NOT NULL DEFAULT 21,
        subtotal_neto REAL NOT NULL DEFAULT 0,
        monto_iva REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        texto_redaccion TEXT,
        texto_disclaimer TEXT,
        visible_listado INTEGER NOT NULL DEFAULT 1,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (cliente_id) REFERENCES clientes(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE prestamo_alquiler_lineas (
        id TEXT PRIMARY KEY,
        prestamo_id TEXT NOT NULL,
        descripcion TEXT NOT NULL,
        cantidad REAL NOT NULL,
        precio_unitario REAL NOT NULL,
        linea_total REAL NOT NULL,
        orden INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        FOREIGN KEY (prestamo_id) REFERENCES prestamos_alquiler(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE pagos_prestamo_alquiler (
        id TEXT PRIMARY KEY,
        prestamo_id TEXT NOT NULL,
        monto REAL NOT NULL,
        concepto TEXT,
        fecha_pago TEXT,
        created_at TEXT,
        medio_pago TEXT,
        anulado INTEGER DEFAULT 0,
        motivo_anulacion TEXT,
        fecha_anulacion TEXT,
        updated_at TEXT,
        FOREIGN KEY (prestamo_id) REFERENCES prestamos_alquiler(id) ON DELETE CASCADE
      )
    ''');

    // ── Metadatos de sync ────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE _sync_meta (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');

    // ── Obligaciones de Pago (Avisos) ─────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS obligaciones_pago (
        id TEXT PRIMARY KEY,
        titulo TEXT NOT NULL,
        tipo_obligacion TEXT NOT NULL,
        fecha_vencimiento TEXT NOT NULL,
        monto_estimado REAL DEFAULT 0,
        estado TEXT DEFAULT 'pendiente',
        fecha_pago TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── Caja fuerte (cupos declarados por el dueño; local-only, sin sync) ────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS caja_fuerte_movimientos (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        monto REAL NOT NULL,
        nota TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    // ── Notas operativas por contrato (sync Supabase; no contable) ───────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notas_operativas_contrato (
        id TEXT PRIMARY KEY,
        contrato_alumno_id TEXT NOT NULL UNIQUE,
        texto TEXT NOT NULL DEFAULT '',
        resuelto INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (contrato_alumno_id) REFERENCES contratos_alumnos(id)
      )
    ''');

    // ── Cierre de caja operativo (guía cambio + anotaciones PDF; sync manual) ─
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cierre_caja_guia_movimientos (
        id TEXT PRIMARY KEY,
        fecha TEXT NOT NULL,
        tipo TEXT NOT NULL,
        monto REAL NOT NULL,
        saldo_antes REAL,
        saldo_despues REAL NOT NULL,
        nota TEXT,
        sesion_caja_id TEXT,
        fecha_mov TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cierre_caja_anotaciones (
        id TEXT PRIMARY KEY,
        fecha TEXT NOT NULL,
        turno TEXT NOT NULL,
        sesion_caja_id TEXT,
        texto TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(sesion_caja_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_egresos_sesion_caja '
      'ON egresos(sesion_caja_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_guia_cambio_sesion '
      'ON cierre_caja_guia_movimientos(sesion_caja_id, fecha_mov)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cierre_anotacion_sesion '
      'ON cierre_caja_anotaciones(sesion_caja_id)',
    );

    // ── Configuración de Rentabilidad Fija ───────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rentabilidad_config (
        id TEXT PRIMARY KEY,
        alquiler_local REAL DEFAULT 0,
        sueldos_admin REAL DEFAULT 0,
        servicios_oficina REAL DEFAULT 0,
        impuestos_fijos REAL DEFAULT 0,
        honorario_adrian_default_monto REAL DEFAULT 0,
        honorario_adrian_default_pct REAL DEFAULT 0,
        honorario_modo_default TEXT DEFAULT 'monto',
        eventos_estimados_mes INTEGER DEFAULT 1,
        updated_at TEXT,
        updated_by TEXT
      )
    ''');

    // Índices para performance
    await db.execute('CREATE INDEX idx_eventos_cliente ON eventos(cliente_id)');
    await db.execute('CREATE INDEX idx_eventos_estado ON eventos(estado)');
    await db.execute(
      'CREATE INDEX idx_transacciones_evento ON transacciones(evento_id)',
    );
    await db.execute('CREATE INDEX idx_egresos_evento ON egresos(evento_id)');
    await db.execute(
      'CREATE INDEX idx_contratos_evento ON contratos_alumnos(evento_id)',
    );
    await db.execute(
      'CREATE INDEX idx_pagos_contrato ON pagos_contrato_alumno(contrato_alumno_id)',
    );
    await db.execute(
      'CREATE INDEX idx_invitados_evento ON invitados(evento_id)',
    );
    await db.execute('CREATE INDEX idx_sync_queue_tabla ON _sync_queue(tabla)');
    await db.execute(
      'CREATE INDEX idx_prestamos_cliente ON prestamos_alquiler(cliente_id)',
    );
    await db.execute(
      'CREATE INDEX idx_prestamos_visible ON prestamos_alquiler(visible_listado)',
    );
    await db.execute(
      'CREATE INDEX idx_lineas_prestamo ON prestamo_alquiler_lineas(prestamo_id)',
    );
    await db.execute(
      'CREATE INDEX idx_pagos_prestamo ON pagos_prestamo_alquiler(prestamo_id)',
    );

    await db.execute(
      'CREATE INDEX idx_caja_fuerte_created ON caja_fuerte_movimientos(created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_guia_cambio_fecha ON cierre_caja_guia_movimientos(fecha, fecha_mov)',
    );
    await db.execute(
      'CREATE INDEX idx_cierre_anotacion_fecha ON cierre_caja_anotaciones(fecha, turno)',
    );
    await db.execute(
      'CREATE INDEX idx_notas_operativas_contrato ON notas_operativas_contrato(contrato_alumno_id)',
    );

    debugPrint('✅ Esquema SQLite creado exitosamente');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    debugPrint('🔄 Migrando SQLite de v$oldVersion a v$newVersion...');
    if (oldVersion < 2) {
      debugPrint('  🔧 Aplicando migración v2...');

      // 1. Agregar created_at a invitados
      try {
        await db.execute('ALTER TABLE invitados ADD COLUMN created_at TEXT');
      } catch (e) {
        debugPrint('  ⚠️ Nota: created_at ya existía o error al añadir: $e');
      }

      // 2. Modificar egresos para permitir evento_id NULL
      // En SQLite, cambiar NOT NULL requiere recrear la tabla.
      try {
        await db.transaction((txn) async {
          // Crear tabla temporal
          await txn.execute('''
            CREATE TABLE egresos_new (
              id TEXT PRIMARY KEY,
              evento_id TEXT,
              monto REAL NOT NULL,
              proveedor TEXT,
              categoria TEXT,
              fecha TEXT,
              created_by TEXT,
              FOREIGN KEY (evento_id) REFERENCES eventos(id)
            )
          ''');

          // Copiar datos
          await txn.execute('INSERT INTO egresos_new SELECT * FROM egresos');

          // Eliminar vieja y renombrar
          await txn.execute('DROP TABLE egresos');
          await txn.execute('ALTER TABLE egresos_new RENAME TO egresos');

          // Re-crear índice
          await txn.execute(
            'CREATE INDEX idx_egresos_evento ON egresos(evento_id)',
          );
        });
      } catch (e) {
        debugPrint('  ❌ Error migrando tabla egresos: $e');
      }

      debugPrint('✅ Migración v2 completada');
    }

    if (oldVersion < 3) {
      debugPrint('  🔧 Aplicando migración v3...');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_precio REAL DEFAULT 0.0',
        );
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_cuotas INTEGER DEFAULT 1',
        );
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_cantidad INTEGER DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_precio_total REAL DEFAULT 0.0',
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columnas de extras a contratos_alumnos: $e',
        );
      }
      debugPrint('✅ Migración v3 completada');
    }

    if (oldVersion < 4) {
      debugPrint('  🔧 Aplicando migración v4...');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN curso_division TEXT',
        );
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN musica_elegida TEXT',
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columnas curso_division y musica_elegida a contratos_alumnos: $e',
        );
      }
      debugPrint('✅ Migración v4 completada');
    }

    if (oldVersion < 5) {
      debugPrint('  🔧 Aplicando migración v5...');
      try {
        await db.execute(
          "ALTER TABLE pagos_contrato_alumno ADD COLUMN concepto TEXT DEFAULT 'Cuota Base'",
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columna concepto a pagos_contrato_alumno: $e',
        );
      }
      debugPrint('✅ Migración v5 completada');
    }

    if (oldVersion < 6) {
      debugPrint('  🔧 Aplicando migración v6...');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN numero_mesa TEXT',
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columna numero_mesa a contratos_alumnos: $e',
        );
      }
      debugPrint('✅ Migración v6 completada');
    }

    if (oldVersion < 7) {
      debugPrint('  🔧 Aplicando migración v7...');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_cuotas_pagadas INTEGER DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_cuotas_pagadas INTEGER DEFAULT 0',
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columnas de cuotas extras pagadas a contratos_alumnos: $e',
        );
      }
      debugPrint('✅ Migración v7 completada');
    }

    if (oldVersion < 8) {
      debugPrint('  🔧 Aplicando migración v8...');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN telefono TEXT',
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columna telefono a contratos_alumnos: $e',
        );
      }
      debugPrint('✅ Migración v8 completada');
    }

    if (oldVersion < 9) {
      debugPrint('  🔧 Aplicando migración v9...');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_pagado REAL DEFAULT 0.0',
        );
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_pagado REAL DEFAULT 0.0',
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columnas mesa_extra_pagado y sillas_extra_pagado a contratos_alumnos: $e',
        );
      }
      debugPrint('✅ Migración v9 completada');
    }

    if (oldVersion < 10) {
      debugPrint('  🔧 Aplicando migración v10...');
      try {
        await db.execute('ALTER TABLE eventos ADD COLUMN observaciones TEXT');
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columna observaciones a eventos: $e',
        );
      }
      debugPrint('✅ Migración v10 completada');
    }

    if (oldVersion < 11) {
      debugPrint('  🔧 Aplicando migración v11...');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_cuotas INTEGER DEFAULT 1',
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columna sillas_extra_cuotas a contratos_alumnos: $e',
        );
      }
      debugPrint('✅ Migración v11 completada');
    }

    if (oldVersion < 12) {
      debugPrint('  🔧 Aplicando migración v12...');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN porcentaje_descuento REAL DEFAULT 0.0',
        );
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir columna porcentaje_descuento a contratos_alumnos: $e',
        );
      }
      debugPrint('✅ Migración v12 completada');
    }

    if (oldVersion < 13) {
      debugPrint('  🔧 Aplicando migración v13 (Persistencia de descuentos)');
      try {
        await db.execute(
          'ALTER TABLE pagos_contrato_alumno ADD COLUMN monto_gross REAL',
        );
        await db.execute(
          'ALTER TABLE pagos_contrato_alumno ADD COLUMN descuento_porcentaje REAL DEFAULT 0.0',
        );

        // Actualizar datos existentes para que monto_gross = monto inicial
        await db.execute(
          'UPDATE pagos_contrato_alumno SET monto_gross = monto WHERE monto_gross IS NULL',
        );

        debugPrint('✅ Migración v13 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v13: $e');
      }
    }

    if (oldVersion < 14) {
      debugPrint('  🔧 Aplicando migración v14 (Módulo de Presupuestos)');
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS presupuestos (
            id TEXT PRIMARY KEY,
            cliente_id TEXT NOT NULL,
            tipo_evento TEXT NOT NULL,
            lugar TEXT,
            detalle_anclaje TEXT,
            fecha_vencimiento TEXT NOT NULL,
            estado TEXT DEFAULT 'activo',
            instagram TEXT,
            telefono TEXT,
            notificado_vencimiento INTEGER DEFAULT 0,
            created_at TEXT,
            FOREIGN KEY (cliente_id) REFERENCES clientes(id)
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS presupuesto_servicios (
            presupuesto_id TEXT NOT NULL,
            servicio_id TEXT NOT NULL,
            precio_final REAL NOT NULL,
            detalle_servicio TEXT,
            PRIMARY KEY (presupuesto_id, servicio_id),
            FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
            FOREIGN KEY (servicio_id) REFERENCES servicios(id)
          )
        ''');

        debugPrint('✅ Migración v14 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v14: $e');
      }
    }
    if (oldVersion < 15) {
      debugPrint('  🔧 Aplicando migración v15 (Categorización de Servicios)');
      try {
        await db.execute(
          "ALTER TABLE servicios ADD COLUMN categoria TEXT DEFAULT 'General'",
        );
        await db.execute(
          "ALTER TABLE servicios ADD COLUMN costo_interno REAL DEFAULT 0.0",
        );
        debugPrint('✅ Migración v15 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v15: $e');
      }
    }
    if (oldVersion < 16) {
      debugPrint(
        '  🔧 Aplicando migración v16 (Servicios Personalizados y Cantidades)',
      );
      try {
        await db.execute('ALTER TABLE servicios ADD COLUMN evento_id TEXT');
        await db.execute(
          'ALTER TABLE eventos_servicios ADD COLUMN cantidad REAL DEFAULT 1.0',
        );
        await db.execute(
          'ALTER TABLE presupuesto_servicios ADD COLUMN cantidad REAL DEFAULT 1.0',
        );
        debugPrint('✅ Migración v16 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v16: $e');
      }
    }
    if (oldVersion < 17) {
      debugPrint('  🔧 Aplicando migración v17 (Identidad del Emisor)');
      try {
        await db.execute(
          'ALTER TABLE presupuestos ADD COLUMN vendedor_nombre TEXT',
        );
        debugPrint('✅ Migración v17 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v17: $e');
      }
    }
    if (oldVersion < 18) {
      debugPrint('  🔧 Aplicando migración v18 (Oratoria del Evento)');
      try {
        await db.execute(
          'ALTER TABLE presupuestos ADD COLUMN titulo_festejado TEXT',
        );
        debugPrint('✅ Migración v18 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v18: $e');
      }
    }
    if (oldVersion < 19) {
      debugPrint('  🔧 Aplicando migración v19 (Archivado de Clientes)');
      try {
        await db.execute(
          'ALTER TABLE clientes ADD COLUMN is_archived INTEGER DEFAULT 0',
        );
        debugPrint('✅ Migración v19 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v19: $e');
      }
    }
    if (oldVersion < 20) {
      debugPrint('  🔧 Aplicando migración v20 (Agrupación de Servicios)');
      try {
        await db.execute(
          'ALTER TABLE presupuesto_servicios ADD COLUMN grupo TEXT',
        );
        await db.execute('ALTER TABLE eventos_servicios ADD COLUMN grupo TEXT');
        debugPrint('✅ Migración v20 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v20: $e');
      }
    }

    if (oldVersion < 22) {
      debugPrint(
        '  🔧 Aplicando migración v22 (Descripción Técnica en Eventos)',
      );
      try {
        await db.execute(
          'ALTER TABLE eventos_servicios ADD COLUMN detalle_servicio TEXT',
        );
        debugPrint('✅ Migración v22 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v22: $e');
      }
    }

    if (oldVersion < 23) {
      debugPrint('  🔧 Aplicando migración v23 (Archivado de Servicios)');
      try {
        await db.execute(
          'ALTER TABLE servicios ADD COLUMN is_archived INTEGER DEFAULT 0',
        );
        debugPrint('✅ Migración v23 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: is_archived ya existía o error al añadir: $e');
      }
    }

    if (oldVersion < 24) {
      debugPrint(
        '  🔧 Aplicando migración v24 (grupo en presupuesto_servicios — BDs nuevas sin v20)',
      );
      try {
        await db.execute(
          'ALTER TABLE presupuesto_servicios ADD COLUMN grupo TEXT',
        );
        debugPrint('✅ Migración v24 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: grupo ya existía o error al añadir: $e');
      }
    }

    if (oldVersion < 25) {
      debugPrint(
        '  🔧 Aplicando migración v25 (Bonificación global % sobre presupuesto del evento)',
      );
      try {
        await db.execute(
          'ALTER TABLE eventos ADD COLUMN bonificacion_global_pct REAL',
        );
        debugPrint('✅ Migración v25 completada');
      } catch (e) {
        debugPrint(
          '  ⚠️ Nota: error al añadir bonificacion_global_pct a eventos: $e',
        );
      }
    }

    if (oldVersion < 26) {
      debugPrint(
        '  🔧 Aplicando migración v26 (Orden de combo en presupuesto/evento)',
      );
      try {
        await db.execute(
          'ALTER TABLE eventos_servicios ADD COLUMN combo_orden INTEGER DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE presupuesto_servicios ADD COLUMN combo_orden INTEGER DEFAULT 0',
        );
        debugPrint('✅ Migración v26 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir combo_orden: $e');
      }
    }

    if (oldVersion < 27) {
      debugPrint('  🔧 Aplicando migración v27 (Préstamo / alquiler de ítems)');
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS prestamos_alquiler (
            id TEXT PRIMARY KEY,
            cliente_id TEXT NOT NULL,
            fecha_inicio TEXT NOT NULL,
            fecha_fin TEXT NOT NULL,
            aplica_iva INTEGER NOT NULL DEFAULT 0,
            alicuota_iva REAL NOT NULL DEFAULT 21,
            subtotal_neto REAL NOT NULL DEFAULT 0,
            monto_iva REAL NOT NULL DEFAULT 0,
            total REAL NOT NULL DEFAULT 0,
            texto_redaccion TEXT,
            texto_disclaimer TEXT,
            visible_listado INTEGER NOT NULL DEFAULT 1,
            created_at TEXT,
            updated_at TEXT,
            FOREIGN KEY (cliente_id) REFERENCES clientes(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS prestamo_alquiler_lineas (
            id TEXT PRIMARY KEY,
            prestamo_id TEXT NOT NULL,
            descripcion TEXT NOT NULL,
            cantidad REAL NOT NULL,
            precio_unitario REAL NOT NULL,
            linea_total REAL NOT NULL,
            orden INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (prestamo_id) REFERENCES prestamos_alquiler(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS pagos_prestamo_alquiler (
            id TEXT PRIMARY KEY,
            prestamo_id TEXT NOT NULL,
            monto REAL NOT NULL,
            concepto TEXT,
            fecha_pago TEXT,
            created_at TEXT,
            FOREIGN KEY (prestamo_id) REFERENCES prestamos_alquiler(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_prestamos_cliente ON prestamos_alquiler(cliente_id)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_prestamos_visible ON prestamos_alquiler(visible_listado)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_lineas_prestamo ON prestamo_alquiler_lineas(prestamo_id)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pagos_prestamo ON pagos_prestamo_alquiler(prestamo_id)',
        );
        debugPrint('✅ Migración v27 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v27: $e');
      }
    }

    if (oldVersion < 28) {
      debugPrint(
        '  🔧 Aplicando migración v28 (pagos_contrato_alumno: gross/descuento en BDs nuevas sin v13)',
      );
      try {
        try {
          await db.execute(
            'ALTER TABLE pagos_contrato_alumno ADD COLUMN monto_gross REAL',
          );
        } catch (e) {
          debugPrint('  ⚠️ Nota: monto_gross ya existía o error al añadir: $e');
        }
        try {
          await db.execute(
            'ALTER TABLE pagos_contrato_alumno ADD COLUMN descuento_porcentaje REAL DEFAULT 0.0',
          );
        } catch (e) {
          debugPrint(
            '  ⚠️ Nota: descuento_porcentaje ya existía o error al añadir: $e',
          );
        }
        await db.execute(
          'UPDATE pagos_contrato_alumno SET monto_gross = monto WHERE monto_gross IS NULL',
        );
        debugPrint('✅ Migración v28 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v28: $e');
      }
    }

    if (oldVersion < 29) {
      debugPrint(
        '  🔧 Aplicando migración v29 (Clasificación de Medios de Pago)',
      );
      try {
        try {
          await db.execute(
            'ALTER TABLE transacciones ADD COLUMN medio_pago TEXT',
          );
        } catch (e) {
          debugPrint(
            '  ⚠️ Nota: error al añadir medio_pago a transacciones: $e',
          );
        }

        try {
          await db.execute(
            'ALTER TABLE pagos_contrato_alumno ADD COLUMN medio_pago TEXT',
          );
        } catch (e) {
          debugPrint(
            '  ⚠️ Nota: error al añadir medio_pago a pagos_contrato_alumno: $e',
          );
        }

        try {
          await db.execute(
            'ALTER TABLE pagos_prestamo_alquiler ADD COLUMN medio_pago TEXT',
          );
        } catch (e) {
          debugPrint(
            '  ⚠️ Nota: error al añadir medio_pago a pagos_prestamo_alquiler: $e',
          );
        }

        try {
          await db.execute('ALTER TABLE egresos ADD COLUMN medio_pago TEXT');
        } catch (e) {
          debugPrint('  ⚠️ Nota: error al añadir medio_pago a egresos: $e');
        }

        debugPrint('✅ Migración v29 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v29: $e');
      }
    }

    if (oldVersion < 31) {
      debugPrint(
        '  🔧 Aplicando migración v30/v31 (fecha_evento en presupuestos)',
      );
      try {
        try {
          await db.execute(
            'ALTER TABLE presupuestos ADD COLUMN fecha_evento TEXT',
          );
        } catch (e) {
          debugPrint(
            '  ⚠️ Nota: error al añadir fecha_evento a presupuestos: $e',
          );
        }
        debugPrint('✅ Migración v31 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v31: $e');
      }
    }
    if (oldVersion < 32) {
      debugPrint('  🔧 Aplicando migración v32 (calculos_rentabilidad)');
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS calculos_rentabilidad (
            id TEXT PRIMARY KEY,
            evento_id TEXT,
            presupuesto_id TEXT,
            precio_venta REAL NOT NULL,
            honorario_adrian_monto REAL DEFAULT 0,
            honorario_adrian_pct REAL DEFAULT 0,
            honorario_modo TEXT DEFAULT 'monto',
            costos_variables_json TEXT,
            costos_fijos_json TEXT,
            resultado REAL,
            notas TEXT,
            created_at TEXT,
            created_by TEXT
          )
        ''');
        debugPrint('✅ Migración v32 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v32: $e');
      }
    }

    if (oldVersion < 33) {
      debugPrint('  🔧 Aplicando migración v33 (rentabilidad_config)');
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS rentabilidad_config (
            id TEXT PRIMARY KEY,
            alquiler_local REAL DEFAULT 0,
            sueldos_admin REAL DEFAULT 0,
            servicios_oficina REAL DEFAULT 0,
            impuestos_fijos REAL DEFAULT 0,
            honorario_adrian_default_monto REAL DEFAULT 0,
            honorario_adrian_default_pct REAL DEFAULT 0,
            honorario_modo_default TEXT DEFAULT 'monto',
            eventos_estimados_mes INTEGER DEFAULT 1,
            updated_at TEXT,
            updated_by TEXT
          )
        ''');
        debugPrint('✅ Migración v33 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v33: $e');
      }
    }

    if (oldVersion < 34) {
      debugPrint(
        '  🔧 Aplicando migración v34 (Sistema de Avisos y Reminders)',
      );
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS obligaciones_pago (
            id TEXT PRIMARY KEY,
            titulo TEXT NOT NULL,
            tipo_obligacion TEXT NOT NULL,
            fecha_vencimiento TEXT NOT NULL,
            monto_estimado REAL DEFAULT 0,
            estado TEXT DEFAULT 'pendiente',
            fecha_pago TEXT,
            created_at TEXT
          )
        ''');
        debugPrint('✅ Migración v34 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v34: $e');
      }
    }

    if (oldVersion < 35) {
      debugPrint(
        '  🔧 Aplicando migración v35 (líneas de presupuesto: id propio, mismo servicio varias veces)...',
      );
      try {
        await db.transaction((txn) async {
          final esRows = await txn.query('eventos_servicios');
          final psRows = await txn.query('presupuesto_servicios');

          await txn.execute('DROP TABLE IF EXISTS eventos_servicios');
          await txn.execute('''
            CREATE TABLE eventos_servicios (
              id TEXT NOT NULL,
              evento_id TEXT NOT NULL,
              servicio_id TEXT NOT NULL,
              precio_final_acordado REAL NOT NULL,
              cantidad REAL DEFAULT 1.0,
              grupo TEXT,
              combo_orden INTEGER DEFAULT 0,
              detalle_servicio TEXT,
              PRIMARY KEY (id),
              FOREIGN KEY (evento_id) REFERENCES eventos(id),
              FOREIGN KEY (servicio_id) REFERENCES servicios(id)
            )
          ''');
          for (final r in esRows) {
            await txn.insert('eventos_servicios', {
              'id': UuidUtils.generate(),
              'evento_id': r['evento_id'],
              'servicio_id': r['servicio_id'],
              'precio_final_acordado': r['precio_final_acordado'],
              'cantidad': r['cantidad'] ?? 1.0,
              'grupo': r['grupo'],
              'combo_orden': r['combo_orden'] ?? 0,
              'detalle_servicio': r['detalle_servicio'],
            });
          }
          await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_es_evento ON eventos_servicios(evento_id)',
          );

          await txn.execute('DROP TABLE IF EXISTS presupuesto_servicios');
          await txn.execute('''
            CREATE TABLE presupuesto_servicios (
              id TEXT NOT NULL,
              presupuesto_id TEXT NOT NULL,
              servicio_id TEXT NOT NULL,
              precio_final REAL NOT NULL,
              cantidad REAL DEFAULT 1.0,
              grupo TEXT,
              combo_orden INTEGER DEFAULT 0,
              detalle_servicio TEXT,
              PRIMARY KEY (id),
              FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
              FOREIGN KEY (servicio_id) REFERENCES servicios(id)
            )
          ''');
          for (final r in psRows) {
            await txn.insert('presupuesto_servicios', {
              'id': UuidUtils.generate(),
              'presupuesto_id': r['presupuesto_id'],
              'servicio_id': r['servicio_id'],
              'precio_final': r['precio_final'],
              'cantidad': r['cantidad'] ?? 1.0,
              'grupo': r['grupo'],
              'combo_orden': r['combo_orden'] ?? 0,
              'detalle_servicio': r['detalle_servicio'],
            });
          }
          await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_ps_presupuesto ON presupuesto_servicios(presupuesto_id)',
          );
        });
        debugPrint('✅ Migración v35 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v35: $e');
      }
    }

    if (oldVersion < 36) {
      debugPrint(
        '  🔧 Aplicando migración v36 (contrato_firmado en contratos_alumnos)',
      );
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN contrato_firmado INTEGER DEFAULT 0',
        );
        debugPrint('✅ Migración v36 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columna contrato_firmado: $e');
      }
    }

    if (oldVersion < 37) {
      debugPrint(
        '  🔧 Aplicando migración v37 (anulación no destructiva de cobros)',
      );
      try {
        for (final t in [
          'transacciones',
          'pagos_contrato_alumno',
          'pagos_prestamo_alquiler',
        ]) {
          try {
            await db.execute(
              'ALTER TABLE $t ADD COLUMN anulado INTEGER DEFAULT 0',
            );
          } catch (e) {
            debugPrint('  ⚠️ Nota: anulado en $t: $e');
          }
          try {
            await db.execute('ALTER TABLE $t ADD COLUMN motivo_anulacion TEXT');
          } catch (e) {
            debugPrint('  ⚠️ Nota: motivo_anulacion en $t: $e');
          }
          try {
            await db.execute('ALTER TABLE $t ADD COLUMN fecha_anulacion TEXT');
          } catch (e) {
            debugPrint('  ⚠️ Nota: fecha_anulacion en $t: $e');
          }
        }
        debugPrint('✅ Migración v37 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v37: $e');
      }
    }

    if (oldVersion < 38) {
      debugPrint(
        '  🔧 Aplicando migración v38 (line_kind en pagos_contrato_alumno)',
      );
      try {
        try {
          await db.execute(
            'ALTER TABLE pagos_contrato_alumno ADD COLUMN line_kind TEXT',
          );
        } catch (e) {
          debugPrint('  ⚠️ Nota: line_kind en pagos_contrato_alumno: $e');
        }
        final rows = await db.query(
          'pagos_contrato_alumno',
          columns: ['id', 'concepto'],
        );
        for (final r in rows) {
          final concepto = r['concepto'] as String?;
          if (!esPagoInteresMoraPorConcepto(concepto)) continue;
          await db.update(
            'pagos_contrato_alumno',
            {'line_kind': kLineKindInteresMora},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
        debugPrint('✅ Migración v38 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v38: $e');
      }
    }

    if (oldVersion < 39) {
      debugPrint(
        '  🔧 Aplicando migración v39 (mora_pendiente_tracked en contratos_alumnos)',
      );
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN mora_pendiente_tracked REAL DEFAULT 0.0',
        );
        debugPrint('✅ Migración v39 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: mora_pendiente_tracked: $e');
      }
    }

    if (oldVersion < 40) {
      debugPrint('  🔧 Aplicando migración v40 (caja_fuerte_movimientos)');
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS caja_fuerte_movimientos (
            id TEXT PRIMARY KEY,
            tipo TEXT NOT NULL,
            monto REAL NOT NULL,
            nota TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_caja_fuerte_created ON caja_fuerte_movimientos(created_at)',
        );
        debugPrint('✅ Migración v40 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota migración v40 caja_fuerte: $e');
      }
    }

    if (oldVersion < 41) {
      debugPrint('  🔧 Aplicando migración v41 (notas_operativas_contrato)');
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS notas_operativas_contrato (
            contrato_alumno_id TEXT PRIMARY KEY,
            texto TEXT NOT NULL DEFAULT '',
            resuelto INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (contrato_alumno_id) REFERENCES contratos_alumnos(id)
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notas_operativas_contrato ON notas_operativas_contrato(contrato_alumno_id)',
        );
        debugPrint('✅ Migración v41 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota migración v41 notas_operativas: $e');
      }
    }

    if (oldVersion < 42) {
      debugPrint(
        '  🔧 Aplicando migración v42 (notas_operativas_contrato: id PK + sync)',
      );
      try {
        final info = await db.rawQuery(
          'PRAGMA table_info(notas_operativas_contrato)',
        );
        if (info.isEmpty) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS notas_operativas_contrato (
              id TEXT PRIMARY KEY,
              contrato_alumno_id TEXT NOT NULL UNIQUE,
              texto TEXT NOT NULL DEFAULT '',
              resuelto INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY (contrato_alumno_id) REFERENCES contratos_alumnos(id)
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_notas_operativas_contrato ON notas_operativas_contrato(contrato_alumno_id)',
          );
        } else {
          final hasIdCol = info.any((c) => c['name'] == 'id');
          if (!hasIdCol) {
            final oldRows = await db.query('notas_operativas_contrato');
            await db.execute('DROP TABLE notas_operativas_contrato');
            await db.execute('''
              CREATE TABLE notas_operativas_contrato (
                id TEXT PRIMARY KEY,
                contrato_alumno_id TEXT NOT NULL UNIQUE,
                texto TEXT NOT NULL DEFAULT '',
                resuelto INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY (contrato_alumno_id) REFERENCES contratos_alumnos(id)
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_notas_operativas_contrato ON notas_operativas_contrato(contrato_alumno_id)',
            );
            final nowIso = DateTime.now().toUtc().toIso8601String();
            for (final r in oldRows) {
              await db.insert('notas_operativas_contrato', {
                'id': UuidUtils.notaOperativaContratoId(
                  r['contrato_alumno_id'] as String,
                ),
                'contrato_alumno_id': r['contrato_alumno_id'],
                'texto': r['texto'] ?? '',
                'resuelto': r['resuelto'] ?? 0,
                'created_at': (r['created_at'] as String?)?.isNotEmpty == true
                    ? r['created_at']
                    : nowIso,
                'updated_at': (r['updated_at'] as String?)?.isNotEmpty == true
                    ? r['updated_at']
                    : nowIso,
              });
            }
            debugPrint(
              '  ✅ Notas operativas: migradas ${oldRows.length} fila(s) a esquema con id',
            );
          }
        }
      } catch (e) {
        debugPrint('  ⚠️ Nota migración v42 notas_operativas: $e');
      }
    }

    if (oldVersion < 43) {
      debugPrint(
        '  🔧 v43: retiros dueño históricos → gasto personal [empresa]',
      );
      try {
        final rows = await db.query(
          'egresos',
          where: "trim(categoria) = ?",
          whereArgs: ['Retiro dueño'],
        );
        for (final r in rows) {
          final id = r['id']?.toString();
          if (id == null || id.isEmpty) continue;
          final prov = (r['proveedor'] ?? 'Retiro bolsillo personal')
              .toString()
              .trim();
          final newProv = prov.startsWith('[empresa]')
              ? prov
              : '[empresa] $prov';
          await db.update(
            'egresos',
            {'categoria': 'Gasto personal', 'proveedor': newProv},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        debugPrint('✅ Migración v43: ${rows.length} retiro(s) reclasificados');
      } catch (e) {
        debugPrint('  ❌ Error migración v43: $e');
      }
    }

    if (oldVersion < 44) {
      debugPrint(
        '  🔧 v44: mora_cobrada_offset (aislamiento de mora por período de cuota)',
      );
      try {
        try {
          await db.execute(
            'ALTER TABLE contratos_alumnos ADD COLUMN mora_cobrada_offset REAL DEFAULT 0.0',
          );
        } catch (e) {
          debugPrint('  ⚠️ mora_cobrada_offset ya existe: $e');
        }
        await db.rawUpdate('''
          UPDATE contratos_alumnos
          SET mora_cobrada_offset = (
            SELECT COALESCE(SUM(p.monto), 0.0)
            FROM pagos_contrato_alumno p
            WHERE p.contrato_alumno_id = contratos_alumnos.id
              AND (p.line_kind = 'interes_mora'
                   OR LOWER(IFNULL(p.concepto,'')) LIKE '%mora%'
                   OR LOWER(IFNULL(p.concepto,'')) LIKE '%inter%')
              AND (p.anulado IS NULL OR p.anulado = 0)
          )
          WHERE cuotas_pagadas > 0
            AND saldo_deudor > 0.01
        ''');
        debugPrint('✅ Migración v44 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v44: $e');
      }
    }

    if (oldVersion < 45) {
      debugPrint('  🔧 v45: updated_at universal + reset sync incremental');
      try {
        // Agregar updated_at a todas las tablas que no lo tienen
        final tablasUpdatedAt = [
          'clientes',
          'eventos',
          'servicios',
          'eventos_servicios',
          'presupuestos',
          'presupuesto_servicios',
          'transacciones',
          'egresos',
          'contratos_alumnos',
          'pagos_contrato_alumno',
          'solicitudes_cotizacion',
          'prestamo_alquiler_lineas',
          'pagos_prestamo_alquiler',
          'calculos_rentabilidad',
          'obligaciones_pago',
          'caja_fuerte_movimientos',
        ];
        for (final tabla in tablasUpdatedAt) {
          try {
            await db.execute('ALTER TABLE $tabla ADD COLUMN updated_at TEXT');
          } catch (_) {
            // Ya existe — OK
          }
        }

        // Inicializar updated_at con created_at donde exista
        final tablasConCreatedAt = [
          'clientes',
          'eventos',
          'presupuestos',
          'contratos_alumnos',
          'pagos_contrato_alumno',
          'pagos_prestamo_alquiler',
          'calculos_rentabilidad',
          'obligaciones_pago',
          'caja_fuerte_movimientos',
          'solicitudes_cotizacion',
        ];
        for (final tabla in tablasConCreatedAt) {
          try {
            await db.execute(
              'UPDATE $tabla SET updated_at = created_at '
              'WHERE updated_at IS NULL AND created_at IS NOT NULL',
            );
          } catch (_) {}
        }

        // Tablas sin created_at: inicializar con now()
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final tablasSinCreatedAt = [
          'servicios',
          'eventos_servicios',
          'presupuesto_servicios',
          'prestamo_alquiler_lineas',
        ];
        for (final tabla in tablasSinCreatedAt) {
          try {
            await db.execute(
              "UPDATE $tabla SET updated_at = '$nowIso' WHERE updated_at IS NULL",
            );
          } catch (_) {}
        }

        // Transacciones y egresos: usar columnas de fecha de negocio como fallback
        try {
          await db.execute(
            'UPDATE transacciones SET updated_at = fecha_pago '
            'WHERE updated_at IS NULL AND fecha_pago IS NOT NULL',
          );
          await db.execute(
            'UPDATE egresos SET updated_at = fecha '
            'WHERE updated_at IS NULL AND fecha IS NOT NULL',
          );
        } catch (_) {}

        // Reset _sync_meta para forzar pull completo la primera vez
        await db.delete('_sync_meta');
        debugPrint('  🔄 _sync_meta reseteado: primer sync será pull completo');

        debugPrint('✅ Migración v45 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v45: $e');
      }
    }

    if (oldVersion < 46) {
      debugPrint(
        '  🔧 v46: es_extra en presupuesto_servicios y eventos_servicios',
      );
      try {
        await db.execute(
          'ALTER TABLE presupuesto_servicios ADD COLUMN es_extra INTEGER DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE eventos_servicios ADD COLUMN es_extra INTEGER DEFAULT 0',
        );
        debugPrint('✅ Migración v46 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v46: $e');
      }
    }

    if (oldVersion < 47) {
      debugPrint(
        '  🔧 v47: cierre_caja_guia_movimientos + cierre_caja_anotaciones',
      );
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cierre_caja_guia_movimientos (
            id TEXT PRIMARY KEY,
            fecha TEXT NOT NULL,
            tipo TEXT NOT NULL,
            monto REAL NOT NULL,
            saldo_antes REAL,
            saldo_despues REAL NOT NULL,
            nota TEXT,
            fecha_mov TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cierre_caja_anotaciones (
            id TEXT PRIMARY KEY,
            fecha TEXT NOT NULL,
            turno TEXT NOT NULL,
            texto TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(fecha, turno)
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_guia_cambio_fecha '
          'ON cierre_caja_guia_movimientos(fecha, fecha_mov)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cierre_anotacion_fecha '
          'ON cierre_caja_anotaciones(fecha, turno)',
        );
        final nowIso = DateTime.now().toUtc().toIso8601String();
        for (final tabla in [
          'cierre_caja_guia_movimientos',
          'cierre_caja_anotaciones',
        ]) {
          await db.insert('_sync_meta', {
            'clave': 'last_pull_$tabla',
            'valor': nowIso,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        debugPrint('✅ Migración v47 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v47: $e');
      }
    }

    if (oldVersion < 48) {
      debugPrint('  🔧 v48: mesa_extra_cantidad + mesas_extra_estado');
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_cantidad INTEGER DEFAULT 0',
        );
      } catch (e) {
        debugPrint('  ⚠️ mesa_extra_cantidad: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN mesas_extra_estado TEXT',
        );
      } catch (e) {
        debugPrint('  ⚠️ mesas_extra_estado: $e');
      }

      try {
        final rows = await db.query(
          'contratos_alumnos',
          columns: [
            'id',
            'mesa_extra_precio',
            'mesa_extra_pagado',
            'mesa_extra_cuotas_pagadas',
            'mesas_extra_estado',
          ],
        );
        for (final row in rows) {
          final estado = row['mesas_extra_estado'] as String?;
          if (estado != null && estado.trim().isNotEmpty) continue;

          final precio = (row['mesa_extra_precio'] as num?)?.toDouble() ?? 0.0;
          if (precio <= 0.01) continue;

          final pagado = (row['mesa_extra_pagado'] as num?)?.toDouble() ?? 0.0;
          final cuotasPagadas =
              (row['mesa_extra_cuotas_pagadas'] as num?)?.toInt() ?? 0;
          final liquidada = pagado >= precio - 0.01;
          final jsonEstado = jsonEncode([
            {
              'n': 1,
              'precio': precio,
              'pagado': pagado,
              'cuotasPagadas': cuotasPagadas,
              'liquidada': liquidada,
            },
          ]);
          await db.update(
            'contratos_alumnos',
            {'mesa_extra_cantidad': 1, 'mesas_extra_estado': jsonEstado},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        debugPrint('✅ Migración v48 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v48 backfill: $e');
      }
    }

    if (oldVersion < 49) {
      debugPrint(
        '  🔧 v49: limpiar mora_pendiente_tracked inflado + actualizar mora_cobrada_offset',
      );
      try {
        // tracked solo debe contener remanente de pagos parciales de mora.
        // Los valores inflados por carry-over de cuotas sin cobrar mora
        // se resetean a 0. offset = total mora cobrada historial para que
        // el FIFO calendario arranque limpio.
        await db.rawUpdate('''
          UPDATE contratos_alumnos
          SET mora_pendiente_tracked = 0,
              mora_cobrada_offset = (
                SELECT COALESCE(SUM(p.monto), 0.0)
                FROM pagos_contrato_alumno p
                WHERE p.contrato_alumno_id = contratos_alumnos.id
                  AND (p.line_kind = 'interes_mora'
                       OR LOWER(IFNULL(p.concepto,'')) LIKE '%mora%'
                       OR LOWER(IFNULL(p.concepto,'')) LIKE '%inter%')
                  AND (p.anulado IS NULL OR p.anulado = 0)
              )
          WHERE mora_pendiente_tracked > 0.01
        ''');
        debugPrint('✅ Migración v49 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v49: $e');
      }
    }

    if (oldVersion < 50) {
      debugPrint(
        '  🔧 v50: mora tracked conservador (historial) + offset/tracked recalculados',
      );
      try {
        // Solo inflados: tracked > 0 sin ningún pago de mora en historial.
        await db.rawUpdate('''
          UPDATE contratos_alumnos
          SET mora_pendiente_tracked = 0,
              mora_cobrada_offset = 0
          WHERE mora_pendiente_tracked > 0.01
            AND NOT EXISTS (
              SELECT 1 FROM pagos_contrato_alumno p
              WHERE p.contrato_alumno_id = contratos_alumnos.id
                AND (p.line_kind = 'interes_mora'
                     OR LOWER(IFNULL(p.concepto,'')) LIKE '%mora%'
                     OR LOWER(IFNULL(p.concepto,'')) LIKE '%inter%')
                AND (p.anulado IS NULL OR p.anulado = 0)
            )
        ''');

        final contratos = await db.query('contratos_alumnos');
        var recalculados = 0;
        for (final row in contratos) {
          final contrato = ContratoAlumno.fromJson(row);
          final pagos = await db.query(
            'pagos_contrato_alumno',
            where: 'contrato_alumno_id = ?',
            whereArgs: [contrato.id],
          );
          if (!MoraTrackedRecovery.tieneMoraEnHistorial(pagos)) continue;

          final sim = MoraTrackedRecovery.recomputarDesdeHistorial(
            contratoBase: contrato.copyWith(
              moraPendienteTracked: 0,
              moraCobradaOffset: 0,
            ),
            pagos: pagos,
          );

          final trackedActual =
              (row['mora_pendiente_tracked'] as num?)?.toDouble() ?? 0;
          final offsetActual =
              (row['mora_cobrada_offset'] as num?)?.toDouble() ?? 0;

          final trackedObjetivo =
              MoraTrackedRecovery.trackedPareceInflado(
                tracked: trackedActual,
                pagos: pagos,
              )
              ? 0.0
              : (trackedActual > 0.01 ? trackedActual : sim.tracked);

          if ((trackedObjetivo - trackedActual).abs() > 0.01 ||
              (sim.offset - offsetActual).abs() > 0.01) {
            await db.update(
              'contratos_alumnos',
              {
                'mora_pendiente_tracked': trackedObjetivo,
                'mora_cobrada_offset': sim.offset,
              },
              where: 'id = ?',
              whereArgs: [contrato.id],
            );
            recalculados++;
          }
        }
        debugPrint(
          '✅ Migración v50 completada ($recalculados contratos recalibrados)',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v50: $e');
      }
    }

    if (oldVersion < 51) {
      debugPrint(
        '  🔧 v51: tracked/offset siempre desde historial (fix carry-over stale + sync)',
      );
      try {
        final recalculados = await MoraTrackedRecovery.reconciliarTodos(
          db: db,
          encolarSync: true,
        );
        debugPrint(
          '✅ Migración v51 completada ($recalculados contratos recalibrados)',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v51: $e');
      }
    }

    if (oldVersion < 52) {
      debugPrint(
        '  🔧 v52: mora_fecha_referencia + baja_temporal_desde (congelar mora en baja)',
      );
      for (final col in [
        'ALTER TABLE contratos_alumnos ADD COLUMN mora_fecha_referencia TEXT',
        'ALTER TABLE contratos_alumnos ADD COLUMN baja_temporal_desde TEXT',
      ]) {
        try {
          await db.execute(col);
        } catch (e) {
          debugPrint('  ⚠️ v52 columna ya existe o error: $e');
        }
      }
      debugPrint('✅ Migración v52 completada');
    }

    if (oldVersion < 53) {
      debugPrint(
        '  🔧 v53: tracked/offset en masivos — cuota sin mora en historial',
      );
      try {
        final recalculados = await MoraTrackedRecovery.reconciliarTodos(
          db: db,
          encolarSync: false,
          soloEventosMasivosActivos: true,
        );
        debugPrint(
          '✅ Migración v53 completada ($recalculados contratos masivos recalibrados)',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v53: $e');
      }
    }

    if (oldVersion < 54) {
      debugPrint(
        '  🔧 v54: line_kind mora remanente + saldo/tracked corregidos',
      );
      try {
        final moraRows = await db.query(
          'pagos_contrato_alumno',
          columns: ['id', 'concepto', 'contrato_alumno_id'],
        );
        final contratosAfectados = <String>{};
        for (final r in moraRows) {
          final concepto = r['concepto'] as String?;
          if (!esPagoInteresMoraPorConcepto(concepto)) continue;
          await db.update(
            'pagos_contrato_alumno',
            {'line_kind': kLineKindInteresMora},
            where: 'id = ? AND (line_kind IS NULL OR line_kind = ?)',
            whereArgs: [r['id'], ''],
          );
          final cid = r['contrato_alumno_id'] as String?;
          if (cid != null && cid.isNotEmpty) contratosAfectados.add(cid);
        }

        var saldosCorregidos = 0;
        for (final contratoId in contratosAfectados) {
          final cRows = await db.query(
            'contratos_alumnos',
            where: 'id = ?',
            whereArgs: [contratoId],
            limit: 1,
          );
          if (cRows.isEmpty) continue;
          final row = cRows.first;
          final contrato = ContratoAlumno.fromJson(row);
          final pagos = await db.query(
            'pagos_contrato_alumno',
            where: 'contrato_alumno_id = ?',
            whereArgs: [contratoId],
          );
          final recalculo = recalcularSaldoDesdePagos(
            montoTotalPactado: contrato.montoTotalPactado,
            totalCuotas: contrato.totalCuotas,
            mesaExtraPrecio: contrato.mesaExtraPrecio,
            sillasExtraPrecioTotal: contrato.sillasExtraPrecioTotal,
            precioUnitarioMesaExtra: contrato.precioUnitarioMesaExtra,
            mesaExtraCuotas: contrato.mesaExtraCuotas,
            mesaExtraCantidad: contrato.mesaExtraCantidad,
            sillasExtraCuotas: contrato.sillasExtraCuotas,
            pagos: pagos,
          );
          final saldoNuevo = recalculo.saldoDeudor.clamp(0.0, double.infinity);
          final updates = <String, dynamic>{
            'cuotas_pagadas': recalculo.cuotasBase,
            'mesa_extra_cuotas_pagadas': recalculo.cuotasMesa,
            'sillas_extra_cuotas_pagadas': recalculo.cuotasSillas,
            'mesa_extra_pagado': recalculo.grossMesa,
            'sillas_extra_pagado': recalculo.grossSillas,
            'saldo_deudor': saldoNuevo,
          };
          var cambio = false;
          for (final e in updates.entries) {
            final old = (row[e.key] as num?)?.toDouble() ?? 0;
            if ((old - (e.value as num).toDouble()).abs() > 0.01) {
              cambio = true;
              break;
            }
          }
          if (cambio) {
            await db.update(
              'contratos_alumnos',
              updates,
              where: 'id = ?',
              whereArgs: [contratoId],
            );
            saldosCorregidos++;
          }
        }

        final trackedCorregidos = await MoraTrackedRecovery.reconciliarTodos(
          db: db,
          encolarSync: false,
          soloEventosMasivosActivos: true,
        );
        debugPrint(
          '✅ Migración v54: $saldosCorregidos saldos, '
          '$trackedCorregidos tracked/offset',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v54: $e');
      }
    }

    if (oldVersion < 55) {
      debugPrint(
        '  🔧 v55: offset al cobrar mora remanente (reconciliar tracked)',
      );
      try {
        final recalculados = await MoraTrackedRecovery.reconciliarTodos(
          db: db,
          encolarSync: false,
          soloEventosMasivosActivos: true,
        );
        debugPrint(
          '✅ Migración v55 completada ($recalculados contratos recalibrados)',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v55: $e');
      }
    }

    if (oldVersion < 56) {
      debugPrint(
        '  🔧 v56: mora_exenta_hasta + reparar alumnos que pagaron toda la mora',
      );
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos ADD COLUMN mora_exenta_hasta TEXT',
        );
      } catch (e) {
        debugPrint('  ⚠️ mora_exenta_hasta ya existía: $e');
      }
      try {
        final repaired =
            await MoraTrackedRecovery.repararExencionDesdeHistorial(
              db: db,
              soloEventosMasivosActivos: true,
            );
        debugPrint(
          '✅ Migración v56 completada ($repaired contratos con exención)',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v56: $e');
      }
    }

    if (oldVersion < 57) {
      debugPrint(
        '  🔧 v57: reparar exenciones mora borradas por sync (post-fix 4.2.7)',
      );
      try {
        final repaired =
            await MoraTrackedRecovery.repararExencionDesdeHistorial(
              db: db,
              soloEventosMasivosActivos: true,
            );
        debugPrint(
          '✅ Migración v57 completada ($repaired contratos con exención)',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v57: $e');
      }
    }

    if (oldVersion < 58) {
      debugPrint(
        '  🔧 v58: Reg unificado 30/03/2026 (masivos, excepto BUENA VISTA / PUERTO VIEJO)',
      );
      try {
        const regIso = '2026-03-30T12:00:00.000Z';
        final rows = await db.rawQuery('''
          SELECT ca.id, ca.institucion, c.nombre_completo AS cliente_nombre,
                 e.tipo AS evento_tipo
          FROM contratos_alumnos ca
          INNER JOIN eventos e ON e.id = ca.evento_id
          LEFT JOIN clientes c ON c.id = e.cliente_id
          WHERE e.modalidad = 'masivo'
        ''');
        final nowUtc = DateTime.now().toUtc().toIso8601String();
        var updated = 0;
        for (final row in rows) {
          if (CronogramaCuotasUtils.excluidoDeRegUnificado(
            clienteNombre: row['cliente_nombre'] as String?,
            eventoTipo: row['evento_tipo'] as String?,
            institucion: row['institucion'] as String?,
          )) {
            continue;
          }
          await db.update(
            'contratos_alumnos',
            {'created_at': regIso, 'updated_at': nowUtc},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          updated++;
        }
        final recalibrados = await MoraTrackedRecovery.reconciliarTodos(
          db: db,
          encolarSync: true,
          soloEventosMasivosActivos: true,
        );
        final exenciones =
            await MoraTrackedRecovery.repararExencionDesdeHistorial(
              db: db,
              soloEventosMasivosActivos: true,
            );
        debugPrint(
          '✅ Migración v58: $updated Reg actualizados, '
          '$recalibrados tracked, $exenciones exenciones',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v58: $e');
      }
    }

    if (oldVersion < 59) {
      debugPrint('  🔧 v59: titulo_festejado en eventos (homenajeado)');
      try {
        await db.execute(
          'ALTER TABLE eventos ADD COLUMN titulo_festejado TEXT',
        );
        debugPrint('✅ Migración v59 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v59: $e');
      }
    }

    if (oldVersion < 60) {
      debugPrint(
        '  🔧 v60: nombre_festejado + encabezado_evento (particulares)',
      );
      try {
        await db.execute(
          'ALTER TABLE eventos ADD COLUMN nombre_festejado TEXT',
        );
        await db.execute(
          'ALTER TABLE eventos ADD COLUMN encabezado_evento TEXT',
        );
        await db.execute(
          'ALTER TABLE presupuestos ADD COLUMN nombre_festejado TEXT',
        );
        await db.execute(
          'ALTER TABLE presupuestos ADD COLUMN encabezado_evento TEXT',
        );

        final eventos = await db.query(
          'eventos',
          columns: ['id', 'tipo', 'titulo_festejado'],
          where: 'titulo_festejado IS NOT NULL AND TRIM(titulo_festejado) != ?',
          whereArgs: [''],
        );
        for (final row in eventos) {
          final titulo = (row['titulo_festejado'] as String?)?.trim();
          if (titulo == null || titulo.isEmpty) continue;
          final tipo = (row['tipo'] as String?) ?? '';
          final partes = EventoPresentacion.dividirTituloFestejadoLegacy(
            titulo,
            tipo,
          );
          await db.update(
            'eventos',
            {
              if (partes.nombreFestejado != null)
                'nombre_festejado': partes.nombreFestejado,
              if (partes.encabezadoEvento != null)
                'encabezado_evento': partes.encabezadoEvento,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }

        final presupuestos = await db.query(
          'presupuestos',
          columns: ['id', 'tipo_evento', 'titulo_festejado'],
          where: 'titulo_festejado IS NOT NULL AND TRIM(titulo_festejado) != ?',
          whereArgs: [''],
        );
        for (final row in presupuestos) {
          final titulo = (row['titulo_festejado'] as String?)?.trim();
          if (titulo == null || titulo.isEmpty) continue;
          final tipo = (row['tipo_evento'] as String?) ?? '';
          final partes = EventoPresentacion.dividirTituloFestejadoLegacy(
            titulo,
            tipo,
          );
          await db.update(
            'presupuestos',
            {
              if (partes.nombreFestejado != null)
                'nombre_festejado': partes.nombreFestejado,
              if (partes.encabezadoEvento != null)
                'encabezado_evento': partes.encabezadoEvento,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }

        debugPrint(
          '✅ Migración v60 completada (${eventos.length} eventos, ${presupuestos.length} presupuestos)',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v60: $e');
      }
    }

    if (oldVersion < 61) {
      debugPrint(
        '  🔧 v61: mora_exencion_reinicia + reparar 5 contratos drift',
      );
      try {
        await db.execute(
          'ALTER TABLE contratos_alumnos '
          'ADD COLUMN mora_exencion_reinicia INTEGER DEFAULT 1',
        );
      } catch (e) {
        debugPrint('  ⚠️ mora_exencion_reinicia ya existía: $e');
      }

      try {
        // Exenciones existentes: default reinicia=1 (comportamiento Lezcano).
        // Casos solo-mora (abono sin liquidar cuota) → permanente (0).
        final exenciones =
            await MoraTrackedRecovery.repararExencionDesdeHistorial(
              db: db,
              soloEventosMasivosActivos: true,
            );
        final recalibrados = await MoraTrackedRecovery.reconciliarTodos(
          db: db,
          soloEventosMasivosActivos: true,
        );
        debugPrint(
          '✅ Migración v61: $exenciones exenciones, $recalibrados tracked',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v61 repair: $e');
      }
    }

    if (oldVersion < 62) {
      debugPrint(
        '  🔧 v62: nombres institución + Reg 30/03/2026 (9 masivos activos, sin exclusiones)',
      );
      try {
        final regIso = MoraCuotaCalculator.regArAUtcIso(DateTime(2026, 3, 30));
        final nowUtc = DateTime.now().toUtc().toIso8601String();

        final eventos = await db.rawQuery('''
          SELECT e.id, c.nombre_completo AS cliente_nombre
          FROM eventos e
          LEFT JOIN clientes c ON c.id = e.cliente_id
          WHERE e.modalidad = 'masivo'
            AND UPPER(COALESCE(e.estado, '')) NOT IN ('FINALIZADO', 'CANCELADO')
        ''');

        var eventosNombrados = 0;
        var contratosInst = 0;
        var contratosReg = 0;

        for (final ev in eventos) {
          final eventoId = ev['id'] as String;
          final nombre = (ev['cliente_nombre'] as String?)?.trim() ?? '';
          if (nombre.isEmpty) continue;

          await db.update(
            'eventos',
            {'encabezado_evento': nombre, 'updated_at': nowUtc},
            where: 'id = ?',
            whereArgs: [eventoId],
          );
          eventosNombrados++;
          await SyncQueue.enqueue(
            executor: db,
            tabla: 'eventos',
            operacion: SyncOperation.update,
            registroId: eventoId,
            payload: {'id': eventoId, 'encabezado_evento': nombre},
          );

          final contratos = await db.query(
            'contratos_alumnos',
            columns: ['id', 'institucion', 'created_at', 'nombre_alumno'],
            where: 'evento_id = ?',
            whereArgs: [eventoId],
          );

          for (final ca in contratos) {
            final contratoId = ca['id'] as String;
            final nombreAlumno = (ca['nombre_alumno'] as String?) ?? '';
            if (nombreAlumno.toUpperCase().startsWith('[BAJA]')) continue;

            final instActual = (ca['institucion'] as String?)?.trim() ?? '';
            final regActual = (ca['created_at'] as String?) ?? '';
            final updates = <String, Object?>{'updated_at': nowUtc};
            final syncPayload = <String, dynamic>{'id': contratoId};

            if (instActual != nombre) {
              updates['institucion'] = nombre;
              syncPayload['institucion'] = nombre;
              contratosInst++;
            }
            if (!regActual.startsWith('2026-03-30')) {
              updates['created_at'] = regIso;
              syncPayload['created_at'] = regIso;
              contratosReg++;
            }

            if (updates.length == 1) continue; // solo updated_at

            await db.update(
              'contratos_alumnos',
              updates,
              where: 'id = ?',
              whereArgs: [contratoId],
            );
            await SyncQueue.enqueue(
              executor: db,
              tabla: 'contratos_alumnos',
              operacion: SyncOperation.update,
              registroId: contratoId,
              payload: syncPayload,
            );
          }
        }

        final recalibrados = await MoraTrackedRecovery.reconciliarTodos(
          db: db,
          encolarSync: true,
          soloEventosMasivosActivos: true,
        );
        final exenciones =
            await MoraTrackedRecovery.repararExencionDesdeHistorial(
              db: db,
              soloEventosMasivosActivos: true,
            );

        debugPrint(
          '✅ Migración v62: $eventosNombrados eventos, '
          '$contratosInst instituciones, $contratosReg Reg, '
          '$recalibrados tracked, $exenciones exenciones',
        );
      } catch (e) {
        debugPrint('  ❌ Error migración v62: $e');
      }
    }

    if (oldVersion < 63) {
      debugPrint(
        '  🔧 v63: reparar pagos "— Completada" con excedente (parcialLibre)',
      );
      try {
        final reparados = await _repararPagosCompletadaConExcedente(
          db,
          encolarSync: true,
        );
        debugPrint('✅ Migración v63 completada ($reparados pagos reparados)');
      } catch (e) {
        debugPrint('  ❌ Error migración v63: $e');
      }
    }

    if (oldVersion < 64) {
      debugPrint(
        '  🔧 v64: operadores_caja + sesiones_caja + sesion_caja_id en pagos',
      );
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS operadores_caja (
            id TEXT PRIMARY KEY,
            nombre TEXT NOT NULL,
            pin TEXT NOT NULL,
            activo INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sesiones_caja (
            id TEXT PRIMARY KEY,
            operador_id TEXT NOT NULL,
            abierta_at TEXT NOT NULL,
            cerrada_at TEXT,
            cambio_inicial REAL NOT NULL DEFAULT 0,
            nota_apertura TEXT,
            etiqueta TEXT,
            arqueo_cierre REAL,
            nota_cierre TEXT,
            device_id TEXT,
            last_heartbeat TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (operador_id) REFERENCES operadores_caja(id)
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sesiones_caja_abierta ON sesiones_caja(cerrada_at, abierta_at)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sesiones_caja_operador ON sesiones_caja(operador_id)',
        );
        try {
          await db.execute(
            'ALTER TABLE pagos_contrato_alumno ADD COLUMN sesion_caja_id TEXT',
          );
        } catch (e) {
          debugPrint('  ⚠️ Nota: sesion_caja_id ya existía o error: $e');
        }
        debugPrint('✅ Migración v64 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v64: $e');
      }
    }

    if (oldVersion < 65) {
      debugPrint('  🔧 v65: cierre de caja por sesión + sesión abierta única');
      try {
        for (final statement in [
          'ALTER TABLE egresos ADD COLUMN sesion_caja_id TEXT',
          'ALTER TABLE cierre_caja_guia_movimientos ADD COLUMN sesion_caja_id TEXT',
        ]) {
          try {
            await db.execute(statement);
          } catch (e) {
            debugPrint('  ⚠️ Columna v65 ya existente o no aplicable: $e');
          }
        }

        // Si una versión de prueba dejó más de una sesión abierta para el mismo
        // operador, conserva la más reciente antes de crear el índice único.
        final nowIso = ArTime.nowUtcIso();
        await db.rawUpdate(
          '''
          UPDATE sesiones_caja
          SET cerrada_at = ?, updated_at = ?
          WHERE cerrada_at IS NULL
            AND EXISTS (
              SELECT 1
              FROM sesiones_caja newer
              WHERE newer.operador_id = sesiones_caja.operador_id
                AND newer.cerrada_at IS NULL
                AND (
                  newer.abierta_at > sesiones_caja.abierta_at OR
                  (newer.abierta_at = sesiones_caja.abierta_at
                    AND newer.id > sesiones_caja.id)
                )
            )
        ''',
          [nowIso, nowIso],
        );
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'idx_sesiones_caja_operador_unica_abierta '
          'ON sesiones_caja(operador_id) WHERE cerrada_at IS NULL',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_egresos_sesion_caja '
          'ON egresos(sesion_caja_id)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_guia_cambio_sesion '
          'ON cierre_caja_guia_movimientos(sesion_caja_id, fecha_mov)',
        );

        // La clave legacy (fecha, turno) impedía dos operadores en el mismo
        // turno. Se reemplaza por una anotación opcional por sesión.
        await db.execute('DROP TABLE IF EXISTS cierre_caja_anotaciones_v65');
        await db.execute('''
          CREATE TABLE cierre_caja_anotaciones_v65 (
            id TEXT PRIMARY KEY,
            fecha TEXT NOT NULL,
            turno TEXT NOT NULL,
            sesion_caja_id TEXT,
            texto TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(sesion_caja_id)
          )
        ''');
        await db.execute('''
          INSERT INTO cierre_caja_anotaciones_v65
            (id, fecha, turno, sesion_caja_id, texto, created_at, updated_at)
          SELECT id, fecha, turno, NULL, texto, created_at, updated_at
          FROM cierre_caja_anotaciones
        ''');
        await db.execute('DROP TABLE cierre_caja_anotaciones');
        await db.execute(
          'ALTER TABLE cierre_caja_anotaciones_v65 '
          'RENAME TO cierre_caja_anotaciones',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cierre_anotacion_sesion '
          'ON cierre_caja_anotaciones(sesion_caja_id)',
        );
        debugPrint('✅ Migración v65 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v65: $e');
      }
    }

    if (oldVersion < 66) {
      debugPrint('  🔧 v66: id UUID válido para operador Modo jefe');
      try {
        // Constantes de lib/features/caja_sesiones/models/modo_jefe_caja.dart.
        // El id legacy (38 chars, no-hex) era rechazado por la cola de sync y
        // por la validación UUID del sync engine: operador y sesión Modo jefe
        // nunca llegaban a Supabase.
        const legacy = '00000000-0000-4000-8000-cafemodojefe01';
        const nuevo = '00000000-0000-4000-8000-0000cafe0001';

        await db.execute('''
          INSERT OR IGNORE INTO operadores_caja
            (id, nombre, pin, activo, created_at, updated_at)
          SELECT '$nuevo', nombre, pin, activo, created_at, updated_at
          FROM operadores_caja WHERE id = '$legacy'
        ''');
        await db.rawUpdate(
          'UPDATE sesiones_caja SET operador_id = ? WHERE operador_id = ?',
          [nuevo, legacy],
        );
        await db.delete(
          'operadores_caja',
          where: 'id = ?',
          whereArgs: [legacy],
        );

        // Cola de sync: reescribe payloads que referencian el id legacy y
        // revive entradas trabadas por FK (sesiones Modo jefe que fallaban).
        await db.rawUpdate(
          'UPDATE _sync_queue SET payload = REPLACE(payload, ?, ?), '
          'intentos = 0, ultimo_error = NULL WHERE payload LIKE ?',
          [legacy, nuevo, '%$legacy%'],
        );
        await db.delete(
          '_sync_queue',
          where: "tabla = 'operadores_caja' AND registro_id = ?",
          whereArgs: [legacy],
        );
        debugPrint('✅ Migración v66 completada');
      } catch (e) {
        debugPrint('  ❌ Error migración v66: $e');
      }
    }
  }

  /// Parte pagos base guardados como una sola línea "— Completada" cuando el
  /// monto superaba el faltante (bug parcialLibre). Conserva fecha/hora.
  static Future<int> _repararPagosCompletadaConExcedente(
    Database db, {
    required bool encolarSync,
  }) async {
    final candidatos = await db.rawQuery('''
      SELECT p.*
      FROM pagos_contrato_alumno p
      WHERE (p.anulado IS NULL OR p.anulado = 0)
        AND LOWER(IFNULL(p.concepto, '')) LIKE '%completada%'
        AND LOWER(IFNULL(p.concepto, '')) NOT LIKE '%mesa%'
        AND LOWER(IFNULL(p.concepto, '')) NOT LIKE '%silla%'
      ORDER BY p.fecha_pago ASC, p.id ASC
    ''');
    if (candidatos.isEmpty) return 0;

    var reparados = 0;
    for (final pago in candidatos) {
      final pagoId = pago['id']?.toString();
      final contratoId = pago['contrato_alumno_id']?.toString();
      if (pagoId == null ||
          pagoId.isEmpty ||
          contratoId == null ||
          contratoId.isEmpty) {
        continue;
      }

      final concepto = pago['concepto']?.toString() ?? '';
      final montoGross =
          (pago['monto_gross'] as num?)?.toDouble() ??
          (pago['monto'] as num?)?.toDouble() ??
          0.0;
      final montoNet = (pago['monto'] as num?)?.toDouble() ?? montoGross;
      if (montoGross <= 0.01) continue;

      final cRows = await db.query(
        'contratos_alumnos',
        where: 'id = ?',
        whereArgs: [contratoId],
        limit: 1,
      );
      if (cRows.isEmpty) continue;
      final contrato = ContratoAlumno.fromJson(cRows.first);
      final totalCuotas = contrato.totalCuotas > 0 ? contrato.totalCuotas : 1;
      final basePlan =
          (contrato.montoTotalPactado -
                  contrato.mesaExtraPrecio -
                  contrato.sillasExtraPrecioTotal)
              .clamp(0.0, double.infinity);
      final cuotaPura = totalCuotas > 0 ? basePlan / totalCuotas : basePlan;

      final fechaPago = pago['fecha_pago']?.toString() ?? '';
      final historicos = await db.rawQuery(
        '''
        SELECT * FROM pagos_contrato_alumno
        WHERE contrato_alumno_id = ?
          AND id != ?
          AND (anulado IS NULL OR anulado = 0)
          AND (
            fecha_pago < ?
            OR (fecha_pago = ? AND id < ?)
          )
        ORDER BY fecha_pago ASC, id ASC
        ''',
        [contratoId, pagoId, fechaPago, fechaPago, pagoId],
      );
      final grossAntes = grossHistoricoClaseCobro(
        historicos,
        CobroConceptoClase.base,
      );

      final lineas = lineasReparacionCompletadaConExcedente(
        concepto: concepto,
        montoGross: montoGross,
        grossHistoricoAntes: grossAntes,
        cuotaPura: cuotaPura,
        totalCuotas: totalCuotas,
      );
      if (lineas == null || lineas.length < 2) continue;

      final descPct = (pago['descuento_porcentaje'] as num?)?.toDouble() ?? 0.0;
      final medio = pago['medio_pago'];
      final createdAt = pago['created_at'] ?? fechaPago;
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      final lineKind = pago['line_kind'];

      var netAcum = 0.0;
      for (var i = 0; i < lineas.length; i++) {
        final l = lineas[i];
        late double netLine;
        if (i == lineas.length - 1) {
          netLine = double.parse((montoNet - netAcum).toStringAsFixed(2));
        } else if (montoGross > 0.011) {
          netLine = double.parse(
            (montoNet * (l.gross / montoGross)).toStringAsFixed(2),
          );
          netAcum += netLine;
        } else {
          netLine = 0;
        }

        if (i == 0) {
          await db.update(
            'pagos_contrato_alumno',
            {
              'concepto': l.concepto,
              'monto': netLine,
              'monto_gross': l.gross,
              'updated_at': updatedAt,
            },
            where: 'id = ?',
            whereArgs: [pagoId],
          );
          if (encolarSync) {
            await SyncQueue.enqueue(
              executor: db,
              tabla: 'pagos_contrato_alumno',
              operacion: SyncOperation.update,
              registroId: pagoId,
              payload: {
                'id': pagoId,
                'concepto': l.concepto,
                'monto': netLine,
                'monto_gross': l.gross,
                'fecha_pago': fechaPago,
              },
            );
          }
        } else {
          final nuevoId = UuidUtils.generate();
          final row = <String, dynamic>{
            'id': nuevoId,
            'contrato_alumno_id': contratoId,
            'monto': netLine,
            'monto_gross': l.gross,
            'descuento_porcentaje': descPct,
            'concepto': l.concepto,
            'fecha_pago': fechaPago,
            'created_at': createdAt,
            'updated_at': updatedAt,
            'medio_pago': medio,
            'anulado': 0,
            if (lineKind != null) 'line_kind': lineKind,
          };
          await db.insert('pagos_contrato_alumno', row);
          if (encolarSync) {
            await SyncQueue.enqueue(
              executor: db,
              tabla: 'pagos_contrato_alumno',
              operacion: SyncOperation.insert,
              registroId: nuevoId,
              payload: row,
            );
          }
        }
      }
      reparados++;
    }
    return reparados;
  }

  /// Cierra la conexión a la base de datos.
  static Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  /// Purga completa para debug — NO disponible en release.
  static Future<void> purgeAllData() async {
    assert(kDebugMode, 'Purga disponible solo en debug');
    if (!kDebugMode) return;

    final db = await instance;
    final tables = [
      'pagos_contrato_alumno',
      'notas_operativas_contrato',
      'contratos_alumnos',
      'transacciones',
      'egresos',
      'eventos_servicios',
      'solicitudes_cotizacion',
      'accesos',
      'invitados',
      'eventos',
      'clientes',
      '_sync_queue',
      '_sync_meta',
    ];
    for (final table in tables) {
      await db.delete(table);
    }
    debugPrint('🗑️ SQLite purgado (debug)');
  }

  /// Saneamiento de emergencia: Elimina registros con IDs malformados (no conformes a UUID).
  /// Aplica también a referencias de FK como contrato_alumno_id y evento_id.
  static Future<void> sanitizeLegacyData() async {
    final db = await instance;
    final tables = [
      'clientes',
      'eventos',
      'servicios',
      'eventos_servicios',
      'transacciones',
      'egresos',
      'contratos_alumnos',
      'pagos_contrato_alumno',
      'notas_operativas_contrato',
      'invitados',
      'accesos',
      'solicitudes_cotizacion',
    ];

    int totalBorrados = 0;

    await db.transaction((txn) async {
      for (final table in tables) {
        final columns = await txn.rawQuery('PRAGMA table_info($table)');
        final hasId = columns.any((c) => c['name'] == 'id');
        final hasEventoId = columns.any((c) => c['name'] == 'evento_id');
        final hasContratoId = columns.any(
          (c) => c['name'] == 'contrato_alumno_id',
        );

        int b1 = 0, b2 = 0, b3 = 0;

        // 1. Borrar por ID malformado (cualquier ID que no sea UUID de 36 chars o sea la palabra "null")
        if (hasId) {
          b1 = await txn.delete(
            table,
            where: "id IS NOT NULL AND (LENGTH(id) != 36 OR id = 'null')",
          );
        }

        // 2. Borrar por evento_id malformado
        if (hasEventoId) {
          b2 = await txn.delete(
            table,
            where:
                "evento_id IS NOT NULL AND (LENGTH(evento_id) != 36 OR evento_id = 'null')",
          );
        }

        // 3. Borrar por contrato_alumno_id malformado
        if (hasContratoId) {
          b3 = await txn.delete(
            table,
            where:
                "contrato_alumno_id IS NOT NULL AND (LENGTH(contrato_alumno_id) != 36 OR contrato_alumno_id = 'null')",
          );
          if (b3 > 0)
            debugPrint(
              '  🧼 Saneados $b3 registros de $table (contrato_alumno_id malformado)',
            );
        }

        totalBorrados += (b1 + b2 + b3);
        if (b1 + b2 > 0) {
          debugPrint('  🧼 Saneados ${b1 + b2} registros de $table');
        }
      }

      // 4. LIMPIEZA NUCLEAR DE HUÉRFANOS (Registros que apuntan a eventos inexistentes)
      // Esto elimina el ruido de sincronización de eventos borrados
      final tablesToCleanup = [
        'contratos_alumnos',
        'transacciones',
        'egresos',
        'invitados',
        'servicios',
      ];
      int orfanosBorrados = 0;

      for (final table in tablesToCleanup) {
        // En servicios, solo borramos los que tienen evento_id (los globales tienen NULL)
        final count = await txn.rawDelete(
          "DELETE FROM $table WHERE evento_id IS NOT NULL AND evento_id NOT IN (SELECT id FROM eventos)",
        );
        if (count > 0) {
          orfanosBorrados += count.toInt();
          debugPrint(
            '  ☢️ Purga Nuclear: Eliminados $count huérfanos de $table (evento inexistente)',
          );
        }
      }

      // Limpiar pagos sin contrato padre
      final pBorrados = await txn.rawDelete(
        "DELETE FROM pagos_contrato_alumno WHERE contrato_alumno_id NOT IN (SELECT id FROM contratos_alumnos)",
      );
      if (pBorrados > 0) {
        orfanosBorrados += pBorrados.toInt();
        debugPrint(
          '  ☢️ Purga Nuclear: Eliminados $pBorrados pagos sin contrato',
        );
      }

      final nBorrados = await txn.rawDelete(
        "DELETE FROM notas_operativas_contrato WHERE contrato_alumno_id NOT IN (SELECT id FROM contratos_alumnos)",
      );
      if (nBorrados > 0) {
        orfanosBorrados += nBorrados.toInt();
        debugPrint(
          '  ☢️ Purga Nuclear: Eliminadas $nBorrados notas operativas sin contrato',
        );
      }

      // 5. Limpiar la cola de sincronización (_sync_queue) de operaciones huérfanas
      final qBorrados = await txn.rawDelete(
        "DELETE FROM _sync_queue WHERE tabla = 'contratos_alumnos' AND registro_id NOT IN (SELECT id FROM contratos_alumnos)",
      );
      if (qBorrados > 0) {
        orfanosBorrados += qBorrados.toInt();
        debugPrint(
          '  ☢️ Purga Nuclear: Eliminadas $qBorrados operaciones de sync huérfanas',
        );
      }

      final qNotas = await txn.rawDelete(
        "DELETE FROM _sync_queue WHERE tabla = 'notas_operativas_contrato' AND registro_id NOT IN (SELECT id FROM notas_operativas_contrato)",
      );
      if (qNotas > 0) {
        orfanosBorrados += qNotas.toInt();
        debugPrint(
          '  ☢️ Purga Nuclear: Eliminadas $qNotas ops sync notas operativas huérfanas',
        );
      }

      // Permitir IDs de 36 chars (UUID) o 73 chars (clave compuesta uuid_uuid)
      // Eliminar todo lo que no cumpla ninguno de los dos formatos
      final bQueue = await txn.rawDelete(
        "DELETE FROM _sync_queue WHERE LENGTH(registro_id) != 36 AND LENGTH(registro_id) != 73",
      );

      if (bQueue > 0) {
        debugPrint(
          '  🧼 Saneada la cola de sync: $bQueue operaciones con IDs malformados eliminadas',
        );
      }
      totalBorrados += (bQueue.toInt() + orfanosBorrados);
    });

    if (totalBorrados > 0) {
      debugPrint(
        '✅ Saneamiento completo: $totalBorrados rastros de IDs corruptos eliminados',
      );
    } else {
      debugPrint('✅ Saneamiento: Base de datos limpia, sin IDs corruptos');
    }
  }
}

/// Provider global de la base de datos local.
final localDatabaseProvider = FutureProvider<Database>((ref) async {
  return LocalDatabase.instance;
});
