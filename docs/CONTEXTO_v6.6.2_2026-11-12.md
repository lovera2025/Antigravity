# Contexto: la 6.6.2 — los papeles sin datos de cobro, y el orden por cumplimiento

12-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. Sin SQL y sin migración (la base del equipo
sigue en la v79). El pedido entero está en `docs/SPEC_frente_por_cumplimiento_2026-11-12.md`, con
lo que el usuario cambió ese mismo día anotado arriba.

## Para retomar en otro chat

**Estado: la 6.6.2 está PROGRAMADA y probada, SIN PUBLICAR. El orden por cumplimiento que se
reparte solo (la 6.7.0) está SOLO EN EL PLAN: lo único programado es el servicio que ordena, sin
pantalla.**

El sorteo de una de las fiestas era ese mismo día. El orden automático toca la parte más delicada
del sorteo y no llegaba probado, así que ese día se hizo **a mano**: al usuario se le entregó la
lista del orden de esa fiesta (con nombres, en `build/orden_frente/`, fuera de git) para fijar las
mesas con "Fijarle mesas" y sortear al resto con la 6.6.1.

| | Estado |
|---|---|
| La lista del orden de la fiesta del 12-nov | Entregada (con los cobros hasta las 13:02) |
| La 6.6.2 (papeles y candado) | Programada y probada. **Sin publicar** |
| El servicio del orden (`cumplimiento_de_cuotas.dart`) | Programado y probado. La app no lo llama |
| El orden que se reparte solo (6.7.0) | Solo en el plan |
| La 6.6.1 en las PCs | El usuario quedó en avisar; falta su foto de la mora "después" |

### Lo que pidió el usuario el 12-nov

1. **Parte A:** las mesas van del que mejor cumplió con las cuotas al que peor, con el respaldo
   guardado para cuando una familia reclame.
2. **Parte B:** la planilla y el plano en papel no dicen quién sorteó, cuántos cambios hubo ni
   "sin pagar". El rojo de SIN MESA queda.

Y lo que decidió durante el día, que **reemplaza** partes de la spec:

- **El orden recorre todo el salón**, no solo las dos primeras líneas: el mejor, pegado a la
  pasarela con su adicional detrás; los que siguen, detrás de los anteriores, cada vez más lejos.
  El azar solo desempata. Se le avisó que así los que peor cumplieron quedan juntos contra los
  bordes. Se toma **por columnas desde el pasillo**; no llegó a elegir entre eso y "por filas
  desde el escenario" (se le mostraron los dos en un simulado).
- **Tolerancia 0 días:** un día tarde ya es "pagó tarde".
- **Ninguna mesa cambia de número** ("debería seguir el típico 1, 2, 3, 4… sino es muy
  evidente"). El orden decide qué familia va a qué mesa; el puesto no se escribe en ningún lado
  fuera de "Ver el orden".
- **Un historial del orden con una oración por familia**, corta y natural, "para tener un
  argumento si se quejan" (`fraseDelPuesto`).
- **No quiere ocuparse del candado** ("¿cuándo debería importarme sacar o poner el candado?"):
  desaparece solo. Se le había ofrecido un botón para sacarlo y lo rechazó.

### Lo que lleva la 6.6.2

- **La línea del sorteo, corta** (`RegistroSorteo.lineaParaPlanilla`): "Sorteo del 12/11/2026
  21:40 hs". Sin quién, sin "con motivo" ni "a mano después". Con dos sorteos, los dos renglones
  sin el nombre. `ResumenRegistroSorteo` los sigue contando; se ven en PLANO → HISTORIAL.
- **Ningún papel del sorteo dice "sin pagar"** (`PlanillaSorteo.fila`, `_celdaMesa`, `_resumen`):
  SIN MESA en rojo y nada más; la adicional, el aviso de mesas y las sillas, sin "(sin pagar)".
  Vale para la versión interna y la de repartir.
- **La planilla para repartir no dice "· lejos · en la zona elegida"**: los números solos. La
  interna lo sigue diciendo.
- **El candado se ve solo mientras la fijada espera a su familia** (`InfoMesa.conCandado`, una
  sola regla para la pantalla y el papel). Entregada, es una mesa más: sin candado, sin "Fijada
  antes del sorteo". **Si la ocupa otra familia (conflicto), el candado sigue.** El dato no
  cambia: la fijada queda en la config, y si se deshace el sorteo vuelve a esperar a su familia,
  con su candado.
- **En una tele acostada, el salón del tótem es toda la pantalla** (pedido del usuario el mismo
  12-nov, mirando el antes y el después): el fondo claro del plano llega a los cuatro bordes, sin
  las dos bandas con el fondo de la apariencia a los costados (`EscenaTotem._conElSalon`,
  `pantallaCompleta`, que es `DatosEscena.apaisado`).
  - **El dibujo no cambia de lugar ni de tamaño**: ya ocupaba todo el alto, y no se agranda sin
    cortarlo. `CuadroDelSalon` no se tocó.
  - El fondo y el panel se apagan juntos detrás del nombre en grande (`_opacidadDelSalon`); la
    secuencia es la de siempre: en grande, se achica, queda en la pista.
  - El nombre en una franja al costado (Arriba, Abajo, Izquierda, Derecha) va sobre el cartel
    oscuro: ahí abajo ahora hay fondo claro. "N más en camino" pasa a oscuro sobre el salón claro.
  - Mientras se ve el salón, el fondo de la apariencia no se ve. Parada, nada cambia.
- **Los tests que esperaban "· Jefe" y "(sin pagar)" se cambiaron a propósito**: cambió lo
  pedido, no se aflojó una prueba. El PDF escribe palabra por palabra: para comprobar que un
  texto no está se busca cada palabra, no la frase.

### El servicio del orden (programado, sin pantalla)

`lib/features/eventos/services/cumplimiento_de_cuotas.dart`:

- `CumplimientoDeCuotas.de`: cuota por cuota, de los **pagos** (nunca de los campos de la mora):
  vencimiento (el de la mora), día en que quedó cubierta (`fecha_pago` en hora de Argentina) y
  días de atraso, sin los congelados. La eximición y el perdón no borran el atraso.
- `PlanDeLaFiesta`: el plan de la mayoría, y el **plan nuevo** deducido (menos cuotas, total de
  base más alto y alta en el mismo mes que la mayoría: las tres).
- `OrdenPorCumplimiento.de`: los tres grupos (nunca tarde · pagó tarde · plan nuevo) y el orden
  de adentro; el azar solo en los empates.
- `fraseDelPuesto`: la oración. No dice "mora" ni "deuda".

Un test ata las cuotas cubiertas a `recalcularSaldoDesdePagos` y los días de una cuota impaga a
los de `MoraCuotaCalculator.calcularDesglose`.

**La lista de una fiesta**, sobre una copia de la base (nunca la de verdad):

```
flutter test tool/orden_del_frente_test.dart --dart-define=copia=<copia de data.db>
  --dart-define=salida=build/orden_frente --dart-define=fiesta=<parte del nombre>
```

Sin `fiesta`, el resumen de todas, sin nombres. **La lista lleva nombres y cómo pagó cada uno:
va a `build/`, nunca a git.** Antes de copiar la base, abrir la app en esa PC para que baje los
cobros del día.

Control del 12-nov contra la sección 2.6 de la spec: la fiesta de 44 familias da **15 / 27 / 2**,
igual; 44 que nunca pagaron tarde y ya cancelaron, igual. De plan nuevo da 34 entre los que
entran al orden y 37 contando a los de baja y a los que no pagaron nada; la spec decía 35 con
otra manera de contar.

### Lo que NO se probó

- **El plano con el candado nuevo no se miró en la ventana** (`tool/plano_prueba.dart`): la regla
  tiene su test, el dibujo no se vio.
- **El camino a mano no se probó con el mouse**: que SORTEO respete las fijadas es lo de
  siempre; lo que se leyó en el código es que con la 6.6.1 el candado quedaba para siempre.
- La 6.6.2 no se instaló ni se imprimió nada con ella.
- En la corrida entera falló una vez `chat_de_la_noche_test` (la central de la puerta); sola pasa
  siempre y ese código no se tocó.

### Lo que sigue

1. **Publicar la 6.6.2, con el usuario**: foto de la mora "antes de 6.6.2", instalador por pasos
   (mirando la página del celular), tag, release y web. La planilla se arma desde el sorteo
   guardado: se puede instalar después de sortear y recién ahí imprimir.
2. **La 6.7.0, el orden que se reparte solo.** La spec, con lo decidido el 12-nov y estas
   correcciones:
   - con el orden prendido, "Las adicionales: Al final" se ve apagada (la adicional va detrás de
     su principal); así no se toca ese camino de `_entera`, `validar` ni `delFinal`;
   - las mesas que sobran quedan vacías afuera, nunca salteadas en el medio;
   - definir la primera línea en las filas donde la pasarela terminó (ahí el medio se llena de
     mesas), y mostrarle cada salón con los puestos pintados antes de programar el reparto;
   - una PC vieja sortea al azar sin avisar: el Historial tiene que decir si el orden no corrió;
   - el historial guarda, por familia, lo que arma la oración (`k`, `f`, `e`), para que diga lo
     mismo aunque después se corrija un cobro.
   **Para pensar antes de programar:** en vez de un camino nuevo (`delFrente`), el orden puede
   escribir fijadas y dejar que el SORTEO de siempre las entregue. Con el candado que ya
   desaparece solo, lo que frenaba esa idea en la spec ("una fijada se dibuja con candado") dejó
   de valer.
3. Preguntarle el recorrido: por columnas desde el pasillo o por filas desde el escenario.
