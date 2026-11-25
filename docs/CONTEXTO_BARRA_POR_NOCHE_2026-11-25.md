# La barra por noche, la madrugada y una central por barra (25-nov-2026)

Parte 2 del plan del 25-nov para la Técnica del 4-dic
(`C:\Users\lover\.claude\plans\donde-nos-quedamos-porque-inherited-sedgewick-of-b24f55ff-68c4-4d3e-875a-b0916b95685c.md`).
Salió de las fotos de BARRA → CAJAS de la Técnica: las cajas de prueba de otros días se sumaban con las de la noche
en TOTAL VENDIDO, DIFERENCIA, STOCK y LO VENDIDO DE LA FIESTA. El usuario pidió separarlo por día de operación, "como
un cierre de caja en su fecha". **Programado y probado en el sandbox, sin publicar.** Sin SQL ni migración: nada se
borra y no hay columnas nuevas.

## Para retomar en otro chat

**Dónde quedó (25-nov, ~16 hs, cortado por el usuario con "guardá contexto"):** la Parte 2 está programada, con sus
tests nuevos en verde, las 27 roturas a propósito atrapadas, la prueba de punta a punta en la ventana de verdad (13
capturas, la huella de la base IGUAL antes y después). En la rama `claude/sleepy-jepsen-bea21a` (worktree
`.claude/worktrees/sleepy-jepsen-bea21a`), que sale de `feature/v4.6-cierre-por-sesiones`. Commits: `995be5b` (todo lo
de la app y sus tests) y el de este cierre (los arreglos de la búsqueda UDP, la ventana de las dos barras, las
roturas, este CONTEXTO y CLAUDE.md). **No se publicó nada ni se subió a GitHub.**

**Lo que sigue, en orden:**
1. ~~La suite entera~~ **hecha: 6.257 tests, 0 fallos** (`bash tool/suite_por_tandas.sh`, 25-nov).
2. **Una revisión independiente** (pedido de la sesión que lanzó esta, por el usuario: "que todo esto no tenga bugs"):
   un subagente que lea el diff de la rama contra `feature/v4.6-cierre-por-sesiones` sin estas conclusiones. Lo que
   encuentre se arregla con su test y su rotura.
3. Juntar esta rama con `feature/v4.6-cierre-por-sesiones` (y la de la tele, que hace otra sesión en paralelo en otros
   archivos) y correr la suite sobre lo junto.
4. La Parte 3 (la página de la encargada en el iPhone, servida por la notebook) y la Parte 4 (el repositor y el stock
   por barra), cada una con su maqueta antes. **La Parte 4 ya la empezó la sesión "Totem pantallas orientación y
   multi-escuela"** con archivos nuevos (`datos/stock_en_la_barra.dart`, `datos/movimiento_de_stock.dart`,
   `cuentas/stock_por_barra.dart`), **la v83** en `local_database.dart` y
   `supabase/migrations/20261125120000_barra_stock.sql`: esta rama no los toca ni usa la v83. Se le contestó cómo leer
   la barra de una caja (`barraDe(sede)`, lista `kBarrasDelSalon`) y la noche (`CajasPorDia.delDia`/`ventasDelDia`,
   "esta noche" = `DiaDeOperacion.de(relojDeLaBarraProvider)`).
5. Con los aparatos de verdad (lo único que el sandbox no ve): las dos notebooks en los dos routers Mercusys, unidos y
   separados; una tablet con la pantalla prendida en LAS CAJAS de madrugada; el vale de madrugada en la TP-POS58.

**Lo que preguntó y se contestó:** nada quedó pendiente de él en esta parte. Para decirle: la fecha de la Técnica en la
copia de la base (1-dic, "Planificación") contra el 4-dic que él dijo.

**Para trabajar en el worktree:** salió con finales de línea CRLF (el repo guarda LF) y eso rompía los tests que leen
el código fuente; se pasaron a LF (contenido igual al repo). Si se vuelve a armar, repetirlo.

**Lo que tiene que saber el usuario:**
- La caja ahora **elige su barra** al abrirse (Barra 1 · Barra 2; la última del equipo viene elegida) y la notebook
  dice de qué barra es antes de PRENDER LA CENTRAL. El texto libre "Dónde está" se fue.
- Una caja de prueba vieja que quedó abierta **no se retoma** esa noche: se abre la de hoy y la vieja sigue en su día
  (se ve tocando su fecha arriba de LAS CAJAS). Nadie la cierra sola: la cierra su cajera desde ese equipo si quiere.
- **Entradas de prueba en la Técnica:** en la copia de la base de esta PC (abierta por última vez el 23-nov a las
  7:37) la Técnica no tiene ninguna venta ni caja de entradas. En la barra sí: 2 cajas de prueba (10 y 11-nov) y 1
  venta, que ahora quedan en sus días. Lo que se haya probado después del 23-nov no está en esa copia. (En esa copia
  la Técnica figura con fecha 1-dic y "Planificación"; él dijo 4-dic: mirar la fecha antes de la fiesta.)

## Lo hecho

**El día de operación** (`lib/features/barra/cuentas/dia_de_operacion.dart`, la única cuenta del día):
- `DiaDeOperacion.de(momento)`: en hora de Argentina, 12 horas antes (`kLaFiestaSigueHasta`), sin la hora. Una caja
  abierta a las 18 del 4-dic es del 4-dic aunque venda hasta las 8 del 5. `deLaCaja` sale de `abierta_at`.
- `CajasPorDia`: las cajas de la fiesta por noche; **cada venta va con su caja** (`diaDeLaVenta`; si su caja todavía
  no llegó, la noche de su hora). `inicial`: el día preferido (el del cierre) si tuvo cajas, esta noche si tiene,
  la última si es "de después" (un reloj corrido), esta noche vacía si es la de la fiesta (así no se ven las de prueba
  antes de abrir la primera), si no la última con cajas.
- `abiertasDeEstaNoche` (el aviso al abrir) y `quedanCajasDeSuNoche` (la fiesta sigue a la vista).

**LAS CAJAS por noche** (jefe y encargada, también en la web; `jefe/cajas_de_la_fiesta.dart`):
- Una noche por vez, con las otras arriba ("Esta noche · Vie 04/12 · 2 cajas", "Vie 20/11 · 1 caja"); mirando otra,
  lo dice en ámbar. Totales, diferencia, LO VENDIDO DE LA FIESTA (el papel: "Las 3 cajas del 4/12") y el stock, de
  esa noche (`CajasDeLaFiesta.delDia` → `NocheDeLaBarra`). Una tarjeta de otra noche dice su fecha (`_horario`), y
  cada tarjeta dice su barra.
- **No deja apagar la pantalla** de la tablet (`PantallaDespierta`, que ahora cuenta cuántas pantallas la piden).
- VENDER: el "Quedan" cuenta solo lo vendido esa noche (`StockDeLaBarra.deLaNoche`).
- BARRA del cierre de caja (`cierre_caja/widgets/sector_barra.dart`): las cajas de la noche del día del cierre, con
  las otras noches para tocar.
- Los vales anulados de la puerta (`recepcion/services/vales_anulados.dart`): solo las cajas de esa noche.

**La madrugada:**
- El vale dice **el día de la fiesta** ("Vie 04/12/2026 - 02:30"), no el del reloj (`ModeloTicket.nocheYHora`).
- La fiesta sigue en la lista de la cajera y de la encargada **mientras queden cajas de su noche abiertas**, aunque
  pase el mediodía (`fiestasQueSiguenProvider`, "Siguen abiertas cajas de esa noche"). En una fiesta que ya pasó no
  se abren cajas nuevas: se retoma la suya o lo dice.
- La central de la notebook **vuelve sola tras un reinicio** la misma noche, la noche de la fiesta o mientras haya
  cajas de esa noche abiertas (`sigueLaNoche`); antes vencía a las 18 horas. Volver sola no cambia "desde cuándo".
- Con dos fiestas en noches seguidas, BARRA abre en **la de esta noche** (`FiestasDelJefe.laDeEstaNoche`): la
  segunda noche abría en la de anoche y la central se prendía para la fiesta equivocada.
- `relojDeLaBarraProvider` (la hora de la barra en un solo lugar): las ventanas de prueba la adelantan.

**Una central por barra** (`lib/features/barra/central/`):
- La barra va en la columna `sede` (`services/barras_del_salon.dart`: "Barra 1", "Barra 2", `barraDe`), y cada equipo
  recuerda la suya (`BarraDelEquipo`).
- La central contesta la búsqueda con su barra y su equipo; la tablet elige la de su barra (`EleccionDeCentral`); si
  la suya no aparece en 10 segundos y otra de la fiesta sí, se engancha a esa (las centrales se pasan todo).
- **Dos centrales de la misma fiesta que se ven se enganchan solas** (`CentralBarra.engancharConOtras`): una sola
  punta se conecta (la de id menor), con el mismo `ClienteDeLaCentral` de las tablets; lo nuevo de sus cajas va a la
  otra y lo de la otra a sus cajas. Una fila solo se reparte si era nueva: no da vueltas ni se repite. Si no se ven,
  cada una sigue sola; se juntan cuando se vuelven a ver (o con internet).
- El panel de la central: "Esta notebook es de la Barra 1 · Barra 2" antes de prenderla, "CENTRAL PRENDIDA · BARRA 1",
  y "Enganchada con la central de Barra 2" o "esta barra trabaja sola".

**Tres arreglos que encontró la prueba de las dos barras** (también para una sola barra):
- **La búsqueda mandaba solo la primera pregunta**: en Windows, `send` devuelve 0 si el socket todavía está mandando
  el anterior, y ese datagrama se perdía. Preguntando a toda la red y a la de cada conexión, salía una sola
  (`mandarDatagrama`, con reintento; también las respuestas).
- **Una ronda de preguntas que fallaba dejaba de buscar para siempre**: ahora sigue en la próxima; y si la búsqueda
  se vuelve a empezar mientras la anterior abría su socket, la anterior se descarta.
- **Cortar a mano** (la dirección escrita, o separar las redes) dejaba la caja "conectada": al volver no mandaba lo
  suyo. Y una conexión rechazada (la notebook apagada) dejaba un error suelto.

## Cómo se probó

- Tests nuevos: `test/dia_de_operacion_test.dart` (el mediodía, la medianoche, el cambio de mes y de año, la zona;
  cada suma con cajas de dos días: totales, diferencia, LO VENDIDO, stock, vale, vales anulados; dos noches
  seguidas; la central que vuelve; la elección de central), `test/barra_por_noche_pantallas_test.dart` (LAS CAJAS,
  VENDER, BARRA del cierre, el inicio de la barra, la pantalla despierta) y `test/dos_barras_con_su_central_test.dart`
  (las dos centrales de verdad por la red de esta PC: separadas, juntas, cortadas y vueltas a juntar, el OK de la
  encargada de una barra a la otra, la tablet que se pasa a la otra central, la notebook que se reinicia).
- **Roturas a propósito:** `bash tool/romper_una_regla.sh tool/roturas_barra_por_noche.txt`, 27 reglas: las 27 las
  atrapa un test.
- **La suite entera: 6.257 tests, 0 fallos** (`bash tool/suite_por_tandas.sh`).
- **La prueba de punta a punta, con el mouse, en la ventana de verdad:** `flutter run -d windows -t
  tool/dos_barras_prueba.dart` (o compilarla con `flutter build windows --debug -t …` y abrir el exe). Pone lado a
  lado la tablet de la Barra 1 (Marta), su notebook, la encargada (Romi, en el wifi de la Barra 1), la tablet de la
  Barra 2 (Sofía) y su notebook, cada una con su barra en memoria y la central de verdad por la red de esta PC; trae
  cajas de prueba del 20/11 cerradas; el reloj es de prueba (viernes 4/12, 23:30) y los botones prenden las dos
  centrales, abren las cajas, venden, juntan y separan las redes, adelantan el reloj y reinician la notebook 1. La
  huella de la base dio **IGUAL** antes y después.
- **Las capturas** (`build/capturas_parte2/`, fuera de git):
  1. La noche de la fiesta sin cajas todavía: "Esta noche · Vie 04/12 · sin cajas", y la prueba del 20/11 aparte.
  2. Las dos centrales prendidas, cada una con su barra; redes separadas: cada tablet con la de su barra, "esta barra
     trabaja sola". En VENDER, "Quedan 24" de cerveza aunque la prueba del 20/11 vendió 8.
  3. Se juntan las redes: "Enganchada con la central de Barra 2 / Barra 1".
  4. CAJAS de la notebook 1: $ 12.000, 2 ventas, 2 cajas (una de cada barra); la prueba del 20/11 ($ 58.000) no suma.
  5. La encargada, en la Barra 1, ve las dos barras.
  6. Tocando "Vie 20/11": sus dos cajas cerradas, con la fecha en la tarjeta.
  7. 01:30 del sábado: una venta queda en la noche del viernes; se reinicia la notebook 1 y su central vuelve sola,
     se vuelve a enganchar y la tablet y la encargada la encuentran.
  8. 13:30 del sábado: la fiesta sigue en la lista de la encargada ("Siguen abiertas cajas de esa noche").
  9. Otro reinicio pasado el mediodía: la central vuelve igual (quedan cajas de esa noche); LAS CAJAS dice en ámbar
     que mira la noche del viernes.
  10. Se separan las redes: "Se cortó el enganche"; la encargada ve $ 24.000 (lo nuevo de la Barra 2 no le llega).
  11. Se juntan otra vez: $ 30.000 y 5 ventas, sin repetir ninguna.
  12. Tocar una fiesta que ya pasó: "no se abren cajas nuevas".
  13. Abrir la caja: el número y "¿En qué barra?", con la última elegida.
- Lo que la ventana muestra distinto de la app (no es de la app): la tablet de la encargada corre en Windows, así
  que ve PRENDER LA CENTRAL (en Android no); "Sin central desde las 15:49" usa la hora de la PC y no la de prueba; el
  encabezado "· hoy / · anoche" de una notebook no se refresca al adelantar el reloj de prueba.
- **Lo que no se pudo ver en la ventana:** el vale en papel (la impresora es de mentira); lo cubre el test "el vale
  de madrugada dice el día de la fiesta". Los routers Mercusys y una tablet Android de verdad: quedan para él.
