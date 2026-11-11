# Contexto de la 6.5.1 (10 y 11-nov-2026)

Las mesas que llegan después del sorteo van al fondo. Sin SQL ni migración.

## Para retomar en otro chat

**PUBLICADA el 11-nov a las 7:30, con el OK del usuario** ("dale, tenés mi ok, publicá"): los tres tramos **y un cuarto, de esa
mañana: la última numeración elegida queda para las fiestas que vienen, en las tres PCs** (abajo, "Tramo 4"). Sin SQL.
- **Foto de la mora "antes de 6.5.1":** 642 alumnos, los mismos que hay (`foto_id` `24de5b63-d23c-48f9-a399-70194ec8f263`). Son 642
  y no los 643 del 10-nov: entre las dos fotos se eliminó a un alumno (sin mora; su ficha no se tocaba desde julio). No se revisó
  quién ni por qué: se le avisó al usuario. **Se sacó por el conector de Supabase, que desde el 11-nov ve ArguelloApp** (antes estaba en otra cuenta): ya no hace falta
  el SQL Editor en el navegador, que ese día pedía iniciar sesión.
- **Tag `v6.5.1`** en `23f9005` y **release** con el Setup y el APK firmado (comprobado con apksigner por el instalador). Novedades:
  "Las mesas que llegan después del sorteo van al fondo".
- **Web** en Vercel: `dpl_77AhrbdhTREfkMNmZLvbzCeZ8QGN`, producción, `version.json` da 6.5.1/68. La anterior, para volver atrás:
  `dpl_H544LDGtEjttRgRJt3Qu3ACN9KCL` (la 6.5.0).
- **La primera PC con la 6.5.1 se abrió el 11-nov a las 7:48 (la de la casa), y la mesa se dio sola a las 7:49:** la familia que
  esperaba su mesa en la escuela ya sorteada quedó con la suya y la 102, como decía el simulacro. En la nube: la ficha con los dos
  números, el plano con la 102 fijada ("Mesa nueva") y el renglón del registro marcado automático. **El usuario avisó a los
  segundos de abrir que "no se la dio": todavía no había pasado la espera** (el programa mira entre 20 y 60 segundos después de
  abrir, cuando terminó de bajar). No había nada roto. Si vuelve a pasar, mirar primero `mesa_nueva_sola.txt` y la hora.

**Lo pendiente, al 11-nov al mediodía** (lo que se sabe hasta las 7:50; después de eso el usuario no avisó qué instaló):
1. **Instalar las otras dos PCs, primero la que sortea** (a la tarde del 11-nov hay un sorteo y esa PC tiene que tener la 6.5.1
   antes), y el APK en la tablet. Las que sigan en la 6.5.0 conviven, pero **el plano se toca solo desde una con la 6.5.1**.
   Preguntarle qué instaló antes de darlo por pendiente.
2. **El sorteo de esa tarde**, con los pasos de "Para la tarde del sorteo", abajo. Preguntarle cómo salió: es la primera vez que
   la numeración al fondo y la memoria se usan con una fiesta de verdad.
3. **La foto de la mora "después de 6.5.1"**, con las tres instaladas y abiertas, y la comparación con "antes de 6.5.1". Va a
   figurar una ficha bajando de $372.368 a 0: es la corrección de la 6.5.0 (abajo).
4. **Mirar que la escuela ya sorteada quedó igual**, salvo la familia de la 102. La 102 se comprobó en la nube; que nadie más
   cambió de mesa no se comparó familia por familia.
5. **Dos cosas que se le avisaron y no contestó:** el alumno que se eliminó entre la foto del 10-nov y la del 11-nov (¿fue él o el
   jefe?), y otra ficha a la que la mora le bajó de $4.200 a 0 el 10-nov a las 18:36 (el perdón y la eximición no cambiaron; no se
   miró qué escritura fue en `mora_cambios`).
6. **De la 6.5.0, ya se puede** (las tres PCs la tienen): crear "Silla suelta" en el catálogo, reservar una mesa con "Es para
   alguien" y que la Encargada de barra use el iPhone.
7. **Lo que no se probó:** dos PCs de verdad contra la nube, ni para la mesa sola ni para la memoria de la numeración.
8. **Lo que quedó sin hacer a propósito:** "Estilo y armado" con mesas (A medida) numera como siempre y toma la recordada recién
   al abrir Acomodar; el chat con la barra (`docs/pendientes/chat-con-la-barra.md`); y `chat_de_la_noche_test`, que falla a veces
   con la PC cargada (abajo).

**La 6.5.0 quedó instalada en las tres PCs** (lo dijo el 10-nov a la noche) **y cerrada el 11-nov a las 7:44**: la ficha corregida
y la foto "después de 6.5.0", sin nada sospechoso (el detalle, arriba de todo en su CONTEXTO). **La foto "antes de 6.5.1" es de las
7:32, doce minutos antes de la corrección:** al compararla con la de "después de 6.5.1", esa ficha va a figurar bajando de
$372.368 a 0. Es la corrección, no algo de la 6.5.1.

**Las pruebas del 11-nov:** la corrida entera dio 4.332 de 4.333; el único que falló, `chat_de_la_noche_test` ("cada celular sabe con
quién puede hablar", con sockets de verdad), pasa corrido solo (14 de 14) y había pasado en la corrida anterior del mismo día: es de
tiempos con la PC cargada, no de lo de hoy. El análisis no nombra ningún archivo tocado (los 3 errores que da son de
`tool/_tmp_espindola_audit.dart`, un archivo viejo fuera de git). **El simulacro se repitió sobre una copia fresca de la base** (la
real, con el mismo SHA-256 antes y después): sigue dando **una sola familia**, la que recibe la 102 en la escuela ya sorteada.

**Para la tarde del sorteo**, en la PC con la 6.5.1: PLANO → Personalizar → Acomodar → "La numeración termina: Al fondo" → GUARDAR
EL SALÓN, **antes de sortear** (con familias sentadas queda apagado); de paso, poner el Ingreso (sin él la puerta no ve la flecha);
y SORTEO. Con candado salen los que no pagaron nada de la cuota base; no hace falta destrabarlos: cuando pagan, reciben solos la
que sigue, al fondo. A quien no pagó nada se le puede cargar una mesa igual; sola no se le da nunca.

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
> publicada desde el 11-nov y la PC de la casa ya la tiene; mirá 'Lo pendiente' y preguntame qué instalé y cómo salió el sorteo."

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

## Tramo 4 · La última numeración queda para las fiestas que vienen (11-nov, mañana)

Lo pidió el usuario el 11-nov a la madrugada, mirando el sorteo de esa tarde: "que venga default como viene, el tema es que si yo
configuro después que quiero al fondo, de ahí ya debe quedar guardado para cada fiesta, salvo que yo cambie después de vuelta, y así
que quede guardado para fiestas futuras". Preguntó si hacía falta una tabla nueva: **no**. Y eligió que lo recuerden **las tres PCs**,
no cada una por separado.

- **Cómo queda:** todo arranca como hoy ("Junto al escenario"). La primera vez que se guarda un salón con "Al fondo", queda
  recordado: en cada fiesta **sin sortear, a medida y que nunca eligió**, Acomodar abre con "Al fondo" ya elegido, lo dice ("Viene
  elegido porque fue lo último que se eligió en otra fiesta. Queda al guardar.") y solo falta GUARDAR EL SALÓN. Si después alguien
  elige "Junto al escenario", pasa a recordarse eso.
- **Dónde vive:** en la `config` del plano de cada fiesta, que ya se sincroniza. Dos claves: `numeracion` (ahora también
  `escenario`, cuando alguien lo eligió) y `numeracion_el` (el momento, en hora universal). **Sin la clave `numeracion`, la fiesta
  nunca eligió.** La recordada es la más nueva de todos los planos que la PC tiene en su base (`NumeracionRecordada.de`, con
  `PlanosEventoRepository.configsDeLasFiestas`, una lectura local sin red). Llega a las otras PCs cuando baja ese plano.
- **Nada cambia solo:** la memoria se aplica al abrir Acomodar (`SesionAcomodo`, con `recordada`), deja GUARDAR prendido, y los
  números se ordenan recién cuando el jefe guarda. Con familias con mesa o en un armado del Canva no se aplica, y la fiesta que ya
  eligió se queda con la suya.
- **La que viene de la memoria conserva el momento de aquella elección** (`SesionAcomodo.finEl`); solo tocar la opción lleva el de
  ahora. Si heredar pusiera el momento de ahora, una PC que todavía no bajó una elección más nueva de la otra le ganaría al guardar
  cualquier fiesta. Está probado con dos PCs (abajo).
- **DESCARTAR** vuelve a como abrió la sesión, con la recordada puesta.
- **Después de guardar la numeración sin que cambie ningún número** (un salón sin mesas), la sesión arranca de nuevo desde lo
  guardado: antes seguía ofreciendo GUARDAR.
- **La 6.5.0 conserva las dos claves** (las guarda entre las que no conoce; se miró su `ConfigPlano` en el tag) y no las usa.
- **Lo que no hace:** "Estilo y armado" con mesas (A medida) sigue numerando como siempre; toma la recordada al abrir Acomodar. En
  la web, si no hay base en el equipo, no recuerda nada y queda como hoy.
- Tests: `test/numeracion_recordada_test.dart` (27: lo que se anota, la más nueva gana, Acomodar, al guardar, y **dos PCs** que se
  pasan los planos: una elige y la otra lo ve al bajar; cambiar de nuevo; la PC atrasada que no le gana a la más nueva) y cinco
  casos nuevos en `test/plano_evento_screen_test.dart`, con la pantalla entera.
- **Con el mouse**, en `tool/plano_prueba.dart` compilada para el navegador (suma el botón OTRA, que pasa a otra fiesta nueva):
  elegir "Al fondo" y guardar; otra fiesta abre con "Al fondo" y el aviso, y al guardar queda en orden y el aviso se va; con familias
  sentadas dice "Ya hay familias con mesa: los números no cambian" y no hay nada que guardar.
- La captura: `build/muestras_6.5.1/7_otra_fiesta_viene_elegido.png`.
- **No se probó con dos PCs de verdad contra la nube:** viaja en la misma fila del plano que ya cruza hoy.

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
2. `6.5.1+68` en `pubspec.yaml` y en `installer/junior_eventos_setup.iss`. **Hecho el 11-nov.**
3. `installer\build_installer.ps1` (comprueba la firma del APK). **Hecho el 11-nov.**
4. Foto de la mora "antes de 6.5.1". Sin SQL. **Hecho el 11-nov** (642 alumnos).
5. Tag `v6.5.1`, release con el Setup y el APK, y la web. **Hecho el 11-nov.**
6. Instala la PC que sortea antes del próximo sorteo; las otras conviven con la 6.5.0.
7. Después de instalar: mirar que la escuela ya sorteada quedó igual, salvo la familia que esperaba su mesa.
