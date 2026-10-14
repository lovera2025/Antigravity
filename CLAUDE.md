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
- Web: `SupabaseInvitadosRepository` (Supabase directo).
- No comparten interfaz: en `totem_checkin_screen.dart` se elige por `kIsWeb`
  con un cast `as dynamic`.

**Rutas por URL en web** (`lib/main.dart:80-130`): se detectan con `contains()`
sobre `Uri.base`, no con path parsing.

| URL | Pantalla | Login |
|---|---|---|
| `?cotizar` | Catálogo público | No |
| `?totem&evento=<id>` | Tótem | **No** (deliberado: se proyecta desde una smart TV) |
| `?lista&evento=<id>` | Lo que ve el invitado al escanear el QR | No |
| `?buscar&evento=<id>` | Self check-in por DNI | No |
| `/op?evento=<id>` | Operador con PIN | No |

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
- **Falta cerrar la RLS de `invitados`**, y va en la misma 6.0.0
  ([docs/pendientes/rls-invitados.md](docs/pendientes/rls-invitados.md)): hoy cualquiera con la clave pública lee y
  cambia esa tabla. Además, **las pantallas `/lista` y `?buscar` marcan el ingreso sin pedir nada a quien no tiene
  DNI, y los alumnos no lo tienen**: con el QR a la vista, cualquiera puede marcar a otro. Se cierra con el tótem
  nuevo (sin QR en masivos) y con el check-in en el servidor.

**Recepción y el tótem nuevos van en la 6.0.0**, por partes (decisión del 13-oct-2026; antes eran "para diciembre").
Están diseñados y aprobados con maquetas: son los seis pendientes de "Tótem y Recepción" en
`docs/pendientes/PENDIENTES.md`. El orden está en `docs/CONTEXTO_v6.0.0_2026-10-11.md`.

**El retiro de entradas** (v72, `retiro_entradas_screen.dart`) es otra cosa: la entrega de entradas y pulseras en la
oficina, antes de la fiesta. Se guarda en `entradas_retiro` y no toca `invitados`.

**Escondido, el tótem se pausa.** `KioskLauncher.close()` manda `pausar` antes de esconder la ventana: suelta
streams, canal y relectura. `launch`/`focus` mandan `reanudar`. Todo lo que se agregue al tótem y hable con la
nube tiene que cortarse en `_pausar()`.

Las pantallas web y el tótem leen hasta 1000 invitados por evento (el "Max rows" de PostgREST). Ver
`docs/pendientes/invitados-mas-de-1000-en-web.md`.

Hay **dos implementaciones casi idénticas** que no comparten código (~800 líneas
duplicadas). Cualquier cambio visual hay que hacerlo dos veces:

- `totem_display.dart` — la pantalla del salón. Va por Supabase directo. Es la
  que se usa en la ventana secundaria, en `?totem` y en la ruta
  `/totem_display`.
- `totem_panel.dart` — panel embebido en Recepción. Va por SQLite.

El tótem **muestra** un QR, no lo lee: no hay dependencia de cámara. El QR apunta
a `/lista?evento=<id>`, que abre el invitado en su celular. Al confirmar el
check-in, esa pantalla emite un broadcast por el canal `totem_<eventoId>`, que es
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
  El sorteo de la v5.0.0 decide así (`pago_para_sorteo.dart`).
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
migraciones), `plano_evento_cuerpo.dart` (~2200), `totem_display.dart` (~2200),
`totem_panel.dart` (~1500). Leer por tramos, no enteros.

## SQL

Las migraciones se versionan en `supabase/` y se corren a mano en el SQL Editor.
No hay CLI de Supabase configurado. Convención: cada sentencia riesgosa lleva su
`ROLLBACK` escrito arriba, comentado, y el archivo termina con las consultas de
verificación: los conteos de antes y después, que tienen que dar igual.

**Los SQL de una versión se corren antes de instalarla**, con el OK del usuario
en el momento. Sin las tablas en la nube, lo que se cargue en las PCs queda
trabado en la cola. (La regla de "después de las 20 hs" la sacó el usuario el
13-oct-2026: lo que solo agrega se puede correr a cualquier hora.)
