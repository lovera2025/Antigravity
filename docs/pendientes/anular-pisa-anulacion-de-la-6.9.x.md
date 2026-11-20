# Anular con la 6.9.3 pisa una anulación de la 6.9.x guardada en la fila

**Estado:** pendiente
**Postergado el:** 2026-11-20

## Qué pasa

Lo encontró la revisión de la caja de entregas (6.9.3, sin publicar, 20-nov). La fila de `entradas_retiro`
guarda **una sola entrega y una sola anulación**. Si una PC con la 6.9.x anuló y después volvió a entregar las
8 juntas, la fila queda "entregado" con la anulación vieja en `anulado_at`; la caja de entregas la cuenta y la
muestra en "Anulaciones de una entrega anterior".

Si después el jefe anula una parte con la 6.9.3, `RetiroEntradas.anular` reescribe la fila con la anulación
nueva y **la vieja se pierde**: `EntregaPorPartes.copiasDeLaFila` copia a un renglón solo lo último de cada
parte (la entrega), no la anulación de antes. La caja deja de contarla (ANULADAS baja de 2 a 1 con dos
anulaciones hechas) y lo que esa anulación tumbaba pasa a decir "NO CUENTA: se volvió a entregar".

Lo mismo con `nuevaEntrega` y `filaCompleta`, que pisan la entrega anterior de la fila, y con el reflejo
(`_NovedadesDeLaFila.esReflejo`), que no mira la parte: una copia a la hora cruda de una sola parte vuelve
reflejo la entrega de la fila para las dos, y la otra parte de esas 8 juntas, si ya no contaba, desaparece de
la lista de la caja. **Lo que cuenta de cada parte no cambia** (lo último sigue siendo lo mismo): es solo la
historia que lista la caja.

## Por qué se postergó

- Desde la vista no se recupera: lo que se pisó ya no está en ningún lado.
- Arreglarlo es copiar la anulación vieja a un renglón **antes** de reescribir la fila (en `anularParte` y
  en la entrega), y eso toca cómo se anula y se entrega, no la caja. La revisión era de la caja.
- Solo pasa con fiestas que tienen entregas hechas con la 6.9.x **y** anuladas y vueltas a dar con la 6.9.x,
  y después anuladas otra vez con la 6.9.3. Una vez que todas las PCs tengan la 6.9.3 no aparecen casos nuevos.

## Qué hacer si se retoma

En `EntregaPorPartes.copiasDeLaFila` (o al lado), si la fila dice "entregado" y tiene `anulado_at` que no es
reflejo de un renglón, escribir también la copia de esa anulación (id fijo por hora, como las otras copias)
antes de reescribir la fila. Con su test en `test/entregar_parte_test.dart` y el caso en
`test/caja_de_entregas_test.dart` (ANULADAS tiene que seguir en 2).
