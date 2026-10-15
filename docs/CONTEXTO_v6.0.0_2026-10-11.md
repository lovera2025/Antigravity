# v6.0.0 — El plano del salón, el sorteo por división y las entradas

**Fecha:** 2026-10-11
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Con migración de base:** la local pasa de la v71 a la **v73** (cinco tablas nuevas, vacías) y la nube necesita
**dos SQL** que crean esas mismas tablas. Ninguna tabla de las que ya existen cambia. Cobros, cuentas, saldos, mora
y caja no cambian.

> **Referencia:** `CONTEXTO_v6.0.0` · `plano del salón` · `sorteo por bloques` · `retiro de entradas` · `v73`
> Anterior: [v5.0.0](CONTEXTO_v5.0.0_2026-09-24.md) (el sorteo según lo pagado).
> El detalle de cada parte, con sus decisiones y sus commits:
> [CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26](CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26.md) (plano, sorteo, personalizar,
> los que faltan, la verificación) y [CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25](CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25.md)
> (sillas, entradas, registro del sorteo).
> Plan aprobado: `C:\Users\lover\.claude\plans\en-que-nos-quedamos-radiant-gadget.md`.

**Estado: SIN PUBLICAR, y creciendo.** Las PCs siguen con la 5.0.0. El 13-oct el usuario sumó a esta versión
la puerta que sigue al sorteo, el Excel de acompañantes y música, y Recepción y el tótem nuevos: ver
**"Qué pasó el 13-oct"** y **"Qué pasó el 14-oct"**, más abajo. **Hechas las partes 1 a 4 y, del orden del 14-oct,
las secciones 1 a 6** (la 3 en tres pasos: el tótem del salón con las cuatro apariencias, Personalizar y la vista
del tótem en Recepción; la 4, el plano con la mesa y el camino en la llegada; la 5, una PC completa sin internet; la
6, el kiosco; **la 7, los celulares de la puerta por una notebook central, hecha el 15-oct y probada con el celular
del usuario**); siguen la 8 (cerrar la lista de la puerta) y la 9 (verificación y publicar). Lo de este encabezado es
cómo quedó el 11-oct.
- `pubspec.yaml` en `6.0.0+57` y el `.iss` en `6.0.0` (`8ca3598`).
- **El instalador hay que armarlo de nuevo.** El que está en `installer/dist/Setup Junior Eventos v6.0.0.exe` se
  armó antes de lo de las notas (`3b63b55`) y quedó viejo. Se arma con `installer\build_installer.ps1`, unos cinco
  minutos; la carpeta no va a git.
- No hay release `v6.0.0` en GitHub y los dos SQL de la nube no se corrieron.
- El usuario tiene para mirar las pantallas: desde el 13-oct, `build/muestras_6.0.0/recorrido/Recorrido.html`
  (33 pantallas numeradas; se abre en Edge, no en el panel de la app). **Todavía no dijo si cambiaría algo.**
- **La nota de un alumno: eligió la B**, la ventana al centro. Aplicada el 13-oct (`b463b4f`).
- El 11-oct pidió frenar ahí y seguir en otro chat. El texto para pegar está al final.

---

## Por qué

El sorteo es en noviembre y las fiestas en diciembre. El jefe armaba el salón en Canva y sorteaba con una lista;
quería hacerlo sobre el plano de verdad, por división, y llegar al sorteo sabiendo sin lugar a dudas cuántas mesas y
sillas tiene cada familia y quién las pagó. El usuario pidió **una sola versión con todo adentro**, sin
intermedias: por eso salta de la 5.0.0 a la 6.0.0 y junta más de 80 commits.

## Qué trae

| Qué | Dónde |
|---|---|
| **El plano del salón**, en tres estilos (Gala, Arquitecto, Neón), armado a medida del playón o con los armados del Canva del jefe | Barra de la fiesta → PLANO |
| **Sorteo por división** (cada una en su bloque) **o toda la escuela junta**, con el pasto solo si hace falta | Barra → SORTEO ▾ |
| **Fijar mesas y dejarlas libres** antes del sorteo; **cambiar o mudar familias** después, con motivo, deshacer e Historial | PLANO → PERSONALIZAR → Mesas |
| **Acomodar el salón a mano** (agregar, sacar, correr, separar o juntar), las **medidas** y los **colores y textos** | PLANO → PERSONALIZAR |
| **Sortear a los que faltan** con el mismo botón, sin mover a nadie; **Deshacer** solo los últimos sorteados o todo | SORTEO ▾ |
| **Plano impreso** y **planilla del sorteo** nueva, por división, con bloque, pasto y a quién avisar; se puede sacar solo de los últimos | PLANILLAS ▾ |
| **Retiro de entradas** en la oficina, con su planilla de entrega | Barra → ENTRADAS |
| **Mesas y sillas de cada uno** antes del sorteo, con lo agregado resaltado y un filtro de quién las pagó | Columna MESA y chip "Mesas y sillas" |
| **El reparto de sillas ("2P · 1A") se elige con las mesas ya sorteadas** | Columna MESA |
| **Lo que cambia el salón, solo en modo jefe**; lo demás se ve, se imprime y se entrega | Toda la fiesta |
| **La nota de un alumno dice cuándo se escribió** y cuándo se tocó por última vez | El ícono de la nota en la grilla (al pasar el mouse) y la hoja de la nota |
| **La lista de la puerta sigue al sorteo:** se arma al sortear y se vacía al deshacer (13-oct) | Sola; a mano, en MÁS |
| El recibo reimpreso cuenta bien las cuotas (lo de GAUNA) | Recibos |
| Mi Empresa: lo disponible en efectivo y en transferencia, las extracciones aparte y el bolsillo arreglado | Mi Empresa |
| La cola de subida no pierde un cambio hecho mientras subía el anterior, y lo trabado se reintenta todo junto | Sincronización |
| Editar o borrar una nota de mora condonada ahora llega a la nube y a las otras PCs | Sincronización |

**Lo que no cambia:** cómo se cobra, las cuentas, los saldos, la mora, la caja, la web, Recepción y el tótem. Una
fiesta sin plano sortea igual que en la 5.0.0. **Recepción y el tótem nuevos pasaron a esta versión el 13-oct** y
todavía no están programados (`docs/pendientes/PENDIENTES.md`).

## Dónde está

- **El plano:** `lib/features/plano/` (`modelo/`, `dibujo/`, `estilos/`, `services/`, `widgets/`), la pantalla en
  `plano_evento_screen.dart` y la barra en `lib/features/eventos/widgets/grupo_fiesta_toolbar.dart`.
- **El sorteo sobre el plano:** `services/sorteo_con_plano.dart`. El motor (`sorteo_mesas_motor.dart`) no cambió.
- **Los que faltan:** `lib/features/eventos/services/ultimos_sorteados.dart` y `registro_sorteo.dart`.
- **Papeles:** `lib/features/common/services/plano_pdf.dart`, `planilla_sorteo_pdf.dart` y `planilla_tema.dart`.
- **Entradas:** `retiro_entradas_screen.dart`. **Mesas y sillas:** `pago_para_sorteo.dart`,
  `filtro_mesas_sillas.dart` y `celda_mesa_alumno.dart`.
- **Notas:** `nota_operativa_bottom_sheet.dart`, `notas_operativas_contrato_repository.dart` y
  `models/nota_operativa_contrato.dart` (`cuando()`).
- **Base:** `local_database.dart`, versiones 72 y 73. **Nube:** `supabase/migrations/20260925120000_sillas_retiro_sorteos.sql`
  y `20260926120000_planos_y_cambios_de_mesa.sql`.
- Las reglas que quedaron para el que toque esto después están en `CLAUDE.md`, sección "El salón: plano, sorteo y
  entradas", y en "Trampas conocidas".

## Verificación

- **1.712 tests** en verde y `flutter analyze` en 313 avisos, los mismos de antes de empezar.
- **La migración, probada sobre una copia de la base real** el 11-oct (`tool/verificar_migracion_v73_test.dart`):
  las 28 tablas de siempre iguales fila por fila, las cinco nuevas vacías, la vuelta a la 5.0.0 con los mismos datos,
  y la base real idéntica antes y después (mismo SHA-256).
- **Volver atrás es reinstalar la 5.0.0 sobre la misma base**, con todos los pagos al día: un test comprueba que la
  5.0.0 abre una base ya migrada. La copia `antes_de_v73.db` que saca la app al actualizar es la última red, no el
  camino: restaurarla dejaría afuera lo cobrado después.
- Las partes difíciles (el dibujo, la base, el sorteo, los cambios de mesa, personalizar) pasaron por revisores de
  solo lectura, y cada arreglo importante se comprobó rompiéndolo a propósito.
- **No se abrió la app nueva contra la base real**: no hay entorno de prueba y la v73 la migraría. Lo primero que
  la prueba de verdad es instalarla en la PC del usuario.
- El control de mesas y sillas con los datos reales (`tool/extras_muestra_test.dart`, 11-oct): 94 sin pago de la
  base, 17 con una mesa agregada sin pagar y 4 con sillas sin pagar. Es una foto del día: se vuelve a sacar cerca
  del sorteo.

## Qué pasó el 11-oct, en orden

El detalle está en "Qué pasó el 11-oct" y "Qué pasó el 11-oct, a la tarde" del CONTEXTO de la Fase 3.

1. **La 9b**, "los que faltan" (`28112b6`).
2. **La etapa 10, la verificación final:**
   - la migración sobre una copia de la base real, sin cambiar un dato;
   - una mesa fijada lejos ya no desparrama el sorteo de toda la escuela (`f70fec2`);
   - el bloque de cada división guarda sus mesas una por una, y el pasto ya no se cuenta como propio (`2761762`);
   - el control de mesas y sillas, con los nombres de los que no pagaron la base (`8a1146e`).
3. **Los seis alumnos corregidos el 24-sep, mirados de nuevo:** están bien, en la PC y en la nube. El usuario
   confirmó que sigue de acuerdo con haber deshecho lo de ESMAY.
4. **La etapa 12, adelantada:** la versión `6.0.0+57` (`8ca3598`) y un primer instalador. El usuario preguntó si se
   podía publicar ese día, después frenó ("¿no te estoy apurando?") y eligió mirar primero las pantallas.
5. **La etapa 11, la documentación:** este archivo y `CLAUDE.md` (`efeafe5`).
6. **Las 31 notas viejas que estaban en su PC y no en la nube:** 17 que nunca habían subido y 14 que alguien había
   borrado desde otra PC. Decidió no subir ninguna y se borraron de su PC, con copia (`e266b97`).
7. **Las notas, en la app** (`3b63b55`), pedido suyo de ese momento ("está bueno ver cuándo se escribieron",
   "mejoralo igual si notás fallas", "y en diseño igual"):
   - la nota dice cuándo se escribió y cuándo se tocó por última vez;
   - editar o borrar una nota de mora condonada ahora llega a la nube (viajaba con un id que allá no existe);
   - la nota y su subida se guardan juntas;
   - quedó preparada, **sin prender**, la opción de abrir la nota como una ventana al centro
     (`kNotaComoVentana`, en `nota_operativa_bottom_sheet.dart`). Al ver las dos lado a lado, el usuario
     dijo que **elegiría la B**, la ventana al centro, y pidió dejarlo anotado;
   - quedó anotado como pendiente que el borrado de una nota no le llega a una PC que estaba cerrada
     (`docs/pendientes/notas-borradas-en-pc-cerrada.md`).

## Qué pasó el 13-oct: la 6.0.0 creció

Plan aprobado: `C:\Users\lover\.claude\plans\donde-nos-quedamos-expressive-nautilus.md`.

**Lo que decidió el usuario ese día:**
- **Todo va en la 6.0.0, también Recepción y el tótem nuevos**, y se hace por partes, "para que todo salga bien".
  El 24 y 25-sep habían quedado para diciembre; ese día aclaró que los quiere en esta versión ("capaz en ese
  momento me expresé mal"). La 6.0.0 se publica cuando cierre la última parte.
- **La lógica del sorteo y la puerta:** se sortea una institución, sube a la nube, queda en cualquier PC que se abra
  sin pisarse, y Recepción y el tótem la muestran. Si se deshace el sorteo, no muestran nada.
- **Exportar e importar un Excel por institución** para que un delegado complete acompañantes (máximo 2) y música.
  Lo que quedó cerrado, viendo maquetas:
  - se llega por **PLANILLAS ▾ → "Acompañantes y música"**, solo en modo jefe;
  - salen todos los alumnos de esa institución tal cual están en el sistema, **menos los dados de baja**;
  - **una sola columna "Acompañantes (hasta 2)"** y otra de música: dos columnas "Acompañante 1" y "Acompañante 2"
    le parecieron mal;
  - el Excel va cerrado salvo esos dos casilleros, y al importar solo se escriben esos datos;
  - si un alumno ya tenía algo cargado vale el Excel, mostrando antes lo que cambia;
  - en Editar alumno, acompañantes y música también quedan solo para el jefe;
  - quiere una prueba de exportar e importar "en dry-run" con sus datos.
- **La regla de "después de las 20 hs" ya no corre:** lo que haya que subir a la nube se le avisa y se hace en el
  momento, con su OK.
- **Un ensayo con una institución real** (sortear, verla en Recepción y en el tótem, y deshacer): con la que él
  elija. Mientras la 6.0.0 no esté, se puede hacer con la 5.0.0 instalada, que tiene el paso a mano.

**Lo que se le dijo y conviene no repetir como pregunta:** le asustó que se le preguntara con qué institución
ensayar ("¿por qué me estás preguntando? me estás asustando"). Lo que tiene poco riesgo y vuelta atrás se le
recomienda y se sigue.

### El camino

| # | Parte | Estado |
|---|---|---|
| 1 | La puerta sigue al sorteo | **hecha el 13-oct** |
| 2 | Acompañantes y música por Excel, con el simulacro | **hecha el 13-oct** |
| 3 | La nota como ventana al centro, y las dos preguntas pendientes | **hecha el 13-oct**; de las pantallas del recorrido todavía no dijo si cambia algo |
| 4 | Tótem: que no se desconecte ni salude tarde (`pendientes/totem-comunicacion.md`) | **hecha el 13-oct** |
| 5 | Tótem: cuatro apariencias (`pendientes/totem-apariencias.md`; una columna en la nube) | falta; **el 14-oct cambió el orden**, ver "Qué pasó el 14-oct" |
| 6 | Recepción más amigable (`pendientes/recepcion-redisenio.md`) | el panel del operador, **hecho el 14-oct** (sección 1 del orden nuevo); falta la vista del tótem al lado |
| 7 | Modo kiosco (`pendientes/totem-kiosco.md`) | falta |
| 8 | Tótems vinculados (`pendientes/totems-vinculados.md`) | falta |
| 8b | **Recepción y el tótem sin internet, con dos puestos** (`pendientes/modo-local-sin-internet.md`). Sumada el 13-oct a la noche; se diseña junto con la 8 | falta |
| 9 | Cerrar la lista de la puerta (`pendientes/rls-invitados.md`; funciones en la nube) | falta |
| 10 | Verificación, documentación, instalador y la web armada | falta |
| 11 | Publicar, instalar, la web, cerrar los permisos y el ensayo | falta |

**La regla que vale para todas las que faltan** (pedido del usuario, 24-sep y 13-oct): **con los datos ya bajados,
Recepción y el tótem tienen que seguir andando sin internet.** Nada nuevo puede necesitar la nube para marcar un
ingreso o saludar. Qué tiene que cuidar cada parte está en la tabla de `pendientes/modo-local-sin-internet.md`.

De la 5 a la 9 son, a ojo, entre 9 y 12 secciones de trabajo como las de la Fase 3. Cada una arranca con su plan
corto leyendo su archivo de diseño (aprobado con maquetas el 24-sep). Para preguntarle en su momento: (5) qué estilo
de plano usan Cristal y Póster en la llegada; (8) cómo se reparte la puerta; (9) qué pasa con la pantalla `/op`.

### La parte 1: la puerta sigue al sorteo

**Qué cambió para el usuario:** al sortear, restaurar o cambiar una familia de mesa, la lista de la puerta de esa
fiesta se arma o se corrige sola, y el aviso lo dice ("Recepción y el tótem ya tienen la lista: 112 persona(s)").
Al deshacer el sorteo entero, se vacía sola. Antes había que acordarse de MÁS → "Pasar a la lista de la puerta", que
en la 6.0.0 además estaba trabado, y la lista nunca se vaciaba.

- **La regla:** la fiesta está en la lista solo mientras algún alumno activo tenga mesa.
- **Quién la arma y la vacía:** solo las dos pantallas del salón (`trasElSalon`), que son del jefe y miran la nube
  antes de guardar. Una baja, un nombre corregido o un alumno nuevo corrigen solo sus filas (`trasLosAlumnos`), y
  en una PC donde nadie tiene mesa no hacen nada: así una PC atrasada no puede vaciar la puerta de una institución.
- **El aviso de Deshacer** dice que Recepción y el tótem dejan de mostrar a la institución y, si hay gente marcada
  como adentro, cuántos ingresos se pierden.
- **Un alumno eliminado** se lleva sus filas en ese momento.
- **Si la lista no se pudo poner al día**, las mesas quedan guardadas igual y el aviso dice cómo arreglarlo.
- Piezas: `lista_puerta.dart` (`planListaPuerta`, `hayMesasSorteadas`, `renglonesPlanPuerta`),
  `puerta_al_dia.dart` (`PuertaAlDia` y su provider) e `InvitadosRepository.aplicarListaPuerta`, que ahora también
  saca filas.
- Tests: 1.753 en la suite (eran 1.712). `test/puerta_sigue_al_salon_test.dart` falla si aparece un guardado de
  mesas que no deja la puerta al día. `flutter analyze` sigue en 313 avisos.
- **Sin cambios en la base ni en la nube.**

**Lo que apareció al revisar, y no se cerró ahí:** las pantallas `/lista` (la del QR) y `?buscar` marcan el ingreso
sin pedir nada a quien no tiene DNI cargado, y los alumnos no lo tienen. Con el QR a la vista, cualquiera puede
marcar a otro desde su celular. No se puede distinguir desde la web a un alumno de un invitado sin DNI de una fiesta
particular (los ids se ven iguales y `eventos` no es público), y cambiar eso para todos cambiaba las fiestas
particulares. Se cierra en las partes 5 (sin QR en masivos) y 9 (el check-in en el servidor). Quedó anotado en
`docs/pendientes/rls-invitados.md`.

### La parte 2: acompañantes y música por Excel

**Qué cambió para el usuario:** en la fiesta de cada institución, PLANILLAS ▾ → "Acompañantes y música" (solo en
modo jefe) abre una ventana con cuántos alumnos ya tienen algo cargado y dos botones.
- **EXPORTAR EXCEL** guarda `Acompañantes y música - <INSTITUCIÓN>.xlsx`: todos los alumnos de esa institución tal
  cual están en el sistema, menos los dados de baja, por división y apellido. Columnas: N°, Alumno, División,
  Acompañantes (hasta 2) y Música. La columna Código va **escondida**: el usuario preguntó para qué estaba al
  lado de la música; es lo que dice de qué alumno es cada renglón, y el delegado no tiene nada que hacer con ella.
- **El Excel va cerrado:** la hoja está protegida (clave `delegado`, para que no se saque con un clic), solo los
  casilleros amarillos se dejan escribir, y el de Acompañantes rechaza un tercero con "Máximo 2 acompañantes".
- **IMPORTAR EXCEL empieza siempre como simulacro:** la ventana "Antes de guardar" dice cuántos se cargan, cuántos
  ya estaban, cuántos vinieron vacíos y qué hay que revisar, con cómo se leyó cada uno. Recién IMPORTAR guarda,
  todos juntos o ninguno.
- **En Editar alumno, los acompañantes y la música quedaron solo para el jefe**, como el número de mesa.

**Las reglas:**
- Una institución no pisa a otra: el archivo lleva el código de su fiesta y el de cada alumno. Un Excel de otra
  institución no entra, aunque le hayan borrado el renglón que lo dice.
- Del alumno se escriben solo acompañantes y música. Un nombre o una división cambiados en el Excel se ignoran.
- Un casillero vacío nunca borra. Con 3 o más acompañantes, ese alumno no se carga y va a "Revisar".
- Se separan con barra, punto y coma, "+", "&", renglón nuevo o " y ". **La coma no separa** (los nombres del
  sistema son "APELLIDO, NOMBRE"): se toma como una persona y se avisa.
- Cada renglón se empareja por el código y además se compara el nombre: si no coinciden, no se carga.
- Si el alumno ya tenía algo distinto, se muestra antes → después y hay que tildar para poder importar.

**El arreglo que hacía falta:** Editar alumno mandaba de nuevo la lista de acompañantes con cada edición. Una PC que
todavía no bajó lo importado la habría mandado vacía al editar un teléfono, y lo habría borrado en la nube y en las
demás. Ahora acompañantes y música viajan solo si alguien los cambió a mano (`datosEdicionAlumno`), como el número
de mesa. De paso: vaciar la música a propósito ahora sí la borra, y quien tenía acompañantes "sin nombre" ya no
pierde la cuenta al editar otra cosa.

**Cómo se comprobó:**
- **Con el Excel de verdad de esta PC (16.0):** el archivo abre sin avisos; no deja escribir en el nombre ni en el
  código; sí en los dos amarillos; la regla del máximo está en todos los renglones; no se desprotege sin la clave.
  Lo que guarda Excel se vuelve a leer bien: quedó como archivo de prueba en `test/datos/`.
- **El simulacro con los datos reales** (`tool/simulacro_acompanantes_musica_test.dart`), sobre una copia de la
  base: 9 instituciones, 636 alumnos activos. Exportó cada una, la completó con datos inventados (a propósito, uno
  con tres acompañantes y uno con el nombre cambiado), la importó y comparó la base entera: solo cambiaron
  acompañantes y música de los alumnos cargados, y lo que queda para subir. Los 72 cruces (el Excel de una en
  otra) fueron rechazados. La base real quedó con el mismo SHA-256.
- 1.832 tests en la suite; `flutter analyze` sigue en 313.

**Piezas:** `planilla_delegado.dart` (`armar`, `leer`, `separarAcompanantes`, `comparar`),
`planilla_delegado_bloqueo.dart` (`bloquearPlanilla`: el paquete `excel` no sabe proteger, se escribe después con
`archive` y `xml`), `planilla_delegado_archivos.dart`, `acompanantes_musica_dialog.dart` y
`ContratosRepository.cargarAcompanantesYMusica`. **Sin cambios en la base ni en la nube.**

**Para tener en cuenta:**
- En la nube `nombres_acompanantes` es `text[]` y nunca guardó un nombre (0 de 643 el 13-oct). Va por el mismo
  camino que Editar alumno, pero la primera prueba de verdad es la primera importación ya con la 6.0.0 instalada:
  conviene que sea la institución más chica, mirando que la cola quede en 0 y que aparezca en la otra PC.
- Google Sheets puede no respetar la protección de la hoja. La garantía está al importar, que no depende de ella.
- El usuario preguntó por qué la ventana se llama "Antes de guardar"; se le explicó y se le ofreció cambiarle el
  nombre. No pidió cambiarlo.
- **Quién importa:** dijo "cuando complete el delegado me pase a mí, y yo la importe o el jefe lo importe". Es
  quien esté en modo jefe (`esRolJefeProvider`: el rol jefe de la caja, o el modo jefe con PIN), sea él o el jefe.

### La parte 3: la nota como ventana al centro

`kNotaComoVentana` quedó en `true` (la opción B, que el usuario eligió el 11-oct). La nota de un alumno se abre
como una ventana al centro en vez de la hoja de abajo; el contenido es el mismo.

**Las dos preguntas del 11-oct, hechas el 13-oct a la noche:**
- **La nota resuelta queda como está, con el tilde verde.** No se cambia nada en la grilla.
- **Las pantallas del recorrido: no entendió la pregunta** ("¿qué cambiaría? no entiendo, o mostrame"). Al
  mostrárselas apareció por qué nunca había opinado:
  - `Recorrido_6.0.0.html` pesa 4,3 MB (las 26 imágenes van adentro) y **el panel de la app no abre páginas de más
    de 512 KB**: le mostraba el texto crudo. Se le abrió en Edge (`Start-Process` sobre el archivo). Con las
    imágenes en archivos al lado tampoco sirve: el panel muestra la página como una copia suelta y no las carga;
  - leyó las pantallas numeradas **como opciones para elegir** ("la 1 me parece más prolija"). Son lugares del
    mismo programa: ahora el recorrido lo dice en la primera línea;
  - **las imágenes 2 a 5 estaban mal sacadas, no el programa:** en una ventana de 330 px de alto el menú no
    entraba debajo del botón, Flutter lo corría para arriba y tapaba PLANO y SORTEO. Se volvieron a sacar, y la
    muestra ahora falla si el menú no cuelga debajo (`tool/barra_fiesta_muestra_test.dart`). De paso, los tres
    menús se abren con 6 px de aire (`94b5002`): pegados, el borde del menú pisaba el de la barra.
- **El recorrido al día:** `build/muestras_6.0.0/recorrido/Recorrido.html`, 33 pantallas (las 26, con las cuatro
  corregidas, y siete del 13-oct: el Excel del delegado, la nota al centro y el aviso del tótem). No va a git.
  **Todavía no dijo si cambiaría algo; no frena nada.**

### La parte 4: el tótem no se desconecta ni saluda tarde

Plan aprobado: `C:\Users\lover\.claude\plans\donde-nos-quedamos-compressed-avalanche.md`. Commit `0404bad`.
**Sin cambios en la base ni en la nube, y sin pantallas ni botones nuevos.**

**Qué cambió para el usuario:**
- **Un aviso que no llega ya no desconecta el tótem.** Antes, con un solo mensaje perdido entre Recepción y la
  ventana del tótem, Recepción dejaba de avisarle por el resto de la noche y escondía sus botones; al reabrirlo
  nacía una segunda ventana. Ahora se reintenta y, si igual no llega, se mira si la ventana sigue abierta: **solo
  se la olvida si ya no existe.** Y al abrir, si hay un tótem abierto que no estaba anotado, **se lo adopta**.
- **Después de un corte de internet no saluda a nadie atrasado.** Si el corte duró más de un minuto, los que
  entraron mientras tanto aparecen en la lista, arriba, sin bienvenida. **Un corte más corto no se come ningún
  saludo.**
- **Lo que se marca sin internet no se saluda dos veces.** Es lo que apareció al leer el código y no estaba
  anotado: sin internet el ingreso llega al tótem por el puente entre ventanas y se saluda bien, pero a la nube
  sube después. Al volver, el tótem leía primero, lo sacaba de la lista y, cuando subía, lo saludaba de nuevo.
- **El público ya no ve "Reconectando..." en rojo** ni el cartel "ESTABLECIENDO CONEXIÓN — JUNIOR EVENTOS • ELITE
  SYSTEM". El estado pasó a la barra del operador, la que aparece al mover el mouse sobre el tótem: "Sin internet:
  esta PC sigue avisando al tótem" (en la web, "Sin internet: reconectando"). La pantalla abre con un fundido
  desde negro.

**Las reglas, que están en `lib/features/totem/services/bienvenidas_totem.dart`:**
- `IngresosTotem` lleva la lista de los que llegaron, la cola de bienvenidas y si se viene pudiendo leer la nube.
  **La pantalla no decide nada:** le cuenta lo que pasó (`leyo`, `noPudoLeer`, `aviso`, `baja`, `vaciar`) y dibuja.
- La primera lectura va en silencio. La primera después de un corte de `kCorteLargoTotem` (un minuto) o más,
  también. El corte se mide con el reloj de esa PC, desde el **primer** fallo: un error del stream o una relectura
  que no pudo leer (la conexión muda).
- Lo que avisó esta PC por el puente (`aviso(..., porElPuente: true)`) no lo saca una lectura de la nube que no lo
  trae: queda protegido hasta que la nube lo confirme, o hasta que la misma PC avise que se deshizo o se borró.
- El que se está saludando o espera en la cola, si una lectura vieja lo había sacado, vuelve a la lista sin otra
  bienvenida. Antes se lo salteaba, y la lectura siguiente lo saludaba de nuevo.
- **Se da por conectado cuando de verdad leyó**, no al intentarlo. Por eso la espera entre reintentos
  (`esperaDeReintento`) ahora sí crece de 2 a 32 segundos; antes volvía siempre a 2.
- Se sacó el recorte de los ya saludados al pasar de 1.000: hoy no se llega (el tótem lee hasta 1.000), pero al
  subir ese tope habría saludado de nuevo a 500.

**`KioskLauncher`** (`lib/core/services/kiosk_launcher.dart`) le habla a las ventanas por `VentanasTotem`, una
interfaz chica que los tests reemplazan. Todos los avisos se reintentan una vez; el del otro lado ignora un ingreso
repetido. **Si quedaron dos ventanas, la de más se esconde y se pausa, no se cierra:** es lo mismo que ya hace
`close()` en las PCs; cerrar una ventana secundaria desde el programa no se pudo probar sin abrir la app.

**Cómo se comprobó:**
- 43 tests nuevos (`test/bienvenidas_totem_test.dart` y `test/kiosk_launcher_test.dart`), con la noche entera de
  corrido: se corta internet, Recepción sigue marcando, vuelve a los cinco minutos con la nube atrasada, y nadie se
  saluda tarde ni dos veces. **1.877 tests** en la suite; `flutter analyze` sigue en 313.
- **Doce roturas a propósito** (el silencio del corte, la protección del puente, no olvidar la ventana, adoptarla,
  los reintentos, el tope de la espera…): todas las vio algún test.
- La imagen del aviso: `build/muestras_6.0.0/Totem_sin_internet.png` (`tool/totem_muestra_test.dart`).
- **No se probó con el tótem de verdad.** La pantalla del tótem lee de la nube sin providers delante y todavía no
  se puede montar en un test; lo que decide quedó afuera, probado. La prueba real es el ensayo: marcar ingresos,
  cortar el wifi un par de minutos, seguir marcando, volver a conectar y mirar que no salude a nadie de nuevo.

**Lo que no se tocó, a propósito:**
- **El panel del tótem que está adentro de Recepción** (`totem_panel.dart`). Lee de la base de la PC; después de
  un corte largo, cuando bajan juntos los ingresos de la otra PC, los puede saludar de corrido. Lo ve el operador,
  no el salón, y se rehace en la parte 6.
- Los botones "maximizar" y "minimizar" de Recepción, que no hacen nada: salen con la parte 6.
- Lo que se marca en **otra** PC llega al tótem solo con internet, igual que antes.
- Si el stream trae una fila que no se puede leer, devuelve la lista vacía y el tótem la muestra vacía
  (`SupabaseService.streamInvitados`). No pasa con los datos de hoy; conviene mirarlo en la parte 5.

## Qué pasó el 14-oct: Recepción y el tótem distinguen particular y masivo

Plan aprobado: `C:\Users\lover\.claude\plans\donde-nos-quedamos-gentle-hummingbird.md`.

**El objetivo, dicho por el usuario** (rechazó tres veces el plan de las apariencias hasta que quedó claro, y
aprobó la maqueta "perfectamente así"): Recepción y el tótem tienen que **distinguir un evento particular de uno
masivo**. Se dice "evento masivo", no "fiesta de alumnos": un masivo no tiene por qué ser de alumnos.
- **Particular:** como siempre, nombre, DNI y mesa; el QR en el tótem.
- **Masivo:** al elegir la institución se ven sus alumnos **menos los dados de baja, con lo cargado en ese
  momento**. Si no se sorteó, un aviso, y sin mesa, sillas ni plano. Ya sorteado: la mesa y, **debajo, las sillas
  que le tocan y cómo se repartieron en ese evento** (pedido suyo al ver la maqueta), el plano con la guía de dónde
  se sienta. Acompañantes y música solo si están cargados; la música en el tótem se prende o se apaga en
  Personalizar. Sin QR: los marca Recepción.

**Cambia lo del 13-oct** ("si se deshace el sorteo, no muestran nada"): antes del sorteo y después de deshacerlo,
Recepción muestra a los alumnos con el aviso. Lo que hace el salón con la lista de la puerta (armarla al sortear,
vaciarla al deshacer todo) sigue igual.

**El orden nuevo, una sección por chat** (lo que hace funcionar la puerta, primero):

| # | Sección | Estado |
|---|---|---|
| 1 | Recepción distingue particular y masivo (el panel del operador de la parte 6, más lo del masivo) | **hecha el 14-oct** |
| 2 | El tótem distingue particular y masivo: la ficha por el puente (mesa, sillas debajo, "acompaña a", música), sin QR en masivos, saludo sin mesa antes del sorteo, la familia saludada junta, la cola que se acorta (7 s solo, 3 s con cola), la casilla de la música | **hecha el 14-oct** |
| 3 | Las cuatro apariencias (parte 5), dibujando lo de la sección 2, y Personalizar con las cuatro tarjetas; la vista del tótem al lado de Recepción | **hecha el 14-oct**, en tres pasos: 3a (el tótem del salón), 3b (Personalizar) y 3c (Recepción) |
| 4 | El plano con la guía en la llegada | **hecha el 14-oct**, en dos pasos: 4a (la mesa en el plano) y 4b (el camino desde el ingreso) |
| 5 | Una PC completa sin internet (8b, pasos 1 y 2) | **hecha el 14-oct**, en cuatro pasos: 5a (el tótem abre con la lista), 5b (la foto guardada), 5c (entrar con la sesión vencida) y 5d ("Lista para trabajar sin internet") |
| 6 | Modo kiosco (parte 7) | **hecha el 14-oct**, en dos pasos: 6a (la ventana del escritorio) y 6b (la web) |
| 7 | Los puestos de la puerta (partes 8 y 8b, paso 3): **celulares por una notebook central**, con y sin internet | **hecha el 15-oct** (7b la central, 7c el celular, 7d Recepción e instalador, 7e probada con su celular) |
| 8 | Cerrar la lista de la puerta (parte 9) | falta |
| 9 | Verificación, instalador, la web y publicar (partes 10 y 11) | falta |

La nube: las dos columnas de `totem_config` (`estilo` y `mostrar_musica`) quedaron en un solo SQL en la sección 2
(`supabase/migrations/20261014120000_totem_config_estilo_y_musica.sql`). **Corrido el 14-oct a las 8:50, con su OK**: antes y después 643 contratos, 4.043 pagos, 26 notas, 10 invitados, 30 eventos y 1 fila de `totem_config`; las dos columnas quedaron vacías y fuera de Realtime.

### La sección 1: Recepción distingue particular y masivo

**Qué cambió para el usuario** (Inicio → RECEPCIÓN → elegir el evento):
- **El selector dice el tipo:** "… · MASIVO" o "… · PARTICULAR".
- **Masivo:**
  - la institución con sus alumnos sin las bajas ("2 dados de baja: no aparecen");
  - el aviso amarillo si no se sorteó;
  - cada alumno con su división, la mesa y debajo las sillas ("10 sillas (8 + 2 extra)", "14: 10 sillas · 15: 9
    sillas", con "reparto a confirmar" si la familia no eligió), o "Sin mesa" si el evento se sorteó y él no tiene;
  - la música con su nota, y sus acompañantes debajo, cada uno con su "Ingresar".
  - No hay "Agregar" ni "Vaciar lista": la lista sale de los alumnos. Lo cargado a mano en esa lista aparece al
    final, con "cargado a mano".
- **Particular:** nombre, DNI (con puntos) y mesa, "AGREGAR", y en "Más ⋯" Importar, Exportar y "Vaciar lista…".
- **En los dos:**
  - arriba "312 de 1.100 adentro · faltan 788" con una barra, en lugar de las tres tarjetas;
  - la búsqueda grande: por nombre en cualquier orden y sin importar acentos, mayúsculas ni la coma ("juan perez"
    encuentra a "PÉREZ, JUAN"); un número de hasta tres cifras es la mesa; uno más largo, el DNI; se pueden
    mezclar ("perez 12");
  - **Enter ingresa** si queda una sola persona sin entrar que coincida, y deja la búsqueda vacía para la
    siguiente. Si son varias dice cuántas; si la única ya entró, "ya ingresó a las 22:41";
  - filtros Todos, Faltan y Adentro, con cuántos;
  - "Adentro · 22:41" con deshacer al lado. El tacho ya no está a la vista: eliminar va por ⋮, con confirmación, y
    solo en lo cargado a mano.
- La letra del panel es Outfit, que viene con la app (anda sin internet). Sin el desenfoque de cada tarjeta, que
  con 1.100 renglones pesaba.

**Cómo se arma:**
- `recepcion/services/puerta_del_evento.dart` (`PuertaDelEvento`): sin pantalla ni base. Un masivo sale de
  `filasPuertaDesdeAlumnos` —los mismos ids fijos que arma el salón— cruzados con la lista de la puerta para saber
  quién entró. Las sillas, con `SalonMesas.repartoSillas` y `RepartoDeSillas.vigente`, lo mismo que la planilla.
  También la búsqueda (`ConsultaPuerta`, `normalizarPuerta`), los filtros y Enter (`alApretarEnter`).
- `recepcion/widgets/panel_puerta.dart` (`PanelPuerta`): solo dibuja y llama a lo de siempre.
- `alumnosDeLaPuertaProvider` y `puertaDelEventoProvider` (`recepcion_provider.dart`): los alumnos y el reparto de
  sillas de la base de la PC, que se releen cuando baja un cambio de la otra PC; con `StreamController` y
  `onCancel`.
- **`InvitadosRepository.ingresarDesdeLaPuerta`:** antes del sorteo una persona no tiene fila en la lista de la
  puerta; al ingresarla se crea, ya marcada. **Lo que sube no lleva la mesa**: si la nube ya tenía la fila (la armó
  el sorteo y esta PC no la bajó), el upsert no la pisa. La mesa de la lista la pone solo el salón.
- **Un arreglo que hacía falta para esto:** marcar y deshacer un ingreso subían con un `update` y borraban la
  entrada de la cola igual. Con una fila recién creada que todavía no estaba en la nube, el `update` no encontraba
  nada y el alta se borraba: la fila no llegaba nunca. Ahora `_subirYa` sube lo que dice la cola (el alta, si está)
  y la saca solo si sigue siendo la que se leyó (`markCompleted`).
- "Vaciar lista" contaba con las tarjetas de números, que ya no están: ahora cuenta en la base
  (`getEstadisticas`). Leído como antes, daba "la lista ya está vacía" con la lista llena.

**Cómo se comprobó:**
- `test/puerta_del_evento_test.dart` (33), `test/ingresar_desde_la_puerta_test.dart` (5, sobre una base temporal) y
  `test/panel_puerta_test.dart` (18, el panel entero con reemplazos en memoria de `test/helpers/puerta_en_memoria.dart`,
  a 360, 800 y 1366 px). **1.933 tests** en la suite (eran 1.877); `flutter analyze` en 312 (eran 313).
- **Ocho roturas a propósito**, todas vistas: la baja que no se cuenta, Enter con dos, la búsqueda con acentos, el
  filtro Faltan, el reparto elegido, subir la mesa, pisar el nombre y la mesa de una fila, no marcar una fila que
  existía. Una décima (mostrar la mesa antes del sorteo) no podía fallar: sin sorteo nadie tiene mesa. Ese resguardo
  sobraba y se sacó.
- Muestras en `build/muestras_6.0.0/recepcion/` (`tool/recepcion_muestra_test.dart`): masivo sin sortear, sorteado,
  buscar "12" con Enter, y un particular.
- **No se probó en la app** (no se corre desde el working tree, y es producción).

**Lo que no se tocó:**
- La vista del tótem al lado de Recepción (`TotemPanel` y sus botones de modo): va con la sección 3.
- La ruta `/op` (`operador_view.dart`): es de la parte de cerrar la lista.
- **No hay "Editar" en el menú ⋮:** Recepción nunca tuvo cómo editar a un invitado. En un masivo se corrige en la
  ficha del alumno.
- El tótem de esta PC, al ingresar a alguien sin fila, recibe la mesa por el puente; el panel viejo de Recepción
  (`totem_panel.dart`), que lee la fila, lo ve sin mesa hasta que el salón la pone. Se rehace en la sección 3.

### La sección 2: el tótem distingue particular y masivo

Plan aprobado: `C:\Users\lover\.claude\plans\purrfect-waddling-micali.md`, con una maqueta para tocar. **Programado
y subido; sin publicar.**

**Qué cambió para el usuario.** Se ve en el tótem (Inicio → TÓTEM → el evento) al marcar en Recepción:
- **Un masivo no muestra el QR.** La espera queda con la foto, el título y el subtítulo, un poco más grandes. Un
  particular sigue con el QR.
- **La familia se saluda junta:** el alumno en grande y "con GÓMEZ, ANA y PÉREZ, LUIS" debajo. Los que esperaban se
  juntan en una tarjeta, y el que se marca mientras está la tarjeta de su familia se suma a ella.
- **Debajo de la mesa, las sillas:** "10 sillas (8 + 2 extra)", "14: 10 sillas · 15: 9 sillas". Sin el "reparto a
  confirmar", que es para el operador.
- **El acompañante que llega solo:** su nombre y "acompaña a PÉREZ, JUAN MARTÍN".
- **La música del alumno**, con su ícono, si está cargada y la casilla está prendida.
- **Antes del sorteo, el saludo sin mesa.** Tampoco hay mesa para el alumno que quedó sin mesa. En el salón nunca se
  dice "sin mesa".
- **La cola se acorta:**
  - una tarjeta dura 7 s si nadie espera y 3 s si hay gente esperando, también la que ya estaba en pantalla;
  - el que se suma a su familia se queda al menos 3 s;
  - debajo de la tarjeta, "2 más en camino".
- **"¡Bienvenidos!"** cuando son varios, si el saludo es el de siempre. Un saludo escrito a mano no se toca.
- **Personalizar tótem, en un masivo**, tiene la casilla **"Mostrar la música de cada alumno"** (viene prendida) en
  lugar de "Texto del QR". La miniatura de arriba deja de mostrar el QR.

**Cómo se arma:**
- **La ficha del evento** (`totem/services/ficha_totem.dart`):
  - por cada persona del masivo lleva el nombre, la familia (el id del alumno), si es el alumno, la mesa, las
    sillas, la música (solo en el alumno) y a quién acompaña;
  - se arma con `PuertaDelEvento`, lo mismo que ve Recepción. Las bajas y lo cargado a mano no entran;
  - de un particular dice solo que es particular;
  - por el puente, una institución de 1.200 personas viaja en menos de 250 KB.
- **La pide el tótem y la contesta la ventana principal** (`PuenteFichaTotem`, método `ficha_totem`).
  - Es el primer mensaje que va del tótem a la ventana principal. El manejador se registra en `AuthWrapper`
    (`main.dart`) y lee la base de la PC: anda sin internet.
  - No se empuja: un mensaje mandado mientras la ventana del tótem recién nace lo contesta el manejador provisorio
    de `main.dart` y se pierde sin error.
  - Se pide al abrir, al reanudar, al cambiar de evento y cada 60 s. También cuando llega alguien que la ficha no
    tiene: en ese caso se espera la respuesta como mucho 1 s antes de saludarlo.
- **La cola y la familia** (`IngresosTotem`, en `bienvenidas_totem.dart`):
  - `siguiente` pone en pantalla al primero de la cola con los de su familia;
  - el que llega con su familia en pantalla se suma a la tarjeta;
  - `finDeBienvenida` dice cuándo se va la tarjeta. La pantalla solo reprograma el temporizador (`_programarFin`).
- **Lo que dice la tarjeta:** `ContenidoBienvenida` (`contenido_bienvenida.dart`). Si la ficha conoce a la persona,
  manda la ficha, también cuando dice que no tiene mesa: la fila puede traer la mesa de un sorteo que se deshizo.
- **La tarjeta y la portada pasaron a widgets propios**, `TarjetaBienvenida` y `PortadaTotem`. La pantalla
  (`totem_display.dart`) bajó de 2.058 a 1.788 líneas, y estas piezas se pueden montar en un test.
  - `hayQrEnElTotem` decide el QR. En la ventana del escritorio, mientras no llega la ficha no se muestra: llega en
    milisegundos, debajo del fundido de apertura. En la web, como siempre.
- **El tótem escucha el puente solo en su propia ventana.** Montado en la ventana principal (la ruta
  `/totem_display`, que hoy nadie usa) le habría sacado a esa ventana el manejador de la ficha.
- `leerAlumnosDeLaPuerta` (`recepcion_provider.dart`) es la lectura de los alumnos y los repartos que comparten
  Recepción y la ficha.

**Lo que decidí yo, y conviene decirle:**
- **La letra de la tarjeta y de la portada pasó de Oswald a Outfit**, la que viene con la app. Oswald se baja de
  internet: sin internet el tótem saludaba con la letra de repuesto, y los tests no pueden usarla. La forma, los
  colores y las animaciones son los mismos.
- **Sin foto del evento, la tarjeta muestra el logo de la empresa**, como la espera, en lugar del emoji del apretón
  de manos (que además no se ve en todas las PCs).
- **En un masivo, Personalizar esconde "Texto del QR"**: no hay QR que lo muestre.
- **La columna `estilo` va sin CHECK**, como `planos_evento.estilo`: los valores los controla la app, y una
  apariencia nueva no espera otro SQL. El diseño del 24-sep lo tenía con CHECK.

**La nube:** `supabase/migrations/20261014120000_totem_config_estilo_y_musica.sql` agrega `mostrar_musica` y
`estilo` a `totem_config`, vacías. Sin la columna, **guardar Personalizar con la 6.0.0 falla**: hay que correrlo antes
de instalar. La 5.0.0 no lo nota. `test/totem_config_test.dart` falla si `TotemConfig.toJson` manda una clave que
no está en los SQL. **Corrido el 14-oct a las 8:50, con su OK**: antes y después 643 contratos, 4.043 pagos, 26 notas, 10 invitados, 30 eventos y 1 fila de `totem_config`; las dos columnas quedaron vacías y fuera de Realtime.

**Cómo se comprobó:**
- `test/ficha_totem_test.dart` (16), `test/tarjeta_bienvenida_test.dart` (23; la tarjeta a 1080×1920, 1920×1080 y
  360×640 sin desbordes), `test/puente_ficha_test.dart` (8) y `test/totem_config_test.dart` (6).
  `test/bienvenidas_totem_test.dart` pasó de 30 a 45: la familia, los 7 s y 3 s, y una noche con cuatro familias de
  golpe (cuatro tarjetas en unos 21 s; con la regla de antes eran seis y unos 50 s).
- **2.001 tests** en la suite (eran 1.933). `flutter analyze` sigue en 312.
- **Once roturas a propósito, todas vistas:**
  - la familia que no se junta;
  - la tarjeta que no se acorta;
  - el que se suma sin sus 3 s;
  - el de la familia que va a la cola;
  - el QR en un masivo;
  - la música con la casilla apagada;
  - la mesa vieja de la fila;
  - sin "acompaña a";
  - el "a confirmar" en el tótem;
  - lo cargado a mano en la ficha;
  - una fila vieja que apaga la música.
- **Muestras** en `build/muestras_6.0.0/totem/` (`tool/totem_muestra_test.dart`, con los widgets de la app):
  - `Totem_bienvenidas.png`: la familia con cola, un acompañante solo, sin sortear y un particular;
  - `Totem_espera.png`: con y sin QR;
  - `Personalizar_musica.png`: la casilla.
- **No se probó en la app.** La prueba real es el ensayo: marcar en Recepción a un alumno y sus acompañantes, uno
  tras otro, y mirar el tótem.

**Lo que no se tocó:**
- El panel del tótem dentro de Recepción (`totem_panel.dart`): sigue con el QR, la cola de 7 s y sin ficha. Se
  rehace en la sección 3.
- La lista "YA LLEGARON": sale en la sección 3.
- El tótem por el navegador: sin ficha, con QR también en un masivo, hasta la sección 8.
- Una familia que se completa cuando su tarjeta ya se está yendo tiene una tarjeta nueva para el que llegó tarde.

### La sección 3a: el tótem del salón con las cuatro apariencias

Plan aprobado: `C:\Users\lover\.claude\plans\purrfect-waddling-micali.md` (la sección 3 arriba). El usuario vio una
maqueta con las cuatro apariencias y los fondos de verdad. Pidió **aprobar cada cambio a mano** ("que no sea modo
automático") y dio el **OK para bajar cuatro letras**. **Programado y subido; sin publicar.**

**Qué cambió para el usuario** (Inicio → TÓTEM → el evento):
- **El tótem tiene cuatro apariencias, Neón, Cristal, Póster y Gala**, con los fondos animados aprobados el 24-sep.
  Si nadie eligió, **Neón en un masivo y Cristal en un particular**. Elegirla en Personalizar es la 3b.
- **La espera es a pantalla completa:** la foto (o el logo), el título partido en dos ("PROMOCIÓN" chico, "2026"
  grande), el subtítulo y el saludo. El QR, solo en un particular.
- **Cada apariencia tiene su llegada:**
  - **Neón:** el cartel cursivo titila al prenderse, el nombre se enciende letra por letra y el círculo de la mesa
    se dibuja;
  - **Cristal:** la tarjeta de vidrio se da vuelta;
  - **Póster:** el nombre sube y la mesa entra en una franja inclinada del color del evento;
  - **Gala:** el nombre aparece letra por letra y la mesa va en un medallón que se dibuja.
  En todas: la familia, la mesa con las sillas debajo, la música, "N más en camino" y **una línea abajo que marca
  el tiempo**.
- **Sale "YA LLEGARON" del salón.** El contador también sale de la vista del público: pasó a la barra del operador
  ("34 LLEGARON").
- **Las letras de la barra y de las cuatro apariencias van dentro del programa.** Con Oswald adentro, también las
  pantallas que la usan (Recepción, Personalizar) la tienen sin internet.

**Cómo se arma:**
- **`lib/features/totem/estilos/`:**
  - `totem_estilo.dart`: la apariencia elegida o la del tipo de evento, el segundo neón, el título partido y
    `hayQrEnElTotem`;
  - `fuentes_totem.dart`: las familias `Totem*`;
  - `fondo_totem.dart`: el shader, cargado una vez, con el degradé de respaldo;
  - `escena_totem.dart` y una escena por apariencia.
- **`shaders/totem_*.frag`:** los fondos del pendiente, pasados a Flutter.
  - Cada uno usa todos sus uniformes: uno sin usar lo saca el compilador y se corren las posiciones.
  - Neón calcula el ancho de la grilla en vez de `fwidth`.
- **`ReproductorBienvenidas`** (`totem/services/`): los tiempos que estaban en la pantalla. Lo va a compartir la
  vista de Recepción en la 3c.
- **`totem_display.dart`** bajó de 1.788 a unas 900 líneas: quedan la conexión, el puente, la orientación y la barra
  del operador.
- **Salen** `TarjetaBienvenida` y `PortadaTotem` (las piezas intermedias de la sección 2). Sus tests de contenido
  quedaron en `test/contenido_bienvenida_test.dart`.
- **`TotemConfig.estilo`** se lee y se guarda. **Personalizar la conserva al guardar:** arma la config campo por
  campo, y un campo que faltara se borraba en la nube. La columna de la nube ya estaba (el SQL de la sección 2).

**Lo que apareció al mirar las muestras, y se arregló:**
- **En Gala, el "12" del medallón se leía "I2":** las cifras de Cormorant son de estilo antiguo. En pantalla se piden
  las alineadas (`FontFeature.liningFigures()`); en el PDF no se puede, por eso ahí van en Outfit.
- **En Neón, las sillas, la música y el QR caían sobre la línea brillante del horizonte.** Ahora lo que se lee va
  arriba del horizonte y el QR, sobre el piso de la grilla.
- Encontrado leyendo el código: si alguien llegaba mientras una tarjeta se iba, se cancelaba la salida y la tarjeta
  quedaba trabada. Se arregló antes de probarlo, y un test lo cubre.

**Decisiones mías:**
- En la ventana del escritorio, si nadie eligió apariencia, **la pantalla queda en negro hasta que llega la ficha**:
  sin ella no se sabe si el evento es masivo, y mostrar Cristal para cambiar enseguida a Neón se vería mal. Llega en
  milisegundos, debajo de la apertura; a los 3 s se sigue sin ella.
- En la web, si se eligió vertical u horizontal y la pantalla dice otra cosa, la escena se encuadra en el medio.

**Cómo se comprobó:**
- `test/escena_totem_test.dart` (48): las cuatro apariencias en espera y llegada, a 1080×1920, 1920×1080 y 360×640,
  sin desbordes. Cubren la familia, dos mesas, sin mesa, el acompañante solo, un nombre muy largo, cinco
  acompañantes de nombre largo (que sin achicarse no entran), el QR, sin "YA LLEGARON", el degradé de respaldo y la
  entrada y salida animadas.
- `test/fondo_totem_test.dart` (6): cada shader compila y dibuja; si no carga, el degradé.
- `test/reproductor_bienvenidas_test.dart` (9), con el reloj de los tests: los 7 s y 3 s, la salida, la familia que
  se suma, el que llega mientras se va, la espera de la ficha.
- `test/totem_config_test.dart` suma la apariencia.
- **2.061 tests** en la suite (eran 2.001); `flutter analyze` sigue en 312.
- **Once roturas a propósito, todas vistas:**
  - una apariencia que no se achica;
  - el degradé de respaldo que no se pinta;
  - la apariencia por defecto al revés;
  - una clave desconocida;
  - el QR en un masivo;
  - el título que no se parte;
  - la tarjeta que se traba al irse;
  - la cola que no se acorta;
  - no esperar la ficha;
  - sin "N más en camino";
  - la apariencia que no se guarda.

  La primera no la veía ningún test, porque todos los casos entraban; se sumó el de los cinco acompañantes.
- **`flutter build windows` y `flutter build web`, los dos bien**: los cuatro fondos compilan para las PCs y para la
  web. No se abrió la app ni se publicó nada.
- **Muestras** con los fondos de verdad, en `build/muestras_6.0.0/totem/`. Reemplazan las de la sección 2:
  - `Totem_espera_masivo.png`;
  - `Totem_llegada_familia.png`;
  - `Totem_particular.png`;
  - `Totem_horizontal.png`.
- **No se probó en la app.**

**Lo que no se tocó (siguen 3b y 3c):**
- Personalizar todavía no deja elegir la apariencia: la conserva.
- `totem_panel.dart` (Recepción y la pantalla del asesor) sigue con la cara vieja hasta la 3c.

### La sección 3b: Personalizar con las cuatro apariencias

Plan aprobado: `C:\Users\lover\.claude\plans\donde-nos-quedamos-abundant-parasol.md` (el detalle del 3b del plan de
la sección 3). Lo pidió con "donde nos quedamos?" y aprobó el plan; cada cambio lo aprobó a mano. **Programado y
subido; sin publicar.**

**Qué cambió para el usuario** (Inicio → RECEPCIÓN → el evento → paleta "Personalizar tótem"):
- **Se elige la apariencia** entre cuatro tarjetas, Neón, Cristal, Póster y Gala:
  - cada una muestra la espera con la foto, el título y el color de ese evento;
  - si nadie eligió, la del tipo viene marcada con "va esta si no elegís".
- **A la izquierda (o arriba), "Vista del tótem · Neón"**: la escena de verdad, con su fondo animado. Sigue al
  instante lo que se escribe, el color y una foto recién elegida, antes de guardarla.
- **"Ver una llegada"** muestra 7 s una llegada de ejemplo y vuelve la espera:
  - en un masivo, PÉREZ, JUAN MARTÍN con dos acompañantes, mesa 12, "10 sillas (8 + 2 extra)" y la música si está
    prendida;
  - en un particular, GONZÁLEZ, MARÍA en la mesa 4.
- **Vertical / Horizontal** debajo de la vista. Arranca como quedó el tótem del evento en esa PC; no guarda nada.
- **En la PC (más de 1.024 px), ventana al centro**; en tablet y celular, hoja a pantalla completa.
- **Un error al guardar se dice en palabras:** "No se pudo guardar. Revisá la conexión e intentá de nuevo."
  Guardar sigue necesitando internet, como siempre: se hace en la oficina, no en la puerta.
- Al guardar, el tótem cambia al instante por el puente, como antes. **Sin SQL nuevo:** la columna `estilo` ya
  estaba (14-oct).

**Cómo se arma:**
- **`totem_config_sheet.dart`, rehecho.** `showTotemConfigSheet` no cambió de forma: elige ventana u hoja con
  `CortesPantalla` (`common/utils/cortes_pantalla.dart`, 600 y 1.024 px), que va a usar también Recepción en la 3c.
  - El cuerpo es `PersonalizarTotem`, con dos acomodos.
  - Las tarjetas son `TarjetaApariencia`: una `EscenaTotem` quieta en 9:16.
  - La vista grande es la `EscenaTotem` animada.
  - "Ver una llegada" la arma `LlegadaDeEjemplo.para`, con `ContenidoBienvenida.armar`, lo mismo que el salón:
    dice el plural, la mesa, las sillas y la música como las diría el tótem.
- **`EscenaTotem.foto`:** una foto que manda sobre `cfg.imagenUrl` (la recién elegida). `DatosEscena.foto` la lleva
  resuelta; `FotoEvento` y el fondo del Póster la usan. En el salón no cambia nada: sin `foto`, la URL.
- **Las letras:** salió `GoogleFonts.oswald` (pedía la seminegrita, que no viene con la app). Van la Oswald de la app
  (`FuentesTotem.cartelera`) y Outfit.
- Si no se toca una tarjeta, se conserva lo guardado, también una clave que esta versión no conoce.
- `PersonalizarTotem.elegirFoto` reemplaza al selector de archivos en los tests, como `FondoTotem.cargar`.

**Decisiones mías, dichas en el plan:**
- **Las tarjetas quietas y la vista animada:** cinco fondos animados a la vez cargan una PC de oficina.
- **No se vuelve a "sin elegir":** se toca la tarjeta del tipo.
- **Lo que no se guardó se pierde al cerrar**, como antes.

**Cómo se comprobó:**
- `test/personalizar_totem_test.dart` (27) monta Personalizar entero, abierto desde un botón como la paleta de
  Recepción, con `test/helpers/personalizar_en_memoria.dart`. Prueba:
  - la ventana en 1366 × 768, la hoja en 390 y 800 px;
  - sin desbordes en 360 × 640, 800 × 1280 y 1366 × 768, en masivo y particular, vertical, horizontal y con la
    llegada;
  - la marcada si nadie eligió;
  - elegir y guardar, también en el celular;
  - conservar lo guardado (vacío, `poster` y una desconocida);
  - las tarjetas quietas;
  - el título, el color y la foto recién elegida en la vista y las tarjetas;
  - la llegada de ejemplo, que se va a los 7 s, sigue al cambiar de apariencia y va sin música con la casilla
    apagada;
  - el QR solo en particulares;
  - la orientación guardada;
  - el error en palabras.
- `test/escena_totem_test.dart` suma 8: en las cuatro apariencias, la foto recién elegida manda, y sin ella va la
  guardada.
- **2.096 tests** en la suite (eran 2.061); `flutter analyze` sigue en 312.
- **Diez roturas a propósito, todas vistas:**
  - la elección que no se guarda;
  - la tarjeta que no cambia la vista;
  - la ventana en el celular;
  - el error con el texto técnico;
  - la llegada que no vuelve;
  - la foto nueva que no se ve (en la hoja y en la escena);
  - el QR en un masivo;
  - las tarjetas animadas;
  - sin el rótulo.
- **Muestras**, con los fondos y las letras de verdad, en `build/muestras_6.0.0/totem/`:
  - `Personalizar_PC.png`;
  - `Personalizar_llegada.png`;
  - `Personalizar_celular.png`;
  - `Personalizar_celular_tarjetas.png`.

  Salen de `tool/totem_muestra_test.dart`.
- Sin shaders nuevos, así que no se volvió a compilar para Windows y la web. **No se probó en la app.**

**Lo que no se tocó (sigue la 3c):** `totem_panel.dart`, la vista vieja de Recepción y del asesor, con sus botones
flotantes. La paleta de Recepción abre el Personalizar nuevo.

### La sección 3c: Recepción con la vista del tótem al lado

Plan aprobado: `C:\Users\lover\.claude\plans\donde-nos-quedamos-abundant-parasol.md` (la 3c arriba). Dijo "seguí
acá" al terminar el 3b. Antes de aprobar preguntó si los SQL ya se habían corrido: se miró la nube en ese momento
(solo lectura) y se le contestó que el de `totem_config` sí (14-oct) y los dos de la Fase 2 y la Fase 3 no, y que van
antes de instalar. Cada cambio lo aprobó a mano. **Programado y subido; sin publicar. Con esto la sección 3 queda
cerrada.**

**Qué cambió para el usuario** (Inicio → RECEPCIÓN → el evento):
- **En la PC (más de 1.024 px), la lista a la izquierda (60 %) y "Vista del tótem · Neón" a la derecha.**
  - Es la pantalla del salón en chico, en la apariencia del evento, vertical u horizontal como quedó ese tótem.
  - Saluda a la familia junta, con la mesa, las sillas, la música, 7 s o 3 s con cola y "N más en camino".
  - El QR, solo en particulares.
  - En una notebook de 1.366 antes salían pestañas; ahora va lado a lado.
- **En una tablet (600 a 1.024 px), pestañas RECEPCIÓN y TÓTEM.** La vista corre solo con su pestaña abierta; al
  volver, no saluda a los que entraron mientras tanto.
- **En el celular, la lista sola**, a pantalla completa, con la paleta arriba en la barra. Antes iba en una caja de
  500 px con el tótem viejo debajo.
- **Sobre la vista, un solo botón: la paleta.** Salieron los otros siete:
  - los tres modos (panel, pantalla completa, foco) y su `PopScope`;
  - cerrar, maximizar y minimizar la ventana del tótem. Maximizar y minimizar no hacían nada; el tótem del salón se
    cierra con el botón de su propia barra.
- **Inicio del asesor → Tótem** muestra la misma escena, a pantalla completa.
- **Anda sin internet:** un ingreso en esta PC hace saludar a la vista al instante, con la mesa de los alumnos aunque
  la fila de la puerta no la tenga.

**Cómo se arma:**
- **`TotemLocal`** (`totem/widgets/totem_local.dart`): la escena alimentada desde la base de la PC.
  - Escucha con `ref.listenManual` lo mismo que la lista de Recepción: `invitadosStreamProvider` y
    `puertaDelEventoProvider` → `FichaTotem.desdePuerta`.
  - La cola y los tiempos los pone `ReproductorBienvenidas`, el mismo del salón; la tarjeta la arma
    `ContenidoBienvenida.armar`.
  - La apariencia sale de `estiloDelEventoProvider` (y `eventoMasivoProvider`): mientras no se sabe el tipo, negro.
  - `encuadrar`: 9:16 o 16:9 según `TotemOrientationStore` del evento.
  - Va con la clave del evento.
- **`VistaDelTotem`** (`recepcion/widgets/vista_del_totem.dart`): el título con la apariencia, la paleta
  (`BotonPersonalizarTotem`, con `puedePersonalizarTotemProvider`) y `TotemLocal` encuadrado.
- **`recepcion_unified_screen.dart`**: los cortes salen de `CortesPantalla` (suma `esCelular`).
- **Salieron:**
  - `totem_panel.dart` (1.480 líneas);
  - `KioskLauncher.maximize` y `minimize`;
  - del modelo, los degradés del panel viejo (`gradientePanel`, `gradienteCard`, `acentoConAlpha`,
    `usaAcentoPorDefecto`). Sin cambios en la base.

**Decisiones mías, dichas en el plan:**
- la lista al 60 %;
- la vista de la tablet solo con su pestaña abierta;
- el título "RECEPCIÓN UNIFICADA" queda.

**Cómo se comprobó:**
- `test/totem_local_test.dart` (10), con la puerta en memoria y sin internet:
  - los que ya habían entrado al abrir no se saludan;
  - un alumno sin fila se saluda con la mesa 12 y sus sillas;
  - la familia, en una tarjeta;
  - dos familias, con "1 más en camino" y la de 3 s;
  - Neón sin QR en un masivo, Cristal con QR en un particular;
  - la elegida manda;
  - encuadrada vertical y horizontal;
  - al salir suelta la lista y los temporizadores.
- `test/recepcion_pantalla_test.dart` (13) monta Recepción entera con `PuertaEnMemoria.recepcion`, que arma los
  reemplazos y que ahora usa también el panel. Prueba:
  - los cortes, en 599/600 y 1.024/1.025 px;
  - las pestañas;
  - el 60 %;
  - un solo botón sobre la vista y ningún flotante;
  - sin el permiso, sin paleta;
  - la paleta abre Personalizar;
  - sin evento;
  - de punta a punta: buscar "bruno", Enter, y la vista saluda a GARCÍA, BRUNO en la mesa 17;
  - sin desbordes en 360, 800 y 1.366 px.
- **2.119 tests** en la suite (eran 2.096); `flutter analyze` sigue en 312.
- **Once roturas a propósito, todas vistas:**
  - un botón de más;
  - el corte de la tablet y el de la PC corridos;
  - la primera lectura que saluda;
  - la familia que no se junta;
  - el QR en un masivo;
  - la vista que no suelta sus temporizadores;
  - la mesa de la fila y no de los alumnos;
  - siempre vertical;
  - la paleta arriba fuera del celular;
  - la lista sin su 60 %.
- **`flutter build windows` y `flutter build web`, los dos bien.** No se abrió la app ni se publicó nada.
- **Muestras** en `build/muestras_6.0.0/recepcion/`, desde `tool/recepcion_muestra_test.dart`, con los fondos de
  verdad:
  - `Recepcion_PC.png`;
  - `Recepcion_tablet_totem.png`;
  - `Recepcion_celular.png`.
- **No se probó en la app.** La prueba de verdad es el ensayo.

**Lo que quedó igual, y dónde va:**
- **La vista lee la base de la PC, que no se corta.** Lo que baja de otra PC después de un corte llega todo junto y
  se saluda en cola, de a 3 s, como hacía el panel viejo. Va con la sección 7 (dos puestos).
- La foto del evento sigue siendo `Image.network`: sin internet cae al logo. Va con la sección 5.

**Un tropiezo de la sesión, sin consecuencias:** se cortó a mano una corrida de la suite y su `flutter test` quedó
andando con el candado de Flutter tomado. La corrida siguiente esperó diez minutos. Se cerró ese proceso (era de la
prueba) y la suite corrió en 51 s.

### La sección 4: el plano con la guía en la llegada

Plan aprobado: `C:\Users\lover\.claude\plans\donde-nos-quedamos-abundant-parasol.md` (la sección 4 arriba). Se le
mostró una maqueta con tres formas (A, el plano abajo; B, el plano de pantalla; C, en dos tiempos) en las cuatro
apariencias. **Eligió la A.** Pidió "completá la sección 4 y después actualizá el contexto". Dos pasos, cada uno con
su commit: **4a** (`4ae3d57`) y **4b** (`51818fb`). **Programado y subido; sin publicar.**

**Qué cambió para el usuario:**
- **Cuando llega una familia de un evento masivo ya sorteado,** el tótem muestra:
  - arriba, la llegada de siempre (saludo, nombre, mesa con sillas, música);
  - abajo, el salón de su plano, con su mesa encendida en el color del evento y las demás apagadas.

  En una tele horizontal, la llegada va a la izquierda y el plano a la derecha. Con dos mesas, las dos encendidas.
- **El camino:** se dibuja en 1,6 s desde el cartel "Ingreso" hasta el borde de la mesa.
  - Va **por los pasillos, sin pisar otras mesas** (con sus sillas) ni el escenario, la pasarela, las barras, las
    cajas o los baños. La pista se cruza.
  - Si no encuentra paso, va en línea recta.
  - Sale del borde del cartel, sin tacharlo.
- **Para que haya camino, el salón tiene que tener marcado el ingreso:** PLANO → PERSONALIZAR → Acomodar → + Sector
  → Ingreso, corrido hasta la entrada (del jefe, como todo el salón).
  - El armado de fábrica "Normal 2A · página 3" ya lo trae.
  - **El armado a medida del playón no.**

  Sin ingreso, la mesa se marca igual, sin camino. Si la mesa está en otra hoja que el ingreso (el pasto), esa hoja
  sin camino.
- **No aparece** en un particular, antes del sorteo, sin mesa, con un número que el plano no tiene, ni en el tótem
  por el navegador (no tiene ficha).
- **El plano se viste como el tótem** (decisión mía, dicha en el plan; responde la pregunta abierta del pendiente):
  - Neón con su plano Neón, Gala con su plano Gala;
  - Cristal con mesas blancas sobre vidrio;
  - Póster con mesas blancas.

  Sin colores de división: en la puerta importa una sola mesa.
- **Anda sin internet:** el plano sale de la base de la PC.
  - Al tótem del salón le llega dentro de la ficha, por el puente: al abrir y cada 60 s.
  - Recepción y el asesor lo leen directo.
- Sin SQL y sin cambios en la base.

**Cómo se arma:**
- **`PlanoDeLaLlegada`** (`totem/services/plano_de_la_llegada.dart`, pura).
  - Arma la hoja de la mesa principal, las mesas a encender, un `EstadoPlano` con **un solo ocupante, la familia**
    (uno por fila daría "conflicto") y el camino.
  - Da null si no hay qué mostrar.
- **`CaminoALaMesa`** (`totem/services/camino_a_la_mesa.dart`, pura).
  - **De dónde sale:** de `armado.ingreso` si está en esa hoja; si no, del sector "Ingreso".
  - **Por dónde va:** búsqueda A* en una grilla de medio radio, con las mesas tapadas a 1,35 radios por las sillas.
  - **Cómo queda:** se endereza, termina a 1,05 radios del centro y arranca en el borde del cartel.
- **`temaPlanoDelTotem(EstiloTotem, color)`** (`totem/estilos/plano_del_totem.dart`).
  - Los cuatro temas, guardados una vez por apariencia y color: `TemaPlano` no tiene `==`, y uno nuevo por cuadro
    redibujaría el salón entero.
  - La familia va en la única división, con el color del evento.
- **La ficha lleva el plano:** `FichaTotem.plano`.
  - `armarFichaTotem` lo lee con `leerPlano` (en `main.dart`, por `leerPlanoDeLaFiestaProvider`).
  - Un plano roto no tira la ficha.
  - Un particular no lleva plano.
- **`EscenaTotem.plano`:**
  - la guía se arma una vez por llegada (`planosArmados`, para los tests);
  - `_conPlano` reparte la pantalla y `PanelPlano` dibuja `VistaPlano`;
  - el camino crece con `caminoEmpieza` (0,9 s) y `caminoDura` (1,6 s).
  - `DatosEscena.conPlanoEn` da la medida de la parte de la llegada (en una apaisada se agranda).
  - Neón usa `planoAlCostado` para seguir arriba del horizonte.
- **`TotemLocal`** lee el plano con `planoDelEventoProvider`: lo relee al bajar un cambio de `planos_evento` y cada
  minuto, y avisa solo si cambió.
- **`leerPlanoDeLaFiestaProvider`** (en `planos_evento_repository.dart`) es una puerta que solo deja leer.
  `test/solo_modo_jefe_test.dart` vigila quién usa el repositorio del plano (nadie más puede guardar el salón). El
  tótem entra por esa puerta, y el test comprueba que sea solo `obtener`.

**Lo que apareció al mirar las muestras, y se arregló antes de subir:**
- En Cristal y Póster los sectores y la pista salían casi blancos: `withValues(alpha: 0.7)` **fija** la
  transparencia, no la multiplica. Ahora se multiplica.
- En una tele horizontal la llegada quedaba chica (medía con la pantalla entera): ahora la parte de la llegada tiene
  su medida.
- En Neón horizontal, las sillas y la música caían sobre la línea del horizonte: ahí se vuelve a respetar.
- El camino tachaba el cartel "Ingreso": ahora sale de su borde.

**Cómo se comprobó:**
- Tests nuevos o ampliados:
  - `test/plano_de_la_llegada_test.dart` (5);
  - `test/camino_a_la_mesa_test.dart` (12): **a cada una de las 78 mesas del salón de la Normal sin pisar otra**,
    medido tramo por tramo, y un playón de 284 mesas en menos de medio segundo;
  - `test/escena_totem_test.dart`: las cuatro apariencias en tres tamaños con el plano, sin plano, el tema que se
    reusa, la guía una vez por llegada y el camino que crece;
  - `test/ficha_totem_test.dart` y `test/puente_ficha_test.dart`: el plano por el puente;
  - `test/totem_local_test.dart`: con y sin plano en la PC.
- **2.163 tests** en la suite (eran 2.119); `flutter analyze` sigue en 312.
- **Quince roturas a propósito, todas vistas.**
  - En el 4a, siete:
    - el plano en un particular;
    - el plano que no viaja por el puente;
    - un ocupante por fila;
    - un tema nuevo por cuadro;
    - la guía por cuadro;
    - `TotemLocal` sin el plano;
    - la mesa sin el color del evento.
  - En el 4b, ocho:
    - el camino que pisa una mesa;
    - pisa la barra;
    - sin paso, ningún camino;
    - termina en el centro de la mesa;
    - tacha el cartel;
    - el ingreso de otra hoja;
    - la guía sin camino;
    - el camino entero desde el principio.
- **Muestras** en `build/muestras_6.0.0/totem/`:
  - `Totem_llegada_plano.png` (las cuatro, vertical);
  - `Totem_llegada_plano_horizontal.png`.
- **No se probó en la app.** La prueba de verdad es el ensayo: marcar el Ingreso en Acomodar, sortear, ingresar a
  una familia y mirar el tótem.

**Tropiezo de la sesión, sin consecuencias:** el script de las roturas dejó una copia de respaldo
(`respaldo_4b.dart`) en la raíz del proyecto, porque se corrió desde otra carpeta. Se vio porque `flutter analyze`
subió a 333; se borró (era idéntica al archivo del camino) y volvió a 312. No llegó a ningún commit.

### La sección 5: una PC completa sin internet

14-oct, otro chat. Pidió "seguí con la sección 5 hasta terminar y ahí actualizás contexto". Sin archivo de plan: el
plan corto se le pasó en el chat (después de que preguntara "¿estás haciendo el plan?": se había empezado a
programar sin mostrárselo; ver la memoria `plan-antes-de-programar`). La línea de Recepción se decidió con una
maqueta de dos opciones: **eligió la A, una línea debajo del progreso** (la B era una pastilla arriba a la derecha).
Cuatro pasos, cada uno con su commit: **5a** (`245c547`), **5b** (`3039b07`), **5c** (`5d78edd`) y **5d**
(`566a3f3`). **Programado y subido; sin publicar.** Es lo que en `docs/pendientes/modo-local-sin-internet.md` son los
pasos 1 y 2.

**Qué cambió para el usuario:**
- **5a · El tótem del salón abre con la lista aunque no haya internet.** Antes, abierto sin internet, arrancaba vacío
  ("0 LLEGARON" con la fiesta empezada). Ahora, si no puede leer la nube, le pide a la PC quién ya entró y lo pone
  en la lista sin saludar. Lo que esta PC marcó sin internet no se saluda de nuevo cuando vuelve la conexión.
- **5b · La foto del evento queda guardada en la PC** (`Documentos\Junior Eventos\fotos_totem\<evento>\`) la primera
  vez que se ve: el tótem, Recepción y Personalizar la siguen mostrando sin internet. Si se cambia la foto y no hay
  internet para bajar la nueva, se ve la anterior en lugar del logo. La vieja se borra recién cuando la nueva quedó
  guardada.
- **5c · El programa entra sin internet con la sesión vencida.** Es lo de todos los días: el permiso de Supabase
  dura una hora, así que el programa abierto al otro día arranca con la sesión vencida. Ya entraba (la librería no
  la borra si no puede renovarla por falta de internet); ahora está **comprobado con la librería de verdad y la red
  cortada**, y la decisión quedó en un solo lugar (`sesionParaEntrar`).
  - **Apareció y se arregló:** con red pero sin salida a internet (un router solo en el salón) el programa quedaba
    **12 segundos en "Verificando permisos..."**. Ahora, si la PC recuerda el rol, espera la nube como mucho 3 s y
    entra con el recordado; si la nube contesta después, el recordado queda al día para la próxima.
  - Si el servidor rechaza la sesión (alguien la cerró), va al login, como antes.
- **5d · "Lista para trabajar sin internet" en Recepción.** Una línea debajo de "312 de 1.100 adentro", que se toca
  para ver el detalle (personas en esta PC, al día, foto del tótem, ingresos sin subir):
  - con internet y todo en la PC: "Lista para trabajar sin internet · al día 21:40", en verde;
  - con internet y algo que falta: "Todavía no está lista…: falta guardar la foto del tótem", o que no se pudo
    bajar la lista, en ámbar;
  - sin internet: "Sin internet · se sigue con lo de esta PC (al día 21:32) · 12 ingresos sin subir: se suben solos
    al volver";
  - sin internet y sin la lista: "Sin internet, y esta PC no tiene la lista de este evento: conectala un momento a
    internet".

  **Al abrir el evento con internet, Recepción lo pone al día**: baja la lista de la puerta entera, en un masivo
  también el evento, los alumnos, sus sillas y el plano, y guarda la foto. Lo repite cada 5 minutos y cuando vuelve
  internet. **Esto arregló algo que estaba:** Recepción bajaba la lista solo si la PC no tenía ninguna fila de ese
  evento, así que una lista cargada o cambiada después en otra PC podía quedar incompleta hasta que alguien marcara
  un ingreso. La línea no sale en la web (sin internet la web no anda).
- Sin SQL, sin cambios en la base. Lo nuevo de la PC: la carpeta de fotos y, en las preferencias, la hora en que
  cada evento se puso al día (`puerta_al_dia_v1_<evento>`).

**Cómo se arma:**
- **5a:**
  - `IngresosTotem.leyoDeLaPc`: siempre en silencio; no se usa si ya leyó la nube; cuida lo que no subió como lo
    avisado por el puente; no da por conectado.
  - La lista viaja en `ListaDeLaPc` (solo los que entraron y cuáles no subieron), por el puente con un segundo
    mensaje, `lista_totem` (`PuenteFichaTotem.metodoLista`). **La pide el tótem**, como la ficha: en cada intento
    fallido de leer la nube, hasta que la lea.
  - En la ventana principal la arma `armarListaDeLaPc` con `getLocalesByEvento` e `idsSinSubir` (nuevo en
    `InvitadosRepository`: los del evento con algo en la cola).
- **5b:** `FotoGuardada` (un `ImageProvider`) y `FotosDelTotem` (`totem/services/foto_guardada.dart`). `EscenaTotem`
  usa `fotoDelEvento(cfg)`: en la web sigue siendo `NetworkImage`. Cada foto se guarda con el nombre de su dirección
  (cambia con `?v=` al subir otra); dos pantallas que la piden a la vez la bajan una vez; solo se guarda lo que la
  nube dice que es una imagen.
- **5c:**
  - `sesionParaEntrar` (`features/auth/sesion_sin_internet.dart`) salió de `AuthWrapper`, sin cambiar lo que hacía.
  - `userRoleProvider` lee `supabaseProvider` (para poder probarlo) y espera `kEsperaDelRolRecordado` (3 s) si hay
    rol recordado.
- **5d:**
  - Lo que dice la línea: `EstadoSinInternet.de` (`recepcion/services/lista_sin_internet.dart`, pura).
  - Cuándo se pone al día: `PuestaAlDiaPuerta`, con `AccesosPuerta` para reemplazarla en los tests.
  - `puestaAlDiaProvider` (`recepcion/providers/sin_internet_provider.dart`) la conecta con la conexión, el tipo de
    evento y la foto del tótem; arranca cuando se sabe si es masivo.
  - `LineaSinInternet` (`recepcion/widgets/linea_sin_internet.dart`) la dibuja, dentro de `PanelPuerta`.
  - Bajadas nuevas que dicen si salieron bien: `InvitadosRepository.bajarListaDelEvento` y
    `SyncEngine.bajarParaLaPuerta` (las `tablasDeLaPuerta`). `_pullTable` y `_pullByEvento` ahora devuelven si
    bajaron, sin cambiar lo que hacen.

**Cómo se comprobó:**
- Tests nuevos o ampliados:
  - `test/bienvenidas_totem_test.dart`, `test/reproductor_bienvenidas_test.dart`, `test/puente_ficha_test.dart` e
    `test/ingresar_desde_la_puerta_test.dart` (5a);
  - `test/foto_guardada_test.dart` (13) y `test/escena_totem_test.dart` (5b);
  - `test/sesion_sin_internet_test.dart` (9): **la librería de Supabase de verdad**, haciendo lo mismo que al abrir
    el programa con la sesión de ayer y la red cortada; la renovación al volver internet; el rechazo; el rol sin red,
    con un router sin salida (en menos de 4 s) y con internet;
  - `test/lista_sin_internet_test.dart` (27) y `test/puesta_al_dia_nube_test.dart` (6, sobre una base temporal y
    una nube simulada) (5d).
- **2.233 tests** en la suite (eran 2.163); `flutter analyze` sigue en 312; `flutter build windows` y `web` bien.
- **Roturas a propósito: 37** (8 de la 5a, 8 de la 5b, 7 de la 5c, 14 de la 5d). **34 las vio algún test**; las
  otras tres no podían fallar y se le dijeron: en la 5a, el silencio de la lectura de la PC (desde ahí no hay cómo
  saludar) y un filtro que repetía el de `armarListaDeLaPc` (se sacó); en la 5c, entrar con una sesión rechazada (no
  queda ninguna con qué entrar). Una de la 5d no la veía nadie al principio (cortarse internet mientras baja): se le
  agregó su test y ahora se ve.
- **Muestras** en `build/muestras_6.0.0/sin_internet/` (`tool/sin_internet_muestra_test.dart`): `SinInternet_1_lista`,
  `_2_falta_la_foto`, `_3_sin_internet` y `_4_sin_la_lista`.
- **No se probó en la app** (no se corre desde el working tree, y es producción). La prueba de verdad es el ensayo:
  con todo bajado, sacar el cable de internet, cerrar y abrir el programa, abrir Recepción y el tótem, marcar
  ingresos, y volver a enchufar.

**Tropiezos de la sesión, sin consecuencias:** dos pruebas se colgaban. Una era del programa: la descarga de la foto
se quedaba esperándose a sí misma (`whenComplete` con `=>` devolvía la misma descarga); se vio en la prueba y se
arregló antes de subir. La otra era de la herramienta de pruebas (dibujar una imagen dentro de `testWidgets`); se
pasó a `test`.

### La sección 6: el tótem en modo kiosco

14-oct, mismo chat que la 5 ("seguimos por este chat hasta completar la sección 6"). Plan aprobado:
`C:\Users\lover\.claude\plans\quizas-seguimos-por-este-soft-sloth.md`, con una maqueta de la ventana y del kiosco.
Dos pasos: **6a** (`3111ce7`, la ventana del escritorio) y **6b** (`acbe9e0`, la web). **Programado y subido; sin
publicar.** Era `docs/pendientes/totem-kiosco.md`.

**Qué cambió para el usuario:**
- **Inicio → TÓTEM**, como siempre. Se arrastra la ventana del tótem a la tele y, en la barra de arriba a la derecha
  (aparece al mover el mouse), se toca **KIOSCO**:
  - el tótem ocupa **la tele entera** en el monitor donde estaba la ventana, sin bordes, sin barra de título y sin la
    barra de Windows;
  - abajo, 3 s: "Pantalla completa · para salir: Esc o doble clic";
  - **se sale con Esc, con doble clic en cualquier lugar o con SALIR DEL KIOSCO**;
  - el puntero se esconde a los 3 s sin moverse;
  - en kiosco no está el botón de girar: si se eligió vertical y la tele está acostada, va en 9:16 en el medio.
- **Al cerrar el tótem** (su ✕, o desde la PC) **sale del kiosco antes de esconderse**; al volver aparece como
  ventana, en el mismo lugar.
- **En la web** (`?totem`): el primer toque pasa a pantalla completa del navegador; doble toque o Esc la dejan. Llega
  cuando se publique la web.
- Sin base, sin nube, sin SQL. Lo único nativo nuevo es del runner de Windows.

**Cómo se arma:**
- **Nativo** (`windows/runner/kiosco.cpp`, llamado desde `flutter_window.cpp`): con
  `DesktopMultiWindowSetWindowCreatedCallback` le da a cada ventana secundaria el canal `junior_eventos/kiosco`
  (`entrar`, `salir`, `estado`). Entrar guarda el lugar (`GetWindowPlacement`) y el estilo, saca
  `WS_OVERLAPPEDWINDOW` y ocupa el monitor; salir los devuelve, sin mostrar una ventana escondida. Los canales no se
  destruyen (el motor de la ventana ya no existe al cerrar el programa). La ventana principal no se toca.
- **Dart:**
  - `totem/services/kiosco.dart`: `Kiosco` (`KioscoVentana`, el canal), `ControladorKiosco` (en kiosco o no, los
    avisos, los pedidos de a uno) y `DobleClic` (contado a mano, así los botones no esperan);
  - `KioscoNavegador` (`kiosco_navegador*.dart`, importación condicional con `dart:js_interop`), que además pregunta
    si el navegador la sacó por su cuenta (`activo`, `sincronizar`);
  - `CapaKiosco` (`totem/widgets/capa_kiosco.dart`): Esc con `HardwareKeyboard`, doble clic, puntero, el aviso, y en
    la web `entrarAlTocar`.
- **`totem_display.dart`:** la píldora KIOSCO solo en la ventana; `_pausar()` sale del kiosco antes que nada y el
  "pausar" de `KioskLauncher.close` contesta recién después; en kiosco no se gira ni se cambia la forma de la
  ventana; en kiosco encuadra según la orientación, como la web.

**Cómo se comprobó:**
- `test/capa_kiosco_test.dart` (24) y `test/kiosco_en_el_totem_test.dart` (6, lee el archivo del tótem como
  `solo_modo_jefe_test`, porque la pantalla no se puede montar). **2.263 tests** (eran 2.233); `flutter analyze` en
  312; `flutter build windows` y `web` bien.
- **Roturas a propósito: 22, todas vistas** (15 de la 6a, 7 de la 6b).
- **La ventana de verdad, con el arnés `tool/kiosco_prueba.dart`** (`flutter run -d windows -t
  tool/kiosco_prueba.dart`: abre `TotemDisplay` con un evento inventado y la nube apuntando a ningún lado; **no abre
  la base** ni sube nada). Lo manejé yo con capturas, con su permiso:
  - KIOSCO: ocupó los 2560 × 1440 de la pantalla, sin barra de título (estilo `0x14000000`) ni barra de Windows, con
    el 9:16 en el medio y el aviso;
  - Esc y doble clic: volvió a ser ventana, en el mismo lugar y tamaño;
  - esconder estando en kiosco (como `KioskLauncher.close`, con un botón del arnés) y volver a mostrar: apareció como
    ventana.
  - **No se pudo tocar SALIR DEL KIOSCO ni la ✕ en kiosco:** en esa esquina estaba la ventana de Claude por encima, y
    los clics le llegaban a ella. Hacen lo mismo que KIOSCO (`alternar`) y que esconder (`_pausar`), que sí se
    probaron, y tienen sus tests. Queda para el ensayo.
  - Una sola pantalla: lo de pasar la ventana a la tele también queda para el ensayo.
- Capturas en `build/muestras_6.0.0/kiosco/` (`Kiosco_1_ventana_con_el_boton`, `_2_en_kiosco`,
  `_3_vuelve_como_ventana`).

**Tropiezos de la sesión, sin consecuencias:**
- La primera vez, el permiso para manejar la ventana de prueba se rechazó, y el usuario dijo "hacela nomás": se pidió
  de nuevo y se aceptó. El arnés figura como `arguello_events.exe`.
- La barra del tótem se esconde a los 5 s y no recibe clics escondida: hay que mover el mouse antes de tocarla.
- No se apretó Esc con la ventana de Claude adelante: le habría llegado a Claude.

### La sección 7: los celulares de la puerta, por una notebook central

14-oct a la noche (plan) y 15-oct (programa), en un chat que empezó con "donde nos quedamos?". Plan aprobado:
`C:\Users\lover\.claude\plans\donde-nos-quedamos-snoopy-salamander.md`, con maqueta. Pasos: **7b** (`adc96d0`, la
central), **7c** (`1be0815`, el celular), **7d** (`70935aa` y `68f4826`, Recepción y el instalador) y **7e** (la
prueba con su celular, abajo). **Programado, subido y probado; sin publicar.**

**Lo que contestó, y por qué cambió el diseño.** Antes de planear se le preguntó lo que estaba anotado en "Lo que
sigue esperando del usuario": los puestos **van a ser casi seguro celulares** (más de dos; quizás alguna PC), **llevan
router propio** aunque sea sin internet ("para que nos conectemos"), y **no sabe dónde va el tótem**. El pendiente
proponía que las PCs se avisaran entre ellas por la red; con celulares no sirve: el celular usa la web, que se baja
de internet. Se le propuso y aprobó **una notebook del salón como central**. No lo entendió a la primera ("eso de una
notebook como central con QR no le entendí"): se le explicó con un dibujo y "cómo sería la noche", y le gustó ("le
sentí una intuición como que podría funcionar"). Preguntó "¿sin internet se opera igual?": sí, el router no necesita
internet. Descartada la app de Android (nunca se armó, habría que instalarla en cada celular y cada uno llevaría la
base entera). En la maqueta eligió **la A: el botón arriba, con cuántos hay**.

**Qué cambió para el usuario:**
- **En la Recepción de la PC, arriba a la derecha, CELULARES** ("CELULARES · 2" con dos conectados). Abre "Sumar un
  celular": el QR, la dirección y el código por si el QR no anda ("192.168.0.10:8787 y el código 4821"), la otra
  dirección si la PC tiene más de una conexión, y quiénes están conectados ("Juli · 41 marcados", "Mati · sin señal
  hace 3 min"). Sin router lo dice y deja probar de nuevo. "Cambiar el código" pregunta antes y desconecta a todos.
  Solo en el programa, no en la web.
- **El celular**, en el wifi del router, escanea el QR y se le abre la misma lista de Recepción en el navegador, sin
  instalar nada. La primera vez pide un nombre (y el código si entró con la dirección). Arriba el evento y "Conectado
  a la PC"; se busca, se ingresa y se deshace como en la PC. No se elimina a nadie desde el celular.
- **Sin conexión con la PC se sigue marcando**: "Sin conexión con la PC · 2 por mandar" y "POR MANDAR" en cada uno.
  Queda guardado en el celular aunque se cierre el navegador, y al volver se manda solo, en el orden en que se tocó
  ("Conectado · se mandaron 2"). **Lo que llega más de un minuto tarde se marca sin saludar en el tótem** (la familia
  ya pasó), igual que después de un corte.
- **No se pisan**: hay una sola lista, la de la notebook. Si otro celular ya lo había ingresado: "GARCÍA, BRUNO ya
  ingresó a las 22:41 · Juli". Debajo de ADENTRO va quién lo ingresó, también en la Recepción de la PC.
- **Si la notebook se reinicia**, al abrir Recepción la central vuelve sola con el mismo código (dura 18 h) y los
  celulares se reconectan sin volver a escanear.
- **El tótem** de la notebook saluda a todos los que se marcan desde cualquier celular (por el puente de siempre).
- **Una tablet, igual que un celular** (lo preguntó su cliente el 15-oct): Android o iPad, por el navegador, con el
  QR o la dirección; la lista se acomoda al ancho. Una segunda notebook también, por el navegador.
- **El instalador** arma la página del celular (`installer\build_installer.ps1`), la deja en `{app}\puesto` y crea la
  regla del cortafuegos de Windows para los puertos 8787 a 8796, en cualquier red (la del router suele quedar como
  "pública"). Al desinstalar la borra.
- Sin cambios en la base ni en la nube. Sin SQL.

**Cómo se arma:**
- **La central** (`lib/features/recepcion/central/`): `CentralPuerta` (`central_puerta.dart`) es un servidor HTTP y
  WebSocket dentro del programa (`dart:io`), en `/vivo?c=<código>&id=<celular>&p=<nombre>`. Le manda a cada celular
  la lista (`PuertaDelEvento.toJson`, con `titulo` y `por`, quién marcó) apenas se conecta y en cada cambio. Atiende
  los pedidos **de a uno**, mirando la base en ese momento (`decidirPedido`, en `pedidos_de_la_puerta.dart`), y los
  hace por `InvitadosRepository` (`PuertaDeEstaPcConBase`): la cola de subida y el aviso al tótem quedan iguales.
  También sirve la página del celular sin dejar salir de su carpeta.
- **Reglas de la central:** un pedido repetido (mismo id) no se hace dos veces y se contesta igual; a quien la lista
  tenía con fila y la base ya no, no se lo vuelve a crear; quién marcó (`MarcasDeLaNoche`, solo en memoria) **se
  anota antes de marcar** (la lista nueva sale enseguida y tiene que salir con el nombre) y se deshace si la base
  falla; cinco códigos mal seguidos frenan un minuto; cambiar el código cierra todas las conexiones.
- **`CentralDeLaPuerta`** (`central_provider.dart`) la prende para un evento y le pasa la lista y el nombre del evento
  con **`ref.container.listen`, no `ref.listen`**: Riverpod 3 pausa lo que escucha un provider que nadie mira, y la
  central tiene que seguir aunque Recepción esté cerrada. `reanudar` la vuelve a prender si hay código de esta noche
  (`CodigoCentral.vigente`). Lo que toca la red va por providers que las pruebas reemplazan
  (`escuchaCentralProvider`, `puertoCentralProvider`, `direccionesDeEstaPcProvider`, los del código,
  `paginaDelCelularProvider`): **las pruebas escuchan solo en esta PC**, así Windows no pregunta por el cortafuegos.
- **El celular:** `ClienteCentral` (`cliente_central.dart`, con `web_socket_channel`) guarda lo pendiente en el
  navegador, pone encima de la lista lo tocado y no contestado (`listaConCambios`), late cada 5 s y da la conexión por
  caída a los 12 s sin noticias. Si la central no hizo nada ("ya ingresó"), vale lo de ella. `PantallaPuesto`
  (`pantalla_puesto.dart`) es la pantalla; adentro va **`PanelPuerta`, el mismo de Recepción**: el panel marca por
  `AccionesPuerta` (`providers/acciones_puerta_provider.dart`), que en la PC es la base y en el celular la central.
- **La página del celular** es otra entrada, `lib/puesto_main.dart` (sin Supabase ni base), armada con
  `flutter build web -t lib/puesto_main.dart --no-web-resources-cdn`: todo sale de la notebook. Pesa 54 MB en
  carpeta, el celular baja unos 11 (el programa y el motor de dibujo), una vez.
- **En la web de un celular, el primer toque después de escribir en la búsqueda no andaba**: Flutter suelta el
  teclado al apoyar el dedo afuera y eso se comía el toque. El buscador de `PanelPuerta` lo suelta al levantarlo
  (`onTapUpOutside`, solo en la web). Arregla también la Recepción de la web.
- `sumar_celular.dart` (el botón y la ventana); `RecepcionUnifiedScreen` llama a `reanudar` al elegir evento.

**Cómo se comprobó:**
- **2.383 tests** (eran 2.263); `flutter analyze` en 312; `flutter build windows` bien, la página del celular armada,
  y el instalador compila (38 MB, con la página adentro; se armó en una carpeta aparte y se borró).
- **La central de verdad con celulares de mentira por la red** (`test/central_puerta_test.dart`), el celular de verdad
  contra la central (`test/cliente_central_test.dart`: sin conexión, reinicio de la notebook, navegador cerrado,
  central muda, código cambiado, dos pestañas), la central desde el programa (`central_provider_test.dart`), las
  pantallas (`pantalla_puesto_test.dart`, `sumar_celular_test.dart`), el "sin saludar" con la base temporal y un
  tótem de mentira (`ingreso_sin_saludo_test.dart`), y el instalador leído (`instalador_puesto_test.dart`).
- **Roturas a propósito: 57, todas vistas** (26 de la 7b, 19 de la 7c, 12 de la 7d). Tres de la 7d al principio no
  las vio nadie: una no rompía nada (la protección estaba dos veces) y dos mostraron pruebas flojas del instalador
  (el texto también estaba en un comentario); se arreglaron las pruebas.
- **En un navegador de verdad**, con la central de prueba (`tool/central_prueba_test.dart`, evento inventado, sin
  base) y la página armada: abre sin pedir nada a internet, entra con el nombre, ingresa, se corta la central y se
  sigue marcando ("2 por mandar"), vuelve y lo manda solo; dos "celulares" (dos pestañas con distinto origen) y la
  misma persona sin conexión en los dos: entró una vez y al otro le dijo "ya ingresó a las 07:40 · Juli". Así
  aparecieron los dos arreglos de arriba (quién marcó y el primer toque).
- Muestras: `build/muestras_6.0.0/celulares/Celulares_1..6.png` (`tool/celulares_muestra_test.dart`).

**La 7e, la prueba con su celular: hecha el 15-oct, anduvo todo.** Volvió del trabajo y pidió "hagamos la prueba
faltante para concluir". Con el arnés `tool/central_puerta_prueba.dart` (`flutter run -d windows -t
tool/central_puerta_prueba.dart`, después de armar la página en `build\puesto`): la Recepción de verdad con un evento
inventado, **sin abrir la base**, y la central escuchando en el wifi de la PC (Windows preguntó por el cortafuegos:
el arnés no tiene la regla del instalador). Con su celular en el wifi de la casa: **"Anduvo todo: conectó, ingresé,
sin wifi quedó por mandar y al volver se mandó, y el tótem saludó."** Se vuelve a usar igual si hace falta.

**Queda afuera** (dicho en el plan): celulares sin ninguna PC en el salón y sin internet (no hay forma; con internet
siguen por la web, `/op`, que se cierra en la 8); una segunda tele (por ahora el tótem va en la central).

**Tropiezos de la sesión, sin consecuencias:** el chat se cortó por el límite de uso en medio de un `git add` (no
había llegado a hacer nada); cortar una prueba larga de Flutter deja el `flutter_tester` escuchando en el puerto, y
hay que cerrarlo a mano (`Get-NetTCPConnection -LocalPort 8799`).

## Lo que falta para publicar

**No se publica sin su "publicamos".** Antes, la sección 8 del orden del 14-oct.
**El instalador se arma con `installer\build_installer.ps1`**, que ahora también arma la página del celular: sin
ella el instalador no compila (y la central no tendría qué darle al celular). Después:

1. **La nube, lo que solo agrega**, con su OK en el momento y sin regla de horario:
   - los dos SQL de siempre (`supabase/migrations/20260925120000_sillas_retiro_sorteos.sql` y
     `20260926120000_planos_y_cambios_de_mesa.sql`). Solo crean tablas nuevas y la 5.0.0 no las mira: se pueden
     correr cuando él diga;
   - las dos columnas de `totem_config` (`supabase/migrations/20261014120000_totem_config_estilo_y_musica.sql`):
     **ya corrido el 14-oct**; queda nombrado para saber que no hay que repetirlo (correrlo de nuevo es inocuo);
   - las funciones de la puerta (sección 8).
   Antes y después de cada uno, los conteos: el 11-oct daban **643 contratos, 3.963 pagos, 26 notas, 7 invitados y
   30 eventos**, y tienen que dar igual (se vuelven a contar ese día).
2. **Antes de publicar, la migración otra vez sobre una copia de su base de ese día**
   (`tool/verificar_migracion_v73_test.dart`): el 11-oct dio perfecto, pero desde entonces hubo cobros.
3. **El release:** `powershell -File tool/publish_windows_release.ps1 -SoloNotas -NotesFile build\novedades_6.0.0.md`.
   El texto de novedades hay que rehacerlo: nombra solo lo del 11-oct.
4. **Instalar:** primero la PC del usuario; después la del operario y la de la oficina.
5. **Mientras una PC tenga la 5.0.0 y otra la 6.0.0** se cobra normal. **No se sortea, no se entregan entradas ni se
   importa ningún Excel hasta que todas tengan la 6.0.0.**
6. **Publicar la web**, con su OK.
7. **Cerrar los permisos de la lista de la puerta**, último: si se cierra antes, el tótem de una PC con la versión
   vieja queda en blanco.
8. **El ensayo:** armar el plano, sortear una institución, mirar en otra PC que está lo mismo, abrir Recepción y el
   tótem, marcar ingresos, y al final SORTEO ▾ → Deshacer sorteo → Todo. Tiene que quedar sin mesas y con la lista
   vacía, en las PCs y en la nube. **Y sin internet** (sección 5): con Recepción diciendo "Lista para trabajar sin
   internet", sacar el cable, cerrar y abrir el programa (tiene que entrar en unos segundos), abrir el tótem (con la
   lista y la foto), marcar ingresos, y volver a enchufar: la línea tiene que pasar de "N ingresos sin subir" a
   lista, y la nube quedar igual que la PC. **Y el kiosco** (sección 6): arrastrar la ventana del tótem a la tele,
   KIOSCO, y salir con Esc, doble clic, SALIR DEL KIOSCO y la ✕ (estos dos no se pudieron tocar en la prueba);
   volver a abrirlo. **Y los celulares** (sección 7): el router propio sin internet, la notebook con la tele por
   HDMI y conectada a ese wifi, Recepción → CELULARES; dos o tres celulares escanean el QR y marcan; uno corta el wifi,
   marca y vuelve; dos marcan a la misma persona; reiniciar la notebook en medio y ver que los celulares vuelven
   solos. Al final, con internet, la nube igual a la notebook. Con la versión instalada (con la regla del
   cortafuegos), Windows no tiene que preguntar nada.
9. Poner acá el estado en "publicada", con el tag y la fecha, y la memoria al día.

## Lo que sigue esperando del usuario (no frena publicar)

- **Marcar el Ingreso en el plano de cada institución** (PLANO → PERSONALIZAR → Acomodar → + Sector → Ingreso),
  para que el tótem dibuje el camino. Lo hace el jefe; el armado a medida del playón no lo trae. Sin eso, la mesa se
  marca igual, sin camino.
- **Las imágenes de la sección 4** (`Totem_llegada_plano.png` y su horizontal): se le mandaron al cerrar el chat;
  todavía no opinó.
- **Las imágenes de la sección 5** (`build/muestras_6.0.0/sin_internet/SinInternet_1..4.png`): se le mandaron al
  cerrar el chat; todavía no opinó.
- **Las capturas de la sección 6** (`build/muestras_6.0.0/kiosco/`): se le mandaron al cerrar; todavía no opinó.
- **Las muestras de la sección 7** (`build/muestras_6.0.0/celulares/Celulares_1..6.png`): se le mandaron tres el
  15-oct; dijo "todo ok", y la probó con su celular.
- **Dónde va el tótem en un masivo** (dijo "todavía no sé"): la recomendación es la notebook central, con la tele
  por HDMI. Una segunda tele, aparte, si hace falta.
- **Si quiere, una prueba real de entrar sin internet, ya, con la 5.0.0 instalada** (no cambia datos): más de una
  hora después de cerrar el programa, sacar internet, abrirlo y ver que entra y que Recepción muestra la lista. Con
  la 5.0.0 entra igual (eso no cambió), pero con un router sin salida a internet tarda unos 12 s en "Verificando
  permisos..."; con la 6.0.0, unos 3 s. Se le ofreció; no es obligatoria.

- **Si cambiaría algo de las pantallas del recorrido** (`build/muestras_6.0.0/recorrido/Recorrido.html`, 33
  pantallas; abrírselo en Edge). No preguntarle "¿cambiarías algo?" a secas: no lo entendió. Mostrarle primero.
  (Lo de la nota resuelta ya lo contestó: queda con el tilde verde.)
- ~~Para la parte 8b: cuántos puestos, con qué, dónde va el tótem y si hay router~~: **contestado el 14-oct**
  (celulares, más de dos; router propio; el tótem, no sabe). Ver "La sección 7". Se le había recomendado además
  internet de respaldo (un router 4G o el celular); no lo descartó, y con la central no hace falta para la puerta.
- La página 6 del Canva: la Normal ya tiene **137 mesas cargadas** (116 con lo pagado el 11-oct), y su armado del
  Canva tiene la hoja B provisoria. Mientras tanto está el armado a medida del playón, y las mesas que falten se
  agregan en Acomodar.
- Los cuatro lados del playón medidos con cinta (hoy son 30, 46 y 39 m, a ojo del satélite).
- Las respuestas del jefe: qué armado usa cada escuela, las numeraciones, el pasto, y por división o entera.
- La fecha del sorteo. El 13-oct dijo que "falta un mes y alguito".
- Cerca del sorteo: volver a sacar el control de mesas y sillas y verlo con él, nombre por nombre.

## Para seguir en otro chat, pegar

```text
Seguimos con la 6.0.0 de Junior Eventos. Leé primero
docs/CONTEXTO_v6.0.0_2026-10-11.md entero (sobre todo "Qué pasó el 14-oct" y
"Lo que falta para publicar"), CLAUDE.md y la memoria del proyecto. El
camino de las secciones está en
C:\Users\lover\.claude\plans\donde-nos-quedamos-gentle-hummingbird.md; lo
hecho en cada una, en el CONTEXTO (la sección 5 no tuvo archivo de plan; la 6
está en C:\Users\lover\.claude\plans\quizas-seguimos-por-este-soft-sloth.md y
la 7 en C:\Users\lover\.claude\plans\donde-nos-quedamos-snoopy-salamander.md).
La 6.0.0 NO está publicada: las PCs siguen con la 5.0.0. En la nube ya se
corrió el SQL de totem_config (14-oct); los de la Fase 2 y la Fase 3, no (lo
confirmé mirando la nube el 14-oct: esas cinco tablas no existen). Van antes
de instalar, con mi OK. Va todo en una sola versión, por partes. El objetivo
de lo que falta: que Recepción y el tótem distingan un evento particular de
uno masivo (se dice "evento masivo", no "fiesta de alumnos"). Están hechas
las secciones 1 (Recepción distingue particular y masivo), 2 (el tótem
distingue particular y masivo), 3 (las cuatro apariencias en el tótem,
Personalizar y la vista del tótem en Recepción con TotemLocal;
totem_panel.dart ya no existe), 4 (en la llegada de un masivo, el plano con
la mesa encendida y el camino desde el Ingreso) y 5 (una PC completa sin
internet: el tótem abre con la lista, la foto guardada en la PC, entrar con
la sesión vencida y "Lista para trabajar sin internet" en Recepción), 6 (el
tótem en modo kiosco, en la ventana y en la web) y 7 (los celulares de la
puerta: una notebook del salón hace de central, CELULARES en Recepción muestra
un QR, el celular abre la lista en el navegador por el wifi del router, sin
internet, y lo marcado sin conexión se manda al volver; la probé con mi
celular el 15-oct y anduvo todo). Seguí por la sección 8 (cerrar la lista de
la puerta: docs/pendientes/rls-invitados.md) y después la 9 (verificación y
publicar).
ANTES DE PROGRAMAR cada sección, mostrame el plan corto y esperá mi OK; si
trae algo nuevo a la vista, una maqueta. Avisame al terminar cada paso con
cómo quedó, un commit y un push. Cada cambio lo apruebo yo.
Todo lo que falta de Recepción y el tótem tiene que andar sin internet con los
datos ya bajados: la regla y lo que cuida cada parte están en
docs/pendientes/modo-local-sin-internet.md (es la parte 8b del camino).
Las muestras con muchas imágenes abrímelas en Edge: el panel de la app no las
muestra. Una imagen suelta sí la veo en el chat. Si no entiendo algo nuevo,
explicámelo con un dibujo y "cómo sería la noche".
Contestame primero lo que te pregunto, en una línea. Lo que tiene poco riesgo y
vuelta atrás, recomendalo y seguí: no me lo preguntes como si fuera un peligro.
No corras la app desde el working tree (la v73 migraría la base real). Lo que
toque la base real o la nube, con mi OK en el momento; ya no hay regla de
horario. Para volver atrás en el código está el tag antes-de-6.0.0. Con
"actualizá el contexto", frená y dejá todo anotado.
```
