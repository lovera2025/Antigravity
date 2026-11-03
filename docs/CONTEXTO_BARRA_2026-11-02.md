# La barra y la impresora (en curso, SIN PUBLICAR)

2-nov-2026, noche. Rama `feature/v4.6-cierre-por-sesiones`. El plan entero, aprobado por el usuario: `docs/PLAN_BARRA_2026-11-03.md`.
El orden de todo: `docs/HOJA_DE_RUTA_2026-11-02.md`.

**Estado (3-nov): la etapa 1 cerrada.** El papel se miró y quedó fijo en `OpcionesEscPos.deLaPrueba`; la impresora se recuerda por equipo y
se conecta sola, en la PC y en el celular Android del usuario. **Lo que sigue es la etapa 2 (los datos).** La app todavía no tiene barra. Sin
versión, sin release, sin web, sin SQL nuevo. Las PCs siguen con la 6.2.1. Publicar, solo preguntándole antes al usuario.

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

**Etapa 1: cerrada el 3-nov.**

**Después, cada una con sus tests:** 2. los datos (v77, sync, SQL) · 3. las cuentas (venta, vuelto, mixto, cierre, stock) · 4. la cajera: entrar, fiesta, caja, VENDER · 5. cobrar e imprimir
· 6. cerrar la caja · 7. el jefe en la PC: catálogo con fotos, precios con stock, cajas, anular, PDF 58 mm y A4 · 8. el jefe en la web del iPhone · 9. Android con su firma
· 10. de punta a punta, sin internet · 11. Entradas, etapas 4 a 6 · 12. versión y publicación, cuando el usuario diga.

**Lo que le toca al usuario:** comprar la tablet cuanto antes, así el APK se prueba en ella desde ya, y copiar a un lugar seguro la clave de firma cuando exista.

**Lo pedido el 2-nov que entra en esas etapas:** cada producto con su foto, para que se vea como un buen catálogo · imprimir el catálogo · alerta de stock · imprimir la caja de
cada persona al terminar · la web del jefe entera · entrar con internet baja todo, se trabaja sin internet, y al volver sube solo y el jefe lo ve enseguida · **todo con sus tests.**
