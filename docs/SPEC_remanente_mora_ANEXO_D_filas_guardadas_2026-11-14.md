> Versión para el repositorio (es público): los nombres de las familias van como F6 a F10. El original, con los
> nombres, queda fuera del repositorio.

# Anexo D a `SPEC_remanente_mora_por_concepto_2026-11-14.md`: las filas del arrastre ya guardadas

**Fecha:** 14-nov-2026, 14:30. **Base:** tag `v6.8.0` (`680f9f9`). **Datos:** nube, solo lectura, 14-nov.

**Cómo se usa:** va **junto** con la spec principal, en la **misma versión**. Primero se hace la spec principal (partes A, B y
C) y después esta parte D. Las pruebas, el comparador, la instalación y la vuelta atrás son los de la **sección 8 de la spec
principal**, con lo que este anexo agrega en las secciones 5 y 6. **No lleva SQL ni toca datos.**

---

## 1. Qué pasó después de escrita la spec principal

El 14/11 a las 11:40, con la 6.8.0, **la familia F6** (una escuela) pagó el remanente. La línea quedó guardada con el rótulo
viejo, que es el error que arregla la spec principal:

| Fecha | Concepto guardado | Monto | Lo correcto |
|---|---|---|---|
| 12/11 17:40 | `Interés mora cuotas 3, 4 + mora pendiente cuota 2` | $75.000 | Está bien: cuota 2 $350 + cuota 3 $47.250 + cuota 4 $27.400 |
| 14/11 11:40 | `Mora pendiente cuotas 2, 4, 5, 6 y 7 (no cobrada al pagar)` | $53.800 | Resto de la cuota 4 $9.000 + cuota 5 $25.550 + cuota 6 $15.050 + cuota 7 $4.200 |

- La mora de la **cuota 2** ($350, 1 día de atraso) **ya se había cobrado el 12/11**. La línea del 14/11 no tendría que
  nombrarla.
- **La plata está bien:** mora total por regla $128.800 = `mora_cobrada_offset` 128.800 ($75.000 + $53.800). Saldo $49.800
  (solo mesa extra), `mora_pendiente_tracked` 0.
- El reparto correcto del 14/11 es **el mismo** que la spec principal ya calculaba para la ficha de F6 (Jul $9.000 +
  Ago $25.550 + Sep $15.050 + Oct $4.200).
- **Por qué importa:** la familia reclamó el cobro. Un estado de cuenta que dice "mora de la cuota 2" en el cobro del 14/11 se
  lee como que se les cobró dos veces lo mismo.

## 2. Por qué la spec principal no alcanza para esta fila

| Dónde | De dónde saca los números de cuota del arrastre | ¿Se arregla con las partes A a C? |
|---|---|---|
| Cobros **nuevos** | El modal arma el concepto desde `MoraTrackedOrigen.inferir` (`detalle_evento_masivo_screen.dart` ~5262, `recorte: MoraOrigenRecorte.loQueQueda`) | **Sí**, con la parte A |
| **Reimpresión** de un recibo | `_repartirMoraMixtoSiAplica` rearma el arrastre con `inferir` (`antesDe: antesDeLote`, `excluirPagoId`), y usa los números del concepto **solo** si eso vuelve vacío (`_detalleDesdeElConcepto`) | **Sí**, con la parte A |
| **Estado de cuenta** (diálogo y PDF) | `MoraConceptoRotulo.rotuloFichaMora` lee los números **del concepto guardado** (`numerosCuotaPendienteDesdeConcepto`) | **No.** Con la parte C, además, le agrega el mes: diría "cuota 2 (vto May 2026)" |

Resultado sin este anexo: para la misma línea, **el recibo reimpreso diría julio a octubre y el estado de cuenta diría mayo,
julio, agosto, septiembre y octubre**. Pantalla y papel se contradicen, y en cada concepto que se haya guardado con el rótulo
viejo queda el error a la vista para siempre.

## 3. Parte D: el arreglo

En `ConceptoPagoDisplay.enriquecerPagosHistorial` (`lib/features/eventos/services/concepto_pago_display.dart`), las **filas de
mora del arrastre** nombran sus cuotas con **la misma reconstrucción que la reimpresión**, no con los números del texto
guardado.

**Qué es una fila del arrastre:** una línea de mora (`esMora`) cuyo concepto cumple `_esConceptoMoraMixtoOPendiente`, o sea,
la sola (`Mora pendiente cuota(s) … (no cobrada al pagar)`) o la mixta (`Interés mora cuota(s) … + mora pendiente cuota(s) …`).

**La regla:**

1. Se llama `MoraTrackedOrigen.inferir` con lo mismo que usa `_repartirMoraMixtoSiAplica`:
   - `contratoBase`: el contrato con `moraExentaHasta: null` y `moraFechaReferencia: null` (como `contratoHist`);
   - `pagos`: todos los pagos del contrato que recibe `enriquecerPagosHistorial`;
   - `trackedMonto`: el **monto de la línea**;
   - `antesDe`: el inicio del día AR del lote (el mismo cálculo que `antesDeLote`);
   - `excluirPagoId`: el `id` de la línea;
   - `recorte`: el de la reimpresión (`loQueSeCobra`, el valor por defecto).

   Como `inferir` recorta FIFO hasta el monto, devuelve exactamente la parte del arrastre de la línea:
   `min(monto, arrastre vivo antes del lote)`, que es la sección 3.3 de la spec principal.
2. **Línea sola:** si el resultado cubre el monto de la línea (± $0,01), sus cuotas son las del título.
3. **Línea mixta:** si el resultado no está vacío, sus cuotas son las del sufijo. El título de calendario (`Interés mora
   cuota(s) N…`) no cambia.
4. **Guarda:** si el resultado vuelve vacío o (en la sola) no cubre el monto, se usan los números del concepto, **como hoy**.
5. **Formato:** el de la parte C, con el mes desde `vencimientoCuotaDesdeRegAr`. El subtexto no cambia.

**Para que no puedan volver a separarse:** extraer en un helper compartido el armado del detalle del arrastre de una línea
(punto 1 más la guarda), y que lo usen tanto `enriquecerPagosHistorial` como `_repartirMoraMixtoSiAplica`. Si el refactor de
la reimpresión cambia **cualquier** recibo que hoy sale bien, se frena: la reimpresión no se toca más allá de llamar al helper.

**No cambia:** el concepto guardado (es la clave que lee la reimpresión), los montos, el saldo, la mora, el offset, la
exención y la sincronización. Nada se escribe en `data.db` ni en la nube.

**Límite conocido (el mismo de hoy en la reimpresión):** `antesDe` corta por día, así que si el mismo alumno tuvo dos cobros
el mismo día, el segundo no ve los cambios del primero. No se arregla acá: pantalla y reimpresión quedan iguales entre sí.

## 4. Tests

En `test/`, con el mismo armado de contrato y pagos que los tests de la spec principal. Los montos son reales.

| # | Caso | Esperado en el estado de cuenta |
|---|---|---|
| D1 | F6, línea del 14/11 de $53.800 (sola) | `Mora cuota 4 (vto Jul 2026), cuota 5 (vto Ago 2026), cuota 6 (vto Sep 2026) y cuota 7 (vto Oct 2026)`. Detalle: 9.000 / 25.550 / 15.050 / 4.200 |
| D2 | F6, línea del 12/11 de $75.000 (mixta) | Calendario `cuotas 3, 4` sin cambio; sufijo `cuota 2 (vto May 2026)`, por $350 |
| D3 | F7, línea del 13/11 `Mora pendiente cuotas 1 y 2` de $39.900 | Igual que con la parte C: cuotas 1 (Abr) y 2 (May); el concepto ya estaba bien |
| D4 | Línea sola sin historial previo (la reconstrucción vuelve vacía) | Los números del concepto, como hoy |
| D5 | Línea sola cuya reconstrucción no cubre el monto | Los números del concepto, como hoy |
| D6 | Para D1, D2 y D3 | El estado de cuenta y la reimpresión del mismo recibo nombran **las mismas cuotas** |
| D7 | Fila que no es del arrastre (`Interés mora cuota 3 (vto Jun 2026)`) | Sin cambio |

Los tests existentes tienen que seguir pasando **sin tocarlos**. Si alguno falla, se arregla el código; cambiar un test
requiere justificarlo por escrito en el commit.

## 5. Lo que se agrega al comparador de la sección 8

Sobre la **copia** del `data.db`, el informe suma una tabla nueva: **todas** las filas del arrastre (en la nube, al 14-nov,
hay 30 solas y 75 mixtas en 83 contratos), con:

- alumno, fecha, concepto guardado y monto;
- las cuotas que nombra **hoy** el estado de cuenta (los números del concepto);
- las cuotas que va a nombrar **con la versión** (la parte D);
- las cuotas que nombra la **reimpresión** con la versión.

**Para publicar:**

- La columna de la versión y la de la reimpresión tienen que ser **iguales en todas las filas** (D6 sobre la base entera).
- Tiene que aparecer **por lo menos** la fila de F6 del 14/11, con `2, 4, 5, 6 y 7` → `4, 5, 6 y 7`.
- **Cada** fila donde cambian las cuotas se revisa a mano antes de publicar. Si alguna queda peor que lo guardado, se
  frena y se avisa. Esto vale en especial para F9 y F10: sus perdones no tienen fecha (límite ya conocido de la spec
  principal).
- Los totales de saldo, mora y offset del informe **no pueden moverse ni un peso** contra la foto "antes".

## 6. Ajuste a la verificación de las 5 fichas de la spec principal

F6 pagó el remanente **después** de escrita la spec principal: su ficha hoy tiene `mora_pendiente_tracked` 0, así que
**no muestra remanente ni antes ni después**. Para ella, en vez de la ficha, se revisa:

- **Estado de cuenta:** la fila del 14/11 dice las cuotas 4 a 7 (D1), y la del 12/11 sigue diciendo cuota 2 en el sufijo (D2).
- **Reimpresión** del recibo del 14/11: las mismas cuotas 4 a 7.
- **Foto de la mora "después":** sin cambios contra la de "antes": tracked 0, offset 128.800, `mora_exenta_hasta` 2026-11-30,
  reinicia 1, saldo 49.800.

Las otras cuatro fichas (F7, F8, F9 y F10) siguen como dice la spec principal. Al 14-nov, 14:20, todavía
tienen remanente: 72.300, 5.790, 52.450 y 9.900.

## 7. No tocar

**La exención de F6 hasta el 30/11 es por diseño**, no un error. La pone `MoraCuotaCalculator.postCobroTrackedOffset`
(bloque "Exención: el cobro saldó toda la mora que estaba pendiente PRE-cobro", ~línea 535): cuando un cobro salda toda la
mora y queda saldo (acá, la mesa extra), lleva la exención a fin de mes con `calcularFechaExencion`, y deja reinicia en 1
porque liquidó cuota base. No es parte de este arreglo.

## 8. Después de instalar

Si la familia de F6 pide el papel, se le reimprime el recibo del 14/11: con la versión sale con las cuotas 4 a 7.
