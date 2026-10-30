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

### 3a. Los números se ordenan solos al guardar el salón (antes del sorteo)

**Decidido por el usuario el 29-oct** (en vez de un botón que hay que acordarse de tocar). El jefe mueve, agrega o
saca mesas como quiera; **al guardar, mientras no haya sorteo, la app las numera 1..N en orden según donde quedaron.
Las mesas no se mueven: solo cambian los números.**

- **Cuenta pura nueva** `ArmarAMedida.ordenarNumeros(ArmadoSalon a) → ({ArmadoSalon armado, Map<int, int> cambio})`
  (`cambio`: número viejo → número nuevo):
  - agrupa las mesas de cada hoja en filas (misma `y` con tolerancia de medio paso, el paso de `pasoDe`);
  - parte cada fila en izquierda y derecha por el centro (pasarela, si no escenario, si no el medio del borde: lo
    mismo que `acomodar`);
  - numera como `acomodar`: la izquierda desde el escenario y la derecha desde el fondo, alternando el sentido, y de
    los dos sentidos queda el que deja menos `cortes` (ver la pregunta 3: el orden lo confirma el usuario);
  - **el pasto va al final**, con los números que siguen (como hoy);
  - las hojas en su orden (A y después B: la numeración sigue);
  - del 1 a N **sin huecos**: antes del sorteo `ultimoNumero` vuelve a N (ningún número salió impreso con una
    familia; ACOMODAR ya renumera igual).
- **Dónde corre:** en `EditarArmado.paraGuardar`, como último paso del armado que se guarda, **solo si**:
  - no hay familias con mesa (las mismas que frenan ACOMODAR: `enUso` sin las fijadas);
  - el salón tiene el borde del playón (salón vacío, a medida o predio). **Los armados del Canva no**: traen la
    numeración que hizo el jefe a mano.
- **Lo que apunta a un número sigue a su mesa física** (no se borra, a diferencia de `rehecho`): con `cambio` se
  traducen las claves de `config.fijadas` y `config.libres` y cada número de `BloqueDivision.mesas`. Una familia
  fijada cerca del Ingreso sigue en la misma mesa, con otro número.
- **Se ve antes de guardar**: en "Antes de guardar" del panel, una línea "Los números se ordenan: quedan del 1 al
  35" (o nada si ya estaban en orden). Con Deshacer no se pierde nada: lo ordenado es lo que se guarda, no un paso
  de la sesión.
- **Después del sorteo los números no se tocan nunca** (pueden estar impresos o en una entrada). Si el jefe mueve
  mesas con familias sentadas, cada una se lleva su número, como hoy. **Al deshacer el sorteo entero, el próximo
  guardado del salón las vuelve a ordenar.** (Es lo que pasó en Puerto Viejo el 29-oct: sorteo 19:50, mesas
  corridas a mano y guardadas 20:05 con el sorteo puesto, deshacer 20:12. Las siete familias con dos o más mesas
  quedaron pegadas; los números, mezclados.)
- **ACOMODAR LAS MESAS sigue como está** (ya numera en orden). Agrandar o achicar el playón o un sector no mueve
  mesas ni números; al guardar se ordenan con las posiciones que tengan.

### 3b. El aviso en el plano

`PlanoDeLaFiesta.avisos` suma uno cuando `armado.cortes.length` pasa de los saltos que trae la serpentina (el paso de
un lado al otro y el cambio de hoja). Sin sorteo: "Los números no siguen el salón (13 saltos): se ordenan al
guardar en Personalizar". Con sorteo: lo mismo, pero "deshacé el sorteo para ordenarlos". No frena el sorteo; avisa.
Sirve para los salones que ya están guardados así (Puerto Viejo) y para el Canva.

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
  serpentina). Un cambio a una de las dos cuentas va en las dos (y en `armar`).
- **Convivencia:** una PC con la versión anterior abre y guarda un salón ordenado sin problema (son los mismos
  datos con otros números). Pero esa PC no ordena al guardar: **el plano se toca desde una PC con la versión nueva**.
- No comparar armados enteros con `firma`: mesa por mesa.
- `flutter analyze` y los tests, en la PC (el contenedor remoto no tiene Flutter).

## 5. Etapas (cada una cierra sola, con commit)

1. **La cuenta** (`armar_a_medida.dart`) y sus tests (`test/ordenar_numeros_test.dart`):
   - un salón acomodado queda igual y `cambio` es la identidad (ocho casos, como el test de `acomodar` contra
     `armar`);
   - Puerto Viejo tal como está en la nube (las 35 posiciones de arriba): de 1 a 35, y a lo sumo el salto entre lados;
   - pasto al final; dos hojas; una fila incompleta; mesas sueltas fuera de fila;
   - roturas a propósito, todas vistas.
2. **Al guardar** (`editar_armado.dart` → `paraGuardar`, y la línea de "Antes de guardar" en `panel_acomodar.dart`):
   - ordena sin familias con mesa; con familias, no toca nada; en el Canva, no toca nada;
   - fijadas, libres y bloques siguen a su mesa física (test con una fijada en una mesa que cambia de número);
   - una PC atrasada no pisa a la otra (`paraGuardar` ya relee la nube; un test de dos PCs como los de la 9c);
   - `test/solo_modo_jefe_test.dart` y `puerta_sigue_al_salon_test` siguen pasando;
   - test de pantalla en `plano_evento_cuerpo_test`.
3. **El aviso** (`plano_de_la_fiesta.dart`) con su test.
4. **Muestras** (`tool/plano_pantalla_muestra_test.dart`): Puerto Viejo antes y después. Mandárselas al usuario.
5. Versión, CONTEXTO nuevo, una línea en CLAUDE.md, instalador. Sin SQL.

## 6. Preguntas para el usuario

1. **"Marcado para que estén lejos":** hoy se tilda en el diálogo de SORTEO, el día del sorteo, y no queda guardado
   antes. ¿Así está bien, o lo quieren marcar antes en la ficha del alumno (cuando la familia lo pide)? Lo segundo es
   una tabla nueva (no una columna de `contratos_alumnos`) y una migración: va aparte de este plan.
2. ~~Armados del Canva~~ **Decidido el 29-oct:** se ordena solo en los salones con borde del playón; el Canva
   conserva la numeración del jefe.
3. **El orden** (pendiente; el usuario lo consulta). Las dos maneras dan 1, 2, 3… hasta N; cambia dónde queda cada
   número. Ejemplo con tres filas de cuatro, escenario arriba:

   ```
   Serpentina (la de siempre)      De corrido, como se lee
     1   2   3   4                   1   2   3   4
     8   7   6   5                   5   6   7   8
     9  10  11  12                   9  10  11  12
   ```

   - En la serpentina **dos números seguidos siempre están pegados** (el 5 queda debajo del 4). Es como numeró el
     jefe su Canva (página 3).
   - Como se lee, el 4 y el 5 quedan en puntas opuestas. El sorteo no separaría a nadie (corta en cada punta), pero
     **una familia no puede pasar de una fila a otra**: con filas de 4, la familia de Puerto Viejo que tuvo 5 mesas
     (20 a 24) no entraría junta, y en general entran menos combinaciones.

Lo que recomiendo: la serpentina, y "lejos" se sigue marcando en SORTEO por ahora. Puerto Viejo hoy no tiene familias
con mesa: con la versión nueva, abrir el plano y guardar alcanza para que queden del 1 al 35 en orden, sin mover
ninguna mesa.
