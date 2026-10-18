# La mora por cuota y las bajas temporales

**Estado:** fase 1 **hecha** el 18-oct-2026 (`ffb8448`; programada en la rama, sin instalar; va en la 6.1.0). Fase 2
**decidida para la misma 6.1.0**, es la sección siguiente. Sale de la especificación que el usuario armó con Claude
en claude.ai el 16-oct, `SPEC — Mora por cuota y bajas temporales`.

## Qué pidió

"Un alumno que vuelve de una baja temporal tiene que verse exactamente igual que uno que nunca estuvo en baja: cada
cuota vencida con su propia mora, calculada desde su vencimiento." En la ventana de cobro: cuota 1 y su mora,
cuota 2 y su mora, cada una con su casilla, como la de un alumno 0/9. El caso real fue TOÑANEZ, AGUSTINA (la
Normal, 0 de 9 cuotas de $30.000).

La cuenta de la especificación es la del programa: vencimiento a fin de mes desde la inscripción
(`_ultimoDiaMesK`), 1 % de la cuota por día. Los números de TOÑANEZ al 16/10 ($50.700, $41.400, $32.400,
$23.100, $13.800 y $4.800: $166.200) están en `test/baja_temporal_mora_test.dart` tal cual.

## Lo que pasaba (leído el 18-oct)

- Dar de baja ponía `[BAJA]` en el nombre y el día en `mora_fecha_referencia`. `fechaEfectivaMoraAr` usaba esa
  fecha en vez de hoy, y la mora quedaba cortada ahí **también después de reincorporar**: TOÑANEZ volvía con $9.300
  en vez de $166.200.
- **Los $166.200 de TOÑANEZ no los escribió la reincorporación**, como dice la especificación. Se cargaron a mano
  en modo jefe con "poner mora" (`aplicarTrackedDeseado`) en la PC del jefe, seguramente para compensar la mora
  congelada. Esa tarde se pusieron en 0 a mano en la nube.
- **Ese arreglo de la nube no llegaba a las PCs.** Al bajar un contrato, la PC conservaba su `mora_tracked_ajuste`
  si la nube traía 0 (`sync_engine.dart`, de cuando esas columnas no subían). Tampoco llegaba sacar un perdón.
- **Editar alumno mandaba toda la mora de esa PC** (`datosEdicionAlumno` usa `toJson()` entero). Editarle el
  teléfono a TOÑANEZ en la PC del jefe habría vuelto a subir los $166.200.
- **La fecha congelada inventó mora vieja.** La revisión automática rehace la ficha repasando los pagos, y con la
  fecha de la baja calculaba todos los pagos viejos a ese día. ESPINOZA, DENIS AIMARA pagó las cuotas 1 a 3 antes
  de que vencieran y quedó con $87.600 de ficha (128, 97 y 67 días al 05/09).

## Lo que se hizo (fase 1, adaptada)

- **La baja no toca la mora.** `fechaEfectivaMoraAr` usa siempre hoy: la fecha guardada se ignora. No alcanzaba
  con borrarla al reincorporar, porque borrarla no cruza entre PCs. Dar de baja solo pone el `[BAJA]`
  (`BajaTemporal`, `eventos/services/baja_temporal.dart`).
  - Mientras dura la baja, la mora corre como la de cualquiera, pero no se cobra ni suma en los totales.
  - Si un día no se quiere cobrar ese período, va con la eximición, nunca con un ajuste.
- **Al reincorporar, la ficha se revisa en el momento:** `revisarMora(soloContratos: {id})`, la misma revisión de
  siempre para un solo alumno. Además, la revisión que corre al abrir el programa ya incluye a las bajas, así que la
  primera vez que se abra la 6.1.0 le deja a DENIS la ficha en $0 y lo sube.
- **El ajuste de la mora lo manda la nube** (`contratoAlBajar`, `core/services/contrato_al_bajar.dart`).
  - Las filas con cambios sin subir no llegan a esa función: las saltea el pull (`pendingIds`).
  - Si al bajar se pone en 0 un ajuste que la PC tenía, queda escrito en `revision_mora.txt` con el nombre y el
    monto, por si alguna vez fuera un perdón que nunca subió.
  - El otro camino de bajada (`_pullByEvento`, al abrir una fiesta) ya tomaba el de la nube.
- **Editar alumno manda la mora solo si alguien la cambió**, como la mesa (`camposMoraDelAlumno`).
- Los textos de dar de baja, de reincorporar y de la planilla de mora ya no dicen "mora congelada".

**Comprobado:**
- 2.496 tests, `flutter analyze` en 312, y 15 roturas a propósito, todas vistas.
- Simulacro sobre una copia de la base del usuario (la de su PC, del 16-oct a las 13:04):
  - con la 6.0.0 y la 6.1.0, los 629 activos dan idénticos en la ventana, el papel, la mora y el recibo, y las
    operaciones del día también;
  - cambian solo las 14 bajas;
  - de los 40 ajustes de la PC, 39 están igual en la nube. MOREIRA, FACUNDO N lo cambiaron en la oficina después
    de que se cerró la PC.

  Página: `build/muestras_6.1.0/bajas/Simulacro_bajas.html`.

## El día de instalar la 6.1.0

- **TOÑANEZ:** con su OK en el momento, tocar su ficha en la nube sin cambiar plata (reescribir
  `mora_tracked_ajuste = 0`; el trigger renueva `updated_at`). Así todas las PCs la vuelven a bajar y la del jefe
  toma el 0. Después, mirar en la PC del jefe que su ventana de cobro se vea como la de un 0/9.
- **Hasta entonces, en la oficina no le cobran ni le editan nada.**
- Mientras convivan versiones, una PC con la 6.0.0 le vuelve a calcular a DENIS los $87.600 al abrirse, y la 6.1.0
  los vuelve a poner en 0. Como está de baja, no toca cobros ni totales.

## Fase 2: la mora de cada cuota guardada

**18-oct: plan corto y maqueta hechos, decisión pendiente del usuario:**
[PLAN_MORA_POR_CUOTA](../PLAN_MORA_POR_CUOTA_2026-10-18.md). Con la fase 1, la ventana ya muestra la mora cuota
por cuota, pero en fila (de la más vieja a la más nueva). Lo único que agrega la fase 2 a la vista es cobrar o
perdonar cada cuota suelta. Medido en su base: 50 de 51 fichas se explican cuota por cuota, y la que no es la de
DENIS, que la fase 1 deja en $0. La recomendación es quedarse con la fila, salvo que la oficina necesite saltear.

Va en la misma 6.1.0, como sección siguiente, **con su plan corto y una maqueta del cobro antes de programar**. La
especificación propone:
- una tabla `mora_cuotas_contrato`, con una fila por cuota que tuvo mora (pendiente, cobrada o condonada);
- el cobro, el recibo y la deuda leyéndola;
- condonar por cuota;
- mudar la mora vieja (51 contratos con ficha y 40 con ajuste en la PC del usuario).

**Su plan tiene que corregir cuatro cosas, que chocan con reglas del proyecto (CLAUDE.md):**
- **Nada de columnas nuevas en `contratos_alumnos`** (`baja_temporal`, `baja_desde`). Esa fila se reescribe entera
  en tres lugares, y así se perdió el perdón de mora. Lo nuevo del alumno va en una tabla aparte, o el estado sigue
  siendo el `[BAJA]`.
- **Sin CHECK en la tabla nueva** (`estado`, `monto`). El motor toma el "violates" como un padre que falta, y la
  fila queda trabada para siempre. Los valores los controla la app, con un test que compara el SQL.
- **La app usa SQLite directo** (`local_database.dart`, con la migración y la copia antes de migrar), no Drift.
- **Es lo más delicado del programa** y no hay entorno de prueba. Antes de instalar:
  - el simulacro de la mudanza sobre una copia de la base;
  - el "cobro igual que hoy" (`tool/cobro_igual_que_hoy_test.dart`) de los que no cambian;
  - las muestras del cobro y del recibo.

## Aparte, sin decidir

La eximición (`mora_exenta_hasta`) sigue conservando el valor de la PC cuando la nube la trae vacía. Esa protección
sí hizo falta: hubo eximiciones que estaban solo en una PC. Sacarla puede borrar perdones, así que va con su propio
análisis.
