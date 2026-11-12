# El plano del tótem, con algo animado mientras nadie entra

**Estado:** idea · **Última revisión:** 12-nov-2026

## De dónde sale

El usuario, el 12-nov, mirando el plano del tótem a pantalla completa: "¿algo animado mientras nadie
ingresa, en unos ítems del plano, solo en el tótem? ¿ideas?". Y enseguida: "pero si nadie entra que
no use nombres de los alumnos".

## Lo que se le propuso

Todas solo en el tótem (`PanelPlano`), solo en la espera y **sin nombres**:

1. **El salón se va llenando.** Las mesas de las familias que ya llegaron quedan encendidas, suave.
   No es un adorno: cuenta algo de la noche. Sale de quién ya entró, que el tótem ya sabe.
2. **Una ola de luz por las mesas.** Cada tanto un destello las recorre en orden, de la 1 a la última.
3. **El camino de muestra.** Una línea sale del Ingreso, llega a una mesa cualquiera y se borra:
   enseña cómo se va a ver cuando entre una familia.
4. **El Ingreso respira.** El cartel del Ingreso late despacio.
5. **Luces en el escenario y la pista.** Haces lentos sobre el escenario y un barrido de color en la
   pista.

Recomendadas: la 1 con la 4. Se ven de lejos, son sobrias y no distraen cuando salta un nombre.

## Antes de programar

- **Mostrárselas en movimiento** para que elija ("mostrame antes de aplicar lo que me proponés").
- Tiene que cortarse cuando llega una familia (la mesa encendida y el camino mandan) y cuando el
  tótem se esconde (`_pausar()`).
- La PC de la tele es modesta: nada que repinte el salón entero en cada cuadro (`TemaPlano` no tiene
  `==`; ver "El salón en el tótem" en CLAUDE.md).
- La 1 muestra qué mesas ya llegaron: preguntarle si eso está bien a la vista del salón.
