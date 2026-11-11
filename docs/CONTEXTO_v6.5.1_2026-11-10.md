# Contexto de la 6.5.1 (10 y 11-nov-2026)

Las mesas que llegan después del sorteo van al fondo. Sin SQL ni migración.

## Para retomar en otro chat

**Dónde estamos (11-nov, madrugada):** programado, con sus tests, guardado y subido a la rama: los tres tramos. **Sin publicar.**
Falta, con el usuario: mirar las capturas, decidir si el tramo 3 sale ahora, la versión `6.5.1+68`, el Setup y el APK, la foto de la
mora "antes de 6.5.1", el tag, el release y la web. Él instala la PC que sortea antes del próximo sorteo.

**De dónde salió.** El 10-nov se sorteó una escuela de 101 mesas con la 6.5.0. El usuario pidió primero cambiar la regla del sorteo
(que la mesa adicional sin pagar se sortee igual); antes de programar hizo escuchar cuatro audios del jefe, y el jefe decía lo
contrario: **el candado estuvo bien**, lo desbloqueó a mano y dejó últimos a los que no pagaron. **Ese cambio quedó descartado.**
Lo que el jefe pidió en los audios:

1. que el último número quede al fondo (la 101 le quedó pegada al escenario), donde está el espacio libre;
2. que quien confirma una mesa después del sorteo reciba una mesa nueva con el número que sigue (102, 103…), por orden de llegada.

Y el usuario sumó: **que se dé sola, sin apretar SORTEO** ("¿por qué tendría que apretar?").

En la base de esa escuela, leída el 10-nov a la noche (solo lectura): 101 mesas, 73 familias con mesa, 4 mesas fijadas por el jefe
para alumnos sin pagos, una mesa libre sin fijar, y **una familia con 2 mesas cargadas y un solo número**, que pagó la adicional 19
minutos después del último sorteo. Con la 6.5.0, SORTEO le daba la mesa libre; el jefe quería la 102. El plano no tenía Ingreso (solo
Escenario y Pasarela): por eso la recepcionista veía la mesa en color y no la flecha del camino. No es una falla: el camino sale del
Ingreso, y se agrega en Acomodar.

**Las dos cosas que conviene saber antes de tocar esto:**

- **El tramo 3 cambia una regla:** es lo único del salón que el programa guarda sin modo jefe. Se apaga en un solo lugar
  (`kMesaNuevaSolaHabilitada`, en `plano/services/mesa_nueva_sola.dart`).
- **La escuela ya sorteada no se renumera.** Con familias con mesa ningún número cambia: sus mesas nuevas van igual al fondo a la
  derecha, aunque la 101 siga junto al escenario.

> Frase para retomar: "Seguimos con la 6.5.1: leé 'Para retomar en otro chat' de docs/CONTEXTO_v6.5.1_2026-11-10.md. Está
> programada y probada en el sandbox; falta publicarla conmigo."

## Tramo 1 · La numeración termina al fondo

En Personalizar → Acomodar: **"La numeración termina: Junto al escenario · Al fondo"**.

- **Junto al escenario** es la serpentina de siempre: la izquierda del escenario al fondo, y la derecha de vuelta.
- **Al fondo:** las dos mitades desde el escenario, primero la izquierda y después la derecha. El último número queda al fondo, a la
  derecha, y las mesas que se agreguen siguen ahí.
- **Ninguna mesa se mueve:** cambian los números, **al guardar**, y lo que apunta a un número (una mesa fijada, una libre, un
  bloque) sigue a su mesa. Mientras se acomoda, los números se ven como estaban: si se renumeraran en la sesión, las fijadas
  quedarían apuntando a otra mesa.
- **Solo sin familias con mesa y en un salón a medida**, lo mismo que ya pedía ordenar los números. Con familias o en un armado
  del Canva se ve apagado, con el motivo.
- La cuenta: `FinNumeracion` (`plano/modelo/numeracion.dart`) y `ArmarAMedida._enSerpentina`, que usan `armar`, `acomodar` y
  `ordenarNumeros`, las tres igual. De los recorridos posibles queda el que menos corta; a igualdad, el que termina en la punta de
  afuera de la última fila de la derecha.
- **Se guarda en la `config` del plano, clave `numeracion`** (`'fondo'`; sin la clave, la de siempre). No va en `medidas` ni en el
  JSON del armado. `ConfigPlano` conserva las claves que no conoce: una PC con la 6.5.0 no la borra. **Lo que esa PC no sabe es
  numerar así: si guarda el salón antes del sorteo, lo vuelve a la serpentina de siempre.** El plano se toca desde la PC con la
  6.5.1.
- Tests: `test/numeracion_al_fondo_test.dart`.

## Tramo 2 · El número que sigue, con un SORTEO del jefe

Con el sorteo ya hecho, el cartel del SORTEO pregunta **"¿Dónde va la mesa que falta?"**: **En una mesa nueva, al fondo** (viene
elegido) · **En las mesas libres del salón** (lo de siempre). Antes de sortear dice qué número le toca a cada familia
("102 → …"), por orden de llegada.

- **El servicio** es `MesasNuevasAlFondo` (`plano/services/mesas_nuevas_al_fondo.dart`), cuenta pura. Por cada mesa que falta:
  - **el número** es el que sigue al más alto (`EditarArmado.proximoNumero`): nunca llena un hueco ni repite uno que ya se dio, ni el
    de una baja, una fijada o una libre;
  - **el lugar:** la primera, al lado de la mesa de más afuera de la última fila del lado derecho, en la hoja del fondo; las
    siguientes, al lado de la anterior. Nunca en el pasillo del medio. Las de una misma familia quedan juntas;
  - **queda fijada para su familia**, con el motivo "Mesa nueva: llegó después del sorteo". El sorteo de siempre se la entrega (le
    da a cada familia sus fijadas antes que nada), y si el sorteo se deshace y se vuelve a hacer, le toca la misma. **El motor no
    se tocó.**
- **El orden de llegada** es la hora del último pago de cada familia (`PagoAlumno.ultimo`, `llegadaPorPago`).
- **A quién no:** a quien tiene una mesa fijada esperándolo (recibe esa), a los de baja, a una familia con un número que no está
  en el plano, y a quien no pagó nada (el candado), salvo que el jefe lo tilde para sortearlo igual.
- **Cuándo se pregunta:** solo en un salón a medida y con alguna familia activa ya sentada. En el primer sorteo y en un armado
  del Canva, no.
- El salón, los números y el renglón van **en una sola transacción** (`asignarNumerosMesa(plano:)`), y el renglón anota qué mesas
  se agregaron (`SorteoMesasRegistro.nuevas`, clave `_nuevas`).
- Una PC con la 6.5.0 ve la mesa nueva como cualquier otra: no hay claves nuevas en el JSON del armado.
- **El salto de la mesa nueva no cuenta para "los números no siguen el salón"** (`PlanoDeLaFiesta._avisoDeSaltos`). En la
  muestra del 11-nov, después de dar la 102 al fondo, el plano decía "deshacé el sorteo para ordenarlos": lo contrario de lo
  pedido. Los tests estaban todos en verde; se vio mirando la imagen.
- Tests: `test/mesas_nuevas_al_fondo_test.dart` y `test/sorteo_mesas_nuevas_dialog_test.dart`.

## Tramo 3 · La mesa se da sola

A la familia que **pagó después del último sorteo** y le falta el número de una mesa que tiene algo pagado, el programa le da la
mesa sin que nadie apriete nada: su fijada, si tenía una esperándola, o una mesa nueva al fondo.

- **Lo que decide** está en `MesaNuevaSola` (`plano/services/mesa_nueva_sola.dart`), que no sabe de bases ni de pantallas: le
  habla al programa por `PuertosDeLaMesaNueva`. En la app, `mesa_nueva_sola_de_la_app.dart`.
- **Es angosta a propósito:**
  - solo **agrega**: nunca mueve ni saca una mesa de nadie, y nunca da una mesa libre del salón elegida al azar;
  - solo a quien **le tocó la mesa por un pago posterior** al último sorteo, deshacer o restaurar **que hizo el jefe**
    (`ultimoDelJefe`): con lo pagado hasta ahí no le tocaba, y ahora sí. No alcanza con haber pagado algo después: si ya le
    tocaba y no la tiene (el jefe deshizo su sorteo para rehacerlo, o tenía algo pagado de la adicional y quedó con una sola),
    que pague otra cuota no se la da sola. Sin registro de sorteos, no hace nada;
  - **o a quien acaba de agregar una mesa** (regla del usuario, 11-nov a la madrugada: "tengo una cuota paga y agrego una mesa
    sin pagar en el momento: solo agrego al sistema, ya debería darle"). Con **una cuota entera** de su contrato paga la recibe
    **al guardar Editar alumno**, aunque esa mesa no esté paga; la paga antes de retirar las entradas, que ya frena a quien debe
    algo. "Una cuota entera" lo confirmó él ("claro, una cuota entera"): una entrega parcial no alcanza, y sale de los pagos con
    la cuenta del saldo (`MesaNuevaSola.tieneUnaCuotaPaga`). **El sorteo no cambia: ahí sigue alcanzando con algo pagado.** Solo
    si tenía todas las suyas (`MesaNuevaSola.agregoUnaMesa`): si le faltaba una de antes (la tenía con candado, o el jefe
    deshizo su sorteo), agregar otra no le da ninguna sola. **No queda anotado en ningún lado que la agregó:** si en ese momento
    no hay internet, o la otra PC cambió mesas que todavía no bajaron, no se le da sola más tarde (salvo que la pague), y el
    aviso lo dice: "El jefe se la da con SORTEO";
  - **fuera de eso, la cuenta del candado, sin excepciones tildadas:** la adicional que ya estaba cargada sin pagar no entra
    (es la que el jefe decide en el sorteo), y quien no pagó nada de su contrato, nunca;
  - **solo con internet**, sin mesas de otra PC por bajar y con el plano recién leído de la nube. Sin internet queda "le falta el
    número de su mesa" y se da al volver.
- **Cuándo mira:** justo después de un cobro (un paso más de `DespuesDeGuardarCobro`, detrás de la subida: no frena el cobro ni
  el recibo), al guardar Editar alumno si se agregó una mesa (sin frenar el cierre de la ventana), y **al abrir el programa y
  cuando baja algo de otra PC** (`VigiaDeLaMesaNueva`, desde
  `OperationalSyncCoordinator`). Sin reloj propio: se dispara con algo que pasó, espera entre 20 y 60 segundos (distinto en cada
  PC) y **mira primero la base de esta PC, sin pedirle nada a la nube**. Casi siempre no hay nada y ahí termina.
- **Dos PCs a la vez.** La fila del plano sube entera: si dos PCs le dan la misma mesa nueva a dos familias en el mismo momento, en
  la nube queda una sola dueña. La próxima vez que cualquiera de las dos mira, **la que no figura en el plano pasa a la que
  sigue** (`_sinRepetidos`). Solo toca mesas fijadas con el motivo de la mesa nueva: una mesa repetida a mano no la arregla.
- **Queda anotado:** el renglón del registro va marcado automático (`SorteoMesasRegistro.automatico`, clave `_auto`), hecho por "El
  programa", y no cuenta como "el último sorteo". El jefe lo deshace con DESHACER → "solo los últimos sorteados". Además queda
  escrito en `Documentos\Junior Eventos\mesa_nueva_sola.txt`.
- **La regla que cambia:** `test/solo_modo_jefe_test.dart` nombra el archivo y lo que se le permite.

## Las pruebas

- **Los tests:** los cinco archivos nuevos y los que ya cuidaban el salón (`solo_modo_jefe`, `puerta_sigue_al_salon`, el sorteo
  sobre el plano).
- **Dos PCs simuladas y una nube de mentira** (`test/mesa_nueva_sola_dos_pcs_test.dart`, pedido del usuario): cada PC con su base,
  su cola y su internet, y la prueba decide cuándo sube y cuándo baja cada una. Son 32 casos. Cubre: una PC; sin internet y al
  volver; el candado; quien tenía una mesa reservada; **quien agrega una mesa sin pagarla** (con su cuota paga, dos de una vez,
  sin nada pagado del contrato, con una entrega parcial, la que ya estaba cargada de antes, sin internet, con mesas de la otra
  PC por bajar); lo que el
  jefe deshace; una PC después de la otra; la que todavía no bajó lo de la otra; las dos mirando a la misma familia; **la
  carrera** (las dos cobrando, o agregando, a familias distintas en el mismo momento, con el plano de cada una subiendo último,
  y las dos arreglándola a la vez). En todos: ningún número repetido al final, nadie se mueve, y queda quieto.
  **Lo que usa de verdad:** `MesaNuevaSola` entera, `MesasNuevasAlFondo`, el sorteo sobre el plano con su control final y la cuenta
  de lo pagado. **Lo que es de mentira:** las bases y la nube. En la app, esos caminos son los mismos por los que ya guarda el
  botón SORTEO; **no se probó con dos PCs de verdad contra la nube.**
- **Con el mouse**, en la ventana de prueba compilada para el navegador (`tool/plano_prueba.dart`, que suma LLEGA UNA FAMILIA):
  la opción en Acomodar, guardar y ver la derecha numerada del escenario al fondo; sortear; el cartel de verdad con la pregunta; la
  mesa nueva al fondo a la derecha, al lado de la última.
- **El simulacro** sobre una copia de la base (`tool/simulacro_mesa_nueva_sola_test.dart`; la real, con el mismo SHA-256): dice,
  fiesta por fiesta, a quién le daría una mesa el programa la primera vez que se abra, y dónde cae. La salida lleva nombres: va a
  `build/`. **El 11-nov dio una sola familia en seis fiestas:** la que esperaba su mesa en la escuela ya sorteada, que recibiría
  la 102 al lado de la mesa libre de la última fila, a 2,50 m y adentro del hormigón. En las otras cinco, nadie.
- **Las muestras** (`tool/mesas_al_fondo_muestra_test.dart`): cinco imágenes de la pantalla y del cartel de verdad, con el salón
  entero y familias inventadas.
- **Dos corridas de `flutter test` a la vez se pisan** (las dos copian `sqlite3.dll` y una se cae): de a una.

## Lo que no hace

- No cambia la regla de lo pagado ni el candado.
- No toca ningún sorteo hecho ni renumera un salón con familias.
- No cobra ni vende las entradas al 50 %.
- Sin SQL ni migración: la base sigue en la versión 78.

## Para publicar

1. Las capturas y lo que pasó las pruebas, con el usuario.
2. `6.5.1+68` en `pubspec.yaml` y en `installer/junior_eventos_setup.iss`.
3. `installer\build_installer.ps1` (comprueba la firma del APK).
4. Foto de la mora "antes de 6.5.1". Sin SQL.
5. Tag `v6.5.1`, release con el Setup y el APK, y la web.
6. Instala la PC que sortea antes del próximo sorteo; las otras conviven con la 6.5.0.
7. Después de instalar: mirar que la escuela ya sorteada quedó igual, salvo la familia que esperaba su mesa.
