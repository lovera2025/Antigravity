# Cadencia del pull por niveles

**Estado:** pendiente
**Postergado el:** 2026-09-02

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
