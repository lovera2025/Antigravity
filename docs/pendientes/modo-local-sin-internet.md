# Recepción y el tótem sin internet (modo local)

**Estado:** pendiente. **Va en la 6.0.0** (decisión del usuario del 2026-10-13).
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
| 5 · Apariencias | La apariencia y los textos ya viajan por el puente (`notifyConfigUpdated`) y se guardan (`TotemConfigCache`). **La foto del evento es `Image.network`:** sin internet cae al logo. Hay que guardarla en la PC. El plano y la guía de la llegada salen de lo que ya está en la PC, no de una consulta a la nube. |
| 6 · Recepción | Ya lee de la base de la PC. Lo nuevo (búsqueda, filtros, "Ingresar" por fila) también. |
| 7 · Kiosco | Es de la ventana: no usa la nube. |
| 8 · Tótems vinculados | "Transmitir en:" y la lista de tótems prendidos hoy están pensados por la nube. Se diseñan junto con este pendiente: el vínculo entre un puesto y un tótem tiene que andar por la nube **y** por la red del salón. |
| 9 · Cerrar la puerta | El check-in en el servidor es para la web. El escritorio sigue marcando en su base y subiendo después: cerrar los permisos no puede dejar a una PC sin poder marcar cuando no hay internet. |

## Cómo está hoy

| | Sin internet |
|---|---|
| Recepción en una PC, con la lista ya bajada | **Anda.** Marca en la base de la PC y encola; sube sola al volver (`InvitadosRepository.marcarIngreso`). |
| El tótem en la ventana de esa misma PC | **Anda.** Recibe el ingreso por el puente (`KioskLauncher.notifyGuestCheckin`) y saluda al instante. Desde la parte 4 no saluda de nuevo al volver internet. |
| El tótem, si se lo abre ya sin internet | Saluda, pero **la lista de los que ya llegaron arranca vacía**: la carga inicial lee Supabase (`totem_display.dart`, `_connect` y `_reconciliar`). |
| Dos PCs de Recepción | **No se ven.** Se coordinan solo por la nube (`_emitir` manda `checkin`, `guest_removed` y `list_reset` por el canal `totem_<eventoId>`, y `subscribeToChanges` escucha la tabla). Cada una marca por su lado y se juntan al volver. |
| Un tótem en otra PC | **No se entera** de nada hasta que vuelve internet. |
| El tótem en una tele por el navegador, `/lista`, `?buscar`, `/op` | **No andan.** La web se sirve desde internet y lee Supabase directo. |
| Celulares y tablets | **No andan.** Usan la web; la app de Android nunca se publicó. |
| Abrir el programa sin internet | La sesión se rehidrata del disco (`AuthWrapper._effectiveSession`, `main.dart:566`) y el rol está cacheado. **Falta probarlo** con la sesión vencida: quedó anotado en la Fase 0 del 24-sep y nunca se hizo. |

Un router sin internet hoy no cambia nada: las PCs no se hablan entre ellas por la red del salón.

## Qué habría que hacer

Va con su plan corto y su maqueta cuando le toque. Lo de abajo es el punto de partida, no el diseño cerrado.

### 1. Una PC, completa sin internet

- **Que el tótem abra con la lista aunque no haya internet.** Recepción ya tiene la lista en su base: al abrir o
  reanudar el tótem se la pasa por el puente (un mensaje nuevo, al lado de `guest_checkin`). El tótem la toma como
  primera lectura, en silencio (`IngresosTotem.leyo`).
- **La foto del evento, guardada en la PC** la primera vez que se ve con internet.
- **Probar abrir el programa sin internet con la sesión vencida**, y arreglar lo que aparezca. Si no deja entrar, no
  sirve nada de lo demás.

### 2. Saber que está lista para trabajar sin internet

Hoy no hay forma de saber, antes de la fiesta, si esa PC tiene todo. En Recepción, a la vista:
- cuántas personas tiene la lista de esa fiesta en esta PC y a qué hora se puso al día;
- cuántos ingresos hay sin subir, cuando no hay internet;
- en palabras: "Lista para trabajar sin internet", o qué le falta.

Sale de lo que ya existe: la lista en la base de la PC y la cola de subida.

### 3. Dos puestos por la red del salón

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

- **Celulares y tablets no entran al modo local.** Usan la web, que se sirve desde internet. Sin internet, los
  puestos son PCs o notebooks con el programa instalado.
- **El tótem en una tele por el navegador tampoco.** La tele va como pantalla de una PC, por HDMI.
- **Cargar o cambiar la lista necesita internet** para que llegue a la otra PC: sortear, importar el Excel, pasar a
  la lista de la puerta. Eso se hace antes, y es lo que el usuario ya da por sentado.

### 5. Cómo se prueba

- Las reglas (qué hace una PC con un aviso que llega, repetido, tarde o en otro orden), con tests, como
  `IngresosTotem`.
- El ida y vuelta por la red, con dos extremos en la misma PC.
- **Con dos PCs de verdad no hay otra forma que el ensayo:** las dos en el router, se saca el cable de internet, se
  marca en una y se mira la otra y el tótem. Se vuelve a enchufar y se mira que la nube quede igual que las PCs.

## Para preguntarle cuando llegue su turno

- Cuántos puestos va a haber en la puerta y con qué (notebooks, o contaba con celulares).
- En cuál va enchufado el tótem, y si va a haber más de uno.
- Si en el salón hay un router propio o se usa el wifi del lugar.

**No volver a preguntarle si lo quiere:** ya lo pidió dos veces. Se le recomendó además llevar internet de respaldo
(un router 4G o el celular compartiendo datos); no lo descartó, pero lo que pidió es que ande sin internet.
