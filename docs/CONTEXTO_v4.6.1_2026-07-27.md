# Contexto — Junior Eventos v4.6.1 (27 de julio de 2026)

> **Referencia:** `CONTEXTO_v4.6.1` · `release 4.6.1` · `operario edita cuota base` · `aviso abrir caja jefe`
> Si en un chat futuro decís *"leé el contexto de 4.6.1"* o *"el dialog de abrir caja del jefe"*, apuntá a este archivo.

**Estado:** **RELEASE** — `4.6.1+28`
**Instalador:** `Setup Junior Eventos v4.6.1.exe` (`installer/dist/` vía `.\installer\build_installer.ps1`)
**Rama:** `feature/v4.6-cierre-por-sesiones`

---

## Qué incluye este release (desde 4.6.0 → 4.6.1)

### 1. Operario puede editar contrato base (lápiz)

Antes (16-jul): al editar sin modo jefe, valor del contrato base y cuotas base
quedaban bloqueados (`baseBloqueada = isEdit && !modoJefe` en
`modal_alumno_premium.dart`).

**Ahora:** el operario edita monto y cuotas base igual que el jefe.

**Sigue solo modo jefe:** baja temporal, eliminar alumno, eliminar evento y
acciones AppBar gated en `detalle_evento_masivo_screen.dart`.

### 2. Aviso al cobrar con caja de jefe cerrada

Antes: cobro masivo en modo jefe sin sesión abierta llamaba
`sesionCajaIdParaCobro()` → `ensureSesionModoJefe()` y abría la caja en
silencio.

**Ahora:** si `esJefe && sesionActiva == null`, sale un diálogo:

- **Abrir caja y cobrar** → `iniciarCajaJefe()` y sigue el cobro.
- **Cancelar** → aborta (no abre caja, no cobra).

Si ya hay sesión activa, no hay diálogo.

### 3. Heredado en la misma rama (ya en HEAD previo)

- **v54 mora carry-over** (27-jul): pagar cuota sin tildar mora ya no borra el
  remanente; se acumula en `mora_pendiente_tracked`. Ver
  `CONTEXTO_MORA_OPERATIVA.md`.
- Caja de jefe explícita + PDFs de cierre por sesión (v4.6).
- Fix UUID operador Modo jefe + migración v66 (4.5.2).

---

## Operativa diaria (recordatorio)

- Jefe + operario pueden cobrar a la vez: sesiones distintas (`sesion_caja_id`).
- Sync entre PCs ~10 s (`OperationalSyncCoordinator`); push inmediato tras cobro.
- No cobrar el mismo alumno a la vez en dos PCs.
- Primera reconciliación de mora vieja: una sola PC, caja cerrada.
- Perdones solo-ficha pueden resucitar tras replay → reaplicar a mano.

---

## Versiones

| Fecha | Versión | Notas |
|-------|---------|--------|
| 23-jul-2026 | 4.5.2+26 | Fix sync operador Modo jefe + migración v66 |
| 24-jul-2026 | 4.6.0+27 | Caja jefe explícita + PDFs cierre por sesión |
| **27-jul-2026** | **4.6.1+28** | **Release** — operario edita base + aviso abrir caja |

## Contextos relacionados

- `docs/CONTEXTO_MORA_OPERATIVA.md` (v54 carry-over)
- `docs/CONTEXTO_v4.5.2_2026-07-23.md`
- `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md`
