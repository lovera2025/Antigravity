# Contexto — Sesiones de caja / roles operativos (17 de julio de 2026)

> **Referencia:** `CONTEXTO_SESIONES_CAJA` · `role gate` · `sesion_caja_id`
> Si en un chat futuro decís *"leé el contexto de sesiones de caja"*, *"role gate"* o *"caja vs jefe"*, apuntá a este archivo.

**Estado:** implementado en rama `feature/optimizacion-finanzas` (commit `10e00a5`+).  
**Versión app:** **4.5.1+25** (release 23-jul-2026; ver `docs/CONTEXTO_v4.5.1_2026-07-23.md`).  
**SQL remoto:** `docs/sql_sesiones_caja_supabase.sql` (ejecutar en Supabase si aún no está).

---

## Qué se hizo

### 1. Roles post-login (Jefe / Caja)

- Tras auth Supabase, si no hay rol → `RoleGateScreen` (PIN maestro = jefe, PIN operador = caja).
- `AppRoleKind`: `none` | `jefe` | `caja` (`app_role_provider.dart`).
- Caja sin sesión abierta obliga a abrir caja o vuelve al gate.
- Heartbeat de sesión + `device_id` en prefs (`caja_device_id`).

### 2. Feature `lib/features/caja_sesiones/`

- Modelos: `OperadorCaja`, `SesionCaja`.
- Repos locales + sync: operadores y sesiones.
- UI: abrir/cerrar caja, operadores, chip de estado, role gate.
- `CajaAutoSyncService`: sync corto cuando hay sesión de caja activa.

### 3. Persistencia local (migración v64+)

- Tablas `operadores_caja` y `sesiones_caja`.
- Índice único parcial: **una sola sesión abierta por operador**.
- `sesion_caja_id` en: pagos, egresos, guía de cambio, anotaciones de cierre.
- Anotaciones: unique por `sesion_caja_id` (ya no solo fecha+turno).

### 4. Supabase (espejo)

- Mismas tablas/columnas e índices (ver SQL doc).
- Normalización de sesiones abiertas duplicadas + unique parcial.
- Sin CHECK estricto de etiqueta (compat con clientes viejos).

### 5. Cierre de caja integrado a sesión

- Se eliminó `turno_cierre_selector.dart`.
- Turno/vista derivado de la sesión (`etiqueta` Mañana/Tarde) o consolidado en jefe.
- Retiros / guía / anotaciones llevan `sesion_caja_id`.

### 6. Sync operativo caja ↔ jefe

- `OperationalSyncCoordinator` en `main` (tick ~10s, foco/ventana).
- Solo actúa con rol operativo elegido; bump de revisión para refrescar dashboard/finanzas.

### 7. Cobros / egresos / finanzas / masivos

- Pagos y egresos pueden asociarse a `sesion_caja_id`.
- Dashboard/finanzas/eventos masivos alineados a rol y sesión (bloqueos si caja sin sesión).

---

## Archivos clave

- `lib/features/caja_sesiones/**`
- `lib/features/common/widgets/operational_sync_coordinator.dart`
- `lib/main.dart` (RoleGate + coordinator)
- `lib/core/database/local_database.dart` (v64+)
- `lib/core/services/sync_engine.dart`
- `lib/features/cierre_caja/**`
- `docs/sql_sesiones_caja_supabase.sql`

---

## Pendiente / smoke

- Ejecutar SQL en Supabase en cada entorno.
- Smoke real: abrir/cerrar caja, 2 operadores, sync jefe↔caja, cierre PDF.
- Confirmar que no queden sesiones abiertas duplicadas tras fallos de red.
- No commitear `releases/`, `installer/output/`, `tool/` temporales ni `.bak`.

---

## Cómo seguir

1. Leer este archivo + `CONTEXTO_v4.5.1_2026-07-23.md` (release) o `CONTEXTO_v4.5.0` / `CONTEXTO_v4.3.2` si hace falta historial.
2. Cambios de caja: partir de `appRoleProvider` / `SesionesCajaRepository`.
3. Schema remoto: solo aditivo vía el SQL doc.
