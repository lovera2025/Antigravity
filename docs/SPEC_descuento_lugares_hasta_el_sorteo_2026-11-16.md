# SPEC — El 50 % de las entradas de los lugares adicionales vale hasta el sorteo

**Archivo:** `docs/SPEC_descuento_lugares_hasta_el_sorteo_2026-11-16.md`
**Rama:** `feature/v4.6-cierre-por-sesiones` (hoy en `6.9.0+75`, publicada el 15-nov). Versión sugerida: `6.9.1`.
**SQL:** ninguno. **Migración local:** ninguna (la base sigue en la v80). **Tablas o columnas nuevas:** ninguna.
**Datos que se corrigen:** ninguno.
**Revisado contra el código** en `8490d5d` (15-nov, 22:56), solo lectura, **desde una sesión sin Flutter**: no se
corrió ningún test ni se miró la base ni la nube. Los números de línea son de ese commit.

> **Este repo es público.** En esta spec, en los tests, en las muestras y en los mensajes de commit de este trabajo
> **no va ningún nombre de alumno ni de comprador**. Los ejemplos usan familias inventadas (F1, F2…). El simulacro
> de la sección 8.5 lee una copia de la base real: su salida va a `build/`, nunca a git.

Es un pedido del usuario del 16-nov: *"una vez sorteado, el beneficio del 50 % de las entradas ya no va"*. Y al
preguntarle por el alcance: *"los que no se sortean aún están a tiempo; después del sorteo ese beneficio se va"*,
*"a partir de hoy 16 de nov es esa decisión"* y *"lo que ya están con ese 50 % se puede dejar pasar"*.

**Qué cambia de verdad:** el **precio** de las entradas de la mesa adicional y de las sillas extra cuando la fiesta
ya está sorteada. Nada más: ni cuántas le corresponden a cada familia, ni el tope, ni lo ya vendido, ni un dato
guardado.

---

## 0. Un punto a confirmar con el usuario antes de programar

**Las fiestas que ya estaban sorteadas antes del 16-nov.** Esta spec toma la lectura más simple de lo que dijo:

- la regla es una sola, **"fiesta sorteada: sin descuento"**, y vale para todas las fiestas desde que el equipo
  tiene la versión, **también para las que se sortearon antes del 16-nov**;
- *"se puede dejar pasar"* es lo ya hecho: una venta guardada al 50 % no se toca nunca (una venta no se edita), y
  lo que se vendió a mano antes de la app tampoco.

Si lo que quiso decir es que **las escuelas sorteadas antes del 16-nov conservan el 50 %** para quien todavía no
compró, es la variante de la sección 10: lleva leer la fecha del sorteo, y **no se programa sin su OK**.

Mientras tanto, para "dejar pasar" a una familia puntual después del sorteo no hace falta código: en modo jefe se
le venden como entradas sueltas con el descuento a mano (queda anotado como descuento a mano en la venta y en el
cierre, y no baja su "le quedan").

---

## 1. Qué hace hoy la 6.9.0

- La mesa del contrato trae sus 8 entradas sin cargo. La mesa adicional y las sillas extra pagan el lugar, no la
  entrada: cada entrada de esos lugares se compra aparte, con el descuento de la fiesta (viene en 50, lo pone el
  jefe en PRECIOS: `entradas_config.descuento_lugares_pct`).
- Cuántas son por familia: `EntradasDeAlumno.alCincuenta` (`eventos/services/retiro_entradas.dart:40`).
- Cuántas le quedan: `LugaresDeLaFamilia` (`entradas/cuentas/lugares_de_la_familia.dart:54-67`), de la cuenta del
  alumno y de las ventas no anuladas.
- A cuánto: `PrecioDeEntradas.deLugar` (`entradas/cuentas/precio_de_entradas.dart:54`), siempre sobre el valor de
  la entrada.
- El renglón de la venta: `PedidoDeEntradas.renglones` (`entradas/cuentas/pedido_de_entradas.dart:185`), tipo
  `lugar`, con el nombre `Entrada de lugar adicional (50 %)`.

**En ningún lado se mira si la fiesta está sorteada:** `lib/features/entradas/` no nombra el sorteo. Hoy el
descuento vale siempre, antes y después.

Dos cosas del código que importan para lo que sigue:

- **El diálogo de la entrega muestra las de los lugares adicionales, con VENDERLE ESAS ENTRADAS, en tres
  momentos:** cuando el freno es la deuda, cuando ya retiró y mientras se le entrega
  (`eventos/widgets/entrega_entradas_dialog.dart:399`, `:537`, `:713`). `RetiroEntradas.bloqueo` mira primero la
  plata y después la mesa (`retiro_entradas.dart:217`): antes del sorteo, la familia que debe lo ve, y **la que
  pagó todo no** (su freno es "Sin mesa").
- **En VENDER se le vende a cualquiera, con o sin mesa**: la familia figura "sin mesa" y se le vende igual
  (`entradas/widgets/vender_entradas_screen.dart:811`). Es el camino seguro para comprar con el descuento antes
  del sorteo.

---

## 2. La regla nueva

**El descuento de los lugares adicionales vale mientras la fiesta no esté sorteada. Con la fiesta sorteada, esas
entradas se venden al precio del día, como cualquier otra.**

| | Antes del sorteo (igual que hoy) | Con la fiesta sorteada |
|---|---|---|
| Cuántas le corresponden a la familia | las de sus lugares adicionales | **igual** |
| Tope de lo que se le vende como "de sus lugares" | las que le quedan | **igual** |
| Precio de cada una | valor de la entrada con el descuento de PRECIOS | **el precio del día** (`PrecioDeEntradas.deHoy`: la anticipada si rige, si no el valor) |
| Renglón de la venta | tipo `lugar`, `Entrada de lugar adicional (50 %)` | tipo `lugar`, **`Entrada de lugar adicional`**, descuento 0 |
| Cuenta para "compró N / le quedan K" | sí | **sí** |
| En el cierre | "de lugares adicionales" | **igual** |

**El renglón sigue siendo `lugar`, a propósito.** Si después del sorteo pasaran a venderse como sueltas, la entrega
perdería el "ya compró 3: le quedan 5" justo cuando se usa (la entrega sin cargo pide mesa: es siempre después
del sorteo), y el cierre dejaría de separar las de los lugares. Un `lugar` con descuento 0 ya es una venta válida
para `VentaEntradas.nueva` y para una PC con la 6.9.0, que lo lee como cualquier renglón.

### 2.1 Qué es "fiesta sorteada"

**Lo mismo que ya decide las sillas** (`puedeSumarSillasAlContrato`, regla del usuario del 6-nov: "por fiesta
sorteada, no por fecha"): `hayMesasSorteadas(alumnos)` (`recepcion/services/lista_puerta.dart:180`), o sea, algún
alumno activo de la fiesta tiene mesa. **No se inventa otra definición al lado.**

Sale de `contratos_alumnos`, que ya está en `tablasDeLaPuerta`: la tablet que vende sin internet lo sabe con lo
que bajó. Por eso no se usa el registro de sorteos (`sorteos_mesas` no está en esa lista).

### 2.2 Lo que esta spec decide para no esperar (cada punto, dónde se cambia)

| Caso | Cómo queda | Dónde se cambia |
|---|---|---|
| Es por fiesta, no por familia | Sorteada la fiesta, tampoco tiene descuento la familia que quedó sin mesa ni la que agrega una mesa después | `DescuentoDeLosLugares.rige` |
| Sin fechas | No hay ningún "16-nov" en el código: la regla vale desde que el equipo tiene la versión | sección 10 si se pide otra cosa |
| Se deshace el sorteo entero | Nadie tiene mesa: el descuento vuelve, hasta que se sortee de nuevo. Es la misma cuenta, no un dato guardado | — |
| Una mesa cargada a mano antes del sorteo | Cuenta como fiesta sorteada (igual que para las sillas) | — |
| Una venta que ya está en la hoja del cobro cuando baja el sorteo | Termina como se mostró: el pedido es el del momento de tocar el medio de pago (`_cobrar`, `vender_entradas_screen.dart:367`) | — |
| Se anula después del sorteo una venta hecha al 50 % | Esas entradas vuelven a "le quedan", y si las compra de nuevo van al precio del día | — |
| El descuento a mano | Sigue sin tocar las de los lugares (`puedeDescontar` es solo de las sueltas) | — |
| Apagar la regla entera | Una constante, en un solo lugar: `kElDescuentoTerminaConElSorteo` | sección 4.1 |

---

## 3. Lo que no se toca

- **Ninguna venta guardada.** Cada renglón lleva el nombre y el precio de su momento; el historial, las
  reimpresiones y los cierres de lo ya vendido dicen lo mismo que antes.
- **Cuántas le corresponden** (`EntradasDeAlumno`, `SalonMesas`), el retiro sin cargo, `RetiroEntradas.bloqueo`,
  `PermisosDeEntrega`.
- **Las tablas, la cola y el SQL.** `VentaEntradas.nueva` y sus validaciones no cambian.
- **`CierreDeEntradas` y los papeles del cierre y del historial:** cuentan por tipo de renglón, no por porcentaje.
- **El sorteo, el plano, las sillas, los cobros.** Esto solo **lee** si algún alumno tiene mesa.
- **PRECIOS guarda lo mismo:** `descuento_lugares_pct` sigue siendo el descuento de antes del sorteo.
- **Sin renombrar** `alCincuenta`, `VentaAlCincuenta` ni `VenderAlCincuenta` en esta versión: son la cantidad de
  entradas de los lugares adicionales; se les corrige el comentario y nada más.

---

## 4. Los cambios, archivo por archivo

### 4.1 La llave — `lib/features/entradas/cuentas/descuento_de_los_lugares.dart` (nuevo, puro)

```dart
/// El descuento de las entradas de los lugares adicionales vale hasta el
/// sorteo de la fiesta (regla del usuario, 16-nov-2026). En false, vale
/// siempre, como en la 6.9.0.
const kElDescuentoTerminaConElSorteo = true;

class DescuentoDeLosLugares {
  DescuentoDeLosLugares._();

  /// Si hoy le corresponde el descuento a una familia de esta fiesta.
  /// [fiestaSorteada] es `hayMesasSorteadas` de los alumnos de la fiesta.
  static bool rige({required bool fiestaSorteada}) =>
      !kElDescuentoTerminaConElSorteo || !fiestaSorteada;
}
```

Acá van también las palabras que cambian (sección 5), para que la pantalla y el papel digan lo mismo.

### 4.2 `LugaresDeLaFamilia` (`entradas/cuentas/lugares_de_la_familia.dart`)

- Campo nuevo `final bool conDescuento` (en `ninguno`, `true`: no tiene lugares, no importa).
- `LugaresDeLaFamilia.de(alumno, ventas:, anulaciones:, required bool fiestaSorteada)`: pone
  `conDescuento: DescuentoDeLosLugares.rige(fiestaSorteada: fiestaSorteada)`.
- **`fiestaSorteada` es obligatorio y sin valor por defecto:** el que arma la cuenta sin decirlo no compila.
- `leCorresponden`, `compradas` y `quedan` **no cambian**.

### 4.3 `PrecioDeEntradas.deLugar` (`entradas/cuentas/precio_de_entradas.dart:54`)

`deLugar(c, {required DateTime hoyAr, required bool conDescuento})`: con descuento, lo de hoy (el valor de la
entrada con `descuentoLugaresPct`, nunca sobre la anticipada); sin descuento, `deHoy(c, hoyAr)`.

### 4.4 `PedidoDeEntradas` (`entradas/cuentas/pedido_de_entradas.dart`)

- `precioDeLugar` (línea 169) pasa `hoyAr` y `lugares.conDescuento`.
- `renglones` (línea 185), el renglón de los lugares:
  - con descuento, como hoy;
  - sin descuento: `RenglonEntradas.lugar(nombre: nombreDeLugarSinDescuento, precioLista: deHoy,
    descuentoPct: 0, cantidad: deLugarQueVan)`, con `static const nombreDeLugarSinDescuento =
    'Entrada de lugar adicional'`.
- `descontado` sigue sumando solo las sueltas. `paraLaFamilia`, `conDeLugar` y `deLugarQueVan` no cambian.

### 4.5 VENDER (`entradas/widgets/vender_entradas_screen.dart`)

- En `_cargar` (línea 173) se guarda `_fiestaSorteada = hayMesasSorteadas(todos)`, y `_lugaresDe` (línea 290) lo
  pasa. La pantalla ya vuelve a leer cuando baja `contratos_alumnos` (`_tablasQueMiro`): **si el sorteo llega con
  VENDER abierta, el precio cambia solo en el próximo dibujo.**
- Los textos de las líneas 817 y 856-867, según la sección 5. El detalle del renglón (línea 907) ya sale de
  `p.precioDeLugar`.
- No se precarga nada nuevo: el renglón de los lugares sigue viniendo con las que le quedan.

### 4.6 La entrega (`eventos/widgets/entrega_entradas_dialog.dart`, `eventos/retiro_entradas_screen.dart`)

- `VentaAlCincuenta` (línea 77) suma `final bool conDescuento`; la pantalla del retiro lo arma (línea 358) con
  `DescuentoDeLosLugares.rige(fiestaSorteada: hayMesasSorteadas(_alumnos))`.
- `_alCincuenta()` (línea 605): el texto según la sección 5. La cuenta de "ya compró / le quedan" y el botón no
  cambian.
- En el retiro: la tarjeta de arriba (líneas 981-983) y el renglón de cada familia (línea 1188).

### 4.7 La planilla de entrega (`common/services/planilla_entrega_pdf.dart`)

`construir` recibe `required bool conDescuento`: cambia el título de la columna (línea 40; `columnas` deja de ser
una constante), la leyenda (línea 97) y la línea de control (línea 141). Los números no cambian.

### 4.8 PRECIOS (`entradas/widgets/precios_de_entradas_dialog.dart:366`)

Debajo de "Siempre sobre el valor de la entrada…", un renglón más con la letra de ayuda: **"Vale hasta el sorteo
de la fiesta. Después, esas entradas van al precio del día."** Siempre a la vista, sin datos nuevos.

---

## 5. Lo que dice cada pantalla y cada papel

| Dónde | Antes del sorteo (como hoy) | Con la fiesta sorteada |
|---|---|---|
| VENDER, lista de familias | `14 al 50 % (compró 3)` | `14 de lugares adicionales (compró 3)` |
| VENDER, tarjeta de la familia | `Le quedan 11 entradas de sus lugares adicionales, a $10.000 cada una (le corresponden 14, compró 3).` | la misma frase con el precio del día, y debajo: `El descuento de los lugares adicionales era hasta el sorteo.` |
| VENDER, renglón | `$10.000 c/u · tope 11` | `$20.000 c/u · tope 11` |
| Comprobante e historial (nombre del renglón) | `Entrada de lugar adicional (50 %)` | `Entrada de lugar adicional` |
| Entrega, diálogo | `…no van sin cargo: se compran aparte, al 50 %.` | `…no van sin cargo: se compran aparte, al precio del día.` |
| Retiro, tarjeta de arriba | `Al 50 %` · `Al 50 %, aparte` | `Lugares adicionales` · `Lugares adicionales, aparte` |
| Retiro, renglón de la familia | `· 8 al 50 %` | `· 8 aparte` |
| Planilla de entrega, columna | `Al 50 %` | `Aparte` |
| Planilla de entrega, leyenda | `Al 50 %: de la mesa adicional y las sillas extra, se compran aparte` | `Aparte: de la mesa adicional y las sillas extra, se compran al precio del día` |
| Planilla de entrega, control | `· 112 al 50 %, aparte` | `· 112 aparte` |

**Con la fiesta sorteada, ninguna pantalla ni papel de la entrega dice "50".** Las palabras son una propuesta: se
le muestran al usuario en las capturas antes de publicar.

---

## 6. Casos, con familias inventadas

Fiesta con valor de la entrada $20.000, anticipada $16.000 hasta el 30/11 y descuento de los lugares 50 %
($10.000 cada una).

| Familia | Qué tiene | Antes del sorteo | Sorteada, el 25/11 (rige la anticipada) | Sorteada, el 2/12 |
|---|---|---|---|---|
| F1 | 1 mesa adicional: 8 entradas de lugares | 8 × $10.000 = $80.000 | 8 × $16.000 = $128.000 | 8 × $20.000 = $160.000 |
| F2 | 1 mesa adicional; compró 3 antes del sorteo | las 3 ya pagas: $30.000 | le quedan 5 × $16.000 = $80.000 | le quedan 5 × $20.000 = $100.000 |
| F3 | solo la mesa del contrato | no tiene lugares adicionales | igual | igual |
| F4 | agrega una mesa después del sorteo | — | 8 × $16.000 | 8 × $20.000 |
| F5 | 2 sillas extra, fiesta sorteada, sin mesa todavía (no entró al sorteo) | — | 2 × $16.000 | 2 × $20.000 |

La venta de F2 de antes del sorteo sigue diciendo `Entrada de lugar adicional (50 %)` a $10.000 en el historial y
en una reimpresión. En el cierre, las 3 de antes y las 5 de después son todas "de lugares adicionales".

---

## 7. Las versiones conviven así

- **Un equipo con la 6.9.0 sigue dando el descuento después del sorteo.** Regla de uso: **no tildar "Vende
  entradas" ni cargar precios hasta que todas las PCs y las tablets tengan la 6.9.1** (es la misma regla que ya
  tiene la 6.9.0, con otro número). Si la 6.9.0 todavía no se instaló, se puede saltar directo a la 6.9.1: lo
  decide el usuario.
- Una venta de la 6.9.1 con el renglón `lugar` sin descuento, leída por la 6.9.0: un renglón más, con su nombre y
  su precio.
- **Un equipo que todavía no bajó el sorteo sigue dando el descuento** (la tablet preparada antes del sorteo y sin
  internet). Es el mismo límite que tiene la regla de las sillas. Para el uso: después de sortear, el equipo que
  vende tiene que haber bajado con internet antes de vender.
- Sin SQL, sin migración: volver atrás es reinstalar la 6.9.0.

---

## 8. Cómo se prueba

### 8.1 Los tests de hoy que cambian, y por qué no es aflojarlos

Las familias de prueba vienen **con mesa** (`alumnoDeLaEntrega`, `test/helpers/entrega_en_memoria.dart:34`:
`mesas = const [12]`; `test/entradas_cuentas_test.dart:78`). Con la regla nueva, esa fiesta está sorteada. Los
tests que hoy comprueban el precio con descuento (`entradas_cuentas_test`, grupos "las de los lugares adicionales"
y "lo que decide VENDER"; `vender_entradas_pantalla_test`, líneas 232 y 288; `entrega_entradas_dialog_test`,
419-468; `retiro_entradas_screen_test`, 400-469; `venta_entradas_prueba_test`) **se parten en dos**:

- el de antes, con la fiesta **sin sortear** (nadie con mesa), comprobando exactamente lo mismo que hoy;
- uno nuevo con la fiesta sorteada, comprobando el precio del día y las palabras nuevas.

No se borra ni se debilita ninguna comprobación: cambió la regla, y cada test queda diciendo en qué estado de la
fiesta vale. El commit lo dice.

### 8.2 Tests nuevos

Cuentas (`test/entradas_cuentas_test.dart`):

1. `DescuentoDeLosLugares.rige`: sin sortear, sí; sorteada, no; con la constante en `false`, siempre.
2. Sorteada: `leCorresponden`, `compradas` y `quedan` dan lo mismo que sin sortear.
3. Sorteada: `precioDeLugar` es `deHoy`; con la anticipada vigente, la anticipada; al día siguiente, el valor.
4. Sorteada: el renglón es tipo `lugar`, se llama `Entrada de lugar adicional`, descuento 0, `descontado` 0, y la
   venta cierra (`venta(...)` no tira).
5. Los casos F1 a F5 de la sección 6, con sus totales.
6. Una venta al 50 % de antes del sorteo cuenta en `compradas` después del sorteo; anulada, vuelve a "le quedan".
7. `hayMesasSorteadas`: una baja temporal con mesa no cuenta; todos sin mesa, no está sorteada.

Pantallas:

8. VENDER, fiesta sin sortear: lo de hoy. **Baja el sorteo con la pantalla abierta** (cambia
   `contratos_alumnos`): el renglón pasa al precio del día y aparece la frase.
9. VENDER, sorteada: se guarda la venta y al repositorio llega el renglón sin descuento.
10. Entrega y retiro, sorteada: los textos de la sección 5; "ya compró / le quedan" y VENDERLE siguen.
11. Planilla de entrega de una fiesta sorteada: **no aparece la palabra "50"** (en un PDF se busca palabra por
    palabra, no la frase); sin sortear, la columna "Al 50 %" de siempre.

Vigía de código (como los que leen `lib/`): fuera de `descuento_de_los_lugares.dart`, ningún archivo de
`entradas/widgets`, `eventos/widgets/entrega_entradas_dialog.dart`, `eventos/retiro_entradas_screen.dart` ni
`common/services/planilla_entrega_pdf.dart` escribe "50 %" a mano.

### 8.3 Roturas a propósito (`bash tool/romper_una_regla.sh <casos>`)

Cada una tiene que hacer fallar su test: `rige` devuelve siempre `true`; `deLugar` ignora `conDescuento`; VENDER
pasa `fiestaSorteada: false` fijo; el retiro arma `VentaAlCincuenta` con `conDescuento: true` fijo; la planilla
recibe `conDescuento: true` fijo.

### 8.4 De punta a punta, en el sandbox

- `tool/venta_entradas_prueba.dart`: las familias arrancan **sin mesa**, y un botón **SORTEAR LA FIESTA ·
  DESHACER EL SORTEO** (en memoria) les pone o les saca la mesa en los dos lados. Recorrido con el mouse: vender
  al 50 % antes; sortear; ver el precio del día en la tablet y en la PC; vender; mirar el historial, el
  comprobante y el cierre con las dos ventas; deshacer y ver que el descuento vuelve.
  `test/venta_entradas_prueba_test.dart` y `test/arneses_sin_base_test.dart` lo siguen vigilando.
- `tool/venta_entradas_muestra_test.dart`: las pantallas y la planilla en los dos estados.
- **Capturas de los dos estados al usuario antes de publicar.**

### 8.5 Simulacro sobre una copia de la base

`tool/simulacro_descuento_hasta_el_sorteo_test.dart`, sobre una copia de `tool/copiar_base_solo_lectura.py`: por
fiesta, si está sorteada, cuántas familias tienen lugares adicionales y cuántas entradas suman. Es el número para
contarle al jefe **a cuántas familias les cambia el precio el día que se instale**. No escribe nada; la salida, a
`build/`.

### 8.6 Antes de darlo por hecho

`bash tool/suite_por_tandas.sh` entera, y `flutter analyze`.

---

## 9. Para publicar

- Versión `6.9.1+76` en `pubspec.yaml` y `installer/junior_eventos_setup.iss`.
- Sin SQL ni migración. El protocolo de siempre: la foto de la mora antes y después (esto no toca la mora).
- Novedades, propuesta: "Entradas: el descuento de los lugares adicionales vale hasta el sorteo".
- `docs/CONTEXTO_v6.9.1_2026-11-16.md` (con "Para retomar en otro chat"), y en `CLAUDE.md`: el punto de "El
  retiro de entradas" y el de "Las cuentas de la venta de entradas" pasan a decir "al 50 % hasta el sorteo;
  después, al precio del día (`DescuentoDeLosLugares`)".
- En `docs/SPEC_venta_de_entradas_2026-11-13.md`, una línea en el punto 8 de la sección 1 que mande a esta spec.

---

## 10. Variante, solo si el usuario la pide: las sorteadas antes del 16-nov conservan el descuento

No está en esta spec. Si la pide:

- `rige` pasa a ser: sin sortear, **o** con el primer sorteo en pie anterior al 16/11/2026 a las 0:00 de
  Argentina (`RegistroSorteo.sorteosEnPie`, sin los automáticos).
- Hace falta `sorteos_mesas` en el equipo que vende: sumarla a `tablasDeLaPuerta`, y decidir qué pasa si la fiesta
  tiene mesas y ningún renglón en el registro (mesas cargadas a mano).
- Los tests de la sección 8 con las dos fechas, y el simulacro separando las fiestas de antes y de después.

---

## 11. Anotado, fuera de esta spec

- Las pantallas y la planilla dicen "50 %" fijo aunque el jefe ponga otro número en PRECIOS. Ya era así; acá no
  se arregla.
- **Antes del sorteo, la entrega no le ofrece VENDERLE ESAS ENTRADAS a la familia que pagó todo** (su freno es
  "Sin mesa", sección 1), y sí a la que debe. Con esta regla, justo la que mejor pagó tiene que ir por VENDER para
  comprar con el descuento. Mostrarlo también con "Sin mesa" es chico y no toca ninguna cuenta (cuántas son sale
  de la cuenta del alumno, no de sus números de mesa), pero no está pedido: **se le pregunta al usuario antes de
  sumarlo.**
