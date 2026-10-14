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
la puerta que sigue al sorteo (hecha), el Excel de acompañantes y música, y Recepción y el tótem nuevos: ver
**"Qué pasó el 13-oct"**, más abajo. Lo de este encabezado es cómo quedó el 11-oct.
- `pubspec.yaml` en `6.0.0+57` y el `.iss` en `6.0.0` (`8ca3598`).
- **El instalador hay que armarlo de nuevo.** El que está en `installer/dist/Setup Junior Eventos v6.0.0.exe` se
  armó antes de lo de las notas (`3b63b55`) y quedó viejo. Se arma con `installer\build_installer.ps1`, unos cinco
  minutos; la carpeta no va a git.
- No hay release `v6.0.0` en GitHub y los dos SQL de la nube no se corrieron.
- El usuario tiene para mirar las pantallas (`build/muestras_6.0.0/Recorrido_6.0.0.html`, 26 pantallas numeradas).
  **Todavía no opinó.**
- **La nota de un alumno: eligió la B**, la ventana al centro (`build/muestras_6.0.0/Nota_dos_opciones.png`). Lo
  dijo al cerrar el chat y pidió dejarlo anotado: **está elegido y sin aplicar.**
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
| 3 | La nota como ventana al centro, y las dos preguntas pendientes | la nota, **hecha el 13-oct**; faltan sus dos respuestas |
| 4 | Tótem: que no se desconecte ni salude tarde (`pendientes/totem-comunicacion.md`) | falta |
| 5 | Tótem: cuatro apariencias (`pendientes/totem-apariencias.md`; una columna en la nube) | falta |
| 6 | Recepción más amigable (`pendientes/recepcion-redisenio.md`) | falta |
| 7 | Modo kiosco (`pendientes/totem-kiosco.md`) | falta |
| 8 | Tótems vinculados (`pendientes/totems-vinculados.md`) | falta |
| 9 | Cerrar la lista de la puerta (`pendientes/rls-invitados.md`; funciones en la nube) | falta |
| 10 | Verificación, documentación, instalador y la web armada | falta |
| 11 | Publicar, instalar, la web, cerrar los permisos y el ensayo | falta |

De la 4 a la 9 son, a ojo, entre 8 y 10 secciones de trabajo como las de la Fase 3. Cada una arranca con su plan
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
como una ventana al centro en vez de la hoja de abajo; el contenido es el mismo. Siguen sin contestar sus dos
preguntas: qué cambiaría de las 26 pantallas del recorrido, y si una nota resuelta deja de llamar la atención en
la grilla.

## Lo que falta para publicar

**No se publica sin su "publicamos".** Antes, las partes 3 a 10 del camino de arriba. Después:

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

- **Las dos preguntas del 11-oct:** qué cambiaría de las 26 pantallas del recorrido, y si una nota resuelta deja de
  llamar la atención en la grilla.
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
(la puerta sigue al sorteo), la 2 (el Excel de acompañantes y música) y la nota
como ventana al centro. Preguntame las dos cosas que quedé debiendo del 11-oct
y seguí por la parte 4 (el tótem), con su
plan corto, y avisame al terminar cada una con cómo quedó, un commit y un push.
Recepción y el tótem nuevos también van en la 6.0.0: sus diseños ya están
aprobados en docs/pendientes/.
Contestame primero lo que te pregunto, en una línea. Lo que tiene poco riesgo y
vuelta atrás, recomendalo y seguí: no me lo preguntes como si fuera un peligro.
No corras la app desde el working tree (la v73 migraría la base real). Lo que
toque la base real o la nube, con mi OK en el momento; ya no hay regla de
horario. Para volver atrás en el código está el tag antes-de-6.0.0. Con
"actualizá el contexto", frená y dejá todo anotado.
```
