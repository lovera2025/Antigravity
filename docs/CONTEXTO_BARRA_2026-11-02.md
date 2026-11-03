# La barra y la impresora (en curso, SIN PUBLICAR)

2-nov-2026, noche. Rama `feature/v4.6-cierre-por-sesiones`. El plan entero, aprobado por el usuario: `docs/PLAN_BARRA_2026-11-03.md`.
El orden de todo: `docs/HOJA_DE_RUTA_2026-11-02.md`.

**Estado: primer tramo de la etapa 1. La app todavía no tiene barra: hay un módulo de impresión y una ventana de prueba. Sin versión, sin
release, sin web, sin SQL nuevo. Las PCs siguen con la 6.2.1. Publicar, solo preguntándole antes al usuario.**

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
**Nadie miró el papel todavía.** Mandar tan rápido puede llenarle el búfer y perder renglones, sobre todo en el logo. Si pasa, se sube `pausa` o se
baja el tamaño del trozo.

## Qué se hizo

- `lib/features/barra/impresion/`: `CanalBle` (la interfaz) y `CanalUniversalBle` (el paquete); `ImpresoraBluetooth` (conectar, trozos, un ticket
  por vez, nunca tira); `elegirCaracteristica` (conocidas primero, nunca las del sistema, así sirve para "lo que se detecte"); `TicketEscPos` (los bytes de
  58 mm); `LogoParaPapel` (silueta y umbral); `textoParaPapel` (un emoji en un producto no frena una venta).
- `tool/impresora_prueba.dart`: BUSCAR, CONECTAR, TICKET, ACENTOS, ANCHO, QR y LOGO. Corre en Windows; para Android, `flutter build apk --debug -t` (sin probar).
- `test/impresora_barra_test.dart`: 27 tests, con 5 roturas a propósito vistas. **Encontró un error antes de la prueba de verdad:** el paquete de imágenes tira con
  un archivo roto, y un logo dañado habría frenado la venta.
- Permisos de Bluetooth en el manifest de Android.

## Decisiones que no estaban en el plan

- **`universal_ble` queda en la 3.1.0, no en la 3.2.0.** Desde la 3.1.1 pide un `dbus` que choca con `file_picker` 10, que usan otras pantallas. Se mueve cuando se
  actualice `file_picker`. El plan decía 3.2.0.
- **No se tomó nada de la rama `feature/barra-impresora`** salvo la idea de los botones: usaba otro paquete y nunca compiló. Se puede borrar.
- **Se imprimió un solo ticket esa noche.** Los otros botones gastan papel y se deciden mirándolo.

## Lo que no se comprobó

- **El papel.** Hay que mirar el ticket que salió: el logo en silueta, los acentos ("N°", "¡Gracias"), las columnas y si el QR se lee con el celular.
- **Android.** La ventana de prueba no se compiló todavía para Android, y es el riesgo más grande.
- **ACENTOS, ANCHO, QR y LOGO** no se mandaron. De ahí sale `OpcionesEscPos.deLaPrueba`, que todavía no existe.

## Lo pendiente, en orden

**Etapa 1, lo que falta:**
1. **El usuario mira el ticket impreso** y dice cómo salió. Con eso se toca la pausa si perdió renglones.
2. ACENTOS, ANCHO, QR y LOGO en el papel: tabla de caracteres, cuántas letras entran y cuál logo se lee. Queda fijo en `OpcionesEscPos.deLaPrueba`.
3. Recordar la impresora por equipo, reconectar sola, y reintentar si se corta a la mitad.
4. `flutter build apk --debug -t tool/impresora_prueba.dart` y al celular del usuario.

**Después, cada una con sus tests:** 2. los datos (v77, sync, SQL) · 3. las cuentas (venta, vuelto, mixto, cierre, stock) · 4. la cajera: entrar, fiesta, caja, VENDER · 5. cobrar e imprimir
· 6. cerrar la caja · 7. el jefe en la PC: catálogo con fotos, precios con stock, cajas, anular, PDF 58 mm y A4 · 8. el jefe en la web del iPhone · 9. Android con su firma
· 10. de punta a punta, sin internet · 11. Entradas, etapas 4 a 6 · 12. versión y publicación, cuando el usuario diga.

**Lo que le toca al usuario:** comprar la tablet cuanto antes, así el APK se prueba en ella desde ya, y copiar a un lugar seguro la clave de firma cuando exista.

**Lo pedido el 2-nov que entra en esas etapas:** cada producto con su foto, para que se vea como un buen catálogo · imprimir el catálogo · alerta de stock · imprimir la caja de
cada persona al terminar · la web del jefe entera · entrar con internet baja todo, se trabaja sin internet, y al volver sube solo y el jefe lo ve enseguida · **todo con sus tests.**
