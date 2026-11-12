# Contexto: la 6.6.1 — la numeración fila por fila y las adicionales al final

11-nov-2026 (noche). Rama `feature/v4.6-cierre-por-sesiones`. Plan aprobado por el usuario ese
día. Sin SQL y sin migración de la base del equipo (sigue en la v79).

## Para retomar en otro chat

**Estado: PUBLICADA el 11-nov a las 23 hs, con el usuario ("Publica"). Falta que instale: primero
la PC que sortea (antes del sorteo del 12-nov), después las otras dos y las tablets; y la foto de
la mora "después de 6.6.1".**

### Publicada

- **Tag `v6.6.1`** en `6fabf66` y **release** "Junior Eventos 6.6.1" (el último), con
  `Setup.Junior.Eventos.v6.6.1.exe` (41 MB) y `Junior.Eventos.v6.6.1.apk` (53 MB, versión 6.6.1,
  firmado con "CN=Junior Eventos", comprobado con `apksigner`). Novedades: "El plano se numera
  fila por fila y, en el sorteo, las mesas adicionales pueden ir al final. Arregla los íconos del
  celular de la puerta". El Setup se bajó del release para comprobarlo (el mismo tamaño que el armado).
- **Web** en Vercel: `arguello-events-q9h532u4d`, producción; `version.json` da 6.6.1/70 y sirve
  sus letras. La anterior, para volver atrás: `arguello-events-qj0b8gfpx` (la 6.6.0).
- **La foto de la mora "antes de 6.6.1"** (por el conector de Supabase): 642 alumnos,
  `foto_id a900a524-77c9-4588-b266-a7e8061d6db1`. No se sabía en qué PCs estaba la 6.6.0 (la de
  la casa, sí). Comparada con la de antes de la 6.6.0 (`da6aec8c…`): **nada sospechoso**. Dos
  perdones nuevos (los de ese día) y un alumno al que la mora pendiente le pasó de 0 a 25.200:
  `mora_cambios` muestra que fue un cobro (cambiaron el saldo y las cuotas pagadas, y el "ya
  usado" subió 140.350), no una mora que revivió.
- **El instalador se armó por pasos**, con las comprobaciones: la clave de firma, la página del
  celular entera antes de `ISCC` (146 archivos en su registro), y `apksigner`.
- Sin SQL.

### Lo que queda

- **Instalar** (lo hace el usuario y avisa): la PC que sortea primero. La base del equipo no
  cambia (sigue en la v79; una PC que venga de la 6.5.1 pasa de la 78 a la 79, como con la 6.6.0).
- **La foto de la mora "después de 6.6.1"**, con las tres PCs instaladas y abiertas, y la
  comparación con `a900a524…`.
- Preguntarle cómo salió el sorteo con "Fila por fila" y "Al final".

> Frase para retomar: "Seguimos con la 6.6.1: leé 'Para retomar en otro chat' de
> docs/CONTEXTO_v6.6.1_2026-11-11.md. Está publicada desde el 11-nov a la noche; preguntame
> qué instalé y cómo salió el sorteo."

### La 6.6.0 salió con la página del celular incompleta (lo arregla esta versión)

El 11-nov a las 21 hs el usuario mandó una captura del celular de la puerta: **los íconos eran
cuadraditos vacíos**. La página instalada con la 6.6.0 (`{app}\puesto`) tenía 16 archivos en
vez de 146: **le faltaba toda la carpeta `assets`** (la letra de los íconos, la del texto, las
demás letras y los fondos).

- **Lo que se ve:** con internet en el celular, el texto aparece (la letra baja de Google) y
  los íconos no. **Sin internet, esa página no dibuja nada** (la trampa de la 6.2.1: sin su
  Roboto, Flutter web espera a `fonts.gstatic.com`). En el salón no hay internet.
- **Por qué pasó:** el instalador de la 6.6.0 se armó por pasos (el script no entra en los 10
  minutos de la herramienta) y `ISCC` se llevó `build\puesto` a medio copiar. La línea con el
  asterisco se lleva lo que haya, sin avisar.
- **El freno, doble:** el `.iss` nombra tres archivos de la página (`FontManifest.json`, la
  letra de los íconos y `Roboto-Regular.ttf`): **si falta uno, el instalador no compila**. Y
  `build_installer.ps1` comprueba lo mismo antes de llamarlo. `test/instalador_puesto_test.dart`
  cuida las dos cosas.
- **Comprobado con la 6.6.1:** el registro de `ISCC` lista los 146 archivos de la página; y la
  página, servida por `tool/central_prueba_test.dart` y abierta en un navegador, muestra todos
  los íconos y pide las letras a la central (ningún pedido a `gstatic`).
- **Hasta instalar la 6.6.1, una PC con la 6.6.0 no sirve para los celulares de la puerta sin
  internet.** La app de la PC, el tótem y Recepción en la PC no tienen el problema.
- Al armar el instalador por pasos: después de `flutter build web … -o build\puesto`, mirar que
  estén esos tres archivos **antes** de `ISCC`, y guardar su registro (`> build\iscc.log`) para
  contar los archivos de `build\puesto`.

### De dónde salió

Un audio del jefe del 11-nov, para el sorteo del día siguiente (transcripto en la PC, automático):
"la serpentina del número tiene que ser todo completo, el plano completo como te mostré, y las
mesas adicionales que me dé la opción que vayan agregándolo último; si son 66 mesas principales,
la mesa adicional que se vaya agregando a partir de la 67 en adelante".

Son dos pedidos que van juntos: **con los números de corrido por el salón entero y las
adicionales al final, las mesas principales quedan en las filas de adelante, a todo lo ancho, y
las adicionales en las del fondo.**

Lo que se vio ese día en la base de la PC de la casa (solo lectura):
- La escuela del 12-nov: 67 alumnos y 13 adicionales (80 mesas cargadas), nadie con mesa, y un
  plano de 75 mesas. Es el "66 y de la 67 en adelante" del audio.
- La escuela sorteada el 11-nov: el jefe lo intentó a mano. Sorteó, deshizo y volvió a sortear
  tildando "lejos → Donde yo elija" a las 16 familias con adicional, una por una. Le quedaron
  principales hasta la 55 y adicionales desde la 6. Lo nuevo es ese trabajo en un toque.

### Lo que pidió el usuario al aprobar

- **Que sea una opción** ("porque por ahí puede que no"): viene sin elegir.
- **Más opciones adentro**: una regla por cantidad y excepciones por familia.
- **Al terminar, la guía paso a paso** de lo nuevo y sus opciones (está abajo).
- Preguntó si lo elegido **se guarda antes de sortear**: ver "Qué se guarda y cuándo".

### Lo que NO se probó

- **Con dos PCs de verdad contra la nube.** Nada de esto cambia cómo se guarda (es el camino de
  siempre del salón y del sorteo), pero no se sorteó de verdad con la opción.
- **Desde la pantalla de la fiesta de la app instalada**: esa pantalla no se puede montar en
  una prueba. Lo que sí se recorrió con el mouse, en `tool/plano_prueba.dart` (en memoria): la
  pantalla del plano de verdad (Acomodar → Fila por fila → GUARDAR EL SALÓN: los números
  cambiaron al guardar) y **el cartel del SORTEO de la app** (el ícono de arriba, nuevo: "Al
  final", "Dejar juntas" en una familia, SORTEAR), con el sorteo y el control final de verdad.
  Lo único que no pasó por el mouse es el tramo de la pantalla de la fiesta que le pasa lo
  elegido al sorteo y anota el registro (dos renglones).

### Convivencia: el plano y el sorteo, desde una PC con la 6.6.1

- Una PC con la 6.6.0 **no conoce "Fila por fila"**: la lee como la serpentina de siempre y, si
  guarda el salón antes del sorteo, lo renumera así. Además, al guardar la `config` del plano
  **pierde la clave** (para ella es una numeración que no entiende).
- Una PC con la 6.6.0 **no tiene la opción "Al final"**: sortea como siempre.
- Con las familias ya sentadas no cambia ningún número, en ninguna versión.

---

## 1. La numeración "Fila por fila"

**Dónde:** PLANO → Personalizar → Acomodar → **LA NUMERACIÓN** (el título decía "LA NUMERACIÓN
TERMINA"): *Al escenario · Al fondo · **Fila por fila***. ("Al escenario" es la de siempre,
"Junto al escenario": con tres opciones lado a lado el rótulo largo no entraba; `FinNumeracion.rotulo`.)

```
 Por mitades ("Al fondo")          Fila por fila
        ESCENARIO                         ESCENARIO
  4  3  2  1 | 33 34 35 36          1  2  3  4 |  5  6  7  8
  5  6  7  8 | 40 39 38 37         16 15 14 13 | 12 11 10  9
 12 11 10  9 | 41 42 43 44         17 18 19 20 | 21 22 23 24
```

- Cada fila va entera, de una punta a la otra **cruzando la pasarela**, y la siguiente vuelve.
  Los primeros números quedan adelante y el último, al fondo.
- **Arranca a la izquierda del escenario** (el 1 donde se empieza a leer); si arrancando a la
  derecha la numeración queda con menos cortes, arranca ahí (`_elQueMenosCorta`, como las otras).
- Igual que las otras dos: **solo sin familias con mesa y en un salón a medida**; los números
  cambian **al guardar**; ninguna mesa se mueve; lo que apunta a un número (fijadas, libres,
  bloques) sigue a su mesa; y **queda recordada para las fiestas que vienen**
  (`NumeracionRecordada`, sin tocar).
- **El cruce de la pasarela es un corte:** una familia con sus mesas juntas nunca queda a los
  dos lados. Lo cuida `CasillerosPlano`, que no se tocó (mete un casillero fantasma donde dos
  números seguidos no están pegados).

**El código:**
- `FinNumeracion.filas` (`plano/modelo/numeracion.dart`), clave `filas`. **Va al final del
  enum**: una versión anterior no la conoce y la toma por `escenario`.
- `ArmarAMedida._Recorrido` tiene un campo más, `cruza`; `_recorridos` da los dos de "fila por
  fila" y `_enSerpentina` los recorre. `armar`, `acomodar` y `ordenarNumeros` pasan las tres
  por ahí, así que dan lo mismo (un test lo compara mesa por mesa).
- `ConfigPlano.eligioNumeracion` preguntaba por `fondo`: ahora, por "distinta de la de siempre".
- Tres textos con tres casos: `panel_acomodar.dart`, `plano_evento_cuerpo.dart` (el aviso al
  elegir) y `sesion_acomodo.dart` ("los números se ordenan al guardar…, fila por fila").

Tests: `test/numeracion_fila_por_fila_test.dart`.

## 2. "Las mesas adicionales: Con su familia · Al final"

**Dónde:** en el cartel del SORTEO, en el recuadro del salón, **debajo de cómo se sortea**
("Por división, cada una junta · Toda la escuela junta"). Solo aparece si alguna familia sin
mesa trae adicionales para sortear.

```
 Las mesas adicionales
   ( Con su familia )   (• Al final, después de las principales )
   Quedan pegadas a la principal:   [ Ninguna ]  [ 1 ]  [ 2 ]
   Adelante: de la 1 a la 67 · Al final: de la 68 a la 80 (13 mesas).

 Con mesas extra (11)
   BENÍTEZ, ALUMNO    1 extra · 2 en total           [ Dejar juntas ]
     La principal va adelante; la otra va al final.
```

Tres cosas para elegir:

1. **La opción general. Viene en "Con su familia"**: sin tocar nada, se sortea como siempre.
2. **La regla por cantidad** (con "Al final"): cuántas adicionales quedan pegadas a la
   principal, para todas las familias. *Ninguna*: todas al final. *1*: la principal y una
   adicional juntas, y de la tercera mesa en adelante, al final. Viene en *Ninguna*.
3. **Las excepciones** (con "Al final"): en "Con mesas extra", cada familia tiene **Dejar
   juntas**: queda con todas sus mesas pegadas, adelante.

Y además:
- **Solo con "Toda la escuela junta".** Por división se ve apagada, con el motivo: cada bloque
  es de su división y "después de todas" no tiene un lugar.
- **Entre las que van al final, por sorteo**; las de una misma familia quedan juntas entre sí.
- Con "Al final", **los tildes de "lejos" de las familias sin mesa no se usan** (los reemplazan
  la regla y "Dejar juntas"): el cartel no los muestra y no viajan al sorteo. Los de quien ya
  tiene mesa y le falta otra siguen igual.
- **La adicional sin pagar sigue el candado de siempre**: esa familia va solo con la principal,
  y cuando paga recibe la mesa nueva al fondo (6.5.1).
- **"Las de adelante, de la mesa 1 a la"**: el casillero de siempre ("Usar de la mesa 1 a la")
  pasa a decir hasta dónde van las de adelante; las del final empiezan en la mesa que sigue.
- **Mover a mano después ya estaba** (6.6.0, mover una sola mesa).

**Cómo se hace, sin tocar el motor** (`sorteo_mesas_motor.dart`):
- `EntradaSorteoPlano.alFinal`: alumno → cuántas de sus mesas van al final. Vacío: lo de
  siempre. Lo arma el cartel con `SorteoConPlano.alFinalSegunElCartel` (la opción, la regla y
  las excepciones); el servicio solo lo cumple.
- `SorteoConPlano.mesasAlFinal` es **la misma cuenta para sortear y para el control final**:
  solo en el sorteo entero, solo para la familia que todavía no tiene mesa, y **la principal
  queda siempre adelante** (como mucho van todas menos una).
- En `_entera`, **dos pasadas con el mismo `_sortearEn`**: primero un pedido por familia con sus
  mesas de adelante, en la capacidad mínima; después, con todo lo de antes tapado (también los
  huecos), un pedido aparte por familia con las del final, desde el casillero que sigue. El
  pedido del final entra al motor con el id del alumno más `#al-final`, y al volver se juntan.
- `PlanSorteo.mesasAlFinal`, `alFinalDesde` y `alFinalHasta`: lo que el cartel dice antes de
  sortear. Si las del final no entran después de las de adelante, `entra` es false y lo dice.
- **`validar` (la red final, antes de guardar):** a esas familias no les pide "todas juntas";
  les pide las de adelante juntas, las del final juntas entre sí, y que **ninguna del final
  quede antes que una de adelante** en el orden en que se recorre el salón. Si algo no cierra,
  no se guarda ni un número, como siempre.
- **El registro:** `SorteoMesasRegistro.alFinal`, que viaja adentro de `resultado` con la clave
  `_al_final` (alumno → "68, 69"). `sorteos_mesas.tipo` no cambia.
- La pantalla de la fiesta solo le pasa `config.alFinal` a la entrada y anota el registro:
  **ningún guardado nuevo del salón** (el mismo camino, con modo jefe y `trasElSalon`).

Tests: `test/sorteo_adicionales_al_final_test.dart` (la cuenta) y
`test/sorteo_adicionales_al_final_dialog_test.dart` (el cartel).

## Qué se guarda y cuándo

- ***Fila por fila*** se guarda con GUARDAR en Acomodar, **antes** del sorteo, y queda
  recordada para las fiestas que vienen.
- **Lo del cartel no se guarda antes**: vale cuando se aprieta SORTEAR. Si se cierra el cartel
  sin sortear no cambia nada, y la próxima vez vuelve a venir en "Con su familia". Lo que se
  hizo queda anotado en el registro de ese sorteo.

## La guía paso a paso (para el jefe)

Todo en modo jefe, desde una PC con la 6.6.1.

**Antes del sorteo: el salón**
1. En la fiesta, **PLANO → PERSONALIZAR → Acomodar**.
2. Poner las mesas que hacen falta: **ACOMODAR LAS MESAS** y la cantidad (para 67 alumnos con
   13 adicionales, 80).
3. En **LA NUMERACIÓN**, tocar **Fila por fila**. Los números todavía se ven como estaban:
   cambian al guardar.
4. **GUARDAR.** Ahora el 1 está adelante a la izquierda, cada fila cruza la pasarela y el
   último número queda al fondo. En las fiestas que vienen ya viene elegido.

**El sorteo**
5. **SORTEO.** Revisar arriba a quién se sortea (el candado de lo pagado, como siempre).
6. En el recuadro del salón, elegir **Toda la escuela junta**.
7. En **Las mesas adicionales**:
   - **Con su familia** (viene así): cada familia con todas sus mesas juntas. Lo de siempre.
   - **Al final, después de las principales**: el cartel dice "Adelante: de la 1 a la 67 · Al
     final: de la 68 a la 80".
8. Si eligió *Al final*, puede ajustar:
   - **Quedan pegadas a la principal: Ninguna · 1 · 2.** Para que cada familia conserve una (o
     dos) adicionales al lado de la principal y solo las de más vayan al final.
   - Más abajo, en **Con mesas extra**, **Dejar juntas** en la familia que pidió estar junta:
     esa queda entera, adelante.
9. **SORTEAR.**

**Después**
10. Si una mesa no le gusta dónde quedó: en PLANO, tocar esa mesa → **Mover a otras mesas** o
    **Cambiar con otra familia** → elegir cuál mesa → tocar el destino. Se mueve esa sola.
11. Si no le gustó el sorteo entero: **SORTEO ▾ → Deshacer**, y de nuevo.
12. Quien pague una mesa después del sorteo recibe la mesa nueva al fondo, con el número que
    sigue, como desde la 6.5.1.

## Las pruebas

- Los tres archivos de test nuevos, y la suite entera: **4.471 pruebas en verde**.
- **La falla suelta de la suite, identificada** (en la 6.6.0 había quedado sin nombre): en dos
  de cinco corridas enteras falló una sola prueba, y es
  `test/chat_de_la_noche_test.dart`, "por la central cada celular sabe con quién puede hablar:
  la PC y los otros" (el chat de la puerta, 6.5.0). Sola pasa siempre (5 de 5): falla solo con
  la PC cargada por la suite entera, así que es de tiempos de la prueba (la central de verdad
  en esta PC), no de estos cambios, que no tocan Recepción. Queda sin arreglar.
- **Simulacro con la escuela de verdad** (`tool/simulacro_adicionales_al_final_test.dart`,
  sobre una copia de la base en `build/`, solo lectura): acomoda el salón, numera fila por
  fila y sortea 200 veces en cada caso, pasando cada sorteo por el control final. El 11-nov a
  la noche, con la escuela del 12-nov (66 alumnos activos, 79 mesas cargadas):
  - **a todo lo cargado** (`--dart-define=todo=true`): con el salón acomodado a 79 mesas,
    **adelante de la 1 a la 66 y al final de la 67 a la 79**; con 1 pegada, adelante de la 1
    a la 77 y al final la 78 y la 79. Los 200 sorteos de cada caso pasaron el control;
  - **con el candado de siempre** ("solo a lo que tiene algo pagado"): ese día entraban 47
    familias y 54 mesas (19 sin nada pagado de la base, 4 solo con la base): adelante de la 1
    a la 47 y al final de la 48 a la 54. **El "66 y de la 67 en adelante" del audio es con
    todos**: depende de cuántos tengan pagado cuando se sortee, o de que el jefe los tilde;
  - en el plano como estaba guardado (75 mesas), todo lo cargado no entra, con ninguna opción:
    hay que acomodarlo.
- **Las muestras** (`tool/adicionales_al_final_muestra_test.dart`): el salón numerado de las
  dos maneras, Acomodar, el cartel en sus tres estados y el salón sorteado.
- **Con el mouse**, en `tool/plano_prueba.dart` (`flutter run -d windows -t
  tool/plano_prueba.dart`): arriba tiene un ícono nuevo, "Sortear con el cartel de la app",
  que abre el cartel de verdad para el primer sorteo. En un salón con pista y sin pasarela (35
  mesas), "Fila por fila" dejó 6 saltos contra 1 de la numeración de siempre: **cada cruce del
  medio es un corte**, así que con familias de varias mesas juntas el salón rinde un poco
  menos; con "Al final" casi no importa, porque casi todo son mesas sueltas.
