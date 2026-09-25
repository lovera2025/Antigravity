# Tótems vinculados a recepcionistas, para que no se pisen

**Estado:** pendiente
**Postergado el:** 2026-09-24

## Por qué se postergó

El usuario priorizó el sorteo de noviembre. Esto es para las fiestas de diciembre. Depende de las apariencias nuevas
([totem-apariencias.md](totem-apariencias.md)), que es donde se arma la cola del tótem.

## Qué se pidió

Descartado el QR para "llevar el tótem a una TV", el usuario pidió otra cosa:

> que se conecte el usuario que están en vivo y quieran transmitir en ese tótem, hasta dos o 3 usuarios para operar
> en dos tótem o 3 […] el tótem reconoce qué usuarios están y transmite lo que ellos pongan en recepción

Cada noche es **una sola escuela**. Hay dos tótems, quizás tres, con mucha gente, y "la idea es que no se pisen".

## Qué se decidió

**Cada tótem da la bienvenida a los de su puerta.** El usuario lo dejó a criterio, y la razón es esta cuenta:

- cada bienvenida dura 7 s;
- con dos recepciones marcando una familia cada 10 s cada una, un tótem que muestre todo necesita 14 s cada 10 s: se
  atrasa y no se recupera;
- con colas separadas, cada tótem usa 7 s de cada 10 y nunca se atrasa. Además, cada familia se ve en el tótem que
  tiene al lado.

En la barra del tótem hay un interruptor **"Solo mi puerta / Todas las puertas"**, por si esa noche conviene otra
cosa. Se vio en una simulación de hora pico, el 24-sep.

**Cómo se vinculan:**

- **Cada tótem tiene nombre:** "Tótem 1", "Tótem 2", por orden de apertura. Se cambia desde su barra y se recuerda en
  esa PC.
- **Misma PC:** la Recepción de la PC que tiene el tótem por HDMI le transmite sola, por el puente. Anda sin internet.
- **Celular, tablet u otra PC sin tótem propio:** en Recepción, debajo del evento, **"Transmitir en:"** con los tótems
  prendidos (decisión del usuario: elige de la lista). Queda elegido para esa noche, y necesita internet.
- **Quién está con quién** se sabe con la **presencia de Supabase Realtime**, en el canal `totem_<eventoId>` que el
  tótem ya usa para el broadcast:
  - cada tótem se anuncia con id y nombre;
  - cada Recepción, con su nombre y el tótem elegido.

  No hace falta tabla ni migración. La presencia no pasa por el WAL, así que no suma Disk IO.
- **La barra del tótem** muestra quiénes están conectados. Ejemplo: "Conectados: PC Recepción 1, Juli (celular)".
- **Cada ingreso** viaja por el puente y por el broadcast con `origen` (quién lo marcó) y `destino` (a qué tótem va).
  El tótem muestra los que van para él. No se persiste en la base.

**Que no se pisen al marcar:**

- Si alguien ya está adentro, Recepción no ofrece "Ingresar". Si se lo busca y se aprieta Enter, avisa "Ya ingresó a
  las 22:41", con el `updated_at` de la fila.
- Con internet, lo que marca la otra puerta llega en segundos, y el tótem no repite una bienvenida. Sin internet,
  marcar dos veces no rompe nada: queda "adentro".

**Sin decidir:** el reparto de la puerta, por letra (A–L / M–Z), por división o sin reparto. El usuario lo va a
preguntar al jefe o a ajustar más adelante.

## Qué habría que hacer

- `invitados_repository.dart` (escritorio) y `supabase_invitados_repository.dart` / `supabase_service.dart` (web):
  el ingreso suma `origen` y `destino` al broadcast.
- `kiosk_launcher.dart`: el puente lleva lo mismo, y la ventana recibe su nombre.
- `totem_display.dart`: presencia, filtro por destino, interruptor y "Conectados".
- `recepcion_unified_screen.dart`: "Transmitir en:", presencia y "Ya ingresó a las…".
- **Función pura, con test,** de a qué tótem va cada ingreso:
  - un ingreso de la misma PC va a su tótem;
  - con "Transmitir en", va al elegido;
  - con "Todas las puertas", lo muestran todos;
  - no se repite una bienvenida ya dada.

## Ojo

- Los celulares y tablets usan la **app web** (Android nunca se publicó). "Transmitir en" les llega cuando se publique
  la web, que es aparte y con OK del usuario.
- La presencia necesita internet. Sin internet queda solo el vínculo de la misma PC. El modo local con router es otro
  pendiente, todavía sin escribir.
