# Dar entradas para rendir también desde VENDER (quien vende, no solo el jefe)

**Estado:** decidido por el usuario el 22-nov-2026, para el martes 24 o miércoles 25 de noviembre. Sin programar.

## Qué pidió

Hoy (6.9.3) DAR ENTRADAS PARA RENDIR es solo del jefe, en modo jefe, desde ENTRADAS de la fiesta → PARA RENDIR.
El usuario quiere que **quien vende (por ejemplo la caja de AGOS) también pueda darlas desde VENDER**, sin pasar
por el jefe: "para que los que vendan como la caja de Agos también lo puedan hacer desde ahí".

Lo dijo al ver que VENDER no mostraba nada de "para rendir": la franja con RENDIR aparece solo cuando alguien ya
tiene entradas para rendir, y para eso hoy tiene que darlas el jefe.

## Por qué no se hizo en el momento

La 6.9.3 se acababa de publicar ese mismo día; lo dejó para la semana.

## Lo que hay que decidir con él antes de programar (plan y maqueta)

- Dónde va el botón en VENDER (al lado de la franja de RENDIR, o en la barra junto a VENTAS).
- Si NO VOLVIERON y ANULAR siguen siendo solo del jefe (hoy sí, con doble llave).
- Si el jefe ve quién dio cada bloque (el renglón `dio` ya guarda `hecho_por`).
- La llave: "Vende entradas" (`puedeVenderEntradasProvider`, `_frenaSinPermiso`) en lugar del modo jefe, con la
  segunda llave después de la ventana. Ajustar `test/solo_modo_jefe_test.dart` (hoy exige el modo jefe para `_dar`).
- Sin SQL ni migración: la tabla `entradas_para_rendir` ya está en la nube y en las PCs.
- Un equipo con la 6.9.3 no tiene el botón, pero lo que dé otro equipo le llega igual.
