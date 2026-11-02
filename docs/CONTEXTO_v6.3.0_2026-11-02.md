# La 6.3.0 (programada, SIN PUBLICAR): el plano antes de los sorteos

2-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. Plan: `docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md`. El orden de todo lo que
sigue: `docs/HOJA_DE_RUTA_2026-11-02.md`.

**Estado: etapas 1 a 8 hechas y subidas a la rama. No hay cambio de versión, ni release, ni web: `pubspec.yaml` sigue en
6.2.1. Publicar, solo preguntándole antes al usuario** (lo pidió el 2-nov). Las PCs siguen con la 6.2.1.

## Qué se hizo

| Etapa | Qué cambia para el usuario | Dónde |
|---|---|---|
| 1 y 2 | Sin familias con mesa, los números se ordenan solos al guardar el salón, sin mover ninguna mesa. Un salón ya mezclado se arregla con abrirlo y guardar | `ArmarAMedida.ordenarNumeros`, `EditarArmado.paraGuardar` |
| 3 | El plano avisa cuántos saltos hay si los números no siguen el salón | `PlanoDeLaFiesta._avisoDeSaltos` |
| 4 | La barra de Acomodar: antes del sorteo reacomoda en vivo; después, o en el Canva, estira | `SesionAcomodo.moverLaBarra`, `PanelAcomodar` |
| 5 | Juntas y separadas marcadas en el plano y en papel, con P y A. Casilla "Familias con adicional" en pantalla y al imprimir | `FamiliasEnElPlano`, `PintorPlano`, `PlanoPdf` |
| 6 | Al marcar "lejos" se elige qué tan lejos: cerca (viene elegida), a unas mesas o bien lejos. Lo pedido queda en el registro y en la planilla | `DistanciaLejos`, `SorteoConPlano._ordenLejos` |
| 7 | El recorrido entero como test | `test/recorrido_salon_test.dart` |
| 8 | Muestras | `tool/numeros_en_orden_muestra_test.dart` |

## Decisiones que no estaban en el plan

- **Sin internet no se ordena** (`leidoDeLaNube`). Esa PC no puede saber si la otra ya sorteó, y renumerar debajo de familias
  sentadas sería grave. Se ordena la próxima vez que se guarde con internet, y el aviso lo dice.
- **Con dos hojas la numeración es la serpentina de `acomodar` y `armar`** (la izquierda de A y de B, y la derecha de vuelta),
  no "toda la A y después la B": si no, ordenar cambiaría un salón recién acomodado.
- **El motor recibe un orden, no una regla nueva** (`OrdenLejos`). Reordena las candidatas de una mesa "lejos", sin sacar
  ninguna, así que lo que entra no cambia: `esFactible` y `seCompleta` siguen igual. Sin orden, el motor hace lo de siempre.
- **Sin decir qué tan lejos, es "bien lejos"**, lo de antes: lo usa quien llame al sorteo sin la opción. El diálogo siempre la
  manda, y ahí viene en "cerca".
- **"Lejos" se sigue marcando en el diálogo de SORTEO**, no en la ficha del alumno (lo recomendado en la pregunta 1 del plan).
  Marcarlo antes llevaría una tabla nueva y una migración, y va aparte.

## La medición (`tool/lejos_distancias_test.dart`)

A cuántos lugares (la distancia entre mesas) queda una mesa "lejos". 1.000 sorteos enteros por salón y 200 por división, con
20 familias "1 lejos" (6 en Puerto Viejo). "Sin decir", lo de antes, dio igual que "bien lejos" en todos los casos.

| Salón y modo | Cerca (mediana) | A unas mesas (entre 3 y 6) | Bien lejos (mediana) | Tocándose |
|---|---|---|---|---|
| Normal 138, entero | 2,0 | 98,0 % | 9,4 | 0 |
| Técnica, entero | 2,0 | 99,5 % | 8,6 | 0 |
| Puerto Viejo, entero | 2,0 | 98,2 % | 6,1 | 0 |
| Normal 138, por división | 2,0 | 98,0 % | 8,1 | 0 |
| Puerto Viejo, por división | 2,0 | 79,2 % | 3,2 | 0 |

Puerto Viejo por división da menos porque cada bloque es chico: la mesa no tiene adónde ir a esa distancia. Ahí el sorteo elige
la más cercana a lo pedido y lo dice con el apellido, como pide el plan.

## Cómo mirarlo sin publicar

```bash
flutter run -d windows -t tool/plano_prueba.dart
```

Es la pantalla del plano de verdad, con el plano real de Puerto Viejo y 35 alumnos inventados, sin base ni nube. Lo que se
guarda se queda en esa ventana. No abrir la app completa desde el código: usa la base y la nube de verdad.

## Lo que falta para publicar

**Sin SQL y sin migración.** Cuando el usuario lo diga, con él presente:

1. Foto de la mora "antes de 6.3.0" (`supabase/mora_fotos.sql`, sección 2).
2. Versión en `pubspec.yaml` y en `installer/junior_eventos_setup.iss`, y novedades.
3. Release y web. Instalar las tres PCs el mismo día.
4. Foto "después de 6.3.0" y la comparación de la sección 3: tiene que dar vacío. Si no, mirar `mora_cambios`.

**Convivencia:** una PC con la 6.2.1 abre y guarda un salón ordenado sin problema, pero no ordena al guardar. El plano se toca
desde una PC con la versión nueva. El renglón del sorteo suma `_lejos`, que la 6.2.1 ignora porque empieza con guion bajo.

**La mora no se toca en toda esta versión:** ordenar y sortear escriben `planos_evento`, `sorteos_mesas` y los números de mesa.
