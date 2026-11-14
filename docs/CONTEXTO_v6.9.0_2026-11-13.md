# CONTEXTO — la 6.9.0: los arreglos de la noche y la venta de entradas

**Estado (14-nov-2026, al cortar el chat):** en curso, **sin publicar**. Rama `feature/v4.6-cierre-por-sesiones`,
todo en esta PC, **sin subir a GitHub**.

## Para retomar en otro chat

**Dónde quedó (14-nov, al cortar el chat a pedido del usuario):**

- **Parte A (los arreglos de la noche): hecha entera.** Faltan solo sus capturas con el mouse, antes de publicar.
- **Parte B (la venta de entradas), 7 etapas:**
  - **1 a 4, hechas y guardadas:** los datos (v80), las cuentas, el permiso "Vende entradas" con PRECIOS, y la
    caja con VENDER y el comprobante. **Ya se puede vender con comprobante.**
  - **5 (VENTAS), a medias y guardada como está:** la pantalla anda y tiene sus pruebas (ver "Etapa 5", abajo, con
    **lo que le falta**). **Empezar por ahí.**
  - **6 (cerrar la caja, la pestaña ENTRADAS del cierre y la entrega): sin empezar.** El plan, en "Etapa 6", abajo.
  - **7 (la ventana de prueba, recorrerlo con el mouse, las capturas y publicar): sin empezar.**
- **El usuario aprobó la maqueta el 14-nov ("Sí, seguí")**: las pantallas se programan como están ahí
  (`docs/maqueta_venta_de_entradas_2026-11-14.html`). Ya vio VENDER de verdad y el comprobante (se le mandaron las
  muestras); no opinó todavía.
- **Preguntó dos veces cuánto falta para publicar.** Se le dijo: terminar la 5, hacer la 6, la prueba de punta a
  punta, y publicar con él; entre 2 y 4 tandas de trabajo, con margen para el 4-dic.
- Antes de cortar se dejó todo en verde: **la suite entera pasa (4.947 pruebas, 288 archivos, 8 tandas)** y el
  repositorio sin cambios sueltos. El 14-nov, al retomar después de una compactación, lo primero fue comprobar que
  nada había quedado a medias (la suite en verde, 4.803) antes de escribir nada.

**Nada de esto está en las PCs ni en la nube**: no se publicó, no se instaló, no se corrió ningún SQL, no se tocó la
base de verdad ni ningún sorteo. La versión sigue en `6.8.0+74` en `pubspec.yaml`: se sube a `6.9.0` al publicar.

**Qué es.** Una sola versión, la 6.9.0, con dos partes y en este orden (plan aprobado por el usuario el 13-nov):

- **Parte A — los arreglos de la noche.** Lo que encontró la revisión del 13-nov sobre la 6.8.0
  (`docs/SPEC_arreglos_antes_de_las_fiestas_2026-11-13.md`; el informe con capturas,
  `docs/REVISION_ANTES_DE_LAS_FIESTAS_2026-11-13.md`). **Programada y guardada entera** (5 commits). Sin SQL ni migración.
- **Parte B — la venta de entradas.** `docs/SPEC_venta_de_entradas_2026-11-13.md` (cinco tablas nuevas, v80, un SQL solo
  de agregar). **Empezada** (ver "Parte B", abajo). La primera recepción es el 4-dic.

**Lo que decidió el usuario el 13-nov** (no volver a preguntarlo):

- **"Lo programes pero no publiques, entonces mandamos todo en una versión."** Los arreglos no salen solos como 6.8.1.
  Si antes del 4-dic hiciera falta sacarlos solos, se pueden armar desde el commit `3136ffe`: se le pregunta.
- **El sorteo que ya está hecho no se toca** (el punto P6 del spec, la mesa "principal" con "Al final"): "si el jefe no
  dijo o no modificó, debe permanecer así, por algo será". Queda anotado en el spec como observación, sin arreglo.
  Al contárselo se asustó: **primero decir que el sorteo y las mesas están bien y que no se cambió nada.**
- **Antes de las pantallas de la venta de entradas, una maqueta y su OK.** Los datos y las cuentas (sin pantallas) van
  sin preguntar.
- Publicar, correr el SQL y cada instalación: con él, preguntando en el momento, con las capturas.

**Lo que sigue, en orden:**

1. ~~Parte B, etapa 1 (los datos)~~: hecha (`c5521e0`).
2. ~~Etapa 2 (las cuentas)~~: hecha el 14-nov (ver "Etapa 2", abajo).
3. ~~La maqueta~~: hecha, mostrada y **aprobada el 14-nov** ("Sí, seguí").
4. ~~Etapa 3 (el permiso y PRECIOS)~~ y ~~etapa 4 (la caja, VENDER y el comprobante)~~: hechas el 14-nov.
5. **Terminar la etapa 5 (VENTAS): empezar acá.** Lo que le falta está en "Etapa 5", abajo. **Sin anular, un error
   de carga no tiene arreglo: la 5 tiene que salir con la 4.**
6. **Etapa 6** (cerrar la caja, ENTRADAS del cierre, la entrega): el plan, en "Etapa 6", abajo.
7. **Etapa 7:** la ventana de prueba (`tool/venta_entradas_prueba.dart`), recorrerlo con el mouse, las capturas
   para el usuario (las quiere ver antes de publicar), la migración v80 sobre una copia de la base real (con el
   programa cerrado: se le pide), y publicar con él (foto de la mora antes, el SQL con su OK, el instalador por
   pasos, la web). Al publicar: `pubspec.yaml` a `6.9.0`, y en `CLAUDE.md` sacar "sin programar" de "El retiro de
   entradas".

**Pendiente de la Parte A, antes de publicar:** las capturas con el mouse de los carteles nuevos (el permiso para
manejar la ventana de prueba se pidió y no se aprobó esa noche: volver a pedirlo), y lo de "Lo que no se probó".

**Cómo se trabaja acá** (lo que hizo falta aprender en este chat):

- La suite entera se corre por tandas de 40 archivos, sin los tres tests que consultan la nube
  (`verify_supabase_content_test`, `query_supabase_id_test`, `search_supabase_broad_test`): entera en un solo comando
  no entra. Tarda unos 4 minutos.
- Los archivos tienen fin de línea de Windows: un test que lee código lo normaliza (`.replaceAll('\r\n', '\n')`).
- Los cambios de varias líneas a archivos grandes (`local_database.dart`, `sync_engine.dart`) se hicieron con un
  script escrito a un archivo y corrido, no con texto pegado en la consola.
- Cada commit: el mensaje en un archivo y `git commit -F`. Sin nombres de alumnos (el repositorio es público).
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

### Etapa 5, VENTAS — A MEDIAS (14-nov): la pantalla anda, falta cerrarla

**Hecho y guardado** (con sus pruebas en verde):

- **La cuenta del historial**, sin pantalla: `cuentas/historial_de_entradas.dart` (`HistorialDeEntradas.de`,
  `VentaDelHistorial`, `FiltroDeVentas`). Cada venta con su anulación y su verificación, de la más nueva a la más
  vieja; `soloDeLaCaja` para quien vende. **Los números repetidos se buscan en toda la fiesta aunque se mire una
  caja.** Una anulada no cuenta como verificada ni espera verificación.
- **La pantalla** `widgets/ventas_de_entradas_screen.dart`: quien vende ve las de su caja, el jefe todas; el aviso de
  números repetidos arriba; el filtro Todas · Verificadas · Sin verificar; los totales en un renglón; cada venta con
  REIMPRIMIR (COPIA, y ANULADA si corresponde), la casilla **Pago verificado** y **ANULAR**. Las dos últimas, solo el
  jefe: apagadas con el motivo, y `_frenaSinModoJefe()` en `_verificar` y `_anular`
  (`test/solo_modo_jefe_test.dart` ya espera `{'_guardar', '_anular', '_verificar'}`).
- **Anular** abre un cartel (`_AnularVentaDialog`, en el mismo archivo): motivo obligatorio y **"¿Devolvieron las
  entradas y las pulseras?"**, que también hay que contestar, con los números a la vista. La venta queda en la lista,
  tachada, con quién, cuándo, el motivo y si devolvieron.
- **El historial impreso** (`pdf/historial_entradas_pdf.dart`, A4, la tabla hija directa del `MultiPage`): la casilla
  de la tilde va dibujada, las anuladas tachadas y con su motivo abajo, los totales y los repetidos. Lo abre
  `abrirHistorialDeEntradasProvider` (`pdf/papeles_de_entradas.dart`).
- **Las dos entradas:** el botón **VENTAS** en la barra de VENDER (`vender_ventas`; al volver relee, porque una
  anulada cambia lo que le queda a la familia y los números libres) y en ENTRADAS de la fiesta (`entradas_ventas`,
  solo en modo jefe, apagado con el motivo).
- **Pruebas:** `test/historial_de_entradas_test.dart` (13: la cuenta y el PDF medido y leído) y
  `test/ventas_de_entradas_test.dart` (12: la pantalla entera).

**Lo que le falta a la etapa 5 (empezar acá):**

1. **Las pruebas de las dos entradas a VENTAS**, que no se escribieron: en `vender_entradas_pantalla_test`, que
   `vender_ventas` abre `VentasDeEntradasScreen` con su caja; en `retiro_entradas_screen_test`, que `entradas_ventas`
   está apagado con `kSoloEnModoJefe` sin modo jefe, abre en modo jefe y no está en el mostrador.
2. **Las roturas a propósito** (ninguna se hizo en esta etapa). Con `tool/romper_una_regla.sh`. Las que conviene:
   quien vende ve solo su caja (`_soloDeLaCaja`); `_frenaSinModoJefe()` en `_verificar` y en `_anular`; anular sin
   motivo; anular sin contestar si devolvieron; una anulada no cuenta como verificada (`verificada`); el filtro
   "Sin verificar" sin las anuladas; los repetidos en toda la fiesta; el total del historial impreso.
3. **Mirarla:** sumar a `tool/venta_entradas_muestra_test.dart` VENTAS como jefe y como quien vende, el cartel de
   anular y el PDF del historial con las letras de la app. **El historial impreso no se miró nunca con los ojos.**
4. La suite entera y el commit de cierre de la etapa.

### Etapa 6, cerrar la caja, ENTRADAS del cierre y la entrega — SIN EMPEZAR

Sección 9 del spec. Las cuentas ya están (`CierreDeEntradas`, `ResumenDeCajaEntradas.porCaja`,
`compradasPorFamilia`, `NumerosDeEntradas.ocupados`); falta enchufarlas.

1. **Cerrar la caja (9.1).** Botón **CERRAR CAJA** en la barra de VENDER, al lado de VENTAS. Se cuenta el efectivo
   **a ciegas** (ninguna plata de la caja a la vista hasta cerrar), y recién después se ve lo que tenía que haber
   (`CierreDeEntradas.de(caja, ventas, anulaciones).efectivoEsperado`) y la diferencia (`diferenciaEnPalabras`, de
   la barra). Guarda con `cerrarCaja` del repositorio, con `_frenaSinPermiso()` antes (el test de
   `solo_modo_jefe_test` espera hoy `{'_abrir', '_cobrar'}`: sumar la función nueva). Nota opcional, y `anotarCierre`
   después. **Una caja cerrada no se vuelve a cerrar ni se corrige.** Su papel en `entradas/pdf/` con su provider en
   `papeles_de_entradas.dart`. Sin el OK de una encargada: eso es de la barra. Modelo: `cerrar_caja_barra_screen.dart`.
2. **La pestaña ENTRADAS del cierre de caja (9.2).** `SectorEntradasDelCierre` hoy es un cartel adentro de
   `cierre_caja/widgets/sector_barra.dart`: pasa a un archivo propio (`cierre_caja/widgets/sector_entradas.dart`)
   con la forma de `SectorBarraDelCierre`: por fiesta (la misma elección, CAMBIAR DE FIESTA), una línea por caja
   (quién, cambio, efectivo, transferencia, mixtos, vendidas, descuentos a mano, anuladas, contó, diferencia, o
   "abierta"), los totales ("vendidas N (sueltas y de lugares) = $ total") y "Anulado después del cierre" si hay.
   Solo para mirar. Sin cajas: "Todavía no se abrió ninguna caja de entradas en esta fiesta."; sin precio: "Esta
   fiesta todavía no tiene precio de entrada: se pone en ENTRADAS → PRECIOS." El texto de hoy ("se venden a mano,
   fuera de la app") se va. **En la web no puede abrir la base** (`entradasEnEsteEquipoProvider`).
   `tool/cierre_sector_prueba.dart` tiene que mostrarlo; test `cierre_por_sector_test` (sin cajas, sin precio, dos).
3. **La entrega con lo vendido a la vista (9.3)**, en `RetiroEntradasScreen` y `entrega_entradas_dialog.dart`:
   la tarjeta "Al 50 %, aparte: 112" pasa a "Al 50 %: 40 vendidas de 112"; en cada familia "· 8 al 50 % (compró 3)";
   y en el cartel de la entrega, con `puedeVenderEntradasProvider`, el botón **VENDERLE ESAS ENTRADAS**, que abre
   `VenderEntradasScreen(evento:, familiaId:)` (**ya acepta `familiaId`**); sin el permiso, el texto de hoy más "Se
   las vende quien tiene la caja de entradas." **Y enchufar `NumerosDeEntradas.ocupados` como el `deOtros` de la
   entrega**, para que no deje repetir un número vendido. La planilla en papel no cambia.
4. **Pendiente chico del spec (7.3):** que las cinco tablas de entradas bajen con "Lista para trabajar sin internet"
   (para una tablet que se prepara en la oficina). No se hizo.

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
