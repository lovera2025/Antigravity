# v4.9.8 — Lo que se carga o se borra en una PC aparece en la otra en segundos

**Fecha:** 2026-09-08
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Sin migración de base.** La v4.9.7 ya dejó la nube y el esquema local como
hacen falta.

Continuación directa de [v4.9.7](CONTEXTO_v4.9.7_2026-09-08.md), que cortó la
pérdida de datos. Ésta cierra la otra mitad: que todo cruce solo y rápido.

---

## De qué se trata

La v4.9.7 dejó la salida rápida —la PC que edita manda el cambio a los 2
segundos— pero la entrada seguía atada al reloj: presupuestos y eventos están en
el nivel lento del pull, o sea **hasta un minuto**. Y los borrados no cruzaban de
ninguna manera.

### El pulso

Un canal de **broadcast** (`sync_pulse`) por el que la PC que sube avisa qué
tablas tocó. La otra baja **solo esas**, con 400 ms de agrupado. De hasta 60
segundos a **2-4**.

Es un **acelerador, no un transporte**: lo único que hace es adelantar un pull
que igual iba a pasar. Por eso no tiene reintentos ni acuses — un aviso perdido
cuesta segundos, no datos. Si el socket está caído, o la PC estaba apagada, el
ciclo de siempre lo cubre.

Vive en el motor y no en un widget, para que llegue también a una PC de Asesor,
que nunca elige rol operativo. Y en web no se suscribe: esa rama va directo a
Supabase y no tiene base local que actualizar.

**No se agrega ninguna tabla a la publicación de Realtime** — sigue solo
`invitados`. Los mensajes de broadcast son WebSocket puro: no consultan el slot
de replicación ni disparan `realtime.apply_rls`, que es lo que agotó el Disk IO
en septiembre. Verificado contra producción: `realtime.subscription` sigue en 0
con el pulso andando.

### Los borrados cruzan, por dos caminos

Es la regla de la v4.9.7 aplicada entera. Un `DELETE` local vale si viene con
nombre y apellido, **o** si sale de una foto completa y contada:

- **Con nombre y apellido.** El pulso lleva los ids que alguien eliminó y la otra
  PC borra exactamente esos. No compara conjuntos, así que no hay forma de que se
  exceda. Borra las hijas antes que el padre, porque **en SQLite local no está
  `PRAGMA foreign_keys = ON`** y el `CASCADE` del esquema es decorativo; el mapa
  `_hijasEnCascada` espeja los `CASCADE` reales de Supabase.
- **Por foto completa.** Para la PC que estaba apagada cuando pasó el borrado.
  Corre a los 20 s de arrancar y cada 10 minutos.

---

## Los dos sustos, que es lo que hay que leer

Ninguno de los dos lo habría encontrado el análisis estático, y los dos fallaban
en silencio.

### 1. Un payload raro reventaba adentro del socket

El filtrado del mensaje se extrajo a `trabajoDelPulso`, función pura con test. El
test encontró, antes de que saliera, que un payload con `tablas` como **texto**
en vez de lista rompía el cast — adentro del callback del WebSocket, donde nadie
lo atrapa. Ahora un mensaje con cualquier forma produce trabajo vacío y sigue de
largo.

El mensaje cruza la red y lo escribió otro proceso: se trata como dato, no como
instrucción. Solo entran tablas que el motor ya conoce, e ids con forma de UUID.

### 2. Contar no alcanzaba: una sesión vencida vaciaba la base

Éste es el importante.

`_reconcileDeletes` ya existía y estaba apagada. Su problema conocido era que
hacía `select('id')` **sin paginar**: PostgREST corta en 1000 filas y devuelve
las primeras mil sin avisar. El llamador las tomaba por "todo lo que hay en la
nube" y borraba el resto. `contratos_alumnos` iba en 643 y sube con cada alumno.

El blindaje previsto era paginar y contrastar contra un `count` exacto. **No
alcanza.** Corriendo la prueba de humo contra Supabase apareció el otro caso:

> Sin sesión, PostgREST **no tira error**. Devuelve cero filas, y el `count`
> también da cero.

Los dos números coinciden, el chequeo canta "foto completa", y comparar eso
contra la base local dice que sobra **todo**. La protección de contar convertía
un problema de permisos en un borrado total.

Es la misma trampa que vació los presupuestos —creer que "no vino" significa "no
existe"— una capa más adentro. Por eso ahora hay una tercera condición,
`fotoDeLaNubeEsCreible`: **si la nube dice cero y acá hay filas, no se toca
nada.** Vaciar una tabla entera a propósito existe, pero es raro y se resuelve
con un pull manual; no vale la pena hacerle lugar automático al mismo camino por
el que se pierde todo.

Medido con la clave anónima sin sesión, que es lo que se parece a una sesión
vencida: `eventos` (25 filas reales) → 0. `contratos_alumnos` (643) → 0.
`prestamos_alquiler` → 0. Sin este freno, la reconciliación las habría borrado
las tres.

Está fijado en `tool/probar_reconciliacion_test.dart`, contra el servidor de
verdad y no contra una maqueta, porque el bug vivía en la forma de la respuesta.

### De paso: el broadcast no se auto-escucha

La prueba de humo también corrigió una suposición: Supabase **no le devuelve el
broadcast a quien lo emitió** por el mismo canal. El filtro por `origen` se queda
igual, como segunda línea —es una opción del servidor, no una garantía del
protocolo— pero no es lo que evita el bucle.

---

## Lo demás

- **El id de instalación** dejó de ser un detalle del flujo de caja:
  `core/services/instalacion_id.dart`, resuelto en el arranque. Reusa la misma
  clave `caja_device_id` para que una PC no termine con dos nombres —
  `sesiones_caja.device_id` y el filtro del pulso tienen que hablar de la misma
  máquina. Antes se creaba recién al abrir caja, así que en una PC usada solo
  como jefe podía no existir nunca.

## Pruebas

Además de la suite (512), hay dos de humo contra Supabase real, en `tool/` para
que no corran sin internet:

```
flutter test tool/probar_pulso_test.dart
flutter test tool/probar_reconciliacion_test.dart
```

La primera prueba que un pulso viaja de una punta a la otra y que no vuelve al
emisor. La segunda, que `count` devuelve un entero comparable —si devolviera un
objeto, la reconciliación se declararía "sin foto completa" para siempre y no
borraría nunca nada, sin un solo error— y que una nube que se lee vacía no
autoriza a borrar.

## Qué verificar en las dos PCs

- Cargar un presupuesto en una y verlo en la otra en segundos, sin tocar nada.
- Borrarlo y ver que desaparece.
- Lo mismo con la otra PC minimizada.
- Cerrar una PC, borrar un evento en la otra, y volver a abrir la primera: a los
  20 segundos tiene que desaparecer también.
- `select count(*) from realtime.subscription` → sigue en 0 salvo tótem abierto.
