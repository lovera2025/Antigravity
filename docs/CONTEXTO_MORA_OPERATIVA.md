# Contexto — Mora operativa (grilla, modal, restore)

> **Referencia para Cursor / equipo:** `CONTEXTO_MORA_OPERATIVA` · `mora pendiente grilla modal` · `fix tracked carry-over` · `migración v49`  
> Si en un chat futuro decís *"leé el contexto de mora"*, *"mora operativa"* o *"fix remanente carry-over"*, apuntá a este archivo.

**Última actualización:** **Sábado 22 de agosto de 2026 (el perdón del remanente suelta la cuota más vieja — `MoraOrigenRecorte`)**  
**Archivo:** `docs/CONTEXTO_MORA_OPERATIVA.md`  
**Tests:** `test/mora_pendiente_display_test.dart` · `test/mora_concepto_rotulo_test.dart` · `test/cobro_pdf_display_test.dart`  
**Release notes del día:** `docs/CONTEXTO_v4.7.8_2026-08-16.md` · columna `mora_tracked_ajuste` (SQLite v68)

---

## Vocabulario UI (23-jul-2026 · Opción B)

| Antes (deprecado en UI) | Ahora |
|-------------------------|--------|
| Saldo en ficha / Mora remanente | **Mora pendiente cuota N** (o `cuotas N y M`) |
| + Remanente / + mora cuotas ya pagadas | **+ mora pendiente cuota N** |
| Interés mora cuota N (Mes) | **Interés mora cuota N (vto Mes AAAA)** |
| (subtexto pendiente) | **Al pagar el DD/MM se cobró $X de $Y** |

PDF: líneas separadas calendario vs pendiente **por cuota** (sin prorratear el total sobre el desglose).
Origen del tracked: `MoraTrackedOrigen.inferir` desde historial, con `MoraOrigenRecorte`
— `loQueSeCobra` para rotular plata que entró, `loQueQueda` para lo que sigue debiéndose.
Rótulos: `MoraConceptoRotulo` · tests `test/mora_concepto_rotulo_test.dart`.
Reconciliar conceptos viejos: `dart run tool/reconciliar_rotulos_mora.dart --dry-run`

### Persistido vs display (10-ago-2026)

El `concepto` de `pagos_contrato_alumno` es **clave**, no copy: lo leen
`esPagoInteresMoraPorConcepto`, `MoraTrackedRecovery` y `recalcularSaldoDesdePagos`.
Está escrito en idioma de **origen**: `Mora pendiente cuota 3 (no cobrada al pagar)`
quiere decir "esta mora quedó sin cobrar cuando se pagó la cuota 3".

Nada de eso se muestra crudo. Cada superficie tiene su capa:

| Superficie | Rótulo | Quién lo arma |
|---|---|---|
| Recibo / resumen | `display` | `lineasDisplayParaPdf` (`cobro_masivo_conceptos_pdf.dart`) |
| Estado de cuenta (diálogo y PDF) | `concepto_ficha` + `subtexto_ficha` | `MoraConceptoRotulo.rotuloFichaMora` vía `enriquecerPagosHistorial` |

`normalizarBanderasLineasPdf` deriva `esMora` / `esCargoCanal` del texto cuando la línea
no las trae: sin esas banderas la mora se sumaba dentro de "Cuotas del plan".

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

**Tracked** (v54) es el **carry-over acumulado**: mora de cuotas liquidadas sin cobrar el interés + remanentes de pagos parciales. Si se paga una cuota sin cobrar mora, esa mora **NO desaparece**: se suma al tracked existente. Queda congelada (no crece día a día).

> ⚠️ Hasta v53 el tracked se **pisaba** en cada cobro con la mora de la última cuota liquidada — el remanente anterior se perdía (caso Bernel: C2 $6.900 borrados al cobrar C3). Corregido el 27-jul-2026 en `postCobroTrackedOffset`.

**Offset** (`moraCobradaOffset`) absorbe los pagos de mora de cuotas que ya salieron del desglose calendario. Se actualiza al confirmar cada cobro.

### Dos conceptos en el modal

| Concepto | Origen | Cuándo aparece |
|----------|--------|----------------|
| **Mora por cuota vencida** (vto Abr, May, …) | `calcularDesglose` + FIFO offset-adjusted | Cuotas base **vencidas e impagas**; crece día a día (1% cuota × días). |
| **Mora de cuotas ya pagadas** | `moraPendienteTracked` | Checkbox si `tracked > 0`; incluido en el total operativo. |

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

## Lógica al confirmar cobro (v54 — `postCobroTrackedOffset`)

```
Rama cuota base liquidada (cuotasBaseLiquidadasEnCobro > 0):
  remanenteCarry     = cuotasPreCobro > 0 ? tracked_actual : 0   // guarda anti-legacy
  moraLiquidadasNeto = mora neta de las cuotas liquidadas en ESTE cobro
  tracked_post       = max(0, remanenteCarry + moraLiquidadasNeto − moraEsteCobro)
  offset            += moraEsteCobro (si > 0)

Rama solo mora (v4.9 — de la más vieja a la más nueva, siempre):
  moraHaciaTracked  = min(moraEsteCobro, remanente)
  moraHaciaDesglose = moraEsteCobro − moraHaciaTracked
```

> ⚠️ Hasta v4.8 esa rama era condicional: *si el pago entraba justo en el
> arrastre iba todo al arrastre; si no, iba todo al calendario*. Con arrastre
> $19.400 y desglose $27.800, cobrar $19.400 imputaba al arrastre y cobrar
> $19.401 imputaba al calendario — un peso daba vuelta la imputación y el recibo
> no podía explicarla. Ahora el arrastre se consume **entero** primero: viene de
> cuotas ya liquidadas y `calcularDesglose` arranca en `cuotasPagadas + 1`, así
> que por construcción es siempre el bucket más viejo.
>
> Las tres capas comparten la regla o el papel contradice la ficha:
> `postCobroTrackedOffset` (ficha), `repartirMoraParcial` /
> `lineasPdfDesdePreviewMora` (líneas del papel) y los checks del modal, que van
> por **prefijo sobre la cola combinada** (arrastre y después calendario).
>
> Efecto conocido: `MoraTrackedOrigen.inferir` replica la regla para reconstruir
> arrastres viejos, así que un recibo **reimpreso** de un cobro anterior a v4.9
> puede atribuir el monto a cuotas distintas de las que nombró el papel
> original. Los montos y la ficha no cambian; solo el rótulo del reimpreso.

La guarda `cuotasPreCobro > 0`: con cero cuotas pagas no puede existir
carry-over legítimo — un tracked ahí solo puede ser un snapshot legacy que ya
refiere a cuotas del desglose, y sumarlo duplicaría. En el caso normal los
conjuntos son disjuntos (el desglose arranca en `cuotasPagadas + 1`; el tracked
es de cuotas ya liquidadas), así que acumular **no** puede duplicar.

### Escenarios verificados

| Escenario | tracked | offset | Resultado |
|-----------|---------|--------|-----------|
| Pagar cuota sin mora | remanente + mora de la cuota | sin cambio | El carry-over se ACUMULA (Bernel: 6.900 → 15.000) |
| Pagar cuota + mora parcial ($5k de $8.7k) | $3,700 | hist + $5k | Remanente legítimo |
| Pagar cuota + mora completa | 0 | hist + mora | Todo pagado |
| Pagar solo una cuota del arrastre | resto del arrastre | hist + lo cobrado | Check por cuota en el modal (v54) |
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

### 0. VAREIRO — perdonar abril y que abril siguiera ahí (22-ago-2026)

- **Síntoma:** remanente $16.600 rotulado "cuotas 1, 2 y 3" (abril, mayo, junio). Se
  perdonaron $5.600 —exactamente la mora de abril— esperando que abril
  desapareciera. En vez de eso abril siguió nombrado y lo que se cayó del rótulo
  fue **julio**, el mes más nuevo.
- **Causa:** el perdón del remanente guarda un **monto**, no un mes
  (`mora_pendiente_tracked` + `mora_tracked_ajuste`, los dos escalares). De qué
  cuotas salió se re-infiere replayando el historial en `MoraTrackedOrigen.inferir`,
  que atribuía el monto FIFO desde la cabeza y descartaba el sobrante por la
  **cola**. Con la cola intacta y el número más chico, abril volvía a ser el
  primero en cobrar nombre.
- **Fix:** `MoraOrigenRecorte`. `loQueSeCobra` (default) sigue como estaba —rotula
  plata que entró, y la mora se cobra de la más vieja a la más nueva. `loQueQueda`
  descuenta la brecha desde la **cabeza**: lo viejo ya se saldó o se perdonó. Lo
  usan las seis superficies que preguntan "qué queda hoy" (grilla, modal, estado de
  cuenta, aviso del recibo, diálogo de perdón, cobro masivos). El perdón del
  remanente pasa a prefijo para no prometer un cherry-pick que la ficha no puede
  recordar.
- **Arnés:** `flutter test tool/verificar_origen_mora_recibo_test.dart --dart-define=NOMBRE=vareiro`
  (solo lectura) imprime la cola del historial y el rótulo bajo las dos reglas.

### 1. VIZGARRA — la mora cobrada que la ficha llamaba "no cobrada" (10-ago-2026)

- **Síntoma:** recibo Nº 11408158 (08/07/2026): `Interés mora (cuota base — este cobro)
  $3.150`. El Estado de cuenta, del mismo movimiento, `Mora pendiente cuota 3 (no cobrada
  al pagar) $3.150`. Dos rótulos que se contradicen sobre plata que sí entró.
- **Causa:** la regla de cómo se llama una línea de mora estaba copiada en tres lados.
  `3d2c8c8` (v4.7.1) arregló el de *eventos*; quedaban el reimprimir de Finanzas
  (`finanzas_provider.dart`, que reescribía **todo** concepto con "mora" o "interés" a esa
  constante) y el `REIMPRIMIR` por fila del estado de cuenta. Los dos armaban los mapas a
  mano, sin `esMora`, así que la mora se contaba como plata del plan.
- **Fix:** Finanzas y la fila reimprimen por `conceptosPdfDesdePagosLote`;
  `normalizarBanderasLineasPdf` deriva las banderas del texto; la ficha muestra
  `rotuloFichaMora` en vez del concepto crudo. Ventana del lote de Finanzas: 2 s → 10 s,
  igual que `getUltimosPagosLote`.
- **Arnés:** `flutter test tool/recibo_muestra_vizgarra_test.dart`.

### 2. Barrientos — grilla inflaba mora (28-jun-2026)

- **Síntoma:** Grilla ~$8.400; modal ~$600 tras cobrar $7.800 de mora.
- **Fix:** Grilla y cobro masivos pasan a `moraPendienteOperativa()`.

### 3. Ayala / restore — tercera línea fantasma (28-jun-2026)

- **Síntoma:** 0/9 cuotas, cero pagos; modal mostraba "cuotas ya pagadas" $9.000.
- **Fix temporal:** `remanenteOperativo()` ignora tracked con 0 cuotas pagadas.
- **Fix definitivo (v49):** Tracked ya no almacena carry-over; migración limpia DB.

### 4. ARROSPIDE / TOLEDO — double-counting mora (29-jun-2026)

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
| Grilla — chip MORA | cantidad + total, y filtro por tipo | `moraPendienteOperativaDetallada()` una vez por build; `cumpleFiltroMora` (`filtro_mora_masivos.dart`) |
| Planilla de mora (PDF) | hoja para llamar, mayor a menor | `PdfService.generarPlanillaMoraPdf` · filas en `planillaMoraFilasTabla` |
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

1. **Cobro normal:** Grilla y modal coinciden. El tracked muestra el arrastre acumulado, abierto por cuota.
2. **Cobro sin mora:** La mora de la cuota pagada queda **en ficha** (se acumula al tracked). Para perdonarla de verdad, usar el perdón admin (Mi Empresa o el botón de la grilla, modo jefe).
3. **Restaurar mora (admin):** Preferir ajustar Reg sin tracked; si se setea tracked manual, el sistema lo trata como remanente parcial. El monto a mano ahora lleva `mora_tracked_ajuste` y **sobrevive** al sync.
4. **Perdonar mora (admin):** Exención hasta fin de mes (o corte de prefijo) con `reinicia=false`. El **remanente en ficha va por prefijo**, igual que el calendario: de la más vieja a la más nueva (tildar junio incluye abril y mayo). Lo que el historial no logre atribuir queda como entrada "sin origen identificado", **al final** de la cola. Un perdón **parcial** es tan durable como uno total: `aplicarTrackedDeseado` escribe `mora_tracked_ajuste` con el resto. **No mueve Reg.** El alumno sigue atrasado en cuotas. Recovery post-sync **no degrada** la exención **ni** la ficha (`mora_tracked_ajuste`). Botón por alumno en la grilla masivo (modo jefe). Ver `CONTEXTO_v4.7.8`.
5. **Migración v49 / v68:** v49 limpia tracked inflado. v68 agrega `mora_tracked_ajuste` (app 4.7.8). Instalar en todas las PCs que sincronizan.

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
| 22-ago-2026 | **El perdón del remanente suelta la cuota más vieja** (`MoraOrigenRecorte`). El rótulo del arrastre se recorta por la **cabeza** cuando la pregunta es "qué queda debiéndose" y por la cola cuando es "de qué cuotas salió lo que entró". El perdón del remanente pasa a **prefijo** (`seleccionPerdonRemanentePrefijo`). Además: un cobro parcial de mora ya no le borra los días de atraso a la cuota. Caso VAREIRO, abajo. |
| 21-ago-2026 (**v4.9**) | **La mora se cobra de la más vieja a la más nueva**, siempre: el arrastre se consume entero antes del calendario, en la ficha (`postCobroTrackedOffset`), en las líneas del papel (`repartirMoraParcial` / `lineasPdfDesdePreviewMora`) y en los checks del modal (prefijo sobre la cola combinada). **Recibo:** verde = lo que entró (“Pago parcial: la mora era de $X”), rojo = lo que falta (“FALTA PAGAR DE MORA”); nunca los dos diciendo lo mismo. En **reimpresión** el rojo ahora sale **fechado** (“FALTA PAGAR DE MORA AL DD/MM/AAAA” + “Es la mora al día de hoy, no la del día de este recibo”) y el verde solo dice “Es un pago parcial de la mora”, sin el total pre-cobro: sumar el restante de hoy daría un total que nunca existió. Omitir el aviso era peor — el papel mostraba lo que entró y nada de lo que seguía debiéndose. Además, y los renglones de arrastre dejan de repetir el título del bloque (`Cuota 1 (May)`, `De cuotas ya pagadas`). Se eliminó `detalleMoraCobradaRecibo`. **Perdón:** el remanente se abre por cuota de origen (`simularPerdonMora(trackedPerdonado:)`); el corte va por prefijo, igual que el calendario (corregido el 22-ago, ver abajo). **Grilla:** chip MORA con filtro por tipo + planilla de mora en PDF para llamar (`generarPlanillaMoraPdf`, ajustada con `_ajustarParaPaginas`). Arneses: `tool/recibo_muestra_vareiro_test.dart`, `tool/planilla_mora_muestra_test.dart`. |
| 16-ago-2026 (**v4.7.8**, v68) | **Perdón durable:** `mora_tracked_ajuste` (SQLite + Supabase). Recovery: `tracked = max(0, historial + ajuste)`. Botón perdonar en cada alumno (modo jefe). No mueve Reg. Ver `CONTEXTO_v4.7.8_2026-08-16.md`. |
| 27-jul-2026 (**v54**) | **Fix carry-over**: `postCobroTrackedOffset` acumula el remanente en vez de pisarlo (guarda estructural `cuotasPreCobro > 0`). `MoraTrackedOrigen` también acumula orígenes (desglose por cuota con vencimiento/días/cobrado). Modal: un check por cuota arrastrada. Grillas: arrastre abierto por cuota. PDFs: "DETALLE DE PAGO" / "LO QUE SE PAGA HOY", mora anidada bajo su cuota (capa `display`, sin tocar `concepto` persistido), franja "ATENCIÓN: queda debiendo mora" en resumen y recibo, nuevo `generarEstadoCuentaAlumno` (botón PDF en Estado de Cuenta). Dry-run read-only `scripts/dry_run_mora_tracked.dart` (47 contratos, $195.630). La reconciliación retroactiva corre sola en el post-pull del sync (decisión 27-jul). El pendiente de “perdón solo-ficha sin marcador” se cerró en **v4.7.8**. |
| 10-jul-2026 (**v4.3.1**) | Perdón solo ficha (tracked independiente, sin exención); filtro masivo Solo ficha. Ver `CONTEXTO_v4.3.1_2026-07-10.md`. |
| 9-jul-2026 (**v4.3.0**) | Perdón admin por exención (sin Reg); multi-cuotas prefijo; recovery no degrada exención local; release + smoke 9 masivos. Ver `CONTEXTO_v4.3.0_2026-07-09.md`. |
| 29-jun-2026 (v50) | Migración conservadora por historial; `postCobroTrackedOffset`; offset solo con cuota+mora; UI checkbox maestro restaurado; recovery tracked legítimo. |
| 29-jun-2026 (v49) | Fix double-counting: tracked solo remanente parcial, offset-adjusted FIFO. |
| 28-jun-2026 | Alineación grilla/modal (`moraPendienteOperativa`), `remanenteOperativo` 0/9, fix Restaurar mora + Reg, limpieza 20 contratos. |

---

## Documentos relacionados

- **`docs/CONTEXTO_v4.7.8_2026-08-16.md`** — perdón durable (`mora_tracked_ajuste`) + botón por alumno.
- **`docs/CONTEXTO_SYNC_v4.1.6.md`** — sync offline, mesas, instalador v4.1.6–4.1.7 (24–25-jun-2026).
- **`docs/CONTEXTO_COBRO_PARCIALES_SALDO.md`** — saldo fantasma con adelantos/parciales, saneamiento `recalcular_contrato`, casos Chamorro/Ayala/Díaz Leiva (30-jun-2026).
