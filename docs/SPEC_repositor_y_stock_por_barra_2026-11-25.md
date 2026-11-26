# El repositor y el stock por barra (25-nov-2026)

Parte 4 del plan del 25-nov (`C:\Users\lover\.claude\plans\donde-nos-quedamos-porque-inherited-sedgewick-of-b24f55ff-68c4-4d3e-875a-b0916b95685c.md`).
Lo decidió el usuario con la maqueta `docs/maqueta_encargada_iphone_y_repositor_2026-11-25.html`. Va para la Técnica
del 4-dic, que es **sin internet** y con **dos barras**, cada una con su router y su notebook.

## Lo que decidió

- **El jefe carga el stock general** (PRECIOS, como hoy: `barra_precios.stock_inicial`) **y reparte con cuánto
  arranca cada barra**. Lo que no reparte es el **depósito**.
- **El depósito es el límite**: no se repone más de lo que hay. Si entra mercadería, el repositor la anota
  ("Entró mercadería") diciendo de dónde vino.
- El repositor **repone** del depósito a una barra, o **pasa de una barra a otra explicando por qué**. Deja dicho
  cuántas quedan en la barra; si no da la cuenta, **el motivo de las que faltan** (rota, congelada, vencida, se perdió,
  otro) o de dónde salieron las de más.
- **Faltante**: lo que falta y no es una venta, con motivo.
- **"Anotar lo que hay"** en una barra o en el depósito: si no da la cuenta, pide el motivo.
- El aviso de **"Está quedando poco"** lo pone el jefe **para cada barra**.
- **Sin stock no se vende.** El repositor manda **"voy en camino" a la barra que elija**; las cajeras lo ven; al
  reponer, el producto vuelve en verde con la cantidad.
- A las cajeras de esa barra y a la encargada les sale **"Se repusieron…"** (informativo).
- El repositor trabaja con **su celular**: la app si es Android, la página de la notebook si es iPhone.
- Permiso **"Repositor de barra"**: Barra con un **3** en `permisos_operador.barra` (sin SQL).

## Los datos (v83, solo tablas nuevas)

**`barra_stock_barras`** — lo que reparte el jefe. Una fila por fiesta, producto y barra, con **id fijo**
(`UuidUtils.barraStockBarraId(evento, producto, barra)`): si el jefe lo cambia desde dos equipos, escriben la misma
fila (gana la última), como `barra_precios`.
`id, evento_id, producto_id, barra (texto), arranque (int ≥ 0), aviso (int ≥ 0, null = no avisa), activo, hecho_por,
device_id, created_at, updated_at`. Sacarla es `activo = 0`: no se borra.

**`barra_stock_movimientos`** — lo que hace el repositor. **Solo se agregan filas** (ninguna se edita ni se borra):
`id, evento_id, producto_id, tipo, cantidad (int ≥ 0), desde (texto o null), hacia (texto o null), contadas (int o
null), ajuste (int, 0 si dio la cuenta), motivo, nota, conocido (texto o null), avisos_previos (int o null),
responde_a (id o null), hecho_por, device_id, created_at, updated_at`. Un `tipo` que la versión no conoce se ignora.

| tipo | desde → hacia | qué hace |
|---|---|---|
| `entrada` | — → `deposito` | suma `cantidad` al depósito; la nota (de dónde vino) es obligatoria |
| `reposicion` | `deposito` → barra | pasa `cantidad`; como mucho lo que hay en el depósito |
| `traspaso` | barra → otra barra | pasa `cantidad`; la nota (por qué) es obligatoria; como mucho lo que tiene la barra de origen |
| `faltante` | barra o `deposito` → — | resta `cantidad`; el motivo es obligatorio |
| `conteo` | — → barra o `deposito` | "Anotar lo que hay": deja `contadas` y `conocido`; no mueve nada |
| `en_camino` | — → barra | aviso a esa barra; no toca el stock |
| `en_camino_no` | — → barra | "Ya no voy": saca el aviso de `responde_a` |

Una reposición o un traspaso con `contadas` y `conocido` es también un conteo de la barra que recibe ("quedan 71"
después de reponer).

**`ajuste` es solo para el historial** ("faltaban 2", con su motivo, obligatorio si no es 0): el stock no lo suma.

**"Voy en camino" se resuelve contando, no por la hora**: la fila guarda en `avisos_previos` cuántas reposiciones y
traspasos hacia esa barra y ese producto había hecho **ese mismo equipo** (un equipo conoce todas sus filas). Queda en
pie hasta que ese equipo reponga ahí, alguien lo saque ("ya no voy") o una reposición lo conteste (`responde_a`). **Lo
cuenta el repositorio con el equipo que va a guardar**: contado con otro, el aviso nacería ya cumplido. Con varios
avisos a la misma barra y el mismo producto se ve uno, el más nuevo (y a la misma hora, por el id: el mismo en todos los
equipos).

## La cuenta (`lib/features/barra/cuentas/stock_por_barra.dart`, pura)

- **Depósito** = stock general − lo repartido − lo repuesto desde el depósito + entradas − faltantes del depósito.
- **Barra** = arranque + lo que entró (reposiciones y traspasos) − lo que salió (traspasos) − lo vendido en sus cajas
  (sin anuladas) − faltantes.
- Las ventas se le pasan ya filtradas (las cajas de esa noche: el día de operación de la Parte 2) y la barra de cada
  caja sale de su `sede`.
- **Una fiesta sin `barra_stock_barras` sigue como hoy** (stock de la fiesta, avisa y no frena). Con reparto, cada
  barra lleva el suyo y **sin stock no se vende** en esa barra. Un producto sin stock general cargado, o sin reparto en
  esa barra, no se frena.
- Lo que se puede reponer, pasar o descontar lo dice la misma cuenta (`cuantoSePuede…`, `errorAl…`): la pantalla no
  hace otra cuenta al lado.
- **El reparto del jefe** (`errorDelReparto`): no más de lo que hay (también el primer reparto, con lo que ya entró y
  faltó en el depósito); una barra que ya usó parte de su arranque no baja de lo usado; y **un producto ya contado no
  cambia el stock general ni el reparto** (lo que se mueve lo anota el repositor). Una barra que ya vendió, movió,
  contó o recibió un aviso de un producto no sale del reparto, ni mientras haya ventas cuya caja no llegó al equipo
  (`errorAlSacarDelReparto`).

### Cómo cuenta un conteo (lo más delicado: lo encontraron dos revisiones independientes)

La noche del 4-dic no hay internet y cada barra tiene su router: el celular del repositor puede no tener todo cuando
cuenta. **Que no conociera algo no quiere decir que haya pasado después.**

- El conteo guarda en `conocido` una `FotoDeStock` **de toda la fiesta**: la venta más alta que conocía de cada caja
  (`ventasHasta`) y la fila más nueva que conocía de cada equipo (`equiposHasta`: ventas, anulaciones y movimientos).
- Lo de ese lugar = **lo contado + lo que pasó después de contar**. Algo fue **antes de contar** si:
  1. lo conocía, o
  2. es una venta de esa caja con número menor o igual al más alto que conocía (los números de una caja van en orden en
     su tablet, aunque su reloj esté corrido), o
  3. es una fila de un equipo anterior o igual a la última que conocía de él (el orden de un equipo es el de su propio
     reloj), o
  4. **solo si no hay otra forma**, su hora es anterior a la del conteo.
  Una anulación conocida al contar ya estaba hecha, aunque su hora diga después.
- **Un conteo reemplaza a otro solo si sabía que el otro fue antes** (conocía lo de ese equipo hasta ahí) y el otro no
  sabía de él. Los que no se conocen valen los dos y se toma **el que da menos** (mejor frenar que vender lo que no hay).
  **La hora nunca decide entre conteos.** Si un reloj corrido los deja "conociéndose en ronda" y no queda ninguno, valen
  todos (nunca se vuelve a la cuenta sin conteos).
- El arranque y el stock general no van en la foto: un producto ya contado no cambia el reparto.
- Cada regla tiene su prueba en `test/stock_por_barra_test.dart` (grupos "contar lo que hay" y "LA SEGUNDA
  REVISIÓN") y su rotura en `tool/roturas_repositor.txt`.

## Lo que viaja

Las dos tablas van por la central de la barra (`tablasDeLaRed`, avisando con `BarraConLaRed`) y por la nube. El SQL
de la nube (`supabase/migrations/20261125120000_barra_stock.sql`) se corre antes de instalar, con el OK del usuario;
sin CHECK nuevos (los valores los controla la app) y con el trigger de `updated_at`.

## Al juntarlo con la Parte 2 (la barra por noche)

- **La barra de cada caja:** la lista fija `kBarrasDelSalon` (`lib/features/barra/services/barras_del_salon.dart`), y
  para leer una caja, `barraDe(sede)` (null si no es de la lista: las cajas viejas con texto libre). El mapa caja →
  barra de `StockPorBarra` tiene que salir de `barraDe(c.sede)`, y el reparto del jefe ofrecer las barras de
  `kBarrasDelSalon`. `claveDeBarra` sigue para comparar.
- **La noche:** a `StockPorBarra.de` se le pasan `CajasPorDia.de(cajas).delDia(dia)` y `.ventasDelDia(ventas, dia)`,
  con "esta noche" = `DiaDeOperacion.de(ref.read(relojDeLaBarraProvider)())`.
- Lo que viaja por la central y los repositorios (`BarraLocal`, `BarraNube`) se hace sobre lo de esa rama. En la
  página del iPhone, cada persona con su propio `device_id` ("pagina:<operador>"), o un aviso de un repositor lo
  cumpliría otro.
- Las pantallas (REPONER, FALTANTE, STOCK, el reparto en PRECIOS, el bloqueo en VENDER, la página del iPhone) van
  después, con su plan.
