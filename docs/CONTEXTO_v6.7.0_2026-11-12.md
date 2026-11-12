# Contexto: la 6.7.0 — "Cumplimiento debido" (la preferencia por cumplimiento)

12-nov-2026 (tarde). Rama `feature/v4.6-cierre-por-sesiones`. Sin SQL y sin migración (la base del
equipo sigue en la v79). Viene de `docs/CONTEXTO_v6.6.2_2026-11-12.md` y del pedido de
`docs/SPEC_frente_por_cumplimiento_2026-11-12.md`.

## Para retomar en otro chat

**Estado al cortar (12-nov, ~16 hs): la 6.7.0 está PROGRAMADA y guardada en la rama, SIN PUBLICAR.
El usuario frenó para seguir en otro chat ("pará, actualizá el contexto con lo hecho y lo
pendiente").**

| | Estado |
|---|---|
| La 6.6.2 (papeles, candado, tótem a pantalla completa) | **Publicada** el 12-nov a las 14:37. Sin instalar, que se sepa |
| La 6.7.0: el tilde "Cumplimiento debido" | **Programada, en la rama.** Versión `6.7.0+72` en `pubspec.yaml` y en el `.iss`. **Sin publicar** |
| Pruebas de lo tocado (339) y análisis | Pasan, con el nombre final |
| La corrida **entera** de pruebas con el nombre final | **No terminó** (se cortó al frenar). La anterior, antes del cambio de nombre, dio 4.545 bien y 1 falla que era de estar editando en el medio |
| El recorrido con el mouse (`tool/plano_prueba.dart`) | **No se hizo.** La ventana ya tiene el tilde y pagos inventados |
| El simulacro con la fiesta que se sorteaba ese día | Hecho: 200 sorteos de verdad, todos bien |
| Foto de la mora "antes de 6.7.0" | Sin sacar (la de "antes de 6.6.2" es de las 14 hs, `5202bec8…`) |
| El sorteo de esa fiesta | **No se sabe si se hizo ni cómo.** Tenía la lista para fijar a mano |

### Lo que falta, en orden

1. **Preguntarle si ya sorteó** y con qué (a mano con la lista, o esperó el tilde). De eso depende
   el apuro.
2. Correr `flutter test` entero y `flutter analyze`.
3. **Recorrerlo con el mouse**: `flutter run -d windows -t tool/plano_prueba.dart` → PERSONALIZAR →
   Mesas → tildar "Cumplimiento debido" → mirar el plano → "Ver la lista y el porqué" → SORTEAR
   (arriba) → ver que los candados se van y cada familia quedó en lo suyo → DESHACER → destildar.
   El permiso para manejarla se pide con la ventana ya abierta (`arguello_events`); **nunca abrir
   "Junior Eventos", que es la app de verdad.**
4. **Publicar la 6.7.0, con su OK** (lo dio para la 6.6.2, no para esta): foto de la mora, el
   instalador por pasos, el APK, tag, release y web. El paso a paso, con lo del corte de luz, en
   "Cómo se publicó" de `docs/CONTEXTO_v6.6.2_2026-11-12.md`.
5. Que instale, primero la PC que sortea, y las fotos de la mora "después".

### Preguntas que quedaron sin contestar

- **Las mesas al costado de la pista cuentan como primera línea** (son las más cercanas al medio
  en su fila). Se le mostró en el dibujo del salón real y no contestó si está bien.
- **El recorrido**: por columnas desde el pasillo (lo hecho) o por filas desde el escenario.
- La idea de animar algo en el plano del tótem mientras nadie entra
  (`docs/ideas/totem-plano-animado-en-la-espera.md`): mostrársela en movimiento antes.

### Cómo se llama (lo eligió él)

El tilde dice **"Cumplimiento debido"** y la lista, **"Ver la lista y el porqué"**. Primero se
llamó "Mesas por orden" y "Ver el orden", para que no se leyera "cumplimiento" en la pantalla, y lo
confundió: creyó que "orden" era el de los números de mesa. Le pregunté y contestó "Cumplimiento
debido". **En el código y en lo guardado sigue diciendo "orden"** (`OrdenEnElSalon`,
`OrdenDelPlano`, la clave `frente`, el motivo "Por orden" de las fijadas): no se renombró, y el
motivo de una fijada lo ve cualquiera.

**Qué es:** un tilde en PLANO → PERSONALIZAR → Mesas, **"Cumplimiento debido"**. Prendido, cada
familia queda con su mesa: de la que mejor cumplió con sus cuotas a la que peor, desde la pasarela
hacia afuera, con la adicional detrás de su principal. **Los números de mesa no cambian.**

**Por qué salió el mismo día que la 6.6.2:** esa mañana se le entregó la lista del orden para fijar
las mesas a mano y se dejó el tilde "para la 6.7.0". A la tarde el usuario dijo que él quería el
tilde y creía que estaba hecho ("pero yo quería y pensé hiciste esa y quiero eso"). El sorteo de una
fiesta era ese día.

### Cómo está hecho (y por qué así)

**No toca el sorteo.** Prender el tilde **le fija a cada familia su mesa**, por el camino de las
fijadas que ya existía; después el jefe aprieta SORTEO como siempre y se las entrega. La spec pedía
un camino nuevo dentro de `SorteoConPlano` (`delFrente`), que tocaba lo más delicado; con el candado
que desaparece solo desde la 6.6.2, lo que frenaba usar las fijadas dejó de valer.

Lo que eso da, sin código nuevo en el sorteo:

- **se ve antes de sortear**: con el tilde prendido las mesas esperan a su familia con el candado,
  y el jefe mira el plano. Si no le gusta, destilda y se borra todo;
- **se deshace como siempre**: la mesa la entrega SORTEO, y Deshacer la saca;
- entregadas, no llevan candado (`InfoMesa.conCandado`): ni la pantalla ni los papeles lo dicen;
- quien paga entre el tilde y el sorteo entra igual, en una mesa que quedó libre.

Las piezas:

- `plano/services/mesas_del_paso.dart` (`MesasDelPaso`): las mesas del salón de la mejor a la peor.
  El eje es el medio de la pasarela (sin pasarela, el del escenario); **línea** es el puesto de la
  mesa en su fila y su lado, contando desde el eje. Primero toda la línea 1, de la fila del
  escenario a la del fondo; después la 2; y así. Las otras hojas y el pasto, al final. **No mira ni
  cambia ningún número de mesa.** Sin pasarela ni escenario no hay paso, y el tilde lo dice.
- `plano/services/orden_en_el_salon.dart` (`OrdenEnElSalon`): `prender` calcula el orden
  (`OrdenPorCumplimiento`, con los pagos de la PC), reparte (`repartir`) y devuelve la config con las
  fijadas y el orden guardado; `apagar` saca solo esas fijadas.
  - Cuántas mesas le fija a cada una: las que el sorteo le daría hoy
    (`ExtrasSegunPago.mesasConElSorteoDeHoy`), así la adicional sin pagar no se ubica.
  - **Lo fijado a mano y lo libre no se tocan**, y la familia con una fijada a mano sale del orden.
  - Los empates se sortean con una semilla que sale de la fiesta (`semillaDe`): apagar y prender no
    los cambia.
  - Con familias ya con mesa no se prende ni se apaga: el orden es de antes del sorteo.
- `models/plano_evento.dart`: la clave **`frente`** de la config del plano (`OrdenDelPlano`): si está
  prendido, cuándo y quién, y por familia el puesto, sus mesas y **la oración**
  (`LugarPorOrden`). Las versiones anteriores la conservan al guardar (desde la 6.0.0).
  Una fijada del orden lleva el motivo `MesaFijada.motivoPorOrden` ("Por orden"), **sin el puesto ni
  nada de cómo pagó**: el motivo de una fijada lo ve cualquiera.
- La pantalla: el tilde y "Ver la lista y el porqué" en `_porOrden` de `plano_evento_cuerpo.dart`; el guardado,
  `PlanoEventoScreen._porOrden`, por `_cambiarConfig` (modo jefe, relee el plano de la nube).
  "Ver la lista y el porqué" (`widgets/ver_el_orden_dialog.dart`) muestra lo guardado, no una cuenta de hoy.
- El Historial junta las fijadas del orden en un renglón, sin nombres ("Las mesas se ubicaron por
  orden: 47 familias"): lo abre cualquiera.
- ACOMODAR LAS MESAS y VACIAR EL SALÓN se llevan las fijadas: también apagan el orden.

### Cómo se usa

1. Con el plano listo y **antes de sortear**: PLANO → PERSONALIZAR → Mesas → tildar "Cumplimiento
   orden". **Tildarlo justo antes de sortear**: usa los pagos que esa PC tiene en ese momento.
2. Mirar el plano y "Ver la lista y el porqué".
3. SORTEO, como siempre. Les entrega esas mesas.
4. Después del sorteo, "Ver la lista y el porqué" sigue ahí: es el respaldo.

**Desde una PC con la 6.7.0.** Una con una versión anterior ve esas mesas como fijadas comunes (y
las entrega igual al sortear), pero no tiene el tilde ni "Ver la lista y el porqué".

### Probado

- `test/mesas_del_paso_test.dart` (un salón a mano con todo calculable, y cinco salones de verdad).
- `test/orden_en_el_salon_test.dart`: el reparto, lo fijado a mano, apagar, y **el sorteo de verdad
  entregando lo fijado** (40 sorteos, todos pasan `validar`).
- `test/plano_evento_screen_test.dart`, grupo "Cumplimiento debido": la pantalla entera, en
  memoria.
- **Sobre una copia de la base, con la fiesta que se sorteaba ese día**
  (`tool/orden_del_frente_test.dart --dart-define=fiesta=…`): 47 familias en 54 mesas, 21 vacías
  afuera, y 200 sorteos de verdad que pasan el control final con cada familia en la mesa que le fijó
  el orden. Deja además un dibujo del salón con el puesto en cada mesa, sin nombres.
- `tool/plano_prueba.dart` tiene el tilde, con pagos inventados.

### Lo que no se hizo de la spec

- El tilde por familia ("Siempre" / "Nunca"). Hoy: una familia con una **fijada a mano** queda con
  la suya y fuera del orden; no hay "Nunca".
- "Ver la lista y el porqué" desde PLANO → HISTORIAL: está en Personalizar → Mesas.
- El detalle cuota por cuota al tocar una familia: está en la lista de
  `tool/orden_del_frente_test.dart`.
- No llegó a elegir entre recorrer por columnas desde el pasillo (lo hecho) o por filas desde el
  escenario. Se cambia en un solo lugar: el orden de `MesasDelPaso.de`.
- **El sorteo por división: el tilde no se prende, y dice por qué.** El orden no mira los bloques
  y dejaría familias fuera del de su división. La spec dice que 2 de las fiestas que faltan están
  por división: es lo primero que sigue.
