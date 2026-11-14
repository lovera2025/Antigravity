# CONTEXTO — la 6.9.0: los arreglos de la noche y la venta de entradas

**Estado (13-nov-2026, noche):** en curso, **sin publicar**. Rama `feature/v4.6-cierre-por-sesiones`.

## Para retomar en otro chat

**Dónde quedó (14-nov):** la Parte A entera y **las etapas 1, 2 y 3 de la Parte B** están **guardadas en la rama**
(**sin subir a GitHub**: se guardan en esta PC hasta que el usuario diga). **El usuario aprobó la maqueta el 14-nov
("Sí, seguí")**: las pantallas se programan como están ahí. **Sigue la etapa 4 (la caja, VENDER y el comprobante).** El 14-nov, al retomar después de una compactación, se comprobó primero que nada había quedado a
medias (el repositorio igual al último commit y la suite entera en verde, 4.803) y recién después se escribió la etapa
2. **Con la etapa 3, la suite entera pasa: 4.883 pruebas, 284 archivos, 8 tandas**, y el análisis de lo nuevo no da
errores.

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
4. ~~Etapa 3 (el permiso y PRECIOS)~~: hecha el 14-nov. **Etapas 4 a 6 del spec: seguir por la 4.**
5. Probar de punta a punta, las capturas, y publicar con él (foto de la mora antes, el SQL, el instalador por pasos).

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
