# Que los borrados crucen solos

**Estado:** a medias — falta la red de seguridad
**Postergado el:** 2026-09-08
**Primera mitad hecha el:** 2026-09-08

## Dónde está parado

El **camino rápido (a) está hecho**: el pulso lleva los ids borrados y la otra PC
los aplica con su cascada. Con las dos máquinas prendidas, un borrado cruza en
2-4 segundos.

Falta la **red de seguridad (b)**: la PC que estaba apagada cuando se borró
sigue mostrando el registro hasta que alguien sincronice a mano. Es el caso menos
frecuente y el único que necesita comparar conjuntos — o sea el único que puede
borrar de más si se hace mal.

Se dejó afuera a propósito para no meterlo en el mismo instalador que el resto:
si aparece un problema, que se sepa cuál de las dos cosas fue.

## Por qué se postergó

Es lo que quedó afuera de la v4.9.7 **a propósito**, y por una razón que vale la
pena dejar escrita: de todo lo que entró ese día, ningún paso podía borrar nada.
El arreglo del prune agrega una condición a un `DELETE` que ya existía —corre en
menos casos, nunca en más—; el reset de marcadores suma filas; el trigger toca
una fecha; la cadencia toca el reloj.

Esto es lo único que **agrega un camino que borra**. Y venía justo después de una
versión que existió porque un borrado silencioso vació los presupuestos en una
PC. Meterlo en el mismo instalador era pedir que, si algo salía mal, no se
supiera cuál de las dos cosas fue.

Así que va aparte, después de que la v4.9.7 haya corrido limpia unos días.

## El problema

Si el jefe borra un presupuesto en una PC, en la otra **sigue apareciendo para
siempre**. Nada lo saca salvo que alguien vacíe la base local a mano.

El código que lo resolvería ya existe: `_reconcileDeletes` (`sync_engine.dart`),
que compara los ids locales contra `select('id')` de la nube entera y borra lo
que sobra, protegiendo lo que esté pendiente en la cola. Cumple la regla. Pero
**nadie lo llama**: `pullRemote` y `syncBidirectional` reciben
`reconcileDeletes: false` por defecto y los tres call sites de
`sync_menu_sheet.dart` los llaman sin argumentos. Es código muerto desde que se
escribió.

## Qué habría que hacer

Dos caminos, y hacen falta los dos.

### a) El camino rápido: el borrado viaja con nombre y apellido — HECHO

Cuando la cola sube un `SyncOperation.delete`, el pulso de broadcast lleva esos
ids y el receptor borra **exactamente esos** (`_aplicarBorrados` en
`sync_engine.dart`). Determinístico: no puede excederse, porque la lista la
escribió una persona apretando eliminar.

Borra **los hijos primero y el padre después, a mano**, según el mapa
`_hijasEnCascada`, que espeja los `ON DELETE CASCADE` verificados contra
Supabase. Hace falta escribirlos porque en SQLite local **no está
`PRAGMA foreign_keys = ON`**: los `CASCADE` del esquema local son decorativos.
Es el mismo orden que ya usaba `eliminar()`
(`presupuestos_repository.dart:253-260`).

Lo que salió distinto de lo previsto: hizo falta extraer `trabajoDelPulso` como
función pura para poder testear el filtrado del mensaje, y **el test encontró un
bug antes de que saliera**: un payload con `tablas` como texto en vez de lista
reventaba el cast adentro del callback del socket, donde nadie lo atrapa. Ahora
un mensaje con cualquier forma produce trabajo vacío.

### b) La red de seguridad: reconciliación por foto completa — LO QUE FALTA

Para la PC que estaba apagada cuando pasó el borrado. Encender
`_reconcileDeletes` — pero **blindarlo antes**.

> **Encenderlo tal cual está sería reintroducir el bug de la v4.9.7 en otra
> tabla.**

Hace `select('id')` **sin paginar**, y PostgREST corta en 1000 filas por defecto.
`contratos_alumnos` iba en 643 al 2026-09-08 y crece con cada alumno. El día que
pase 1000, la consulta vuelve truncada, la comparación cree que a la nube le
faltan filas, y borra en masa.

El blindaje:

1. Paginar, como ya hace `_pullTable`.
2. Contrastar la cantidad traída contra un `count` exacto de la tabla.
3. **Si no coinciden, no borrar nada** y dejarlo en el log.
4. Pasar el resultado por `filasAPodar(fotoCompleta: ...)`, para que la decisión
   siga viviendo en un solo lugar con un solo test.

Cadencia: al arrancar la app y cada ~10 minutos. Son 6 requests que traen solo
ids.

## Dónde tocar

- `lib/core/services/sync_engine.dart` → `_reconcileDeletes` (paginación + count),
  y el emisor del pulso para que lleve los ids borrados.
- `lib/features/common/widgets/operational_sync_coordinator.dart` → el receptor
  del pulso. **No puede colgar del guard de rol**: tiene que escuchar en
  cualquier sesión abierta, también la de un Asesor.
- `test/filas_a_podar_test.dart` → ya tiene el caso de la foto truncada.

## Cuidado con

- ~~El id de instalación~~ — resuelto: vive en `core/services/instalacion_id.dart`
  y se inicializa en el arranque, reusando la misma clave `caja_device_id` que ya
  usaba la caja para que una PC no tenga dos nombres. `_deviceId()` de
  `app_role_provider` ahora delega ahí.
- Broadcast, no `postgres_changes`. No agregar ninguna tabla a la publicación de
  Realtime: eso es lo que quemó el Disk IO en septiembre de 2026, y está contado
  en `docs/CONTEXTO_v4.9.4_2026-09-02.md`. El broadcast no consulta el WAL.
- Verificar después: `select count(*) from realtime.subscription` tiene que
  seguir en 0 salvo con el tótem abierto.
