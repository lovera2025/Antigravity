# Plan: los números del salón en orden, y la adicional pegada (v6.2.2 o la que siga)

Fecha: 29-oct-2026. Rama: `feature/v4.6-cierre-por-sesiones`. **Plan para revisar: no programar sin el OK del
usuario.**

Leer antes: `CLAUDE.md` ("El salón: plano, sorteo y entradas"), y en `docs/PLAN_SALON_PRIMERO_2026-10-16.md` las
secciones 3c, 12 y 13.

## 1. De dónde sale (mensaje del usuario, 29-oct)

> "Las mesas deben estar ubicadas numéricamente del 1 hasta la cantidad de mesas que tenga la escuela, o que tenga
> que repartir; total en el sorteo los alumnos se ubican. Y que por default estén todas juntas la del contrato con la
> adicional, exceptuando que esté marcado para que estén lejos."

Se lo dijeron mirando el plano. Son tres reglas:

1. **Del 1 a N, sin huecos**: N es lo que necesita la fiesta (`PlanoDeLaFiesta.mesasQueNecesita`).
2. **En orden en el salón**: dos números seguidos son dos mesas pegadas (la serpentina del jefe).
3. **La adicional pegada a la principal**, salvo que se marque "lejos".

## 2. Cómo está hoy (leído en el código y en la nube, 29-oct)

| Regla | En el código | En la nube |
|---|---|---|
| 1. Del 1 a N | ACOMODAR LAS MESAS numera 1..N; agregar a mano usa `proximoNumero` (con `ultimoNumero`, puede dejar huecos) | Las cuatro fiestas con mesas van de 1 a N sin huecos (Buena Vista está en salón vacío) |
| 2. En orden | ACOMODAR numera en serpentina. **Mover una mesa a mano no cambia su número**, y no hay cómo volver a numerar sin ACOMODAR (que vuelve a poner las mesas donde él quiere) | **Puerto Viejo: 13 saltos en 35 mesas** (tocado hoy 20:05). Normal, Técnica y Gregoria Morales: 1 salto cada una (el paso de un lado al otro) |
| 3. Adicional pegada | **Ya está.** En SORTEO viene "Van todas juntas"; "lejos" se tilda por alumno en ese diálogo. Juntas y lejos se miden en el salón dibujado (`tramosPegados`, `lejosEnElSalon`) | Sin sorteo todavía en ninguna fiesta |

**Conclusión:** lo que vieron es la regla 2 en Puerto Viejo. Las mesas se corrieron a mano después de acomodar y
cada una se llevó su número. Así quedó (filas desde el escenario):

```
         lado izquierdo          lado derecho
fila 1:   5   6   7   8         26  27  28  29
fila 2:  14  13  12  11         23  22  21  20
fila 3:  10   1   2  16         24  35  34  33
fila 4:   9  15   4   3         25  17  18  31
fila 5:              19         32  30
```

Para el sorteo esto no es solo feo: `CasillerosPlano` corta en cada salto, así que quedan tramos de 1 o 2 mesas. Una
familia con principal y adicional puede no entrar pegada, o el sorteo decir que no entra.

## 3. Lo que se agrega

### 3a. ORDENAR LOS NÚMEROS (Acomodar, solo modo jefe)

Un botón al lado de ACOMODAR LAS MESAS. **Las mesas no se mueven: solo cambian los números**, para que queden 1..N
en serpentina sobre donde el jefe las dejó.

- **Cuenta pura nueva** `ArmarAMedida.ordenarNumeros(ArmadoSalon a) → ArmadoSalon`:
  - agrupa las mesas de cada hoja en filas (misma `y` con tolerancia de medio paso, el paso de `pasoDe`);
  - parte cada fila en izquierda y derecha por el centro (pasarela, si no escenario, si no el medio del borde: lo
    mismo que `acomodar`);
  - numera como `acomodar`: la izquierda desde el escenario y la derecha desde el fondo, alternando el sentido, y de
    los dos sentidos queda el que deja menos `cortes`;
  - **el pasto va al final**, con los números que siguen (como hoy);
  - las hojas en su orden (A y después B: la numeración sigue);
  - `ultimoNumero` queda en `max(ultimoNumero, N)`.
- **Mismas trabas que ACOMODAR** (`motivoSinAcomodar` sin la cantidad): apagado con familias con mesa ("deshacé el
  sorteo primero") y en un armado del Canva (ver pregunta 2). Después del sorteo un número no cambia nunca: ya pudo
  salir impreso o en una entrada.
- **Pasa por `SesionAcomodo` como `rehecho: true`**: se ve "ASÍ QUEDARÍA · SIN GUARDAR", se deshace, y al guardar
  (`paraGuardar(rehecho:)`) se quitan las fijadas, las libres y los bloques, con el aviso de siempre, porque sus
  números quedaron en otra mesa.
- Si ya están en orden, el botón dice "Los números ya están en orden" y no agrega un paso.

### 3b. El aviso en el plano

`PlanoDeLaFiesta.avisos` suma uno cuando `armado.cortes.length` pasa de los saltos que trae la serpentina (el paso de
un lado al otro y el cambio de hoja): "Los números no siguen el salón (13 saltos): en Personalizar → Acomodar,
ORDENAR LOS NÚMEROS". No frena el sorteo; avisa.

### 3c. Lo que no cambia

- La regla 3 (adicional pegada, "lejos" opcional): ya está y se deja como está, salvo lo que diga la pregunta 1.
- `SorteoMesasMotor`, `SorteoConPlano`, `CasillerosPlano`.
- Base local y nube: nada. Es el mismo `armado_json` con otros números; **ninguna clave nueva** (convivencia con la
  6.0.0 y la 6.1.x).
- La lista de la puerta: sin familias con mesa no hay nada que mover (`trasElSalon` no se llama).

## 4. Reglas que hay que respetar

- Doble llave de modo jefe (`_frenaSinModoJefe()` y `kSoloEnModoJefe`); `test/solo_modo_jefe_test.dart`.
- `AvisoDelPlano`, no SnackBar.
- La cuenta en función pura con test; la pantalla solo la llama.
- **Sobre un salón recién acomodado, `ordenarNumeros` tiene que dar exactamente lo mismo, mesa por mesa** (es la misma
  serpentina). Un cambio a una de las dos cuentas va en las dos.
- No comparar armados enteros con `firma`: mesa por mesa.
- `flutter analyze` y los tests, en la PC (el contenedor remoto no tiene Flutter).

## 5. Etapas (cada una cierra sola, con commit)

1. **La cuenta** (`armar_a_medida.dart`) y sus tests (`test/ordenar_numeros_test.dart`):
   - un salón acomodado queda igual (ocho casos, como el test de `acomodar` contra `armar`);
   - Puerto Viejo tal como está en la nube (las 35 posiciones de arriba): de 1 a 35, y a lo sumo el salto entre lados;
   - pasto al final; dos hojas; una fila incompleta; mesas sueltas fuera de fila;
   - roturas a propósito, todas vistas.
2. **La sesión y el panel** (`sesion_acomodo.dart`, `panel_acomodar.dart`, `plano_evento_cuerpo.dart`): el botón,
   apagado con su motivo, deshacer, y lo que se quita al guardar. Test de pantalla en `plano_evento_cuerpo_test`.
3. **El aviso** (`plano_de_la_fiesta.dart`) con su test.
4. **Muestras** (`tool/plano_pantalla_muestra_test.dart`): Puerto Viejo antes y después. Mandárselas al usuario.
5. Versión, CONTEXTO nuevo, una línea en CLAUDE.md, instalador. Sin SQL.

## 6. Preguntas para el usuario

1. **"Marcado para que estén lejos":** hoy se tilda en el diálogo de SORTEO, el día del sorteo, y no queda guardado
   antes. ¿Así está bien, o lo quieren marcar antes en la ficha del alumno (cuando la familia lo pide)? Lo segundo es
   una tabla nueva (no una columna de `contratos_alumnos`) y una migración: va aparte de este plan.
2. **Armados del Canva** (Normal 2A, etc.): traen la numeración que hizo el jefe a mano. ¿ORDENAR también ahí, o solo
   en los salones con borde del playón (los de hoy son todos "A medida" o "Salón vacío")? Recomiendo solo con borde,
   como ACOMODAR.
3. ¿El orden es la serpentina de siempre (izquierda desde el escenario, derecha desde el fondo)? Si "numéricamente"
   quería decir otra cosa (por ejemplo, de izquierda a derecha como se lee, fila por fila), cambia la cuenta y hay
   que decirlo antes de la etapa 1. Ojo: de izquierda a derecha, el último de una fila y el primero de la siguiente
   quedan en las puntas opuestas, y la adicional se separaría de la principal.

Lo que recomiendo: la serpentina, solo con borde, y "lejos" se sigue marcando en SORTEO por ahora. Para Puerto Viejo,
mientras tanto, alcanza con tocar ACOMODAR OTRA VEZ, pero eso vuelve a poner las mesas donde las calcula la app.
