# Para la Técnica del 4-dic: la tele, la barra por día, la encargada en el iPhone y el repositor (25-nov-2026)

## Para retomar en otro chat

### EMPEZAR POR ACÁ (lo último): 28-nov a la noche, chat "donde nos quedamos… hacé todo, el mouse al final"

**Plan aprobado de este chat** (6 etapas, A a F, todas de corrido; **el mouse, la nube y publicar, al final, con
él**): `C:\Users\lover\.claude\plans\donde-nos-quedamos-sigamos-fluffy-lampson-of-b2f6a465-dd63-4dad-a456-d8cc83aa7804.md`.
A "¿Volvió el vale?" → B la encargada (y el repositor) en el iPhone → C la noche simulada y el repaso → D el locutor →
E el plano ancho y Noche y Blanco → F con él. Si falta tiempo, se cae primero Noche y Blanco, después el plano ancho,
la página del repositor y el locutor.

#### CÓMO QUEDÓ AL CORTAR (28-nov, noche; el usuario pidió "actualizá el contexto para retomar en otro chat")
**~93 %. Nada publicado.** Hechas A, B y C; D a medias; faltan E y F. Commits: `c0d7137` (A), `3d036b3` (B),
`cbf46f0` (C, la noche simulada), `c748e8c` (D, primera parte) y el de esta nota (los arreglos de la revisión, **sin
probar**). El usuario preguntó en el medio cómo entra la encargada con el iPhone: se le explicó (QR de la notebook,
solo su PIN, retoma sola).

**Lo primero al retomar, en orden:**
1. **Probar los arreglos de la tercera revisión** (commit de esta nota: compilan, `flutter analyze` sin errores,
   **ninguna prueba corrida todavía**). Correr `test/pagina_de_la_barra_test.dart`, `test/pagina_de_la_barra_pantalla_test.dart`,
   `test/noche_simulada_test.dart` y las de la barra (`grep -l "features/barra" test/*.dart`). Sumar pruebas y roturas de
   cada arreglo (abajo, "La tercera revisión"). Lo más importante: **se corta justo después de mandar un retiro desde el
   iPhone → dice "por confirmar, no lo repitas" → al reconectarse se reenvía con el mismo número → queda una sola vez**.
2. **Mirar las roturas que corren aparte**: en la copia `..\arguello_events_pruebas` (un `git worktree` en `cbf46f0`,
   script `correr_todo.sh`) corrieron **la suite entera: 6.951 en verde, ninguna falla** y después las 21 listas de
   roturas (499 casos; al cortar iban 63). El resumen queda en `..\arguello_events_pruebas\build_pruebas\resumen.txt`
   ("nombre: N de M"; cada log en esa carpeta). Una "ATENCION" = falta una prueba. Al terminar: `git worktree remove
   ..\arguello_events_pruebas`.
   **Terminaron (28-nov, noche): 479 de 499 atrapadas. Los 20 que no, ninguno es una regla sin vigilar:**
   - **16 "NO SE APLICO"** (el texto a romper ya no está tal cual, porque el código cambió en las etapas A y B): listas
     viejas. Poner al día el texto de cada caso y volver a correr esa lista: `roturas_6.9.3` (9 y 59),
     `roturas_barra_por_noche` ("el Quedan de VENDER"), `roturas_permisos_barra` ("la lista de la encargada guarda"),
     `roturas_precio_de_lista` (G4, G6, G12 y seis de recetas/VENDER: el stock pasó a `ventasAnuladasConElVale`),
     `roturas_recorrido_28nov` (los dos del trago con receta) y `roturas_retiros` ("retiro sobre una caja cerrada").
   - **3 "ATENCION" de `roturas_permisos_barra` en LAS CAJAS y el PIN:** dos son de la lista vieja: en la etapa B el
     botón CATÁLOGO Y PRECIOS pasó a `if (veCatalogo && CortesPantalla.esCelular(ancho))` / `else if (veCatalogo)`
     (`las_cajas_screen.dart:67-94`), y el texto `              if (veCatalogo)` ahora cae en el de
     `AvisoDeVendidoSinStock` (línea 117), no en el botón; el test (`encargada_de_barra_test.dart:409`) sí lo mira.
     Cambiar el texto a `else if (veCatalogo)`. El tercero ("su propia caja no se la aprueba la encargada con su PIN",
     `pin_de_la_encargada.dart:34`): desde el 27-nov la encargada cierra su caja sola y la prueba ya no llega a ese
     camino; ver si sigue haciendo falta y, si sí, una prueba que lo recorra.
   - **1 "ATENCION" de `roturas_precios_con_lista`** ("sin modo jefe PRECIOS lee el precio de lista"): la segunda
     llave (`listaDelProveedorProvider` vacío a quien no es el jefe, 27-nov) tapa la rotura de la primera. Para
     vigilarla, una prueba que reemplace ese provider con datos y vea que PRECIOS sin modo jefe no lo mira.
3. **Terminar la etapa D (el locutor)**: lo que falta, abajo en "Etapa D".
4. Etapa E (el plano ancho en la tele y Noche y Blanco) y la F con él (mouse, nube, publicar).

**La tercera revisión independiente (28-nov, noche; agente que leyó `b03825d..HEAD` sin mis conclusiones):**
- **ALTA, arreglado sin probar:** desde el iPhone, si la respuesta no llegaba (iPhone bloqueado, wifi cortado), la
  pantalla decía "No se pudo. Probá de nuevo." y repetirlo anotaba **otro** retiro, cambio o reposición (id nuevo).
  Ahora: `ClienteDeLaPagina.escribir` guarda lo mandado en `_porConfirmar` y tira **`QuedaPorConfirmar`** ("No llegó la
  respuesta… No lo repitas: se confirma solo"); al reconectarse (`_mandarLoPorConfirmar`) lo reenvía igual y la
  notebook contesta "ya estaba"; una respuesta tardía también lo confirma (`_respuesta`). La franja dice "N por
  confirmar". **Las pantallas dicen el aviso tal cual** con `textoDelError` (`barra/datos/aviso_al_anotar.dart`,
  `AvisoAlAnotar`): `cajas_de_la_fiesta.dart` (retiro/cambio y anular), `ok_del_cierre.dart`,
  `stock_de_las_barras_screen.dart`.
- **ALTA, arreglado sin probar:** el freno del PIN se salteaba abriendo muchas conexiones juntas, y `/barra` (las
  tablets) no tenía freno. Ahora **los PIN se prueban de a uno por dirección** (`CentralBarra._deAUnoPorIp`, `_Conexion.ip`)
  en `/barra` y `/pagina`, y `/barra` también cuenta los equivocados (`_fallo`): a los 5 en un minuto, 4029.
- **MEDIA, arreglado sin probar:** la respuesta de la notebook lleva **la fila como quedó** (`'fila'`): si la misma
  venta ya la anuló otro equipo, el iPhone guarda la de la notebook (no la suya). `BarraDeLaPagina` devuelve lo que
  guardó la notebook.
- **Arreglados sin probar, menores:** si falla leer la fiesta después de un PIN bueno ya no dice "PIN no reconocido"
  (cierra 4010 y vuelve solo); **SALIR borra la ficha en la notebook** (`'salir'`, 4011); **si a mitad de la noche le
  sacan el permiso, la ficha deja de valer** (se revisa `paraLaPagina` al volver); la franja sin conexión agrega "Si la
  notebook se reinició, escaneá otra vez su QR"; "La tablet se entera al momento" también en la notebook con la central
  prendida (`_seEnteraAlMomento`); **la silla de la noche no cuenta como perdida** si el vale no volvió
  (`entregadasSinCobrar`).
- **NO arreglado (decirle al usuario / límites):** (a) quien tenga la clave del wifi de la barra y capture un ingreso
  puede sacar el PIN (la llave es un sha256 del PIN, por `ws://`): **la protección real es que la clave del router de
  cada barra no se comparta**; (b) la misma venta anulada sin internet desde la tablet y desde la notebook con
  respuestas distintas: cada una se queda con la suya hasta que hay internet (ya en
  `docs/pendientes/anular-dos-veces-desde-dos-pcs.md`); (c) "¿Volvió el vale?" es por venta, no por vale (con POR
  SEPARADO no se puede decir "uno sí y otro no"); (d) el retiro y el OK desde el iPhone llevan la hora del teléfono
  (solo el orden a la vista); (e) la noche simulada no prueba escrituras del iPhone con la respuesta perdida, ni
  conteos, recetas o sillas: sumarlas.

#### Etapa C — La noche simulada (hecha; `cbf46f0`)
`test/noche_simulada_test.dart`: dos barras con sus centrales de verdad (UDP y WebSocket en esta PC), tres cajas, la
encargada en su tablet, Ana en el iPhone (la página), el repositor; 300 ventas (efectivo, transferencia, mixto) de 21
a 01:35; Sofía casi toda la noche sin señal (≥80 ventas), la notebook de la Barra 1 se apaga y vuelve, las barras se
separan y se juntan, anulaciones con y sin el vale, retiro y cambio, reposición sin señal. Comprueba que todo llega a
todos lados una sola vez, que todas las ventas son de la noche del 4, cada cierre igual al centavo en todos los
equipos y en el iPhone, el stock igual en todos, GANANCIA igual en las dos notebooks, y las tres cajas cerradas con
el OK. 5 de 5 corridas. **Encontró un error real**: al apagarse la notebook, el reintento del iPhone dejaba un error
suelto (`canal.ready` sin atender): arreglado en `cliente_de_la_pagina.dart`.

#### Etapa D — El locutor, "Cómo lo nombran" (a medias; `c748e8c`)
**Hecho y probado** (`test/como_lo_nombran_test.dart` 16, `test/nombrar_por_el_candado_test.dart` 11; las 64 de
Recepción, la puerta, la tele y el tótem: 1.133 en verde):
- **Datos:** `lib/models/como_lo_nombran.dart` (`ComoLoNombran`, `NombreDeAcompanante`), `UuidUtils.comoLoNombranId`,
  **tabla `como_lo_nombran` en la v85** (`crearTablasV85`; la base del equipo va por la 85; `test/migracion_v84_test.dart`
  puesto al día), `ComoLoNombranRepository` (`cambios`, `sinSubir`), `comoLoNombranDelEventoProvider`.
- **Reglas puras** (`recepcion/services/como_lo_nombran.dart`): `deCorrido`, `limpiarNombre` (60 letras, sin emojis ni
  letras que la tele no tiene), `lugaresDe` (el mismo número que la lista de la puerta), `NombresDeLaFamilia` (cruza lo
  guardado con la lista de hoy por lo cargado; lo que no cruza va a `sobrantes`; `firma` sin `updated_at`; `filaCon`),
  `DatosNombres`.
- **La puerta:** `PuertaDelEvento.masivo(nombres:)`; `GrupoPuerta.institucion` y `.nombres`; `PersonaPuerta.nombrado`
  (el `nombre` sigue siendo el cargado); se busca también por el apodo; JSON con claves nuevas opcionales.
- **El pedido `QuePide.nombrar`** por el mismo `ResolvedorDePedidos` (`decidirNombres`: conflicto si cambió mientras se
  editaba, "Quedó así." si ya está, idempotente por id; `PuertaDeEstaPc.nombresDe/guardarNombres`).
  `AccionesPuerta.nombrar` en la PC (texto según la central prendida) y en el celular (`ClienteCentral.nombrar`, solo
  conectado, espera 8 s; `sillasPorMandar` cuenta solo sillas).
- **La pantalla:** `recepcion/widgets/hoja_como_lo_nombran.dart` (un campo por lugar, ↺, el aviso de la tele, el
  conflicto sin borrar lo escrito, reintento con el mismo id) y en `PanelPuerta` la línea "Lo nombran: «…»" y el botón
  **CÓMO LO NOMBRAN** (también antes del sorteo, solo familias de alumno).
- `ComoLoNombranEnMemoria` en `test/helpers/puerta_en_memoria.dart` (y en los arneses que reemplazan las sillas).

**Falta, en orden** (el diseño entero en `docs/SPEC_locutor_2026-11-18.md`, que no está en git; **v85 en vez de v81**,
sin la app Android del locutor, sin música, y con la tele como central):
1. **El locutor en la central** (`central_puerta.dart`): `r=locutor` en `/vivo` con **código propio**
   (`CodigoCentral` con otro prefijo; con el de los celulares también entra; con el suyo sin `r`, 4001); rol de solo
   mirar (acepta solo `hola`; no recibe `puerta`, `salon`, `chat` ni `puestos`; va en `locutores`, no en puestos);
   mensaje `locutor` con `ListaDelLocutor` (nuevo, `services/lista_del_locutor.dart`: institución → división →
   familias por apellido, sin profes, cargados a mano ni bajas) **solo cuando cambia** (un ingreso no lo reenvía).
2. **La página del locutor**: `?locutor` en `lib/puesto_main.dart` **antes** de crear `ClienteCentral`;
   `ClienteLocutor` (claves propias en el navegador) y `PantallaLocutor` (oscura, Outfit, el nombre grande y los
   acompañantes, "Sin conexión" con la lista a la vista; los extras NUEVO/A−/A+ si da el tiempo).
3. **SUMAR AL LOCUTOR** en Recepción → CELULARES (`widgets/sumar_celular.dart`, solo en un masivo: QR, código,
   "No puede ingresar a nadie ni cambiar nada") y en el menú de la tele (`tele/pantalla_tele.dart`).
4. **El tótem**: `FichaTotem.desdePuerta` saluda con `nombrado ?? nombre` (nunca `deCorrido`); `armarFichaTotem` con
   los nombres (`puente_ficha.dart`, `main.dart` AuthWrapper); `KioskLauncher.notifyFichaCambio` + `ficha_cambio` en
   `totem_display.dart`; `TotemSigueLosNombres`. La Tele 2: mandarle los nombres por `/tele`.
5. **Sync y nube**: en `sync_engine.dart` (`_incrementalColumns`, `_tablasDelCobro`, prioridad 4, la bajada,
   `tablasDeLaPuerta`, `_cleanForSqlite`, `_tablasSinRevisarBorrados` con el motivo); el SQL nuevo en
   `supabase/migrations/` (molde `20261105120000_sillas_puerta.sql`, **sin correr**); `test/sync_tablas_v85_test.dart`;
   "Todo subido" cuenta los nombres sin subir; `test/migracion_v85_test.dart`; la migración 82 → 85 sobre una copia.
6. Pruebas de la central con el locutor, capturas, roturas, y el recorrido en el navegador (al final, con el resto).

#### Etapa A — "¿Volvió el vale?" al anular (~86 %)
- **La ventana** (`barra/widgets/anular_venta_dialog.dart`, `pedirAnulacion`): el motivo y **"¿Volvió el vale?" SÍ,
  LO TENGO · NO, YA SE ENTREGÓ**, sin ninguna marcada (ANULAR apagado hasta contestar). La usan VENTAS de la caja (con
  el PIN de la encargada) y LAS CAJAS / CAJAS del jefe / la web (`cajas_de_la_fiesta.dart`). **Una venta de solo
  sillas no pregunta** (`AnulacionBarra.preguntaPorElVale`). `pedirMotivo` no se tocó. Capturas mandadas
  (`build/capturas_vale_28nov/`, de `tool/volvio_el_vale_muestra_test.dart`); el usuario no contestó todavía.
- **La respuesta va dentro del motivo** (sin SQL): `AnulacionBarra.marcaValeNoVolvio` ("[el vale no volvió]") al
  final; `valeVolvio`, `motivoParaMostrar`, `sinLaMarca`. Lo anulado antes (sin marca) cuenta como "volvió". **Una
  versión anterior ve la marca en el motivo y devuelve el stock.** `anular(..., valeVolvio:)` en `BarraDelJefe`,
  `BarraDeLaCaja`, `BarraLocal`, `BarraNube`, `BarraConLaRed` (también `anularConLaEncargada`).
- **Las cuentas:** la plata usa `ventasAnuladas` (todas, como siempre); **el stock usa `ventasAnuladasConElVale`**
  (`StockDeLaBarra.de`, `StockPorBarra` y sus conteos `_anulacionDe`). GANANCIA: lo entregado sin el vale va a
  `perdidas` (`entregadasSinCobrar`), también en los tragos con receta, y "quedaron" lo descuenta. El papel imprime
  `motivoParaMostrar` y "El vale no volvió". Los renglones ANULADA dicen "· el vale no volvió".
- Pruebas: `test/volvio_el_vale_test.dart` (20, con una que lee el código: ninguna cuenta del stock usa
  `ventasAnuladas(`), 2 nuevas de pantalla en `barra_ventas_test` y `barra_jefe_pantalla_test`, una en
  `central_barra_test` (la anulación sin el vale cruza y los tres equipos dan el mismo stock), y las de la base y la
  nube; las de antes que anulaban ahora contestan SÍ; la encargada anulando en su propia tablet. Las 77 de la barra: 1.433 en verde. Roturas (22 de 22 atrapadas; dos destaparon pruebas que faltaban):
  `tool/roturas_volvio_el_vale.txt`.

#### Etapa B — La encargada (y el repositor) en su iPhone, por el wifi de la notebook (~91 %)
El usuario preguntó en el medio "¿cómo entra la encargada con el iPhone?": se le contestó el QR de la notebook, solo
su PIN, y que retoma sola.
- **La notebook sirve la página** (`CentralBarra`, mismo puerto 8797…: el cortafuegos ya estaba): los archivos de
  `{app}\barra_pagina` (`paginaDeLaBarraProvider`; en desarrollo `build\barra_pagina`) con la función común
  `ServirArchivos` (`lib/core/red/servir_archivos.dart`, que ahora usa también la puerta), y el WebSocket `/pagina`.
- **Solo el PIN, que no viaja:** la página firma el reto con las dos llaves del PIN (operador y maestro); la central
  prueba el maestro y `QuienEsQuienEnLaBarra.paraLaPagina()` (encargadas y repositores activos). Freno: 5 PIN malos por
  minuto y dirección (`kIntentosDeLaPagina`, cierra 4029). La central firma de vuelta (una notebook de afuera no se
  hace pasar). Una cajera no entra (4006).
- **La ficha de la noche** (`LlaveDeLaBarra.deLaFicha`): se saca de la llave del PIN, del número de ficha y del
  teléfono; ninguno de los dos lados la manda. El navegador guarda la ficha, no el PIN. Atada al teléfono; vive en
  la memoria de la central: si la notebook se reinicia, pide el PIN (4008).
- **La página no es una caja** (`CentralBarra.paginas`, `PaginaConectada`): no suma en "cajas conectadas"; el panel de
  la notebook dice quién la tiene abierta, con el QR (`_ParaElIphone`, `EstadoCentralBarra.enlaceDeLaPagina`).
- **Lo que anota la página** (`tablasDeLaPagina`: anulaciones, pasos del cierre, retiros y cambio, movimientos del
  stock; solo filas nuevas): la central mira `ReglasDeLaBarra` con el rol de la página, que la fila sea de su teléfono
  y de la fiesta, y la guarda **con la cola de subida** (`BarraDeLaRed.guardarDeLaPagina`, en `BarraLocal` con
  `_guardar`), la reparte a las cajas y a la otra barra, llama a `alGuardarDeLaPagina` (la notebook la sube ya) y
  contesta `respuesta` ok o el motivo. **La página no da nada por hecho hasta la respuesta**
  (`ClienteDeLaPagina.escribir`; sin conexión, `SinConexionConLaNotebook`).
- **Lo que recibe**: todo lo de la red y el catálogo (`tablasDelCatalogoDeLaPagina`: productos, precios, recetas,
  recargo; `catalogoParaLaPagina`) y la fiesta sin PIN ni observaciones (`fiestaParaLaPagina`). **Nunca el precio de
  lista.** Va con la hora de la notebook (`ClienteDeLaPagina.ahora`).
- **La página** (`lib/barra_pagina_main.dart`, `lib/features/barra/pagina/`): `PaginaDeLaBarraApp` → PIN →
  `LasCajasScreen` (encargada y jefe) o `StockDeLasBarrasScreen` (repositor), las mismas de la app, con
  `BarraDeLaPagina` en memoria y sus providers reemplazados (`enLaWebProvider` true, `enLaPaginaDeLaBarraProvider` true,
  el OK cada 3 s con `cadaCuantoMirarPedidosDeCierreProvider`, el sonido por Web Audio que se habilita con ENTRAR).
  Arriba, la franja "Romi · Barra 1 · conectada" (o en rojo "Sin conexión… Reconectando") y SALIR. Vuelve a
  conectarse sola al desbloquear el iPhone (`alVolverALaVista`). Sin internet: Outfit de respaldo (la flecha "→" salía
  como cuadradito con Roboto sola).
- **LAS CAJAS en un celular**: STOCK y PRECIOS son solo íconos (el título salía "LAS CAJ…").
- **El instalador** la arma (`build_installer.ps1`, borrando antes `.dart_tool\flutter_build`) y la deja en
  `{app}\barra_pagina` con las tres líneas con nombre (`test/instalador_barra_pagina_test.dart`). Compila: 5,1 MB.
- Pruebas: `test/pagina_de_la_barra_test.dart` (23, la central de verdad en loopback, una tablet y la página),
  `test/pagina_de_la_barra_pantalla_test.dart` (4, la pantalla entera contra la central), 2 en
  `barra_repositorios_test` (la base con la cola), el instalador; las centrales y la encargada: 222 en verde.
  Roturas: `tool/roturas_pagina_de_la_barra.txt` (22 de 22; una destapó que a la base le faltaba el caso de una venta nueva).
- **Probado en el navegador como iPhone** (`preview_start` con `barra-pagina-prueba`, `tool/barra_pagina_servidor_test.dart`:
  una notebook en memoria en 127.0.0.1:8810 y una tablet que vende sola y pide cerrar a los 2 minutos): Romi entra con
  7777, ve las ventas llegar, recarga y entra sola, VER → el OK con los números → ACEPTAR Y CERRAR llega a la notebook
  y queda en su cola; SALIR y Nico 5555 ve STOCK con lo que queda en la Barra 1.
- **Falta con aparatos:** un iPhone de verdad en el router de la barra (que no se vaya a los datos).

### Cómo quedó el 28-nov a la tarde (chat "sigamos en donde estuvimos"; frenado a pedido del usuario al cerrar la etapa 3)

**El plan del 4-dic va por ~84 %. Nada publicado. La fiesta es el viernes 4-dic, sin internet.** Publicar: martes 1 o
miércoles 2-dic. El plan aprobado de este chat (8 etapas) está en
`C:\Users\lover\.claude\plans\sigamos-en-donde-estuvimos-keen-chipmunk-of-671a8863-3f74-4822-8109-d6c57f2a6f8b.md`.
**Hechas las etapas 1, 2 y 3; faltan la 4 a la 8.** Todo guardado y subido. **El usuario cerró el chat el 28-nov a
la tarde ("retomaremos en otro chat"): lo primero al retomar es "¿Volvió el vale?", que decidió ese día** (está
en "Lo que falta, en orden", punto 1).

**Lo que contestó el usuario el 28-nov (no se vuelve a preguntar):**
- **La notebook de la barra: "solo la central (en modo jefe)".** La encargada no tiene vista simple; sigue con sus
  límites (sin ganancia ni precio de lista).
- **Los 4 dudosos de los lugares: sin descuento.**
- **El locutor entra, por el wifi** (sin la app Android del locutor) **y sin música.**
- Las pruebas que necesitan que él apruebe algo (el permiso de pantalla para el mouse, la nube): **al final, y
  esperarlo** ("cuando me desperté me esperás y le acepto y probás").

#### Etapa 1 — Los que agregaron después del sorteo (commit `e1f46a5`)
Pidió: "eso de revisar lista es muy demasiado… que le aparezcan todas las personas que agregaron después del sorteo, y
que sea preciso y que solo tenga que darle a ok… solo avisa". **Con descuento, solo lo que ya estaba cargado al
sorteo** (cuándo se pagó no importa).
- **`AgregaronDespues`** (`eventos/services/agregaron_despues.dart`, puro): sale de
  `RetiroEntradas.entradasDe(a, foto:).cosas` con `!alSorteo`. No hace otra cuenta: es lo mismo que cobra VENDER.
- **Al entrar a VENDER** (`vender_entradas_screen.dart`, `_alEntrar`): el aviso
  (`entradas/widgets/agregaron_despues_dialog.dart`, `avisarQuienesAgregaronDespues`), **antes de la caja**, con un
  solo botón (ENTENDIDO), sin plata; apagada la familia que ya compró lo suyo. No sale con `familiaId` ni se repite
  si baja algo; queda el renglón **"Agregaron después: N · VER"**. Una fiesta **sin anotar** lo dice ("avisale al
  jefe").
- `tool/lugares_de_todas_las_fiestas_test.dart` usa lo mismo: sobre una copia de la base (v82) dio igual que el
  27-nov en las 10 fiestas sorteadas (5 anotadas con 11 familias que agregaron después, 4 sin anotar).
- **`supabase/lugares_cambios.sql` (SIN CORRER, pide su OK):** tabla `lugares_cambios` y un trigger sobre
  `contratos_alumnos` que anota cada cambio de cantidad o precio de mesas adicionales o sillas (solo anota, nunca
  frena). Probado en el sandbox: `tool/lugares_cambios_sandbox.mjs` (12 de 12).
- Pruebas: `test/agregaron_despues_test.dart` (17), 11 nuevas en `test/vender_entradas_pantalla_test.dart`;
  `tool/roturas_agregaron_despues.txt` (15 de 15). Capturas: `build/capturas_lugares_28nov/` (mandadas).
- **Falta, con su OK en el momento:** anotar en la nube las **4 fiestas sin anotar** y el dudoso de la Técnica, con
  los dudosos **sin descuento** (rehacer el SQL de `build/lugares_27nov/` sobre una copia nueva con
  `tool/lugares_para_aceptar_test.dart`; simulacro; huella de cada renglón; **mirar antes que ninguna de esas
  familias tenga entradas ya vendidas con descuento**), y correr `supabase/lugares_cambios.sql`.
- **28-nov (noche): los 16 dudosos de las 4 fiestas, revisados con las copias de la base** (pedido del usuario: "si
  figuraban antes le corresponde descuento"). Se miró cada ficha en `backups\antes_de_vNN.db` y en los zip del 11, 18
  y 26-nov, antes y después de cada sorteo; los huecos, con `mora_fotos.contrato_updated_at` y con lo que dio cada
  sorteo. **3 se cargaron antes del sorteo y van CON descuento aunque se pagaron después; 12 se cargaron después;
  1 queda sin comprobar.** Dos que la lista del 27-nov tenía con descuento se cargaron después. El dudoso de la
  Técnica (lista ya aceptada) también queda sin comprobar. **"Sin descuento" vale solo para los que no se pueden
  comprobar**: el SQL se rehace con esta lista, no con la regla a ciegas. **Un pago posterior al sorteo no prueba
  que se cargó después.** El detalle con nombres: `build/lugares_27nov/dudosos_revisados_28nov.md`, fuera de git.
  **Los dos sin comprobar van sin descuento** (el usuario: "para los dudosos sería sin descuento"). `tildar.json`
  ya quedó rehecho (13 sin descuento, 3 con descuento); `anotar_lugares.sql` es del 27-nov y se rehace sobre una
  copia nueva. El de la Técnica se corrige en la nube. Las dos cosas, con su OK en el momento.

#### Etapa 2 — La notebook de la barra y lo de la revisión de los roles (commit `fb78d95`)
- **La vista simple, probada** (`test/notebook_de_la_barra_a_la_vista_test.dart`, 26; `tool/roturas_notebook_a_la_vista.txt`,
  21 de 21; capturas en `build/capturas_notebook_28nov/`, mandadas). Arreglo: **la vista simple sigue aunque venza el
  modo jefe** (antes desaparecía y quedaba todo a la vista).
- **Lo que la central no aceptó se ve** en el panel de la notebook (`EstadoCentralBarra.rechazos`, `_Rechazos`) y en
  LAS CAJAS (`LineaDeLaCaja`).
- **Una cajera no puede darse sola el OK del cierre**: `BarraConLaRed.anotarPasoDelCierre` pide `daElOk` para `ok` y
  `recontar`; LA ENCARGADA ESTÁ ACÁ va por `responderConLaEncargada`.
- **Un retiro que llega con la caja ya cerrada se guarda** (antes la central lo rechazaba para siempre).
- Los hallazgos 9, 10 y 11: verificados, son límites conocidos, sin cambio.

#### Etapa 3 — El repositor y los frenos del stock (commits `569fce8`, `9d26380`, `bf2fcdd`, `3262e51` y el de esta nota)
- **Datos:** `BarraDelJefe` y `BarraDeLaCaja` leen y escriben `barra_stock_barras` y `barra_stock_movimientos`
  (`repartos`, `guardarReparto`, `movimientosDeStock`, `anotarMovimientoDeStock`, `avisarQueVa`) en `BarraLocal`,
  `BarraNube` y `BarraConLaRed`, con la segunda llave (`reparteElStock`: el jefe; `mueveElStock`: el repositor y el
  jefe) y el aviso a la red.
- **El permiso:** `PermisoOperador.repositorBarra` = **Barra con un 3** (sin SQL). Tilde "Repositor de barra" en
  OPERADORES (no es cajera ni encargada; avisa lo de las versiones). Entra por BARRA: tocar la fiesta abre **STOCK**.
- **STOCK** (`lib/features/barra/repositor/`: `stock_de_la_fiesta.dart`, `texto_del_stock.dart`,
  `dialogos_del_stock.dart`, `stock_de_las_barras_screen.dart`): lo que queda en cada barra y en el depósito,
  REPONER, FALTANTE, ANOTAR LO QUE HAY, ENTRÓ MERCADERÍA, VOY EN CAMINO / YA NO VOY y los movimientos. Sin plata. La
  encargada (LAS CAJAS → STOCK) y el jefe (BARRA → el ícono) la abren **solo para mirar**. Cada guardado pasa por
  `_frenaSinPermiso()`, antes de la ventana y otra vez antes de guardar.
- **El jefe reparte** en PRECIOS → **STOCK POR BARRA** (`jefe/reparto_del_stock.dart`, `_guardarReparto` con
  `_frenaSinModoJefe`; en `test/solo_modo_jefe_test.dart`). GANANCIA ya cuenta lo perdido que anotó el repositor.
- **VENDER** (`widgets/vender_screen.dart`) cuenta con **`StockParaVender`** (`cuentas/stock_para_vender.dart`: una
  sola cuenta para "Quedan", el freno al tocar y el freno al cobrar):
  - lo repartido en la barra de la caja se cuenta con `StockPorBarra.deLaNoche`; lo demás, con el stock general de
    siempre (pregunta y deja "VENDER IGUAL");
  - **con señal** (`hayCentralALaVistaProvider`: conectada a la central, o la notebook que la tiene prendida), **lo
    que no queda no se vende**: un aviso con un solo botón; y al cobrar se mira otra vez (`noAlcanzaPara`), por si
    otra caja vendió las últimas;
  - **sin señal**, aviso en rojo "no sé si repusieron" con NO HAY · HAY, VENDER (una vez por producto y por cuenta);
    el stock queda en negativo y se descuenta de lo que se reponga;
  - arriba, **"Nico está en camino con …"** y **"Se repusieron 12 … en tu barra · quedan N · Nico"** con OK (lo que
    ya estaba repuesto al abrir VENDER no se avisa).
- **Sin internet:** `test/central_barra_test.dart` prueba que el repositor repone con la central caída, la caja vende
  sin stock, y al volver **los tres equipos dan el mismo stock** (3 − 3 − 2 + 24 = 22), sin duplicar.
- Pruebas: `test/repositor_de_barra_test.dart` (20), `test/stock_de_las_barras_pantalla_test.dart` (21),
  `test/reparto_del_stock_test.dart` (11), `test/vender_con_el_stock_por_barra_test.dart` (24), dos en
  `test/operadores_screen_test.dart`, una en `test/central_barra_provider_test.dart`. Roturas:
  `tool/roturas_repositor_y_stock.txt` (34 casos; 32 de 32 atrapadas antes del corte, y dos más del aviso de lo vendido sin stock; una no tenia prueba y destapo un error de OPERADORES: al abrir a un repositor "Barra" venia tildada, arreglado). Capturas: `tool/repositor_y_stock_muestra_test.dart` →
  `build/capturas_stock_28nov/` (6 capturas, mandadas al usuario el 28-nov a la tarde).

**Reglas que dejó la etapa 3 (para lo que se programe después):**
- **Toda pantalla que diga cuánto queda en una barra sale de `StockPorBarra`** (STOCK, LAS CAJAS) **o de
  `StockParaVender`** (VENDER); ninguna hace otra cuenta. Cómo se dice, en `repositor/texto_del_stock.dart`.
- **Un guardado nuevo del stock** va por `BarraConLaRed` (su llave y su aviso a la red) y, en la pantalla, con
  `_frenaSinPermiso()` o `_frenaSinModoJefe()`.
- **Una prueba que monte VENDER y quiera "con señal" reemplaza `hayCentralALaVistaProvider`** (en las pruebas de
  pantalla la red está apagada: es "sin señal").
- **Los precios (con el stock general) no viajan por el wifi del salón**: bajan de la nube antes de la fiesta. El
  reparto y los movimientos sí cruzan. **Repartir el stock de la Técnica con internet, antes del 4-dic.**
- **No tildar "Repositor de barra" ni repartir stock por barra hasta que todos los equipos tengan la versión**: una
  anterior lee el 3 como "sin Barra" y no conoce el reparto.

**Lo que NO se hizo de la etapa 3 (y por qué):**
- **"¿Volvió el vale?" al anular: DECIDIDO el 28-nov ("sí, agregá la pregunta"), SIN PROGRAMAR.** Se le explicó
  con el ejemplo de 2 Speed: hoy anular devuelve el stock siempre; con la pregunta, vuelve solo si el vale está en
  la mano de quien anula. El diseño, en el punto 1 de "Lo que falta, en orden".
- **LA ENCARGADA ESTÁ ACÁ con el PIN del jefe:** quedó como estaba (solo el PIN de una encargada); cambiarlo toca lo
  que acepta la central. El jefe da el OK desde su aparato.
- **Hecho después del corte (28-nov, tarde):** arriba de las cajas, la encargada (LAS CAJAS) y el jefe (BARRA →
  CAJAS) ven **"Se vendió sin stock: 5 speed en la Barra 1 · … Se descuenta de lo que se reponga"**
  (`repositor/aviso_de_vendido_sin_stock.dart`, `vendidoSinStock`; tocarlo abre STOCK; la cajera no lo ve;
  `test/vendido_sin_stock_en_las_cajas_test.dart`). Y un desborde real: en un celular de 360 de ancho el renglón de
  STOCK con "SIN STOCK · se vendieron N de más" se salía; ahora baja de renglón (`Wrap`).
- **Un repositor en una ventana de prueba** (`tool/dos_barras_prueba.dart`) y **el recorrido con el mouse**: esperan
  al usuario (el permiso de pantalla).
- **La suite entera** (`bash tool/suite_por_tandas.sh`, 28-nov a la tarde, sobre lo último): **6.891 en verde, ninguna falla** (372 archivos, 10 tandas; registros en build/suite_28nov). flutter analyze, sin nada nuevo en lo tocado.
- No se probó con tablets ni con el router del salón.

**Lo que falta, en orden (etapas 4 a 8 del plan):**
1. **"¿Volvió el vale?" al anular (decidido el 28-nov; lo primero).** Se le prometió **mostrarle la ventana antes
   de programar** (una captura o maqueta de la pregunta). Lo pensado, para no empezar de cero:
   - **La pregunta**, después del motivo, en todo lugar que anula una venta de la barra (VENTAS de la caja con el
     PIN de la encargada, `ventas_de_la_caja_screen.dart`; LAS CAJAS y CAJAS del jefe, `jefe/cajas_de_la_fiesta.dart`;
     la web): **"¿Volvió el vale?" · SÍ, LO TENGO · NO, YA SE ENTREGÓ.** Con SÍ, como hoy (el stock vuelve). Con
     NO, la plata se anula igual pero **el stock no vuelve**, y queda a la vista del jefe como entregado sin cobrar,
     con quién anuló.
   - **Dónde se guarda:** `barra_anulaciones` no tiene columna para eso (una fila por venta, id fijo, solo se
     agregan). Lo recomendado: **una marca dentro de `motivo`** (sin SQL ni migración, como la mesa reservada en
     el motivo de la mesa libre), leída por un getter de `AnulacionBarra`. Una versión anterior la ve como parte
     del motivo y devuelve el stock: decirlo en las reglas de la versión.
   - **Las cuentas:** las de la plata siguen con `ventasAnuladas` (todas: el cierre, VENTAS, el papel). **Las del
     stock** (`StockDeLaBarra.de`, y `StockPorBarra` en sus dos lugares) pasan a usar solo las anuladas **con el
     vale devuelto**: la venta anulada sin el vale sigue descontando. GANANCIA la cuenta como perdida (se le paga
     igual al proveedor). Una prueba que lea el código, como la de las recetas, para que ninguna cuenta del stock
     use la otra lista.
   - **La silla de la noche:** el vale de una silla lo tiene la recepcionista; hoy la silla va en rojo ("vale
     anulado en la barra: revisar"). No cambiar eso; ver qué dice la pregunta para una venta que es solo sillas.
   - Pruebas de pantalla (cada lugar que anula), roturas, la central (`ReglasDeLaBarra.porQueNoSeGuarda` no
     cambia: es la misma fila) y la suite.
2. **Con el usuario:** el recorrido con el mouse (repositor, reparto, VENDER con y sin señal; pide su permiso de
   pantalla); su OK para la nube (las 4 fiestas, `lugares_cambios.sql`). Las 6 capturas de la etapa 3 ya se le
   mandaron; no dijo nada de ellas todavía.
3. **Etapa 4 — la encargada en su iPhone**: la página que sirve la notebook por el wifi (`guardarDeLaPagina`, el
   saludo solo con el PIN, el acuse "guardada", `/fiesta.json`, `lib/barra_pagina_main.dart`, el instalador).
4. **Etapa 5 — la noche simulada y el repaso entero** (dos barras, cientos de ventas, una tablet 4 horas sin señal,
   el repositor, la tele, Recepción con el chat), las roturas todas, la suite y la tercera revisión independiente.
5. **Etapa 6 — el locutor por el wifi** (v85, `como_lo_nombran`; `docs/SPEC_locutor_2026-11-18.md`), sin música.
6. **Etapa 7 — el plano a todo lo ancho en la tele y Noche y Blanco.**
7. **Etapa 8 — publicar con él** (v83, v84 y v85 sobre una copia; foto de la mora; los SQL con su OK).
Si el tiempo no alcanza, queda afuera primero: Noche y Blanco → el plano ancho → la página del repositor para iPhone
→ el locutor.

**Lo que depende del usuario:** su OK para la nube; **probar ya un iPhone en el router del salón sin internet** con
lo instalado (Recepción → CELULARES → el QR): es el mismo mecanismo de la página de la encargada y del locutor;
instalar la 6.9.4 en las otras dos PCs (foto de la mora "después"); mirar las capturas; el APK en la Quint.

---

### Cómo quedó el 27-nov a las 20:30 (para la historia; lo vigente está arriba)

**El plan del 4-dic va por ~78 %. Nada publicado. La fiesta es el viernes 4-dic, sin internet.** Recomendado: publicar
a más tardar el martes 1 o miércoles 2-dic. Todo lo de abajo está guardado y subido (último commit: el de esta nota).
El detalle de cada cosa está en los bloques que siguen, en este orden.

**Lo que se hizo el 27-nov (tarde y noche), ya guardado:**
- Repaso entero: `flutter analyze` sin errores en `lib/` y `test/`; la suite entera **6.742 en verde y 1 falla, la de
  siempre** (LA ALFONSINA), corrida ANTES de la vista simple de la notebook; después, las pruebas de la barra: 954.
- La revisión independiente de los roles (12 hallazgos) y lo que salió de ahí: la conexión con la central es de la
  persona; VENDER dice el problema del PIN y lo que la central no aceptó; leer el precio de lista mira el rol; **la
  encargada cierra su propia caja sola**; su cambio, con motivo; **el jefe en una tablet se conecta a la central**.
- **La vista simple de la notebook de la barra: programada, SIN PRUEBAS** (ver su bloque).
- **Lugares al sorteo, en la app en uso:** tres alumnos de una fiesta corregidos en la nube con el OK del usuario
  (cargaron después del sorteo y habían quedado con descuento).

**Lo que falta, en orden:**
1. **Lugares al sorteo, las 4 fiestas con la lista sin aceptar: PREPARADO, SIN APLICAR.** El usuario dijo "yo veré
   ahora, otras instituciones, cuando llego a casa": **no aplicar nada sin que lo pida.** Está todo en
   `build/lugares_27nov/` (fuera de git): `anotar_lugares.sql` (un `update` por fiesta, atado a la huella del
   renglón y a que no tenga lista: si el jefe aceptó esa lista desde el programa, no hace nada), `tildar.json`,
   `lugares_para_aceptar.json` y los dos scripts. Se rehace con `tool/lugares_para_aceptar_test.dart` sobre una copia
   nueva (`tool/copiar_base_solo_lectura.py`). Marcaba sin descuento a 10 (las 6 mesas adicionales que el programa
   tilda solo y 4 casos de sillas probados) y dejaba **4 dudosos con descuento** (uno de la fiesta ya aceptada y
   tres de dos de las pendientes): los decide el jefe. La guía con nombres: `build/revisar_lugares_2026-11-27.md`.
   **Las 9 instituciones revisadas una por una (20:40, pedido del usuario: "revisá las 9, porque dijiste cuatro"),**
   con `tool/lugares_de_todas_las_fiestas_test.dart` (el cálculo del programa, `LugaresAlSorteo.vigente`, sobre una
   copia de la base; dice quién tiene hoy más que al sorteo): **una** aceptada el 27-nov y corregida (7 pagan sin
   descuento, 1 dudoso); **cuatro** con la foto tomada en el sorteo (en tres hay familias que agregaron después y ya
   pagan sin descuento solas: 2, 3 y 1; en la otra, nadie); y **cuatro** con la lista sin aceptar (lo de arriba). El
   detalle con nombres quedó al final de `build/revisar_lugares_2026-11-27.md`.
2. **El arreglo de fondo, decidido para ESTA versión** ("no da para estar revisando todas las listas todo el tiempo",
   "poné algo más que sea verificable, más confiable"), sin programar:
   - **un registro en la nube de cada vez que cambia la cantidad de mesas adicionales o de sillas de una ficha**
     (qué había, qué quedó, cuándo, desde qué equipo), escrito por un trigger como el de `mora_cambios` (solo anota,
     nunca frena; SQL solo de agregar, con su OK): vale para todas las PCs y versiones;
   - que el programa decida solo con eso (y con la foto del sorteo) qué va con descuento, y que se vea la fecha;
   - que lo "para revisar" no se acepte sin elegir, y que el jefe pueda corregir una familia de una lista aceptada.
   **Decirle el diseño antes de programar** (maqueta si cambia una pantalla).
3. **La vista simple de la notebook:** escribir sus pruebas y roturas, las capturas, y preguntarle por la misma vista
   para la encargada en la notebook.
4. Del hallazgo 2 de los roles: mostrar los rechazos en LAS CAJAS y en la notebook. Los hallazgos 5, 7, 9, 10 y 11,
   sin verificar.
5. Las 16 listas de roturas y la suite entera sobre lo último; el recorrido por rol y **la tele entera en el
   sandbox** (lo pidió), con capturas.
6. El plan: **Noche y Blanco**; **el repositor** ("Voy en camino", todo al toque, sin stock no se vende con señal y
   con aviso sin señal, lo vendido de más se descuenta de lo repuesto); **la página de la encargada en el iPhone**;
   la noche simulada y la tercera revisión; **el plano a todo lo ancho en la tele**; y **publicar con él** (v83 y v84
   sobre una copia, los dos SQL de la barra, foto de la mora).

**Lo que depende del usuario:** instalar la 6.9.4 en las otras dos PCs y avisar (foto "después"); decir **qué versión
tiene cada PC y en qué pantalla ve "15.000" en una y "10 mil" en otra** (quedó sin resolver); mirar las capturas;
probar el APK en la Quint; las tablets y el router del salón. El PIN maestro queda en 2026 ("lo cambio después").

---

### LEER PRIMERO (lo último): 27-nov a la tarde, chat "decime bien qué falta" — el repaso y la revisión de los roles

**Ojo con las fechas:** lo que más abajo dice "28-nov" se hizo el **27-nov** (git lo fecha el 27; ese chat iba un día
adelantado). La fiesta es el **viernes 4-dic**.

**Plan aprobado de esta vuelta** (con lo que falta, en orden, y lo que depende del usuario):
`C:\Users\lover\.claude\plans\bueno-decime-bien-que-dazzling-biscuit-of-e4f64a94-3528-405d-9a24-a49ca2cb1830.md`.
Recomendación: **publicar a más tardar el martes 1 o miércoles 2-dic**; si el lunes a la noche no cerró la página de
la encargada, quedan afuera primero Noche y Blanco en lo que falte y el plano a todo lo ancho.

**Lo que se repasó (27-nov):** repo limpio y subido; la 6.9.4 instalada en esta PC (base v82); en la nube faltan las
5 tablas de la v83 y la v84 (los dos SQL sin correr); fotos de la mora: la última es "antes de 6.9.4" (faltan las
"después" de la 6.9.3 y la 6.9.4). `flutter analyze`: **0 errores en `lib/` y `test/`** (los 52 que marca son de
`build/cdp_head.dart` y `tool/_tmp_espindola_audit.dart`, fuera de git). **La suite entera: 6.712 en verde y 1 falla,
la de siempre** (LA ALFONSINA; registros en `build/suite_27nov/`). Huella "antes" en `build/huella_antes_27nov.txt`.

**Hecho y guardado (`0a523e9`):** **leer** el precio de lista y la ganancia también mira el rol, sin pedir ninguna
clave: `BarraConLaRed.costos()`, `listaDelProveedorProvider` y `gananciaDelJefeProvider` dan vacío a quien no es el
jefe (también en la web). **El provider no tira un error:** Riverpod 3 reintenta solo al que falla y la pantalla queda
cargando. Prueba `test/precio_de_lista_solo_lo_lee_el_jefe_test.dart` (lee `lib/` y falla si otra pantalla lee
`.costos(`); 3 roturas al final de `tool/roturas_ganancia.txt`. Las pruebas de la barra: 909 en verde.

**Decidido por el usuario el 27-nov (no volver a preguntar):**
- **El recargo por transferencia no cuenta como vendido**: GANANCIA queda como está.
- **La comprobación del rol no pide la clave de nuevo**: es por dentro; quien ya entró no ve ningún cartel más.
- **Sin señal se sigue trabajando.** Con señal, sin stock no se vende. **Sin señal y con el stock en 0, avisa en rojo
  ("Sin señal: no sé si repusieron") y deja vender**; lo vendido de más queda en negativo y **se descuenta solo de lo
  que se reponga** (la cuenta ya lo hace: `StockPorBarra.queda` puede dar negativo). Falta mostrarlo: "Se vendieron
  5 sin stock" a la encargada y al jefe, "24 que traés − 5 ya vendidas = quedan 19" al repositor; la cajera, solo
  "Sin stock". La misma línea tranquila, con "al día hasta las 23:40", en el repositor y la página de la encargada.
- **El repositor:** el botón "Voy en camino" a la barra que elija, y **todo lo que carga se ve al toque** en VENDER,
  LAS CAJAS y la encargada (por el wifi del salón, sin internet).
- **La tele se prueba de nuevo entera en el sandbox** (ahora y después del plano a todo lo ancho), y la barra rol por
  rol (cajera, encargada, repositor, jefe).

**Contestado por el usuario el 27-nov sobre los hallazgos 4, 6 y 8 (no volver a preguntar):**
- **4 → con motivo y anotado:** la encargada cambia el cambio inicial de su propia caja poniendo el porqué, y queda
  en el historial (como un retiro), a la vista del jefe en LAS CAJAS y en el papel del cierre.
- **8 → cambia una regla del 26-nov: "La encargada puede cerrar su caja sin necesidad que le confirmen. Ella es la
  encargada."** Su propia caja la cierra ella sola, sin OK de nadie (como el jefe), y puede ver lo esperado. Hay que
  cambiar `ReglasDeLaBarra.puedeCerrar`, `ok_del_cierre.dart`, la central, las pruebas y las roturas que decían "la
  encargada no se aprueba su propia caja", **la tabla de más abajo y CLAUDE.md**.
- **6 → sí, que se conecte:** el jefe en MODO JEFE desde una tablet se conecta a la central como la encargada. **El
  PIN maestro de fábrica (2026) no le preocupa** ("si es 2026 de fábrica no hay problema"): no insistir con cambiarlo
  y **no hacer el aviso del PIN maestro** que estaba en la lista.
**Programado el 27-nov: el 8** (`ReglasDeLaBarra.cierraSinPedir`: jefe y encargada; lo usan `puedeCerrar` y
`cerrar_caja_barra_screen.dart`; prueba en `test/barra_cerrar_test.dart` y `test/reglas_de_la_barra_test.dart`; 2
roturas en `tool/roturas_permisos_barra.txt`; lo de "su OK no vale para su propia caja" quedó en el código pero ya
no se usa, porque ella no pide el OK). **Programado el 27-nov: el hallazgo 2, en VENDER** (`TextosDeLaCaja.de(problema:, rechazadas:)`: con el PIN que la
central no reconoce la línea dice eso y no "Buscando la central…"; conectada, "· la central no aceptó N" en
amarillo; el cartel de la central lista los últimos 5 motivos; `test/linea_de_la_caja_test.dart`, 3 roturas). **Falta
de ese hallazgo:** LAS CAJAS de la encargada en una tablet y la notebook (`CentralBarra.rechazos`) siguen sin
mostrarlos. **Programado el 27-nov: el 4** (`ReglasDeLaBarra.pisaElCambioInicial`: solo el jefe reescribe el cambio sin motivo desde
VENDER; la cajera **y la encargada** lo ponen una vez antes de vender; después la encargada lo cambia desde LAS CAJAS
con DAR CAMBIO o Corregir, que ya pedían el porqué y quedan en el historial; el botón apagado le dice "El cambio se
corrige desde LAS CAJAS, con el motivo"; guardado y central con la misma regla; `test/reglas_de_la_barra_test.dart`,
3 roturas). **Programado el 27-nov: el 6** (`BarraJefeScreen._buscarLaCentral`: con modo jefe y fuera de la web llama a
`arrancarSiNoHay(nombre: 'Jefe')`; entra con el PIN maestro del aparato y la central lo toma como jefe; prueba de
punta a punta en `test/central_barra_provider_test.dart`: su OK le llega a la cajera sin internet; 2 roturas). **No
se miró todavía en `tool/central_barra_prueba.dart` ni en `tool/dos_barras_prueba.dart`**, que abren esa pantalla
con la red de verdad: va en el recorrido por rol. Las pruebas de la barra: **954 en verde**.

**LA VISTA SIMPLE DE LA NOTEBOOK (27-nov, noche): PROGRAMADA, SIN SUS PRUEBAS. Es lo primero a retomar.** El usuario
vio la maqueta de más abajo y la cambió: **no es una pantalla tapada**. Lo que decidió, en orden:
- La notebook queda en **la vista simple**: solo la central (las cajas conectadas, si está todo subido). **Sin las
  cajas con la plata, sin catálogo, precios ni GANANCIA.**
- **Un logo arriba** (el isotipo, en la barra de arriba, como un adorno): **mantenerlo apretado 2 segundos** pide **la
  clave de esa notebook, la que ese aparato ya tiene para el modo jefe** (`pinMaestroDeEstaPc`; hoy 2026, "lo cambio
  después"). **No es una clave nueva.**
- **La seguridad viene APAGADA** ("que haya una opción para activar esa seguridad, porque si no el jefe va a estar a
  cada rato después de las fiestas"): el candado de arriba abre "Dejar solo la central ahora" y el tilde "Que se
  bloquee sola a los 2 minutos (con la central prendida)", que se recuerda en el equipo.
- **"La central debe estar prendida, si no todos se desconectan"**: en la vista simple **no hay botón APAGAR**
  (`PanelCentralDeLaBarra(sinApagar: true)`); PRENDER sí, por si está apagada. Bloquear nunca toca la central.
Lo programado: `lib/features/barra/jefe/vista_simple_de_la_notebook.dart` (la clave, el tilde, el cartel) y
`barra_jefe_screen.dart` (`_vistaSimple`, el logo `jefe_logo`, el candado `jefe_bloquear`, `PopScope` para que no se
salga para atrás, el uso mirado en toda la app con `pointerRouter.addGlobalRoute`, y al bloquear se cierra lo que
quedó abierto encima). Solo en la notebook (`centralSePrendeAcaProvider`), con modo jefe y fuera de la web.
**Falta:** sus pruebas (`test/notebook_de_la_barra_a_la_vista_test.dart`, sin escribir: el candado, el logo menos de
2 s y 2 s, clave mala y buena, que no se vea ningún "$" ni APAGAR, que se bloquee sola solo con el tilde y la central
prendida, que en la web, en una tablet y sin modo jefe no aparezca), sus roturas, las capturas para el usuario, y la
misma vista para **la encargada en la notebook** (LAS CAJAS: hoy no la tiene; preguntarle). La maqueta vieja
(`docs/maqueta_notebook_bloqueada_2026-11-27.html`) quedó superada.

**Un aviso de la app en uso (27-nov, 19:40), sin tocar nada:** el usuario agregó una mesa después del sorteo y las
entradas le salen "con descuento". Mirado en la nube (solo lectura): esa fiesta se sorteó el **10-nov**, antes de la
regla de la 6.9.2, y **nadie aceptó la lista** (ENTRADAS -> PRECIOS -> REVISAR LA LISTA): su sorteo no tiene
`_lugares`, y hasta aceptarla **todo va con descuento, a propósito**. En esa fiesta el programa dio 12 mesas después
del sorteo. **5 de las 9 fiestas con precios están igual.** Los precios cargados (23-nov, en 8 fiestas): entrada
$15.000, anticipada $10.000 hasta el 30-nov, lugares al 50 % ($7.500). Quedó por saber qué versión tiene cada PC y
en qué pantalla ve "15.000" en una y "10 mil" en otra.

**Cómo siguió (27-nov, 19:49 a 19:56):** el usuario aceptó la lista de esa fiesta, y a un alumno las **2 sillas
cargadas hoy** le quedaron con descuento: en la lista vinieron "para revisar", sin tildar (para las sillas el programa
no tiene huella de cuándo se cargaron: solo mira si hay un pago de sillas anterior al sorteo o el reparto elegido
antes, `lugares_al_sorteo.dart`), y se aceptó así. **Una lista aceptada no se vuelve a abrir desde el programa**
(`RevisionDeLugares`: "ya tiene los lugares"). Con su OK ("Se cargaron hoy", "Sí, aplicala") se corrigió **en la
nube, ese solo alumno y ese solo dato**: en `_lugares` del renglón del sorteo, de `"1,2"` a `"1,0"`. Simulacro antes
(el largo no cambia, todo lo demás igual, el alumno aparece una vez), la escritura atada a la huella del texto, y
comprobado después. No tenía entradas vendidas. La corrección y su vuelta atrás, en
`build/correccion_lugares_2026-11-27.md` (fuera de git; lleva ids).
**DECIDIDO por el usuario el 27-nov (20 hs): "hay que solucionar y llevarlo junto con la versión completa que
estamos haciendo".** Va en esta versión, sin programar todavía. Lo que propongo (decírselo antes de programar):
- **En REVISAR LA LISTA, lo que está "para revisar" no se acepta sin elegir**: cada renglón en duda pide "Lo tenía al
  sorteo" o "Lo agregó después"; hoy viene sin tildar y ACEPTAR lo toma como "lo tenía" (así se escaparon las sillas).
- **Corregir una familia de una lista ya aceptada**, en modo jefe, con internet y por el mismo camino
  (`SorteosMesasRepository.completarLugares`), dejando dicho quién y cuándo.
- Ver si conviene **anotar la huella al cargar** una mesa o sillas con el sorteo hecho (sin columnas nuevas en
  `contratos_alumnos`).

**La revisión de todas las fiestas (27-nov, 20 hs; solo lectura, mi cuenta con la regla del programa; el detalle con
nombres en `build/revisar_lugares_2026-11-27.md`, fuera de git, mandado al usuario):**
- **Una sola fiesta se aceptó tarde** (sorteada el 10-nov, aceptada hoy): ahí **5 familias quedaron con descuento sin
  prueba** de que lo tuvieran al sorteo (3 con sillas, 2 con la mesa adicional). El usuario tiene que decir cuáles lo
  agregaron después; esas se corrigen en la nube como la de hoy.
- **4 fiestas siguen con la lista sin aceptar**: 16 familias en duda (3, 3, 6 y 4) que van a aparecer para revisar.
- **4 fiestas sorteadas con la versión nueva** tienen la foto tomada en el sorteo: nada que revisar.

**Lo que cuenta es CUÁNDO SE AGREGÓ, no cuándo se pagó** (el usuario lo remarcó el 27-nov: "el haber agregado, ahí
está el tema"). Cómo se sabe, para cualquier alumno:
- **Las copias de la base de la PC** (`Documentos\Junior Eventosackupsntes_de_vNN.db`, una antes de cada
  actualización: 9, 11, 15 y 22-nov) tienen `mesa_extra_cantidad` y `sillas_extra_cantidad` de cada ficha ese día
  (se leen con `mode=ro&immutable=1`).
- **La nube, sin depender de ninguna PC:** `mora_fotos.contrato_updated_at` dice cuándo se tocó la ficha por última
  vez en cada foto; si entre el sorteo y una fecha nadie la tocó, nada se cargó en ese tramo. Y `sorteos_mesas` dice
  a qué hora el programa dio una mesa "al cargarla".
Con eso, en la fiesta aceptada el 27-nov: **dos alumnos agregaron después del sorteo y quedaron con descuento** (uno
2 sillas, otro la mesa adicional) y uno queda sin prueba. **La corrección de esos dos está simulada y SIN APLICAR:**
el usuario dijo "bancame, te digo que revises de vuelta, esperame". El SQL listo y las huellas, en
`build/correccion_lugares_2026-11-27.md`; la guía alumno por alumno de las 5 fiestas, en
`build/revisar_lugares_2026-11-27.md`. **No aplicar nada hasta que lo diga.**

**Lo que dejó a la vista (ya decidido arriba):**
- que el jefe pueda **corregir una familia de una lista ya aceptada** (hoy hace falta tocar la nube a mano);
- que **lo que se carga después del sorteo deje huella** (hoy las sillas sin pago anterior quedan "para revisar" y es
  fácil aceptarlas sin tildar);
- **4 fiestas más siguen sorteadas con la lista sin aceptar**: ahí todo va con descuento.

**La maqueta de antes (superada):** la notebook del jefe queda toda la noche con la central prendida (pedido del 27-nov
a la noche): la notebook del jefe queda toda la noche con la central prendida y la pantalla abierta, y cualquiera
podía mirar las cajas. Maqueta: `docs/maqueta_notebook_bloqueada_2026-11-27.html` (`preview_start` con `maquetas`).
Lo que eligió: **el logo** (el isotipo, `assets/icons/isotipo-ej.png`, grande y al centro) y que **desde el logo
también se prenda o apague esta seguridad**. El diseño:
- **Bloqueada muestra solo:** el logo, "CENTRAL DE LA BARRA 1 · PRENDIDA", cuántas cajas conectadas, "Todo subido" o
  cuánto falta, y la hora. Sin plata, cajas, ventas, nombres ni botones.
- **Se abre** manteniendo apretado el logo 2 segundos y escribiendo una **clave de bloqueo propia de esa notebook**
  (no es el PIN del modo jefe; se guarda solo en el equipo). Con la clave: ENTRAR · "Se bloquea sola: SÍ (2 min) / NO"
  · Cambiar la clave.
- **Un candado** arriba a la derecha de BARRA y LAS CAJAS (al lado de la impresora) bloquea en el momento; la primera
  vez pide elegir la clave, y hasta entonces la seguridad está apagada.
- **La central sigue andando siempre**: en el código no depende de la sesión (se apaga solo con su botón,
  `panel_central_barra.dart`), **pero no se probó** dejarla prendida y salir: hay que escribir esa prueba.
- Si se olvidan la clave: cerrar el programa y entrar con el PIN del jefe. **El PIN queda en 2026** ("lo cambio
  después"): el bloqueo frena al que pasa y hace clic, no a quien cierra el programa y conoce el 2026 (se le dijo).
- Va **antes que Noche y Blanco**.

**La suite entera sobre todo lo del 27-nov: 6.742 en verde y 1 falla, la de siempre** (`build/suite_27nov_b/`).

**La revisión independiente de los roles (27-nov): 12 hallazgos.** Los dos primeros, **confirmados leyendo el código**.
**El 1 quedó arreglado el 27-nov** (`quienUsaLaBarraProvider`: "operador:<id>", "jefe" o null; `ClienteDeLaBarra`
recuerda de quién es la conexión, `_deQuien`, y `arrancar` / `arrancarSiNoHay` la rehacen si entró otra persona;
prueba en `test/central_barra_provider_test.dart`, 2 roturas al final de `tool/roturas_permisos_barra.txt`; **toda
prueba que arme un equipo de la barra reemplaza `quienUsaLaBarraProvider`**). **El 2 sigue sin arreglar:**
1. **La conexión con la central queda a nombre de quien usó antes la tablet** (`central_barra_provider.dart`:
   `arrancar` solo la rehace si cambia el nombre de la caja, y `arrancarSiNoHay` no hace nada si ya hay una de esa
   fiesta). Una cajera sale, la encargada entra en esa tablet a LAS CAJAS: lo que acepta, anula o saca lo rechaza la
   central (la sigue viendo como la cajera). Arreglo pensado: el cliente recuerda de quién es la credencial y se
   rehace si cambió la persona.
2. **Los rechazos de la central no se ven en ninguna pantalla** (`CentralBarra.rechazos`,
   `ClienteDeLaCentral.rechazadas` y `problema` no los lee nadie): con el PIN que la notebook no reconoce, VENDER dice
   "Buscando la central…" toda la noche. Arreglo pensado: la línea de VENDER y LAS CAJAS dice el problema del PIN y
   cuántas cosas no aceptó la central.
Los demás (sin verificar por mí; **4, 6 y 8 son decisiones del usuario**): 3) MODO JEFE entra con el PIN maestro de
cada aparato (2026 de fábrica: cambiarlo en todos); 4) la encargada cambia el cambio inicial de **su propia** caja
sin motivo ni rastro (`vender_screen.dart`, y `reglas_de_la_barra_test.dart:113` lo avala); 5) el OK del cierre no
tiene segunda llave en `BarraConLaRed` (que la encargada no apruebe su caja depende de `ok_del_cierre.dart:264`);
6) el jefe en una tablet (no en la notebook) no se conecta a la central; 7) un retiro hecho con la caja abierta que
llega después del cierre se rechaza para siempre ("La caja ya cerró") y dos pruebas se contradicen; 8) la encargada
ve TIENE QUE HABER de su propia caja antes de contar; 9) bordes de `porQueNoSeGuarda` (caja que llega nueva y ya
cerrada; el cambio de la cajera sin mirar si vendió; OK con `caja == null`); 10) el PIN de la encargada en la tablet
de la cajera se valida por nombre; 11) una fila nueva con otro `device_id` se acepta de cualquier rol; 12) la nube
no tiene llave (límite conocido). El informe entero se pegó en el chat; no quedó en un archivo.

**Lo que sigue, en orden:** del hallazgo 2, mostrar los rechazos en LAS CAJAS y en la notebook; mirar los hallazgos
5, 7, 9, 10 y 11 (sin verificar); las 16 listas de roturas y la suite entera sobre lo último; el recorrido por rol y la tele en el sandbox; y después el plan (Noche y Blanco, repositor,
página de la encargada, plano a todo lo ancho, publicar).

---

### Dónde quedó el "28-nov" (en realidad 27-nov; las pruebas a fondo; chat "sigamos, con lo que habíamos quedado")

**El plan para el 4-dic va por ~76 %** (sin el plano impreso). **Nada publicado.** Plan de esta vuelta:
`C:\Users\lover\.claude\plans\sigamos-con-lo-que-glimmering-church-of-6c79e454-a838-433a-885a-f9d233311434.md`. El
usuario pidió probar a fondo todo lo junto y dejar **la pantalla (el plano a todo lo ancho en la tele) para el final**;
lo que no cierra se le dice y se arregla (un error claro, con su prueba; una decisión de cómo tiene que ser, se le
pregunta antes).

**El plano a todo lo ancho, aprobado con un dibujo** (widget del 28-nov: de 57 % a 71 % del ancho en el salón de 151
mesas, recortado al dibujo del escenario al Ingreso con las barras, sin el playón vacío de arriba, agrandado hasta el
alto, sin acostarlo): **"claro, iría así, grande y que muestre todo, entonces se ve muy bien"**. Se programa al final.

**Lo que se probó el 28-nov:**
- **La suite entera** antes de tocar nada: **6.701 en verde y 1 falla, la de siempre** (LA ALFONSINA).
- **El cartel del OK** tiene su prueba (`fed01ec`, en `test/retiros_de_la_encargada_test.dart`): "Cambio de la
  encargada" y "Sacó la encargada" solo si hubo, antes del esperado; 3 roturas atrapadas.
- **La Tele 2 de punta a punta** (`tool/tele_prueba.dart` con `escuelas=distintas`, el celular en el navegador de la
  app): cada tele saluda solo a su escuela (con la mesa encendida y la flecha), elegir la Tele 2 en el celular lo pasa
  a la escuela de esa tele, GIRAR desde el celular, la página cerrada y abierta entra sola, apagar y prender las teles
  y el celular se engancha solo, CAMBIAR LA ESCUELA pregunta antes ("Sus celulares pasan solos") y las dos teles lo
  avisan, y con la misma escuela "Las dos" saluda en las dos. **Nada que arreglar.** Capturas:
  `build/capturas_tele2_28nov/` (11).
- **La barra recorrida por rol** (`tool/barra_prueba.dart`): el jefe carga botellas en CATÁLOGO y arma "cómo se
  prepara" (Fernet con coca $3.200 → gana $2.800; Speed con vodka $1.886 → $6.114: las cuentas dan); la cajera vende en
  efectivo y por transferencia, VENTAS sin plata, ANULAR con su PIN dice "Ese PIN no es de una encargada de barra"; el
  jefe saca $5.000 y da $2.000 de cambio (TIENE QUE HABER $10.000); la cajera cuenta a ciegas $10.000, pide el OK, el
  cartel dice +$2.000, −$5.000, esperado $10.000, "Justo, sin diferencia", y el papel del cierre, LAS CAJAS del jefe y
  las de la encargada dicen lo mismo; GANANCIA: le debo $8.085,71 (suma justa), ganancia $12.914,29; la encargada ve
  CATÁLOGO Y PRECIOS sin precio de lista ni recetas. Capturas: `build/capturas_barra_28nov/` (13).
- La huella de la base antes y después: **IGUAL**.

**Lo que se encontró y se arregló (con su prueba y sus roturas):**
1. `2923777` — **En PRECIOS, el stock de lo que no se vende solo se perdía**: la lata de Speed (va entera en el vodka,
   sin tildar) dejaba escribir el stock y al guardar no se guardaba ni contaba como cambio. Ahora se guarda como un
   precio sin tildar (`activo: false`, precio 0: no se ofrece en VENDER ni dice "$ 0"). Prueba en
   `test/barra_jefe_pantalla_test.dart`; 3 roturas al final de `tool/roturas_precios_con_lista.txt`.
2. `ec6c3f1` — **VENDER ignoraba el stock que el jefe le carga al trago con receta**: el vodka decía solo lo que alcanza
   el Speed (sin Speed controlado, nada), y LAS CAJAS contaba sus 12. Ahora dice lo menor de los dos. Pruebas en
   `test/recetas_en_la_barra_test.dart`; roturas en `tool/roturas_recorrido_28nov.txt`.
3. **El recargo sin elegir, a la vista** (el usuario eligió **"que avise el 5 %"**: la regla del 3-nov,
   `recargoDeArranque`, no cambia). Antes, si el jefe no lo había puesto, PRECIOS decía "sin" y la encargada "Sin
   recargo por transferencia en esta fiesta", y cada cobro arrancaba con el último de la tablet (la primera vez, 5 %).
   Ahora PRECIOS muestra "—" con el aviso en amarillo (`jefe_recargo_sin_elegir`: "Sin elegir: cada tablet arranca
   cada cobro con el último que usó (la primera vez, 5 %), y la lista impresa no lo dice. Elegilo para que todas
   arranquen igual.") y **bajar desde "—" es elegir "sin"** (se guarda en 0: los cobros arrancan sin); la encargada lee
   "Recargo por transferencia sin elegir: cada tablet arranca con el último que usó (la primera vez, 5 %)." El
   recargo de PRECIOS es `double?` (null = sin elegir). Pruebas en `test/barra_jefe_pantalla_test.dart` y
   `test/encargada_de_barra_test.dart`; 4 roturas en `tool/roturas_recorrido_28nov.txt`. Las pruebas de la barra: 831
   en verde.
4. **"Elegí qué lleva" ofrece solo lo que puede ir adentro de un trago** (el usuario: "perfecto", después de
   aclararle que el catálogo no cambia): ni otro trago (con receta, o de una categoría que empieza con "Trago";
   "Para los tragos" sí va) ni una silla de la noche (`esSillaDeLaPuerta`); lo ya elegido en una receta se sigue
   mostrando (`_puedeIrAdentro`). Prueba en `test/barra_jefe_pantalla_test.dart`; 3 roturas en
   `tool/roturas_recorrido_28nov.txt`. Las pruebas de la barra: 832 en verde.
5. **El papel, el cartel del OK y LAS CAJAS dicen quién sacó o dio la plata** (el usuario: "que diga quién"):
   "Cambio que dio Romi", "Sacó Romi y el jefe" (el jefe se anota "Jefe" y se lee "el jefe"); sin nadie anotado,
   "la encargada". La cuenta guarda quiénes (`CierreDeBarra.dieronCambio`, `retiraron`, de `hechoPor`) y los rótulos
   son `rotuloDelCambio` / `rotuloDeLoSacado` (`quienesLoHicieron`). Pruebas en
   `test/retiros_de_la_encargada_test.dart` y `test/barra_jefe_pantalla_test.dart`; 5 roturas en
   `tool/roturas_recorrido_28nov.txt` (y `tool/roturas_retiros_pantalla.txt` puesta al día: 10 de 10). Las pruebas
   de la barra: 875 en verde.

**Preguntas para el usuario: contestadas todas.**
- GANANCIA dice "Se vendió $21.000" y LAS CAJAS "$21.400": la diferencia es el recargo por transferencia, que GANANCIA
  no cuenta como venta. **Contestado el 27-nov: "El recargo es el recargo por transferencia, no cuenta como
  vendido."** Queda como está.

**Las roturas de la barra y la tele, todas juntas sobre lo de hoy: 262 de 262 atrapadas** (14 listas; registros en
`build/roturas_28nov/`). La primera pasada dio 258: tres de `tool/roturas_precio_de_lista.txt` tenían el texto de
antes de cambios posteriores (puestas al día) y una mostró que **nada vigilaba el recargo de un trago con receta en
GANANCIA** (la cuenta estaba bien): prueba nueva en `test/cuenta_del_proveedor_test.dart`.

**Lo que falta, en orden:**
1. Que mire las capturas (las de hoy y las de ayer: `build/capturas_4dic/`, `build/capturas_tele_27nov/`) y conteste las
   la pregunta que queda arriba (la de GANANCIA y el recargo; las otras ya las contestó).
2. **Noche y Blanco** en todas las pantallas de la barra (`DisenioBarra`; cada aparato elige el suyo).
3. El repositor, "¿Volvió el vale?", LA ENCARGADA ESTÁ ACÁ del jefe, el aviso del PIN maestro y **sin stock no se vende**;
   con el repositor, GANANCIA lee el stock por barra (hoy lo perdido da 0).
4. La página de la encargada en el iPhone, la noche simulada y la tercera revisión independiente.
5. **Al final, el plano a todo lo ancho en la tele acostada** (aprobado): la muestra con los 10 salones de verdad
   (`tool/tele_salones_de_verdad_test.dart`) antes, que el nombre en grande, la mesa encendida y la flecha sigan bien,
   y la fluidez de nuevo en el emulador. El borde verde y la fluidez real, con la Quint.

---

### Lo del 27-nov a la noche (chat "sigamos"; lo vigente está arriba)

**El plan para el 4-dic va por ~73 %** (sin el plano impreso). **Nada publicado.** Plan de esta vuelta:
`C:\Users\lover\.claude\plans\sigamos-peaceful-harp-of-314d8c5f-dfb0-4642-a1b4-8e6c4ea26b76.md`.

**La maqueta de recetas y estilos no lo convenció** (27-nov): tiene que notarse qué es el **precio de lista** y qué es
**lo que se le debe al proveedor**, intuitivo, fácil, **sin redundancia**; "si se cumple eso, todo ok". Los estilos
Noche y Blanco no los objetó. **Se rehízo: `docs/maqueta_barra_proveedor_y_retiros_2026-11-27.html`** (commit
`dac99a8`, abierta en Edge y mandada): siempre "Precio de lista · lo que me cobra el proveedor" y "Le debo al
proveedor"; PRECIOS en dos bloques (lo que se vende, con el precio de lista del trago "sale de la receta" sin
escribirse; y las botellas de los tragos con lo que trae); GANANCIA con **dos formas** (A recomendada: "LE DEBO AL
PROVEEDOR" grande, una sola tabla por lo que entrega el proveedor y la ganancia por producto plegada; B: una tabla
por lo vendido); la encargada con SACAR EFECTIVO · DAR CAMBIO · "Corregir (se anotó mal algo)"; los renglones nuevos
del papel del cierre ("Cambio de la encargada", "Sacó la encargada"); y "Lo que saqué por repetido". **Aprobada el
27-nov con la forma A de GANANCIA** (se le mandó sola, cerrada y abierta: `build/maquetas/ganancia_forma_A.png`;
contestó "Perfecto"). Se programan las pantallas.

**Respuestas del 27-nov sobre RETIRO y CAMBIO (no volver a preguntar):** la encargada los anota **también en su propia
caja**, y **siempre con motivo, desde su sesión de encargada** (no con su PIN en la tablet de la cajera).

**Hecho el 27-nov: RETIRO y CAMBIO por dentro, sin pantalla** (mientras nadie anote uno, nada cambia a la vista):
- `BarraDelJefe.movimientosDeCaja` / `anotarMovimientoDeCaja(movimiento, quien:)` y
  `BarraDeLaCaja.movimientosDeLaCaja` (solo leer), en `BarraLocal`, `BarraNube` (avisa a los equipos; sin la tabla en la
  nube, ninguno), `BarraConLaRed` (segunda llave `manejaLaPlataDeLasCajas` y aviso a la red), `BarraEnMemoria` y
  `_LoQueSubio`. **Sobre una caja cerrada no se anota** (`CajaYaCerrada`); el mismo, dos veces, queda uno.
- `barra_caja_movimientos` en `tablasDeLaRed`, **antes que `barra_cierres`** (la tablet guarda en ese orden: tiene el
  retiro antes que el OK) y en `_enOrden`; `ReglasDeLaBarra.porQueNoSeGuarda` lo acepta solo de encargada o jefe, en
  cualquier caja abierta, sin cambiar uno que ya está.
- `SyncEngine.bajarCierresDeLaBarra` baja los retiros antes que el OK (si los retiros no bajan, el OK baja igual).
- Los 4 lugares del efectivo esperado pasan `movimientos:` (LAS CAJAS por `ResumenDeCajas.de` y `cajasDelJefeProvider`,
  cerrar caja dos veces, `cuentasParaElOk`); la prueba que lo exige ya no está en espera. `ResumenDeCajas` suma
  `retirado` y `cambioAgregado`, y `ResumenDeCaja.cambioDespuesDelCierre` / `diferenciaConTodo` dicen si un retiro (o una
  anulación) llegó después del cierre, sin tocar lo anotado: **falta mostrarlo en la tarjeta** (va con las pantallas).
- Pruebas: `test/retiros_de_la_encargada_test.dart` (SQLite de verdad, la llave, la regla, la central de verdad de
  punta a punta, LAS CAJAS y el OK), dos en `test/barra_cerrar_test.dart` (el retiro antes y mientras espera el OK) y
  tres en `test/barra_nube_test.dart`. Roturas: 19 nuevas en `tool/roturas_retiros.txt` (**23 de 23 atrapadas**). La
  suite entera: **6.671 y 1 falla, la de siempre** (`modal_cobro_masivos_medios_pago_test.dart`, LA ALFONSINA).

**Cómo se programan (decidido por Claude el 27-nov, con la maqueta aprobada):**
- **Datos:** `BarraDelJefe.costos(evento)` / `guardarCosto(costo, quien:)` y `guardarReceta(receta, quien:)` (sacar un
  ingrediente es guardarlo con `activo: false`, mismo id fijo), en `BarraLocal` (con la cola), `BarraNube`,
  `BarraConLaRed` (llave `veElCostoYLaGanancia`), `BarraEnMemoria` y `_LoQueSubio`.
- **PRECIOS:** las columnas de hoy (VA · PRODUCTO · PRECIO · STOCK · AVISAR DESDE) más **PRECIO DE LISTA** y **GANO**.
  Un producto con receta (o de la categoría "Tragos") muestra el precio de lista gris "sale de la receta" y "RECETA ▸"
  plegada (ingredientes del catálogo, cc o unidades, "+ AGREGAR INGREDIENTE", "Cuesta · ganás por trago"). Lo que va
  por cc en alguna receta sale de la lista y va al bloque **LAS BOTELLAS DE LOS TRAGOS** (precio de lista de la botella
  y cuánto trae). Todo se guarda junto con GUARDAR CAMBIOS; COPIAR DE OTRA FIESTA trae también lista, botellas y recetas.
- **GANANCIA** (pestaña nueva, solo `veElCostoYLaGanancia`): elegir las fiestas (desde · hasta), la tarjeta grande "LE
  DEBO AL PROVEEDOR", la cuenta una vez, la tabla de `CuentaDelProveedor.paraElProveedor`, la ganancia por producto
  plegada, VER POR FIESTA y IMPRIMIR (A4, con botón).

**Hecho el 27-nov (tarde), con la maqueta aprobada:**
- `9a1d048`: los datos (`costos`, `guardarCosto`, `guardarReceta` en las cinco barras; la llave es
  `veElCostoYLaGanancia`). Pruebas: `test/precio_de_lista_y_recetas_datos_test.dart`.
- PRECIOS (`jefe/precios_de_la_fiesta.dart`): columnas VENDO A · STOCK · AVISAR DESDE · **PRECIO DE LISTA** (con
  centavos: `PesosConCentavosFormatter`) · **GANO**; la receta plegada en cada trago (categoría "Tragos" o con
  receta), con ingredientes del catálogo, cc o entero, "Cuesta · ganás por trago" (`costoDeUnTrago`, la misma cuenta
  que GANANCIA, redondeada a pesos en pantalla); un trago **sin** ingredientes deja escribir su precio de lista; el
  bloque **LAS BOTELLAS DE LOS TRAGOS**; COPIAR DE OTRA FIESTA trae lista y recetas. Lee `listaDelProveedorProvider`
  (solo PRECIOS del jefe y GANANCIA). 5 pruebas nuevas en `test/barra_jefe_pantalla_test.dart` (42 en verde) y la
  muestra `Jefe_2b_precios_con_lista_pc.png` (`tool/barra_jefe_muestra_test.dart`).
- PRECIOS cerrado: una prueba compara `costoDeUnTrago` con `CuentaDelProveedor` (dan lo mismo), y las roturas
  `tool/roturas_precios_con_lista.txt` (**14 de 14 atrapadas**).
- `74203a6`: **la pestaña GANANCIA** (`jefe/ganancia_del_jefe.dart`; `PestanaBarraJefe.ganancia` al final, solo con
  `veElCostoYLaGanancia`): las fiestas que se rinden juntas (`fiestasDeLaTanda`: la elegida y las de los 3 días que
  siguen; CAMBIAR las elige), "LE DEBO AL PROVEEDOR" grande, la cuenta una vez, la tabla de `paraElProveedor` (sin lo de
  precio de lista 0, como la silla: `deLoQueSePaga`), la ganancia por producto plegada, VER POR FIESTA, el aviso con
  IR A PRECIOS si falta una lista, e IMPRIMIR en A4 (`GananciaPdf`, por `imprimirGananciaProvider`). **Le debo redondea
  el centavo de cada botella** (así la tabla suma justo): un Fernet con coca debe $3.797,34 aunque PRECIOS diga
  "$ 3.797". **Lo perdido es 0 hasta que exista el repositor** (no hay de dónde leer el stock por barra todavía).
  Pruebas: `test/ganancia_del_jefe_test.dart` (9); muestra `Jefe_8_ganancia_pc.png`; roturas
  `tool/roturas_ganancia.txt` (**7 de 7 atrapadas**).

- `3cde476`: **SACAR EFECTIVO · DAR CAMBIO · Corregir** en el detalle de una caja de LAS CAJAS (`_plataDeLaCaja` y
  `_PedirMovimiento` en `jefe/cajas_de_la_fiesta.dart`; solo con `mandaEnLaBarraProvider`, y los botones solo con la
  caja abierta): TIENE QUE HABER con de dónde sale, LO QUE SE HIZO CON LA PLATA, monto y motivo obligatorio (con
  motivos rápidos), Corregir suma o resta. La tarjeta, el cartel del OK y el papel del cierre dicen "Cambio de la
  encargada" y "Sacó la encargada" (`masOMenos`, en `cuentas/pesos.dart`) solo si hubo, y la tarjeta avisa si algo llegó
  después del cierre. Pruebas: 4 en `test/barra_jefe_pantalla_test.dart` y 1 del papel en
  `test/retiros_de_la_encargada_test.dart`; muestras `Jefe_9_caja_con_retiros_pc.png` y `Jefe_10_sacar_efectivo_pc.png`;
  roturas `tool/roturas_retiros_pantalla.txt` (**7 de 7 atrapadas**). **El cartel del OK no tiene una prueba que mire sus renglones nuevos.**

- **Solo el jefe ve el precio de lista y la ganancia** (lo recordó el usuario el 27-nov: "la encargada no puede ver la
  ganancia"). Se encontró un hueco y se cerró: BARRA del jefe se abre sin modo jefe para mirar, y PRECIOS mostraba
  igual el precio de lista y GANO. Ahora PRECIOS lo muestra y lo lee solo con `veElCostoYLaGanancia` (sin modo jefe:
  sin esas columnas, sin recetas ni botellas, y sin leerlas). Pruebas: la encargada sin GANANCIA, PRECIOS sin modo jefe
  (con `lecturasDeCostos` = 0) y la regla para cada rol; 2 roturas más en `tool/roturas_precios_con_lista.txt` (16 de 16).

- **Cómo se ve un trago en PRECIOS (decidido el 27-nov, a la noche; no volver a preguntar).** La receta abierta en
  el medio de la lista le pareció rara ("pensaba que iba a estar el precio del trago en sí; como mucho un pequeño
  subtexto de cómo preparar"). Se le ofrecieron dos formas y pidió la que yo recomendara, pensando en que sea fácil
  para la cajera, la encargada y el repositor, y que lo delicado y el cálculo queden en modo jefe y sean sencillos.
  Se eligió **la A con la receta en chico**: el trago es un renglón más (precio de venta, precio de lista **calculado**
  por las botellas, gano); **debajo del nombre, una línea chica** "200 cc Fernet 750 + 500 cc Coca-Cola 2,25" (o
  "Agregar cómo se prepara"), y **tocándola se abre una ventanita** ("Fernet con coca · cómo se prepara") con lo que
  lleva y, de cada cosa, su precio de lista y cuánto trae la botella. **En la lista no hay receta abierta ni bloque de
  botellas**, y no quedan textos de más ("sale de la receta", "falta", "más o menos"). Las botellas que no se venden
  solas no aparecen en la lista. Para la cajera, la encargada y el repositor no cambia nada (no ven recetas ni costos);
  cada vodka sigue descontando su Speed del stock. Código: `_lineaDeLaReceta`, `_abrirReceta` y `_receta` en
  `jefe/precios_de_la_fiesta.dart`. Pruebas en `test/barra_jefe_pantalla_test.dart` (47 en verde); roturas
  `tool/roturas_precios_con_lista.txt` (**17 de 17**). Muestras rehechas como serían de verdad (cada trago con su receta,
  ninguno con un precio de lista inventado; `listaYRecetas` en `tool/barra_jefe_muestra_test.dart`):
  `Jefe_2b_precios_con_lista_pc.png`, `Jefe_2c_como_se_prepara_pc.png`, `Jefe_8_ganancia_pc.png` en
  `build/capturas_4dic/`.

**La prueba de las teles del 27-nov (noche), con todo lo de la barra junto** (capturas en `build/capturas_tele_27nov/`):
- Las pruebas de la tele, el tótem y la puerta (63 archivos): **1.170 en verde**.
- Los salones de verdad sacados de nuevo de una copia (ahora 10: apareció uno de 12 mesas): el tótem en la tele se ve
  igual que en la PC, como mucho 0,56 % de los puntos distintos a la vista (`tool/tele_salones_de_verdad_test.dart`, 25
  en verde).
- **La app de prueba en el emulador `Recepcion_Tablet` como una tele de 1920×1080 a 320 dpi y con `-gpu
  swiftshader_indirect`** (dibuja con el procesador, como la vez pasada): **la espera, 48-49 por segundo** (el 25-nov,
  40-44); **la bienvenida, lo peor 27 al aparecer el nombre, después 31-37** (el 25-nov, 24-29 y 35-44): igual o mejor.
  Con el celular (el navegador por `adb forward tcp:8787`, código de la tele): entrar como Juli, elegir la Tele 1, dos
  ingresos con su bienvenida (nombre en la pista, mesa encendida, la flecha, "Tele 1 · la maneja Juli"), GIRAR a vertical
  desde el celular.
- **Salir y volver:** Inicio en la tele, 20 s afuera y volver: mismo proceso, el tótem esperando, el celular seguía
  conectado y el ingreso siguiente saludó bien. **La página del celular cerrada y abierta de nuevo: entra sola como Juli,
  con su tele elegida y los ingresos**. Con la app nueva instalada encima (otro proceso), el celular se volvió a enganchar
  solo ("La maneja: Juli"). En la app de prueba lo marcado vive en memoria (se pierde si se cierra la app, a propósito);
  la de verdad lo guarda en la base: eso lo cubren las pruebas (`modo_tele_test`, `tele_dos_escuelas_test`, …).
- **Encontrado: un borde verde finito alrededor de toda la app después de apretar una tecla del control** (en el inicio
  del emulador no aparece). Se probó apagar el resaltado de foco de Android en el tema y en la vista: **no cambió nada**,
  y se volvió atrás (no se deja un cambio que no demostró servir). Puede ser del emulador (una tablet con Android 16, que
  muestra el foco del teclado). **Preguntarle si en la Quint aparece un borde verde al usar el control**; si aparece,
  buscarlo con la tele de verdad. Una vez el primer OK solo puso ese borde y no abrió el menú (con la app recién
  instalada, el primer OK sí lo abrió): parece el modo táctil del emulador.
- Huella de la base antes y después: **IGUAL**. Roturas de la tele (`tool/roturas_tele.txt`) sobre todo lo junto:
  **56 de 56 atrapadas**.
- **Pedido del usuario (27-nov, noche): "el plano debe tomar toda la tele en horizontal, en lo posible".** Hoy, en una
  tele acostada, el salón de 151 mesas ocupa ~58 % del ancho (1.120 de 1.920 puntos) y deja franjas a los costados:
  el dibujo no se agranda (`CuadroDelSalon`, "no cambia de lugar ni de tamaño" desde la 6.6.2). **Propuesta: recortar
  al dibujo (mesas, escenario y sectores, sin el borde vacío del playón de arriba) y agrandarlo hasta donde dé el alto,
  sin deformarlo ni acostarlo** (con el escenario a un costado no se entiende): en ese salón quedaría ~75 % del ancho.
  Hacerlo para la tele acostada (no para la parada), con `tool/tele_salones_de_verdad_test.dart` y los 10 salones de
  verdad, mirando que el nombre en grande, la mesa encendida y la flecha sigan bien, y medir la fluidez de nuevo
  (el salón más grande es más para dibujar). Mostrarle antes la muestra con los 10 salones.
- **Falta de esta prueba:** la Tele 2 de punta a punta en el sandbox (la ventana `tool/tele_prueba.dart` en Windows con
  las dos teles, o dos emuladores); está cubierta por las pruebas, no se recorrió hoy. Y la Quint de verdad (la fluidez
  real, el borde verde, el control).

**Lo que falta, en orden** (27-nov, cierre del chat; el usuario: "vemos cómo queda en el próximo intento, retomamos
en otro chat"):
1. **Que mire las capturas** (`build/capturas_4dic/`: `Jefe_2b` PRECIOS, `Jefe_2c` cómo se prepara, `Jefe_8` GANANCIA,
   `Jefe_9` una caja con retiros, `Jefe_10` SACAR EFECTIVO; `build/capturas_tele_27nov/`: la tele en el emulador) y
   diga si va así. **Correr la suite entera** (`bash tool/suite_por_tandas.sh`): la última, 6.698 y 1 falla (la de
   siempre), fue antes de la receta en chico; después corrieron PRECIOS, GANANCIA y las 1.170 de la tele, la puerta y
   el tótem.
2. **La tele: el plano a todo lo ancho** (el pedido y la propuesta, en "La prueba de las teles del 27-nov", arriba):
   muestra con los 10 salones de verdad antes de programarlo, después la fluidez de nuevo. **El borde verde:** se ve
   en el próximo intento con la Quint (el usuario: "vemos cómo queda en el próximo intento"); si aparece en la tele de
   verdad, buscarlo ahí. **La Tele 2 de punta a punta** en el sandbox (la ventana `tool/tele_prueba.dart` con las dos
   teles, o dos emuladores). Quedan para la tele de verdad: la fluidez real, el control y dos teles por el router.
3. **Noche y Blanco en todas las pantallas de la barra** (`DisenioBarra`; hoy solo VENDER elige; BARRA del jefe, LAS
   CAJAS, VENTAS y cerrar caja van siempre en Noche): cada aparato elige el suyo y vale para todas sus pantallas.
4. Desde el punto 3 de "Lo que falta" de abajo (el repositor, "¿Volvió el vale?", sin stock no se vende, el aviso del
   PIN maestro), y lo demás en el mismo orden. **Con el repositor, GANANCIA tiene que leer el stock por barra** (hoy lo
   perdido da 0).

---

### Lo del 26-nov (23:40), chat "¿En qué quedamos?" (para la historia; lo vigente está arriba)

**El plan para el 4-dic va por ~60 %** (sin el plano impreso). **Nada publicado.** Rama
`feature/v4.6-cierre-por-sesiones`, último commit `0b74a37`, árbol limpio (salvo los archivos sueltos de siempre:
`Nuevo Documento de texto.txt`, `scripts_ver_cola.dart`, `scripts/descartar_cola.dart`, `docs/SPEC_locutor_…`, que
no son de esto). **Todo en un solo chat, uno detrás del otro** (el chat "Planes para barra" ya no se usa). Plan de
esta vuelta: `C:\Users\lover\.claude\plans\en-que-quedamos-resilient-river-of-eeea9ef1-6b33-47bb-97b6-06dbde9b3e95.md`.

**Esperando al usuario:** que mire la maqueta `docs/maqueta_recetas_y_estilos_2026-11-27.html` (PRECIOS con la
receta, GANANCIA con "Para el proveedor", y los estilos Noche y Blanco mejorados en VENDER, LAS CAJAS y STOCK) y diga
"va así" o qué cambia. **Sin su OK no se programan esas pantallas.**

**Lo que decidió esta noche (no volver a preguntar):**
- Columnas de GANANCIA: Vendidas · Perdidas · Precio de lista · Le debo · Se vendió · Ganancia. **Ningún botón** de
  "traer lo que quedó": cada fiesta carga su stock en PRECIOS como hoy.
- **Estilo:** cada aparato elige **Noche o Blanco**, pero mejores, en **todas** las pantallas de la barra.
- **Los tragos llevan receta** (el jefe por WhatsApp): trago de 1 L, receta editable; Fernet con coca = 200 cc de
  fernet + 500 cc de coca + hielo; vodka = 500 cc de vodka + 1 Speed de 250 cc + hielo; lista **por botella** (y por
  lata). "Más o menos, para calcularle". El usuario aclaró: **las botellas se calculan con los tragos vendidos** y
  **no se muestra en la barra cuántas botellas quedan** ni la empezada ("es raro"). Lo demás lo decide Claude.
- Decidido por Claude con eso: lo que va **en cc** no tiene stock en la barra, solo calcula botellas para GANANCIA;
  lo que va **entero** (el Speed) **baja de su stock** como si se vendiera suelto (si no, al contar faltarían Speed y
  se pagarían dos veces); un trago no se frena por la receta; sin la lista de un ingrediente, el trago debe lo que sí
  se sabe y la ganancia queda sin saber, con aviso.
- La receta, la lista, las botellas y GANANCIA **solo las ve el jefe**. La receta (sin plata) viaja a la tablet para
  descontar el Speed; la lista no baja nunca a una tablet.
- **La receta no se muestra en ningún lado salvo PRECIOS del jefe, y ahí va plegada** ("RECETA ▸ 2 ingredientes", se
  abre al tocarla): pedido del usuario el 26-nov, "no creo apropiado" que se vea al vender. En VENDER el trago es un
  producto más (el vodka dice "Quedan N" sin decir por qué); el vale, el ticket, VENTAS y el cierre no la nombran (la
  venta se guarda igual: el Speed se descuenta solo en la cuenta del stock); el repositor ve el Speed con su número,
  sin explicar que baja con los vodkas, y no ve nada de los tragos. La maqueta ya está así.

**Hecho esta noche, cada paso con pruebas, roturas a propósito y commit:**
1. `ed21ab9` — la maqueta y las decisiones.
2. `776e4bf` — **la encargada ve CATÁLOGO Y PRECIOS solo mirando** (botón en LAS CAJAS,
   `widgets/catalogo_y_precios_screen.dart`; `ReglasDeLaBarra.veCatalogoYPrecios` y `veElCostoYLaGanancia`) y **las
   recetas**: modelos `RecetaBarra` y `CostoBarra`, la cuenta `RecetasDeLaBarra` (`paraElStock`, `loQueBaja`,
   `alcanzaPara`) y `CuentaDelProveedor` con tragos y `paraElProveedor`. Roturas 15 de 15.
3. `99220c0` — **la v84** (`barra_costos` con `contenido_cc`, `barra_recetas`, `barra_caja_movimientos`), las listas
   del sync (`barra_costos` no baja en Android: `SyncEngine.bajaLoDelJefe`), el modelo `MovimientoDeCaja` y el SQL de
   la nube `supabase/migrations/20261127120000_barra_costos.sql` con las tres (**sin correr**). Roturas 6 de 6, y
   `tool/romper_una_regla.sh` ahora reintenta la restauración y frena si un archivo no vuelve igual (Windows lo tuvo
   tomado y dejó `local_database.dart` roto; se reparó).
4. `3a9cebf` — CLAUDE.md con la v84 y las recetas.
5. `969e46b` — **VENDER y CAJAS descuentan el Speed de cada vodka** y el vodka dice "Quedan N" por su Speed
   (`recetas(evento)` en los repositorios). Una prueba lee el código: toda cuenta del stock pasa por `paraElStock`.
6. `0b74a37` — **el efectivo esperado del cierre cuenta retiros y cambio** (`CierreDeBarra.cambioAgregado` y
   `retirado`), solo la cuenta. Roturas 4 de 4.

**Lo que falta, en orden:**
1. **Con el OK de la maqueta:** PRECIOS del jefe con Lista, "Trae" y la receta (guardar `CostoBarra` y `RecetaBarra`
   por `BarraDelJefe`/`BarraLocal`/`BarraNube`, que todavía no los guardan; COPIAR DE OTRA FIESTA los trae); la
   pestaña **GANANCIA** con su papel A4 (con botón, nada sale solo); y **Noche y Blanco** en todas las pantallas de la
   barra (`DisenioBarra` ya existe para VENDER).
2. **RETIRO y CAMBIO de la encargada:** leer y guardar `MovimientoDeCaja` en `BarraDelJefe` y `BarraDeLaCaja` (y sus
   cinco implementaciones: `BarraLocal`, `BarraNube`, `BarraConLaRed`, `BarraEnMemoria`, `_LoQueSubio` de
   `tool/barra_prueba.dart`); `barra_caja_movimientos` en `tablasDeLaRed` (y `_enOrden` de `central_barra.dart`) con su
   regla en `ReglasDeLaBarra.porQueNoSeGuarda` (solo encargada y jefe); pasar `movimientos:` en los 4 lugares que dicen
   el esperado (LAS CAJAS por `ResumenDeCajas.de`, cerrar caja dos veces, el OK); **sacarle el `skip` a la última
   prueba de `test/cierre_con_retiros_test.dart`**; y la pantalla (maqueta antes).
3. El **repositor** (Barra con un 3: `PermisoOperador.repositorBarra`, OPERADORES sin borrar el 3, su pantalla); "¿Volvió
   el vale?" al anular; el jefe con LA ENCARGADA ESTÁ ACÁ; el aviso del PIN maestro de fábrica en CAJAS; **sin stock no
   se vende de verdad** con el stock por barra en VENDER (hoy pregunta y deja VENDER IGUAL), con `loQueBaja`.
4. La página de la encargada en el iPhone (Parte 3).
5. La noche simulada y la tercera revisión independiente (también con tragos y retiros).
6. Las pantallas en la app de verdad con capturas por rol (el APK en el emulador con la central en esta PC).
7. La v83/v84 sobre una copia de la base real, los SQL con su OK (el de la v83 y el de la v84 están sin correr), la
   foto de la mora, y publicar cuando él diga.
8. Después: el plano impreso entero.

**Recordarle al usuario:** cambiar el PIN maestro de fábrica en las dos notebooks de la barra (el mismo en las dos).
La falla de siempre de la suite (`modal_cobro_masivos_medios_pago_test.dart`, LA ALFONSINA, del cobro de cuotas) se
mira aparte con él.

---

**26-nov (noche): el audio 77 del jefe y todo en un solo chat.** Plan aprobado:
`C:\Users\lover\.claude\plans\te-mando-un-audio-buzzing-bubble-of-20d8810b-4918-44eb-a5f5-b6b73407e7e6.md`.
- **Todo se hace en un solo chat, sin sesiones en paralelo** (pedido del usuario: tenía que vigilar sesiones que
  apuntaban a cosas distintas). La rama del APK (`claude/priceless-borg-e85cd6`) se junta acá con su OK (dado al
  aprobar el plan); la sesión que coordinaba no se usa más.
- **El audio** (`Desktop\AUDIOS ADRI\77.mp4`, pasado a texto en esta PC): el jefe carga con el stock el **precio de
  lista** del proveedor y quiere ver, solo él, **lo que le tiene que pagar al proveedor y la ganancia**, juntando
  varias noches (pide bebida para vie-sáb-dom-lun y rinde el martes; la primera tanda, del 4 al 7-dic). Ejemplo: 200
  latas a $1.500, venta $5.000, vende 2 → recaudó $10.000, a pagar $3.000, ganancia $7.000. Decidido: la lista **en
  PRECIOS, por fiesta**; **cada fiesta con su stock** y un botón para traer lo que quedó de la anterior; **lo perdido se
  paga igual** (a pagar = vendidas + perdidas, por la lista). Tabla nueva `barra_costos` en la **v84** (con
  `barra_caja_movimientos`), `CuentaDelProveedor`, pestaña **PROVEEDOR**. **Maqueta primero.**
- **Anular sigue como el 26-nov** (el audio decía "todos pueden anular"; la cajera no anula).
- **El posnet no lleva nada en la app**: quien vende mira el verde del posnet y aprieta CONFIRMAR como hoy. Lo de
  "Cobrá en el posnet" y "APROBADO EN EL POSNET" de abajo **no se hace**.
- **Las pantallas de la barra, atractivas, intuitivas y fáciles para cada rol** (cajera, encargada, repositor, la
  barra): maqueta con dos o tres estilos lado a lado antes de programarlas, y todo probado en el sandbox (el APK en el
  emulador con la central de verdad en esta PC) con capturas por rol antes de dárselo.
- **Hecho esa noche:** la rama del APK juntada (`74d3306`; la reconexión de la barra era el mismo cambio que
  `18b1b5d`: en sus cinco archivos quedó la versión de acá). La suite entera sobre lo junto: **6.568 y 1 falla**, la
  de siempre (`modal_cobro_masivos_medios_pago_test.dart`, LA ALFONSINA, no es de la barra). Roturas de la nube sin
  stock 3 de 3. Las maquetas mandadas (`docs/maqueta_precio_de_lista_2026-11-26.html`, con el agua arriba, y
  `docs/maqueta_estilos_de_la_barra_2026-11-26.html`: A Noche dorada · B Mostrador claro · C Semáforo); **esperan sus
  respuestas** (los tragos: lista por vaso o botella y rinde; las columnas; SUMAR o reemplazar; qué estilo). El SQL
  `supabase/migrations/20261127120000_barra_costos.sql` escrito, **sin correr**.
- **La encargada prende la central sin modo jefe** (lo pidió el 26-nov, noche: esa noche la notebook no se pone en
  modo jefe y nadie ve lo recaudado ni la ganancia): ya es así en el código (LAS CAJAS de la encargada en la notebook
  tiene PRENDER LA CENTRAL; en la tablet no). **Falta la prueba** que lo vigile (en `test/encargada_de_barra_test.dart`
  solo está el caso de la tablet) y que no vea CATÁLOGO, PRECIOS ni GANANCIA. Recordarle: **cambiar el PIN maestro de
  las dos notebooks** (el mismo en las dos). Su propia caja la aprueba el jefe; si no está, CERRAR SIN ESPERAR.
- **La encargada ve el CATÁLOGO y los PRECIOS de venta, solo mirando** (pedido del 26-nov, noche: "que pueda ver el
  catálogo y precio, y hasta ahí"). **No ve el precio de lista, lo que se le debe al proveedor ni la ganancia.** Hoy
  no ve esas pestañas (`test/encargada_de_barra_test.dart` lo exige): cambia. En `ReglasDeLaBarra`: `veCatalogoYPrecios`
  (encargada y jefe), `cambiaCatalogoYPrecios` (solo jefe, como hoy) y `veElCostoYLaGanancia` (solo jefe). PRECIOS de
  la encargada sin la columna "Lista", sin guardar, COPIAR ni SUMAR LO QUE QUEDÓ; y la doble llave al guardar.
- **La cuenta de GANANCIA, programada y probada (26-nov, noche), sin pantalla:**
  `lib/features/barra/cuentas/cuenta_del_proveedor.dart` (`CuentaDelProveedor.de`, `FiestaParaLaGanancia`,
  `GananciaDeUnProducto`, `GananciaDeUnaFiesta`), en centavos. Vendidas y lo vendido salen de
  `CierreDeBarra.deLaFiesta` sobre las ventas de **la noche de la fiesta** (`CajasPorDia`; si esa noche no tuvo cajas,
  la que más vendió; las otras noches van en `otrasNoches`); perdidas de `StockPorBarra.deLaNoche` (faltantes y lo que
  dio de menos un conteo, netos, nunca negativas); le debo = (vendidas + perdidas) × lista; sin lista, no entra y se
  avisa (`faltaLaLista`); la silla con lista 0 es toda ganancia; el recargo por transferencia aparte. "Quedaron": del
  stock por barra, y sin reparto, el stock del jefe menos lo vendido. `test/cuenta_del_proveedor_test.dart` (15, con
  el ejemplo del audio y el del agua) y `tool/roturas_precio_de_lista.txt` (**13 de 13**).
- **Roturas de la tele después de juntar el APK: 56 de 56**, después de arreglar la prueba de la R6 (tomaba un
  "escuelas" viejo y a veces dejaba pasar la regla rota; ahora una ida y vuelta con "hola", `9749f20`).
- **Lo que sigue, en orden:** la v84 (`barra_costos` y su modelo `costo_barra.dart`, las listas del sync, fuera de
  `tablasDeLaRed` y de lo que baja la tablet), `ReglasDeLaBarra.veCatalogoYPrecios` y `veElCostoYLaGanancia`, la
  prueba de la encargada en la notebook (PRENDER LA CENTRAL sí; CATÁLOGO y PRECIOS solo mirando; nunca GANANCIA), y
  con sus respuestas a las maquetas, las pantallas (PRECIOS con la Lista y SUMAR LO QUE QUEDÓ, la pestaña GANANCIA y
  su papel A4); después, el repositor, RETIRO y el cambio.
- **Las respuestas a las maquetas y los tragos con receta (26-nov, 22:30; chat "¿En qué quedamos?", que sigue; el
  chat "Planes para barra" ya no se usa).** Plan aprobado:
  `C:\Users\lover\.claude\plans\en-que-quedamos-resilient-river-of-eeea9ef1-6b33-47bb-97b6-06dbde9b3e95.md`.
  - Columnas de GANANCIA: **así**. **Ningún botón** de "traer lo que quedó" (sale TRAER / SUMAR LO QUE QUEDÓ).
    Estilo: **cada aparato elige Noche o Blanco**, mejorados, en todas las pantallas de la barra.
  - **Los tragos llevan receta** (el jefe por WhatsApp): trago de 1 L, receta editable; Fernet con coca = 200 cc de
    fernet + 500 cc de coca + hielo; vodka = 500 cc de vodka + 1 Speed de 250 cc + hielo; lista por botella. "Más o
    menos, para calcularle". El usuario aclaró: **las botellas se calculan con los tragos vendidos** (40 × 200 cc ÷
    750 = 10,67) y **no se muestra en la barra cuántas botellas quedan** ("es raro"); lo demás lo decido yo.
  - Decidido: fernet, coca y vodka (en cc) **no tienen stock en la barra**, solo lista y cuánto trae; entran en
    GANANCIA y en "Para el proveedor". **Lo que va entero (el Speed) baja de su stock** como si se vendiera suelto
    (si no, al contar faltarían y se pagarían dos veces); sin Speed, el vodka no se vende. `StockPorBarra` no cambia:
    recibe las ventas con el ingrediente entero adentro. La receta va por fiesta en PRECIOS (`barra_recetas`, v84).
  - Maqueta mandada: `docs/maqueta_recetas_y_estilos_2026-11-27.html` (PRECIOS con recetas, GANANCIA con "Para el
    proveedor", Noche y Blanco en VENDER, LAS CAJAS y STOCK). Las pantallas esperan su OK; los datos y la cuenta no.
  - **Hecho esa noche:**
    - **La encargada ve CATÁLOGO Y PRECIOS solo mirando**: `ReglasDeLaBarra.veCatalogoYPrecios` (encargada y jefe) y
      `veElCostoYLaGanancia` (solo jefe); botón en LAS CAJAS → `widgets/catalogo_y_precios_screen.dart` (sin
      campos, sin guardar, sin costo). Pruebas en `test/encargada_de_barra_test.dart` (26 en verde, con la central en
      la notebook sin modo jefe) y la pantalla en `test/modo_barra_cerrado_test.dart`.
    - **Las recetas, datos y cuenta (sin pantallas ni base todavía):** `datos/receta_barra.dart` (`RecetaBarra`,
      `UnidadDeReceta` cc · unidad; id `UuidUtils.barraRecetaId`), `datos/costo_barra.dart` (`CostoBarra`: lista y
      `contenidoCc`; id `UuidUtils.barraCostoId`), `cuentas/recetas_de_la_barra.dart` (`RecetasDeLaBarra`:
      `paraElStock` suma lo entero adentro de cada trago con precio 0, `loQueBaja`, `alcanzaPara`) y
      `CuentaDelProveedor` con tragos (costo por receta, `porReceta`, y **`paraElProveedor`** por botella y lata, que
      suma lo mismo que "Le debo"; sin la lista de un ingrediente, el trago debe lo que sí se sabe y la ganancia no
      se sabe). `test/recetas_de_la_barra_test.dart` (12) con los números de la maqueta. El SQL de la nube suma
      `contenido_cc` y la tabla `barra_recetas` (sin correr).
    - **Roturas: 15 de 15** (6 de la encargada en `tool/roturas_permisos_barra.txt`, 9 de las recetas en
      `tool/roturas_precio_de_lista.txt`). Dos agujeros que encontraron, cerrados: LAS CAJAS con otro rol (prueba
      nueva que la monta con cajera, repositor y encargada) y la cuenta del fernet que dependía de un `cc!` para
      compilar (ahora `trae`).
  - **La v84, programada (26-nov, noche):** `crearTablasV84` (`barra_costos` con `contenido_cc`, `barra_recetas`,
    `barra_caja_movimientos`) y `_version = 84`; el modelo `datos/movimiento_de_caja.dart` (`MovimientoDeCaja`,
    `TipoMovimientoDeCaja`: retiro · cambio · ajuste_cambio, con motivo); en `sync_engine.dart` las tres en las listas
    (costos y recetas con lo de carga, los movimientos con lo del cobro), **`barra_costos` no baja en Android**
    (`SyncEngine.bajaLoDelJefe`, `enAndroidParaLaPrueba`, en `_pullTable`) y `barra_recetas` en `tablasDeLaBarra`.
    El SQL de la nube con las tres (sin correr). Pruebas: `test/migracion_v84_test.dart` (de 80 y de 83 a 84, la
    vuelta atrás, la copia `antes_de_v84`), `test/sync_tablas_v84_test.dart`; `migracion_v83_test.dart` quedó fija
    en la 83 y `sync_tablas_v77_test.dart` suma las recetas. Roturas: `tool/roturas_v84.txt` (**6 de 6**). Una de
    ellas dejó `local_database.dart` roto: Windows tenía el archivo tomado un rato después de la prueba y el
    respaldo no se pudo copiar. **`tool/romper_una_regla.sh` ahora reintenta la restauración y frena si no queda
    igual.** **Falta de la v84:**
    leer y guardar en `BarraDelJefe`/`BarraLocal`/`BarraNube`, y `barra_caja_movimientos` en `tablasDeLaRed` con
    su regla en `porQueNoSeGuarda` (va con RETIRO).
  - **El Speed del vodka en VENDER y CAJAS (26-nov, noche):** `recetas(evento)` en `BarraDelJefe` y `BarraDeLaCaja`
    (`BarraLocal`, `BarraNube` —sin la tabla en la nube devuelve ninguna—, `BarraConLaRed`, `BarraEnMemoria` y la
    ventana de prueba); `CajasDeLaFiesta.recetas` y VENDER pasan las ventas por `paraElStock`; en VENDER el vodka
    dice "Quedan N" por su Speed (`alcanzaPara`) y la cuenta se lleva el Speed de cada vodka (`_enLaCuenta`).
    `test/recetas_en_la_barra_test.dart` (5, con una que lee el código: **toda cuenta del stock pasa por
    `paraElStock`**, y otra que ninguna pantalla de la cajera, la encargada o el repositor nombre el costo).
    Roturas 5 de 5 (al final de `tool/roturas_precio_de_lista.txt`). **"Sin stock no se vende" sigue como antes
    (pregunta y deja VENDER IGUAL)**: el freno de verdad va con el stock por barra en VENDER.
  - **El efectivo esperado con retiros y cambio, la cuenta (26-nov, noche):** `CierreDeBarra` tiene `cambioAgregado`
    y `retirado`, y `efectivoEsperado` = cambio + cambio agregado + efectivo − retirado; `CierreDeBarra.de` y
    `deLaFiesta` reciben `movimientos:` (lo de otra caja no cuenta; el mismo llegado dos veces, una).
    `test/cierre_con_retiros_test.dart` (7) y `tool/roturas_retiros.txt` (4 de 4). **Falta:** que la barra lea y
    guarde los movimientos (`BarraDelJefe`/`BarraDeLaCaja` y sus cinco implementaciones), que viajen por la central
    (`tablasDeLaRed` + `porQueNoSeGuarda`: solo encargada y jefe), y pasarlos en los 4 lugares de la app que dicen el
    esperado (LAS CAJAS con `ResumenDeCajas.de`, cerrar caja dos veces, el OK). **La prueba que lo exige ya está
    escrita, en espera (`skip`)**: al cablearlo, sacarle el `skip`. Y las pantallas RETIRO y CAMBIO (con maqueta).
  - **Lo que sigue, en orden:** (1) la **v84** con tres tablas: `barra_costos` (con `contenido_cc`), `barra_recetas`
    y `barra_caja_movimientos` (retiro · cambio · ajuste_cambio, solo se agregan filas; borrador del modelo
    `MovimientoDeCaja` en el scratchpad de este chat: rehacerlo si se perdió) + las listas de `sync_engine.dart`
    (`barra_costos` **no se baja en Android**; `barra_recetas` va en `tablasDeLaBarra`; `barra_caja_movimientos` en
    `tablasDeLaRed` y su regla en `ReglasDeLaBarra.porQueNoSeGuarda`: solo encargada y jefe) + leer y guardar en
    `BarraDelJefe`/`BarraLocal`/`BarraNube`; (2) **toda cuenta del stock recibe las ventas por
    `RecetasDeLaBarra.paraElStock`** (`StockDeLaBarra.deLaNoche` en `barra_jefe_providers.dart` y en
    `vender_screen.dart`) y sin stock no se vende en `vender()` con `loQueBaja`; (3) el efectivo esperado del cierre
    con retiros y cambio (`CierreDeBarra`: 17 lugares lo usan; un test que exija pasar los movimientos); (4) las
    pantallas con su OK de la maqueta: PRECIOS (Lista, Trae, receta), GANANCIA con su A4, RETIRO y CAMBIO en LAS
    CAJAS, el repositor (Barra con un 3), Noche y Blanco.
- El plan para el 4-dic va por **~57 %** (sin el plano impreso). Orden: el repositor, RETIRO y el cambio (v84), sin
  stock no se vende → el precio de lista y PROVEEDOR → la página de la encargada → la noche simulada y la tercera
  revisión → las pantallas en la app de verdad y la tele con el APK → la v83/v84 sobre una copia, los SQL y publicar
  cuando él diga.

**26-nov (tarde): la barra sólida y segura — hecho hasta el PIN en la central y las reglas por rol** (sin publicar,
en esta rama). Plan de esta vuelta, aprobado por el usuario el 26-nov a la tarde:
`C:\Users\lover\.claude\plans\c-users-lover-desktop-plan-sp-fancy-wall-of-db314a36-8fe0-4cf2-ad8e-bd040753c86b.md`.
**Su orden: primero la barra sólida y segura ("los permisos totalmente") y las pantallas en la app de verdad (barra,
repositor, encargada, la tele); después publicar; al final el plano impreso** (los planos ya se entregaron y el sorteo
pasó). Lo hecho esta tarde, cada cosa con sus pruebas y sus roturas a propósito:
- **El vale impreso dice la fecha y la hora reales** (`173037f`): el de la 01:30 dice "Sáb 05/12/2026 - 01:30"; la
  caja sigue siendo de la noche en que se abrió (regla del usuario: "la caja se toma de cuando se abrió; lo que se
  imprime, con la hora real"). Cambia lo que decía el plan del 25-nov.
- **La barra se reconecta sola al volver al wifi** (`18b1b5d`, 6 de 6 roturas): lo vio el usuario (otro wifi, volvió y
  no se actualizó hasta apagar y prender la central). Reproducido en el sandbox: el cambio de red mataba los sockets de
  la búsqueda y ninguno se volvía a abrir. Ahora `RespondeBusqueda` y `BuscaCentral` se reabren solos (y la búsqueda
  renueva el socket cada 30 s sin respuesta), y `VigiaDeLaRed` (las direcciones del equipo cada 5 s) hace que la
  notebook reabra lo que contesta y relea sus direcciones, y que la caja sin central busque de nuevo. **El botón
  PRENDER / APAGAR LA CENTRAL queda igual** (lo pidió él). **No probado con un cambio de wifi de verdad.** La Tele 1
  (`RespondeLaTele1`, `lib/features/tele/busqueda_de_la_tele.dart`) tiene la misma falla: se le pidió a la sesión del
  APK que la arregle igual.
- **El stock por barra se cuenta por noche y cruza sin internet** (`0f7b740`, 5 de 5 roturas): `StockPorBarra.deLaNoche`
  (las pantallas usan esta), la barra de cada caja con `barraDe` (que ahora compara con `claveDeBarra`), y
  `barra_stock_barras` y `barra_stock_movimientos` en `tablasDeLaRed`.
- **El PIN en la central y las reglas por rol** (`c4aacf4`, 19 de 19 roturas en `tool/roturas_permisos_barra.txt`):
  ver "La barra, quién puede qué (26-nov)" abajo.
- **La suite entera sobre todo esto: 6.558 de 6.559.** La que falla no es de la barra:
  `test/modal_cobro_masivos_medios_pago_test.dart` lee la base real de esta PC (solo lectura) y marca, en LA ALFONSINA
  (26-dic), cobros de una silla extra por transferencia o mixto **sin el cargo por canal** ("falta cargo canal"). Es
  del cobro de cuotas, no se tocó: **mirarlo aparte con el usuario** (puede ser cómo se cargó esa fiesta o un error de
  verdad en el cobro). Las roturas de antes siguen atrapadas (barra por noche, reconexión, stock, repositor).

**Sesión en paralelo:** "APK de prueba de la app de verdad para la Google TV" (`local_fb5b1a19-2401-455c-acd2-0da86e83153d`,
en su worktree): comprueba que la v83 no corta la bajada sin las tablas del stock en la nube, arregla la línea de LA
FIESTA, arma el APK de la app de verdad (32 y 64 bits) y se lo manda. Se le pidió traer `18b1b5d` y arreglar la Tele 1.
Cuando termine, mirar su rama y juntarla (preguntándole al usuario).

**26-nov: retomado después de la 6.9.4** (ya publicada; está en esta rama). Este chat coordina las sesiones en
paralelo: **cuando el usuario dice "actualizá", se actualiza acá y se les manda lo mismo a todas** (memoria
`actualiza-va-para-todas-las-sesiones`). El plan de esta vuelta, aprobado el 26-nov:
`C:\Users\lover\.claude\plans\sigamos-donde-nos-quedamos-expressive-matsumoto-of-dc76a2f7-5e35-44c8-9dc7-efce16acf58a.md`
(hasta el paso 3 de su lista, **y juntar cada rama apenas cierre su revisión**, con la suite, las roturas y el sandbox
sobre lo junto: lo pidió él).

**El plan aprobado** (25-nov, con el usuario):
`C:\Users\lover\.claude\plans\donde-nos-quedamos-porque-inherited-sedgewick-of-b24f55ff-68c4-4d3e-875a-b0916b95685c.md`.
La fiesta es la **Técnica Pinaroli, el 4-dic**: la primera de verdad, **sin internet**, todo por el wifi. El usuario
quiere **todo prolijo, punto por punto, y sin bugs** ("lo importante es que todo esto no tenga bugs, por favor").
**No se publica nada hasta que él lo diga**, cuando no haya más cambios.

### Dónde está cada parte

| Parte | Dónde | Estado (26-nov) |
|---|---|---|
| 0. Maquetas | acá | **Hechas y contestadas**: `docs/maqueta_encargada_iphone_y_repositor_2026-11-25.html` (`preview_start` con `maquetas`) |
| 1. La tele | **junta en esta rama el 26-nov** (merge `17c6f5b`, desde `claude/peaceful-golick-fa7148`; su sesión ya no la toca; `docs/CONTEXTO_TELE_COMO_TOTEM_2026-11-24.md`) | revisión independiente con 11 arreglos (`37109b8`), punta a punta en el sandbox y en el emulador con la huella IGUAL (en su rama); sobre lo junto: la suite entera **6.514**, con una sola falla que era de los finales de línea de esta carpeta (arreglada en la prueba, `452d8bd`), y las roturas de la tele **52 de 52**. **Falta:** el APK de prueba suelto para el usuario, y mirar por qué LA FIESTA de la app de prueba del emulador no mostró la línea de cada escuela (en las pruebas y la muestra sí) |
| 2. La barra por día de operación y la madrugada | **junta en esta rama el 26-nov** (merge `53303ba`, desde `claude/sleepy-jepsen-bea21a`; su sesión ya no la toca) | revisión independiente con 9 arreglos (`eb07be5`); sobre lo junto: la suite entera **6.424 y 0 fallos**, las roturas **41 de 41** y la huella de la base IGUAL; **el recorrido con el mouse no se hizo** (el usuario no dio el permiso de la pantalla el 26-nov) |
| 3. La encargada en el iPhone por el wifi | acá, **después de juntar la Parte 2** (toca los mismos archivos) | sin empezar |
| 4. El repositor y el stock por barra | acá | **la base (sin pantallas) cerrada el 26-nov**: las pruebas de la segunda revisión, las roturas y el SPEC (ver abajo) |
| 2b. La barra sólida y segura (26-nov, tarde) | acá | **hecho hasta el PIN en la central y las reglas por rol**: el vale con la hora real, la reconexión al volver al wifi, el stock por noche que cruza sin internet, el PIN y quién puede qué (arriba). Falta: repositor, retiros y cambio de la encargada (v84), el precio de lista y PROVEEDOR, la noche simulada y la tercera revisión (el posnet no lleva nada: 26-nov, noche) |
| 5. Publicar | con el usuario, cuando él diga | — |
| 6. El plano impreso entero | después de publicar la barra | spec aprobada (en `Desktop\PLAN`), con lo que agregó él el 26-nov; sin empezar |

Las dos sesiones salieron de la rama feature (comprobado: su base es `2a0a0d2`). A las dos se les mandó el 25-nov
que el usuario pide **sin bugs**: tests, suite entera, roturas, sandbox con la huella IGUAL **y una revisión
independiente**. Cuando terminen, sus ramas hay que juntarlas acá (preguntarle al usuario antes de mezclar).

### Lo que decidió el usuario (todo, para no volver a preguntar)

- **Tele:** girar (Horizontal · Vertical · Dar vuelta), sin PIN; **cada tele con su escuela**, cambiada desde el
  celular de la recepción **sin PIN** (la tele está con la cuenta del jefe), con un cartel que confirma; cuando una
  cambia, a la otra le salta "La Tele 1 cambió a ESCUELA B · MANTENER · CAMBIAR". Todas las escuelas de los
  próximos 30 días guardadas sin internet; Personalizar sigue en la PC y avisa al guardar.
- **Barra por día de operación** ("como un cierre de caja en su fecha"): la caja se abre a la tarde y sigue hasta
  las 7-8; corte al mediodía. El cierre queda igual (a ciegas solo el efectivo, transferencia aparte, el OK de la
  encargada).
- **La central de la barra sigue en la notebook, una por barra.** Cada barra tiene su router **Mercusys MW305R**, en
  las dos puntas, **sin cable**. Se pueden unir por wifi (WDS); la guía está en `docs/GUIA_ROUTERS_DE_LAS_BARRAS.md`
  y **la prueba él en la oficina** (todavía no avisó). El programa tiene que andar unidas o cada barra sola. Las teles
  quizás vayan con un router cada una (no sabe): en redes separadas, las dos como Tele 1.
- **La encargada usa su iPhone**: la notebook le sirve una página por el wifi (sin internet la web no anda). Ve las
  cajas de esta noche y, arriba, los otros días; **acepta cierres y anula ventas con motivo**; el jefe también entra
  con su PIN; el aviso con sonido como en la maqueta (un toque la primera vez). Si el iPhone se bloquea o se apaga,
  retoma solo.
- **El repositor** (permiso Barra con un 3, sin SQL): trabaja con su celular, **la app si es Android y la página de
  la notebook si es iPhone**. El jefe carga el stock general **y reparte con cuánto arranca cada barra**; el depósito
  es **el límite**; "Entró mercadería" lo anota el repositor diciendo de dónde vino; repone del depósito o **de una
  barra a otra con el porqué**; deja dicho cuántas quedan y, si no da (se sabía que eran 70 y hay 68), **el motivo**
  (rota, congelada, vencida, se perdió, otro); el aviso de "está quedando poco" lo pone el jefe **por barra**; **sin
  stock no se vende**, el repositor manda **"voy en camino" a la barra que elija** y al reponer vuelve en verde;
  a las cajeras de esa barra y a la encargada les sale "Se repusieron…".
- Se compran 5 tablets Android; 4 impresoras, una por tablet. Las sillas sueltas ya las vende cualquier cajera.

### La base del repositor (Parte 4): lo hecho, sin pantallas

- `docs/SPEC_repositor_y_stock_por_barra_2026-11-25.md` (**su sección de conteos quedó vieja**: manda el código, ver
  abajo).
- `lib/features/barra/cuentas/nombre_de_barra.dart`: `claveDeBarra` (sin espacios de más, minúsculas, sin acentos)
  y `esElDeposito`. **Todo lo que compara barras pasa por ahí.**
- `lib/features/barra/datos/stock_en_la_barra.dart` (`barra_stock_barras`: el reparto del jefe, id fijo por fiesta,
  producto y clave de barra) y `movimiento_de_stock.dart` (`barra_stock_movimientos`: entrada, reposicion, traspaso,
  faltante, conteo, en_camino, en_camino_no; **solo se agregan filas**; `FotoDeStock`).
- `lib/features/barra/cuentas/stock_por_barra.dart`: **la única cuenta del stock por barra** (`StockPorBarra.de`,
  `sePuedeVender`, `cuantoSePuedeReponer`, `errorAlReponer`, `errorAlPasar`, `errorAlDescontar`, `errorDelReparto`,
  `errorAlSacarDelReparto`, `enCamino`, `enAviso`, `fotoDe`, `ajustePara`).
- **v83** en `local_database.dart` (`crearTablasV83`, solo `CREATE … IF NOT EXISTS`) y en `sync_engine.dart` (las
  listas: columnas, lo del cobro, la bajada, el orden de subida y `_tablasSinRevisarBorrados`). **El locutor pasa a la
  v84.** SQL de la nube `supabase/migrations/20261125120000_barra_stock.sql`, **sin correr**.
- Tests: `test/stock_por_barra_test.dart`, `test/migracion_v83_test.dart`, `test/sync_tablas_v83_test.dart` (y
  `migracion_v82_test.dart` quedó con la versión fija en 82). **106 en verde al 26-nov** (72 del stock, con el grupo
  "LA SEGUNDA REVISIÓN"). Roturas: `tool/roturas_repositor.txt`, **31 de 31 atrapadas el 26-nov** (las 22 de antes,
  cuatro con el texto puesto al día con el código, y 9 nuevas de la segunda revisión).

**Cómo cuenta un conteo (lo más delicado; lo encontraron dos revisiones independientes):** un conteo ("quedan 40")
guarda en `conocido` una `FotoDeStock`: **de toda la fiesta**, la venta más alta que conocía de cada caja y la fila
más nueva que conocía de cada equipo. Después, lo de ese lugar = lo contado + lo que pasó **después de contar**:
- antes de contar = lo que conocía, **o** una venta de esa caja con número menor que la que conocía, **o** una fila
  de un equipo anterior a la última que conocía de él (el orden dentro de una caja y de un equipo es seguro); solo si
  no hay otra forma, la hora;
- un conteo reemplaza a otro **solo si sabía** que el otro fue antes; los que no se conocen valen los dos y se toma
  **el que da menos**; la hora nunca decide entre conteos;
- un producto ya contado **no cambia el reparto ni el stock general** (`errorDelReparto` lo frena): lo que se mueve
  lo anota el repositor.

### La barra, quién puede qué (26-nov, decidido por el usuario; programado hasta el PIN y las reglas)

**La regla, en un solo lugar: `ReglasDeLaBarra`** (`lib/features/barra/cuentas/reglas_de_la_barra.dart`), con
`RolEnLaBarra` (cajera, encargada, repositor, jefe, central). La usan las pantallas, el guardado y la central. El rol
de este aparato: `rolEnLaBarraProvider` (`providers/barra_del_jefe_provider.dart`: modo jefe, o el PIN y los permisos).

| | Cajera | Encargada | Repositor | Jefe |
|---|---|---|---|---|
| Abrir caja con el cambio (opcional) | sí | habilitada, en una tablet | no | — |
| Cambiar el cambio después | **una sola vez, si abrió sin cambio y no vendió** (hecho); después no | **sí, con el porqué y el historial** (falta: v84) | no | sí |
| Vender | sí (sin stock, no) | habilitada, en una tablet con su caja | no | — |
| Transferencia | mira el verde del posnet y aprieta CONFIRMAR **como hoy** (la app no cambia: 26-nov, noche) | — | no | — |
| Sus ventas | **sin plata** (hecho) | — | no | — |
| Anular, con motivo | **no** (hecho) | **sí**: desde su aparato, o **con su PIN en la tablet de la cajera** (hecho) | no | sí |
| Retirar efectivo, con el porqué | no | **sí** (falta: v84) | no | sí |
| LAS CAJAS con la plata, imprimir | no (hecho: CAJAS no muestra nada sin encargada o jefe) | sí | no | sí |
| Contar al cerrar | a ciegas, pide el OK | da el OK; **su propia caja no** (hecho) | — | da el OK y cierra sin pedir |
| Ver el stock | — | lo ve, no lo cambia | **solo el stock** | todo |
| Mover el stock, con nota | no | no | sí | sí |
| Repartir el stock, catálogo, precios | no | **ve el catálogo y los precios de venta, sin cambiarlos** (26-nov, noche) | no | sí |
| Precio de lista, lo que se le debe al proveedor, GANANCIA | no | **no** | no | sí |

**El PIN en la central** (`lib/features/barra/central/llave_de_la_barra.dart`): la central manda un número (`reto`);
el aparato contesta quién es (`operador` + id, o `maestro`) y la firma con una llave sacada de su PIN (**el PIN no
viaja**). La central saca la misma llave de su base (`QuienEsQuienEnLaBarra`: los operadores con sus permisos y su PIN
maestro; en la app, `QuienEsQuienDeLaApp`) y compara; si da, firma el número de la tablet para que la tablet sepa que
es la central de verdad. Sin PIN: 4005 a los 10 s; PIN que no conoce: 4006; sin permiso de barra: 4007. **Hasta probar
el PIN no recibe ni guarda nada, ni echa a la tablet de verdad que tenga el mismo equipo.** El jefe y el enganche entre
las dos centrales entran con el **PIN maestro de la notebook: las dos notebooks tienen que tener el mismo** (si no, no
se enganchan y cada barra sigue sola). La tablet guarda el PIN de quien entró (`credencialDeLaBarraProvider`) y se
reconecta sola sin pedirlo de nuevo.

**Lo que la central acepta de cada uno** (`ReglasDeLaBarra.porQueNoSeGuarda`; lo que no, va a `CentralBarra.rechazos`
y se le avisa al aparato, `ClienteDeLaCentral.rechazadas`): lo de su caja (`device_id` = el aparato); anular, la
encargada (o firmado por una encargada en la tablet de esa caja); el OK, la encargada a una caja que no es suya (o
LA ENCARGADA ESTÁ ACÁ en la tablet de la cajera); cerrar, con el OK o sin esperar con motivo; una venta no se cambia;
el stock, el repositor; el reparto, el jefe. Lo de otro aparato que la central no tiene se repone; lo que ya tiene no
se pisa.

**La segunda llave**: `BarraConLaRed(rolDeQuienUsa:)` no anula, no cierra sin el OK, no cambia el cambio ni el
catálogo si no le toca (`NoLeTocaEnLaBarra`). La encargada anula en la tablet de la cajera con
`anularConLaEncargada` (la pantalla comprobó su PIN con `laEncargadaAutoriza`, `widgets/pin_de_la_encargada.dart`).

**Límites que quedan:** la nube deja escribir a cualquiera con la cuenta (una sola para todos); el PIN maestro de
fábrica (2026) está en el repositorio público: **recomendarle cambiarlo en las dos notebooks** antes del 4-dic; una
fila firmada con el nombre de una encargada desde la tablet de la cajera se cree (haría falta modificar la app).

### Lo que falta, en orden (26-nov, tarde)

1. ~~El vale con la hora real, la reconexión al volver al wifi, el stock por noche, el PIN en la central y las reglas
   por rol~~ **hechos el 26-nov** (arriba).
2. **Repositor, retiros y el cambio de la encargada:**
   - el permiso repositor (Barra con un 3): `PermisoOperador.repositorBarra`, `PermisosOperador.fromMap` lee el 3,
     `ReglasDeLaBarra.dePermisos` da `repositor`, la tercera opción en OPERADORES que **no borra el 3** al guardar
     otra cosa, y la entrada a su pantalla (no abre caja ni ve LAS CAJAS). **No tildar repositor hasta que todos los
     equipos tengan la versión;**
   - **RETIRO** y **el cambio de la encargada** (dar, agregar, ajustar, con el porqué y el historial): una tabla nueva
     donde solo se agregan filas (`barra_caja_movimientos`, tipo `retiro`, `cambio` o `ajuste_cambio`), su SQL y la
     migración **v84** (el locutor pasa a la v85), probada sobre una copia y desde un equipo que ya está en la v83 (el
     APK de prueba); viaja por la central; el esperado del cierre la cuenta;
   - ~~transferencia con el posnet~~ **no se hace** (26-nov, noche: la app queda como está; quien vende mira el
     posnet y aprieta CONFIRMAR);
   - "¿Volvió el vale?" al anular (en el motivo);
   - el jefe con LA ENCARGADA ESTÁ ACÁ; el aviso del PIN maestro de fábrica en CAJAS;
   - **sin stock no se vende** adentro de `vender()` (y en VENDER) con `StockPorBarra.deLaNoche`.
3. **La noche simulada y la tercera revisión independiente** sobre todo lo de la barra: dos barras, cientos de ventas
   (efectivo, transferencia, mixto), anulaciones, retiros, cambio, el stock que se acaba y vuelve, pasada la
   medianoche, **una tablet 4 horas sin señal** que vuelve (que llegue en segundos), la notebook que se apaga y prende
   en medio de un pedido de cierre, las barras separadas y juntas; cada cierre al centavo igual en la cajera, la
   notebook, la encargada y el jefe; y que las pantallas de la cajera y del repositor no muestren "$" ni "vendido".
4. **Las pantallas en la app de verdad, cómodas de usar:** el repositor (app en Android, página de la notebook en
   iPhone), VENDER con el stock, la página de la encargada en el iPhone (Parte 3: igual que LAS CAJAS, con su PIN,
   retoma sola), y la tele con lo que diga su prueba del APK. Capturas para él; el recorrido con el mouse si da el
   permiso.
5. La v83 y la v84 sobre una copia de la base real, los SQL con su OK, la foto de la mora, y publicar cuando él diga.
6. **Después:** el plano impreso entero (Parte 6; la spec está en
   `C:\Users\lover\Desktop\PLAN\SPEC_plano_impreso_entero_con_medidas_2026-11-26.md`, con lo que agregó él en el
   plan del 26-nov: el cuadro al costado/arriba/abajo/no, horizontal o vertical, "Detalle de las mesas aparte", una
   medida nunca pisa un sector, y pruebas sobre los 10 planos que existen).

**De antes, sigue valiendo** (lo que hizo falta para juntar las ramas):
1. ~~Las pruebas de la segunda revisión, las roturas otra vez y el SPEC~~ **hechos el 26-nov** (9 pruebas nuevas,
   ninguna encontró un error en el código; 31 de 31 roturas; la sección de conteos del SPEC al día). **La tercera
   revisión independiente va con el paso 3**, sobre el stock ya unido con la barra por noche.
2. **Juntar las ramas** (aprobado el 26-nov). **La barra, junta el 26-nov** (ver la tabla; las roturas no corrían en
   esta carpeta: con `core.autocrlf` el archivo de casos sale con CRLF y el `\r` pegado al nombre del test hacía que
   no corriera ninguno; `tool/romper_una_regla.sh` ahora lo limpia y avisa si un test no existe). **La tele, junta
   el 26-nov** (un conflicto en `test/pc_despierta_test.dart`, las dos ramas buscaban `prender` igual; se quedó la de
   la tele). **Las pruebas que leen el código tienen que aguantar `\r\n`:** en esta carpeta, lo que escribe git sale con
   CRLF (`test/modo_tele_cerrado_test.dart` falló por eso al juntar).
   Cada una apenas cierre su revisión, primero la barra y después la tele,
   con `git merge` acá. Sobre lo junto: conflictos, finales de línea LF, que nada nombre a un alumno real (contra
   `build/nombres_reemplazados_2026-11-26.md`), `flutter analyze`, la suite entera, las roturas de esa parte y la
   ventana de prueba con la huella IGUAL (`tool/dos_barras_prueba.dart`; `tool/tele_prueba.dart` con dos escuelas).
3. **Al juntar la Parte 2 con el stock**, con la tercera revisión independiente (lo contestó esa sesión el 25-nov;
   rama `claude/sleepy-jepsen-bea21a`, commits `995be5b`, `927c22f` y `6493a20`):
   - **La barra de cada caja:** una lista fija, `kBarrasDelSalon` (`lib/features/barra/services/barras_del_salon.dart`;
     no hay config por fiesta). La caja la elige obligatoria y se guarda tal cual en `sede`. Para leerla, `barraDe(sede)`
     (trim, sin distinguir mayúsculas; **null si no es de la lista**: las cajas viejas con texto libre). Cada equipo
     recuerda la suya (`barraDelEquipoProvider`) y la central también (`EstadoCentralBarra.barra`). → En
     `StockPorBarra`, el mapa caja → barra tiene que salir de `barraDe(c.sede)` (no de `claveDeBarra` a secas), y el
     reparto del jefe ofrecer las barras de `kBarrasDelSalon`. `claveDeBarra` sigue para comparar.
   - **La noche:** `lib/features/barra/cuentas/dia_de_operacion.dart`. `DiaDeOperacion.de(momento)` y `.deLaCaja(caja)`;
     "esta noche" = `DiaDeOperacion.de(ref.read(relojDeLaBarraProvider)())` (`providers/barra_del_jefe_provider.dart`,
     **la única hora de la barra**). `CajasPorDia.de(cajas)`: `.delDia(dia)`, `.idsDelDia(dia)`,
     `.ventasDelDia(ventas, dia)` (cada venta con su caja) e `.inicial(ahora:, fechaDeLaFiesta:)`. Modelo:
     `StockDeLaBarra.deLaNoche(...)` en `cuentas/stock_de_la_barra.dart`, que usan CAJAS y el "Quedan" de VENDER. →
     A `StockPorBarra.de` se le pasan `porDia.delDia(dia)` y `porDia.ventasDelDia(ventas, dia)`.
   - Lo que viaja por la central (`tablasDeLaRed`, `BarraConLaRed`) y los repositorios (`BarraLocal`, `BarraNube`)
     se hace sobre lo de esa sesión, que tocó la central. `avisos_previos` lo cuenta el repositorio con el equipo que
   va a guardar. En la página del iPhone, cada persona con su propio `device_id` ("pagina:<operador>"), o un aviso de
   un repositor lo cumpliría otro.
4. Las pantallas del repositor y el bloqueo en VENDER (con la maqueta aprobada), y la Parte 3 (la página de la
   encargada).
5. La migración v83 sobre una copia de la base real (`tool/verificar_migracion_v82_test.dart` como modelo), el SQL
   con el OK del usuario, y publicar cuando él diga.

### Pendientes del usuario

- ~~Confirmar la regla del corte al mediodía~~: **confirmada el 26-nov** ("la caja se toma de cuando se abrió").
- ~~Probar los routers Mercusys~~: **los unió por wifi y anda** (26-nov).
- Probar el APK de la app de verdad en su Google TV (se lo manda la sesión en paralelo) y contar qué no anda.
- Cambiar el PIN maestro de fábrica en las dos notebooks de la barra (el mismo en las dos).
- La foto de "Cómo anda" con la Quint (de antes, sigue pendiente: `docs/CONTEXTO_TELE_COMO_TOTEM_2026-11-24.md`).
