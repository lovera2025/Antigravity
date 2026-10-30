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

### 3c. La barra de Acomodar: antes del sorteo reacomoda, después estira

**Pedido del usuario el 30-oct.** Hoy la barra "Separar o juntar" (`EditarArmado.separar`) estira las mesas parejo y
no cambia números, pero no sabe de la pista, la barra, los baños ni el borde del hormigón. Si se sube mucho, las mesas
de atrás quedan encima de un sector o fuera del playón. Encima, ACOMODAR OTRA VEZ la ignora y vuelve a la distancia
de Medidas. En Puerto Viejo, eso terminó con las mesas corridas a mano y los números mezclados.

**Ahora la barra hace lo que corresponde según el momento:**

- **Sin familias con mesa y con el borde del playón** (salón vacío, a medida o predio): la barra es **"Distancia
  entre mesas"**, de 1,5 a 5 m (`lugarMinimoM` a `lugarMaximoM`), de a 5 cm.
  - **Mientras se arrastra, el salón se reacomoda en vivo**, con `ArmarAMedida.acomodar(cantidad, lugarM: valor)`.
    Las mesas esquivan los sectores, quedan dentro del hormigón y se numeran en serpentina. Es la misma cuenta que
    ACOMODAR LAS MESAS, así que no hay dos formas de acomodar.
  - Al lado dice "Entran las 35" o "Faltan 3: bajá la distancia, agrandá el playón o achicá un sector".
  - **Soltar es un paso de Deshacer**, como `acomodar`, con `rehecho: true`: al guardar se quitan las fijadas, las
    libres y los bloques, con el aviso de siempre. Si había mesas corridas a mano, el aviso dice que se pierden (vuelven
    con Deshacer).
  - **La distancia se guarda en Medidas** al GUARDAR EL SALÓN (`config.medidas.lugarMesaM`, en `paraGuardar`, como
    `conMedidasDelPlayon`). El casillero "De centro a centro" de Medidas y la barra dicen siempre lo mismo, y ACOMODAR
    OTRA VEZ respeta lo que se eligió.
  - Rendimiento: la cuenta es pura y chica (hasta ~150 mesas); se recalcula como mucho cada 50 ms mientras se arrastra.
    Si en la PC del jefe se nota lenta, se reacomoda al soltar y mientras tanto se muestra la distancia.
- **Con familias con mesa, o en un armado del Canva**: la barra es **"Separar o juntar"**, como hoy. Estira, no cambia
  ningún número ni ninguna familia, con el alcance (todo, un lado, el bloque de una división) y la vista previa que
  avisa cuántas quedan fuera o encima de un sector. Es la única forma de abrir el salón después del sorteo.
- El título de la barra dice cuál de las dos es, y una línea debajo explica por qué ("Antes del sorteo: las mesas se
  vuelven a acomodar" / "Ya hay familias con mesa: se estira sin cambiar ninguna mesa").

### 3d. En el plano se ve qué familias tienen adicional, juntas o separadas

**Pedido del usuario el 30-oct.** Hoy cada mesa se pinta con el color de su división y la principal lleva el
apellido, pero no se ve qué mesas son de la misma familia.

- **Qué es cada una, sin guardar nada nuevo:** las mesas de la familia se parten en grupos pegados con
  `SorteoConPlano.tramosPegados(armado, numeros)`, la misma medida que usa el sorteo:
  - **una mesa**: nada nuevo;
  - **un solo grupo de dos o más**: **juntas**;
  - **más de un grupo**: **separadas** (lo que se marcó "lejos", o una familia que quedó partida).
- **Cómo se dibuja** (`pintor_plano.dart`), encima del relleno de la división, que no cambia:
  - **juntas**: una **cápsula** que une las mesas del grupo, por detrás, siguiendo la serpentina (también cuando dobla
    de fila, como la 8 y la 9);
  - **separadas**: un **aro punteado** en cada mesa, y abajo **"→ 30"** con el número de la otra mesa;
  - en las dos, la **P** en la principal (la que lleva el apellido, `InfoMesa.principal`) y la **A** en las
    adicionales.
- **Los colores salen del tema de cada estilo** (`TemaPlano`), con un contraste revisado contra los colores de las
  divisiones. **Nunca son la única marca**: la cápsula es línea llena, el aro es punteado, y van la P, la A y la
  flecha. Así se lee igual en blanco y negro.
- **Al tocar una mesa de una familia separada**, la otra se resalta (el foco de hoy), aunque esté en la otra hoja.
- **Antes del sorteo**, lo mismo con las fijadas: una familia con dos mesas fijadas se ve junta o separada.
- **La leyenda** suma "Juntas" y "Separadas" solo si en el salón hay alguna.
- **Prendido o apagado:** en la pantalla del plano, un botón "Familias con adicional", prendido de entrada. En el
  plano impreso, una casilla con el mismo nombre en el diálogo de imprimir, también prendida.
- **El tótem no cambia**: ya enciende las mesas de la familia que llega.

### 3e. "Lejos", y qué tan lejos

**Pedido del usuario el 30-oct:** que se respete que una familia con adicional quede junta, que la de una mesa tenga
una, y que la marcada "lejos" quede separada, **"obviamente no tan lejos"**.

**Revisado en el código el 30-oct:**
- **Juntas: se cumple.** El motor pone cada bloque en casilleros corridos, `CasillerosPlano` corta en cada salto del
  salón y `validar` rechaza a una familia nueva partida (`tramosPegados`). En el sorteo de prueba de Puerto Viejo del
  29-oct, las siete familias con dos mesas o más quedaron con números corridos (2-3, 6-8, 9-10, 17-18, 20 a 24, 26-27,
  28-29).
- **Una mesa: se cumple** (`simples`, una cada uno).
- **Lejos sin tocarse: se cumple** desde la 6.1.0 (`lejosEnElSalon`, medido en el salón, con sus tests).
- **Pero "lejos" hoy es lo más lejos posible.** `SorteoMesasMotor.candidatasLejos` ordena las libres de la más lejana
  a la más cercana, y `seCompleta` usa `_masLejos`. En la Normal (138 mesas), una familia en la 5 se lleva la
  adicional a la otra punta del salón, o de su bloque si se sortea por división. Es lo contrario de lo pedido.

**Ahora: el jefe elige qué tan lejos** (pedido del usuario el 30-oct: "una opción de qué tan lejos quiero que esté").
En el diálogo de SORTEO, al tildar "lejos" en un alumno, además de **cuántas** van lejos aparece **a qué distancia**:

| Opción | Qué hace | En el salón |
|---|---|---|
| **Cerca** (viene elegida) | La libre más cercana que no toque a la familia | Una mesa de por medio, o la fila de al lado sin tocarse |
| **A unas mesas** | Entre 3 y 6 lugares de su familia | Otra zona, a la vista |
| **Bien lejos** | La más lejana que haya (lo de hoy) | La otra punta del salón, o de su bloque |

- Las distancias se miden **en metros en el salón dibujado** y se cuentan en "lugares" (la distancia entre mesas de
  Medidas), así valen igual con las mesas a 2 m o a 3 m. Siempre **sin tocarse** (`lejosEnElSalon`, como hoy).
- **Lo normal es sortear entero** (dicho por el usuario el 30-oct: "por división casi no se hará, pero está bien que
  esté"). SORTEO ya viene en "entera" (`ModoSorteo.entera`, y ninguna fiesta tiene otro modo guardado). Las pruebas y
  la medición van primero sobre el sorteo entero.
- **Por división, todo es dentro de su bloque**: "bien lejos" es la otra punta del bloque, no del salón.
- Si en el salón no queda ninguna mesa en esa franja, se toma la más cercana a la franja, y el resultado del sorteo
  lo dice ("PÉREZ: la adicional quedó a 8 lugares; no había lugar a unas mesas").
- **Cómo se pasa:** `SorteoMesasDialogResult.separaciones` deja de ser `Map<String, int>` y pasa a llevar, por alumno,
  cuántas y a qué distancia. `PedidoSorteo` suma la distancia. Lo elegido queda escrito en el registro del sorteo,
  dentro de `resultado` con una clave con guion bajo (`_lejos`), sin tocar `sorteos_mesas.tipo`.
- **En la planilla del sorteo**, la columna Adicional de esa familia dice "lejos · cerca" (o "a unas mesas", "bien
  lejos"), así el jefe ve lo que se pidió.
- El motor recibe cómo ordenar las candidatas de cada familia (por defecto, el orden de hoy); `SorteoConPlano` le pasa
  el orden por distancia real en el salón, según la opción. **`esFactible` y `seCompleta` tienen que usar el mismo orden** que el
  sorteo: si no, el botón se habilita con una cuenta y el sorteo hace otra.
- Sin plano, lo mismo por número: "cerca" es la libre más cercana que no sea vecina; "a unas mesas", entre 3 y 6
  números; "bien lejos", lo de hoy.
- **Riesgo:** las sueltas se ponen después de todos los bloques. En un salón muy justo, lo cercano ya puede estar
  ocupado y la adicional cae donde quede. Si la medición lo muestra, se pone cada suelta enseguida después del bloque
  de su familia (cambia `esFactible`: va con sus tests de miles de salones).
- **Se mide antes y después**, como el arreglo de la 6.1.0: 1.000 sorteos por salón (Normal 138, Técnica, Puerto
  Viejo 35), entero y por división, con 20 familias "1 lejos" en cada una de las tres opciones. Se anota a cuántos
  lugares quedó la adicional. Lo esperado: casi siempre dentro de la franja elegida, y nunca tocándose.

### 3f. Lo que no cambia

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

## 5. Etapas (cada una cierra sola, con commit, y no se pasa a la siguiente con un test en rojo)

1. **Ordenar los números** (`ArmarAMedida.ordenarNumeros`), sin pantalla.
2. **Ordenar al guardar** (`EditarArmado.paraGuardar` y "Antes de guardar" del panel).
3. **El aviso de los números que no siguen el salón** (`PlanoDeLaFiesta.avisos`).
4. **La barra de Acomodar**: reacomoda antes del sorteo, estira después.
5. **Juntas y separadas en el plano**, en pantalla y en papel.
6. **"Lejos" y qué tan lejos**: el diálogo de SORTEO, el motor, `SorteoConPlano`, el registro y la planilla.
7. **El recorrido entero** (sección 5b, última fila de la tabla).
8. **Muestras** (`tool/plano_pantalla_muestra_test.dart`): Puerto Viejo antes y después; un salón sorteado con
   familias juntas y separadas, en pantalla y en PDF (color y blanco y negro). Mandárselas al usuario.
9. Versión, CONTEXTO nuevo, una línea en CLAUDE.md, instalador. Sin SQL.

## 5b. Qué prueba cada cosa acordada

Cada fila es un test que tiene que existir y pasar. Además, en cada etapa, **roturas a propósito**: se rompe la cuenta
a mano y el test tiene que ponerse en rojo (como en la 6.1.0).

| Lo acordado | El test |
|---|---|
| Números del 1 a N, sin huecos, en serpentina | `ordenar_numeros_test`: Puerto Viejo con las 35 posiciones de la nube del 29-oct queda de 1 a 35, con un solo salto (el pasillo); pasto al final; dos hojas; fila incompleta; mesa suelta |
| Ordenar no cambia un salón que ya está en orden | `ordenar_numeros_test`: sobre ocho salones acomodados, mesa por mesa igual y `cambio` vacío |
| Se ordena solo al guardar, antes del sorteo | `ordenar_al_guardar_test`: sin familias, ordena; con familias, no toca ningún número; en el Canva, no toca nada |
| Una mesa fijada sigue a su lugar, con otro número | `ordenar_al_guardar_test`: una fijada en la mesa que pasa del 15 al 2 queda fijada en la 2, en el mismo lugar; lo mismo con una libre y un bloque |
| Una PC atrasada no pisa a la otra | `ordenar_al_guardar_test`: dos PCs, como los de la 9c |
| Solo el jefe | `solo_modo_jefe_test` y `puerta_sigue_al_salon_test` siguen pasando sin cambios |
| El aviso de los saltos | `plano_de_la_fiesta_test`: con 13 saltos avisa; recién acomodado, no |
| La barra reacomoda antes del sorteo | `barra_acomodar_test`: arrastrar sin soltar no agrega pasos de Deshacer, soltar agrega uno, Deshacer vuelve; ninguna mesa encima de un sector ni fuera del hormigón; numeradas en serpentina; "Faltan N" cuando no entran |
| Barra y ACOMODAR dan lo mismo | `barra_acomodar_test`: la barra en 3 m y ACOMODAR con Medidas en 3 m, mesa por mesa iguales |
| La distancia queda en Medidas | `barra_acomodar_test`: después de guardar, `config.medidas.lugarMesaM` es la de la barra, y ACOMODAR OTRA VEZ la usa; `salon_convivencia_test`: sin claves nuevas en el JSON |
| Después del sorteo, la barra estira sin cambiar ninguna mesa | `barra_acomodar_test`: con familias, ningún número ni familia cambia; los tests de `separar` de hoy siguen pasando |
| El plano marca juntas y separadas | `familias_en_el_plano_test`: una mesa (nada), dos pegadas (juntas), tres que doblan de fila (juntas), dos lejos (separadas), tres con una lejos, pasto, dos hojas; P en la principal y A en las demás |
| Se lee en blanco y negro | `familias_en_el_plano_test`: el dibujo en los tres estilos, con color y sin color, lleva cápsula, aro punteado y letras |
| Tocar una separada resalta la otra | `plano_evento_cuerpo_test` |
| Con adicional, siempre juntas | `sorteo_juntas_test`: 1.000 sorteos enteros (y 200 por división) sobre Normal 138, Técnica y Puerto Viejo, con las familias reales de la nube copiadas a datos de prueba: **ninguna familia sin "lejos" queda partida** |
| Una mesa, una | `sorteo_juntas_test`: cada familia recibe exactamente las mesas que tiene en su cuenta |
| "Lejos" nunca se toca | `sorteo_lejos_en_el_salon_test` (el de hoy), con las tres opciones |
| "Qué tan lejos" se respeta | `tool/lejos_distancias_test.dart`: 1.000 sorteos por salón y por opción; cerca, casi siempre a 1 o 2 lugares; a unas mesas, entre 3 y 6; bien lejos, como hoy. La medición de hoy queda anotada antes del cambio |
| Si no hay lugar a esa distancia, avisa | `sorteo_con_plano_test`: el salón lleno da la más cercana a lo pedido y el aviso con el nombre |
| Lo pedido queda registrado | `sorteo_con_plano_test`: `_lejos` en `resultado`, y `sorteos_mesas.tipo` sin valores nuevos |
| La planilla dice "lejos · cerca" | `planilla_sorteo_test` |
| El motor sigue siendo factible | `sorteo_mesas_motor_test`, con los miles de salones de hoy y las tres opciones |
| **El recorrido entero** | `recorrido_salon_test`: Puerto Viejo como está en la nube → guardar (se ordena) → sortear con dos familias "lejos" (una cerca, una bien lejos) → juntas, lejos y números en orden → deshacer → barra a 3 m → sortear de nuevo |

Los tests corren en la PC del usuario (`flutter test`): el contenedor remoto no tiene Flutter.

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
