# Plan: el salón primero, las mesas después (v6.1.0)

Fecha: 16-oct-2026. Rama: `feature/v4.6-cierre-por-sesiones` (la 6.0.0 ya está instalada y publicada; esto va en la
siguiente). Maqueta aprobada por el usuario: `docs/maqueta_salon_primero_2026-10-16.html` (abrirla en el navegador;
los pasos 2 y 3 se arrastran de verdad).

Leer antes: `CLAUDE.md` (sección "El salón: plano, sorteo y entradas" y "Roles y permisos"), y en
`docs/CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26.md` las etapas 4b, 5, 9 paso 3 y "Qué pasó el 4-oct".

## 1. De dónde sale (audio del jefe, 16-oct)

El jefe entró a PLANO y "le doy y ya me saltan las mesas". Lo que pidió, en su orden:

1. **Primero el salón vacío.** Armar el espacio (pista, pasarela, barras, ingreso, dónde va cada cosa) sin que
   aparezcan las mesas. Motivo: no todas las fiestas son en Costa Surubí; nombró Buena Vista y Puerto Viejo y dijo
   que "quedan dos que no son iguales".
2. **Un botón que acomode las mesas** de los alumnos cargados en los espacios que quedaron libres, según cómo él
   armó el salón.
3. **Después el sorteo**, como hoy. Antes del sorteo el plano no marca quién es quién (ya es así).
4. **"Poné que deshaga todo por las dudas, para probar"**: poder vaciar el salón y empezar de nuevo.

En la revisión de la maqueta el usuario sumó:

5. **Manijas sobre el dibujo** para agrandar o achicar escenario, pasarela, pista y demás (hoy son cuatro flechitas
   en el panel), y moverlos arrastrando.
6. **El playón también se personaliza**: no todas las fiestas son en el predio. Con las mismas ocho manijas que un
   sector (lados y esquinas), moverlo entero arrastrando, atajos Rectángulo / Trapecio / Costa Surubí y los
   casilleros Frente / Fondo / Profundidad. **Sin tope de hasta dónde se mueve**: la hoja crece sola.
7. **Las mesas se siguen pudiendo acomodar a mano** una por una, por si lo automático no gusta.

Idea sin decidir (preguntarle cuando esté lo demás): guardar el espacio armado con nombre de predio ("Buena Vista")
para elegirlo en Estilo y armado la próxima vez. No programar sin su OK.

## 2. Lo que ya existe y se reusa

- `ArmadoSalon` guarda el borde del hormigón por esquinas (`ContornoPlano`, clave `borde`) y los sectores
  (`SectorPlano`, con `TipoSector.escenario/pasarela/ingreso/barra/pista/otro`). Es JSON en `armado_json`:
  **nada de esto toca la base local ni la nube.**
- `EditarArmado` (cuentas puras): `mover`, `agregar`, `sacar`, `moverSector`, `tamanoSector`, `agregarSector`,
  `sacarSector`, `pisadas`, `separar`, `paraGuardar`. `SesionAcomodo` lleva la sesión con Deshacer; nada se guarda
  hasta GUARDAR EL SALÓN. Las mesas ya se arrastran a mano (pedido 7: **ya está**).
- `ArmarAMedida.armar(OpcionesAMedida)`: filas desde el escenario, simétricas, con pasarela y despejes. Hoy solo
  conoce escenario y pasarela; `conPlayon` redibuja el borde y **ata el escenario al frente del playón**.
- `MedirSalon.revisar`: apretadas y fuera del hormigón. `PlanoDeLaFiesta.mesasQueNecesita`: cuántas mesas pide la
  fiesta (sin mirar lo pagado).
- Pantalla: `PlanoEventoScreen` (lee, guarda `planos_evento`, `_cambiarConfig` relee la nube antes de escribir) y
  `PlanoEventoCuerpo` (pestañas Mesas / Acomodar / Medidas / Colores y textos; `_modo`). Panel de Acomodar en
  `widgets/personalizar/panel_acomodar.dart`; el dibujo en `dibujo/pintor_plano.dart` y `pintor_acomodo.dart`;
  los eventos crudos en `VistaPlano` (`onApretar`, `onArrastrar`, `onSoltar`).
- `elegir_plano_dialog.dart`: los tres pasos. La primera vez se abre solo con "A medida del playón" y las mesas de
  la fiesta ya elegidas (eso es lo que "salta").
- "Volver al armado original" existe, solo sin familias con mesa.

## 3. Lo que se agrega

### 3a. Salón vacío (Estilo y armado)

- Nueva tarjeta **"Salón vacío"**, primera, **elegida por defecto la primera vez**. Arma el playón de Costa Surubí
  (`PlayonReal.costaSurubi` o las medidas guardadas en `config.medidas`) con el escenario y nada más. Clave del
  armado: `vacio@1`.
- `ArmarAMedida.vacio(playon)` → `ArmadoSalon` con una hoja, borde, escenario, sin mesas, `lugarOriginalM` y
  `pasarelaOriginalM` como hoy (para "volver al original").
- Las otras tarjetas quedan (A medida y las cuatro del Canva).
- El texto de la tarjeta dice que las mesas se ponen después desde Acomodar. Si el predio no es Costa Surubí, el
  espacio se cambia en Acomodar.
- `aplicar_eleccion.dart`: un salón vacío se aplica como cualquier armado; sigue sin cambiar el armado si ya hay
  familias sentadas.

### 3b. Manijas sobre el dibujo (sectores y playón)

- `pintor_acomodo.dart`: el elegido (sector o playón) dibuja **ocho manijas**: cuatro lados y cuatro esquinas, en
  el color de selección, con la medida del lado escrita al lado mientras se arrastra (reusar el estilo de la regla).
- `VistaPlano`: al apretar, decidir qué hay debajo en este orden: manija → mesa → sector → playón → nada. Una manija
  tiene prioridad aunque esté sobre una mesa. Mantener los 6 px de "un clic no mueve".
- `EditarArmado`:
  - `tamanoSector` ya existe; sumar `estirarSector(indice, lado, dM)` que mueve **un solo lado** (n/s/e/w) y las
    esquinas como dos lados a la vez. Mínimo 0,5 m, pasos de 0,5 m **contando desde donde estaba** (como `mover`).
  - **Playón:** `moverPlayon(dxM, dyM)` (las cuatro esquinas), `estirarPlayon(lado, dM)` (el lado entero),
    `moverEsquina(esquina, dxM, dyM)`. Trabaja sobre `HojaPlano.contorno`. Un lado nunca mide menos de 0,5 m.
  - **La hoja crece y no achica mientras se arrastra** (ya es así: `_conCajas`). Sin tope de hasta dónde se mueve.
  - El **escenario deja de atarse al frente del playón**: `conPlayon` no lo redibuja más; es un sector como los
    demás (se mueve, se agranda). Al elegir "Salón vacío" o "A medida" se crea centrado en el frente, como hoy.
- `panel_acomodar.dart`: con el playón elegido muestra Frente / Fondo / Profundidad (casilleros), los atajos
  **Rectángulo / Trapecio / Costa Surubí**, y la lista "EL ESPACIO" con el playón primero y después los sectores.
  Con un sector elegido, Ancho / Fondo (en vez de las cuatro flechitas; dejarlas solo si el usuario las pide).
- `MedirSalon.fueraDelHormigon` y `PlanoDeLaFiesta.avisos` siguen avisando con el borde nuevo.
- La pestaña **Medidas** sigue existiendo: es la misma información escrita con cinta. Lo que se guarda ahí y lo que
  se arrastra en Acomodar tienen que dar el mismo borde (`ArmarAMedida.playonDe` lee las esquinas; `conPlayon`
  las escribe). Si el borde dejó de ser un trapecio simétrico, Medidas lo dice ("el playón se dibujó a mano") y
  muestra frente, fondo y profundidad aproximados sin reescribirlo salvo que se toque un casillero.

### 3c. ACOMODAR LAS MESAS

- Botón en la pestaña Acomodar, **solo en modo jefe** y **solo sin familias con mesa** (si hay, gris con el motivo,
  igual que "Volver al armado original"). Dice la cantidad: "ACOMODAR LAS MESAS (132)".
- `ArmarAMedida.armar` recibe **obstáculos**: los sectores de la hoja que no son escenario ni pasarela. Una mesa no
  se pone si su círculo (radio + 0,5 m) pisa un sector; el escenario lleva 2,5 m de despeje como hoy; la pasarela
  sigue con sus 2,5 m a cada lado. Las filas van desde el escenario, a `lugarM` (la distancia guardada), **dentro
  del borde real del hormigón** (interpolando los lados izquierdo y derecho a cada profundidad: el playón ya no es
  necesariamente un trapecio simétrico) con 1,2 m contra el borde.
- Numeración: la serpentina del jefe, izquierda primero y luego derecha, como hoy. **Se reasigna cada vez** que se
  toca el botón (no hay familias; el número de una mesa que se sacó y se guardó no se vuelve a dar sigue valiendo
  para lo que haya quedado guardado: `ArmadoSalon.ultimoNumero`).
- Pasa por `SesionAcomodo` como un paso más: se ve "ASÍ QUEDARÍA · SIN GUARDAR", se deshace, y se guarda con
  GUARDAR EL SALÓN por `paraGuardar` (relee la nube, `enUsoVisto`).
- Si no entran todas: titular "Faltan N mesas" y aviso "agrandá el playón, achicá un sector o juntá más".
- Después de acomodar, las mesas se corren a mano como siempre. **Mover un sector o el playón no reacomoda solo**
  (en la maqueta sí, por demostración): el jefe toca ACOMODAR OTRA VEZ, y el aviso dice que lo corrido a mano se
  pierde (queda en la pila de Deshacer).

### 3d. VACIAR EL SALÓN

- Botón en Acomodar, modo jefe, **solo sin sorteo vigente** (si alguna familia tiene mesa: gris, "deshacé el
  sorteo primero"). Saca todas las mesas, los bloques, las fijadas y las libres; **deja los sectores, el borde y
  las medidas**. Es un paso de la sesión (se deshace) y se guarda por `paraGuardar`.
- `CambiosDeMesa`/config: al vaciar, `config.fijadas`, `config.libres` y los bloques quedan vacíos. Los colores y
  textos quedan.
- `mesas_movimientos` no se toca (no hay familias). `sorteos_mesas` tampoco.

### 3e. Lo que no cambia

- Base local y nube: ninguna columna, ninguna tabla. Es JSON de `armado_json` y `config`.
- `SorteoMesasMotor` y `SorteoConPlano`. `CasillerosPlano` sigue leyendo cortes y pasto.
- La lista de la puerta: no se toca ninguna familia, así que `trasElSalon` no se llama desde lo nuevo. Si un
  guardado nuevo toca mesas de familias, el test `puerta_sigue_al_salon_test` lo va a pedir.
- Los PDF (`plano_papel.dart`, `plano_pdf.dart`) dibujan el borde que haya: probar un rectángulo y un playón
  movido en `tool/plano_muestra_test.dart`.

## 4. Reglas que hay que respetar

- **Todo guardado nuevo del salón lleva la doble llave de modo jefe** (`_frenaSinModoJefe()` y el botón apagado con
  `kSoloEnModoJefe`). `test/solo_modo_jefe_test.dart` lo revisa.
- En la pantalla del plano **no se usa SnackBar**: `AvisoDelPlano`.
- Las cuentas van en funciones puras con test; la pantalla solo las llama.
- Un arrastre entero es un paso de Deshacer.
- No comparar armados enteros con `firma` en un test: mesa por mesa.
- `flutter analyze` y los tests se corren en esta PC (el contenedor remoto no tiene Flutter).

## 5. Orden de etapas (cada una cierra sola, con commit)

1. **Cuentas del playón y los sectores** (`editar_armado.dart`, `armar_a_medida.dart`): `vacio`, `estirarSector`,
   `moverPlayon`, `estirarPlayon`, `moverEsquina`, el escenario desatado, `armar` con obstáculos y borde real.
   Tests: `editar_armado_test.dart` (nuevos casos), `armar_a_medida_test.dart` (obstáculos: pista a la izquierda,
   al medio, pegada al escenario; playón rectángulo; borde asimétrico; no entran → cuántas faltan).
2. **Salón vacío** en Estilo y armado + `aplicar_eleccion`. Test: `elegir_plano_dialog_test` y
   `aplicar_eleccion_test`.
3. **Manijas en el dibujo** (`pintor_acomodo`, `VistaPlano`, `PlanoEventoCuerpo`, `panel_acomodar`). Test de
   pantalla con `plano_evento_cuerpo_test` (apretar una manija y arrastrar cambia la medida de a 0,5 m; apretar sin
   mover no cambia nada).
4. **ACOMODAR LAS MESAS** y **VACIAR EL SALÓN** en `SesionAcomodo`, el panel y la pantalla. Tests: sesión
   (deshacer, bloqueos con familias), y en `sorteo_con_plano_test` "acomodar, sortear por división, deshacer,
   vaciar, acomodar otra vez" sobre un playón rectángulo con pista.
5. **Muestras** con `tool/plano_pantalla_muestra_test.dart`: `Salon_vacio.png`, `Acomodar_playon_manijas.png`,
   `Acomodar_sector_manijas.png`, `Acomodar_mesas_puestas.png`, `Acomodar_faltan.png`, `Salon_vaciado.png`, y un
   PDF con playón rectángulo. Mandárselas al usuario antes de la etapa 6.
6. Versión 6.1.0 (`pubspec.yaml` + `installer/junior_eventos_setup.iss`), CONTEXTO nuevo
   (`docs/CONTEXTO_v6.1.0_<fecha>.md`), CLAUDE.md (dos párrafos: el salón vacío y las manijas; el escenario ya no se
   ata al frente), instalador.

## 6. Preguntas para el usuario cuando lleguen

- Predios guardados con nombre (sección 1, idea): ¿sí o no?
- Las cuatro flechitas del panel: ¿se sacan al poner las manijas, o quedan las dos cosas?
- Si el jefe mueve un sector después de acomodar: ¿reacomodar solo (como en la maqueta) o solo con el botón (lo que
  dice este plan, 3c)? Este plan elige el botón para no perderle una mesa corrida a mano sin avisar.

Lo que recomiendo, para decírselo junto con las preguntas: los predios con nombre, después (cuando haya un segundo
predio medido); las cuatro flechitas, sacarlas (quedan las manijas y los casilleros); y mover un sector después de
acomodar, solo con el botón.

## 7. Lo que sumó la revisión (16-oct, leyendo el código)

Lo que el plan dice que existe, existe con esos nombres: el plan se puede seguir tal cual. Encima, cinco cosas:

- **Convivir con la 6.0.0.** Una PC con la 6.0.0 tiene que poder abrir un salón armado en la 6.1.0 sin romperlo.
  - **Regla: ninguna clave nueva en el JSON del armado**, porque la 6.0.0 lo reescribe entero al guardar y la
    perdería.
  - En la 6.0.0, "Volver al armado original" no conoce la clave `vacio@1`, y Medidas vuelve a atar el escenario al
    frente. Por eso el plano se toca solo desde una PC con la 6.1.0, y como es del jefe, se instala primero en la
    suya.
  - Antes de cambiar nada, un test con el código de hoy (que es el de la 6.0.0) que lee un salón como lo va a
    guardar la 6.1.0 y lo vuelve a escribir sin perder nada.
- **SORTEO con el salón vacío:** con 0 mesas no sortea, y lo dice con `AvisoDelPlano` ("Primero acomodá las
  mesas"), no con un error.
- **El salón vacío trae el sector Ingreso** al fondo, al medio, como en la maqueta: así el tótem dibuja el camino a
  la mesa sin pasos extra.
- **Una PC atrasada no pisa el salón:** ACOMODAR y VACIAR guardan por `paraGuardar`, que relee la nube. Lleva un test
  de dos PCs como los de la 9c.
- **Lo que ya está guardado no se toca:** quedan tres planos de práctica del 16-oct "A medida del playón" (la Normal
  138 mesas, Gregoria Morales 41, Puerto Viejo 31). El salón vacío viene elegido solo en una fiesta sin plano. Para
  arrancar uno de cero, VACIAR EL SALÓN: nadie tiene mesa, porque el sorteo de práctica de Puerto Viejo (9:28) se
  deshizo a las 9:34.

**18-oct: la 6.1.0 lleva todo junto** (lo decidió el usuario): la mora de las bajas temporales (fase 1, hecha) y
este salón. La fase 2 de la mora no va: eligió quedarse con la mora en fila (ver
[mora-por-cuota](pendientes/mora-por-cuota.md)).

## 8. Lo que decidió el usuario el 18-oct

- **Las cuatro flechitas del panel se sacan.** Quedan las manijas sobre el dibujo y los casilleros Ancho y Fondo.
- **Mover un sector después de acomodar no reacomoda solo:** se toca ACOMODAR OTRA VEZ.
- **Los predios con nombre van en la 6.1.0** ("Buena Vista", "Costa Surubí"): guardar el espacio vacío para elegirlo
  de punto de partida en otra fiesta. Cada fiesta sigue con su propio salón. **Es una etapa nueva**, con su maqueta
  antes de programar: dónde se guardan (una tabla nueva, nada en `contratos_alumnos` ni claves nuevas en el JSON del
  armado), cómo se elige en Estilo y armado, y qué pasa si se cambia un predio que ya usó una fiesta (la fiesta no
  cambia: se copia).
- **"Volver al armado original" también en el salón vacío**, aparte de VACIAR EL SALÓN. Preguntó "por si uno quiere
  volver al inicio":
  - **VACIAR EL SALÓN** saca las mesas y deja el espacio como el jefe lo armó;
  - **VOLVER AL ARMADO ORIGINAL** vuelve al salón vacío como salió: el playón, el escenario al frente y el Ingreso.
    Se van las mesas y los sectores agregados.
- Preguntó si cada institución guarda su salón y se puede volver a abrir, cambiar y guardar: **sí, ya es así desde la
  6.0.0** (una fila de `planos_evento` por fiesta).

## 9. La etapa 1, hecha el 18-oct (las cuentas, sin pantalla)

- **`ArmarAMedida.vacio(playon)`** (clave `vacio@1`): el borde, el escenario centrado al frente y el Ingreso de 4 × 2
  m al fondo, al medio, a medio metro del fondo. Sin mesas.
- **`ArmarAMedida.acomodar(armado, cantidad:)`**, el motor del botón ACOMODAR LAS MESAS.
  - Dentro del borde de cada hoja, midiendo los costados a la altura de cada fila, y sin pisar ningún sector salvo la
    pasarela: el círculo de la mesa más medio metro (`despejeSectorM`).
  - Si el escenario no está arriba, hay filas de los dos lados.
  - **Sobre el mismo playón da exactamente lo mismo que `armar`**, mesa por mesa: el test lo compara en ocho casos.
- **Corrección a este plan:** los despejes son los de hoy, no los de la sección 3c: medio metro delante del escenario y
  contra el borde, y 2,5 m a cada lado de la pasarela. Si fueran otros, el salón acomodado no daría igual que el armado
  a medida.
- **Las manijas** (`Manija`, en `editar_armado.dart`):
  - `estirarSector` mueve un lado o una esquina, de a medio metro desde donde estaba, con un mínimo de medio metro;
  - `moverPlayon` y `estirarPlayon` hacen lo mismo con el borde de cuatro puntos. Una esquina mueve solo ese punto,
    y eso es "moverEsquina".
  - La hoja crece sola con el borde, sin tope.
- **El escenario desatado:** `conPlayon` (la pestaña Medidas) ya no le cambia el tamaño al escenario.
- `playonDe`, `lugarDe` y `conPlayon` sirven también para el salón vacío. Su original es el salón vacío, y por eso
  ahí no frena el aviso de "entran menos mesas".
- **Convivencia con la 6.0.0:** `test/salon_convivencia_test.dart`, escrito con el modelo de la 6.0.0, lee y
  reescribe un salón vacío, uno con el escenario corrido y el playón torcido, y uno acomodado, sin perder nada. En
  la 6.0.0, un salón vacío no ofrece "Volver al armado original" y la pestaña Medidas no le redibuja el borde. Por
  eso el plano se toca desde una PC con la 6.1.0.
- `test/salon_primero_cuentas_test.dart` (33 tests) y 13 roturas a propósito, todas vistas.

## 10. La etapa 2, hecha el 18-oct (la tarjeta "Salón vacío")

- **Estilo y armado** (`elegir_plano_dialog.dart`) suma la tarjeta "Salón vacío", primera de la fila. **Viene elegida
  la primera vez** (fiesta sin plano): al tocar LISTO ya no saltan las mesas. Con plano sigue "Como está ahora", y
  desde el aviso de Medidas, "A medida".
  - No dice si entra la fiesta: su pastilla es "Mesas después". Debajo, con qué playón arranca y que el espacio se
    cambia en Acomodar.
  - **Con familias ya sentadas y sin plano** (un sorteo hecho sin plano) queda apagada, con el motivo, y viene "A
    medida": esas familias se quedarían sin su mesa. Con plano, el armado entero ya lo traba `armadoTrabado`.
  - Con seis tarjetas, la sexta quedaba sola en un segundo renglón: ahora se reparten parejas
    (`anchoTarjetaArmado`): seis de a tres, siete de a cuatro y tres.
- `aplicar_eleccion` no cambió: el salón vacío se guarda como cualquier armado (tests nuevos).
- **La pantalla del plano** dice "Sin mesas todavía" (`SemaforoPlano.sinMesas`, en gris azulado) y el aviso "El salón
  está vacío…", que no es grave.
- **SORTEO con el salón vacío no sortea** (`LecturaPlano.problemaParaSortear`): lo dice con la ventana de siempre de
  la fiesta, antes de abrir el diálogo y otra vez con el plano recién leído. Corrección a la sección 7: decía
  `AvisoDelPlano`, pero SORTEO está en la barra de la fiesta. Deshacer no lo mira. Un test lee
  `detalle_evento_masivo_screen.dart` y exige las dos llamadas.
- **Lo que no vio la etapa 1 (corrección a la sección 9):** hasta acá, `PlanoEvento.armadoONull` daba por **roto** a
  todo armado sin mesas, así que un salón vacío guardado no se podía volver a abrir. Ahora lo roto es un armado sin
  hojas. **En la 6.0.0 un salón vacío sigue leyéndose como roto**: no sortea, el tótem va sin plano y PLANO dice "El
  armado de esta fiesta no se puede leer" y ofrece elegirlo de nuevo (si el jefe toca LISTO ahí, lo reemplaza por
  "A medida"). No pierde plata ni familias, pero confirma la regla: **el plano se toca desde una PC con la 6.1.0**.
  `salon_convivencia_test` probaba el modelo del armado, no esa regla de `PlanoEvento`; un salón ya acomodado (con
  mesas) la 6.0.0 lo lee bien.
- **Comprobado:** 2.555 tests, `flutter analyze` en 312 (los de siempre), 6 roturas a propósito, todas vistas, y las
  muestras `Pasos_plano.png`, `Pasos_plano_trabado.png` y `Pantalla_plano_vacio.png`
  (`build/muestras_6.1.0/salon_vacio/`).

## 11. La etapa 3, hecha el 19-oct (las manijas)

El plan corto lo aprobó el usuario el 19-oct, con dos cambios a la maqueta que se le explicaron antes:
- **El playón entero se mueve con una manija en el medio**, no arrastrándolo desde adentro: con el plano acercado,
  arrastrar el piso mueve la vista, y eso se perdía.
- **Las medidas con cinta siguen en la pestaña Medidas** (frente, fondo, costado y "Volver a las de fábrica"): sin los
  casilleros ni los atajos Rectángulo / Trapecio / Costa Surubí en Acomodar, que hubieran sido dos lugares para lo
  mismo.

Lo hecho:
- **Las manijas sin pantalla** (`services/manijas.dart`, `ManijasPlano`): dónde va cada una de un sector o del playón,
  la del medio, y cuál hay bajo el dedo, con 9 px de tolerancia en la pantalla.
- **`SesionAcomodo`**: `estirarSector`, `estirarPlayon` y `moverPlayon`, contando desde como estaba al apretar. Un
  arrastre es un paso de Deshacer.
- **La pantalla** (`PlanoEventoCuerpo`):
  - al apretar busca primero las manijas de lo elegido (pueden quedar sobre una mesa), después una mesa, un sector
    y, sobre el piso vacío, **elige el playón sin agarrarlo**;
  - **mientras se arrastra, el dibujo se queda con la caja de la hoja que tenía al apretar** (`_conCajaQuieta`).
    Antes la hoja crecía en cada paso, el dibujo se achicaba y lo agarrado corría más rápido que el mouse: el playón
    estirado 2 m quedaba en 3,5. Lo vio un test. Arregla también a las mesas y los sectores llevados al borde.
- **El dibujo** (`PintorAcomodo`): las ocho manijas, la del medio del playón (un círculo con una cruz), el borde del
  playón elegido y lo que mide el sector debajo de él, del mismo tamaño en pantalla con cualquier zoom.
- **El panel**: sin las cuatro flechitas; **Ancho** y **Fondo** del sector (se aplican con Enter o al salir; lo que
  no es una medida vuelve a lo que estaba), y la lista **"El espacio"**, con el playón y cada sector.
- **Guardar el salón vacío:** "El salón quedó sin mesas" frena solo si el salón guardado tenía mesas
  (`EditarArmado.sinMesasDeMas`). VACIAR, en la etapa 4, lo vuelve a mirar.
- **Las medidas siguen al playón** (`EditarArmado.conMedidasDelPlayon`, en `paraGuardar`): al guardar un playón
  cambiado con las manijas, `config.medidas.playon` toma lo dibujado (aproximado si lo era); un lado de menos de 5 m
  no las cambia, porque al leerlas volverían a las de fábrica. Moverlo entero no las cambia.
- **Medidas avisa el borde a mano** (`ArmarAMedida.esParejo`): si quedó torcido, lo que se escriba lo vuelve a dibujar
  parejo. Correr un costado entero deja el trapecio parejo.
- **Un arreglo de la etapa 1:** `estirarSector` recalculaba el ancho restando dos números aunque no se hubiera movido
  y cambiaba el último decimal: apretar y soltar dejaba el salón "cambiado". Un lado quieto queda tal cual.
- Sin tocar la base ni la nube: es el mismo borde y los mismos sectores, sin claves nuevas.
- **Comprobado:**
  - 2.582 tests (`test/salon_primero_manijas_test.dart` nuevo, y la pantalla entera en `plano_evento_cuerpo_test`);
  - `flutter analyze` en 312, los de siempre;
  - 8 roturas a propósito, todas vistas;
  - las muestras `Acomodar_sector_manijas.png` y `Acomodar_playon_manijas.png` (`build/muestras_6.1.0/manijas/`),
    mandadas al usuario.

## 12. La etapa 4, hecha el 19-oct (ACOMODAR LAS MESAS y VACIAR EL SALÓN)

El plan corto lo aprobó el usuario el 19-oct con las tres decisiones recomendadas:
1. **Las mesas fijadas y las libres van por número**: después de ACOMODAR o VACIAR, al guardar se quitan (también los
   bloques). Se avisa antes, en "Antes de guardar", con los nombres, y con Deshacer no se pierde nada. La otra opción
   era que los botones no anduvieran hasta sacarlas a mano.
2. **"El salón quedó sin mesas" ya no frena nada**: VACIAR es justamente eso. Lo que no se hace sin mesas es sortear.
3. **La distancia entre mesas es la de Medidas.**

Lo hecho:
- **`SesionAcomodo`**: `acomodar(cantidad, lugarM:)` (con `ArmarAMedida.acomodar` de la etapa 1) y `vaciar()`, cada
  uno un paso de Deshacer.
  - `rehecho` dice si lo que se ve salió de uno de los dos, aunque después se corra algo a mano. Viaja con cada paso de
    Deshacer (`_pilaRehecho`), y DESCARTAR lo vuelve a false.
  - Apagados con el motivo (`motivoSinAcomodar`, `motivoSinVaciar`): con familias con mesa ("deshacé el sorteo
    primero"), en un armado del Canva (sin el borde del playón), sin alumnos, o ya vacío.
  - Rehecho, una fijada no frena "Volver al armado original": al guardar se quita.
- **Guardar** (`paraGuardar(rehecho:)`): quita las fijadas, las libres y los bloques; una fijada no frena que se saque
  su mesa, una familia sí. Una PC atrasada sigue sin poder pisar a la otra (la nube se relee antes). `onGuardarArmado`
  lleva `rehecho`, y el aviso del pie dice si se fueron fijadas o libres.
- **El panel**: "ACOMODAR LAS MESAS (132)" (u "OTRA VEZ" si ya hay mesas) y VACIAR EL SALÓN en un renglón, con el
  motivo debajo si están apagados. Al acomodar dice cuántas entraron o cuántas faltan ("agrandá el playón, achicá un
  sector o juntá más").
- **El panel se arma entero** (`SingleChildScrollView`, no `ListView`): con la sección nueva, lo de más abajo no se
  dibujaba hasta bajar, y los tests no lo encontraban.

- **Comprobado:**
  - 2.603 tests (`test/salon_primero_acomodar_test.dart` nuevo: la sesión, lo que se guarda, la PC atrasada, y el
    recorrido "acomodar, sortear por división, deshacer, vaciar y acomodar otra vez" sobre un playón con pista;
    y la pantalla entera en `plano_evento_cuerpo_test`);
  - `flutter analyze` en 312, los de siempre;
  - 11 roturas a propósito, todas vistas;
  - las muestras `Acomodar_mesas_puestas.png`, `Acomodar_faltan.png` y `Salon_vaciado.png`
    (`build/muestras_6.1.0/acomodar/`), mandadas al usuario.

## 13. "Lejos" en el salón de verdad, hecho el 19-oct

El usuario pidió, mientras se armaba la maqueta de los predios: "cuando marquen que una mesa quede lejos o cerca de
una, que se cumpla". Se midió y aprobó arreglarlo antes de los predios.

- **Cómo estaba:** "juntas" ya se medía en el salón dibujado (`tramosPegados`). "Lejos" (la extra que no toque a la
  principal, en el diálogo del sorteo) se medía **por número**: el motor ve casilleros en fila y para él lejos es "no
  seguidas". En el salón, dos mesas no seguidas pueden tocarse (una detrás de la otra; la 1 y la 132 a los dos lados
  del medio sin pasarela).
- **Medido sin el arreglo**, 20 familias con "1 lejos" en 100 sorteos por salón:
  - sorteo entero: 0 de 2.000;
  - **por división: 163 de 2.000 en el salón acomodado, 157 en A medida y 84 en el Canva Normal 2A + 2B** (entre 4 %
    y 8 %). Esto está así en la 6.0.0 instalada.
- **Ahora** (`sorteo_con_plano.dart`):
  - `_sortearEn` vuelve a sortear el tramo si una mesa lejos toca a su familia (`lejosEnElSalon`, con
    `ArmadoSalon.pegadas`, la misma medida que juntas: hasta 1,5 veces la distancia entre mesas), hasta 200 veces;
  - `validar` lo revisa antes de guardar;
  - si en ese salón no hay manera, `preparar` dice que no entra, con el motivo, y no se sortea.
  - El motor no cambió. El sorteo sin plano tampoco: ahí no hay salón dibujado.
- **Comprobado:** con el arreglo, 0 de 2.000 en los seis casos; `test/sorteo_lejos_en_el_salon_test.dart` (60 sorteos
  por salón y modo, el caso en cadena, el salón donde no se puede y la revisión final); 2.617 tests; 4 roturas a
  propósito vistas.

**Sigue:** los **predios con nombre** (opción A y las tres decisiones recomendadas, aprobadas el 19-oct) y la etapa 5
(las muestras que faltan, con un PDF de playón rectangular). Después, la versión.
