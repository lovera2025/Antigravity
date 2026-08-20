# Junior Eventos v4.8.0 — el historial se toca

**Fecha:** 2026-08-20
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Sin migración de base.** No cambia ninguna tabla ni ninguna columna. Se puede
reinstalar el build anterior encima.

---

## El problema

Los paneles SALDO DEL NEGOCIO y MI BOLSILLO mostraban un historial de solo
lectura. Un movimiento con la fecha, el monto o el concepto equivocados no se
podía corregir desde ahí: había que borrarlo y volver a cargarlo, o convivir con
el error. Y con 116 movimientos en un mes, encontrar uno era scrollear.

---

## MI EMPRESA

### Buscador en los dos paneles

Los dos paneles son el mismo widget instanciado dos veces, así que el buscador
salió en los dos de una. Filtra en memoria sobre la lista que el estado ya trae:
sin base, sin red.

Busca por concepto, categoría, el rubro con el que se muestra —"operadores"
encuentra los pagos guardados como `Personal`— y monto. **No** busca por medio de
pago: para eso están los chips Efectivo/Transfer. justo arriba, y dos puertas para
el mismo filtro hacen que el resultado dependa de cuál usaste.

**El buscador manda sobre el calendario.** Con el calendario en el 6 de agosto,
buscar algo del 17 no devolvía nada y parecía que el sistema lo había perdido.
Ahora, mientras hay texto, el recorte de fechas queda suspendido y se busca en
todo el historial; el panel lo dice. Al limpiar la búsqueda vuelve el día que
estaba elegido — se suspende, no se borra.

El estado vacío dejó de ser mudo: nombra el filtro que está puesto
("No hay coincidencias con «maxi» en Transferencia").

### Editar una fila

Tocás la fila y se abre el editor: monto, fecha, concepto, medio de pago y
eliminar. Sin PIN — a esta pantalla entra solo el jefe.

La fecha cambia el día y **conserva la hora**. Los pagos a operadores abren su
propio editor, que sabe manejar el `evento_id`.

`EditarEgresoBolsilloDialog` existía desde hacía versiones y no lo abría nadie:
era código muerto. Se extendió y pasó a ser `EditarMovimientoDialog`, con el monto
editable (era un cartel de solo lectura) y la reclasificación limitada al
bolsillo, que es donde la bolsa de origen significa algo.

### El aviso de caja

Los movimientos atados a una sesión de caja se editan igual, pero avisando qué se
rompe, con el cierre nombrado por su fecha.

El motivo: `arqueo_cierre` se guarda congelado en la sesión, pero lo esperado se
recalcula cada vez —`arqueo − (cambio inicial + efectivo − egresos)`—. Cambiarle
el monto o el medio de pago a un egreso de una sesión cerrada hace que esa sesión
muestre diferencia para siempre. La fecha no mueve ese número —la sesión agarra
sus egresos por `sesion_caja_id`, no por fecha— pero deja el papel impreso fechado
otro día. El aviso dice cuál de las dos cosas está pasando.

Al guardar, se refresca caja **solo** si la fila pertenece a una sesión.

### Datos vivos

El panel recibía el monto, los chips y la lista como valores fijos al abrirse.
Editando un monto, la lista cambiaba y el número grande de arriba quedaba
mostrando el saldo viejo: dos cifras que no cerraban en la misma pantalla. Ahora
todo se relee del estado en cada rebuild, y el panel no se cierra al editar.

---

## REDUNDANCIAS DADAS DE BAJA

**El chip "Salió del negocio".** Ese número aparecía tres veces en la misma
pantalla: como chip, abierto por rubro en "EN QUÉ SE FUE", y otra vez como neto al
pie del historial. Quedan tres chips y entran en una sola fila.

**El tachito de "EGRESOS DE HOY".** Borraba retiros de caja pidiendo PIN, mientras
el panel borra cualquier fila sin PIN: la misma acción con dos reglas según por
dónde entraras, y la que pedía PIN era justo la de lo más delicado. El borrado
quedó en un solo lugar.

---

## INCONGRUENCIAS ARREGLADAS

### Un solo matcher para todos los buscadores

Había tres reglas distintas para lo mismo, todas `contains` pelado sobre el texto
crudo. Resultado: "maxi operador" encontraba `MAXI OPERADOR` pero "operador maxi"
no encontraba nada, y "anotacion" no daba con "Anotación".

Ahora hay un helper compartido (`features/common/utils/texto_busqueda.dart`):
minúsculas, sin tildes, y todas las palabras en cualquier orden. Lo usan el
buscador maestro, la lista de ingresos, la de egresos y el del panel. Qué campos
mira cada lista sigue siendo distinto a propósito, según lo que esa pantalla ya
filtre por otro lado.

`_normalizarTextoMatch` vivía privado adentro del armador de PDFs, siendo lo único
del sistema que sabía ignorar tildes. Subió al helper.

### Tres lugares imprimían el día en UTC

`Egreso.fecha` es UTC. Un movimiento de las 21:30 del 17/08 se guarda como 18/08
00:30 UTC, y estos tres lo mostraban como **18/08**: la tabla REGISTROS DE EGRESOS
(con la tabla de ingresos doce líneas más arriba haciéndolo bien), el diálogo de
pago a operador y la pantalla de Egresos. Pasan todos por `ArTime`.

### El que corría un pago un día

Los dos anteriores encadenados. Abrías un pago de las 21:30 del 17 → el diálogo
mostraba "18/08" → tocabas el selector y elegías lo que te estaba mostrando →
guardaba `toIso8601String()` de un `DateTime` local, sin marca de zona, a las
00:00. El pago se corría un día por abrirlo y confirmarlo sin querer cambiar nada.

Ahora muestra en AR, guarda con `ArTime.arToUtc()` y conserva la hora. Hay tests
que fijan el caso de las 21:30.

---

## ESTADO

381 tests (eran 379). Analyzer sin errores nuevos. Setup v4.8.0 generado.

Este commit también pone el repositorio al día: el código de 4.7.4 → 4.7.9 estaba
publicado en GitHub Releases pero nunca commiteado, incluido el actualizador
(`app_update_checker.dart`, `app_update_downloader.dart`). Eran seis instaladores
en producción corriendo código que no estaba en git. Se agregó `releases/` al
`.gitignore`: 1 GB de instaladores viejos sin trackear que un `git add -A` habría
intentado subir.

---

## FALTA PROBAR EN LA APP

- Buscar con un día elegido en el calendario: el movimiento tiene que aparecer
  igual y el día tiene que volver al limpiar la búsqueda.
- Editar el monto de una fila y ver que el número grande de arriba se mueva solo.
- Tocar una fila con candado y confirmar que el aviso nombra el cierre y no
  bloquea.
- MI BOLSILLO: que la reclasificación siga estando.

---

## PENDIENTE PARA OTRA TANDA

**"REGISTROS DE EGRESOS"** (`finanzas_view.dart`): tabla de solo lectura, dentro
de un desplegable, con su propio buscador. Muestra menos que el historial del
panel y no deja tocar nada. Con el buscador nuevo no aporta.

**"Operadores" duplicado**: `EN QUÉ SE FUE → Operadores` y justo debajo
`LIQUIDACIÓN POR OPERADOR` con el mismo total, calculado dos veces por caminos
distintos que resultan ser el mismo conjunto. Lo natural es que la línea del
desglose sea la que abre la liquidación.
