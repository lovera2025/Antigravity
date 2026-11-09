# La puerta ve el plano, sillas sueltas, chat y "dónde van las mesas lejos" (6.5.0)

## Contexto

Con la 6.4.0 publicada (falta instalarla en las tres PCs), el usuario trajo cinco temas de la primera noche con
el tótem en la tele horizontal (foto del 9-nov, 12:21):

1. **El tótem en horizontal.** Resuelto sin código: el salón ya ocupa todo el alto, y lo de la espera queda a la
   izquierda porque ese plano **no tiene pista** (`CuadroDelSalon.para`: sin pista ni hueco, franja forzada al
   costado). Con una pista en el armado, la espera va adentro de la pista y el salón se lleva la pantalla. El usuario
   lo entendió y lo deja así. Único consejo: la foto no está en KIOSCO (barra de título y de tareas a la vista, un
   15 % del alto); con KIOSCO el salón se agranda.
2. **La recepcionista ve el plano y repite la llegada en su pantalla**, PC o celular, sin tocar la tele: al tocar
   una familia, el salón con su mesa encendida y el camino; y, si quiere, VER LA LLEGADA (la animación entera). Y el
   plano entero con los apellidos, para orientar.
3. **Sillas sueltas**: las que no van a una mesa (la familia ya está en el tope, o quiere una al lado o en un lugar
   "x"). La barra las vende como otro producto con su vale, y la puerta las anota con **un botón al lado de SUMAR
   SILLA**, sin tope.
4. **Chat entre los puestos de la puerta** (la PC y los celulares), por la central del salón: le salta a cada uno
   "Juli te habla".
5. **Las adicionales de más van lejos, y el jefe elige dónde**: en el sorteo, una familia con más de 3 mesas
   (principal + 2 adicionales se tolera) viene avisada y tildada: las de más van lejos, "bien lejos" o a una zona
   que el jefe marca **tocando mesas en el plano**. También para la mesa que se compra después del sorteo (hoy va
   pegada al tramo).

Todo sale junto en la **6.5.0**, sin SQL (nada nuevo en la nube: ver cada etapa), y se publica solo cuando él lo
diga. Las pruebas de punta a punta las hago yo en el sandbox (`tool/*_prueba.dart`, en memoria), nunca contra la
base real ni Supabase.

## Lo que no se toca

- `CuadroDelSalon` y la escena del tótem: la tele está bien.
- `contratos_alumnos`, `sillas_puerta` (ni una columna), `sorteos_mesas.tipo`, el motor de sync.
- El tótem del salón no se entera de nada de lo que la recepcionista mire en su pantalla.

---

## Etapa 0 · El modal de cobro se cierra apenas se guarda el pago

**Lo que pasa** (lo contó el usuario el 9-nov: a veces CONFIRMAR PAGO deja el modal abierto con el pago ya hecho, y
tiene que cancelar). En `detalle_evento_masivo_screen.dart:8021-8067`, después de `registrarPagosLote` (la
transacción: desde ahí el cobro existe) vienen, **antes del `Navigator.pop`**, cuatro pasos esperados:
`afterMassiveMutation` (sube a la nube: red), `getContratoById`, y cinco `prefsMedio.set…`. Si uno falla, cae en el
mismo `catch` que el guardado (línea 8124): "No se pudo guardar el cobro. Reintentá", modal abierto y el pago
guardado; reintentar lo cobraría dos veces. Sin falla, con internet lento el modal queda en GUARDANDO hasta que la
nube conteste. El error va solo a `debugPrint`: no queda en ningún archivo.

**El cambio**, todo en ese handler:
- Apenas vuelve `registrarPagosLote`: `Navigator.pop(context, true)` (si `context.mounted`). Lo que sigue usa el
  `context` y el `ref` de la pantalla, no los del modal.
- Después, cada uno en su propio `try`, sin que ninguno pueda frenar al siguiente ni mostrar "no se pudo guardar":
  la subida (`afterMassiveMutation`), la relectura (`fresco`), las preferencias, `_patchAlumnoLocal`, el PDF y el
  `bump`. Si falla la subida, lo dice el aviso de siempre de la cola (sube en la próxima vuelta: "Lo trabado se
  reintenta todo junto"); si falla el PDF, el aviso "No salió el recibo: reimprimilo desde la ficha".
- **Lo que falle después de guardar queda escrito** en `Documentos\Junior Eventos\cobros_despues_de_guardar.txt`
  (fecha, alumno, paso, error), como `revision_mora.txt`: la próxima vez se sabe cuál de los cuatro fue.
- El `catch` del guardado queda solo para `registrarPagosLote` y lo anterior (ahí sí "Reintentá" es verdad: la
  transacción no escribió nada).

**Test:** `test/cobro_cierra_al_guardar_test.dart` lee el handler (como `solo_modo_jefe_test` lee pantallas) y falla si
entre `registrarPagosLote` y `Navigator.pop` vuelve a aparecer un `await`. La lógica de "qué se hace después" sale a
`eventos/services/despues_de_guardar_cobro.dart` con su test: cada paso corre aunque el anterior falle, y lo que
falla se anota.

## Etapa 1 · Ver en el plano y la llegada, desde la puerta (PC y celular)

**Acceso.** En cada tarjeta de familia de `PanelPuerta` (masivo sorteado, familia con mesa), un botón **VER EN EL
PLANO** al lado de SUMAR SILLA (`_sillas` → `_botonSumar`, `lib/features/recepcion/widgets/panel_puerta.dart:707`).
En el menú MÁS (`_menuMas`, línea 342), "Ver el plano entero". Lo mismo en la PC y en el celular: el panel es uno.

**Qué decide, sin pantalla** — `lib/features/recepcion/services/plano_de_la_puerta.dart` (nuevo):
- `PlanoDeLaPuerta.deLaFamilia(armado, grupo)` → `PlanoDeLaLlegada.para(armado, mesa: titular.mesa, nombre:)` (ya
  existe, `totem/services/plano_de_la_llegada.dart`): la hoja, las mesas encendidas, el camino.
- `PlanoDeLaPuerta.entero(armado, puerta)` → `EstadoPlano.desde(armado, ocupantes: [...])` con un `OcupantePlano`
  por `GrupoPuerta` con mesa (nombre, números de `MesasExtraUtils.numerosMesaDesdeTexto`, división). Marca quiénes
  ya entraron (`ingresados: Set<int>` de mesas) para pintarlas distinto.
- Test puro: `test/plano_de_la_puerta_test.dart`.

**Las hojas** — `lib/features/recepcion/widgets/hoja_plano_familia.dart` (nuevo):
- `HojaPlanoFamilia`: pantalla completa (diálogo en la PC, página en el celular). Arriba "GÓMEZ, ANA · Mesa 12 y 13
  · 5° A"; el salón con `PanelPlano` (`totem/estilos/escena_totem.dart:1074`, el mismo panel de la tele, con
  `temaPlanoDelTotem(estilo, color)`; `animar: false`, `progresoCamino: 1`, `pulsar: true`). Botones: **VER LA
  LLEGADA** y CERRAR.
- `ReproducirLlegada`: `EscenaTotem` con `llegada: ContenidoBienvenida.armar(...)`, `plano`, `empezo: ahora`,
  alimentada por un `ReproductorBienvenidas` propio al que se le da solo esa familia (`leyo` con el titular
  ingresado, `familiaDe` de la `FichaTotem`). Al terminar (`fin`), vuelve a la hoja. Sin `TotemLocal`: no escucha la
  base ni la lista. **En la PC** la ficha sale de `FichaTotem.desdePuerta(eventoId, puerta, plano:)` y la config de
  `totemConfigDeLaNocheProvider`. **En el celular** no hay base: la central manda el armado y la config (abajo), y la
  escena va **sin foto ni fondo propio** (`TotemConfig` con `fotoUrl`/`fondoUrl` en null: "Tu fondo" sin imagen cae
  en `EscenaTotem.respaldo`, como ya está previsto).
- `HojaPlanoEntero`: `VistaPlano` (`plano/widgets/vista_plano.dart`, con zoom y arrastre, ya usada por el plano del
  jefe) con el `EstadoPlano` de `PlanoDeLaPuerta.entero`; tocar una mesa abre `HojaPlanoFamilia` de esa familia.
  Las familias que ya entraron, en verde suave; las que faltan, como el papel.

**El celular necesita el armado** — `central_puerta.dart` manda `{'t': 'plano', 'v': n, 'armado': <json>, 'cfg':
<toJson>}` al conectarse (después de la lista) y cuando cambia (`CentralDeLaPuerta` escucha
`planoDelEventoProvider(eventoId)` y `totemConfigDeLaNocheProvider`, con `ref.container.listen` como la lista).
`ClienteCentral` lo guarda (`plano`, `cfg`); `PantallaPuesto` lo pasa por un provider como `puertaDelCelularProvider`.
`PanelPuerta` lee el armado por **un provider único** (`armadoDeLaPuertaProvider`: en la PC `planoDelEventoProvider`,
en el celular el del cliente) y, sin armado, no muestra el botón. Mensaje aparte de la lista, que se manda muchas
veces por noche: el armado pesa.

**Quién está saludando la tele.** Con el filtro ADENTRO la lista va **por hora, el último arriba**
(`PuertaDelEvento.buscar` con `filtro: adentro`): eso es lo que está saludando la tele. Hoy va por nombre.

**Tests:** `test/plano_de_la_puerta_test.dart`; en `test/panel_puerta_test.dart` (con `PuertaEnMemoria`), el botón
aparece solo con armado y mesa, abre la hoja con la mesa de la familia resaltada y el camino, VER LA LLEGADA monta
`EscenaTotem` con esa llegada; `test/central_puerta_test.dart`: el mensaje `plano` llega al conectarse y al cambiar.
Muestra PNG de las dos hojas (PC y celular) en `tool/puerta_plano_muestra_test.dart`, y las miro antes de mandarlas.

## Etapa 2 · Sillas sueltas

**La regla.** Una silla suelta no va a una mesa: no cuenta para el tope de 2 extra por mesa, no entra en
`SillasDeUnaMesa`, y una familia la puede comprar aunque esté en el tope o no tenga lugar al lado. Sigue siendo de
una familia de alumnos (queda quién la compró) y se paga en la barra con su vale.

**Sin SQL: `sillas_puerta.mesa = 0` quiere decir suelta.** Ninguna mesa de un armado lleva el 0
(`ArmadoSalon` lo toma por inválido, `armado_salon.dart:442`). `SillaPuerta.esSuelta => mesa == 0`. Una PC vieja que
baje una fila con `mesa 0` la mostraría "fuera de sus mesas: revisar" (no rompe nada); las tres se actualizan juntas.

**Barra** (`lib/features/barra/cuentas/silla_de_la_puerta.dart`):
- `esSillaSuelta(nombre)`: tiene "silla" y "suelta". `esSillaDeLaPuerta` sigue valiendo para las dos (las dos
  salen **una por vale**, `Vale.deUnaSilla`, `elegir_vales.dart`), y `Vale.esDeSillaSuelta` para el pie del papel.
- `impresion/modelo_ticket.dart:174`: el pie de una suelta dice "Silla suelta · no va a la mesa" arriba de "Llevá
  este vale a la recepcionista".
- `cuentas/cierre_de_barra.dart`: `sillas` (de mesa) y `sillasSueltas` aparte, en el papel, la pantalla, el PDF y el
  cierre por sector ("Silla extra: N · Silla suelta: M").
- El producto lo crea el jefe en CATÁLOGO con el nombre "Silla suelta", como "Silla extra" hoy. `FotoDeLaBarra.para`
  le da la misma foto que a la silla.

**Puerta:**
- `DatosSilla.suelta` (clave `suelta` en el JSON; una central vieja la ignora, pero celular y central son siempre la
  misma versión: la página la sirve la central).
- `decidirSilla` (`central/pedidos_de_la_puerta.dart:271`): con `suelta`, no pide mesa ni lugar; sí pide el vale,
  que no esté anulado ni usado, y que la familia sea de un alumno. `DecisionSilla.mesa = 0`. Aviso: "Silla suelta
  anotada para GÓMEZ, ANA." (`textoSillaHecha`).
- `SillasDeLaFamilia._armar` (`services/sillas_de_la_puerta.dart:160`): las de `mesa 0` van a `sueltas` (cantidad),
  no a `fueraDeSusMesas`. `ConteoDeLaNoche`: "4 sillas sumadas (1 suelta) · vales …". `textoSillaSumada`: "+1 silla
  suelta · vale 2-17 · Pato 23:05".
- `PanelPuerta`: botón **SILLA SUELTA** al lado de SUMAR SILLA (`_botonSumar`), siempre habilitado para una familia
  de alumno; abre `HojaSumarSilla` en modo suelta (sin "¿A qué mesa?", con "No va a una mesa: se sienta al lado o
  donde haya lugar"). La línea "Sueltas esta noche: 2". El tooltip del tope dice "…sillas sueltas, con el botón de
  al lado". Las quitadas, como hoy (`HojaQuitarSilla`).
- `PuertaDeEstaPc.sumarSilla(mesa: 0)` y `ResolvedorDePedidos` sin cambios de forma; `AccionesPuerta.sumarSilla`
  recibe `DatosSilla(suelta: true)`.
- `test/sillas_puerta_no_toca_test.dart` sigue: una suelta tampoco toca el contrato.

**Tests:** `test/sillas_sueltas_test.dart` (decidirSilla con tope lleno, vale repetido, vale anulado; `_armar`;
conteo; vales de la barra y el cierre); `test/panel_puerta_test.dart`: el botón y la hoja en modo suelta, en PC y
celular (por la central en memoria). Un test afirma que ningún armado de `ArmarAMedida` numera una mesa 0.

## Etapa 3 · Chat entre los puestos de la puerta

**Dónde vive.** `lib/features/recepcion/chat/` (nuevo). Solo en la memoria de la central, como `MarcasDeLaNoche`:
si la notebook se reinicia, el chat se vacía. Sin tabla, sin nube: anda sin internet, por el wifi del salón.

**A quién le hablo (pedido del usuario, 9-nov).** El chat no es una sola sala: al abrirlo se elige **a quién**, una
recepcionista (la PC o un celular, por su nombre) o **Todos**. Cada conversación es aparte, con su número sin leer; la
lista de puestos sale de la central (`CentralPuerta.puestos`, los conectados primero), y la PC figura con el nombre de
quien la opera.

- `MensajeDePuesto {id, de, para, texto, hora}` con `toJson`/`fromJson` (texto hasta 300 letras). `para` null es
  Todos; si no, el nombre del puesto. Cada puesto ve los de Todos, los que le mandaron y los que mandó.
- `ChatDeLaNoche`: la lista de la central (tope 200), `agregar`, `paraElPuesto(nombre)`.
- `ChatDelPuesto` (`ChangeNotifier`): lo que ve cada puesto, PC o celular: `conversaciones` (Todos y una por puesto,
  con `sinLeer` cada una), `mandar(texto, para:)`, `leida(para)`. En la PC lo arma `CentralDeLaPuerta` (su nombre,
  `quienOperaEnEstaPc`); en el celular, `ClienteCentral`.
- Por la red: celular → central `{'t': 'chat', 'id', 'para', 'texto'}` (`CentralPuerta._mensaje`,
  `central_puerta.dart:339`); la central lo guarda y se lo manda **solo a quien le toca** (`{'t': 'chat', 'm': {...}}`
  a todos si es para Todos; al destinatario y al que lo mandó si es para uno); al conectarse,
  `{'t': 'chat', 'todos': [...]}` con lo que le toca a ese puesto, después de la lista. El `id` lo pone quien manda:
  si llega dos veces, es el mismo. La lista de puestos ya viaja (`PuestoConectado`); el celular la recibe en un
  mensaje `{'t': 'puestos', ...}` para armar la lista de a quién hablarle.

**Camino, clic por clic.** En la PC: Recepción → arriba a la derecha, CHAT (al lado de CELULARES), con un número
rojo si hay mensajes sin leer. En el celular: arriba, al lado del reloj de los segundos. Tocarlo abre **la lista de
a quién hablarle**: Todos, y cada recepcionista con un punto verde si está conectada y su número sin leer; tocar una
abre esa conversación, se escribe y ENVIAR; atrás vuelve a la lista. Cuando llega un mensaje y esa conversación no
está abierta: una línea arriba de la lista de la puerta ("**Juli, a vos:** ¿alguien vio a GÓMEZ?" o "**Juli, a
todos:** …"), el número en el botón, sonido en la PC y **vibración en el celular Android** (`navigator.vibrate`, por
`dart:js_interop`; en iPhone no hay, queda la línea). Tocar la línea abre esa conversación.

**Pantalla.** `BotonChat` con el número sin leer, en el `AppBar` de Recepción (PC, solo con la central prendida:
`centralDeLaPuertaProvider`) y en la cabeza del celular (`PantallaPuesto._cabeza`). Abre `HojaChat`: la lista de
conversaciones y, adentro de una, los mensajes (los propios a la derecha, con quién y la hora), el campo y ENVIAR.
Se adapta sola: en la PC, lista a la izquierda y conversación a la derecha; en el celular, una pantalla y la otra.
**El aviso** sale igual que `_lineaAviso`, 6 s, con `SystemSound.play(SystemSoundType.alert)` en la PC (el de
"pagó: ya podés entregar"; en la web del celular el sonido depende del navegador, por eso la vibración).

**Tests:** `test/chat_de_la_noche_test.dart` (central y dos clientes en memoria, como `central_puerta_test.dart`:
un mensaje a Todos llega a todos; uno a Juli llega a Juli y a quien lo mandó, y Pato no lo ve; el que llega dos veces
es uno; el que se conecta tarde recibe lo suyo; el contador sin leer baja al abrir esa conversación y no otra).
Widget: la hoja con la lista, una conversación y el aviso, con `PuertaEnMemoria`.

## Etapa 4 · Dónde van las mesas lejos (y la que se compra después)

**El cartel avisa solo (pedido del usuario, 9-nov).** Principal + 2 adicionales juntas se tolera; de ahí en más, las
de más van lejos. En el diálogo del sorteo (`eventos/widgets/sorteo_mesas_dialog.dart`, `_FilaMesasExtra`, línea
946) una familia con **más de 3 mesas** viene **ya tildada** con `separadas = mesas − 3` y una línea en ámbar:
"GÓMEZ: 5 mesas · la principal y 2 adicionales juntas, las otras 2 lejos". Arriba de la sección, el resumen: "3
familias con más de 3 mesas: las de más van lejos". El jefe puede destildarla o cambiar el número (`_cambiarSeparacion`
ya existe); hoy nadie viene tildado y había que acordarse familia por familia. `MesasExtraUtils.cantidadAlejadasEfectivas`
sigue siendo el tope.

**Dónde.** "Qué tan lejos" suma **"Donde yo elija"** (`DistanciaLejos.enLaZona`, `mesas_extra_utils.dart:7`), y al
elegirla aparece **ELEGIR EN EL PLANO** ("2 mesas elegidas"). Sin elegir, van "bien lejos" como hoy. Solo con plano:
sin plano no se ofrece. Modo jefe, como todo el sorteo.

- `ElegirZonaDialog` (`plano/widgets/elegir_zona_dialog.dart`, nuevo): **se abre encima del cartel del sorteo**
  (`showDialog` desde el diálogo; el jefe no sale de la grilla ni va a PLANO), con el salón dibujado por `VistaPlano`
  y el `EstadoPlano` de la fiesta de hoy (`PlanoDeLaFiesta`, para ver ocupadas, fijadas y libres en gris); tocar una
  mesa libre la marca o la desmarca; LISTO vuelve al cartel, que dice "2 mesas elegidas". Devuelve `Set<int>`. La
  pantalla de la fiesta ya tiene el armado leído para el sorteo (`leerPlanoParaSortear`): se le pasa al diálogo.
  **Antes de programarla, una maqueta** (PNG de la muestra) para que el usuario la vea.
- `SorteoMesasDialogResult.zonas: Map<String, Set<int>>` y `EntradaSorteoPlano.zonas`.

**El motor.** `SorteoConPlano._ordenLejos` (`plano/services/sorteo_con_plano.dart:399`): con zona, las candidatas
cuya mesa está en la zona van primero (al azar entre ellas), y las demás después con el orden de "bien lejos".
`lejosEnElSalon` sigue mandando: una elegida que toca a la familia se saltea. `_conAvisosLejos` avisa "GÓMEZ: la
adicional no quedó en la zona elegida (ya estaban ocupadas)". `SorteoMesasMotor.ordenPorNumero` (sin plano) no
cambia.

**La mesa comprada después del sorteo.** Hoy `PedidoSorteo.separadas` es 0 si ya tiene mesas, y `_Armado.completar`
la pega al tramo (`sorteo_mesas_motor.dart:503`). Nuevo: si el jefe le elige zona a una familia que ya tiene mesas y
le falta una, `pedidos` le da `separadas = faltan` con esa zona; `completar` la saltea y `_Piezas.de` pone sus
faltantes como sueltas (en el orden de la zona). `seCompleta`, `esFactible` y `capacidadMinima` hacen lo mismo (los
tres recorren igual, a propósito). En `sorteo_con_plano.dart:797` el control de `lejosEnElSalon` incluye a estas
familias. En el diálogo, la fila de una familia que "ya tiene 12, 13" y le falta una deja elegir "la nueva: pegada"
(hoy) o "en una zona que elijo".

**Registro.** `_lejosParaElRegistro` (`detalle_evento_masivo_screen.dart:4512`) escribe `enLaZona`, y una clave nueva
**`_zonas`** en `resultado` (alumno → mesas elegidas), con guion bajo: una versión vieja la ignora. La planilla dice
"en la zona elegida". Sin tocar `sorteos_mesas.tipo`.

**Tests:** `test/sorteo_mesas_dialog_test.dart` (una familia con 4 mesas viene tildada con 1 separada y su aviso; con
3, no; destildar la deja junta); `test/sorteo_zona_elegida_test.dart` (con zona libre, cae ahí; con la zona ocupada, lo más lejos y el
aviso; la zona que toca a la familia se saltea; la mesa comprada después va a la zona; 60 sorteos por salón como
`sorteo_lejos_en_el_salon_test.dart`); el motor sin plano, igual que antes (los tests que ya hay). Widget:
`ElegirZonaDialog` marca y desmarca, no deja tocar una ocupada. Se mira con el mouse en `tool/plano_prueba.dart`.

## Etapa 5 · La prueba en el sandbox, lo escrito y la versión

- **Sandbox:** `tool/central_puerta_prueba.dart` con un armado inventado y sorteado, así el celular de verdad (o
  pestañas del navegador, `tool/central_prueba_test.dart`) muestra VER EN EL PLANO, VER LA LLEGADA, SILLA SUELTA y el
  chat entre dos puestos y la PC. Recorro la noche: una familia en el tope compra una suelta, el vale se anota, el
  chat avisa con sonido en la PC, la llegada se reproduce en el celular sin que la tele se entere.
- La suite entera en verde y `flutter analyze` sin errores (localmente).
- **Versión 6.5.0** en `pubspec.yaml` e `installer/junior_eventos_setup.iss`. **Sin SQL.** Se publica cuando el
  usuario diga, con él presente (instalador, APK y web juntos). Novedades: "La puerta ve el plano, sillas sueltas,
  chat entre puestos y dónde van las mesas lejos".
- **Docs:** este plan a `docs/PLAN_PUERTA_PLANO_Y_SORTEO_2026-11-09.md`; `docs/CONTEXTO_v6.5.0_2026-11-09.md` con "Para
  retomar en otro chat"; CLAUDE.md (la 6.5.0, `mesa 0`, el chat, `enLaZona`); `docs/pendientes/sillas-barra-vs-puerta.md`
  (las sueltas también se cruzan); memoria.

## Orden y cierre

Cada etapa cierra sola, con sus tests, y le digo dónde estamos (etapa, paso, qué sigue, %). Orden: 0 → 1 → 2 → 3 →
4 → 5. La 0 va primera porque es un cobro que puede salir dos veces. Si el usuario quiere ver una maqueta antes de programar una hoja (el plano de la familia, el chat, el elegir la
zona), la saco como PNG de la muestra y la miro antes de mandarla.
