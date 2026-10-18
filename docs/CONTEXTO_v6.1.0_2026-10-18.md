# v6.1.0 — Las bajas temporales, la mora por cuota y el salón primero

**Fecha:** 2026-10-18
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Estado: EN CURSO. Nada instalado.** La 6.0.0 está publicada e instalada en las tres PCs (la de la casa el 15-oct;
las del operario y del jefe el 16-oct). Lo de acá está programado en la rama, no en las PCs.

> Anterior: [v6.0.0](CONTEXTO_v6.0.0_2026-10-11.md). Pendientes de esta versión:
> [mora-por-cuota](pendientes/mora-por-cuota.md) y [PLAN_SALON_PRIMERO](PLAN_SALON_PRIMERO_2026-10-16.md), con su
> [maqueta](maqueta_salon_primero_2026-10-16.html).
> Plan de este chat: `C:\Users\lover\.claude\plans\donde-nos-quedamos-dreamy-blossom.md`.

## Qué lleva y en qué orden (decidido por el usuario, 16 y 18-oct)

**Una sola versión con todo junto**, que se publica cuando esté completa. Va en partes, una por chat, con el plan
corto y su OK antes de programar.

1. **Las bajas temporales (fase 1 de la mora por cuota).** **HECHA el 18-oct (`ffb8448`)**, programada y sin
   instalar. Ver abajo.
2. ~~La mora de cada cuota guardada (fase 2)~~. **Descartada el 18-oct**: vio la maqueta con la mora en fila y cada
   cuota suelta, y eligió la fila (la A de [PLAN_MORA_POR_CUOTA](PLAN_MORA_POR_CUOTA_2026-10-18.md)). A cambio,
   **el aviso "Revisar la ficha", HECHO (`964b141`)**.
3. **El salón primero, las mesas después**, las etapas de su plan. **La etapa 1 (las cuentas) HECHA el 18-oct**; ver
   las secciones 8 y 9 del plan.
   - Las cuatro flechitas se sacan.
   - Mover un sector después de acomodar no reacomoda: se toca el botón.
   - **Los predios con nombre van en la 6.1.0**, como etapa nueva con maqueta.
   - "Volver al armado original" también en el salón vacío.
   - **Sigue la etapa 2:** la tarjeta "Salón vacío" en Estilo y armado.
4. **La versión:** `pubspec.yaml` y el `.iss` en 6.1.0, el instalador, y publicar con él presente.

Sin la fase 2 la versión es más chica, pero el salón tiene sus etapas 2 a 6 más los predios: tampoco llega al lunes 20.

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

## Para el día de instalar la 6.1.0

- **TOÑANEZ:** con su OK en el momento, reescribir en la nube su `mora_tracked_ajuste = 0`, sin cambiar plata,
  para que todas las PCs la vuelvan a bajar. Después, mirar en la PC del jefe que su ventana de cobro se vea como
  la de un 0/9. **Hasta entonces, en la oficina no le cobran ni le editan nada**; si va a pagar, se calcula su mora
  al día.
- **DENIS:** mientras convivan versiones, una PC con la 6.0.0 le vuelve a calcular los $87.600 y la 6.1.0 los pone
  en 0. Está de baja: no toca cobros ni totales.
- La regla de siempre: los SQL de la fase 2 se corren antes de instalar, con su OK; operario primero.

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
(sobre todo las secciones 7, 8 y 9), CLAUDE.md y la memoria del proyecto. La
6.0.0 está publicada e instalada en las tres PCs. La 6.1.0 va en una sola
versión con todo junto: las bajas temporales y el aviso "Revisar la ficha",
HECHOS el 18-oct y sin instalar (la fase 2 de la mora por cuota la descarté:
me quedo con la mora en fila); el salón primero, con la etapa 1 (las cuentas)
HECHA el 18-oct; sigue la etapa 2 (la tarjeta "Salón vacío" en Estilo y
armado), después las manijas, los botones, las muestras y los predios con
nombre (etapa nueva, con maqueta); y al final la versión y publicar conmigo
presente.
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
