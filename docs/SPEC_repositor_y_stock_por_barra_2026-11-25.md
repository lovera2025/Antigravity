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
`id, evento_id, producto_id, tipo, cantidad (int ≥ 0), desde (texto o null), hacia (texto o null), ajuste (int, 0 si
dio la cuenta), contadas (int o null), motivo (texto o null), nota, avisos_previos (int o null), hecho_por, device_id,
created_at, updated_at`.

| tipo | desde → hacia | qué hace |
|---|---|---|
| `entrada` | — → `deposito` | suma `cantidad` al depósito; la nota (de dónde vino) es obligatoria |
| `reposicion` | `deposito` → barra | pasa `cantidad`; como mucho lo que hay en el depósito |
| `traspaso` | barra → otra barra | pasa `cantidad`; la nota (por qué) es obligatoria; como mucho lo que tiene la barra de origen |
| `faltante` | barra o `deposito` → — | resta `cantidad`; el motivo es obligatorio |
| `conteo` | — → barra o `deposito` | "Anotar lo que hay": no mueve nada, deja `ajuste` |
| `en_camino` | — → barra | aviso a esa barra; no toca el stock |

**El ajuste no depende de la hora de ningún equipo.** Cuando el repositor deja dicho cuántas hay (`contadas`), su
equipo calcula en ese momento `ajuste = contadas − la cuenta` y lo guarda **como cantidad**. El stock suma los
ajustes: da lo mismo en qué orden lleguen las filas a cada equipo. Con `ajuste ≠ 0`, el motivo es obligatorio.
(Comparar relojes de equipos distintos está prohibido en este proyecto: ver CLAUDE.md.)

**"Voy en camino" se resuelve contando, no por la hora**: la fila guarda en `avisos_previos` cuántas reposiciones y
traspasos hacia esa barra y ese producto conocía el equipo; queda "en camino" hasta que haya más que esas.

## La cuenta (`lib/features/barra/cuentas/stock_por_barra.dart`, pura)

- **Depósito** = stock general − lo repartido − lo repuesto desde el depósito + entradas − faltantes del depósito
  + ajustes del depósito.
- **Barra** = arranque + lo que entró (reposiciones y traspasos) − lo que salió (traspasos) − lo vendido en sus cajas
  (sin anuladas) − faltantes + ajustes.
- Las ventas se le pasan ya filtradas (las cajas de esa noche: el día de operación de la Parte 2) y la barra de cada
  caja sale de su `sede`.
- **Una fiesta sin `barra_stock_barras` sigue como hoy** (stock de la fiesta, avisa y no frena). Con reparto, cada
  barra lleva el suyo y **sin stock no se vende** en esa barra.
- Lo que se puede reponer, pasar o descontar lo dice la misma cuenta (`cuantoSePuede…`): la pantalla no hace otra
  cuenta al lado.

## Lo que viaja

Las dos tablas van por la central de la barra (`tablasDeLaRed`, avisando con `BarraConLaRed`) y por la nube. El SQL
de la nube (`supabase/migrations/20261125120000_barra_stock.sql`) se corre antes de instalar, con el OK del usuario;
sin CHECK nuevos (los valores los controla la app) y con el trigger de `updated_at`.

## Pendiente de coordinar

- El nombre de cada barra (la Parte 2 lo pone en `sede` con una lista "Barra 1 · Barra 2"): la cuenta recibe el
  nombre tal cual.
- Las pantallas (REPONER, FALTANTE, STOCK, el reparto en PRECIOS, el bloqueo en VENDER, la página del iPhone) van
  después de que la Parte 2 esté en la rama: tocan los mismos archivos.
