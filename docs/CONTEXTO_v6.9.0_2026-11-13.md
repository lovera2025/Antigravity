# CONTEXTO — la 6.9.0: los arreglos de la noche y la venta de entradas

**Estado (15-nov-2026, a la noche):** en curso, **sin publicar**. La hoja C del historial, cerrada; sigue lo de antes de publicar (la v80 y el comparador de la mora sobre una copia de la base, con el programa cerrado). Rama `feature/v4.6-cierre-por-sesiones`, todo en esta
PC, **sin subir a GitHub**. **Las etapas 1 a 7 de la venta de entradas están hechas, menos publicar**: la ventana de
prueba, el recorrido con el mouse, las capturas (mandadas) y la revisión final con sus 6 arreglos (ver "Etapa 7").

## Para retomar en otro chat

**DÓNDE QUEDÓ (15-nov, a la noche, segundo chat: "hagamos lo que falta", con el plan aprobado en
`C:\Users\lover\.claude\plans\cuchame-hagamos-lo-que-resilient-karp.md`):**
- **La hoja C (el historial de ventas en A4) está CERRADA** (ver "8." en "Etapa 7"). Se le mandaron la muestra de
  1.000 entradas con las letras de la app (3 PDF: el del jefe, la caja de Carla sin sumas, y un tramo "de la hoja 11
  a la 19" de uno de 2.200) y las capturas del cartel Todo junto · Por hojas (PC y celular), en
  `build/muestras_6.9.0/historial_1000/`.
- **La etapa 2 (antes de publicar) quedó HECHA el 15-nov a la noche**, con el programa cerrado:
  - **La copia de la base** (`tool/copiar_base_solo_lectura.py`, la base real quedó igual): era del 14-nov a las
    15:41 (el programa no se había abierto después en esta PC); 642 alumnos, 5.275 pagos, el último del 14-nov a las
    14:29. La huella de la base dio IGUAL antes y después.
  - **La migración v80 sobre la copia: pasó** (`tool/verificar_migracion_v80_test.dart`): las 46 tablas de antes con
    los mismos datos, las 5 de la venta de entradas nuevas y vacías, el esquema de lo que ya existía igual (87
    tablas, índices y triggers), y la vuelta a la 6.8.0 y de nuevo a la 6.9.0 con los datos iguales.
  - **El comparador de la mora (6.8.0 → 6.9.0): "Todo en orden: ninguna suma se movió"**; 4 fichas cambian (las del
    Anexo D de la 6.8.1), 2.934 cobros, ninguno deja de sumar lo cobrado. Contra la 6.8.1 (corrida en
    `..\arguello_events_6.8.x`), **cambian 25 recibos reimpresos y ninguna suma**: 16 confirman "(parcial)" con lo
    que se debía (la mora de una sola cuota cobrada a medias) y 9 juntan la mora partida en efectivo y
    transferencia. Son los arreglos de la revisión final; ninguno más.
  - **Mirando esos recibos apareció "Se pagaron 1 mora parcialmente"**: ahora "Se pagó 1 mora parcialmente"
    (`pieDeMorasParciales`, con su prueba). La suite entera, después: 5.128 pruebas, todas pasan.
  - **Se le mandaron** el informe del comparador y 5 recibos de antes y después (en `build/papeles_6.9.0/`, con
    nombres: fuera de git). La copia, los JSON y el worktree de la 6.8.0 quedaron en el scratchpad de la sesión.
  - La prueba de "retomar la caja" que pidió (cerrar el programa, volver a entrar con el PIN y seguir con la misma
    caja; desde otra tablet no): `test/retomar_la_caja_test.dart` (`03aca9b`).
- **Lo que sigue: publicar con él, paso por paso** (punto 5 de "Lo que sigue", abajo). Primero preguntarle si la
  6.8.0 ya está en las tres PCs (si sí, la foto de la mora "después de 6.8.0" va antes que la de "antes de 6.9.0").
- **Lo que seguía antes de la etapa 2** (quedó hecho; se deja como referencia):
  1. Pedirle que abra el programa (para que baje lo del día) y lo cierre. Copia:
     `python -I tool/copiar_base_solo_lectura.py <scratchpad>\copia.db`.
  2. `flutter test tool/verificar_migracion_v80_test.dart --dart-define=base=<copia>` (**escrito el 15-nov, sin
     correr**: necesita la copia; la base de esta PC está en la 79).
  3. El comparador de la mora como en la 6.8.1 (worktree con `v6.8.0`, `tool/rotulo_mora_antes_despues_test.dart` en
     las dos y `python -I tool/comparar_rotulo_mora.py`), los papeles de antes y después a `build/papeles_6.9.0/` y
     mandárselos. Tiene que mostrar los cambios de la 6.8.1, los tres del recibo reimpreso de la revisión final y el
     del perdón de esta revisión, sin ninguna suma movida.
  4. Publicar con él, paso por paso (punto 5 de "Lo que sigue", abajo).
- **No se pudo manejar la ventana de prueba con el mouse**: el permiso de computer-use para `arguello_events.exe` se
  pidió y no se dio. La captura del cartel salió de la pantalla VENTAS de verdad montada en la muestra
  (`tool/venta_entradas_muestra_test.dart`, "IMPRIMIR HISTORIAL"). `tool/venta_entradas_prueba.dart` acepta
  `--dart-define=ventas=muchas` (700 ventas más en la caja de Maxi) para verlo con el mouse.
- **La huella de la base dio IGUAL** antes y después de abrir la ventana de prueba compilada (se cerró sin usarla).

**Lo último (15-nov, a la tarde):**
- **Pendiente de su respuesta: la hoja A4 del historial de ventas de entradas, "con todos los detalles".** (Ya contestó:
  la C. Ver arriba.) Lo pidió él al
  ver las capturas ("imaginá 1.000 entradas"). Se le mostró la **forma C** (una muestra de verdad en tamaño A4,
  `build/muestras_6.9.0/historial_c/historial_c_hoja1.png`, armada con `build/muestras_6.9.0/historial_c/hoja_c.py` y Edge sin ventana): un renglón por
  venta (N°, hora, comprador · familia y mesa, entradas, talonario, total, pagó, vendió, verificado) y un segundo
  renglón **solo** si hay algo que explicar (mixto, descuento a mano, anulada); **40 ventas por hoja, 1.000 entradas ≈ 8
  hojas**, los totales al final; y antes de imprimir, si son muchas hojas, el cartel **Todo junto · Por hojas** (de a
  tandas de 10, o "de la hoja X a la Y"). Se le preguntó si va así y si el N° (que se repite: cada caja numera desde 1)
  queda así o se separa la hoja por caja. **No está programado**; va en la 6.9.0 si dice que sí (sin SQL). El historial
  de hoy es `entradas/pdf/historial_entradas_pdf.dart` (una línea por venta, sin talonario ni familia).
- Las otras dos formas que se le mostraron: A (dos renglones siempre, 25 por hoja) y B (hoja acostada, todo en
  columnas, 30 por hoja). Le recomendé la C.

**Antes que esto: la 6.8.1** (14-nov, a la tarde). En el medio de la 6.9.0 el usuario trajo una spec del rótulo de la
mora (una familia reclamó un recibo) y el jefe avisó que los recibos reimpresos salían con menos datos. Se hizo como
**6.8.1, sola**, desde `release/6.8.x`: **programada y probada sobre una copia de la base, sin publicar; falta su OK y
publicar con él.** Todo en `docs/CONTEXTO_v6.8.1_2026-11-14.md`. Sus commits ya están también en esta rama (la suite
entera pasa: 5.000). **El 14-nov a la noche el usuario decidió no publicarla sola: sale adentro de la 6.9.0** (le
recomendé publicarla antes del 16, cuando la empresa empieza a cobrar; eligió esperar). Entonces:
- **La 6.9.0 lleva también la 6.8.1**: el rótulo de la mora, el recibo reimpreso entero y el recuadro verde con la
  tabla Debía · Pagó · Quedó. Las novedades tienen que nombrarlo ("correcciones en la mora y en los recibos").
- **Antes de publicar la 6.9.0**, además de lo suyo: correr otra vez el comparador de la mora y los papeles de antes y
  después sobre una copia nueva de la base, y mandárselos (cómo, en "Cómo se probó" del CONTEXTO de la 6.8.1). La
  versión anterior para comparar es la 6.8.0.
- Hasta que salga: a las 4 familias del Anexo D, todo el remanente junto y nada de perdón por mes.
- ~~Se sigue por la etapa 5 de la venta de entradas~~: la 5 y la 6 se cerraron el 15-nov. **Sigue la etapa 7.**

El plan general va por 9 partes (los arreglos de la noche, las 7 etapas de la venta de entradas y la 6.8.1 programada;
publicar todo es la etapa 7): **8 de 9, 89 %** (15-nov).

**Dónde quedó (15-nov, al cortar el chat a pedido del usuario: "actualizá tu contexto y retomamos en otro chat"):**

- **Parte A (los arreglos de la noche): hecha entera**, sin instalar. Faltan sus capturas con el mouse y dos
  comprobaciones con aparatos de verdad (abajo).
- **Parte B (la venta de entradas): etapas 1 a 6 hechas y guardadas** (`cba8c7d` la 5, `d259ea1` la 6; lo hecho, en
  "Etapa 5" y "Etapa 6", abajo). Ya se vende con comprobante, se ve VENTAS, se cierra la caja con su papel, el jefe la
  ve en ENTRADAS del cierre de caja y la entrega muestra lo vendido. **Falta la 7.**
- **La suite entera pasa: 5.054 pruebas** (`FIN fallo=0`). El repositorio, sin cambios sueltos.
- Se le mandaron las muestras de VENTAS y de la etapa 6 (`build/muestras_6.9.0/venta_entradas_v5/` y `_v6/`).

**Lo que preguntó y se le contestó el 15-nov (no volver a preguntarlo):**

- "¿Todo saldrá como 6.9.0, todo incluido?" → **Sí**: los arreglos de la noche, la 6.8.1 y la venta de entradas
  entera, en una sola versión, cuando él diga.
- Aprobó el plan de la 5 y la 6 ("sigamos?") con cuatro decisiones mías que no objetó: VENDERLE ESAS ENTRADAS también
  en el mostrador (a quien tenga "Vende entradas"), también con la familia que debe o que ya retiró, "(compró N)" solo
  si compró alguna, y el papel del cierre que se abre solo al cerrar.
- "¿Todo ok? ¿No dejaste nada por alto?" → se le dijo que sí, con la lista de lo no probado y lo dejado afuera (abajo,
  en "Lo que sigue"). **Lo que más importa que sepa:** la revisión encontró que la entrega sin cargo que ya usa (desde
  la 6.0.0) no veía los números de dos alumnos con el mismo nombre ni los de un alumno que pasó a baja temporal: se
  podía dar dos veces el mismo número. Sus datos están bien; se corrige con la 6.9.0.
- "Esa noche, ¿ya no habrá problema después de las doce, y si se minimiza sin internet?" → **Sí, está solucionado en
  la Parte A, pero no instalado**: la fiesta sigue en la lista de la barra y de Entradas hasta el mediodía siguiente
  (P2), la tele sin internet se queda con lo guardado y no vuelve a la de fábrica (P1), y la notebook no se duerme con
  la tele a la vista o la central prendida (P9; cerrar la tapa la duerme igual). Hasta instalar la 6.9.0, las PCs
  siguen como antes. Se le preguntó si con "minimizar" quería decir otra cosa (el programa minimizado): **no
  contestó todavía**; si lo trae, revisarlo.

**Nada de esto está en las PCs ni en la nube**: no se publicó, no se instaló, no se corrió ningún SQL, no se tocó la
base de verdad ni ningún sorteo. La versión sigue en `6.8.0+74` en `pubspec.yaml`: se sube a `6.9.0` al publicar.

**Qué es.** Una sola versión, la 6.9.0, con dos partes y en este orden (plan aprobado por el usuario el 13-nov):

- **Parte A — los arreglos de la noche.** Lo que encontró la revisión del 13-nov sobre la 6.8.0
  (`docs/SPEC_arreglos_antes_de_las_fiestas_2026-11-13.md`; el informe con capturas,
  `docs/REVISION_ANTES_DE_LAS_FIESTAS_2026-11-13.md`). **Programada y guardada entera** (5 commits). Sin SQL ni migración.
- **Parte B — la venta de entradas.** `docs/SPEC_venta_de_entradas_2026-11-13.md` (cinco tablas nuevas, v80, un SQL solo
  de agregar). **Etapas 1 a 6 hechas; falta la 7** (ver "Parte B", abajo). La primera recepción es el 4-dic.

**Lo que decidió el usuario el 13-nov** (no volver a preguntarlo):

- **"Lo programes pero no publiques, entonces mandamos todo en una versión."** Los arreglos no salen solos como 6.8.1.
  Si antes del 4-dic hiciera falta sacarlos solos, se pueden armar desde el commit `3136ffe`: se le pregunta.
- **El sorteo que ya está hecho no se toca** (el punto P6 del spec, la mesa "principal" con "Al final"): "si el jefe no
  dijo o no modificó, debe permanecer así, por algo será". Queda anotado en el spec como observación, sin arreglo.
  Al contárselo se asustó: **primero decir que el sorteo y las mesas están bien y que no se cambió nada.**
- **Antes de las pantallas de la venta de entradas, una maqueta y su OK.** Los datos y las cuentas (sin pantallas) van
  sin preguntar.
- Publicar, correr el SQL y cada instalación: con él, preguntando en el momento, con las capturas.

**Lo que sigue, en orden** (las etapas 1 a 7 están hechas, menos publicar):

1. ~~La ventana de prueba~~ y 2. ~~el recorrido con el mouse y las capturas~~: **hechos el 15-nov** (ver "Etapa 7").
   Queda, si él dice que sí, **la hoja A4 del historial de ventas con todos los detalles y el cartel para imprimir por
   hojas** (arriba, "Lo último"): programarla, con su prueba y su muestra de 1.000 entradas inventadas, y mostrársela.
3. **Comprobaciones con aparatos de verdad, cuando estén:** la notebook sola unos minutos con la tele abierta, que no
   se apague (P9); el OK de la encargada desde el iPhone (P4); los papeles abiertos desde el programa (el cartel de
   imprimir de Windows); una tablet.
4. **Antes de publicar:** la migración v80 sobre una copia de la base real (con el programa cerrado: se le pide);
   correr otra vez el comparador de la mora de la 6.8.1 sobre una copia nueva y mandarle los papeles de antes y
   después (cómo, en el CONTEXTO de la 6.8.1).
5. **Publicar con él** (lo de siempre, preguntando en cada paso): la foto de la mora "antes de 6.9.0"; el SQL de la v80
   (`supabase/migrations/20261113200000_venta_de_entradas.sql`) con su OK y los conteos; `pubspec.yaml` a `6.9.0`; el
   instalador por pasos (tarda más que el tope de 10 minutos; mirar los tres archivos de la página del celular antes
   de `ISCC`, ver el CONTEXTO de la 6.6.0), el APK, el tag, el release y la web. Las novedades nombran la venta de
   entradas y "correcciones en la mora y en los recibos". En `CLAUDE.md`, sacar "sin programar" de "El retiro de
   entradas" y sumar a Trampas las reglas de la venta.
6. **Después de instalar:** la foto "después de 6.9.0". **No tildar "Vende entradas" ni cargar precios hasta que todas
   las PCs y las tablets tengan la versión.**

**Se le ofreció y no contestó (no frena nada):**
- Un botón para **volver a sacar el papel del cierre de una caja** desde ENTRADAS del cierre de caja: hoy se saca solo
  desde la pantalla del cierre, y si la cajera elige "salir igual" sin papel, se pierde (el aviso lo dice).

**Quedó afuera, y se le dijo:**
- `docs/pendientes/anular-dos-veces-desde-dos-pcs.md`: anular la misma venta desde dos PCs antes de que una se entere
  de la otra (la segunda pisa a la primera en la nube). Muy improbable; toca la subida del motor.
- Al volver de VENDERLE ESAS ENTRADAS, el cartel de la entrega no se vuelve a abrir solo (no se pierde nada guardado).
- **Dos arreglos sin una prueba que los vigile:** que Atrás no deje salir mientras se cierra la caja, y la segunda
  llave de VENDERLE ESAS ENTRADAS (sin el permiso el botón no aparece). Se pueden sumar en la etapa 7.
- De la Parte A, lo anotado en el spec sin hacer (abajo, "Lo demás de la tabla").

**Cómo se trabaja acá** (lo que hizo falta aprender en este chat):

- La suite entera se corre por tandas de 40 archivos, sin los tres tests que consultan la nube
  (`verify_supabase_content_test`, `query_supabase_id_test`, `search_supabase_broad_test`): entera en un solo comando
  no entra. Tarda unos 4 minutos.
- Los archivos tienen fin de línea de Windows: un test que lee código lo normaliza (`.replaceAll('\r\n', '\n')`).
- Los cambios de varias líneas a archivos grandes (`local_database.dart`, `sync_engine.dart`) se hicieron con un
  script escrito a un archivo y corrido, no con texto pegado en la consola.
- Cada commit: el mensaje en un archivo y `git commit -F`. Sin nombres de alumnos (el repositorio es público).
- **15-nov:** cada etapa se cerró con **una revisión independiente** (un Workflow de tres lectores, uno por tema, y un
  verificador por hallazgo que intenta refutarlo), en solo lectura y mientras corría la suite. Encontró lo que las
  pruebas no veían (13 confirmados entre las dos etapas). Conviene repetirlo en la etapa 7 antes de publicar.
- **Los PDF se miran con la herramienta de leer archivos** (muestra las hojas): así se vio que el historial partía
  cada fecha en dos renglones.
- `tool/romper_una_regla.sh` imprime cada caso en un renglón que empieza con `[`: filtrar con `grep "^\["` (con
  `tail` se cortan los primeros).
- Para guardar una etapa sin lo de la siguiente que ya estaba empezado: la versión del archivo compartido armada
  aparte (`git hash-object -w` + `git update-index --cacheinfo`), `git stash push --keep-index --include-untracked`
  para correr las pruebas de lo que se guarda, y `git stash pop`.
- Las ediciones de varias líneas van en un script de Python escrito a un archivo (un heredoc con comillas mezcladas
  falla en esta PC), con un `assert` de que el texto a cambiar aparece una sola vez.
- **Los dos scripts del trabajo quedaron en el repositorio** (14-nov): `bash tool/suite_por_tandas.sh` (la suite
  entera; termina con `FIN fallo=0 total=N`) y `bash tool/romper_una_regla.sh <casos>` (las roturas a propósito: un
  caso son cinco renglones y uno de `---`; lo explica arriba del archivo).
- **Mientras corre la suite no se escribe en `lib/` ni en `test/`**: hay tests que leen carpetas enteras
  (`lib/features/entradas/widgets`) y un archivo a medio escribir los hace fallar. Se adelanta lo que no tiene
  pantalla, o los documentos.
- **Un script con comillas simples y dobles mezcladas no va en la consola** (falla el heredoc), y con Perl las llaves
  del código rompen `q{}`: los cambios al código van con la herramienta de edición.
- **Las pantallas se miran, no alcanza con los tests:** `flutter test tool/venta_entradas_muestra_test.dart
  --dart-define=salida=<carpeta>` saca las imágenes con el tema de la app. La primera vez aparecieron tres defectos.
- Las capturas de una página web con Edge sin ventana se saltean algunas si van de corrido: cada una con su perfil
  (`--user-data-dir`) y reintentando.

## Parte A — lo hecho

Los 9 puntos "que pueden fallar la noche" se comprobaron contra el código antes de tocar nada: **los 9 eran reales**. Se
arreglaron 8 (el P6 queda como está) y ocho de la tabla de "los que molestan".

| Commit | Qué arregla |
|---|---|
| `88a5245` | **P2** la fiesta ya no desaparece de la barra ni de Entradas a las 00:00 · **P7** la tele no vuelve a saludar a todos · **P1** el tótem sin internet se queda con lo guardado, y Personalizar no pisa lo de la nube |
| `61b7341` | **P4** el OK de la encargada desde el iPhone llega en segundos · **P3** la encargada que entra directo a LAS CAJAS se conecta a la notebook |
| `0acb39e` | **P5** Recepción pregunta antes de mover la tele o los celulares a otra fiesta · **P9** la notebook no se duerme |
| `c816347` | **P8** la ventana de la tele no pisa las preferencias de la PC |
| `3136ffe` | los ocho chicos (abajo) |

### Lo que cambió, y dónde

- **P2.** `primerDiaDeLasFiestasQueVienen` (`common/utils/dia_de_la_fiesta.dart`): la fiesta sigue en la lista **hasta el
  mediodía siguiente** (ahora − 12 h). La usan `fiestasParaLaBarra` y `fiestasQueVienen`. **No "desde ayer"**: con
  fiestas dos noches seguidas la de anoche saldría primera y se abriría la caja equivocada. El jefe (`FiestasDelJefe`)
  sigue con "desde ayer": él mira, no abre cajas.
- **P7.** `IngresosTotem.vaciar()` deja la lectura siguiente en silencio (una sola). El `list_reset` del puente lleva el
  evento (`KioskLauncher.notifyListReset(eventoId)`), y la ventana del tótem ignora un `list_reset` o un
  `guest_checkin` de otra fiesta (`avisoEsDeEsteEvento`).
- **P1.** `totemConfigProvider`: ante un error **no emite los valores de fábrica** (solo la caché los emite, si no hay
  nada guardado) y **vuelve a pedir la config** hasta leerla una vez (5, 10, 20, 40 s y después cada minuto;
  `esperaDeReintentoDeLaConfig`). Leída, no reintenta más. `TotemConfigRepository.sigueComoSeAbrio`: Personalizar lee
  la fila de la nube antes de guardar y, **si no es la que se abrió o no se puede leer, no guarda**
  (`mismaConfig`: no cuentan `updated_at`, `updated_by` ni los segundos de la llegada, que se cambian a mano esa noche).
- **P4.** `BarraNube.anotarPasoDelCierre` manda el aviso entre equipos (`core/services/pulso_entre_equipos.dart`:
  `kCanalDelPulso`, `kEventoDelPulso`, `avisoDeTablas`; el motor usa las mismas constantes). Y la tablet que espera el
  OK baja `barra_cierres` cada 15 s **solo mientras espera** (`SyncEngine.bajarCierresDeLaBarra`,
  `bajarCierresDeLaBarraProvider`, `kMiradasPorPregunta`). `bajarParaLaBarra()` no sirve para eso: baja el catálogo.
- **P3.** `ClienteDeLaBarra.arrancarSiNoHay`: el botón LAS CAJAS del inicio de la barra busca la central, **sin cortar**
  la conexión si VENDER ya la armó. No en `jefe/cajas_de_la_fiesta.dart` (la comparten el jefe y la web).
- **P5.** `elegirEventoEnRecepcion` (`recepcion/widgets/otra_fiesta_en_la_tele.dart`): si el tótem está con otra fiesta,
  pregunta PASAR EL TÓTEM · SOLO MIRAR ACÁ (`SelectedEventNotifier.select(moverLaTele:)`). `VentanaSumarCelular`: si la
  central está prendida para otra fiesta, dice cuántos celulares tiene y pregunta antes de pasarla. **El celular no se
  tocó**: el 4001 también es "Cambiar el código", y no hay que dejarle la lista a un celular echado. Los otros dos que
  llaman a `select` (el Centro de Comando al abrir el tótem y `totem_launcher_screen`) siguen moviendo la tele: ahí se
  está eligiendo qué proyectar.
- **P9.** `PcDespierta` (`core/services/pc_despierta.dart`, con `pc_despierta_windows.dart` por FFI y un stub para la
  web): cada 30 s le avisa a Windows que hay uso (`SetThreadExecutionState`, **sin `ES_CONTINUOUS`**: nada que soltar).
  La prenden la ventana de la tele a la vista (se corta en `_pausar()`), y las dos centrales prendidas. **No alcanza si
  se cierra la tapa**: eso es de Windows.
- **P8.** `PreferenciasDeLaVentana` (`core/services/preferencias_de_la_ventana.dart`): la ventana del tótem **no
  escribe el archivo de preferencias**; le pide a la principal por el puente (`PuenteFichaTotem.metodoGuardar`,
  `guardar_preferencia`) y se lo acuerda ella en memoria. La principal guarda **solo** `totem_config_v1_<evento>` y
  `totem_orient_v1_<evento>`. `TotemConfigCache` y `TotemOrientationStore` pasan por ahí.

### Los ocho chicos (`3136ffe`)

- Un número de 19 cifras o más en el buscador de la puerta dejaba la lista en gris: `int.tryParse`.
- "Todo subido" cuenta las sillas de la noche (`DatosSinInternet.sillasSinSubir`, `SillasPuertaRepository.sinSubir`).
- El botón de actualizar la lista dice que no pudo cuando no bajó (`forceRefresh` devuelve si bajó).
- **La cola de la puerta ya no pierde un ingreso**: agregar a mano, eliminar, destrabar el DNI y vaciar subían por un
  camino que al terminar borraba de la cola todo lo de esa persona. Ahora todo va por `_subirYa` y
  `SyncQueue.markCompleted(leidaCon:)`. `_syncImmediately` ya no existe.
- La música de la llegada ocupa dos renglones como mucho (`kRenglonesDeLaMusica`).
- La foto y el fondo que no bajaron se vuelven a pedir solos (`ImagenQueReintenta`, `CargaDelFondo`,
  `esperaDeReintentoDeLaFoto`: 15 s, 30 s, y cada minuto), y `FotoGuardada` saca su fallo del caché de imágenes.
- Sin impresora elegida, el vale lo dice (`kSinImpresoraElegida`, `PapelDeLaBarra.sinImpresora`).
- El buscador del mostrador de Entradas encuentra sin acentos (`coincideTextoBusqueda`).

**Lo demás de la tabla quedó anotado en el spec, sin hacer**: los PDF que sin internet salen en otra letra (14
funciones de `pdf_service.dart`), los avisos que corren la lista de la puerta bajo el dedo, el tamaño de la ventana del
tótem en una notebook chica o con la tele al 150 %, la X del tótem sin pregunta, Póster y Gala que saltan cada minuto,
el id del acompañante por posición, y el resto.

### Cómo se probó

- **La suite entera: 4.753 pruebas, todas pasan** (eran 4.667; 86 nuevas), en 7 tandas de 40 archivos, sin los tres
  tests que consultan la nube. `flutter analyze` de `lib/`: sin errores (los avisos que hay son de antes).
- Las dos pruebas aisladas de la revisión (`build/revision/probes/`) cambiaron de resultado: la cola del tótem pasó de
  50 a 0, y la tele sin internet termina en "PROMOCIÓN 2026 | foto".
- Pruebas nuevas, por arreglo: `totem_config_sin_internet_test` (con la librería de Supabase de verdad contra un
  servidor chico en esta misma PC: sin internet, y "vuelve internet"), `otra_fiesta_en_la_tele_test`,
  `pc_despierta_test`, `preferencias_de_la_ventana_test`, `puerta_cola_no_se_pierde_test` (**primero se corrió con el
  código de antes y falló**: el ingreso se perdía), `imagen_que_reintenta_test`, y casos nuevos en las que ya había.

### Lo que no se probó (queda dicho)

- **El aviso a Windows de verdad** (P9): hay que dejar la notebook sola unos minutos con la tele abierta y ver que no
  apaga la pantalla. En las pruebas ese aviso no corre.
- **El OK desde el iPhone contra la nube** (P4) y con las tablets de verdad.
- **Las capturas con el mouse** de la pregunta de la tele, la de los celulares y los carteles nuevos: el permiso para
  manejar la ventana de prueba no se aprobó esa noche. **El usuario quiere las capturas antes de publicar**: se sacan
  cuando esté.
- La tele, la notebook y el router del salón.

### Lo que sí se comprobó con las dos ventanas de verdad (P8)

`flutter run -d windows -t tool/kiosco_prueba.dart --dart-define=auto=true` corre solo, sin mouse: abre el tótem, el
tótem guarda su orientación y cada ventana lo dice por la consola. Salió:

```
AUTO-PRINCIPAL: el tótem pidió guardar "totem_orient_v1_deadbeef-…" = "vertical" -> se guardaría
AUTO-TOTEM: guardó la orientación por el puente (porElPuente=true); … ahora lee vertical
```

y **el archivo de preferencias quedó con la misma huella SHA-256 antes y después** (`%APPDATA%\Junior Eventos\Junior
Eventos\shared_preferences.json`): la ventana del tótem no lo escribió. **Ese archivo es el mismo del programa
instalado en esta PC**: por eso el arnés muestra lo que el tótem pide guardar y no lo escribe. En la misma corrida se
vio a la config del tótem reintentar sola contra una nube que no contesta (P1).

Para cerrar el arnés sin tocar el programa instalado: se mata solo el proceso cuya ruta está en `build\windows`.

## Parte B — la venta de entradas

**Comprobado contra el código antes de empezar:** lo que el spec da por hecho existe y es como lo describe. Siete
nombres están escritos distinto (no cambian qué se hace):

- `fromMap` y `toMap` de los permisos están en `PermisosOperador` (la fila), no en `PermisosEfectivos`.
- `MedioBarra` está en `barra/datos/venta_barra.dart`.
- `CierreDeBarra` es solo de la barra: `CierreDeEntradas` se escribe nuevo.
- `anuladoDespuesDelCierre` es de los cobros de cuotas: se usa el criterio, no la función.
- No hay un `sellada()` suelto: cada modelo tiene el suyo.
- La prioridad de subida y las columnas que suben son listas adentro de funciones del motor.
- `ArTime` no tiene "hoy": se saca de `nowAr()`.

**Ajustes al spec** (aprobados con el plan): los tres PDF nuevos con `PdfService.fuentesOutfit()` y en un archivo
propio; maqueta antes de las pantallas; elegir la fiesta para vender usa la regla del mediodía de la Parte A.

### Etapa 1, los datos — HECHA (13-nov)

- **Los cinco modelos** en `lib/features/entradas/datos/`: `ConfigEntradas` (el precio de la fiesta; `conPrecios`
  valida y tira si algo no cierra), `CajaEntradas`, `VentaEntradas` con `RenglonEntradas` (`suelta` y `lugar`;
  `precioCon` es la única cuenta del descuento, en pesos enteros; `VentaEntradas.nueva` tira si no cierra),
  `AnulacionEntradas` (con `devueltas`) y `VerificacionEntradas`. Los tres ids fijos, en `UuidUtils`.
- **El repositorio:** `EntradasLocal` (`entradas_local.dart`), con tres interfaces en `entradas_repositorio.dart`:
  `EntradasDeLaFiesta` (leer), `EntradasDeLaCaja` (abrir, vender, cerrar) y `EntradasDelJefe` (precio, anular,
  verificar). Todo lo que escribe va con su entrada en la cola en la misma transacción. Nada se borra.
  **Una caja vive en el equipo que la abrió** (`cajaAbierta` mira el `device_id`).
- **La v80** en `LocalDatabase` (`crearTablasV80`, el bloque `oldVersion < 80`, la red del arranque y `_onCreate`).
- **El SQL de la nube, escrito y SIN CORRER:** `supabase/migrations/20261113200000_venta_de_entradas.sql`. Solo
  agrega cinco tablas; sin CHECK, sin clave foránea, sin índice único; RLS para usuarios logueados y los dos
  disparadores; nada a Realtime. **Se corre antes de instalar, con el OK del usuario.**
- **El motor:** las cinco en `_incrementalColumns` y en la bajada general; cajas, ventas y anulaciones en
  `_tablasDelCobro` (la red de 5 minutos), config y verificaciones en `_tablasDeCarga`; prioridades 2, 4 y 5; sus
  columnas; y las cinco en `_tablasSinRevisarBorrados`, con su motivo.
- **Tests nuevos:** `migracion_v80_test` (de 79 a 80 lo demás queda igual, se corre dos veces, la vuelta a la 6.8.0),
  `sync_tablas_v80_test` (el modelo, la base, el motor y el SQL tienen las mismas columnas), `entradas_repositorio_test`
  y `venta_entradas_no_toca_test` (lee el código de la venta de entradas y falla si toca cuotas, saldo, mora, mesas o
  sillas). `borrados_de_otra_pc_test` y `sync_en_reposo_test` siguen pasando.
- A `migracion_v79_test` se le puso `versionNueva: 79` en la copia, como a la de la 78.

**Falta de la etapa 1, para el día de publicar:** `tool/verificar_migracion_v80_test.dart` sobre una copia de la base
real (el de la v79 es el modelo), con la app instalada cerrada: se le pide al usuario.

**Con la v80 en la rama, no correr la app desde esta carpeta contra la base de verdad** (las PCs tienen la 79). Los
arneses `tool/*_prueba.dart` que no abren la base sí se pueden correr.

**Después de la etapa 1 se corrió la suite entera: 4.803 pruebas, todas pasan.**

### Etapa 2, las cuentas — HECHA (14-nov)

`lib/features/entradas/cuentas/`, puras y sin pantalla ni base (sección 5 del spec). **Se usa lo de la barra, no se
escribe otro:** `centavos`, `deCentavos` y `pesos` (`barra/cuentas/pesos.dart`), `MedioBarra`, `PartidoMixto` y
`CobroBarra` (`barra/cuentas/cobro_barra.dart`), `diferenciaEnPalabras` (`barra/cuentas/cierre_de_barra.dart`).

**Quedó como estaba decidido, con esto de más o distinto** (lo que tiene que saber quien haga las pantallas):

- **La pantalla guarda con `PedidoDeEntradas.guardarEn(repositorio, caja:, cobro:, quien:)`**, no llamando a
  `vender` a mano: arma primero la venta con `venta(...)` (que tira si algo no cierra) y al repositorio le manda eso
  mismo, campo por campo. Así no hay una segunda cuenta en la pantalla. El número lo sigue dando el repositorio.
- **El descuento a mano lo decide el pedido** (`puedeDescontar`: modo jefe, o el tilde de PRECIOS): la pantalla le
  pasa `esJefe` y nada más. Sin permiso, `descuentoQueVa` es 0 aunque alguien haya escrito otra cosa.
- **`paraLaFamilia(id, lugares)` viene con todas las de sus lugares que le quedan** (lo del spec: "viene tildado con
  todas"), y `conDeLugar(n)` nunca pasa de las que le quedan.
- **Con el 100 % de descuento la venta vale 0** (`esSinCargo`): se guarda igual, con `cobroPor(MedioBarra.efectivo)`,
  **sin abrir `pedirCobro`** (que con total 0 dice "La cuenta está vacía").
- `cobroPor(medio)` da el `CobroBarra` con el recargo de la fiesta (`recargoPrendido`, `recargoPct`); para
  `pedirCobro` se pasan esos dos.
- El nombre del renglón de lugar dice **lo que paga** del valor: con el descuento en 50, "(50 %)"; en 40, "(60 %)".
- **Los repetidos son una lista de `NumeroRepetido`** (con `.texto`), no de textos: entre dos ventas, o entre una
  venta y una entrega (`conUnaEntrega`).
- **En el cierre, una venta cuyos renglones no dan su cantidad y su total va entera a "otras"**; un renglón de un
  tipo que la versión no conoce, también. Así las entradas y la plata suman siempre lo vendido.
- `CierreDeEntradas.deLaFiesta(cajas, ventas, anulaciones)` cuenta **todas** las ventas que recibe (vienen por
  fiesta), aunque la caja de alguna todavía no haya bajado.
- `ResumenDeCajaEntradas.porCaja(...)`: una por caja, la que abrió primero arriba.
- "Anulado después del cierre" compara el momento de la anulación con el del cierre, que son de dos equipos (el del
  jefe y el de quien vende): es el criterio de los cobros. Con los relojes corridos unos minutos, una anulación
  hecha justo al cerrar puede caer del otro lado. No cambia ninguna plata: solo en qué renglón se muestra.

**Cómo se probó:** 54 pruebas nuevas en tres archivos (`entradas_cuentas_test`, `entradas_numeros_test`,
`cierre_de_entradas_test`), y **diez roturas a propósito, una por regla** (el último día de la anticipada, el lugar
sobre el valor y no sobre la anticipada, la anulada que devuelve las de lugar, el tope de las que le quedan, el
descuento sin permiso, la anulada con devolución que libera los números, lo vendido sumado a lo entregado, la
anulada fuera del efectivo, los descuentos en su renglón, lo anulado después del cierre): **las diez hicieron fallar
su test**, y cada archivo volvió a quedar igual (misma huella). `venta_entradas_no_toca_test` sigue pasando con la
carpeta nueva adentro.

**Lo que no se probó:** nada de esto tiene pantalla todavía, así que no se vio con el mouse. La regla de "anulado
después del cierre" con dos equipos de verdad.

Los cinco archivos, como quedaron pensados:

1. **`precio_de_entradas.dart`** — `PrecioDeEntradas`: `hoyEnArgentina()` (`ArTime.nowAr()`), `rigeLaAnticipada(c,
   hoyAr)` (el día `AAAA-MM-DD` de `hoyAr` contra `anticipada_hasta`, **inclusive**, comparado como texto con
   `ConfigEntradas.diaDe`), `deHoy(c, hoyAr)` (null sin precio) y `deLugar(c)` (**siempre sobre el valor de la
   entrada, nunca sobre la anticipada**, con `RenglonEntradas.precioCon`).
2. **`lugares_de_la_familia.dart`** — `anulacionesPorVenta(anulaciones)` (id de la venta → su anulación) y
   `LugaresDeLaFamilia`: `leCorresponden` (`RetiroEntradas.entradasDe(alumno).alCincuenta`), `compradas` (sus renglones
   `lugar` en ventas no anuladas) y `quedan` (con piso en cero). `compradasPorFamilia(ventas, anulaciones)` (id del
   alumno → cantidad) es lo que después muestra la entrega ("8 al 50 % (compró 3)"). **No se guarda: se cuenta cada vez.**
3. **`numeros_de_entradas.dart`** — `NumerosDeEntradas`:
   - `deLasVentas(ventas, anulaciones, {salvo})`: comprador → tramos. Cuentan los de una venta que cuenta y los de una
     **anulada sin devolver** (con el nombre más "(venta anulada, sin devolver)"); los de una anulada **con
     devolución** quedan libres.
   - `ocupados({entregados, ventas, anulaciones, salvoVenta})`: lo de `RetiroEntradas.tramosDeOtros` más lo vendido,
     juntando las listas de un mismo nombre. **Es el `deOtros` de `errorTramos` para la venta y para la entrega**: así
     "El 1043 ya se le dio a…" sirve para los dos (enchufarlo en la entrega es de la etapa 6).
   - `error({tramos, cantidad, ocupados})`: sin números, null (son opcionales). Si están bien escritos y no son tantos
     como entradas: "Son N números y la venta lleva M entradas." Todo lo demás lo decide
     `RetiroEntradas.errorTramos(tramos:, generales: cantidad, deOtros: ocupados)`: mismas reglas y palabras.
   - `repetidos({ventas, anulaciones, entregados})`: los que quedaron en dos ventas (o en una venta y una entrega) por
     vender en dos equipos sin internet: "El 1043 está en dos ventas (A y B): revisar". Solo avisa.
4. **`pedido_de_entradas.dart`** — `PedidoDeEntradas`, lo que decide VENDER sin pantalla: la config y el día, la
   familia (o nadie), cuántas de lugar (con tope en las que le quedan) y cuántas sueltas, el descuento a mano (solo si
   puede), el comprador y los números. Da los renglones (nombres: "Entrada", "Entrada anticipada", "Entrada de lugar
   adicional (50 %)"), el total, `falta` (por qué no se puede confirmar, en palabras: sin precio, sin nombre y
   apellido —dos palabras, como `erroresQuienRetira`—, sin entradas, los números mal) y `venta(caja, numero, cobro)`,
   que arma `VentaEntradas.nueva` desde un `CobroBarra` igual que `vender_screen.dart:224-237` de la barra
   (`efectivo: cobro.efectivo`, `transferencia: cobro.transfiere`, `recibe: cobro.recibeQueCuenta`, `recargo`,
   `recargoPct: cobro.recargoPctQueQueda`).
5. **`cierre_de_entradas.dart`** — `CierreDeEntradas`, con la forma de `CierreDeBarra` y escrito nuevo: cuántas
   sueltas y de lugar y su plata (lo que no se pueda leer de los renglones va a "otras", por la cantidad y el total de
   la venta), efectivo, transferencia, mixtos, con transferencia, recargos aparte, **descuentos a mano** en su renglón;
   **una anulada no cuenta, tampoco en el efectivo que tiene que haber**; `efectivoEsperado` = cambio inicial + efectivo
   de las que cuentan; `diferenciaCon(contado)`. `de(caja, ventas, anulaciones)` y `deLaFiesta(cajas, ventas,
   anulaciones)`. **Anulado después del cierre:** la anulación con `created_at` posterior al `cerrada_at` de su caja va
   en `efectivoAnuladoDespues` y `transferenciaAnuladaDespues` (el criterio de `anuladoDespuesDelCierre`, no la
   función). Y `ResumenDeCajaEntradas(caja, cuentas)`: **la diferencia de una caja cerrada es la que se anotó al
   cerrar**, no una cuenta de ahora.

**Tests de la etapa 2** (sección 10 del spec), cada uno con una rotura a propósito:

- `entradas_cuentas_test`: sin precio, null; el último día de la anticipada rige; al otro día, el valor; **a
  medianoche de Argentina, no de UTC** (`ArTime.toAr(DateTime.utc(2026, 11, 29, 1, 30))` todavía es el 28). 14 lugares
  y 3 compradas, quedan 11; una anulada las devuelve; no se venden más de las que quedan; el precio del lugar sale del
  valor. La venta cierra con los tres medios y con recargo; cada caso de 5.3 tira.
- `entradas_numeros_test`: contra una entrega sin cargo, contra otra venta, contra una anulada sin devolver; una
  anulada con devolución los libera; la entrega tampoco deja repetir uno vendido (con `RetiroEntradas.errorTramos` y
  `ocupados`); los repetidos entre dos ventas.
- `cierre_de_entradas_test`: una anulada no cuenta en el efectivo; los descuentos a mano en su renglón; anulada
  después de cerrar, el cierre queda y va la línea aparte.

`test/venta_entradas_no_toca_test.dart` ya mira `lib/features/entradas/cuentas`: nada de ahí puede nombrar
`saldo_deudor`, `RepartoDeSillas`, `sillas_puerta` ni lo demás de su lista (importar `retiro_entradas.dart` y
`contrato_alumno.dart` sí se puede).

### Etapa 3, el permiso "Vende entradas" y PRECIOS — HECHA (14-nov)

- **El permiso** es Entradas con un **2** en `permisos_operador.entradas` (sin columna ni SQL, como la Encargada de
  barra): `PermisoOperador.vendeEntradas` (al final del enum; no es una puerta más), `PermisosEfectivos.vendeEntradas`
  y `nivelEntradas`. `tiene(entradas)` da verdadero también con el 2: quien vende también entrega. En OPERADORES, la
  casilla **"Vende entradas"** debajo de Entradas (tildarla tilda Entradas; destildar Entradas la destilda), con el
  aviso de no tildarla hasta que todas las PCs y las tablets tengan la versión. En la lista dice "Entradas y venta".
- **La llave:** `puedeVenderEntradasProvider` (`app_role_provider.dart`): el jefe en modo jefe, o un operador con
  "Vende entradas". **Toda pantalla nueva de la venta pregunta por ahí.** PRECIOS, anular y "Pago verificado", por
  `esRolJefeProvider`, con `_frenaSinModoJefe()` antes de guardar (`test/solo_modo_jefe_test.dart` lee
  `lib/features/entradas/widgets/` y falla si una función guarda sin la llave).
- **PRECIOS:** el botón en ENTRADAS de la fiesta (`RetiroEntradasScreen`, solo en la oficina; en el mostrador no
  está), apagado y con el motivo sin modo jefe. El diálogo, `entradas/widgets/precios_de_entradas_dialog.dart`:
  valor, anticipada con su día (se escribe `28/11/2026`; `PrecioDeEntradas.diaDeTexto` y `textoDelDia`), el descuento
  de los lugares con "Cada una: $ X" a la vista, el recargo y el tilde del vendedor. Lo que está mal se dice adentro y
  no se cierra. Guardar sin cambiar nada no escribe.
- **Los providers** de la venta: `entradas/providers/entradas_providers.dart` (`entradasDeLaFiestaProvider`,
  `entradasDeLaCajaProvider`, `entradasDelJefeProvider`, `configDeEntradasProvider`). **En la web no hay venta de
  entradas** (`entradasEnEsteEquipoProvider`, `kEntradasDesdeLaPc`): lo de la venta se ve apagado.
- **Para los tests de pantalla:** `test/helpers/entradas_en_memoria.dart` (`EntradasEnMemoria`, con `reemplazos`),
  que hace lo mismo que `EntradasLocal`.
- **Probado:** 26 pruebas nuevas y **diez roturas a propósito, las diez detectadas**. La suite entera: 4.883.
- **No se probó:** con el mouse en una ventana de prueba (queda para el arnés de la etapa 7).

### Etapa 4, la caja, VENDER y el comprobante — HECHA (14-nov)

- **Por dónde se entra:** en el inicio de Entradas (`EntradasHomeScreen`), quien tiene "Vende entradas" ve **ENTREGAR ·
  VENDER** en cada fiesta (en un celular, debajo del nombre); quien solo entrega la ve como siempre. En ENTRADAS de la
  fiesta (`RetiroEntradasScreen`, la oficina), **VENDER** al lado de PRECIOS, apagado y con el motivo sin el permiso.
- **Abrir la caja** (`widgets/abrir_caja_entradas_dialog.dart`): VENDER sin caja abierta la pide, con su cambio
  inicial. Sin precio no la abre y lo dice. Si baja de la nube otra caja abierta de esa persona en otro equipo, avisa y
  deja seguir. **Volver sin abrirla sale de VENDER.** La caja del jefe va sin operador (`operador_id` null).
- **VENDER** (`widgets/vender_entradas_screen.dart`): la línea "Caja abierta · Carla · Todo subido"
  (`cuentas/linea_de_subida.dart`), a quién (una familia, con buscador; o alguien de afuera), los renglones con su
  cantidad, el descuento a mano (apagado y con el motivo sin permiso), los números (un tramo con el "al" calculado, o
  dos) y el total con EFECTIVO · TRANSFERENCIA · MIXTO, que abren **la hoja del cobro de la barra** (`pedirCobro`).
  **Toda la cuenta sale de `PedidoDeEntradas`**: la pantalla lo arma de nuevo en cada dibujo con lo escrito.
  - La venta **se guarda antes de abrir el comprobante**; si el comprobante falla, la venta queda y lo dice.
  - Con el 100 % de descuento el botón es GUARDAR SIN CARGO, con una pregunta, sin pasar por el cobro.
  - **Para releer lo que debe la familia escucha `contratos_alumnos`, no la tabla de los pagos**: el guardián
    (`venta_entradas_no_toca_test`) no deja nombrarla, y un cobro siempre cambia la cuenta del alumno.
  - Por debajo de 560 px se acomoda como en un celular (rótulos y botones uno debajo del otro).
- **El comprobante** (`pdf/comprobante_entradas_pdf.dart`, media A4; `pdf/papeles_de_entradas.dart` lo abre con las
  letras de la app y el isotipo): no hace cuentas, dice lo que la venta tiene guardado. COPIA al reabrirlo; ANULADA
  cruzado con el motivo.
- **El nombre de la fiesta** en todo lo de la venta: `services/nombre_de_la_fiesta.dart` (la institución; si el evento
  no la trae, su título, nunca "Evento").
- **Las llaves:** `_frenaSinPermiso()` (con `puedeVenderEntradasProvider`) antes de abrir una caja o guardar una venta;
  `test/solo_modo_jefe_test.dart` lo exige en `lib/features/entradas/widgets/`.
- **Las muestras** (las pantallas de verdad, con el tema claro de la app): `tool/venta_entradas_muestra_test.dart`
  (`--dart-define=salida=…`; quedaron en `build/muestras_6.9.0/venta_entradas/`). `test/helpers/tema_de_la_app.dart`
  copia el tema de `main.dart`, que es privado. **Mirándolas aparecieron tres defectos que ningún test veía** (en el
  celular los botones partían el texto y los rótulos se cortaban; en la PC los subtotales no quedaban alineados; un
  rótulo de PRECIOS se cortaba): corregidos.
- **Probado:** 39 pruebas nuevas (la pantalla entera con la hoja del cobro de verdad, el comprobante medido, las dos
  entradas) y **trece roturas a propósito, las trece detectadas**. La suite entera: 4.922.
- **No se probó:** con el mouse en una ventana, ni el PDF abierto desde el programa (la entrega del PDF en Windows);
  una tablet de verdad.
- **Distinto de la maqueta:** el comprobante se abre solo al guardar (la maqueta mostraba solo el botón); VENTAS y
  CERRAR CAJA todavía no están en la barra de VENDER (etapas 5 y 6).

### Etapa 5, VENTAS — HECHA (14 y 15-nov, `cba8c7d`)

- **La cuenta del historial**, sin pantalla: `cuentas/historial_de_entradas.dart` (`HistorialDeEntradas.de`,
  `VentaDelHistorial`, `FiltroDeVentas`). Cada venta con su anulación y su verificación, de la más nueva a la más
  vieja; `soloDeLaCaja` para quien vende. **Los números repetidos se buscan en toda la fiesta aunque se mire una
  caja.** Una anulada no cuenta como verificada ni espera verificación.
- **La pantalla** `widgets/ventas_de_entradas_screen.dart`: quien vende ve las de su caja (y sin caja, ninguna), el
  jefe todas; el aviso de números repetidos arriba; el filtro Todas · Verificadas · Sin verificar; los totales en un
  renglón; cada venta con REIMPRIMIR (COPIA, y ANULADA si corresponde), **Pago verificado** y **ANULAR**, las dos
  últimas solo del jefe (apagadas con el motivo, y `_frenaSinModoJefe()` en `_verificar` y `_anular`).
- **Quien vende no ve sumas de plata** (revisión del 15-nov; la maqueta tampoco las mostraba): ni en el renglón de los
  totales ni en su historial impreso (`DatosDelHistorial.conPlata`, `_conPlata`). Con el total de su caja abierta
  sabía cuánto efectivo tenía que haber, y el cierre se cuenta a ciegas. El monto de cada venta sí, como en la barra.
- **Anular** abre un cartel (`_AnularVentaDialog`): motivo obligatorio y **"¿Devolvieron las entradas y las
  pulseras?"**, con los números a la vista. La venta queda en la lista, tachada, con quién, cuándo, el motivo y si
  devolvieron.
- **El historial impreso** (`pdf/historial_entradas_pdf.dart`, A4): la casilla de la tilde dibujada, las anuladas
  tachadas con su motivo abajo, los totales y los repetidos; **cada fecha en un renglón** ("20/11 21:40",
  `cuandoEnLaTabla`: con el año y el "hs" partía cada fila en dos).
- **Las dos entradas:** VENTAS en la barra de VENDER (`vender_ventas`, solo con la caja abierta; al volver relee) y en
  ENTRADAS de la fiesta (`entradas_ventas`, solo en modo jefe, apagado con el motivo, no en el mostrador).
- **En el celular**, IMPRIMIR HISTORIAL es un ícono (con el texto, el título se cortaba) y los botones de cada venta
  van en un `Wrap`; en la PC el "$" no se separa de su número (espacio duro).
- **Lo que encontró la revisión independiente del 15-nov** (lectores que buscan y otros que intentan refutar), ya
  arreglado:
  - **dos alumnos con el mismo nombre se pisaban los números entregados** (`RetiroEntradas.tramosDeOtros` armaba el
    mapa de una vez): el número de uno se podía vender, o entregar sin cargo, sin aviso. **Vale también para la
    entrega sin cargo, que está en las PCs desde la 6.0.0**; ahora junta los tramos;
  - VENDER seguía mostrando "guardada" la última venta después de anularla desde VENTAS, y su copia salía sin
    ANULADA: ahora el aviso se va y la copia lleva la anulación;
  - quien vende veía la suma de su caja (arriba).
  - **Queda como pendiente** que el jefe anule la misma venta desde dos PCs antes de que una se entere de la otra:
    `docs/pendientes/anular-dos-veces-desde-dos-pcs.md`.
- **Pruebas:** `test/historial_de_entradas_test.dart` (16, con el total de cada renglón del PDF vigilado por su lugar
  en la hoja), `test/ventas_de_entradas_test.dart` (13, con el celular), las dos entradas en
  `vender_entradas_pantalla_test` y `retiro_entradas_screen_test`, y los homónimos en `retiro_entradas_test`.
  **Catorce roturas a propósito, las catorce detectadas.** La suite entera: 5.008.
- **Las muestras:** `tool/venta_entradas_muestra_test.dart` saca VENTAS como jefe, como quien vende y en el celular,
  el cartel de anular y `Historial_de_ventas.pdf` (en `build/muestras_6.9.0/venta_entradas_v5/`). El PDF se miró
  página por página.
- **El arreglo de `retiro_entradas_screen_test`:** `_montar` pone siempre un `EntradasEnMemoria` (sin eso, lo que la
  pantalla lee de la venta caería en la base de verdad).

### Etapa 6, cerrar la caja, ENTRADAS del cierre y la entrega — HECHA (15-nov)

1. **Cerrar la caja (9.1)**, `widgets/cerrar_caja_entradas_screen.dart`, desde **CERRAR CAJA** en la barra de VENDER
   (`vender_cerrar`, al lado de VENTAS):
   - **contar a ciegas**: el efectivo con el cambio y una nota opcional, sin ninguna plata de la caja a la vista
     (`test/cerrar_caja_entradas_test.dart` lee `_contar()` y falla si aparece); VOLVER A VENDER · CERRAR LA CAJA;
     confirma con el número grande ("¿Contaste todo el efectivo, con el cambio?");
   - recién cerrada: Contaste · Tenía que haber · Justo / Sobran / Faltan (`diferenciaEnPalabras`), y las cuentas
     (cambio, efectivo, transferencia, mixtas, vendidas "N (X sueltas y Y de lugares)", descuentos a mano, anuladas,
     lo anulado después del cierre). **La diferencia se anota al cerrar**; después solo AGREGAR UNA NOTA
     (`anotarCierre`). Sin el OK de una encargada (eso es de la barra);
   - `_cerrarDeVerdad` lleva `_frenaSinPermiso()` (`solo_modo_jefe_test` espera ahora
     `{'_abrir', '_cobrar', '_cerrarDeVerdad'}`);
   - **cerrada, VENDER se va**, y mientras el cierre está abierto VENDER no pide caja aunque relea
     (`_cerrandoCaja`): si no, el cartel de abrir saldría encima;
   - **el papel** (`pdf/cierre_caja_entradas_pdf.dart`, media A4, una hoja; `abrirCierreDeEntradasProvider`): la
     fiesta, quién, abierta y cerrada, lo vendido, la plata, lo que tenía que haber, lo contado, la diferencia y la
     nota. **Se abre solo al cerrar** (como el comprobante; la maqueta mostraba solo el botón) y queda IMPRIMIR EL
     CIERRE.
2. **ENTRADAS en el cierre de caja (9.2)**, `cierre_caja/widgets/sector_entradas.dart`: la misma elección de fiesta que
   BARRA (`FiestaDelCierre`, en `estilo_del_sector.dart`, que ahora usan las dos; BARRA se ve igual), una línea por
   caja (CAJA · CAMBIO · EFECTIVO · TRANSF. · MIXTOS · VENDIDAS · DESC. · ANUL. · CONTÓ · DIFERENCIA, o "abierta"), la
   fila TOTAL y las tarjetas TOTAL VENDIDO, ANULADO DESPUÉS DEL CIERRE (si hay) y CAJAS. La cuenta es
   `CajasDeEntradasDeLaFiesta` (`cuentas/cierre_de_entradas.dart`: lo contado y la diferencia suman solo las
   cerradas) y la lee `cajasDeEntradasDeLaFiestaProvider`. Sin precio, sin cajas y en la web lo dice. El cartel "se
   venden a mano, fuera de la app" se fue. `tool/cierre_sector_prueba.dart` muestra dos cajas, y
   `reemplazosDelCierre` pone siempre la venta en memoria.
3. **La entrega con lo vendido a la vista (9.3)**, en `RetiroEntradasScreen` y `entrega_entradas_dialog.dart`:
   - la tarjeta **"Al 50 %: 3 vendidas de 8"** y en cada familia **"· 8 al 50 % (compró 3)"** (solo si compró
     alguna); sin precio en la fiesta (o en la web) se ve como antes;
   - en el cartel de la entrega, "Ya compró 3: le quedan 5." y **VENDERLE ESAS ENTRADAS**, que abre VENDER con la
     familia elegida (`VenderAlCincuenta`; doble llave en `_venderAlCincuenta`); sin el permiso, "Se las vende quien
     tiene la caja de entradas.". **También en el mostrador** (a quien tenga "Vende entradas"), **con la familia que
     debe** (la deuda frena solo lo sin cargo) **y con la que ya retiró**; no con las mesas o la cuenta mal cargadas;
   - **un número vendido no se entrega sin cargo**: la entrega usa `NumerosDeEntradas.ocupados` (`_ocupadosPara`) en
     el cartel y al revalidar antes de guardar;
   - **la entrega no depende de la venta**: si no se puede leer, sigue como antes de la 6.9.0.
4. **Lo que baja con "Lista para trabajar sin internet" (7.3):** las cinco tablas de entradas y `entradas_retiro`
   entran en `SyncEngine.tablasDeLaPuerta` (`sync_tablas_v80_test`). **Sin el SQL de la v80 en la nube, esa línea no
   queda lista**: el SQL se corre antes de instalar, como siempre.

- **Lo que encontró la revisión independiente del 15-nov** (9 confirmados, ya arreglados):
  - **ENTRADAS del cierre seguía viejo** después de lo hecho en la misma PC (una caja recién cerrada figuraba
    "abierta"): `cajasDeEntradasDeLaFiestaProvider` es `autoDispose`, y cerrar, la nota, vender, abrir la caja, anular
    y PRECIOS avisan con `avisarQueCambioLaVenta`; el botón de recargar del cierre también lo relee.
  - **"Anulado después del cierre" comparaba los relojes de dos equipos:** la tablet que cierra sin internet no sabe
    de una venta que el jefe anuló antes desde la oficina, y ese efectivo desaparecía. Ahora, para una caja cerrada,
    sale de lo anotado al cerrar (`CierreDeEntradas.esperadoAlCerrar` = lo contado menos la diferencia; lo que falta
    desde lo de ahora es anulado después, con tope en lo anulado de esa caja). La hora queda solo para la
    transferencia. "Tenía que haber" de una caja cerrada es lo anotado al cerrar, en la pantalla y en el papel.
  - **ENTRADAS del cierre podía abrir en un evento particular** (la lista de BARRA trae todos):
    `fiestasDeEntradasDelCierreProvider` lleva solo los masivos; la elección sigue compartida.
  - **Los números entregados a un alumno que después pasó a baja temporal quedaban libres** (viene de antes): la
    entrega y VENDER los cuentan (`_todos`, con las bajas, solo para los números ocupados).
  - Cerrar la caja: Atrás y LISTO esperan a que termine de cerrar y de salir el papel; si el papel no salió, LISTO
    pregunta ("Después no se puede volver a sacar"); VENDER, cerrada la caja, ya no puede pedir otra mientras se va.
  - Descartado: al volver de VENDERLE ESAS ENTRADAS la entrega no se reabre sola (no se pierde nada guardado).
  - Cinco roturas a propósito más, sobre estos arreglos: las cinco detectadas.
- **Pruebas:** `test/cerrar_caja_entradas_test.dart` (17: la pantalla entera, a ciegas, sin permiso, el cierre por
  sector que se entera, el papel que no salió, el papel medido y leído), `cierre_por_sector_test` (sin precio, sin cajas, dos cajas, la web, el celular), `cierre_de_entradas_test`
  (la cuenta de la fiesta y lo que el cierre no conoció), `retiro_entradas_screen_test` y
  `entrega_entradas_dialog_test` (lo vendido, VENDERLE con y sin permiso, el número vendido, el de un alumno de baja).
  **Catorce roturas a propósito, las catorce detectadas.** La suite entera: 5.054.
- **Las muestras** (`tool/venta_entradas_muestra_test.dart`, en `build/muestras_6.9.0/venta_entradas_v6/`): cerrar la
  caja (contar, confirmar, cerrada, el celular), `Cierre_de_caja_entradas.pdf`, ENTRADAS del cierre (PC y celular) y
  la entrega con VENDERLE ESAS ENTRADAS. Se miraron todas.
- **No se probó:** con el mouse en una ventana, ni el PDF abierto desde el programa, ni en una tablet de verdad. Es la
  etapa 7.

### Etapa 7, la prueba de punta a punta — HECHA (15-nov, a la tarde); falta publicar con él

Plan aprobado el 15-nov ("prosigamos", con el botón): `C:\Users\lover\.claude\plans\prosigamos-eventual-crab.md`.

1. **Los peligros de las ventanas de prueba (commit `c2adc64`).** Cinco podían, con un clic, abrir y migrar a la v80 la base de
   verdad de la PC, o escribir las preferencias del programa instalado o su carpeta de PDF: la del mostrador de Entradas (al
   abrir una fiesta), las de Recepción (Actualizar la lista, Vaciar, Agregar; y las preferencias), la de la barra (la tablet que
   espera el OK de la encargada, la notebook al contar lo suyo, los PDF) y la de operadores (VENDER). **Ninguna llegó a hacerlo:
   la base de esta PC sigue en la 79, sin `antes_de_v80.db`.** Ahora:
   - `LocalDatabase.cerrarParaLaPrueba()` (un solo freno, `_frenarSiEstaCerrada`, para `instance` y `dbPath`): toda ventana lo
     llama al arrancar. La app nunca.
   - Cada ventana pone en memoria lo que le faltaba; `InvitadosEnMemoria` reemplaza todo lo que abre la base;
     `RepoTotemEnMemoria` pasó a `test/helpers/repo_totem_en_memoria.dart` (sin `flutter_test`, para usarlo en Windows).
   - `test/arneses_sin_base_test.dart` lee las ventanas y lo vigila; `test/base_cerrada_para_la_prueba_test.dart`, el freno.
   - `tool/huella_de_la_base.py`: la huella de la base (sin abrirla), de las preferencias y de la carpeta de PDF. Antes y después
     de cada sesión con el mouse: **dio IGUAL las tres veces** el 15-nov.
   - Para las capturas de la Parte A, con `--dart-define`: `central_puerta_prueba` (`red=local`, `tele=masivo`,
     `personalizar=cambio`, `sillas=2`) y `barra_prueba` (`impresora=ninguna`, `anoche=si`).
2. **Las dos pruebas que faltaban (`ce933cb`):** Atrás mientras se cierra la caja (`_CierreQueTarda`) y la segunda llave de
   VENDERLE ESAS ENTRADAS (con el cartel abierto y leyendo el código).
3. **La ventana de la venta (`4d26a70`):** `tool/venta_entradas_prueba.dart` + `test/venta_entradas_prueba_test.dart` (7). Dos
   equipos con su base (`EntradasDeUnEquipo`: `tablet-carla` y `pc-oficina`), una nube de prueba (`NubeDeLaPrueba`: sube a los
   2 s, `CORTAR INTERNET` deja todo en la cola, al volver suben las dos colas), los papeles de la app en `build/` (sin el menú de
   la app) y el modo jefe con una sola llave (`adminAuthProvider → ModoJefeDelCierre`). La noche arranca con precio, la caja de
   Maxi cerrada con $ 500 de menos y PÉREZ con 8 lugares al 50 %.
   - **Arreglo de la app:** VENDER quedaba en "1 venta subiendo" con la venta ya en la nube (el aviso del motor sale al bajar,
     no al subir). Ahora escucha `pendingStream` y vuelve a contar (`_contarSinSubir`). La prueba falló primero con el código de
     antes.
4. **Las roturas a propósito:** 22 en total entre los pasos 1 a 3, todas detectadas. Tres que no se detectaban al principio
   eran controles repetidos (el freno de la base y el de la nube de prueba): se dejó uno solo.
5. **La suite entera: 5.078 pruebas, todas pasan** (eran 5.054).
6. **El recorrido con el mouse** (`2462f87` ordena dónde caen los papeles: una ventana compilada corre con la carpeta del exe
   como la actual; `tool/raiz_del_proyecto.dart`). Se recorrió la venta entera con los dos equipos (abrir la caja, vender 3 de
   los lugares de PÉREZ con talonario, el comprobante, la entrega del jefe con "Ya compró 3: le quedan 5", VENTAS, verificar,
   el historial impreso, PRECIOS, MODO JEFE en NO, ENTRADAS del cierre, vender sin internet y volver, anular desde el jefe y
   que le llegue a Carla, VENTAS de Carla sin sumas, cerrar la caja a ciegas con su papel, el cierre del jefe con la caja
   cerrada, Carla en un celular) y los carteles de la Parte A (la pregunta de la tele, la de los celulares, Actualizar la
   lista sin nube, Personalizar que no pisa, las sillas sin subir, el vale sin impresora). **Las capturas y los tres papeles
   se le mandaron**; están en `build/capturas_6.9.0/` (no van a git).
   - No se capturó "la fiesta de anoche hasta el mediodía": la sesión fue a la tarde (lo cubren sus pruebas).
   - **Para traer una ventana de prueba al frente no usar `open_application`: abre otra copia** (pasó: tres ventanas).
7. **La revisión independiente de toda la 6.9.0** (Workflow de cinco lectores por tema —la noche, la mora y los recibos, la
   venta, los datos y la v80, la convivencia con PCs en la 6.8.0— y un verificador por hallazgo que intentó refutarlo, solo
   lectura; el resultado entero, en `build/revision_6.9.0.json`, fuera de git). **9 hallazgos: 6 confirmados (todos
   medios) y 3 descartados.** Ninguno cambia plata ni datos; nada estaba instalado. Arreglados, cada uno con su prueba y
   su rotura a propósito (11 de 11 detectadas):
   - **La tele después de SOLO MIRAR ACÁ** (`51e3702`): el botón TÓTEM del Centro de Comando la pasaba en silencio a la
     fiesta de Recepción y, con el filtro de la 6.9.0, dejaba de saludar a los de esa noche. Ahora pregunta
     (`fiestaParaAbrirLaTele`: SEGUIR CON LA DE LA TELE · PASAR EL TÓTEM).
   - **La tele sin internet con la config de fábrica** (`51e3702`): abierta antes para otra fiesta, buscaba la config de
     la de la noche en su copia vieja de las preferencias. Ahora le pregunta a la principal (`leer_preferencia`, solo las
     preferencias de la tele; si no contesta, su copia).
   - **Una caja de entradas (o de la barra) abierta después del mediodía** (`51e3702`): la fiesta salía de la lista y la
     caja quedaba abierta para siempre. Ahora la fiesta sigue en la lista de quien tiene ahí su caja abierta, en ese
     equipo (`conCajaAbierta`), hasta que la cierre.
   - **El recibo reimpreso: la mora de una cuota cobrada a medias** decía "Debía $5.000 · Quedó $0" (se guarda sin
     "(parcial)"). Ahora la reconstrucción lo confirma como en las mixtas (`_confirmarParcialDeUnaCuota`,
     `_moraQueQuedoElDia`).
   - **El recibo reimpreso de un Mixto con la mora partida** en efectivo y transferencia (dos filas, mismo concepto): cada
     fila se repartía sola y la cuota del arrastre salía dos veces. Ahora se juntan antes de repartir
     (`_juntarMoraPartida`), como ya hacía la ficha.
   - **El título del recuadro verde reimpreso** decía "PARCIALMENTE" solo porque la familia debe hoy otra mora. Ahora no
     mira la mora de hoy (`tituloMoraCobradaPdf`).
   - Descartados por el verificador: que quien vende pueda cambiar el recargo por transferencia (es la regla de la spec,
     queda para preguntarle al jefe), que una lectura fallida en el cierre guarde una diferencia falsa (no pasa), y que
     una PC con la 6.9.0 sin el SQL de la v80 no haga la revisión de la mora al arrancar (el camino de publicar corre el
     SQL antes de instalar).
   - **Los tres del recibo tocan cómo se nombra la mora al reimprimir: antes de publicar, el comparador de la mora de la
     6.8.1 (`tool/rotulo_mora_antes_despues_test.dart` en la 6.8.0 y en la versión, `tool/comparar_rotulo_mora.py`) tiene
     que mostrar esos cambios y ningún otro.**
8. **La hoja C, cerrada (15-nov, a la noche).** La forma C del historial impreso (programada en `d3dee79`):
   - **Las roturas:** 22 sobre lo programado; dos no se detectaban (el talonario largo que no bajaba y el segundo
     renglón largo cortado a uno) y una solo la veía una prueba vecina (los totales sin hoja propia: **no se salen de
     la hoja, desaparecen**, porque lo que no entra en una `pw.Page` no se dibuja). Se sumaron las pruebas.
   - **La muestra con las letras de la app mostró lo que las pruebas no veían** (con Helvetica sí entraba): el N°
     cortado ("0004" salía "000": Outfit tiene los números de distinto ancho), "VERIF." cortado, los nombres largos sin
     el final, y en el cartel el "10" cortado en su cajita. Arreglado: las columnas se miden con la letra de verdad en
     un test (`PdfFont.stringMetrics`; **un PDF con Outfit no se lee palabra por palabra**), el nombre que no entra
     va entero en el segundo renglón y la cajita va con poco relleno.
   - **La revisión independiente** (Workflow, 4 lectores —la hoja C, el cartel y VENTAS, la tele y la caja, el
     recibo reimpreso— y 3 verificadores por hallazgo que intentan refutarlo; resultado en
     `build/revision_hoja_c.json`, fuera de git): **15 hallazgos, 13 confirmados (1 medio, 12 bajos), ninguno cambia
     plata ni datos**. Arreglados 11, cada uno con su prueba:
     - ENTRADAS, CUÁNDO, TOTAL y VEND. cortaban texto ("8 lugar + 2", la hora con ceros, "$ 1.000.000" como "$",
       "Juan Pablo" y "Juan Carlos" los dos "Juan"): columnas medidas con los peores casos reales, y lo que igual no
       entra baja entero al segundo renglón ("13 en total" arriba).
     - Con muchos números repetidos los totales no entraban ni en una hoja: ahora siguen en otra
       (`HojaDelHistorial`); si entran juntos, van juntos.
     - La marca "impresa" de una tanda seguía aunque sus hojas cambiaran: ahora va con lo que decían
       (`firmaDeLasHojas`).
     - **(el medio)** En la barra, la fiesta de anoche con la caja olvidada salía primera y sin marca, y se vendía
       en ella: ahora las que ya pasaron van al final y marcadas en Entradas y en la barra (`laFiestaYaPaso`,
       `enElOrdenDeLasFiestas`).
     - Cerrada esa caja, la lista no se releía (seguía "Tu caja sigue abierta"): se relee al volver de VENDER.
     - La tele sin internet podía salir con una config de la tarde que ella había guardado: lo que le llegó a la
       principal ya no le gana a la principal (`PreferenciasDeLaVentana._sinEntregar`).
     - Con un perdón en la ficha, el recibo reimpreso podía decir "a medias" una mora pagada entera: con un perdón,
       la línea sale como se guardó (`_confirmarParcialDeUnaCuota`).
   - **Los otros dos son los límites ya anotados en la 6.8.1** ("Límites conocidos" de su CONTEXTO): dos cobros del
     mismo alumno el mismo día, y el título "EN SU TOTALIDAD" de un reimpreso que mira la mora de hoy. Quedan así.
   - **Las roturas de los arreglos: 21 de 21** (la del tope de 4 cifras de la cajita necesitó su prueba).
   - Nombres y números de la muestra, inventados.

### La maqueta — HECHA, mostrada y **APROBADA el 14-nov** ("Sí, seguí")

`docs/maqueta_venta_de_entradas_2026-11-14.html` (un solo archivo, sin imágenes, 48 KB: abre en el panel de la app).
Nueve pasos, cada uno con su "Dónde:" (por dónde se llega): PRECIOS, por dónde se entra (ENTREGAR · VENDER), abrir la
caja, VENDER (con el cobro), el comprobante, VENTAS, cerrar la caja, ENTRADAS del cierre y la entrega con lo vendido a
la vista. Arriba se elige mirar como quien vende o como el jefe, y si rige la anticipada. Se puede tocar todo: una
venta hecha en el paso 4 aparece en el comprobante, en VENTAS, en el cierre y en el sector.

- **Las pantallas van con el tema claro**, que es el del programa (`ThemeMode.light`); la maqueta de la encargada las
  había pintado oscuras. Los textos, las tarjetas y los estados de `RetiroEntradasScreen`, `EntradasHomeScreen`, el
  diálogo de entrega y el cierre por sector se copiaron del código.
- **Para mirarla:** `preview_start` con `maquetas` (`.claude/launch.json`, sirve `docs/` en el 8796). Abre en un paso
  con `…html#p=4&caja=1&jefe=1&nombre=…`. Las capturas de cada paso, en
  `build/maquetas/venta_de_entradas_2026-11-14/` (no van a git; se sacan con Edge sin ventana, **cada una con su
  propio perfil y reintentando**: de corrido, Edge se saltea algunas).
- Probada con clics simulados de punta a punta (los mismos mensajes que da `PedidoDeEntradas.falta`), sin errores en
  la consola.

**Aprobada el 14-nov.** Lo que se programe distinto de la maqueta se le dice (y se le muestra) antes de publicar.

### Para preguntarle al jefe (ninguna frena el trabajo)

Si el vendedor puede descontar solo; si la transferencia lleva recargo; si el número del talonario es obligatorio; si
"Pago verificado" lo tilda solo él; si se vende la noche de la fiesta y desde cuántos equipos; y si la silla que se
compra esa noche en la barra lleva además su entrada al 50 %. Hoy cada una es un dato de PRECIOS o una regla que se
cambia sin reprogramar.
