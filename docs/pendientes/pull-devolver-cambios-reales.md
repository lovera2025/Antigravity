# Que el pull diga cuántas filas bajó

**Estado:** pendiente
**Postergado el:** 2026-09-02

## Por qué se postergó

Obliga a cambiar la firma de `_pullTable` de `Future<void>` a `Future<int>` y a
revisar sus llamadores en los dos puntos de entrada (`pullOperationalUpdates` y
`_pullFromCloud`, 24 llamadas entre ambos). Es un cambio correcto y no
especialmente difícil, pero ese día había que cobrar con el build recién
instalado y no era momento de tocar la firma del corazón del sync.

Ese mismo día sí entró la mitad barata del problema —que el pull avise cuándo
falla, ver `_tablasConFalloPull` en `sync_engine.dart`—, que no necesitaba
cambiar ninguna firma.

## El problema

`pullOperationalUpdates` devuelve `true` siempre, aunque no baje una sola fila.
Cada 10 segundos, eso:

- Llama a `FinanzasRepository.invalidateProyeccionCache()`, que anula el caché
  de 2 minutos de `obtenerProyeccionFinanciera`. Resultado: el RPC
  `obtener_proyeccion_financiera` (45,8 ms, 445 bloques por llamada) se ejecuta
  prácticamente siempre que Finanzas está abierta, en vez de una vez cada dos
  minutos.
- Bombea `dashboardStatsProvider`, `contratosMutationTickProvider` y
  `operationalSyncRevisionProvider` desde
  `operational_sync_coordinator.dart:142`, encadenando recargas en cada pantalla
  abierta.

Con los `ref.listen(operationalSyncRevisionProvider)` que se agregaron el
2026-09-02 para reemplazar a Realtime, esto pesa más que antes: ahora hay más
pantallas escuchando ese tick.

## Qué habría que hacer

1. `_pullTable` devuelve cuántas filas guardó.
2. `pullOperationalUpdates` suma esos totales.
3. Usar el total para el `return` **y** para decidir si invalidar el caché de la
   proyección.
4. Con eso disponible, encarar el backoff del coordinador: mantener 10 s
   mientras haya movimiento, estirar a 30 s tras ~2 minutos sin novedades, y
   volver a 10 s en cuanto baje algo o el usuario haga una mutación.

## Dónde tocar

- `lib/core/services/sync_engine.dart` → `_pullTable`, `pullOperationalUpdates`, `_pullFromCloud`.
- `lib/features/common/widgets/operational_sync_coordinator.dart:140` (el `changed`) y `:56` (el timer, para el backoff).
- `lib/features/mi_empresa/repositories/finanzas_repository.dart` → `invalidateProyeccionCache`.

## Cuidado con

Que "0 filas bajadas" no apague refrescos que sí hacen falta. El `return` se usa
para decidir si invalidar providers; si una mutación local no dispara ningún
pull, la pantalla tiene que seguir refrescándose por su propio camino
(`contratosMutationTickProvider`), no por éste.
