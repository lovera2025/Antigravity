# CONTEXTO — la 6.9.3: VENDER con la entrega adentro, la entrega en dos partes y PRECIOS nuevo

**Estado (20-nov-2026): programada y probada en el sandbox, SIN PUBLICAR.** La versión del programa sigue en
`6.9.2+77`; al publicar pasa a `6.9.3+78` (`pubspec.yaml` y `installer/junior_eventos_setup.iss`), con las novedades
**"Actualizaciones y estabilidad"** (decisión del usuario, 20-nov). Lleva **un SQL en la nube, solo de agregar, sin
correr** (`supabase/migrations/20261120120000_entradas_entregas.sql`) y **una migración en las PCs, la v81, que solo
crea una tabla**.

Planes aprobados: el de la versión, `C:\Users\lover\.claude\plans\cucha-tema-permisos-de-resilient-codd.md` (20-nov,
madrugada), y el de comprobar y probar, `C:\Users\lover\.claude\plans\hay-que-segur-chequear-synthetic-abelson.md`
(20-nov, mañana). Sale del audio 6 del jefe: "estas que estamos haciendo son las anticipadas, las ventas al público;
me tienen que llegar las pulseras para los egresados y acompañantes y las entradas para ellos".

## Para retomar en otro chat

### Dónde quedó (20-nov-2026, mediodía)

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

### Lo que falta, en orden

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
2. Repetir la migración v81 sobre una copia nueva de la base, si pasaron días.
3. **El SQL de `entradas_entregas`**, con su OK en el momento, antes de instalar; los conteos de antes y después
   iguales, y probar que un anónimo no ve ni escribe nada.
4. Versión `6.9.3+78`, el instalador por pasos (ver el de la 6.9.2) y el APK firmado.
5. Antes de subir, lo agregado desde `v6.9.2` comparado con los nombres de una copia de la base (el repo es público).
6. Tag `v6.9.3`, release "Junior Eventos 6.9.3" con el Setup y el APK, novedades "Actualizaciones y estabilidad", y
   la web.
7. **Todas las PCs y las tablets con la 6.9.3 antes de usar PRECIOS nuevo o entregar por partes**: una 6.9.x muestra
   una entrega a medias como "Pendiente" y junta los talonarios. Volver atrás: reinstalar la 6.9.2 sobre la misma
   base (la tabla nueva queda y no molesta).
8. Foto de la mora "después de 6.9.3".

**El locutor** (`docs/SPEC_locutor_2026-11-18.md`, en pausa desde el 18-nov) **pasa a la v82**: la v81 ya es de la
entrega en dos partes.
