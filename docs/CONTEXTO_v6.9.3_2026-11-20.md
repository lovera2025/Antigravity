# CONTEXTO — la 6.9.3: VENDER con la entrega adentro, la entrega en dos partes y PRECIOS nuevo

**Estado (22-nov-2026, tarde): SIN PUBLICAR, 98 %. Todo programado y probado en el sandbox, también "Entradas para
rendir" entera (etapas 2 a 8), los papeles solo con su botón, el talonario obligatorio, "Para el DJ" y PRECIOS en
otras fiestas, y el recorrido con el mouse hecho. Falta publicar con él** (ver "Para retomar").
La versión del programa sigue en `6.9.2+77`; al publicar pasa a `6.9.3+78` (`pubspec.yaml` y
`installer/junior_eventos_setup.iss`), con las novedades **"Actualizaciones y estabilidad"** (decisión del usuario,
20-nov). Lleva **dos SQL en la nube, solo de agregar, sin correr**
(`supabase/migrations/20261120120000_entradas_entregas.sql` y `supabase/migrations/20261121120000_entradas_para_rendir.sql`)
y **dos migraciones en las PCs, la v81 y la v82, que solo crean una tabla cada una** (las PCs tienen la 80). **Con la
v82 en el código, no correr la app desde esta carpeta contra la base de verdad.**

Planes aprobados: el de la versión, `C:\Users\lover\.claude\plans\cucha-tema-permisos-de-resilient-codd.md` (20-nov,
madrugada), y el de comprobar y probar, `C:\Users\lover\.claude\plans\hay-que-segur-chequear-synthetic-abelson.md`
(20-nov, mañana). Sale del audio 6 del jefe: "estas que estamos haciendo son las anticipadas, las ventas al público;
me tienen que llegar las pulseras para los egresados y acompañantes y las entradas para ellos".

## Para retomar en otro chat

### Dónde quedó (22-nov-2026, tarde) — 98 %

El usuario pidió repasar lo que le sirve (venderle a los alumnos con contrato, a los de afuera y que puedan
rendir) y sumó cuatro cosas, todas **programadas, probadas y guardadas** (plan aprobado:
`C:\Users\lover\.claude\plans\bueno-que-falta-para-encapsulated-blum-of-11f9623c-fd9d-444d-a433-890d20403b77.md`):
- **Ningún papel sale solo** (eligió "Nada sale solo"): el aviso de VENDER lleva IMPRIMIR EL COMPROBANTE (el
  original; después VER DE NUEVO, la COPIA), PARA RENDIR → IMPRIMIR LA CONSTANCIA (y CONSTANCIA de cada bloque
  sale REIMPRESA solo si el bloque tiene movimientos), cerrar la caja → IMPRIMIR EL CIERRE y LISTO no pregunta;
  el cierre dice que después lo saca el jefe en **Cierre de caja → ENTRADAS**, que tiene la impresora en el
  renglón de cada caja cerrada (`cc476db`).
- **El número del talonario es obligatorio en cada venta** (`kTalonarioObligatorio`, en `PedidoDeEntradas.falta`;
  VENDER lo sigue proponiendo y se escribe a mano). Las generales que se entregan sin cargo siguen con número
  opcional. El historial A4 ya no dice "pulseras" (`d32b5e3`).
- **PLANILLAS → "Para el DJ"**: un PDF con cada egresado, sus acompañantes y su música, por división, sin los de
  baja ni nada más; sin modo jefe (`1b31e7a`, `lib/features/common/services/planilla_dj_pdf.dart`). Muestra en
  `build/muestras_dj/` (mandada).
- **PRECIOS en otras fiestas** (pedido a mitad de camino): al GUARDAR, si hay otras fiestas por venir, salta
  "¿Poner estos precios también en otras fiestas?" (ninguna tildada, TODAS); con la anticipada se elige "el día
  anterior a cada fiesta" o "el mismo día" (`f58ebeb`, `cuentas/precios_en_otras_fiestas.dart`,
  `widgets/precios_en_otras_fiestas_dialog.dart`, `fiestasParaLosPreciosProvider`). Con "el mismo día" no deja
  tildar una fiesta que es ese día o antes, y la de anoche no se ofrece.
- `entradas_config` y `sorteos_mesas` bajan con lo del cobro (`ba6dee7`): el precio llega enseguida a la tablet.

Y lo que faltaba de antes:
- **Etapa 7 hecha**: la ventana de prueba recorre los tres casos de punta a punta entre la tablet y la PC, con y
  sin internet (`3833dde`; `test/venta_entradas_prueba_test.dart`, 23). Muestras en `build/muestras_6.9.3_final/`.
- **Etapa 8 hecha**: roturas 36 a 75 en `tool/roturas_6.9.3.txt` (todas detectadas); la regla 61 en
  `test/venta_entradas_no_toca_test.dart`; RENDIR vuelve a pedir el permiso después de su ventana (test nuevo);
  **la v82 sobre una copia de la base real**, de la 80 a la 82 de una y en dos pasos, con la vuelta a la 6.9.2, la
  base real IGUAL (`tool/verificar_migracion_v82_test.dart`); el conteo de familias por grupo de VENDER sobre la
  copia (`tool/familias_para_vender_test.dart`, los nombres fuera de git): de 9 fiestas, entre 0 y 28 "puede
  retirar" cada una, la mayoría "debe", 17 "revisar" en SAGRADO CORAZON (sin mesa: falta sortear) y 2 a 16 con algo
  "a confirmar"; **una revisión independiente** de tres miradas (la plata, sin internet y dos equipos, pantallas y
  llaves): todo lo confirmado, arreglado con su test (`93d12c7`, `100f6d5`).
- **La suite entera, con todo: 6.118 tests, ninguno falla** (22-nov a la tarde).

- **El recorrido con el mouse, hecho el 22-nov a la tarde** (con su permiso), en `tool/venta_entradas_prueba.dart`,
  con la huella de la base IGUAL antes y después: PRECIOS → "otras fiestas" (BAHÍA SERENA, "EL 28/11"); A PAGAR de
  ACOSTA (mesa adicional, 8 al 50 %, del 2001 al 2008, efectivo; el jefe ve "8 vendidas de 24"); alguien de afuera
  (2 anticipadas, propuesto el 2009, transferencia); DAR 20 a PEREZ JUAN (1201-1220) y en la tablet "Entradas para
  rendir: 1 persona"; RENDIR 15 + devuelve 5 (propuestos 1216-1220), $120.000 en efectivo, el jefe ve "rindió todo";
  CERRAR CAJA justo ($165.000), LISTO sin preguntar, y el papel desde Cierre de caja → ENTRADAS. **Ningún papel salió
  solo**; cada botón sacó el suyo. Capturas en `build/capturas_6.9.3_mouse/` (mandadas). El primer toque a la
  impresora del cierre en la ventana solo la activó (la ventana no estaba al frente): no es de la app.

**Lo que falta, en orden:**
1. Que mire las capturas y las muestras (`build/muestras_6.9.3_final/`, `build/muestras_6.9.3/`, `build/muestras_dj/`).
2. Para preguntarle, sin frenar: "Emitido:" 3 horas antes en otros papeles
   (`docs/pendientes/horas-corridas-en-otros-papeles.md`); el recargo por transferencia para quien vende; cómo
   recibe el comprador el comprobante desde la tablet (Compartir).
3. **Publicar con él** ("Al publicar", abajo): los dos SQL antes de instalar; la migración se repite sobre una
   copia nueva si pasan días.

**Quedó sin arreglar, a propósito:** `entradas_config` es una fila por fiesta que sube entera: si el jefe pone
precios en varias fiestas desde una PC sin internet y otra PC cambia una de esas mientras tanto, gana la que sube
última (ya pasaba con una sola fiesta; un solo jefe). El original del comprobante se saca desde el aviso de la
venta; después, VENTAS → REIMPRIMIR da la COPIA.

### Dónde quedó (22-nov-2026)

- **La etapa 6, los papeles: programada, revisada y guardada (22-nov).** El usuario preguntó qué faltaba para quedar
  seguro de empezar a vender; se hizo una auditoría de solo lectura (abajo, "La auditoría del 21/22-nov") y dijo
  "seguí". Lo hecho, en "Etapa 6, los papeles (22-nov)", abajo.
- **Plan general de la 6.9.3: 88 %.** Sigue la etapa 7 (la ventana de prueba con PARA RENDIR y las muestras).

### Dónde quedó (21-nov-2026)

- **Lo que faltaba de la 6.9.3 de antes, hecho el 20-nov a la noche** (`ca149c0`): el arreglo 9 (anular una parte
  queda siempre después de cada copia de la fila, con su rotura, la 35), **las roturas 21, 22 y 24 a 35, todas
  detectadas**, y la suite entera: 5.798 tests, ninguno falla.
- **"Entradas para rendir", pedido del usuario el 20-nov y sumado adentro de la 6.9.3** (plan aprobado
  `C:\Users\lover\.claude\plans\que-sigue-fizzy-thompson.md`; SPEC `docs/SPEC_entradas_para_rendir_2026-11-20.md`;
  maqueta `docs/maqueta_entradas_para_rendir_2026-11-20.html`, que vio y aprobó el 20-nov). A veces se le dan entradas
  a alguien sin plata en el momento (un egresado o alguien de afuera), las vende y después rinde: al precio del día
  en que se las llevó, toda la plata, sin comisión, con los números del talonario reservados a su nombre. Ver
  "Entradas para rendir", abajo.
  - **Lo que aclaró al ver la maqueta (20-nov): la pulsera no se vende.** Lo único que se vende son las entradas
    anticipadas; las pulseras VIP y las entradas generales se entregan sin cargo a los alumnos que pagaron. Quien le
    compra a quien rinde se lleva solo la entrada (`8480ed3`).
  - **"Olvidá el viceversa":** la regla de quién retira entradas sin cargo no cambia (`RetiroEntradas.bloqueo` y
    `bloqueoDeLaVenta` no se tocaron).
  - **Programadas, probadas y guardadas las etapas 2 a 5 de la SPEC**: los datos (`8a25140`), el motor y el SQL de la
    nube, las cuentas y las pantallas (los commits de abajo). Cada etapa la programó un agente y la revisó otro, que
    no escribía, hasta que dio bien; al final, siete detalles más de esas revisiones y dos revisiones más. **La suite
    entera: 6.051 tests, ninguno falla (21-nov), y `flutter analyze` sin avisos en lo tocado.**
  - **El usuario cortó acá** ("hacé hasta las pantallas: dar, rendir, aviso, ventas, y actualizá el contexto con lo
    hecho y lo pendiente para retomar en otro chat").
- **Plan general de la 6.9.3: 85 %** (lo de antes estaba en 96 %; con "Entradas para rendir" faltan los papeles, la
  ventana de prueba y el cierre). El 100 % es publicar con él.

### Lo que falta, en orden (21-nov)

1. ~~**Etapa 6, los papeles**~~ **Hecha el 22-nov** (ver "Etapa 6, los papeles (22-nov)"; queda la pregunta del
   historial A4). Lo que decía:
   - **La constancia "ENTRADAS PARA RENDIR"** (`pdf/para_rendir_pdf.dart`, `abrirConstanciaParaRendirProvider`, media
     A4 en dos copias para firmar: quién, los números, el precio y "sin pulseras, rinde toda la plata"). Hoy el botón
     CONSTANCIA de cada bloque está apagado con `kConstanciaTodaviaNo`; tiene que salir también después de DAR.
   - **El comprobante de la rendición**: el mismo `ComprobanteEntradasPdf` con `DatosDelComprobante.rendicion`
     ("Recibió / Rinde", regla 59). Hoy VENDER, después de rendir, solo dice "Rendición guardada · … · $ X", y en
     VENTAS REIMPRIMIR de una rendición está apagado ("El comprobante de la rendición todavía no se imprime"): el de
     una venta común diría "Pulseras normales".
   - **Sacar las pulseras de lo vendido** (lo dijo el usuario): `comprobante_entradas_pdf.dart:216` ("Pulseras
     normales: N") y `:227` ("devolvieron las entradas y pulseras"). VENTAS ya pregunta solo "¿Devolvieron las
     entradas?". **El historial A4** (`historial_entradas_pdf.dart:278`, "devolvieron las entradas y pulseras") está en
     la lista de lo que no se toca (§8): cambiar su texto cambia `firmaDeLasHojas` y una tanda ya impresa con una
     anulada aparecería "sin imprimir". **Preguntarle** si se cambia igual.
   - Los reemplazos en `PapelesDeLaPrueba` y en `test/arneses_sin_base_test.dart` (regla 60: una ventana de prueba no
     escribe la constancia en la carpeta del programa).
2. **Etapa 7, la ventana de prueba y las muestras:** en `tool/venta_entradas_prueba.dart`, el jefe le da 20 a Juan
   en la PC y Carla rinde 15 y devuelve 5 en la tablet, con el caso sin internet de los dos lados (la nube de prueba
   ya sube y baja `entradas_para_rendir`: `_sube` y `ponerDeOtroEquipo`); el recorrido de dos equipos en
   `test/venta_entradas_prueba_test.dart` (rendir dos veces lo mismo da "rindió de más"). Las muestras
   (`tool/venta_entradas_muestra_test.dart --dart-define=salida=build/muestras_para_rendir`, 23 casos de PARA RENDIR,
   DAR, el aviso, RENDIR y VENTAS en PC y celular) **hay que sacarlas de nuevo** (las del 21-nov tienen textos viejos)
   y mandárselas.
3. **Etapa 8, el cierre:**
   - **Las roturas 36 a 61** en `tool/roturas_6.9.3.txt` (una por regla de la sección 9 de la SPEC). Los agentes
     rompieron unas 40 reglas a mano mientras programaban (todas detectadas, y los archivos volvieron a quedar
     iguales), pero **no están en el archivo**.
   - **La regla 61:** ampliar `test/venta_entradas_no_toca_test.dart` para que falle si otro archivo que no sea
     `EntradasLocal` escribe `entradas_para_rendir`.
   - **`tool/verificar_migracion_v82_test.dart`** (no existe; modelo: `tool/verificar_migracion_v81_test.dart`) sobre
     una copia nueva de la base real (`python -I tool/copiar_base_solo_lectura.py`), **de la 80 a la 82** (lo que
     tienen las PCs) y de la 81 a la 82, con la vuelta a la 6.9.2. La app instalada tiene que estar cerrada:
     pedírselo.
   - La suite entera y **una revisión independiente de todo "Entradas para rendir"** (un workflow con tres miradas: la
     plata y las cuentas; sin internet, dos equipos y versiones mezcladas; las pantallas, las llaves y los papeles;
     cada hallazgo con un verificador que intenta refutarlo).
4. **Lo que ya estaba pendiente de la 6.9.3:** las muestras de la caja de entregas (`build/muestras_6.9.3/`: las 8
   juntas partidas, NO CUENTA, la familia hoy de baja, la anulación de una entrega anterior, el TOTAL con la nota) y
   mandárselas; **el recorrido con el mouse** en `tool/venta_entradas_prueba.dart`, ahora también con PARA RENDIR
   (el jefe da, Carla rinde, VENTAS anula una rendición), con `python -I tool/huella_de_la_base.py` antes y después
   (IGUAL) y **el permiso de computer-use: avisarle al celular y esperarlo**; que mire las capturas; y preguntarle
   por "Emitido:" 3 horas antes en otros papeles (`docs/pendientes/horas-corridas-en-otros-papeles.md`).
5. **Para preguntarle, sin frenar nada:**
   - al DAR un número que ya se vendió, el aviso dice "El 1205 ya se le dio a …" (como VENDER desde la 6.9.0); la
     maqueta decía "ya se le vendió a". Se dejó "ya se le dio a" porque sale de `RetiroEntradas.errorTramos`, que usa
     también la entrega;
   - el historial A4 con "pulseras" (punto 1).
6. **Lo que sumó la auditoría del 21/22-nov** (detalle en "La auditoría del 21/22-nov", abajo):
   - **programar:** que `entradas_config` y `sorteos_mesas` lleguen enseguida a la tablet que vende (hoy están en
     `_tablasDeCarga`, cada 30 min; pasarlas a `_tablasDelCobro`, o que VENDER las baje al abrir la caja);
   - **programar:** una prueba de solo lectura sobre una copia nueva de la base que diga, por fiesta, cuántas familias
     quedan en "puede retirar", "debe", "revisar" y "a confirmar" con las cuentas de VENDER (el 18-nov eran 52
     adicionales "a confirmar"), con los nombres a `build/`;
   - opcionales: PRECIOS avisa si la anticipada no es más barata que la General; DAR avisa sin internet; el texto de
     VENDER antes del sorteo; las ventanas `tool/entradas_prueba.dart` y `tool/operadores_prueba.dart` llegan a VENDER
     sin reemplazar `abrirComprobanteDeEntradasProvider` (lo vio el agente de la etapa 6: ya pasaba antes);
   - **preguntarle:** ¿el número del talonario pasa a ser obligatorio en cada venta?; ¿el recargo por transferencia
     queda fijo para quien vende, y lleva recargo o va en 0? (pregunta 2 de la SPEC de la venta, sin contestar);
     ¿cómo recibe el comprador el comprobante cuando se vende desde la tablet (ahí se abre "Compartir")?; ¿se vuelve
     a poder sacar el papel del cierre de entradas después de LISTO?
7. **Publicar, cuando el usuario lo diga y con él presente** (ver "Al publicar"): **los dos SQL antes de instalar**,
   y **no dar entradas para rendir hasta que todos los equipos que venden tengan la 6.9.3** (una 6.9.x no conoce los
   bloques y vendería sus números).

### Etapa 6, los papeles (22-nov)

Programada por un agente y revisada por otros que no escribían (dos miradas: lo que dice cada papel y el cableado con
las pruebas; 4 hallazgos chicos, todos arreglados con su test; una segunda vuelta no encontró nada). Los tests de
entradas y `flutter analyze` sobre lo tocado, en verde.
- **La constancia "ENTRADAS PARA RENDIR"** (`pdf/para_rendir_pdf.dart`, `ConstanciaParaRendirPdf`,
  `DatosDeLaConstancia`; `abrirConstanciaParaRendirProvider` en `pdf/papeles_de_entradas.dart`): **una A4 con dos copias
  de media hoja**, PARA QUIEN LAS LLEVA y PARA LA OFICINA, con la línea de corte punteada. Cada copia: la fiesta y su
  fecha, "Se lleva: … (de afuera / alumno de la fiesta, 5° A)", el contacto, "Entradas: 20 anticipadas · del 1201 al
  1220 · sin pulseras" (o generales, según el precio congelado; hasta dos tramos), "Precio: $ 8.000 cada una (precio del
  20/11, queda fijo)", lo que rinde si las vende todas (`ParaRendir.renglon(b, b.cantidad)`, la misma cuenta de RENDIR),
  quién se las dio y cuándo, la nota (cortada a 240 letras con "...": una nota enorme no puede dejar afuera la firma) y
  firma y aclaración en las dos. **Reimpresa** dice REIMPRESA y "Hoy, 22/11: vendió · devolvió · no volvieron · le
  quedan" (con el día: "Hoy" solo se leía como el día en que se las dieron). Sale sola después de DAR (solo si se
  guardó) y con CONSTANCIA en cada bloque; `kConstanciaTodaviaNo` ya no existe. Si el papel falla, lo dado queda y lo
  dice sin asustar.
- **El comprobante de la rendición:** `ComprobanteEntradasPdf` con `DatosDelComprobante.rendicion`
  (`RendicionDelComprobante.alRendir` y `.reimpresa`): "RENDICIÓN DE ENTRADAS · N° 0007", "Recibió" (quien cobró) y
  "Rinde", "Se llevó 20 (1201 al 1220) el 20/11 · vendió 15 · devolvió 5 (1216 al 1220) · le quedan 0"
  (`lineaDeLaRendicion`), el renglón con "· precio fijo", TOTAL, cómo pagó y el vuelto; sin Talonario ni pulseras.
  **VENDER lo abre después de rendir con venta** (sin venta, "Devolución guardada" y nada más) y el aviso tiene VER EL
  COMPROBANTE (la COPIA es fiel a ese acto: lo guarda `_Rendida`, no se relee). **VENTAS → REIMPRIMIR de una
  rendición** saca la COPIA con lo seguro: se llevó, "vendió N en esta rendición" y "hoy, dd/mm, le quedan N"; sin el
  bloque bajado, sin ese renglón; anulada, con ANULADA y "las N dejaron de contar como vendidas". Archivo
  `Rendicion_0007_<nombre>.pdf`.
- **Sin pulseras en lo vendido:** "Pulseras normales: N" pasó a "Entradas: N" y la anulación dice "devolvieron las
  entradas". **El historial A4 no se tocó** (sigue "devolvieron las entradas y pulseras"): espera la pregunta del punto 5.
- **Las pruebas:** `test/comprobante_rendicion_test.dart` (regla 59, con la letra de fábrica, palabra por palabra) y
  `test/constancia_para_rendir_test.dart` (las dos copias, cada palabra dentro de su media hoja, la aclaración en las
  dos, con nombre largo, contacto, nota larga y dos tramos); regla 60 en `test/arneses_sin_base_test.dart` (falla si
  una ventana que llega a PARA RENDIR no reemplaza el provider) y en `test/venta_entradas_prueba_test.dart` (llama al
  provider de los dos lados y comprueba que no escriba en la carpeta del programa); las pantallas en
  `para_rendir_pantalla_test`, `vender_entradas_pantalla_test` y `ventas_de_entradas_test`. `PapelesDeLaPrueba` y
  `tool/venta_entradas_muestra_test.dart` reemplazan la constancia. Las roturas de las reglas 59 y 60 se hicieron a mano
  y fallaron como debían; **pasarlas a `tool/roturas_6.9.3.txt` en la etapa 8**.
- **Sin mirar todavía con las letras de la app**: las muestras son de la etapa 7.

### La auditoría del 21/22-nov

El usuario preguntó qué faltaba para "saber que haya quedado todo óptimo para empezar a vender". Un workflow de solo
lectura con cuatro miradas (lo pedido contra lo hecho, la plata, equipos y versiones, pantallas y arranque), un
verificador por mirada que intentó refutar cada hallazgo y un crítico de completitud: 25 confirmados, 4 descartados y
2 del crítico. **Las cuentas están sólidas** (la anticipada hasta la medianoche de Argentina, el descuento sobre la
General, el recargo solo sobre lo transferido, centavos enteros, una anulada no cuenta, la rendición al precio fijo en
una transacción), **las llaves también** (ningún camino guarda sin su llave) y **el motor** (columnas iguales en modelo,
base, motor y SQL; "Todo subido" no miente). Lo nuevo, además de lo del punto 6 de "Lo que falta":
- **Pasos del usuario antes de la primera venta:** aceptar REVISAR LA LISTA en las 5 fiestas ya sorteadas (**se puede
  ya con la 6.9.2**; hasta entonces lo agregado después del sorteo se vende con descuento, y aceptada no se corrige);
  PRECIOS de cada fiesta (sin precio no abre ninguna caja); "Vende entradas" a cada vendedora y que vuelva a entrar con
  su PIN; en cada tablet, fecha y hora automáticas (el reloj del equipo decide el fin de la anticipada; la zona no
  importa: `ArTime` resta 3 horas a la universal) y abrir la app con internet después de PRECIOS y los permisos; el
  talonario físico en tramos, uno por persona; un sobre por fiesta aparte del cajón de cuotas y cerrar la caja de
  entradas antes de darle la plata al jefe, en el mismo equipo; antes del sorteo, la venta va por "Alguien de afuera";
  una primera venta vigilada con él, en la tablet y en la PC.
- **Al publicar:** ningún equipo vende sin la 6.9.3 (una 6.9.2 le vende a quien no pagó su mesa adicional); **en una
  tablet no hay vuelta atrás** (Android no deja instalar una versión más vieja): actualizarla con "Todo subido" y la
  caja cerrada.
- **Descartados:** el talonario de la General que se vende al terminar la anticipada (lo decidió el usuario el 20-nov:
  todo lo vendido va al de las anticipadas); una lectura de ventas que falla (si la base no abre, VENDER falla antes);
  instalar antes de los SQL (ya está en el orden de publicar); preparar la tablet con la cuenta Admin (ya se hace).

### Entradas para rendir: lo programado (21-nov)

- **Cómo se usa** (el ejemplo de Juan): el lunes el jefe, en modo jefe, entra a ENTRADAS de la fiesta → **PARA
  RENDIR** → DAR ENTRADAS PARA RENDIR; elige un alumno de la fiesta o escribe nombre y apellido de alguien de afuera
  (y un contacto, si quiere), cuántas y los números (del 1201 al 1220; hasta dos tramos). **El precio no se escribe:**
  es el de PRECIOS que rige ese día (la anticipada si todavía vale, si no la general) y queda fijo. Desde ahí ninguna
  caja vende esos números ("El 1205 ya se le dio a PÉREZ, JUAN, para rendir (1201 al 1220).") y VENDER no los
  propone. El viernes Carla, con permiso de vender, ve en VENDER **"Entradas para rendir: N personas · RENDIR"**, sin
  plata; Juan vendió 15 y devuelve 5 (la app propone del 1216 al 1220); le cobra con la hoja de siempre (recargo
  apagado) y la plata entra en su caja y en su cierre. Se rinde de a partes; si solo devuelve, no hace falta caja.
  El jefe ve en PARA RENDIR quién tiene qué, desde cuándo y "faltan hasta $X", y puede marcar NO VOLVIERON (con
  motivo) o ANULAR.
- **Los datos** (`8a25140`): la tabla **`entradas_para_rendir`** (v82; solo se agregan renglones: `dio`, `vendio`,
  `devolvio`, `no_volvieron`, `anulo`, este con id fijo `UuidUtils.entradasParaRendirAnulacionId`), el modelo
  `datos/movimiento_para_rendir.dart` (cada renglón se arma validando: números del 1 en adelante, no al revés, que no
  se pisen, del bloque, la cantidad justa), y `EntradasLocal.darParaRendir`, `rendir` (una sola transacción: vuelve a
  contar lo que le queda y guarda la venta con `_venderEn`, que salió del cuerpo de `vender`), `noVolvieron`,
  `anularDeParaRendir` y `paraRendir`. **La plata es una venta común de `entradas_ventas`**: sin familia
  (`contratoAlumnoId` null), a nombre de quien rinde, con un solo renglón "<precio> · para rendir"
  (`MovimientoParaRendir.sufijoDelRenglon`) al precio fijo y sin descuento. "Todo subido" cuenta la tabla. Los dobles
  (`EntradasEnMemoria`, `EntradasDeUnEquipo`) hacen lo mismo que la base: `test/para_rendir_en_los_dobles_test.dart`
  corre los mismos casos contra los tres.
- **El motor y la nube:** la tabla en los mismos 7 lugares que `entradas_entregas` (`_incrementalColumns`, la bajada,
  `_tablasDelCobro`, prioridad 5 para que suba después de su venta, `tablasDeLaPuerta`, `_cleanForSqlite` y
  `_tablasSinRevisarBorrados`). SQL `supabase/migrations/20261121120000_entradas_para_rendir.sql`, **sin correr**: sin
  CHECK, sin claves foráneas, sin índice único, con RLS y los disparadores, fuera de Realtime.
  `test/sync_tablas_v82_test.dart` compara el modelo, la base, el motor y el SQL, y prueba el motor de verdad contra
  una nube de mentira.
- **Las cuentas** (`cuentas/para_rendir.dart`, puras): `ParaRendir.de` (bloques, por persona, totales y avisos: rindió
  de más, bloque anulado con movimientos, un renglón de un bloque que no bajó, números cruzados), `errorAlDar`,
  `errorAlRendir` (si anular un "no volvieron" alcanzaría, lo dice), `errorAlMarcarNoVolvieron`,
  `proponerDevueltos`, `renglon` y `precioParaDar`. En `numeros_de_entradas.dart`: `ocupadosParaRendir`,
  `primeroLibreDesde` y `repetidosConParaRendir`. **Dos talonarios:** la entrega sin cargo no mira los bloques
  (`test/entrega_por_partes_test.dart` lo vigila).
- **Las pantallas:** el botón PARA RENDIR (después de VENTAS, solo con modo jefe y la venta en este equipo; en el
  celular PRECIOS, VENDER, VENTAS y PARA RENDIR van en un menú porque la barra se desbordaba);
  `widgets/para_rendir_screen.dart`, `dar_para_rendir_dialog.dart` (no escribe, sin casilla de pulseras),
  `vender_para_rendir.dart` (el aviso, sin plata), `rendir_entradas_dialog.dart` (no escribe; hoja de abajo en el
  celular) y `para_rendir_comun.dart`. **Doble llave, y la segunda después de la ventana:** `_dar`, `_noVolvieron` y
  `_anularMovimiento` empiezan y terminan con `_frenaSinModoJefe()`; `_rendir` de VENDER con `_frenaSinPermiso()`.
  `_dar` vuelve a leer la fiesta antes de guardar: si con la ventana abierta otro equipo dio o vendió esos números, o
  **cambió el precio** (GENERAL en PRECIOS, o pasó la medianoche del último día de la anticipada), no guarda y lo
  dice. **VENTAS:** el chip "RENDICIÓN · de …"; anular una rendición no pregunta si devolvieron, manda `devueltas:
  false` y dice cuántas vuelven a quedar a su cargo (si rindió de más, las de verdad; si el bloque no bajó todavía,
  "dejan de contar como vendidas"). Una venta sin familia con el renglón " · para rendir" se reconoce como rendición
  aunque su "vendió" no haya bajado (la venta sube antes). **En una venta común, la pregunta es solo "¿Devolvieron las
  entradas?"**. `paraRendirDeLaFiestaProvider` (en `entradas_providers.dart`), y `avisarQueCambioLaVenta` también lo
  invalida. `test/solo_modo_jefe_test.dart` cubre los archivos y guardados nuevos.
- **Las pruebas:** `test/para_rendir_test.dart`, `test/para_rendir_pantalla_test.dart`,
  `test/para_rendir_en_los_dobles_test.dart`, `test/sync_tablas_v82_test.dart`, `test/migracion_v82_test.dart` y lo
  sumado a `entradas_repositorio_test`, `vender_entradas_pantalla_test`, `ventas_de_entradas_test`,
  `cierre_de_entradas_test` (regla 42: la plata entra en el cierre de la caja que cobró) y `entrega_por_partes_test`.

### Lo que no se probó de "Entradas para rendir"

- Con la nube de verdad (el SQL no está corrido) y con dos equipos de verdad.
- Los papeles (no están hechos) y el recorrido con el mouse.
- La v82 sobre una copia de la base real (`tool/verificar_migracion_v82_test.dart` no existe todavía).

### Dónde quedó antes (20-nov-2026, mediodía)

- **VENDER y la entrega en dos partes: programados, probados y guardados** (`436adec`; los pasos 1 a 5 del plan: los
  dos talonarios, PRECIOS nuevo, "VENDER le vende solo lo pagado entero", la entrega en dos partes con la tabla
  `entradas_entregas` y la v81, y VENDER entero). La sesión de la madrugada se había cortado a las 4:27 con VENDER sin
  guardar; el 20-nov a la mañana se revisó y se probó entero (ver "Cómo se probó"). Se le mandaron las **14 capturas
  del recorrido** (`build/capturas_6.9.3/01_…` a `14_…`, fuera de git).
- **"Todo subido" de VENDER: hecho y guardado** (`952900a`). La línea de arriba contaba solo las ventas y decía "Todo
  subido" con una entrega sin subir (lo vio el recorrido; el usuario: "si sube, que suba de verdad"). Ver "La línea
  'Todo subido'", abajo.
- **La caja de entregas en el cierre: programada y probada, guardada al cortar este chat** (pedido del usuario el
  20-nov; maqueta `docs/maqueta_entregas_en_el_cierre_2026-11-20.html`, que aprobó con la **tabla por persona**:
  "si son muchos en simultáneo, conviene"). Ver "La caja de entregas", abajo.
- **Los 8 arreglos de la revisión de la caja de entregas: programados y probados (20-nov, noche)**, con el plan
  aprobado `C:\Users\lover\.claude\plans\sigamos-happy-cocke.md`. Antes de programar, un workflow de solo lectura
  diseñó cada arreglo y un verificador intentó romperlo; el usuario vio cómo quedaba en una maqueta (hoy contra con
  los arreglos) y **eligió que lo entregado a familias hoy de baja vaya en el TOTAL** ("la tabla suma justo"), con
  una línea que dice cuánto es. Lo hecho, en "Los arreglos del 20-nov (noche)", abajo. **El usuario cortó acá**
  ("hacé hasta ventana de prueba y planilla sin la carpeta y ahí guardá contexto"): del plan quedan los pasos de
  "Lo que falta".
- **Plan general de la 6.9.3: 96 %; el 100 % es publicar con él.**

### Lo que faltaba el 20-nov (los pasos 1 a 3, hechos esa noche; el resto pasó a "Lo que falta, en orden (21-nov)")

1. **El arreglo 9, de paso (chico):** `anularParte` (`eventos/services/entregar_parte.dart`) calcula la hora de la
   anulación con `horaDelRenglon` sin mirar las copias de la fila que va a escribir. Con una fila "entregado" cuya
   anulación está a la misma hora o después que la entrega (una 6.9.x atrasada), la copia queda a
   `anulado_at + 1 ms` y la anulación cae **en el mismo milisegundo**: se ordenan por id, al azar, y la mitad de las
   veces se relee "siguen figurando entregadas" (CambioAlgo: "algo cambió, probá de nuevo"). Arreglo: armar las
   copias, correr `ahora` a después de cada `copia.createdAt` y volver a armar las copias con ese `ahora`. Test en
   `test/entregar_parte_test.dart`: la anulación queda **siempre** después de cada copia (no depende del id).
2. **Las roturas:** ya están escritas en `tool/roturas_6.9.3.txt` (la 21 y la 22 reescritas, de la 24 a la 34
   nuevas), **sin correr**: `bash tool/romper_una_regla.sh tool/roturas_6.9.3.txt` (todas tienen que decir "el test
   FALLA"). Sumar la del arreglo 9.
3. **La suite entera** (`bash tool/suite_por_tandas.sh`), si cambió algo después de la del 20-nov a la noche.
4. **Una revisión independiente del cambio** (workflow: buscar fallas + verificador adversarial; el usuario tiene
   ultracode prendido), y arreglar lo confirmado.
5. **Las muestras de la caja** (`tool/venta_entradas_muestra_test.dart` → `build/muestras_6.9.3/`) con los casos
   nuevos: las 8 juntas partidas, NO CUENTA, la familia hoy de baja, la anulación de una entrega anterior y el
   TOTAL de familias con la nota. Mirarlas y mandárselas (todavía no vio la caja programada, solo maquetas).
6. **El recorrido con el mouse** en `tool/venta_entradas_prueba.dart` (Carla entrega → CIERRE DE CAJA del jefe →
   ENTRADAS → IMPRIMIR, y PLANILLA de VENDER), con capturas. **Pide el permiso de computer-use: avisarle al celular
   y esperarlo.** `python -I tool/huella_de_la_base.py` antes y después (tiene que dar IGUAL): desde el 20-nov la
   ventana ya no escribe en la carpeta de PDF ni con IMPRIMIR de la caja ni con PLANILLA.
7. **Que mire las capturas** de VENDER y de la caja de entregas, y diga si algo no le gusta.
8. **Preguntarle** por lo visto de paso en otros papeles ("Emitido:" 3 horas antes, la fecha de Finanzas de
   madrugada): `docs/pendientes/horas-corridas-en-otros-papeles.md`. No se tocó: son de cobros y mora.
9. **Publicar, cuando el usuario lo diga y con él presente** (ver "Al publicar"). Todo va en la misma 6.9.3, sin SQL
   nuevo.

### Los arreglos del 20-nov (noche)

Lo que pidió la revisión independiente (la lista de abajo, "Lo que pidió la revisión"), programado así:

- **La historia de cada parte** (`entrega_por_partes.dart`): `HistoriaDeLaEntrega.de(retiro:, renglones:)` da, por
  parte, todas las novedades (`NovedadDeLaParte`: momento, acción, renglón o fila) en el orden en que decide
  `EstadoDeLaEntrega`, con las mismas reglas (reflejos, relojes corridos). **No decide nada: lo último de cada
  historia es lo que dice el estado** (un test lo compara en 10 casos). Se sacaron a funciones `_validos`,
  `_novedadesDe` y `_NovedadesDeLaFila.leer` (que además devuelve la hora cruda de la anulación de la fila y si es
  reflejo); los 95 tests de la entrega pasaron sin tocarlos. `EstadoDeLaEntrega.algoRecibido` (alguna parte con
  cantidad) y `ResumenPorPartes.familiasConUnaSolaParte` (**required**, contado familia por familia).
- **La caja** (`caja_de_entregas.dart`, reescrita): cada entrega lleva `lasPulseras`/`lasGenerales`
  (`ComoQuedoLaParte`: sigue, **anulada** con hora/quién/motivo, o **reemplazada**: otra entrega de la misma parte
  vino después, con hora y quién). Sale de la historia: si le sigue una anulación, anulada; si le sigue otra
  entrega, "NO CUENTA". La entrega de las 8 juntas de la fila va con las partes donde quedó su novedad (las dos, una
  o ninguna). **El recorte:** en cada parte, si lo primero que sigue a la entrega de la fila (saltando anulaciones)
  es su copia (`kCopiaDeLaFila`, mismo `entregadoPor`, cantidad y `retiroNombre`), esa novedad de la fila se saca de
  la historia de la caja (caso M1: con relojes, la fila volvía a su hora y aparecía dos veces). `EntregaDeLaCaja.estado(hora)`
  es lo único que leen la pantalla y el papel (`LineaDeLaEntrega` con `TonoDeLaLinea`).
- **Las anulaciones** se cuentan **por acto** (lo que se anuló junto, misma hora y mismo quién: las dos partes, o
  las copias de una anulación de la fila, una por parte, es **una**) más la que guarda la fila de una 6.9.x, salvo
  que sea reflejo o tenga su copia (`_esCopiaDeLaAnulacion`: el id de las copias a su propia hora, quién y motivo, a
  la hora de la fila o después). La que no tumba ninguna entrega de la lista va a `anulacionesAnteriores` y se ve
  en el recuadro "ANULACIONES DE UNA ENTREGA ANTERIOR" (y al final del papel, sin `soloDe`).
- **Los totales** (`pulserasDeLasFilas`, `generalesDeLasFilas`, `familiasConAlgo`; las bajas en `pulserasDeBaja`,
  `generalesDeBaja`, `familiasDeBaja`, `textoDeLasBajas`; `familiasEnDosFilas` y `notaDeLasFamilias`). **La
  conciliación**, en cada caso: filas − bajas = la tarjeta de arriba (pulseras, generales, y familias =
  `familiasConTodo + familiasConUnaSolaParte`). Una familia cuenta solo si lo que cuenta tiene cantidad (las 8
  juntas de una familia de 8 o más llevan generales 0).
- **La pantalla** (`entregas_del_cierre.dart`): TOTAL de familias con la clave `cierre_entregas_total_familias`,
  debajo `cierre_entregas_bajas` y `cierre_entregas_nota_familias`; en el detalle, "Qué" y "Cant." con `Text.rich`
  (partida, se tacha solo la parte que no cuenta: "~~3~~ + 5"), "· hoy de baja", ANULADA en rojo en lugar de quién
  retiró (como antes) y **NO CUENTA en naranja debajo de quién retiró, que sigue a la vista en gris** (ese material
  salió y el jefe tiene que saber quién lo tiene); el recuadro `cierre_entregas_anulaciones_anteriores`.
- **El papel** (`entregas_sin_cargo_pdf.dart`): lo mismo en la celda (con `AltoLibre`), "(hoy de baja)", la línea
  de las bajas en el encabezado, "· N que no cuentan" en el título de cada persona, la tabla de anulaciones
  anteriores al final, y **"Impreso el" con `ArTime.nowUtc()`** (salía 3 horas antes; `generada` es un instante).
- **La ventana de prueba y la planilla** (arreglo 6): `PapelesDeLaPrueba` reemplaza `imprimirEntregasSinCargoProvider`
  y el provider nuevo **`imprimirPlanillaDeEntregaProvider`** (`common/services/imprimir_planilla_de_entrega.dart`),
  que ahora usan PLANILLA de VENDER y la impresora de la entrega en lugar de llamar a `PdfService` directo; guardan
  en `build/venta_entradas_prueba` (`entregasSinCargo`, `planillas`). `entradas_prueba.dart` y
  `operadores_prueba.dart` reemplazan la planilla por una que no sale. `test/arneses_sin_base_test.dart`: toda
  ventana que muestre el cierre o la entrega reemplaza su papel (`reemplazosDelCierre(` cuenta solo como llamada) y
  ninguna nombra `PdfService.generarEntregasSinCargo` ni `generarPlanillaEntrega`; `test/venta_entradas_prueba_test.dart`
  comprueba que IMPRIMIR del cierre queda en la prueba (antes de tocar, que el provider no sea el de la app).
- **Probado:** `test/caja_de_entregas_test.dart` (42: los 10 de antes, 11 de conciliación, 10 del contrato de la
  historia y 11 de los arreglos), `test/entregas_del_cierre_test.dart` y `test/entregas_sin_cargo_pdf_test.dart` (20),
  `test/arneses_sin_base_test.dart` y `test/venta_entradas_prueba_test.dart` (24), los de la entrega (95), y la suite
  entera el 20-nov a la noche: **5.797 tests, ninguno falla**. **Sin correr: las roturas.**
- **Quedó en `docs/pendientes/`:** `anular-pisa-anulacion-de-la-6.9.x.md` (anular con esta versión pisa la anulación
  vieja de la fila: se pierde de la historia, lo que cuenta no cambia) y `horas-corridas-en-otros-papeles.md`
  (preguntarle).

### Lo que pidió la revisión (20-nov, hecho a la noche)

1. **Arreglar lo que confirmó la revisión independiente de la caja de entregas** (20-nov, terminó después del commit
   `8d62895`; dos miradas y un verificador que intentó refutar cada hallazgo). **8 reales**, cada uno con su test
   (que falle sin el arreglo) y, si se puede, su rotura en `tool/roturas_6.9.3.txt`:
   1. **El TOTAL de FAMILIAS de la tabla suma dos veces** a la familia que recibió cada parte de una persona distinta
      (lo normal: cada material llega en su tanda). Agregar `familiasConAlgo` en `CajaDeEntregas` (alumnoId
      distintos con algo vigente) y usarlo en el TOTAL, con la clave `cierre_entregas_total_familias`.
   2. **La entrada de "las 8 juntas" de una 6.9.x mira solo las pulseras para saber si sigue**: si una parte sale de
      la fila y la otra de un renglón (relojes distintos, o una tablet sin internet), lo de las personas no suma lo de
      `ResumenPorPartes`. Separar `pulserasVigentes` y `generalesVigentes` (`parte.deLaFila && parte.entregada`), que
      `_persona` sume cada material con lo suyo, y tachar solo la parte que ya no sigue.
   3. **Una anulación de una 6.9.x desaparece** cuando después se volvió a entregar (la fila queda "entregado" con su
      `anuladoAt`). Contarla siempre que `f.anuladoAt != null` y no haya un renglón de anulación con la misma hora
      (reflejo o copia), y mostrar "Anulación de una entrega anterior" con hora, quién y motivo.
   4. **El TOTAL suma lo entregado a familias hoy de baja y la tarjeta de arriba no**: marcar la baja en
      `EntregaDeLaCaja`, dejar lo de las bajas fuera del TOTAL y decirlo en una línea debajo ("incluye N pulseras de
      familias hoy de baja", o "fuera del total").
   5. **"N con una sola parte" puede dar negativo** (familias de 8 o más con cena no llevan generales): contarlo por
      familia, `algoEntregado && !todoEntregado`, en vez de restar.
   6. **La ventana de prueba `tool/venta_entradas_prueba.dart` escribe en la carpeta de PDF del programa instalado**
      si se toca IMPRIMIR en la caja de entregas: reemplazar `imprimirEntregasSinCargoProvider` en `PapelesDeLaPrueba`
      (que guarde en la carpeta de la prueba, como los otros papeles) y sumar a `test/arneses_sin_base_test.dart` que
      toda ventana con el cierre lo reemplace. **Antes del recorrido con el mouse.**
   7. **Una entrega que quedó sin efecto sin anulación** (otra entrega de la misma parte después, dos equipos sin
      internet) sale tachada sin motivo en la pantalla, y en el papel como válida: agregar `reemplazadaAt` y
      `reemplazadaPor` y mostrar "NO CUENTA: se volvió a entregar el … por …" en la pantalla y en el PDF.
   8. **"Impreso el" del PDF sale 3 horas antes**: `ArTime.formatFechaHora` ya pasa a la hora de Argentina y se le
      daba `ArTime.nowAr()`. Usar `ArTime.nowUtc()` y dejar escrito que `generada` es un instante.

   Descartado: ninguno de los 9 hallazgos (los dos de la pantalla repetían 1 y 4).

### La línea "Todo subido" (`952900a`)

- Cuenta **las ventas, las entregas y los cambios de la caja** que esperan subir (`PendientesDeEntradas`,
  `cuentas/linea_de_subida.dart`): "Sin internet · 1 venta, 1 entrega y 1 cambio por subir"; "Todo subido" solo sin
  nada en la cola.
- Las entregas van **por familia** (`EntradasEntregasRepository.familiasSinSubir`: las dos partes y la fila de la
  entrega son una sola); los cambios, `EntradasDeLaCaja.cambiosSinSubir` (cajas, anulaciones, verificaciones, precios).
- Se vuelve a contar al guardar y con cada `pendingStream` del motor.
- Probado con sus tests, 3 roturas (18 a 20 de `tool/roturas_6.9.3.txt`) y una revisión independiente: de 5
  hallazgos, 1 real (la ventana de prueba no lo mostraba; arreglado con `_PartesDeUnLado`).
- Ojo: **en la nube de verdad las entregas no pueden subir hasta correr el SQL de `entradas_entregas`** al publicar;
  hasta entonces la línea dice que hay entregas por subir, y es correcto.

### La caja de entregas (Cierre de caja → ENTRADAS)

- **Qué eligió el usuario:** ver el detalle de lo entregado sin cargo, **sin contar material** (lo de contar a ciegas
  quedó descartado por ahora), en el cierre de caja, con **una tabla por quién entregó**. Lo puede entregar también el
  operario de caja desde la oficina (la fiesta → ENTRADAS): queda con su nombre y aparece en su renglón.
- **La cuenta** (`eventos/services/caja_de_entregas.dart`, pura): `CajaDeEntregas.de(alumnos, todos, retiros,
  renglones)`. Lo que tiene que llegar y lo entregado sale de `ResumenPorPartes`; si cada entrega sigue en pie, de
  `EstadoDeLaEntrega` (las mismas reglas, también relojes y 6.9.x). Agrupa por quién la anotó (`hechoPor`; vacío →
  "Sin nombre"). Cada entrega: hora, familia, parte (o "las 8 juntas" de una 6.9.x), cantidad, quién retiró,
  números, y si se anuló, cuándo, quién y por qué. Las copias de la fila (`kCopiaDeLaFila`) son la entrega de las 8
  juntas; la fila de la 6.9.x se lista solo si no es el reflejo de un renglón. Lo de las bajas se ve pero no cuenta en
  lo que tiene que llegar.
- **La pantalla** (`cierre_caja/widgets/entregas_del_cierre.dart`), debajo de las cajas de venta, **siempre**
  (aunque no haya cajas ni precio): ENTREGAS SIN CARGO, cuatro números (pulseras, generales, familias con todo,
  anuladas), la tabla por persona con el total, y al tocar a una, su detalle (en el celular, renglones apilados).
  IMPRIMIR (todo) e IMPRIMIR LO DE … (solo esa persona). Solo para mirar: anular sigue en ENTRADAS de la fiesta.
- **El papel** (`common/services/entregas_sin_cargo_pdf.dart`, `PdfService.generarEntregasSinCargo`): A4 parado, por
  persona, sin plata, con las tablas como hijas directas del `MultiPage`.
- **Los datos**: `cajaDeEntregasDeLaFiestaProvider` (`cierre_caja/providers/caja_de_entregas_provider.dart`), que se
  relee con lo que baja y se descarta al dejar de mirarla; `imprimirEntregasSinCargoProvider` para que las pruebas no
  abran nada. **Toda prueba que monte el cierre de ENTRADAS reemplaza ese provider** (`reemplazosDelCierre` lo hace;
  `cajaDeEntregasVacia`).
- **Probado:** `test/caja_de_entregas_test.dart` (10: por persona, anulación, 8 juntas, copias, 6.9.x atrasada, bajas,
  sin nombre), `test/entregas_del_cierre_test.dart` (5: la tabla, el detalle, IMPRIMIR, vacío, celular),
  `test/entregas_sin_cargo_pdf_test.dart` (5: lo que dice, nada fuera de la hoja, solo una persona, 120 familias en
  varias hojas, vacío), `test/cierre_por_sector_test.dart` (aparece aunque no haya precio) y 3 roturas (21 a 23).
  Muestras en `build/muestras_6.9.3/`. **La suite entera, con todo esto: 5.753 tests, ninguno falla.** **Sin SQL ni
  migración.**

### Lo que no se probó

- **Con dos equipos de verdad contra la nube**: la entrega en dos partes entre la PC y una tablet se probó con
  equipos en memoria (`test/entregar_parte_test.dart`) y contra una base SQLite de verdad
  (`test/entregar_parte_en_la_base_test.dart`), no con la nube de verdad: su SQL no está corrido.
- **Una PC con la 6.9.2 leyendo una entrega a medias**: probado en memoria (la fila de `entradas_retiro` se escribe
  solo con las dos partes y una 6.9.x la lee "Retiró"), no con el programa viejo instalado.
- La impresora y la tablet física.
- **La caja de entregas con el mouse** (falta el recorrido; ver "Lo que falta"). En la ventana de prueba la entrega por
  partes es una memoria compartida entre la tablet y la PC: lo de cada equipo sin internet se prueba con los tests.

## Lo que lleva

1. **Los dos talonarios** (`c705474`). Lo que se vende (las anticipadas, `entradas_ventas.numeros`) y lo que se
   entrega sin cargo (las generales de los alumnos) son materiales distintos: ya no se frenan entre sí
   (`NumerosDeEntradas.ocupadosDeLaVenta` y `ocupadosDeLaEntrega`). Cada talonario sigue sin dejar repetir lo suyo, y
   en VENTAS el aviso "revisar" sale para dos ventas o dos entregas con el mismo número, no para una de cada una.
   **En la base real no había ninguna entrega todavía** (`entradas_retiro` vacía al 20-nov): no choca con nada guardado.
2. **PRECIOS nuevo** (`f0f5a1a`, `cuentas/eleccion_de_precios.dart`). Arriba "¿Qué se vende ahora? ANTICIPADA ·
   GENERAL". Con la anticipada: su precio, hasta qué día vale (propuesto el día anterior a la fiesta; un día que ya
   pasó no se acepta) y el precio de la General, del que sale el de la mesa adicional y las sillas. Con la General,
   solo su precio. Los porcentajes van siempre con número (vacío no vale 0). Sin SQL: sale de las columnas de
   siempre, así una 6.9.x cobra lo mismo.
3. **VENDER le vende solo lo pagado entero, cosa por cosa** (`1330d10`, `eventos/services/lugares_pagos.dart`). La
   mesa adicional o la silla extra paga entera se le vende aunque la familia deba otra cosa; la que no, "a confirmar:
   falta pagarla en caja". Sale de los pagos, nunca de los campos del contrato. **Lo agregado después del sorteo paga
   el precio del día, sin descuento**, sin cobrar dos veces (se descuentan las sueltas ya compradas y lo comprado de
   más con descuento con la 6.9.0 y la 6.9.1).
4. **La entrega en dos partes** (`7bdf09f`). Las pulseras VIP con cena (el egresado y sus acompañantes) un día y las
   generales que completan la mesa otro. Cada entrega o anulación de una parte es un renglón de
   **`entradas_entregas`**, que solo agrega (v81 local; SQL de la nube sin CHECK, sin clave foránea, sin índice único,
   con RLS y los disparadores de `updated_at`). El estado de cada parte es su último renglón; una entrega de las 8
   juntas hecha con la 6.9.x cuenta como las dos partes. **Con las dos partes se escribe también la fila completa de
   `entradas_retiro`**, para que una 6.9.x, el plano y la planilla vieja vean "Retiró"; **sin internet no la escribe**
   (puede no saber de una anulación que no bajó): la escribe `completarLaFila` cuando vuelve la red. Un solo camino:
   `EntregarParte` (`eventos/services/entregar_parte.dart`), y el único que escribe la tabla es
   `entregar_parte_de_la_app.dart` (`test/entregar_parte_test.dart` lo vigila). Anular una parte o las dos es solo del
   jefe, con motivo (doble llave). Los números de las generales son opcionales.
5. **El inicio de Entradas: un solo VENDER** con "Vende entradas" (y la tarjeta entera abre VENDER), solo en un equipo
   con la base; en la web, la entrega de siempre.
6. **VENDER entero** (`entradas/widgets/vender_entradas_screen.dart`, `vender_lista.dart`, `vender_gratis.dart`,
   `vender_a_pagar.dart`; `eventos/widgets/formulario_entrega_parte.dart`, `carteles_de_la_entrega.dart`):
   - la lista con el buscador y el filtro **"Pagó todo: puede retirar · Debe: a caja · Ya retiró · Todos"**, que abre
     en "puede retirar", y **un quinto, "Revisar", que aparece solo si hay alguien en ese grupo** (la ficha no
     coincide con los pagos, sin mesa, mesas que no coinciden, no entran). El plan los ponía con los que no pueden
     retirar: se dejó aparte porque es más claro, y igual no entran en "puede retirar";
   - arriba, el **total de la fiesta**: pulseras VIP y generales, con cuántas se entregaron (`ResumenPorPartes`), y
     **PLANILLA**, una por material;
   - **GRATIS · SE ENTREGA** en dos renglones con ENTREGAR o su ✓, quién y cuándo; las generales con "Vienen con
     número" y el "al" calculado. Si debe: "TODAVÍA NO SE ENTREGA", MANDAR A CAJA, y "pagó todo: ya podés entregar"
     cuando el pago baja;
   - **A PAGAR** por mesa adicional y por sillas, con o sin descuento, precio c/u, subtotal, total y el talonario de
     las anticipadas con el número que sigue al último de esa caja;
   - la caja se pide una vez; si se cancela, GRATIS sirve igual y A PAGAR muestra ABRIR LA CAJA.
7. **"Todo subido" de VENDER** (`952900a`) y **la caja de entregas en el cierre** (`8d62895`, `c139ca3`, `ca149c0`).
8. **Entradas para rendir** (21-nov, etapas 2 a 5 de 9; v82 y un SQL nuevo): ver "Entradas para rendir: lo
   programado", en "Para retomar en otro chat".

## Cómo se probó (20-nov)

- `flutter analyze`: ningún error en lo tocado.
- **Dos revisiones del código contra el plan** (solo lectura): cada punto hecho, nada a medias, sin código colgado.
- **La suite entera** (`bash tool/suite_por_tandas.sh`): **5.700 tests, ninguno falla.**
- **Test nuevo contra una base SQLite de verdad** (`test/entregar_parte_en_la_base_test.dart`, 8 de 8): las pulseras
  un día y las generales otro con su entrada en la cola, la fila completa en la misma transacción, sin internet sin
  fila y `completarLaFila` al volver la red, las generales sin número, una entrega de la 6.9.x como dos partes, anular
  una parte, sin modo jefe nada, y guardar todo o nada (con la cola rota no queda ni el renglón ni la fila).
- **Roturas a propósito** (`bash tool/romper_una_regla.sh tool/roturas_6.9.3.txt`): **las 10 detectadas** (quien debe
  retira; el filtro; la adicional no paga; cobrar dos veces; la fila con una parte; anular sin jefe; el porcentaje
  vacío; el día pasado; un talonario frena al otro; otro archivo escribe la tabla). La guarda de afuera de la fila
  completa (`_laFilaAlDia`) es una capa más: la que vigila el test es la de `filaCompleta`.
- **La migración v81 sobre una copia de la base real** (`python -I tool/copiar_base_solo_lectura.py` y
  `tool/verificar_migracion_v81_test.dart`): todas las tablas iguales, `entradas_entregas` nueva y vacía, el esquema
  de lo que existía igual, vuelve a la 80 y otra vez a la 81 sin perder nada, y la base real con el mismo SHA-256.
- **Las muestras** (`build/muestras_6.9.3/`, fuera de git): 69 tests, PNG de cada caso en PC y celular.
- **Una revisión independiente** (un workflow: tres revisores, la plata, sin internet y entre equipos, y las
  pantallas y las llaves; cada hallazgo, verificado por otro agente que intentó refutarlo). Encontró 9; **5 reales**,
  arreglados con su test, que falla con el código de antes (comprobado sacando el arreglo y volviéndolo a poner):
  1. **A PAGAR le vendía a una familia que debía algo y no tenía mesa** (o las mesas no coincidían, o no entraban):
     en `RetiroEntradas.bloqueo` la deuda va primero y tapaba esos frenos. Ahora A PAGAR usa
     **`RetiroEntradas.bloqueoDeLaVenta`** (lo mismo sin la deuda), en VENDER, en la entrega de ENTRADAS y en el
     diálogo (que usa el suyo solo cuando el que recibe dice "debe"). Lo encontraron dos revisores.
  2. **Relojes distintos con una 6.9.x de por medio** (`_NovedadesDeLaFila.de`): lo que el estado de la fila da
     como último tiraba la otra hora. Si lo hizo una 6.9.x (no es reflejo de un renglón), ahora va un milisegundo
     después de la otra; si es el reflejo de un renglón, mandan los renglones. **La propuesta del revisor se ajustó**:
     tal cual, una anulación de una 6.9.x adelantada anulaba una parte que esta versión había vuelto a entregar.
  3. **Se podían dar 9 sin cargo** si cambiaban los acompañantes entre una parte y la otra.
     `EntregaPorPartes.frenoPorLaOtraParte` lo frena en el servicio y en las dos pantallas ("Pendiente" y "Pedile
     al jefe que lo revise desde ENTRADAS de la fiesta"); si la otra se llevó de menos, se entrega igual.
  4. **VENDER perdía un pago que bajaba con el cartel de una entrega abierto** (estaba "ocupado" y tiraba el
     aviso): ahora lo anota y relee al terminar, y el cartel ya no cuenta como ocupado.
  5. **En un celular de 360 px, "Alguien de afuera" se salía 30 px**: el descuento va en su propio renglón.

  Descartados, con el motivo: VENDER guarda con el pedido de cuando se abrió el cobro (es igual desde la 6.9.0 y
  en la barra; la carrera es la de trabajar sin internet, y la cubre la anulación del jefe); una familia que pagó
  todo con un concepto sin "mesa" queda con la adicional "a confirmar" (lo pagado sale de los pagos por concepto, a
  propósito, y el cobro de la app siempre nombra la mesa); dos equipos sin internet entregando la misma parte a la
  misma familia (sin internet la entrega pregunta antes y pide no entregarle desde otro equipo; la 6.9.2 hacía
  lo mismo o peor, y detectarlo sería una mejora nueva).
- **Después de los arreglos:** la suite entera, **5.724 tests, ninguno falla**; `flutter analyze` sin errores; y las
  roturas de `tool/roturas_6.9.3.txt`, **16 de 16 detectadas** (con las de los arreglos). La rotura de
  `_lugaresDe` de la entrega de ENTRADAS no se ve en pantalla (el diálogo ya oculta lo de los lugares con la regla
  nueva): es una capa más y salió de la lista.
- **El recorrido con el mouse** en `tool/venta_entradas_prueba.dart` (la tablet de Carla y la PC del jefe), con la
  huella de la base IGUAL antes y después: PRECIOS con la anticipada; abrir la caja; la lista con el filtro; las
  pulseras de ACOSTA (el jefe las ve al instante); CORTAR INTERNET y las generales con número (pregunta antes y avisa
  "Entregado, pero todavía no subió"); A PAGAR de su mesa adicional, del 101 al 108, en efectivo (comprobante en
  PDF; el jefe ve "compró 8"); PÉREZ debe: no se le entrega, MANDAR A CAJA, la otra caja le cobra y salta "pagó todo:
  ya podés entregar"; y el jefe anula solo las generales de ACOSTA con motivo, y Carla la ve otra vez en "puede
  retirar" con las pulseras ✓. **En la ventana de prueba la entrega por partes es una sola memoria compartida** entre
  los dos lados: sin internet igual cruza, así que lo de cada equipo sin internet se probó con los tests, no ahí.

## Al publicar (con el usuario presente, cuando lo diga)

1. Foto de la mora "antes de 6.9.3" (`supabase/mora_fotos.sql`) y comparar con la de "después de 6.9.2".
2. Repetir la migración sobre una copia nueva de la base, **de la 80 a la 82** (`tool/verificar_migracion_v82_test.dart`),
   si pasaron días.
3. **Los dos SQL, `entradas_entregas` y `entradas_para_rendir`**, con su OK en el momento, antes de instalar; los conteos de antes y después
   iguales, y probar que un anónimo no ve ni escribe nada.
4. Versión `6.9.3+78`, el instalador por pasos (ver el de la 6.9.2) y el APK firmado.
5. Antes de subir, lo agregado desde `v6.9.2` comparado con los nombres de una copia de la base (el repo es público).
6. Tag `v6.9.3`, release "Junior Eventos 6.9.3" con el Setup y el APK, novedades "Actualizaciones y estabilidad", y
   la web.
7. **Todas las PCs y las tablets con la 6.9.3 antes de usar PRECIOS nuevo, entregar por partes o dar entradas para
   rendir** (una 6.9.x no conoce los bloques y vendería sus números): una 6.9.x muestra
   una entrega a medias como "Pendiente" y junta los talonarios. Volver atrás: reinstalar la 6.9.2 sobre la misma
   base (la tabla nueva queda y no molesta).
8. Foto de la mora "después de 6.9.3".

**El locutor** (`docs/SPEC_locutor_2026-11-18.md`, en pausa desde el 18-nov) **pasa a la v83**: la v81 es de la
entrega en dos partes y la v82 de las entradas para rendir.
