# Contexto — Mora operativa (grilla, modal, restore)

> **Referencia para Cursor / equipo:** `CONTEXTO_MORA_OPERATIVA` · `mora pendiente grilla modal` · `fix tracked carry-over` · `migración v49`  
> Si en un chat futuro decís *"leé el contexto de mora"*, *"mora operativa"* o *"fix remanente carry-over"*, apuntá a este archivo.

**Última actualización:** **Domingo 29 de junio de 2026 (v50)**  
**Archivo:** `docs/CONTEXTO_MORA_OPERATIVA.md`  
**Tests:** `test/mora_pendiente_display_test.dart` (17 tests)

---

## Resumen operativo (cómo funciona AHORA — v49+)

La mora que ve el operador en **grilla**, **Cobro masivos** y **modal de cobro** sale de:

**`MoraCuotaCalculator.moraPendienteOperativa()`**

### Modelo simplificado (v49)

```
moraCobradaAjustada  = (moraCobradaHistorial - moraCobradaOffset).clamp(0, ∞)
desgloseNeto         = desglosePendiente(calcularDesglose(contrato), moraCobradaAjustada)
moraPendienteOperativa = sum(desgloseNeto) + tracked
```

**Tracked** solo contiene remanente de pagos **parciales** de mora. Si se pagó una cuota sin cobrar mora, esa mora queda **perdonada** (no se carry-overea a tracked).

**Offset** (`moraCobradaOffset`) absorbe los pagos de mora de cuotas que ya salieron del desglose calendario. Se actualiza al confirmar cada cobro.

### Dos conceptos en el modal

| Concepto | Origen | Cuándo aparece |
|----------|--------|----------------|
| **Mora por cuota vencida** (Abr, May, …) | `calcularDesglose` + FIFO offset-adjusted | Cuotas base **vencidas e impagas**; crece día a día (1% cuota × días). |
| **"Remanente mora parcial"** | `moraPendienteTracked` | Solo informativo si **tracked > 0**; ya incluido en el total (sin checkbox). |

### Helpers clave (`lib/features/eventos/services/mora_cuota_calculator.dart`)

| Helper | Rol |
|--------|-----|
| `calcularDesglose()` | Mora bruta por cada cuota vencida no liquidada. |
| `desglosePendiente()` | FIFO: resta `moraCobradaAjustada` del desglose bruto. |
| **`moraPendienteOperativa()`** | `sum(desgloseNeto) + tracked` — total para grilla, modal, cobro masivos. |
| `pendienteDisplay()` | Legacy: fórmula del día + carry-over tracked. **Ya no se usa en flujos principales.** |
| `remanenteTrackedNeto()` | Legacy: tracked menos historial. **Ya no se usa en flujos principales.** |
| `remanenteOperativo()` | Legacy: tracked solo si cuotasPagadas > 0. **Ya no se usa en flujos principales.** |

---

## Lógica al confirmar cobro (modal)

```
moraEsteCobro = suma de líneas interés mora en previewConceptos

SI moraEsteCobro > 0:
  moraDesgloseQueSale = sum(desglose cuotas que están siendo liquidadas)
  moraNoRecuperable   = moraDesgloseQueSale + remanenteMora
  trackedNuevo        = max(0, moraNoRecuperable - moraEsteCobro)  // remanente parcial real
SINO:
  trackedNuevo = moraDesgloseQueSale + remanenteMora  // mora pendiente en ficha (v51)

offsetNuevo = moraYaCobradaHist + moraEsteCobro  // absorbe todo lo pagado hasta ahora
```

### Escenarios verificados

| Escenario | tracked | offset | Resultado |
|-----------|---------|--------|-----------|
| Pagar cuota sin mora | moraDesgloseQueSale + remanente | sin cambio | Mora queda en ficha (tracked); no toca saldo plan |
| Pagar cuota + mora parcial ($5k de $8.7k) | $3,700 | hist + $5k | Remanente legítimo |
| Pagar cuota + mora completa | 0 | hist + mora | Todo pagado |
| Pagar solo mora sin cuota base | 0 | hist + mora | FIFO reduce desglose |

---

## Migración v50 — limpieza conservadora (historial)

1. **Reset inflado:** `tracked → 0` solo si **no hay** pagos `interes_mora` en historial.
2. **Preserva legítimo:** si hay mora cobrada en historial y `tracked > 0` → **no toca tracked**.
3. **Recupera v49:** si `tracked = 0` pero historial tiene mora → recalcula `tracked`/`offset` simulando cobros (`MoraTrackedRecovery`).
4. **No toca:** pagos, cuotas, saldos, alumnos al día (`tracked = 0`).

```dart
// Offset solo sube al cobrar mora junto con liquidación de cuota base.
// Mora solo (sin cuota) → FIFO sobre desglose; offset sin cambio.
MoraCuotaCalculator.postCobroTrackedOffset(...)
```

---

## Incidentes previos

### 1. Barrientos — grilla inflaba mora (28-jun-2026)

- **Síntoma:** Grilla ~$8.400; modal ~$600 tras cobrar $7.800 de mora.
- **Fix:** Grilla y cobro masivos pasan a `moraPendienteOperativa()`.

### 2. Ayala / restore — tercera línea fantasma (28-jun-2026)

- **Síntoma:** 0/9 cuotas, cero pagos; modal mostraba "cuotas ya pagadas" $9.000.
- **Fix temporal:** `remanenteOperativo()` ignora tracked con 0 cuotas pagadas.
- **Fix definitivo (v49):** Tracked ya no almacena carry-over; migración limpia DB.

### 3. ARROSPIDE / TOLEDO — double-counting mora (29-jun-2026)

- **Síntoma:** Modal mostraba desglose $8,700 + remanente "cuotas sin liquidar" $8,700 = total $17,400 (doble conteo).
- **Causa raíz:** Al confirmar cobro sin cobrar mora, `trackedNuevoPostCobro = moraPendienteEfectivo` (incluía calendario completo). Eso inflaba tracked con mora de cuotas aún vencidas, que luego se duplicaba con el desglose vivo.
- **Fix:** Tracked solo se setea si hubo pago parcial de mora. Offset absorbe historial. FIFO usa `moraCobradaAjustada = hist - offset`.

---

## Cambios en código (archivos)

| Archivo | Cambio |
|---------|--------|
| `mora_cuota_calculator.dart` | `moraPendienteOperativa()` simplificada: desglose offset-adjusted + tracked. |
| `detalle_evento_masivo_screen.dart` | FIFO usa `moraCobradaAjustada`; tracked solo con pago parcial real; offset se persiste; label "Remanente mora parcial". |
| `contratos_repository.dart` | Removido snapshot de tracked en `registrarPago` (dialog lo maneja). |
| `cobro_masivos_tab.dart` | Eliminado `moraCobradaPeriodo` innecesario. |
| `dry_run_cobro_simulator.dart` | Eliminado `moraCobradaPeriodo` innecesario. |
| `local_database.dart` | Migración v49: reset tracked + update offset. |
| `test/mora_pendiente_display_test.dart` | Tests nuevos: offset-adjusted FIFO, remanente parcial, no carry-over. |

### Qué NO se modificó

- Cálculo diario de mora (`calcular`, 1% × días).
- `line_kind: interes_mora` en pagos.
- Sync engine, PDF, self-heal.
- Restaurar mora dialog (sigue funcionando como admin override).

---

## Dónde se muestra qué

| UI | Campo / texto | Cálculo |
|----|---------------|---------|
| Grilla detalle masivo | `Mora pendiente: $…` | `moraPendienteOperativa()` |
| Grilla (subtítulo naranja) | `C1 (Abr) 59d · C2 (May)…` | `calcularDesglose()` bruto (informativo) |
| Cobro masivos tab | `f.moraPendiente` | `moraPendienteOperativa()` |
| Modal | `Mora pendiente total` | `moraPendienteOperativa()` |
| Modal | Líneas por cuota | `desglosePendiente` (neto, offset-adjusted) |
| Modal | Checkbox maestro | **Incluir mora en este cobro** (siempre visible si hay mora) |
| Modal | Cuotas vencidas | Opcional: refina monto sugerido |
| Modal | Remanente parcial | Texto informativo si `tracked > 0` |

---

## Operación día a día

1. **Cobro normal:** Grilla y modal coinciden. Tracked solo aparece si hubo pago parcial de mora previo.
2. **Cobro sin mora:** La mora de la cuota pagada queda perdonada. No infla tracked.
3. **Restaurar mora (admin):** Preferir ajustar Reg sin tracked; si se setea tracked manual, el sistema lo trata como remanente parcial.
4. **Migración v49:** Automática al actualizar app. Limpia tracked inflado y calibra offset.

---

## Comandos útiles

```powershell
# Tests mora
flutter test test/mora_pendiente_display_test.dart
```

**DB local:** `Documents/Junior Eventos/data.db`

---

## Historial de esta doc

| Fecha | Qué |
|-------|-----|
| 29-jun-2026 (v50) | Migración conservadora por historial; `postCobroTrackedOffset`; offset solo con cuota+mora; UI checkbox maestro restaurado; recovery tracked legítimo. |
| 29-jun-2026 (v49) | Fix double-counting: tracked solo remanente parcial, offset-adjusted FIFO. |
| 28-jun-2026 | Alineación grilla/modal (`moraPendienteOperativa`), `remanenteOperativo` 0/9, fix Restaurar mora + Reg, limpieza 20 contratos. |

---

## Documentos relacionados

- **`docs/CONTEXTO_SYNC_v4.1.6.md`** — sync offline, mesas, instalador v4.1.6–4.1.7 (24–25-jun-2026).
- **`docs/CONTEXTO_COBRO_PARCIALES_SALDO.md`** — saldo fantasma con adelantos/parciales, saneamiento `recalcular_contrato`, casos Chamorro/Ayala/Díaz Leiva (30-jun-2026).
