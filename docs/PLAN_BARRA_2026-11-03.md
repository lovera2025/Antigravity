# Plan: el módulo de barra, con la impresora, y después Entradas: todo en una versión

Fecha: 2-nov-2026 (noche). Rama: `feature/v4.6-cierre-por-sesiones`. Aprobado por el usuario el 2-nov, después de ajustarlo: fotos en el catálogo, stock con alerta, la web entera, tests de todo. **Publicar, solo cuando él lo diga.**

Leer antes: `CLAUDE.md`, `docs/HOJA_DE_RUTA_2026-11-02.md` (paso 4) y `docs/CONTEXTO_OPERADORES_2026-11-02.md`.

## Contexto

Hecho y subido a la rama, sin publicar: el plano (6.3.0, probado con el mouse) y Operadores con permisos (etapas 1 a 3).
La impresora de la barra **ya llegó y el usuario imprimió desde su celular**. Lo que se vio en esta PC el 2-nov:

- Es una **TP-POS58** (térmica de 58 mm), emparejada en esta PC por **Bluetooth de bajo consumo (BLE)**, conectada hoy a las
  18:42. No hay nada de ella por USB (el puerto serie USB que aparece es de otro aparato, "HL-VMAX"). Expone los servicios
  GATT `0000FF00`, `49535343-FE7D-…` (UART ISSC/Microchip) y `E7810A71-…`: se puede escribir por BLE desde Android y desde Windows.
- Lo que pidió el usuario: la cajera vende desde **Android (tablet o celular, por comprar)**; la impresión tiene que estar
  **"preparada para lo que se detecte"**; BARRA del jefe va **en la PC y también entera en la web del iPhone** (catálogo,
  precios, cajas y anular); la clave de firma de Android **la genero yo** y queda fuera del repo. Después de la barra sigo con
  **Entradas (etapas 4 a 6)** y se **publica todo en una sola versión**, cuando él lo diga.
- La rama `feature/barra-impresora` (un commit, nunca compilado, con `print_bluetooth_thermal`) no se mezcla: se toma el arnés
  como referencia y los permisos del manifest. El paquete elegido es **`universal_ble` 3.1.0** (misma API en Android y
  Windows: buscar, conectar, escribir; la 3.1.1 en adelante choca con `file_picker` 10) con **`esc_pos_utils_plus` 2.0.4** (bytes del ticket, `PaperSize.mm58`, QR nativo,
  imagen) e `image` (silueta del logo). Verificados en pub.dev el 2-nov.
- Las maquetas de Vender, Cobrar y Cerrar la caja ya están aprobadas (2-nov, hoja de ruta paso 4). No hay maqueta nueva.

**Primer entregable:** `docs/PLAN_BARRA_2026-11-03.md` con este mismo plan (es la convención de la casa), y recién después el
código. Cada etapa cierra sola con su commit, tests y roturas a propósito; nada se publica.

**Esta noche (2-nov), solo lo cortito que pidió el usuario:** la etapa 0 (el plan en `docs/`) y el primer tramo de la etapa 1:
los paquetes, el módulo de impresión mínimo y el arnés, hasta que la TP-POS58 imprima un ticket de prueba desde esta PC.
Commit y, antes de parar, **poner al día lo hecho y lo pendiente**: `docs/HOJA_DE_RUTA_2026-11-02.md` (lo de hoy: el plano
probado, operadores, la impresora), el CONTEXTO que corresponda, `CLAUDE.md` y la memoria. El resto sigue mañana, cuando él diga.

## Decisiones (lo aprobado, más lo que resolví yo y se puede cambiar)

> **Cambio del 3-nov (pedido del jefe, el "3b"):** el papel de cada compra es **un vale**, no el ticket: sin logo, sin precios, **sin QR**,
> con lo que se entrega en letras grandes. TODO JUNTO o POR SEPARADO (cada bebida con su casilla "vale por" y su IMPRIMIR), un vale por
> papel, el barman se lo queda, COPIA marcada y anotada, la cajera también anula con motivo, y abrir la caja no pregunta el cambio ni el
> turno. El ticket con precios queda para quien lo pida. Lo que dice cada línea de abajo sobre el ticket y su QR queda para ese ticket.
> El detalle, en "El 3b: los vales" de `docs/CONTEXTO_BARRA_2026-11-02.md`.

- **"Por sede" = por fiesta.** La ficha del evento no tiene sede. La caja lleva `sede` como texto opcional (prellenado con el
  predio del plano si lo hay), y el jefe ve las cajas agrupadas por fiesta.
- **El logo en papel** va como **silueta negra** de `assets/icons/2.png` (es blanco y magenta sobre transparente: en papel
  blanco desaparece). El arnés imprime también `isotipo-ej.png` por umbral, para elegir mirando el papel.
- **El QR del ticket** lleva el id de la venta (`je:barra:<uuid>`): único en todos los equipos, sirve para buscarla y anularla.
- **El número del ticket** es correlativo **por caja** (`MAX+1` en la misma transacción) y sale como "Caja 2 · N° 0017"; una caja
  vive en un solo equipo, así que no choca sin internet. Sin secuencia ni índice único en la nube.
- **Cerrar la caja:** la cajera cuenta a ciegas (pone el efectivo contado) y recién después ve lo esperado y la diferencia.
  No se corrige nada.
- **Una venta nunca se edita.** Anular es una fila nueva en otra tabla (`barra_anulaciones`), solo el jefe, con motivo. Así la
  tablet nunca pisa una anulación hecha desde la PC.
- **La venta se guarda antes de imprimir.** Sin impresora, el ticket queda guardado y se reimprime; nunca se frena una venta.
- **Precio por fiesta** (no por caja). Un producto se da de baja, no se borra.
- **Cada producto con su foto** (pedido del 2-nov, "que se vea como un buen catálogo"): el jefe la elige al cargar el
  producto; se achica a 800 px (`image`) y sube al bucket `barra` como hace la foto del tótem
  (`TotemConfigRepository`: `uploadBinary` + `getPublicUrl`). **En la tablet se guarda en la PC**
  (`ImagenDeProducto`, calcada de `FotoGuardada`, carpeta `imagenes_barra`): la baja la puesta al día y después se ve sin
  internet; en la web se ve desde la URL. Las fotos salen en VENDER, en el catálogo del jefe y en la lista de precios en PDF
  (la de 58 mm sin fotos: no entran). Sin foto, un recuadro con la inicial. El bucket se crea con el SQL de la versión.
- **Con internet y sin internet, siempre** (regla del usuario, 2-nov): entrar con internet baja todo (fiesta, precios, fotos,
  operadores); en el salón se vende sin; al volver el internet **sube solo** (la cola, cada 10 s, y `subirYa` en cada venta
  con internet) y el jefe lo ve en segundos por el pulso. `operational_sync_coordinator.dart` suma `esBarra` a lo que puede
  subir solo. La prueba de punta a punta (etapa 10) hace exactamente ese recorrido, con modo avión.
- **Stock con alerta** (pedido del 2-nov): el jefe carga por fiesta cuántas unidades hay y desde cuántas avisar. Lo que queda es
  `stock_inicial − vendido` sobre las ventas no anuladas de la fiesta (`StockDeLaBarra`, cuenta pura). En VENDER cada producto
  muestra lo que queda y se pinta de aviso al llegar al mínimo; en CAJAS el jefe ve el stock de toda la fiesta. **Sin internet
  cada equipo descuenta solo lo que vendió él** (las ventas de la otra caja llegan al volver el internet): se dice en pantalla.
  No frena la venta: con stock en cero igual se puede vender, con el aviso.
- **`applicationId` pasa a `ar.com.junioreventos.app`** ahora, que nada está instalado; después sería otra app.
- **Ninguna tablet de producción recibe un APK firmado con la clave de prueba:** cambiar la firma obliga a desinstalar, y eso
  borra las ventas que no subieron.
- **La web del jefe** lee y escribe directo en Supabase: los repositorios de la barra tienen una interfaz con dos
  implementaciones (SQLite + cola en PC y Android; Supabase directo en la web), como ya pasa con los invitados.

## 1. Los datos (v77 local, un SQL de nube sin correr)

Cinco tablas nuevas, todas `CREATE TABLE IF NOT EXISTS` en `LocalDatabase.crearTablasV77` (molde `crearTablasV76`, en
`lib/core/database/local_database.dart`), con `hecho_por`, `device_id`, `created_at`, `updated_at`:

| Tabla | Id | Lo propio | Quién escribe |
|---|---|---|---|
| `barra_productos` | aleatorio | `nombre`, `categoria`, `activo`, `orden`, **`imagen_url`** (la foto, en el bucket `barra` de Supabase Storage) | el jefe |
| `barra_precios` | fijo `UuidUtils.barraPrecioId(evento, producto)` | `evento_id`, `producto_id`, `precio`, `activo`, `orden`, **`stock_inicial`** (nulo = sin control), **`aviso_stock`** (desde cuántas avisar) | el jefe (dos PCs escriben la misma fila) |
| `barra_cajas` | aleatorio | `evento_id`, `operador_id`, `numero_caja`, `sede`, `cambio_inicial`, `abierta_at`, `cerrada_at`, `efectivo_contado`, `diferencia`, `nota_cierre` | la tablet que la abre; cerrar es un update del mismo equipo |
| `barra_ventas` | aleatorio | `caja_barra_id`, `evento_id`, `numero`, `renglones` (JSON con nombre y precio del momento), `total`, `medio`, `efectivo`, `transferencia`, `recibe`, `vuelto`, `comprobante_visto` | la tablet; nunca se edita |
| `barra_anulaciones` | fijo `UuidUtils.barraAnulacionId(venta)` | `venta_id`, `caja_barra_id`, `evento_id`, `motivo` | el jefe |

- `lib/core/services/sync_engine.dart`: las cinco en `_incrementalColumns`; `barra_cajas`, `barra_ventas` y `barra_anulaciones`
  en `_tablasDelCobro` (cada 10 s: el jefe mira la fiesta en vivo); `barra_productos` y `barra_precios` en `_tablasDeCarga`;
  `_pullFromCloud`; `_cleanForSqlite`; prioridad (productos 1, precios y cajas 2, ventas 4, anulaciones 5);
  `_tablasSinRevisarBorrados` con motivo. `sync_queue.dart`: padre-hija (eventos, operadores_caja, productos, cajas, ventas).
  **`SyncEngine.tablasDeLaBarra`** (`eventos`, `operadores_caja`, `permisos_operador`, `barra_productos`, `barra_precios`) y
  `bajarParaLaBarra()`, sin tocar `tablasDeLaPuerta`.
- SQL `supabase/migrations/20261106120000_barra.sql`, calcado del de permisos: sin CHECK, sin FK, sin único; RLS
  `authenticated`; triggers de `updated_at`; ROLLBACK y verificación. `renglones` como `text`, plata como `numeric`.
- Tests: `migracion_v77` (saltos 76→77 y 75→77), `sql_v77_coherencia`, `sync_tablas_v77`, `barra_repositorios` (numerar en
  transacción, anular no toca la venta, cerrar escribe la diferencia, lo encolado), `puesta_al_dia_barra`, y
  `tool/verificar_migracion_v77_test.dart` sobre una copia de la base real con la app cerrada (acepta base en 75 o 76).

## 2. La impresión: `lib/features/barra/impresion/`

- **`ModeloTicket`**: líneas puras (título, texto, renglón izquierda/derecha, separador, logo, QR) armadas desde la venta, el
  cierre o la lista de precios. Test con el texto esperado línea por línea, incluida la venta anulada ("*** ANULADA ***").
- **`TicketEscPos`**: los bytes, sobre `esc_pos_utils_plus` (`PaperSize.mm58`, columnas 8/4 de 12, 32 caracteres), con
  `OpcionesEscPos` (tabla de caracteres CP1252 o sin acentos, columnas, QR nativo o como imagen, logo raster) que se fija con lo
  que dé la prueba (`OpcionesEscPos.deLaPrueba`, con fecha). `LogoParaPapel.silueta` y `.umbral` con `image`. Test de bytes
  (`ESC @`, tabla, alineación, `GS ( k` del QR, raster, corte).
- **`ImpresoraBluetooth`** sobre una interfaz `CanalBle` (`CanalUniversalBle` real; `CanalBleEnMemoria` en tests): buscar sin
  filtro y ordenar por "parece impresora"; elegir la característica de escritura (ISSC → FF02 → E7810A71 → la primera que
  escriba), **cuenta pura con test**; MTU en Android; mandar en trozos (`mín(mtu−3, 180)`, 20 si no se sabe) con pausa;
  recordar la impresora por equipo en `SharedPreferences`; reconectar al abrir VENDER, al volver del segundo plano y antes de
  cada ticket; un ticket a la vez; `ResultadoImpresion` (impreso / sin impresora elegida / no conectada / falló). Disponible
  en Android y Windows. Si `universal_ble` no pide el permiso solo, `permission_handler`.
- **PDF en archivos aparte** (`ticket_pdf.dart`, `papeles_barra_pdf.dart`): 58 mm (`PdfPageFormat(58 mm, alto libre)`) y A4
  (`MultiPage`) del mismo modelo, para el ticket, la lista de precios y el cierre; Outfit de los assets (`PdfService._fuentesOutfit`
  pasa a público: el único toque a `pdf_service.dart`, junto con `_entregarPdfEnWindows`); QR con `pw.BarcodeWidget`. En la
  tablet se guarda y se ofrece COMPARTIR; en la PC se abre; en modo jefe se elige el tamaño. Tests de ancho, una hoja, texto,
  "ANULADA"; muestras en `tool/barra_muestra_test.dart`.
- **`tool/impresora_prueba.dart` reescrito sobre el módulo**, sin base ni nube, para Windows y Android: BUSCAR, CONECTAR,
  TICKET, ACENTOS, ANCHO, QR, **LOGO** (las dos imágenes, raster y ESC *), VELOCIDAD (trozos de 20/100/180) y CIERRE.
  **Se corre primero desde esta PC** (la impresora está emparejada acá) y después en el celular del usuario con el APK.

## 3. Las pantallas

**La cajera** (`AppRoleKind.barra`, `destinoDeEntrada` → `BarraHomeScreen`, en `lib/features/barra/`; `kBarraTodaviaNo` desaparece
de `entrada_de_operador.dart`, `role_gate_screen.dart` y su test): elegir la fiesta (solo las que tienen precios) con la
línea "Lista para trabajar sin internet" de la barra (`EstadoSinInternetBarra`, `PuestaAlDiaBarra`, calcados de la puerta) →
abrir su caja (número 1 a 6, cambio inicial, sede) → **VENDER** (`CortesPantalla`: en celular productos arriba y la cuenta
abajo; en tablet lado a lado; chips de categoría; tocar suma; − / + / quitar; VACIAR) → **COBRAR** (hoja en celular, diálogo
en tablet: efectivo con "Recibe" y vuelto en vivo; transferencia con "Vi el comprobante" obligatoria; mixto con dos
casilleros atados y corregibles) → confirmar: guarda en transacción, `subirYa`, imprime, guarda el PDF, cartel con número y
vuelto → **CERRAR LA CAJA** (contado a ciegas, diferencia, PDF y ticket del cierre) → sus ventas, con REIMPRIMIR / PDF.
Cuentas puras con test: `CuentaBarra`, `CobroBarra`, `PartidoMixto`, `NumeroDeTicket`, `CierreDeBarra`, `StockDeLaBarra`,
`fiestasConPrecios`, `EstadoSinInternetBarra`. `test/modo_barra_cerrado_test.dart` lee las pantallas: ningún camino a cobrar cuotas ni al panel;
`sesionCajaIdParaCobro` ya rechaza a barra.

**El jefe** (tarjeta BARRA en el centro de comando, `BarraJefeScreen` en `lib/features/barra/jefe/`, doble llave
`kSoloEnModoJefe` + `_frenaSinModoJefe()`): CATÁLOGO (nombre, categoría libre, baja), PRECIOS por fiesta (casilla, precio,
stock y aviso; "copiar de otra fiesta"; la lista de precios en PDF 58 mm / A4), CAJAS por fiesta (`ResumenDeCajas`: por caja,
efectivo, transferencia, mixtos, ventas, anuladas, contado y diferencia; totales; **el stock que queda de cada producto, con los
que están en aviso arriba**), ventas de una caja, ANULAR con motivo, REIMPRIMIR / PDF, cierre en PDF.
**En la web del iPhone, lo mismo**, con `CortesPantalla` para celular, sobre `BarraSupabaseRepositorio`; la impresora por
Bluetooth queda para PC y Android. `test/solo_modo_jefe_test.dart` ampliado; "nadie más anula".

**Cómo se prueba:** `test/helpers/barra_en_memoria.dart` (repos, canal BLE y entrega de PDF en memoria, reloj fijo),
`test/barra_pantalla_test.dart` (la pantalla de la cajera de verdad, a 360 y a 1024 px, de punta a punta),
`test/barra_jefe_pantalla_test.dart`, y el arnés `tool/barra_prueba.dart` para manejarlo con el mouse en esta PC, con la
impresora real si está prendida.

## 4. Android

- Etapa 0: `flutter build apk --debug` y `--release`; gates que faltan (`_abrirTotem` y `KioskLauncher.launch` solo en
  escritorio); permisos Bluetooth en el manifest (`BLUETOOTH_SCAN` sin ubicación, `BLUETOOTH_CONNECT`, y los viejos con
  `maxSdkVersion=30`); `applicationId ar.com.junioreventos.app`; ícono.
- **La firma:** genero la clave con `keytool` en `Documentos\Junior Eventos\claves\junior_eventos.jks`, `android/key.properties`
  con las contraseñas (fuera de git: `.gitignore` suma `key.properties`, `*.jks`, `*.keystore`), `build.gradle.kts` lee
  `key.properties` si existe y si no cae a debug. **Le digo al usuario qué carpeta copiar a un lugar seguro.**
- **Qué va a GitHub:** todo el código de Android, en la misma rama (es la misma app). El APK firmado se sube al release de
  GitHub junto al instalador de Windows al publicar. **La clave de firma y sus contraseñas, nunca.**
- Sin Android conectado: compila en la PC, `test/android_listo_test.dart` lee los gates, los permisos y la firma; el APK va al
  celular del usuario (primero el arnés de la impresora en la etapa 1; después la app entera). Antes de instalar la firmada
  hay que desinstalar la de prueba.

## 5. Las etapas (una por commit)

| # | Etapa | Días | Riesgo |
|---|---|---|---|
| 0 | `docs/PLAN_BARRA_2026-11-03.md` | — | — |
| 1 | **La impresora desde Windows**: paquetes, manifest, `impresion/` entero, arnés; `flutter build windows` y `flutter build apk --debug`; la prueba de hardware acá y el APK del arnés al celular; lo que dio queda en `OpcionesEscPos.deLaPrueba` | 2–3 | **Alto**: BLE lento sin MTU o sin raster; plan B: `CanalBle` con `print_bluetooth_thermal` en Android, sin tocar el resto |
| 2 | **Los datos**: v77, modelos, repositorios (interfaz + SQLite + Supabase), sync, `tablasDeLaBarra`, SQL; migración sobre copia de la base (pedir la app cerrada) | 2–3 | Bajo |
| 3 | **Las cuentas puras** | 1–2 | Bajo |
| 4 | **La cajera**: entrar, fiesta, caja, VENDER responsive, sin internet; `tool/barra_prueba.dart` con el mouse | 3 | Medio: 360 px con el teclado |
| 5 | **Cobrar e imprimir**: COBRAR, ticket por BLE y PDF, reimpresión | 2 | Medio |
| 6 | **Cerrar la caja** con su PDF y ticket | 1–2 | Bajo |
| 7 | **El jefe en la PC**: catálogo, precios, cajas, anular, PDF 58/A4 | 3 | Medio |
| 8 | **El jefe en la web**: las mismas pantallas sobre Supabase directo, en el iPhone; se publica la web al final con todo | 2–3 | Medio: la web se prueba en el navegador de esta PC a 390 px |
| 9 | **Android**: gates, firma, `applicationId`, APK firmado al celular; Recepción sin internet en el celular | 2–3 | **Alto para el 4-dic**: primer Android en producción; se mitiga probando el APK en la etapa 1 |
| 10 | **De punta a punta**: celular vendiendo sin internet con la impresora, la PC del jefe viendo las cajas al volver el internet, anular desde la PC, reimprimir | 2 | Medio |
| 11 | **Entradas, etapas 4 a 6** (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`) | 3–4 | Medio |
| 12 | **Versión y publicación**, cuando el usuario diga: foto de la mora antes, los SQL v76 y v77 antes de instalar con su OK, release Windows + web + APK firmado, foto después, CONTEXTO y CLAUDE.md | 1–2 | Medio |

Son 24 a 30 días para 32 hasta el 4-dic. **Lo que recomiendo: comprar la tablet ya**, así el APK se prueba en ella desde la
etapa 1 y no en la semana 4.

## Qué prueba cada cosa acordada (todo lleva test; cada fila existe y pasa antes de cerrar su etapa)

| Lo acordado | El test |
|---|---|
| El ticket dice lo que tiene que decir, también anulado | `modelo_ticket_test`: línea por línea; `ticket_esc_pos_test`: bytes (reset, tabla, 32 columnas, QR, corte) |
| El logo sale en papel | `logo_para_papel_test`: silueta negra, ancho 240, raster; y el papel de verdad desde esta PC |
| La impresora se encuentra, se recuerda y se reconecta | `impresora_bluetooth_test`: característica elegida con los GATT de la TP-POS58, trozos, corte y reintento, sin impresora no toca nada |
| Sin impresora la venta igual se guarda | `barra_pantalla_test`: cobrar con el canal caído deja la venta y el aviso con REIMPRIMIR |
| La migración solo agrega | `migracion_v77_test` (75→77 y 76→77, dos veces, vuelta a la 6.2.1); `tool/verificar_migracion_v77_test` sobre la copia real |
| La nube acepta lo que manda la app | `sql_v77_coherencia_test`: columnas = `toMap`, sin CHECK/FK/único; `sync_tablas_v77_test`: listas, prioridad, padre-hija, sin borrados |
| El número del ticket no se repite en una caja | `barra_repositorios_test`: dos ventas seguidas dan 1 y 2 dentro de la transacción |
| Una venta nunca se edita; anular es un renglón nuevo | `barra_repositorios_test`: anular inserta y no toca la venta; `solo_modo_jefe_test`: "nadie más anula" |
| La cuenta, el vuelto, el mixto y el cierre dan bien | `cuenta_barra_test`, `cobro_barra_test` (sin tilde no confirma; mixto suma al total), `partido_mixto_test`, `cierre_de_barra_test` (diferencia) |
| El stock avisa y no frena | `stock_de_la_barra_test`: descuenta las no anuladas, aviso al mínimo, vende en cero |
| La cajera no llega a cobrar cuotas ni al panel | `modo_barra_cerrado_test` (lee las pantallas), `sesionCajaIdParaCobro` rechaza a barra |
| Entrar con Barra, directo o eligiendo | `entrada_operador_test` ampliado |
| La pantalla entera, en celular y en tablet | `barra_pantalla_test` a 360 y 1024 px: fiesta → caja → tres toques → cobrar → ticket y PDF → segunda venta 0002 → cerrar |
| Solo el jefe carga, pone precios y anula | `barra_jefe_pantalla_test` (apagado con el motivo sin modo jefe); `solo_modo_jefe_test` ampliado |
| Las fotos se bajan y se ven sin internet | `imagen_de_producto_test`: achica a 800 px, guarda en `imagenes_barra`, sin internet lee la guardada |
| "Lista para trabajar sin internet" dice la verdad | `estado_sin_internet_barra_test`, `puesta_al_dia_barra_test` (baja todo o dice qué faltó, cuenta ventas sin subir) |
| Lo vendido sube solo al volver el internet | `sync_tablas_v77_test` (en `_tablasDelCobro`, prioridad), `esBarra` en el coordinador (test que lee el archivo); y la etapa 10 a mano |
| La web del jefe lee y escribe la nube | `barra_supabase_repositorio_test` con el cliente simulado (como `puesta_al_dia_nube_test`) |
| Los PDF salen en 58 mm y en A4 | `ticket_pdf_test`, `papeles_barra_pdf_test` (ancho exacto, una hoja, texto, "ANULADA", fotos solo en A4) |
| Android compila y queda firmado | `android_listo_test` (gates, permisos, `key.properties`, release no firma con debug); `flutter build apk --release` |

## Verificación

- Por etapa: `flutter analyze` sin nada nuevo, `flutter test` entero en verde, roturas a propósito vistas en rojo, commit.
- Etapa 1: tickets de verdad por la TP-POS58 desde esta PC (el usuario mira el papel cuando vuelve) y desde su celular.
- Etapa 2: `tool/verificar_migracion_v77_test.dart` sobre la copia de la base real: ningún dato cambia, vuelta a la 6.2.1, mismo
  SHA-256.
- Etapas 4 a 7: `tool/barra_prueba.dart` con el mouse en esta PC; etapa 8: la web en el navegador a 390 px; etapa 9: el APK en
  el celular del usuario, con modo avión.
- Etapa 10 a mano, con guion escrito en el CONTEXTO. Lo que no se pueda probar queda dicho ahí.

## Lo que supongo si no decís otra cosa

Sede = fiesta; silueta negra de `2.png` en papel; el QR con el id de la venta; conteo a ciegas al cerrar; precio por fiesta;
tablet con Android 12 o más (el manifest cubre las dos); dos cajas con el mismo número en la misma fiesta se avisan al abrir.
