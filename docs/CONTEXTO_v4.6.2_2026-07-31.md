# Contexto — Junior Eventos v4.6.2 (31 de julio de 2026)

> **Referencia:** `CONTEXTO_v4.6.2` · `release 4.6.2` · `mora fuera de término` · `viene de qué cuotas` · `recibo reimpreso`
> Si en un chat futuro decís *"leé el contexto de 4.6.2"*, *"lo de fuera de término"* o
> *"por qué el perdón de mora no queda"*, apuntá a este archivo.

**Estado:** **RELEASE** — `4.6.2+29`
**Instalador:** `Setup Junior Eventos v4.6.2.exe` (`installer/dist/` vía `.\installer\build_installer.ps1`)
**Rama:** `feature/v4.6-cierre-por-sesiones`

Release de **papeles**: todo lo que cambia acá es lo que lee la familia. No se
tocó ningún cálculo de montos, saldos ni mora.

---

## Qué incluye este release (desde 4.6.1 → 4.6.2)

### 1. La mora se llama "por pagar fuera de término"

Antes convivían tres nombres para lo mismo: *"interés por pagar tarde"*,
*"interés por atraso"* e *"INTERESES POR ATRASO"*. Ahora es **"interés por pagar
fuera de término"** en todos los papeles y en la pantalla de cobro.

`"días de atraso"` (el conteo de días) se mantiene: es el dato, no el nombre del
interés.

### 2. Los PDFs no repiten lo mismo tres veces

Regla que quedó aplicada y escrita en comentarios:

> **El rótulo identifica, el subtexto explica, la definición va una sola vez por documento.**

Menciones de la definición de mora, antes → después:

| Documento | Antes | Ahora |
|---|---|---|
| Recibo de pago | 5 | 1 (pie de la tabla del plan) |
| Resumen a abonar | 2 | 1 (recuadro rojo) |
| Estado de cuenta | 3 | 1 (fila "Mora pendiente") |

Además se eliminó la duplicación literal por línea: el rótulo decía *"Mora
(interés por atraso, 27 días)"* y justo debajo el subtexto repetía *"27 días de
atraso"*. Ahora la línea es una sola: **`Mora — 27 días fuera de término`**. Se
ahorra un renglón por cada mora impresa.

También se corrigió un desborde: `"sin interés por pagar fuera de término"` no
entraba en la columna Balance del recibo (ancho fijo 120 pt, 5,5 pt); ahora dice
`"por pagar fuera de término"` / `"al día"`.

### 3. El aviso de mora dice de qué cuotas viene

Antes: **`Viene de: de cuotas ya pagadas $ 15.000,00`** — con el "de" duplicado y
sin nombrar nada.

Ahora: **`Viene de: cuota 2 (May, 23 d) $ 6.900,00 · cuota 3 (Jun, 27 d) $ 8.100,00.`**

Dos cambios lo hacen posible:

- **`origenMoraPendienteLinea`** acepta el desglose del tracked
  (`MoraTrackedOrigen`), ordena de la cuota más vieja a la más nueva sin importar
  si ya está pagada, y reparte el corte de 3 cuotas entre calendario y arrastre.
  Si no se puede reconstruir, cae en `"interés de cuotas ya pagadas $X"` (bien
  escrito, sin inventar cuotas).
- **La línea se arma al generar el PDF**, no en el modal: ahí el cobro ya está
  guardado. Desde el modal se perdía la cuota que se acababa de liquidar.

Resguardos: si el recálculo no coincide con el monto que trae el modal se
conserva la línea del modal (manda el número impreso), y si la consulta falla
sale el recibo igual con la línea vieja (salvo que el monto de mora todavía no se
conozca, ahí sí aborta: un recibo sin aviso de mora es peor que uno que no sale).

### 4. Fix: la exención borraba el origen de la mora

**Causa raíz de los 6 contratos que no se podían reconstruir.**
`MoraTrackedOrigen.inferir` replayea el historial, pero le pasaba a cada estado
del pasado la exención de **hoy**. Con la exención puesta, el desglose de aquel
mes daba cero y el tracked quedaba sin cuota que lo explicara.

`MoraTrackedRecovery.recomputarDesdeHistorial` ya lo hacía bien (reconstruye la
exención cronológicamente). `inferir` quedó alineado con esa regla.

**Resultado sobre la base real: 286/286 contratos con mora nombran sus cuotas
(antes 280), 0 descuadres entre lo atribuido y el tracked.**

Esto también mejora el arrastre que se ve en la grilla y en el modal de cobro,
que usan la misma función.

### 5. El recibo reimpreso lleva la fecha del pago

El botón "imprimir recibo" de la grilla rearma el recibo desde el último lote de
pagos, pero no le pasaba ni la fecha del pago ni la marca de reimpresión: un pago
del 27/07 salía fechado *"Operación gestionada el 31 de julio"* y afirmando la
mora de hoy.

Ahora toma la fecha real del lote y decide sola:

- Lote **de hoy** → se comporta como el original (muestra la mora), fechado con
  la hora real del cobro.
- Lote **de otro día** → sale como *"Reimpreso el DD/MM (Original: DD/MM)"* y no
  afirma la mora de hoy. El PDF ya tenía ese rótulo; nadie le pasaba el dato.

### 6. Herramienta: `tool/verificar_origen_mora_recibo_test.dart`

Imprime el recuadro de mora tal como va a salir en el papel, para todos los
contratos o para uno, **sin hacer un cobro de prueba**. Solo lectura.

```
flutter test tool/verificar_origen_mora_recibo_test.dart
flutter test tool/verificar_origen_mora_recibo_test.dart --dart-define=NOMBRE=bernel
```

Falla si lo atribuido a las cuotas no suma el tracked, así que sirve de chequeo
después de tocar cualquier cosa de mora.

---

## Auditoría de mora en Mi Empresa — PENDIENTE, no arreglado

Se auditó "perdonar mora" y "poner mora por días/monto"
(`restaurar_mora_dialog.dart`). Hallazgo, con prueba sobre datos de Bernel
(historial que implica tracked $15.000):

> **Todo lo que escribe `mora_pendiente_tracked` se revierte solo en la próxima
> sincronización.**

Después de cada pull, el sync corre `MoraTrackedRecovery.reconciliarTodos`
(`sync_engine.dart:763`), que recalcula el tracked desde el historial de pagos y
lo **pisa sin condición** (`mora_tracked_recovery.dart:511`). La exención está
protegida por `resolverExencionPreservandoLocal`; el tracked **no**.

| Acción admin | Queda guardado | Lo que escribe la reconciliación |
|---|---|---|
| Perdonar solo ficha | $0 | **$15.000** ← vuelve |
| Perdonar cuotas + ficha | $0 + exención | exención se respeta, tracked **vuelve** |
| Poner mora a mano $40.000 | $40.000 | **$15.000** ← se pisa |
| Mover fecha de Reg | — | **sobrevive** ✅ |

**Mientras no se arregle: el único ajuste durable de mora es mover la fecha de
Reg.** Cambia los vencimientos y el replay lo respeta.

El código ya lo tenía anotado (`mora_cuota_calculator.dart:975`: *"necesita un
marcador propio antes de que la reconciliación retroactiva se corra en
producción"*). Lo nuevo es que **ya se está corriendo**, no solo en la migración
sino en cada pull, y que afecta también a "poner mora a mano", no solo al perdón
de ficha.

**Arreglo propuesto (postergado por decisión del 31-jul):** columna nueva que
registre el ajuste admin (perdonado / puesto a mano) para que la reconciliación
no lo resucite. Implica migración local + campo en el modelo + columna en
Supabase + mapeo de sync.

**Menor, del mismo audit:** la vista previa de "restaurar mora" muestra solo el
monto que va a escribir, no la mora operativa resultante. Como el tracked se
**suma** a la mora de calendario, si el contrato tiene cuotas vencidas la familia
queda debiendo más que lo tipeado. El panel de perdón sí lo muestra bien
(`Mora operativa: X → Y`); el de restaurar debería copiar ese patrón.

---

## Pendiente cosmético conocido

En el recibo rearmado desde la base, la cuota sale como *"Cuota 3 de 9"* sin el
*"— venció 30/06/2026"*. La línea reconstruida no trae el número de cuota como
dato (solo el texto `"Cuota Base (3/9)"`), así que el rótulo cae en la rama que
no calcula el vencimiento. Desde el modal de cobro sí sale con la fecha.

---

## Archivos tocados

| Archivo | Qué |
|---|---|
| `lib/features/common/services/pdf_service.dart` | Terminología, redundancias, textos de los 3 papeles |
| `lib/features/eventos/services/cobro_masivo_conceptos_pdf.dart` | `_displayMora`: rótulos cortos, sin repetir el subtexto |
| `lib/features/eventos/services/mora_concepto_rotulo.dart` | `origenMoraPendienteLinea` con `trackedDetalle` + orden por cuota; sin subtextos duplicados |
| `lib/features/eventos/services/mora_tracked_origen.dart` | **Fix exención en el replay** |
| `lib/features/eventos/detalle_evento_masivo_screen.dart` | "Viene de" al generar el PDF; fecha/reimpresión del recibo rearmado |
| `tool/verificar_origen_mora_recibo_test.dart` | Herramienta de verificación (nueva) |

Tests: **180/180**. Analyzer sin issues nuevos.

---

## Versiones

| Fecha | Versión | Notas |
|-------|---------|--------|
| 23-jul-2026 | 4.5.2+26 | Fix sync operador Modo jefe + migración v66 |
| 24-jul-2026 | 4.6.0+27 | Caja jefe explícita + PDFs cierre por sesión |
| 27-jul-2026 | 4.6.1+28 | Operario edita base + aviso abrir caja |
| **31-jul-2026** | **4.6.2+29** | **Release** — papeles: mora fuera de término, sin redundancias, "viene de" con cuotas |

## Contextos relacionados

- `docs/CONTEXTO_v4.6.1_2026-07-27.md`
- `docs/CONTEXTO_MORA_OPERATIVA.md` (v54 carry-over)
- `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md`
