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
| 5 | Juntas y separadas marcadas en el plano y en papel, con P y A. Toda mesa de una familia separada lleva el apellido y, abajo, "→ la otra mesa". Casilla "Familias con adicional" en pantalla y al imprimir | `FamiliasEnElPlano`, `PintorPlano`, `PlanoPdf` |
| 6 | Al marcar "lejos" se elige qué tan lejos: cerca (viene elegida), a unas mesas o bien lejos. Lo pedido queda en el registro y en la planilla | `DistanciaLejos`, `SorteoConPlano._ordenLejos` |
| 7 | El recorrido entero como test | `test/recorrido_salon_test.dart` |
| 8 | Muestras | `tool/numeros_en_orden_muestra_test.dart` |

## Decisiones que no estaban en el plan

- **El apellido en toda mesa separada** (pedido del usuario el 2-nov, mirando la muestra: "la tercera de GOMEZ" no se sabía de
  quién era). Va en un renglón y la flecha en otro: un apellido largo se corta con "…", y el número de la otra mesa no se puede
  perder.
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

## Lo que no se comprobó

- **Nadie la usó todavía en una ventana de verdad.** Lo probado son los tests, con las pantallas montadas, y las muestras
  miradas. La ventana de prueba compila para Windows, pero falta que el usuario la abra y la maneje con el mouse.
- **El PDF se miró en chico** (en el panel, a 40 %): se leen las cápsulas, los aros, las letras y los apellidos. Conviene mirarlo
  impreso de verdad antes del primer sorteo.
- **Un test falló una vez y no se reprodujo:** `test/recepcion_suelta_canal_test.dart`, "sigue emitiendo la lista cuando cambia
  algo". Pasó en las demás corridas completas y 8 de 8 corrido solo. No se tocó nada de Recepción, y el test espera 50 ms de
  reloj: lo más probable es que sea la PC cargada, sin confirmar. Si vuelve a pasar, cambiarle la espera por un aviso.

## Lo pendiente, en orden

1. **El usuario mira la ventana de prueba y dice si se publica la 6.3.0.** Los sorteos de verdad son en noviembre y las fiestas
   desde el 1-dic. Publicar: la lista de arriba, con él presente.
2. **Operadores con permisos** (paso 3 de la hoja): Cobros, Entradas y Barra. El plan ya está corregido:
   `docs/PLAN_MODO_ENTRADAS_2026-10-30.md`. Lleva una tabla nueva y la migración v76, que se prueba sobre una copia de su base con
   la app cerrada: hay que pedírselo.
3. **La app de hoy corriendo en una tablet** (etapa 0 del paso 4): ninguna tablet tiene la app, y es el riesgo más grande para el
   4-dic. Hace falta un Android conectado y una clave de firma propia.
4. **La impresora** (paso 1): espera a que el usuario la tenga. La rama `feature/barra-impresora` está sin compilar, y a su arnés le
   falta el botón LOGO.
5. **El plan del módulo de barra** (paso 4): después de la impresora, con lo aprobado en las maquetas, que está en la hoja.
6. **Entradas** (paso 5). La venta suelta es lo último.

**Queda abierto, sin apuro:** marcar "lejos" antes, en la ficha del alumno. Hoy se tilda en SORTEO. Llevaría una tabla nueva, y va
aparte si lo piden.
