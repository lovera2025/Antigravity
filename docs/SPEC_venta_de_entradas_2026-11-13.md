# SPEC — La venta de entradas: su precio, su caja, el comprobante y su cierre

**Archivo:** `docs/SPEC_venta_de_entradas_2026-11-13.md`
**Rama:** `feature/v4.6-cierre-por-sesiones` (hoy en `6.8.0+74`). Versión sugerida: la que siga (6.9.0).
**SQL:** uno nuevo, solo de agregar (cinco tablas). **Migración local:** v80, solo tablas nuevas.
**Revisado contra el código** en `b3ca309` (13-nov, 8:12), solo lectura. No se corrió `flutter test` ni se miró la nube.
**Reemplaza** la sección 8 de `docs/PLAN_MODO_ENTRADAS_2026-10-30.md` ("a revisar cuando se llegue"): lo que sigue manda.

> **Este repo es público.** En esta spec, en los tests, en las muestras y en los mensajes de commit de este trabajo
> **no va ningún nombre de alumno ni de comprador**. Los ejemplos usan familias inventadas (F1, F2…).

El usuario lo pidió el 13-nov: *"ya debemos dejarle lista"*. Hoy el cierre de caja en modo jefe tiene la pestaña
ENTRADAS con un cartel fijo (`SectorEntradasDelCierre`, en `cierre_caja/widgets/sector_barra.dart`): no hay venta de
entradas en la app, y las del 50 % se venden a mano, fuera de todo cierre. **La primera recepción es el 4-dic.**

---

## 1. Qué está decidido, y de dónde sale

Del jefe y del usuario (30-oct y 4-nov, anotado en la sección 8 del plan):

1. **Una caja de venta de entradas por escuela (por fiesta), aparte de la de cuotas**, para saber cuántas se vendieron.
   Una persona tiene esa caja: vende y va anotando.
2. **El precio de la entrada lo ponen ellos**, en un lugar donde se escribe "$X".
3. **Cada venta queda con quién vendió, a quién, cuánto y cómo se pagó.** Nombre y apellido del comprador, obligatorios.
4. Pago en **efectivo, transferencia o mixto**.
5. Al confirmar sale **un comprobante en PDF de media A4**, con las pulseras.
6. **Un historial de ventas** que se imprime en PDF, con la tilde **"Pago verificado"**.
7. **Anular, solo el jefe**, con motivo y con la pregunta de si devolvieron las entradas y pulseras.
8. **Solo la mesa del contrato trae sus 8 entradas sin cargo.** La mesa adicional y las sillas extra pagan el lugar, no
   la entrada: cada entrada de esos lugares **se compra al 50 % de su valor** (regla del 4-nov; la app ya cuenta cuántas
   son por familia: `EntradasDeAlumno.alCincuenta`).
9. También se le vende **a gente de afuera**. "Primero la anticipada y después la general."
10. Los descuentos a mano, **con porcentaje y en 0 de entrada**.
11. **La plata de cada sector no se mezcla** (5-nov, `sector_del_cierre.dart`): COBROS, BARRA y ENTRADAS, cada uno con
    su cierre.

### 1.1 Lo que esta spec decide para no esperar más (cada punto se cambia sin reprogramar, o está marcado)

El jefe todavía no contestó todo. Para que salga, **lo que falta va como un dato que carga el jefe por fiesta**, no
como código:

| Lo que faltaba | Cómo queda | Dónde se cambia |
|---|---|---|
| El precio de la entrada | Sin precio cargado, esa fiesta **no se puede vender** y lo dice | PRECIOS, modo jefe |
| Anticipada y general | Un precio de anticipada con su "hasta qué día", **opcional**. Vacío: un solo precio | PRECIOS |
| El 50 % de los lugares adicionales | Viene en **50**, y es un número del jefe por fiesta. **No es un descuento a mano**: sale solo, y solo para la familia que tiene esos lugares | PRECIOS |
| ¿El vendedor puede poner descuentos? | **No, solo en modo jefe**, hasta que el jefe tilde "El vendedor puede poner descuentos" | PRECIOS |
| ¿Recargo por transferencia? | Viene en **0 %** (sin recargo) | PRECIOS |
| ¿Con número del talonario? | **Opcional** en cada venta. Si se escribe, se valida | — |
| ¿Quién tilda "Pago verificado"? | **Solo el jefe** (es quien ve la cuenta) | Marcado en la sección 12 |
| ¿Se vende con cena? | **No en esta versión**: toda entrada vendida es general (pulsera normal) | Sección 12 |
| ¿Tope de entradas por fiesta? ¿El comprador va a la lista de la puerta? | **No y no**: entra con su entrada y su pulsera | Sección 12 |

**Lo que cambió desde el plan, y por qué:**

- **Acá no se venden sillas ni lugares, solo entradas.** El plan decía "las sillas extra también se compran ahí". Después
  se decidió otra cosa (6-nov, 6.4.0): con la fiesta sorteada no se suman sillas al contrato en la oficina
  (`puedeSumarSillasAlContrato`), y la noche de la fiesta la silla se paga en la barra (`esSillaDeLaPuerta`,
  `sillas_puerta`). Eso queda como está. **La venta de entradas no toca `SalonMesas`, `RepartoDeSillas`, el plano ni
  `sillas_puerta`.**
- **"El porcentaje viene en 0" (30-oct) y "al 50 %" (4-nov) son dos cosas.** El 50 % de los lugares adicionales es una
  regla del contrato: la app sabe cuántas le tocan a cada familia y a qué precio. El descuento a mano es otra cosa, viene
  en 0 y es plata que no entra: por eso queda escrito en la venta y en el cierre, y de entrada lo pone solo el jefe.

---

## 2. Lo que no se toca

- **Los pagos de los masivos.** Una venta de entradas **no es** un `pagos_contrato_alumno`, su caja **no es**
  `sesiones_caja`, y nada de esto escribe en `contratos_alumnos`. El saldo, la mora, el cierre de COBROS y Mi Empresa
  siguen leyendo lo de siempre. **No se usa `sesionCajaIdParaCobro` ni `registrarPago`.**
- **La entrega sin cargo** (`entradas_retiro`, `RetiroEntradas.bloqueo`, `PermisosDeEntrega`): igual. Solo se le suma
  lo de la sección 9.
- **La barra.** Se usan sus cuentas (sección 5), no sus tablas.
- **Ninguna columna nueva en una tabla que ya existe**, ni en la PC ni en la nube.

---

## 3. Los datos: cinco tablas nuevas (v80)

Mismo molde que la barra (`lib/features/barra/datos/`, v77): modelo con `toMap`/`fromMap`, `sellada()` con `hecho_por`,
`device_id` (`InstalacionId`) y `updated_at`, lectura con `lectura_de_filas.dart`, y todo lo que se escribe va con su
entrada en la cola en la misma transacción (`SyncQueue.enqueue`, como `BarraLocal._guardar`). **Nada se borra.**

Carpeta nueva: `lib/features/entradas/datos/`.

### 3.1 `entradas_config` — el precio de la fiesta

Una fila por fiesta, con id fijo (`UuidUtils.entradasConfigId(eventoId)`, nuevo). Cambiarla la actualiza.

| Columna | Tipo en la nube | Qué es |
|---|---|---|
| `id` | uuid, PK | fijo por fiesta |
| `evento_id` | uuid not null | |
| `valor_entrada` | numeric | el "$X". Null: todavía no se puso, no se vende |
| `precio_anticipada` | numeric | null: no hay anticipada |
| `anticipada_hasta` | text | `AAAA-MM-DD`, el último día de la anticipada, en hora de Argentina |
| `descuento_lugares_pct` | numeric not null default 50 | el % de los lugares adicionales |
| `recargo_pct` | numeric not null default 0 | recargo por transferencia |
| `descuento_a_mano` | integer not null default 0 | 1: el vendedor puede poner descuentos |
| `hecho_por`, `device_id`, `created_at`, `updated_at` | como la barra | |

### 3.2 `entradas_cajas` — la caja de entradas

Como `barra_cajas`, sin `numero_caja` ni `sede`. **La abre quien vende, en su equipo, y vive en ese equipo**: por eso
el número del comprobante no choca sin internet. Cerrarla la actualiza.

`id`, `evento_id`, `operador_id` (uuid, null si la abre el jefe), `operador_nombre` (el de ese día), `cambio_inicial`
(numeric not null default 0), `abierta_at` (timestamptz not null), `cerrada_at`, `efectivo_contado`, `diferencia`,
`nota_cierre`, `hecho_por`, `device_id`, `created_at`, `updated_at`.

### 3.3 `entradas_ventas` — cada venta

**Una venta nunca se edita ni se borra:** anularla es otra fila (3.4).

| Columna | Tipo | Qué es |
|---|---|---|
| `id` | uuid, PK | |
| `caja_entradas_id` | uuid not null | |
| `evento_id` | uuid not null | |
| `numero` | integer not null | correlativo dentro de su caja, dado en la misma transacción que guarda (como `BarraLocal.vender`) |
| `contrato_alumno_id` | uuid | la familia, si compra una familia de la fiesta. Null: alguien de afuera |
| `comprador_nombre` | text not null | nombre y apellido de quien compra y retira |
| `comprador_dni` | text | si lo dan |
| `renglones` | text not null | JSON, ver abajo |
| `cantidad` | integer not null | entradas de toda la venta (la suma de los renglones) |
| `total` | numeric not null | lo que valen, ya con los descuentos. El recargo va aparte |
| `descuento` | numeric not null default 0 | la plata descontada **a mano** en esta venta |
| `medio` | text not null | `efectivo`, `transferencia`, `mixto` (`MedioBarra`) |
| `efectivo`, `transferencia` | numeric not null default 0 | suman `total` + `recargo` |
| `recibe` | numeric | |
| `vuelto` | numeric not null default 0 | |
| `recargo` | numeric not null default 0 | |
| `recargo_pct` | numeric | |
| `numeros` | text | los del talonario, como `TramoTalonario.aTexto` ("1043-1058,1101-1108"). Null: no se anotaron |
| `hecho_por`, `device_id`, `created_at`, `updated_at` | | |

**Un renglón** lleva el nombre y el precio de ese momento, como `RenglonVenta` (si el jefe cambia el precio, la venta
vieja sigue diciendo lo que se cobró):

```json
{"tipo": "suelta", "nombre": "Entrada general", "precio_lista": 10000, "descuento_pct": 0, "precio": 10000, "cantidad": 2}
{"tipo": "lugar",  "nombre": "Entrada de lugar adicional (50 %)", "precio_lista": 10000, "descuento_pct": 50, "precio": 5000, "cantidad": 8}
```

`tipo`: `suelta` (a precio de lista, con el descuento a mano si lo hay) o `lugar` (las de la mesa adicional y las sillas
extra de esa familia). **Un tipo que esta versión no conoce se cuenta por su `precio` y su `cantidad`**, como
`MedioBarra.otro`. Los $10.000 son un ejemplo: el precio todavía no se sabe.

### 3.4 `entradas_anulaciones`

Como `barra_anulaciones`: una por venta, con id fijo (`UuidUtils.entradasAnulacionId(ventaId)`, nuevo), solo se
agregan. Columnas: `id`, `venta_id`, `caja_entradas_id`, `evento_id`, `motivo` (not null), **`devueltas`** (integer not
null: 1 devolvieron las entradas y pulseras, 0 no), `hecho_por`, `device_id`, `created_at`, `updated_at`.

### 3.5 `entradas_verificaciones` — "Pago verificado"

Una por venta, con id fijo (`UuidUtils.entradasVerificacionId(ventaId)`, nuevo). Tildar y destildar la actualiza; no
se borra. `id`, `venta_id`, `evento_id`, `verificado` (integer not null), `hecho_por`, `device_id`, `created_at`,
`updated_at`. **Va aparte para no editar la venta.**

### 3.6 En la PC (v80)

- `LocalDatabase._version` pasa a 80. `crearTablasV80(db)` con `CREATE TABLE IF NOT EXISTS` y sus índices
  (`evento_id`, `caja_entradas_id`, `contrato_alumno_id` en ventas), y el bloque `if (oldVersion < 80 && newVersion >= 80)`
  igual a los de la 76 a la 79 (el `try` que no frena el arranque).
- **Copia antes de migrar** (`copiaAntesDeMigrar`), como siempre.
- Leer sin las tablas no tira: da la lista vacía (`BarraLocal._leer`).

### 3.7 En la nube

`supabase/migrations/20261113HHMMSS_venta_de_entradas.sql`, con el molde de `20261103140000_barra.sql`:

- solo `create table if not exists`, índices comunes y los dos disparadores de `updated_at`
  (`update_updated_at_column`);
- **sin CHECK, sin clave foránea y sin índice único**: el motor toma cualquier "violates" como un padre que falta y la
  fila queda trabada en la cola;
- RLS prendida con la política `<tabla>_all_authenticated`, igual que la barra. **Un anónimo no ve nada**;
- nada a la publicación de Realtime;
- el `ROLLBACK` comentado arriba de cada tabla y las consultas de antes y después al final (los conteos de
  `contratos_alumnos`, `pagos_contrato_alumno` y `eventos` tienen que dar igual).

**Se corre antes de instalar, con el OK del usuario en el momento.** Sin las tablas en la nube, cada PC falla al bajar
en cada ciclo, lo vendido queda trabado en la cola y la revisión de la mora no corre.

### 3.8 En el motor (`sync_engine.dart`)

Las cinco tablas, en los mismos lugares que `barra_ventas`:

- `_incrementalColumns` (`updated_at`) y `_pullFromCloud` (`_pullTable`);
- la prioridad de la subida (`getPriority`, en `_flushQueue`): config y cajas 2, ventas 4, anulaciones y verificaciones 5;
- las columnas que suben (el mapa donde está `'barra_ventas': [...]`): **exactamente las del `toMap` y las del SQL**;
- `_tablasSinRevisarBorrados`, cada una con su motivo;
- **`entradas_cajas`, `entradas_ventas` y `entradas_anulaciones` van en `_tablasDelCobro`**: es plata, y dos PCs
  vendiendo la misma fiesta tienen que verse en segundos (los números del talonario). `entradas_config` y
  `entradas_verificaciones`, no: van con lo de carga. **El costo:** tres tablas más en la red de seguridad de 5 minutos,
  36 pedidos por hora por PC. En reposo sigue sin pedir nada; `test/sync_en_reposo_test.dart` lo tiene que seguir
  diciendo.

---

## 4. El permiso: "Vende entradas"

**Sin columna nueva y sin SQL**, igual que la Encargada de barra: es Entradas con un **2** en `permisos_operador.entradas`
(en la nube ya es `integer`).

- `PermisoOperador` suma `vendeEntradas('vende_entradas')`. **No es una puerta más**: `deEntrada` sigue con las tres.
- `PermisosEfectivos` suma `vendeEntradas` y `nivelEntradas` (0 nada, 1 entrega, 2 entrega y vende).
  `tiene(entradas)` da verdadero también con el 2. `fromMap`: `entradas = prendido(v) || v == 2`,
  `vendeEntradas = v == 2`. `toMap`: `'entradas': nivelEntradas`.
- `CambioDePermiso.entre` ya recorre `PermisoOperador.values`: el cambio queda en `permisos_operador_cambios`.
- En OPERADORES (`operadores_caja_screen.dart`), la casilla **"Vende entradas"** debajo de Entradas, como "Encargada de
  barra" debajo de Barra. Tildarla tilda Entradas; destildar Entradas la destilda.
- **La llave:** `puedeVenderEntradasProvider` (en `app_role_provider.dart`, al lado de `mandaEnLaBarraProvider`):
  el jefe en modo jefe, o un operador con `vendeEntradas`. **Toda pantalla nueva pregunta por este provider, nunca por
  el rol a mano.** Anular, verificar y PRECIOS preguntan por `esRolJefeProvider`.

**Quien solo entrega (el 1) sigue sin tocar plata.** Quien vende también entrega: es quien le da la entrada en la mano.

**Convivencia:** una PC con una versión anterior lee el 2 como "sin Entradas" (falla cerrada) y, si el jefe guarda los
permisos de esa persona desde ahí, lo vuelve a 0 o 1. **Regla: no tildar "Vende entradas" a nadie hasta que todas las
PCs y las tablets tengan esta versión.** La pantalla lo avisa al tildar, como hoy al destildar Cobros.

---

## 5. Las cuentas (puras, sin pantalla ni base)

Carpeta nueva: `lib/features/entradas/cuentas/`. **Se usa lo de la barra, no se escribe otro:** `centavos`,
`deCentavos` y `pesos` (`barra/cuentas/pesos.dart`), `MedioBarra`, `PartidoMixto` y `CobroBarra`
(`barra/cuentas/cobro_barra.dart`). Todo en centavos enteros y precios en pesos enteros.

### 5.1 El precio de hoy

```dart
/// Null: la fiesta no tiene precio y no se vende.
static double? precioDeHoy(ConfigEntradas c, DateTime hoyAr);
```

- sin `valor_entrada`: null;
- con `precio_anticipada` y `hoyAr` (el día, en Argentina: `ArTime`) hasta `anticipada_hasta` inclusive: la anticipada;
- si no, `valor_entrada`. Una anticipada sin fecha no rige nunca (PRECIOS no deja guardarla así).

### 5.2 Las de los lugares adicionales

- **Precio:** `valor_entrada × (100 − descuento_lugares_pct) / 100`, redondeado a pesos. **Siempre sobre el valor de la
  entrada**, no sobre la anticipada: la regla es "el 50 % de su valor".
- **Cuántas le quedan por comprar a una familia:**
  `RetiroEntradas.entradasDe(alumno).alCincuenta` menos las de sus renglones `lugar` en ventas **no anuladas** de esa
  fiesta, con piso en cero. **No se guarda en ningún lado: se cuenta cada vez**, así no hay dos lugares que digan cosas
  distintas.
- No se le pueden vender más de las que le quedan. Si quiere más entradas, van como `suelta`, a precio de lista.

### 5.3 La venta que cierra

`VentaEntradas.nueva(...)` arma la fila y **tira `ArgumentError`** si algo no cierra, como `VentaBarra.nueva`:

- sin renglones, o una cantidad menor que 1;
- sin nombre y apellido del comprador;
- un renglón `lugar` sin `contrato_alumno_id`;
- `total` distinto de la suma de los renglones; `efectivo + transferencia` distinto de `total + recargo`;
- un descuento a mano fuera de 0 a 100.

### 5.4 Los números del talonario

Opcionales. **Si se escriben:** tienen que ser tantos como entradas lleva la venta, sin tramos al revés ni pisados
(las mismas reglas y palabras de `RetiroEntradas.errorTramos`), y **no pueden repetir**:

- uno ya entregado sin cargo a una familia (`RetiroEntradas.tramosDeOtros`);
- uno de otra venta no anulada;
- uno de una venta **anulada sin devolver** (esos quedan anulados para siempre).

Los de una venta anulada **con las entradas devueltas** vuelven a quedar libres. La entrega sin cargo tiene que
aprender lo mismo al revés: al mapa que hoy arma `RetiroEntradas.tramosDeOtros` (nombre → tramos, el `deOtros` de
`errorTramos`) se le suman los vendidos, con el nombre del comprador, así el mensaje "El 1043 ya se le dio a…" sirve
para los dos.

Dos equipos vendiendo sin internet pueden anotar el mismo número: **no se puede evitar, se avisa cuando se juntan**
("El 1043 está en dos ventas: revisar", en VENTAS).

### 5.5 El cierre de una caja

`CierreDeEntradas`, con la forma de `CierreDeBarra`:

- vendidas: cuántas `suelta` y cuántas `lugar`, y su plata;
- por medio: efectivo, transferencia, mixtos; el recargo aparte;
- **"Descuentos a mano: $Y"**, en un renglón propio;
- **una venta anulada no cuenta, tampoco en el efectivo que tiene que haber** (se supone devuelta, como en la barra). Lo
  anulado va aparte;
- efectivo que tiene que haber: `cambio_inicial` + el efectivo de las ventas que cuentan;
- **la diferencia de una caja cerrada es la que se anotó al cerrar.** Si el jefe anula después, el cierre no se
  corrige: va abajo "Anulado después del cierre: $X" (el criterio de `anuladoDespuesDelCierre`).

---

## 6. PRECIOS (modo jefe)

Un botón **PRECIOS** en la pantalla de ENTRADAS de la fiesta (`RetiroEntradasScreen`, la de la oficina), apagado y con
el motivo sin modo jefe (`kSoloEnModoJefe`). **Doble llave:** el botón, y la función que guarda vuelve sin escribir si
`esRolJefeProvider` da falso (lo que hace `_frenaSinModoJefe()` en las pantallas del salón; `RetiroEntradasScreen` hoy
no tiene una: su llave es `if (!_permisos.anular) return;`). El diálogo va en un archivo propio
(`lib/features/entradas/widgets/precios_de_entradas_dialog.dart`).

- **Valor de la entrada: $** (pesos enteros).
- **Anticipada** (opcional): **$** y **hasta el día**. Las dos o ninguna.
- **Entradas de la mesa adicional y las sillas extra: ___ % del valor** (viene en 50), con la cuenta a la vista:
  "Cada una: $ 5.000".
- **Recargo por transferencia: ___ %** (viene en 0).
- **☐ El vendedor puede poner descuentos.** Destildado: solo en modo jefe.

Guardar sin cambiar nada no escribe. **Cambiar el precio no toca ninguna venta hecha.**

---

## 7. La caja de entradas y VENDER

### 7.1 Por dónde se entra

- **Operador con "Vende entradas":** `EntradasHomeScreen`. Cada fiesta pasa a tener dos botones, **ENTREGAR** (lo de
  hoy, `RetiroEntradasScreen.mostrador`) y **VENDER**. Quien solo entrega ve la pantalla como hoy.
- **El jefe, en modo jefe:** en ENTRADAS de la fiesta, **VENDER** y **VENTAS** (al lado de PRECIOS). Su caja lleva
  `operador_id` null y el nombre de `quienOpera`.
- **Quien entró a COBROS y además vende:** pasa a Entradas como hoy, con su caja de cuotas abierta y latiendo. Son dos
  cajas y no se cruzan.

`test/modo_entradas_cerrado_test.dart` sigue valiendo entero: **el camino de la venta no usa nada de lo que ese test
prohíbe.** Lo nuevo va en archivos propios (`lib/features/entradas/widgets/`), no adentro de `entradas_home_screen.dart`
más que el botón.

### 7.2 Abrir la caja

VENDER sin caja abierta la pide: **"Abrir la caja de entradas de [fiesta]"**, con el **cambio inicial** (puede ser 0).
A diferencia de la barra, acá se pregunta: el usuario la pidió "con su propio inicio".

- Si ese operador ya tiene una abierta en esa fiesta **en este equipo**, se retoma: tocar dos veces no abre dos.
- Si la fiesta no tiene precio: **"El jefe todavía no puso el precio de la entrada de esta fiesta"**, y no abre.
- Si la nube ya conoce otra caja abierta de ese operador en esa fiesta, en otro equipo: avisa y deja seguir.

### 7.3 La pantalla de venta (`vender_entradas_screen.dart`)

Arriba: la fiesta, quién vende, "Caja abierta", y la línea de internet (el mismo criterio que la barra: "Todo subido"
o cuántas ventas esperan subir).

1. **¿A quién?** Dos opciones:
   - **Una familia de la fiesta:** se busca al alumno como en la entrega. Muestra su mesa y, si le quedan, **"Le quedan
     N entradas de sus lugares adicionales, a $ X cada una"**. Si debe del contrato, lo dice (**"Debe $ X del contrato:
     se salda en caja"**) y **deja vender igual**: la plata del contrato no se cobra acá, y lo que frena por deuda es la
     entrega sin cargo, que no cambia.
   - **Alguien de afuera.**
   - En los dos casos, **nombre y apellido de quien compra** (obligatorio) y DNI (opcional).
2. **Los renglones**, cada uno con su casilla y su cantidad, como en el cobro de los masivos:
   - ☐ **Entradas de sus lugares adicionales** × n (tope: las que le quedan) · $ c/u. Solo con una familia a la que le
     quedan. Viene tildado con todas las que le quedan.
   - ☐ **Entradas** × n · $ c/u (el precio de hoy; si rige la anticipada, dice "anticipada"). Con **Descuento ___ %**,
     en 0. Sin permiso para descontar, el casillero se ve apagado con el motivo.
3. **Números del talonario** (opcional), con el mismo casillero de tramos de la entrega.
4. **El total**, y **EFECTIVO · TRANSFERENCIA · MIXTO**, que abren `pedirCobro` (`barra/widgets/cobrar_hoja.dart`) con
   el recargo de la fiesta (`recargoPrendido: recargo_pct > 0`).
5. **Confirmar:** la venta se guarda **antes** de abrir el comprobante. Sin impresora, igual queda. Después limpia la
   pantalla para la siguiente.

Sin internet se vende igual: todo queda en el equipo y sube solo. Para una tablet que se prepara en la oficina, las
cinco tablas se suman a lo que baja "Lista para trabajar sin internet".

### 7.4 El comprobante

`PdfService.generarComprobanteVentaEntradas`, media A4 (`_mediaA4`), con la cabecera de los recibos de cobro:

- la escuela y la fecha de la fiesta; **COMPROBANTE DE ENTRADAS · N° 0017**; fecha y hora (Argentina); quién vendió;
- quién compra (y DNI si está); si es una familia de la fiesta, el alumno y su mesa;
- los renglones (cantidad, cada una, descuento si lo hay, subtotal), el recargo si lo hay, **el total**;
- cómo pagó (en el mixto, cuánto de cada uno);
- **Pulseras normales: N** y los números del talonario, si se anotaron;
- reimpreso dice **COPIA**; anulado, **ANULADA** cruzado.

---

## 8. VENTAS: el historial de la fiesta

`ventas_de_entradas_screen.dart`. Quien vende ve **las de su caja**; el jefe, **todas las de la fiesta**, por caja.

- Cada renglón: N°, hora, comprador, cuántas, total, cómo pagó, quién vendió, y **☑ Pago verificado**.
- **REIMPRIMIR** el comprobante (sale con COPIA).
- **Pago verificado:** lo tilda **solo el jefe** (doble llave). Queda quién y cuándo. Filtro: todas, verificadas, sin
  verificar.
- **ANULAR, solo el jefe** (apagado con el motivo para los demás; doble llave en la función): motivo obligatorio y
  **"¿Devolvieron las entradas y pulseras?"**, con los números a la vista. La venta sigue en la lista, tachada, con
  quién la anuló, cuándo, el motivo y si devolvieron. Anular dos veces devuelve la que ya había.
- **IMPRIMIR HISTORIAL** (PDF A4): todas las ventas de la fiesta con la tilde en cada renglón, las anuladas tachadas y
  los totales abajo.
- El aviso de números repetidos de 5.4, arriba, si hay.

---

## 9. Cerrar la caja, el cierre por sector y la entrega

### 9.1 Cerrar la caja de entradas

Desde la pantalla de venta, **CERRAR CAJA**: se cuenta el efectivo **a ciegas**, y recién después se ve lo que tenía
que haber y la diferencia ("Justo", "Sobran $ 500", "Faltan $ 1.500": `diferenciaEnPalabras`). Nota opcional. **Una
caja cerrada no se vuelve a cerrar ni se corrige**; solo se le puede agregar la nota. Sale su papel
(`generarCierreCajaEntradasPdf`): la fiesta, quién, abierta y cerrada, y las cuentas de 5.5.

Sin el OK de una encargada: eso es de la barra.

### 9.2 ENTRADAS en el cierre de caja (lo que hoy dice "todavía no hay ventas")

`SectorEntradasDelCierre` deja de ser un cartel. Pasa a un archivo propio (`cierre_caja/widgets/sector_entradas.dart`)
con la forma de `SectorBarraDelCierre`:

- **por fiesta, no por día**, con la misma elección de fiesta (la próxima, la de anoche hasta el día siguiente, CAMBIAR
  DE FIESTA);
- **una línea por caja**: quién, el cambio, efectivo, transferencia, mixtos, vendidas, descuentos a mano, anuladas, lo
  contado y la diferencia; "abierta" si sigue abierta;
- los totales de la fiesta: **vendidas N (sueltas y de lugares) = $ total**, y "Anulado después del cierre", si hay;
- **solo para mirar**: anular, verificar y reimprimir están en VENTAS;
- sin ninguna caja: **"Todavía no se abrió ninguna caja de entradas en esta fiesta."** Sin precio: **"Esta fiesta
  todavía no tiene precio de entrada: se pone en ENTRADAS → PRECIOS."** El texto "se venden a mano, fuera de la app"
  se va.

Sigue siendo solo de modo jefe (`sectoresDelCierre`). `tool/cierre_sector_prueba.dart` tiene que mostrarlo.

### 9.3 La entrega sin cargo, con lo vendido a la vista

- La tarjeta **"Al 50 %, aparte: 112"** pasa a **"Al 50 %: 40 vendidas de 112"**.
- En cada familia: "· 8 al 50 %" pasa a "· 8 al 50 % (compró 3)".
- En `entrega_entradas_dialog.dart`, debajo de "se compran aparte, al 50 %": con `puedeVenderEntradasProvider`, el
  botón **VENDERLE ESAS ENTRADAS**, que abre la venta con esa familia ya elegida. Sin el permiso, el texto de hoy más
  "Se las vende quien tiene la caja de entradas."
- La planilla de entrega en papel no cambia.

---

## 10. Reglas, y el test de cada una

Cada fila es un test que tiene que existir y pasar, **con una rotura a propósito** en cada etapa. `flutter analyze` y
`flutter test` enteros, en la PC.

| Lo acordado | El test |
|---|---|
| La migración solo agrega | `migracion_v80_test`; y `tool/verificar_migracion_v80_test.dart` sobre una copia de la base real: tabla por tabla, la vuelta a la 6.8.0 y el mismo SHA-256 de la real (con la app cerrada: se le pide al usuario) |
| La nube y la PC dicen lo mismo | `sql_v80_coherencia_test`: el `toMap` de cada modelo contra las columnas del SQL y las del motor |
| Las cinco tablas suben, bajan y no se revisan sus borrados | `sync_tablas_v80_test` y `borrados_de_otra_pc_test` |
| En reposo no se le pide nada a la nube | `sync_en_reposo_test`, con las tablas nuevas |
| Una venta de entradas no toca cuotas, saldo ni mora | `venta_entradas_no_toca_test`: lee `lib/features/entradas/` y falla si aparece `pagos_contrato_alumno`, `sesiones_caja`, `sesionCajaIdParaCobro`, `registrarPago`, `saldo_deudor` o una escritura en `contratos_alumnos` |
| El modo Entradas sigue cerrado | `modo_entradas_cerrado_test`, sin cambios, sigue pasando |
| Sin fila es Cobros; con 1 entrega; con 2 entrega y vende | `permisos_operador_test`: los tres, y que una fila con 2 leída con el `fromMap` de antes (`v == 1`) no da Entradas |
| Solo vende quien puede | `solo_modo_jefe_test`, ampliado: las pantallas nuevas preguntan por `puedeVenderEntradasProvider`; PRECIOS, anular y verificar, por `esRolJefeProvider`, con la doble llave |
| El precio de hoy | `entradas_cuentas_test`: sin precio, null; el último día de la anticipada rige; al otro día, el valor; a medianoche de Argentina, no de UTC |
| Las de los lugares | `entradas_cuentas_test`: 14 lugares adicionales y 3 compradas, quedan 11; una venta anulada las devuelve; no se venden más de las que quedan; el precio sale del valor, no de la anticipada |
| La venta cierra | `entradas_cuentas_test`: con los tres medios y con recargo, `efectivo + transferencia == total + recargo`; cada caso de 5.3 tira |
| Los números no se repiten | `entradas_numeros_test`: contra una entrega sin cargo, contra otra venta, contra una anulada sin devolver; una anulada con devolución los libera; la entrega sin cargo tampoco deja repetir uno vendido |
| El número del comprobante no se repite en su caja | `entradas_repositorio_test`: dos ventas seguidas, 1 y 2; guardar dos veces la misma no crea otra |
| El cierre cuenta bien | `cierre_de_entradas_test`: una anulada no cuenta en el efectivo; los descuentos a mano en su renglón; anulada después de cerrar, el cierre queda y va la línea aparte |
| Sin precio no se vende | `vender_entradas_pantalla_test`: el aviso, y no abre caja |
| Nombre y apellido obligatorios | `vender_entradas_pantalla_test`: sin eso, confirmar está apagado y dice por qué |
| El descuento a mano, solo con permiso | `vender_entradas_pantalla_test`: con `descuento_a_mano` en 0 y sin modo jefe, apagado; en 1, se puede; siempre queda en la venta |
| Anular y verificar, solo el jefe | `ventas_de_entradas_test`: apagados con el motivo, y la función frena igual |
| El cierre por sector muestra las cajas | `cierre_por_sector_test`: sin cajas, sin precio y con dos cajas |
| Vendidas X de Y en la entrega | `retiro_entradas_screen_test` |
| El comprobante entra en media A4 | `comprobante_entradas_medida_test`, como `hoja_cierre_sesion_medida_test`: con 1 y con 6 renglones |

---

## 11. Etapas (cada una cierra sola, con su commit)

1. **Los datos:** los cinco modelos, la v80, el SQL (sin correr), el repositorio local (`EntradasLocal`, con una
   interfaz para quien vende y otra para el jefe, como `BarraDeLaCaja` y `BarraDelJefe`), el motor, y sus tests.
2. **Las cuentas** de la sección 5, puras, con todos sus tests.
3. **El permiso** "Vende entradas" y **PRECIOS**.
4. **La caja y VENDER**, con el comprobante.
5. **VENTAS:** historial, reimprimir, anular, verificar y el PDF.
6. **Cerrar la caja, el sector ENTRADAS del cierre y la entrega** (sección 9).
7. **Probarlo y publicar:** `tool/venta_entradas_prueba.dart` (sin base ni nube, como `tool/entradas_prueba.dart`);
   de punta a punta en dos PCs (una vende y la otra ve la venta y el cierre; una familia compra las de sus lugares y
   la entrega lo muestra); la migración sobre una copia de la base real; `CONTEXTO`, `CLAUDE.md` (sacar "sin
   programar" de "El retiro de entradas" y sumar las reglas de acá a Trampas) y `HOJA_DE_RUTA`.

**Para publicar** (lo de siempre): foto de la mora "antes"; el SQL, con el OK del usuario en el momento, y sus conteos
de antes y después; `flutter test` entero; instalador, APK, tag, release y web; foto "después" con las PCs instaladas.
**No tildar "Vende entradas" ni cargar precios hasta que todas las PCs y las tablets tengan la versión.**

**Si el 4-dic aprieta:** las etapas 1 a 4 y el punto 9.2 ya dejan vender con comprobante y ver la plata en el cierre.
Anular (de la 5) tiene que salir con eso: sin anular, un error de carga no tiene arreglo.

---

## 12. Fuera de esta versión, y lo que conviene preguntarle al jefe

**Fuera, a propósito:**

- **La web** (el iPhone del jefe): ENTRADAS del cierre se mira en la PC. La interfaz del jefe queda separada para
  sumarle después una `EntradasNube`, como `BarraNube`. **La web no tiene que romperse**: el sector no puede abrir la
  base local ahí.
- La central por la red del salón (dos equipos vendiendo sin internet no se ven entre sí hasta subir).
- Entradas con cena (pulsera VIP), tope por fiesta, y el comprador en la lista de la puerta o en el tótem.
- Guardar los PIN cifrados: sigue siendo otro pendiente.

**Para el jefe, ninguna frena el trabajo:**

1. ¿El que vende puede poner descuentos solo, o siempre lo hace el jefe? (Hoy: el jefe, con una casilla para cambiarlo.)
2. ¿La transferencia lleva recargo, como en las cuotas? (Hoy: 0 %.)
3. ¿Las entradas vendidas llevan número del talonario siempre? (Hoy: opcional.)
4. ¿"Pago verificado" lo tilda solo él? (Hoy: sí.)
5. ¿Se venden la noche de la fiesta en el predio, y desde cuántos equipos? Con uno solo anda sin internet tal como
   queda; con dos, los números repetidos se avisan recién al subir.
6. La silla que se compra la noche de la fiesta en la barra, ¿lleva además su entrada al 50 %? Hoy la barra cobra la
   silla y nada más; si lleva entrada, es un renglón `lugar` más y hay que decidir quién la cobra.
