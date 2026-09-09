# v4.9.7 — Los presupuestos dejan de aparecer en cero

**Fecha:** 2026-09-08
**Rama:** `feature/v4.6-cierre-por-sesiones`
**CON migración de base:** `supabase/migrations/20260908120000_updated_at_trigger.sql`
— correr a mano en el SQL Editor. Es casi toda documentación de lo que ya estaba
aplicado; lo único nuevo son dos tablas.
**Migración local:** v71 (`local_database.dart`), automática al abrir.

---

## El síntoma

En la PC de la oficina los presupuestos aparecían en **$0**. No siempre, no todos
a la vez, y sin un solo error en el log. El "Pull completo forzado" los devolvía,
así que la nube estaba bien. Se rompía la copia local.

En la otra PC no pasaba, o eso parecía.

## Lo que estaba pasando

El monto del presupuesto **no existe como dato**: es un `fold` sobre sus líneas
(`presupuesto.dart:49-51`). Lo mismo para eventos particulares sobre
`eventos_servicios` (`detalle_evento_particular_screen.dart:38-40`). Si las
líneas no están, el monto es cero y nadie avisa.

Y las líneas se estaban borrando. Al final de cada `_pullTable`, para
`eventos_servicios` y `presupuesto_servicios`, corría un prune: *"estas son las
filas que vinieron de la nube; toda fila local que no esté acá, la borro"*.

La idea original era correcta —la migración v35 reasignó UUIDs y quedaron líneas
duplicadas conviviendo, había que limpiar—, pero la comparación corría también en
el pull incremental, donde lo que llega no es la tabla sino el delta de los
últimos diez segundos.

**La secuencia, con los números reales del 7 de septiembre:** a las 22:00 alguien
tocó 22 líneas de 2 presupuestos. La otra PC, en su ciclo de 10 s, bajó esas 22
filas. `cloudIds` quedó con 22 ids. El loop borró las **203 restantes**. Todos los
demás presupuestos, en $0.

225 − 22 = 203. Es el mismo número del encabezado de
`test/marcador_pull_seguro_test.dart` —*"dejó `presupuesto_servicios` con 18 de
203 filas"*—, que en su momento se atribuyó al marcador del pull. **Aquel arreglo
era correcto y resolvió su parte; este prune producía el mismo síntoma por otro
camino y siguió vivo cinco días más.**

Peor: el marcador ya había avanzado antes de podar, así que esas filas **no se
volvían a pedir**. Y "Bajar cambios" tampoco salvaba, porque también es
incremental y también podaba.

### Por qué una PC sí y la otra no

Dos frenos, y ninguno era una protección:

- `_tick()` salía entero si el rol era `none`, y **un usuario Asesor nunca elige
  rol** — va derecho a su menú sin pasar por la pantalla de roles, que es solo
  para Admin. Esa PC no sincronizaba sola nunca, ni para un lado ni para el otro.
- `_tick()` también salía si la ventana no tenía foco.

O sea que **la PC que más sincronizaba era la que más perdía**, y la que parecía
sana lo estaba por no sincronizar. Es la peor forma de estar bien.

## La regla que faltaba

> **Nada se borra de la base local, salvo que alguien lo haya borrado a mano.**
>
> Un `DELETE` local solo es legítimo si viene **con nombre y apellido** —una
> lista explícita de ids que una persona eliminó— o si sale de comparar contra
> una **foto completa y contada** del mismo alcance. Un lote incremental, una
> página que cortó en las 1000 filas de PostgREST, o una consulta que falló a
> medias: ninguna autoriza a borrar nada.

Quedó anotada en `CLAUDE.md` junto a la de `REPLICA IDENTITY`, que es la misma
clase de trampa: algo que parece gratis y rompe en silencio.

En código vive en `filasAPodar` (`sync_engine.dart`), función pura al lado de
`marcadorPullSeguro`, con su test en `test/filas_a_podar_test.dart`. **Cualquier
camino nuevo que borre tiene que pasar por ahí**, no reimplementar la comparación
al lado.

De regalo arregla un segundo defecto del mismo bloque: el id sintetizado para
líneas sin UUID usaba `UuidUtils.lineaIdDeterministic(..., i)` con `i` = índice
**dentro del delta**, así que ni siquiera coincidía con el del pull completo.

---

## Lo que se encontró verificando, y no era lo que se esperaba

El plan original de esta versión decía que **no había trigger de `updated_at`** y
que por eso las ediciones de presupuestos no cruzaban. Contra la base:
`public.update_updated_at_column()` con **50 triggers**, `before insert` y
`before update`, sobre 24 de las 26 tablas sincronizadas. Cero filas con
`updated_at` nulo. 32/32 presupuestos, 25/25 eventos y 51/51 clientes con
`updated_at > created_at`.

Nunca se habían versionado: se aplicaron a mano en el SQL Editor y el cuerpo de
la función todavía tiene los `\r\n` del pegado desde Windows. Leyendo el repo, la
conclusión razonable era que no existían.

**Y eso invertía la urgencia.** El plan decía *"hoy el prune casi no se dispara
porque `updated_at` está roto; arreglarlo haría que borre todo el tiempo"*. Al
revés: `updated_at` funcionaba, así que **el prune ya estaba borrando**, todos los
días, cada vez que alguien tocaba un presupuesto. No había ningún bug tapando al
otro.

Los triggers quedaron versionados en
`supabase/migrations/20260908120000_updated_at_trigger.sql`. Correrlo es inocuo y
repetible. Lo único que cambia de verdad son las dos tablas que se crearon
después de aquella tanda manual y habían quedado sin trigger:
**`compromisos_personal`** (que está en el pull, o sea que sus ediciones no
cruzaban) y **`totem_config`**. De paso se saca el trigger duplicado de
`invitados`, que tenía dos haciendo exactamente lo mismo.

---

## Lo demás que entró

- **v71 local: reinicio de marcadores.** Tercera vez, después de la v45 y la v69.
  El primer arranque de esta versión baja todo una vez y **recupera solo** las
  líneas que el prune ya borró. Nadie tiene que acordarse del pull forzado.

- **El marcador deja de salir del reloj de la PC.** `updated_at` lo sella Postgres
  con su `now()`; el marcador se calculaba con `DateTime.now()` de la máquina. Dos
  relojes distintos, y la diferencia entraba en el filtro. Ahora sale del
  `updated_at` más alto que trajo la bajada (`marcaDeLoBajado`), que es el mismo
  reloj contra el que después se compara y no cuesta un request extra. Y cuando
  la página vuelve **vacía, el marcador ya no se toca**: antes se lo empujaba a
  "ahora", que es justo cuando no hay ninguna promesa nueva que hacer.
  Cierra `docs/pendientes/watermark-reloj-del-servidor.md`.

- **El jefe sube sin caja abierta.** Entrar como jefe no abre caja —se abre recién
  al cobrar—, así que un cambio hecho antes del primer cobro del día se quedaba
  parado en la cola sin que nadie lo reintentara. Y es exactamente cuando se
  cargan los presupuestos.

- **La cola se vacía ~2 s después de encolar.** `SyncQueue.onChanged` ya estaba
  cableado al motor y solo refrescaba el contador; ahora dispara un `flushPending`
  con debounce, así que un cobro de 20 filas sigue siendo una sola subida.

- **Se sincroniza con la ventana atrás o minimizada**, y **también en las PCs sin
  rol operativo** (bajar, no subir: subir sigue pidiendo jefe o caja). Las dos
  cosas suben el tráfico, y por eso van con lo de abajo.

- **Cadencia por niveles.** `_tablasDelCobro` (8) sigue cada 10 s — ahí llegar
  tarde se ve. `_tablasDeCarga` (16) pasa a cada 60 s. Cierra
  `docs/pendientes/pull-cadencia-por-niveles.md`, con dos niveles en vez de los
  tres previstos: el intermedio de 30 s no se justificaba.

- **Las 8 tablas que cruzaban solo a mano** entraron al pull automático, que pasa
  de 16 a 24 tablas. Cierra `docs/pendientes/tablas-en-sync-manual.md`.
  `invitados` se queda con Realtime porque es el tótem.

### Las cuentas, por PC

| | Requests/min |
|---|---|
| Antes, con foco (16 tablas × 6 ciclos) | 96 |
| Antes, sin foco | 0 — y por eso no llegaba nada |
| Sacar el freno de foco sin tocar la cadencia, con 24 tablas | 144 |
| **Ahora** (8 × 6 + 16 × 1) | **64**, siempre |

Cobertura de 16 a 24 tablas, sincroniza minimizada, y un tercio menos de tráfico.

---

## Lo que NO entró, y por qué

**Los borrados siguen sin cruzar.** Si el jefe borra un presupuesto, en la otra PC
sigue apareciendo. `_reconcileDeletes` ya existe y ya cumple la regla, pero nadie
lo llama.

Se dejó afuera a propósito: de todo lo que entró acá, **ningún paso puede
borrar** —el arreglo del prune agrega una condición a un `DELETE` que ya existía,
el reset de marcadores suma filas, el trigger toca una fecha—. Encender la
reconciliación es lo único que agrega un camino que borra, justo después de una
versión que existió porque un borrado silencioso vació los presupuestos.

Y no se puede encender tal cual está: hace `select('id')` **sin paginar**, y
PostgREST corta en 1000. `contratos_alumnos` va en 643 y crece con cada alumno.
El día que pase 1000 borraría en masa — el mismo bug de esta versión con otra
cara. Va en `docs/pendientes/borrados-que-cruzan.md`, con el blindaje escrito.

## Cómo verificar que anduvo

- Abrir la lista de presupuestos en una PC, hacer que la otra toque **un** renglón,
  y confirmar que el resto sigue con su monto. Es la prueba que fallaba.
- Contar `presupuesto_servicios` local en las dos PCs contra las 225 de la nube.
- Entrar como jefe **sin cobrar nada**, cargar un presupuesto, y verlo aparecer en
  la otra PC.
- Repetir con la ventana de la otra PC minimizada.
- `select count(*) from realtime.subscription` → sigue en 0 salvo tótem abierto.
