# La tele es el tótem: Google TV sin PC y sin internet

## Context

El usuario quiere ahorrar las PC del salón: que el tótem salga en las smart TV (Google TV de 50", dos por evento),
conectadas al wifi del router propio, **sin internet**, y que la recepcionista, con su celular, marque el ingreso y la
tele dé la bienvenida con el recorrido, como hoy. Preguntó cómo hacer con los iPhone.

Hoy una notebook hace dos cosas: dibuja el tótem (ventana por HDMI) y es la **central de la puerta** (los celulares
escanean un QR y marcan por el wifi). La idea es que **la tele haga lo que hoy hace la notebook**.

### Por qué no "proyectar" desde el celular (Cast / duplicar pantalla)

- **Sin internet no anda:** para recibir lo que manda una app, la Google TV baja de internet la pantalla que lo
  recibe. En el salón no hay.
- **Duplicar la pantalla copia el celular:** la tele mostraría la lista de recepción, no el tótem. No se pueden hacer
  las dos cosas a la vez, y si el celular se bloquea o se aleja, la tele se corta.
- **El iPhone no proyecta a una Google TV** (AirPlay solo en algunas teles), y haría falta una app de iPhone (una Mac
  y una cuenta de Apple de USD 99 por año).

### Lo que se propone

**La app Junior Eventos se instala en cada tele** (Google TV es Android: se instala el mismo APK de la tablet). La
tele dibuja el tótem sola, en calidad completa, y **es la central**: los celulares solo le mandan "llegó PÉREZ". Para
la recepcionista se siente igual a proyectar: elige su tele y cada ingreso saluda en esa tele.

**Los iPhone no necesitan nada:** escanean el QR de la tele y la recepción se abre en Safari, servida por la tele,
sin internet. Es lo mismo que hacen hoy con la notebook. Los Android, igual.

### Sus preguntas (24-nov)

- **¿Se instala en la tele y se le pone internet antes de salir?** Sí: una vez la app; antes de cada evento, internet
  en la oficina para que baje lo último (la lista, las mesas, el sorteo). Lo que cambie después no lo sabe hasta que
  vuelva a tener internet.
- **¿Cómo "proyecto" con el iPhone y el Android por la red local?** No se proyecta la imagen: la tele ya tiene el
  tótem abierto. El celular escanea el QR que muestra la tele, se abre la recepción en Safari o Chrome por el wifi del
  router, y cada INGRESAR le manda a la tele "llegó PÉREZ". Anda sin internet: es la misma página que hoy usan los
  celulares con la notebook. No hay que instalar nada en el celular.
- **Tele 1 con la recepcionista 1 y Tele 2 con la 2, ¿se pisan?** No. Cada celular queda atado a su tele: lo que marca
  la recepcionista 1 saluda solo en la Tele 1, y lo de la 2, solo en la Tele 2. La lista es una sola: si las dos buscan
  a la misma persona, la segunda ve "ya ingresó a las 22:41 · Juli" y no se saluda dos veces.

- **Su resumen, confirmado:** instala en la tele, entra una vez con la cuenta del jefe (la escribe él), elige
  "Usar esta tele como tótem" (Tele 1 o Tele 2) y la deja; desde ahí abre sola en el tótem. Cada recepcionista engancha
  su celular a su tele con el QR. Las dos teles van en el mismo router: la Tele 2 se engancha sola a la 1.

- **Dos teles, dos recepcionistas, cada una con el control de su tele:** sí, y con una sola lista por detrás (la
  lleva la Tele 1; la 2 se engancha sola por el wifi y copia). Si cada tele tuviera su lista, sin internet una puerta
  no sabría quién entró por la otra: se ingresaría dos veces a alguien y el tope de sillas por mesa se podría pasar.
  No hacen falta dos cuentas: las dos teles entran con la del jefe.

### Cómo sería la noche (con dos teles)

1. **En la oficina, con internet:** se prenden las dos teles, se abre la app y queda "Lista para trabajar sin
   internet" para la fiesta del sábado (la lista, las mesas, el plano, la foto). Una queda como **Tele 1
   (principal)** y la otra como **Tele 2**. Esto se elige una vez.
2. **En el salón:** se enchufa el router y se prenden las teles. La app abre sola en el tótem de la fiesta de hoy.
   La Tele 2 encuentra sola a la Tele 1.
3. **Juli** aprieta OK en el control de la Tele 1: sale un QR grande. Lo escanea con su iPhone y se abre la
   recepción, con "Tu tele: Tele 1". **Caro** hace lo mismo en la Tele 2 y le queda "Tu tele: Tele 2".
4. Llega PÉREZ: Juli lo busca y toca INGRESAR. **La Tele 1** lo saluda con su mesa y el camino. La Tele 2 no se
   entera de la bienvenida, pero en las dos listas PÉREZ ya figura adentro (hay una sola lista).
5. Si Caro busca a PÉREZ, le sale "ya ingresó a las 22:41 · Juli".
6. Si un celular pierde el wifi, guarda lo que marca y lo manda al volver (eso ya existe); si llega más de un minuto
   tarde, la tele no lo saluda atrasado.
7. **Al volver a la oficina con internet**, la Tele 1 sube los ingresos a la nube.

Lo único a cuidar: **la app tiene que quedar abierta en la tele** (si alguien aprieta "Inicio" en el control, se
vuelve a abrir). Y conviene que el router le dé siempre la misma dirección a la Tele 1.

## Lo que ya existe y se reusa (repaso del código, 24-nov)

- **La central** (`lib/features/recepcion/central/central_puerta.dart`, `central_provider.dart`): `dart:io` puro, sin
  nada de Windows; en Android arranca. Lo que falta: **la página del celular no está en el APK**
  (`paginaDelCelularProvider` la busca al lado del `.exe`), nada mantiene la tele despierta y solo se prende desde el
  cartel de Recepción.
- **El tótem a pantalla completa que ya anda en Android y sin internet:** `TotemLocal`
  (`lib/features/totem/widgets/totem_local.dart`), que lee la base del equipo (`puertaDelEventoProvider`,
  `planoDelEventoProvider`, `invitadosStreamProvider`, `totemConfigDeLaNocheProvider`). La foto se guarda en el
  equipo (`FotoGuardada`), la apariencia en las preferencias (`totem_config_cache.dart`), las letras vienen en la app
  y los shaders tienen respaldo si no cargan.
- **Lo que el celular ya hace:** `ClienteCentral` y `PantallaPuesto` (ingresar, deshacer, sillas, segundos del tótem,
  chat, la cola sin wifi). `MarcasDeLaNoche` anota quién marcó a quién.
- **Encontrarse por la red del salón:** `lib/features/barra/central/buscar_central.dart` (`BuscaCentral` pregunta por
  UDP, `RespondeBusqueda` contesta). Para la Tele 2 buscando a la Tele 1.
- **Escribir lo de otro equipo sin encolarlo:** el patrón de `BarraLocal.guardarDeOtroEquipo`.
- **Mantener la pantalla prendida:** `PantallaDespierta` (canal `junior_eventos/pantalla` en `MainActivity.kt`).
- **La fiesta de hoy:** `primerDiaDeLasFiestasQueVienen` y `enElOrdenDeLasFiestas` (`common/utils/dia_de_la_fiesta.dart`).
- **Lista para trabajar sin internet:** `PuestaAlDiaPuerta`, `EstadoSinInternet` (`recepcion/.../lista_sin_internet.dart`).
- La decisión de dos tótems, del 24-sep (`docs/pendientes/totems-vinculados.md`): **cada tele saluda a los de su
  puerta**, con la opción de las dos. Se retoma por la central, no por la nube.

Sin SQL ni migración: lo de "a qué tele va" vive en la memoria de la central, como el chat.

## Las etapas (cada una cierra sola)

### Etapa 0 — Maqueta y OK

Maqueta (HTML, `preview_start` con `maquetas`) de: la tele esperando, el tótem, el menú del control (OK), el QR para
sumar celulares, la Tele 2 buscando a la 1, y en el celular "Tu tele: Tele 1 · Tele 2 · Las dos". Se la muestro y
espero su OK antes de programar.

### Etapa 1 — La app en la tele, con el tótem (una tele, sin celulares)

- **Que la tele la muestre entre sus apps:** `AndroidManifest.xml` con `LEANBACK_LAUNCHER` (antes que `LAUNCHER`),
  `android:banner` (320×180, el logo) y `touchscreen`/`leanback` con `required="false"` (la tablet sigue igual).
- **El APK de 32 bits:** muchas Google TV solo aceptan 32 bits. `installer\build_installer.ps1` ya arma
  `app-armeabi-v7a-release.apk`: publicarlo también, comprobado con `apksigner` (CN=Junior Eventos), y que
  `app_update_checker.dart` (`apkAssetUrl`) ofrezca el que corresponde al aparato. Ajustar `test/android_listo_test.dart`.
- **El modo tele** (`lib/features/tele/`, nuevo): se elige una vez en modo jefe ("Usar esta tele como tótem",
  principal o segunda) y queda en el equipo (preferencia `modo_tele_v1`). Al abrir la app va derecho a la pantalla de
  la tele, sin PIN, y **desde ahí no hay camino al panel ni a cobrar**: salir pide el PIN del jefe.
  `test/modo_tele_cerrado_test.dart` lo vigila, como `modo_barra_cerrado_test`.
- **La pantalla de la tele:** `TotemLocal` a pantalla completa, sin los botones de `TotemLauncherScreen`, con
  `PantallaDespierta`, pantalla inmersiva y el botón Atrás frenado. OK del control abre un menú chico, manejable con
  las flechas: la fiesta, "Lista para trabajar sin internet", el QR (etapa 2), girar y salir.
- **La fiesta sola:** la de hoy (`primerDiaDeLasFiestasQueVienen`); si hay dos, se elige con el control.
- **"Lista para trabajar sin internet" también mira la apariencia del tótem** (hoy `EstadoSinInternet` no revisa
  `totem_config` guardada).
- **Ventana de prueba** `tool/tele_prueba.dart` (sin la base: `LocalDatabase.cerrarParaLaPrueba()`, preferencias en
  memoria, una fiesta inventada), que corre en Windows y como APK.

### Etapa 2 — La tele es la central de los celulares

- **La página del celular adentro del APK:** el instalador arma `build\puesto` antes del APK y Gradle la mete en los
  archivos propios de Android (no en los de Flutter, así Windows no la lleva dos veces). Al abrir, la tele la copia a
  su carpeta (`MainActivity.kt`) y `paginaDelCelularProvider` la busca ahí. `test/instalador_puesto_test.dart` lo exige.
- La central **se prende sola con el modo tele** (Tele 1) para la fiesta de la noche; el QR y el código salen grandes
  en el menú de la tele. El código de 4 cifras sigue igual.
- **La tele no saluda un ingreso atrasado:** hoy `TotemLocal` saluda todo lo nuevo en la base y no respeta
  `saludar: false` (lo que llega más de un minuto tarde). `IngresosTotem` (`bienvenidas_totem.dart`) pasa a preguntarle
  a `MarcasDeLaNoche` si ese ingreso se saluda.
- Prueba: la ventana de prueba con la central de verdad y pestañas del navegador haciendo de celulares.

### Etapa 3 — La segunda tele y "Tu tele"

- **La Tele 2 encuentra a la Tele 1** con `BuscaCentral`/`RespondeBusqueda` (otro puerto UDP, p. ej. 8778). La Tele 1
  necesita el permiso de multicast de Android para oír la pregunta (`MainActivity.kt`, `CHANGE_WIFI_MULTICAST_STATE`).
  Si el router no deja, la dirección se escribe con el control.
- **La Tele 2 copia en su base los ingresos que le manda la Tele 1, sin encolarlos** (un `guardarDeOtroEquipo` para
  `invitados`, como la barra): así su tótem es el mismo `TotemLocal` y, si la Tele 1 se rompe, la 2 tiene la lista.
- **Cada ingreso dice a qué tele va:** el celular elige "Tu tele" (viene la del QR que escaneó; también "Las dos"),
  el pedido lo lleva, `MarcasDeLaNoche` lo anota y cada tele saluda solo lo suyo. La lista es una sola: todas ven
  quién entró. Una función pura con su test decide a qué tele va cada bienvenida.
- El QR de la Tele 2 conecta el celular a la Tele 1 con "Tele 2" ya elegida.
- **Cada recepcionista controla su tele** (pedido del usuario, 24-nov): lo que marca saluda solo en su tele, y lo que
  cambia del tótem desde el celular (los segundos de la llegada, `TiemposAMano`) va solo a su tele. Hoy los segundos
  son uno por fiesta: pasan a ser uno por tele, en la memoria de la central. La tele muestra quién la maneja
  ("La maneja: Juli", con el nombre que el celular ya pone al conectarse). La lista compartida no se ve: solo evita
  que alguien se ingrese dos veces.
- **Si la Tele 1 se apaga**, la Tele 2 tiene la copia: con el PIN del jefe pasa a principal y los celulares escanean
  su QR.

### Etapa 4 — Actualizar las teles (después)

La tele no tiene navegador: el aviso de versión nueva de la tablet no le sirve. Para empezar, se actualiza desde la
PC de la oficina por la red (`adb`), con su OK. Más adelante, si lo pide, que la app baje e instale su versión.

## Lo que no cambia

La notebook como central y el tótem en la PC siguen andando igual. **Una sola central por noche:** o la notebook o
la Tele 1. La venta, la barra y la oficina no se tocan.

## Las teles (24-nov)

- **Para probar:** una Quint Google TV de 50" (marca argentina), en la pieza del usuario.
- **Las del salón:** dos Google TV de 50" que compró el jefe el 24-nov (marca "CMB o algo así"), en la oficina.
- Son teles de gama económica: lo común en esas es un procesador chico, unos 2 GB de memoria y **apps de 32 bits**.
  Por eso van los dos APK y el fondo quieto como respaldo. Lo exacto se lee de cada tele con `adb` (solo lectura).

## Riesgos que se miran en la tele de verdad

- **Si la tele es de 32 bits** (la marca y el modelo están en Ajustes → Sistema → Acerca de).
- **Si el fondo animado anda suave** en el procesador de la tele; si no, en el menú se elige el fondo quieto.
- **"Inicio" en el control** saca la app: el tótem desaparece y la central puede pausarse; los celulares guardan lo
  marcado y lo mandan al volver. Si molesta, se agrega un servicio que la mantenga viva.
- La tele lleva la base entera del programa, como la tablet de la barra.

## Las pruebas

El usuario tiene **una** Google TV de 50" (en su pieza) para probar, no dos. Todo lo que se pueda se prueba acá, en
el sandbox (regla del 6-nov); a él le queda solo lo que necesita su tele, su celular o el router.

### A. En el sandbox, en cada etapa (las hago yo)

1. **Tests de cada pieza nueva, con su test de "no se puede":**
   - el modo tele queda recordado en el equipo y **desde la tele no hay camino al panel ni a cobrar**
     (`test/modo_tele_cerrado_test.dart`);
   - la fiesta de la tele (la de hoy, la de anoche hasta el mediodía, dos la misma noche);
   - la página del celular está en el APK y se encuentra en Android (`test/instalador_puesto_test.dart`,
     `test/android_listo_test.dart`: los dos APK, 32 y 64 bits, firmados con CN=Junior Eventos);
   - la tele no saluda un ingreso atrasado (más de un minuto) ni dos veces el mismo;
   - **a qué tele va cada bienvenida** (función pura): lo de Juli solo en la Tele 1, lo de Caro solo en la 2, "Las
     dos" en las dos, sin repetir;
   - los segundos de la llegada, uno por tele;
   - la central con dos teles y dos celulares en memoria (`central_en_memoria`, `celular_de_prueba`): Juli y Caro
     marcan a la misma persona a la vez y queda un solo ingreso, con "ya ingresó";
   - la Tele 2 copia en su base **sin encolar** nada para subir, y no pisa lo que tenga en la cola;
   - la Tele 2 encuentra a la 1 por UDP (como `test/central_barra_test.dart`:328), y si no, con la dirección a mano;
   - la Tele 1 se apaga: la 2 pasa a principal con el PIN del jefe y los celulares vuelven a enganchar.
2. **Roturas a propósito** (`bash tool/romper_una_regla.sh`, lista nueva `tool/roturas_tele.txt`): sacar cada freno
   y comprobar que su test falla.
3. **La ventana de prueba** `tool/tele_prueba.dart`, sin la base de la PC (`LocalDatabase.cerrarParaLaPrueba()`,
   preferencias en memoria, una fiesta inventada con plano y sorteo): **la Tele 1 y la Tele 2 lado a lado en la
   misma ventana**, con la central de verdad, y los celulares como pestañas del navegador de la app con medida de
   iPhone y de Android. Recorrido con el mouse: Juli y Caro marcan, cada tele saluda lo suyo, se corta el wifi de
   un celular y vuelve, se apaga la Tele 1. `test/arneses_sin_base_test.dart` la vigila.
   `python -I tool/huella_de_la_base.py` antes y después (`--comparar`: IGUAL).
4. **Emulador de Google TV en esta PC** (imagen de Android TV, `-gpu host`; bajar la imagen pide su OK): el APK de
   la ventana de prueba, manejado solo con las flechas y el OK del control; la página del celular servida por el
   emulador y abierta en el navegador (`adb forward tcp:8787`). Dos emuladores como Tele 1 y Tele 2 con la dirección
   a mano (entre emuladores el UDP no pasa).
5. **Simulacro sobre una copia de la base** (`tool/copiar_base_solo_lectura.py`; los nombres a `build/`): una
   fiesta de verdad, sin red, en modo tele: que con lo bajado esté todo (lista, mesas, plano, apariencia y foto)
   y que la tele salude a cada familia con su mesa, igual que el tótem de la PC.
6. Una revisión independiente del código y **capturas de cada pantalla** (tele, menú del control, QR, celular),
   mandadas antes de pedirle nada.

### B. Con su tele, en su pieza (lo que necesita el aparato)

Con una sola tele se prueba todo: **la Tele 2 la hace su celular Android** (o una tablet de la barra), que dibuja
el mismo tótem. **Los ingresos se prueban con el APK de prueba** (la fiesta inventada de `tool/tele_prueba.dart`,
sin la nube): la app de verdad escribiría ingresos reales en la nube. Paso a paso, con él:

1. **Ver qué tele es:** modelo en Ajustes → Sistema → Acerca de; con el modo de desarrollador y la depuración por
   red prendidos (lo hace él), desde esta PC se lee si es de 32 o 64 bits (`adb shell getprop
   ro.product.cpu.abilist`, solo lectura).
2. **Instalar** por `adb` desde esta PC (con su OK en el momento; la tele pide aceptar) o con un pendrive: primero
   el APK de prueba.
3. **Sin internet, con el APK de prueba:** desenchufar la fibra del router de la casa (como el 8-nov). Apagar y
   prender la tele: abre sola en el tótem. Mirar que el fondo animado ande suave. Escanear el QR con el iPhone y con
   el Android; marcar; la tele saluda con mesa y camino.
4. **Las dos puertas:** el Android con el APK de prueba en "Tele 2" se engancha solo a la tele; el iPhone con "Tu
   tele: Tele 1" y una pestaña de la PC (o otro celular) con "Tele 2". Cada uno saluda en su pantalla, y la segunda
   que busca a la misma persona ve "ya ingresó".
5. **Lo que falla a propósito:** cortar el wifi de un celular y marcar (al volver, se manda y no saluda tarde);
   apretar Inicio en el control y volver a abrir; apagar la tele (la "Tele 2" pasa a principal).
6. **Con internet, la app de verdad:** aparece entre las apps de la tele; entra con la cuenta del jefe (la escribe
   él), elige "Tele 1"; queda "Lista para trabajar sin internet" para la próxima fiesta y abre en su tótem. **Sin
   marcar a nadie.**

### C. En la oficina, con las dos teles del jefe (la prueba final)

Lo mismo de B, pero con **las dos teles de verdad** como Tele 1 y Tele 2 y, si está, el router del salón sin
internet. Primero con el APK de prueba; al final la app de verdad en las dos, "Lista para trabajar sin internet" para
la próxima fiesta, sin marcar a nadie. Sin código nuevo: si algo falla acá, vuelve a A.

## Al cerrar cada etapa

CONTEXTO "Para retomar", `CLAUDE.md`, memoria y commit en la rama feature. Publicar, solo cuando él lo diga.
