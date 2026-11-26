# CONTEXTO — la 6.9.4: la planilla del sorteo por número de mesa, y DAR MESA

**Estado (25-nov-2026, noche, 95 %): programada, probada y mostrada, SIN PUBLICAR.** Falta solo que él la mire
y publicar juntos. El usuario la quiere publicar el **26-nov**
("esto lo saco para mañana"), con él. Sale de la rama **`release/6.9.x`** (desde el tag `v6.9.3`, en la carpeta
`..\arguello_events_6.9.x`), como la 6.3.x y la 6.8.x: la rama feature tiene la v83 y lo del 4-dic a medio hacer y
**no se publica de ahí**. Cada commit va también a la feature con `cherry-pick`. Versión `6.9.4+79`. **Sin SQL ni
migración** (la base sigue en la 82). Plan aprobado:
`C:\Users\lover\.claude\plans\donde-nos-quedamos-lucky-pony-of-a093f1a7-a9c1-4e30-b633-861c3baf943d.md`.

## Para retomar en otro chat

### Lo que pidió (25-nov, la tarde del plan del 4-dic, que quedó en pausa)

1. **La planilla impresa del sorteo en orden numérico, de la mesa 1 a la última**, "porque si no imaginate el
   quilombo para ir poniendo qué mesa le tocó a cada chico". En la interna y en la de repartir.
2. **Que el jefe, en modo jefe, le dé la mesa a quien no pagó con un clic en la grilla**, "le salta el número
   automáticamente, como cuando tiene una cuota paga, pero en este caso el jefe decide", **uno por uno o a todos
   juntos**. Caso: una familia de la Técnica con la 107 y "⚠ le falta 1 mesa" en amarillo (los nombres, en
   `build/nombres_6.9.4.md` de la carpeta principal, fuera de git: el repositorio es público).
3. **Qué pasa con la 106 vacía del plano de la Técnica.**

### Lo que se decidió con él (con maquetas en el chat)

- **La planilla:** el cartel suma **Orden: Alfabético · Por número de mesa** (viene en Alfabético). Por número de
  mesa: la hoja del resumen y después todo el salón en una lista, con la columna Mesa primero y la división debajo
  del nombre; **cada mesa adicional tiene su renglón corto en su número** ("Mesa adicional de X · su principal es
  la 12"), así se recorre mesa por mesa sin saltear ninguna. Los sin mesa, al final.
- **La 106:** el programa se la dio sola a una familia el 11-nov (mesa nueva al fondo); el 16-nov el
  jefe lo movió a la 51 y la 106 quedó sin nadie; como el programa nunca reusaba un hueco, a la familia de la 107 le dio la 107
  (24-nov, al pagar $200.000). El usuario: "lo primero sería llenar esa 106". **Solución elegida: la 106 es la
  adicional de la familia de la 107**, que está pegada a su 107 en la misma fila del plano.
- **La principal de esa familia sigue siendo la 107** ("tiene la principal ya figurada como 107"): **la principal pasa
  a ser la primera mesa anotada**, no la de número más bajo. Queda "107, 106".
- **De ahora en más, una mesa nueva al fondo usa primero una del fondo que quedó vacía** (la que da el programa
  solo y DAR MESA). Si varias familias reciben a la vez y hay menos vacías, **el azar** decide.
- La adicional que el jefe da sin pagar **sigue "a confirmar" en la puerta y el tótem hasta que se pague**, como
  toda adicional sin pagar. DAR MESA da el número; no la da por pagada.
- El resultado en la Técnica, con DAR MESA A TODOS: **la familia de la 107 queda 107 + 106 y las cuatro sin nada
  pagado reciben la 42, la 47, la 52 y la 54** (las cuatro fijadas "junior" que el jefe dejó el 10 y 11-nov). Ninguna mesa vacía ni con candado.

### Lo programado (4 commits en `release/6.9.x`)

1. **La principal es la primera anotada** (`60c8531`):
   - `MesasExtraUtils.numerosEnOrdenDelTexto` (los números en el orden escrito) y
     `MesasExtraUtils.conLaPrincipalDeAntes` (lo que se escribe conserva la principal primera).
   - `SalonMesas.principal`, `SalonMesas.enOrdenDelContrato` (ahora el orden escrito) y `SalonMesas.mesasEnOrden`
     (la principal primero, para las sillas: `repartoSillas`, la puerta y las sillas de la noche).
   - **`ContratosRepository.asignarNumerosMesa` es el único lugar por donde se escriben los números** (sorteo,
     mover, intercambiar, deshacer, restaurar, la mesa sola y DAR MESA): ahí se aplica `conLaPrincipalDeAntes`.
   - **No cambia a nadie hoy:** en la nube, las 574 familias con mesa tenían los números de menor a mayor
     (consulta del 25-nov). **En la planilla sí cambian 4 familias de 168 con varias mesas**, las de la principal
     sola y las adicionales juntas en otro lado ("74, 88, 89"): antes la planilla decía principal 88, ahora 74, como
     ya decía la puerta desde el 20-nov. Ninguna tiene sillas extra.
2. **La planilla por número de mesa** (mismo commit): `OrdenPlanillaSorteo`, `RenglonPorMesa`,
   `PlanillaSorteo.porMesa` (`eventos/services/planilla_sorteo.dart`); `_tablaPorMesa` y `_filaAdicional`
   (`common/services/planilla_sorteo_pdf.dart`); `orden` en `construirPlanillaSorteoPdf`/`generarPlanillaSorteo`
   (el archivo suma `_por_mesa`) y en el cartel (`opciones_planilla_sorteo_dialog.dart`, `planilla_orden`).
3. **La cuenta de DAR MESA** (`b8cd3b6`): `MesaQueDaElJefe` (`plano/services/mesa_que_da_el_jefe.dart`), hecha como
   `MesaNuevaSola.calcular`: el sorteo de siempre solo para los elegidos, con ellos tildados "sortear igual" y sin el
   "solo la base"; entrega sus fijadas; solo guarda lo que salió de una fijada. `MesasNuevasAlFondo.vaciasDelFondo`
   (las que se agregaron como mesa nueva —clave `_nuevas` del registro— y hoy no son de nadie) y `planear(vacias:,
   azar:)`: antes de una nueva, la vacía más cerca de las mesas de la familia (la de número más bajo si no tiene).
   **`MesaNuevaSola` también la usa** (solo cambia el número que da, no a quién). El renglón del registro lleva
   `delJefe` (clave `_del_jefe`) y `automatico`: **no cuenta como "el último sorteo"** (quien pague después sigue
   recibiendo su mesa sola) y la lista de PRECIOS lo pone "para revisar" ("se la dio el jefe").
4. **La pantalla** (`1f22c9f`): en la grilla, con el sorteo hecho, quien no tiene mesa dice **"Sin mesa · no
   pagó"** (o "Sin mesa"); quien no tiene todas, el "⚠ le falta 1 mesa" de siempre; las dos con **DAR MESA**
   (`celda_mesa_alumno.dart`). En la barra, **"N · SIN MESA · DAR MESA A TODOS"** abre el cartel
   (`dar_mesa_a_todos_dialog.dart`): todas tildadas, qué mesa recibe cada una (la misma cuenta con lo de esta PC y
   la misma semilla del azar), un solo DAR MESA. `_darMesa` en `detalle_evento_masivo_screen.dart`: con la llave del
   modo jefe, **con internet** (si no: "la otra PC podría dar la misma mesa"), sin mesas de otra PC por bajar, con el
   plano de la nube, los números + el renglón + el plano en una transacción, `trasElSalon` antes de subir, y el
   aviso con **DESHACER** (abre el deshacer de siempre). Sin modo jefe, todo se ve apagado con el motivo.
   `test/solo_modo_jefe_test.dart` y `test/puerta_sigue_al_salon_test.dart` ya nombran `_darMesa`.

### La revisión independiente (25-nov, noche) y lo que se arregló

Un agente aparte leyó el diff sin conocer lo programado. Lo que encontró y cómo quedó:
1. **El PLANO tomaba como principal la primera del tramo más largo** (`OcupantePlano.principalDe`): con "107, 106"
   ponía la P y el apellido en la 106. Ahora `OcupantePlano` lleva `principalAnotada` (`SalonMesas.principal`, desde
   `PlanoDeLaFiesta.ocupanteDe`) y `principalEntre` la usa; `GrupoPuerta` lleva `principal` (también por la central,
   clave `principal`) para el plano de la recepcionista. Las fijadas que esperan familia siguen con la regla de
   siempre.
2. **Mover o intercambiar una sola mesa ordenaba los números**: con "107, 106", mover la 107 dejaba la 106 (sin
   pagar) de principal. Ahora `CambiosDeMesa.reemplazar`: **si los números estaban de menor a mayor (todo lo
   sorteado), quedan de menor a mayor como siempre** (así una PC con la 6.9.3 los lee igual; la primera pasada lo
   hizo en su lugar para todos y rompió tres pruebas de `cambios_de_mesa_test.dart` con razón); **si no** (lo que
   deja DAR MESA), la que entra toma el lugar de la que sale y la principal sigue siendo la principal.
   `CambiosDeMesa.numerosDe` devuelve el orden anotado (el `antes` del renglón también: deshacer la devuelve igual).
3. **Las vacías iban por el orden del azar**: una familia sin mesa podía quedarse con la 106 de al lado de la 107.
   Ahora primero reciben las familias que ya tienen mesa (la más cerca de las suyas) y después las que no tienen.
4. **La mesa que el programa da solo podía dejar una adicional con número más chico que la principal**, y una PC
   con la 6.9.3 la leería al revés. Ahora (`soloSiQuedaEnOrden`) solo toma una vacía con número más alto que las de
   la familia: lo automático siempre queda de menor a mayor. DAR MESA, que es del jefe, sí puede.
5. DAR MESA a una familia cuyo número no está en el plano decía "ya tiene todas": ahora dice también "o su número
   no está en el plano".
6. `_darMesa` sin `catch`: ahora avisa en palabras si falló antes de guardar ("no se cambió nada") o después ("quedó
   guardada en esta PC"). DAR MESA A TODOS no abre dos carteles con un doble toque.
Sin arreglar, a sabiendas: si dos PCs dan la misma vacía en el mismo momento (DAR MESA en una y la mesa sola en la
otra), la que no figura en el plano de la nube la pierde (`_sinRepetidos`) y, si no pagó, queda sin mesa: el jefe
vuelve a tocar DAR MESA. Y la flecha del tótem, con las dos mesas pagas, apunta a la más baja de las dos (son
pegadas). "12, 13" reacomodado a "11, 12" se guarda "12, 11" (la principal de antes sigue primera): da igual.

### Lo último del 25-nov (noche), después de mostrársela

- **La columna MESA de la grilla dice primero la principal** (`SalonMesas.textoMesas`): "107 y 106 (1 extra)"; con
  las adicionales al final, "12 + 67-68 (separada)". Lo sorteado se ve igual que siempre. Sin esto la grilla decía
  "106-107" y parecía que la principal había cambiado.
- El botón de la barra pasó a su propio archivo, `widgets/chip_dar_mesa.dart` (`ChipDarMesa`), para que la muestra
  use el de verdad.
- **Los PDF ya se pueden pasar a imagen en esta PC**: `tool/pdf_a_png.ps1` (PowerShell, con el lector de PDF de
  Windows, `Windows.Data.Pdf`): `& tool/pdf_a_png.ps1 -Pdf <archivo.pdf> -Carpeta <carpeta> [-Ancho 1600]`.
- Capturas mandadas al usuario (en `build/pruebas_6.9.4/` y `build/muestras_6.9.4/` de la carpeta principal, fuera
  de git): la grilla antes (con y sin modo jefe) y después de DAR MESA (`tool/dar_mesa_muestra_test.dart`), el plano
  de la Técnica real antes y después y la planilla por número de mesa de ese después
  (`tool/simulacro_dar_mesa_test.dart --dart-define=datos=<json> --dart-define=salida=<carpeta>`), y las hojas de las
  muestras interna parada y para repartir acostada. **La grilla entera no se puede abrir sin la base**: la muestra
  usa las piezas de verdad (la celda MESA y el botón) con el resto de las columnas resumido.

### Lo que se probó

- Pruebas nuevas: `test/principal_primera_anotada_test.dart` (15, con una SQLite temporal para
  `asignarNumerosMesa`), `test/mesa_que_da_el_jefe_test.dart` (15, la Técnica armada como pasó),
  `test/dar_mesa_a_todos_dialog_test.dart` (5), y grupos nuevos en `test/planilla_sorteo_test.dart` (el orden, las
  adicionales en su número, sin mesa al final, bajas afuera, el PDF en las cuatro hojas leído palabra por palabra,
  que no se sale de la hoja, y que sin elegir sale igual que antes), `test/celda_mesa_alumno_test.dart` (6) y
  `test/opciones_planilla_sorteo_dialog_test.dart`.
- **Simulacro con los datos de verdad de la Técnica** (leídos de la nube en solo lectura el 25-nov y guardados
  fuera de git): `tool/simulacro_dar_mesa_test.dart --dart-define=datos=<json>`. Ver el resultado en "Lo que falta".
- Muestras: `tool/planilla_sorteo_muestra_test.dart` (suma tres PDF por número de mesa) y
  `tool/dar_mesa_muestra_test.dart` (las celdas con y sin modo jefe, el cartel de "a todos" y el de la planilla).

- **Simulacro con la Técnica real** (`tool/simulacro_dar_mesa_test.dart`, con el JSON leído de la nube): DAR MESA A
  TODOS da **107, 106 · 42 · 47 · 52 · 54** (las cinco familias), sin mesas nuevas, igual
  con 50 semillas del azar y de a una familia. La única vacía del fondo es la 106.
- **Roturas a propósito: 24 de 24 detectadas** (`tool/roturas_6.9.4.txt`, `bash tool/romper_una_regla.sh`).
- La suite entera (`bash tool/suite_por_tandas.sh`): 4 fallas la primera vez, las 4 explicadas y corregidas — dos
  tests que buscaban `\n  }\n` y en una carpeta recién creada git deja `\r\n` (ahora los normalizan), y uno que
  esperaba la regla vieja de las sillas con "40, 12, 13".
- Muestras mandadas al usuario el 25-nov: `build/muestras_6.9.4/` de la carpeta principal (tres PDF por número de
  mesa y cuatro PNG), y después las hojas pasadas a imagen con `tool/pdf_a_png.ps1` (se ven bien).

### Lo que falta, en orden

1. Que diga si lo que vio está bien (se le mandó todo el 25-nov a la noche).
2. Lo de esta rama ya está también en la feature (`cherry-pick`, sin conflictos); cada commit nuevo, igual.
3. **Publicar con él (26-nov):** la foto de la mora "antes de 6.9.4"; versión `6.9.4+79` en `pubspec.yaml` e
   `installer/junior_eventos_setup.iss`; el instalador **por pasos** desde `..\arguello_events_6.9.x` (con las tres
   comprobaciones de la página del celular antes de `ISCC`), tag `v6.9.4`, release con el Setup y el APK, novedades
   **"Nuevas capacidades en el modo jefe, y la planilla del sorteo por número de mesa"**, y la web.
4. Después de instalar: la foto "después", CLAUDE.md y la memoria.

### Cuidado

- **No usar DAR MESA hasta que las tres PCs (y la notebook de la puerta) tengan la 6.9.4.** Una PC con la 6.9.3 lee
  "107, 106" con la regla vieja: la principal sería la 106 y la puerta diría que la **107** está "a confirmar" (el
  tótem no la encendería). La planilla por número de mesa no tiene ese problema.
- **El botón SORTEO de siempre**, con "las que faltan en una mesa nueva al fondo", **sigue dando el número que
  sigue**: no reusa las vacías (no tiene el registro a mano). Las reusan DAR MESA y la mesa que el programa da
  solo.
- Lo de las mesas de una familia se escribe siempre por `asignarNumerosMesa`: un camino nuevo que escriba
  `numero_mesa` por otro lado perdería la principal.
