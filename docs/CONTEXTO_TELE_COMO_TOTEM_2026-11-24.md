# La tele es el tótem (24-nov-2026)

El plan: `docs/PLAN_TELE_COMO_TOTEM_2026-11-24.md`. El usuario pidió saltear la maqueta: programar, probar en el
sandbox y darle la app de prueba para sus pruebas internas, sin publicar.

## Para retomar en otro chat

**26-nov (noche): el APK de la app de verdad para la Google TV — el paso 0 del plan del 26-nov** (plan:
`C:\Users\lover\.claude\plans\c-users-lover-desktop-plan-sp-fancy-wall-of-db314a36-8fe0-4cf2-ad8e-bd040753c86b.md`).
Sesión aparte en la rama `claude/priceless-borg-e85cd6` (sobre la feature en `173037f`, más `18b1b5d` de la barra traído
con `cherry-pick`); **sin juntar con la feature, sin
tag, sin release y sin web**: lo junta la sesión que coordina. El usuario pidió que **las pruebas las haga Claude en el
sandbox** (no está en casa).
1. **La nube sin las tablas del stock** (el SQL `20261125120000_barra_stock.sql` sigue **sin correr**): la app con la v83
   **baja todo lo demás igual**. La nube contesta `PGRST205` (404) y eso **no es una caída** (`esCaidaDeLaNube`): cada
   tabla baja por su lado y la que falta queda nombrada. Prueba nueva `test/nube_sin_las_tablas_del_stock_test.dart`
   (`NubeDePrueba.faltan`, en `test/helpers/`): el arranque pide cada tabla del cobro y de carga y guarda lo que hay; el
   estado dice "No bajaron: barra_stock_barras, barra_stock_movimientos" y nada más; en reposo, silencio; la red de 5
   minutos y un aviso que nombra el stock bajan lo demás; "Lista para trabajar sin internet" queda lista. Roturas:
   `tool/roturas_nube_sin_stock.txt`, **3 de 3**. **No hizo falta tocar el motor ni correr el SQL.**
   - **Lo que sí cambia mientras falte ese SQL** (no se tocó; con el SQL corrido desaparece): el ícono de sincronización
     queda en error con ese "No bajaron"; la revisión de la mora **no corre sola** en esa sesión (espera una bajada
     entera, `_bajar`: `_tablasConFalloPull.isEmpty`; en la tele no hace falta, y así la tele no sube correcciones de
     mora); la revisión de borrados la hace la de los 20 s en vez del arranque.
2. **LA FIESTA sin la línea de cada escuela, en la app de prueba del emulador: la causa era la app de prueba.**
   `tool/tele_prueba.dart` pone las escuelas con la fecha de hoy, pero "preparar las fiestas" en memoria
   (`SinInternetEnMemoria`) usaba la hora fija de las pruebas (12-dic-2026): las daba por pasadas y no les armaba la
   línea. Ahora `SinInternetEnMemoria.reloj` y la app de prueba le pasa la hora de verdad. **En la app de verdad había
   una variante:** LA FIESTA lista todas las que vienen, pero se preparan solo las 10 primeras de los próximos 30 días;
   las demás salían sin línea. Ahora cada una dice algo (`PrepararLasFiestas.sinPreparar`: "Se prepara sola cuando
   falte un mes", "Todavía no se prepara: primero las 10 que vienen antes" o "Preparándose…"). Pruebas en
   `preparar_las_fiestas_test` y `pantalla_tele_test`; roturas R53 y R54 en `tool/roturas_tele.txt` (atrapadas).
   **Confirmado en el emulador `Recepcion_Tablet`** (sin ventana, `-gpu host`, la app de prueba x86_64): las dos
   escuelas con "Lista sin internet · al día hoy 18:42" (`build/capturas_tele/Emulador_LaFiesta_26nov.png`).
3. **El APK: `installer\dist\prueba\Junior Eventos app de verdad tele.apk`** (del checkout principal; fuera de git;
   SHA-256 que empieza con `a1fd7c0a8e7d04d5`, 116 MB; reemplaza al primero, `cc98bc1b…`, que no llegó a instalarse). `lib/main.dart`, `ar.com.junioreventos.app`, **6.9.4 (79)** (el
   número del `pubspec.yaml`, que no se tocó), armado con `flutter build apk --release --target-platform
   android-arm,android-arm64` (**32 y 64 bits**), firmado con la clave de siempre (`apksigner`: CN=Junior Eventos;
   `android/key.properties` copiado del checkout principal, fuera de git) y con la página del celular entera (145
   archivos en `assets/puesto`, con `FontManifest.json`, los íconos y Roboto; `build/puesto` armado de cero en esta
   carpeta). Trae una carpeta `lib/x86_64` incompleta (solo `libsqlite3` y `libdatastore_shared_counter`, de dos
   plugins): en un aparato ARM no importa; en el emulador x86_64 se instala con `adb install --abi arm64-v8a`.
   **En el emulador abrió hasta el login** (arm64 traducido); el registro mostró que **la nube de verdad contesta
   `PGRST205`** por las dos tablas del stock, como la prueba, y "No bajaron: barra_stock_barras,
   barra_stock_movimientos". Sin usuario no subió nada. Huella de la base de esta PC antes y después: **IGUAL**.
   - Ojo: es 6.9.4 (79) con la base v83. Si en esa tele se instalara después la 6.9.4 publicada (la de la v82), la base
     quedaría más nueva que la app: no hacerlo; la próxima versión publicada (mayor) la reemplaza bien.
3b. **La Tele 1 sigue contestando a la Tele 2 después de un cambio de wifi** (lo pidió la sesión que coordina, antes de
   armar el APK). Se trajo `18b1b5d` de la feature (la barra se reconecta sola al volver al wifi: `BuscaCentral`, que usa
   la Tele 2, renueva su socket, y `VigiaDeLaRed`). **La Tele 1 tenía la misma falla:** `RespondeLaTele1.escuchar`
   (`busqueda_de_la_tele.dart`) no miraba si su socket se moría, y dejaba de contestar hasta reiniciarla. Ahora, como
   `RespondeBusqueda`, lo vuelve a abrir solo (`_seMurio`, `esperaParaReabrir`) y `reabrir()` lo cambia por otro; la
   central de la tele (`central_provider.dart`) prende el vigía de la red (`vigiaDeLaRedProvider`) y al cambiar de red
   reabre. Pruebas en `cliente_de_la_tele_test` (se muere y la Tele 2 la encuentra igual; reabrir; apagada no se reabre);
   roturas R55 y R56 en `tool/roturas_tele.txt` (atrapadas). **No probado aparte:** que el vigía llame a `reabrir` (está
   igual que en la barra; ninguna prueba lo mira en la central de la tele). 63 archivos de pruebas (tele, central, puerta,
   barra y lo tocado): **1230 en verde**; `flutter analyze` sin nada en lo tocado. El APK nuevo abrió hasta el login en el
   emulador (hubo que desinstalar las dos apps del emulador: no tenía lugar). Huella IGUAL.
4. **Al usuario se le avisó** que es la app de verdad contra la nube de verdad (lo que marque como ingresado en una
   escuela real queda marcado en esa fiesta: probar con una fiesta de prueba o deshacer los ingresos), y se le pidió la
   foto de "Cómo anda" y qué no anda. "Cómo anda" está solo en la app de prueba: en la de verdad no aparece.

**Lo que falta (de este paso 0):** la prueba en la Quint de verdad (la hace el usuario cuando vuelva: no está en casa);
lo que encuentre entra en el paso 2 del plan. Juntar esta rama con la feature lo hace la sesión que coordina.

**26-nov: la revisión independiente de la Parte 1, arreglada con sus pruebas y sus roturas** (sin publicar, en la misma
rama; el detalle de cada hallazgo, abajo en "La revisión del 26-nov"). Lo pidió la sesión que coordina (la
"Continuación post-6.9.4"): suite + `flutter analyze`, la ventana con dos escuelas, la prueba de punta a punta con la
huella IGUAL, capturas, roturas y la revisión. **No se junta con la feature, no se sube y no se arma el APK de prueba:
eso lo hace la sesión que coordina después de juntar.** Sigue sin tocarse `lib/features/barra/` ni la v83. Desde el
26-nov el repositorio no nombra alumnos reales: los casos nuevos van con apellidos de árboles y pájaros.

### La revisión del 26-nov

Un subagente leyó el diff `2a0a0d2..HEAD` sin mis conclusiones. Encontró 11 cosas; todas arregladas:
1. **`/tele` y la búsqueda por UDP abiertas a cualquier escuela** (la más grave): con el id de cualquier evento una
   tele entraba y se llevaba el código de los celulares y la lista. Ahora `CentralPuerta.conoce(id)` (la que muestra,
   las que atiende o las que vienen de LA FIESTA) decide `/tele` (si no, 4001), `atender`, `cambiarEscuelaDeTele` y
   `RespondeLaTele1` (que ya no dice cuáles atiende).
2. **El código "por noche" duraba lo que la central prendida** y la clave era siempre `tele`. Ahora
   `CodigoCentral.claveDeLaNoche` (la noche va de mediodía a mediodía: a las 3 sigue la de la fiesta), la central se
   vuelve a prender cuando empieza otra noche, y `_asegurar` de la tele lleva la noche en su clave. El reloj de la
   central es `relojDeLaCentralProvider` (las pruebas lo mueven).
3. **"Pasar a principal" dejaba sin camino a la escuela de la Tele 1 apagada:** `atenderSinTele` la pone en el lugar
   de la Tele 2, y CELULARES muestra **dos QR** ("ESTA TELE" y "SIN TELE", el segundo con `&t=2`).
4. **Pasar a una escuela sin lista dejaba la de antes en el celular** (y su salón): la central manda `esperando` y un
   salón vacío **con la escuela**; el celular suelta la lista, y no muestra un salón de otra escuela (`_salonDe`).
5. **La central podía quedar en una escuela que la tele no muestra:** si la Tele 1 no la tiene entre las que vienen
   (`_laTeleLaMuestra`), la central vuelve a la de la tele y el cartel dice "Esta tele no tiene esa escuela"; la Tele 2
   hace lo mismo con lo que le pide la Tele 1.
6. **La Tele 2 desconectada "cambiaba" de escuela sin enterarse:** ahora no (el celular recibe "La Tele 2 no está
   conectada"), y a una pregunta MANTENER · CAMBIAR solo se suman teles conectadas.
7. **Las escuelas no se soltaban nunca:** la que ninguna tele muestra se suelta (`_soltarSinTele`, `alSoltar`: el
   provider deja de escucharla y, si vuelve, la escucha de nuevo); la Tele 2 desconectada conserva la suya. Al pasar a
   principal, la Tele 2 sube solo lo copiado de las escuelas que la Tele 1 atendía al final.
8. **Guardar Personalizar esperaba el aviso a las teles:** va sin esperar (`unawaited`).
9. **Preguntas viejas:** si la tele vuelve a cambiar, la pregunta de antes se cierra ("volvió a cambiar") y su
   respuesta no hace nada; sin conexión, contestar no se manda y la pregunta queda (el celular lo dice); elegir la
   propia tele saca la pregunta de la otra.
10. **Apagar mientras se prende dejaba una central abierta:** `_vuelta` cuenta cada prender/apagar; la que terminó de
    arrancar tarde se cierra. Los oyentes de una central vieja no hacen nada (`identical(_central, central)`).
11. **El orden de `_asegurar`:** con la central ya prendida como tele, cambiar de escuela no vuelve a copiar la página
    del celular. `cambiarCodigo` le avisa el código nuevo a la Tele 2.

**Se descartó un hallazgo mío:** creí que el celular no mostraba los avisos de la central; los muestra `PanelPuerta`.

**Lo que apareció en la prueba de punta a punta** (arreglado, con su prueba y su rotura):
- **Con la Tele 1 apagada, cada reintento de la Tele 2 (y del celular) dejaba un error sin atender** (el `ready` de la
  conexión; lo mostró el registro del emulador). Venía de antes de esta rama. Ahora `canal.ready.catchError`, en
  `cliente_de_la_tele.dart` y `cliente_central.dart`.
- El texto de LA FIESTA decía "Con dos teles, las dos van con la misma": ahora "cada una puede tener la suya".

**Cómo quedó probado (26-nov):**
- `flutter analyze`: sin errores ni avisos en lo tocado.
- **La suite entera: 342 archivos, 6303 pruebas, 0 fallas** (la segunda vuelta, con todos los arreglos; la primera
  dio 6301 de 6301).
- **Las roturas, `tool/roturas_tele.txt`: 52 de 52** (R6 no la agarraba: su prueba miraba antes de que llegara el
  mensaje; se arregló la prueba). Las pruebas nuevas: `tele_segunda_provider_test`, grupos nuevos en
  `tele_dos_escuelas_test`, `tele_central_provider_test`, `celular_tu_tele_test`, `cliente_de_la_tele_test`,
  `tele_central_test` y `pantalla_tele_test`.
- **De punta a punta, en el sandbox** (huella de la base antes y después: **IGUAL**): la ventana `tool/tele_prueba.dart`
  compilada (`--dart-define=escuelas=distintas`) con la Tele 1 y la Tele 2 en escuelas distintas; dos pestañas del
  navegador como celulares (Juli en la Tele 1 por `127.0.0.1`, Caro en la Tele 2 por `localhost`: **dos pestañas del
  mismo origen son el mismo celular**, comparten lo guardado); cada tele saludó a los suyos; TU TELE → CAMBIAR LA
  ESCUELA con su cartel; "Las dos" se prende y se apaga según las escuelas; MANTENER · CAMBIAR le saltó a Caro y **se
  cerró sola cuando la Tele 1 volvió a cambiar**; GIRAR desde el celular. Después **el emulador `Recepcion_Tablet`
  como Tele 2 parada** (APK de `tool/tele_prueba.dart` solo para el emulador, `papel=segunda`, `giro=1`; no se entregó):
  encontró sola a la Tele 1 de la PC, saludó, se apagó la Tele 1 (se cerró la ventana), "Pasar a principal" con las
  flechas del control parado y el PIN en el teclado de la tele, **dos QR**, los dos celulares volvieron solos a la
  nueva central (`adb forward tcp:8787`), Caro marcó en la escuela sin tele, Juli en la de la tele (saludó), y GIRAR →
  Horizontal la acostó.
- Capturas en `build/capturas_tele/` (no van a git): `Punta_1` a `Punta_4` (la ventana), `Emulador_0` a `Emulador_9`
  (la tele parada, el menú, el PIN oculto, los dos QR, acostada, LA FIESTA), y las muestras `Tele_1` a `Tele_6`
  (acostada y parada; `tool/tele_menu_muestra_test.dart`) y `TuTele_1` a `TuTele_6` (`tool/tele_tu_tele_muestra_test.dart`).

**No probado:** aparatos de verdad (la Quint, dos Google TV por el router del salón, un iPhone), el UDP entre dos
aparatos de verdad, el cambio de noche al mediodía con la tele prendida (está en las pruebas con el reloj de prueba,
no en un aparato). En la app de prueba del emulador LA FIESTA no mostró la línea de cómo quedó cada escuela (en la
muestra y en `pantalla_tele_test` sí): falta mirar por qué en la app de prueba.
En la ventana de prueba hubo un momento con **dos Tele 2** (la de la ventana y la del emulador) que se pisaban la
conexión: no es un caso real, pero si alguien pone dos teles como "Tele 2", pasa eso.

**25-nov (tarde/noche): la Parte 1 del plan del 25-nov, programada (etapas 1 a 5), sin publicar.** Plan aprobado:
`C:\Users\lover\.claude\plans\donde-nos-quedamos-porque-inherited-sedgewick-of-b24f55ff-68c4-4d3e-875a-b0916b95685c.md`
(solo la Parte 1 y "La red" son de la tele; la barra la hace otra sesión en `lib/features/barra/`: no tocar esos archivos).
Va en la rama **`claude/peaceful-golick-fa7148`** (worktree `.claude\worktrees\peaceful-golick-fa7148`), salida de la rama feature
en `2a0a0d2`: **todavía no está en `feature/v4.6-cierre-por-sesiones`** (hay que mergearla o hacer cherry-pick, preguntándole al usuario).
Commits: `6ed0686` (girar), `1067cf3` (todas las escuelas listas), `c2797d6` (cada tele con su escuela, el celular y la Tele 1 apagada).

**Lo hecho:**
1. **Girar** (`lib/features/tele/giro_de_la_tele.dart`): `Giro` (horizontal/vertical/darVuelta/segun), `GiroGuardado`
   (`tele_giro_v1`, 0-3 cuartos, se lee en `main.dart` con el modo tele), `giroDeLaTeleProvider`, `GiroDeLaApp` en el `builder`
   del `MaterialApp` (sin modo tele: el hijo tal cual; en modo tele, siempre el mismo árbol, también con 0) y `TeleGirada`
   (`RotatedBox` + `MediaQuery` cruzada + las flechas). **Trampa encontrada:** `FocusNode.rect` de Flutter no gira bien el
   rectángulo (sale con el izquierdo mayor que el derecho) y el recorrido con flechas saltaba a cualquier lado: con la tele
   girada las flechas van a `FlechaEnLoQueSeVe`, que mide cada opción adentro del giro (`TeleGirada.siguiente`); acostada, las
   de Flutter como siempre. `foto_de_lo_quieto.dart`: el corrimiento a píxeles va con la inversa de `getTransformTo`
   (`_corrimiento`), la foto saca **un píxel de más alrededor** (corrida perdía la fila del borde del salón) y un borde que cae
   justo en un píxel ya no da fase 0,9999. Menú: "Girar la pantalla" (Horizontal · Vertical · Dar vuelta, sin PIN); los paneles
   entran parados; **el PIN y la dirección de la Tele 1 con `TecladoDeLaTele`** (`teclado_de_la_tele.dart`, sin `showDialog`).
   Capturas: `tool/tele_salones_de_verdad_test.dart` (grupo "parada"): con los 9 salones, girar no cambia nada (≤0,008 % de
   puntos) y acostada da como antes; las imágenes en `build/capturas_tele/Parada_Salon_*.png` (HOY parada vs LA TELE GIRADA).
   `build/salones_prueba/salones.json` se copió del checkout principal (no va a git).
2. **Todas las escuelas listas** (`lib/features/tele/preparar_las_fiestas.dart`): `PrepararLasFiestas` (los próximos 30 días,
   hasta 10; `bajarListaDelEvento` de cada una, `bajarParaLaPuerta` una vez por vuelta, las apariencias en una sola consulta con
   `AparienciaEnLaPc` → `TotemConfigCache`, foto y fondo si faltan; queda "al día" con `AlDiaDeLaPuerta`), cada 30 min y al
   volver internet; sin internet mira lo guardado (`mirar`). En LA FIESTA, una línea por escuela ("Lista sin internet · al día
   hoy 15:00" o lo que falta). `lista_sin_internet.dart` mira la apariencia (`aparienciaGuardada`, también en la PC).
   `TotemConfigRepository.guardar/guardarTiempos` avisa por el pulso (`avisoDeLaApariencia`, `pulso_entre_equipos.dart`); el
   motor lo lee antes de `trabajoDelPulso` (`aparienciasCambiadasStream`) y la tele invalida `totemConfigProvider` y relee foto
   y fondo.
3. **Cada tele con su escuela:** `CentralPuerta` con lo de cada escuela aparte (`_Escuela`: resolvedor, marcas, lista, tiempos,
   salón, filas), `atiende`, `escuelaDeTele`, `cambiarEscuelaDeTele`, la pregunta MANTENER · CAMBIAR (`_Pregunta`, vence a los
   3 min: se mantiene), "Las dos" solo con la misma escuela (`tu_tele`), `PedidoPuerta.evento`. `CentralDeLaPuerta` no se
   reinicia al cambiar (escucha cada escuela con `_escucharEscuela`), en la tele el código es **uno por noche**
   (`CodigoCentral.deLaNoche`). La escuela de la tele vive en `fiestaDeLaTeleProvider` (`modo_tele.dart`), el cartel en
   `avisoEnLaTeleProvider`. En la tele, LA FIESTA → otra escuela → **cartel que confirma, sin PIN**. La Tele 2 cambia sin
   desconectarse (`ClienteDeLaTele.cambiarEscuela`, `TeleSegunda.conectar`) y copia las filas de todas las escuelas
   (`copiadasDe`). La búsqueda es propia (`busqueda_de_la_tele.dart`, `RespondeLaTele1`: contesta por cualquier escuela con
   `atiende`), **sin tocar `buscar_central.dart` de la barra** (la otra sesión lo toca).
4. **Desde el celular** (`cliente_central.dart`, `pantalla_puesto.dart`): la hoja **TU TELE** (ícono de la tele arriba) con
   CAMBIAR LA ESCUELA (cartel que confirma) y GIRAR; el aviso cuando la tele cambia; el recuadro **MANTENER · CAMBIAR**.
5. **Si la Tele 1 se apaga:** "Pasar a principal" atiende también la escuela de la Tele 1 (`atenderTambien`). Menú: "Dos teles en
   routers separados" explica ponerlas las dos como Tele 1 y avisa que con la misma escuela no se ven.

**En la PC no cambia nada** (todo detrás de `esTele`): `central_puerta_test`, `central_provider_test`, `cliente_central_test`,
`chat_de_la_noche_test`, `sumar_celular_test` pasan sin tocarlos. Se cambiaron a propósito tres pruebas de la tele (la Tele 2
"de otra fiesta" ahora se conecta; el PIN se escribe con el teclado de la tele). Pruebas nuevas: `giro_de_la_tele_test`,
`preparar_las_fiestas_test`, `tele_dos_escuelas_test`, `tele_central_provider_test`, `celular_tu_tele_test` y grupos nuevos en
`pantalla_tele_test` y `cliente_de_la_tele_test`. La última tanda: **201 de 201** (13 archivos de la tele, la central y el
celular). Una tanda de 59 archivos de puerta/tótem/recepción dio 1041 de 1041 con la etapa 2; **con las etapas 3 a 5 falta
correrla** (y la suite entera).

**Trampas de este worktree:** salió con saltos CRLF (el `core.autocrlf` del sistema) y `modo_tele_cerrado_test` busca `\n`:
se restauró en LF con `git -c core.autocrlf=false reset --hard`. Un mensaje de commit con comillas, por archivo (`-F`). En
Dart, `..x = (a) => f(a)` seguido de `..y = …` se come la cascada: con llaves.

**Lo que falta, en orden (al 26-nov: los puntos 1 a 6 están hechos, ver "Cómo quedó probado" arriba; queda el 7, que
hace la sesión que coordina):**
1. La suite entera (`bash tool/suite_por_tandas.sh`) y `flutter analyze` de todo.
2. `tool/tele_prueba.dart` con **dos escuelas** (hoy tiene una sola fiesta inventada; ya tiene el giro con
   `--dart-define=giro=1` y `GiroDeLaApp`): una segunda fiesta, `fiestaDeLaTeleProvider` en memoria por tele, y
   `totemConfigProvider` de las dos.
3. La prueba de punta a punta en el sandbox: huella de la base antes (`python -I tool/huella_de_la_base.py`), la ventana con las
   dos teles y dos escuelas, pestañas como celulares (TU TELE, CAMBIAR, GIRAR, MANTENER · CAMBIAR, "Las dos"), el emulador
   `Recepcion_Tablet` parado y acostado (con `--dart-define=giro=1`), "Pasar a principal", y la huella después (IGUAL).
4. Capturas para el usuario: la tele parada con el menú, Girar, el teclado del PIN, LA FIESTA con cómo quedó cada escuela,
   el cartel de cambiar la escuela; el celular con TU TELE y la pregunta (`tool/celulares_muestra_test.dart` sirve de modelo).
5. Las roturas a propósito en `tool/roturas_tele.txt` (formato de `tool/romper_una_regla.sh`; por ejemplo: quitar la
   traducción de flechas, el píxel de más de la foto, `atender` en `_conectarTele`, el `yaCambio`, el "Las dos" con escuelas
   distintas, `evento` del pedido, el aviso del pulso).
6. **Una revisión independiente** (un subagente que lea el diff `2a0a0d2..HEAD` y el código **sin mi conclusión**, buscando
   errores de verdad: medianoche, sin red, reconexiones, dos teles con escuelas distintas, la PC sin cambios). Lo que
   encuentre se arregla con su test.
7. Mergear la rama a `feature/v4.6-cierre-por-sesiones` (con el OK del usuario) y el APK de prueba suelto (sin publicar).

**Pedido del usuario (25-nov, por la sesión que coordina): "lo importante es que todo esto no tenga bugs, por favor".**
Ninguna etapa se da por cerrada sin: sus tests y la suite entera en verde, las roturas, la prueba de punta a punta con la
huella IGUAL y la revisión independiente. **No usar la migración v83** (es del repositor, en otra sesión) **ni tocar
`lib/features/barra/`** (la barra por día de operación, otra sesión). El 25-nov a la noche el usuario cortó antes de
correr la suite: se retoma cuando vuelva del trabajo, por el punto 1.

**No probado:** nada con aparatos de verdad (la Quint parada, dos teles por el router, el teclado del control girado).

**25-nov: la tele, fluida.** El usuario probó el APK en la Quint: "anda todo ok", pero las animaciones iban a los
saltos. Pidió que se vea igual de lindo (el plano con sus números, la guía, todo animado) y que ande súper fluido,
probado **con los salones de verdad de todos los eventos masivos**, y que en la app de verdad no aparezca ningún
número. Plan: `C:\Users\lover\.claude\plans\bro-ya-prob-anda-enumerated-dusk-of-d596eb60-a234-48bd-94dc-42ab18802b1d.md`.
- **Por qué iba lento:** en Android, Flutter dibuja con Impeller, que rehace la pantalla entera en cada imagen sin
  guardar nada de la anterior, y el tótem pide 60 por segundo siempre (`_reloj.repeat()`). Así, 60 veces por segundo,
  la placa chica rehacía el fondo animado píxel por píxel (aunque el salón lo tapaba), las 3 sombras borrosas de cada
  letra de neón y el salón entero. "Fondo quieto" casi no ayudaba: el reloj seguía pidiendo imágenes.
- **Lo hecho (sin publicar, todo detrás de `EscenaTotem.enLaTele`, que prende solo `PantallaTele`; apagado no cambia
  nada):**
  - **`FotoDeLoQuieto`** (`lib/features/common/widgets/foto_de_lo_quieto.dart`): dibuja a su hijo una vez en una
    imagen y pinta la imagen. Se da cuenta sola de cuándo cambió lo de adentro (su `markNeedsPaint`); si cambia en
    cada imagen va en vivo y saca la foto cuando se queda quieto; `huella` guarda una foto por valor (la letra floja
    de Neón); la foto se saca **alineada a los píxeles de la pantalla** (sin eso los bordes salían apenas corridos).
    Adentro no puede haber un `RepaintBoundary` (no le avisaría). `NombreQueSePrende` (el nombre letra por letra,
    tomado de su foto) y `BarridoDeCirculo` (el círculo de la mesa descubierto como un barrido).
  - En la escena: la espera, la llegada (en grande se achica la foto), el resumen en la pista y las capas del fondo
    tapado, en foto (`DatosEscena.enFoto`, `textoConBrillo`); el salón (`VistaPlano(enFoto:)`) en foto con todo su
    detalle, **el camino en su capa** (en vivo mientras se dibuja, en foto al terminar) y el pulso de las mesas en
    vivo; Cristal sin `BackdropFilter`.
  - **El fondo, a la mitad** (`FondoTotem`/`FondoPropio(escala:)`, `pintarEnChico`; `DibujoEnChico` para los efectos
    de Tu fondo) y **quieto mientras el salón lo tapa** (`tapado`: el salón claro deja ver un 3 %, por eso no se saca).
  - **La tele se ajusta sola, callada** (`AjusteDeLaTele`, `calidad_de_la_tele.dart`): si no llega al 83 % de los Hz
    en dos medidas seguidas, baja solo el fondo (mitad → tercio → quieto) y lo recuerda (`calidad_tele_v1`).
  - **"Cómo anda" solo en la app de prueba** (`PantallaTele(conDiagnostico:)`): imágenes por segundo de verdad (por
    `vsyncStart`), ms de dibujo y de armado, resolución, Hz, escalón del fondo, 32/64 bits y Vulkan u OpenGL
    (`AparatoDeLaTele`, canal `junior_eventos/aparato`). En la app de verdad, ningún número
    (`test/pantalla_tele_test.dart`).
  - **Los salones de verdad**: `tool/salones_de_verdad.py` los saca de una copia (sin nombres ni ids) a
    `build/salones_prueba/salones.json` (9 salones, de 41 a 151 mesas). Gradle los mete **solo** en el APK de prueba
    (`salonesDePrueba`, `test/android_listo_test.dart`); `tool/tele_prueba.dart` arranca con el más grande y deja
    elegir otro.
- **Probado:** `tool/tele_salones_de_verdad_test.dart` dibuja, con los 9 salones de verdad, la espera, el nombre en
  grande y acomodado (con el camino), hoy y en la tele, y los compara píxel por píxel: **0,02 de 255 en promedio y
  0 % de píxeles distintos a la vista** (en grande, 0,2: el fondo a la mitad apenas detrás del salón apagado). Las
  capturas lado a lado en `build/capturas_tele/`. `test/foto_de_lo_quieto_test.dart` y
  `test/escena_en_la_tele_test.dart` (13 s de espera con el salón: ninguna foto después de las primeras; la llegada
  entera, menos de 40 fotos en 750 imágenes). 799 pruebas del tótem, la tele y el plano, iguales.
- **Segunda tanda (25-nov, la bienvenida y la flecha a 60):** el usuario quiere 60 por segundo en la bienvenida y
  la flecha, y vio las capturas lado a lado de cada momento antes de instalar.
  - **El resplandor del camino, en chico** (`PintorResaltado(resplandorEnChico:)`, `pintarEnChico` ahora en
    `lib/features/common/widgets/pintar_en_chico.dart`); la línea y la flecha, nítidas. El camino se mide una vez por
    ruta (`_medidos`).
  - **El salón en dos partes** (`PanelPlano(parte: ParteDelPanel.quieto | loQueSeMueve)`, `VistaPlano(capas:)`):
    lo quieto (con la mesa encendida) siempre en foto; el camino, la flecha, el pulso y el borde que late, encima.
    El resplandor del borde va afuera del salón (`_AfueraDe`). Lo que se mueve va adentro del mismo `Opacity` que el
    salón: si no, mientras vuelve el salón el borde se veía más pálido (lo mostró la comparación).
  - **`MismoHijo`** (`foto_de_lo_quieto.dart`) y la `clave` de `DatosEscena.enFoto`: lo que va en foto no se vuelve a
    armar mientras no cambie lo que se ve. **Sin esto la foto del salón no servía nunca**: el tótem arma la escena en
    cada imagen y el `LayoutBuilder` del plano avisaba un cambio en cada una. Se vio en el emulador (la espera bajó
    a 30); las pruebas solo contaban fotos sacadas: ahora cuentan también `dibujosEnVivo`.
  - **El nombre letra por letra, igual que en vivo:** en vivo, las letras que no se prendieron ya muestran su brillo
    (dorado en Neón) y después se prenden en blanco (`copyWith(shadows: null)` deja el brillo). En la tele: la foto
    del brillo entero siempre y las letras sin brillo de a una (`letraPorLetra(enLaTele:)`).
  - **El ensayo** (`TotemLocal(ensayar:)`): al abrir, dos bienvenidas quietas con todas las letras se dibujan 1,5 s
    tapadas de negro.
  - **La tele se ajusta sola, con cuidado** (`AjusteDeLaTele`): baja el fondo solo si es la placa (dibujo > 85 % del
    tiempo de una imagen), con tres medidas malas seguidas, 15 s después de abrir, y **vuelve atrás si bajar no
    ayudó** (en el emulador lo dejaba quieto de balde).
  - **"Lo peor del último minuto"** en "Cómo anda" (solo la app de prueba) y cada medida al registro
    (`adb logcat -s flutter`).
- **Medido en el emulador `Recepcion_Tablet` con `-gpu swiftshader_indirect`** (dibuja con el procesador: se parece a
  una placa chica), pantalla 1920×1080 a 320 dpi, salón de 151 mesas: **espera 19-21 → 40-44 por segundo**;
  **bienvenida 12-18 → lo peor 24-29 al aparecer el nombre, después 35-44**. Con el fondo quieto la bienvenida da casi
  igual: ahí ya no frena ningún cálculo, frena pintar la pantalla con el procesador (lo que una placa hace rápido).
  Con `-gpu host` todo da 60 y no sirve para comparar. **Para la próxima:** `--dart-define=fluida=no` arma la prueba
  como antes, `--dart-define=fondo=quieto` arranca con el fondo quieto, y la bienvenida se dispara desde la página
  del celular (`adb forward tcp:8787 tcp:8787` y el navegador en `http://127.0.0.1:8787/`).
- **Las capturas de la bienvenida**, momento por momento (`tool/tele_salones_de_verdad_test.dart`, valores fijos
  `EscenaTotem(entradaFija:, caminoFijo:)` solo para las muestras): como mucho 0,11 % de puntos distintos.
- **No probado:** la Quint de verdad. Falta que el usuario instale el APK nuevo y mande la foto de "Cómo anda" (con
  "lo peor del último minuto" después de hacer entrar a alguien).

**Estado (24-nov):** etapas 1, 2 y 3 programadas y probadas en el sandbox (commit `9029fa3`, rama feature). **Sin publicar.**
Al usuario se le dio `installer\dist\prueba\Junior Eventos prueba tele.apk` (la app de prueba, 32 y 64 bits, firmada
con CN=Junior Eventos). El 25-nov la prueba con dos teles y una red sin internet (la hace él).

**Lo que hay:**
- `lib/features/tele/`: `ModoTele` (Tele 1 o 2, recordado en el equipo, `modo_tele_v1`), `PantallaTele` (el tótem a
  pantalla completa + el menú del control), `ClienteDeLaTele` y `TeleSegunda` (la Tele 2 enganchada a la 1),
  `RedDeLaTele` y `PaginaDelCelularEnAndroid` (multicast y la página del celular sacada del APK), `Fluidez`
  (imágenes por segundo en el menú), `elegirModoTele` (la tarjeta TÓTEM del Centro de Comando en Android, modo jefe).
- La central (`CentralPuerta`) con `esTele`: "Tu tele" de cada celular (`?t=`), el mensaje `teles`, la Tele 2 por
  `/tele?evento=&n=2` (filas que cambiaron + bienvenidas + segundos + quién la maneja) y los segundos por tele.
- `MarcasDeLaNoche` anota la bienvenida de cada ingreso (`BienvenidaDeLaNoche`: tele, saludar, cuándo) antes de
  marcar; **`seSaludaEnLaTele`** decide (solo lo que entró por la central, de su tele o "las dos", a tiempo).
- `IngresosTotem.seSaluda` / `TotemLocal(seSaluda:, fondoQuieto:)`: sin filtro, todo igual que antes (Recepción).
- La Tele 2 copia con `InvitadosRepository.guardarDeOtraTele` (sin encolar) y, al pasar a principal,
  `subirLoDeOtraTele` encola lo copiado.
- Android: `LEANBACK_LAUNCHER`, banner, `CHANGE_WIFI_MULTICAST_STATE`, canal `junior_eventos/red`. Gradle mete
  `build/puesto` en el APK (`copiarPaginaDelCelular`) y **frena si está a medio armar** (sin
  `assets/FontManifest.json`). `JUNIOR_APK_DE_PRUEBA=1` arma la app de prueba con otro id (`.prueba`).

**Probado:** 1071 pruebas de lo tocado (61 archivos) y las nuevas (`tele_central_test`, `tele_saludo_test`,
`modo_tele_test`, `cliente_de_la_tele_test` —con la búsqueda por UDP en esta PC—, `modo_tele_cerrado_test`,
`pantalla_tele_test`). La ventana `tool/tele_prueba.dart` con el mouse (las dos teles saludando a la vez, cada una lo
suyo, "ya ingresó · Juli", el QR de cada tele, la flecha desde el Ingreso, un ingreso que llegó tarde sin saludo) y
el APK en el emulador `Recepcion_Tablet` (elegir y el menú con las flechas y el OK, Atrás, la página del celular
servida desde el APK, el saludo con la mesa). La base de esta PC: IGUAL antes y después.

**Encontrado al probar:** un `flutter build web` hecho encima de otro dejó `build\puesto` sin
`assets/FontManifest.json` (los íconos como cuadraditos, lo de la 6.6.0). Se arregla borrando `build\puesto` y
`.dart_tool\flutter_build`. Ahora Gradle no arma el APK así, y la tele no da por buena una página sin esos archivos.

**Lo que falta, en orden:**
1. Lo que diga la prueba del usuario (32 o 64 bits, los cuadros por segundo, si la Tele 2 encuentra sola a la 1).
2. El instalador: publicar también el APK de 32 bits (comprobado con `apksigner`, que necesita `JAVA_HOME` =
   `C:\Program Files\Android\Android Studio\jbr`) y que `app_update_checker.dart` ofrezca el del aparato.
3. "Lista para trabajar sin internet" que mire también la apariencia del tótem guardada.
4. Las roturas a propósito (`tool/roturas_tele.txt`), el simulacro sobre una copia de la base y una revisión
   independiente.
5. La app de verdad en la tele (la que entra con la cuenta del jefe), recién después de la prueba.
6. CLAUDE.md y publicar, solo cuando él lo diga.

**No probado:** una Google TV de verdad, el router sin internet, el iPhone, dos aparatos de verdad buscándose por UDP
(en Android hace falta el multicast), y "Pasar a principal" de punta a punta.
