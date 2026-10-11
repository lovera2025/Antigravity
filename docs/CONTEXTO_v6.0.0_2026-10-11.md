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

**Estado: programada, verificada y documentada. SIN PUBLICAR.** Las PCs siguen con la 5.0.0.
- `pubspec.yaml` en `6.0.0+57` y el `.iss` en `6.0.0` (`8ca3598`).
- **El instalador hay que armarlo de nuevo.** El que está en `installer/dist/Setup Junior Eventos v6.0.0.exe` se
  armó antes de lo de las notas (`3b63b55`) y quedó viejo. Se arma con `installer\build_installer.ps1`, unos cinco
  minutos; la carpeta no va a git.
- No hay release `v6.0.0` en GitHub y los dos SQL de la nube no se corrieron.
- El usuario tiene para mirar las pantallas (`build/muestras_6.0.0/Recorrido_6.0.0.html`, 26 pantallas numeradas) y
  las dos formas de abrir la nota (`build/muestras_6.0.0/Nota_dos_opciones.png`). **Todavía no opinó.**
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
| "Pasar a la lista de la puerta", **trabado hasta diciembre** | MÁS |
| El recibo reimpreso cuenta bien las cuotas (lo de GAUNA) | Recibos |
| Mi Empresa: lo disponible en efectivo y en transferencia, las extracciones aparte y el bolsillo arreglado | Mi Empresa |
| La cola de subida no pierde un cambio hecho mientras subía el anterior, y lo trabado se reintenta todo junto | Sincronización |
| Editar o borrar una nota de mora condonada ahora llega a la nube y a las otras PCs | Sincronización |

**Lo que no cambia:** cómo se cobra, las cuentas, los saldos, la mora, la caja, la web, Recepción y el tótem. Una
fiesta sin plano sortea igual que en la 5.0.0. **Recepción y el tótem nuevos siguen pendientes, para diciembre**
(`docs/pendientes/PENDIENTES.md`).

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
     (`kNotaComoVentana`, en `nota_operativa_bottom_sheet.dart`);
   - quedó anotado como pendiente que el borrado de una nota no le llega a una PC que estaba cerrada
     (`docs/pendientes/notas-borradas-en-pc-cerrada.md`).

## Lo que falta para publicar

**No se publica sin su "publicamos".** En orden:

1. **Tres cosas que tiene que contestar el usuario:**
   - **las pantallas:** qué cambiaría del recorrido (`Recorrido_6.0.0.html`), por número de pantalla;
   - **la nota, A o B:** como hoy, que sube desde abajo, o como una ventana al centro (`Nota_dos_opciones.png`). Si
     elige B, es pasar `kNotaComoVentana` a `true`;
   - **la nota resuelta:** se le ofreció que deje de llamar la atención en la grilla (el ícono en gris clarito) sin
     borrarse. Preguntó si convenía que "desaparezca"; se le recomendó no borrarla sola. No contestó.
2. **Armar de nuevo el instalador** (`installer\build_installer.ps1`), después de lo que cambie en el punto 1. Antes,
   la suite entera y `flutter analyze`.
3. **Los dos SQL en la nube, con su OK en el momento** (un domingo sin cobros o después de las 20 hs). Antes y
   después de cada uno, los conteos: el 11-oct daban **643 contratos, 3.963 pagos, 26 notas, 7 invitados y 30
   eventos**, y tienen que dar igual. Después, las consultas de verificación del final de cada archivo (RLS
   prendida, un trigger de insert y uno de update por tabla, la policy, y ninguna en Realtime).
4. **El release:** `powershell -File tool/publish_windows_release.ps1 -SoloNotas -NotesFile build\novedades_6.0.0.md`.
   Crea el tag `v6.0.0` sobre la rama y sube el instalador. El texto de novedades (cinco renglones, acortado a
   pedido) está también en el CONTEXTO de la Fase 3. No nombra lo de las notas: si el usuario quiere, se suma un
   renglón. `build/` no va a git: si el archivo no está, se arma de nuevo desde el CONTEXTO.
5. **Instalar:** primero la PC del usuario, para probarla; después la del operario y la de la oficina. Al abrir, la
   app saca sola la copia y actualiza la base.
6. **Mientras una PC tenga la 5.0.0 y otra la 6.0.0** se cobra normal. **No se sortea ni se entregan entradas
   hasta que todas tengan la 6.0.0**: la 5.0.0 no ve el plano, los repartos ni las entregas.
7. **Después de instalar:** mirar en la nube que las tablas nuevas reciben filas y que la cola de subida queda en 0.
8. Poner acá el estado en "publicada", con el tag y la fecha, y la memoria al día.

## Lo que sigue esperando del usuario (no frena publicar)

- La página 6 del Canva: la Normal ya tiene **137 mesas cargadas** (116 con lo pagado el 11-oct), y su armado del
  Canva tiene la hoja B provisoria. Mientras tanto está el armado a medida del playón, y las mesas que falten se
  agregan en Acomodar.
- Los cuatro lados del playón medidos con cinta (hoy son 30, 46 y 39 m, a ojo del satélite).
- Las respuestas del jefe: qué armado usa cada escuela, las numeraciones, el pasto, y por división o entera.
- La fecha del sorteo.
- Cerca del sorteo: volver a sacar el control de mesas y sillas y verlo con él, nombre por nombre.

## Para seguir en otro chat, pegar

```text
Seguimos con la 6.0.0 de Junior Eventos. Leé primero
docs/CONTEXTO_v6.0.0_2026-10-11.md entero (sobre todo "Qué pasó el 11-oct, en
orden" y "Lo que falta para publicar") y la memoria del proyecto. Está todo
programado, verificado y documentado, hasta 3b63b55, con 1.712 tests en verde y
el working tree limpio. NO está publicada: las PCs siguen con la 5.0.0 y los
dos SQL de la nube no se corrieron.
Antes de seguir, preguntame tres cosas que quedé debiendo: (1) qué cambiaría de
las pantallas del recorrido (build/muestras_6.0.0/Recorrido_6.0.0.html, por
número); (2) si la nota de un alumno se abre como hoy, desde abajo, o como una
ventana al centro (build/muestras_6.0.0/Nota_dos_opciones.png); (3) si una nota
resuelta deja de llamar la atención en la grilla.
Después: armá de nuevo el instalador (el que hay quedó viejo), y para publicar
seguí los pasos del CONTEXTO, frenando en los dos SQL de la nube y antes del
release para pedirme el OK. Instalo primero en mi PC, después el operario y la
oficina.
Trabajá por secciones: avisame cada cosa que termines y cómo quedó, con un
commit y push por paso, y cuando te diga "actualizá el contexto" frená y dejá
todo anotado. Contestame primero lo que te pregunto, en una línea. No corras la
app desde el working tree (la v73 migraría la base real). Lo que toque la base
real o la nube, con mi OK en el momento. Para volver atrás en el código está el
tag antes-de-6.0.0.
```
