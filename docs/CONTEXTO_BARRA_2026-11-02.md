# La barra y la impresora (en curso, SIN PUBLICAR)

2 y 3-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. El plan entero, aprobado por el usuario: `docs/PLAN_BARRA_2026-11-03.md`.
El orden de todo: `docs/HOJA_DE_RUTA_2026-11-02.md`.

**Estado (3-nov): las etapas 1, 2 y 3 cerradas.** La impresora, probada en papel desde la PC y desde un celular Android. Los datos de la barra
(v77, el sync y el SQL de la nube **sin correr**), con la migración probada sobre una copia de la base real. Las cuentas y lo que dice cada
papel, mirado en el papel con fotos. **Lo que sigue es la etapa 4 (la cajera: entrar, fiesta, caja, VENDER).** La app todavía no tiene
pantallas de barra. Sin versión, sin release, sin web. Las PCs siguen con la 6.2.1. Publicar, solo preguntándole antes al usuario.

## Para retomar en otro chat

**Dónde quedó (3-nov, tarde):** todo commiteado y subido. Después de la etapa 3 se hizo un tramo corto, **el "3b": los vales** (abajo). La
suite entera, en verde (3.324 tests). `flutter analyze` sin nada nuevo. Ningún archivo a medias. **Falta:** que el usuario imprima los vales
(botón VALES), mande la foto y se los muestre al jefe con la maqueta.

## El 3b: los vales, en vez del ticket (3-nov, pedido del jefe)

El jefe pidió que de una compra salga **un vale**, no el ticket: sin logo, sin precios, **sin QR** ("es muy un embole") y con lo que se
entrega en letras grandes, como "JUNIOR EVENTOS". Lo hablado, con muestras en el chat:
- **Dos formas al cobrar:** **TODO JUNTO** (un vale con todas las bebidas, para quien retira de una vez) y **POR SEPARADO** (para ir
  retirando de a poco). "Sin papel" lo sacó el jefe.
- **Por separado, cada bebida es su sector, con una sola casilla "vale por ___" (vacía: la cajera la escribe si aplica) y su propio botón
  IMPRIMIR.** 10 cervezas y "vale por 3" son 4 vales: 3, 3, 3 y 1. Sin número, un vale con todas. Lo impreso queda marcado y su botón se apaga.
- **Cada vale sale solo, cuadradito, y se arranca antes del siguiente** (nada de tira). Lleva todo para reclamarlo, porque el barman se lo
  queda: la fiesta en negrita, el día, la fecha y la hora, "Caja 2 · Marta · N° 0017", "VALE POR 3 / CERVEZA LATA" en grande, "1 DE 4" y
  "Vale solo hoy · una sola vez / El barman se queda el vale".
- **Contra el engaño, sin aparato:** el barman se queda el vale; la fiesta y el día dicen de qué noche es; una fotocopia se nota; la cajera
  reimprime solo la última venta, una vez; el jefe, cualquiera, y sale **\*\*\* COPIA \*\*\*** arriba y abajo con quién, cuándo y el motivo
  ("se entrega solo con el jefe"). Todo queda anotado.
- **La cajera también anula**, con el motivo obligatorio y anotado (quién, cuándo, desde qué equipo), como hoy el jefe.
- **Abrir la caja no pregunta el cambio ni el turno** (es de noche, nada de mañana/tarde): el cambio se pone después, con un ícono, si hay.
- **Una persona controla el sector de barras con un iPhone:** es la web en modo jefe, que ya estaba en el plan (etapa 6).

**Lo programado (solo el papel, sin pantallas ni base):** `cuentas/vales_de_barra.dart` (`Vale.todoJunto`, `Vale.porSeparadoDe`,
`partirEnVales`, `valePorValido`, `CopiaDeVale`); `GrandeTicket` y `renglonesGrandes` en `impresion/ticket_esc_pos.dart` (doble de alto y de
ancho, 16 letras partidas por palabras; `soloAlto`, 32); `ModeloTicket.deVale` y `diaFechaYHora` ("Vie 04/12/2026 - 23:41"). Tests:
`test/vales_de_barra_test.dart`, el grupo "el vale" de `modelo_ticket_test` y la letra grande en `impresora_barra_test`. Roturas a propósito
vistas en rojo (el último vale con lo que sobra, las 16 letras, la COPIA de abajo).

**Para mirarlo:** el botón **VALES** de `tool/impresora_prueba.dart` imprime uno todo junto, los 4 de la cerveza de a uno (4 s para
arrancar cada uno: lo decide el papel) y una copia. La maqueta, con los dos botones, la casilla y el IMPRIMIR por bebida:
`build/maquetas/vales_de_la_barra.html` (no va a git; se rehace desde el chat). Papel estimado: el ticket de hoy unos 12,5 cm; un vale
todo junto unos 6 cm; uno por separado unos 5 cm. La medida justa, de la foto.

**Dónde entra en las etapas:** la 4 (la cajera) lleva abrir sin cambio ni turno y el ícono del cambio; la 5 (cobrar e imprimir) lleva los
dos botones, la casilla, la impresión de a uno, reimprimir con freno y ANULAR de la cajera. **Datos de la 5, decididos:** `vale_por` adentro
del JSON `renglones` de `barra_ventas` (sin columna); una tabla nueva `barra_reimpresiones`, que solo agrega, dentro de la v77 (no se
publicó): con ella hay que volver a probar la migración sobre una copia de la base real, con la app cerrada.

**La rama lleva, sin publicar:** el plano antes de los sorteos (6.3.0, `docs/CONTEXTO_v6.3.0_2026-11-02.md`), operadores con permisos (etapas 1
a 3, `docs/CONTEXTO_OPERADORES_2026-11-02.md`) y la barra, etapas 1 a 3 (este archivo). **Dos SQL sin correr, antes de instalar:**
`supabase/migrations/20261103120000_permisos_operador.sql` (v76) y `supabase/migrations/20261103140000_barra.sql` (v77).

**Lo que sigue: la etapa 4, la cajera.** Antes de programar, el plan corto y el OK del usuario (así trabaja: una etapa por vez, cada una cierra
con tests, roturas a propósito, commit, push y este archivo al día). Lo que entra, según la sección 3 del plan (con lo que cambió el 3b:
abrir sin cambio ni turno):
- **Entrar:** `AppRoleKind.barra` (hoy el enum es `none, jefe, caja, entradas`, en `caja_sesiones/providers/app_role_provider.dart`);
  `destinoDeEntrada` lleva a `BarraHomeScreen` (nueva, en `lib/features/barra/`). `kBarraTodaviaNo` desaparece de
  `caja_sesiones/services/entrada_de_operador.dart`, de `caja_sesiones/widgets/role_gate_screen.dart` y de su test. Molde: cómo se hizo
  Entradas (`lib/features/entradas/entradas_home_screen.dart`, `test/modo_entradas_cerrado_test.dart`).
- **Elegir la fiesta:** solo las que tienen precios (`fiestasConPrecios`), con la línea "Lista para trabajar sin internet" de la barra:
  `EstadoSinInternetBarra` y `PuestaAlDiaBarra`, calcados de los de la puerta (`recepcion/services/lista_sin_internet.dart`), sobre
  `SyncEngine.bajarParaLaBarra()`.
- **Abrir su caja:** número 1 a 6 y sede (`BarraDeLaCaja.abrirCaja`), **sin preguntar el cambio ni el turno** (3b). El cambio se pone
  después, con un ícono en la pantalla de la caja o al cerrar. Dos cajas con el mismo número en la misma fiesta se avisan al abrir.
- **VENDER**, según `CortesPantalla` (600 y 1.024 px): en el celular los productos arriba y la cuenta abajo; en la tablet, lado a lado. Chips
  de categoría, tocar suma, − / + / quitar, VACIAR (`CuentaBarra`), y lo que queda de cada producto (`StockDeLaBarra`). Al abrir VENDER y al
  volver del segundo plano, `ImpresoraBluetooth.reconectar()`. El botón COBRAR lleva a la etapa 5.
- **`esBarra` en `common/widgets/operational_sync_coordinator.dart`:** que lo vendido suba solo.
- **Los tests:** `test/helpers/barra_en_memoria.dart`, `test/barra_pantalla_test.dart` (la pantalla de verdad a 360 y a 1024 px),
  `test/modo_barra_cerrado_test.dart` (ningún camino a cobrar cuotas ni al panel; `sesionCajaIdParaCobro` rechaza a barra) y
  `entrada_operador_test` ampliado. **Y con el mouse**, en `tool/barra_prueba.dart` (nuevo, sin base ni nube): lo visual se termina de probar
  en la ventana de verdad.

**Lo que se habló y quedó decidido el 3-nov:**
- **El catálogo es general, el precio va por fiesta.** El usuario pensaba que el precio era general; se le explicó y dijo "está bien". Si
  después quiere un precio general con cambios por fiesta, se cambia fácil mientras no se publique: las tablas no están en ninguna PC.
- **Una venta anulada no cuenta en el efectivo esperado del cierre** (se supone que la plata se devolvió). Se le dijo y no lo objetó.
- **Lo impreso se mira con foto**: el 2-nov "salió bien" escondía los acentos rotos.

**Para probar la impresora:** `flutter run -d windows -t tool/impresora_prueba.dart` (se conecta sola a la TP-POS58 recordada; TICKET y
CIERRE salen con `ModeloTicket`). Para manejarla con capturas, el permiso es para la ruta entera de
`build\windows\x64\runner\Debug\arguello_events.exe`. La impresora atiende a un equipo por vez: cerrar la ventana de la PC antes de usar
el celular. El APK del celular: ver "El APK para mandar al celular", abajo.

## Etapa 3: las cuentas (3-nov)

Todo puro, sin pantalla ni base, en `lib/features/barra/cuentas/`, y lo que dice cada papel en `impresion/modelo_ticket.dart`:

- **`pesos`**: "$ 7.000", "$ 3.999,99". Las cuentas van **en centavos enteros** (`centavos`): 3 x 1.333,33 da 3.999,99. La de la app
  (`toCurrency`) pone siempre ",00" y no entra en el renglón.
- **`CuentaBarra`**, la cuenta de VENDER: sumar, restar (en cero sale), quitar, vaciar. Cada toque da una cuenta nueva, y cada renglón se queda
  con el precio con que se sumó.
- **`CobroBarra`** y **`PartidoMixto`**, COBRAR: efectivo con lo que entrega y el vuelto (sin anotar lo que entrega, paga justo);
  transferencia con la tilde "Vi el comprobante"; mixto en dos casilleros atados que se corrigen. `falta` dice por qué no se puede confirmar,
  con las palabras de la cajera. **Un test arma la venta con cada cobro que se puede confirmar, y todas cierran.**
- **`NumeroDeTicket`**: "Caja 2 · N° 0017" y el QR `je:barra:<id de la venta>`, que se lee de vuelta (`ventaDelQr`). El "·" sale bien en la
  TP-POS58: es el mismo byte que en la prueba de la 1252 salió así.
- **`CierreDeBarra`**: ventas, mixtas, efectivo, transferencia y **el efectivo esperado: el cambio inicial más lo cobrado en efectivo**.
  **Una venta anulada no cuenta, tampoco en el esperado** (se supone que esa plata se devolvió; decisión del 3-nov, el usuario no la objetó).
  Lo anulado se muestra aparte. `diferenciaEnPalabras`: "Justo, sin diferencia", "Sobran $ 500", "Faltan $ 500".
- **`ResumenDeCajas`**, CAJAS del jefe: cada caja por número con sus cuentas, y los totales; lo contado y la diferencia, de las cerradas.
  **La diferencia es la que se anotó al cerrar**: si el jefe anula después, el cierre no se corrige.
- **`StockDeLaBarra`**: lo cargado menos lo vendido que cuenta, por fiesta. Avisa al llegar al mínimo, y en cero siempre. **No frena la venta**:
  puede quedar negativo. Para el jefe, solo los controlados y los que están en aviso arriba.
- **`fiestasConPrecios`**: las fiestas que la cajera puede elegir, las que tienen algún precio activo.
- **`ModeloTicket.deVenta`** (con la anulada: "*** ANULADA ***" arriba y abajo, con el motivo, sin las gracias) y **`deCierre`** (una caja
  abierta sale sin lo contado). La hora, siempre en Argentina (`ArTime`), y los textos largos partidos por palabras (`partirPorPalabras`).
  Los tests comparan el papel renglón por renglón, a 32 letras.
- **La ventana de prueba** imprime TICKET y CIERRE con `ModeloTicket` y datos inventados. **Salieron bien en el papel** (foto del usuario,
  3-nov): el isotipo, los acentos, las columnas, el QR, la hora y las cuentas del cierre.
- **Al final, 3 renglones en blanco y el pedido de corte solo** (`OpcionesEscPos.avanceAlFinal`, `pedidoDeCorte`). Antes eran 8: 3 nuestros
  y 5 que `Generator.cut` agrega antes de cortar, papel tirado en una impresora sin cortador como la TP-POS58 (se arranca contra la tapa). Con 3,
  lo último impreso sale entero y el blanco entre dos papeles es corto (foto del usuario, 3-nov).

**Tests:** `barra_cuentas_test` y `modelo_ticket_test`. Roturas a propósito vistas en rojo: el cierre contando las anuladas, la
transferencia sin tilde, el mixto que no suma y el stock contando las anuladas. **No probado:** que la hora salga en Argentina en un equipo
con otro huso (esta PC ya está en el de Argentina; la cuenta usa `ArTime`, que no mira el del equipo).

**Lo que la etapa 3 deja para las pantallas:** `EstadoSinInternetBarra` y `PuestaAlDiaBarra` (etapa 4, con la puesta al día de la tablet).

## Etapa 2: los datos (3-nov)

**Cinco tablas nuevas, v77** (`LocalDatabase.crearTablasV77`), y su SQL de la nube, **sin correr**:
`supabase/migrations/20261103140000_barra.sql`.

| Tabla | Id | Para qué |
|---|---|---|
| `barra_productos` | aleatorio | el catálogo, de todas las fiestas; dar de baja es `activo = 0` |
| `barra_precios` | fijo, `UuidUtils.barraPrecioId(fiesta, producto)` | el precio de un producto en una fiesta, con stock y aviso si se controla |
| `barra_cajas` | aleatorio | la caja de barra que abre la cajera en su equipo (no es la de cuotas) |
| `barra_ventas` | aleatorio | una venta; **nunca se edita ni se borra**; los renglones con el nombre y el precio del momento |
| `barra_anulaciones` | fijo, `UuidUtils.barraAnulacionId(venta)` | anular es otra fila: una por venta |

- **Los modelos** (`lib/features/barra/datos/`): `ProductoBarra`, `PrecioBarra`, `CajaBarra`, `VentaBarra` (con `RenglonVenta` y `MedioBarra`) y
  `AnulacionBarra`. **Una venta que no cierra no se arma** (`VentaBarra.nueva`): el total es la suma de los renglones, efectivo más
  transferencia dan el total, el vuelto es lo que sobra de lo recibido, y una transferencia lleva el comprobante visto. Lo leído **nunca tira**:
  unos renglones rotos dejan la venta sin renglones y con sus montos; un medio que esta versión no conoce es `MedioBarra.otro`.
- **Dos interfaces** (`barra_repositorio.dart`): `BarraDelJefe` (catálogo, precios, mirar cajas y ventas, anular) y `BarraDeLaCaja` (abrir,
  vender, cerrar). `BarraLocal` hace las dos sobre la base y la cola; `BarraNube` hace solo la del jefe, directo en la nube, para la web del
  iPhone: **la web no vende**.
- **El número del ticket** sale de `MAX(numero) + 1` de su caja, en la misma transacción que guarda la venta: ocho ventas a la vez dan del 1 al 8.
- **Una caja vive en un solo equipo:** `cajaAbierta` y `abrirCaja` miran solo las de este equipo; tocar dos veces abrir no abre dos.
- **Cerrar la caja** escribe lo contado y la diferencia, y una caja cerrada no se vuelve a cerrar. **Anular** no toca la venta, y anular dos veces
  deja la primera anulación.
- **El sync:** las cinco en `_incrementalColumns` y en la bajada general; cajas, ventas y anulaciones en `_tablasDelCobro` (cada 10 s); productos
  y precios en `_tablasDeCarga` (cada minuto). Prioridad de subida: productos 1, precios y cajas 2, ventas 4, anulaciones 5. Las cinco en
  `_tablasSinRevisarBorrados`, con el motivo. **`SyncEngine.tablasDeLaBarra`** (la fiesta, los operadores con sus permisos, el catálogo y los
  precios) y `bajarParaLaBarra()`, para preparar la tablet en la oficina.
- **La web pagina de a 1000** (una fiesta puede tener más ventas) y **ordena siempre con `ascending: true`**: un test encontró que el paquete
  ordena de mayor a menor si no se le dice.

**La migración sobre una copia de la base real** (`tool/verificar_migracion_v77_test.dart`, 3-nov, con la app cerrada): la base estaba en la v75
(la 6.2.1) y saltó a la 77; las 35 tablas de antes, iguales fila por fila; aparecieron las 7 nuevas (las 2 de los permisos y las 5 de la barra),
vacías; el esquema de lo de antes, igual; se vuelve a la 6.2.1 y de nuevo a la 77 con los mismos datos; y la base real quedó con el mismo SHA-256.

**Tests:** `migracion_v77` (de 75 y de 76 a 77, dos veces, vuelta a la 6.2.1, sin únicos), `sql_v77_coherencia`, `sync_tablas_v77` (con la
bajada de la tablet sobre una nube simulada), `barra_repositorios` y `barra_nube`. Roturas a propósito vistas en rojo: el número repetido,
las ventas fuera del ciclo de 10 s, un CHECK en la nube y un índice único en la PC.

**Decisiones que no estaban en el plan:**
- **Ninguna tabla de la barra va en la limpieza padre-hija de la cola** (`_cleanOrphanQueueEntries`). Esa limpieza saca de la cola las hijas
  de un padre que se borra: con una venta adentro, borrar la fiesta en el equipo perdería una venta que no subió. En la nube no hay clave
  foránea que la rechace, así que sube igual. El plan decía ponerlas.
- **`barra_cajas` lleva `operador_nombre`**: el nombre de la cajera ese día, para el ticket y el cierre aunque después le cambien el nombre.
- **Sin índices únicos fuera del id, también en la PC:** al bajar, la fila entra con `INSERT OR REPLACE`, y un único repetido haría que SQLite
  borre la otra fila sin avisar.
- **Quedan para su etapa:** el depósito `barra` de las fotos y `ImagenDeProducto` (etapa 7, con el catálogo), `esBarra` en el coordinador del
  sync y `PuestaAlDiaBarra` (etapa 4, con la entrada de la cajera), y `subirYa` en cada venta (etapa 5).

**Antes de instalar, el SQL de la barra tiene que estar corrido:** sin las tablas en la nube, cada PC falla al bajarlas en cada ciclo, lo vendido
queda trabado en la cola y **la revisión de la mora no corre** (espera una bajada sin fallas).

## Lo que dio el celular (3-nov, con capturas de su pantalla)

| | En la PC | En el celular Android |
|---|---|---|
| Conectar la primera vez | 1,6 a 2,5 s | 1,5 s |
| Por dónde escribe | el UART de ISSC, sin respuesta | el mismo |
| De a cuánto | 180 bytes | 180 bytes: el MTU se negocia bien, no hizo falta tocar `pedirMtu` |
| Reabrir la ventana | "Conectada sola" en 1,9 s | "Conectada sola" en 0,4 s |

El usuario dijo que las impresiones salieron "un lujo". Las capturas no muestran el renglón de TICKET del celular: que imprimió desde ahí
lo dice él.

## Lo que dio el papel (3-nov, mirado por el usuario, con fotos)

| Prueba | Lo que salió | Lo que quedó |
|---|---|---|
| ACENTOS con la tabla 1252 | **letras raras**: "á" salió "ß", "Ú" salió "┌", "°" salió "░" | descartada |
| ACENTOS, otra vez | con la **tabla 850** todo bien: acentos, ñ, mayúsculas, ¿¡ y "N°" | la 850 (`tabla_850.dart`) |
| ANCHO | las 32 cifras entran justas; el nombre largo se partía "product / o" | renglones partidos por palabras (`renglonesDe`) |
| ANCHO, otra vez | se lee bien, con el importe a la derecha del primer renglón | — |
| QR nativo | se lee con la cámara del celular | queda nativo |
| LOGO | el isotipo (`isotipo-ej.png`, por umbral) se lee mejor que la silueta de `2.png` | el isotipo |

**El 2-nov el ticket "salió entero y bien" según el usuario, y no era cierto en los acentos**: con la 1252 el "N°" y el "¡" salían cambiados, y
recién la foto lo mostró. Lo que diga el papel se confirma con una foto, no con la respuesta a una pregunta.

**Por qué la 850:** las letras raras eran exactamente lo que dibuja la 850 con los bytes de la 1252. La impresora no hace caso del pedido de la
1252 y queda en la 850. `esc_pos_utils_plus` manda el texto en Latin-1 si no se le da otro `codec`: se le pasa `tabla850`, que pone cada
letra del castellano en su lugar de la 850, y se pide la tabla 2 (`ESC t 2`).

## La impresora

Es una **TP-POS58**, de 58 mm, por **Bluetooth de bajo consumo (BLE)**. No hay nada de ella por USB en esta PC. El usuario imprimió desde su
celular con otra app antes de esto, y la app la encontró en esta PC con la búsqueda, sin emparejarla de nuevo.

| Lo que se vio el 2-nov desde esta PC | |
|---|---|
| Búsqueda | la encontró en 10 s; no figura como emparejada para la app |
| Conexión | 1,3 s |
| Por dónde escribe | `49535343-8841-…` (UART de ISSC), sin respuesta |
| De a cuánto | 180 bytes |
| Ticket con logo y QR | 7.897 bytes en 1,05 s, sin error |

**Sin respuesta quiere decir que la impresora no confirma nada:** "impreso" es que la app mandó todo sin error, no que el papel salió bien.
Con trozos de 180 bytes y 20 ms de pausa no perdió ningún renglón, tampoco en el logo (14.503 bytes en 1,9 s): `pausa` queda como está.

## Qué se hizo

- `lib/features/barra/impresion/`: `CanalBle` (la interfaz) y `CanalUniversalBle` (el paquete); `ImpresoraBluetooth` (conectar, trozos, un ticket
  por vez, nunca tira); `elegirCaracteristica` (conocidas primero, nunca las del sistema, así sirve para "lo que se detecte"); `TicketEscPos` (los bytes de
  58 mm); `LogoParaPapel` (silueta y umbral); `textoParaPapel` (un emoji en un producto no frena una venta).
- `tool/impresora_prueba.dart`: BUSCAR, CONECTAR, TICKET, ACENTOS, ANCHO, QR, LOGO y OLVIDAR. Al abrir, si el equipo ya tiene impresora, se
  conecta sola (lo mismo que va a hacer VENDER). Corre en Windows y compila para Android.
- `test/impresora_barra_test.dart`: 27 tests, con 5 roturas a propósito vistas. **Encontró un error antes de la prueba de verdad:** el paquete de imágenes tira con
  un archivo roto, y un logo dañado habría frenado la venta.
- Permisos de Bluetooth en el manifest de Android.

**El 3-nov:**
- **La impresora de cada equipo** (`ImpresoraRecordada`, en `SharedPreferences`, claves `barra.impresora.*`): se elige una vez. Antes de cada ticket
  `ImpresoraBluetooth` mira si sigue conectada y, si no, se conecta a la recordada (`reconectar`, también para VENDER al abrir y al volver del segundo
  plano). Sin ninguna elegida dice `sinImpresoraElegida` sin tocar el Bluetooth; apagada, `noConectada`. En esta PC, reabrir la ventana la conectó
  sola en 1,9 s.
- **Si se corta a la mitad, reconecta y manda el ticket entero una vez más**; si se vuelve a cortar, `fallo`. Puede salir un pedazo repetido: mejor
  eso que un ticket que no sale. La venta se guarda antes de imprimir (lo dice el plan), así que `fallo` nunca pierde una venta.
- **La tabla 850**, `renglonesDe` (32 letras, el importe al borde, partido por palabras) y `LogoDelPapel` con el que va en la app.
- `test/impresora_barra_test.dart` pasó a 50 tests.
- **Android compila:** `applicationId` pasó a `ar.com.junioreventos.app` (no hay nada instalado). `universal_ble` 3.1.0 no aplicaba el plugin de
  Kotlin (espera el Android Gradle Plugin 9; la app usa el 8.11): `android/build.gradle.kts` se lo aplica solo a ese paquete. Sacarlo al pasar al 9.

## Decisiones que no estaban en el plan

- **`universal_ble` queda en la 3.1.0, no en la 3.2.0.** Desde la 3.1.1 pide un `dbus` que choca con `file_picker` 10, que usan otras pantallas. Se mueve cuando se
  actualice `file_picker`. El plan decía 3.2.0.
- **No se tomó nada de la rama `feature/barra-impresora`** salvo la idea de los botones: usaba otro paquete y nunca compiló. Se puede borrar.
- **Se imprimió un solo ticket esa noche.** Los otros botones gastan papel y se deciden mirándolo.
- **Los renglones de un producto no usan las columnas del paquete** (`row` con 8/4): cortaban la palabra a la mitad. `renglonesDe` arma cada renglón
  de 32 letras a mano.
- **El QR queda nativo**, sin la variante como imagen: se leyó a la primera.
- **El APK para mandar al celular** se arma así: `flutter build apk --release --split-per-abi -t tool/impresora_prueba.dart` (36 MB, firmado con la
  clave de prueba de esta PC) y se le sacan los logos de `assets/icons` que la ventana no usa, con zipalign y apksigner de nuevo: queda en 20 MB, bajo el
  tope de 30 MB del chat. El de debug pesa 172 MB. La app entera no se achica así: lleva esos logos.

## Lo que no se comprobó

- **Un corte de verdad a la mitad de un ticket.** El reintento está probado en los tests, no con la impresora. **Si se corta en medio del logo**, la
  impresora puede quedar esperando el resto de la imagen y tomarse el principio del reintento como imagen: saldría una franja rara arriba del ticket
  repetido. Se mira apagando la impresora a la mitad de un LOGO.
- **Una tablet.** Se probó en el celular del usuario; la tablet de la barra todavía no se compró.
- **La app entera en Android.** Lo que compiló es la ventana de prueba; la app con la base, el sync y el login va en la etapa 9.

## Lo pendiente, en orden

**Etapas 1 (la impresora), 2 (los datos) y 3 (las cuentas): cerradas el 3-nov.**

**Después, cada una con sus tests** (el detalle de la 4, arriba en "Para retomar"):
4. la cajera: entrar, fiesta, caja, VENDER;
5. cobrar e imprimir: COBRAR con `CobroBarra`, guardar con `BarraDeLaCaja.vender` **antes** de imprimir, `subirYa` con internet, el ticket por
   Bluetooth con `ModeloTicket.deVenta` y su PDF (58 mm), REIMPRIMIR; sin impresora, la venta igual queda y se avisa;
6. cerrar la caja: contado a ciegas, `CierreDeBarra`, `cerrarCaja`, el papel y el PDF del cierre;
7. el jefe en la PC: catálogo con fotos (el depósito `barra` de Storage, con su SQL aparte, e `ImagenDeProducto`), precios con stock y "copiar
   de otra fiesta", CAJAS (`ResumenDeCajas`, el stock con los que están en aviso arriba), anular con motivo, PDF 58 mm y A4, la lista de precios;
8. el jefe en la web del iPhone, sobre `BarraNube`;
9. Android con su firma: la clave la genero yo fuera del repo (`Documentos\Junior Eventos\claves\`), `key.properties` fuera de git, y el
   usuario la copia a un lugar seguro;
10. de punta a punta, sin internet, con modo avión;
11. Entradas, etapas 4 a 6 (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`);
12. versión y publicación, cuando el usuario diga: foto de la mora antes, los dos SQL (v76 y v77) con su OK, release de Windows, web y APK
    firmado, foto después.

**Lo que le toca al usuario:** comprar la tablet cuanto antes, así el APK se prueba en ella desde ya, y copiar a un lugar seguro la clave de firma
cuando exista. **Antes de instalar la app firmada en su celular, desinstalar la ventana de prueba** (`ar.com.junioreventos.app`, con la clave de
prueba): con otra firma no se instala encima.

**Lo pedido el 2-nov que entra en esas etapas:** cada producto con su foto, para que se vea como un buen catálogo · imprimir el catálogo · alerta de stock · imprimir la caja de
cada persona al terminar · la web del jefe entera · entrar con internet baja todo, se trabaja sin internet, y al volver sube solo y el jefe lo ve enseguida · **todo con sus tests.**
