# La tele es el tótem (24-nov-2026)

El plan: `docs/PLAN_TELE_COMO_TOTEM_2026-11-24.md`. El usuario pidió saltear la maqueta: programar, probar en el
sandbox y darle la app de prueba para sus pruebas internas, sin publicar.

## Para retomar en otro chat

**Estado:** etapas 1, 2 y 3 programadas y probadas en el sandbox (commit `9029fa3`, rama feature). **Sin publicar.**
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
