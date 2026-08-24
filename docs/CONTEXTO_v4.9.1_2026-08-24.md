# Junior Eventos v4.9.1 — el chip decía un número y el papel otro

**Fecha:** 2026-08-24
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Sin migración de base.** No cambia ninguna tabla ni ninguna columna. Se puede
reinstalar el build anterior encima.

**Novedades publicadas:** "Estabilidad y mantenimiento." (a pedido, una línea).

---

## De dónde salió

Auditoría de eventos masivos sobre la base de producción: 642 contratos, 2.735
pagos, 13 eventos en planificación, 278 alumnos con mora por $15.702.805. El
analyzer no daba errores y los 425 tests pasaban. Lo que sigue no eran fallas de
compilación sino cuatro lugares donde la app decía algo distinto de lo que hacía.

---

## EL CHIP DE MORA

### Contaba el evento entero y su propio PDF contaba otra cosa

`alumnosConMora` salía de `_alumnos` crudo con `FiltroMora.conMora` fijo:
ignoraba el curso, la búsqueda **y** el filtro de mora que él mismo rotulaba. El
botón PDF que está pegado al chip aplicaba los tres.

Medido en COLEGIO NACIONAL (114 inscriptos, 5 cursos):

| Filtro puesto | La grilla mostraba | El chip decía |
|---|---|---|
| curso "A" | 14 alumnos | 59 · $3.530.504 |
| "Mora no cobrada al pagar" | 18 · $297.788 | 59 · $3.530.504, rotulado con ese filtro |

No hacía falta ni generar el PDF para verlo: el diálogo de confirmación canta el
número correcto, a un centímetro del chip que dice otro.

**Qué se hizo.** La regla de curso+búsqueda estaba escrita tres veces. Ahora es
`cumpleCursoYBusqueda` en `filtro_mora_masivos.dart`, al lado de
`cumpleFiltroMora`, y la comparten la grilla, el chip y la planilla. El "filtro
efectivo" —con el chip en Todos igual se habla de mora— salió a un getter.

Que el chip ignore `_filtroMora` **no** era a propósito; que la grilla con
"Todos" muestre a todos, sí. Por eso la grilla usa `_filtroMora` crudo y el chip
el efectivo.

---

## EL ALUMNO QUE TERMINA DE PAGAR DEBIENDO MORA

### No había ninguna pantalla capaz de cobrarle

Terminar el plan no salda la mora: al cobrar la última cuota sin el interés, el
arrastre queda en ficha (`mora_pendiente_tracked`) y el saldo llega a cero. Nada
en `postCobroTrackedOffset` lo pone en cero — es la fila "Pagar cuota sin mora"
de la tabla de escenarios, que en la última cuota funciona igual que en las
otras.

Con ese estado, antes de esta versión:

| Superficie | Qué hacía |
|---|---|
| Chip MORA y planilla | Lo contaban y lo mandaban a llamar |
| Celda ESTADO DE DEUDA | **LIQUIDADO** en verde, con el tilde de verificado |
| Dos renglones más abajo, misma celda | `Mora pendiente: $1.200` |
| Cobro masivos | Le escondía la mora |
| Registrar pago | *"Este alumno no tiene saldo pendiente"* y no abría |

**Cuántos.** Cero contratos hoy. Pero **73 arrastran $1.014.576** con el plan
abierto, los 13 eventos en planificación tienen 642 alumnos que van a terminar de
pagar antes de su fiesta, y solo 19 contratos están saldados: la ola no pasó
todavía. `RIQUELME, AYLEN PRISCILA` está a un pago — base 9/9 paga, le queda la
mesa de $70.000 y arrastra $1.200.

**Qué se hizo.**

1. La guarda del modal mira saldo **y** mora. La verificación de caja sigue yendo
   antes; la carga de `moraYaCobradaHist` se movió entre las dos.
2. `resolverEstadoUi` gana `planSaldadoConMora` → **"PLAN SALDADO · DEBE MORA"**,
   naranja. El `return liquidado` temprano ganaba antes de mirar la mora.
3. Cobro masivos deja de esconder la mora detrás de `enMora`.

El modal no hizo falta tocarlo: con saldo cero las deudas de base, mesa y sillas
dan cero, `moraPendienteEfectivo` es el tracked, y ya había una condición que
contempla `deudaBaseTotal <= 0.01` para la línea de interés. Al confirmar entra
por la rama "solo mora" de `postCobroTrackedOffset`, que ya estaba testeada.

### Las 33 líneas que Cobro masivos escondía

La línea de mora estaba detrás de `mora.enMora && f.moraPendiente > 0.01`.
`calcular().enMora` mira **solo la próxima cuota impaga**: no ve el arrastre de
cuotas ya liquidadas, no ve las cuotas que la exención salteó, y con saldo cero
da `false` de entrada. La grilla del evento usa `moraPendienteFila > 0.01` a
secas, así que las dos pantallas discrepaban.

Eran **33 alumnos y $380.380** de mora real que una pantalla mostraba y la otra
tapaba. Casos: CABALLERO TOBIAS $55.200, AQUINO ALEJO $54.400, MOLINA BRIAN
$54.250, SANCHEZ LUANA $42.600.

---

## EL COBRO SE GUARDABA DE A PEDAZOS

El confirm hacía un `registrarPago` por línea —cada uno con su propia
transacción— y después dos `actualizarContrato` sueltos, para las mesas y para la
mora. Si algo fallaba en el medio quedaban líneas ya escritas, el cartel decía
*"No se pudo guardar el cobro. Reintentá"*, y **no hay deduplicación en ninguna
parte**: el reintento las volvía a insertar y `recalcularProgresoContrato`
recalcula el saldo desde los pagos, así que la familia terminaba figurando como
que pagó el doble. Es la forma del incidente MONTIEL, que se había cerrado solo
por el lado del doble clic.

**Probabilidad baja, daño alto.** Verificado: `flushBestEffort` se traga todo, así
que la caída de internet **no** dispara el catch. Todo lo que queda dentro del
`try` después de las líneas es SQLite local.

**Qué se hizo.** `registrarPagosLote` mete todas las líneas y el patch del
contrato en una sola transacción. `SyncQueue.enqueue` ya aceptaba un ejecutor, así
que el encolado entra también: la cola tampoco puede quedar con medio cobro. El
recálculo de progreso pasa a correr una vez por cobro en vez de una por línea.

`registrarPago` no se duplicó: los dos comparten `_aplicarLineaPagoEn`, que es la
misma escritura. Lo único que cambia es cuántas líneas entran en la transacción.
`actualizarContrato` ganó un núcleo con ejecutor, igual que
`actualizarContratoFirmadoBulk`.

Se fue la llamada suelta a `reconciliarMesasEstadoContrato`: era redundante —
`recalcularProgresoContrato` termina reconciliando, y ya lo hacía por línea.

---

## "RECAUDADO" NO ERA LO RECAUDADO

`pactado − saldo` es gross del plan antes de descuento y **deja afuera toda la
mora cobrada**: ~$2,4M en los eventos activos, $381.400 solo en COLEGIO NACIONAL.
En el Dashboard esa misma palabra es `SUM(transacciones)`, que sí es caja.

Pasa a **ABONADO DEL PLAN**. El cálculo no se toca y el número no se mueve. El
panel solo lo ve el modo jefe.

---

## LO QUE NO SE TOCÓ

Los controles de caja, a propósito y verificado contra el diff: modo caja sin
sesión abierta, jefe con caja cerrada, atribución por `sesionCajaIdParaCobro`,
bloqueo anti-doble-clic y chequeo de cambio remoto. Cero líneas.

---

## ESTADO

445 tests (eran 425). Analyzer sin errores y sin warnings nuevos: el módulo da
los mismos 60 issues que antes de tocar nada.

**Tests nuevos.** `registrar_pagos_lote_test.dart` corre contra una base SQLite
**temporal** —se redirige el directorio de documentos, igual que hacen los tests
de recibos— así que nunca toca producción: tres de equivalencia que comparan
contrato, pagos y filas de `_sync_queue` entre el camino viejo y el lote, dos de
atomicidad (una falla real a mitad no deja ni una línea ni una entrada de cola, y
el reintento no duplica) y dos de atribución de caja. Más el estado
`planSaldadoConMora`, el cobro de sola mora con saldo cero, y el alcance
compartido del chip y la planilla.

> Un aviso sobre el arnés: los ids de prueba tienen que medir 36 caracteres.
> `SyncQueue.enqueue` descarta cualquier otro, así que con nombres sueltos la cola
> quedaba vacía y su comparación no probaba nada aunque el test pasara. Hay una
> guarda que falla si la cola no se llenó.

---

## FALTA PROBAR EN LA APP

- Filtrar por curso y ver que el chip acompañe: COLEGIO NACIONAL con curso "A"
  tiene que decir **14 · $1.107.804**, y el diálogo del PDF lo mismo.
- Filtro "Mora no cobrada al pagar" sin curso: **18 · $297.788**.
- Cobrar normal en modo jefe y en modo caja.
- Mi Empresa → Cobro masivos: tienen que aparecer las 33 líneas de mora nuevas.
- Panel de jefe: ABONADO DEL PLAN con el mismo número de siempre.

**El modo solo-mora no se ejecutó nunca.** Está razonado y la matemática está
cubierta por tests, pero hoy no hay ni un contrato con saldo cero y mora, así que
ni el arnés ni la app pueden recorrerlo. Se va a ejercitar con el primer caso
real — el candidato es RIQUELME cuando pague la mesa.

**La construcción de las líneas del lote vive dentro del modal** y ningún test la
alcanza. La traducción se revisó campo por campo contra el diff, pero es el
riesgo residual de esta versión.

---

## PENDIENTE PARA OTRA TANDA

**El subtítulo naranja de la grilla usa `calcularDesglose` bruto** mientras la
planilla usa el neto, así que puede nombrar meses ya saldados. Medido: 6
contratos discrepan y en 5 el total operativo es $0, o sea que el bloque ni se
dibuja. El único visible hoy es **ROMERO, THIAGO** — título "Mora pendiente:
$1.400", la grilla dice `C3 (Jun) · C4 (Jul)` y la planilla solo `C4 (Jul)`. El
neto ya está calculado arriba y gratis. El mismo bloque está copiado en
`cobro_masivos_tab.dart`.

**Higiene de `detalle_evento_masivo_screen.dart`** (8.900 líneas): el buscador de
la grilla quedó afuera del matcher compartido de v4.8 —13 nombres con tilde o ñ
de 642 no se encuentran—, `_lazyScrollController` no se dispone, `_setupRealtime`
es un comentario vacío con un campo y un import muertos,
`baja_temporal_desde` se escribe y no lo lee nadie (0 filas lo tienen, ni las 3
bajas actuales), hay cuatro definiciones distintas de "es baja", y tres celdas de
la tabla duplican el subárbol entero para el caso baja —~250 líneas— cuando la
celda MESA ya lo resuelve con `opacity: esBajaTemporal ? 0.55 : 1`.

**Sondas en `test/`**: `query_supabase_id_test`, `verify_supabase_content_test` y
`search_supabase_broad_test` pegan a Supabase en cada `flutter test` y pasan igual
sin traer nada ("Supabase está vacío"). No son tests.
