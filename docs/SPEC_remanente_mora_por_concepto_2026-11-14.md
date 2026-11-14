# SPEC — El remanente de mora nombra los meses que de verdad se deben

**Archivo:** `docs/SPEC_remanente_mora_por_concepto_2026-11-14.md`
**Rama:** `feature/v4.6-cierre-por-sesiones` (hoy en `6.8.0+74`). Versión sugerida: la que siga, **sola**.
**SQL:** ninguno. **Migración local:** ninguna. **Tablas o columnas nuevas:** ninguna. **Datos que se corrigen:** ninguno.
**Revisado contra el código** en `b3ca309` (13-nov, 08:12) y **contra los pagos reales** el 14-nov (solo lectura).
**Verificado el 14-nov** con dos simulaciones independientes sobre las 36 fichas reales con remanente y una revisión
adversarial de esta spec contra el código (sección 6).

> **Este repo es público.** En esta spec, en los tests, en las muestras y en los mensajes de commit de este trabajo
> **no va ningún nombre de alumno, id de contrato ni historial de pago**. Los ejemplos son familias inventadas (F1…F5). El
> comparador de la sección 7.2 sí lee la base real, pero su informe va a una carpeta de afuera del repo y no se sube nunca.

Es un pedido del usuario del 14-nov. Una ficha de un evento masivo mostraba un remanente de mora "de abril" que la familia
había pagado el día anterior. **El total del remanente está bien; lo que está mal es de qué meses dice que es.**

**Hoy hay 5 fichas que lo muestran mal** (sección 5). No hay nada guardado mal en ellas: la app arma el desglose de nuevo
cada vez que lo muestra. Cuando la cuenta se corrija, **esas 5 pasan solas a verse como las demás**, sin SQL ni reparación
de datos.

**Qué cambia de verdad:** no cambia ningún total ni nada ya guardado. Sí cambia **el monto que ofrece cada tilde del
remanente** en la ventana de cobro y en el perdón: hoy, en esas 5 fichas, cada tilde ofrece el monto de un mes equivocado.

---

## 1. El caso (familia inventada F1, con la misma forma que el caso real)

Contrato de 9 cuotas de $30.000 ($270.000), sin mesa ni sillas, sin descuento, alta el 30/03/2026. La cuota 1 vence el
30/04/2026, la 2 el 31/05, la 3 el 30/06, la 4 el 31/07 y la 5 el 31/08. La mora es del 1 % diario sobre la cuota ($300 por día).

| Fecha | Lo que se cobró (un lote por día) |
|---|---|
| 20/07/2026 | `Cuota Base (1/9)` $30.000 · `Cuota Base (2/9)` $30.000 · **sin mora** |
| 12/11/2026 | `Cuota Base (3/9)` $30.000 · `Cuota Base (4/9)` $30.000 · `Entrega parcial — Cuota Base (5/9)` $100 · `Mora pendiente cuotas 1 y 2 (no cobrada al pagar)` $39.300 |

Lo que tiene que pasar:

- El **20/07** las cuotas 1 y 2 se pagan sin mora y pasan al remanente: cuota 1, 81 días, $24.300; cuota 2, 50 días, $15.000.
  En total, **$39.300**.
- El **12/11** entra una línea que **dice** que es la mora pendiente de las cuotas 1 y 2, por **$39.300**: salda abril y mayo
  enteros. En el mismo lote se pagan las cuotas 3 y 4 **sin su mora**, que pasa al remanente: cuota 3, 135 días, $40.500;
  cuota 4, 104 días, $31.200.
- Ficha después del 12/11: `mora_pendiente_tracked` = **$71.700** y `mora_cobrada_offset` = $39.300. **Esto ya da bien hoy.**

| Hoy (mal) | Después del arreglo |
|---|---|
| C1 (Abr) 81d · $24.300 · "no se cobró nada de los $24.300,00 de mora" | — (ya se pagó) |
| C2 (May) 50d · $15.000 · "no se cobró nada…" | — (ya se pagó) |
| C3 (Jun) 135d · $1.200 · "se cobró $39.300,00 de los $40.500,00 de mora" | C3 (Jun) 135d · **$40.500** · "Venció el 30/06/2026 · se pagó el 12/11/2026, 135 días tarde · no se cobró nada de los $40.500,00 de mora" |
| C4 (Jul) 104d · $31.200 | C4 (Jul) 104d · **$31.200** · "Venció el 31/07/2026 · se pagó el 12/11/2026, 104 días tarde · no se cobró nada de los $31.200,00 de mora" |
| Suma $71.700 | Suma $71.700 (igual) |

**Por qué importa aunque el total esté bien:**

- Los tildes del remanente en la ventana de cobro salen de este desglose. Si la familia vuelve a pagar, el concepto nuevo
  diría **otra vez "Mora pendiente cuotas 1 y 2"**, y tildar solo el primer renglón cobraría $24.300 (C1) en vez de
  $40.500 (C3).
- En el perdón pasa lo mismo: tildar "abril" perdona un monto que en realidad es de junio.

---

## 2. La causa

`MoraTrackedOrigen.inferir` (`lib/features/eventos/services/mora_tracked_origen.dart`) no lee el origen de ningún lado: lo
**reconstruye** volviendo a pasar el historial lote por lote (un lote = los pagos no anulados de un mismo día en hora AR).
En la rama de un lote que **liquida cuotas** (`if (cuotasLiquidadas > 0)`, líneas 372-439), reparte `moraEsteCobro`:

1. primero sobre las cuotas que se liquidan **en ese lote** (`liquidadas` → `nuevos`, 382-405);
2. y solo lo que sobra sobre el arrastre de antes (`previos`, 406-434).

Eso falla de dos formas:

- **F1:** la línea dice que paga el arrastre ("Mora pendiente cuotas 1 y 2"), pero los $39.300 se los come la cuota 3, y
  abril y mayo quedan "vivos".
- **F4:** la línea es de calendario y nombra una cuota (`Interés mora cuota 6 (vto Sep 2026)`), pero en el lote se liquidan
  la 5 y la 6, y la plata va a **la 5**, la más vieja, no a la que nombra la línea.

Contradice al resto de la app:

- **La ventana de cobro** tilda la mora por prefijo sobre una sola cola, **el arrastre primero**
  (`aplicarSeleccionPrefijo`, `detalle_evento_masivo_screen.dart` ~5425).
- **`MoraConceptoRotulo.repartirMoraParcial`** (`mora_concepto_rotulo.dart` 449-455): primero el arrastre, después el
  calendario.
- **La rama "solo mora" de `MoraCuotaCalculator.postCobroTrackedOffset`** (`mora_cuota_calculator.dart` 522): primero el arrastre.
- **El comentario del `enum MoraOrigenRecorte`** (`mora_tracked_origen.dart` 129-131): "la mora se cobra de la más vieja a la
  más nueva (v4.9)".
- **El concepto guardado de cada cobro.**

**Ojo con la historia:** la regla "arrastre primero" en las líneas mixtas rige **desde la v4.9 (21-ago-2026)**
(`docs/CONTEXTO_MORA_OPERATIVA.md` 96-116 y 341). Entre la v4.6.6 y la v4.8, una línea mixta que no alcanzaba para todo se
repartía **calendario primero** (`docs/CONTEXTO_v4.6.6_2026-08-04.md` 173-176). Antes de la v4.6.6 no había reparto. La regla
nueva respeta esa fecha (sección 3.1).

**Lo que no está mal: la plata.** En esa rama, `postCobroTrackedOffset` suma el arrastre y las cuotas que se cierran en un
solo monto (`aCerrar - moraEsteCobro`, 491-492), así que `mora_pendiente_tracked` y `mora_cobrada_offset` salen bien. Se
verificó en las 36 fichas reales con remanente (sección 6).

---

## 3. El arreglo

### 3.1 La regla: cada línea de mora va a lo que dice su concepto

En la rama `cuotasLiquidadas > 0` de `inferir`, en lugar del reparto de hoy:

1. **Cada línea de mora del lote** (las que cumplen `_esMora`), en el orden del lote, ubica su `monto` según su concepto:
   - **Solo arrastre** (`mencionaArrastre` y sin cuotas de calendario): va al **arrastre** (punto 2).
   - **Solo calendario** (`cuotasDeCalendarioEnConcepto` no vacío y sin arrastre): va a las **liquidadas que nombra**, en
     orden de número.
   - **Mixta** (las dos cosas): si el lote es **desde el 21/08/2026**, primero al arrastre y lo que sobre a las liquidadas
     que nombra. **Antes del 21/08/2026**, al revés: primero las que nombra y después el arrastre.
   - **Sin nada reconocible** (el genérico `Interés mora (cuota base — este cobro)`, formatos viejos): va entera al **pozo**.
2. **Ir al arrastre** es, en este orden:
   - las cuotas que el concepto nombra como pendientes (`MoraConceptoRotulo.numerosCuotaPendienteDesdeConcepto`, que ya existe
     y lee también el sufijo ` + mora pendiente cuota(s) …`), buscándolas primero en `previos` y después en las `liquidadas`
     del mismo lote (dos cobros el mismo día);
   - después, el resto de `previos`, de la más vieja a la más nueva.

   Si `cuotasPre == 0`, `previos` no cuenta, igual que hoy (línea 439).
3. **Lo que una línea no pudo ubicar va al pozo.** El pozo sigue **exactamente el camino de hoy**: primero las `liquidadas`
   que tengan lugar, en orden, y después `previos`, con la guarda `<= 0.01` de hoy.
4. Todo lo que se aplica a un origen se suma a su `moraCobrada`, como hoy.

Para un lote cuyas líneas no nombran nada, o nombran justo lo que el reparto de hoy ya elegía, **el resultado es el de hoy**.

**La rama "solo mora" no se toca:** ya consume el arrastre primero.

### 3.2 Los helpers

Van en `lib/core/utils/pago_interes_mora.dart`, con el mismo plegado que `esPagoInteresMoraPorConcepto` (minúsculas, sin
marcas combinadas, `foldDiacriticosLatin`). **Se aplican solo a líneas que cumplen `_esMora`.**

**`mencionaArrastre`**: `true` si el concepto contiene `mora pendiente`, `cuotas ya pagadas`, `mora remanente`,
`+ remanente` o `no cobrada al pagar`.

**`cuotasDeCalendarioEnConcepto`**: toma el texto **antes** del primer ` + ` y devuelve los números de
`interes\s*mora\s*cuotas?\s+(\d+(?:\s*,\s*\d+)*)`. **Solo esa lista**: el año de `(vto Oct 2026)` no cuenta.

Formatos reales en la base (14-nov) y cómo se clasifican:

| Formato | Veces | `mencionaArrastre` | `cuotasDeCalendarioEnConcepto` |
|---|---|---|---|
| `Interés mora cuota N (vto Mmm AAAA)` | 312 | false | [N] |
| `Interés mora cuota N (Mmm AAAA)` (sin "vto") | 77 | false | [N] |
| `Interés mora cuotas N, N[, N…] (vto …)` / `(Mmm, …)` | 127 | false | lista |
| `Interés mora (cuota base — este cobro)` | 27 | false | [] |
| `Interés mora cuota(s) … + mora pendiente cuota(s) …` | 76 | true | lista de antes del ` + ` |
| `Mora pendiente cuota(s) … (no cobrada al pagar)` | 31 | true | [] |
| `Interés mora cuota N (Mmm AAAA) + Remanente` (anulada) | 1 | true | [N] |

En la base no hay `mora remanente`, `cuotas ya pagadas` ni `(parcial)`. `(parcial)` y `Mora pendiente cuota N` sin sufijo
existen solo en el PDF (`lineasPdfDesdePreviewMora`), nunca en un concepto guardado.

### 3.3 Por qué alcanza con el orden por fecha en las líneas mixtas

Una línea mixta guarda un solo monto, sin el reparto interno. Desde la v4.9, `repartirMoraParcial` llena primero el arrastre
y la ventana obliga a tildar todo el arrastre antes de cualquier cuota del calendario: la parte de arrastre de la línea es
`min(monto, arrastre vivo)`, que es lo que hace el punto 1. Antes de la v4.9 era al revés, y el punto 1 lo respeta por fecha.

### 3.4 Lo que no cambia, por construcción

Sean `M = moraEsteCobro`, `L = Σ interesBruto` de las `liquidadas` y `P = Σ remanente` de `previos` (0 si `cuotasPre == 0`).
Cada paso consume de esos mismos dos pozos, nunca más de lo que hay ni más de `M`, y el pozo final sigue hasta agotar `M` o
la capacidad. Entonces en cada lote se consume en total `min(M, L + P)`, **igual que hoy**: solo cambia **sobre qué
orígenes**. Por inducción sobre los lotes:

- la suma de los orígenes después de cada lote es la misma;
- `tracked`, `offset` y la exención del re-juego no dependen de los orígenes;
- `MoraTrackedOrigen.sinExplicar` y el recorte `loQueQueda` dan igual en todas las fichas.

Por los `toStringAsFixed` intermedios puede haber diferencias de centavos: tolerancia de 0,01.

---

## 4. Qué cambia y qué no

**Cambia** (solo qué meses se nombran y cuánto se atribuye a cada uno; siempre en fichas con un lote como los de la sección 5):

| Dónde | Llamada a `inferir` |
|---|---|
| Grilla del evento masivo: desglose del remanente y filtro "Revisar la ficha" | `detalle_evento_masivo_screen.dart` ~384 |
| Planilla de mora en PDF | ~384 → ~2752 |
| Ventana de cobro: tildes del remanente, **monto de cada tilde** y concepto de los cobros nuevos | ~5264 |
| Estado de cuenta en PDF | ~9109 |
| Pie del recibo "Mora no cobrada al pagar" (nuevo y reimpreso) | ~9307 |
| Perdón de mora: tildes y **monto de cada tilde** | `perdonar_mora_alumno_dialog.dart` ~176 |
| Mi Empresa → cobro de masivos | `cobro_masivos_tab.dart` ~895 |
| Reimpresión de líneas de mora | `concepto_pago_display.dart` ~1078, 1109, 1122 |

**No cambia:**

- La base: ningún SQL, ninguna migración, ningún `UPDATE` ni recovery.
- `postCobroTrackedOffset`, `calcularDesglose`, `desglosePendiente`, `recalcularSaldoDesdePagos`,
  `MoraTrackedRecovery.recomputarDesdeHistorial`, `reconciliarTodos` y `reconciliarMesas*`. Ninguno llama a `inferir`.
- `mora_pendiente_tracked`, `mora_cobrada_offset`, `saldo_deudor` y lo ya guardado en `pagos_contrato_alumno`.
- El formato de los conceptos que se guardan.
- `revision_mora.txt` (`fichasSinExplicar`, línea 891, solo lee y depende de la suma).

> **No correr `tool/reconciliar_rotulos_mora.dart`** ni antes ni después de este cambio. Usa `inferir` (134, 218, 229),
> **reescribe conceptos en `data.db` y vacía `_sync_queue`** (471-495). Si algún día hace falta, va en una revisión aparte.

### 4.1 Parte B: la reimpresión de las líneas mixtas

Hoy la reimpresión de una línea mixta contradice al papel original y a la ficha nueva:

- `_repartirMoraMixtoSiAplica` (`concepto_pago_display.dart` ~1049-1105) la reparte **calendario primero**.
- `_numeroCuotaCalendarioDesdeConcepto` (~970-975) usa `cuota\s*(\d+)`, que no reconoce `cuotas 3, 4`.

Ejemplos (familias inventadas, mismas formas que en la base):

- Línea `Interés mora cuota 7 (vto Oct 2026) + mora pendiente cuota 6` por $1.910, con un arrastre de la 6 de $1.100. Hoy
  se reimprime "Interés mora cuota 7 (parcial) $1.910" y nada de la 6. Tiene que salir la cuota 6 $1.100 y la cuota 7
  $810 (parcial).
- Línea `Interés mora cuotas 3, 4 + mora pendiente cuota 2` por $75.000. Hoy se reimprime "Mora pendiente cuota 2 $350 +
  Mora pendiente de cuotas ya pagadas $74.650". Tiene que salir la cuota 2 $350, la 3 entera y la 4 (parcial) con el resto.

**Arreglo, en esta misma versión:**

- Reimprimir con la misma regla de 3.1: desde el 21/08/2026, arrastre = `min(monto, Σ de inferir con antesDe)` y
  calendario = el resto; antes de esa fecha, al revés.
- Leer los números de calendario con la regex de `cuotasDeCalendarioEnConcepto`.

### 4.2 Parte C: el estado de cuenta nombra el mes de cada cuota del arrastre

Pedido del usuario del 14-nov, comparando estados de cuenta (botón de la fila de la grilla): en la mayoría, la fila de mora
dice la cuota **y su mes**; en una fila de cobro del arrastre, no.

**Por qué:**

- Las filas de mora del calendario traen el mes en el propio concepto: `Interés mora cuota 3 (vto Jun 2026)`.
- Las del arrastre no lo traen. `MoraConceptoRotulo.rotuloFichaMora` arma el título solo con el texto del concepto, y sale
  `Mora de las cuotas 1 y 2` o `Mora de la cuota 1`, sin mes.
- Lo mismo pasa con el sufijo de las mixtas: `… + mora pendiente cuota 6`.

**Arreglo** (solo lo que se muestra; el concepto guardado no cambia, porque es la clave que se lee al reimprimir):

- `rotuloFichaMora` recibe el contrato y nombra cada cuota con su vencimiento, con el mismo formato que las filas del
  calendario: **`Mora cuota 1 (vto Abr 2026) y cuota 2 (vto May 2026)`**. El subtexto queda igual ("Quedaba de cuando se
  pagaron esas cuotas · se cobró en este pago").
- En las mixtas: **`Interés mora cuota 7 (vto Oct 2026) + mora cuota 6 (vto Sep 2026)`**.
- El mes sale de `MoraCuotaCalculator.vencimientoCuotaDesdeRegAr` (alta del contrato + número de cuota), con el formato de
  `calcularDesglose` (`Abr 2026`). Sin fecha de alta, queda como hoy.
- Su único llamador es `ConceptoPagoDisplay.enriquecerPagosHistorial` (`concepto_ficha`, línea ~301), que alimenta el diálogo y
  el PDF del estado de cuenta.

---

## 5. Por qué solo algunas fichas, y cuáles (base real, 14-nov, solo lectura)

Para que una ficha muestre mal el remanente tienen que pasar **tres cosas juntas**:

1. en un mismo día se liquidan cuotas **y** entra mora;
2. la mora que entra **no alcanza para todo** (queda remanente);
3. alguna línea dice a qué va (el arrastre, o una cuota que no es la más vieja del lote), y hoy se reparte distinto.

Además, la ficha tiene que **seguir teniendo remanente hoy**. Si la familia pagó todo después, se ve bien aunque la cuenta
sea la misma.

**En la base:**

- **81 lotes en 69 contratos** liquidan cuota base y tienen una línea de mora que nombra el arrastre (por día AR, sin
  anuladas). **46 son anteriores al 21/08/2026.**
- Hay unos **10 lotes** más donde una línea de calendario nombra una cuota que no es la más vieja del lote.
- Casi todos esos contratos tienen hoy el remanente en 0, así que no se nota.

**5 fichas lo muestran mal hoy, de 36 con remanente.** El usuario las conoce por nombre; acá no van.

| Forma | Fichas | Qué muestra hoy | Qué va a mostrar |
|---|---|---|---|
| Pagó el arrastre viejo entero y no la mora de las cuotas que liquidó (F1) | 1 | meses ya pagados | las cuotas que liquidó ese día |
| Línea mixta parcial (calendario + arrastre) | 2 | el mes del arrastre, ya pagado, y montos corridos | solo lo que de verdad falta, en su cuota |
| Línea solo de arrastre que nombra la cuota, con un perdón antes (F5) | 1 | los montos de cada mes cambiados | cada mes con su monto, y "se cobró" correcto |
| Línea de calendario que nombra la cuota más nueva del lote (F4) | 1 | la mora de esa cuota, ya pagada | la mora de la cuota más vieja, que es la que falta |

En las 5 la suma no cambia.

---

## 6. Verificación hecha (14-nov)

- **Dos simulaciones independientes.** Dos agentes portaron a Python, cada uno por su lado, `inferir` y todo lo que usa
  (`calcularDesglose` con exención y mora congelada, `desglosePendiente`, `postCobroTrackedOffset`,
  `recalcularSaldoDesdePagos`). Las corrieron sobre los pagos reales de las 36 fichas con remanente.
  - **El port es fiel:** el `tracked` del re-juego más `mora_tracked_ajuste` da `mora_pendiente_tracked` en las 36, y el
    `mora_cobrada_offset` coincide en las 36.
  - **Con la regla nueva cambian exactamente 5 fichas**, las de la sección 5, con los mismos montos en las dos
    simulaciones. La suma y `sinExplicar` dan igual en las 36.
  - En las 5, el desglose nuevo **no nombra como pendiente ningún mes que un concepto diga que se cobró**.
- **La regla final**, línea por línea y con el orden por fecha, se volvió a correr sobre las 36: siguen cambiando solo esas
  5, con los mismos montos. En la ficha de F5 ahora también da bien el "se cobró".
- **Revisión adversarial:** el invariante de 3.4 queda demostrado, los números de los tests coinciden con las reglas del
  código y los formatos reales están clasificados (3.2). Sus correcciones están incorporadas acá.

---

## 7. Pruebas

### 7.1 Tests (`test/mora_tracked_origen_arrastre_test.dart`)

Familias inventadas: `ContratoAlumno` armado a mano, con alta el 30/03/2026, 9 cuotas de $30.000 y **`saldoDeudor` mayor que
0** (con 0, `calcularDesglose` devuelve vacío). Los pagos van como `Map`, con `fecha_pago` en ISO con `-03:00`. La regla de
hoy va copiada **solo en el test**, como `_inferirHoy`.

| # | Caso | Esperado (regla nueva) | Hoy |
|---|---|---|---|
| 1 | **F1 ficha** (`loQueQueda`, `trackedMonto` 71.700, `saldoDeudor` 149.900) | C3 `Jun 2026` $40.500 135d (debida 40.500, cobrada 0) · C4 `Jul 2026` $31.200 104d (cobrada 0). `sinExplicar` 0 | C1 24.300 · C2 15.000 · C3 1.200 · C4 31.200 |
| 2 | **F1 recibo del 12/11** (`antesDe` = medianoche AR del 12/11, `DateTime.utc(2026,11,12,3)`; `excluirPagoId` = la línea; `trackedMonto` 39.300; `loQueSeCobra`) | C1 `Abr 2026` $24.300 81d · C2 `May 2026` $15.000 50d | igual |
| 3 | **F2:** remanente de la C1 abierto; después un lote con `Cuota Base (3/9)` + `Interés mora cuota 3 (vto Jun 2026)` por toda la mora de la 3 | igual que hoy | — |
| 4 | **F3, desde la v4.9:** C1 pagada el 30/05, 30 días tarde y sin mora (arrastre $9.000); C2 el 30/05 y C3 el 30/06, a tiempo; el 09/09, `Cuota Base (4/9)` (40 días, $12.000) + `Interés mora cuota 4 (vto Jul 2026) + mora pendiente cuota 1` por $15.000 (`trackedMonto` 6.000) | C4 $6.000 40d (debida 12.000, cobrada 6.000) | C1 $6.000 (cobrada 3.000) |
| 5 | **F3 antiguo:** igual, pero C3 el 09/08 (40 días) + `Interés mora cuota 3 (vto Jun 2026) + mora pendiente cuota 1` por $15.000 | igual que hoy: C1 $6.000 (es anterior al 21/08) | C1 $6.000 |
| 6 | **F4:** C1 a C4 pagadas antes de vencer; el 20/10, `Cuota Base (5/9)`, `Cuota Base (6/9)` e `Interés mora cuota 6 (vto Sep 2026)` por $6.000 (`trackedMonto` 15.000) | C5 $15.000 50d (cobrada 0) | C5 $9.000 + C6 $6.000 |
| 7 | **F5:** C1 pagada el 30/05 y C2 el 30/06, cada una 30 días tarde y sin mora ($9.000 y $9.000); perdón de los $9.000 de la C1 (fuera de los pagos); el 09/09, `Cuota Base (3/9)` (71 días, $21.300) + `Mora pendiente cuota 2 (no cobrada al pagar)` $9.000 (`trackedMonto` 21.300) | C3 $21.300 71d (cobrada 0) | C2 $9.000 + C3 $12.300 |
| 8 | **Helpers:** todos los formatos de la tabla de 3.2, con y sin acentos y en mayúsculas | lo que dice la tabla | — |
| 9 | **La suma no cambia:** en los casos 1 y 3 a 7, la suma de los orígenes es igual con las dos reglas | igual | — |
| 10 | **Parte B:** reimpresión de las dos líneas mixtas de 4.1 | lo que dice 4.1 | — |
| 11 | **Parte C:** con alta el 30/03/2026, `Mora pendiente cuotas 1 y 2 (no cobrada al pagar)` → `Mora cuota 1 (vto Abr 2026) y cuota 2 (vto May 2026)`; `Mora pendiente cuota 3 (no cobrada al pagar)` → `Mora cuota 3 (vto Jun 2026)`; `Interés mora cuota 7 (vto Oct 2026) + mora pendiente cuota 6` → `Interés mora cuota 7 (vto Oct 2026) + mora cuota 6 (vto Sep 2026)`; `Interés mora cuota 3 (vto Jun 2026)` queda igual | lo que dice | sin mes en el arrastre |

Los casos 1 y 4 a 7 se corrieron el 14-nov con la simulación de la sección 6 y dan lo que dice la tabla.

### 7.2 El comparador sobre la base real (`tool/rotulo_mora_antes_despues_test.dart`)

Mismo patrón que `tool/cobro_igual_que_hoy_test.dart`: trabaja sobre una copia hecha con `VACUUM INTO`, **nunca abre la
base real**, la nube apunta a `http://localhost:1` y escribe solo en la carpeta `salida`, afuera del repo. **A diferencia
de ese tool, tiene que cargar la mora congelada (`MoraCongelada`) como la app**: hay 48 contratos con pausas.

```
flutter test tool/rotulo_mora_antes_despues_test.dart
  --dart-define=copia=<data.db copiada con VACUUM INTO>
  --dart-define=salida=<carpeta fuera del repo>
```

Para cada contrato compara, con `_inferirHoy` (regla vieja, solo dentro del tool) contra la nueva:

1. **La ficha:** `inferir(loQueQueda, trackedMonto: mora_pendiente_tracked)`.
2. **Cada línea de mora del historial:** lo que imprime la reimpresión (con la parte B).

**Se frena** (falla) si:

- en alguna llamada la suma de `montoAtribuido` difiere en más de 0,01;
- `sinExplicar` cambia en alguna ficha;
- cambia algo en un contrato en el que ningún lote se reparte distinto (el tool anota cada lote que cambia);
- cambia la ficha en **más de las 5** esperadas: no es un error seguro, pero se frena para que el usuario mire las que sobran;
- en las reimpresiones, los números de cuota que nombra el detalle coinciden con los del concepto guardado **menos veces**
  que hoy.

**Informe** (`salida/rotulo_mora.txt`, con nombres porque queda afuera del repo): un renglón por ficha que cambia, con el
antes y el después, y el conteo de coincidencias con el concepto guardado. El usuario lo lee antes de publicar.

---

## 8. Probar y publicar, paso a paso (como siempre)

Todo con los pasos de siempre del proyecto (`CLAUDE.md`, sección SQL, y "Cómo se publicó" de los CONTEXTO de la 6.7.0 y la
6.8.0). **Esta versión no lleva SQL ni toca datos de la nube.** Lo único que se escribe en la nube son las fotos de la mora,
como en cada versión.

### 8.1 Mientras se programa (en esta PC, nunca contra la base real)

1. Rama `feature/v4.6-cierre-por-sesiones`. Versión nueva en `pubspec.yaml` y en `installer/junior_eventos_setup.iss`, iguales.
2. Los tests de la sección 7.1, primero en rojo con la regla de hoy y después en verde.
3. **`flutter test` entero en verde.** Hoy son 4.670: no puede fallar ninguno de los que ya existían.
4. **`flutter analyze` sin errores ni avisos nuevos.** No corre en sesiones remotas: va en esta PC.
5. Un commit por parte (A, B y C), con el mensaje en castellano y **sin nombres ni datos de alumnos**.

### 8.2 La prueba con los datos reales, sin tocar nada

1. **Copia de la base:** `data.db` copiada con `VACUUM INTO` desde la PC del jefe, con la app cerrada o sin cobros en curso.
   Todo lo que sigue trabaja sobre copias de esa copia, en carpetas temporales. La nube apunta a `http://localhost:1`.
2. **El comparador (7.2)** sobre la copia. Tiene que pasar todas sus condiciones. El informe (`salida/rotulo_mora.txt`)
   va afuera del repo.
3. **Los papeles de antes y después** de las 5 fichas, en PDF en `salida/`, armados con la versión de hoy y con la nueva
   sobre la misma copia:
   - el estado de cuenta;
   - la reimpresión del recibo del cobro que generó el error;
   - la planilla de mora de su institución.

   Con `palabrasDelPdf` (`test/helpers/leer_pdf.dart`), comprobar que nombran los meses de la sección 5 y que no se corta
   nada.
4. **Capturas de las 5 fichas** sobre la copia, de la versión de hoy y de la nueva: la grilla, la ventana de cobro (los
   tildes del remanente y sus montos) y el perdón. **El usuario las quiere ver antes de aprobar** (las mira en el celular).
5. **Se le pasa al usuario:** el informe del comparador, los PDF y las capturas, y lo que no se pudo probar. Sin su OK no
   se publica.

### 8.3 Publicar, con su "publicá" y con él presente

1. **Que nadie esté cobrando:** mirar el último latido de cada caja y la última ficha tocada, como el 11-nov.
2. **Respaldo:** el de Supabase, más la copia del `data.db` de cada PC.
3. **Foto de la mora "antes de X.Y.Z"** (`supabase/mora_fotos.sql`, sección 2, por el conector), comparada con la anterior
   (sección 3). Si lista a alguien, explicarlo antes de seguir: un cobro del día que no saldó toda la mora no es una mora
   revivida.
4. **`flutter test` entero otra vez**, antes de compilar.
5. **El instalador, por pasos**, con las comprobaciones de siempre: que el programa diga la versión nueva, la página del
   celular entera antes de `ISCC` (misma lista de archivos que la 6.8.0), la clave de firma y `apksigner` del APK. Los
   registros, en `build/armado_XYZ/`.
6. **Tag `vX.Y.Z`**, release con el Setup y el APK, y las novedades. Texto propuesto: "Correcciones en la mora de la ficha
   y del estado de cuenta", a confirmar con él. **Sin nombres.**
7. **Web en Vercel**, en producción. Que `version.json` diga la versión nueva. Anotar el despliegue anterior para volver
   atrás.
8. CONTEXTO de la versión, que empieza con "Para retomar en otro chat", y su entrada en `CLAUDE.md`.

### 8.4 Instalar y comprobar

1. **Primero la PC del jefe.** Abrir las 5 fichas: grilla, ventana de cobro (tildes y montos), perdón, planilla de mora,
   estado de cuenta (con el mes de cada cuota en las filas del arrastre) y pie del recibo. Tienen que nombrar los meses
   que de verdad se deben, con el mismo total que antes.
2. **Después las otras dos PCs y las tablets, el mismo día** si se puede. El rótulo se calcula en cada PC y no viaja por
   la nube: una PC sin actualizar sigue mostrando los meses mal y los imprime en sus recibos.
3. **Foto de la mora "después de X.Y.Z"** y la comparación con la de "antes". Lo esperado: nada sospechoso, porque esta
   versión no cambia ningún monto. Si `mora_cambios` muestra una escritura de la mora que no sea un cobro, un perdón o
   la revisión de siempre, se frena y se mira.
4. Preguntarle al usuario cómo se ven las 5 fichas en cada PC.

### 8.5 Si algo sale mal

- **No hay datos que restaurar:** la versión no escribe nada nuevo.
- **Volver atrás:** reinstalar el Setup de la 6.8.0 en las PCs y, en Vercel, promover el despliegue anterior anotado en 8.3.
- Si aun así una mora cambiara, la sección 4 de `supabase/mora_fotos.sql` vuelve a ese alumno a la foto de antes, con su
  OK en el momento.

### 8.6 Mientras no esté instalado

En esas 5 fichas, si la familia viene a pagar el remanente: cobrar **todo el remanente**, porque el total está bien, y no
por tilde suelto. Avisar que el texto del recibo nombra mal los meses. No usar el perdón por mes.

---

## 9. Lo que NO se toca, y límites conocidos

**No se toca:** nada de la plata (`postCobroTrackedOffset`, `EstadoMoraPostCobro`, `calcularDesglose`, exención, congelado,
offset); cómo se escribe el concepto (`MoraConceptoRotulo`); la rama "solo mora" de `inferir`; el recorte `loQueQueda`; la
cola de subida, el pulso y las sesiones de caja.

**Límite conocido: perdones.** `inferir` rearma la historia **solo con los pagos**. Los perdones (`mora_tracked_ajuste`) no
tienen fecha y no entran. En una ficha con perdón, **el monto y el mes del remanente dan bien** (el recorte `loQueQueda` lo
descuenta al final), pero el subtexto ("tantos días tarde", "se cobró $X de los $Y") puede no coincidir. Ejemplo: un cobro
"solo mora" que nombra una cuota del calendario, hecho después de un perdón, el re-juego lo manda al arrastre ya perdonado.
Pasa hoy igual, y este arreglo no lo empeora.

**Ticket aparte, no en esta versión.** `_esBaseCuota` (`mora_tracked_origen.dart` 173-196, idéntico en
`mora_tracked_recovery.dart` 63-86) cuenta como cuota base líneas de mesa y sillas: `… — Completada`, `N Cuotas (Mesa Extra)`
y `Cuotas Mesa Extra (…)`. Eso crea cuotas fantasma en unos 7 lotes de la base. Como `recomputarDesdeHistorial` comparte ese
código, **puede tocar plata**. En las 36 fichas con remanente el re-juego coincide con la base, pero hay que revisarlo en
otro trabajo.

---

## 10. Para confirmar con el usuario

- **Antes de programar:** nada bloqueante.
- **Antes de publicar (8.2):** el informe del comparador, los PDF y las capturas de antes y después de las 5 fichas, y su OK.
- **Al publicar (8.3):** su "publicá", con él presente, y el texto de las novedades.
