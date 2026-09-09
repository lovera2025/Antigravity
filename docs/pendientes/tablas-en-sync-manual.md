# Tablas que quedaron en sync manual

**Estado:** hecho
**Postergado el:** 2026-09-02
**Resuelto el:** 2026-09-08

## Cómo se resolvió

Las siete pasaron al pull automático, en `_tablasDeCarga` (`sync_engine.dart`).
El pull operativo va de 16 a 24 tablas y queda igualado al manual salvo
`invitados`, que —como decía este documento— se queda con su camino de Realtime
porque es el tótem.

No costó lo que se temía: entraron en el **nivel lento** de la cadencia por
niveles, o sea un request por minuto cada una en vez de uno cada 10 segundos. Es
menos de lo que costaba cualquiera de ellas cuando alguien apretaba sincronizar y
se bajaban enteras.

Se sumó además `compromisos_personal`, que no existía cuando se escribió esto
(migración del 4 de septiembre) y había quedado en el mismo lugar: en el pull
manual y sin trigger de `updated_at`, o sea que sus ediciones no cruzaban ni a
mano. El trigger entró en
`supabase/migrations/20260908120000_updated_at_trigger.sql`.

Ver `docs/CONTEXTO_v4.9.7_2026-09-08.md`.

---

## El planteo original

## Por qué se postergó

Ese día se amplió `pullOperationalUpdates` de 8 a 16 tablas para cerrar el
agujero de los eventos —masivos y particulares no cruzaban solos entre las dos
PCs—. Las que quedaron afuera se dejaron a propósito: **ninguna está en la ruta
de cobro y todas tenían entre 0 y 3 filas** al momento de medir. Sumarlas habría
subido el tráfico sin resolver nada real.

No es un olvido: es una decisión que hay que revisar si alguna empieza a
moverse.

## Las que cruzan solo a mano

| Tabla | Filas al 2026-09-02 | Para qué |
|---|---|---|
| `prestamos_alquiler` | 0 | Alquiler de mobiliario |
| `prestamo_alquiler_lineas` | 0 | Detalle de cada alquiler |
| `pagos_prestamo_alquiler` | 0 | Cobros de alquiler |
| `calculos_rentabilidad` | 3 | Rentabilidad por evento |
| `obligaciones_pago` | 2 | Obligaciones a pagar |
| `caja_fuerte_movimientos` | 2 | Movimientos de caja fuerte |
| `rentabilidad_config` | 0 | Config de rentabilidad |
| `invitados` | 3 | Tótem — **este tiene su propio camino**: sigue en Realtime, filtrado por evento |

Todas siguen bajando en el pull manual de 24 tablas (`_pullFromCloud`), o sea
que cruzan cuando alguien apreta sincronizar. No se pierde nada; solo no es
automático.

## Cuándo revisarlo

Si el módulo de alquileres empieza a usarse de verdad, `prestamos_alquiler` y
sus dos tablas hijas pasan a ser plata que se cobra en una PC y no se ve en la
otra — el mismo problema que tenían los eventos masivos. Ahí hay que subirlas al
pull automático.

Lo mismo con `caja_fuerte_movimientos` si se empieza a operar desde las dos
máquinas.

## Dónde tocar

- `lib/core/services/sync_engine.dart` → `pullOperationalUpdates`: agregar el `_pullTable` correspondiente.
- Todas ya están declaradas en `_incrementalColumns` (`sync_engine.dart:44`), así que no hay que registrar nada nuevo.
- Conviene sumarles el índice de `updated_at` en Supabase, como se hizo con las otras en `supabase/migrations/20260902000000_realtime_publicacion_e_indices_updated_at.sql`.
