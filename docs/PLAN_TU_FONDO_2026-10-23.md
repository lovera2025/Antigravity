# "Tu fondo": la quinta apariencia del tótem (23-oct-2026)

**Estado:** **publicado en la 6.2.0 el 23-oct**: el SQL, el release y la web. Sin instalar todavía. Lo que se hizo en
cada paso está en `docs/CONTEXTO_v6.2.0_2026-10-23.md`.

- Spec del usuario: `Desktop\SPEC_totem_tu_fondo.md`.
- Diseño en Claude Design: https://claude.ai/artifact/7QwqMNZtr44HMbBrkqJPor ("Tótem · Tu fondo"), privado en su cuenta.

## Qué es

El jefe carga una imagen (una story, por ejemplo) y **el tótem entero sale de ella**. No es Neón ni Gala con una imagen
atrás. Lo que pidió, por encima del spec:

- **Dos imágenes:** la foto del círculo queda como siempre; el fondo es otra imagen, aparte.
- **La animación de la imagen y los efectos son dos cosas distintas.**
  - La animación es lo que hace la imagen misma: quieta, acercarse, recorrer, flotar, respirar u ondular.
  - Los efectos van encima, sin tocarla: destellos, polvo de luz, bokeh, titileo, barrido de luz, marco que respira,
    glitch y bruma.
  - Se combinan.
- **Adaptativo = cada imagen trae su propia receta.** Se lee la imagen y sale la animación, los efectos, los colores y
  las letras. En Personalizar arranca en "Automático · según la imagen", y se puede cambiar a mano.

## La receta (`services/lectura_del_fondo.dart`)

**Se lee una vez**, al cargar la imagen en Personalizar, sobre una copia de 72 px de ancho. Se mide:

- la luz media, y la luz del centro (donde va el texto);
- qué tan colorida es (Hasler y Süsstrunk) y cuántos colores distintos tiene (la "variedad": un dorado fuerte es uno
  solo; una fiesta, muchos);
- si es cálida o fría;
- cuánto detalle tiene;
- dónde está lo importante (grilla de 6 × 8).

| La imagen | Animación | Efectos | Letras |
|---|---|---|---|
| Clara (un pastel) | Respirar | Bokeh | Suave (Outfit + Cormorant), texto oscuro, sin oscurecer |
| Cálida (dorados) | Acercarse a lo importante | Polvo de luz y barrido | Clásica (Cormorant) |
| Fría (de noche) | Recorrer hacia lo importante (u ondular, si está al centro) | Titileo y bruma | Moderna (Outfit + Tilt Neon) |
| Muy colorida (una fiesta) | Flotar | Destellos y marco que respira | Fiesta (Oswald + Tilt Neon) |
| Lo demás | Acercarse | Polvo de luz | Clásica |

- Con mucho detalle se mueve menos (si no, tiembla); lisa, más.
- **Con las cuatro imágenes del diseño da exactamente sus recetas.**
- **Los tres colores** (brillo, saludo, tarjeta) salen de `material_color_utilities` (Celebi y Score):
  - **Score, con una imagen casi blanca, devolvía el azul de Google**: se le da un respaldo propio;
  - **el saludo siempre se lee:** contraste 4,5 contra la luz del centro ya oscurecida; si no llega, va blanco (o casi
    negro, con el texto oscuro).
- **La receta y los colores se guardan con la config**: la PC y el tótem por el navegador muestran lo mismo sin volver
  a leer la imagen. Los colores se rehacen al guardar: dependen del oscurecido.

## Lo que se guarda (`totem_config`, 11 columnas nuevas)

`fondo_url`, `fondo_automatico`, `fondo_animacion`, `fondo_efectos` (con comas), `fondo_intensidad`,
`fondo_intensidad_efectos`, `fondo_oscurecer`, `fondo_paleta` (`#RRGGBB,#RRGGBB,#RRGGBB`), `fondo_foco` (`x,y`),
`fondo_letras` y `fondo_luz` (la del centro).

- **Sin NOT NULL, DEFAULT ni CHECK**, como `mostrar_musica` y `estilo`: vacía quiere decir "lo de siempre".
- **Lo que una versión no conoce se guarda como vino** (una animación o un efecto nuevos), igual que `estilo`: si no,
  guardar Personalizar pisaría lo que eligió una más nueva.
- **Personalizar arma la config campo por campo**: lo del fondo viaja entero (`TotemConfig.conFondoDe`). Un test lo
  cuida.

## Cómo se dibuja

- **`shaders/totem_tu_fondo.frag`:** la imagen con su animación (y el glitch, que necesita la imagen) y el
  oscurecido.
  - Una story en una tele horizontal va entera al medio, con su copia chica y borrosa a los costados (un segundo
    sampler, hecha una vez al cargar).
  - El orden de los uniformes está en su cabecera.
- **`estilos/fondo_propio.dart`:**
  - `CargaDelFondo` decodifica la imagen (hasta 1.920 px) y la suelta al cambiar;
  - `FondoPropio` la pinta. Sin shader, o con "Quieta" sin glitch, `PintorFondoQuieto` da lo mismo que el shader sin
    animación.
- **`estilos/escena_tu_fondo.dart`:** los efectos (con el reloj de la escena; cada período divide a 60 s) y la espera y
  la llegada en las letras y los colores de la imagen.
  - Detrás del texto se oscurece o se aclara según la luz del centro.
  - Con texto oscuro, la llegada no atenúa la imagen.
- **Nunca una pantalla rota:**
  - si el shader no carga, va la imagen quieta;
  - si la imagen no está en la PC ni baja, va la apariencia del tipo (`EscenaTotem.respaldo`), con `debugPrint`;
  - sin fondo cargado, "Tu fondo" no se puede elegir (`EstiloTotem.elegida`).

## Sin internet

- **El fondo se guarda en `Documentos\Junior Eventos\fondos_totem\<evento>`**, aparte de las fotos. `FotosDelTotem`
  deja una sola imagen por carpeta y evento: en la misma carpeta, guardar el fondo borraba la foto del círculo, y sin
  internet el círculo podía mostrar el fondo.
- "Lista para trabajar sin internet" pide el fondo **solo si el tótem va con "Tu fondo"**.

## Con las versiones de antes

- Una 6.1.1 (o 6.0.0) que lee `estilo = 'tu_fondo'` no lo conoce y va a la apariencia del tipo (verificado en
  `019bca3`).
- Si guarda Personalizar, deja `'tu_fondo'` y las columnas `fondo_*` como estaban: su upsert no las nombra.
- **Las PCs pueden quedar sin esta versión;** solo no muestran "Tu fondo".

## Cómo se prueba

- **Tests:**
  - `totem_config_test` (modelo y SQL);
  - `lectura_del_fondo_test` (rosa, oscura dorada, casi blanca, fiesta, noche, foco);
  - `fondo_propio_test` (shader con cada animación, respaldos, horizontal, carga);
  - `escena_totem_test` (grupo "Tu fondo");
  - `personalizar_totem_test` (grupo "Tu fondo");
  - `foto_guardada_test` (la foto y el fondo conviven);
  - `lista_sin_internet_test`.
- **Muestras:** `flutter test tool/totem_muestra_test.dart --plain-name "Tu fondo" --dart-define=salida=<carpeta>
  --dart-define=fondos=<carpeta con JPG/PNG>`.
- **Arnés, sin base ni nube:** `flutter run -d windows -t tool/tu_fondo_prueba.dart`, o
  `flutter build web -t tool/tu_fondo_prueba.dart --no-web-resources-cdn --output build/tu_fondo_web` y servir la
  carpeta.
- **Probado el 23-oct en el navegador (CanvasKit):** el shader lee la imagen ("con shader"); ondular, glitch y la tele
  horizontal sin errores en la consola.
- **Falta, después del SQL:** guardar con un evento de verdad, ver el tótem de la ventana y el de `?totem`, y "Lista
  para trabajar sin internet" con la red cortada.

## La publicación (con el OK del usuario en cada paso)

1. **El SQL, primero:** `supabase/migrations/20261023120000_totem_config_tu_fondo.sql`, en el SQL Editor, con los
   conteos de antes y después. **Sin él, guardar Personalizar falla** en las PCs nuevas y en la web: `toJson()` manda
   todas las columnas (pasó con `mostrar_musica`).
2. **Unir** `feature/totem-tu-fondo` a `feature/v4.6-cierre-por-sesiones`.
   - No se unió antes a propósito: una publicación de la rama principal sin el SQL rompería el guardado.
3. **La versión** (sugerida: 6.2.0), en `pubspec.yaml` y en el instalador.
4. **La web** y el instalador.
5. **Las novedades del release dicen "Nuevas características y detalles"** (pedido del usuario el 23-oct).
6. Instalar las PCs, con él presente.
