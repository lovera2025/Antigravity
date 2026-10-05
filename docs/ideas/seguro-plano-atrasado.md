# Seguro para el plano atrasado

**Estado:** relevado — no se programa por ahora (decisión del 4 de octubre de 2026)
**Última revisión:** 4 de octubre de 2026 (sobre `feature/v4.6-cierre-por-sesiones`, commit `99c02be`)

---

## El problema

El plano de una fiesta es **una sola fila** de `planos_evento`, con id fijo, y sube entera desde la cola. Si una PC
guarda el plano y ese cambio no llega a subir (sin internet, o se cortó justo), queda esperando. Si mientras tanto
otra PC cambia el plano de esa fiesta, cuando vuelve la conexión el cambio viejo sube y **le pisa todo** lo que hizo
la otra: por ejemplo los bloques de un sorteo.

Lo encontró la revisión de M6 y volvió a salir en la de M9 (era el punto 1 de la etapa 9c).

## Por qué no se hace

El 4-oct el usuario contó cómo trabajan: **el plano y el sorteo los hace solo el jefe, desde la PC de la oficina.**
Él entra en modo jefe en su PC para mantenimiento, no para armar salones.

Con eso, en vez del seguro se programó la regla: lo que cambia el salón pide modo jefe (etapa 9c-1). Lo que queda
sin cubrir necesita tres cosas juntas: dos PCs en modo jefe, las dos tocando el plano de la misma fiesta, y una sin
internet. Y aun así la app pregunta antes de guardar sin conexión.

Del otro lado de la balanza, el seguro toca `_executeSyncOperation`, el mismo camino por donde suben los cobros. A
semanas de publicar la 6.0.0, ese riesgo es más grande que el que cubre. Lo peor que pasa sin el seguro es rehacer
un acomodo o volver a fijar una mesa; nunca un cobro.

**Cuándo volver a mirarlo:** si algún día dos PCs arman planos (otra sucursal, un segundo encargado), o si el plano
se empieza a tocar desde el salón, con mala señal.

## El diseño, ya pensado

### La marca

Cada guardado del plano lleva dos datos en `config` (que es un texto y conserva las claves que no conoce, así que no
hace falta tocar la base ni la nube):

- `sello`: el nombre de esa versión, uno nuevo por guardado;
- `sobre`: las versiones sobre las que se hizo. La que se leyó y, si había cambios propios sin subir, también esos.

Se pone en `PlanosEventoRepository.guardarEn`, que es el único lugar por donde pasan todos los guardados. Si hay una
entrada esperando en `_sync_queue` para esa fila, `sobre` es el de la fila local más su `sello`; si no, es el `sello`
de lo que leyó quien llama.

### Al subir la fila del plano (y solo esa)

Se lee `config` de la nube y se compara:

| La nube tiene | Qué se hace |
|---|---|
| Ninguna fila | Se sube |
| El mismo `sello` | Ya está arriba: no se reescribe |
| Un `sello` que está en mi `sobre` | Se sube: nadie tocó el plano desde que lo leí |
| Otro `sello` | No se sube. Se guarda acá la fila de la nube, se saca la entrada de la cola (solo si sigue siendo la que se leyó) y se deja un aviso |

### Lo que no es obvio

- **Un contador (`rev`) no alcanza.** Con dos guardados seguidos sin internet, el atrasado queda "más nuevo" que el
  de la otra PC y la pisa igual. Hace falta saber sobre qué versión se hizo, no cuál es más alta.
- **Un contador con base tampoco:** si un guardado propio está subiendo y entra otro, cuando el primero llega a la
  nube el segundo ve "la nube cambió" y da un choque falso. Por eso `sobre` es una lista que incluye los propios.
- **No sirve comparar `updated_at`.** Lo escribe el trigger de la nube con su reloj; acá queda el de la PC hasta la
  próxima bajada. Es la misma trampa del marcador del pull (ver CLAUDE.md).
- **`config` en la nube es `text`, no `jsonb`:** no se puede filtrar por la marca en el servidor. Leer y después
  subir deja una ventana de menos de un segundo, la misma que ya tiene el guardado con internet. Cerrarla del todo
  pediría un mecanismo en la nube que no se puede probar antes de publicar (no hay entorno de prueba).
- **`subirYa` devuelve `true` aunque el cambio se haya descartado**, porque la entrada salió de la cola. Las
  pantallas tienen que comparar el `sello` de lo que guardaron con el de la fila local antes de decir "Plano
  guardado".
- **El sorteo sin internet.** Los números suben por `contratos_alumnos` aunque el plano choque, así que los bloques
  no se pueden descartar. La regla es la de `RespaldoSorteo.bloquesARestaurar`: se reponen sobre el plano de la
  nube, salvo que ese ya tenga bloques (ahí mandan los de la nube y el aviso lo dice).
- **El aviso es de esta PC:** va en `SharedPreferences`, no en una tabla. Tiene que verse al entrar a la fiesta y en
  PLANO, y decir qué no se subió, por sección (mesas fijadas, libres, bloques, colores, medidas, salón).
- **`traerDeLaNube` puede dejar la fila local vieja** si una respuesta lenta llega después de guardar (probable, sin
  confirmar). Arreglo: leer la fila local antes de consultar y no reemplazarla si cambió en el medio.

### Dónde iría

- `lib/models/plano_evento.dart`: `ConfigPlano` con `sello` y `sobre`.
- `lib/features/plano/repositories/planos_evento_repository.dart`: `guardarEn` y `traerDeLaNube`.
- `lib/features/plano/services/subida_del_plano.dart` (nuevo): la decisión, el plano tras el choque y el resumen del
  aviso, como funciones puras.
- `lib/core/services/sync_engine.dart`: una rama en `_executeSyncOperation` solo para `planos_evento`, con un test
  que lea el archivo y falle si alcanza a otra tabla.

### Los casos para probar ("dos PCs, dos fotos")

A sin red fija mesas y B sortea · A sortea sin red y B cambia colores · las dos acomodan · dos guardados seguidos
sin red · un guardado mientras sube el anterior (no tiene que chocar) · reinicio en el medio · las dos arman el
primer plano.

## Lo mismo, en sillas y entradas

`sillas_reparto` y `entradas_retiro` también son una fila que sube entera, pero **por alumno**: para pisarse, las
dos PCs tienen que tocar al mismo alumno con una sin internet. La pantalla de entradas ya lo avisa. Ahí que quede la
última escritura es lo correcto, y además esas tablas no tienen un `config` donde llevar la marca.
