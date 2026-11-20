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

### Dónde quedó

- **Programado entero** (los pasos 1 a 5 del plan): los dos talonarios, PRECIOS nuevo, "VENDER le vende solo lo
  pagado entero", la entrega en dos partes (tabla `entradas_entregas`, v81) y el inicio con un solo VENDER y VENDER
  entero (lista con filtro, total de la fiesta, GRATIS en dos renglones, A PAGAR por origen, la caja una vez, la
  planilla por material).
- **La sesión de la madrugada se cortó a las 4:27 con VENDER sin guardar en git.** El 20-nov a la mañana se revisó
  (compilaba, todo lo del plan estaba hecho, nada a medias) y se probó: ver "Cómo se probó", abajo.

- **Probada entera el 20-nov a la mañana** (ver "Cómo se probó") y guardada en git (`436adec`). Se le mandaron las
  14 capturas del recorrido (`build/capturas_6.9.3/01_…` a `14_…`, fuera de git). **Plan general de la 6.9.3: 95 %;
  el 100 % es publicar con él.**

### Lo que falta, en orden

1. **Que el usuario mire las capturas** y diga si algo no le gusta.
2. **Decidir una cosa que se vio en el recorrido** (no es un error de la versión): la línea de arriba de VENDER
   ("Todo subido" / "N ventas subiendo") cuenta solo las ventas. Una entrega hecha sin internet no aparece ahí: la
   avisa el cartel "Entregado, pero todavía no subió" en el momento, pero después la línea dice "Todo subido". Se
   le preguntó si sumarla.
3. **Publicar, cuando el usuario lo diga y con él presente** (ver "Al publicar").

### Lo que no se probó

- **Con dos equipos de verdad contra la nube**: la entrega en dos partes entre la PC y una tablet se probó con
  equipos en memoria (`test/entregar_parte_test.dart`) y contra una base SQLite de verdad
  (`test/entregar_parte_en_la_base_test.dart`), no con la nube de verdad: su SQL no está corrido.
- **Una PC con la 6.9.2 leyendo una entrega a medias**: probado en memoria (la fila de `entradas_retiro` se escribe
  solo con las dos partes y una 6.9.x la lee "Retiró"), no con el programa viejo instalado.
- La impresora y la tablet física.

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
