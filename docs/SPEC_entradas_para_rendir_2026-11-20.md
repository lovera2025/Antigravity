# SPEC — Entradas para rendir (consignación), adentro de la 6.9.3

**Estado (21-nov-2026): aprobado y en programación, sin publicar.** El usuario vio la maqueta
(`docs/maqueta_entradas_para_rendir_2026-11-20.html`) el 20-nov y dio el OK. La etapa 2 (datos: el modelo, la v82,
`EntradasLocal`, las interfaces y los dobles, con sus tests) está programada, sin commit; de la 3 en adelante, sin
programar. **Con la v82 en el código, no correr la app desde esta carpeta contra la base de verdad.** Plan aprobado:
`C:\Users\lover\.claude\plans\que-sigue-fizzy-thompson.md`.

Sale de una pregunta del usuario (20-nov): "hay veces que se le da y después le rinden, pero no es plata en el momento:
se le entrega a ciertas personas X cantidad de entradas y ellos venden; después de esas entradas se sabe cuánto
vendieron". El diseño salió de una revisión de solo lectura: tres lectores del código, tres diseños con miradas
distintas ("reusar lo que hay", "que no falle", "el que lo usa") y un juez que comprobó en el código cada afirmación.
Ganó "el que lo usa" (18 de 20), con injertos de los otros dos.

## 1. Lo que decidió el usuario (20-nov)

| Pregunta | Respuesta |
|---|---|
| ¿Cuándo? | **Adentro de la 6.9.3**, aunque la atrase |
| ¿A quién se le dan? | **A los dos**: alumnos de la fiesta y gente de afuera |
| ¿Cómo se anota a quién? | **Si es alumno, se elige de la lista; si no, se escribe quién se las lleva** (sin parentesco) |
| ¿A qué precio rinden? | **Al del día en que se las llevan**: el precio queda fijo aunque venza la anticipada |
| ¿Ganan algo? | **Rinden toda la plata**, sin comisión. "Puede ser que haya recompensas": sin regla por ahora |
| ¿Se llevan las pulseras? | **No, solo las entradas** |
| ¿Números del talonario? | **Siempre** |

**El precio no se escribe:** la app toma el de PRECIOS que rige ese día (la anticipada si todavía vale, si no la
general). Lo que se dice "fijo" es el precio, no los números: los números se anotan y **quedan reservados** para esa
persona hasta que rinda o devuelva.

**Las recompensas, a mano:** la lista dice cuántas vendió cada uno; si el jefe quiere premiar con una entrada, la da con
la venta sin cargo que ya existe. Una regla fija (por ejemplo, 1 cada 10) se puede sumar después sin tocar la base.

**La pulsera no se vende** (lo aclaró el usuario el 20-nov, al ver la maqueta): lo que se vende son las entradas
anticipadas, y las pulseras son VIP, para los chicos (llegan aparte, con las generales de los alumnos). Quien le compra
una entrada a quien rinde se lleva **solo la entrada**: no hace falta ningún paso para una pulsera.

## 2. Cómo se usa

- **DAR** (el jefe, en modo jefe, en la PC o en la tablet entrando con su usuario): ENTRADAS de la fiesta → **PARA
  RENDIR** → DAR ENTRADAS PARA RENDIR.
  - **Un alumno de la fiesta** (buscador sobre los alumnos sin baja; el nombre viene del alumno) **o Alguien de afuera**
    (nombre y apellido escritos, y un contacto opcional: teléfono o DNI).
  - La cantidad y los números del talonario (**obligatorios**, del/al con el "al" calculado, hasta dos tramos).
  - El precio de hoy, a la vista y sin poder cambiarlo: "a $X cada una · Entrada anticipada · precio de hoy, queda
    fijo". Sin precio cargado no se puede dar (`kLaFiestaNoTienePrecio`).
  - Una nota opcional. Confirma ("DAR 20 ENTRADAS a …") y sale la **constancia** para firmar.
- **RENDIR** (quien puede vender: la cajera con "Vende entradas" o el jefe): en VENDER, arriba, el aviso **"Entradas
  para rendir: N personas · RENDIR"**, sin ninguna suma de plata. Se busca a la persona; la tarjeta dice "se llevó 20 el
  lun 16-nov · del 1201 al 1220 · Entrada anticipada · le quedan 20". Se carga **Vendió** y **Devuelve sin vender**, con
  los números propuestos (los últimos que todavía tiene) y "Le quedan". "A cobrar: 15 × $X" es la única plata a la vista,
  como en una venta. EFECTIVO / TRANSFERENCIA / MIXTO con la hoja del cobro de siempre (recargo apagado, se puede
  prender), o **GUARDAR LA DEVOLUCIÓN** si solo devuelve (sin caja abierta). Sale el comprobante de la rendición. **Se
  puede rendir de a partes.**
- **Mirar** (el jefe): PARA RENDIR, por persona: se llevó, vendió, devolvió, no volvieron, sin rendir, desde cuándo y
  "faltan hasta $X" (lo máximo que podría deber: puede devolver). Arriba los totales y los avisos.
- **NO VOLVIERON** (el jefe, con motivo): no entra plata y esos números quedan anulados para siempre. Si la persona
  paga una que no volvió, se rinde como vendida.
- **ANULAR** (el jefe, con motivo): un bloque sin movimientos, un "devolvió" o un "no volvieron". **La plata de una
  rendición se anula solo en VENTAS → ANULAR**, como cualquier venta (y si la caja ya cerró, sale como "anulado
  después").
- **Después de la fiesta:** lo que se rinda tarde lo cobra el jefe desde la PC (ENTRADAS de la fiesta → VENDER →
  RENDIR); la tablet solo muestra fiestas pasadas con una caja abierta.

## 3. Datos

**La plata de una rendición es una venta común de `entradas_ventas`, sin columnas nuevas:** `caja_entradas_id` la que
cobra; `contrato_alumno_id` **null siempre** (si llevara la familia, `sueltasPorFamilia` en
`cuentas/lugares_de_la_familia.dart` le descontaría esas entradas); `comprador_nombre` quien rinde; `numeros` null (los
números los lleva el bloque); `hecho_por` quien cobra; un solo renglón
`RenglonEntradas.suelta(nombre: '<nombre_precio> · para rendir', precioLista: <precio congelado>, descuentoPct: 0,
cantidad: vendidas)`. El nombre sigue diciendo "anticipada" (el historial pone "anticip.") y en una 6.9.2 el comprobante
ya dice "para rendir". Con eso la cuentan bien, sin cambiar nada: `CierreDeEntradas` (efectivo esperado, "anulado
después"), VENTAS, "Pago verificado", el historial, CERRAR CAJA a ciegas y una 6.9.2.

**Una tabla nueva, `entradas_para_rendir` (base v82), en la que solo se agregan renglones:**

| Columna | Tipo PC / nube | Qué es |
|---|---|---|
| `id` | TEXT PK / uuid PK | |
| `evento_id` | TEXT NOT NULL / uuid not null | |
| `bloque_id` | TEXT NOT NULL / uuid not null | el `dio` al que pertenece (en el `dio`, su propio id) |
| `que` | TEXT NOT NULL / text | `dio`, `vendio`, `devolvio`, `no_volvieron`, `anulo`. Uno desconocido se conserva y no cuenta |
| `persona_nombre` | TEXT / text | en todos (copia, para mostrar); en `dio`, obligatorio: el del alumno o el escrito |
| `persona_contacto` | TEXT / text | `dio`: teléfono o DNI, opcional |
| `contrato_alumno_id` | TEXT / uuid | `dio`: si es un alumno de la fiesta (solo para mostrar y agrupar) |
| `cantidad` | INTEGER NOT NULL DEFAULT 0 / integer | |
| `numeros` | TEXT / text | `TramoTalonario.aTexto`. `dio`: el bloque; `devolvio`: los que volvieron; `no_volvieron`: opcional; `anulo`: ninguno (los del renglón que anula se leen por `anula_id`) |
| `precio` | REAL / numeric | `dio`: `PrecioDeEntradas.deHoy(config, hoyAr)`, congelado |
| `nombre_precio` | TEXT / text | `dio`: el nombre de la anticipada o de la general |
| `con_pulseras` | INTEGER NOT NULL DEFAULT 0 / integer | **0 siempre** por ahora (el usuario: solo entradas); queda la columna porque después no se puede sumar |
| `venta_id` | TEXT / uuid | `vendio` |
| `caja_entradas_id` | TEXT / uuid | `vendio` / `devolvio` |
| `anula_id` | TEXT / uuid | `anulo` |
| `motivo` | TEXT / text | `no_volvieron` y `anulo`: obligatorio |
| `nota` | TEXT / text | |
| `hecho_por`, `device_id`, `created_at`, `updated_at` | como las demás | |

- Índices `IF NOT EXISTS`, **sin UNIQUE**: `evento_id`, `bloque_id`, `venta_id`, `updated_at`.
- **Los vínculos van en null, nunca en `''`**: en la nube son uuid y un `''` traba la fila.
- **Ids:** `dio`, `vendio`, `devolvio` y `no_volvieron` con `UuidUtils.generate()` (cada uno lo crea un solo equipo en
  un solo acto). `anulo` con id fijo, `UuidUtils.entradasParaRendirAnulacionId(anulaId)` =
  `_uuidDe('entradas_para_rendir_anulo_v1|$anulaId')`, al lado de `entradasAnulacionId`; antes de escribir se mira si ya
  está (como `EntradasLocal.anular`): dos equipos que anulan lo mismo dejan una sola fila.
- **Qué se anula:** `dio` solo sin movimientos vigentes (lo revisa el repositorio dentro de la transacción);
  `devolvio` y `no_volvieron` con `anulo`; `vendio` no: se anula su venta en VENTAS. Nada se edita.
- **Modelo:** `lib/features/entradas/datos/movimiento_para_rendir.dart`, `MovimientoParaRendir` y `QueParaRendir`
  (`deClave` da null si no la conoce); constructores `.dio`, `.vendio`, `.devolvio`, `.noVolvieron`, `.anulo` que
  validan; `fromMap` nunca tira (`lectura_de_filas`); un `quedanSinRendir` mínimo para que el repositorio frene sin
  importar `cuentas/`. Se exporta en `entradas_repositorio.dart`.
- **Interfaces** (`datos/entradas_repositorio.dart`): `EntradasDeLaFiesta.paraRendir(eventoId)`;
  `EntradasDeLaCaja.rendir({caja, bloque, vendidas, devueltas, numerosDevueltos, medio, efectivo, transferencia, recibe,
  recargo, recargoPct, quien})`; `EntradasDelJefe.darParaRendir(...)`, `noVolvieron(...)`, `anularDeParaRendir(...)`.
  Solo `EntradasEnMemoria` y `EntradasDeUnEquipo` los implementan de verdad (`_RepoQueAnota` tiene `noSuchMethod`).
- **`EntradasLocal`:** `tablaParaRendir`, que **no** entra en `tablas` (`test/sync_tablas_v80_test.dart` exige cinco).
  El cuerpo de `vender` pasa a `_venderEn(txn, …)`, que usan `vender` y `rendir`. **`rendir` es una sola transacción:**
  vuelve a contar lo que le queda al bloque (si se pasa, `StateError` y la pantalla dice "cambió algo, revisá"), guarda
  la venta si vendió algo (caja de este equipo y abierta, número `MAX+1`) y el `vendio` y/o el `devolvio`, todo con su
  cola. `cambiosSinSubir` suma la tabla nueva (`PendientesDeEntradas` no cambia).
- **La v82** (la v81 nunca se instaló, pero ya se probó sobre una copia: no se toca): `crearTablasV82`, `_version = 82`,
  el `try` en `_initDb`, la llamada en `_onCreate` y el bloque `if (oldVersion < 82 && newVersion >= 82)`. Una PC en la
  80 salta a la 82 en un arranque, con una sola copia (`antes_de_v82.db`). En `test/migracion_v81_test.dart` (l.346 y
  l.359) se pasa `versionNueva: 81`. **El locutor pasa a la v83.**
- **La nube:** `supabase/migrations/20261121120000_entradas_para_rendir.sql`, con el molde de
  `20261120120000_entradas_entregas.sql`: `-- ROLLBACK`, `create table if not exists`, índices con `updated_at desc`, RLS
  con `_all_authenticated`, los dos disparadores `update_updated_at_column`, los conteos de verificación; sin CHECK, sin
  clave foránea, sin UNIQUE y fuera de Realtime. Se corre antes de instalar, con su OK, junto con el de
  `entradas_entregas`.

## 4. Cuentas puras: `lib/features/entradas/cuentas/para_rendir.dart`

- **`ParaRendir.de({movimientos, ventas, anulaciones})`** → `bloques`, `porPersona`, totales (personas, sin rendir,
  plata que falta, no volvieron) y `avisos`.
- **Toda cuenta mira `que` antes de sumar** (revisión del 20-nov): un `anulo` lleva la cantidad del renglón que anula
  (para que quede escrito) y no lleva números. Los números de un bloque salen de su `dio` y de sus `devolvio` /
  `no_volvieron` vigentes, **nunca de juntar los tramos de todas las filas con ese `bloque_id`**; si no, "números
  cruzados entre dos bloques" vería el bloque contra sí mismo.
- **`BloqueParaRendir`** (uno por `dio`): `vendidas` (los `vendio` cuya venta no está anulada; si la venta todavía no
  bajó, cuenta y marca "plata en camino"); `devueltas` y `noVolvieron` (sin `anulo`); `sinRendir = cantidad − vendidas −
  devueltas − noVolvieron` (si da menos de 0, se muestra 0 y avisa "rindió de más: revisar"); `plataRendida`;
  `plataQueFalta = sinRendir × precio` ("hasta $X"); `plataNoVolvio`; `numerosOcupados = bloque − devueltos vigentes`
  (lo vendido y lo que no volvió sigue ocupado; un bloque anulado no ocupa nada).
- **Avisos** (solo avisan): rindió de más; bloque anulado con movimientos; un renglón de un bloque que todavía no bajó;
  números cruzados entre un bloque y una venta, o entre dos bloques.
- **`porPersona`:** por `contrato_alumno_id` o, sin él, por nombre normalizado; primero quien tiene más sin rendir.
- **Números** (`cuentas/numeros_de_entradas.dart`, todo nuevo, sin cambiar firmas): `ocupadosParaRendir(bloques)` →
  `{'Juan Pérez (para rendir)': tramos}`; VENDER junta `ocupadosDeLaVenta ∪ ocupadosParaRendir` en `_ocupados` y el
  mensaje sale de `RetiroEntradas.errorTramos` ("El 1205 ya se le dio a Juan Pérez (para rendir)"); `primeroLibreDesde`
  para que `_proponerNumero` no proponga uno de un bloque; `repetidosConParaRendir` (los cruces, solo en PARA RENDIR).
  `repetidosDeLaVenta`, el historial PDF y `firmaDeLasHojas` no se tocan. **La entrega sin cargo
  (`EntregaPorPartes.numerosDeOtros`, `ocupadosDeLaEntrega`) no mira los bloques: es el otro talonario.**
- **`errorAlDar`:** sin precio, `kLaFiestaNoTienePrecio`; nombre y apellido (dos palabras) si es de afuera; cantidad de
  1 en adelante; **números obligatorios** con `RetiroEntradas.errorTramos(tramos, generales: cantidad, deOtros:
  ocupadosDeLaVenta ∪ los otros bloques)` (no `NumerosDeEntradas.error`, que acepta sin números).
- **`errorAlRendir`:** `1 ≤ vendidas + devueltas ≤ sinRendir`; los devueltos con números, la cantidad justa y dentro de
  `numerosOcupados` ("El 1230 no es de las que se llevó", "El 1216 ya lo devolvió"); si vendió, caja abierta.
- **`proponerDevueltos(bloque, n)`:** los últimos n números que todavía tiene.
- **`renglon(bloque, vendidas)`:** el renglón con el precio y el nombre congelados. **El precio no se vuelve a leer de
  `ConfigEntradas`**: esa fila se sobrescribe, y GENERAL borra la anticipada.
- Al dar, el precio sale de `PrecioDeEntradas.deHoy(config, hoyAr)` y el nombre de `rigeLaAnticipada`
  (`hoyEnArgentinaProvider`).

## 5. Pantallas y accesos

| Lugar | Quién | Qué |
|---|---|---|
| ENTRADAS de la fiesta (oficina), botón **PARA RENDIR** (`entradas_para_rendir`) después de VENTAS | El jefe | Como `_botonVentas`: prendido con modo jefe y entradas en este equipo; si no, apagado con `kSoloEnModoJefe` o `kEntradasDesdeLaPc`. `_abrirParaRendir` con la llave antes del push. En el mostrador no aparece |
| `widgets/para_rendir_screen.dart` | El jefe | Totales y avisos arriba; lista por persona que se despliega en bloques y movimientos; DAR ENTRADAS PARA RENDIR; por bloque CONSTANCIA, NO VOLVIERON (`pedirMotivo`) y ANULAR (apagado con el motivo si tiene movimientos). Guardados `_dar`, `_noVolvieron`, `_anularMovimiento` con `_frenaSinModoJefe()`. Vacía: "Nadie tiene entradas para rendir" |
| `widgets/dar_para_rendir_dialog.dart` (no escribe) | El jefe | Un alumno de la fiesta / Alguien de afuera; contacto; cantidad; del/al; el precio de hoy fijo; nota; DAR N ENTRADAS con confirmación. **Sin casilla de pulseras** |
| VENDER: `widgets/vender_para_rendir.dart` (aviso) | Quien puede vender | "Entradas para rendir: N personas · RENDIR", **sin plata**, solo si alguien tiene algo sin rendir |
| `widgets/rendir_entradas_dialog.dart` (no escribe; hoja de abajo en el celular) | Ídem | Buscador, tarjeta, Vendió / Devuelve, números propuestos, Le quedan, A cobrar, medios o GUARDAR LA DEVOLUCIÓN |
| VENDER `_rendir` | Ídem | `_frenaSinPermiso()`; ABRIR LA CAJA si vendió y no hay; no corre con `_ocupado`; `pedirCobro` con recargo apagado; `rendir(...)`, `avisarQueCambioLaVenta`, `_cargar` y el comprobante. `_tablasQueMiro`, `_cargar`, `_ocupados` y `_proponerNumero` suman los bloques |
| VENTAS | El jefe y quien vende | Chip "RENDICIÓN · de …"; el anular de una rendición no pregunta "¿Devolvieron…?", dice "Las 15 vuelven a quedar a cargo de … para rendir" y manda **`devueltas: false`**; REIMPRIMIR saca el comprobante de rendición |
| Cierre de caja → ENTRADAS | — | **No se toca**: la plata ya está en la caja como venta |
| `avisarQueCambioLaVenta` | — | también invalida `paraRendirDeLaFiestaProvider` |

**Quién puede qué:** dar, NO VOLVIERON y anular, solo el jefe en modo jefe; rendir, `puedeVenderEntradasProvider`; la
plata que falta, solo el jefe; la web no da ni rinde.

## 6. Papeles

1. **Constancia "ENTRADAS PARA RENDIR"** (`pdf/para_rendir_pdf.dart`, `abrirConstanciaParaRendirProvider`): media A4,
   dos copias (PARA QUIEN LAS LLEVA / PARA LA OFICINA). La fiesta; "Se lleva: Juan Pérez (alumno de la fiesta / de
   afuera)"; "20 entradas anticipadas · del 1201 al 1220 · **sin pulseras**"; "A $X cada una (precio del 16/11, queda
   fijo). Si las vende todas rinde $Y; las que no venda las devuelve. Rinde toda la plata"; quién se las dio; firma y
   aclaración. Reimpresa, muestra cómo está ahora.
2. **Comprobante de la rendición:** el mismo `ComprobanteEntradasPdf` con `DatosDelComprobante.rendicion` opcional:
   "RENDICIÓN DE ENTRADAS · N° 0007", "Recibió: Carla", "Rinde: Juan Pérez", "Se llevó 20 (1201 al 1220) · vendió 15 ·
   devolvió 5 (1216 al 1220) · le quedan 0", **sin "Pulseras normales"**.
3. El historial PDF y el cierre PDF **no cambian**.

La constancia se reemplaza en `PapelesDeLaPrueba.reemplazos` y entra en `test/arneses_sin_base_test.dart`.

## 7. Sin internet y con dos equipos

El motor (`core/services/sync_engine.dart`) suma la tabla como `entradas_entregas`: `_incrementalColumns` con
`updated_at`, `_pullTable` en `_pullFromCloud`, `_tablasDelCobro` (es plata), `getPriority` 5 (la venta, 4, sube
antes), `tablasDeLaPuerta` (la tablet frena números y rinde sin internet), sus columnas en `_cleanForSqlite` y
`_tablasSinRevisarBorrados` ("solo se agregan renglones; anular es otro renglón"). No va en `_tablasAReconciliar`, ni
en `_hijasEnCascada`, ni en las relaciones de `sync_queue.dart`.

- **El jefe da sin internet, o la tablet se preparó antes:** la tablet no ve el bloque y podría vender el 1205; al
  juntarse, el cruce sale en PARA RENDIR. Regla: dar con internet y después "Lista para trabajar sin internet".
- **La tablet rinde sin internet:** venta y renglones en la cola, una sola transacción; VENDER dice "1 venta y 1 cambio
  por subir".
- **Dos equipos rinden el mismo bloque:** "rindió de más: revisar"; el jefe anula una venta en VENTAS.
- **Un `vendio` llega antes que su venta:** cuenta y marca "plata en camino".
- **Dos anulaciones de lo mismo:** id fijo, una sola.
- **Una 6.9.2 mirando:** ve las rendiciones como ventas (su cierre cuadra) pero no frena los números de los bloques.
- **Volver a la 6.9.2:** la tabla queda sin leer; al volver a la 6.9.3 reaparece todo.

## 8. Lo que no se toca

Las columnas de todas las tablas existentes; `VentaEntradas`, `TipoRenglonEntradas`, `PedidoDeEntradas`;
`CierreDeEntradas`, CERRAR CAJA y el cierre de caja; `CajaDeEntregas`, `EntregasDelCierre`, `entradas_entregas`,
`numerosDeOtros`; PRECIOS y `entradas_config`; `LugaresDeLaFamilia`; el historial PDF; la v81 (salvo `versionNueva: 81`);
`EntradasLocal.tablas`; `_tablasAReconciliar`, `_hijasEnCascada`, `sync_queue.dart`; pagos, saldo, mora, COBROS,
contrato y salón. **Lo que alguien debe de entradas para rendir no es deuda del contrato y no frena nada.**

## 9. Reglas, tests y roturas (en `tool/roturas_6.9.3.txt`, desde la 36)

| # | Regla | Test |
|---|---|---|
| 36 | Se rinde al precio y con el nombre del día en que se las llevó, aunque venza la anticipada o el jefe ponga GENERAL | `test/para_rendir_test.dart`, `test/entradas_repositorio_test.dart` |
| 37 | Con la anticipada vigente, queda "Entrada anticipada" con su precio | `test/para_rendir_test.dart` |
| 38 | Sin comisión ni descuento: `descuentoPct` 0, total = vendidas × precio | `test/para_rendir_test.dart` |
| 39 | La venta de la rendición no es de la familia (`contratoAlumnoId` null): A PAGAR no cambia | `test/para_rendir_test.dart` |
| 40 | Rendir es todo o nada (venta, renglones y cola en una transacción) | `test/entradas_repositorio_test.dart` |
| 41 | No se rinde más de lo que le queda: se vuelve a contar dentro de la transacción | `test/entradas_repositorio_test.dart` |
| 42 | La plata entra en el cierre de la caja que cobró (efectivo esperado, "anulado después") | `test/cierre_de_entradas_test.dart` |
| 43 | VENDER no deja vender un número de un bloque | `test/vender_entradas_pantalla_test.dart`, `test/para_rendir_test.dart` |
| 44 | Los devueltos quedan libres; lo vendido y lo que no volvió sigue ocupado; un bloque anulado libera todo | `test/para_rendir_test.dart` |
| 45 | Dos talonarios: el bloque no frena la entrega sin cargo | `test/entrega_por_partes_test.dart` |
| 46 | Al dar: números obligatorios, sin pisar ventas ni otros bloques; nombre y apellido si es de afuera | `test/para_rendir_test.dart` |
| 47 | Lo que se devuelve es de lo que todavía tiene, y no estaba devuelto | `test/para_rendir_test.dart` |
| 48 | Una rendición anulada en VENTAS vuelve a "sin rendir", y el papel no dice "devolvieron las entradas y pulseras" | `test/para_rendir_test.dart`, `test/ventas_de_entradas_test.dart` |
| 49 | Si rindió de más, se avisa y no se esconde | `test/para_rendir_test.dart` |
| 50 | Dar, NO VOLVIERON y anular son solo del modo jefe (doble llave) | `test/solo_modo_jefe_test.dart` (regex y conjuntos ampliados) |
| 51 | Rendir pide el permiso de vender | `test/solo_modo_jefe_test.dart` |
| 52 | PARA RENDIR se abre con su llave | `test/solo_modo_jefe_test.dart` |
| 53 | Quien cobra no ve sumas de plata en el aviso de VENDER | `test/vender_entradas_pantalla_test.dart` |
| 54 | "Todo subido" cuenta la tabla nueva | `test/entradas_repositorio_test.dart` y el de `linea_de_subida` |
| 55 | Anular es otra fila con id fijo; dos veces deja una | `test/entradas_repositorio_test.dart` |
| 56 | Modelo, base, motor y SQL dicen lo mismo (sin CHECK/references/unique; RLS, disparadores, ROLLBACK; fuera de Realtime; en `tablasDeLaPuerta` y `_tablasSinRevisarBorrados`) | `test/sync_tablas_v82_test.dart`, `test/borrados_de_otra_pc_test.dart`, `test/puesta_al_dia_nube_test.dart` |
| 57 | La v82 solo crea (80→82, 81→82, ida y vuelta a la 6.9.2, `antes_de_v82.db`) | `test/migracion_v82_test.dart`, `test/migracion_v81_test.dart`, `tool/verificar_migracion_v82_test.dart` |
| 58 | Un `que` desconocido no le cambia nada a nadie | `test/para_rendir_test.dart` |
| 59 | El comprobante de una rendición dice Recibió/Rinde y no habla de pulseras | test nuevo del comprobante (letra de fábrica) |
| 60 | Las ventanas de prueba no escriben la constancia en la carpeta del programa | `test/arneses_sin_base_test.dart` |
| 61 | Lo de entradas no nombra los pagos de cuota, y la tabla solo la escribe `EntradasLocal`, por `_guardar` | `test/venta_entradas_no_toca_test.dart` |

Sin rotura propia: el recorrido de dos equipos en `test/venta_entradas_prueba_test.dart` (el jefe da en la PC, Carla
rinde en la tablet sin internet, vuelve la red y el jefe ve 0 sin rendir y la plata en la caja de Carla; rendir dos
veces lo mismo da "rindió de más"). Antes: `_sube('entradas_para_rendir')` y el caso en `ponerDeOtroEquipo`.

## 10. Riesgos

- **Una PC o tablet con la 6.9.2 no ve los bloques y puede vender esos números.** Regla en `CLAUDE.md`: no dar entradas
  para rendir hasta que todos los equipos que venden tengan la 6.9.3.
- **Sin el SQL nuevo en la nube**, los renglones quedan trabados en la cola, "Todo subido" no llega y "Lista para
  trabajar sin internet" no termina: los dos SQL se corren antes de instalar.
- Una tablet preparada antes de dar un bloque no lo conoce hasta conectarse.
- Dos rendiciones del mismo bloque sin internet no se pueden evitar: se avisan.
- "Faltan $X" es lo máximo que podría deber, no plata segura.
- Dos personas de afuera con el mismo nombre se juntan en la lista (solo lo que se ve; el contacto las distingue).
- En el celular, la barra de ENTRADAS suma un botón: muestras con "nada se desborda"; si no entra, va a un menú.

## 11. Etapas

1. **La maqueta** y el OK del usuario (antes de programar nada).
2. **Datos**: modelo, id de la anulación, v82, `EntradasLocal`, interfaces y dobles de prueba; tests del repositorio.
3. **Motor y nube**: el motor y el SQL; `sync_tablas_v82_test`.
4. **Cuentas puras**: `para_rendir.dart` y los números; `test/para_rendir_test.dart`.
5. **Pantallas**: PARA RENDIR, DAR, el aviso y RENDIR, VENTAS; `solo_modo_jefe_test` ampliado.
6. **Papeles**: la constancia y el comprobante de la rendición; los reemplazos de las pruebas.
7. **Ventana de prueba y muestras**.
8. **Cierre**: roturas 36 a 61, la suite, una revisión independiente, `verificar_migracion_v82` sobre una copia nueva de
   la base real, documentos (`CLAUDE.md`, el CONTEXTO de la 6.9.3).
9. **Publicar la 6.9.3 con el usuario**: los dos SQL antes de instalar, todas las PCs y tablets con la versión, y recién
   después dar las primeras entradas para rendir.
