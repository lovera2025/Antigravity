# SPEC — La mora cobrada de una cuota que no se completa se vuelve a pedir

> **Decidido el 6-nov a la noche (el usuario):** sale sola, en el **parche 6.3.2**, desde la rama `release/6.3.x`
> (creada desde el tag `v6.3.1`, en la carpeta `..\arguello_events_6.3.x`), con meta el **lunes 9-nov**. Es la opción (a) de la
> sección 7. Cada commit va también a `feature/v4.6-cierre-por-sesiones`. Después sale la 6.3.3 con el sync en reposo
> (`docs/PLAN_SYNC_EN_REPOSO_2026-11-06.md`); la barra 5-10 y Entradas 4-6 esperan.
>
> **Hecho el 6-nov (noche):** el arreglo, las 10 pruebas de `test/mora_adelantada_cuota_abierta_test.dart` (8 vistas en rojo
> antes), la costura `cuenta` en `MoraTrackedRecovery` y el simulacro `tool/simulacro_mora_adelantada_test.dart`, que carga la
> mora congelada (el viejo `tool/simulacro_revision_mora_test.dart` no la cargaba). Lo que falta y quién lo hace, en el
> CONTEXTO de la 6.3.2.

Fecha: 6-nov-2026 · Rama: `feature/v4.6-cierre-por-sesiones` (pubspec 6.3.1+63) · Prioridad: alta (se cobra todos los días)

> **Revisada el 6-nov a la noche contra el código de la rama y contra la nube.** Lo que dice la sección 1 coincide con `contratos_alumnos` en Supabase (`cuotas_pagadas 3`, `saldo_deudor 200900`, `mora_cobrada_offset 130900`, `mora_pendiente_tracked 0`, `mora_exenta_hasta null`). La causa de la sección 2 es la línea 464-466 de `mora_cuota_calculator.dart` tal cual. La fórmula de la sección 4 se simuló a mano con los casos 1, 3 y 5 de los tests y da 98.000 / 130.900 / 15.000. Lo agregado en la revisión va marcado **[Revisión]**.

## 1. El caso que lo destapó

**LOPEZ, MORENA AILEN** — GREGORIA MORALES — contrato `31f442c5-de9d-479b-842d-e8ecd1baeb91`

- Plan base $315.000 en 9 cuotas de $35.000. Alta 30/03/2026: la cuota N vence el último día del mes `marzo + N`.
- Mora congelada "Todas" desde el 2/11 (`mora_congelada.pausas = [{cuota: null, desde: 2026-11-02}]`).
- Antes del cobro: 1 cuota paga más $10.000 a cuenta de la C2. Capital $270.000.

Mora al 6/11, a $350 por día con los días contados hasta el 2/11:

| Cuota | Vence | Días | Mora |
|---|---|---|---|
| C2 | 31/05 | 155 | $54.250 |
| C3 | 30/06 | 125 | $43.750 |
| C4 | 31/07 | 94 | $32.900 |
| C5 | 31/08 | 63 | $22.050 |
| C6 | 30/09 | 33 | $11.550 |
| C7 | 31/10 | 2 | $700 |
| **Total** | | | **$165.200** |

Total antes: $270.000 + $165.200 = **$435.200** (coincide con lo que mostró la app).

**El cobro del 6/11 ($200.000, efectivo, un solo lote):**
- $25.000 — Cuota Base (2/9), completada
- $35.000 — Cuota Base (3/9)
- $9.100 — Entrega parcial, Cuota Base (4/9)
- $130.900 — Interés mora cuotas 2, 3, 4 (vto May, Jun, Jul)

**Después del cobro:** la app muestra **$268.100**. Lo correcto es **$235.200** ($200.900 de capital + $34.300 de mora de C5, C6 y C7).

**La diferencia de $32.900 es la mora de la C4**: se cobró hoy y se vuelve a pedir.

Estado actual en la nube: `cuotas_pagadas 3`, `saldo_deudor 200900`, `mora_cobrada_offset 130900`, `mora_pendiente_tracked 0`, sin eximición. En `mora_cambios` (id 76) se ve el offset pasar de 0 a 130900 en ese cobro.

**[Revisión] El congelamiento no tiene nada que ver.** Sin congelar, el error es el mismo; lo único que cambia es que los $32.900 de la C4 seguirían creciendo $350 por día. El cobro del operador estuvo bien hecho.

## 2. La causa

En `MoraCuotaCalculator.postCobroTrackedOffset` (`lib/features/eventos/services/mora_cuota_calculator.dart`), la rama `cuotasBaseLiquidadasEnCobro > 0` hace:

```dart
tracked = (remanenteCarry + moraLiquidadasNeto - moraEsteCobro).clamp(0.0, double.infinity);
if (moraEsteCobro > 0.01) {
  offset = moraCobradaOffsetActual + moraEsteCobro;   // ← toda la mora cobrada
}
```

El offset ("ya usado") absorbe **toda** la mora del cobro: $130.900. Pero solo $98.000 eran de cuotas que se cerraron (C2 y C3). Los $32.900 restantes eran un **adelanto de mora de una cuota que sigue abierta** (la C4).

Como la C4 sigue impaga, `calcularDesglose` vuelve a arrancar en la C4. El crédito FIFO que tendría que descontarla es `historial − offset = 130.900 − 130.900 = 0`. Resultado: la mora de la C4 aparece entera de nuevo.

No hay eximición que lo tape, porque el cobro no saldó toda la mora (faltaban C5, C6 y C7). Cuando se salda todo, el bloque de la eximición pone `offset = todoCobrado` y corre la fecha, y ahí el problema no se ve.

**Un solo punto de arreglo.** Los cuatro lugares que deciden la mora después de un cobro pasan por esta función:
- `cobro_mora_resolver.dart:99` — el cobro en vivo.
- `MoraTrackedRecovery.recomputarDesdeHistorial` (`mora_tracked_recovery.dart:181`) — la revisión al abrir la app.
- La copia del replay en `mora_tracked_recovery.dart:570` — anular un cobro.
- `mora_tracked_origen.dart:356` — de dónde sale el tracked.

**Por eso un UPDATE a mano no sirve:** la revisión de la mora (`SyncEngine.revisarMora` → `reconciliarTodos`) recalcula el offset desde el historial con la misma función y vuelve a dejar 130.900.

## 3. Segundo problema, del mismo lugar (hay que arreglarlo junto)

Si solo se arregla lo de arriba, a Morena le queda un crédito FIFO de $32.900 sobre la C4. Cuando complete la C4 en otro cobro sin mora, esa rama hace `tracked = carry + moraLiquidadasNeto` (el neto de la C4, que da $0) y **no mueve el offset**. El crédito de $32.900 sigue vivo y, con la C4 fuera del desglose, se descuenta de la **C5**. Sería un cobro de menos.

Esto ya puede pasar hoy, sin el arreglo, con cualquier mora parcial. Ejemplo: se pagan $15.000 de mora sobre la C3 (rama "solo mora": si no cubre el desglose entero, el offset no se mueve, `mora_cuota_calculator.dart:481`), después se completa la C3 sin mora, y los $15.000 se vuelven a descontar de la C4. Es lo que razoné leyendo el código: **confirmarlo primero con un test en rojo**.

**Regla general que tiene que cumplirse después de cualquier cobro:**
> `historial − offset` (el crédito FIFO) tiene que ser exactamente la mora pagada por adelantado de cuotas que **siguen abiertas**. Ni más ni menos.

## 4. El cambio

Solo en la rama `cuotasBaseLiquidadasEnCobro > 0` de `postCobroTrackedOffset`. La rama "solo mora" y el bloque de la eximición quedan como están.

```dart
final cuotasPreCobro = cuotasBasePagadasPostCobro - cuotasBaseLiquidadasEnCobro;
bool seCierra(MoraCuotaDetalle d) =>
    d.numeroCuota > cuotasPreCobro && d.numeroCuota <= cuotasBasePagadasPostCobro;

final moraLiquidadasNeto = moraDesgloseNetoPreCobro.where(seCierra).fold(0.0, (s, d) => s + d.interesBruto);
final moraLiquidadasBruto = moraDesglosePreCobro.where(seCierra).fold(0.0, (s, d) => s + d.interesBruto);

// (a) Crédito FIFO previo que ya se gastó en las cuotas que se cierran: pasa a "ya usado".
final creditoUsadoEnCerradas = (moraLiquidadasBruto - moraLiquidadasNeto).clamp(0.0, double.infinity);

final remanenteCarry = cuotasPreCobro > 0 ? remanente : 0.0;   // sin cambios
final aCerrar = remanenteCarry + moraLiquidadasNeto;

// (b) Lo cobrado va primero a lo que se cierra (arrastre + cuotas liquidadas)…
final aplicadoACerradas = math.min(moraEsteCobro, aCerrar);
// (c) …y lo que sobra es adelanto de cuotas que siguen abiertas.
final excedente = moraEsteCobro - aplicadoACerradas;
final netoAbiertas = moraDesgloseNetoPreCobro
    .where((d) => d.numeroCuota > cuotasBasePagadasPostCobro)
    .fold(0.0, (s, d) => s + d.interesBruto);

tracked = (aCerrar - moraEsteCobro).clamp(0.0, double.infinity);   // igual que hoy
offset = moraCobradaOffsetActual
    + creditoUsadoEnCerradas
    + aplicadoACerradas
    // Si el excedente cubre TODAS las abiertas, entra al offset (igual que la rama "solo mora"
    // cuando liquida el desglose completo). Si no, queda afuera y el FIFO lo descuenta de la
    // cuota abierta más vieja.
    + (excedente > 0.01 && excedente >= netoAbiertas - 0.01 ? excedente : 0.0);
```

- Redondear como hoy (`toStringAsFixed(2)` al devolver).
- Actualizar el comentario de la función: explicar (a), (b) y (c) y nombrar a LOPEZ, MORENA AILEN como el caso, igual que BERNEL y MOLINA.
- `mora_tracked_origen.dart` replica el corte de las liquidadas alrededor de la línea 375. Revisar que siga cerrando con el nuevo offset; el tracked no cambia.

**[Revisión] Dos cosas que el código de hoy no dice y hay que tener en cuenta:**

1. **La función recibe `moraDesglosePreCobro` (el bruto) pero hoy no lo usa.** El término (a) es el primero que lo lee. Los cuatro llamadores lo pasan de verdad (`desgloseBruto` en `cobro_mora_resolver.dart:105`, `moraDesgloseBruto` en `mora_tracked_origen.dart:362`, `mora_tracked_recovery.dart:187` y `:576`), así que anda. Pero si alguna vez un llamador pasa una lista vacía, `creditoUsadoEnCerradas` da 0 por el `clamp` y el crédito **no se traslada, en silencio**. Agregar al principio de la rama un `assert(moraDesglosePreCobro.length >= moraDesgloseNetoPreCobro.length)` y un test que lo cubra (test 7, abajo).
2. **Con el cambio, un cobro sin mora puede mover el offset** (por el término (a)). Hasta hoy el offset solo cambiaba con `moraEsteCobro > 0.01`. Es lo buscado (sección 3), pero puede hacer saltar tests que no lo esperaban: el que cuenta llamadas en `revision_mora_test.dart` y los de caracterización. Si saltan, frenar y explicar antes de tocarlos; no debilitarlos.

**Fuera de alcance:** la mora de una cuota parcialmente paga sigue calculándose sobre la cuota entera ($35.000). No tocar.

## 5. Tests (primero en rojo, después el arreglo)

Archivo nuevo: `test/mora_adelantada_cuota_abierta_test.dart`.

1. **Morena, la función sola.**
   - Entrada: desglose bruto = neto = C2..C7 de la tabla, offset 0, tracked 0, `moraEsteCobro` 130.900, 2 liquidadas, 3 pagas después, saldo 200.900, fecha 6/11, historial previo 0.
   - Esperado: offset **98.000**, tracked **0**, sin eximición.
   - Aplicarlo al contrato y medir `moraPendienteOperativa` con historial 130.900: tiene que dar **$34.300**.
2. **Morena, el replay entero.**
   - `recomputarDesdeHistorial` con sus 6 pagos reales (sección 1) y la pausa puesta con `MoraCongelada.conPausas`. Fecha del cálculo: 6/11/2026.
   - Esperado: offset 98.000, mora operativa $34.300.
3. **Completar después la C4 sin mora.**
   - Partiendo del estado de (1), un cobro que completa la C4 ($25.900) sin mora, con la C4 todavía congelada.
   - Esperado: offset **130.900**. La mora que queda es C5 + C6 + C7 completas: el crédito **no** pasa a la C5.
4. **Lo mismo pero descongelada.** Si la C4 ganó días desde el 2/11, esos días nuevos (y solo esos) quedan como tracked.
5. **El segundo problema (sección 3).**
   - Mora parcial de $15.000 sobre C3 = 20.000 (rama "solo mora"), después C3 completada sin mora.
   - Esperado: tracked 5.000, offset 15.000, y la C4 se cobra entera.
6. **El excedente cubre todas las abiertas.** El offset absorbe todo y la eximición se comporta como hoy.
7. **[Revisión] Desglose bruto vacío con neto no vacío.** La función tiene que fallar (assert en debug), no devolver un offset sin el crédito.

Además:
- `test/mora_offset_pago_parcial_test.dart` es de caracterización. Sus seis casos tienen que seguir pasando sin tocarlos; con este cambio deberían dar lo mismo. Si alguno cambia, frenar y explicar por qué antes de tocar el test.
- También tienen que seguir en verde, sin debilitarlos: `mora_pendiente_display_test.dart`, `mora_exencion_post_cobro_test.dart`, `revision_mora_test.dart` (incluido el que cuenta las llamadas a `postCobroTrackedOffset`) y `mora_congelada_test.dart`.

## 6. Reconciliación (antes de publicar)

La revisión de la mora corre sola al abrir la app en cada PC (`revisarMora` → `reconciliarTodos`, una vez por sesión, solo con saldo mayor a 0). Sube el offset, el tracked y la eximición, y lo anota en `revision_mora.txt`. **O sea: instalar la versión ya reconcilia a todos.** Por eso hay que saber antes a quién le cambia.

1. **Simulacro sobre una copia de la base real.** Usar `tool/simulacro_revision_mora_test.dart` (copia con `VACUUM INTO`; nunca la base real ni Supabase).
   - Comparar el **objetivo con la regla vieja contra el objetivo con la regla nueva**, contrato por contrato. No contra la ficha actual: así se ve solo el efecto de este cambio y no los desvíos viejos de las altas movidas a mano (ver la cabecera de `mora_offset_pago_parcial_test.dart`).
   - Sacar un CSV en `build/`: nombre, institución, offset viejo → nuevo, mora de hoy vieja → nueva, y a qué grupo pertenece.
2. **Grupo A — se les estaba pidiendo mora ya cobrada** (el caso de Morena). Su mora **baja**. Se aplica sin más.
   - Candidatos que ya vi en la nube con mora cobrada de cuotas sin completar: ESCOBAR ULISES, MELGAREJO MAIARA, FRANCO JUAN NICOLAS, QUIROZ JAQUELINE, PEÑA GAMBOA, CUEVAS, DIAZ RITA, AYALA YAMILA, ROMERO MARIA VICTORIA, MEZA CASTILLO, CORREA, VELAZQUEZ JONATHAN y otros.
   - Muchos seguramente saldaron toda la mora y no cambian. Que lo diga el simulacro.
3. **Grupo B — se les estaba cobrando de menos** (sección 3). Su mora **sube**.
   - **Frenar y mostrarle la lista a Maxi antes de publicar.** Subirle la deuda a una familia es decisión de él (puede preferir perdonar esa diferencia en modo jefe). No aplicar nada automático para este grupo sin su OK.
4. Confirmar que ningún perdón cambió: los que tienen ajuste de ficha conservan su eximición. El simulacro ya lo comprueba.
5. Al publicar, seguir el procedimiento de siempre: foto de la mora "antes de X.Y.Z" (`supabase/mora_fotos.sql`) → instalar las tres PCs y abrirlas → foto "después" → comparar (sección 3 del SQL). Lo único que tiene que aparecer es lo del simulacro. Si cambia algo más, `mora_cambios` dice qué escritura fue.

**Morena no necesita SQL a mano:** con el arreglo, la revisión le deja el offset en 98.000 y la app muestra $235.200.

## 7. Publicación — decisión de Maxi

La rama tiene la barra y la 6.4.0 a medio hacer y sin publicar ("sin apuro de fecha"), y este error pega en los cobros de todos los días. Opciones:

- **(a) Parche 6.3.2 desde el tag `v6.3.1`** con solo este arreglo y sus tests, publicarlo ya, y llevar el commit también a la rama. **[Revisión] Es la recomendada:** el tag existe, el cambio es una función y sus tests, y la rama no está para publicar.
- **(b) Esperar a la 6.4.0.**

Mientras tanto, a mano: en los alumnos del grupo A, cobrar sobre la cuenta correcta y no sobre lo que muestra la app.

**[Revisión] El orden, que no se saltea:** tests en rojo → arreglo → tests en verde → simulacro sobre la copia → lista de los grupos A y B a Maxi → OK → foto "antes de 6.3.2" → instalar las tres PCs y abrirlas → foto "después" → comparar. Sin SQL en la nube: no hay tabla nueva.

**Commit** (efecto para el usuario): "la mora que se cobra por adelantado de una cuota que no se completa ya no se vuelve a pedir".
