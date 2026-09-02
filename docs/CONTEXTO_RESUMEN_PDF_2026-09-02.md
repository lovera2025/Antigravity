# El RESUMEN PDF dejó de adivinar cómo queda la cuenta

**Fecha:** 2026-09-02
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Sin migración de base.** Es puro layout de PDF: no toca datos, ni cuentas, ni sync.
**Sin bump de versión.** Queda sobre la 4.9.3 hasta que se pruebe en la app.

---

## De dónde salió

El botón `RESUMEN PDF` del modal de cobro emite `Detalle_de_pago_<Nombre>.pdf`, el papel
que se le da a la familia **antes** de cobrar. El propio papel lo aclara arriba de todo:

> Este papel no es un recibo: todavía no se registró el pago.

Y abajo del total imprimía un bloque titulado `CÓMO QUEDA LA CUENTA SI PAGÁS ESTE TOTAL`,
con el saldo del plan y la mora **proyectados a después del pago**.

El caso que lo destapó, generado el 2 de septiembre a las 05:47:

```
ACOSTA, NATALIA ALDANA — COLEGIO NACIONAL A
LO QUE SE PAGA HOY
  · Cuota 6 de 9 — vence 30/09/2026            $ 30.000,00
TOTAL A PAGAR AHORA                            $ 30.000,00

CÓMO QUEDA LA CUENTA SI PAGÁS ESTE TOTAL
  Saldo del plan                               $ 90.000,00
  Mora                                              $ 0,00
  Saldo del plan hoy (sin mora):              $ 120.000,00
```

Tres números de plan en la misma hoja —30.000, 90.000 y 120.000— y el más grande, el
único que es la deuda real de hoy, en itálica de 7,5 puntos al pie del recuadro. La
familia leía los 90.000 como si fuera lo que debe.

---

## LA CAUSA: DOS PAPELES CONTANDO LO MISMO

`CÓMO QUEDA LA CUENTA DESPUÉS DE ESTE PAGO` ya existe en el **recibo**, el que sale al
confirmar el cobro (`generarReciboAlumno`), con su tabla de tres columnas, sus cuotas
pagadas y su `FALTA PAGAR DE MORA`. Ahí es un hecho consumado.

En el resumen era la misma cuenta pero en condicional, sobre un pago que todavía no
existía. Nadie necesitaba las dos: el que paga se lleva el recibo cinco segundos después.

---

## EL FIX

**1. Se borró el bloque de proyección** de `generarResumenAbonarAlumno`
(`lib/features/common/services/pdf_service.dart`). Con él se fueron:

- el título `CÓMO QUEDA LA CUENTA SI PAGÁS ESTE TOTAL`
- la fila `Saldo del plan` → `saldoPlanDespues`
- la fila `Mora` → `moraDespues`
- la notita `Saldo del plan hoy (sin mora): $X`

El papel ahora termina en `TOTAL A PAGAR AHORA`.

**2. La leyenda del pie pasó a ser condicional.** Esta:

> La mora no forma parte del saldo del plan de cuotas; sí suma al total a pagar ahora si
> está en la selección.

salía siempre, incluso en papeles donde la mora era `$ 0,00` —el de ACOSTA, sin ir más
lejos—. Ahora sale sólo si el papel efectivamente habla de mora:

```dart
if (moraSeleccionada > 0.01 || moraDespues > 0.01) ...[
```

**3. Limpieza.** `saldoPlanDespues` quedó sin usos y se fue. El parámetro
`saldoActualPlan` también: sus tres usos vivían todos dentro del bloque borrado, así que
salió de la firma y del call site en `detalle_evento_masivo_screen.dart`.

**Balance:** 100 líneas borradas, 20 agregadas, en dos archivos.

---

## SEGUNDA PASADA: EL SUBTOTAL QUE REPETÍA

Con el bloque de proyección afuera apareció la otra redundancia. El papel de **AZUAGA,
MIA** (2 de septiembre, 06:03), una sola cuota pagada por transferencia:

```
LO QUE SE PAGA HOY
  · Cuota 6 de 9 — vence 30/09/2026            $ 35.000,00
  Subtotal liquidación                         $ 35.000,00
```

Y tres renglones más arriba ya decía
`Transferencia total canal: $ 36.500,00 (liquidación $ 35.000,00 + cargo $ 1.500,00)`.
El mismo `$ 35.000,00` tres veces en media hoja.

`mostrarSubtotalLiquido` se prendía con `cargoTotal > 0.01 || hayDescuento || ...`, sin
mirar **cuántas líneas** había que sumar. Con una sola, el subtotal es esa línea otra vez.

Ahora se exige además que haya algo que sumar:

```dart
final bool subtotalRepiteLaUnicaLinea =
    lineasLiquidacion.length + lineasArrastreMora.length <= 1;
```

Con dos o más conceptos el renglón vuelve, que es cuando se gana el lugar: ahí sí evita
sumar tres cuotas de cabeza, y el subtotal (`$ 105.000,00`) **no** es el total
(`$ 109.500,00`, con el cargo adentro). Son números distintos y los dos hacen falta.

---

## LO QUE NO SE TOCÓ

- **El recuadro rojo** `ATENCIÓN: queda debiendo mora (interés por pagar fuera de
  término) por $X` + `No se cobra en este pago. Sigue sumando hasta que se abone.`
  Sigue arriba del total, igual que siempre. Es lo que evita que alguien firme creyendo
  que queda en cero, y no es una proyección: es lo que se está por dejar afuera.
- **El detalle de mora.** Las líneas anidadas bajo cada cuota, el bloque
  `MORA NO COBRADA AL PAGAR` y la línea `Plan $X · Mora $Y` quedaron intactos. La
  consigna fue explícita: si aplica mora, mostrarla **bien detallada**.
- **El recibo.** Cero cambios en `generarReciboAlumno`. Su `CÓMO QUEDA LA CUENTA DESPUÉS
  DE ESTE PAGO` y su `FALTA PAGAR DE MORA` son de otro papel y ahí corresponden.
- **Las cuentas.** Ni una línea de `mora_cuota_calculator.dart` ni de los helpers de
  `cobro_masivo_conceptos_pdf.dart`. `moraPendienteNoIncluida` y su cálculo en el modal
  siguen igual: alimentan el recuadro rojo.

---

## EFECTO SOBRE EL AJUSTE A MEDIA HOJA

`generarResumenAbonarAlumno` mide el cuerpo con `_ajustarParaEntrar(objetivo: _mediaA4)`
y va subiendo escalones de `AjustePdf` —juntar aire, abreviar rótulos, achicar letra—
hasta que entre. Sacar ~85 líneas de widget **libera** espacio: el papel entra más
fácil y los escalones se disparan menos seguido. Un cobro que antes salía abreviado
ahora puede salir intacto.

---

## LA REGLA QUE QUEDA

El resumen es un **presupuesto**: qué se selecciona en el modal, la mora que aplica con
su detalle, y el total a pagar ahora. El recibo es el **comprobante**: ahí va cómo queda
la cuenta.

Si algo del resumen habla en condicional —"quedaría", "si pagás", "saldo después"—, va
al recibo o no va.

---

## ESTADO

**447 tests**, todos pasando. Ninguno construye `generarResumenAbonarAlumno`
(`pdf_ajuste_medido_test.dart` y `recibo_alto_test.dart` miden cuerpos sintéticos, no el
papel real), así que el arnés no cubre este cambio.

`flutter analyze` sobre los dos archivos: **0 errores**. Los 36 avisos son los de
siempre y ninguno cae en las líneas tocadas —el `unnecessary_non_null_assertion` de
`pdf_service.dart` es el `efDet!` que viene de la v4.1.1—.

---

## FALTA PROBAR EN LA APP

La verificación fue por arnés y por diff. El papel real no se generó. Para la primera
oportunidad:

La primera pasada **sí se probó**: los papeles de ACOSTA (efectivo, sin mora) y AZUAGA
(transferencia con cargo) salieron cortados en el total, como se esperaba. Falta:

1. **Dos o más cuotas** en el mismo cobro, con cargo por transferencia: el
   `Subtotal liquidación` tiene que **volver** a aparecer, con la suma de las líneas y
   distinto del total. Es el caso que la segunda pasada podría haber roto.
2. Un alumno **con mora**: confirmar que el recuadro rojo sigue arriba del total, que el
   detalle por cuota sigue anidado y que la leyenda del pie vuelve.
3. Un cobro **con descuento** y una sola línea: el bloque `DESCUENTO LIQUIDACIÓN` con su
   `Subtotal nominal` y su `Descuento` tiene que seguir entero; lo único que se va es el
   `Subtotal liquidación`.
4. Confirmar que entra en media hoja en todos los casos.
5. Reimprimir un recibo viejo desde el historial y ver que su bloque
   `CÓMO QUEDA LA CUENTA DESPUÉS DE ESTE PAGO` está intacto.

---

## Documentos relacionados

- **`docs/CONTEXTO_MORA_OPERATIVA.md`** — doc vivo de mora; de ahí sale qué es cada
  número que este papel imprime.
- **`docs/CONTEXTO_COBRO_PARCIALES_SALDO.md`** — cómo se arma el saldo del plan y por
  qué la mora no lo baja.
- **`docs/CONTEXTO_v4.9.3_2026-08-28.md`** — la tanda anterior, sobre el transporte del
  perdón de mora entre las dos PCs.
