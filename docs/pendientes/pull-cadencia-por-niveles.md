# Cadencia del pull por niveles

**Estado:** hecho
**Postergado el:** 2026-09-02
**Resuelto el:** 2026-09-08

## Cómo se resolvió

Con **dos niveles**, no tres: `_tablasDelCobro` (8, cada ciclo) y
`_tablasDeCarga` (16, cada 6 ciclos = 1 minuto) en `sync_engine.dart`. El
contador de ticks vive en `OperationalSyncCoordinator` como estaba previsto, y
—como avisaba el "cuidado con"— **no se reinicia** con los ticks de foco de
ventana: cuenta bajadas efectivamente corridas y nunca vuelve a cero.

El nivel intermedio de 30 s no se justificó: `eventos`, `clientes`,
`eventos_servicios` y `transacciones` cambian cuando alguien se sienta a cargar
algo, no en el mostrador, y con el pulso por broadcast la latencia real no la
marca el timer. Dos niveles son menos superficie para el mismo resultado.

Lo que salió distinto: esto entró **como parte de un arreglo, no como
optimización**. En la misma versión se sacó el freno de foco de ventana —la PC
de la oficina, con la app atrás del navegador, no sincronizaba— y se empezó a
bajar también en las PCs sin rol operativo. Las dos cosas suben el tráfico; la
cadencia por niveles es lo que las paga. Por PC: de ~96 requests/min con foco (y
0 sin foco) a ~64, siempre, cubriendo 24 tablas en vez de 16.

Ver `docs/CONTEXTO_v4.9.7_2026-09-08.md`.

---

## El planteo original

## Por qué se postergó

Ese mismo día había que cobrar en la oficina en modo caja con el build recién
instalado. La cadencia por niveles necesita un contador de ticks en
`OperationalSyncCoordinator` —lógica nueva, y por lo tanto una forma nueva de
equivocarse— justo en el camino que sincroniza los cobros. No valía la pena:
esto es una **optimización de tráfico**, no una corrección. El problema de Disk
IO lo resolvió sacar las suscripciones de Realtime, no esto.

Así que las 16 tablas quedaron bajando cada 10 segundos, usando el mismo
`_pullTable` que ya corría en el pull manual: cero código nuevo.

## Qué habría que hacer

Separar `pullOperationalUpdates` en tres niveles según cuánto se mueve cada
tabla:

| Nivel | Cada | Tablas |
|---|---|---|
| 1 | 10 s | `contratos_alumnos`, `pagos_contrato_alumno`, `notas_operativas_contrato`, `sesiones_caja`, `operadores_caja`, `egresos`, `cierre_caja_guia_movimientos`, `cierre_caja_anotaciones` |
| 2 | 30 s (cada 3 ticks) | `eventos`, `clientes`, `eventos_servicios`, `transacciones` |
| 3 | 60 s (cada 6 ticks) | `servicios`, `presupuestos`, `presupuesto_servicios`, `solicitudes_cotizacion` |

Baja el promedio de ~17 requests por tick a ~11.

## Dónde tocar

- `lib/core/services/sync_engine.dart` → `pullOperationalUpdates`: partir el `Future.wait` según el nivel.
- `lib/features/common/widgets/operational_sync_coordinator.dart:56`: el contador de ticks.

Los watermarks viven por tabla en `_sync_meta` (`last_pull_<tabla>`) y son
independientes de la cadencia, así que cambiar cada cuánto se pide una tabla no
los afecta.

## Cuidado con

Que el contador no se reinicie en cada `_tick()` disparado por foco de ventana
(`onWindowFocus`, `onWindowRestore`), o un alt-tab seguido haría que los niveles
2 y 3 nunca lleguen a su turno — o que lleguen siempre.
