# Contexto — Fix sync, mesas y carpeta (v4.1.6 → v4.1.7)

> **Referencia para Cursor / equipo:** `incidente sync 24-jun-2026` · `CONTEXTO_SYNC_v4.1.6` · `fix cobro PDF/UI 25-jun-2026`  
> Si en un chat futuro decís *“leé el contexto del 24 de junio”*, *“el incidente sync v4.1.6”* o *“fix cobro mesas 25-jun-2026”*, apuntá a este archivo.

**Última actualización:** **Miércoles 25 de junio de 2026, 13:00** (hora local PC de build)  
**Versión actual recomendada:** **4.1.7+10**  
**Instalador:** `installer/dist/Setup Junior Eventos v4.1.7.exe` · copia en `releases/v4.1.7/`  
**Rama:** `feature/optimizacion-finanzas`  
**Archivo:** `docs/CONTEXTO_SYNC_v4.1.6.md`

---

## Actualización 25-jun-2026 (v4.1.7) — PDF ≠ UI al cobrar mesas/cuotas

**Fecha y hora del fix y release:** **25/06/2026, ~13:00**

### Problema reportado

- Alumno (ej. Santino): cobró **cuota base** y **mesa extra**; el **PDF/recibo salía bien** pero la **grilla “Estado de deuda”** no actualizaba (cuotas base `(1/9)` en vez de `(3/9)`, mesa sin `3/7`).
- Tras intentar “salvar” **editando el contrato**, los datos empeoraron.
- Consola Windows con spam `Failed to update ui::AXTree` (accesibilidad Flutter; no es la causa del dato malo).

### Causa raíz

1. **Dos fuentes de verdad:** el PDF usaba clon optimista del modal (`skipDbRefresh: true`); la UI se refrescaba desde SQLite tras persistencia distinta.
2. **`directUpdates` post-cobro** pisaba `cuotas_pagadas` / `mesa_extra_cuotas_pagadas` con valores **congelados al abrir el modal**, contradiciendo `recalcularProgresoContrato`.
3. **`mesas_extra_estado`** no se persistía igual que el preview; solo `reconciliarMesasEstadoContrato`, con FIFO erróneo si el concepto no tenía `Mesa Extra N`.
4. **Auditoría silenciosa de todo el evento** tras cada cobro competía con el patch optimista.
5. Grilla con **3+ mesas** ocultaba progreso `X/7` (solo deuda total).

### Solución técnica (v4.1.7)

| Archivo | Cambio |
|---------|--------|
| `detalle_evento_masivo_screen.dart` | Conceptos persistidos con `Mesa Extra N`; sin overwrite manual de contadores; JSON mesas alineado al PDF; refresh vía `getContratoById` (sin auditoría masiva post-cobro) |
| `mesas_extra_utils.dart` | `conceptoPagoPersistido`, reconciliación mesa 1 explícita, grilla con `Mesa N · X/7` |
| `contratos_repository.dart` | Detección pagos numerados incluye mesa 1 |
| `test/mesas_extra_utils_test.dart` | Tests nuevos |
| `pubspec.yaml` + `.iss` | Versión **4.1.7+10** |

### Operación post-instalación 4.1.7

1. Instalar **`Setup Junior Eventos v4.1.7.exe`** en **cada PC** que cobre.
2. En eventos con datos viejos: **Auditar y Sincronizar DB** (una vez).
3. **Cobrar** por el modal normal; **no** “salvar” editando contrato después de un cobro.
4. Sync entre PCs: igual que siempre — **Subir pendientes** / **Bajar cambios**.

### Build instalador

```powershell
.\installer\build_installer.ps1
```

Salida: `installer\dist\Setup Junior Eventos v4.1.7.exe`

---

## Incidente original — 24-jun-2026 (v4.1.6)

**Fecha del incidente y fix:** **Miércoles 24 de junio de 2026**  
**Versión:** 4.1.6+9  
**Instalador:** `installer/dist/Setup Junior Eventos v4.1.6.exe`  
**Commits:** `4966057` (fix código) · `e3c8b0f` (este doc)

Este documento queda en el repositorio (Git) para que cualquier persona del equipo — o el asistente en Cursor — sepa qué pasó ese día, qué se corrigió y cómo operar la app con dos PCs.

---

## Resumen (24-jun-2026)

La app **Junior Eventos** es offline-first: guarda todo en SQLite local (`Mis Documentos/Junior Eventos/data.db`) y sincroniza manualmente con Supabase. Se usa en **dos o más PCs** a la vez (oficina + notebook en escuelas).

**Ese día (24/06/2026)** aparecieron y se resolvieron problemas graves de sync y de cálculo de mesas extra. Se corrigieron en código, se recuperaron datos desde un backup local viejo (`data.db`), se subió a Supabase y se publicó el instalador **4.1.6**.

---

## Problemas que reportamos

### 1. Pagos no aparecían en la otra PC (CRÍTICO)

**Síntoma:** Un cliente pagaba en la PC A; en la PC B no figuraba el pago. Alumnos como Acosta Ángeles tenían pagos en local pero la otra máquina o Supabase no los reflejaban bien.

**Causa:**
- Al registrar un pago, `registrarPago()` guardaba `created_at` pero **no** `updated_at`.
- El motor de sync incremental (`sync_engine.dart`) filtra con `WHERE updated_at > last_pull`.
- Pagos con `updated_at = NULL` **nunca entraban** al pull incremental.
- Además, al bajar pagos desde Supabase, el batch insert **no guardaba** `updated_at` en SQLite local.

### 2. Pull traía solo 1000 pagos

**Síntoma:** Tras “bajar todo”, el log mostraba `pagos_contrato_alumno: 1000 registros` aunque en Supabase había más (~1400+).

**Causa:** Supabase PostgREST devuelve máximo **1000 filas por request**. `_pullTable()` hacía una sola consulta sin paginar.

### 3. Mesa 2 se liquidaba junto con Mesa 1

**Síntoma:** Contrato con 2 mesas extra (ej. $1000 c/u, 7 cuotas por mesa). Al liquidar Mesa 1, Mesa 2 quedaba mal o “liquidada”.

**Causa:**
- `cuotaPuraMesa` usaba `mesaExtraPrecio / mesaExtraCuotas` (precio **total** de todas las mesas) en vez del precio **unitario por mesa** (`precioUnitarioMesaExtra`).
- El clamp de `cuotasMesaCount` no multiplicaba por `mesaExtraCantidad`.

### 4. Dos carpetas en Documentos

**Síntoma:** En “Mis Documentos” aparecían `JuniorEventos` y `Junior Eventos`.

**Causa:**
- `local_database.dart` usaba `JuniorEventos` (sin espacio).
- `pdf_service.dart` usaba `Junior Eventos` (con espacio).

### 5. Recuperación de datos (incidente operativo)

**Qué pasó:**
- Se movió/borró la carpeta local de Documentos en una PC.
- Se hizo pull desde Supabase pero faltaban pagos (límite 1000 + pagos nunca subidos).
- Un backup **`data.db` viejo** tenía datos correctos (ej. Acosta Ángeles con 3 cuotas pagadas) que no estaban completos en la nube.

**Recuperación:**
1. Restaurar `data.db` viejo en `Mis Documentos/Junior Eventos/data.db`.
2. **Subir pendientes** (subió contratos + pagos; hubo errores FK temporales resueltos por self-healing del sync).
3. **Pull completo forzado** con paginación → 1386+ pagos bajados.

---

## Solución técnica (archivos modificados)

| Archivo | Cambio |
|---------|--------|
| `lib/features/eventos/repositories/contratos_repository.dart` | `updated_at` en `pagoData` y en pull de pagos; fix `cuotaPuraMesa` y clamp; `reconciliarMesasLegacyPendientesEvento` tras pull de contratos |
| `lib/core/database/local_database.dart` | Carpeta única `Junior Eventos`; migración automática de `JuniorEventos/data.db` |
| `lib/core/services/sync_engine.dart` | Paginación en `_pullTable`; `resetPullTimestamps()` y `forceFullPull()` |
| `lib/features/common/widgets/sync_menu_sheet.dart` | Botón “Pull completo forzado”; texto UI actualizado |
| `pubspec.yaml` + `.iss` | Versión **4.1.6** |

---

## Cómo funciona el sync (importante)

- **No hay sync automático** al abrir la app ni al cambiar de pantalla.
- Todo es **manual** desde el ícono de nube:
  - **Subir pendientes** → local → Supabase
  - **Bajar cambios** → Supabase → local (incremental si ya hubo pull antes)
  - **Pull completo forzado** → borra timestamps de última bajada y trae **todo** (paginado)
  - **Verificar nube** → solo cuenta; **no descarga**

Cada pago tiene un **`id` UUID único**. Al bajar se hace `REPLACE`, no se duplican filas con el mismo id.

---

## Flujo operativo diario (2 PCs)

| Dónde | Qué hacer |
|-------|-----------|
| PC donde se cobra/edita | Al terminar: **Subir pendientes** |
| La otra PC | **Bajar cambios** |
| PC nueva o vacía | Instalar **4.1.7** → **Pull completo forzado** |
| Notebook a la escuela | Opcional: borrar carpetas en Documentos → **Pull completo forzado** → cobrar → al volver **Subir pendientes** |

### No hacer

- Borrar `Mis Documentos/Junior Eventos` **sin subir antes** (se pierden cobros locales).
- Instalar exe **viejo** (vuelven los bugs).
- **Pull completo forzado** todos los días sin necesidad (solo recuperación o PC limpia).

---

## Guía rápida si vuelve a pasar algo

| Síntoma | Qué hacer |
|---------|-----------|
| Pagó en PC A, no aparece en B | PC A: **Subir pendientes** → PC B: **Bajar cambios** |
| Pull trae ~1000 pagos y faltan | Actualizar a **4.1.7+** → **Pull completo forzado** |
| Dos carpetas en Documentos | Instalar **4.1.7** en todas las PCs; usar solo `Junior Eventos`; borrar `JuniorEventos` vacía si queda |
| Liquidar Mesa 1 afecta Mesa 2 | Actualizar a **4.1.7**; revisar contrato en app |
| PDF bien pero grilla no actualiza mesa/cuota | Actualizar a **4.1.7**; auditar evento; no editar contrato para “salvar” |
| PC sin datos | **Pull completo forzado** (no hace falta “Verificar nube” antes) |
| Datos solo en backup `data.db` | Copiar backup → `Junior Eventos/data.db` → **Subir pendientes** → **Pull completo forzado** |

---

## Instalación / actualización

1. Ejecutar `Setup Junior Eventos v4.1.7.exe` en **cada PC**.
2. Misma versión en oficina, segunda PC y notebook.
3. El instalador compilado **no está en Git** (solo el script); se genera con:
   ```powershell
   .\installer\build_installer.ps1
   ```
   Salida: `installer\dist\Setup Junior Eventos v4.1.7.exe`

---

## Dónde vive este documento

- **En Git:** `docs/CONTEXTO_SYNC_v4.1.6.md` — para el equipo y futuras sesiones de desarrollo.
- **Local:** el mismo archivo en tu clone del repo; no hace falta copia aparte salvo que quieras imprimirlo en oficina.

---

## Contacto / mantenimiento

Si aparece un caso nuevo: anotar PC, versión del exe, si hubo Subir/Bajar, y comparar un alumno concreto en Supabase (`contratos_alumnos` + `pagos_contrato_alumno`) vs historial en la app.

---

## Cómo referenciar este incidente en un chat (Cursor)

Decile al asistente cualquiera de estas frases:

- *“Leé `docs/CONTEXTO_SYNC_v4.1.6.md`”*
- *“Es el incidente sync del **24 de junio de 2026**”*
- *“Fix cobro PDF/UI del **25 de junio de 2026**”*
- *“CONTEXTO_SYNC_v4.1.6 / incidente sync 24-jun-2026 / v4.1.7”*

Asuntos cubiertos: pagos que no sync entre PCs, límite 1000 pagos, mesas extra liquidadas juntas, carpetas `JuniorEventos` duplicadas, recuperación con `data.db` viejo + Subir + Pull completo forzado, releases **4.1.6** y **4.1.7** (alineación PDF/UI post-cobro mesas y cuotas).
