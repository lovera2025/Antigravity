# Contexto — Junior Eventos v4.3.0 (9 de julio de 2026)

> **Referencia:** `CONTEXTO_v4.3.0` · `perdón mora admin` · `fecha presupuesto particular` · `smoke masivos`  
> Si en un chat futuro decís *"leé el contexto del 9 de julio"* o *"qué salió en 4.3.0"*, apuntá a este archivo.

**Fecha:** Jueves **9 de julio de 2026**  
**Versión:** **4.3.0+21** (`pubspec.yaml`)  
**Instalador:** `Setup Junior Eventos v4.3.0.exe` (`installer/dist/` · también `releases/v4.3.0/` si se copia)

---

## Resumen de lo entregado hoy

### 1. Perdón de mora (admin) — sin tocar Reg

- **UI:** Mi Empresa → Restaurar mora → pestaña individual → panel *Perdonar mora*.
- Checkboxes **circulares** por cuota con mora (multi-selección con **prefijo**: marcar May incluye Abr).
- Persistencia: `mora_exenta_hasta` + `mora_exencion_reinicia = false` (+ `tracked = 0` si se limpia todo el desglose).
- **No** modifica `created_at` / Reg ni saldo / cuotas pagadas.
- Si se perdona todo lo vivo → exención hasta **fin de mes** (tiempo para ponerse al día en cuotas).
- Prefijo parcial → corte al día siguiente del último vencimiento perdonado.
- El alumno **sigue atrasado** en cuotas; solo se perdona el interés.

**API:** `MoraCuotaCalculator.simularPerdonMora` / `payloadPerdonMora` / `normalizarSeleccionPerdonPrefijo`.

**Recovery blindado:** `MoraTrackedRecovery.resolverExencionPreservandoLocal` — el post-pull **no degrada** un perdón admin (fecha más lejana / `reinicia=false` ganan).

Ver detalle operativo: `docs/CONTEXTO_MORA_OPERATIVA.md`.

### 2. Fecha del evento en presupuestos particulares

- Al crear/actualizar presupuesto se **persiste** `fecha_evento` (antes se elegía y se perdía).
- **Panel Maestro Pro:** campo editable “Fecha del Evento” (aparte del vencimiento del presupuesto).
- **PDF élite (sin redundancia):**
  - Header: `Fecha del evento: 1 de diciembre de 2026` (formato largo).
  - Resumen: solo total + `VÁLIDO HASTA` (validez de la propuesta).
  - Sin fecha cargada → header sin subtítulo inventado con la validez.

Archivos clave: `presupuestos_repository.dart`, `selector_servicios_screen.dart`, `presupuestos_screen.dart`, `evento_presentacion.dart`, `pdf_service.dart`.

### 3. Readiness cobro masivos (smoke)

Contra `Documents/Junior Eventos/data.db` (solo lectura):

| Métrica | Resultado |
|---------|-----------|
| Eventos masivos activos | **9 / 9 OK** |
| Contratos con deuda | **622** |
| Escenarios E/T/Mixto | **1645** |
| Suite mora | **43 tests** |

Colegios: Nacional, Gregoria Morales, Guemez, Normal Mariano Iloza, Puerto Viejo, Rotonda, Sagrado Corazón, Técnica Pinaroli, Buena Vista.

---

## Cómo generar el instalador

```powershell
.\installer\build_installer.ps1
```

Alinear siempre:

- `pubspec.yaml` → `version: 4.3.0+21`
- `installer/junior_eventos_setup.iss` (y hermanos) → `#define MyAppVersion "4.3.0"`

Salida: `installer\dist\Setup Junior Eventos v4.3.0.exe`

---

## Smoke manual sugerido (día siguiente)

1. Cobro efectivo cuota + PDF recibo  
2. Cobro parcial  
3. Mixto o transferencia  
4. Alumno con mora (con/sin incluir mora)  
5. Presupuesto nuevo → fecha en Panel Maestro + PDF header  

---

## Historial corto

| Fecha | Versión | Qué |
|-------|---------|-----|
| 9-jul-2026 | **4.3.0** | Perdón mora admin + fecha presupuesto PDF/Maestro + smoke 9 masivos |
| (prev) | 4.2.8 / 4.2.9 | Exención mora cobro, cronograma, Reg unificado |

Documentos relacionados: `CONTEXTO_MORA_OPERATIVA.md`, `CONTEXTO_COBRO_PARCIALES_SALDO.md`.
