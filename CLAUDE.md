# Junior Eventos / Argüello Events

App Flutter de gestión operativa para eventos: presupuestos, finanzas, recepción
con check-in por QR y un tótem que se proyecta en el salón.

- Paquete: `arguello_events` · versión en `pubspec.yaml` (mantener en sync con
  `installer/junior_eventos_setup.iss`).
- Supabase: proyecto `bucnrydgojyzntgesxqb` (ArguelloApp). Credenciales en
  `lib/main.dart:29-34`.
- Web deployada en `https://arguello-events.vercel.app` (`kWebBaseUrl`). Se publica desde esta PC con la sesión de
  Vercel del usuario: `flutter build web --release`, `build/web` copiado a `.vercel/output/static` con su
  `config.json` (todas las rutas a `index.html`) y `npx vercel deploy --prebuilt --prod`. El detalle, en el punto 6
  de "Lo que falta para publicar" del CONTEXTO de la 6.0.0.

## Antes de tocar nada: la rama

**El desarrollo va en `feature/v4.6-cierre-por-sesiones`, no en `main`.** Esa
rama está ~200 commits adelante y va por la v6.2.0 (publicada el 23-oct; al 23-oct, instalada
en las tres PCs: la casa, el operario y el jefe); `main` quedó en la 2.2.0.
Ramificar de `main` significa trabajar sobre código de hace meses.

**La 6.1.0:** las bajas temporales y el aviso "Revisar la ficha"
(hechos), el salón primero (etapas 1 a 4 hechas), "lejos" medido en el salón, los predios
con nombre (la migración v74 ya probada sobre una copia de la base real) y las muestras de
la etapa 5, en una sola versión. **Publicada el 19-oct** (el SQL de los predios corrido y la
web también). Lo de TOÑANEZ en la PC del jefe quedó resuelto. La mora por cuota suelta (fase 2) quedó descartada.
Entrada: `docs/CONTEXTO_v6.1.0_2026-10-18.md`.

**La 6.1.1** (publicada el 19-oct; al 23-oct, instalada en las tres PCs): lo que se borra a mano en una PC desaparece
también en la otra (ver la trampa "Lo que se borra a mano…", abajo). Entrada: `docs/CONTEXTO_v6.1.1_2026-10-19.md`.

**Las instalaciones las hace el usuario por su cuenta y avisa.** Si un "falta instalar" de acá quedó viejo, lo que
vale es lo que diga él.

**La 6.2.0: "Tu fondo"** (publicada el 23-oct: el SQL de sus columnas corrido, el release y la web; **instalada en
las tres PCs** el 23-oct). La quinta apariencia del tótem: una imagen propia es el fondo. Las novedades
dicen "Nuevas características y detalles". Entrada: `docs/CONTEXTO_v6.2.0_2026-10-23.md`; el detalle,
`docs/PLAN_TU_FONDO_2026-10-23.md`.

**La 6.2.1** (**publicada el 24-oct**: los dos SQL, el release y la web; **instalada en las tres PCs**, confirmado
por el usuario el 2-nov, así que congelar la mora ya se puede): la foto del tótem se saca,
cambia de forma y se agranda; las frases se agrandan; las dos se mueven juntas, con manijas en Personalizar. El
camino a la mesa va en escuadra. La página del celular de la puerta abre sin internet. Y se sumaron tres cosas:
**"Congelar la mora"** (ver "La mora congelada", abajo), **la limpieza** (sin OPERADORES, sin "Restaurar mora", sin
PRESUPUESTOS en Mi Empresa, sin `/op` ni rutas viejas, y código muerto afuera) y **el evento particular que muestra
todo lo de su presupuesto** (detalle de cada servicio, lugar, combos; nunca dos eventos del mismo presupuesto). Las
novedades dicen "Nuevas capacidades en el modo jefe, limpieza". Entrada: `docs/CONTEXTO_v6.2.1_2026-10-23.md`.

**La 6.3.0: el plano antes de los sorteos** (`docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md`; el orden de todo, en
`docs/HOJA_DE_RUTA_2026-11-02.md`). **Publicada el 4-nov** (los dos SQL, v76 y v77, el release y la web), sola y antes que la barra, porque
los sorteos son en noviembre (decisión del usuario). Las novedades dicen "El plano, ordenado para los sorteos". **El mismo día salió la
6.3.1** (`docs/CONTEXTO_v6.3.1_2026-11-04.md`, sin SQL): en ENTRADAS, sin cargo solo las 8 de la mesa del contrato; las de la mesa adicional
y las sillas extra, al 50 %, aparte. **Instalada en las tres PCs (4-nov)**, y la foto de la mora "después" comparada con la de antes: vacía. Entrada: `docs/CONTEXTO_v6.3.0_2026-11-02.md`. Para mirar el plano sin base ni nube: `flutter run -d windows -t tool/plano_prueba.dart`.

**La 6.3.3, publicada el 7-nov a la mañana: la mora adelantada (la 6.3.2) y el sync en reposo, en un solo instalador `6.3.3+65`**
(el usuario dijo "vamos"). Sale de la rama **`release/6.3.x`** (creada desde el tag `v6.3.1`, en la carpeta `..\arguello_events_6.3.x`),
y cada commit va también a esta rama con `cherry-pick`. **Ningún instalador de la 6.3.x sale de la rama feature**: tiene la v78 y cuatro
SQL sin correr. Tags `v6.3.2` (el commit de la mora, sin release) y `v6.3.3`; release de GitHub y web publicados, sin SQL. **Instalada en las tres
PCs el 7-nov**; la foto "después" muestra solo a los 4 del simulacro, y en reposo cada PC le pide a la nube unas 370 cosas por hora
(antes, miles). Cerrada. La barra y Entradas siguen en esta rama para la 6.4.0.
- **Programado el 7-nov, sin publicar, en `release/6.3.x` y acá: cambiar la fecha de un cobro a otro día lo saca de su caja**
  (Mi Empresa → lápiz → Corregir medio de pago; `cajaTrasCambioDeFecha`, `cierre_caja/services/fecha_y_caja.dart`). Regla del usuario:
  esa plata no entró ese día. Una caja cerrada no se toca. Cambia todo el cobro junto (`lineasDelMismoCobro`), sin fechas futuras, y al
  cambiar la fecha o anular se revisa la mora del alumno en el momento. **No sale como 6.3.4 sola: va con todo junto en la 6.4.0**
  (decidido el 7-nov a la noche). Caso: ENRIQUE, MAXIMO, que sigue en la caja del modo jefe del 7-nov hasta entonces. Entrada:
  `docs/CONTEXTO_v6.3.4_2026-11-07.md`, que empieza con "Para retomar en otro chat".
- **Programado el 8-nov (noche), sin publicar: el aviso entre PCs que llega por el socket ya no se tira**
  (`docs/SPEC_pulso_por_el_socket_2026-11-07.md`, `cuerpoDelBroadcast`). Ver "El sync en reposo", en Arquitectura. Sale con todo junto
  en la 6.4.0.
- **La mora adelantada** (entrada: `docs/CONTEXTO_v6.3.2_2026-11-09.md`, que empieza con "Para retomar en otro chat"). La mora cobrada
  por adelantado de una cuota que no se completa se volvía a pedir (LOPEZ, MORENA AILEN: $268.100 en vez de $235.200). El simulacro,
  repetido el 7-nov sobre la base del día: a 4 alumnos les baja la mora, a nadie le sube. Foto "antes de 6.3.3" sacada.
- **El sync en reposo** (`docs/PLAN_SYNC_EN_REPOSO_2026-11-06.md`, con el diseño aprobado al final; entrada:
  `docs/CONTEXTO_v6.3.3_2026-11-06.md`): sin el ciclo de 10 s, el pulso como transporte, red de seguridad de 5 y 30 min, latido
  cada 5 min (7 commits en las dos ramas). La etapa 6 quedó en `docs/pendientes/sync-novedades-en-una-consulta.md`. Ver "El sync en
  reposo", en Arquitectura.

**La 6.3.0 lleva también, dormidos, operadores con permisos** (etapas 1 a 3 de `docs/PLAN_MODO_ENTRADAS_2026-10-30.md`, `docs/CONTEXTO_OPERADORES_2026-11-02.md`)
**y la barra, etapas 1 a 4.** Entradas 4 y 5 están hechas en la rama (8-nov); **no darle Entradas a nadie, ni tildar a nadie como
Encargada de barra, ni crear operadores sin Cobros hasta que las tres PCs tengan la 6.4.0** (la 6.3.x deja anular una entrega, deja
cobrar a quien no tiene Cobros y lee a la encargada como "sin Barra"). Para mirarlo:
`flutter run -d windows -t tool/operadores_prueba.dart`.

**8-nov (noche), en la rama para la 6.4.0: la Encargada de barra, el cierre por sector y probar la impresora** (detalle en el
CONTEXTO de la barra). La encargada es Barra con un 2 en `permisos_operador.barra` (sin SQL): vende con su caja y ve LAS CAJAS
(`widgets/las_cajas_screen.dart`, la vista de CAJAS del jefe), con la llave **`mandaEnLaBarraProvider`** (jefe en modo jefe o
encargada), que solo usa `cajas_de_la_fiesta.dart`; el catálogo y los precios siguen con `esRolJefeProvider`. En una tablet no se
prende la central (`centralSePrendeAcaProvider`). El cierre de caja de hoy, en modo jefe, tiene **COBROS · BARRA · ENTRADAS**
(`cierre_caja/services/sector_del_cierre.dart`): BARRA va por fiesta y solo mira; los movimientos, REGISTRAR RETIRO y los papeles son de
COBROS. "La impresora de este equipo" tiene **IMPRIMIR UNA PRUEBA** (`ModeloTicket.dePrueba`: no es una venta, no se anota) y el
**nombre de cada impresora**, guardado en el equipo. Ventanas de prueba: `tool/cierre_sector_prueba.dart` y `tool/barra_prueba_web.dart`
(la de la barra, para el navegador; Romi 7777 es la encargada).

**En curso desde el 2-nov (noche): la barra** (`docs/PLAN_BARRA_2026-11-03.md`, 12 etapas, aprobado; estado en `docs/CONTEXTO_BARRA_2026-11-02.md`,
que empieza con **"Para retomar en otro chat"**). Las etapas 1 (la impresora), 2 (los datos) y 3 (las cuentas, `lib/features/barra/cuentas/`, y lo que dice cada papel,
`impresion/modelo_ticket.dart`) se cerraron el 3-nov, y también la 4: **la cajera entra con su PIN (`AppRoleKind.barra`, que nunca arma el
panel), elige la fiesta, abre su caja sin cambio ni turno y vende** (`widgets/barra_home_screen.dart`, `vender_screen.dart`, `cobrar_hoja.dart`;
para mirarla, `flutter run -d windows -t tool/barra_prueba.dart`, y con `--dart-define=papel=pantalla` los papeles se ven como texto, sin
imprimir). **La 5 se cerró el 7-nov: VENTAS** (`widgets/ventas_de_la_caja_screen.dart`): las ventas de su caja; **REIMPRIMIR con freno**
(`VentaDeLaCaja`, `cuentas/reimpresion_de_barra.dart`: solo la última, una vez por vale, con motivo, el mismo vale que salió con COPIA),
IMPRIMIR LO QUE FALTA, el TICKET con precios (sin logo) y **ANULAR, también la cajera**, con motivo (`anular` está en `BarraDeLaCaja`).
**Cada vale que sale se anota en `barra_vales`** (v78; solo se agregan filas; la venta no se toca). **La 6 se cerró el 7-nov: cerrar la
caja** (el candado en VENDER, `widgets/cerrar_caja_barra_screen.dart`): **cuenta a ciegas** (ninguna plata de la caja a la vista;
`modo_barra_cerrado_test` lo vigila), confirma, se cierra y recién ahí ve lo esperado, la diferencia y el cierre entero como el papel, con
lo vendido por producto, las sillas y el historial; solo la nota cambia después (`anotarCierre`). **La 7 se programó el 7-nov: el jefe en la
PC** (`lib/features/barra/jefe/`): la tarjeta BARRA en el Centro de Comando, **la fiesta primero** (abre en la próxima; la de anoche sigue al
día siguiente), CATÁLOGO, PRECIOS con el **recargo por fiesta** (`barra_recargos`, v78, cuarto SQL sin correr; cada cobro arranca con ese) y
la lista en 58 mm, y CAJAS con una tarjeta por caja, el stock de la fiesta, y anular y reimprimir cualquier venta; cada guardado pregunta por
el modo jefe, y arriba está el ícono de la impresora de esa PC (`faltaLaImpresora` avisa si nunca se eligió). **Cerrada el 7-nov con el
recorrido con el mouse: `tool/barra_prueba.dart` pone a la cajera y al jefe lado a lado sobre la misma barra en memoria**, y lo que hace
uno le llega al otro como en la app (el detalle y lo que encontró, en "El recorrido de la etapa 7" del CONTEXTO de la barra). **La 8 se
cerró el 7-nov: el jefe en el iPhone.** En la web BARRA lee y escribe directo en la nube por `BarraNube` (también las fiestas,
`BarraNube.eventos()`), con la única llave `enLaWebProvider` (`barra_del_jefe_provider.dart`; las pantallas del jefe no preguntan por
`kIsWeb`, y nunca por el singleton de Supabase: `test/barra_en_la_web_test.dart`). CAJAS se relee sola cada 30 s y al deslizar hacia
abajo (las tablas de la barra no están en Realtime), y sin impresora: quedan los PDF. Para mirarla, `tool/barra_web_prueba.dart` **compilado
como la web de verdad** (`flutter build web -t … --output build/barra_web_prueba` y un servidor estático, `.claude/launch.json`): el compilador
de desarrollo de la web (`flutter run -d web-server`) se cae con este proyecto y deja la página en blanco. **La central de la barra se
cerró el 7-nov a la noche** (`lib/features/barra/central/`; el detalle en "La central de la barra" del CONTEXTO de la barra): **es la
bajada de la nube, pero por la red del salón.** La notebook de la barra la prende desde BARRA → CAJAS; las tablets la encuentran solas
(preguntan por UDP al 8777, la notebook contesta; si el router no deja, la dirección se escribe a mano en VENDER) y se conectan por
WebSocket al 8797-8806 (la puerta usa 8787-8796). Lo que escribe una caja (`barra_cajas`, `barra_ventas`, `barra_anulaciones`,
`barra_vales`) va a la notebook y de ahí a las demás, que lo guardan **sin encolarlo** con `BarraLocal.guardarDeOtroEquipo`, **el único
camino para escribir una fila que no es de este equipo** (no pisa lo que está en la cola; `sync_engine.dart` no se tocó). Al conectarse
o reconectarse, las dos puntas se mandan todo lo de la fiesta: no hay cola de lo no mandado. Cada escritura de la caja pasa por
`BarraConLaRed`, que avisa por `AvisoALaRed` (`test/barra_con_la_red_test.dart` falla si una no avisa). El catálogo, los precios y el
recargo no viajan por la red del salón. **VENDER, la notebook y Recepción dicen "Todo subido" o cuánto falta** (pedido del usuario), y la
cuenta **no corre sola salvo mientras hay internet y algo está subiendo**: se cuenta cuando el equipo escribe (`AvisoALaRed.escrituras`),
cambia la conexión o baja algo. Probarla: `flutter run -d windows -t tool/central_barra_prueba.dart` (dos tablets y la notebook, con la
central de verdad en esta PC).
**La etapa 9 se cerró el 8-nov: la app entera en Android, firmada** (el detalle en "Etapa 9" del CONTEXTO de la barra). **La clave de
firma vive fuera del repo**, en `Documentos\Junior Eventos\claves` (con su `LEEME.txt`; copia en el Google Drive del usuario);
`android/key.properties` la apunta y no va a git. **Nunca a GitHub: el repositorio es público.**
Android solo actualiza la app con la misma clave: perderla obliga a desinstalar de cada tablet. `build.gradle.kts` firma con ella si
existe; **el instalador frena sin ella y comprueba con `apksigner` que el APK salió con "CN=Junior Eventos"**, y deja
`installer\dist\Junior Eventos v<versión>.apk` (arm64) para el release. La tablet se entera de una versión nueva en la pantalla del PIN
(`versionNuevaEnLaTabletProvider`), y DESCARGAR abre el APK en el navegador (`actualizar_app.dart`). En Android la tarjeta TÓTEM se ve
apagada ("Se proyecta desde la PC", `KioskLauncher.disponible`), y VENDER deja la pantalla prendida (`PantallaDespierta`, un canal propio en
`MainActivity.kt`). **Para saber si algo corre en la tablet se pregunta por `Platform`, no por `defaultTargetPlatform`: en `flutter test`
dice siempre Android.** Probado en el emulador `Recepcion_Tablet` (sin ventana y con `-gpu host`: con `swiftshader` se cae al abrir la app):
`tool/tablet_barra_prueba.dart` como APK, la central de verdad en esta PC y la tablet conectada a `10.0.2.2:8797` por `ws://`: la venta
llegó a la notebook y la anulación volvió; la app de verdad abrió hasta el login. **La etapa 10 se cerró el 8-nov con el
celular Android del usuario y el router de su casa**: conectado a la central de esta PC por el wifi, la TP-POS58 desde Android y sin la
fibra, "todo ok". Queda repetirlo con la tablet y el TP-Link del salón cuando estén, sin código.
**Entradas 4 y 5, programadas el 8-nov (noche), sin publicar** (detalle, las roturas y lo que no se comprobó en "Para retomar en otro chat" de
`docs/CONTEXTO_OPERADORES_2026-11-02.md`): la entrega desde Entradas abre `RetiroEntradasScreen.mostrador`, sin cobrar ni editar; los
botones de cada uno los decide `PermisosDeEntrega`; la familia que debe va a "En caja" (`enCajaProvider`, en memoria) y cuando el pago
baja salta "pagó: ya podés entregar" con sonido; **anular una entrega es solo del jefe, también en la oficina**. Probar:
`flutter run -d windows -t tool/entradas_prueba.dart`. Queda para la instalación: el sonido y la entrega en dos PCs de verdad.
**La barra vende con la app en cada tablet, no
por QR como la puerta, y la central de la barra sigue en pie** (decidido el 7-nov). **Lo que
se imprime en la barra ahorra papel: sin logo en vales, copias, ticket ni cierre, y el ticket sin QR** (pedido del usuario, 7-nov). **Los
PDF de la barra son de 58 mm, una sola hoja larga, nunca A4** (`PapelPdf`; en pantalla, `PapelEnPantalla`: la misma lista de líneas que va
a la impresora). **Debajo del total, EFECTIVO · TRANSFERENCIA · MIXTO; transferencia
es todo lo de Mercado Pago, sin comprobante que tildar; el recargo por transferencia va sobre lo transferido** y la venta lo guarda aparte
(`recargo`: `efectivo + transferencia = total + recargo`). **Las cuentas van en centavos enteros** (`centavos`), y **una venta
anulada no cuenta, tampoco en el efectivo esperado del cierre**. **El papel de cada compra es un vale, no el ticket** (pedido del jefe, 3-nov,
el "3b"): sin logo, sin precios y sin QR, TODO JUNTO o POR SEPARADO (cada vale armado a mano con su "vale por" hasta que no quede nada: `widgets/elegir_vales.dart`), uno por papel, en letras
grandes (`GrandeTicket`), y **el barman se lo queda**: ese es el control, junto con la fiesta y el día impresos y la COPIA marcada. **La silla de la
noche es otra cosa** (6-nov): un producto con "silla" en el nombre (`esSillaDeLaPuerta`) sale aparte, **un vale por silla** con su número, y su pie dice
"Llevá este vale a la recepcionista · Ella suma la silla y se queda el vale" (ver "Las sillas de la noche" en El tótem). La app ya imprime
por Bluetooth desde la PC y desde un celular Android (`lib/features/barra/impresion/`, `flutter run -d windows -t tool/impresora_prueba.dart`), pero todavía no tiene pantallas de barra.
**Los datos** son cinco tablas de la v77 (`barra_productos`, `barra_precios`, `barra_cajas`, `barra_ventas`, `barra_anulaciones`), con su SQL
`supabase/migrations/20261103140000_barra.sql` **sin correr**, y viven en `lib/features/barra/datos/`: `BarraDelJefe` (PC y web) y `BarraDeLaCaja`
(solo en el equipo: la web no vende). **Una venta nunca se edita: anular es otra fila.** El número del ticket es por caja, en la misma
transacción, y una caja vive en un solo equipo. Ninguna tabla de la barra va en la limpieza padre-hija de la cola: perdería una venta sin subir.
**En `BarraNube`, `order` va siempre con `ascending: true`:** el paquete ordena de mayor a menor si no se le dice. La impresora es una **TP-POS58 por BLE**, y la escritura va
sin respuesta: "impreso" no dice que el papel salió bien, hay que mirarlo, **con foto** (el 3-nov el "salió bien" escondía los acentos rotos). Lo que dio
el papel está en `OpcionesEscPos.deLaPrueba`: **los acentos van con la tabla 850** (`tabla_850.dart`; con la 1252 salen letras raras), 32 letras por
renglón (`renglonesDe` parte por palabras), QR nativo y el isotipo. La impresora se recuerda por equipo (`ImpresoraRecordada`) y se conecta sola.
`universal_ble` queda en la 3.1.0 (la 3.1.1 choca con `file_picker` 10), y para que compile en Android `android/build.gradle.kts` le aplica el plugin de
Kotlin (espera el Android Gradle Plugin 9). El `applicationId` de Android es `ar.com.junioreventos.app`. **VENDER tiene dos diseños** (Noche dorada y Mostrador, `estilos/disenio_barra.dart`; cada
equipo recuerda el suyo) **y las fotos de los tragos y las marcas vienen adentro de la app** (`assets/barra/`, 74): cada producto toma la suya por el nombre
(`FotoDeLaBarra.para`: primero lo que se toma, después la cerveza sin marca, al final lo sin alcohol). **Una foto nueva lleva su renglón en
`docs/FOTOS_DE_LA_BARRA.md`** (autor y licencia; un test lo exige), y solo de fuentes libres: nunca de páginas de marcas ni de supermercados.
**Después de la barra, Entradas 4 a 6, y se publica todo en una**, **sin apuro de fecha** (6-nov: "cuando salga nomás, ahora hay más
tiempo"), preguntando. **La 6.4.0 se publicó el 9-nov a la madrugada, con el usuario** (la foto de la mora "antes de 6.4.0", los
cuatro SQL con los conteos iguales, el release `v6.4.0` con el Setup y el APK, y la web). **Instalada en las tres PCs (lo confirmó el
usuario el 10-nov); falta la foto de la mora "después de 6.4.0"**, que es el paso 0 de publicar la 6.5.0. Antes de eso estaba todo programado y probado (27 de 28, 96 %, con la encargada y el cierre por sector). Lo que lleva, la revisión de bugs y el paso a paso: "Para retomar en otro chat" de
`docs/CONTEXTO_v6.4.0_2026-11-06.md`. Lo de antes de publicar quedó hecho el 8-nov: la migración v78 sobre una copia de la base real
(con `barra_recargos`, SHA-256 igual; repetirla si pasan días), el aviso entre PCs contra la nube y **PAPEL con la TP-POS58: contesta**
(con rollo "hay", sin rollo "no hay"), así que el aviso de papel de VENDER sale de verdad.

**La 6.5.0, programada el 9 y el 10-nov, publicada el 10-nov** (`docs/CONTEXTO_v6.5.0_2026-11-09.md`, que empieza con "Para retomar en otro
chat": ahí está lo hecho, **lo que quedó sin probar** y el paso a paso; el plan del 9-nov, `docs/PLAN_PUERTA_PLANO_Y_SORTEO_2026-11-09.md`).
Sin SQL. **PUBLICADA el 10-nov** (tag `v6.5.0`, release con el Setup y el APK, web en Vercel), con las fotos de la mora "después de
6.4.0" y "antes de 6.5.0". **Falta que el usuario instale las tres PCs y la tablet; después, con la app cerrada en las tres, la
corrección de una ficha (etapa 12 del CONTEXTO, `build/corregir_mora_10nov_6.5.0.sql`) y la foto "después de 6.5.0".** El chat con la
barra (cajeras y encargada con solapas, un puente entre las dos notebooks) lo pidió y **lo dejó para después**:
`docs/pendientes/chat-con-la-barra.md`. Lleva:
- **la Encargada de barra entra con su PIN desde la web del iPhone** (etapa 10): en la web el PIN se le pregunta a la nube
  (`operadorPorLaNube`; **en la nube `operadores_caja.activo` es booleano**), entra solo la encargada (`OpcionesDeEntrada.de(enLaWeb:)`)
  y ve las fiestas y LAS CAJAS (`BarraHomeEnLaWeb`). No vende ni imprime;
- **el inicio y el cierre de caja en un celular** (etapa 11): en el inicio, el título corto y los botones en un menú
  (`encabezado_del_inicio.dart`); en el cierre, un renglón por cosa;
- **el modal del cobro se cierra apenas el pago queda guardado** (`DespuesDeGuardarCobro`, `cerrarRuta`): lo de después no lo frena ni
  dice "Reintentá", y lo que falla queda en `cobros_despues_de_guardar.txt`;
- **la recepcionista ve el plano** en su pantalla (VER EN EL PLANO, VER LA LLEGADA, "Ver el plano entero"; `SalonParaLaPuerta`), sin
  que la tele se entere; el celular lo recibe de la notebook;
- **sillas sueltas** (`sillas_puerta.mesa = 0`, ver "Las sillas de la noche");
- **el chat de la puerta** (ver "Los celulares de la puerta");
- **las mesas de más van lejos y el jefe elige dónde** (ver "El sorteo sobre el plano");
- **la planilla del sorteo sale parada** (10-nov): el cartel pregunta "La hoja: Parada · Acostada", con Parada elegida
  (`PlanillaSorteoPdf.construir(vertical:)`). Acostada, en una impresora puesta en vertical, salía a media hoja o cortada. Los grises y
  las líneas de `PlanillaTema` van más oscuros. La de entrega y el plano siguen acostados. La impresora de la oficina es una Epson L495;
- **el recibo de un evento particular sale entero** (10-nov, `PdfService._buildDocument`, `construirReciboParticularPdf`): ver la trampa
  "En una fila de un PDF…", abajo;
- **una mesa del plano se reserva para quien no es alumno** (los profes, 10-nov): ver "La mesa reservada", en El salón;
- **los profes aparecen en Recepción y el tótem los saluda con su mesa** (10-nov): ver "Los que se sientan en una mesa reservada", en El
  tótem.
**No crear "Silla suelta" en el catálogo, ni usar SILLA SUELTA, ni reservar una mesa con "Es para alguien" hasta que las PCs y las
tablets tengan la 6.5.0.**

**Antes de la barra 5 (5 y 6-nov): el tótem con el salón y las sillas de la noche, hechos en la rama** (`docs/PLAN_TOTEM_SALON_Y_SILLAS_2026-11-05.md`;
lo de las sillas en **`docs/CONTEXTO_v6.4.0_2026-11-06.md`**, el tótem en `docs/CONTEXTO_TOTEM_SALON_Y_SILLAS_2026-11-05.md`). **El tótem:** en
un masivo sorteado la tele muestra el salón entero y claro (`CuadroDelSalon`, `temaPlanoDelTotem(claro: true)`); el nombre salta en grande y
se acomoda **en la pista, resumido** (`ResumenEnElSalon`), con la mesa encendida, el camino y el borde que late (`PanelPlano.pulsar`); **con
cola no se acorta** (`TiemposDeBienvenida`); los segundos y el lugar se eligen en Personalizar ("LA LLEGADA") y se cambian a mano esa noche con
el reloj de Recepción (`TiemposAMano`, vive en la PC, viaja por `tiempos_totem` y en la ficha). SQL `20261105100000_totem_config_llegada.sql`
**sin correr**. **Las sillas de la noche (6-nov):** desde los sorteos (10-nov) una silla más se pide solo esa noche (**mesas, nunca esa
noche**); **la recepcionista no toca plata**: la barra la cobra como producto y da un vale, y la puerta la anota con el número del vale en
`sillas_puerta` (v78, filas que solo se agregan; quitar deja la huella con motivo). En la oficina, con la fiesta sorteada, no se suman sillas
extra al contrato salvo en modo jefe. Ver "Las sillas de la noche" en El tótem. SQL `20261105120000_sillas_puerta.sql` **sin correr**; la
prueba de punta a punta quedó hecha en el sandbox el 6-nov (`tool/puerta_sandbox_test.dart`).

**Las pruebas de punta a punta las hace Claude, en un sandbox, y se asegura de que salgan bien** (regla del usuario, 6-nov). Aisladas:
los arneses `tool/*_prueba.dart` en memoria, sin la base real ni la nube; el navegador de la app con pestañas que hacen de celulares.
Nunca contra `Documentos\Junior Eventos\data.db` ni contra Supabase. No se le pide al usuario que pruebe: queda para él solo lo que
necesita un aparato físico (la impresora, un celular en el router del salón) o su OK. Publicar se propone recién con la prueba hecha.

## Documentación del proyecto

Hay convenciones propias, y conviene respetarlas antes de inventar otras:

- `docs/CONTEXTO_<version>_<fecha>.md` — qué se hizo en cada release y por qué.
  El más reciente es el mejor punto de entrada al estado actual.
- `docs/pendientes/` — trabajo **ya decidido** que se postergó. Un archivo por
  pendiente, con estado, fecha y —lo importante— **por qué** se postergó.
- `docs/ideas/` — lo que capaz nunca se hace. No confundir con pendientes.
- `tool/` — scripts de diagnóstico y arreglo puntuales (`recalcular_contrato.dart`,
  auditorías de mora, reconciliaciones). Muchos son de un solo uso pero
  documentan incidentes reales.

Los mensajes de commit describen el efecto para el usuario, no el cambio
técnico: "el perdón de mora ahora cruza entre las dos PCs", no "fix sync".

## Arquitectura

**Offline-first.** SQLite local (`lib/core/database/local_database.dart`, va por
la versión 78 en la rama, con `sillas_puerta` y `barra_vales`; las PCs tienen la 77) es la fuente de verdad del escritorio; los cambios se encolan en
`_sync_queue` y suben a Supabase cuando hay red. La web va directo a Supabase.

- Escritorio/móvil: `InvitadosRepository` (SQLite + cola de sync).
- Web sin usuario (la página del QR): `SupabaseInvitadosRepository`, que **no
  lee la tabla**: busca y anota por funciones de la nube (ver "La lista de la
  puerta, cerrada a los anónimos", abajo).

**El sync en reposo** (6.3.3; `docs/CONTEXTO_v6.3.3_2026-11-06.md`). **En reposo, la app no le pide nada a la nube.** Hasta la
6.3.2 el coordinador bajaba 16 tablas cada 10 s haya o no novedades: unas 7.500 consultas por hora por PC, el 95 % de lo que la app
le pedía a la nube (plan Free, instancia Nano). Ahora:
- **Lo que corre solo vive en el motor (`SyncEngine`), no en una pantalla:** la subida a los 2 s de guardar, sus reintentos con
  espera creciente (`esperaCreciente`: 30 s, 1, 2, 5 min, y 5 para siempre; para cualquier rol), el pulso, y **la red de seguridad**:
  lo del cobro cada 5 minutos (con la cuenta de borrados), lo de carga cada 30. Si alguien bajó todo hace menos de un minuto, la
  vuelta se saltea. `OperationalSyncCoordinator` ya no tiene reloj: baja al abrir (`bajarAlArrancar`), al volver a la ventana si
  pasó más de un minuto (`bajarAlMirar`), y refresca las pantallas **solo cuando bajó algo nuevo** (`cambiosBajadosStream`, que
  además invalida la proyección de Finanzas). Un test lee el coordinador y falla si vuelve un `Timer.periodic`.
- **El pulso es el transporte:** un aviso que llega con la PC ocupada se guarda y se atiende a los 3 s (antes se tiraba); si el canal
  estuvo caído más de 20 s, al volver se baja lo del cobro; sin red, lo atiende la vuelta de la red. **Una sola bajada a la vez**:
  atender el aviso marca al motor ocupado.
- **Vuelve la red** (de `offline` a `online`): primero sube lo que esperaba y después baja lo del cobro (y lo de carga, si nunca bajó).
  Es el caso de cobrar en el campo sin internet.
- **Sin ping antes de bajar o subir:** la primera tabla hace de ping. **Una nube caída (`esCaidaDeLaNube`) no se le cuenta a la
  fila**: no suma intentos ni la deja "trabada"; se corta la pasada y se reintenta. El motor no se frena esperando que alguien
  diga que la nube volvió: la próxima vuelta lo prueba con un solo pedido.
- **El latido de la caja, cada 5 minutos** (`kLatidoSesionPeriodo`; en uso hasta 11, sin señales después de 20: van juntos,
  `test/latido_sesion_test.dart`). Avisa a la otra PC marcado `latido: true`, que baja `sesiones_caja` sin refrescar pantallas.
- **Los relojes del motor pasan por `RelojDelMotor`**; las pruebas le pasan `RelojDePrueba` (`test/helpers/`), nunca `fake_async`
  (el motor hace I/O real). `test/sync_en_reposo_test.dart` cuenta, con `NubeDePrueba`, qué pide el motor en cada momento.
- **Un comentario que diga "el ciclo de 10 s lo cubre" está viejo.** El tope de un borrado o un cambio cuyo aviso se perdió pasa de
  10 s a 5 minutos (antes de cobrar se baja todo igual).
- **Un broadcast llega con dos formas, y se lee siempre con `cuerpoDelBroadcast`** (`core/services/cuerpo_del_broadcast.dart`; en la
  rama desde el 8-nov, sale en la 6.4.0; `docs/SPEC_pulso_por_el_socket_2026-11-07.md`). Por el socket, la librería manda los datos
  sueltos (`{origen, tablas, …, type, event}`); por REST, el servidor los envuelve en `payload`. Hasta la 6.3.3 `_alRecibirPulso` y el
  tótem de la web leían solo `payload`: lo del socket, que es casi todo, se tiraba sin error (lo tapaba el ciclo de 10 s), y en las PCs
  lo nuevo de la otra llega al volver a la ventana, antes de cobrar o con la red de 5 minutos hasta instalar la 6.4.0.
  **Ningún aviso nuestro lleva una clave `payload`**, y **las pruebas del pulso van con las dos formas**
  (`test/pulso_por_el_socket_test.dart`, que también falla si vuelve `payload['payload']`). La forma cruda que manda la nube no se
  probó contra Supabase (`tool/pulso_prueba.dart`, sección 7.9 del SPEC, pide el OK del usuario): se comprueba con los registros
  después de instalar (sección 9).

**Rutas por URL en web** (`lib/main.dart:80-130`): se detectan con `contains()`
sobre `Uri.base`, no con path parsing.

| URL | Pantalla | Login |
|---|---|---|
| `?cotizar` | Catálogo público | No |
| `?totem&evento=<id>&clave=<k>` | Tótem (el link, con la clave, sale de Personalizar tótem) | **No** (deliberado: se proyecta desde una smart TV) |
| `/lista?evento=<id>` | Lo que ve el invitado al escanear el QR: busca su nombre y entra con su DNI | No |
| `?buscar&evento=<id>` | La misma página que `/lista` | No |

`/op` y las rutas internas `/operador` y `/recepcion_unified` se sacaron en la 6.2.1 (la segunda abría Recepción en la
web sin pedir usuario): `/op` cae en el login. `test/puerta_cerrada_test.dart` vigila que no vuelvan.

**Ventana secundaria de escritorio.** El tótem nativo corre en otra ventana vía
`desktop_multi_window` (`KioskLauncher`). Esa ventana **no** inicializa el
singleton de Supabase (crashea `app_links`): crea un `SupabaseClient` propio y lo
inyecta con `supabaseProvider.overrideWithValue(...)` (`main.dart:48-64`). Por eso
**todo provider que use Supabase debe leer `supabaseProvider`, nunca
`Supabase.instance`**, si va a correr en el tótem.

Comunicación entre ventanas: `DesktopMultiWindow.invokeMethod` con los métodos
`refresh`, `list_reset`, `guest_checkin`, `guest_removed`.

## Roles y permisos

Solo dos roles en `perfiles.rol`: `Admin` y `Asesor`. La única comparación de rol
de toda la app está en `user_role_provider.dart:66`.

- Admin → `DashboardScreen`, con `UserPermissions.admin()` (todo en true).
- Asesor → `AsesorHomeScreen`, con flags granulares de `permisos_usuario`
  (`puede_eventos`, `puede_totem`, `puede_recepcion`, …). Cada flag prende o
  apaga una tarjeta del menú.

**Desde la 6.2.1 no se asignan desde la app:** la pestaña OPERADORES de Mi Empresa se sacó (no había asesores en
uso: una sola cuenta, sin entrar desde abril). Los permisos siguen en la nube (`permisos_usuario`) y
`AsesorHomeScreen` los lee; para darlos, SQL o volver a poner la pestaña (está en la historia de git).

**Los operadores tienen otros permisos, que no son esos** (sin publicar): Cobros, Entradas y Barra, en la tabla aparte `permisos_operador` (v76), y en
`permisos_operador_cambios` quién dio o sacó cada uno. Los carga el jefe en OPERADORES (`operadores_caja_screen.dart`, con doble llave).
- **Sin fila, es de Cobros solo (`PermisosEfectivos.de`); con fila en cero, no tiene permisos.** Son dos cosas distintas: así Maxi y Juan siguen igual, sin
  volver a darles nada. Guardar sin cambiar nada no escribe.
- **Un PIN y se despliegan las opciones** (`OpcionesDeEntrada`, en `RoleGateScreen`). `buscarOperador` baja de la nube un PIN que no está en esta PC, antes de
  decir que es incorrecto. Barra entra a `BarraHomeScreen` (`entrarComoBarra`, sin caja de cuotas ni latido; `test/modo_barra_cerrado_test.dart`).
- **`destinoDeEntrada` decide la pantalla, y con `AppRoleKind.entradas` nunca arma el panel:** va a `EntradasHomeScreen`, sin camino a cobrar ni a editar
  (`test/modo_entradas_cerrado_test.dart`). `sesionCajaIdParaCobro` lo rechaza.
- **De la caja a Entradas, la caja queda abierta y latiendo.** Entrar directo a Entradas no abre ni mira ninguna caja.
- **Encargada de barra (6.4.0) no es una puerta más:** es Barra con un 2 en la misma columna (`PermisosEfectivos.encargadaBarra`;
  `PermisoOperador.deEntrada` son las tres de siempre). Entra por BARRA (`AppRoleState.esEncargadaDeBarra`), y el registro anota
  `encargada_barra`. **Una pantalla nueva que deje anular o ver todas las cajas de la barra pregunta por `mandaEnLaBarraProvider`**,
  nunca por el rol a mano (`test/solo_modo_jefe_test.dart`).

**Ojo:** hay un segundo concepto de "admin" totalmente independiente, por PIN
local (`admin_provider.dart`, PIN maestro `2026`, TTL 3 min), que gatea Mi
Empresa. No se cruza con el rol de Supabase.

**El rol se cachea** (`user_role_cache.dart`) y hoy solo se invalida al cambiar
de sesión (`main.dart:567-576`), así que un permiso recién asignado no se ve
hasta re-loguear.

**Lo que cambia el salón, solo en modo jefe** (v6.0.0). Armar y personalizar el plano, sortear, deshacer, restaurar,
cambiar o mudar familias y escribir el "N° de mesa" de Editar alumno piden modo jefe (`esRolJefeProvider`, en
`caja_sesiones/providers/app_role_provider.dart`; no hay PIN nuevo). Sin él se ve, se imprime y se entrega.
- **Lo bloqueado se ve, apagado y con el motivo** (`kSoloEnModoJefe`, en `common/utils/solo_jefe.dart`). Si
  desapareciera, el operario no sabría que existe ni a quién pedírselo.
- **Doble llave:** los botones, y `_frenaSinModoJefe()` al principio de cada función que guarda el salón, en
  `detalle_evento_masivo_screen.dart` y `plano_evento_screen.dart`.
- `test/solo_modo_jefe_test.dart` lee esas dos pantallas y falla si aparece un guardado del salón sin la llave.
  **Un guardado nuevo del salón tiene que llevarla.**

## El salón: plano, sorteo y entradas

Todo lo de la v6.0.0 está en `lib/features/plano/` (`modelo/`, `dibujo/`, `estilos/`, `services/`, `widgets/`) y se
abre desde la barra de la fiesta (`GrupoFiestaToolbar`: PLANO, SORTEO ▾, PLANILLAS ▾ y ENTRADAS, al lado de MÁS).
El detalle de cada parte, con sus decisiones, está en `docs/CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26.md`.

**Cinco tablas nuevas, todas aparte** (ver la primera trampa de abajo): `sillas_reparto`, `entradas_retiro` y
`sorteos_mesas` (v72), `planos_evento` y `mesas_movimientos` (v73).
- `planos_evento`: una fila por fiesta, con id fijo. Lleva la copia del armado (`armado_json`) y, en `config`
  (JSON en texto), las mesas fijadas y libres, los bloques, los colores, los textos y las medidas.
  **La fila sube entera**, así que antes de sortear, deshacer o restaurar se lee el plano de la nube
  (`leerPlanoParaSortear`): con el de esta PC se pisaba lo que la otra acababa de cambiar.
- `sorteos_mesas` y `mesas_movimientos`: **solo se agregan renglones**. Deshacer es otro renglón, nunca un borrado.
- **No agregar un valor a `sorteos_mesas.tipo`:** el SQL de la nube lo limita a `sorteo`, `deshacer` y `restaurar`.
  Lo nuevo del registro viaja adentro del texto `resultado`, con claves que empiezan con guion bajo (`_antes`,
  `_quedan`); una clave así que la versión no conoce se ignora.

**El sorteo sobre el plano no toca el motor.** `SorteoConPlano` le arma las entradas y traduce la salida. Lo único que
le pasa es `OrdenLejos`: en qué orden probar las candidatas de una mesa "lejos" (cerca, a unas mesas, bien lejos), sin sacar
ninguna. Por eso lo que entra no depende de esa opción.
- **El sorteo no recorre las mesas por número.** `CasillerosPlano` las pone en fila: primero las comunes, por
  número, y **el pasto al final**; en cada corte (otra hoja, mesas sueltas, un número que no existe) mete un
  casillero fantasma, siempre ocupado, para que una familia no quede a los dos lados.
- **Por eso el bloque de una división es su lista de mesas, no un rango.** `BloqueDivision.mesas` es la lista
  exacta; `desde` y `hasta` son solo el número más bajo y el más alto. **Para saber si una mesa es del bloque se
  pregunta con `contiene`, nunca comparando números.** En Técnica el pasto va del 131 al 150 y una mesa agregada a
  mano lleva el 151: el bloque "121 a 151" no tiene ninguna mesa del pasto. El texto sale de `texto()`, por tramos
  ("121-130 y 151").
- **Las familias que reciben una mesa fijada van aparte**, por división y con toda la escuela junta: se quedan con
  su fijada y, si les falta otra mesa, se les da pegada a esa. Si entran en la cuenta de "hasta qué mesa", una
  fijada lejos estira el salón y las demás caen repartidas hasta ahí.
- **"Sortear a los que faltan" es el mismo botón SORTEO**: completa sin mover a nadie. `UltimosSorteados` y
  `LoQueSeDeshace` (`ultimos_sorteados.dart`) dicen quiénes son los del último sorteo y qué pasa al deshacer solo
  ese. Una familia se revierte solo si hoy tiene exactamente lo que ese sorteo le dejó.
- **Con familias con mesa, el número de una mesa que se sacó y se guardó no se vuelve a dar** (`ArmadoSalon.ultimoNumero`):
  ya pudo salir impreso.
- **Sin familias con mesa, los números se ordenan solos al guardar** (`EditarArmado.paraGuardar`, con
  `ArmarAMedida.ordenarNumeros`; `ultimoNumero` vuelve a N). Las mesas no se mueven. Las fijadas, las libres y los
  bloques siguen a su mesa (`conNumerosNuevos`). No en un armado del Canva, ni **sin internet**: esa PC no puede saber si
  la otra ya sorteó.
- **La barra de Acomodar depende del momento** (`SesionAcomodo.barraReacomoda`): sin familias con mesa y con el borde del
  playón, "Distancia entre mesas", que reacomoda en vivo con la misma cuenta de ACOMODAR LAS MESAS y al guardar pasa a Medidas;
  si no, "Separar o juntar", que estira sin cambiar ninguna mesa.
- **Juntas y separadas se dibujan sin dato nuevo** (`PlanoDeLaFiesta.familias`, con `tramosPegados`), en pantalla y en papel, y
  nunca solo con un color.
- **"Lejos" se mide en el salón dibujado, igual que "juntas"** (6.1.0). Para el motor, lejos es "no en casilleros
  seguidos", y en el salón dos mesas no seguidas pueden tocarse: en el sorteo por división quedaban así entre el 4 % y
  el 8 %.
  - `_sortearEn` vuelve a sortear el tramo hasta que cada mesa lejos no toque a su familia (`lejosEnElSalon`, con
    `pegadas`).
  - `validar` lo revisa, y `preparar` dice que no entra si en ese salón no hay manera.
  - `test/sorteo_lejos_en_el_salon_test.dart` lo prueba con 60 sorteos por salón y modo.
- **Las mesas de más van lejos, y el jefe elige dónde** (6.5.0). En el cartel del sorteo, una familia con más de
  `kMesasJuntasEnElSorteo` (3) mesas viene tildada sola, con las de más separadas. **"Donde yo elija"**
  (`DistanciaLejos.enLaZona`) abre `ElegirZonaDialog` encima del cartel para tocar mesas libres.
  - Con zona, sus candidatas van primero (`_ordenLejos`), aunque estén fuera de "hasta qué mesa" (`fueraDelRango` en el motor).
    Si la zona se llena o toca a la familia, va lo más lejos que se pueda, con aviso.
  - La mesa comprada después del sorteo también se puede pedir lejos: `completar` la saltea y va como suelta.
  - Con dos familias con lejos en un salón justo, `_minimaConLejos` busca unas mesas más en vez de decir que no entra.
  - La zona va en el registro con la clave `_zonas` (`test/sorteo_zona_elegida_test.dart`).

**El salón primero** (6.1.0, en curso; `docs/PLAN_SALON_PRIMERO_2026-10-16.md`): el jefe arma primero el espacio
vacío y después pone las mesas con un botón.
- **El salón vacío** es `ArmarAMedida.vacio` (clave `vacio@1`): el borde, el escenario y el Ingreso, sin mesas.
- **Las mesas las pone `ArmarAMedida.acomodar`**: dentro del borde de cada hoja y sin pisar ningún sector salvo la
  pasarela. **Sobre el mismo playón tiene que dar lo mismo que `armar`, mesa por mesa:** un test lo compara, así que un
  cambio a una de las dos cuentas va en las dos.
- **El escenario es un sector como los demás:** `conPlayon` ya no lo ata al frente.
- **No agregar claves al JSON del armado:** la 6.0.0 lo reescribe entero y las perdería
  (`test/salon_convivencia_test.dart`).
- **La primera vez, Estilo y armado viene con el salón vacío** (salvo familias ya sentadas sin plano: ahí apagado,
  con el motivo).
- **Un plano sin mesas se lee:** `PlanoEvento.armadoONull` da null solo si el armado no tiene hojas. **La 6.0.0 lo
  toma por roto** (no sortea, el tótem va sin plano, PLANO ofrece elegirlo de nuevo): el plano se toca desde una PC
  con la 6.1.0. Quien use el armado tiene que aguantar cero mesas.
- **SORTEO no sortea un salón sin mesas** (`LecturaPlano.problemaParaSortear`, las dos veces que lee el plano;
  `test/plano_para_sortear_test.dart` lee la pantalla de la fiesta). Deshacer no lo mira.
- **Las manijas** (etapa 3): dónde van y cuál hay bajo el dedo, en `ManijasPlano` (`services/manijas.dart`); lo que
  hacen, en `EditarArmado` y `SesionAcomodo`.
  - **Sobre el piso vacío se elige el playón sin agarrarlo**: arrastrar ahí mueve la vista con el plano acercado. Se
    mueve entero con la manija del medio.
  - **Mientras se arrastra, el dibujo se queda con la caja de la hoja del momento de apretar**
    (`_conCajaQuieta`): si la hoja crecía en cada paso, lo agarrado corría más rápido que el mouse.
  - Al guardar un playón cambiado a mano, las medidas guardadas lo siguen (`conMedidasDelPlayon`).
- **ACOMODAR LAS MESAS y VACIAR EL SALÓN** (etapa 4, `SesionAcomodo.acomodar` y `vaciar`): solo sin familias con mesa
  y con el borde del playón (no en un armado del Canva).
  - **Un salón sin mesas se guarda siempre**: lo que no se hace sin mesas es sortear.
  - **`SesionAcomodo.rehecho`** viaja con cada paso de Deshacer. Si está, al guardar (`paraGuardar(rehecho:)`) se
    quitan las fijadas, las libres y los bloques, porque sus números quedaron en otro lugar; el panel lo avisa antes,
    con los nombres.
  - El panel de Acomodar es un `SingleChildScrollView`, no un `ListView`: lo de abajo existe aunque no se vea.
- **Los predios con nombre** (6.1.0, sección 14 del plan): el espacio de un lugar (playón, sectores, Ingreso, sin
  mesas) guardado con nombre desde Acomodar (GUARDAR COMO PREDIO…) y elegido en Estilo y armado de otra fiesta.
  - **Tabla aparte `predios` (v74)**, de todas las fiestas. **Borrar le pone `borrado_at`: la fila no se saca** (no
    va en `_tablasAReconciliar`). Las reglas, en `PrediosDelSalon`; el repositorio que guarda lo usa solo la
    pantalla del plano (`test/solo_modo_jefe_test.dart`), y quien lee entra por `leerPrediosProvider`.
  - **La fiesta se lleva una copia** con `clave: 'predio@<id>'` (`ArmarAMedida.prefijoPredio`): sin claves nuevas en
    el JSON. `_esAMedida` acepta el prefijo, y "Volver al armado original" vuelve al predio como está hoy
    (`EditarArmado.original(a, predios:)`).
  - Las medidas del predio pasan a Medidas al elegirlo (`aplicarEleccionAlPlano(playon:)`); la distancia entre mesas
    es de cada fiesta.

**La mesa reservada** (6.5.0, sin publicar; `docs/CONTEXTO_v6.5.0_2026-11-09.md`, etapa 8). El jefe le da una mesa a quien no es alumno
(los profes: se la regala la empresa, sin contrato ni pago). **Es una mesa libre que dice para quién es**, y va entera en el motivo de la
mesa libre: `Reservada para Profes: GARCÍA, ANA; LÓPEZ, LUIS` (`ReservaDeMesa`, `plano/modelo/reserva_de_mesa.dart`).
- **Sin claves nuevas en el plano de la fiesta:** una PC con una versión anterior la ve como una libre con su motivo.
- **Tiene que empezar con "Reservada para".** Una libre con otro motivo ("Columna") no es una reserva: no se usa y sigue tachada.
  **La coma no separa los nombres** ("GARCÍA, ANA"): separan el punto y coma y el renglón.
- "Dejar libre" pregunta **No se usa · Es para alguien** (`reserva_de_mesa_dialog.dart`), y una libre tiene "Para quién es"
  (`CambiosDeMesa.cambiarMotivoDeLibre`). Todo por `_cambiarConfig`: en modo jefe.
- **En la pantalla, debajo de la mesa van los nombres** en un renglón ("GARCÍA +3", `rotuloEnPantalla`) y la lista se despliega al tocarla;
  **en el papel, "PROFES"** sin la tachadura, con la lista al pie de su hoja (`InfoMesa.rotuloDeReservada` y `nombreDeReservada`).
- Para el sorteo es una libre más: no se la da a nadie.

**En la pantalla del plano no se usa el SnackBar.** Lo que pasó se dice con `AvisoDelPlano`, al lado de los
botones del pie: el SnackBar los tapaba varios segundos después de cada cambio. Un error se dice en palabras, sin
el texto de la excepción.

**El detalle del plano depende de cuánto se ve la mesa, con el zoom** (6.3.0). El zoom agranda el dibujo por fuera, así que el pintor
no se entera solo: `PlanoEventoCuerpo` le pasa `VistaPlano.zoom` con `NivelDetalle.zoomQueCuenta`, que cambia solo al cruzar un
umbral (si no, se vuelve a pintar el salón en cada cuadro). Sin esto, en un salón con el playón entero el apellido no salía nunca.

**Una muestra sale por el camino real, sin recortar el salón**: recortada, enseñó apellidos que el papel no traía. Lo visual se
termina de probar en `tool/plano_prueba.dart`, con el mouse: ahí aparecieron cuatro errores con todos los tests en verde.

**En papel:**
- **la letra de los apellidos sigue a la mesa, pero si hay lugar a lo alto y a lo ancho va con la mínima** (`tamApellido`), y lo de
  debajo de la última fila tiene su lugar en el recorte (`lugarDebajo`). **En un PDF el espaciado de letras queda puesto**: `_escribir`
  lo pone siempre, también en cero, o lo que sigue al nombre de un sector sale más ancho de lo medido y corrido de su mesa;
- **se recorta hasta la última fila de mesas** (`PlanoPapel.marco`). En una hoja con el borde del playón, un sector
  que queda entero más al fondo que las mesas (el Ingreso del salón vacío) no estira el recorte, y
  `PlanoPapel.textoAlFondo` lo dice ("…sigue 14 m más hacia el fondo, con el Ingreso"); si no, el papel llegaba al
  fondo y las mesas salían sin apellido. En el Canva entran todos los sectores;
- el salón vacío guardado con mesas se llama "A medida del playón" (`ArmarAMedida.conNombreSegunMesas`, al guardar):
  el nombre sale en el papel y en SORTEO. La pantalla compara lo guardado con `EditarArmado.comoSeGuarda`, no con lo
  que se ve;
- cada estilo lleva sus colores a la hoja (`TemaPlano.papel` y `papelNumero`): es una cuenta sobre el color de
  pantalla, no una lista a mano;
- **los números de Gala van en Outfit**: las cifras de su serif son de estilo antiguo, un 1 se lee como una I, y el
  PDF no sabe pedir las alineadas.

**Cómo se prueba una pantalla entera.** `test/plano_evento_screen_test.dart` monta `PlanoEventoScreen` de verdad,
con reemplazos en memoria puestos por los mismos providers que usa la app. Es el modelo para otra pantalla que lea
con Riverpod. Para eso `subirYa` tiene un provider delante (`subidaInmediataProvider`, en `subir_ya.dart`).
`detalle_evento_masivo_screen.dart` no se puede montar así (son casi 10.000 líneas): lo que decide está afuera, en
servicios y diálogos con sus tests.

**Las muestras.** `tool/*_muestra_test.dart` sacan imágenes y PDF con datos inventados; todos aceptan
`--dart-define=salida=<carpeta>`. La carpeta `build/` no va a git: sirve para dejarlas donde el usuario las abra.
- **Una muestra con un menú abierto necesita una ventana alta.** Si el menú no entra debajo de su botón, Flutter
  lo corre para arriba y tapa la barra: la imagen muestra algo que en la app no pasa. `barra_fiesta_muestra_test.dart`
  falla si el menú no cuelga debajo.
- **Un HTML con muchas imágenes no se ve en el panel de la app** (ni con las imágenes adentro, por el tope de
  512 KB, ni al lado): se le abre al usuario en el navegador de la PC. Una imagen suelta sí la ve en el chat.

## El tótem

**La lista de la puerta es por evento**, y el tótem no distingue particular de masivo: lo que cambia es cómo se
carga.
- **Particulares:** a mano o por CSV, con DNI.
- **Masivos (fiestas de alumnos):** desde los alumnos (`lista_puerta.dart`). Lleva cada alumno activo y sus
  acompañantes con nombre, con la mesa del sorteo. Los ids son fijos por alumno y lugar (`idInvitadoPuerta`).

**La puerta sigue al sorteo** (v6.0.0, pedido del usuario el 13-oct-2026). El sorteo guarda la mesa en
`contratos_alumnos`; Recepción y el tótem leen `invitados`. `PuertaAlDia` (`recepcion/services/puerta_al_dia.dart`)
las pone de acuerdo sola:
- **La fiesta está en la lista de la puerta solo mientras algún alumno activo tenga mesa.** Al sortear, restaurar o
  cambiar una familia de mesa se arma o se corrige; **al deshacer el sorteo entero se vacía**. Antes de sortear no
  hay nadie.
- **Armar o vaciar la lista entera (`trasElSalon`) solo lo llaman las dos pantallas del salón**, que son del jefe y
  antes de guardar miran la nube. Una PC atrasada nunca vacía la lista: `planListaPuerta` con `soloDe` (una baja,
  un nombre, un alumno nuevo: `trasLosAlumnos`) no hace nada si en esa PC nadie tiene mesa.
- **Un guardado nuevo de mesas tiene que llamar a `trasElSalon`, antes de subir.** `test/puerta_sigue_al_salon_test.dart`
  lee las dos pantallas y falla si aparece uno que no.
- Solo se escriben y se sacan las filas que salieron de los alumnos. Lo cargado a mano en esa lista no se toca.
  El ingreso de quien se queda no se toca; el de quien se saca se va con la fila, y el aviso de Deshacer lo dice
  antes con el número.
- Un alumno eliminado se lleva sus filas en ese momento (`trasEliminar`): después ya no hay de dónde sacar sus ids.
- MÁS → "Pasar a la lista de la puerta" quedó para ponerla al día a mano. `kListaPuertaHabilitada` vuelve a
  trabarlo todo en un solo lugar.

**La lista de la puerta, cerrada a los anónimos** (v6.0.0, sección 8; detalle en "La sección 8" del CONTEXTO).
Quien no tiene usuario (la ventana del tótem, el tótem por el navegador, la página del QR y `?buscar`) **no lee ni
cambia `invitados` ni anota en `accesos`**: va por las funciones de
`supabase/migrations/20261016120000_puerta_funciones.sql`.
- **El tótem** lee `totem_lista` con la clave del tótem (`ListaDelTotem`, cada 20 s, y al instante por el canal). La
  clave (`ClaveTotem`, tabla `claves_totem`) la pide con usuario la ventana principal y se la da al tótem por el
  puente (`clave_totem`); en la web viene en el link. **Sin internet o sin clave, sigue con lo de la PC.**
- **La página del QR** busca desde 3 letras (`puerta_buscar`, en un masivo nadie) y el DNI lo compara la nube
  (`puerta_checkin`). Quien no tiene DNI cargado se anota en la recepción.
- **Con los permisos cerrados, un anónimo que lee la tabla recibe una lista vacía, sin error**, y el tótem sacaría a
  todos. Nada nuevo sin usuario puede leer `invitados` ni escuchar su Realtime: `test/puerta_cerrada_test.dart`
  lee esos archivos y compara el SQL con lo que llama la app.
- **Lo que va por el canal `totem_<evento>` sale sin DNI ni intentos** (`Invitado.sinDatosPrivados`, en
  `InvitadosRepository._emitir`; `paraAviso` en la página del QR). El canal sigue abierto a quien sepa el número
  del evento: [docs/pendientes/canal-totem-abierto.md](docs/pendientes/canal-totem-abierto.md).
- **Los dos SQL:** las funciones, antes de instalar (solo agregan); `20261016130000_puerta_cerrar_permisos.sql`,
  **último**, con todas las PCs y la web en la 6.0.0: si no, el tótem viejo queda sin nadie en la lista. **Los dos
  corridos** (15-oct, el de cerrar a las 22:53, con la web nueva y antes de instalar la oficina: lo eligió el usuario).

**Recepción distingue un evento particular de uno masivo** (v6.0.0, el objetivo del usuario desde el 14-oct-2026; se
dice "evento masivo", no "fiesta de alumnos"). Lo decide `PuertaDelEvento` (`recepcion/services/puerta_del_evento.dart`);
el panel es `PanelPuerta` (`recepcion/widgets/panel_puerta.dart`).
- **Un particular** es su lista de la puerta tal cual: nombre, DNI y mesa.
- **Un masivo sale de los alumnos de la base de la PC, no de la lista de la puerta**: así se ven con lo cargado en el
  momento, antes y después del sorteo, menos los de baja. De la lista se toma solo quién entró, por el id fijo
  (`filasPuertaDesdeAlumnos`, `idInvitadoPuerta`). Sin sortear, un aviso y sin mesa ni sillas; las sillas debajo de
  la mesa salen de `SalonMesas.repartoSillas` con `RepartoDeSillas.vigente`, como en la planilla.
- **Antes del sorteo una persona no tiene fila**: `ingresarDesdeLaPuerta` la crea al ingresarla. **Lo que sube no
  lleva la mesa**: una PC atrasada no puede pisar una mesa del sorteo en la nube. La mesa de la lista la pone solo el
  salón (`trasElSalon`).
- **Subir ya (`_subirYa`) sube lo que dice la cola, no un `update` suelto**, y saca la entrada con `markCompleted`.
  Antes marcar o deshacer un ingreso mandaba un `update` y borraba la entrada igual: una fila recién creada que no
  estaba en la nube perdía su alta y no llegaba nunca.
- El panel usa Outfit (`GoogleFonts.outfit`, que viene con la app): con Oswald, que se baja de internet, un test con
  `allowRuntimeFetching = false` falla. Se prueba entero con `test/helpers/puerta_en_memoria.dart`.

**Acompañantes y música se cargan con un Excel por institución** (v6.0.0): PLANILLAS ▾ → "Acompañantes y música",
solo en modo jefe. Lo completa un delegado; ver "Qué pasó el 13-oct" del CONTEXTO de la versión.
- Lo que decide está en `eventos/services/planilla_delegado.dart`, sin pantalla ni base: `armar`, `leer` y
  `comparar`. **`comparar` no escribe:** es el simulacro que la ventana muestra antes de guardar.
- **Del alumno se escriben solo `nombres_acompanantes`, `cantidad_acompanantes` y `musica_elegida`**, por
  `cargarAcompanantesYMusica`, que rechaza cualquier otra clave. Un Excel no cambia un nombre ni una división.
- **Una institución no pisa a otra:** el archivo lleva el id de su fiesta y un código por alumno (el principio de
  su id). El alumno se busca por el principio del código, no por el código entero.
- **La coma no separa acompañantes** (los nombres son "APELLIDO, NOMBRE"), y un casillero vacío nunca borra.
- El Excel sale protegido (`planilla_delegado_bloqueo.dart`): el paquete `excel` no sabe, así que se escribe
  después sobre el XML. **Es una ayuda, no la garantía**: Google Sheets puede no respetarlo. Si se toca cómo se
  arma el archivo, abrirlo con el Excel de verdad antes de darlo por bueno.
- `tool/simulacro_acompanantes_musica_test.dart` lo prueba entero sobre una copia de la base real.

**Recepción y el tótem nuevos van en la 6.0.0**, por partes (decisión del 13-oct-2026; antes eran "para diciembre").
Están diseñados y aprobados con maquetas: son los seis pendientes de "Tótem y Recepción" en
`docs/pendientes/PENDIENTES.md`. El orden está en `docs/CONTEXTO_v6.0.0_2026-10-11.md`.

**El retiro de entradas** (v72, `retiro_entradas_screen.dart`) es otra cosa: la entrega de entradas y pulseras en la
oficina, antes de la fiesta. Se guarda en `entradas_retiro` y no toca `invitados`.
- **Solo la mesa del contrato trae sus 8 entradas sin cargo** (6.3.1, regla del usuario del 4-nov). La mesa adicional y las sillas
  extra pagan el lugar, no la entrada: esas se compran aparte, **al 50 %** de su valor, y no se entregan en el retiro
  (`EntradasDeAlumno.alCincuenta`). El precio de la entrada todavía no se sabe: nada lleva un precio fijo. Cobrarlas es la venta de
  entradas (sección 8 de `docs/PLAN_MODO_ENTRADAS_2026-10-30.md`), sin programar. Detalle: `docs/CONTEXTO_v6.3.1_2026-11-04.md`.

**Los que se sientan en una mesa reservada** (los profes; 6.5.0, sin publicar; etapa 9 del CONTEXTO de la 6.5.0) **aparecen en Recepción
y el tótem los saluda con su mesa, como a un alumno.**
- **Salen del plano** (`reservadosDeLaPuerta`, `recepcion/services/reservados_de_la_puerta.dart`): uno por nombre de cada mesa
  reservada. **Una reserva sin nombres no pone a nadie en la puerta.**
- **Su fila tiene un id fijo** (`idInvitadoReserva`: la fiesta, la mesa y el nombre) **y se crea al marcar el ingreso**, como la de un
  alumno antes del sorteo: `PuertaAlDia` no los arma ni los limpia. Corregir una letra del nombre es otra persona.
- **Un grupo por mesa** en `PuertaDelEvento.masivo(reservados:)`, con `GrupoPuerta.reservadaPara` ("PROFES", la distinción). **Sin
  `contratoId`: ni sillas de la noche ni nada de cobros.** Quien arme algo para "la familia" tiene que aguantar un grupo sin contrato.
- En la ficha del tótem, `PersonaFicha.grupo` (clave `g`); los de una mesa comparten `familia` y se saludan juntos. `armarFichaTotem`
  los lee con `leerReservados`. El tótem de la web no tiene ficha: ahí van sin mesa.

**Las sillas de la noche** (6.4.0, en la rama; `docs/CONTEXTO_v6.4.0_2026-11-06.md`). La noche de la fiesta, la familia paga la silla en la
caja de la Encargada de barra, lleva el vale a la recepcionista, y Recepción suma la silla a esa familia de un masivo sorteado con el número
del vale (`SillaPuerta`, tabla `sillas_puerta`). La recepcionista se queda el papel.
- **Si la barra anula esa venta, la silla va en rojo** ("vale anulado en la barra: revisar", `ValesAnulados`, `valesAnuladosDelEventoProvider`
  por `barraDelJefeProvider`) y no se saca sola: la recepcionista la quita con motivo. Depende de que la notebook de la puerta tenga lo de la
  barra (con internet, en segundos). Un vale anulado no sirve para sumar.
- **Un solo candado para la PC y los celulares** (`ResolvedorDePedidos`, `central/resolvedor_de_pedidos.dart`): todo lo que se pide en la
  puerta de un evento pasa por esa fila, de a uno, y `decidirSilla` decide con la base del momento. La PC la usa aunque la central esté
  apagada (`CentralDeLaPuerta.resolverDeEstaPc`). **Un camino nuevo que sume o quite sillas pasa por ahí**, no escribe el repositorio al lado.
- **El tope es 2 extra por mesa, contando las del contrato y las sumadas** (`SillasDeLaFamilia`, `services/sillas_de_la_puerta.dart`). Las
  sumadas **no entran en `SalonMesas.sillasExtra` ni en `RepartoDeSillas`**: el sorteo, la planilla, lo pagado, el retiro de entradas y el
  plano no las conocen (`test/sillas_puerta_no_toca_test.dart`).
- **El vale se compara normalizado** (`valeNormalizado`: "2 0017" → "2-17"): cada caja de la barra numera desde 1, así que va la caja.
- **`sillas_puerta` está en `tablasDeLaPuerta`**: sin su SQL en la nube, "Lista para trabajar sin internet" no queda lista.
- **En la oficina, con la fiesta ya sorteada, no se suman sillas extra al contrato** (`puedeSumarSillasAlContrato`; segunda llave
  `sillasExtraTrabadas` al guardar en Editar alumno); en modo jefe sí. Lo eligió el usuario el 6-nov: por fiesta sorteada, no por fecha.
- **La silla suelta** (6.5.0): no va a una mesa ni cuenta para el tope. **Es una fila de `sillas_puerta` con la mesa en 0**
  (`SillaPuerta.mesaSuelta`, `esSuelta`), sin columnas nuevas: ningún armado numera una mesa 0. La barra la vende como "Silla suelta"
  (`esSillaSuelta`), una por vale; la puerta la anota con SILLA SUELTA, por el mismo candado (`DatosSilla.suelta`). Una PC con la 6.4.0
  la muestra "fuera de sus mesas: revisar".

**Escondido, el tótem se pausa.** `KioskLauncher.close()` manda `pausar` antes de esconder la ventana: suelta
streams, canal y relectura. `launch`/`focus` mandan `reanudar`. Todo lo que se agregue al tótem y hable con la
nube tiene que cortarse en `_pausar()`.

**El modo kiosco** (v6.0.0, sección 6): KIOSCO en la barra del tótem pone su ventana en pantalla completa en el
monitor donde está; se sale con Esc, doble clic o SALIR DEL KIOSCO.
- **La ventana secundaria no tiene `window_manager`:** el kiosco es un canal nativo del runner de Windows
  (`windows/runner/kiosco.cpp`, `junior_eventos/kiosco`), puesto en cada ventana secundaria con
  `DesktopMultiWindowSetWindowCreatedCallback`.
- Lo que decide está en `totem/services/kiosco.dart` y `totem/widgets/capa_kiosco.dart`. **`_pausar()` sale del
  kiosco antes que nada:** una ventana escondida no puede quedar sin bordes (`test/kiosco_en_el_totem_test.dart`).
- En la web (`?totem`) el primer toque pide la pantalla completa del navegador (`KioscoNavegador`).
- **El código nativo se prueba con el arnés `tool/kiosco_prueba.dart`** (`flutter run -d windows -t
  tool/kiosco_prueba.dart`): abre el tótem de verdad con un evento inventado y sin abrir la base, así que sí se puede
  correr desde el working tree. Para manejarlo con capturas, el permiso es para `arguello_events.exe`. La barra del
  tótem se esconde a los 5 s y no recibe clics escondida: mover el mouse antes de tocarla.

**Con los datos ya bajados, Recepción y el tótem tienen que andar sin internet** (pedido del usuario el 24-sep y
otra vez el 13-oct-2026). Nada nuevo puede necesitar la nube para marcar un ingreso o saludar: lo que el tótem
muestra llega por el puente o está guardado en la PC. Una PC completa anda (sección 5, 14-oct); varios puestos, por
la notebook central (sección 7, abajo). Lo que cuida cada parte: `docs/pendientes/modo-local-sin-internet.md`.
- **El tótem que abre sin poder leer la nube le pide a la PC quién ya entró** (`lista_totem`, `ListaDeLaPc`,
  `IngresosTotem.leyoDeLaPc`): en silencio, solo hasta que lea la nube, y lo que esta PC no subió se cuida como lo
  avisado por el puente.
- **La foto del tótem se guarda en la PC** (`FotoGuardada`, en `Documentos\Junior Eventos\fotos_totem`). En el
  escritorio, la foto del evento sale de `fotoDelEvento(cfg)`, nunca de `NetworkImage`.
  - **El fondo de "Tu fondo" va en otra carpeta** (`fondos_totem`, `FotosDelTotem.fondosEnLaPc`). Cada carpeta deja
    una imagen por evento: en la misma, guardar el fondo borraba la foto del círculo.
- **Sin internet y con la sesión vencida, entra** (`sesionParaEntrar`, `test/sesion_sin_internet_test.dart`, con la
  librería de Supabase de verdad). Si la PC recuerda el rol, la nube se espera 3 s (`kEsperaDelRolRecordado`).
- **"Lista para trabajar sin internet"**, la línea de Recepción: lo que dice es `EstadoSinInternet` y cuándo se pone
  al día, `PuestaAlDiaPuerta`. Al abrir el evento con internet baja la lista entera (`bajarListaDelEvento`:
  `getByEvento` solo baja si la PC no tiene ninguna fila) y, en un masivo, `SyncEngine.tablasDeLaPuerta`. **Un dato
  nuevo que la puerta necesite sin internet tiene que entrar en esa puesta al día.**

**Los celulares de la puerta van por una notebook central** (v6.0.0, sección 7, 15-oct). Los puestos son celulares y
llevan router propio: la notebook del salón (la de la tele) sirve la página del celular y marca en su base todo lo
que le piden por el wifi, con o sin internet. Recepción → CELULARES ("Sumar un celular") muestra el QR.
- Todo en `lib/features/recepcion/central/`. **`CentralPuerta`** es el servidor (`dart:io`, WebSocket en `/vivo`,
  puertos 8787 a 8796); **`decidirPedido`** decide cada pedido con la base de ese momento, de a uno; marca por
  `InvitadosRepository`, así la cola de subida y el aviso al tótem son los de siempre. Un ingreso que llega más de un
  minuto tarde va con `saludar: false` (`marcarIngreso` e `ingresarDesdeLaPuerta` lo aceptan).
- **`CentralDeLaPuerta` escucha con `ref.container.listen`, no con `ref.listen`**: Riverpod 3 pausa lo que escucha
  un provider que nadie mira, y la central se quedaba sin lista al salir de Recepción.
- **Quién marcó se anota antes de marcar** (`MarcasDeLaNoche`, solo en memoria): la base avisa el cambio y la lista
  nueva sale enseguida; si se anotaba después, el otro celular no veía el nombre.
- **El celular** (`ClienteCentral`, `PantallaPuesto`) usa el mismo `PanelPuerta` que la PC: el panel marca por
  `AccionesPuerta` (`providers/acciones_puerta_provider.dart`), que en la PC es la base y en el celular la central.
  Lo que no puede hacer el celular (eliminar, la línea "Lista para trabajar sin internet") lo dice `AccionesPuerta`.
- **La página del celular es otra entrada**: `lib/puesto_main.dart`, armada con `flutter build web -t
  lib/puesto_main.dart --no-web-resources-cdn` (sin CDN: en el salón no hay internet). La arma
  `installer\build_installer.ps1` y el instalador la deja en `{app}\puesto`, con la regla del cortafuegos
  (`test/instalador_puesto_test.dart` lee los dos archivos).
- **Sin CDN no alcanza: la app tiene que traer su Roboto** (v6.2.1). Si no hay una familia `Roboto` en `pubspec.yaml`,
  Flutter web la baja de `fonts.gstatic.com` al arrancar y no dibuja nada hasta tenerla: sin internet, el celular veía
  la página en blanco (ensayo del 23-oct). `test/puesto_sin_internet_test.dart`. Para probar una página web sin
  internet: Edge sin ventana con `--host-resolver-rules` (ver el CONTEXTO de la 6.2.1).
- **En la web de un celular, `TextField` suelta el teclado al apoyar el dedo afuera y eso se come el toque.** El
  buscador de `PanelPuerta` lo suelta al levantarlo (`onTapUpOutside`, solo en la web).
- **El chat de la puerta** (6.5.0, `lib/features/recepcion/chat/`): **vive solo en la memoria de la notebook** (`ChatDeLaNoche`), sin
  tabla ni nube, y se elige a quién (Todos o una recepcionista). **Quién lo mandó lo dice la conexión, no el mensaje**, y cada uno llega
  solo a quien le toca. La lista de puestos se manda al que llega y a los demás solo si cambió: antes salía con cada latido, cada
  5 s. **Un `Badge` va adentro del `IconButton`**: encima, se comía el toque.
- **Las pruebas escuchan solo en esta PC** (`escuchaCentralProvider` en `loopbackIPv4`): en todas las conexiones,
  Windows abre el cartel del cortafuegos. Para mirar el celular en un navegador: `tool/central_prueba_test.dart`
  (central con un evento inventado); para probar con un celular de verdad: `tool/central_puerta_prueba.dart`
  (`flutter run -d windows`, Recepción en memoria, sin abrir la base). Cortar una prueba larga de Flutter deja el
  `flutter_tester` con el puerto tomado: cerrarlo a mano.

**A quién saluda el tótem no lo decide la pantalla** (v6.0.0). `IngresosTotem`
(`totem/services/bienvenidas_totem.dart`) lleva la lista, la cola de bienvenidas y si se viene pudiendo leer la
nube; `totem_display.dart` solo le cuenta lo que pasó (`leyo`, `noPudoLeer`, `aviso`, `baja`, `vaciar`).
- La primera lectura va en silencio, y también la primera después de un corte de más de un minuto: los que
  entraron mientras tanto van a la lista sin bienvenida atrasada. Un corte más corto no se come ningún saludo.
- **Lo que avisó esta PC por el puente no lo deshace la nube.** Sin internet el ingreso llega al tótem por el
  puente pero sube después; al volver, el tótem leía primero, lo sacaba de la lista y, al subir, lo saludaba de
  nuevo.
- Se da por conectado cuando leyó, no al intentarlo: si no, la espera entre reintentos vuelve siempre a 2 s.
- El aviso de que no hay internet va en la barra del operador (`AvisoSinInternet`), no a la vista del salón.
- `TotemLocal` (el tótem de Recepción y del asesor) usa lo mismo, alimentado desde la base de la PC.

**El tótem distingue particular de masivo por la ficha del evento** (v6.0.0, sección 2). La lista de la puerta solo
tiene nombre y mesa; quién es alumno, con quién viene, sus sillas y su música están en los alumnos, en la base de la
PC. `FichaTotem` (`totem/services/ficha_totem.dart`) se arma con lo mismo que ve Recepción (`PuertaDelEvento`).
- **La pide el tótem; la ventana principal contesta** (`PuenteFichaTotem`, método `ficha_totem`, con el manejador
  que se registra en `AuthWrapper`). Lo que se le manda a una ventana que recién nace lo traga el manejador
  provisorio de `main.dart` sin error: por eso no se empuja. Se pide al abrir, al reanudar, al cambiar de evento,
  cada 60 s y cuando llega alguien que la ficha no tiene. Sale de la PC: anda sin internet.
- **La web (`?totem`) no tiene ficha**: saluda con la fila y sigue con el QR (`hayQrEnElTotem`).
- **La familia se saluda junta y la cola se acorta**, en `IngresosTotem`: `siguiente` junta a los de la misma
  familia, el que llega con su familia en pantalla se suma a la tarjeta, y `finDeBienvenida` da 7 s sin cola, 3 s
  con cola y 3 s más al que se suma. La pantalla solo reprograma el temporizador (`_programarFin`).
- Lo que dice la tarjeta lo decide `ContenidoBienvenida`; la tarjeta y la portada son widgets aparte
  (`TarjetaBienvenida`, `PortadaTotem`), con tests y muestras. **Su letra es Outfit regular o negrita**, la que viene
  con la app: con Oswald un test con `allowRuntimeFetching = false` falla, y sin internet no está.
- **Si la ficha conoce a la persona, la ficha manda**, también cuando dice que no tiene mesa: la fila puede traer
  la mesa de un sorteo que se deshizo. En el salón nunca se dice "sin mesa".
- La música se prende o apaga en Personalizar (`totem_config.mostrar_musica`; vacía = prendida). **Guardar
  Personalizar necesita la columna en la nube**: `test/totem_config_test.dart` compara `toJson` con el SQL.

**Cuatro apariencias: Neón, Cristal, Póster y Gala** (v6.0.0, sección 3a; diseño en
`docs/pendientes/totem-apariencias.md`). Todo en `lib/features/totem/estilos/`.
- **La apariencia:** la elegida en Personalizar (`totem_config.estilo`) o, si nadie eligió, Neón en un masivo y
  Cristal en un particular (`estiloDelTotem`). Una clave vacía o desconocida va a la del tipo: nunca una pantalla rota.
- **La pantalla es una escena** (`EscenaTotem`): la espera a pantalla completa o una llegada, sobre su fondo animado.
  Cada apariencia es una `EscenaEstilo` (`escena_neon.dart`, …). Todo se mide en `u`, un 27avo del ancho de una
  pantalla vertical, así se ve igual en la tele y en chico. Lo que no entra se achica entero (`Centrado`).
- **Los fondos son shaders** (`shaders/totem_*.frag`, declarados en `pubspec.yaml`). `FondoTotem` los carga una vez
  y, si una PC no puede, pinta un degradé del color. **Cada shader usa todos sus uniformes**: uno sin usar lo saca
  el compilador y se corren las posiciones de `setFloat`. En Neón la grilla calcula su ancho en vez de `fwidth`.
  `flutter test` los compila, así que los tests y las muestras los dibujan de verdad.
- **Las letras van dentro de la app** (`fuentes_totem.dart`, familias `Totem*` en `pubspec.yaml`): Tilt Neon,
  Neonderthaw, Cormorant Garamond y Oswald. Sin `google_fonts` en el tótem. **En Gala se piden las cifras
  alineadas** (`FontFeature.liningFigures()`): las de Cormorant son antiguas y "12" se leía "I2".
- **En Neón lo que se lee va arriba del horizonte del fondo** (el 67 % de arriba) y el QR va sobre el piso: sobre la
  línea brillante no se lee.
- **`ReproductorBienvenidas`** pone los tiempos de la cola (la tarjeta en pantalla, cuándo se va, la siguiente).
  Mientras una tarjeta se va, su temporizador es el de la salida: **no se lo cancela** al llegar alguien, o la
  tarjeta queda trabada.
- Sin "YA LLEGARON" en el salón. Cuántos llegaron va en la barra del operador.
- En la ventana del escritorio, si nadie eligió apariencia, la pantalla queda en negro hasta que llega la ficha (no
  se sabe si es masivo); a los 3 s se sigue sin ella.
- **Personalizar tótem** (`totem_config_sheet.dart`, sección 3b) se dibuja con las mismas escenas, así que no puede
  mentir:
  - cuatro tarjetas (`TarjetaApariencia`, quietas) y la vista grande animada, con "Ver una llegada"
    (`LlegadaDeEjemplo`, armada con `ContenidoBienvenida.armar`);
  - en la PC es ventana al centro y si no, hoja a pantalla completa. El corte está en `CortesPantalla`
    (`common/utils/cortes_pantalla.dart`): 600 y 1.024 px, el mismo de la pantalla de Recepción;
  - una foto recién elegida va por `EscenaTotem.foto`, antes de subirla;
  - **si no se toca una tarjeta, `estilo` se guarda como estaba**, porque la config se arma campo por campo;
  - se prueba entera con `test/helpers/personalizar_en_memoria.dart`, y `PersonalizarTotem.elegirFoto` reemplaza al
    selector de archivos.

**"Tu fondo", la quinta apariencia** (v6.2.0; todo en `docs/PLAN_TU_FONDO_2026-10-23.md`). Una imagen propia es el fondo, y de ella salen la animación, los efectos, los
colores y las letras.
- **La animación de la imagen** (`AnimacionFondo`: quieta, acercarse, recorrer, flotar, respirar, ondular) **y los
  efectos** (`EfectoFondo`: van encima y se combinan) **son dos cosas distintas**: así lo pidió el usuario. Todo en
  `estilos/tu_fondo.dart`.
- **Cada imagen trae su receta** (`LecturaDelFondo.receta`, `services/lectura_del_fondo.dart`): se lee una vez en
  Personalizar y **se guarda entera con la config** (11 columnas `fondo_*`), así la PC y la web muestran lo mismo.
  "Automático · según la imagen" viene prendido; tocar algo lo apaga.
- **`EstiloTotem.deLaCasa` son las cuatro de antes**: `FondoTotem` solo pinta esas. "Tu fondo" lo pinta `FondoPropio`
  con `shaders/totem_tu_fondo.frag`, que lee la imagen (`setImageSampler`).
- **"Tu fondo" sin imagen no cuenta** (`EstiloTotem.elegida`); si la imagen no está ni baja, va
  `EscenaTotem.respaldo` (la del tipo). Sin shader, la imagen quieta (`PintorFondoQuieto`, igual al shader sin
  animación).
- **`AnimacionFondo.index` es el número que recibe el shader:** una animación nueva va al final.
- **Personalizar guarda lo del fondo entero** (`TotemConfig.conFondoDe`): la config se arma campo por campo.
- Arnés sin base ni nube: `tool/tu_fondo_prueba.dart` (Windows o web). Muestras: `tool/totem_muestra_test.dart`,
  grupo "Tu fondo".

**La foto y las frases de la espera** (v6.2.1; `docs/CONTEXTO_v6.2.1_2026-10-23.md`). En Personalizar la foto se saca
(`mostrarFoto`), cambia de forma (`FormaFoto`, nueve, con "tal cual" para un logo sin fondo) y de tamaño (50 a 300 %);
las frases, de tamaño (50 a 200 %); y las dos se mueven **juntas** (`ubicacionX`/`ubicacionY`), así la foto nunca
tapa las frases.
- **Las apariencias arman la foto con `fotoDeLaEspera` y las frases con `d.frases`**, y lo de la espera va en
  `Centrado(ubicacion: d.ubicacionDeLaEspera, child: d.bloque(...))`. Una apariencia nueva tiene que pasar por los
  tres: ahí se cuelgan las manijas de Personalizar (`alrededorDeLaFoto`, `alrededorDelTexto`, `alrededorDelBloque`).
- **`Escalado` agranda ocupando lo que mide** (`Transform.scale` no: lo de abajo se pisaría).
- Póster no usa forma, tamaños ni lugar: la foto es su fondo.

**El salón en el tótem** (antes "El plano en la llegada"; v6.0.0, sección 4). Cuando llega una familia de un masivo sorteado, la llegada va arriba
(a la izquierda en una tele horizontal) y abajo el salón con su mesa encendida y el camino desde el Ingreso.
**Desde el 5-nov, en la rama (sin publicar), cambió:** el salón se ve entero toda la espera y la llegada salta y se acomoda
en el cuadro (`CuadroDelSalon`, `EscenaTotem._conElSalon`); `_conPlano` ya no existe. Ver
`docs/CONTEXTO_TOTEM_SALON_Y_SILLAS_2026-11-05.md`. Lo de abajo sigue valiendo para la guía (`PlanoDeLaLlegada`, el camino).
- **Datos:** el armado viaja en la ficha (`FichaTotem.plano`). `armarFichaTotem` lo lee con `leerPlano`, y
  `TotemLocal` con `planoDelEventoProvider`.
- **Lo que decide**, sin pantalla:
  - `PlanoDeLaLlegada` arma la hoja, las mesas y **un solo ocupante, la familia**: uno por fila de la puerta da
    "conflicto";
  - `CaminoALaMesa` busca el paso (A* en una grilla de medio radio, sin pisar mesas con sus sillas, escenario,
    pasarela, barras, cajas ni baños), sale del sector "Ingreso" o de `armado.ingreso` y, sin paso, va recto.
    **Desde la 6.2.1 va en escuadra** (pedido del usuario: "línea recta y que doble"): solo a lo largo y a lo ancho,
    por el medio de los pasillos, con pocas vueltas, sin escalones y saliendo enseguida del cartel del Ingreso; el
    dibujo suaviza apenas la esquina y pone una flecha. No volver a las diagonales: se veía "como rayas".
    **Entre las sillas se pasa, la mesa no** (con las sillas, entre filas quedan 22 a 33 cm y por ahí camina la
    gente): si las sillas vuelven a ser pared, el camino rodea por afuera. Todo sale del plano (posiciones y radio):
    `tool/caminos_rodeo_test.dart` mide el rodeo de cada mesa en la Normal y en playones a 2 y 2,5 m.
- **Cómo se dibuja:**
  - la escena arma la guía **una vez por llegada** (`EscenaTotem.planosArmados`);
  - los temas salen de `temaPlanoDelTotem`, **guardados por apariencia y color**: `TemaPlano` no tiene `==` y uno
    nuevo por cuadro redibuja el salón.
- **Ojo con `withValues(alpha: x)`: fija la transparencia, no la multiplica.** Para aclarar un color que ya es
  transparente: `c.withValues(alpha: c.a * x)`.
- **Quien solo lee el plano entra por `leerPlanoDeLaFiestaProvider`**, no por `planosEventoRepositoryProvider`:
  `test/solo_modo_jefe_test.dart` vigila que el repositorio que guarda el salón lo usen solo la fiesta y el plano.

**Un aviso que no llega no quiere decir que la ventana murió.** `KioskLauncher` reintenta y, si igual no llega,
pregunta si la ventana sigue abierta: solo la olvida si ya no existe. Olvidarla de más dejaba a Recepción sin
avisarle al tótem toda la noche, y reabrirlo creaba una segunda ventana. Le habla a las ventanas por
`VentanasTotem`, que los tests reemplazan (`test/kiosk_launcher_test.dart`).

La Recepción de la web lee hasta 1000 invitados por evento (el "Max rows" de PostgREST). Ver
`docs/pendientes/invitados-mas-de-1000-en-web.md`. El tótem y la página del QR ya no: sus funciones devuelven un solo
JSON.

Hay dos tótems, y **lo visual se hace una sola vez**: los dos dibujan `EscenaTotem` con el mismo
`ReproductorBienvenidas` y `ContenidoBienvenida`.

- `totem_display.dart` — la pantalla del salón. Lee la nube por `totem_lista` con su clave y la ficha le llega por
  el puente. Es la que se usa en la ventana secundaria, en `?totem` y en la ruta `/totem_display`.
- `TotemLocal` (`totem/widgets/totem_local.dart`, sección 3c) — el tótem de esta PC. Lo usan la vista de Recepción
  (`VistaDelTotem`) y la pantalla del asesor. Lee lo mismo que la lista de Recepción, de la base de la PC
  (`invitadosStreamProvider` y `puertaDelEventoProvider` → `FichaTotem.desdePuerta`), así que anda sin internet y
  saluda con la mesa aunque la fila de la puerta no la tenga. Va con la clave del evento.
- **El panel viejo (`totem_panel.dart`, con sus modos y sus botones de ventana) ya no existe.** Recepción va
  según `CortesPantalla`: en la PC, la lista (60 %) y la vista lado a lado; en una tablet, pestañas RECEPCIÓN y
  TÓTEM; en el celular, la lista sola con la paleta arriba. Sobre la vista, un solo botón: la paleta.
  `test/recepcion_pantalla_test.dart` monta Recepción entera con `PuertaEnMemoria.recepcion`.

El tótem **muestra** un QR, no lo lee: no hay dependencia de cámara. El QR apunta
a `/lista?evento=<id>`, que abre el invitado en su celular. **Desde la 6.0.0, solo en
los particulares** (`hayQrEnElTotem`; en `TotemLocal`, según el tipo del evento). Al confirmar el
check-in, esa pantalla emite un broadcast (sin DNI) por el canal `totem_<eventoId>`, que es
el bus de baja latencia que evita esperar la replicación de Postgres.

Identidad visual por evento en la tabla `totem_config` (foto, título, subtítulo,
saludo, color). Sin fila, `TotemConfig.defaults()` devuelve los literales
históricos y la pantalla se ve como siempre.

## Trampas conocidas

- **No agregar columnas a `contratos_alumnos`: un dato nuevo del alumno va en una
  tabla aparte.** Esa fila se reescribe entera en tres lugares:
  - Editar alumno manda `toJson()` completo (`datosEdicionAlumno`);
  - `_pullByEvento` la rearma desde el modelo con INSERT OR REPLACE;
  - `_pullTable` la rearma con la lista de `_cleanForSqlite`.

  Una columna que falte en cualquiera de los tres se pisa o vuelve a su default en silencio. Así se perdía el perdón
  de mora. El patrón probado es el de `notas_operativas_contrato`: tabla propia, una fila por alumno con id fijo
  (`UuidUtils`), como `sillas_reparto` y `entradas_retiro` (v72). El usuario le tiene miedo a las migraciones con
  razón:
  - solo tablas nuevas, con `CREATE ... IF NOT EXISTS`;
  - copia antes de migrar (`LocalDatabase.copiaAntesDeMigrar`). Si ya hay una (`antes_de_v73.db`), saca otra con
    la fecha y la hora: reinstalar la versión vieja, seguir cobrando y volver a instalar dejaba la copia del primer
    día. **Esa copia es la última red, no el camino para volver atrás:** restaurarla deja afuera lo cobrado después;
  - probar sobre una copia de la base real (`tool/verificar_migracion_v73_test.dart` como modelo): compara tabla
    por tabla, prueba la vuelta a la versión anterior y exige que la base real quede con el mismo SHA-256. La app
    instalada tiene que estar cerrada, y se le pide al usuario: no se cierra desde acá;
  - **volver atrás es reinstalar la versión anterior sobre la misma base**: por eso una migración no puede cambiar
    nada de lo que la versión anterior lee.

- **Lo que se carga de a muchos no puede viajar con cada edición del alumno.** `datosEdicionAlumno` manda el
  número de mesa, los acompañantes y la música **solo si alguien los cambió a mano**. Editar alumno manda la ficha
  entera: una PC que todavía no bajó el sorteo o el Excel del delegado los mandaría vacíos al editar un teléfono, y
  los borraría en la nube y en las demás. Un dato nuevo que se cargue de a muchos tiene que entrar en esa regla.
  **La mora, igual** (6.1.0, `camposMoraDelAlumno`): editar a TOÑANEZ desde la PC del jefe habría vuelto a subir
  los $166.200 que en la nube ya estaban en 0.

- **La mora congelada (6.2.1): resta días, nunca cambia una fecha.** El jefe congela la mora de un alumno (el copo de
  nieve de la fila, solo modo jefe), por cuota o "Todas" (también las que se venzan). Se pidió para el que no pagó
  nada y viene a hacer un compromiso.
  - Las pausas (`PausaMora`: cuota o todas, `desde`, `hasta`) están en `features/eventos/services/mora_congelada.dart`.
    `MoraCuotaCalculator` resta los días quietos en `calcular` y `calcularDesglose` (`_diasQueCuentan`); un repaso a un
    cobro viejo no ve una pausa posterior. El tramo se cuenta desde el vencimiento efectivo, así que **un perdón (la
    eximición) no resucita** al congelar ni al recalcular (`test/mora_congelada_test.dart`).
  - **Mantener** cierra la pausa (lo congelado queda quieto para siempre); **Recalcular** la saca, pero solo en las
    cuotas que se deben: una cuota pagada mientras estaba congelada se cobró así y su pausa queda.
  - La cuenta lee un **registro en memoria** (`MoraCongelada.de(id)`), vacío por defecto: sin nada congelado todo da
    igual que antes. Se carga al abrir (`main.dart`), **antes de la revisión de la mora** (`revisarMora`) y cuando el
    sync baja filas. **No va en `ContratoAlumno`** (la trampa de las columnas de `contratos_alumnos`).
  - Tabla aparte **`mora_congelada` (v75)**, una fila por alumno con id fijo, que nunca se borra
    (`_tablasSinRevisarBorrados`). En la nube, sin CHECK, sin clave foránea y sin índice único.
  - **No congelar a nadie hasta que todas las PCs tengan la 6.2.1:** una PC más vieja cuenta la mora entera y, si
    cobra, deja la ficha sin congelar.
  - El aviso celeste ("Mora congelada desde dd/mm · C4, C5") es `AvisoMoraCongelada` y va en la grilla, el cobro y Mi
    Empresa → Cobro. La línea de la eximición dice "Sin mora hasta" (decía "Mora congelada hasta").
- **La baja temporal no toca la mora** (6.1.0; ver `docs/pendientes/mora-por-cuota.md`). Hasta la 6.0.0 la baja
  guardaba el día en `mora_fecha_referencia` y la mora quedaba cortada ahí, también después de reincorporar.
  - Ahora `fechaEfectivaMoraAr` usa siempre hoy, y la fecha se ignora: borrarla no cruza entre PCs, porque el pull
    conserva la de la PC si la nube la trae vacía.
  - Un reincorporado tiene la misma mora que uno que nunca estuvo de baja, y al reincorporar se revisa su ficha en
    el momento (`revisarMora(soloContratos:)`).
  - **Ojo: la revisión que corre al abrir el programa incluye a las bajas.** Solo
    `soloEventosMasivosActivos: true` las deja afuera.
- **Al bajar un contrato, el ajuste de la mora (`mora_tracked_ajuste`) lo manda la nube** (6.1.0, `contratoAlBajar`
  en `core/services/contrato_al_bajar.dart`).
  - Antes la PC se quedaba con el suyo si la nube traía 0: sacar un perdón o arreglar la nube a mano no le llegaba a
    las otras.
  - Las filas con cambios sin subir no llegan ahí (`pendingIds`).
  - Si se pierde un ajuste, queda escrito en `revision_mora.txt`.
  - La eximición, en cambio, sigue conservándose: hubo eximiciones que estaban solo en una PC.

- **Las tablas que se sincronizan no llevan CHECK nuevos en la nube.** El motor toma cualquier "violates" como un
  padre que falta: reencola el evento y la fila queda trabada para siempre. Los valores válidos los controla la
  app, y un test compara el SQL con lo que la app manda. (El SQL de la Fase 2 sí tiene CHECK en
  `sorteos_mesas.tipo`, en `entradas_retiro.estado` y en las cantidades: por eso no se les agrega un valor.)

- **Un cambio hecho mientras sube el anterior no se puede perder.** `SyncQueue.enqueue` no agrega una segunda
  entrada para un registro que ya está en la cola: reescribe la que hay. Si pasaba durante la subida, al terminar
  se borraba la entrada con el cambio nuevo adentro: la nube con el dato viejo, la PC con el nuevo y nada en la
  cola. Por eso `markCompleted(id, leidaCon:)` saca la entrada solo si sigue siendo la que se leyó. Estaba en la
  5.0.0; lo encontró una revisión, no un incidente.

- **Lo trabado en la cola se reintenta todo junto** (`entradasDeEstaPasada`, en `sync_engine.dart`). Antes el
  primer trabado sellaba la hora y los demás no entraban: uno que no podía subir —una tabla que todavía no existe
  en la nube— le sacaba el turno a un pago. **Por eso el SQL de la nube se corre antes de instalar** una versión
  con tablas nuevas.

- **Nada se borra de la base local salvo que alguien lo haya borrado a mano.**
  Un `DELETE` local solo es legítimo si viene con nombre y apellido —una lista
  explícita de ids que una persona eliminó— o si sale de comparar contra una
  foto **completa y contada** de la nube, del mismo alcance que se va a
  recorrer. Un lote incremental, una página que cortó en las 1000 filas de
  PostgREST, o una consulta que falló a medias: ninguna autoriza a borrar nada.

  Es la misma clase de trampa que la de `REPLICA IDENTITY` de acá abajo: parece
  gratis y rompe en silencio. El prune de `_pullTable` comparaba el delta
  incremental —las pocas líneas que alguien acababa de tocar en la otra PC—
  contra **todas** las filas locales de `presupuesto_servicios`, y borraba el
  resto. Como el monto del presupuesto no existe como columna, es la suma de sus
  líneas, los presupuestos aparecían en **$0**: sin excepción, sin log, y solo
  en la PC que más sincronizaba. La nube nunca se tocó —los `delete` a Supabase
  salen solo de la cola— y por eso el pull forzado devolvía todo.

  Hoy la decisión vive en `filasAPodar` (`sync_engine.dart`), con su test en
  `test/filas_a_podar_test.dart`. **Cualquier camino nuevo que borre tiene que
  pasar por ahí**, no reimplementar la comparación al lado.

- **Lo que se borra a mano en una PC tiene que llegar a la otra, y el pull no lo trae** (6.1.1). El pull baja lo
  nuevo y lo cambiado, nunca lo que dejó de existir. El 19-oct-2026 el jefe borró un pago de $60.000 de DE CARLO,
  MICAELA ESTEFANIA. La PC del operario, prendida y cobrando, se lo quedó: el aviso al instante (el pulso) se tiraba
  si la PC estaba ocupada, y la revisión de cada 10 minutos miraba solo seis tablas padre ("las hijas caen por
  cascada", que vale si se borra el padre, no una hija suelta). Al cobrarle, contó los dos pagos y le pisó el saldo
  a la nube ($176.100 en vez de $236.100). En la PC de la casa había además 23 renglones de presupuesto borrados.
  Ahora un borrado llega por cuatro caminos (`borrados_de_otra_pc.dart` dice cuál en `borrados_en_otra_pc.txt`):
  - **el aviso**, que ya no se tira con la PC ocupada: se reintenta a los 3 s;
  - **la cuenta de la red de seguridad, cada 5 minutos** (`_contarParaVerBorrados`; hasta la 6.3.2, cada 10 s): un
    `count` de pagos, alumnos y egresos; si en la nube hay menos que acá, se revisa esa tabla en el momento;
  - **al abrir un alumno** (`revisarPagosDelAlumno`, desde `getHistorialPagosAlumno` y antes de
    `recalcularProgresoContrato`): sus pagos contra la nube, una consulta con 3 s de tope y una vez cada 15 s por
    alumno; sin internet no hace nada;
  - **la revisión de cada 10 minutos y la del arranque**, que mira **todas las tablas que se borran a mano** y corre
    antes de la revisión de la mora. Lee lo de la PC y la cola **antes** que la nube: al revés, un cobro que subía en
    el medio se tomaba por borrado.

  Al sacar un pago se rehace la cuenta del alumno, solo si sus pagos quedaron iguales a los de la nube.
  **Una tabla nueva que se baje tiene que estar en `_tablasAReconciliar` o en `_tablasSinRevisarBorrados`, con el
  motivo**: `test/borrados_de_otra_pc_test.dart` falla si no, y también si aparece un borrado a mano de una tabla que
  no se revisa.

- **El `updated_at` de Supabase lo mantiene un trigger, no los repos.** Hay un
  `before insert or update` sobre cada tabla sincronizada que corre
  `public.update_updated_at_column()`. Estuvo aplicado a mano y sin versionar
  desde 2026 hasta que se versionó en
  `supabase/migrations/20260908120000_updated_at_trigger.sql` — leyendo solo el
  repo la conclusión razonable era que no existía, y eso ya mandó a un plan a
  "arreglar" algo que funcionaba. Si agregás una tabla al sync, **agregale el
  trigger**: sin él sus ediciones no cruzan nunca, porque el motor no rellena
  `updated_at` y varios repos tampoco.

- **El marcador del pull sale del servidor, no de la PC.** `marcaDeLoBajado`
  toma el `updated_at` más alto de lo que bajó. No volver a usar `DateTime.now()`
  para eso: se compara contra el reloj de Postgres, y la diferencia entre los
  dos relojes entra directo en el filtro.

- **`REPLICA IDENTITY` y los DELETE.** Cualquier suscripción de Realtime
  **filtrada por una columna** —sea `.stream().eq(...)` o un
  `PostgresChangeFilter`— **descarta los DELETE** si la tabla está en
  `REPLICA IDENTITY DEFAULT`: el payload del borrado lleva solo la primary key,
  el servidor no puede evaluar el filtro y tira el evento. Por eso `invitados`
  necesita `REPLICA IDENTITY FULL` (ver `supabase/migracion_totem_config.sql`).

  Vale la pena entender el orden en que pasó, porque es fácil repetirlo: el
  panel de Recepción funcionaba porque su `onPostgresChanges` **no tenía
  filtro**. Al agregarle el filtro por `evento_id` el 2026-09-02 —una
  optimización correcta y necesaria— quedó ciego a los borrados, igual que el
  tótem. Agregar un filtro a una suscripción es gratis en apariencia y rompe
  los DELETE en silencio. Si una lista filtrada no se actualiza al borrar,
  empezar por acá.
- **Un `async*` con `await for` no suelta nada al cancelarlo.** Sigue parado hasta el próximo evento del
  stream de adentro, y su `finally` corre recién ahí. `InvitadosRepository.watchByEvento` era así: al salir de
  Recepción, el canal de Realtime quedaba abierto hasta el próximo cambio del evento. Si un stream tiene que
  liberar un recurso al cancelarse, usar `StreamController` con `onCancel`.
- **Para decidir con lo pagado, leer los pagos, no los campos del contrato.** `saldo_deudor`,
  `mesa_extra_pagado` y `sillas_extra_pagado` son derivados y pueden no coincidir con los pagos. En sep-2026
  ARGUELLO, TOMAS daba $30.000 de base pagados según el contrato y no tenía ningún pago. Lo que manda es
  `grossHistoricoClaseCobro(pagos, clase)` (`cobro_abono_acumulado.dart`), lo mismo que usa el recálculo del saldo.
  El sorteo de la v5.0.0 decide así (`pago_para_sorteo.dart`). (ARGUELLO era un contrato de prueba que quedó; el
  usuario lo corrigió el 15-oct.)
- **La mora que ya se pagó no se puede volver a descontar** (regla del usuario: la mora de un mes pagada no se
  cobra más; la siguiente sí). Lo cuida el "ya usado" (`mora_cobrada_offset`): cuando un cobro salda toda la mora
  y da la eximición, cubre **todo** lo cobrado (`postCobroTrackedOffset(moraCobradaHistorialPreCobro:)`). En
  oct-2026 a 33 alumnos se les cobraba de menos (VERON, DALMA: $1.100 en vez de $33.000), por tres caminos:
  - la revisión automática (`MoraTrackedRecovery.reconciliarTodos`) corregía en la PC pero **no subía** el "ya
    usado" ni la eximición, y solo corría con "Bajar": ahora sube todo y corre sola una vez por sesión
    (`SyncEngine.revisarMora`), con constancia en `revision_mora.txt`;
  - la mora pagada en dos veces dejaba afuera la primera parte;
  - anular un cobro dejaba su eximición.

  **El "ya usado" se queda solo con la mora de lo que se cierra** (6.3.2). Después de cualquier cobro, `historial − offset`
  (el crédito FIFO) tiene que ser exactamente la mora pagada por adelantado de cuotas que **siguen abiertas**. LOPEZ, MORENA
  AILEN pagó $130.900 de mora de las cuotas 2, 3 y 4 cerrando la 2 y la 3: el offset se quedaba con todo y los $32.900 de la 4
  se le volvían a pedir. Y al revés, mora pagada de a partes sobre una cuota que después se completaba sin mora se descontaba
  también de la siguiente. `postCobroTrackedOffset` ahora lee el desglose bruto (un `assert` frena si llega vacío);
  `test/mora_adelantada_cuota_abierta_test.dart`. Para comparar una regla vieja con la nueva sobre una copia, el repaso del
  historial acepta otra cuenta (`CuentaPostCobro cuenta`, que la app nunca pasa) y `tool/simulacro_mora_adelantada_test.dart`
  lo hace alumno por alumno, con grupos A (baja) y B (sube: lo decide el jefe), y cobro por cobro con `detalle=cambios`.
  **Los dos simulacros cargan la mora congelada** antes de repasar, como la app; sin eso los congelados salían mal.

  **La eximición se resuelve con `resolverExencion`:** la de un cobro anulado se va; la que vino de cobros la
  reemplaza la del último cobro; **la de un perdón (con ajuste de ficha, o que ningún cobro reproduce) no se toca**.
  `test/revision_mora_test.dart` cuida las tres cosas; `tool/simulacro_revision_mora_test.dart` muestra qué cambia
  con una copia de la base real.

  **A quien tiene un perdón, la revisión no le sube la mora** (6.5.0, `MoraTrackedRecovery.tienePerdon`). El repaso de los cobros usa
  las eximiciones que dieron los cobros, nunca la de un perdón: a una alumna (perdón con "sin mora hasta 30/09" permanente, la
  ventana le mostraba $0) le dejó $372.368 el 10-nov después de pagar sus cuotas. Si la cuenta se la subiría, la ficha
  queda y lo dice `revision_mora.txt`; bajarla, sí. Lo encontró la foto de la mora "después de 6.4.0".

  **La revisión no toca a quien ya terminó de pagar** (saldo 0). Su ficha la dejó el cobro, y el jefe la perdona en
  modo jefe como liquidación (queda en verde). El repaso de los cobros usa el saldo de hoy, y sin saldo da siempre
  $0: le borraba la mora a ALTAMIRANO, CELESTE ABIGAIL (15-oct). No rehacerla con el saldo de cada cobro: los
  perdones de esos alumnos se anotaron con la cuenta vieja (ajuste 0) y se revivirían.
- **En una fila de un PDF, un hijo sin `flex` no tiene tope de ancho: el texto no baja de renglón y se sale de la hoja, sin error.** Así
  salía recortado el encabezado del recibo de los eventos particulares (10-nov-2026): la columna de la derecha, sin `pw.Expanded`, se
  estiraba con la frase "Este evento fue diseñado para …" y se llevaba afuera la etiqueta y la fecha. Lo que va al lado de otra cosa en un
  `pw.Row` y puede ser largo va en `pw.Expanded`. **Y un cuerpo entero metido en un solo `pw.Column` no se parte entre hojas:** con
  pocas filas deja el encabezado solo en la hoja 1, y si no entra en una hoja el paquete no termina nunca (su freno es un `assert`, que
  en la app instalada no corre). Las tablas van como hijas directas del `pw.MultiPage`. Para comprobar que nada se salga,
  `palabrasDelPdf` (`test/helpers/leer_pdf.dart`) dice dónde cae cada palabra; modelo: `test/recibo_particular_test.dart`.
- **En un PDF, una columna de renglones dentro de una celda de tabla puede perder el último, sin avisar.** El
  paquete arma cada fila dos veces y, en la segunda, le da a la celda como tope exactamente lo que mide; si la suma
  de los renglones lo pasa por un redondeo, deja el último "para la hoja siguiente" y no lo dibuja. Así no salía
  "PASTO · avisar" ni el último acompañante. Se arregla envolviendo el contenido de la celda en `AltoLibre`
  (`planilla_tema.dart`). La planilla del sorteo es la única tabla con `TableCellVerticalAlignment.full`.
- **Realtime no cubre todas las tablas.** Verificar con `pg_publication_tables`
  antes de suscribirse: varias tablas no están en la publicación
  `supabase_realtime`.
- **IDs malformados.** Supabase tira 22P02 con un UUID inválido. Los repos
  abortan si `eventoId.length != 36`; conviene mantener ese blindaje.
- **Branding inconsistente.** Los títulos de app dicen "Argüello Events" y la UI
  del tótem decía "Junior Eventos".
- **`flutter analyze` no corre en las sesiones remotas de Claude Code**: el
  contenedor no trae Flutter ni Dart. Hay que correrlo localmente.

## Archivos grandes

`detalle_evento_masivo_screen.dart` (~9900), `pdf_service.dart` (~8800),
`finanzas_view.dart` (~7600), `local_database.dart` (~3500 con todas las
migraciones), `plano_evento_cuerpo.dart` (~2200), `totem_display.dart` (~900).
Leer por tramos, no enteros.

## SQL

Las migraciones se versionan en `supabase/` y se corren a mano en el SQL Editor.
No hay CLI de Supabase configurado. Convención: cada sentencia riesgosa lleva su
`ROLLBACK` escrito arriba, comentado, y el archivo termina con las consultas de
verificación: los conteos de antes y después, que tienen que dar igual.

**Antes y después de cada versión, una foto de la mora** (`supabase/mora_fotos.sql`, tabla `mora_fotos` en la nube,
creada el 2-nov-2026 con la primera foto: 643 alumnos). Con cada actualización revivían moras cobradas o perdonadas y
no había con qué compararlas. Ahora: foto "antes de X.Y.Z" antes de correr los SQL e instalar; instalar las tres PCs
y abrirlas (la revisión de la mora corre al arrancar); foto "después de X.Y.Z"; y la comparación de la sección 3 lista
a quién le subió la mora, se le fue la eximición o el perdón, o se le descongeló. La sección 4 vuelve a un alumno a la
foto de antes. La app no conoce la tabla; se corre desde el SQL Editor o el MCP.

**Cada cambio a la mora de un alumno queda anotado en la nube** (`supabase/mora_cambios.sql`, tabla `mora_cambios` y
el trigger `contratos_alumnos_mora_cambios`, corridos el 2-nov-2026 y probados con una escritura revertida). Anota
antes → después de los seis campos de la mora y el saldo, qué otras columnas vinieron en la misma escritura (si cambió
el saldo fue un cobro; si cambió otra cosa, una edición; si nada, la revisión) y el usuario. **Solo anota, nunca
frena**: si no puede, la escritura sigue. Cuando una mora reviva, esta tabla dice qué escritura lo hizo: ese es el
camino a cerrar en el código, con su test. La app no la lee (sin políticas); una pantalla "Historial de la mora" queda
para después de operadores y barra.

**Los SQL de una versión se corren antes de instalarla**, con el OK del usuario
en el momento. Sin las tablas en la nube, lo que se cargue en las PCs queda
trabado en la cola. (La regla de "después de las 20 hs" la sacó el usuario el
13-oct-2026: lo que solo agrega se puede correr a cualquier hora.)
