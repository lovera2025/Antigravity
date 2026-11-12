# "Cumplimiento debido" después del sorteo, sin deshacerlo

**Estado:** pedido, con el plan escrito y **sin programar**. 12-nov-2026.

## Qué pidió

Mirando la captura de la 6.7.0, donde el aviso en rojo dice "para usarlo hay que deshacer el
sorteo entero": "hay que hacer que no sea rehacer el sorteo de vuelta… debería haber otra cosa en
vez de eso". Y que los textos explicativos sean más cortos.

## Por qué se postergó

Se le mostró el plan y, antes de contestar, dijo **"ya con lo publicado probemos"**: primero quiere
usar la 6.7.0 como está (tildar antes de sortear). No contestó si el plan le sirve ni a qué textos
se refería (los de la pantalla, las oraciones de la lista o los mensajes del chat).

## El plan que se le mostró

- **Con el sorteo ya hecho, tildar (o cambiar "Por columnas · Por filas") reubica en el momento**:
  muestra cuántas familias cambian de mesa, pide confirmar y las mueve. Nadie gana ni pierde mesas;
  lo fijado a mano y las libres no se tocan. Quien no tiene mesa sigue sin mesa.
- **DESHACER** las vuelve a donde estaban, y el tilde vuelve a como estaba.
- **Destildar** con el sorteo hecho apaga la marca y nadie se mueve.
- En el Historial, un renglón sin nombres.
- Sin SQL ni migración.

## Cómo se haría (visto en el código, sin tocar nada)

- Por `PlanoEventoScreen._cambiarMesas`, el camino de Mover y Cambiar: los números, el renglón de
  `mesas_movimientos` y el plano en una transacción, la lista de la puerta al día (`trasElSalon`),
  la llave del modo jefe y el DESHACER del pie. `CambioDeMesas` ya lleva cualquier cantidad de
  familias en `antes` y `despues`.
- La cuenta, en `OrdenEnElSalon` (una función nueva al lado de `prender`): el mismo
  `OrdenPorCumplimiento` y el mismo `repartir`, con cada familia en la cantidad de mesas que tiene
  hoy, y fuera del reparto las mesas de quien no entra al orden. Con el sorteo por división,
  tampoco.
- **Sin un tipo nuevo de movimiento** (iría como `mover`, con un motivo fijo que no diga cómo pagó
  nadie): una versión anterior no conoce otro tipo.
- A resolver: el cartel de confirmar y el Historial listan hoy un renglón por familia, con nombres;
  para esto van resumidos. Y deshacer tiene que devolver también el `frente` del plano a como
  estaba (apagado, o el recorrido anterior).
- Los textos a acortar: el de debajo del tilde, el renglón del recorrido y los avisos del pie
  (`_porOrden` en `plano_evento_cuerpo.dart` y en `plano_evento_screen.dart`).
