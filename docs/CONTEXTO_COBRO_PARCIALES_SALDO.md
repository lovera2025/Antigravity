# Contexto — Cobro con parciales / adelantos y saldo deudor

> **Referencia para Cursor / equipo:** `CONTEXTO_COBRO_PARCIALES_SALDO` · `fantasma adelanto` · `saldo_deudor parcial` · `recalcular_contrato` · `caso Chamorro`
>
> Si en un chat futuro decís *"leé el contexto de parciales"*, *"saldo fantasma adelanto"* o *"bug Chamorro cuota 3"*, apuntá a este archivo.

**Última actualización:** **Martes 30 de junio de 2026**  
**Archivo:** `docs/CONTEXTO_COBRO_PARCIALES_SALDO.md`  
**Tests:** `test/cobro_abono_acumulado_test.dart` (regresión Chamorro) · `test/recalcular_saldo_desde_pagos_test.dart` (auditoría no infla) · `tool/recalcular_contrato.dart` (`--dry-run`)

---

## Resumen del problema

Cuando un alumno paga con **adelanto**, **entrega parcial** o **abono** y después liquida varias cuotas en un mismo cobro (o cierra la cuota con rotulo **"— Completada"**), el **`saldo_deudor`** en `contratos_alumnos` podía quedar **menor** que lo que indica la suma de `monto_gross` en `pagos_contrato_alumno`.

### Síntoma típico

```
saldo_deudor  <  (monto_total_pactado − Σ monto_gross plan)
```

La diferencia suele coincidir con el **monto del adelanto/parcial previo** que ya estaba embebido en un pago anterior (doble descuento fantasma).

### Lo que NO es el bug

| Caso | Por qué no corregir |
|------|---------------------|
| Línea **"Cargo canal / operador"** | No cuenta para saldo del plan (`line_kind: cargo_canal_ref` o concepto con `cargo canal`). |
| **Interés mora** | No reduce capital ni cuotas base. |
| Pagos de **mesa / silla** | Van en su propia clase; el saldo es `pactado − base − mesa − sillas`. |
| Cuota pura **no redonda** (ej. $27.777,78 en plan $250.000 / 9) | Usar FIFO sobre gross, no asumir $30.000. |

---

## Fuente de verdad del saldo

```
saldo_correcto = monto_total_pactado
               − gross_histórico_base
               − gross_histórico_mesa
               − gross_histórico_sillas
```

Clasificación alineada a `grossHistoricoClaseCobro()` en `lib/features/eventos/services/cobro_abono_acumulado.dart` (excluye mora, cargo canal, anulados).

**Cuotas pagadas (base):** `floor((gross_base + 0.1) / cuota_pura)` con `cuota_pura = (base_plan / total_cuotas)`.

---

## Fix en código (30-jun-2026)

| Archivo | Cambio |
|---------|--------|
| `detalle_evento_masivo_screen.dart` | Saldo post-cobro = `pactado − gross_histórico_plan − gross_este_cobro` (ya no `saldo_deudor − monto`). Tras persistir lote: `recalcularProgresoContrato()`. |
| `cobro_abono_acumulado.dart` | `repartirGrossEnCuotasPlan`: `break` si `resto <= 0`; cada cuota usa solo su `faltante` vigente. |
| `test/cobro_abono_acumulado_test.dart` | Regresión **Chamorro**: hist $83.500 + cobro $66.500 → saldo $120.000, sin parcial fantasma en C6. |
| `tool/recalcular_contrato.dart` | Saneamiento local por `--nombre`, `--id` o `--evento`; flag `--dry-run` para auditar sin escribir. |
| `cobro_abono_acumulado.dart` | `recalcularSaldoDesdePagos` — lógica compartida repo + tool (suma gross, sin inflar). |
| `contratos_repository.dart` | `recalcularProgresoContrato` delega en `recalcularSaldoDesdePagos`; **no reescribe** `monto_gross` por heurística. |

### Flujo post-cobro (modal masivo)

1. Registrar líneas en `pagos_contrato_alumno` (`registrarPago` ya llama `recalcularProgresoContrato` por línea).
2. Reconciliar mesas / mora tracked.
3. **`recalcularProgresoContrato` final** sobre el contrato (alinea saldo tras el lote completo).
4. Refrescar UI con `getContratoById`.

---

## Herramienta de saneamiento

**Ruta DB:** `Documents/Junior Eventos/data.db`  
**Cerrar la app** antes de escribir, o hot-restart después.

```bash
# Auditar las 9 instituciones activas sin tocar datos
dart run tool/recalcular_contrato.dart --dry-run --evento "COLEGIO NACIONAL"
dart run tool/recalcular_contrato.dart --dry-run --evento "SAGRADO CORAZON"

# Corregir un colegio
dart run tool/recalcular_contrato.dart --evento "SAGRADO CORAZON"

# Un alumno
dart run tool/recalcular_contrato.dart --nombre "CHAMORRO"
```

Salida `[REVISAR]` en dry-run = descuadre real. `OK` = saldo ya coincide con pagos.

---

## Incidentes resueltos (30-jun-2026)

Auditoría en **9 eventos masivos activos** (~636 contratos). Tras clasificar bien mora / cargo canal / mesa:

### Corregidos en DB (3 + 1 previo en la misma sesión)

| Alumno | Colegio | Saldo antes → después | Patrón |
|--------|---------|------------------------|--------|
| **CHAMORRO AMARILLA, NEREA VICTORIA** | Colegio Nacional | $96.500 → **$120.000** | 2 cuotas + adelanto $23.500 en C3; cobro $66.500 (C3–C5). Fantasma **$23.500**. |
| **DIAZ LEIVA, JAZMIN ANA BELEN** | Sagrado Corazón | $166.000 → **$168.000** | Cuota pura **$28.000**; C1 $30.000 (+$2.000); C3 $26.000 "Completada". Fantasma **$2.000**. |
| **AYALA, YAMILA ITATI** | Sagrado Corazón | $170.000 → **$180.000** | Abono $10.000 C3 + $20.000 cierre. Fantasma **$10.000**. |
| **PEREZ, PABLO ALEJANDRO** | Técnica Pinaroli | $194.444,42 → **$197.222,20** | Cuota **$27.777,78**; C1 $25.000 parcial + segundo pago; cuotas DB **2 → 1**. Fantasma **$2.777,78**. |

### Falsos positivos (no tocar)

| Alumno | Motivo |
|--------|--------|
| **BENITEZ GUARDERES, SANTINO** | Auditoría naive sumó **cargo canal $2.000** como cuota base. Saldo $220.000 correcto. |
| **PEREZ, NICOLE MILAGROS** | Igual: **cargo canal $1.000** confundido con base. Saldo $194.444,42 correcto. |

**Estado post-saneamiento:** 0 descuadres en las 9 instituciones activas.

### Regresión auditoría inteligente (30-jun-2026 tarde)

Tras el saneamiento matutino, **Auditoría inteligente** (`ejecutarAuditoriaInteligente`) volvió a corromper saldos porque `recalcularProgresoContrato` inflaba `monto_gross` vía regex en conceptos ("— Completada" contaba como 1 cuota entera). **Fix:** `recalcularProgresoContrato` usa `recalcularSaldoDesdePagos` (misma lógica que `tool/recalcular_contrato.dart`). Re-sanear DB tras desplegar.

---

## Cómo diagnosticar un caso nuevo

1. **Pagos:** listar `pagos_contrato_alumno` ordenados por `fecha_pago`; separar BASE / MESA / SILLAS / MORA / CARGO CANAL.
2. **Σ gross plan** vs **`monto_total_pactado − saldo_deudor`**.
3. Si `diff < 0` (saldo DB menor): buscar adelanto/parcial previo + cobro multi-cuota o "Completada".
4. Confirmar con `--dry-run` antes de escribir.
5. Si el fix de código del 30-jun-2026 está desplegado, **nuevos cobros** no deberían regenerar el fantasma; datos viejos requieren `recalcular_contrato`. **Auditoría inteligente** del evento es segura solo tras el fix de `recalcularProgresoContrato` (30-jun tarde): antes inflaba `monto_gross` y bajaba saldo de más.

### Ejemplo Chamorro (referencia numérica)

- Plan: $270.000 / 9 × $30.000  
- Hist: $83.500 (`2 Cuotas + Adelanto C3`, incluye $23.500 adelanto)  
- Cobro: $6.500 + $30.000 + $30.000 = $66.500  
- Capital pagado: **$150.000** → saldo **$120.000** (no $96.500)

---

## Archivos relacionados

| Archivo | Rol |
|---------|-----|
| `lib/features/eventos/services/cobro_abono_acumulado.dart` | FIFO cuotas, `recalcularSaldoDesdePagos`, `grossHistoricoClaseCobro` |
| `lib/features/eventos/repositories/contratos_repository.dart` | `registrarPago`, `recalcularProgresoContrato` (suma gross, sin inflar) |
| `lib/features/eventos/services/concepto_pago_display.dart` | Rotulado historial / mixto |
| `lib/core/utils/pago_interes_mora.dart` | `esPagoCargoCanalPorConcepto`, `kLineKindInteresMora` |

---

---

## 2026-09-02 — "Auditoría inteligente" se retiró

El botón **"Auditar y Sincronizar DB"** (ícono de sync dorado en el AppBar del
detalle de evento masivo, modo jefe) y su `ejecutarAuditoriaInteligente` ya no
existen.

Este mismo documento lo venía marcando: la línea sobre el saneamiento matutino
deja constancia de que la auditoría **volvió a corromper saldos**, y la nota
posterior avisaba que solo era segura después del fix del 30-jun. El 1-sep-2026
volvió a morder, esta vez con la mora: el jefe perdonó una mora en la PC de
oficina, en la otra se apretó el botón sin querer y la mora volvió.

**El defecto era la fuente, no el cálculo.** Recalculaba desde
`pagos_contrato_alumno` de la base **local** y encolaba el resultado a Supabase.
Si un pago no había bajado todavía de la otra PC, concluía que el alumno debía
más, pisaba un saldo correcto y publicaba el error a la nube.

Contraste útil: `MoraTrackedRecovery.reconciliarTodos` hace un recálculo
automático y está bien hecho — *"solo escribe exención si el merge la mejora;
nunca degrada admin"* (`mora_tracked_recovery.dart:520`). El botón nunca recibió
esa regla.

Era además el mayor generador de escritura de la base: 66.627 updates de
recálculo contra 3.368 pagos realmente registrados.

**`recalcularProgresoContrato` sigue intacto** y es el que hay que usar: corre
sobre un contrato puntual, justo después de persistir sus pagos. Lo llaman
`registrarPago`, la anulación de cobro y la purga inteligente.

Para auditar, `tool/recalcular_contrato.dart --dry-run` (sincronizando antes).
Detalle en [`docs/pendientes/chequeo-salud-saldos.md`](pendientes/chequeo-salud-saldos.md).

---

## Docs hermanos

- **`docs/CONTEXTO_MORA_OPERATIVA.md`** — mora pendiente, tracked, offset (no mezclar con saldo de capital).
- **`docs/CONTEXTO_SYNC_v4.1.6.md`** — sync offline, mesas, instalador.
- **`docs/pendientes/PENDIENTES.md`** — lo que quedó a medio hacer y por qué.

---

## Frases para Cursor

- *"Leé `docs/CONTEXTO_COBRO_PARCIALES_SALDO.md`"*
- *"CONTEXTO_COBRO_PARCIALES_SALDO / fantasma adelanto / caso Chamorro"*
- *"Auditar saldo con recalcular_contrato --dry-run"*
