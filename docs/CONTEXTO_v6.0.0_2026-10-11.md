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
**"Qué pasó el 13-oct"**, más abajo. **Hechas las partes 1 a 4; sigue la 5** (las cuatro apariencias del tótem).
Lo de este encabezado es cómo quedó el 11-oct.
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
| 5 | Tótem: cuatro apariencias (`pendientes/totem-apariencias.md`; una columna en la nube) | **sigue esta** |
| 6 | Recepción más amigable (`pendientes/recepcion-redisenio.md`) | falta |
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

## Lo que falta para publicar

**No se publica sin su "publicamos".** Antes, las partes 5 a 10 del camino de arriba. Después:

1. **La nube, lo que solo agrega**, con su OK en el momento y sin regla de horario:
   - los dos SQL de siempre (`supabase/migrations/20260925120000_sillas_retiro_sorteos.sql` y
     `20260926120000_planos_y_cambios_de_mesa.sql`). Solo crean tablas nuevas y la 5.0.0 no las mira: se pueden
     correr cuando él diga;
   - la columna de la apariencia del tótem (parte 5) y las funciones de la puerta (parte 9).
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
   vacía, en las PCs y en la nube.
9. Poner acá el estado en "publicada", con el tag y la fecha, y la memoria al día.

## Lo que sigue esperando del usuario (no frena publicar)

- **Si cambiaría algo de las pantallas del recorrido** (`build/muestras_6.0.0/recorrido/Recorrido.html`, 33
  pantallas; abrírselo en Edge). No preguntarle "¿cambiarías algo?" a secas: no lo entendió. Mostrarle primero.
  (Lo de la nota resuelta ya lo contestó: queda con el tilde verde.)
- **Para la parte 8b (sin internet, con dos puestos):** cuántos puestos va a haber en la puerta y con qué
  (notebooks, o contaba con celulares: los celulares no entran al modo local), en cuál va enchufado el tótem, y si
  en el salón hay un router propio. **No preguntarle si lo quiere:** el 13-oct a la noche preguntó si operar sin
  internet "había quedado", se le dijo que a medias (con una PC sí, con dos no) y lo pidió de nuevo, con todas las
  letras. Se le recomendó además internet de respaldo (un router 4G o el celular); no lo descartó.
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
docs/CONTEXTO_v6.0.0_2026-10-11.md entero (sobre todo "Qué pasó el 13-oct" y
"Lo que falta para publicar"), CLAUDE.md y la memoria del proyecto. El plan
aprobado está en
C:\Users\lover\.claude\plans\donde-nos-quedamos-expressive-nautilus.md.
La 6.0.0 NO está publicada: las PCs siguen con la 5.0.0 y los SQL de la nube no
se corrieron. Va todo en una sola versión, por partes: están hechas la parte 1
(la puerta sigue al sorteo), la 2 (el Excel de acompañantes y música), la 3 (la
nota como ventana al centro) y la 4 (el tótem no se desconecta ni saluda
tarde). Seguí por la parte 5, las cuatro apariencias del tótem
(docs/pendientes/totem-apariencias.md): primero su plan corto y una maqueta, y
avisame al terminar con cómo quedó, un commit y un push. Recepción y el tótem
nuevos también van en la 6.0.0: sus diseños ya están aprobados en
docs/pendientes/.
Todo lo que falta de Recepción y el tótem tiene que andar sin internet con los
datos ya bajados: la regla y lo que cuida cada parte están en
docs/pendientes/modo-local-sin-internet.md (es la parte 8b del camino).
Las muestras con muchas imágenes abrímelas en Edge: el panel de la app no las
muestra. Una imagen suelta sí la veo en el chat.
Contestame primero lo que te pregunto, en una línea. Lo que tiene poco riesgo y
vuelta atrás, recomendalo y seguí: no me lo preguntes como si fuera un peligro.
No corras la app desde el working tree (la v73 migraría la base real). Lo que
toque la base real o la nube, con mi OK en el momento; ya no hay regla de
horario. Para volver atrás en el código está el tag antes-de-6.0.0. Con
"actualizá el contexto", frená y dejá todo anotado.
```
