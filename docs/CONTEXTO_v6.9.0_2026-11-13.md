# CONTEXTO — la 6.9.0: los arreglos de la noche y la venta de entradas

**Estado (13-nov-2026, noche):** en curso, **sin publicar**. Rama `feature/v4.6-cierre-por-sesiones`.

## Para retomar en otro chat

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

1. Terminar la Parte B, etapa 1 (los datos): ver "Parte B".
2. Etapa 2 (las cuentas).
3. **Frenar: la maqueta** de PRECIOS, VENDER, el comprobante, VENTAS, cerrar la caja y ENTRADAS del cierre, y su OK.
4. Etapas 3 a 6 del spec.
5. Probar de punta a punta, las capturas, y publicar con él (foto de la mora antes, el SQL, el instalador por pasos).

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

### Etapa 2, las cuentas — sigue esto

`lib/features/entradas/cuentas/`, puras y sin pantalla (sección 5 del spec): el precio de hoy, las de los lugares
adicionales (cuántas le quedan a cada familia), los números del talonario y el cierre de una caja.
