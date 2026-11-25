# La tele es el tótem (24-nov-2026)

El plan: `docs/PLAN_TELE_COMO_TOTEM_2026-11-24.md`. El usuario pidió saltear la maqueta: programar, probar en el
sandbox y darle la app de prueba para sus pruebas internas, sin publicar.

## Para retomar en otro chat

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
