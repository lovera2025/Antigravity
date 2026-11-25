# Al abrir "Caja 1" aparecen cajas viejas con el mismo número

**Estado (25-nov, tarde): EN CURSO** en la sesión "La barra por día de operación y la madrugada": las cajas
separadas por día de operación, como un cierre de caja en su fecha (lo pidió el usuario con fotos de LAS CAJAS).
Ver `docs/CONTEXTO_PLAN_4DIC_2026-11-25.md`.

## Qué pasa

Al abrir una caja de la barra (por ejemplo "Caja 1") ya aparecen cajas viejas con ese mismo número, y confunde.
El usuario pregunta si se puede **empezar de nuevo sin que se borre el historial**: que lo que ya fue no se mezcle
con la caja de hoy.

## Lo que hay que mirar

- Dónde aparece exactamente: VENDER, VENTAS, LAS CAJAS del jefe o de la encargada, el cierre. Pedirle una foto.
- Si son cajas de otras fiestas o de la misma fiesta (una caja que se cerró y se volvió a abrir con el mismo
  nombre).
- **Nada se borra** (una venta nunca se edita; `barra_cajas` y `barra_ventas` solo agregan): la solución es mostrar
  solo lo de la caja abierta y dejar lo anterior en un historial aparte.
