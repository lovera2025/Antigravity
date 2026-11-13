# Contexto: la 6.8.0 — el link del delegado, y todo lo de la 6.7.1

12 y 13-nov-2026 (noche). Rama `feature/v4.6-cierre-por-sesiones`. **Un SQL nuevo en la nube, solo de
agregar** (`supabase/migrations/20261113120000_link_delegado.sql`). **Sin migración en las PCs**: la
base del equipo sigue en la v79. Viene de `docs/CONTEXTO_v6.7.1_2026-11-12.md`.

## Para retomar en otro chat

**Estado al cortar (13-nov, 0:30): la 6.8.0 está PROGRAMADA, probada en el sandbox y guardada en la
rama, SIN PUBLICAR.** Versión `6.8.0+74` en `pubspec.yaml` y en el `.iss`. El usuario pidió guardar
el contexto para seguir en otro chat. **No se corrió ningún SQL en su nube ni se tocó la web.**

**Decidido por el usuario el 12-nov: sale todo junto en una sola versión, la 6.8.0.** La 6.7.1 (el
tilde "Cumplimiento debido" en el cartel del SORTEO y la cruz para alinear) ya no se publica sola:
va adentro. **No volver a preguntarle si se publica la 6.7.1.**

| | Estado |
|---|---|
| El SQL del link (tres tablas cerradas y trece funciones) | Escrito. **Sin correr en la nube** |
| Las reglas, contra ese mismo SQL en un Postgres de prueba | **61 de 61 pasan** (`node pruebas.mjs`) |
| La página del delegado (`?delegado&clave=…`) | Programada |
| La sección LINK PARA LOS DELEGADOS y ACEPTAR Y CARGAR | Programadas |
| La alerta en el Centro de Comando y el punto en PLANILLAS | Programados |
| `flutter test` entero | **4.670, todas pasan** (13-nov, después de la última corrección) |
| De punta a punta, con la página y la ventana de verdad contra el Postgres de prueba | Hecho, con clics, en el navegador de la app. 13 capturas en `build/capturas_680/` (no van a git) |
| Capturas enviadas al usuario | Sí: las de la prueba suelta (12-nov) y 9 del recorrido con la página de verdad (13-nov). **No contestó todavía qué le parecen** |
| El instalador, el APK y la web de la 6.8.0 | **Sin armar** |
| Foto de la mora "antes de 6.8.0" | Sin sacar |

### Lo que falta, en orden

1. **Preguntarle qué le parecen las capturas del recorrido** (se le mandaron 9 el 13-nov; las 13
   están en `build/capturas_680/`, que no va a git: si esa carpeta ya no está, se sacan de nuevo
   con la prueba de punta a punta). Quiere ver las capturas antes de aprobar o publicar.
2. **Que el link funcione de verdad**, con su OK **uno por uno y en el momento** (así lo pidió: "que
   ese link ya funcione"):
   1. correr el SQL en la nube con el conector de Supabase (solo agrega; los conteos de antes y
      después de la sección 6 del archivo tienen que dar igual);
   2. probar ahí las funciones con un link de prueba y borrarlo al terminar, sin tocar ningún
      alumno (el conector corre como dueño: para hacer de "con usuario" hay que poner el rol en la
      misma consulta, como hace `tool/delegado_sandbox/db.mjs`);
   3. poner la página en una dirección de prueba de Vercel (`flutter build web --release`, copiar a
      `.vercel/output/static` y `npx vercel deploy --prebuilt`, **sin** `--prod`), para que abra el
      link desde su celular por WhatsApp. La web de siempre no cambia.
3. ~~El título cortado del selector del día ("Hasta qué día pu…")~~ **Hecho el 13-nov**: ahora
   dice "Día límite" (`elegirLimiteConSelectores`, `link_del_delegado_panel.dart`).
4. Lo que quedó abierto de la 6.7.1, antes de publicar: si "Por filas" corregido es lo que quería
   (recorrerlo con el mouse en `tool/plano_prueba.dart` y mandarle la captura), y **qué dicen las
   novedades** de la 6.8.0.
5. Publicar con su "publicá": foto de la mora "antes de 6.8.0", el SQL si no se corrió ya, el
   instalador por pasos, el APK, tag `v6.8.0`, release y web. Paso a paso en "Cómo se publicó" de
   `docs/CONTEXTO_v6.7.0_2026-11-12.md`.
6. Que instale, primero la PC que sortea, y la foto "después" (cubre de la 6.6.1 en adelante).
7. Con la 6.8.0 instalada: **aceptar de verdad desde el programa** (es lo único que ni el sandbox
   ni la nube pueden probar) y, de la 6.7.1, las preguntas del final de su contexto.

**No crear links hasta que las PCs tengan la 6.8.0 y el SQL esté corrido.** Una PC con una versión
anterior no ve la sección y no rompe nada.

### Lo que NO se probó

- **Supabase de verdad.** El SQL corrió en PGlite (PostgreSQL 16) con los dos roles y un
  `auth.role()` de mentira. Los tipos de las columnas que lee sí se miraron en la nube (solo
  lectura, 12-nov): `contratos_alumnos.id` y `evento_id` son `uuid`, `nombres_acompanantes` es
  `text[]`, `eventos.id` es `uuid`.
- **Un celular de verdad**, y el link abierto desde WhatsApp. Riesgo conocido: WhatsApp puede abrir
  el link en su propio navegador; si el delegado después lo abre en otro, la nube lo toma por un
  celular nuevo (ocupa otro lugar y no puede editar lo que cargó antes). Se arregla sacando al
  primero "dejando lo que cargó".
- **Aceptar desde la pantalla de la fiesta instalada** (`detalle_evento_masivo_screen.dart` no se
  puede montar en una prueba) y **la alerta abriendo la fiesta** con la base de verdad. En la
  prueba de punta a punta la alerta abre la misma ventana, pero no la pantalla de la fiesta.
- **Dos guardados en el mismo instante con dos conexiones**: PGlite tiene una sola. En la nube lo
  garantiza que cada función que escribe toma la fila del link (`for update`).
- **El Excel junto con el link en la misma fiesta**, con la pantalla. La revisión es la misma y está
  probada para cada origen por separado.
- Dos PCs.

## Qué pidió

Algo más fácil que el Excel para cargar acompañantes y música, "que todos puedan usar", que no
fuera Excel, y seguro. Lo fue definiendo con una maqueta y preguntas (12-nov):

- **Convive con el Excel**, que no cambia.
- **Un link por evento masivo**, con todos sus alumnos activos (los de baja temporal no).
- **Sin código**: el grupo de WhatsApp donde lo manda "son todos los delegados nomás".
- **Entran varios delegados** (él elige cuántos, 1 a 5) **y no se pisan**: el alumno que cargó uno
  queda a su nombre y los demás lo ven cerrado.
- **Lo ya cargado en el programa** se ve gris, tachado, y no se toca desde el link.
- **Día y hora límite exactos**, que pone él.
- **Guardar** en el lugar de cada alumno y **Enviar** abajo, bien distintos. Enviar es una sola
  vez, con un aviso "amable, convincente y profesional" y una casilla.
- **Dos acompañantes, ni uno más**; la música, texto libre "bien detallado".
- El aviso le llega **cuando un delegado envía**, no por cada guardado ("si no, a cada rato me
  saltaría la alerta"); tocarlo lo lleva al evento masivo y **aceptar** carga.
- Pidió **probarlo en un sandbox antes de integrarlo**, y después que "ya funcione" de verdad.

## Cómo queda

**En la fiesta** (PLANILLAS → "Acompañantes y música", en modo jefe), debajo del Excel: **LINK
PARA LOS DELEGADOS**. Sin link: el límite (día y hora), cuántos delegados y CREAR LINK. Con link:
COPIAR, el límite (CAMBIAR EL LÍMITE), cuántos, APAGAR, cada celular (quién dijo ser, cuándo entró,
cuántos cargó, si envió) con REABRIRLE y SACAR, y **TRAER LO CARGADO**.

**TRAER** abre el "Antes de guardar" de siempre, con quién cargó cada alumno. Lo que todavía no
enviaron va aparte, con un tilde para incluirlo. **ACEPTAR Y CARGAR** guarda por el mismo camino
del Excel.

**El aviso**: una alerta en ALERTAS del Centro de Comando, que se toca: abre ese evento masivo y,
en modo jefe, directo la revisión. Y un punto en PLANILLAS. La ve cualquiera; aceptar, el jefe.

**La página** (`https://arguello-events.vercel.app/?delegado&clave=…`): la fiesta, "¿Sos delegado
de…?", nombre y apellido; la lista por división con buscador; Guardar en cada alumno; Enviar abajo,
con "Antes de enviar, una última revisión", cuántos faltan y la casilla; y el agradecimiento.

## Cómo está hecho

### La nube: `supabase/migrations/20261113120000_link_delegado.sql`

Tres tablas **cerradas del todo** (RLS, sin políticas, sin permisos para nadie): `links_delegado`
(uno por fiesta: la clave, el nombre de la fiesta, el límite, el cupo), `celulares_delegado`
(quién entró) y `cargas_delegado` (lo cargado, una fila por alumno). No son de la base de las PCs.

- **Todo por funciones**, con el molde de `puerta_funciones.sql`. Sin usuario: `delegado_lista`,
  `delegado_entrar`, `delegado_guardar`, `delegado_entregar`. Con usuario (`auth.role()`):
  `delegado_link_crear`, `delegado_link`, `delegado_link_cambiar`, `delegado_cargas`,
  `delegado_pendientes`.
- **No escribe nunca en `contratos_alumnos` ni en `eventos`**: solo los lee. A la grilla entra lo
  que el programa guarda después de la revisión.
- **El límite lo decide el reloj de la nube** (`delegado_ahora()`), y el texto "jueves 19/11 a las
  20:00" lo arma la nube en hora de Argentina (`delegado_texto_fecha`). La página no usa el reloj
  del celular para nada.
- **Cada función que escribe toma la fila del link** (`for update`): lo de un link va de a uno, y
  de dos guardados del mismo alumno queda uno solo.
- **El nombre de la fiesta lo manda el programa** al crear el link (`links_delegado.fiesta`): las
  funciones no dependen de ninguna columna de `eventos`.
- **La música se guarda en un solo renglón** (`delegado_un_espacio`), como la del Excel.
- **El aviso** (`delegado_aviso`): alguien envió después de la última vez que se trajo, o el link
  venció y alguien que no envió dejó algo sin traer. Cada carga sabe si ya se trajo (`traido_at`):
  con una sola fecha por fiesta, el aviso de "venció sin enviar" no saltaba si antes se había
  traído lo de otro delegado (lo encontró el recorrido en el navegador).

### Las pruebas de reglas: `tool/delegado_sandbox/`

`npm install` (baja PGlite a esa carpeta; `node_modules` no va a git) y `node pruebas.mjs`. Corre
el **mismo archivo de la migración** en un Postgres en memoria, con el reloj de la nube puesto a
mano para probar el límite al segundo. `revision.js` hace de programa en esas pruebas. **Un cambio
al SQL del link se corre ahí antes de darlo por bueno.**

### El programa

- `lib/features/delegado/datos/`: `NubeDelDelegado` (la página) y `LinkDelDelegado` (el programa),
  **solo `.rpc`**, y `lecturaDeLasCargas`, que lleva lo cargado a `PlanillaDelegado.comparar`.
- `lib/features/delegado/pagina/`: `DelegadoApp` y `PaginaDelDelegado`. La sesión del celular, en
  `shared_preferences` (`SesionesDelDelegado`).
- `lib/features/delegado/delegado_providers.dart`: los proveedores (leen `supabaseProvider`) y
  **`avisosDelDelegadoProvider`**, sin reloj: lo invalida `OperationalSyncCoordinator` al arrancar
  y al volver a la ventana, y la ventana después de traer. Sin internet, lista vacía.
- `planilla_delegado.dart`: `comparar` acepta lo del link (`LecturaPlanilla.delLink`): los
  acompañantes vienen separados (`RenglonDelegado.nombres`), no avisa la coma, y manda el id del
  alumno, no el nombre. **El Excel no cambió.**
- `acompanantes_musica_dialog.dart` y `link_del_delegado_panel.dart`: la sección y TRAER.
  **Guardar es el `onImportar` de siempre** (`cargarAcompanantesYMusica`, la puerta, la subida).
  Avisarle a la nube qué se trajo va después y no frena nada.
- `dashboard/widgets/alertas_del_delegado.dart`, y `hayParaTraer` en `GrupoFiestaToolbar`.
  `DetalleEventoMasivoScreen(abrirLoDelDelegado: true)` abre la revisión al entrar.
- La ruta: `lib/main.dart`, `currentUrl.contains('delegado')`. La clave es hexadecimal: no puede
  traer la palabra de otra ruta.

### Tres trampas que aparecieron

- **Una llamada a una función de la nube lleva siempre `params`, aunque no mande ninguno.** Sin
  eso la librería de Supabase manda `null` de cuerpo en vez de `{}` y la llamada falla: así el
  aviso del inicio no llegaba nunca, sin ningún error a la vista (`delegado_pendientes`). Lo
  vigila `test/link_delegado_cerrado_test.dart`.
- **Las pruebas que leen la pantalla de la fiesta buscan la firma exacta de
  `_abrirAcompanantesYMusica`** (`test/solo_modo_jefe_test.dart`,
  `test/puerta_sigue_al_salon_test.dart`): al cambiarla hay que cambiarla en las dos.
- **Para llevar una lista arriba después de que cambió lo que hay encima, el salto va después de
  que la pantalla se acomodó** (`_arriba`, en la página): dado antes, quedaba corrido.

### Cómo se prueba

- `test/link_delegado_cerrado_test.dart`: el SQL contra lo que llama el programa; nada de
  `lib/features/delegado/` lee una tabla; la página no usa el reloj del celular.
- `test/pagina_del_delegado_test.dart`, `test/link_del_delegado_en_la_ventana_test.dart`,
  `test/alertas_del_delegado_test.dart`, con `test/helpers/delegado_en_memoria.dart`.
- De punta a punta, **la página y la ventana de verdad contra el Postgres de prueba**:

  ```bash
  flutter build web -t tool/link_delegado_prueba.dart --output build/link_delegado_prueba --no-web-resources-cdn
  ```
  ```bash
  node tool/delegado_sandbox/servidor.mjs
  ```
  ```bash
  node tool/delegado_sandbox/preparar.mjs 3
  ```

  El cliente de Supabase de la prueba apunta a esa misma dirección y el servidor contesta
  `/rest/v1/rpc/…` con el SQL de verdad. Cada puerto (8800 a 8803) es un aparato distinto.
  `preparar.mjs` reinicia los datos, crea un link y dice las dos direcciones.
  - La prueba prende sola la lectura de pantalla, para poder manejarla desde el navegador de la
    app. **Con `&sinlectura` en la dirección queda como un celular común**, y ahí se maneja por
    coordenadas: con la lectura prendida, tocar algo puede correr la lista.
  - Para capturas nítidas, el tamaño del celular va en 375×527 y el del programa en 610×527: con
    más, el navegador de la app achica la imagen.

## Probado

- **Reglas** (61): qué alumnos muestra el link (los activos de esa fiesta y nadie más, lo ya cargado
  cerrado), el límite al segundo y en hora de Argentina, guardar y enviar una sola vez, varios
  celulares sin pisarse (también dos a la vez sobre el mismo alumno), el cupo, sacar y reabrir,
  apagar, los topes (2 acompañantes, 80 y 300 letras), que nadie sin usuario lea una tabla ni use
  lo del jefe, y el aviso (salta al enviar o al vencer, uno por fiesta, se va al traer).
- **La app** (4.670): entre ellas la página entera, la ventana con el link, la alerta, y las que
  comparan el SQL con lo que llama el programa.
- **De punta a punta, con clics**: crear el link con los selectores de día y hora, entrar (sin
  apellido no entra), la lista, lo ya cargado que no se abre, guardar, volver a abrir y seguir
  adentro, Enviar con cambios sin guardar, el aviso con el número justo, sin tildar no confirma,
  confirmar y el agradecimiento, el segundo celular viendo lo del primero cerrado, el que no entra
  por el cupo, un link mal copiado, la alerta con los dos delegados, la revisión, ACEPTAR Y CARGAR,
  la grilla, REABRIRLE, SACAR, APAGAR y PRENDER, y CAMBIAR EL LÍMITE.
- El recorrido encontró cuatro cosas que las pruebas no habían visto, todas corregidas: el aviso
  de "venció sin enviar" que no saltaba, el aviso del inicio que no llegaba (`params`), un cartel
  rojo que quedaba después de guardar y el agradecimiento fuera de la vista al enviar.
