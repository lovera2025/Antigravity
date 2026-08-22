# Contexto — Junior Eventos v4.7.2 (11 de agosto de 2026)

> **Referencia:** `CONTEXTO_v4.7.2` · `mora cobrada que decía "no cobrada"` · `recibo de Finanzas` · `un solo motor de conceptos` · `Reg movido y auditorías retroactivas`
> Si en un chat futuro decís *"leé el contexto de 4.7.2"*, *"lo de VIZGARRA"*,
> *"por qué la ficha decía que no se cobró"* o *"por qué no se puede auditar mora vieja
> con el Reg de hoy"*, apuntá a este archivo.

**Estado:** código completo, `flutter analyze` sin errores nuevos, **289 tests verdes**
(eran 273), build Windows y Setup v4.7.2 generados.
**Rama:** `feature/v4.6-cierre-por-sesiones`

**Sin migración de base.** No se toca ni una columna ni un dato: `_version` queda donde
estaba y se puede reinstalar el build anterior encima. Todo el arreglo es de lectura —
los rótulos se arman al mostrar, no se guardan.

---

## El caso

Foto del 10-ago: recibo Nº 11408158 (VIZGARRA, SONIA — cobro del 08/07/2026 10:14) al
lado del Estado de cuenta del **mismo movimiento**.

| Papel | Dice | $ |
|---|---|---|
| Recibo | `Interés mora (cuota base — este cobro)` | 3.150 |
| Estado de cuenta | `Mora pendiente cuota 3 (no cobrada al pagar)` | 3.150 |

Un solo pago de $3.150 en efectivo dentro de un cobro de $38.150, con dos rótulos que se
contradicen: uno dice que es la mora de la cuota base que se está pagando, el otro que es
el arrastre de la cuota 3 — y además suena a que no se cobró, arriba de plata que sí
entró.

Es la misma familia de bug que `3d2c8c8` (v4.7.1), por otro camino.

---

## Causa

La regla de **cómo se llama una línea de mora y si cuenta como mora** estaba copiada en
tres lugares. v4.7.1 arregló uno.

1. **`finanzas_provider.dart`** — el *reimprimir recibo* de Mi Empresa → Finanzas tenía su
   propia tabla de rótulos: **todo** concepto con `MORA` o `INTERE` se reescribía a la
   constante `'Interés mora (cuota base — este cobro)'`. Ese es, literal, el texto de la
   foto. Armaba los mapas a mano (`{concepto, monto}`), **sin `esMora`**, así que
   `moraSeleccionadaPdf` daba 0 y los $3.150 se sumaban dentro de *"Cuotas del plan"*.
2. **`detalle_evento_masivo_screen.dart`** — el `REIMPRIMIR` por fila del Estado de cuenta
   pasaba el mismo mapa pelado. Mismo defecto.
3. **`concepto_pago_display.dart`** — para filas de mora la ficha imprimía el `concepto`
   persistido **crudo**. Ese texto es una **clave**, no copy, y está escrito en idioma de
   *origen*: "no cobrada al pagar" significa *no se cobró cuando se pagó la cuota 3*. En
   la ficha queda arriba de un importe cobrado y se lee como estado del movimiento.

---

## Qué cambió

### 1. Las banderas se derivan del concepto (red estructural)

`normalizarBanderasLineasPdf` (`cobro_masivo_conceptos_pdf.dart`) completa `esMora` /
`esCargoCanal` cuando la línea no las trae, usando `esPagoInteresMoraPorConcepto` /
`esPagoCargoCanalPorConcepto`. Una clave explícita en `false` se respeta.

Corre en `lineasDisplayParaPdf` y en `generarReciboAlumno` / `generarResumenAbonarAlumno`
**antes** de `agruparConceptosMesasParaPdf` y `compactarCuotasBaseParaPdf`, que también
deciden por `esMora`.

> **Dato que hace esto obligatorio:** `line_kind` está **NULL en las 2.481 filas** de
> `pagos_contrato_alumno` de la base local. La separación mora/plan depende enteramente de
> reconocer el texto del concepto. No es una red de seguridad opcional: es el único
> mecanismo que hay.

### 2. Finanzas reimprime con el motor de todos

Se borró la tabla de rótulos y el reimprimir pasa por
`ConceptoPagoDisplay.conceptosPdfDesdePagosLote(contrato, lote, historialCompleto:)`, el
mismo que usan el "imprimir recibo" de la grilla y la ficha. `todosPagosRows` ya estaba
cargado: no hay consulta nueva.

Además la ventana del lote pasó de **±2 s a ±10 s**, el umbral con que
`getUltimosPagosLote` (`contratos_repository.dart:664`) define "un cobro". Con 2 s, un
cobro cuyas filas tardan un poco más en escribirse salía partido en dos recibos. Y como el
motor filtra anulados, dejan de colarse.

### 3. `REIMPRIMIR` por fila lleva las banderas

Se agregan `esMora` / `esCargoCanal` (ya estaban calculadas en la fila) y `esReimpresion`.

### 4. El rótulo de la ficha

`MoraConceptoRotulo.rotuloFichaMora(concepto)` traduce el concepto persistido a título +
subtexto:

| Concepto persistido | Ficha |
|---|---|
| `Mora pendiente cuota 3 (no cobrada al pagar)` | **Mora de la cuota 3**<br>*Quedaba de cuando se pagó la cuota 3 · se cobró en este pago* |
| `Mora pendiente cuotas 2 y 3 (…)` | **Mora de las cuotas 2 y 3** |
| `Mora pendiente de cuotas ya pagadas (…)` | **Mora de cuotas ya pagadas**<br>*Quedaba de cobros anteriores · se cobró en este pago* |
| `Interés mora cuota 1 (vto Abr 2026)` | intacto, ya se entiende |

Se publica en claves **nuevas** `concepto_ficha` / `subtexto_ficha`, no encima de
`concepto_detallado`: ese lo parsean el motor de reimpresión
(`_repartirMoraMixtoSiAplica`, `_numeroCuotaCalendarioDesdeConcepto`) y `_displayMora`.
Si el texto de display entrara ahí, el recibo dejaría de reconocer la línea.

Lo consumen el diálogo de Estado de cuenta (con el subtexto en gris debajo del título) y
el PDF `generarEstadoCuentaAlumno`, los dos con fallback al detallado.

**Como se arma al leer y no se guarda, aplica solo a partir de instalar: los 38 arrastres
que ya existen en la base se muestran bien sin tocar un registro.**

### 5. Ícono de la fila de mora

Reloj → tilde. El historial es de plata cobrada; el reloj la hacía leer como pendiente.
Lo que la distingue sigue siendo el naranja (círculo, borde y chip `MORA`).

### 6. Último recurso para el origen del arrastre

Si `MoraTrackedOrigen.inferir` no reconstruye de qué cuota viene el arrastre, el recibo
caía en el genérico "de cuotas ya pagadas" mientras la ficha, leyendo el mismo texto,
nombraba la cuota 3. Ahora usa el número que **ya está escrito en el concepto persistido**
— y solo si nombra **una** cuota, porque ahí todo el monto es de esa cuota y no se inventa
nada. Con varias, repartir sería fabricar un desglose que nadie calculó.

---

## El Reg movido: por qué una auditoría retroactiva miente

Durante el análisis de VIZGARRA se concluyó que había un **cobro de más de $3.150**.
**Esa conclusión era incorrecta** y quedó registrada acá para que nadie la repita.

El razonamiento fue: con el Reg actual (30/03/2026) la cuota 3 vencía el 30/06 y se pagó
el 09/06, adelantada, así que no pudo generar mora. Correcto — **pero el Reg de ese
contrato se había movido en su momento y después se volvió al original**. La mora se
calculó contra el Reg vigente ese día, que ya no existe en la base.

> **Regla:** recalcular mora vieja contra el Reg de hoy **no sirve** si el Reg se movió en
> el medio. La base guarda solo el Reg actual — no hay historial de cambios, `_sync_queue`
> no conserva los payloads viejos y no hay tabla de auditoría. Un barrido así da falsos
> positivos.

Con ese criterio se marcaron como sospechosos VIZGARRA, OJEDA y JUAREZ sobre 38 arrastres
del evento. **Los tres son falsos positivos.**

---

## Qué NO arregla este release

- **El monto cobrado.** Todo el cambio es de rotulado y de clasificación en el papel.
  `mora_cuota_calculator.dart` (`calcularDesglose`, `postCobroTrackedOffset`) no se tocó.
- **La atribución de cuota del arrastre.** `MoraTrackedOrigen.inferir` sigue como estaba; el
  punto 6 solo reusa el número ya persistido cuando la inferencia no llega, y si ese número
  refleja un Reg anterior, lo repite.

Los papeles ahora coinciden. Si alguna vez el monto estuviera mal, coincidirían en el monto
equivocado en vez de contradecirse — y la contradicción era justamente lo que hizo saltar
este caso.

---

## Archivos

| Archivo | Cambio |
|---|---|
| `lib/features/eventos/services/cobro_masivo_conceptos_pdf.dart` | `normalizarBanderasLineasPdf`; `lineasDisplayParaPdf` la aplica |
| `lib/features/common/services/pdf_service.dart` | Normaliza antes de agrupar/compactar (recibo y resumen); Estado de cuenta lee `concepto_ficha` |
| `lib/features/mi_empresa/providers/finanzas_provider.dart` | Reimprime con `conceptosPdfDesdePagosLote`; se borró la tabla de rótulos; lote 2 s → 10 s |
| `lib/features/eventos/detalle_evento_masivo_screen.dart` | Banderas en el reimprimir por fila; `concepto_ficha` + subtexto; tilde en mora |
| `lib/features/eventos/services/mora_concepto_rotulo.dart` | `rotuloFichaMora`, `numerosCuotaPendienteDesdeConcepto`, `sufijoNoCobradaAlPagar` |
| `lib/features/eventos/services/concepto_pago_display.dart` | `concepto_ficha`/`subtexto_ficha`; `_detalleDesdeElConcepto` |
| `docs/CONTEXTO_MORA_OPERATIVA.md` | Sección "Persistido vs display" + incidente VIZGARRA |

**Tests:** `test/mora_concepto_rotulo_test.dart` (`rotuloFichaMora`),
`test/cobro_pdf_display_test.dart` (mapas armados a mano),
`test/concepto_pago_display_test.dart` (historial VIZGARRA completo).

**Arnés manual**, emite el papel sin base ni red:

```powershell
flutter test tool/recibo_muestra_vizgarra_test.dart
```

Sale `Cuota 4 de 9 $35.000` + `Mora de la cuota 3 $3.150` en el bloque de arrastre,
desglose `Cuotas del plan $35.000 · Mora $3.150` (antes: $38.150 de plan) y **una sola
hoja**.

---

## Documentos relacionados

- **`docs/CONTEXTO_MORA_OPERATIVA.md`** — modelo tracked/offset/exención (actualizado 16-ago).
- **`docs/CONTEXTO_v4.6.2_2026-07-31.md`** — capa `display` del PDF, "viene de", recibo
  reimpreso con la fecha del pago. Auditoría de perdón de ficha **resuelta en 4.7.8**.
- **`docs/CONTEXTO_v4.7.0_2026-08-06.md`** — un cobro una fila, ventana de lote de 10 s.
- **`docs/CONTEXTO_v4.7.8_2026-08-16.md`** — perdón durable + botón por alumno.
