import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/sqflite.dart' show databaseFactory;
import 'package:sqflite/sqflite.dart' as sqflite_mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/pago_interes_mora.dart';
import '../utils/uuid_utils.dart';

/// Base de datos local SQLite — persistencia offline.
///
/// Almacena en: Mis Documentos/JuniorEventos/data.db
/// Esquema espejo de Supabase para sincronización bidireccional.
class LocalDatabase {
  static Database? _db;
  static const String _dbName = 'data.db';
  static const int _version = 40;

  /// Singleton de acceso a la base de datos.
  static Future<Database> get instance async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<String> get dbPath async {
    // Almacenar en Mis Documentos/JuniorEventos/
    final docsDir = await getApplicationDocumentsDirectory();
    final appDir = Directory('${docsDir.path}${Platform.pathSeparator}JuniorEventos');
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
        created_at TEXT
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
        bonificacion_global_pct REAL,
        created_at TEXT,
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
        is_archived INTEGER DEFAULT 0
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
        PRIMARY KEY (id),
        FOREIGN KEY (evento_id) REFERENCES eventos(id),
        FOREIGN KEY (servicio_id) REFERENCES servicios(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_es_evento ON eventos_servicios(evento_id)');

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
        sillas_extra_pagado REAL DEFAULT 0.0,
        curso_division TEXT,
        musica_elegida TEXT,
        numero_mesa TEXT,
        telefono TEXT,
        porcentaje_descuento REAL DEFAULT 0.0,
        created_at TEXT,
        contrato_firmado INTEGER DEFAULT 0,
        mora_pendiente_tracked REAL DEFAULT 0.0,
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
        FOREIGN KEY (contrato_alumno_id) REFERENCES contratos_alumnos(id)
      )
    ''');

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
        created_at TEXT
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
        created_by TEXT
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
        notificado_vencimiento INTEGER DEFAULT 0,
        created_at TEXT,
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
        PRIMARY KEY (id),
        FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
        FOREIGN KEY (servicio_id) REFERENCES servicios(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_ps_presupuesto ON presupuesto_servicios(presupuesto_id)');

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
        created_at TEXT
      )
    ''');

    // ── Caja fuerte (cupos declarados por el dueño; local-only, sin sync) ────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS caja_fuerte_movimientos (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        monto REAL NOT NULL,
        nota TEXT,
        created_at TEXT NOT NULL
      )
    ''');

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
    await db.execute('CREATE INDEX idx_transacciones_evento ON transacciones(evento_id)');
    await db.execute('CREATE INDEX idx_egresos_evento ON egresos(evento_id)');
    await db.execute('CREATE INDEX idx_contratos_evento ON contratos_alumnos(evento_id)');
    await db.execute('CREATE INDEX idx_pagos_contrato ON pagos_contrato_alumno(contrato_alumno_id)');
    await db.execute('CREATE INDEX idx_invitados_evento ON invitados(evento_id)');
    await db.execute('CREATE INDEX idx_sync_queue_tabla ON _sync_queue(tabla)');
    await db.execute('CREATE INDEX idx_prestamos_cliente ON prestamos_alquiler(cliente_id)');
    await db.execute('CREATE INDEX idx_prestamos_visible ON prestamos_alquiler(visible_listado)');
    await db.execute('CREATE INDEX idx_lineas_prestamo ON prestamo_alquiler_lineas(prestamo_id)');
    await db.execute('CREATE INDEX idx_pagos_prestamo ON pagos_prestamo_alquiler(prestamo_id)');

    await db.execute('CREATE INDEX idx_caja_fuerte_created ON caja_fuerte_movimientos(created_at)');

    debugPrint('✅ Esquema SQLite creado exitosamente');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
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
          await txn.execute('CREATE INDEX idx_egresos_evento ON egresos(evento_id)');
        });
      } catch (e) {
        debugPrint('  ❌ Error migrando tabla egresos: $e');
      }
      
      debugPrint('✅ Migración v2 completada');
    }

    if (oldVersion < 3) {
      debugPrint('  🔧 Aplicando migración v3...');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_precio REAL DEFAULT 0.0');
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_cuotas INTEGER DEFAULT 1');
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_cantidad INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_precio_total REAL DEFAULT 0.0');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columnas de extras a contratos_alumnos: $e');
      }
      debugPrint('✅ Migración v3 completada');
    }

    if (oldVersion < 4) {
      debugPrint('  🔧 Aplicando migración v4...');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN curso_division TEXT');
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN musica_elegida TEXT');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columnas curso_division y musica_elegida a contratos_alumnos: $e');
      }
      debugPrint('✅ Migración v4 completada');
    }

    if (oldVersion < 5) {
      debugPrint('  🔧 Aplicando migración v5...');
      try {
        await db.execute("ALTER TABLE pagos_contrato_alumno ADD COLUMN concepto TEXT DEFAULT 'Cuota Base'");
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columna concepto a pagos_contrato_alumno: $e');
      }
      debugPrint('✅ Migración v5 completada');
    }

    if (oldVersion < 6) {
      debugPrint('  🔧 Aplicando migración v6...');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN numero_mesa TEXT');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columna numero_mesa a contratos_alumnos: $e');
      }
      debugPrint('✅ Migración v6 completada');
    }

    if (oldVersion < 7) {
      debugPrint('  🔧 Aplicando migración v7...');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_cuotas_pagadas INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_cuotas_pagadas INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columnas de cuotas extras pagadas a contratos_alumnos: $e');
      }
      debugPrint('✅ Migración v7 completada');
    }

    if (oldVersion < 8) {
      debugPrint('  🔧 Aplicando migración v8...');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN telefono TEXT');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columna telefono a contratos_alumnos: $e');
      }
      debugPrint('✅ Migración v8 completada');
    }

    if (oldVersion < 9) {
      debugPrint('  🔧 Aplicando migración v9...');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN mesa_extra_pagado REAL DEFAULT 0.0');
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_pagado REAL DEFAULT 0.0');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columnas mesa_extra_pagado y sillas_extra_pagado a contratos_alumnos: $e');
      }
      debugPrint('✅ Migración v9 completada');
    }

    if (oldVersion < 10) {
      debugPrint('  🔧 Aplicando migración v10...');
      try {
        await db.execute('ALTER TABLE eventos ADD COLUMN observaciones TEXT');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columna observaciones a eventos: $e');
      }
      debugPrint('✅ Migración v10 completada');
    }

    if (oldVersion < 11) {
      debugPrint('  🔧 Aplicando migración v11...');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN sillas_extra_cuotas INTEGER DEFAULT 1');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columna sillas_extra_cuotas a contratos_alumnos: $e');
      }
      debugPrint('✅ Migración v11 completada');
    }

    if (oldVersion < 12) {
      debugPrint('  🔧 Aplicando migración v12...');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN porcentaje_descuento REAL DEFAULT 0.0');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columna porcentaje_descuento a contratos_alumnos: $e');
      }
      debugPrint('✅ Migración v12 completada');
    }

    if (oldVersion < 13) {
      debugPrint('  🔧 Aplicando migración v13 (Persistencia de descuentos)');
      try {
        await db.execute('ALTER TABLE pagos_contrato_alumno ADD COLUMN monto_gross REAL');
        await db.execute('ALTER TABLE pagos_contrato_alumno ADD COLUMN descuento_porcentaje REAL DEFAULT 0.0');
        
        // Actualizar datos existentes para que monto_gross = monto inicial
        await db.execute('UPDATE pagos_contrato_alumno SET monto_gross = monto WHERE monto_gross IS NULL');
        
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
        await db.execute("ALTER TABLE servicios ADD COLUMN categoria TEXT DEFAULT 'General'");
        await db.execute("ALTER TABLE servicios ADD COLUMN costo_interno REAL DEFAULT 0.0");
        debugPrint('✅ Migración v15 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v15: $e');
      }
    }
    if (oldVersion < 16) {
      debugPrint('  🔧 Aplicando migración v16 (Servicios Personalizados y Cantidades)');
      try {
        await db.execute('ALTER TABLE servicios ADD COLUMN evento_id TEXT');
        await db.execute('ALTER TABLE eventos_servicios ADD COLUMN cantidad REAL DEFAULT 1.0');
        await db.execute('ALTER TABLE presupuesto_servicios ADD COLUMN cantidad REAL DEFAULT 1.0');
        debugPrint('✅ Migración v16 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v16: $e');
      }
    }
    if (oldVersion < 17) {
      debugPrint('  🔧 Aplicando migración v17 (Identidad del Emisor)');
      try {
        await db.execute('ALTER TABLE presupuestos ADD COLUMN vendedor_nombre TEXT');
        debugPrint('✅ Migración v17 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v17: $e');
      }
    }
    if (oldVersion < 18) {
      debugPrint('  🔧 Aplicando migración v18 (Oratoria del Evento)');
      try {
        await db.execute('ALTER TABLE presupuestos ADD COLUMN titulo_festejado TEXT');
        debugPrint('✅ Migración v18 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v18: $e');
      }
    }
    if (oldVersion < 19) {
      debugPrint('  🔧 Aplicando migración v19 (Archivado de Clientes)');
      try {
        await db.execute('ALTER TABLE clientes ADD COLUMN is_archived INTEGER DEFAULT 0');
        debugPrint('✅ Migración v19 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v19: $e');
      }
    }
    if (oldVersion < 20) {
      debugPrint('  🔧 Aplicando migración v20 (Agrupación de Servicios)');
      try {
        await db.execute('ALTER TABLE presupuesto_servicios ADD COLUMN grupo TEXT');
        await db.execute('ALTER TABLE eventos_servicios ADD COLUMN grupo TEXT');
        debugPrint('✅ Migración v20 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v20: $e');
      }
    }

    if (oldVersion < 22) {
      debugPrint('  🔧 Aplicando migración v22 (Descripción Técnica en Eventos)');
      try {
        await db.execute('ALTER TABLE eventos_servicios ADD COLUMN detalle_servicio TEXT');
        debugPrint('✅ Migración v22 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v22: $e');
      }
    }

    if (oldVersion < 23) {
      debugPrint('  🔧 Aplicando migración v23 (Archivado de Servicios)');
      try {
        await db.execute('ALTER TABLE servicios ADD COLUMN is_archived INTEGER DEFAULT 0');
        debugPrint('✅ Migración v23 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: is_archived ya existía o error al añadir: $e');
      }
    }

    if (oldVersion < 24) {
      debugPrint('  🔧 Aplicando migración v24 (grupo en presupuesto_servicios — BDs nuevas sin v20)');
      try {
        await db.execute('ALTER TABLE presupuesto_servicios ADD COLUMN grupo TEXT');
        debugPrint('✅ Migración v24 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: grupo ya existía o error al añadir: $e');
      }
    }

    if (oldVersion < 25) {
      debugPrint('  🔧 Aplicando migración v25 (Bonificación global % sobre presupuesto del evento)');
      try {
        await db.execute('ALTER TABLE eventos ADD COLUMN bonificacion_global_pct REAL');
        debugPrint('✅ Migración v25 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir bonificacion_global_pct a eventos: $e');
      }
    }

    if (oldVersion < 26) {
      debugPrint('  🔧 Aplicando migración v26 (Orden de combo en presupuesto/evento)');
      try {
        await db.execute('ALTER TABLE eventos_servicios ADD COLUMN combo_orden INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE presupuesto_servicios ADD COLUMN combo_orden INTEGER DEFAULT 0');
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
        await db.execute('CREATE INDEX IF NOT EXISTS idx_prestamos_cliente ON prestamos_alquiler(cliente_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_prestamos_visible ON prestamos_alquiler(visible_listado)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_lineas_prestamo ON prestamo_alquiler_lineas(prestamo_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pagos_prestamo ON pagos_prestamo_alquiler(prestamo_id)');
        debugPrint('✅ Migración v27 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v27: $e');
      }
    }

    if (oldVersion < 28) {
      debugPrint('  🔧 Aplicando migración v28 (pagos_contrato_alumno: gross/descuento en BDs nuevas sin v13)');
      try {
        try {
          await db.execute('ALTER TABLE pagos_contrato_alumno ADD COLUMN monto_gross REAL');
        } catch (e) {
          debugPrint('  ⚠️ Nota: monto_gross ya existía o error al añadir: $e');
        }
        try {
          await db.execute('ALTER TABLE pagos_contrato_alumno ADD COLUMN descuento_porcentaje REAL DEFAULT 0.0');
        } catch (e) {
          debugPrint('  ⚠️ Nota: descuento_porcentaje ya existía o error al añadir: $e');
        }
        await db.execute('UPDATE pagos_contrato_alumno SET monto_gross = monto WHERE monto_gross IS NULL');
        debugPrint('✅ Migración v28 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v28: $e');
      }
    }

    if (oldVersion < 29) {
      debugPrint('  🔧 Aplicando migración v29 (Clasificación de Medios de Pago)');
      try {
        try {
          await db.execute('ALTER TABLE transacciones ADD COLUMN medio_pago TEXT');
        } catch (e) { debugPrint('  ⚠️ Nota: error al añadir medio_pago a transacciones: $e'); }
        
        try {
          await db.execute('ALTER TABLE pagos_contrato_alumno ADD COLUMN medio_pago TEXT');
        } catch (e) { debugPrint('  ⚠️ Nota: error al añadir medio_pago a pagos_contrato_alumno: $e'); }
        
        try {
          await db.execute('ALTER TABLE pagos_prestamo_alquiler ADD COLUMN medio_pago TEXT');
        } catch (e) { debugPrint('  ⚠️ Nota: error al añadir medio_pago a pagos_prestamo_alquiler: $e'); }
        
        try {
          await db.execute('ALTER TABLE egresos ADD COLUMN medio_pago TEXT');
        } catch (e) { debugPrint('  ⚠️ Nota: error al añadir medio_pago a egresos: $e'); }

        debugPrint('✅ Migración v29 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v29: $e');
      }
    }

    if (oldVersion < 31) {
      debugPrint('  🔧 Aplicando migración v30/v31 (fecha_evento en presupuestos)');
      try {
        try {
          await db.execute('ALTER TABLE presupuestos ADD COLUMN fecha_evento TEXT');
        } catch (e) { debugPrint('  ⚠️ Nota: error al añadir fecha_evento a presupuestos: $e'); }
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
      debugPrint('  🔧 Aplicando migración v34 (Sistema de Avisos y Reminders)');
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
      debugPrint('  🔧 Aplicando migración v35 (líneas de presupuesto: id propio, mismo servicio varias veces)...');
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
          await txn.execute('CREATE INDEX IF NOT EXISTS idx_es_evento ON eventos_servicios(evento_id)');

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
          await txn.execute('CREATE INDEX IF NOT EXISTS idx_ps_presupuesto ON presupuesto_servicios(presupuesto_id)');
        });
        debugPrint('✅ Migración v35 completada');
      } catch (e) {
        debugPrint('  ❌ Error en migración v35: $e');
      }
    }

    if (oldVersion < 36) {
      debugPrint('  🔧 Aplicando migración v36 (contrato_firmado en contratos_alumnos)');
      try {
        await db.execute('ALTER TABLE contratos_alumnos ADD COLUMN contrato_firmado INTEGER DEFAULT 0');
        debugPrint('✅ Migración v36 completada');
      } catch (e) {
        debugPrint('  ⚠️ Nota: error al añadir columna contrato_firmado: $e');
      }
    }

    if (oldVersion < 37) {
      debugPrint('  🔧 Aplicando migración v37 (anulación no destructiva de cobros)');
      try {
        for (final t in ['transacciones', 'pagos_contrato_alumno', 'pagos_prestamo_alquiler']) {
          try {
            await db.execute('ALTER TABLE $t ADD COLUMN anulado INTEGER DEFAULT 0');
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
      debugPrint('  🔧 Aplicando migración v38 (line_kind en pagos_contrato_alumno)');
      try {
        try {
          await db.execute(
              'ALTER TABLE pagos_contrato_alumno ADD COLUMN line_kind TEXT');
        } catch (e) {
          debugPrint('  ⚠️ Nota: line_kind en pagos_contrato_alumno: $e');
        }
        final rows =
            await db.query('pagos_contrato_alumno', columns: ['id', 'concepto']);
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
      'pagos_contrato_alumno', 'contratos_alumnos', 'transacciones',
      'egresos', 'eventos_servicios', 'solicitudes_cotizacion',
      'accesos', 'invitados', 'eventos', 'clientes',
      '_sync_queue', '_sync_meta',
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
      'clientes', 'eventos', 'servicios', 'eventos_servicios', 
      'transacciones', 'egresos', 'contratos_alumnos', 
      'pagos_contrato_alumno', 'invitados', 'accesos', 'solicitudes_cotizacion'
    ];

    int totalBorrados = 0;

    await db.transaction((txn) async {
      for (final table in tables) {
        final columns = await txn.rawQuery('PRAGMA table_info($table)');
        final hasId = columns.any((c) => c['name'] == 'id');
        final hasEventoId = columns.any((c) => c['name'] == 'evento_id');
        final hasContratoId = columns.any((c) => c['name'] == 'contrato_alumno_id');

        int b1 = 0, b2 = 0, b3 = 0;

        // 1. Borrar por ID malformado (cualquier ID que no sea UUID de 36 chars o sea la palabra "null")
        if (hasId) {
          b1 = await txn.delete(table, 
            where: "id IS NOT NULL AND (LENGTH(id) != 36 OR id = 'null')");
        }
        
        // 2. Borrar por evento_id malformado
        if (hasEventoId) {
          b2 = await txn.delete(table, 
            where: "evento_id IS NOT NULL AND (LENGTH(evento_id) != 36 OR evento_id = 'null')");
        }

        // 3. Borrar por contrato_alumno_id malformado
        if (hasContratoId) {
          b3 = await txn.delete(table, 
            where: "contrato_alumno_id IS NOT NULL AND (LENGTH(contrato_alumno_id) != 36 OR contrato_alumno_id = 'null')");
          if (b3 > 0) debugPrint('  🧼 Saneados $b3 registros de $table (contrato_alumno_id malformado)');
        }
        
        totalBorrados += (b1 + b2 + b3);
        if (b1 + b2 > 0) {
          debugPrint('  🧼 Saneados ${b1 + b2} registros de $table');
        }
      }
      
      // 4. LIMPIEZA NUCLEAR DE HUÉRFANOS (Registros que apuntan a eventos inexistentes)
      // Esto elimina el ruido de sincronización de eventos borrados
      final tablesToCleanup = ['contratos_alumnos', 'transacciones', 'egresos', 'invitados', 'servicios'];
      int orfanosBorrados = 0;
      
      for (final table in tablesToCleanup) {
        // En servicios, solo borramos los que tienen evento_id (los globales tienen NULL)
        final count = await txn.rawDelete(
          "DELETE FROM $table WHERE evento_id IS NOT NULL AND evento_id NOT IN (SELECT id FROM eventos)"
        );
        if (count > 0) {
          orfanosBorrados += count.toInt();
          debugPrint('  ☢️ Purga Nuclear: Eliminados $count huérfanos de $table (evento inexistente)');
        }
      }

      // Limpiar pagos sin contrato padre
      final pBorrados = await txn.rawDelete(
        "DELETE FROM pagos_contrato_alumno WHERE contrato_alumno_id NOT IN (SELECT id FROM contratos_alumnos)"
      );
      if (pBorrados > 0) {
        orfanosBorrados += pBorrados.toInt();
        debugPrint('  ☢️ Purga Nuclear: Eliminados $pBorrados pagos sin contrato');
      }

      // 5. Limpiar la cola de sincronización (_sync_queue) de operaciones huérfanas
      final qBorrados = await txn.rawDelete(
        "DELETE FROM _sync_queue WHERE tabla = 'contratos_alumnos' AND registro_id NOT IN (SELECT id FROM contratos_alumnos)"
      );
      if (qBorrados > 0) {
         orfanosBorrados += qBorrados.toInt();
         debugPrint('  ☢️ Purga Nuclear: Eliminadas $qBorrados operaciones de sync huérfanas');
      }

      // Permitir IDs de 36 chars (UUID) o 73 chars (clave compuesta uuid_uuid)
      // Eliminar todo lo que no cumpla ninguno de los dos formatos
      final bQueue = await txn.rawDelete(
        "DELETE FROM _sync_queue WHERE LENGTH(registro_id) != 36 AND LENGTH(registro_id) != 73"
      );
        
      if (bQueue > 0) {
        debugPrint('  🧼 Saneada la cola de sync: $bQueue operaciones con IDs malformados eliminadas');
      }
      totalBorrados += (bQueue.toInt() + orfanosBorrados);
    });
    
    if (totalBorrados > 0) {
      debugPrint('✅ Saneamiento completo: $totalBorrados rastros de IDs corruptos eliminados');
    } else {
      debugPrint('✅ Saneamiento: Base de datos limpia, sin IDs corruptos');
    }
  }
}

/// Provider global de la base de datos local.
final localDatabaseProvider = FutureProvider<Database>((ref) async {
  return LocalDatabase.instance;
});
