# El watermark del pull sale del reloj de la PC, no del servidor

**Estado:** hecho
**Postergado el:** 2026-09-02
**Resuelto el:** 2026-09-08

## Cómo se resolvió

Por la **opción 1** —el `updated_at` más alto de lo que se acaba de bajar—, que
es la que este mismo documento recomendaba. Sin RPC y sin tráfico extra. Vive en
`marcaDeLoBajado` (`sync_engine.dart`), función pura con su test en
`test/marca_de_lo_bajado_test.dart`.

El "cuidado con" de más abajo era el punto: cuando la página vuelve vacía **ya no
se escribe nada** y el marcador se queda donde estaba. Antes se lo empujaba a
`now()`, que es justamente el caso en que no hay ninguna promesa nueva que hacer.
Tampoco cuesta requests de más: la próxima pasada pide el mismo rango y vuelve a
venir vacía.

Lo que salió distinto de lo previsto: el documento decía que `updated_at` "lo
escribe Postgres". Es cierto —hay un trigger por tabla—, pero eso **no se podía
saber leyendo el repo**, porque los triggers estaban aplicados a mano y sin
versionar. Quedaron versionados en
`supabase/migrations/20260908120000_updated_at_trigger.sql` el mismo día.

Entró junto con el arreglo del prune de `_pullTable`, que es lo que de verdad
estaba vaciando los presupuestos. Ver `docs/CONTEXTO_v4.9.7_2026-09-08.md`.

---

## El planteo original

## Por qué se postergó

Apareció mientras se auditaba el consumo de Disk IO, pero no era la causa de
nada de lo que se estaba arreglando ese día, y tocarlo implica cambiar cómo se
guarda el watermark de las 24 tablas. Se anotó para no perderlo.

## El problema

`_pullTable` marca hasta dónde llegó usando la hora **local de la PC**:

```dart
// lib/core/services/sync_engine.dart:839
final String currentSyncStr = DateTime.now().toUtc().toIso8601String();
```

Ese valor se guarda en `_sync_meta` como `last_pull_<tabla>` y en el próximo
ciclo se usa como `.gt(updated_at, lastSync)`. Pero `updated_at` lo escribe
**Postgres**, con el reloj del servidor.

Si el reloj de una PC está atrasado respecto del servidor, su watermark queda
siempre por detrás y esa PC vuelve a bajar las mismas filas indefinidamente. Si
está adelantado es peor: puede saltear filas que se escribieron en la ventana de
diferencia y no volver a verlas nunca.

Con Windows sincronizando hora por NTP esto normalmente no se nota, pero es una
bomba silenciosa: cuando pasa, no hay error, solo datos que no llegan.

## Qué habría que hacer

Que el watermark venga del servidor y no del cliente. Opciones, de menos a más
invasiva:

1. **El `updated_at` más alto de lo que se acaba de bajar.** Es exacto y no
   necesita nada nuevo: si bajaste filas, la última que ordenaste por
   `updated_at desc` te da el corte. El detalle a resolver es qué hacer cuando
   la página vuelve vacía (hoy igual se escribe el watermark).
2. **Pedirle la hora a Postgres** con un RPC mínimo (`select now()`) y usar esa.
   Cuesta un request por ciclo.

La 1 es la buena: no agrega tráfico y es la que usan los sistemas de replicación
por watermark.

## Dónde tocar

- `lib/core/services/sync_engine.dart:839` (`currentSyncStr`) y el bloque de escritura del watermark alrededor de `:879`.

## Cuidado con

El caso de la página vacía. Hoy, cuando no hay filas nuevas, igual se avanza el
watermark a "ahora". Si se pasa a usar el máximo `updated_at` recibido, con cero
filas no hay de dónde sacarlo: hay que dejar el watermark como estaba, no
ponerlo en cero ni en `now()`.
