# Junior Eventos v4.9.4 — los eventos cruzan solos, y Realtime deja de quemar el disco

**Fecha:** 2026-09-02
**Rama:** `feature/v4.6-cierre-por-sesiones`
**CON migración de base.** `supabase/migrations/20260902000000_realtime_publicacion_e_indices_updated_at.sql`
achica la publicación de Realtime y agrega 13 índices. **La migración va primero**:
ver "El orden importa", abajo.

**Novedades publicadas:**
```
- Los eventos nuevos ahora aparecen solos en la otra PC, sin sincronizar a mano.
- Se quitó el botón "Auditar y Sincronizar DB": recalculaba saldos con datos incompletos y podía deshacer un perdón de mora.
- Si algo no se puede bajar, la app ahora avisa en vez de decir que sincronizó.
```

---

## De dónde salió

Supabase avisó por mail el 1-sep a las 19:40 que el proyecto estaba **agotando su
Disk IO Budget**. Cuando se agota, las respuestas se vuelven lentas, el CPU sube
por IO wait y la instancia puede dejar de responder — las dos PCs colgadas en
plena jornada de caja.

La sospecha inicial era el latido de sesión. **No era.** Medido sobre 201 días:

| | |
|---|---|
| Latido (`UPDATE sesiones_caja`) | 15.100 llamadas, 9,6 MB de WAL — ruido |
| **`realtime.apply_rls`** | **14,73 h de 16,46 h de CPU — 89,5%** |
| Bloques leídos que le corresponden | **99,7%** |
| Llamadas | 10.148.455 |
| Una de sus tres variantes | **3.137.112 llamadas → 138 filas devueltas** |

El dato que cierra el caso: **el cache hit de la base es 100,000%** — 2.887
bloques leídos de disco en 201 días. La base pesa 16 MB y vive entera en memoria,
así que los datos nunca tocan el disco. Lo único que lo toca sin parar es
Realtime, consultando el slot de replicación cada 100 ms mientras haya un cliente
conectado, haya o no cambios. Eso lee segmentos de WAL crudos, salteando la caché
por diseño.

El costo por llamada escala con (registros de WAL) × (suscripciones vivas), y la
app abría **~20 suscripciones `postgres_changes` sin filtro por PC**, dos de ellas
idénticas sobre las mismas 7 tablas (`finanzas_provider` y `cierre_caja_provider`
llamaban al mismo `subscribeToChanges`).

---

## EL AGUJERO QUE APARECIÓ BUSCANDO OTRA COSA

`eventos` **nunca se sincronizó solo**, desde que existe el proyecto.

- No estaba en el pull de 10 s de `pullOperationalUpdates` — solo en el pull manual de 24 tablas.
- No estaba en la publicación `supabase_realtime`.
- El canal `eventos_repo_changes` (`eventos_repository.dart:536`) escuchaba esa tabla no publicada: **se suscribía y no disparó una sola vez**. Lo mismo `clientes_repo_changes`.

Consecuencia diaria: cargabas un evento masivo en una PC y en la otra **no
aparecía en el desplegable de Cobros masivos** hasta que alguien apretaba
sincronización manual. Los contratos y sus cobros sí bajaban cada 10 s, pero
quedaban colgados de un `evento_id` que localmente no existía, y el desplegable
sale de `eventos LEFT JOIN clientes` (`eventos_repository.dart:30`), así que no
tenía de dónde mostrarlos. Las instituciones tampoco: salen de
`contratos_alumnos.institucion` deduplicadas en vivo, pero recién después de
elegir el evento.

Los FK de SQLite son declarativos (no hay `PRAGMA foreign_keys = ON`), así que
esto nunca tiró un error. Simplemente el evento no estaba.

---

## QUÉ SE HIZO

### 1. La publicación de Realtime quedó con una sola tabla

De `contratos_alumnos`, `egresos`, `invitados`, `pagos_contrato_alumno`,
`pagos_prestamo_alquiler`, `solicitudes_cotizacion` y `transacciones` → **solo
`invitados`**.

`invitados` se queda porque es el tótem: ahí hay alguien parado en la puerta
esperando el check-in, y es el único lugar donde la latencia de Realtime se
justifica. Además se le agregó el filtro `eq('evento_id')` que le faltaba — sin
él, un check-in en un evento refrescaba la lista de todos los demás.

Reversible en un segundo: `alter publication supabase_realtime add table <tabla>`.

### 2. Ocho canales `postgres_changes` eliminados

| Archivo | Canal |
|---|---|
| `finanzas_repository.dart` | `finanzas_dashboard_changes` (7 tablas, **suscrito dos veces**) |
| `eventos_repository.dart` | `eventos_repo_changes` y `evento_detalle_$id` |
| `clientes_repository.dart` | `clientes_repo_changes` |
| `egresos_repository.dart` | `egresos_repo_changes` |
| `contratos_repository.dart` | `contratos_repo_$id` (con `pagos_contrato_alumno` **sin filtro**) |
| `transacciones_repository.dart` | `transacciones_$id` |
| `dashboard_screen.dart` | `solicitudes_changes` |

Las pantallas que dependían de ellos pasaron a
`ref.listen(operationalSyncRevisionProvider)`, que es el tick del pull.

Los canales de *broadcast* del tótem y los de *presence* (`online_users`) se
quedan: no consultan el WAL, no disparan `apply_rls`, no gastan Disk IO.

### 3. El pull operativo pasó de 8 a 16 tablas

Se sumaron `eventos`, `clientes`, `eventos_servicios`, `servicios`,
`transacciones`, `presupuestos`, `presupuesto_servicios` y
`solicitudes_cotizacion`.

Las primeras cuatro cierran el agujero de arriba. Las otras sostienen el detalle
de evento particular, que se apoyaba en los dos canales que se fueron
(`getPresupuesto` es `eventos_servicios LEFT JOIN servicios`).

Cuesta ~50% más de requests REST y está bien: los requests REST **no** eran el
problema —el cache hit es 100%— y ahora todas esas tablas tienen índice sobre
`updated_at`.

### 4. Trece índices sobre `updated_at`

El pull incremental filtra y ordena por `updated_at`, pero solo tres tablas tenían
el índice. `pagos_contrato_alumno` acumulaba **43.030 seq scans y 96 millones de
tuplas leídas** sobre 3.066 filas.

### 5. El pull dejó de decir "sincronizado" cuando falla

`_pullTable` se tragaba toda excepción con un `debugPrint` invisible en release. Y
como nunca lanzaba, el `Future.wait` no veía el fallo: el estado quedaba en `idle`
aunque no hubiera bajado una fila.

Ahora anota las tablas fallidas en `_tablasConFalloPull` y el estado pasa a error
nombrándolas. **Sigue devolviendo `true`**: lo que sí bajó tiene que refrescar la
pantalla igual.

La mitad buena no cambió: el watermark solo avanza si el pull salió bien, así que
un corte pasajero se cura solo en el siguiente ciclo y no se pierde nada.

### 6. El probe usa `CountOption.planned`

`probeRemoteChanges` hacía 24 `COUNT(*)` **exactos** de un saque —24 scans
completos, el pico más caro del sistema— y se disparaba solo al final de cada
pull manual. El número solo alimenta un "hay N cambios para bajar", así que la
estimación del planner alcanza.

---

## EL BOTÓN "AUDITAR Y SINCRONIZAR DB" SE RETIRÓ

Ícono de sync dorado en el AppBar del detalle de evento masivo, modo jefe. Llamaba
a `ejecutarAuditoriaInteligente`, que recorría los contratos del evento
recalculando `saldo_deudor`, `cuotas_pagadas` y las cuotas de mesa/sillas **desde
la copia local de los pagos**, y encolaba el resultado para subirlo.

**La premisa era correcta —los pagos son la verdad, los totales un caché— pero la
fuente no.** Si un pago todavía no había bajado de la otra PC, el recálculo
concluía que el alumno debía más, pisaba un saldo correcto y publicaba el error a
la nube, de donde volvía a la otra máquina.

Ya había corrompido saldos antes: `CONTEXTO_COBRO_PARCIALES_SALDO.md` registra que
"tras el saneamiento matutino, Auditoría inteligente volvió a corromper saldos". Y
el 1-sep-2026 volvió a morder: el jefe perdonó una mora en la PC de oficina, en la
otra se apretó el botón sin querer, y **la mora volvió**.

Contraste que cierra el caso: `MoraTrackedRecovery.reconciliarTodos` hace un
recálculo automático después de cada sync y está bien hecho —
*"Solo escribe exención si el merge la mejora; nunca degrada admin. No toca
`mora_tracked_ajuste`: el perdón/poner admin tiene que sobrevivir."*
(`mora_tracked_recovery.dart:520`). Esa lección se aprendió con MOREIRA y se
aplicó ahí. El botón nunca la recibió.

**Era además el mayor generador de escritura de la base:**

| Statement | Llamadas | WAL |
|---|---|---|
| `UPDATE contratos_alumnos SET cuotas_pagadas, mesa_extra_*, sillas_extra_*, saldo_deudor` | **66.627** | **62 MB** |
| `UPDATE sesiones_caja` (el latido) | 15.100 | 9,6 MB |

En toda la historia de la base se insertaron **3.368 pagos** pero hay **66.627
updates de recálculo**: ~20 por pago, cuando el cobro normal genera uno o dos. El
resto era recálculo en lote. Eso explica los 73.593 updates sobre 642 contratos —
114 por fila.

### Lo que NO se tocó

`recalcularProgresoContrato` sigue intacto. Es el mismo motor de cálculo, pero ahí
está bien usado: corre sobre un contrato puntual justo después de una operación
que ya persistió sus pagos. Lo llaman `registrarPago`, `modal_alumno_premium`,
`anular_cobro_cuota_dialog`, `smart_purge_dialog` y
`test/registrar_pagos_lote_test.dart`.

**El camino de subida tampoco se tocó.** `flushPending`, `_sync_queue` y
`CajaAutoSyncService.afterMassiveMutation` quedaron igual: un cobro en modo caja
sigue subiendo solo al registrarse, con la red del coordinador cada 10 s por si
ese envío falla.

### Para auditar saldos

`tool/recalcular_contrato.dart --dry-run --evento "..."` — no escribe nada,
apunta a la base correcta y filtra por evento o alumno. **Sincronizar antes**:
lee la base local.

**`scripts/recalculate_all.dart` NO sirve**: no tiene modo informe y su ruta
apunta a `Documents\JuniorEventos` (sin espacio) cuando la base vive en
`Junior Eventos`. Ver `docs/pendientes/chequeo-salud-saldos.md`.

---

## El orden importa

1. **Primero la migración de Supabase.** Ya está aplicada (2026-09-02). Sin ella, el instalador nuevo deja de recibir eventos por Realtime pero todavía no los baja por el pull — o sea, peor que antes.
2. **Después el instalador, en las DOS PCs.** La que quede en 4.9.3 **sigue teniendo el botón de auditoría** y puede volver a pisar saldos desde ahí. Sacarlo protege solo a la máquina donde se instaló.
3. **Instalar antes de abrir caja**, no en el medio de una sesión.

---

## Qué verificar después de instalar

- Crear un evento —masivo o particular— en una PC y confirmar que aparece en la otra **sin tocar sincronización manual**, en ~10 segundos. *Esto es lo que nunca funcionó.*
- Cargar un contrato con una institución nueva → aparece en el filtro de la otra PC.
- Registrar un cobro → se ve en la otra PC con el saldo actualizado.
- Detalle de evento particular: agregar un servicio y cargar una transacción desde la otra PC.
- Check-in en el tótem: tiene que seguir siendo instantáneo.
- En el AppBar del detalle masivo, modo jefe: ya no está el ícono de sync dorado; los otros tres (fecha, finalizar, eliminar) siguen.
- `select count(*) from realtime.subscription` en Supabase → **0**, salvo con una pantalla de tótem abierta.

---

## Docs hermanos

- **`docs/CONTEXTO_v4.9.3_2026-08-28.md`** — el incidente MOREIRA y las cuatro columnas de mora que faltaban en la nube.
- **`docs/CONTEXTO_COBRO_PARCIALES_SALDO.md`** — saldo, parciales, y la historia larga de la auditoría.
- **`docs/pendientes/PENDIENTES.md`** — lo que quedó a medio hacer de esta tanda y por qué.
