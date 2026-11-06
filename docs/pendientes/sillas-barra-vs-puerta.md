# Comparar las sillas vendidas en la barra con las sumadas en la puerta

**Estado:** pendiente (la parte en vivo, hecha el 6-nov: ver abajo).
**Postergado el:** 2026-11-06.

**Lo que ya se hizo en vivo (6-nov):** si la barra **anula** la venta de una silla, Recepción la marca en rojo ("vale anulado en la
barra: revisar") y no deja sumar otra con ese vale (`ValesAnulados`, `docs/CONTEXTO_v6.4.0_2026-11-06.md`). Lo que sigue pendiente
es la comparación entera de la oficina: los vales vendidos que nadie anotó y las sillas anotadas con un vale que la barra no tiene.

## Qué es

La noche de la fiesta, una silla extra la cobra la barra ("Silla extra", un producto más del catálogo, con su precio por fiesta) y
la anota la puerta con el número del vale (`sillas_puerta`, 6.4.0). Para el jefe, al otro día en la oficina: cuántas "Silla extra"
vendió cada caja, cuántas sumó la puerta, y cuáles no coinciden (un vale vendido que nadie anotó, o una silla anotada con un vale que
no existe).

La puerta ya deja todo para eso: cada silla con su vale normalizado (`valeNormalizado`: "2-17" es la caja 2, venta 17), quién y la
hora, y el conteo de la noche ("Esta noche: 4 sillas sumadas · vales …", `ConteoDeLaNoche`).

## Por qué se postergó

Lo de la puerta se hizo antes de la barra 5 porque los sorteos empiezan el 10-nov. Del lado de la barra todavía no hay catálogo en
pantalla (etapa 7), ni el cierre por sector (el selector COBROS · BARRA · ENTRADAS, decidido el 5-nov), que es donde el jefe lo
miraría. Sin eso no hay con qué comparar.

## Qué habría que hacer

- En el cierre de la barra (etapa 6-7 de `docs/PLAN_BARRA_2026-11-03.md`), "Silla extra: N vendidas" por caja.
- Una línea en la oficina que cruce los vales: vendidos en la barra contra anotados en la puerta, cuando las dos notebooks suben.
  En vivo entre las dos notebooks, un paso más: no por ahora.
