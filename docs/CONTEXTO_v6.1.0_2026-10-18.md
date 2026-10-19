# v6.1.0 — Las bajas temporales, la mora por cuota y el salón primero

**Fecha:** 2026-10-18 · **actualizado el 19-oct**
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Estado: EN CURSO. Nada instalado.** La 6.0.0 está publicada e instalada en las tres PCs (la de la casa el 15-oct;
las del operario y del jefe el 16-oct). Lo de acá está programado en la rama, no en las PCs.

> Anterior: [v6.0.0](CONTEXTO_v6.0.0_2026-10-11.md). Pendientes de esta versión:
> [mora-por-cuota](pendientes/mora-por-cuota.md) y [PLAN_SALON_PRIMERO](PLAN_SALON_PRIMERO_2026-10-16.md), con sus
> maquetas: la del [salón primero](maqueta_salon_primero_2026-10-16.html) y la de los
> [predios con nombre](maqueta_predios_con_nombre_2026-10-19.html).
> Planes de los chats: `C:\Users\lover\.claude\plans\donde-nos-quedamos-dreamy-blossom.md` (18-oct) y
> `C:\Users\lover\.claude\plans\donde-nos-quedamos-prancy-bunny.md` (18 y 19-oct).

## Qué lleva y en qué orden (decidido por el usuario, 16 y 18-oct)

**Una sola versión con todo junto**, que se publica cuando esté completa. Va en partes, una por chat, con el plan
corto y su OK antes de programar.

1. **Las bajas temporales (fase 1 de la mora por cuota).** **HECHA el 18-oct (`ffb8448`)**, programada y sin
   instalar. Ver abajo.
2. ~~La mora de cada cuota guardada (fase 2)~~. **Descartada el 18-oct**: vio la maqueta con la mora en fila y cada
   cuota suelta, y eligió la fila (la A de [PLAN_MORA_POR_CUOTA](PLAN_MORA_POR_CUOTA_2026-10-18.md)). A cambio,
   **el aviso "Revisar la ficha", HECHO (`964b141`)**.
3. **El salón primero, las mesas después**, las etapas de su plan. **Las etapas 1 (las cuentas) y 2 (la tarjeta
   "Salón vacío") HECHAS el 18-oct; la 3 (las manijas) y la 4 (ACOMODAR y VACIAR) el 19-oct**; ver las secciones 8 a
   12 del plan.
   - Las cuatro flechitas se sacaron (etapa 3).
   - Mover un sector después de acomodar no reacomoda: se toca el botón.
   - "Volver al armado original" también en el salón vacío.
4. **"Lejos" en el salón de verdad. HECHO el 19-oct (`2f968f2`)**: lo pidió él a mitad de la maqueta de los predios.
   Sección 13 del plan.
5. **Los predios con nombre: PROGRAMADOS el 19-oct**, sin instalar (`91d2145`, `0053e57`, `c44c870`, muestras
   `88389e4`). Ver "Los predios con nombre" abajo y la sección 14 del plan del salón. **Falta la prueba de la
   migración v74 sobre una copia de su base**, con la app instalada cerrada.
6. **La etapa 5 del salón:** las muestras que faltan de su lista, con un PDF de playón rectangular. **Es lo que
   sigue.**
7. **La versión:** `pubspec.yaml` y el `.iss` en 6.1.0, el instalador, el SQL de los predios antes de instalar, y
   publicar con él presente.

Sin la fase 2 la versión es más chica, pero quedan los predios (con una migración) y la etapa 5: no llega al lunes 20.

## Qué pasó el 16-oct

- Instaló la 6.0.0 en las PCs del operario y del jefe.
- Mostró la 6.0.0 en una reunión con los futuros recepcionistas (todavía no contó cómo salió). Esa mañana hubo un
  sorteo de práctica en Puerto Viejo (9:28), deshecho a las 9:34. Quedaron tres planos de práctica "A medida del
  playón" (la Normal 138 mesas, Gregoria Morales 41, Puerto Viejo 31).
- El jefe pidió "el salón primero": el usuario lo resolvió con Claude en claude.ai, y el plan y la maqueta quedaron
  en `docs/`.
- En la oficina reincorporaron a TOÑANEZ, AGUSTINA (la Normal) y le cargaron $166.200 de mora a mano en la PC del
  jefe. Esa tarde, desde claude.ai, se pusieron en 0 a mano en la nube (18:19) y se escribió la especificación
  `SPEC — Mora por cuota y bajas temporales`.

## La parte 1: las bajas temporales (18-oct)

Su regla: **un alumno que vuelve de una baja tiene la misma mora que uno que nunca estuvo de baja**, cuota por cuota
desde su vencimiento. En la ventana de cobro: cuota 1 y su mora, cuota 2 y su mora, cada una con su casilla, como un
0/9. Lo vio en un show widget y aprobó.

Lo que se hizo, el porqué y lo comprobado: [mora-por-cuota](pendientes/mora-por-cuota.md). En corto:

- **La baja no toca la mora.** La fecha que guardaba la 6.0.0 se ignora, porque borrarla no cruza entre PCs. Al
  reincorporar, la ficha del alumno se revisa en el momento.
- **El ajuste de la mora lo manda la nube.** Una PC ya no se queda con el suyo si la nube trae 0, y si lo pierde,
  queda escrito en `revision_mora.txt`.
- **Editar alumno manda la mora solo si alguien la cambió.**
- **Apareció ESPINOZA, DENIS AIMARA:** $87.600 de ficha que la 6.0.0 inventó contando la mora de pagos viejos hasta
  el día de su baja. Con la 6.1.0 queda en $0, y su mora real hoy es $43.500.
- **Preguntó si perdonar mora traía problemas.** No: un perdón nuevo llega como siempre, y uno sin subir no se pisa.
  Lo único nuevo es que sacar un perdón también llega a las otras PCs. De los 40 ajustes de su PC, 39 están igual
  en la nube; el otro lo cambiaron en la oficina después.
- **Comprobado:**
  - 2.496 tests, `flutter analyze` en 312, 15 roturas a propósito, todas vistas;
  - simulacro sobre una copia de su base: los 629 activos idénticos a la 6.0.0, y cambian solo las 14 bajas
    (`build/muestras_6.1.0/bajas/Simulacro_bajas.html`, abierto en Edge).
- **Me equivoqué y lo corregí en el momento:**
  - le dije que la revisión automática dejaba afuera a las bajas; la que corre al abrir el programa las incluye;
  - le dije que TOÑANEZ se había reincorporado a las 18:19; a esa hora fue el arreglo a mano en la nube.

## El aviso "Revisar la ficha" (18-oct, `964b141`)

Lo pidió al quedarse con la mora en fila.
- **En la grilla:** el filtro de mora suma "Revisar la ficha", que lista a los alumnos cuya mora en la ficha no se
  explica cuota por cuota, bajas incluidas. El menú dice cuántos son.
- **Al abrir el programa:** la revisión los anota en `revision_mora.txt`.
- La cuenta es `MoraTrackedOrigen.sinExplicar`, la misma de la ventana de cobro.
- **Comprobado:** con la copia de su base, antes de la revisión aparece DENIS y después ninguno; 2.503 tests y 5
  roturas vistas.
- **Me equivoqué y lo corregí:** el filtro de mora deja afuera a las bajas, así que DENIS no habría aparecido. Lo vi al
  armarle la muestra, antes de terminar.

## El salón primero, etapa 1 (18-oct)

Las cuentas, sin pantalla: el salón vacío, las manijas, el escenario desatado y acomodar las mesas esquivando los
sectores, dentro del borde real. **Con el mismo playón da exactamente lo mismo que el armado a medida de hoy, mesa por
mesa.** Detalle en la sección 9 de [PLAN_SALON_PRIMERO](PLAN_SALON_PRIMERO_2026-10-16.md).

## El salón primero, etapa 2 (18-oct)

La primera vez que el jefe toca PLANO, Estilo y armado viene con **"Salón vacío"** elegido: al tocar LISTO queda el
playón con el escenario y el Ingreso, y ya no saltan las 132 mesas. Arriba dice "Sin mesas todavía", sin rojo. Detalle
en la sección 10 de [PLAN_SALON_PRIMERO](PLAN_SALON_PRIMERO_2026-10-16.md).
- Con familias ya sentadas y sin plano, el salón vacío queda apagado con el motivo.
- **SORTEO no sortea un salón sin mesas:** lo dice con la ventana de siempre. Preguntó qué era "el freno del
  sorteo"; se le explicó con la noche (arma el salón el lunes, el miércoles alguien toca SORTEO antes de poner las
  mesas: sale el cartel y no se toca nada).
- **Lo que encontré:** hasta acá un plano sin mesas se daba por roto, y un salón vacío guardado no se podía volver a
  abrir; la etapa 1 no lo vio. Ahora se lee. **En la 6.0.0 se sigue viendo como roto** (no sortea, el tótem va sin
  plano, PLANO ofrece elegir el armado de nuevo): no pierde nada, y confirma que el plano se toca desde una PC con la
  6.1.0.
- **Comprobado:** 2.555 tests, 6 roturas a propósito vistas, y tres muestras (dos se le mandaron).

## El salón primero, etapa 3: las manijas (19-oct)

Preguntó qué era la etapa 3 y se le explicó con un dibujo; preguntó si ya estaba (no: estaba solo en el plan). Aprobó
el plan corto con dos cambios a la maqueta:
- el playón entero se mueve con una manija en el medio, porque arrastrar el piso mueve la vista con el plano
  acercado;
- las medidas con cinta siguen en la pestaña Medidas.

Ahora, en Acomodar:
- al tocar un sector o el piso del playón le aparecen sus manijas, y se estira de a medio metro;
- en el panel van **Ancho** y **Fondo** en lugar de las flechitas, y la lista **"El espacio"**;
- el salón vacío se puede guardar después de armarlo (antes "El salón quedó sin mesas" no dejaba);
- las medidas guardadas siguen al playón cambiado a mano, y Medidas avisa si quedó torcido.

**Encontrado en el camino:** mientras se arrastraba, la hoja crecía en cada paso y lo agarrado corría más rápido que el
mouse (el playón estirado 2 m quedaba en 3,5). Ahora el dibujo se queda quieto hasta soltar. Detalle en la sección 11
del plan.

## El salón primero, etapa 4: ACOMODAR y VACIAR (19-oct)

Aprobó el plan corto con las tres decisiones recomendadas. En Acomodar:
- **ACOMODAR LAS MESAS (132)** pone las mesas de la fiesta alrededor de lo armado, a la distancia de Medidas. Dice
  cuántas faltan si no entran, y con mesas puestas pasa a "ACOMODAR OTRA VEZ".
- **VACIAR EL SALÓN** saca las mesas y deja el espacio.
- Los dos se apagan con el motivo si hay familias con mesa, en un armado del Canva o sin alumnos.
- **Las mesas fijadas y las libres se quitan al guardar** lo acomodado o vaciado. Se avisa antes, con los nombres.
- Un salón sin mesas ya se puede guardar.

Detalle en la sección 12 del plan.

## "Lejos" en el salón de verdad (19-oct)

Pidió que "lejos" y "cerca" se cumplan. Juntas ya se cumplía. **Lejos no**: se medía por número, y en el sorteo por
división entre el 4 % y el 8 % de las familias con "1 lejos" quedaban con la extra tocando a la principal, también en
los salones de la 6.0.0 instalada. Ahora se mide en el salón dibujado: el sorteo vuelve a sortear si hace falta, la
revisión final lo comprueba, y si no hay manera no sortea y dice por qué. Con el arreglo, 0 de 2.000 en cada caso.
Detalle en la sección 13 del plan del salón.

**Contestado el 19-oct, en otro chat:** no hubo un sorteo de verdad por división con "lejos" en la 6.0.0. Los de
prueba fueron de escuela completa, y el problema medido era del sorteo por división: no hay nada que revisar en la
nube.

## Los predios con nombre (19-oct)

Lo aprobó con la maqueta (opción A y las tres decisiones), y se le pasó el plan corto con ExitPlanMode antes de
programar. Ahora, para el jefe:
- **Guardar:** PLANO → PERSONALIZAR → Acomodar → **GUARDAR COMO PREDIO…** (modo jefe). Pide el nombre; los chips de
  los guardados ponen el suyo, y con un nombre que ya está avisa que lo reemplaza. "Costa Surubí" no se acepta. Se
  guarda lo que se ve, aunque la fiesta no esté guardada (y lo dice).
- **Elegir:** en Estilo y armado, una tarjeta por predio con su dibujo, después de "Salón vacío". Arranca la fiesta
  con ese espacio, sin mesas, y sus medidas en Medidas; sigue ACOMODAR LAS MESAS, a la distancia de la fiesta.
- **Renombrar y Borrar:** el menú ⋯ de la tarjeta. Borrar se pide dos veces. Las fiestas que lo usaron no cambian.
- **Volver al armado original** en un salón que salió de un predio vuelve a ese predio como está hoy; si se borró,
  apagado con el motivo.

Tres cosas chicas que decidí al programar, recomendadas y sin preguntarle (poco riesgo, con vuelta atrás): borrar
marca la fila en vez de sacarla; en un armado del Canva el botón se apaga con el motivo; solo las tarjetas de predio
llevan dibujo.

**Comprobado:** 2.692 tests, `flutter analyze` en 312 (los mismos de antes), 8 roturas a propósito vistas (2 del paso 2
y 6 del paso 3) y cuatro muestras (`build/muestras_6.1.0/predios/`, se le mandaron).

**Encontrado en el camino:** la herramienta de muestras no fotografiaba lo que se abre encima (un menú) y `flutter
test` dibuja las sombras como una raya negra; ahora puede, con la sombra de verdad (`conLoDeArriba`).

**Falta:** la prueba de la migración sobre una copia de su base (`tool/verificar_migracion_v74_test.dart`): **la app
instalada tiene que estar cerrada, y se le pide a él.**

## Qué más pasó el 19-oct

- **Preguntó si después de acomodar y sortear se puede seguir cambiando y volver a guardar.** Sí:
  - Medidas se guarda siempre, sin mover mesas ni familias;
  - Acomodar a mano también (correr y agregar mesas, sectores, manijas);
  - ACOMODAR, VACIAR y cambiar el armado se apagan con familias sentadas, con el motivo.
  - En Medidas no se ponen sillas: las de cada familia salen de su alumno y se ven cuando tiene mesa.
- **Preguntó qué aparece después del sorteo.** Más que el número y las sillas:
  - cada mesa en el color de su división, con la leyenda;
  - el apellido debajo de la principal y las sillas, al acercar la vista;
  - al tocar una mesa, la familia con sus mesas y sillas;
  - los avisos de mesas apretadas.

  Se le mandó `Pantalla_plano_arquitecto.png`. Es de la 6.0.0 y no cambia.
- **La maqueta de los predios** (`docs/maqueta_predios_con_nombre_2026-10-19.html`, `aacce78`): la aprobó con la
  opción A y las tres decisiones.
- Una vez la sesión se cortó justo al pasarle un plan: cuando dice "estoy en modo plan", quiere el botón para
  aprobarlo.

## Para el día de instalar la 6.1.0

- **TOÑANEZ:** con su OK en el momento, reescribir en la nube su `mora_tracked_ajuste = 0`, sin cambiar plata,
  para que todas las PCs la vuelvan a bajar. Después, mirar en la PC del jefe que su ventana de cobro se vea como
  la de un 0/9. **Hasta entonces, en la oficina no le cobran ni le editan nada**; si va a pagar, se calcula su mora
  al día.
- **DENIS:** mientras convivan versiones, una PC con la 6.0.0 le vuelve a calcular los $87.600 y la 6.1.0 los pone
  en 0. Está de baja: no toca cobros ni totales.
- **El plano se toca desde una PC con la 6.1.0:** en la 6.0.0 un salón sin mesas se ve como roto, y "lejos" sigue
  midiéndose por número. Conviene que el jefe no sortee por división con "lejos" hasta tener la 6.1.0.
- **El SQL de los predios** (`supabase/migrations/20261020120000_predios.sql`, solo crea la tabla) se corre antes de
  instalar, con su OK; operario primero. Sin él, las PCs con la 6.1.0 dicen "No bajaron: predios" y lo guardado queda
  en la cola.

## Lo de la 6.0.0 que sigue esperando

- **El ensayo** (punto 8 de "Lo que falta para publicar" del CONTEXTO de la 6.0.0).
- **Cómo salió la reunión con los recepcionistas.**
- Lo de "Lo que sigue esperando del usuario" de ese CONTEXTO: marcar el Ingreso, las muestras sin opinar, el control
  de mesas y sillas cerca del sorteo.
- Mejorar "Buscar actualización" en la PC del operario: si falla, que vuelva a probar.

## Para seguir en otro chat, pegar

```text
Seguimos con la 6.1.0 de Junior Eventos. Leé primero
docs/CONTEXTO_v6.1.0_2026-10-18.md entero, docs/PLAN_SALON_PRIMERO_2026-10-16.md
(sobre todo las secciones 12, 13 y 14), CLAUDE.md y la memoria del proyecto. La
6.0.0 está publicada e instalada en las tres PCs. La 6.1.0 va en una sola
versión con todo junto, programada en la rama y sin instalar: las bajas
temporales y el aviso "Revisar la ficha" (la fase 2 de la mora por cuota la
descarté); el salón primero con las etapas 1 a 4 (salón vacío, manijas,
ACOMODAR LAS MESAS y VACIAR EL SALÓN); que "lejos" se cumpla en el salón de
verdad; y los PREDIOS CON NOMBRE (sección 14 del plan), con su tabla nueva
(migración v74). De los predios falta la prueba de la migración sobre una
copia de mi base: avisame antes, porque la app instalada tiene que estar
cerrada. Sigue la etapa 5 del salón (las muestras que faltan, con un PDF de
playón rectangular), y al final la versión y publicar conmigo presente, con el
SQL de los predios corrido antes.
Hasta instalar la 6.1.0, en la oficina nadie le cobra ni le edita nada a
TOÑANEZ, AGUSTINA.
La regla de la mora, mía: la mora de un mes que ya se pagó no se cobra más; se
cobra la siguiente si no se abonó. Los perdones no se tocan. Un reincorporado
tiene la misma mora que uno que nunca estuvo de baja.
ANTES DE PROGRAMAR cada parte, mostrame el plan corto y esperá mi OK; si trae
algo nuevo a la vista, una maqueta. Avisame al terminar cada paso con cómo
quedó, un commit y un push. Cada cambio lo apruebo yo.
Contestame primero lo que te pregunto, en una línea. Lo que tiene poco riesgo y
vuelta atrás, recomendalo y seguí: no me lo preguntes como si fuera un peligro.
Las muestras con muchas imágenes abrímelas en Edge. Si no entiendo algo
nuevo, explicámelo con un dibujo y "cómo sería la noche". No corras la app
desde el working tree. Lo que toque la base real o la nube, con mi OK en el
momento. Con "actualizá el contexto", frená y dejá todo anotado.
```
