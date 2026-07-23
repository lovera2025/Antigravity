# Contexto — Junior Eventos v4.3.2 (16 de julio de 2026)

> **Referencia:** `CONTEXTO_v4.3.2` · `sorteo mesas alejadas` · `modo jefe` · `sesiones de caja` · **WIP**
> Si en un chat futuro decís *"leé el contexto del 16 de julio"* o *"qué hay en 4.3.2"*, apuntá a este archivo.
> Sesiones de caja / role gate: ver `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md`.

**Estado:** **SUPERSEDIDO** por **v4.5.0** (23-jul-2026) — ver `docs/CONTEXTO_v4.5.0_2026-07-23.md`.  
**Versión histórica:** **4.3.2+23** (WIP consolidado en 4.5.0+24).  
**Instalador vigente:** `Setup Junior Eventos v4.5.0.exe`.

---

## Resumen de lo agregado en estos últimos tiempos (rama + WIP)

### 1. Sorteo de mesas — juntas + alejadas por alumno (nuevo)

Reemplaza el flujo de **pares A ↔ B** en el diálogo de sorteo.

- Switch **“Separar mesas extras”**.
- Lista **solo alumnos con mesas extras** (`cantidadMesasFisicasSorteo > 1`).
- Checkbox + selector **cuántas mesas alejadas** (`1 .. físicas−1`), extras del contrato **solo lectura**.
- Motor: bloque consecutivo de `(N−K)` + `K` singles **lejos del bloque y entre sí** (no vecinos).
- Capacidad mínima: `demanda + sum(alejadas)`.
- Sin marcar → todas las mesas del alumno **juntas** (como antes).

**Archivos:** `sorteo_mesas_dialog.dart`, `mesas_extra_utils.dart` (`AlumnoMesasSeparadas`), cableado en `detalle_evento_masivo_screen.dart`, tests en `mesas_extra_utils_test.dart`.

### 2. Modo jefe / operativa (WIP)

- Dashboard: badge **MODO JEFE**, KPIs / QR pendiente condicionados al modo.
- Cierre de caja: restricción operativa al salir de modo jefe; fuerza jornada de hoy para operador.
- `admin_provider` / providers de caja alineados a ese flujo.

### 3. Conceptos de pago / cobro (WIP)

- `concepto_pago_display`: enriquecimiento de display, lotes mixtos efectivo/transferencia (E/T) en mismo minuto.
- Ajustes en `cobro_abono_acumulado`, `contratos_repository`, tests de conceptos / mora display.
- Local DB: migraciones / hardening pendientes de documentar caso a caso si se tocan schemas.

### 4. Sesiones de caja / roles (17-jul) — ver archivo dedicado

MVP en commit `10e00a5`: role gate (jefe/caja), `sesiones_caja` + `operadores_caja`, `sesion_caja_id` en cobros/egresos/cierre, sync operativo cada ~10s.

**Detalle completo:** `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md`  
**SQL Supabase:** `docs/sql_sesiones_caja_supabase.sql`

### 5. Versión

| Fecha | Versión | Notas |
|-------|---------|--------|
| 9-jul-2026 | **4.3.0** | Perdón mora admin + fecha presupuesto |
| 10-jul-2026 | **4.3.1** | Perdón solo ficha + fix PDF previo cobro |
| 16-jul-2026 | **4.3.2** | **WIP** — sorteo alejadas + modo jefe + conceptos |
| 17-jul-2026 | **4.3.2+23** | Sesiones de caja + role gate (sin bump de release) |

Referencias previas: `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md`, `docs/CONTEXTO_v4.3.1_2026-07-10.md`, `docs/CONTEXTO_v4.3.0_2026-07-09.md`, `docs/CONTEXTO_MORA_OPERATIVA.md`.

---

## Pendiente / sigue en curso

> Release **4.5.0** cerró el bump de instalador. Pendientes operativos:

- Smoke real en oficina: role gate / abrir-cerrar / sync jefe↔caja (SQL Supabase aplicado).
- Confirmar que el sorteo con salón agujereado / muchos separados no degrada UX.
- No mezclar en este contexto: carpetas `releases/`, `installer/output/`, scripts `tool/` temporales ni `.bak`.

---

## Cómo seguir en el próximo chat

1. Preferir `CONTEXTO_v4.5.0_2026-07-23.md` + `CONTEXTO_SESIONES_CAJA_2026-07-17` si tocás caja/roles; + `CONTEXTO_v4.3.1` si hace falta mora/perdón.
2. Este archivo queda como bitácora del WIP 4.3.2.
3. Cambios de sorteo: partir de `AlumnoMesasSeparadas` / `asignarMesasSorteo(separaciones: ...)`.
4. Cambios de caja: partir de `appRoleProvider` / `SesionesCajaRepository`.
