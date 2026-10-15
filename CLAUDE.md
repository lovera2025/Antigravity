# Junior Eventos / Argüello Events

App Flutter de gestión operativa para eventos: presupuestos, finanzas, recepción
con check-in por QR y un tótem que se proyecta en el salón.

- Paquete: `arguello_events` · versión en `pubspec.yaml` (mantener en sync con
  `installer/junior_eventos_setup.iss`).
- Supabase: proyecto `bucnrydgojyzntgesxqb` (ArguelloApp). Credenciales en
  `lib/main.dart:29-34`.
- Web deployada en `https://arguello-events.vercel.app` (`kWebBaseUrl`).

## Antes de tocar nada: la rama

**El desarrollo va en `feature/v4.6-cierre-por-sesiones`, no en `main`.** Esa
rama está ~170 commits adelante y va por la v6.0.0; `main` quedó en la 2.2.0.
Ramificar de `main` significa trabajar sobre código de hace meses.

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
la versión 73) es la fuente de verdad del escritorio; los cambios se encolan en
`_sync_queue` y suben a Supabase cuando hay red. La web va directo a Supabase.

- Escritorio/móvil: `InvitadosRepository` (SQLite + cola de sync).
- Web sin usuario (la página del QR): `SupabaseInvitadosRepository`, que **no
  lee la tabla**: busca y anota por funciones de la nube (ver "La lista de la
  puerta, cerrada a los anónimos", abajo).

**Rutas por URL en web** (`lib/main.dart:80-130`): se detectan con `contains()`
sobre `Uri.base`, no con path parsing.

| URL | Pantalla | Login |
|---|---|---|
| `?cotizar` | Catálogo público | No |
| `?totem&evento=<id>&clave=<k>` | Tótem (el link, con la clave, sale de Personalizar tótem) | **No** (deliberado: se proyecta desde una smart TV) |
| `/lista?evento=<id>` | Lo que ve el invitado al escanear el QR: busca su nombre y entra con su DNI | No |
| `?buscar&evento=<id>` | La misma página que `/lista` | No |
| `/op?evento=<id>` | Ya no se usa: dice dónde se suman los celulares | No |

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

Se asignan desde Mi Empresa → pestaña OPERADORES (`finanzas_view.dart`, ~6500
líneas; el diálogo está en `_showPermissionsDialog`).

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

**El sorteo sobre el plano no toca el motor.** `SorteoMesasMotor` sigue igual; `SorteoConPlano` le arma las
entradas y traduce la salida.
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
- **El número de una mesa que se sacó y se guardó no se vuelve a dar** (`ArmadoSalon.ultimoNumero`): ya pudo salir
  impreso.

**En la pantalla del plano no se usa el SnackBar.** Lo que pasó se dice con `AvisoDelPlano`, al lado de los
botones del pie: el SnackBar los tapaba varios segundos después de cada cambio. Un error se dice en palabras, sin
el texto de la excepción.

**En papel:**
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
  **último**, con todas las PCs y la web en la 6.0.0: si no, el tótem viejo queda sin nadie en la lista.

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
- **En la web de un celular, `TextField` suelta el teclado al apoyar el dedo afuera y eso se come el toque.** El
  buscador de `PanelPuerta` lo suelta al levantarlo (`onTapUpOutside`, solo en la web).
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

**El plano en la llegada** (v6.0.0, sección 4). Cuando llega una familia de un masivo sorteado, la llegada va arriba
(a la izquierda en una tele horizontal) y abajo el salón con su mesa encendida y el camino desde el Ingreso.
- **Datos:** el armado viaja en la ficha (`FichaTotem.plano`). `armarFichaTotem` lo lee con `leerPlano`, y
  `TotemLocal` con `planoDelEventoProvider`.
- **Lo que decide**, sin pantalla:
  - `PlanoDeLaLlegada` arma la hoja, las mesas y **un solo ocupante, la familia**: uno por fila de la puerta da
    "conflicto";
  - `CaminoALaMesa` busca el paso (A* en una grilla de medio radio, sin pisar mesas con sus sillas, escenario,
    pasarela, barras, cajas ni baños), sale del sector "Ingreso" o de `armado.ingreso` y, sin paso, va recto.
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

  **La eximición se resuelve con `resolverExencion`:** la de un cobro anulado se va; la que vino de cobros la
  reemplaza la del último cobro; **la de un perdón (con ajuste de ficha, o que ningún cobro reproduce) no se toca**.
  `test/revision_mora_test.dart` cuida las tres cosas; `tool/simulacro_revision_mora_test.dart` muestra qué cambia
  con una copia de la base real.
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

**Los SQL de una versión se corren antes de instalarla**, con el OK del usuario
en el momento. Sin las tablas en la nube, lo que se cargue en las PCs queda
trabado en la cola. (La regla de "después de las 20 hs" la sacó el usuario el
13-oct-2026: lo que solo agrega se puede correr a cualquier hora.)
