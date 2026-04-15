import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Base de datos local SQLite — persistencia offline.
///
/// Almacena en: Mis Documentos/JuniorEventos/data.db
/// Esquema espejo de Supabase para sincronización bidireccional.
class LocalDatabase {
  static Database? _db;
  static const String _dbName = 'data.db';
  static const int _version = 22;

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
    // ── BLINDAJE WEB/MOBILE ──────────────────────────────────────────────────
    // sqflite_common_ffi es SOLO para escritorio (Windows/Linux/macOS).
    // En Web o Móvil (Android/iOS) no se debe inicializar.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await dbPath;
    debugPrint('📦 SQLite DB path: $path');

    if (kIsWeb) {
      throw UnsupportedError('SQLite local no está soportado en entorno Web.');
    }

    return openDatabase(
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
        evento_id TEXT
      )
    ''');

    // ── Eventos ↔ Servicios ──────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE eventos_servicios (
        evento_id TEXT NOT NULL,
        servicio_id TEXT NOT NULL,
        precio_final_acordado REAL NOT NULL,
        cantidad REAL DEFAULT 1.0,
        grupo TEXT,
        detalle_servicio TEXT,
        PRIMARY KEY (evento_id, servicio_id),
        FOREIGN KEY (evento_id) REFERENCES eventos(id),
        FOREIGN KEY (servicio_id) REFERENCES servicios(id)
      )
    ''');

    // ── Transacciones (Ingresos) ─────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE transacciones (
        id TEXT PRIMARY KEY,
        evento_id TEXT NOT NULL,
        monto REAL NOT NULL,
        concepto TEXT,
        fecha_pago TEXT,
        created_by TEXT,
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
        FOREIGN KEY (evento_id) REFERENCES eventos(id)
      )
    ''');

    // ── Pagos Contrato Alumno ────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE pagos_contrato_alumno (
        id TEXT PRIMARY KEY,
        contrato_alumno_id TEXT NOT NULL,
        monto REAL NOT NULL,
        concepto TEXT DEFAULT 'Cuota Base',
        fecha_pago TEXT,
        created_at TEXT,
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
        presupuesto_id TEXT NOT NULL,
        servicio_id TEXT NOT NULL,
        precio_final REAL NOT NULL,
        cantidad REAL DEFAULT 1.0,
        detalle_servicio TEXT,
        PRIMARY KEY (presupuesto_id, servicio_id),
        FOREIGN KEY (presupuesto_id) REFERENCES presupuestos(id) ON DELETE CASCADE,
        FOREIGN KEY (servicio_id) REFERENCES servicios(id)
      )
    ''');

    // ── Metadatos de sync ────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE _sync_meta (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
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
          orfanosBorrados += count;
          debugPrint('  ☢️ Purga Nuclear: Eliminados $count huérfanos de $table (evento inexistente)');
        }
      }

      // Limpiar pagos sin contrato padre
      final pBorrados = await txn.rawDelete(
        "DELETE FROM pagos_contrato_alumno WHERE contrato_alumno_id NOT IN (SELECT id FROM contratos_alumnos)"
      );
      if (pBorrados > 0) {
        orfanosBorrados += pBorrados;
        debugPrint('  ☢️ Purga Nuclear: Eliminados $pBorrados pagos sin contrato');
      }

      // 5. Limpiar la cola de sincronización (_sync_queue) de operaciones huérfanas
      final qBorrados = await txn.rawDelete(
        "DELETE FROM _sync_queue WHERE tabla = 'contratos_alumnos' AND registro_id NOT IN (SELECT id FROM contratos_alumnos)"
      );
      if (qBorrados > 0) {
         orfanosBorrados += qBorrados;
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
      totalBorrados += (bQueue + orfanosBorrados);
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
