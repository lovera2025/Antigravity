# Contexto: la 6.6.0 — una sola mesa, el papel corto y el cierre con el OK

11-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. Plan aprobado por el usuario ese día
(mover una sola mesa, y en la barra el papel corto, el detalle en la app y el cierre con el OK
de la encargada).

## Para retomar en otro chat

**Estado: PUBLICADA el 11-nov a las 15 hs, con el usuario ("publicá la nueva versión").
Falta que instale las tres PCs y las tablets, y la foto de la mora "después de 6.6.0".**

### Publicada

- **Tag `v6.6.0`** en `fdb4dfd` y **release** "Junior Eventos 6.6.0" con
  `Setup.Junior.Eventos.v6.6.0.exe` (39 MB) y `Junior.Eventos.v6.6.0.apk` (51 MB, firmado con
  "CN=Junior Eventos", comprobado con `apksigner`). Novedades: "Mover una sola mesa en el plano.
  En la barra: el papel corto y el cierre con el OK de la encargada". Desde ese momento las PCs
  y las tablets avisan que hay versión nueva.
- **Web** en Vercel: `arguello-events-qj0b8gfpx`, producción; `version.json` da 6.6.0/69. La
  anterior, para volver atrás: `arguello-events-8usv530pr` (la 6.5.1).
- La suite entera con la 6.6.0: 4.425 pruebas en verde.
- **`installer\build_installer.ps1` no entra en el tope de 10 minutos de la herramienta de
  Claude**: se corta a mitad y parece una falla. Se hizo por pasos, con las mismas
  comprobaciones (la clave de firma, `apksigner`): `flutter build windows --release`, la página
  del celular (`flutter build web --release -t lib/puesto_main.dart --no-web-resources-cdn -o
  build\puesto`), `ISCC.exe installer\junior_eventos_setup.iss`, `flutter build apk --release
  --split-per-abi`, y copiar el arm64 a `installer\dist`.

Lleva tres cosas, cada una con su commit:

| Qué | Commit | SQL |
|---|---|---|
| En el plano, mover **una sola mesa** de una familia que tiene varias | `a7267d5` | No |
| En la barra, **el papel del cierre corto** y el detalle en la app | `d4b07aa` | No |
| En la barra, **la caja se cierra cuando la encargada acepta** | `6b44440` | **Sí**: `supabase/migrations/20261111120000_barra_cierres.sql`, **corrido el 11-nov** |

**La base del equipo va por la v79** (las PCs y las tablets tienen la 78 hasta que instalen).
No correr la app desde esta carpeta contra la base de verdad: la migraría.

**No usar el cierre con el OK hasta que las PCs y las tablets tengan la versión.** Una tablet
con la versión anterior cierra sola como siempre, y una encargada con la versión anterior no ve
el pedido (la cajera esperaría 3 minutos y cerraría sin el OK).

### El 11-nov el usuario perdonó varias moras a mano

Lo avisó ese día, sin acordarse de los nombres. **Al comparar las fotos de la mora van a figurar
perdones nuevos y moras que bajaron: es eso, no un problema.** Lo que sí sería raro es una mora
que sube o un perdón que se va.

### Publicar: lo hecho el 11-nov a la tarde, con el usuario ("publicá la nueva versión")

1. **La migración v79 sobre una copia de la base real: pasó.** La app de esta PC estaba cerrada.
   Las 45 tablas iguales (642 alumnos, 5.025 pagos), aparece `barra_cierres` vacía, se puede
   volver a la 6.5.1 y de nuevo a la nueva, y la base de verdad quedó con el mismo SHA-256.
2. **La versión pasó a `6.6.0+69`** (`pubspec.yaml` y el instalador), commit `fdb4dfd`.
3. **La foto de la mora** (por el conector de Supabase): "después de 6.5.1 (las tres PCs) ·
   antes de 6.6.0", 642 alumnos, `foto_id da6aec8c-0eef-4f2e-816c-6950c15e2ca0`. El usuario
   confirmó ese día que **la 6.5.1 estaba instalada en las tres PCs**. Comparada con la de
   después de la 6.5.0 (la de las 7:44): **nada sospechoso** (ninguna mora subió, ninguna
   eximición se fue ni se acortó, ningún "ya usado" bajó, nada se descongeló). Un perdón nuevo
   y una mora que bajó: los perdones de ese día.
4. **El SQL de `barra_cierres`, corrido con su OK.** Conteos de antes y de después, iguales
   (642 contratos, 5.050 pagos, 2 cajas de barra, 1 venta, 31 eventos). La tabla quedó con RLS,
   un disparador de insert y uno de update, su policy, y fuera de Realtime.

El instalador, el tag, el release y la web: arriba, en "Publicada".

### Lo que queda después de publicar

- **Instalar las tres PCs y las tablets** (lo hace el usuario y avisa). Al abrir, cada equipo
  pasa su base de la v78 a la v79 (deja antes la copia `antes_de_v79.db`).
- **La foto de la mora "después de 6.6.0"**, con las tres PCs instaladas y abiertas, y la
  comparación con `da6aec8c…`.

### Lo que no se probó

- **El cierre con el OK con aparatos de verdad**: dos tablets y la notebook en el router del
  salón, y dos equipos por la nube. Está probado con la central de verdad en esta PC (loopback)
  y con la pantalla entera en memoria.
- **La encargada aceptando desde el iPhone (la web)**: `BarraNube.anotarPasoDelCierre` escribe
  derecho en la nube y no se probó contra Supabase (la tabla todavía no existe ahí).
- **El papel corto en la térmica**: falta la foto del papel impreso.
- **El sonido del aviso** en la tablet Android.
- **Mover una sola mesa a una mesa vacía, con el mouse**: en la ventana de prueba no había mesa
  vacía (se recorrió el cambio por la de otra familia). Está probado en la pantalla entera en
  memoria (`test/plano_evento_screen_test.dart`).

### Lo que quedó distinto del plan

- **"LA ENCARGADA ESTÁ ACÁ" acepta solo el PIN de una encargada de barra**, no el del jefe: el
  PIN del jefe en la app lo deja en modo jefe en ese equipo (`loginJefe`), y no hay cómo
  comprobarlo sin entrar. El jefe acepta desde su equipo, en modo jefe (BARRA → CAJAS).
- La suite entera dio **una falla suelta en una corrida** (1 de 4.365) que no se repitió en las
  corridas siguientes y no se llegó a identificar. No es de estos cambios a simple vista, pero
  no quedó demostrado.

---

## 1. Mover una sola mesa

**El pedido (11-nov):** en Técnica una familia tenía la mesa del sorteo y otra que recibió
después, al fondo. El jefe quería juntarlas y no podía: al tocar una se prendían las dos.

**Por qué pasaba:** no era un error. `CambiosDeMesa.mover` pide tantas mesas seguidas, pegadas
y vacías como tenga la familia, e `intercambiar` pide que las dos familias tengan la misma
cantidad. Siempre se movía la familia entera.

**Lo nuevo:**
- Con una familia de 2 o más mesas, *Mover a otras mesas* y *Cambiar con otra familia* abren
  **"¿Cuál mesa querés mover?"** (`elegirCualMesa`, en `cambio_de_mesa_dialogs.dart`): solo una,
  o todas juntas (lo de siempre). Viene elegida la que se tocó en el plano; si se llegó por el
  buscador, todas juntas. Con una sola mesa no pregunta.
- Con una sola elegida, **el toque decide**: en una mesa vacía la pasa ahí
  (`CambiosDeMesa.moverUna`); en la de otra familia cambia esas dos mesas
  (`intercambiarUna`), aunque tengan distinta cantidad. Mientras se espera, en el plano se
  enciende solo esa mesa.
- El cartel de siempre muestra cómo queda, pide el motivo y avisa: juntas, **pegadas en el
  salón aunque los números no sean seguidos**, o separadas.
- **Las fijadas van mesa por mesa** (`_fijadasMesaPorMesa`): la fijada sigue solo a la mesa que
  se mueve. `deshacer` hace lo mismo cuando la familia conservó alguna mesa; si no, lo de antes.
- **Sin SQL ni tipo nuevo:** el renglón de `mesas_movimientos` es el mismo (`mover` o
  `intercambio`, con el antes y el después de cada familia). Una PC con la 6.5.1 lo lee bien.
- **Ningún guardado nuevo del salón:** `_moverUna` y `_cambiarUna` van por `_cambiarMesas`
  (modo jefe, relee la nube, no guarda si la otra PC movió algo, pone al día la puerta).

**Pruebas:** `test/cambios_de_mesa_test.dart` (grupo "una sola mesa de la familia"),
`test/plano_evento_cuerpo_test.dart`, `test/plano_evento_screen_test.dart`. Con el mouse en
`tool/plano_prueba.dart` compilada para el navegador: LLEGA UNA FAMILIA le dio a una familia la
mesa 36 al fondo, y se cambió su mesa 12 por la 30, que está al lado. Capturas en
`build/muestras_mover_una_mesa/` (fuera de git). **La ventana de prueba ahora cambia y mueve de
verdad** (antes esos dos botones no hacían nada ahí).

## 2. El papel del cierre, corto; el detalle, en la app

**El pedido:** con mucha venta la tira del cierre salía larguísima (un renglón por bebida). El
detalle tiene que verse en la app; el papel, resumido.

- **`ModeloTicket.deCierre(corto: true)`**: lo vendido va **por categoría del catálogo**
  (`CierreDeBarra.porCategoria`), no por bebida. Mide lo mismo se venda lo que se venda. Es el
  que sale solo al cerrar y el de IMPRIMIR de la cajera. Sin categorías cargadas dice
  "Unidades vendidas" en un renglón. La pantalla y el PDF siguen con cada bebida.
- `CierreDeBarra.de(..., categorias:)` recibe la categoría de cada producto (id → "Tragos").
  "Tragos" y "tragos" son la misma; lo que no tiene categoría va a "Otros", al final.
- **LAS CAJAS → una caja** (`jefe/cajas_de_la_fiesta.dart`, la ven el jefe y la encargada):
  - pestañas **VENTAS** y **LO VENDIDO** (cada bebida con sus unidades y su plata, por
    categoría; el total va sin el recargo, que se dice aparte);
  - filtro de ventas **Todas · Efectivo · Transferencia · Mixto · Anuladas**. "Transferencia"
    trae también las mixtas y dice cuántas son y cuánto suman: es la lista para comparar con
    Mercado Pago. La venta mixta dice "E $ x · T $ y".
- **LO VENDIDO DE LA FIESTA** (botón debajo de los totales): todas las cajas juntas
  (`CierreDeBarra.deLaFiesta`, `ModeloTicket.deLoVendido`), con PDF.
- **IMPRIMIR pregunta qué papel** (`widgets/elegir_papel.dart`): corto, o con cada bebida.

**El cierre y las transferencias, como ya estaba:** la cajera cuenta solo el efectivo, y el
efectivo esperado es el cambio más **solo la parte en efectivo** de cada venta (de un mixto,
lo que fue en billetes). Eso no cambió.

**Pruebas:** `barra_cuentas_test`, `modelo_ticket_test` (el corto mide lo mismo con 3 bebidas
que con 60), `barra_jefe_pantalla_test`, `barra_cerrar_test`. Muestra:
`flutter test tool/barra_cierre_muestra_test.dart --plain-name "el papel corto"
--dart-define=salida=<carpeta>` (una noche de 240 ventas y 28 bebidas: 24 renglones contra 47).

## 3. La caja se cierra cuando la encargada acepta

**El pedido, en sus palabras:** la cajera pone cerrar la caja, le salta que tiene que esperar a
que la encargada acepte; a la encargada le salta que tal caja pide cerrar; y la caja se cierra
cuando ella da el OK. Con o sin internet.

**La noche:**
1. La cajera toca el candado y cuenta **a ciegas**, como siempre. Confirma con "SÍ, PEDIR EL
   CIERRE".
2. Su tablet dice **"Esperá a la encargada"**. La caja sigue abierta y no se ve ninguna plata.
3. A la encargada (o al jefe en modo jefe) le salta en su aparato **"La Caja 2 (Marta) pide
   cerrar"**, con sonido, esté en VENDER o en LAS CAJAS (`AvisoDePedidosDeCierre`,
   `widgets/ok_del_cierre.dart`). Toca VER y ve lo esperado, lo que contó, la diferencia, lo
   transferido con cuántas ventas, y el total.
4. **ACEPTAR Y CERRAR**: le llega el ok a la tablet de la cajera, que **cierra la caja ella
   misma** y saca el papel corto, con "Aceptó: Romi" en la nota. **QUE CUENTE DE NUEVO**: la
   cajera vuelve a contar, sin ver ninguna plata.

**Para que ninguna caja quede trabada** (en la pantalla de la espera):
- **LA ENCARGADA ESTÁ ACÁ**: su PIN en esa tablet; ve los totales y acepta ahí. Sin red.
- **CERRAR SIN ESPERAR**: aparece a los 3 minutos (`kEsperaDelOkDeCierre`), pide motivo, y la
  caja queda marcada en LAS CAJAS ("Cerró sin el OK de la encargada").
- **VOLVER A VENDER** (o la flecha de volver): cancela el pedido.

**Quien manda en la barra cierra sin pedir:** la encargada con su propia caja, o el jefe
(`mandaEnLaBarraProvider`).

### Cómo se guarda: `barra_cierres` (v79)

Una fila por paso (`PasoDelCierre`, `datos/paso_del_cierre.dart`), con `tipo`: `pedido`
(lleva lo contado), `ok`, `recontar`, `cancelado`, `sin_ok`. **Solo se agregan filas.** Es el
modelo de `barra_vales`: tabla aparte, sin CHECK, sin clave foránea, sin índice único, con el
trigger de `updated_at`, en `tablasDeLaRed` (cruza por la central de la barra) y en las listas
del motor (baja con lo del cobro).

- **`barra_cajas` no cambia**, y **la caja la sigue cerrando su propio equipo**: el aparato de
  la encargada nunca escribe la caja de otra, solo agrega su respuesta
  (`test/modo_barra_cerrado_test.dart` lo vigila).
- **Como son filas guardadas, un ok no se pierde**: si se corta la red, llega cuando vuelve.
- Quién aceptó va en la nota del cierre ("Aceptó: Romi"), que ya existía y ya sale en el papel.
  Cambiar la nota después no la pierde (`PedidoDeCierre.notaNueva`).
- Un `tipo` que una versión no conoce se ignora.

### La regla (`cuentas/pedido_de_cierre.dart`, sin pantalla ni base)

- **No compara la hora de un equipo con la de otro** (los relojes de las tablets no coinciden):
  una respuesta se ata a su pedido por el id. Entre pedidos de una caja, que anota siempre el
  mismo equipo, manda la hora de ese equipo.
- Lo que anotó la tablet de la cajera (volvió a vender, cerró sin esperar) manda sobre lo que
  contestó otro equipo: es lo que de verdad pasó con la caja.
- **Si hubo ventas después del pedido** (la app se cerró mientras esperaba y siguió vendiendo),
  el ok no cierra: el pedido se cancela y hay que contar de nuevo.
- Los 3 minutos se cuentan con el reloj de la tablet que pidió.

### Cómo se entera cada equipo

Sin reloj nuevo contra la nube. La tablet que espera y el equipo de la encargada **miran su
propia base cada 3 segundos** (`kMirarPedidosDeCierre`): lo que llegó por la red del salón o
bajó de la nube. En la web no hay base: va con la relectura de 30 segundos de LAS CAJAS.

**Pruebas:** `pedido_de_cierre_test` (la regla), `barra_cerrar_test` (la pantalla de la cajera
entera: esperar, recontar, volver a vender, cerrar sin esperar, el PIN), `encargada_de_barra_test`
(el aviso, los totales, aceptar, que suene una sola vez), `central_barra_test` (**sin internet,
con la central de verdad**: el pedido y el ok cruzan, y si la red se cae el ok llega al volver),
`migracion_v79_test`, `sync_tablas_v79_test`, `modo_barra_cerrado_test`. Con el mouse en
`tool/barra_prueba_web.dart`: la cajera pidió, al jefe le saltó el aviso, aceptó, y la caja se
cerró sola con su papel. Capturas en `build/muestras_barra_11nov/` (fuera de git).

**La ventana de prueba de la barra en el navegador estaba rota desde la 6.5.0**: el PIN se le
preguntaba a la nube y nadie podía entrar. `armarLados` ahora pone `enLaWebProvider` en false
(los dos lados son equipos con su base).
