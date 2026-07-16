# Contexto — Junior Eventos v4.3.2 (16 de julio de 2026)

> **Referencia:** `CONTEXTO_v4.3.2` · `sorteo mesas alejadas` · `modo jefe` · **WIP**
> Si en un chat futuro decís *"leé el contexto del 16 de julio"* o *"qué hay en 4.3.2"*, apuntá a este archivo.

**Estado:** **EN PROCESO / actualizando** — no tratar como release cerrado.  
**Versión en curso:** **4.3.2+23** (`pubspec.yaml`)  
**Instalador:** `#define MyAppVersion "4.3.2"` (ISS) — el `.exe` de dist puede aún no estar armado.

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

### 4. Versión

| Fecha | Versión | Notas |
|-------|---------|--------|
| 9-jul-2026 | **4.3.0** | Perdón mora admin + fecha presupuesto |
| 10-jul-2026 | **4.3.1** | Perdón solo ficha + fix PDF previo cobro |
| 16-jul-2026 | **4.3.2** | **WIP** — sorteo alejadas + modo jefe + conceptos |

Referencias previas: `docs/CONTEXTO_v4.3.1_2026-07-10.md`, `docs/CONTEXTO_v4.3.0_2026-07-09.md`, `docs/CONTEXTO_MORA_OPERATIVA.md`.

---

## Pendiente / sigue en curso

- Cerrar y smoke de modo jefe + cierre de caja en máquina real.
- Confirmar que el sorteo con salón agujereado / muchos separados no degrada UX (capacidad mínima ya suma huecos).
- Armar instalador `Setup Junior Eventos v4.3.2.exe` cuando se considere release.
- No mezclar en este contexto: carpetas `releases/`, `installer/output/`, scripts `tool/` temporales ni `.bak`.

---

## Cómo seguir en el próximo chat

1. Leer este archivo + `CONTEXTO_v4.3.1` si hace falta mora/perdón.
2. Asumir que **4.3.2 sigue abriéndose** hasta que se marque release cerrado aquí.
3. Cambios de sorteo: partir de `AlumnoMesasSeparadas` / `asignarMesasSorteo(separaciones: ...)`.
