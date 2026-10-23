# Recepción y el tótem sin internet (modo local)

**El 23-oct, el primer ensayo sin internet encontró la página del celular en blanco**: Flutter web bajaba la letra
Roboto de Google antes de dibujar. Arreglado en la 6.2.1 (la app trae su Roboto; ver
`docs/CONTEXTO_v6.2.1_2026-10-23.md`), sin publicar. Falta repetir el ensayo con la 6.2.1 instalada.

**Estado:** hecho y probado con su celular (15-oct); falta solo el ensayo con el router de verdad. **Va en la 6.0.0**
(decisión del usuario del 2026-10-13). **Los pasos 1 y 2 están hechos** (14-oct, sección 5). **El 3 se hizo de otra
forma** (15-oct, sección 7): los puestos van a ser celulares (o tablets), así que **una notebook del salón hace de
central** y los celulares le hablan por el wifi del router; ver "La sección 7" en
`docs/CONTEXTO_v6.0.0_2026-10-11.md`. Lo del 4 se le dijo en el plan.
**Postergado el:** 2026-09-24

## Qué pidió el usuario

El 24-sep, al simplificar Recepción y el tótem:
- "que se carguen todos los alumnos con internet primero y después se pueda manejar sin internet";
- "quizás con un router alcanzará para modo local", y que los dos recepcionistas no se pisen.

El 13-oct preguntó si había quedado así, y al saber que a medias lo pidió de nuevo: "debe seguir la recepción y el
tótem aun si no hay internet... obviamente con los datos cargados previamente, eso sí con internet. Una vez que se
tengan los datos, que pueda operar aun sin internet". Tiene que quedar **listo para las dos cosas**: con internet y,
sobre todo, en modo local por si no hay.

## Por qué se postergó

El 24-sep se priorizó el sorteo de noviembre y este punto quedó sin escribir: lo nombraba una sola línea de
[totems-vinculados.md](totems-vinculados.md) ("el modo local con router es otro pendiente"). Por eso no entró en el
camino de la 6.0.0 que se armó el 13-oct. No se había descartado: se había perdido.

## La regla, que vale desde ya

**Con los datos ya bajados, Recepción y el tótem tienen que seguir andando sin internet.** Nada de lo que se
agregue puede necesitar la nube en el momento de marcar un ingreso o de saludar: lo que el tótem muestra llega por
el puente entre ventanas o está guardado en la PC.

Cómo le pega a cada parte que falta:

| Parte | Qué tiene que cuidar |
|---|---|
| 5 · Apariencias | La apariencia y los textos ya viajan por el puente (`notifyConfigUpdated`) y se guardan (`TotemConfigCache`). **La foto del evento queda guardada en la PC** (`FotoGuardada`, hecho el 14-oct). El plano y la guía de la llegada salen de lo que ya está en la PC, no de una consulta a la nube. |
| 6 · Recepción | Ya lee de la base de la PC. Lo nuevo (búsqueda, filtros, "Ingresar" por fila) también. |
| 7 · Kiosco | Es de la ventana: no usa la nube. |
| 8 · Tótems vinculados | "Transmitir en:" y la lista de tótems prendidos hoy están pensados por la nube. Se diseñan junto con este pendiente: el vínculo entre un puesto y un tótem tiene que andar por la nube **y** por la red del salón. |
| 9 · Cerrar la puerta | El check-in en el servidor es para la web. El escritorio sigue marcando en su base y subiendo después: cerrar los permisos no puede dejar a una PC sin poder marcar cuando no hay internet. **Programado el 15-oct (sección 8):** Recepción y la central no cambiaron; el tótem lee la nube por `totem_lista` con su clave, y sin internet o sin clave sigue con lo de la PC, como en la sección 5. La clave queda guardada en la PC. |

## Cómo está hoy

| | Sin internet |
|---|---|
| Recepción en una PC, con la lista ya bajada | **Anda.** Marca en la base de la PC y encola; sube sola al volver (`InvitadosRepository.marcarIngreso`). |
| El tótem en la ventana de esa misma PC | **Anda.** Recibe el ingreso por el puente (`KioskLauncher.notifyGuestCheckin`) y saluda al instante. Desde la parte 4 no saluda de nuevo al volver internet. |
| El tótem, si se lo abre ya sin internet | **Anda** (14-oct): si no puede leer la nube, le pide a la PC quién ya entró (`lista_totem`, `IngresosTotem.leyoDeLaPc`). Antes la lista arrancaba vacía. |
| Dos PCs de Recepción | **No se ven.** Se coordinan solo por la nube (`_emitir` manda `checkin`, `guest_removed` y `list_reset` por el canal `totem_<eventoId>`, y `subscribeToChanges` escucha la tabla). Cada una marca por su lado y se juntan al volver. |
| Un tótem en otra PC | **No se entera** de nada hasta que vuelve internet. |
| El tótem en una tele por el navegador, `/lista`, `?buscar`, `/op` | **No andan.** La web se sirve desde internet y lee Supabase directo. |
| Celulares y tablets | **No andan.** Usan la web; la app de Android nunca se publicó. |
| Abrir el programa sin internet | **Anda, con la sesión vencida** (comprobado el 14-oct con la librería de Supabase y la red cortada, `test/sesion_sin_internet_test.dart`; la decisión está en `sesionParaEntrar`). Con un router sin salida a internet tardaba 12 s en "Verificando permisos...": ahora 3 s si la PC recuerda el rol. Falta verlo en el ensayo. |

Un router sin internet hoy no cambia nada: las PCs no se hablan entre ellas por la red del salón.

## Qué habría que hacer

Va con su plan corto y su maqueta cuando le toque. Lo de abajo es el punto de partida, no el diseño cerrado.

### 1. Una PC, completa sin internet — **hecho el 14-oct** (5a, 5b y 5c)

- **Que el tótem abra con la lista aunque no haya internet.** Recepción ya tiene la lista en su base: al abrir o
  reanudar el tótem se la pasa por el puente (un mensaje nuevo, al lado de `guest_checkin`). El tótem la toma como
  primera lectura, en silencio (`IngresosTotem.leyo`).
- **La foto del evento, guardada en la PC** la primera vez que se ve con internet.
- **Probar abrir el programa sin internet con la sesión vencida**, y arreglar lo que aparezca. Si no deja entrar, no
  sirve nada de lo demás.

### 2. Saber que está lista para trabajar sin internet — **hecho el 14-oct** (5d, la línea debajo del progreso)

Hoy no hay forma de saber, antes de la fiesta, si esa PC tiene todo. En Recepción, a la vista:
- cuántas personas tiene la lista de esa fiesta en esta PC y a qué hora se puso al día;
- cuántos ingresos hay sin subir, cuando no hay internet;
- en palabras: "Lista para trabajar sin internet", o qué le falta.

Sale de lo que ya existe: la lista en la base de la PC y la cola de subida.

### 3. Dos puestos por la red del salón — **hecho de otra forma el 15-oct** (sección 7)

**Lo que se hizo:** el usuario contestó que los puestos van a ser casi seguro celulares y que llevan router propio.
Los celulares no pueden avisarse entre ellos (la web se baja de internet), así que una notebook del salón hace de
**central** (`CentralPuerta`): sirve la página del celular y marca en su base todo lo que le piden. Hay una sola
lista, así que no se pisan; lo marcado sin conexión queda en el celular y se manda al volver. El cortafuegos lo deja
abierto el instalador, y el código de cuatro cifras del QR cumple lo de "un aviso no puede venir de cualquiera".

Lo de abajo es lo que estaba pensado antes, para PCs: queda como registro.

La idea más simple, y la que se recomienda: **los mismos avisos que hoy viajan por la nube, también por la red
local.** Son tres (`checkin`, `guest_removed`, `list_reset`) y ya tienen un solo lugar de salida (`_emitir`, en
`invitados_repository.dart`).

- Cada PC sigue marcando en su base y encolando, como hoy. La red local solo agrega el aviso a las otras.
- La PC que recibe un aviso lo guarda en su base, lo encola también (es un estado: subirlo dos veces no rompe nada)
  y se lo pasa a su tótem por el puente.
- **Que no se pisen:** al buscar a alguien que ya entró por la otra puerta, "Ya ingresó a las 22:41", como está
  diseñado en [totems-vinculados.md](totems-vinculados.md).
- Un aviso por la red se puede perder: cada tanto las PCs se cuentan lo que tienen y se ponen al día. Cuando vuelve
  internet, la nube empareja todo como hoy.

A decidir en su plan:
- **Cómo viaja.** Lo más simple es avisar a toda la red (sin una PC "central" ni direcciones que configurar). La
  alternativa es que una PC haga de central y las otras se conecten a ella.
- **El cortafuegos de Windows.** Para recibir por la red hace falta una regla. La puede dejar puesta el instalador
  (`installer/junior_eventos_setup.iss`); si no, Windows pregunta la primera vez y hay que decir que sí.
- **Quién más está en esa red.** Si el wifi del salón lo usan los invitados, un aviso no puede venir de cualquiera:
  van firmados con una clave que se baja con los datos de la fiesta.

### 4. Lo que queda afuera, y hay que decírselo

- ~~Celulares y tablets no entran al modo local~~ (así estaba pensado el 13-oct). **Desde la sección 7 sí, por la
  notebook central**: sin ninguna PC en el salón y sin internet, no. Una segunda notebook entra igual que un celular,
  por el navegador.
- **El tótem en una tele por el navegador tampoco.** La tele va como pantalla de una PC, por HDMI.
- **Cargar o cambiar la lista necesita internet** para que llegue a la otra PC: sortear, importar el Excel, pasar a
  la lista de la puerta. Eso se hace antes, y es lo que el usuario ya da por sentado.

### 5. Cómo se prueba

- Las reglas (qué hace una PC con un aviso que llega, repetido, tarde o en otro orden), con tests, como
  `IngresosTotem`.
- El ida y vuelta por la red, con dos extremos en la misma PC.
- **Con dos PCs de verdad no hay otra forma que el ensayo:** las dos en el router, se saca el cable de internet, se
  marca en una y se mira la otra y el tótem. Se vuelve a enchufar y se mira que la nube quede igual que las PCs.

## Lo que se le preguntó (14-oct), y contestó

- Cuántos puestos y con qué: "no se sabe, más de dos podría ser; pueden ser unas PCs pero más probable es Android o
  celulares".
- Dónde va el tótem: "todavía no sé". Se recomienda la notebook central, con la tele por HDMI.
- Router: "llevamos router propio por las dudas, aunque seguramente habrá wifi en ese salón; aunque sea sin
  internet, para que nos conectemos".

**No volver a preguntarle si lo quiere:** ya lo pidió dos veces. Se le recomendó además llevar internet de respaldo
(un router 4G o el celular compartiendo datos); no lo descartó, pero lo que pidió es que ande sin internet.
