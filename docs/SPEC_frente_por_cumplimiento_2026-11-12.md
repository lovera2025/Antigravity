# SPEC — El frente del salón por cumplimiento, y los papeles que se reparten sin datos de cobro

**Archivo:** `docs/SPEC_frente_por_cumplimiento_2026-11-12.md`
**Rama:** `feature/v4.6-cierre-por-sesiones` (hoy en `6.6.1+70`). Versión sugerida: la que siga (6.7.0).
**SQL:** ninguno. **Migración local:** ninguna. **Tablas nuevas:** ninguna.
**Revisado contra el código** en `9bf41c9` (11-nov, 23:02) y **contra los pagos reales** el 12-nov (solo lectura).

> **Este repo es público.** En esta spec, en los tests, en las muestras y en los mensajes de commit de este trabajo
> **no va ningún nombre de alumno ni su historial de pago**. Los ejemplos usan familias inventadas (F1, F2…).

> **Lo que el usuario cambió el mismo 12-nov, después de leerla** (manda sobre lo que sigue; el
> detalle y el estado, en `docs/CONTEXTO_v6.6.2_2026-11-12.md`):
>
> - **El orden recorre todo el salón**, no solo la primera y la segunda línea: reemplaza "el
>   resto del salón sigue siendo sorteo puro" (secciones 1, 3.6 y 4.3). Por columnas desde el
>   pasillo.
> - **Tolerancia 0** y **sale "· lejos · en la zona elegida"** de la planilla para repartir
>   (puntos 1 y 8 de la sección 12): confirmados.
> - **Ninguna mesa cambia de número.**
> - **Una oración por familia** en "Ver el orden" y en el respaldo (secciones 5.3 y 7).
> - **El candado desaparece solo** cuando la familia ya tiene su mesa: lo que la sección 8
>   dejaba "fuera de la parte B".
> - **La parte B salió sola, en la 6.6.2.** La parte A queda para la 6.7.0, con las
>   correcciones del contexto. La sección 11 dice que la planilla interna no cambia: vale solo
>   para la parte A.

Son dos pedidos del usuario del 12-nov, que salen juntos:

- **Parte A.** Que las mejores mesas (las que dan al paso de los egresados) no salgan del azar: van, en orden, **del que mejor
  cumplió con las cuotas al que peor**. Con un tilde discreto, sin puntajes en pantalla, y con el respaldo guardado para cuando
  una familia reclame.
- **Parte B.** Que la planilla y el plano en papel no digan quién hizo el sorteo, cuántos cambios hubo ni "sin pagar".
  El rojo de SIN MESA queda: el color ya lo dice.

---

## 1. Qué se decidió (12-nov, con el usuario)

1. La mesa **principal** de quien tiene preferencia va **sobre el paso**: la pasarela y su continuación hasta el fondo de las
   mesas. El usuario lo marcó sobre el plano: las dos columnas pegadas al pasillo central, de punta a punta.
2. La **adicional** va **detrás de su principal**: en la misma fila, hacia afuera. Si ahí no hay lugar, la libre más cercana
   de ese mismo lado.
3. El orden es **del que mejor cumplió al peor**, en tres grupos: **quien nunca tuvo mora** (y adelante de todos, quien
   canceló todo más rápido), después **quien tuvo mora**, y al final **quien hizo un plan nuevo**. No hay puntaje a la
   vista: es un tilde.
4. Se puede **elegir familias a mano**, cumplan como cumplan.
5. **Discreto:** se prende en el plano, en privado. El cartel del sorteo, la planilla, el plano en papel, el tótem y
   Recepción no dicen nada.
6. **Con respaldo:** queda escrito por qué cada familia quedó donde quedó.

**Lo que se agrega a propósito, para que sea discreto de verdad:** la preferencia **solo reparte las mesas del paso**
(primera y segunda línea). **El resto del salón sigue siendo sorteo puro.** Si todo el salón se ordenara por cumplimiento,
los que peor pagaron quedarían todos juntos al fondo y se notaría a simple vista.

---

## 2. La regla: quién cumplió mejor

Un servicio puro, sin pantalla ni base: `lib/features/eventos/services/cumplimiento_de_cuotas.dart`.

### 2.1 Con qué datos

- **Los pagos, no los campos de la mora.** `mora_pendiente_tracked`, `mora_tracked_ajuste`, `mora_cobrada_offset` y
  `mora_exenta_hasta` tuvieron correcciones y perdones; las fechas de los pagos no. Es el mismo criterio de
  `PagoAlumno.desdePagos` (`pago_para_sorteo.dart`).
- Entran los pagos que cuentan para la cuota base: `pagoCuentaParaClaseCobro(p, CobroConceptoClase.base)`
  (`cobro_abono_acumulado.dart`). Eso ya deja afuera los anulados, el interés por mora, el cargo por canal, las mesas y las
  sillas. **No se escribe otro clasificador.**
- El importe de cada pago es `monto_gross` (si falta, `monto`), como en `grossHistoricoClaseCobro`.
- La fecha de cada pago es **`fecha_pago` en hora de Argentina** (`ArTime.toAr`), no `created_at`: un cobro cargado tarde
  con la fecha corregida vale por el día en que entró la plata.
- Solo la **cuota base**. Las mesas extra y las sillas no tienen vencimiento ni mora: no cuentan.

### 2.2 La cuenta

Para cada alumno, con `N = totalCuotas` y `cuota = MoraCuotaCalculator.cuotaBaseDe(a)`:

1. **Vencimiento de la cuota n:** `MoraCuotaCalculator.vencimientoCuotaDesdeRegAr(altaAr, n)`, con
   `altaAr = ArTime.toAr(a.createdAt)`. Es el último día del mes (mes del alta + n): **la misma fecha con la que hoy se le
   cobra la mora.**
2. **Cuándo quedó cubierta la cuota n:** se ordenan sus pagos de base por `fecha_pago` (y `created_at` para desempatar) y se
   acumula. La cuota n queda cubierta el día del primer pago con el que
   `floor((acumulado + kToleranciaCuotaPura) / cuota) >= n`. Es la cuenta de `recalcularSaldoDesdePagos`, pago por pago.
   Las entregas parciales y los adelantos caen solos en su lugar.
3. **Corte:** el día (Argentina) en que se aprieta SORTEO.
4. **Días de atraso de la cuota n**, solo si su vencimiento es anterior al corte:
   - cubierta: los días entre el vencimiento y el día en que quedó cubierta (cero si fue antes o ese mismo día);
   - sin cubrir: los días entre el vencimiento y el corte;
   - a esos días **se les restan los congelados**: `MoraCongelada.de(a.id).diasQuietos(cuota: n, vencimientoEfectivo: venc, al: hasta)`.
     Si el jefe le congeló la mora, esos días no son incumplimiento.
5. Las cuotas que todavía no vencieron **no suman ni restan**.

```dart
class CumplimientoDeCuotas {
  final int vencidas;      // cuotas con vencimiento anterior al corte
  final int tarde;         // de esas, las que tienen 1 día de atraso o más
  final int diasDeAtraso;  // la suma de los días de todas
  final int impagas;       // vencidas y sin cubrir al corte
  final int cubiertas;     // cuotas cubiertas al corte, vencidas o no
  final DateTime? canceloEl; // el día en que quedó cubierta la última; null si falta alguna
  final List<AtrasoDeCuota> detalle; // n, vencimiento, cubierta (o null), días
}

static CumplimientoDeCuotas de(
  ContratoAlumno a,
  Iterable<Map<String, dynamic>> pagos, {
  required DateTime corteAr,
});
```

### 2.3 El orden (regla del usuario, 12-nov)

Tres grupos, de mejor a peor. **Primero manda el grupo; después, el orden de adentro.**

**Grupo 1 — Nunca tuvo mora.** 0 días de atraso en todas sus cuotas vencidas, y no es de plan nuevo.

1. Primero quienes **ya cancelaron toda la cuota base**, por el día en que la cancelaron (`canceloEl`): el más antiguo
   adelante. Es "quien pagó la totalidad lo más rápido posible".
2. Después quienes están al día sin haber cancelado: **más cuotas cubiertas**, adelante.
3. A igualdad, **al azar**, con el mismo `Random` del sorteo.

**Grupo 2 — Tuvo mora.** Algún día de atraso, y no es de plan nuevo.

1. **Menos días de atraso** acumulados;
2. a igualdad, más cuotas vencidas pagadas en término (`vencidas − tarde`);
3. a igualdad, al azar.

**Grupo 3 — Plan nuevo** (2.4). Va último aunque hoy no deba nada.

1. El plan que **empezó antes**, adelante: cuanto más cerca de diciembre, peor;
2. a igualdad, **más cuotas**, adelante: en menos cuotas o en una sola, peor;
3. a igualdad, al azar.

Por qué los días y no "cuántas veces pagó tarde": es la vara con la que la empresa ya cobra la mora (1 % por día y por
cuota). Ante un reclamo, el número se explica solo.

**No se usa tolerancia** (`kToleranciaDiasDeAtraso = 0`, en un solo lugar). **Con los grupos pesa más que antes:** un solo
día de atraso saca a la familia del grupo 1. Un vencimiento que cae sábado y se paga el lunes son 2 días, igual que para
la mora. Ver la sección 12.

"Cancelar" es la **cuota base**. Las mesas extra y las sillas no cuentan: una familia que canceló en junio y compró una mesa
en octubre no pierde su lugar.

### 2.4 Plan nuevo: cómo se reconoce

**La app no guarda cuándo se cambió un plan.** Revisado: `contratos_alumnos` no tiene esa fecha, `updated_at` cambia con
cada cobro, `mora_cambios` existe desde el 2-nov y en el programa no hay nada que se llame "plan nuevo". **Se deduce.**

**La señal fuerte es el monto** (contexto del usuario, 12-nov): cuando se arma un plan nuevo, **a las cuotas del principio
se les suman todos los recargos y se junta todo**. Por eso el total de la cuota base de ese contrato queda **más alto que
el de sus compañeros**, y en menos cuotas.

Es de plan nuevo el contrato que cumple **las tres**:

1. **Menos cuotas que la mayoría de su fiesta:** `total_cuotas` menor que el más repetido entre los alumnos de la fiesta.
   (No `eventos.cantidad_cuotas`: en varias fiestas dice 1 y los contratos tienen 9.)
2. **Un total de cuota base mayor que el de la mayoría de su fiesta:** `monto_total_pactado − mesa_extra_precio −
   sillas_extra_precio_total` (la cuenta de `cuotaBaseDe`, sin dividir) por encima del más repetido. Ahí están los
   recargos.
3. **No es un alta tardía:** su alta es del mismo mes que la de la mayoría de su fiesta. Quien se anotó en agosto o en
   septiembre también tiene menos cuotas y un total más alto, pero porque entró después y con otro precio: se mide como
   cualquiera, en el grupo 1 o en el 2.

**La fecha de inicio del plan** no decide si es plan nuevo: **ordena el grupo 3** (2.3). Es la de su primer pago de base
cuyo concepto lleva el plan de hoy, "Cuota Base (k/N)" con `N = total_cuotas`; si ningún concepto lo dice, su primer pago
de base. (Antes de escribir un lector de "k/N", buscar si `concepto_pago_display.dart` ya tiene uno.)

Lo que **no** es plan nuevo:

- menos cuotas con **el mismo total** que los demás (un contado en entregas desde marzo, o un plan de 6 cuotas al precio
  de todos): no hay recargos sumados;
- un alta tardía;
- más cuotas que la mayoría.

Van por su cumplimiento, y "Ver el orden" los marca "plan distinto".

**Es una deducción y puede fallar.** Por eso "Ver el orden" (5.3) marca cada "plan nuevo" con su fecha de inicio, y el
jefe corrige con "Siempre" o "Nunca". Guardar la fecha del cambio de plan de acá en adelante pide una columna (SQL): queda
anotado, fuera de este trabajo.

### 2.5 Casos que hay que tener presentes

| Caso | Qué hace la regla |
|---|---|
| Reincorporado de una baja temporal | Igual que uno que nunca estuvo de baja (regla de la 6.1.0). |
| `mora_exenta_hasta` (la mora de esos meses ya se pagó) | **No borra el atraso.** Pagó la mora, pero pagó tarde. |
| Perdón de mora del jefe | **No borra el atraso.** Si el jefe quiere a esa familia adelante, la tilda a mano (sección 5). |
| Mora congelada | Los días congelados no cuentan. |
| Alta tardía (se inscribió meses después) | Sus cuotas vencen más tarde. No es plan nuevo: va al grupo 1 o al 2 por sus fechas. |
| Menos cuotas, pagando desde el principio | No es plan nuevo. Se mide igual; si su única cuota venció hace meses, cae al grupo 2. **"Ver el orden" lo marca "plan distinto" y el jefe decide.** |
| Plan nuevo que ya canceló todo | Grupo 3 igual: canceló, pero con un plan hecho a último momento. |
| Canceló todo temprano, pero antes tuvo una cuota tarde | Grupo 2: tuvo mora. |
| Sin ningún pago de base | No entra al sorteo (regla de siempre): no hay nada que ordenar. |
| Baja temporal vigente | No entra (`esBajaTemporal`), como hoy. |

### 2.6 Probado con los pagos reales (12-nov, solo lectura, con SQL equivalente)

- En una fiesta de 44 familias: **grupo 1, 15** (6 ya cancelaron, la primera el 8 de abril; 9 al día), **grupo 2, 27**
  (de 11 a 562 días de atraso, bien repartidos), **grupo 3, 2** (planes empezados el 6 y el 11 de noviembre).
- En las 9 fiestas cargadas (642 contratos): **35 de plan nuevo**, empezados entre agosto y noviembre. **Las tres
  condiciones hacen falta juntas:**
  - el monto solo marcaría de más a 5 altas tardías (entraron en agosto o septiembre con otro precio);
  - sin el monto, entraría un plan de 6 cuotas al mismo total que sus compañeros;
  - ningún contrato con las cuotas de la mayoría tiene un total más alto: no hay planes nuevos "escondidos" en 9 cuotas.
- Otros 9 contratos tienen menos cuotas y **no** son plan nuevo. 44 familias nunca tuvieron mora y ya cancelaron.
- El grupo 1 tiene entre 5 y 29 familias por fiesta. En las fiestas grandes hay más familias del grupo 1 que mesas de
  primera línea: entre las que cumplieron igual, decide el azar.
- Hay 118 cuotas pagadas con 1 a 3 días de atraso (sobre todo vencimientos de fin de semana). Es lo que cambiaría una
  tolerancia.

---

## 3. Qué mesas dan al paso

Otro servicio puro: `lib/features/plano/services/mesas_del_paso.dart`. Trabaja sobre `ArmadoSalon`, sin familias.

1. **La hoja:** la que tiene el sector `TipoSector.pasarela`. Si ninguna lo tiene, la del `TipoSector.escenario`. Las demás
   hojas y las mesas del pasto (`MesaPlano.pasto`) **nunca** son del paso.
2. **El eje del paso:** la recta que pasa por el centro de la pasarela, paralela a su lado largo, **prolongada hasta la
   última mesa**. Sin pasarela: la perpendicular al escenario por su centro. Sin pasarela ni escenario: no hay paso, y la
   opción queda apagada con su explicación.
3. **De cada mesa:** de qué **lado** del eje está, a qué distancia del escenario a lo largo del eje (**fila**) y a qué
   distancia del eje (**profundidad**).
4. **Filas:** las mesas de un mismo lado cuya distancia al escenario difiere en menos de medio lugar (el lugar es
   `pegadasHastaU / ArmarAMedida.pegadasHastaPasos`, la medida de `SorteoConPlano._lugar`). Una mesa corrida a mano en
   Acomodar sigue en su fila.
5. **Línea:** en cada fila y lado, las mesas en orden de profundidad: la más cercana al eje es **primera línea**, la que
   sigue **segunda**, etc. **Es el puesto en su fila, no los metros:** donde la pasarela deja un hueco al lado, la primera
   mesa de la fila es primera línea igual.
6. **Mesas del paso:** las de línea 1 y 2 (`kLineasDelPaso = 2`, en un solo lugar).
7. **De mejor a peor mesa:** por línea, después por fila (la más cercana al escenario primero), y a igualdad el lado
   izquierdo mirando desde el Ingreso.
8. **Detrás de una mesa:** la de su misma fila y lado con la línea siguiente.

Sobre el plano real de la fiesta de 44 familias (63 mesas, dos bloques y pasarela al medio, 7 filas por lado): 14 mesas
de primera línea y 14 de segunda. La "detrás" de cada una resulta pegada (`ArmadoSalon.pegadas`) y con el número seguido, así que la familia
se dibuja y se imprime "junta". **Eso depende de la numeración:** ver la prueba 9.6.

---

## 4. Cómo se reparten

Va **antes** del sorteo de siempre y **no toca el motor** (`SorteoMesasMotor`).

### 4.1 Cuándo corre

- Solo si **ninguna familia tiene mesa todavía** (el primer sorteo de la fiesta, o después de deshacerlo entero). En
  "sortear a los que faltan", en las mesas nuevas al fondo (`MesasNuevasAlFondo`) y en la mesa que se da sola
  (`MesaNuevaSola`) **no corre**: nadie se mueve y nadie nuevo pasa adelante.
- Solo si el plano tiene paso (sección 3) y hay alguna familia con preferencia (sección 5).

### 4.2 Quiénes y en qué orden

Las familias que este sorteo va a sentar: los pedidos de `SorteoMesasMotor.pedidos` con `esNuevo`, ya sin las de
`ExclusionSorteo.sinMesa` y **sin mesa fijada**. Cada una entra con las mesas que ese pedido le da (a la de
`ExclusionSorteo.soloBase`, solo la principal):

1. primero las tildadas **"Siempre"**, ordenadas entre sí por la regla de la sección 2;
2. después, si el tilde general está prendido, todas las demás menos las tildadas **"Nunca"**, por la regla.

### 4.3 Qué mesa le toca a cada una

Las mesas del paso que están para sortear: ni fijadas, ni libres o reservadas (`ConfigPlano.libres`), ni fuera de "hasta
qué mesa" si el jefe lo acortó.

Para cada familia, en orden:

1. **Sus mesas de adelante:** la principal más las adicionales que el cartel deja junto a la principal. Es la cuenta que ya
   existe: todas, o `mesas − SorteoConPlano.mesasAlFinal(...)` si el jefe eligió "Las mesas adicionales: Al final".
   **Las que van al final siguen yendo al final, como las de cualquiera.**
2. **La principal:** la mejor mesa del paso libre **de primera línea**. Si no queda ninguna, la mejor de segunda.
   Entre dos mesas igual de buenas se prefiere la que tiene libre "detrás" todo lo que la familia necesita.
3. **Cada adicional de adelante:** la mesa "detrás" de la anterior. Si está ocupada o no existe (fin de la fila): la libre
   pegada a alguna de las suyas que esté más lejos del eje. Si tampoco: la libre más cercana de ese lado. **Nunca una de
   primera línea si hay otra.**
4. Cuando no queda ninguna mesa del paso libre, **la etapa termina**. Esa familia y todas las que siguen van al sorteo
   común, con el resto del salón, como hoy.

Las mesas de segunda línea tienen los dos usos que marcó el usuario: adicional de la familia de adelante, o principal de la
siguiente con preferencia si la de adelante no tiene adicional.

### 4.4 Cómo entra al sorteo

Lo que salió de 4.3 entra al sorteo **por el camino de las mesas fijadas**, que ya existe y está probado: en `_entera` y en
`_bloques`, las familias de `b.conFijada` "van aparte", se quedan con sus mesas y no entran en la cuenta de "hasta qué mesa".

- Es un dato nuevo de `EntradaSorteoPlano` (por ejemplo `delFrente: Map<String, List<int>>`, vacío por defecto).
  **No se escribe en `ConfigPlano.fijadas`:** una fijada se dibuja con candado y con motivo, y esto no se muestra.
- `preparar`, `sortear` y `validar` tienen que tratarlas igual. `validar` no les pide "todas juntas" si una adicional cayó
  en "la libre más cercana": les pide lo mismo que a una fijada.
- El orden de 4.2 usa el azar **solo en los empates**, con el `Random` que recibe `sortear`. Con el mismo `Random`, el mismo
  resultado.
- Vacío, **todo da exactamente lo de hoy**. Tiene que quedar probado (9.4).

### 4.5 Sorteo por división (`ModoSorteo.bloques`)

Lo mismo, división por división: las mesas del paso **que son del bloque** (`BloqueDivision.contiene`, nunca comparando
números) para las familias de esa división, ordenadas entre ellas. Un bloque que no tiene ninguna mesa del paso no reparte
nada, y el panel del plano lo dice (5.3). **Hace falta desde el primer día:** de las 7 fiestas que faltan sortear, 2 están
en "por división".

---

## 5. Dónde se prende: en el plano, en privado

PLANO → PERSONALIZAR → pestaña **Mesas** (`ModoPersonalizar.mesas`), que ya es solo de modo jefe. **Los rótulos no dicen
"cumplimiento", "pago" ni "deuda":** alguien puede estar mirando la pantalla.

### 5.1 El tilde general

En el panel de Mesas, un renglón: **"El frente, por orden"** (apagado por defecto). Debajo, en chico y solo si está prendido:
"14 mesas de primera línea y 14 de segunda." Si el plano no tiene paso: apagado, con "Este salón no tiene pasarela ni
escenario dibujados."

### 5.2 El tilde de cada familia

Al tocar una familia **sin mesa** (`_accionesDeLoElegido`, al lado de "Fijarle mesas"), un botón **"Frente"** con tres
opciones:

- **Según el orden** (por defecto): entra si el tilde general está prendido.
- **Siempre**: va primero, con el general prendido o apagado. Es "elegir a algunos a mano".
- **Nunca**: no entra aunque el general esté prendido.

La familia tildada "Siempre" o "Nunca" lleva una marca chica y neutra en la lista de Personalizar (un punto), sin texto.
Fuera de Personalizar no se ve.

### 5.3 "Ver el orden"

Un botón en el mismo panel, solo en modo jefe. Abre la lista de las familias que entrarían, **en orden y sin números**:
puesto, apellido y, si corresponde, una marca: "a mano", "plan nuevo" (con su fecha de inicio) o "plan distinto". Los
tres grupos van separados por una raya, sin título. Al tocar una familia, su detalle: cada cuota vencida con su
vencimiento, el día en que quedó cubierta y los días de atraso; y, si canceló, cuándo. Arriba: "Entran N familias; quedan M mesas del paso."
Sirve para que el jefe revise **antes** de sortear, y es la misma pantalla del respaldo (sección 7).

### 5.4 Lo que no cambia en ningún lado

- **El cartel del SORTEO no dice nada.** Ni un tilde, ni un aviso, ni una palabra en la vista previa.
- La planilla del sorteo (las dos versiones), el plano en papel, el tótem, Recepción y la puerta: nada.
- Los avisos de después del sorteo ("N sin mesa…") no nombran el frente.
- El plano dibuja a esas familias como a cualquiera: sin candado, sin color propio.

---

## 6. Dónde se guarda

### 6.1 La elección: en la `config` del plano

`planos_evento.config`, clave nueva **`frente`**:

```json
"frente": { "general": true, "siempre": ["<alumnoId>", "..."], "nunca": ["<alumnoId>"], "el": "2026-11-12T15:40:00Z" }
```

- `ConfigPlano` ya conserva las claves que no conoce (`otras`): una PC con la 6.6.1 que guarde el plano no la borra.
- Se agrega a `_conocidas`, con su campo y su `copyWith`. Sin la clave: todo apagado.
- **La fila del plano sube entera.** Antes de sortear ya se lee el plano de la nube (`leerPlanoParaSortear`): el frente se
  toma de ahí, no del de esta PC.
- Un alumno de la lista que ya no está, o que quedó de baja, se ignora sin error.

### 6.2 Lo que pasó: en el registro del sorteo

`sorteos_mesas.resultado`, clave nueva **`_frente`** (`SorteoMesasRegistro.claveFrente`), junto a `_lejos`, `_zonas` y
`_al_final`. **No se agrega ningún valor a `sorteos_mesas.tipo`.** Una versión que no conoce la clave la ignora.

```json
"_frente": {
  "_": "regla=1;corte=2026-11-12;lineas=2;general=1",
  "<alumnoId>": "p=1;g=1;o=c;d=0;t=0;v=7;c=2026-04-08;m=1",
  "<alumnoId>": "p=2;g=2;o=m;d=34;t=2;v=7;m=33,34",
  "<alumnoId>": "p=23;g=2;o=c;d=47;t=3;v=7;m=",
  "<alumnoId>": "p=43;g=3;o=c;d=196;t=1;v=1;i=2026-11-06;m="
}
```

- Una entrada por **cada familia que entró al orden**, no solo las que recibieron mesa: la pregunta va a ser "¿por qué yo no?".
- `p` puesto · `g` grupo (1, 2 o 3) · `o` origen (`c` por cumplimiento, `m` a mano) · `d` días de atraso · `t` cuotas
  tarde · `v` cuotas vencidas · `c` el día en que canceló (si canceló) · `i` el inicio del plan nuevo (solo grupo 3) ·
  `m` las mesas que recibió por el frente (vacío: fue al sorteo común).
- `regla=1` es la versión de la sección 2 (los grupos y la deducción del plan nuevo incluidos). Si la regla cambia, cambia el número y el respaldo viejo se sigue leyendo.
- Las tildadas "Nunca" no figuran.

---

## 7. El respaldo, para cuando alguien reclama

PLANO → HISTORIAL (`HistorialSorteo`). **El Historial hoy lo abre cualquiera** (`onHistorial` no depende del rol): el renglón
del sorteo se ve igual que hoy, sin nada del frente. Solo en modo jefe (`esRolJefeProvider`) ese renglón tiene
**"Ver el orden"**, que abre la pantalla de 5.3 con lo guardado:

- el orden completo de ese día, con la fecha de corte;
- de cada familia: su puesto, si fue a mano, sus mesas y el detalle cuota por cuota;
- el detalle se rearma con los pagos de hoy. **Si no coincide con lo guardado** (se anuló o se corrigió un cobro después),
  manda lo guardado y la pantalla dice: "Los pagos cambiaron después del sorteo."

Una familia elegida **a mano** figura como "a mano": su respaldo es la decisión del jefe, no el cumplimiento. Tiene que
quedar así de claro para quien lo lea después.

No se imprime. No sale de modo jefe.

---

## 8. Parte B: la planilla y el plano en papel, sin datos de cobro

Lo que pidió el usuario (12-nov): que el encabezado no diga que el jefe hizo cambios, y que el renglón de quien no tiene
mesa diga **SIN MESA en rojo y nada más**: "el color ya dice todo". Vale para **las dos versiones** de la planilla
(`VersionPlanillaSorteo.interna` y `paraRepartir`) y para el plano en papel.

| Dónde | Hoy | Queda |
|---|---|---|
| Encabezado (`RegistroSorteo.lineaParaPlanilla`) | "Sorteo del 11/11/2026 19:33 hs · Jefe · 5 cambios con motivo · 2 cambios a mano después" | **"Sorteo del 11/11/2026 19:33 hs"** |
| Encabezado con dos sorteos (`_primerSorteo`, `_losQueFaltaban`) | "… · Jefe · 128 familias" y "Los que faltaban: … · Jefe · 5 familias (antes, otro sorteo: …)" | lo mismo **sin "· Jefe"** |
| Celda de la mesa (`_celdaMesa`) | "SIN MESA" y abajo "sin pagar", en rojo | **"SIN MESA" en rojo**, sin el segundo renglón |
| Fondo de la fila (`f.sinMesa` → `rojoSinMesa`) y referencia "Sin mesa" | rojo | **igual que hoy** |
| Texto de la fila (`PlanillaSorteo.fila`) | "sin mesa (sin pagar)" | **"sin mesa"** |
| Adicional y sillas | "1 mesa extra (sin pagar)", "3 (sin pagar)" | **sin "(sin pagar)"** |
| Aviso de mesas (`alertaMesas`) | "(!) le falta 1 mesa (sin pagar)" | **"(!) le falta 1 mesa"** |
| Tarjetas del resumen (`_resumen`) | "Sin mesa: N · sin pagar la cuota base", "Sillas extra … +N sin pagar" | **"Sin mesa: N"** sin detalle; "Sillas extra" sin el "+N sin pagar" |
| Plano en papel (`plano_pdf.dart`, `extra: lineaSorteo`) | la línea completa | la misma línea corta |

Cómo:

- `lineaParaPlanilla` deja de agregar `_quien(...)`, `conMotivo` y `aMano`. Los dos llamadores
  (`detalle_evento_masivo_screen.dart` ≈3583 y `plano_evento_screen.dart` ≈1337) no cambian.
- `ResumenRegistroSorteo.cambiosConMotivo` y `cambiosAMano` **se siguen calculando**: si alguien más los lee, no se rompe.
  Los cambios con motivo se siguen viendo donde corresponde, en PLANO → HISTORIAL.
- En `PlanillaSorteo.fila` sale "(sin pagar)" de sus cuatro lugares: mesa principal, mesas extra, aviso de mesas y sillas. `FilaPlanillaSorteo.sinMesa` no cambia: es lo que pinta el rojo.
- **"Sin pagar" no aparece en ningún papel del sorteo.** Los avisos de pantalla del jefe después de sortear ("N sin mesa por
  no tener nada pagado") no son papel y no se tocan.

**Propuesto, a confirmar** (no lo pidió el usuario, va en la misma línea): en "Para repartir", sacar de la adicional
"· lejos · en la zona elegida" y dejar solo los números ("13 · 40"). Dice que a esa familia la separaron a propósito.

**Fuera de la parte B** (anotado): la referencia "Fijada antes del sorteo" del plano en papel y el contador "2 fijadas".

---

## 9. Pruebas

Todas sin base y sin nube, con familias inventadas.

1. **`test/cumplimiento_de_cuotas_test.dart`**
   - en término, tarde, sin cubrir, adelantada, y la que todavía no venció;
   - entregas parciales que completan una cuota en el tercer pago;
   - un pago de dos cuotas juntas;
   - anulados, interés por mora, cargo por canal, mesa y sillas: no cuentan;
   - `fecha_pago` corregida hacia atrás: vale la fecha, no `created_at`;
   - días congelados: se restan; `mora_exenta_hasta`: no cambia nada;
   - plan de 1 cuota; alta tardía;
   - **atado a la app:** para cada caso, la cantidad de cuotas cubiertas al final es la `cuotasBase` de
     `recalcularSaldoDesdePagos`.
2. **El orden y los grupos**
   - grupo 1 antes que el 2, y el 2 antes que el 3, siempre;
   - en el grupo 1: los que cancelaron, por fecha; después los que están al día, por cuotas cubiertas;
   - un día de atraso manda al grupo 2, aunque después haya cancelado todo;
   - en el grupo 2: días, después cuotas en término;
   - en el grupo 3: inicio del plan, después cantidad de cuotas;
   - los empates, al azar: con el mismo `Random`, el mismo orden.
   - **Plan nuevo:** menos cuotas, total más alto y alta con la mayoría → sí; alta tardía con total más alto → no; menos
     cuotas con el mismo total → no; más cuotas que la mayoría → no; una fiesta donde todos tienen el mismo plan → nadie; con pagos del plan viejo ("…/9") y del nuevo ("…/1"), el inicio es el primer pago del
     nuevo; plan nuevo ya cancelado → grupo 3 igual.
3. **`test/mesas_del_paso_test.dart`**: un salón a medida con pasarela (las filas de adentro tienen una columna más), uno
   sin pasarela, uno de dos hojas, uno con pasto, uno con una mesa corrida a mano, uno sin escenario.
4. **`test/sorteo_frente_test.dart`**
   - con `delFrente` vacío, **el resultado es idéntico al de hoy** con el mismo `Random` (entero y por división);
   - 200 sorteos por caso: pasan `validar`, nadie queda en dos mesas, ninguna mesa sale dos veces;
   - la principal de cada familia con frente está en línea 1 o 2, y ninguna con peor puesto quedó en una mesa mejor;
   - la adicional queda detrás; con "detrás" ocupada, pegada y más afuera;
   - con "Al final", las del final van al final también para las del frente;
   - con mesas fijadas y libres sobre el paso: no se tocan;
   - con alguna familia ya con mesa: la etapa no corre;
   - por división, con un bloque sin mesas del paso.
5. **`test/registro_sorteo_test.dart`**: `_frente` va y vuelve; una versión que no lo conoce (el `fromMap` de hoy) lo ignora
   y lee el resto igual.
6. **La numeración:** con "Fila por fila" (`FinNumeracion.filas`) y con la de siempre, una familia del frente con adicional
   se dibuja junta (`PlanoDeLaFiesta.familias`) y la planilla **no** la marca "(separada)" (`SalonMesas.tramos` mira números
   seguidos). Si en alguna numeración "detrás" no es el número que sigue, se prefiere, entre las pegadas de más afuera, la
   de número seguido.
7. **`test/planilla_sorteo_test.dart`, `test/registro_sorteo_test.dart` y el del PDF**: en las dos versiones, ninguna página
   contiene "sin pagar", "Jefe", "con motivo" ni "a mano después"; la fila sin mesa dice "SIN MESA" y va en rojo. Los tests
   de hoy que esperan "· Jefe" o "(sin pagar)" **se cambian a propósito**, y el commit lo dice: cambió lo pedido, no se
   aflojó una prueba.
8. **Config:** `frente` va y vuelve; un `ConfigPlano` de la 6.6.1 (sin el campo) lo conserva en `otras` al guardar.
9. **Muestra** en `tool/`, como las otras: el salón de 63 mesas, con 44 familias inventadas, para mirar el resultado en el
   plano sin base ni nube.

---

## 10. Entre versiones y entre PCs

- **Sin SQL y sin migración.** Todo viaja en dos textos que ya existen (`planos_evento.config` y `sorteos_mesas.resultado`).
- **El sorteo, desde una PC con la versión nueva.** Una PC vieja que sortee no conoce `frente`: sortea todo al azar, sin
  error. Va en las novedades y en el CONTEXTO, como se hizo con la 6.6.1.
- Una PC vieja que guarde el plano conserva `frente`. Una que mire el Historial no ve `_frente`: lo ignora.
- La mora no se toca: ni campos, ni fotos, ni revisión.

---

## 11. Lo que NO se cambia

- `SorteoMesasMotor`, `CasillerosPlano`, las fijadas, las libres, las reservadas, "lejos", las zonas y "Al final".
- Quién entra al sorteo (`pago_para_sorteo.dart`): sigue siendo "algo pagado".
- `sorteos_mesas.tipo`, las tablas y las reglas de la nube.
- La planilla interna, el tótem, Recepción.

---

## 12. Para confirmar con el usuario antes de programar

Cada una tiene su opción por defecto escrita arriba; se cambian en un solo lugar.

1. **Tolerancia: 0 días.** Con los grupos, un solo día de atraso saca a una familia del grupo 1. Es lo mismo que "se le
   cobró mora". Hay 118 cuotas con 1 a 3 días, casi todas por vencimientos de fin de semana. ¿Queda en 0, o 2 o 3?
2. **"Canceló todo" es la cuota base**, sin mirar mesas extra ni sillas.
3. **El plan nuevo se deduce** (2.4) por menos cuotas y un total más alto que el de sus compañeros, porque la fecha del
   cambio no está guardada. El jefe lo revisa en "Ver el orden".
4. **El perdón de mora no borra el atraso.** El jefe puede tildar "Siempre".
5. **Las líneas:** primera y segunda. ¿O solo la primera?
6. **Los rótulos:** "El frente, por orden" y "Frente: Según el orden · Siempre · Nunca".
7. **Las fiestas ya sorteadas no se tocan.** Para usarlo en una, habría que deshacer su sorteo entero: lo decide el jefe.
8. **Parte B:** ¿sale también "· lejos · en la zona elegida" de la planilla para repartir?

## 13. Riesgos

- **Lo que se le dice a la gente.** Si la fiesta se anuncia como sorteo y el frente se reparte por orden de pago, la
  explicación que se sostiene es simple: "quien pagó en término eligió antes; el resto se sorteó". El respaldo de la
  sección 7 la acompaña. Qué se comunica y cuándo lo decide el jefe.
- **Las elegidas a mano no tienen ese respaldo.** Quedan anotadas como "a mano".
- **Un plan nuevo mal deducido** deja último a quien no corresponde, o deja pasar a quien sí. Lo ataja "Ver el orden" antes
  de sortear; lo cura de raíz guardar la fecha del cambio de plan.
- **Un dato de alta mal cargado** (`created_at`) corre todos los vencimientos de ese alumno. Es el mismo dato que usa la
  mora, así que el error ya se vería ahí; "Ver el orden" lo deja a la vista antes de sortear.
