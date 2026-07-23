# Contexto — Junior Eventos v4.5.0 (23 de julio de 2026)

> **Referencia:** `CONTEXTO_v4.5.0` · `release 4.5.0` · `sesiones de caja` · `modo jefe` · `sorteo alejadas`
> Si en un chat futuro decís *"leé el contexto del 23 de julio"* o *"qué hay en 4.5.0"*, apuntá a este archivo.

**Estado:** **RELEASE** — `4.5.0+24`  
**Instalador:** `Setup Junior Eventos v4.5.0.exe` (`installer/dist/` vía `.\installer\build_installer.ps1`)  
**Rama:** `feature/optimizacion-finanzas`

---

## Qué incluye este release (desde 4.3.1 → 4.5.0)

Consolida el WIP de **4.3.2** + sesiones de caja en un bump de versión de producto.

### 1. Sesiones de caja / roles (jefe ↔ caja)

- Role gate post-login: PIN maestro = **jefe**, PIN operador = **caja**.
- Sesión de caja obligatoria para operar como caja; heartbeat + `device_id`.
- Cobros / egresos / cierre llevan `sesion_caja_id`.
- **Caja sube altoque** tras mutaciones + flush si hay pendientes (~10 s).
- **Jefe baja** updates operativos (~10 s); sube pendientes manualmente (nube).
- Detalle: `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md`  
- SQL remoto: `docs/sql_sesiones_caja_supabase.sql` (**debe estar aplicado en Supabase**).

### 2. Modo jefe / operativa

- Badge **MODO JEFE** en dashboard; KPIs / QR condicionados al rol.
- Restricciones de grilla/edición masiva y cierre de caja alineados al modo.

### 3. Sorteo de mesas — juntas + alejadas

- Switch “Separar mesas extras”; bloque consecutivo + singles lejos.
- Motor: `AlumnoMesasSeparadas` / `asignarMesasSorteo(separaciones: ...)`.

### 4. Conceptos de pago / cobro

- `ConceptoPagoDisplay`: historial enriquecido, mixtos E/T, rótulos con adelanto (`· $X` = solo el parcial, no el total del cobro).
- Saldo desde gross de plan (base/mesa/sillas); tool `tool/recalcular_contrato.dart` para saneamiento local.

### 5. Mora / perdón (heredado 4.3.0–4.3.1)

- Perdón admin, ficha independiente del calendario; ver `CONTEXTO_MORA_OPERATIVA.md` y `CONTEXTO_v4.3.1`.

---

## Versiones

| Fecha | Versión | Notas |
|-------|---------|--------|
| 9-jul-2026 | **4.3.0** | Perdón mora + fecha presupuesto |
| 10-jul-2026 | **4.3.1** | Perdón solo ficha |
| 16–17-jul-2026 | **4.3.2+23** | WIP: sorteo alejadas, modo jefe, sesiones caja |
| **23-jul-2026** | **4.5.0+24** | **Release** — consolidación + instalador |

---

## Operativa recomendada (2 PCs)

1. Misma versión **4.5.0** en caja y jefe.
2. SQL de sesiones aplicado en Supabase.
3. Flujo día a día: **caja cobra** (auto-sube) → **jefe baja** operativo → jefe **sube** solo lo suyo si tiene pendientes.
4. PC nueva / desfasada: **Pull completo forzado** una vez; no usarlo a diario sin necesidad.

---

## Pendiente / smoke post-install

- Smoke real en oficina: rol caja + cobro visible en jefe en ~10–20 s.
- Confirmar SQL sesiones en el proyecto Supabase de producción.
- No mezclar builds viejos (p. ej. 4.0.x) subiendo cola grande contra ofi en 4.5.0.

---

## Archivos de versión tocados en este release

- `pubspec.yaml` → `4.5.0+24`
- `installer/junior_eventos_setup.iss` / `junior_eventos.iss` / `installer.iss` → `MyAppVersion "4.5.0"`

## Contextos relacionados

- `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md`
- `docs/CONTEXTO_v4.3.2_2026-07-16.md` (WIP previo; supersedido por este release)
- `docs/CONTEXTO_SYNC_v4.1.6.md`
- `docs/CONTEXTO_COBRO_PARCIALES_SALDO.md`
- `docs/CONTEXTO_MORA_OPERATIVA.md`
