# La red de seguridad en una sola consulta

**Estado:** pendiente
**Postergado el:** 2026-11-06

## Por qué se postergó

Es la etapa 6 del sync en reposo (`docs/PLAN_SYNC_EN_REPOSO_2026-11-06.md`), y la única que necesita SQL en la
nube. El usuario pidió el sync en reposo "de inmediato, bien hecho y probado", en su propia versión (6.3.3) y
sin SQL: las etapas 1 a 5 ya bajan el reposo de unas 7.500 consultas por hora por PC a unas 500. Esta deja la
red en una consulta, pero agrega una función a la base que hay que correr antes de instalar.

## Qué habría que hacer

- Una función `sync_novedades(marcas jsonb) returns jsonb`, `security definer`, con la **lista fija de tablas
  escrita adentro** (nunca las claves del JSON que llega), que devuelva por tabla el `max(updated_at)` y el
  `count(*)` solo de las que tienen algo más nuevo que la marca. `revoke` a `public` y `anon`, `grant` a
  `authenticated`. Con el `ROLLBACK` comentado arriba y la verificación abajo, como siempre.
- En el motor, la red de 5 minutos le pregunta a esa función y baja solo las tablas marcadas; el `count`
  reemplaza los tres de `_contarParaVerBorrados`. Si la función no está (PGRST202/404), sigue con las 16
  consultas de hoy por el resto de la sesión: nunca se queda sin red.
- Las dos redes (5 y 30 minutos) podrían ser una sola consulta cada 5 minutos.

Con esto el reposo de una PC queda en unas 175 a 330 consultas por hora, y el 90 % pasa a ser la revisión de
borrados de cada 10 minutos, que podría ir por la misma función (el `count` por tabla ya lo da).

## Dónde tocar

- `supabase/migrations/2026xxxx_sync_novedades.sql` (nuevo).
- `lib/core/services/sync_engine.dart`: `_vueltaDeLaRed`, `_contarParaVerBorrados`.
- `test/puerta_cerrada_test.dart`: verificar que no la tome por una función para anónimos.

## Cuidado con

La función lee tablas con datos de todos; que nunca acepte nombres de tabla del que llama. Y que el motor nunca
dependa de ella: sin la función, la app tiene que andar igual.
