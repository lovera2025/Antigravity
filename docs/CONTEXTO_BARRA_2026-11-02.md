# La barra y la impresora (en curso)

2 a 4-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. El plan entero, aprobado por el usuario: `docs/PLAN_BARRA_2026-11-03.md`.
El orden de todo: `docs/HOJA_DE_RUTA_2026-11-02.md`.

## Para retomar en otro chat

> **Al 7-nov (noche): las etapas 1 a 8 y la central de la barra están cerradas en la rama, sin publicar.** La 7 se cerró con el
> recorrido con el mouse y la foto de la lista de precios impresa en la TP-POS58 ("un lujo"). La 8 (el jefe en el iPhone, en la web):
> BARRA lee y escribe directo en la nube por `BarraNube` (abajo, "Etapa 8"). **La central de la barra** (abajo, "La central de la
> barra"): la notebook de la barra la prende desde BARRA → CAJAS, las tablets la encuentran solas por el wifi del salón, y lo que vende
> una caja lo ven las demás y la notebook al momento, **con o sin internet**. Cada tablet y la notebook dicen **"Todo subido"** o cuánto
> falta subir (pedido del usuario, "para quedarnos tranquilos"), y Recepción dice lo mismo con las mismas palabras. Probada entera en el
> sandbox: 3.900 y pico de tests y el recorrido con el mouse de `tool/central_barra_prueba.dart` (dos tablets y la notebook en una
> ventana). **Sigue la 9 (Android firmado)**: ahí se prueba con la tablet y el router de verdad lo que el sandbox no puede (que la
> tablet encuentre la notebook por el wifi real y el `ws://` desde Android). Después la 10 (de punta a punta), Entradas 4 a 6 y
> publicar la 6.4.0. Plan general: **19 de 26 partes, 73 %**.
>
> **Lo decidido el 7-nov:** la barra vende con **la app instalada en cada tablet**, no como las recepcionistas por QR (el navegador no
> imprime por Bluetooth y la barra no puede dejar de vender si se cae la red); **la central sigue en pie** (el stock general, en vivo
> también sin internet; solo comparte el stock y deja al jefe ver las cajas; cómo se conecta la tablet, QR o sola, se decide en su
> etapa). **La primera fiesta con barra es TÉCNICA PINAROLI, el viernes 4 de diciembre.**
>
> La 6.3.3 (la mora adelantada y el sync en reposo) se publicó e instaló el 7-nov, desde `release/6.3.x`. **Aparte de la barra, el
> 7-nov quedó programado sin publicar el arreglo de la fecha de un cobro** (`docs/CONTEXTO_v6.3.4_2026-11-07.md`). **Y se sumó al
> plan, sin programar, el arreglo del aviso entre PCs** (`docs/SPEC_pulso_por_el_socket_2026-11-07.md`): hoy la otra PC no se pone al
> día sola, solo al volver a la ventana, antes de cobrar o a los 5 minutos. Ninguno de los dos sale solo: **va todo junto en la 6.4.0**
> (decidido el 7-nov a la noche). El plan general pasó a 26 partes: 60 %.

**Estado al 4-nov (noche).** Las etapas 1 a 4 de la barra (la impresora, los datos, las cuentas y la cajera vendiendo con sus tres cobros y
los vales) **salieron dormidas dentro de la 6.3.0**, que se publicó por el plano (`docs/CONTEXTO_v6.3.0_2026-11-02.md`; después la 6.3.1,
`docs/CONTEXTO_v6.3.1_2026-11-04.md`). **Los SQL de la barra (v77) y de los permisos (v76) ya están corridos en la nube**: lo que le cambie
a sus tablas va en tablas nuevas, como siempre. Ninguna PC tiene un producto ni un precio cargado: todavía no hay pantalla del jefe.

**Después de publicar, en la rama y sin publicar:** VENDER con el stock de toda la fiesta, los dos diseños (Noche dorada y Mostrador) y
74 fotos de tragos y marcas adentro de la app (el detalle, abajo).

**Regla del usuario (4-nov): se sigue sin publicar hasta completar todas las etapas que quedan**, y se publica todo en una sola versión
**cuando esté, sin apuro de fecha** (6-nov: "cuando salga nomás, ahora hay más tiempo"), preguntándole. Commit y push a la rama
sí. Cada etapa empieza con su plan corto y su OK.

**6-nov: antes de esta etapa 5 quedaron hechas las sillas de la noche** (`docs/CONTEXTO_v6.4.0_2026-11-06.md`): la puerta anota cada
silla con el número del vale de la barra, normalizado como "caja-número" ("2-17"). "Silla extra" en el catálogo y en el cierre va en
las etapas de la barra (`docs/pendientes/sillas-barra-vs-puerta.md`).

**Lo que queda, con lo que ya tiene hecho por dentro** (casi todo lo que falta son pantallas):

| Etapa | Ya hecho | Falta |
|---|---|---|
| 5. Reimprimir y anular | **Hecha el 7-nov** (VENTAS de la cajera, el freno de la copia, IMPRIMIR LO QUE FALTA, el ticket con precios, ANULAR con motivo, la tabla `barra_vales`) | Lo del jefe (reimprimir cualquiera, anular desde la PC) va en la 7 |
| La central de la barra | **Cerrada el 7-nov** (abajo, "La central de la barra"): la notebook la prende desde CAJAS, las tablets la encuentran solas por UDP, lo de cada caja va a todas por la red del salón sin internet, "Todo subido" en VENDER, en la notebook y en Recepción; tests y el recorrido con el mouse de `tool/central_barra_prueba.dart` | Con aparatos de verdad, en la 9 y la 10: que la tablet la encuentre por el wifi del TP-Link y el `ws://` desde el APK |
| El aviso de papel | Nada | Un botón PAPEL en `tool/impresora_prueba.dart` (`DLE EOT 4`) para ver si la TP-POS58 contesta |
| 6. Cerrar la caja | **Hecha el 7-nov** (contar a ciegas, el cierre como el papel con el historial, la térmica, el PDF de 58 mm y la nota), con el papel impreso y mirado en una foto | Nada |
| 7. El jefe en la PC | **Cerrada el 7-nov** (abajo): el recargo por fiesta (`barra_recargos`), la tarjeta BARRA, la fiesta primero, CATÁLOGO, PRECIOS con la lista en 58 mm, CAJAS con anular y reimprimir, la impresora de la PC; 26 pruebas de pantalla, las muestras, el recorrido con el mouse y la foto de la lista impresa | Nada. Subir una foto propia de un producto queda para después: necesita el depósito `barra` de Storage y su SQL |
| 8. El jefe en el iPhone | **Cerrada el 7-nov** (abajo, "Etapa 8"): la web lee y escribe por `BarraNube` (también las fiestas), CAJAS se relee cada 30 s y al deslizar, sin impresora; `tool/barra_web_prueba.dart` y su test; recorrida en el navegador a 375 px | Nada. La web se publica con todo en la 6.4.0 |
| 9. Android firmado | La ventana de prueba de la impresora compila y anduvo en su celular | La app entera en Android y la clave de firma |
| 10. De punta a punta | Nada | Con modo avión, sin internet |
| Entradas 4 a 6 | Las etapas 1 a 3, publicadas apagadas | La entrega según los permisos, "pagó: ya podés entregar", anular solo el jefe (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`) |
| Publicar | Los SQL de la barra y los permisos, corridos | **Cuatro SQL sin correr antes de instalar:** `20261105100000_totem_config_llegada.sql`, `20261105120000_sillas_puerta.sql`, `20261107100000_barra_vales.sql` y `20261107140000_barra_recargos.sql`. Foto de la mora antes, versión, release, web, APK firmado, foto después |

**Lo que le toca al usuario:** comprar la tablet de la barra; hasta la próxima versión, nadie con Entradas y nadie sin Cobros. (Las tres
PCs tienen la 6.3.3 desde el 7-nov.)

**La impresora (6-nov):** las pruebas las hace Claude en el sandbox, pero el papel impreso de verdad necesita la TP-POS58 del usuario.
**Cuando haga falta imprimir, avisarle** ("después me avisás si necesitás usar la impresora y vemos lo impreso"). El vale de la silla y
los papeles de la etapa 5 ya salieron y se miraron en una foto (7-nov).

> Frase para retomar: "Seguimos con la barra: leé 'Para retomar en otro chat' de docs/CONTEXTO_BARRA_2026-11-02.md y pasame el plan
> corto de la etapa 9 (Android firmado)."

### La central de la barra (7-nov, noche)

**Decidido por el usuario el 7-nov:** la central es **la notebook de la barra** (Windows, enchufada, como la de la puerta) y **las
tablets la encuentran solas**. Pedido de la misma noche: **ver lo que falta subir y, con internet, que diga que subió todo**, en la
tablet y en la central, "para quedarnos tranquilos"; y lo mismo para las recepcionistas, que ya lo tenían con otras palabras.

**La idea: la central es "la bajada de la nube", pero por la red del salón.** Lo que una tablet escribe (su caja, sus ventas, sus
anulaciones, sus vales) se lo manda a la notebook; la notebook lo guarda **como si lo hubiera bajado de la nube, sin encolarlo para
subir**, y se lo reparte a las demás tablets, que lo guardan igual. VENDER no cambió: ya leía las ventas de toda la fiesta de su base
(`StockDeLaBarra`) y se rehace cuando baja algo. Con internet, cada tablet sube lo suyo por su cola, como antes; la central no sube
nada de otro, así que no hay duplicados. **La central de la puerta no se tocó** (está publicada y ensayada): se copió su forma.

Todo en `lib/features/barra/central/`:
- **`filas_de_la_red.dart`**: las cuatro tablas que viajan (`tablasDeLaRed`: `barra_cajas`, `barra_ventas`, `barra_anulaciones`,
  `barra_vales`), la interfaz `BarraDeLaRed` y `PendientesDeLaBarra` ("2 ventas y 1 cambio"). **El catálogo, los precios y el recargo
  no viajan por la red del salón**: los pone el jefe antes de la fiesta y llegan por la nube. Cambiarlos esa noche sin internet no le
  llega a las tablets (a propósito).
- **`BarraLocal.guardarDeOtroEquipo`**: el único camino para escribir una fila que no es de este equipo. Dentro de una transacción:
  si el id está en `_sync_queue` no lo pisa (lo de este equipo manda), deja solo las columnas que la tabla tiene (`PRAGMA table_info`),
  compara con `cambiaLaFila` (gana el `updated_at` más nuevo; con la misma hora, solo si el contenido cambió) e inserta **sin encolar**.
  **`sync_engine.dart` no se tocó**: el plan decía sacar un `guardarFilasBajadas` del pull, y se eligió no tocar el sync que cobra.
  `filasDeLaFiesta`, `filaDeLaRed` y `pendientesDeLaBarra` (lo de la barra en la cola, por tabla).
- **`CentralBarra`** (`central_barra.dart`): el servidor, en la notebook. `HttpServer` desde el puerto **8797** (prueba diez, hasta el
  8806; la puerta usa 8787 a 8796), WebSocket en `/barra?evento=&equipo=&caja=`, una conexión por equipo (la nueva reemplaza a la
  vieja, cierre 4003; otra fiesta, 4001; faltan datos, 4002). Mensajes `{t:'filas', filas:{tabla:[…]}}` en las dos direcciones y
  `{t:'hola', ventas, otros}`, el latido de la tablet con lo que tiene sin subir. **Al conectarse o reconectarse, las dos puntas se
  mandan todo lo de la fiesta**: no hay cola de lo no mandado que pueda perderse, y lo repetido no cambia nada (`cambiaLaFila`).
- **La búsqueda** (`buscar_central.dart`): la tablet pregunta cada 3 s por UDP al puerto **8777** a toda la red (`255.255.255.255` y
  la `.255` de su red) `{t:'buscar', evento}`; la notebook contesta a esa tablet `{t:'central', evento, puerto}`. Pregunta la tablet y
  contesta la notebook porque Android recibe bien una respuesta directa y mal un anuncio a toda la red. **Si el router no deja pasar la
  pregunta**, en VENDER se toca la parte de la central y se escribe la dirección que muestra la notebook ("192.168.0.10:8797").
- **`ClienteDeLaCentral`** (en la tablet): busca, conecta, latido cada 5 s, reintenta, y lleva `porMandar` mientras no está conectada.
- **`BarraConLaRed`** (`barra_con_la_red.dart`): envuelve la barra del equipo; después de cada escritura (abrir caja, cambio, vender,
  anular, vale, cierre, nota) avisa por `AvisoALaRed`, que en la tablet manda al cliente y en la notebook reparte la central
  (`difundirDeEstaPc`: el jefe anula desde CAJAS y les llega a las tablets). `barraDeEsteEquipoProvider` la devuelve en la PC y en la
  tablet; en la web no hay red del salón (`redDeLaBarraHabilitadaProvider`, que los tests de pantalla ponen en `false`).
- **Los providers** (`central_barra_provider.dart`): `centralDeLaBarraProvider` (prender, reanudar, apagar; queda prendida mientras el
  programa está abierto y **se vuelve a prender sola** si la notebook se reinició esa noche: se recuerda 18 h) y
  `clienteDeLaBarraProvider` (lo arranca VENDER; en la notebook con la central prendida no arranca otro). Puertos y direcciones van
  por providers para que los tests escuchen solo en esta PC.

**Lo que se ve:**
- **En VENDER, una línea arriba de los filtros** (`LineaDeLaCaja`): "Todo subido" en verde; "2 ventas y 1 cambio subiendo"; "Sin
  internet · nada por subir"; "Sin internet · 1 venta por subir"; y al lado la central: "Buscando la central…", "Central conectada" o
  "Central · 3 cajas", o "Sin central desde las 23:36 · 1 por mandar" en ámbar. Si no entra en un renglón, la central baja al segundo
  (en el recorrido se cortaba con "…"; `test/linea_de_la_caja_test.dart`).
- **En la notebook, BARRA → CAJAS**, arriba, el panel de la central (`PanelCentralDeLaBarra`): PRENDER LA CENTRAL, la dirección para
  escribir a mano, cada caja conectada con "al día" o "1 venta por subir", y "Esta notebook: Todo subido". Debajo, las mismas tarjetas
  y el stock de siempre, que se rehacen con cada venta que llega. El renglón verde dice "Se pone al día con cada venta que llega por la
  red del salón, haya internet o no" cuando la central de esa fiesta está prendida.
- **En Recepción**, la línea de la PC suma "· Todo subido" o "· N ingresos subiendo" (`lista_sin_internet.dart`). El celular de la
  puerta ya decía "Sin conexión con la PC · N por mandar" y quedó igual.
- **El instalador** abre en el cortafuegos TCP 8797-8806 y UDP 8777 y las saca al desinstalar; **Android** pide `ACCESS_WIFI_STATE` y
  `ACCESS_NETWORK_STATE` y deja `ws://` a la red local (`usesCleartextTraffic`; la nube sigue por https).

**Las pruebas, en el sandbox:** `test/central_barra_test.dart` (servidor y tablets de verdad por la red de esta PC: la venta de una
llega a la otra, conectarse tarde trae todo, sin central se vende y al volver se manda **sin duplicar**, el latido, la búsqueda por
UDP), `central_barra_provider_test.dart`, `barra_con_la_red_test.dart` (lee `BarraLocal` y falla si aparece una escritura que no
avisa), `android_central_barra_test.dart`, `linea_de_la_caja_test.dart` y lo sumado en `barra_repositorios_test.dart` (lo recibido no
se encola, lo pendiente no se pisa), `instalador_puesto_test.dart`, `barra_home_test.dart`, `barra_jefe_pantalla_test.dart` y
`lista_sin_internet_test.dart`. Rotura a propósito: sin el reenvío completo al reconectar, falla "sin central … nada se duplica";
con la línea cortada con "…", falla la del ancho.

**El recorrido con el mouse (7-nov, noche)**, en `tool/central_barra_prueba.dart` (`flutter run -d windows -t
tool/central_barra_prueba.dart`): la tablet A (Marta, PIN 1111), la tablet B (Sofía, 2222) y la notebook con CAJAS, cada una con su
barra en memoria, unidas por la central de verdad en esta PC; la subida a la nube se simula a los 2 s y la barra de la notebook tiene
CORTAR INTERNET. Lo que dio:
1. Prendida la central, las dos tablets la encontraron solas ("Central · 2 cajas"); la notebook, "Esta notebook: Todo subido".
2. La A vendió 3 cervezas y en la B "Quedan" bajó al momento; la notebook vio la caja, la venta y el stock.
3. APAGAR: las tablets pasaron a "Sin central desde las 23:36"; la B vendió igual ("1 por mandar").
4. PRENDER otra vez (en otro puerto): las tablets la encontraron solas, la A vio la venta de la B y la notebook sumó $ 26.500; nada
   repetido.
5. CORTAR INTERNET: la A vendió un fernet; la A decía "Sin internet · 1 venta por subir", la B "Sin internet · nada por subir", y la
   notebook "Caja 1 · Marta · 1 venta por subir" con el total en $ 32.500: **sin internet, la venta llegó igual a la notebook.**
6. VOLVER EL INTERNET: las dos tablets "Todo subido" y la notebook las dos cajas "al día".

Encontró tres cosas, arregladas con su test: la línea de VENDER se cortaba en la tablet ("Sin central desde las 23:36 · 1 …"), el
renglón verde de CAJAS seguía diciendo "cuando las cajas suben sus ventas" con la central prendida, y "Esta notebook" no se ponía al
día sola cuando terminaba de subir lo suyo (se quedaba en "subiendo" hasta que llegaba otra cosa).

**La cuenta de lo pendiente no corre sola todo el tiempo** (pregunta del usuario: "¿cada 10 s no era lo que se cambió del sync?",
"la idea es ahorrar también eso"). No es lo mismo que el ciclo que sacó la 6.3.3 (aquel le pedía 16 tablas a la nube cada 10 s; esto
cuenta filas en la base de la misma PC), pero igual se ahorra: VENDER (`PuestaAlDiaBarra`) y la notebook (`_EstaNotebook`) cuentan
al abrir, **cuando el equipo escribe algo** (`AvisoALaRed.escrituras`, que sube con cada escritura de `BarraConLaRed`, también el
catálogo y los precios), cuando cambia la conexión y cuando baja o llega algo; y **cada 10 s solo mientras hay internet y queda algo
subiendo**, que es lo único que cambia el número sin que nadie toque nada. Sin internet, o con todo subido, la cuenta queda quieta
(`test/barra_home_test.dart`, "la cuenta corre sola solo mientras…"). La línea de Recepción (publicada) sigue contando como antes.

**Lo que el sandbox no puede probar y queda para la 9 y la 10, con la tablet y el TP-Link:** que la pregunta por UDP pase por el wifi
real (algunos routers aíslan a los equipos; para eso está la dirección a mano), el `ws://` desde el APK de Android, y la notebook con
el cortafuegos del instalador. Qué mirar: en la tablet, "Central · N cajas" al abrir VENDER; vender en una y ver "Quedan" bajar en la
otra; con el cable de internet del router desenchufado, lo mismo, y al enchufarlo "Todo subido" en todas.

**Lo que no entra:** vender desde la notebook o la web; ver desde el iPhone lo del salón sin internet (afuera nadie lo ve hasta que
vuelve el internet); un código de 4 cifras como el de la puerta (la llave es el id de la fiesta, y la notebook muestra quién está
conectado; si el wifi lo comparten los invitados, se agrega después sin cambiar el resto).

### Etapa 8: el jefe en el iPhone, en la web (7-nov, noche)

**Hasta acá BARRA del jefe no andaba en la web:** `barraDelJefeProvider` armaba `BarraLocal` (SQLite, que en la web tira
`UnsupportedError`), las fiestas salían de la base de la PC y lo guardado iba a la cola de sync, que en la web no existe. Ahora:
- **`enLaWebProvider`** (`providers/barra_del_jefe_provider.dart`, `kIsWeb`): la única llave de "estoy en la web". Los tests la ponen
  en `true`; las pantallas del jefe no preguntan por `kIsWeb` (`test/barra_en_la_web_test.dart` lee los archivos y lo vigila, junto con
  que la nube entre por `supabaseProvider` y nunca por el singleton de Supabase).
- **Los datos:** en la web, `barraDelJefeProvider` es `BarraNube(ref.watch(supabaseProvider))`; las fiestas vienen de
  **`BarraNube.eventos()`** (lee `eventos` de la nube, ordenado y de a 1000; `FiestasDelJefe.de` saca las canceladas) por
  `eventosDeLaBarraProvider`; `subirDeLaBarraProvider` en la web no hace nada (BarraNube ya escribió). Quien firma sigue siendo "Jefe".
- **CAJAS se relee sola en la web** (`CajasDeLaFiestaVista`): cada 30 s mientras está abierta (`kRelecturaDeCajasEnLaWeb`) y al
  deslizar hacia abajo (`RefreshIndicator`, `jefe_cajas_releer`); el renglón verde lo dice. En la PC nada de eso: la rehace el sync. Las
  tablas de la barra no están en Realtime a propósito, así que no hay otro aviso.
- **Sin impresora en la web:** sin el ícono, sin IMPRIMIR LISTA, sin REIMPRIMIR y sin IMPRIMIR el cierre; quedan los dos PDF de 58 mm
  (`PdfService.entregarPdf` en la web va por `Printing.sharePdf`, que abre o guarda el archivo).
- **La noche inventada pasó a `test/helpers/noche_de_barra.dart`** (`nocheDeBarra()`): la usan la muestra del jefe, el arnés de la web
  y sus tests.
- **El arnés `tool/barra_web_prueba.dart`:** BARRA del jefe sobre la noche en memoria, con la llave de la web prendida. **Se compila
  como la web de verdad** (`flutter build web -t tool/barra_web_prueba.dart --no-web-resources-cdn --output build/barra_web_prueba`) y
  se sirve con `python -I -m http.server 8790 --directory build/barra_web_prueba` (`.claude/launch.json`, para el navegador de la app):
  **el compilador de desarrollo (`flutter run -d web-server`) se cae con este proyecto y deja la página en blanco** ("The Dart compiler
  exited unexpectedly", 7-nov). `test/barra_web_prueba_test.dart` lo monta a 390 px.
- **Pruebas:** `barra_jefe_pantalla_test.dart`, grupo "en la web" (4: sin impresora, la relectura a los 30 s, deslizar, y que en la PC
  no pasa); `barra_nube_test.dart` (`eventos()`); `barra_en_la_web_test.dart`; `barra_web_prueba_test.dart`. Las cuatro de la web fallan
  sin el cambio. En el helper `tocar` de la pantalla del jefe hace falta un `pump()` entre `ensureVisible` y el toque: si no, el toque va
  a donde estaba el botón antes de desplazar (apareció con el texto más largo de la web).

**El recorrido en el navegador de la app a 375 px** (el usuario lo miraba y tocaba a la vez): CATÁLOGO con las fotos; PRECIOS (un precio,
el recargo, GUARDAR CAMBIOS: "Guardado: 1 precio y el recargo."); CAMBIAR DE FIESTA a ROTONDA (CAJAS vacía), COPIAR DE OTRA FIESTA
("Se copiaron 11 precios de TÉCNICA PINAROLI y su recargo", sin el Red Bull dado de baja) y guardar; LISTA · PDF; CAJAS con la noche,
Caja 1, VER CÓMO VA (CERRAR y PDF, sin IMPRIMIR), PDF del cierre; ANULAR con motivo desde la web ("ANULADA · se cobró dos veces ·
Jefe"); MODO JEFE en NO. **No apareció ningún error.** Lo que no se pudo ver en el panel: el archivo que baja el PDF (las letras Outfit se
cargaron, así que el PDF se armó; `Printing.sharePdf` es lo mismo que usan los demás PDF de la web) y deslizar para releer con el mouse
(el navegador de escritorio no desliza con el mouse; en el iPhone es un toque, y el test lo cubre).

### El recorrido de la etapa 7 (7-nov, noche)

**La ventana de prueba, con los dos lados** (`tool/barra_prueba.dart`; `flutter run -d windows -t tool/barra_prueba.dart`, y con
`--dart-define=papel=pantalla` los papeles se miran con PAPEL en vez de salir por la impresora). La cajera a la izquierda (una tablet,
o un celular con VER COMO CELULAR) y el jefe a la derecha (la PC). **Cada lado es su propia app** (su `MaterialApp`, sus diálogos y su
ancho, para que `CortesPantalla` mida el lado) **sobre la misma `BarraEnMemoria`**, y se hablan como en la app: lo que la tablet sube, el
jefe lo baja (`operationalSyncRevisionProvider` del otro lado), y al revés. CORTAR INTERNET vale para los dos: el jefe no ve las ventas
que la tablet no subió (`_LoQueSubio`), y al volver suben y le llegan. MODO JEFE: SÍ / NO, arriba del jefe. Una sola impresora para los
dos. La ventana se agranda cuando ya se ve (el runner de Windows la muestra después del primer cuadro y eso deshacía el `maximize`). El
test `test/barra_prueba_test.dart` la monta y prueba que los lados se hablan (con la rotura a propósito del filtro de lo no subido).

**Lo que se recorrió:** CATÁLOGO (alta con la foto por el nombre, ELEGIR FOTO, baja), PRECIOS (precio nuevo, producto nuevo, recargo,
GUARDAR CAMBIOS, COPIAR DE OTRA FIESTA), la cajera con su PIN (la fiesta con precios nuevos le aparece sola), VENDER con el precio
nuevo, efectivo, transferencia (el cobro arranca con el recargo que puso el jefe: se probó con 8 %), mixto, la silla extra con su
vale, CAJAS que se pone al día sola, anular desde el jefe (la tablet recupera el stock), reimprimir con COPIA y "Jefe", sin internet y
de vuelta, cerrar la caja a ciegas (al jefe le llega la diferencia), VER CIERRE, sin modo jefe, y la cajera y el jefe en celular.

**Lo que encontró, arreglado con su test (en rojo sin el arreglo):**
1. **MIXTO: la casilla que se completa sola no se podía corregir.** Al escribir el efectivo, la transferencia se completa sola; al
   tocarla para cambiarla, lo escrito se pegaba al número ($ 5.400 y "5000" dejó $ 55.400.000). Ahora cada casilla de plata del cobro
   queda toda marcada al entrar y lo escrito reemplaza (`_Plata`, `cobrar_hoja.dart`).
2. **Con recargo, "Cobrado" decía el total sin el recargo** ($ 11.500 debajo de "Venta guardada: $ 12.075"). Ahora dice lo cobrado
   (`elegir_vales.dart`, `vales_cobrado`).
3. **En la PC del jefe no había dónde elegir la impresora:** solo desde VENDER, y en la oficina nadie abre una caja. IMPRIMIR LISTA,
   reimprimir y el cierre decían "¿La impresora está prendida?" con la impresora al lado. Ahora BARRA tiene arriba el ícono de la
   impresora (la misma pantalla de la cajera; no en la web), y si esta PC nunca eligió una, lo dice (`faltaLaImpresora`,
   `kSinImpresoraEnEstaPc`), en reimprimir antes de pedir el motivo.
4. **Guardar precios y recargo juntos decía solo "Guardado: 2 precios."** Ahora "… y el recargo".
5. **COPIAR DE OTRA FIESTA contaba un producto dado de baja**: decía "10 precios" y copiaba 9. Ahora cuenta los que va a copiar.
6. En la ventana de prueba: la caja salía "abierta desde las 23:00" (la barra en memoria tiene un reloj fijo; ahora usa la hora real) y
   la ventana no se agrandaba.

**Visto y dejado como está:** en el celular, el título de VENDER corta el nombre de la cajera ("Caja 2 · …") por los cinco íconos; la
cajera de la barra va en tablet. Abrir una caja no le llega al jefe hasta la primera venta (en la app la sube el motor a los 2 s). En el
papel de la lista, cada línea de guiones parece salir como dos rayas juntas (`g.hr()` manda una sola de 32): sin verificar en los
otros papeles; si se quiere ahorrar ese renglón, se mira con la impresora.

**La foto:** la lista de precios de PUERTO VIEJO salió por la TP-POS58 desde el lado del jefe ("un lujo"): acentos bien, el nombre largo
en dos renglones con el precio en el primero, sin logo ni QR. **La primera vez no salió**: la PC la tenía recordada, pero no contestó
al reconectarse sola; después de buscarla y tocar CONECTAR, salió. No se sabe si estaba apagada o dormida en ese momento: si vuelve a
pasar con la impresora prendida, es para mirar (reconectarse sola en Windows sin buscarla antes).

### Etapa 7: el jefe en la PC (7-nov, en la rama)

**Antes de programar:** el plan corto y una maqueta en Claude Design (https://claude.ai/artifact/YBhdWQsf4C7HKJeKFoaDxQ, privada). Eligió
**CAJAS con una tarjeta por caja** (se ve bien en el iPhone de la etapa 8; la tabla se descartó) y **la fiesta primero**. El recargo ya
estaba decidido el 3-nov ("Recargo por transferencia", abajo): **se lo pregunté dos veces sin acordarme; antes de preguntar algo de la
barra, buscarlo acá.**

**El recargo de cada fiesta** (`c93eff5`): tabla nueva **`barra_recargos`** (dentro de la v78, que no está en ninguna PC), una fila por
fiesta con id fijo (`UuidUtils.barraRecargoId`), `RecargoBarra` (0 a 100; en 0 arranca apagado). Baja con lo de carga y la tablet la
baja al prepararse (`tablasDeLaBarra`: sin su SQL en la nube, la tablet no queda "Lista para trabajar sin internet"). **Cada cobro arranca
con el de la fiesta** (`recargoDeArranque`); la cajera lo cambia en ese cobro y el siguiente vuelve al de la fiesta; sin el de la fiesta,
el último del equipo como antes. SQL `supabase/migrations/20261107140000_barra_recargos.sql`, **sin correr** (el cuarto de la 6.4.0).

**La pantalla** (`lib/features/barra/jefe/`, `c41114b` y `c1ac6bb`): la tarjeta **BARRA** en el Centro de Comando, al lado de RECEPCIÓN
(el Centro solo se ve en modo jefe). `BarraJefeScreen` con el tema Noche dorada (`temaDeVender`):
- **La fiesta arriba** (`FiestasDelJefe`, `services/fiestas_del_jefe.dart`): abre en la próxima; **la de anoche sigue abriendo al día
  siguiente** (para mirar las cajas a la mañana); CAMBIAR DE FIESTA con LAS QUE VIENEN y LAS ÚLTIMAS (8); sin las canceladas. La fecha
  dice "· hoy", "· anoche" o "· la próxima" (`fechaConCuando`).
- **CATÁLOGO** (`catalogo_del_jefe.dart`): uno solo para todas las fiestas, los activos primero; en la PC el producto elegido al lado,
  en tablet y celular en una ventana. Nombre, categoría (con las que ya hay a un toque), **foto elegida de las 74** (`biblioteca:<clave>`)
  o "según el nombre", dar de baja / volver a dar de alta (nunca se borra).
- **PRECIOS** (`precios_de_la_fiesta.dart`): cada producto activo con VA, precio (con el "$" y los puntos), stock y desde cuántos avisar;
  el recargo con − / +; **todo se guarda junto con GUARDAR CAMBIOS** (una barra abajo dice cuántos cambios hay); va sin precio no guarda
  y dice cuál falta; sacar un producto de la fiesta no borra su fila. **COPIAR DE OTRA FIESTA** trae los que van, sus precios y el
  recargo, **no el stock**, y espera GUARDAR. **La lista de precios** se ve al lado como sale (`ModeloTicket.deListaDePrecios`, por
  categoría, con el recargo al pie), se imprime por la térmica o sale en PDF de 58 mm. **Los avisos van arriba de la lista, no en un
  SnackBar:** tapaba GUARDAR CAMBIOS (lo encontró una prueba).
- **CAJAS** (`cajas_de_la_fiesta.dart`): los totales (vendido, efectivo, transferencia con su recargo, ventas y anuladas, cajas abiertas y
  cerradas, la diferencia de las cerradas), **una tarjeta por caja** (a todo el ancho en el celular) con lo contado y la diferencia de las
  cerradas, y al costado **el stock de toda la fiesta, con lo agotado y en aviso arriba**. Tocar una caja muestra sus ventas: **el jefe
  anula cualquiera** con motivo, **reimprime cualquiera las veces que haga falta** (`VentaDeLaCaja.copiaDelJefe`: sin el freno de la
  cajera; cada vale con su copia que sigue, anotada con "Jefe") y ve el cierre como el papel (VER CIERRE, o VER CÓMO VA si sigue abierta),
  con IMPRIMIR (sin el historial) y PDF de 58 mm. Se pone al día sola cuando bajan ventas.
- **Sin modo jefe** se ve todo, con el aviso, y lo que guarda queda apagado; **cada guardado vuelve a preguntar** (`_frenaSinModoJefe` en
  las tres pestañas; `test/solo_modo_jefe_test.dart` lee la carpeta `jefe/` y falla si aparece un guardado sin la llave).

Pruebas: `test/barra_jefe_pantalla_test.dart` (23, la pantalla entera con la barra en memoria, a 390, 800 y 1280 px),
`barra_repositorios_test` (el recargo), `barra_pantalla_test` (el cobro arranca con el de la fiesta), `reimpresion_de_barra_test` (la copia
del jefe), `sync_tablas_v78_test`, `migracion_v78_test`, `sync_tablas_v77_test`. La suite entera, en verde. **Las muestras**
(`tool/barra_jefe_muestra_test.dart`, siete imágenes con una noche inventada en TÉCNICA PINAROLI) encontraron cuatro cosas con las pruebas
en verde: CAMBIAR DE FIESTA salía con los colores claros de la app (el diálogo usaba el contexto de afuera del tema), las cajas no
ocupaban el ancho del celular, "Avisar desde" se cortaba en el celular y los botones del producto quedaban debajo del borde en la PC.

### Etapa 6: cerrar la caja (7-nov, en la rama)

**El candado arriba en VENDER** (`vender_cerrar`) abre `CerrarCajaBarraScreen` (`widgets/cerrar_caja_barra_screen.dart`):
1. **Contar, a ciegas.** "Contá todo el efectivo del cajón, con el cambio." La pantalla no muestra **ninguna plata de la caja** (ni lo
   vendido ni lo esperado; `modo_barra_cerrado_test` lee el paso y lo vigila). Confirma viendo el número grande ("¿Contaste todo el
   efectivo, con el cambio?", VOLVER A CONTAR / SÍ, CERRAR) y **la caja se cierra en ese momento**: lo contado ya no se cambia
   (decidido el 7-nov, después de pensarlo con el usuario: así la cajera no puede espiar lo esperado). La diferencia se calcula con la
   caja como está guardada (el cambio pudo ponerse después de abrir) y sube enseguida (`barra_cajas`).
2. **El cierre.** Recién ahí: "Tenía que haber $ X · Contaste $ Y" y la diferencia en grande (verde justo, rojo faltan, ámbar sobran), y
   **el cierre entero como el papel** (`PapelEnPantalla`): lo vendido de cada producto (`CierreDeBarra.porProducto`, el que más salió
   primero, sin anuladas), las sillas extra vendidas, los totales, lo anulado, el esperado, lo contado, la nota y **el historial**, una
   línea por venta con hora y medio, las anuladas marcadas. IMPRIMIR (por la térmica **sin el historial**, para ahorrar papel; sale solo al
   cerrar), GUARDAR PDF y AGREGAR UNA NOTA (`anotarCierre`: lo único que cambia después; lo contado no). LISTO (o atrás) vuelve al inicio
   de la barra, y esa fiesta pide abrir otra caja. En la tablet acostada y la PC, la diferencia y los botones a la izquierda y el papel a
   la derecha; en el celular, uno debajo del otro.

**El PDF es de 58 mm, una sola hoja tan larga como haga falta** (el usuario: "A4 es muy grande; si tiene que ser largo que sea"):
`PapelPdf` (`impresion/papel_pdf.dart`) arma la misma lista de líneas que va a la impresora, con las Outfit (`PdfService.fuentesOutfit`,
que pasó a público junto con `PdfService.entregarPdf`: en Windows el menú de ver, guardar o abrir la carpeta; en Android, compartir).
`PapelEnPantalla` y `PapelPdf` sirven para cualquier papel de la barra: **los PDF del jefe de la etapa 7 se hacen con esto, nada en A4.**

**El ticket con precios ya no lleva QR** (7-nov: nadie lo lee, 3 cm de papel). `NumeroDeTicket.qr` queda para el arnés de la impresora.

**Lo que dio la prueba:** con el mouse en `tool/barra_prueba.dart` (dos ventas, cerrar con $ 500 de menos, el papel por la TP-POS58, el PDF
abierto y guardado en `Documentos\Junior Eventos\PDFs` de 58 × 86 mm, volver y que pida otra caja) todo anduvo. **El papel del cierre,
mirado en la foto del usuario (7-nov):** lo vendido por producto, "Sillas extra vendidas", los totales, lo esperado, lo contado y "Faltan
$ 500", con los acentos y sin logo. (Abrió y Cerró a la misma hora es del reloj fijo de la ventana de prueba.) Las muestras
(`tool/barra_cierre_muestra_test.dart`, una noche de 30 ventas) encontraron que **el papel en pantalla perdía la letra de la app**
(reemplazaba el estilo entero): arreglado con `DefaultTextStyle.merge`.

Tests: `barra_cuentas_test` (lo vendido por producto, las sillas), `modelo_ticket_test` (el cierre con lo vendido, las sillas y el historial;
el ticket sin QR), `barra_repositorios_test` (`anotarCierre`), `papel_en_pantalla_test`, `papel_pdf_test` (una hoja, 58 mm, más larga con
más renglones) y `barra_cerrar_test` (de punta a punta desde el inicio, volver a contar, justo, sin impresora, atrás antes y después de
cerrar, a 360, 800 y 1280 px). Roturas vistas en rojo: lo esperado a la vista antes de contar, cerrar sin confirmar y no subir.

### Etapa 5: reimprimir y anular (7-nov, en la rama)

**VENTAS** (el ícono de recibo arriba en VENDER, `widgets/ventas_de_la_caja_screen.dart`): las ventas **de su caja**, la última arriba,
con lo que salió de cada una ("Salió 1 vale · 1 copia", "No salió ningún vale", "faltan 9 sin vale"). Con cada venta:
- **REIMPRIMIR, con freno** (decidido el 3-nov): solo la **última** venta de la caja, **una vez**, con **motivo** obligatorio. Saca **el
  mismo vale que salió** (sus bebidas, su número y si era por separado), cada uno con `*** COPIA ***` arriba y abajo, "Copia 1 - Marta",
  la hora, el motivo y "Se entrega solo con el jefe". **El freno es por vale:** si la impresora se cortó a la mitad, lo que no salió se
  termina con otro REIMPRIMIR. Lo decide `VentaDeLaCaja` (`cuentas/reimpresion_de_barra.dart`, cuenta pura). Otra copia, o una venta
  anterior: el jefe, en la etapa 7.
- **IMPRIMIR LO QUE FALTA**, si quedaron bebidas sin vale (sin impresora, o la cajera salió antes): abre la misma pantalla de los vales
  (`ValesDeLaVentaScreen`) con lo que ya salió descontado (`ElegirVales.yaSalieron`), y sigue la numeración ("N° 0001-2"). Son originales,
  sin COPIA: nunca salieron.
- **TICKET** con precios, si el cliente lo pide (también abajo en la pantalla de después de cobrar, `vales_ticket`). `ModeloTicket.deVenta`
  **sin logo**, para ahorrar papel (pedido del usuario, 7-nov: "el logo en los vales no van"); lleva el QR y "¡Gracias, salud!".
- **ANULAR** cualquier venta de su caja, con motivo (decidido el 3-nov: la cajera también anula). `anular` pasó a `BarraDeLaCaja`: es
  la misma fila de `barra_anulaciones` que la del jefe, con quién y el equipo, y sube enseguida (`subirDeLaBarraProvider`). La venta no se
  toca; deja de contar en la caja y en el stock, y una silla de esa venta queda en rojo en la puerta (`ValesAnulados`). Una anulada no se
  reimprime ni saca ticket.

**Cada vale que sale queda anotado** en una tabla nueva, **`barra_vales`** (v78, junto con `sillas_puerta`; SQL
`supabase/migrations/20261107100000_barra_vales.sql`, **sin correr**): una fila por papel que salió, el original (`copia_numero` 0) y
cada copia (con su motivo). Se anota recién cuando el papel salió (`ElegirVales.anotar`). **Cambia lo decidido el 3-nov** (los vales
adentro del JSON `renglones` y una tabla `barra_reimpresiones`): eso editaba la venta, que nunca se edita; una sola tabla que solo agrega
sirve para las dos cosas. Sube con lo del cobro, nunca se borra (`_tablasSinRevisarBorrados`), y no va en la limpieza padre-hija de la cola.
**La migración v78 se volvió a probar sobre una copia de la base real** (7-nov): las 42 tablas iguales, las dos nuevas vacías, vuelta a la
6.3.1, y la base real con la misma huella.

**Lo que dio la prueba con el mouse** (`tool/barra_prueba.dart`, que ahora acepta `--dart-define=papel=pantalla` para ver los papeles
como texto sin imprimir): todo anduvo, y apareció un error con los tests en verde: **en VENDER el texto tachado no se veía** (la raya salía
casi negra, del tema claro de la app). Arreglado en el tema (`temaDeVender`, `decorationColor`), con su test.

**Lo que dio el papel** (foto del usuario, 7-nov, con la TP-POS58): el vale de la silla, el de las bebidas, el ticket con precios y las dos
copias salieron bien, con los acentos y las letras grandes; las copias con COPIA arriba y abajo. Las dos copias salen una detrás de la otra
con el espacio para cortar entre las dos, como los vales sueltos.

Tests: `test/reimpresion_de_barra_test.dart` (el freno), `test/barra_ventas_test.dart` (la pantalla entera, a 360 y 800 px),
`barra_repositorios_test` (anotar, anular desde la caja), `migracion_v78_test` y `sync_tablas_v78_test` (las dos tablas),
`modelo_ticket_test` (la copia sin logo ni QR ni precios), `modo_barra_cerrado_test` (las pantallas nuevas, solo su caja). Roturas vistas en
rojo: sin "solo la última", sin "una vez", sin anotar el vale, sin la columna `por_separado`, sin la tabla en los borrados, y la raya oscura.

**VENDER, cerrado el 4-nov (`c9fc4c0`):** **el stock es general**: lee las ventas de **todas las cajas de la fiesta**
(`BarraDeLaCaja.ventas(eventoId)`) y se vuelve a leer cuando baja algo (`ref.listenManual(operationalSyncRevisionProvider, ...)`);
**"Quedan" resta también lo que ya está en la cuenta** (`_quedan`); **sin stock pregunta antes** ("No queda … ¿Vender igual?",
`Key('sin_stock')`, una vez por producto y por cuenta, `_sinStockIgual`, que se limpia en `_vaciar`); la tarjeta apagada con "Agotado",
"Sin stock" si se vende igual, y **el + / − en la misma tarjeta**. El + de la cuenta pasa por el mismo `_sumar`. Tests en
`test/barra_pantalla_test.dart` (25), con 3 roturas vistas en rojo.

**El diseño y las fotos, hechos el 4-nov** (en la rama, sin publicar):
- **Dos diseños a elección**, como en la maqueta: **Noche dorada** y **Mostrador** (`estilos/disenio_barra.dart`: `DisenioBarra`,
  `TemaBarra` como `ThemeExtension`, `temaDeVender`). **Cada equipo recuerda el suyo** (`DisenioRecordado`, clave `barra.disenio`) y se
  cambia con el ícono de paleta de VENDER (`widgets/elegir_disenio.dart`, con una tarjeta de verdad de cada uno). El tema va **arriba**
  de VENDER (`VenderScreen` envuelve a `_Vender`): si no, la hoja de cobro y los avisos salían con los colores de la app. La pantalla de
  los vales es otra ruta y lleva el tema a mano.
- **La tarjeta** (`widgets/tarjeta_producto.dart`): la foto en 4:3 (el alto de la grilla sale del ancho, así no se desborda en ningún
  tamaño), sin foto las iniciales, agotada en gris; en Mostrador el − n + siempre, con el − apagado en cero que **se come el toque** (un
  test encontró que pasaba a la tarjeta y sumaba uno). Mostrador en la tablet: los tres pagos como barras, con su letra chica.
- **Las fotos vienen adentro de la app** (`assets/barra/`, 74, unos 2 MB): "el jefe no las va a cargar". Cada producto toma la suya **por
  el nombre** (`estilos/fotos_de_la_barra.dart`, `FotoDeLaBarra.para`): **primero lo que se toma** (tragos, bebidas blancas por marca y
  cervezas por marca, con la lata aparte en Quilmes y Heineken), **después la cerveza sin marca** por estilo (IPA/APA, roja, negra, rubia)
  y por cómo se sirve, y **al final lo sin alcohol** (gaseosas, energizantes y agua por marca). Así "Fernet con coca" es fernet y "Speed con
  vodka" es vodka. Si el jefe elige otra de la biblioteca (`biblioteca:<clave>` en `imagenUrl`) o sube una propia (`http…`), esa gana
  (`services/imagen_de_producto.dart`; la propia se guarda en el equipo, nunca `NetworkImage` en la PC).
- **De dónde salió cada foto:** Unsplash (sin crédito) y, para las marcas, Openverse (Flickr y Wikimedia Commons, Creative Commons con
  crédito). El autor y la licencia de cada una: `docs/FOTOS_DE_LA_BARRA.md`; un test exige que cada foto tenga su renglón. **No se copió
  nada de páginas de marcas ni de supermercados.** Marcas sin foto libre (Schneider, Andes rubia, Palermo, Gancia, Fernet Branca como
  botella, Beefeater, Baileys, José Cuervo, Chandon, Paso de los Toros, 7up): salen con la foto de su tipo y el nombre encima; se pueden
  sumar con una foto sacada por ellos.
- Tests: `test/barra_disenio_test.dart` (los dos diseños en 4 tamaños, recordar, elegir, foto o inicial, agotada, pagos), y
  `test/fotos_de_la_barra_test.dart` (más de 90 nombres, cada foto alcanzable por algún nombre, cada archivo en la app y en los créditos,
  ninguna foto suelta). Muestras: `tool/barra_muestra_test.dart`.

**Para mirarlo con el mouse:** `flutter run -d windows -t tool/barra_prueba.dart` (sin base ni nube; PIN Marta 1111, Tati 5555; botón para
cortar el internet; los vales salen por la TP-POS58 de verdad; los productos ya salen con sus fotos). **Falta:** recorrerla de punta a punta,
que lo hace Claude en el arnés (regla del 6-nov: las pruebas las hace Claude, en un sandbox), y la foto de los vales impresos, que
necesita la impresora de verdad.

**El aviso de papel, pedido el 3-nov:** hoy la app solo le escribe a la impresora. Si la TP-POS58 contesta el pedido de estado (`DLE EOT 4`)
por Bluetooth, VENDER avisa "sin papel" antes de cobrar; si no, queda como está.

**Decidido el 3-nov (noche), para hacer en su etapa:**
- **El stock de todas las cajas, también sin internet, por la red del salón.** El jefe quiere que lo que vende una caja se vea en las
  demás. Con internet ya pasa (las ventas suben y bajan). Sin internet: **habrá un router TP-Link en el salón** al que se conectan todas
  las tablets, y una hace de central, como la notebook de la puerta (`recepcion/central/`, `CentralPuerta`): recibe las ventas de cada
  caja y reparte el stock de todas. Si la central no está, cada tablet sigue vendiendo y descontando lo suyo. Falta decidir qué equipo es la
  central (la notebook de la puerta u otra tablet). Es una etapa nueva, antes de la prueba de punta a punta. **La red tiene señal pero no
  internet** (lo aclaró el usuario), y **va a haber varios TP-Link, distintos de los de la puerta y lejos unos de otros**. **El stock es
  general** (lo carga el jefe en modo jefe el día antes, y todas las cajas descuentan del mismo), y **todas tienen que ver en vivo cómo se
  va gastando, haya o no internet**. Para eso **las redes se unen con cable de red** (decidido el 3-nov): de un puerto LAN a un puerto LAN
  (nunca el WAN), un TP-Link principal y los demás en modo "Punto de acceso" (o, si el modelo no lo trae, con otra dirección LAN y el
  DHCP apagado), todos con el mismo nombre de wifi y clave; tramos de hasta 100 m, con un switch en el medio si hace falta. **La central
  la programa una etapa propia**: una tablet de la barra recibe las ventas de todas y reparte el stock; si no está o se corta un cable,
  cada caja sigue vendiendo con el último stock que conoce y avisa "Sin conexión desde las 23:40". Con internet, además, sube como siempre.
  **En la app, sea cual sea la conexión, "Quedan" tiene que descontar lo vendido por todas las cajas de la fiesta** (hoy VENDER lee solo
  las ventas de su caja) y actualizarse solo cuando llegan ventas nuevas.
  **7-nov, confirmado por el usuario:** la barra vende con **la app instalada en cada tablet**, no como las recepcionistas (celular sin
  app, por QR): el navegador no imprime por Bluetooth y la barra no puede dejar de vender si se cae la red. La central solo comparte el
  stock y deja al jefe ver las cajas en vivo. Cómo se conecta la tablet (QR como Recepción, o que la encuentre sola) se decide en su etapa.
- **Sin stock, pregunta antes** (elegido por el usuario): la tarjeta se ve apagada con "Agotado" y, si la tocan, "Según lo cargado no queda.
  ¿Vender igual?". **"Quedan" tiene que bajar con lo que ya está en la cuenta** (hoy en VENDER baja solo con lo vendido: hay que restar
  también la cuenta). Y en la misma tarjeta se suma y se quita (+ / −).
- **El diseño se elige:** Noche dorada o Mostrador, cada equipo recuerda el suyo, con la foto de cada producto bien a la vista. Maqueta:
  `build/maquetas/barra_disenios.html`.

## Etapa 4: la cajera (3-nov, noche)

Lo que se ve, en orden (todo en `lib/features/barra/`, y se adapta a celular, tablet y PC con `CortesPantalla`):
- **Entrar:** el PIN con permiso Barra entra derecho (`AppRoleKind.barra`, `entrarComoBarra`: sin caja de cuotas, sin latido, apaga el modo
  jefe); con varios permisos, BARRA ya está prendido. `destinoDeEntrada` lo manda a `BarraHomeScreen` antes que nada. `kBarraTodaviaNo` ya
  no existe. Lo vendido sube solo (`esBarra` en el coordinador de sync).
- **`BarraHomeScreen`:** "BARRA · MARTA", SALIR, la línea "Lista para trabajar sin internet" de la barra (`services/barra_sin_internet.dart`:
  `EstadoSinInternetBarra`, `PuestaAlDiaBarra` sobre `SyncEngine.bajarParaLaBarra()`; cuenta las ventas que esperan subir) y las fiestas
  **con precios en este equipo y por hacer**, masivas o particulares (`fiestasParaLaBarra`).
- **Abrir la caja** (`abrir_caja_barra_dialog.dart`): el número (1 a 6) y, si hace falta, dónde está. Nada de cambio ni de turno. Si otra
  caja abierta de la fiesta ya tiene ese número, lo dice con el nombre y deja seguir. Con la caja ya abierta en este equipo, entra derecho.
- **VENDER** (`vender_screen.dart`): buscador (sin acentos, palabra por palabra) y chips de categoría; tarjetas con el precio, lo que lleva
  la cuenta y el stock ("Quedan 3", "Agotado", sin frenar la venta). En el celular la cuenta va abajo, con el total y los tres botones
  siempre a la vista, y se despliega tocando el total; en la tablet y la PC, al costado. Arriba, el ícono del **cambio** (se pone cuando
  haya: `BarraDeLaCaja.ponerCambio`) y el de la **impresora** (verde si está lista; abre `ElegirImpresoraScreen` para elegirla o cambiarla).
- **EFECTIVO · TRANSFERENCIA · MIXTO** (`cobrar_hoja.dart`, hoja en el celular y diálogo en la tablet): la plata a mano con
  `PesosEnterosFormatter`; el vuelto; **transferencia sin comprobante** (es todo lo que entra por Mercado Pago, posnet con QR, débito o
  transferencia: quien cobra lo ve en el momento); el **recargo** con su check, por % (arranca en el último que usó el equipo, 5 la primera
  vez, `RecargoRecordado`) o en $; en el mixto las dos casillas se escriben y la de transferencia ya trae el recargo. Las cuentas son
  `CobroBarra` (`recargo`, `transfiere`, `aCobrar`, `conTransfiereDelMixto`).
- **Confirmar:** la venta se guarda **antes de imprimir**, sube si hay internet (`subirVentaProvider`) y sigue la pantalla de los vales,
  con "Venta guardada" y el vuelto. LISTO vuelve a VENDER con la cuenta vacía; si quedan bebidas sin vale, pregunta antes.

**Los datos cambiaron, dentro de la v77 (no publicada):** `barra_ventas` pierde `comprobante_visto` y suma `recargo` (lo cobrado de más) y
`recargo_pct`. `VentaBarra.total` sigue siendo lo que valen las bebidas; `efectivo + transferencia = total + recargo`; `cobrado` es lo que
pagó. El cierre cuenta los recargos aparte (`CierreDeBarra.recargos`, "De ellos, recargos" en el papel) y el ticket con precios dice
"Recargo transf." y "COBRADO". Cambiaron a la vez la base (`crearTablasV77`), el SQL, el motor de sync y sus tests.

**Tests:** `test/barra_home_test.dart`, `test/barra_pantalla_test.dart` (VENDER de verdad a 360×740, 740×360, 800×1280 y 1280×800: sin
desbordes y con los tres botones a la vista; los tres cobros, el recargo en % y en $, el mixto por las dos casillas, el cambio, los vales,
sin impresora, y la base que no guarda), `test/modo_barra_cerrado_test.dart`, `test/pesos_enteros_formatter_test.dart`,
`test/productos_para_vender_test.dart`, y lo nuevo en `entrada_operador_test`, `barra_cuentas_test`, `barra_repositorios_test` y
`modelo_ticket_test`. Con `test/helpers/barra_en_memoria.dart`. **Los tests encontraron** dos desbordes en el celular (la fila del total y las
tarjetas con el celular acostado) y que los productos mezclaban precios de otra fiesta: arreglados. Roturas a propósito vistas en rojo: la
Barra que cae en el panel, el recargo que no se guarda y el recargo sobre el total en vez de lo transferido.

## El 3b: los vales, en vez del ticket (3-nov, pedido del jefe)

El jefe pidió que de una compra salga **un vale**, no el ticket: sin logo, sin precios, **sin QR** ("es muy un embole") y con lo que se
entrega en letras grandes, como "JUNIOR EVENTOS". Lo hablado, con muestras en el chat:
- **Dos formas al cobrar:** **TODO JUNTO** (un vale con todas las bebidas, para quien retira de una vez) y **POR SEPARADO** (para ir
  retirando de a poco). "Sin papel" lo sacó el jefe. **Se pasa de una a la otra cuando se quiere** (lo pidió el usuario probándolo): después de
  sacar algunos por separado, TODO JUNTO saca un vale con todo lo que queda ("Un vale con lo que queda: 5 cerveza lata, 1 fernet…"). Lo que
  ya salió no vuelve a salir. Si TODO JUNTO es el primero, es el único vale y va sin número de vale ("N° 0017").
- **Por separado, cada bebida es su sector, con una sola casilla "vale por ___" y su propio IMPRIMIR, y cada vale lo arma la cajera a
  mano** (lo corrigió el usuario probándolo: "poner SIGUIENTE y bloquearme de poner manual no da"). Escribe 3, IMPRIMIR, sale un vale por
  3; la casilla queda vacía y dice "Quedan 7 · Salió 1 vale: 3"; escribe 2, y así hasta que no queda nada ("Todo en vales: 3 · 2 · 5").
  Vacía, el botón dice "IMPRIMIR LAS 5": un vale por todas las que quedan. No deja pasar más de lo que queda.
- **Cada vale sale solo, cuadradito, un papel por IMPRIMIR** (nada de tira). Lleva todo para reclamarlo, porque el barman se lo queda: la
  fiesta en negrita, el día, la fecha y la hora, "Caja 2 · Marta · N° 0017-3" (el -3 es el orden del vale en toda la venta, así no hay dos
  iguales aunque sean de bebidas distintas), "VALE POR 3 / CERVEZA LATA" en grande y "Vale solo hoy · una sola vez / El barman se queda el
  vale".
- **Contra el engaño, sin aparato:** el barman se queda el vale; la fiesta y el día dicen de qué noche es; una fotocopia se nota; la cajera
  reimprime solo la última venta, una vez; el jefe, cualquiera, y sale **\*\*\* COPIA \*\*\*** arriba y abajo con quién, cuándo y el motivo
  ("se entrega solo con el jefe"). Todo queda anotado.
- **La cajera también anula**, con el motivo obligatorio y anotado (quién, cuándo, desde qué equipo), como hoy el jefe.
- **Vender y pagar en una sola pantalla** (3-nov, con maquetas en el chat): se tocan los productos, la cuenta muestra el total y abajo
  hay **tres botones: EFECTIVO, TRANSFERENCIA y MIXTO**. No hay un COBRAR que después pregunte el medio: cada botón abre su cobro. Al
  confirmar se guarda la venta y sigue "¿Cómo se imprime?" (los vales).
- **La plata se escribe a mano, sin botones de billetes** (los sacó el usuario): cada casilla trae el "$" puesto y se lee con los puntos
  mientras se escribe ("2-0-0-0-0" se ve "$ 20.000"), en pesos enteros, sin centavos. No es el `CurrencyInputFormatter` de las cuotas, que
  entra por la derecha con centavos.
- **Recargo por transferencia**, como en el cobro de cuotas: un check que se prende o se apaga, **por %** o **en $** a mano. Va solo
  sobre lo que se transfiere (en el mixto, sobre la parte transferida), y la casilla de transferencia ya lo muestra sumado. **Sin "Vi el
  comprobante"** (lo sacó el usuario: el posnet de Mercado Pago está en la cuenta de quien cobra, que ve el pago al momento). **El % lo pone
  el jefe por fiesta, en BARRA junto con los precios (etapa 7); la cajera lo puede cambiar en cada cobro.** Mientras tanto arranca en el último
  que usó el equipo. La venta guarda cuánto fue de recargo y el cierre lo muestra aparte (hecho en la etapa 4). El % de la fiesta va en una
  tabla aparte, una fila por fiesta con id fijo (no en `eventos`).
- **Abrir la caja no pregunta el cambio ni el turno** (es de noche, nada de mañana/tarde): el cambio se pone después, con un ícono, si hay.
- **Una persona controla el sector de barras con un iPhone:** es la web en modo jefe, que ya estaba en el plan (etapa 6).

**Lo programado:** `cuentas/vales_de_barra.dart` (`Vale.todoJunto`, `Vale.conLoQueQueda`, `Vale.deUnaBebida`, `valePorValido`,
`CopiaDeVale`); `GrandeTicket` y
`renglonesGrandes` en `impresion/ticket_esc_pos.dart` (doble de alto y de ancho, 16 letras partidas por palabras; `soloAlto`, 32);
`ModeloTicket.deVale` y `diaFechaYHora` ("Vie 04/12/2026 - 23:41"). Tests: `test/vales_de_barra_test.dart`, el grupo "el vale" de
`modelo_ticket_test` y la letra grande en `impresora_barra_test`.

**La pantalla de después de cobrar: `widgets/elegir_vales.dart` (`ElegirVales`)**, sin base, con la impresora como un `ImprimirPapel` (true si
salió); la va a usar COBRAR en la etapa 5. Si un vale no sale, lo dice, no descuenta y deja lo escrito para volver a mandarlo.
`test/elegir_vales_test.dart` (8 tests, uno a 360 px). Roturas vistas en rojo: la casilla que no se vacía, dejar pasar más de lo que queda,
numerar por bebida, mandar todo en tira, TODO JUNTO con la compra entera después de otros vales, y trabar la forma. (Antes de que el usuario lo corrigiera,
la casilla partía la bebida en vales fijos y salían de a uno con SIGUIENTE; una prueba anterior que los mandaba seguidos sacó una tira larga.)

**Para mirarlo:** en `tool/impresora_prueba.dart`, **VALES** abre esa pantalla con una compra inventada (10 cervezas, 2 fernet, 3 aguas) y
la impresora de verdad; **COPIA** imprime un vale reimpreso. La maqueta, con los dos botones, la casilla y el IMPRIMIR por bebida:
`build/maquetas/vales_de_la_barra.html` (no va a git; se rehace desde el chat). Papel estimado: el ticket de hoy unos 12,5 cm; un vale
todo junto unos 6 cm; uno por separado unos 5 cm. La medida justa, de la foto.

**Dónde entra en las etapas:** la 4 (la cajera) lleva abrir sin cambio ni turno, el ícono del cambio y VENDER con los tres botones de
pago abajo; la 5 (cobrar e imprimir) lleva el cobro de cada medio con el recargo, los vales, reimprimir con freno y ANULAR de la cajera;
la 6 (el jefe) lleva el % de recargo de cada fiesta. **(Cambió al programarla, 7-nov: una sola tabla `barra_vales`, ver "Etapa 5:
reimprimir y anular" arriba.)** Lo que se había decidido: por cuánto salió cada vale
(`[3, 2, 5]`, con su número en la venta) adentro del JSON `renglones` de `barra_ventas` (sin columna), para reimprimir el mismo; una tabla nueva `barra_reimpresiones`, que solo agrega, dentro de la v77 (no se
publicó): con ella hay que volver a probar la migración sobre una copia de la base real, con la app cerrada.

**La rama lleva, sin publicar:** el plano antes de los sorteos (6.3.0, `docs/CONTEXTO_v6.3.0_2026-11-02.md`), operadores con permisos (etapas 1
a 3, `docs/CONTEXTO_OPERADORES_2026-11-02.md`) y la barra, etapas 1 a 4 (este archivo). **Dos SQL sin correr, antes de instalar:**
`supabase/migrations/20261103120000_permisos_operador.sql` (v76) y `supabase/migrations/20261103140000_barra.sql` (v77).

**Cómo se planeó la etapa 4 (queda como historia; lo hecho está arriba, en "Etapa 4: la cajera").** Lo que entraba, según la sección 3 del
plan (con lo que cambió el 3b: abrir sin cambio ni turno):
- **Entrar:** `AppRoleKind.barra` (hoy el enum es `none, jefe, caja, entradas`, en `caja_sesiones/providers/app_role_provider.dart`);
  `destinoDeEntrada` lleva a `BarraHomeScreen` (nueva, en `lib/features/barra/`). `kBarraTodaviaNo` desaparece de
  `caja_sesiones/services/entrada_de_operador.dart`, de `caja_sesiones/widgets/role_gate_screen.dart` y de su test. Molde: cómo se hizo
  Entradas (`lib/features/entradas/entradas_home_screen.dart`, `test/modo_entradas_cerrado_test.dart`).
- **Elegir la fiesta:** solo las que tienen precios (`fiestasConPrecios`), con la línea "Lista para trabajar sin internet" de la barra:
  `EstadoSinInternetBarra` y `PuestaAlDiaBarra`, calcados de los de la puerta (`recepcion/services/lista_sin_internet.dart`), sobre
  `SyncEngine.bajarParaLaBarra()`.
- **Abrir su caja:** número 1 a 6 y sede (`BarraDeLaCaja.abrirCaja`), **sin preguntar el cambio ni el turno** (3b). El cambio se pone
  después, con un ícono en la pantalla de la caja o al cerrar. Dos cajas con el mismo número en la misma fiesta se avisan al abrir.
- **VENDER**, según `CortesPantalla` (600 y 1.024 px): en el celular los productos arriba y la cuenta abajo; en la tablet, lado a lado. Chips
  de categoría, tocar suma, − / + / quitar, VACIAR (`CuentaBarra`), y lo que queda de cada producto (`StockDeLaBarra`). Al abrir VENDER y al
  volver del segundo plano, `ImpresoraBluetooth.reconectar()`. El botón COBRAR lleva a la etapa 5.
- **`esBarra` en `common/widgets/operational_sync_coordinator.dart`:** que lo vendido suba solo.
- **Los tests:** `test/helpers/barra_en_memoria.dart`, `test/barra_pantalla_test.dart` (la pantalla de verdad a 360 y a 1024 px),
  `test/modo_barra_cerrado_test.dart` (ningún camino a cobrar cuotas ni al panel; `sesionCajaIdParaCobro` rechaza a barra) y
  `entrada_operador_test` ampliado. **Y con el mouse**, en `tool/barra_prueba.dart` (nuevo, sin base ni nube): lo visual se termina de probar
  en la ventana de verdad.

**Lo que se habló y quedó decidido el 3-nov:**
- **El catálogo es general, el precio va por fiesta.** El usuario pensaba que el precio era general; se le explicó y dijo "está bien". Si
  después quiere un precio general con cambios por fiesta, se cambia fácil mientras no se publique: las tablas no están en ninguna PC.
- **Una venta anulada no cuenta en el efectivo esperado del cierre** (se supone que la plata se devolvió). Se le dijo y no lo objetó.
- **Lo impreso se mira con foto**: el 2-nov "salió bien" escondía los acentos rotos.

**Para probar la impresora:** `flutter run -d windows -t tool/impresora_prueba.dart` (se conecta sola a la TP-POS58 recordada; TICKET y
CIERRE salen con `ModeloTicket`). Para manejarla con capturas, el permiso es para la ruta entera de
`build\windows\x64\runner\Debug\arguello_events.exe`. La impresora atiende a un equipo por vez: cerrar la ventana de la PC antes de usar
el celular. El APK del celular: ver "El APK para mandar al celular", abajo.

## Etapa 3: las cuentas (3-nov)

Todo puro, sin pantalla ni base, en `lib/features/barra/cuentas/`, y lo que dice cada papel en `impresion/modelo_ticket.dart`:

- **`pesos`**: "$ 7.000", "$ 3.999,99". Las cuentas van **en centavos enteros** (`centavos`): 3 x 1.333,33 da 3.999,99. La de la app
  (`toCurrency`) pone siempre ",00" y no entra en el renglón.
- **`CuentaBarra`**, la cuenta de VENDER: sumar, restar (en cero sale), quitar, vaciar. Cada toque da una cuenta nueva, y cada renglón se queda
  con el precio con que se sumó.
- **`CobroBarra`** y **`PartidoMixto`**, COBRAR: efectivo con lo que entrega y el vuelto (sin anotar lo que entrega, paga justo);
  transferencia con la tilde "Vi el comprobante"; mixto en dos casilleros atados que se corrigen. `falta` dice por qué no se puede confirmar,
  con las palabras de la cajera. **Un test arma la venta con cada cobro que se puede confirmar, y todas cierran.**
- **`NumeroDeTicket`**: "Caja 2 · N° 0017" y el QR `je:barra:<id de la venta>`, que se lee de vuelta (`ventaDelQr`). El "·" sale bien en la
  TP-POS58: es el mismo byte que en la prueba de la 1252 salió así.
- **`CierreDeBarra`**: ventas, mixtas, efectivo, transferencia y **el efectivo esperado: el cambio inicial más lo cobrado en efectivo**.
  **Una venta anulada no cuenta, tampoco en el esperado** (se supone que esa plata se devolvió; decisión del 3-nov, el usuario no la objetó).
  Lo anulado se muestra aparte. `diferenciaEnPalabras`: "Justo, sin diferencia", "Sobran $ 500", "Faltan $ 500".
- **`ResumenDeCajas`**, CAJAS del jefe: cada caja por número con sus cuentas, y los totales; lo contado y la diferencia, de las cerradas.
  **La diferencia es la que se anotó al cerrar**: si el jefe anula después, el cierre no se corrige.
- **`StockDeLaBarra`**: lo cargado menos lo vendido que cuenta, por fiesta. Avisa al llegar al mínimo, y en cero siempre. **No frena la venta**:
  puede quedar negativo. Para el jefe, solo los controlados y los que están en aviso arriba.
- **`fiestasConPrecios`**: las fiestas que la cajera puede elegir, las que tienen algún precio activo.
- **`ModeloTicket.deVenta`** (con la anulada: "*** ANULADA ***" arriba y abajo, con el motivo, sin las gracias) y **`deCierre`** (una caja
  abierta sale sin lo contado). La hora, siempre en Argentina (`ArTime`), y los textos largos partidos por palabras (`partirPorPalabras`).
  Los tests comparan el papel renglón por renglón, a 32 letras.
- **La ventana de prueba** imprime TICKET y CIERRE con `ModeloTicket` y datos inventados. **Salieron bien en el papel** (foto del usuario,
  3-nov): el isotipo, los acentos, las columnas, el QR, la hora y las cuentas del cierre.
- **Al final, 3 renglones en blanco y el pedido de corte solo** (`OpcionesEscPos.avanceAlFinal`, `pedidoDeCorte`). Antes eran 8: 3 nuestros
  y 5 que `Generator.cut` agrega antes de cortar, papel tirado en una impresora sin cortador como la TP-POS58 (se arranca contra la tapa). Con 3,
  lo último impreso sale entero y el blanco entre dos papeles es corto (foto del usuario, 3-nov).

**Tests:** `barra_cuentas_test` y `modelo_ticket_test`. Roturas a propósito vistas en rojo: el cierre contando las anuladas, la
transferencia sin tilde, el mixto que no suma y el stock contando las anuladas. **No probado:** que la hora salga en Argentina en un equipo
con otro huso (esta PC ya está en el de Argentina; la cuenta usa `ArTime`, que no mira el del equipo).

**Lo que la etapa 3 deja para las pantallas:** `EstadoSinInternetBarra` y `PuestaAlDiaBarra` (etapa 4, con la puesta al día de la tablet).

## Etapa 2: los datos (3-nov)

**Cinco tablas nuevas, v77** (`LocalDatabase.crearTablasV77`), y su SQL de la nube, **sin correr**:
`supabase/migrations/20261103140000_barra.sql`.

| Tabla | Id | Para qué |
|---|---|---|
| `barra_productos` | aleatorio | el catálogo, de todas las fiestas; dar de baja es `activo = 0` |
| `barra_precios` | fijo, `UuidUtils.barraPrecioId(fiesta, producto)` | el precio de un producto en una fiesta, con stock y aviso si se controla |
| `barra_cajas` | aleatorio | la caja de barra que abre la cajera en su equipo (no es la de cuotas) |
| `barra_ventas` | aleatorio | una venta; **nunca se edita ni se borra**; los renglones con el nombre y el precio del momento |
| `barra_anulaciones` | fijo, `UuidUtils.barraAnulacionId(venta)` | anular es otra fila: una por venta |

- **Los modelos** (`lib/features/barra/datos/`): `ProductoBarra`, `PrecioBarra`, `CajaBarra`, `VentaBarra` (con `RenglonVenta` y `MedioBarra`) y
  `AnulacionBarra`. **Una venta que no cierra no se arma** (`VentaBarra.nueva`): el total es la suma de los renglones, efectivo más
  transferencia dan el total, el vuelto es lo que sobra de lo recibido, y una transferencia lleva el comprobante visto. Lo leído **nunca tira**:
  unos renglones rotos dejan la venta sin renglones y con sus montos; un medio que esta versión no conoce es `MedioBarra.otro`.
- **Dos interfaces** (`barra_repositorio.dart`): `BarraDelJefe` (catálogo, precios, mirar cajas y ventas, anular) y `BarraDeLaCaja` (abrir,
  vender, cerrar). `BarraLocal` hace las dos sobre la base y la cola; `BarraNube` hace solo la del jefe, directo en la nube, para la web del
  iPhone: **la web no vende**.
- **El número del ticket** sale de `MAX(numero) + 1` de su caja, en la misma transacción que guarda la venta: ocho ventas a la vez dan del 1 al 8.
- **Una caja vive en un solo equipo:** `cajaAbierta` y `abrirCaja` miran solo las de este equipo; tocar dos veces abrir no abre dos.
- **Cerrar la caja** escribe lo contado y la diferencia, y una caja cerrada no se vuelve a cerrar. **Anular** no toca la venta, y anular dos veces
  deja la primera anulación.
- **El sync:** las cinco en `_incrementalColumns` y en la bajada general; cajas, ventas y anulaciones en `_tablasDelCobro` (cada 10 s); productos
  y precios en `_tablasDeCarga` (cada minuto). Prioridad de subida: productos 1, precios y cajas 2, ventas 4, anulaciones 5. Las cinco en
  `_tablasSinRevisarBorrados`, con el motivo. **`SyncEngine.tablasDeLaBarra`** (la fiesta, los operadores con sus permisos, el catálogo y los
  precios) y `bajarParaLaBarra()`, para preparar la tablet en la oficina.
- **La web pagina de a 1000** (una fiesta puede tener más ventas) y **ordena siempre con `ascending: true`**: un test encontró que el paquete
  ordena de mayor a menor si no se le dice.

**La migración sobre una copia de la base real** (`tool/verificar_migracion_v77_test.dart`, 3-nov, con la app cerrada): la base estaba en la v75
(la 6.2.1) y saltó a la 77; las 35 tablas de antes, iguales fila por fila; aparecieron las 7 nuevas (las 2 de los permisos y las 5 de la barra),
vacías; el esquema de lo de antes, igual; se vuelve a la 6.2.1 y de nuevo a la 77 con los mismos datos; y la base real quedó con el mismo SHA-256.

**Tests:** `migracion_v77` (de 75 y de 76 a 77, dos veces, vuelta a la 6.2.1, sin únicos), `sql_v77_coherencia`, `sync_tablas_v77` (con la
bajada de la tablet sobre una nube simulada), `barra_repositorios` y `barra_nube`. Roturas a propósito vistas en rojo: el número repetido,
las ventas fuera del ciclo de 10 s, un CHECK en la nube y un índice único en la PC.

**Decisiones que no estaban en el plan:**
- **Ninguna tabla de la barra va en la limpieza padre-hija de la cola** (`_cleanOrphanQueueEntries`). Esa limpieza saca de la cola las hijas
  de un padre que se borra: con una venta adentro, borrar la fiesta en el equipo perdería una venta que no subió. En la nube no hay clave
  foránea que la rechace, así que sube igual. El plan decía ponerlas.
- **`barra_cajas` lleva `operador_nombre`**: el nombre de la cajera ese día, para el ticket y el cierre aunque después le cambien el nombre.
- **Sin índices únicos fuera del id, también en la PC:** al bajar, la fila entra con `INSERT OR REPLACE`, y un único repetido haría que SQLite
  borre la otra fila sin avisar.
- **Quedan para su etapa:** el depósito `barra` de las fotos y `ImagenDeProducto` (etapa 7, con el catálogo), `esBarra` en el coordinador del
  sync y `PuestaAlDiaBarra` (etapa 4, con la entrada de la cajera), y `subirYa` en cada venta (etapa 5).

**Antes de instalar, el SQL de la barra tiene que estar corrido:** sin las tablas en la nube, cada PC falla al bajarlas en cada ciclo, lo vendido
queda trabado en la cola y **la revisión de la mora no corre** (espera una bajada sin fallas).

## Lo que dio el celular (3-nov, con capturas de su pantalla)

| | En la PC | En el celular Android |
|---|---|---|
| Conectar la primera vez | 1,6 a 2,5 s | 1,5 s |
| Por dónde escribe | el UART de ISSC, sin respuesta | el mismo |
| De a cuánto | 180 bytes | 180 bytes: el MTU se negocia bien, no hizo falta tocar `pedirMtu` |
| Reabrir la ventana | "Conectada sola" en 1,9 s | "Conectada sola" en 0,4 s |

El usuario dijo que las impresiones salieron "un lujo". Las capturas no muestran el renglón de TICKET del celular: que imprimió desde ahí
lo dice él.

## Lo que dio el papel (3-nov, mirado por el usuario, con fotos)

| Prueba | Lo que salió | Lo que quedó |
|---|---|---|
| ACENTOS con la tabla 1252 | **letras raras**: "á" salió "ß", "Ú" salió "┌", "°" salió "░" | descartada |
| ACENTOS, otra vez | con la **tabla 850** todo bien: acentos, ñ, mayúsculas, ¿¡ y "N°" | la 850 (`tabla_850.dart`) |
| ANCHO | las 32 cifras entran justas; el nombre largo se partía "product / o" | renglones partidos por palabras (`renglonesDe`) |
| ANCHO, otra vez | se lee bien, con el importe a la derecha del primer renglón | — |
| QR nativo | se lee con la cámara del celular | queda nativo |
| LOGO | el isotipo (`isotipo-ej.png`, por umbral) se lee mejor que la silueta de `2.png` | el isotipo |

**El 2-nov el ticket "salió entero y bien" según el usuario, y no era cierto en los acentos**: con la 1252 el "N°" y el "¡" salían cambiados, y
recién la foto lo mostró. Lo que diga el papel se confirma con una foto, no con la respuesta a una pregunta.

**Por qué la 850:** las letras raras eran exactamente lo que dibuja la 850 con los bytes de la 1252. La impresora no hace caso del pedido de la
1252 y queda en la 850. `esc_pos_utils_plus` manda el texto en Latin-1 si no se le da otro `codec`: se le pasa `tabla850`, que pone cada
letra del castellano en su lugar de la 850, y se pide la tabla 2 (`ESC t 2`).

## La impresora

Es una **TP-POS58**, de 58 mm, por **Bluetooth de bajo consumo (BLE)**. No hay nada de ella por USB en esta PC. El usuario imprimió desde su
celular con otra app antes de esto, y la app la encontró en esta PC con la búsqueda, sin emparejarla de nuevo.

| Lo que se vio el 2-nov desde esta PC | |
|---|---|
| Búsqueda | la encontró en 10 s; no figura como emparejada para la app |
| Conexión | 1,3 s |
| Por dónde escribe | `49535343-8841-…` (UART de ISSC), sin respuesta |
| De a cuánto | 180 bytes |
| Ticket con logo y QR | 7.897 bytes en 1,05 s, sin error |

**Sin respuesta quiere decir que la impresora no confirma nada:** "impreso" es que la app mandó todo sin error, no que el papel salió bien.
Con trozos de 180 bytes y 20 ms de pausa no perdió ningún renglón, tampoco en el logo (14.503 bytes en 1,9 s): `pausa` queda como está.

## Qué se hizo

- `lib/features/barra/impresion/`: `CanalBle` (la interfaz) y `CanalUniversalBle` (el paquete); `ImpresoraBluetooth` (conectar, trozos, un ticket
  por vez, nunca tira); `elegirCaracteristica` (conocidas primero, nunca las del sistema, así sirve para "lo que se detecte"); `TicketEscPos` (los bytes de
  58 mm); `LogoParaPapel` (silueta y umbral); `textoParaPapel` (un emoji en un producto no frena una venta).
- `tool/impresora_prueba.dart`: BUSCAR, CONECTAR, TICKET, ACENTOS, ANCHO, QR, LOGO y OLVIDAR. Al abrir, si el equipo ya tiene impresora, se
  conecta sola (lo mismo que va a hacer VENDER). Corre en Windows y compila para Android.
- `test/impresora_barra_test.dart`: 27 tests, con 5 roturas a propósito vistas. **Encontró un error antes de la prueba de verdad:** el paquete de imágenes tira con
  un archivo roto, y un logo dañado habría frenado la venta.
- Permisos de Bluetooth en el manifest de Android.

**El 3-nov:**
- **La impresora de cada equipo** (`ImpresoraRecordada`, en `SharedPreferences`, claves `barra.impresora.*`): se elige una vez. Antes de cada ticket
  `ImpresoraBluetooth` mira si sigue conectada y, si no, se conecta a la recordada (`reconectar`, también para VENDER al abrir y al volver del segundo
  plano). Sin ninguna elegida dice `sinImpresoraElegida` sin tocar el Bluetooth; apagada, `noConectada`. En esta PC, reabrir la ventana la conectó
  sola en 1,9 s.
- **Si se corta a la mitad, reconecta y manda el ticket entero una vez más**; si se vuelve a cortar, `fallo`. Puede salir un pedazo repetido: mejor
  eso que un ticket que no sale. La venta se guarda antes de imprimir (lo dice el plan), así que `fallo` nunca pierde una venta.
- **La tabla 850**, `renglonesDe` (32 letras, el importe al borde, partido por palabras) y `LogoDelPapel` con el que va en la app.
- `test/impresora_barra_test.dart` pasó a 50 tests.
- **Android compila:** `applicationId` pasó a `ar.com.junioreventos.app` (no hay nada instalado). `universal_ble` 3.1.0 no aplicaba el plugin de
  Kotlin (espera el Android Gradle Plugin 9; la app usa el 8.11): `android/build.gradle.kts` se lo aplica solo a ese paquete. Sacarlo al pasar al 9.

## Decisiones que no estaban en el plan

- **`universal_ble` queda en la 3.1.0, no en la 3.2.0.** Desde la 3.1.1 pide un `dbus` que choca con `file_picker` 10, que usan otras pantallas. Se mueve cuando se
  actualice `file_picker`. El plan decía 3.2.0.
- **No se tomó nada de la rama `feature/barra-impresora`** salvo la idea de los botones: usaba otro paquete y nunca compiló. Se puede borrar.
- **Se imprimió un solo ticket esa noche.** Los otros botones gastan papel y se deciden mirándolo.
- **Los renglones de un producto no usan las columnas del paquete** (`row` con 8/4): cortaban la palabra a la mitad. `renglonesDe` arma cada renglón
  de 32 letras a mano.
- **El QR queda nativo**, sin la variante como imagen: se leyó a la primera.
- **El APK para mandar al celular** se arma así: `flutter build apk --release --split-per-abi -t tool/impresora_prueba.dart` (36 MB, firmado con la
  clave de prueba de esta PC) y se le sacan los logos de `assets/icons` que la ventana no usa, con zipalign y apksigner de nuevo: queda en 20 MB, bajo el
  tope de 30 MB del chat. El de debug pesa 172 MB. La app entera no se achica así: lleva esos logos.

## Lo que no se comprobó

- **Un corte de verdad a la mitad de un ticket.** El reintento está probado en los tests, no con la impresora. **Si se corta en medio del logo**, la
  impresora puede quedar esperando el resto de la imagen y tomarse el principio del reintento como imagen: saldría una franja rara arriba del ticket
  repetido. Se mira apagando la impresora a la mitad de un LOGO.
- **Una tablet.** Se probó en el celular del usuario; la tablet de la barra todavía no se compró.
- **La app entera en Android.** Lo que compiló es la ventana de prueba; la app con la base, el sync y el login va en la etapa 9.

## Lo pendiente, en orden

**Al 4-nov: la tabla de "Para retomar en otro chat", arriba, es la que vale.** Esto queda como el detalle de cada etapa:
- **5. Cobrar e imprimir:** cobrar, guardar antes de imprimir, subir con internet y los vales, **hechos en la etapa 4**. Falta REIMPRIMIR con
  freno, ANULAR de la cajera, el ticket con precios por Bluetooth y su PDF (58 mm).
- **6. Cerrar la caja:** contado a ciegas, `CierreDeBarra`, `cerrarCaja`, el papel y el PDF del cierre.
- **7. El jefe en la PC:** catálogo con fotos (**las 74 de la biblioteca ya están**; subir una propia necesita el depósito `barra` de Storage,
  con su SQL aparte, y la guardada en el equipo ya está en `imagenDelProducto`), precios con stock y "copiar de otra fiesta", CAJAS
  (`ResumenDeCajas`, el stock con los que están en aviso arriba), anular con motivo, PDF 58 mm y A4, la lista de precios.
- **8. El jefe en la web del iPhone,** sobre `BarraNube`.
- **9. Android con su firma:** la clave la genero yo fuera del repo (`Documentos\Junior Eventos\claves\`), `key.properties` fuera de git, y el
  usuario la copia a un lugar seguro.
- **10. De punta a punta,** sin internet, con modo avión.
- **11. Entradas, etapas 4 a 6** (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`).
- **12. Versión y publicación,** cuando el usuario diga: foto de la mora antes, los SQL nuevos que haya (los de v76 y v77 ya están corridos),
  release de Windows, web y APK firmado, foto después.

**Lo que le toca al usuario:** comprar la tablet cuanto antes, así el APK se prueba en ella desde ya, y copiar a un lugar seguro la clave de firma
cuando exista. **Antes de instalar la app firmada en su celular, desinstalar la ventana de prueba** (`ar.com.junioreventos.app`, con la clave de
prueba): con otra firma no se instala encima.

**Lo pedido el 2-nov que entra en esas etapas:** cada producto con su foto, para que se vea como un buen catálogo · imprimir el catálogo · alerta de stock · imprimir la caja de
cada persona al terminar · la web del jefe entera · entrar con internet baja todo, se trabaja sin internet, y al volver sube solo y el jefe lo ve enseguida · **todo con sus tests.**
