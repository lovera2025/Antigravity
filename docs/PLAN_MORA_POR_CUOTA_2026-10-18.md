# Plan: la fase 2 de la mora por cuota (6.1.0)

Fecha: 18-oct-2026. Rama: `feature/v4.6-cierre-por-sesiones`. **Solo planeado: no hay nada programado.** Sale de la
especificación del usuario del 16-oct (`docs/pendientes/mora-por-cuota.md`) y de lo medido el 18-oct en su base.

## 1. Lo que hay hoy (con la fase 1)

- **La ventana de cobro ya muestra la mora cuota por cuota**, cada una con su casilla. Primero va la mora de la
  ficha (la de cuotas que se pagaron sin su mora: "Mora de la cuota 1 · Abr") y después la de las cuotas vencidas
  ("Cuota 3 · Jun · 110 d"). El recibo nombra cada cuota.
- **Pero va en fila, de la más vieja a la más nueva.** Tildar una cuota tilda las anteriores y destildar una destilda
  las siguientes (`aplicarSeleccionPrefijo` en `detalle_evento_masivo_screen.dart`). Perdonar es igual
  para la mora de la ficha (`perdonar_mora_alumno_dialog.dart`). El motivo: la ficha guarda **un solo monto**
  (`mora_pendiente_tracked`), y de qué cuota es cada parte se reconstruye repasando los pagos
  (`MoraTrackedOrigen.inferir`).
- **Medido en su base (18-oct):** de los 51 alumnos con mora en la ficha, **50 se explican cuota por cuota**
  ($1.592.537). El único que no, ESPINOZA, DENIS AIMARA, son los $87.600 inventados que la fase 1 deja en $0. Los 40
  ajustes de su PC son todos perdones.

**Entonces, lo que la fase 2 agrega a la vista es una sola cosa:** cada cuota suelta. Cobrar o perdonar la mora de la
cuota 3 dejando la de la 2, y que lo que se perdonó o se cobró de una cuota quede anotado a nombre de esa cuota para
siempre, sin reconstruirlo.

## 2. La decisión que es del usuario

- **A. Quedarse con lo de hoy** (en fila, de la más vieja a la más nueva). No hay tabla nueva ni mudanza. Se suma
  una revisión que avisa si la mora de una ficha deja de explicarse cuota por cuota, como pasó con DENIS. La 6.1.0
  sigue con el salón.
- **B. La fase 2:** cada cuota suelta, guardada. Es lo de abajo: unas cinco partes, en lo más delicado del programa.

**Recomendación: A**, salvo que en la oficina haga falta cobrar o perdonar salteado. Hoy, con la fase 1, la ventana
ya hace lo que se le mostró en el widget. La B cambia el cobro de todos a un mes del sorteo y a dos de las fiestas,
sin entorno de prueba.

## 3. Si elige B: las partes (cada una cierra sola, con commit)

**Correcciones a la especificación** (choca con reglas del proyecto, ver CLAUDE.md):
- Nada de columnas nuevas en `contratos_alumnos`: la baja sigue siendo el `[BAJA]`.
- Nada de CHECK ni UNIQUE en la nube. Dos PCs sin internet no pueden crear dos filas de la misma cuota porque el id
  es fijo por contrato y cuota (`UuidUtils`, como `notas_operativas_contrato`).
- SQLite directo (`local_database.dart`, v74, con la copia antes de migrar), no Drift.
- **Una mora se puede cobrar en parte** (hoy existe: "(parcial)"). Por eso la fila guarda montos (congelado, cobrado
  y perdonado) y el estado sale de ahí, no de una sola palabra.
- **Las versiones tienen que convivir.** Una PC con la 6.0.0 lee `mora_pendiente_tracked`, así que la 6.1.0 lo
  sigue escribiendo, igual a la suma de lo pendiente en la tabla. Los campos viejos se dejan de escribir recién
  cuando ninguna PC tenga la 6.0.0.

**Las partes:**
1. **La tabla** `mora_cuotas_contrato`: una fila por cuota que dejó mora pendiente, con id fijo, sin CHECK, con su
   trigger de `updated_at` y los permisos de `pagos_contrato_alumno`. Entra en la sincronización y en la puesta al
   día. SQL de la nube con su vuelta atrás, que se corre antes de instalar y con su OK. Test que compara el SQL con
   lo que manda la app.
2. **La mudanza**, en simulacro primero. Las filas salen de lo que hoy reconstruye `MoraTrackedOrigen` (explica el
   100 % después de la fase 1). Los 40 perdones pasan a "perdonado" en la cuota más vieja primero, que es como los
   aplicó el diálogo. Sobre una copia de su base, la mora de cada alumno tiene que dar **exactamente** lo mismo antes
   y después; lo que no dé igual se lista y se mira con él, sin forzarlo.
3. **El cobro con cada cuota suelta.** La ventana lee las filas en vez de reconstruir; cada casilla va sola; al
   cobrar una cuota sin su mora se guarda su fila; al cobrar una mora, su fila. Todo en la misma transacción del
   cobro (`registrarPagosLote`). Antes de programar, la maqueta ya aprobada.
4. **Perdonar por cuota**, suelto, en el diálogo de modo jefe, con quién y cuándo.
5. **Verificación:** `tool/cobro_igual_que_hoy_test.dart` (cobrando en fila tiene que dar idéntico a la 6.0.0), el
   simulacro de la mudanza, los papeles de 5 o 6 alumnos que él elija lado a lado, y roturas a propósito.

**Lo que no cambia en ninguna de las dos:** la cuenta (1 % por día de la cuota base, fin de mes), la eximición, la
regla de la mora del usuario, el recibo de una hoja.

## 4. Preguntas para el usuario

1. ¿En la oficina hace falta cobrar o perdonar la mora de una cuota salteando las anteriores? (Decide A o B.)
2. Si es B: ¿se sigue con el salón en paralelo o espera a que termine la mora? La recomendación es esperar: las dos
   partes tocan pantallas grandes y se prueban mejor de a una.
