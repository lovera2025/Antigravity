# La 6.5.0: la puerta ve el plano, sillas sueltas, chat entre puestos, mesas lejos, la planilla parada, el recibo de particulares y los profes (sin publicar)

9 y 10-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. **Programada y probada, sin publicar.** Sin SQL. **La versión sigue diciendo
`6.4.0+66`**: el número nuevo se pone al publicar, con el usuario (lo dijo el 9-nov: "Aún no publiques hasta que yo diga"; y antes,
"se publica con mi orden y o yo presente"). El plan del 9-nov es `docs/PLAN_PUERTA_PLANO_Y_SORTEO_2026-11-09.md`; lo del 10-nov salió
de una charla con el usuario desde el celular y no tiene plan aparte: está todo acá.

## Para retomar en otro chat

**Dónde estamos (10-nov, tarde):** las etapas 0 a 9 están programadas, con sus tests y guardadas en la rama. **Falta una sola cosa por
programar: la Encargada de barra con su PIN en la web del iPhone** (abajo, "Pendiente · La Encargada en la web": está pensada, no
empezada). Después, publicar, cuando el usuario esté en su casa y diga "publicá".

**La 6.4.0 ya está instalada en las tres PCs** (lo confirmó el usuario el 10-nov) y en su celular Android (Redmi Note 14 Pro, con el APK
del release). **La foto de la mora "después de 6.4.0" no se sacó todavía:** es el paso 0 de publicar.

Lo que lleva la 6.5.0, en una línea cada uno:

Del 9-nov (probado en el sandbox con dos celulares y la PC):
- **El modal del cobro se cierra apenas el pago queda guardado** (etapa 0, `a5458f6`).
- **La recepcionista ve el plano** en la PC y en el celular: VER EN EL PLANO, VER LA LLEGADA y "Ver el plano entero" (etapa 1, `50065e7`).
- **Sillas sueltas:** la barra vende "Silla suelta" y la puerta la anota con SILLA SUELTA, sin tope (etapa 2, `84a9361`).
- **El chat de la puerta:** CHAT, se elige a quién y salta "Juli, a vos: …" (etapa 3, `695c64c`, `cf991ae`).
- **Las mesas de más van lejos:** una familia con más de 3 mesas viene tildada sola, y "Donde yo elija" abre el plano para tocar la zona
  (etapa 4, `e654fb0`).

Del 10-nov (cada uno con su muestra mirada y sus tests; **sin recorrido con el mouse ni con celulares**):
- **La planilla del sorteo sale parada** (vertical) y se lee en papel; el cartel pregunta "La hoja: Parada · Acostada" (etapa 6, `e2c7888`).
- **El recibo de un evento particular sale entero:** el encabezado ya no se sale de la hoja, tiene margen y entra en una hoja (etapa 7,
  `b4c19cb`). El encabezado del presupuesto llevaba el mismo defecto y el mismo arreglo.
- **Una mesa del plano se reserva para quien no es alumno (los profes)**, con los nombres de quienes se sientan (etapa 8, `75a3307`).
- **Los profes aparecen en Recepción y el tótem los saluda con su mesa**, igual que a un alumno (etapa 9, `c1df048`).

**La revisión del 10-nov, antes de tocar nada:** `flutter analyze` sin errores en la app (los 3 que da son de `tool/_tmp_espindola_audit.dart`,
un script viejo que no está en git) y **4.108 tests en verde** sobre `cf991ae`. Leídos enteros, sin encontrar fallas: el cobro
(`a5458f6`), el sorteo (`e654fb0`: sin tildar nada da lo mismo que la 6.4.0), las sillas sueltas (`84a9361`: la nube no tiene CHECK en
`sillas_puerta.mesa`) y la central del chat. **No se leyeron línea por línea** las pantallas nuevas (`hoja_plano_puerta.dart`,
`hoja_chat.dart`): las cubren sus tests y la prueba del sandbox del 9-nov.

**Lo que hay que saber antes de publicar:**
- **Los sorteos empezaron el 10-nov con la 6.4.0:** nadie viene tildado y no hay "Donde yo elija"; las familias con más de 3 mesas se
  tildan a mano. La planilla de la 6.4.0 es la acostada: se imprime eligiendo orientación **Horizontal**.
- **No crear el producto "Silla suelta" ni usar SILLA SUELTA hasta que las PCs y las tablets tengan la 6.5.0.**
- **No reservar una mesa para alguien ("Es para alguien") hasta que las tres PCs tengan la 6.5.0.** Una PC con la 6.4.0 la ve como una
  mesa libre con el motivo "Reservada para Profes: …" (no rompe nada), pero no pone a los profes en Recepción ni en el tótem. La mesa
  para los profes **sí se puede dejar hoy** con la 6.4.0: Agregar mesa y Dejar libre con el motivo "Profes"; en el papel sale tachada.
- **La Encargada de barra, en un iPhone, hoy no entra con su PIN** (ver el pendiente). En un Android o en una PC, sí, completo.
- **Los commits del 10-nov están subidos a GitHub** (rama feature), sin release.

**Lo que NO se probó y hay que mirar** (regla del usuario: las pruebas de punta a punta las hace Claude, en un sandbox):
- **El recorrido con el mouse** de la mesa reservada en `tool/plano_prueba.dart`: agregar una mesa después de un sorteo, "Dejar libre" →
  "Es para alguien", ver "GARCÍA +3" debajo de la mesa y la lista al tocarla, "Para quién es", y que SORTEO no se la dé a nadie. Los
  tests lo cubren pieza por pieza y el papel se miró; **la pantalla del plano con la reservada no se vio**.
- **Los profes con celulares:** `tool/central_prueba_test.dart` con un plano que tenga una mesa reservada, y dos pestañas de celular:
  buscar a un profe, INGRESAR, VER EN EL PLANO. La lista del celular sale de la misma `PuertaDelEvento`, y el test de ida y vuelta por
  JSON pasa; con la central de verdad no se corrió.
- **El tótem del salón (la ventana) saludando a un profe:** se vio VER LA LLEGADA en la muestra (`tool/puerta_plano_muestra_test.dart`,
  `8_profes_llegada_PC.png`), que usa la misma escena; la ventana de verdad, no.
- **La página del celular compilada** (`flutter build web -t lib/puesto_main.dart`): ahora importa `reservados_de_la_puerta.dart`. No
  tiene nada que el navegador no pueda (ni `dart:io` ni la base), pero no se compiló.
- **En papel de verdad, nada:** la planilla parada, el recibo y el plano se miraron pasados a imagen. Cómo salen en la Epson L495 de la
  oficina lo dice una foto del usuario.
- El sonido del aviso del chat en la notebook, la vibración en un Android y el chat por el router del salón (del 9-nov).

**Publicar, paso a paso (cada paso con su OK y con el usuario presente; él dijo el 10-nov que publica al llegar a su casa):**
0. Con él en la PC, **el sonido y la vibración del chat** (5 minutos): `flutter run -d windows -t tool/central_puerta_prueba.dart` y su
   Android por el wifi de su casa. Si fallan, el cartel sale igual; se arregla antes de armar el instalador.
1. **Cerrar la 6.4.0:** foto de la mora "después de 6.4.0" (`supabase/mora_fotos.sql`) y la comparación con "antes de 6.4.0": vacía.
2. Foto de la mora **"antes de 6.5.0"**.
3. **Sin SQL.** La silla suelta es la mesa 0, el chat vive en la memoria de la notebook, la zona va en el registro del sorteo (`_zonas`),
   y la mesa reservada y sus nombres, en el motivo de la mesa libre.
4. `flutter analyze` y `flutter test` enteros.
5. Versión **`6.5.0+67`** en `pubspec.yaml` y `#define MyAppVersion "6.5.0"` en `installer/junior_eventos_setup.iss`. Novedades
   (propuesta, elige el usuario): **"La puerta ve el plano, chat entre puestos, la planilla parada y la mesa de los profes"**, en
   `build/novedades_6.5.0.md`.
6. `powershell -File installer\build_installer.ps1`, sin redirigir el stderr (necesita `android\key.properties`): Setup y APK firmado en
   `installer\dist`, con la página del celular (`{app}\puesto`) adentro.
7. Tag `v6.5.0` y push. Release: `tool/publish_windows_release.ps1 -SoloNotas -NotesFile build/novedades_6.5.0.md`. La web a Vercel.
8. Instalar las tres PCs y la tablet, y abrirlas.
9. Foto "después de 6.5.0" y la comparación: vacía.
10. Recién ahí: el producto "Silla suelta" en el catálogo, y reservar la mesa de los profes con "Es para alguien".

> Frase para retomar: "Seguimos con la 6.5.0: leé 'Para retomar en otro chat' de docs/CONTEXTO_v6.5.0_2026-11-09.md. Falta la Encargada
> de barra en la web del iPhone y las pruebas que quedaron sin hacer; después, publicar."

## Etapa 0 · El modal del cobro

**Lo que pasaba** (lo contó el usuario el 9-nov): a veces, después de CONFIRMAR PAGO, salía el recibo pero el modal seguía abierto, y
había que tocar CANCELAR con el pago ya hecho. Entre guardar el pago y cerrar el modal se esperaba la subida a la nube, la relectura de
la ficha y las preferencias del medio de pago. Con internet lento, el modal quedaba en GUARDANDO. Si alguno fallaba, caía en el mismo
aviso que un guardado fallido ("No se pudo guardar el cobro. Reintentá"), y reintentar cobraba dos veces.

**Ahora:** apenas vuelve `registrarPagosLote`, se cierra el modal del cobro (`cerrarRuta`: ese modal y no otro que se haya abierto
encima). Lo de después va cada paso por su lado (`DespuesDeGuardarCobro.correr`, `eventos/services/despues_de_guardar_cobro.dart`): si
uno falla, los demás corren igual, y queda escrito en `Documentos\Junior Eventos\cobros_despues_de_guardar.txt`. La subida no se espera:
si falla, la sube la próxima vuelta de la cola. `test/cobro_cierra_al_guardar_test.dart` lee el handler y falla si vuelve un `await`
entre guardar y cerrar.

## Etapa 1 · La puerta ve el plano

- **Qué decide:** `SalonParaLaPuerta` (`recepcion/services/plano_de_la_puerta.dart`): el armado y la config del tótem de la noche.
  `deLaFamilia` y `llegadaDe` usan `PlanoDeLaLlegada` y `ContenidoBienvenida.armar`, lo mismo que la tele. `entero` arma `SalonEntero`,
  con quién ya entró y las familias que faltan.
- **En la PC**, el salón sale de `salonDeLaPuertaProvider` (el plano de la fiesta y la config del tótem). **En el celular**, la notebook
  se lo manda por el wifi al conectarse (`{'t': 'salon'}`, `CentralPuerta.ponerSalon`), sin la foto ni el fondo del tótem
  (`cfgParaElCelular`): sin internet no bajan.
- **Las hojas** están en `recepcion/widgets/hoja_plano_puerta.dart`. `HojaPlanoFamilia` usa el mismo panel de la tele. En un celular,
  si la mesa queda chica, arranca acercada sobre ella y se mueve con los dedos (`_PlanoAcercado`). VER LA LLEGADA pasa la escena del
  tótem y vuelve. `HojaPlanoEntero` tiene Todas o Faltan entrar, y tocar una mesa abre esa familia.
- **ADENTRO va por hora, el último arriba** (`PuertaDelEvento.buscar`): es a quien está saludando la tele.

## Etapa 2 · Sillas sueltas

- **La regla:** una silla suelta no va a una mesa. No cuenta para el tope de 2 extra por mesa, se compra aunque la familia esté en el
  tope, y se paga en la barra con su vale.
- **Sin SQL: `sillas_puerta.mesa = 0` es suelta** (`SillaPuerta.mesaSuelta`, `esSuelta`). Ningún armado numera una mesa 0.
- **En la barra**, el producto se llama "Silla suelta" (`esSillaSuelta`: "silla" y "suelta" en el nombre). Sale una por vale y el pie
  dice "Silla suelta: no va a la mesa". El cierre de la caja, CAJAS y el cierre por sector la cuentan aparte (`sillasSueltas`).
- **En la puerta**, SILLA SUELTA abre `HojaSumarSilla` en modo suelta: solo el vale, sin "¿A qué mesa?". Pasa por el mismo candado
  (`decidirSilla` con `DatosSilla.suelta`): el vale no puede estar anulado ni usado. Queda "+1 silla suelta · vale …", con QUITAR como
  las otras. El aviso del tope dice "Una silla suelta, sí".

## Etapa 3 · El chat de la puerta

- **Vive solo en la memoria de la notebook** (`ChatDeLaNoche`, tope 200): si se reinicia, se vacía. Sin tabla ni nube: anda sin
  internet, por el wifi del salón.
- **Se elige a quién:** Todos, o una recepcionista. `ChatDelPuesto` (`recepcion/chat/`) lleva las conversaciones y los sin leer de cada
  puesto. En la PC lo arma `CentralDeLaPuerta` con el nombre de quien opera; en el celular, `ClienteCentral`.
- **Cada mensaje llega solo a quien le toca**, y quién lo mandó lo dice la conexión, no el mensaje (nadie escribe con el nombre de
  otro). Al conectarse, el celular recibe lo suyo de la noche, ya leído.
- **La lista de puestos se manda al que llega y a los demás solo cuando cambia.** En el sandbox se vio que salía en cada latido, cada
  5 s (`_ultimosPuestos`).
- **El aviso:** "Juli, a vos: …" arriba de la lista (`AvisoDelChat`), con sonido en la PC y vibración en el celular Android. El botón
  CHAT va en el `AppBar` de Recepción con la central prendida, y en la cabeza del celular. **El número sin leer va adentro del botón:**
  afuera, encima, se comía el toque (visto en el sandbox).

## Etapa 4 · Dónde van las mesas lejos

- **El cartel avisa solo:** una familia con más de 3 mesas (`kMesasJuntasEnElSorteo`) viene tildada con las de más separadas, con un
  aviso arriba y la explicación en su renglón. Se puede destildar o cambiar cuántas.
- **"Donde yo elija"** (`DistanciaLejos.enLaZona`): ELEGIR EN EL PLANO abre `ElegirZonaDialog` encima del cartel. Se tocan mesas libres;
  una ocupada, fijada o libre a propósito no se deja tocar y dice por qué.
- **El motor:** con zona, las candidatas de la zona van primero (`_ordenLejos`). Si la zona está fuera de "hasta qué mesa", igual entra
  (`fueraDelRango`). Si se llena o toca a la familia, va lo más lejos que se pueda, y el aviso lo dice.
- **La mesa comprada después del sorteo** se puede pedir lejos de las suyas, en vez de pegada.
- **Con dos familias con lejos en un salón justo**, el sorteo busca unas mesas más (`_minimaConLejos`) en vez de decir que no entra.
  Pasaba también antes (se comprobó en la versión anterior).
- **Registro:** la zona va en `resultado` con la clave `_zonas`. Una versión vieja la ignora. Sin tocar `sorteos_mesas.tipo`.

## Etapa 5 · La prueba en el sandbox

Hecha el 9-nov con `tool/central_prueba_test.dart`: la central de prueba con un evento inventado, el salón y la PC en el chat como
"Pato". Contesta "recibido" y a los 30 s escribe a todos. Dos celulares en el navegador de la app: Juli en `127.0.0.1:8799` y Vero en
`localhost:8799`. Sin la base real ni Supabase.

Anduvo, de punta a punta:
- VER EN EL PLANO y VER LA LLEGADA en el celular;
- SILLA SUELTA con una familia en el tope (la central anotó la mesa 0 con el vale 2-51);
- la lista de a quién hablarle, un mensaje a una sola (la otra no lo vio) y uno a todos;
- el aviso con RESPONDER, y la respuesta de la PC.

Encontró dos cosas, arregladas: el número sin leer se comía el toque, y la lista de puestos salía en cada latido.

**Visto, no arreglado:** en el navegador con mouse, el primer clic después de escribir en un campo a veces no hace nada. Es de Flutter
web y pasaba antes. Con el dedo, en un celular de verdad, ya estaba resuelto (`onTapUpOutside`).

**Queda para la instalación:** el sonido del aviso en la notebook, la vibración en un Android de verdad y el chat con el router del
salón. Necesitan el aparato, no código.

**Muestras:** `tool/puerta_plano_muestra_test.dart`, `tool/chat_puerta_muestra_test.dart` y `tool/zona_sorteo_muestra_test.dart`.

## Etapa 6 · Las hojas del sorteo, en papel (10-nov)

**Lo que contó el usuario:** "en pantalla se ve todo bien pero a veces en impresión no se puede apreciar la calidad", y pidió que salgan
bien en vertical. La impresora de la oficina es una **Epson L495** (tinta, A4; las de esa línea dejan sin imprimir unos 3 mm por lado: el
margen de 7 mm de las planillas alcanza).

**La prueba** (cada hoja pasada a imagen como la ve la impresora, con datos inventados): la planilla **acostada**, en una impresora puesta
en vertical, sale a media hoja con la letra al 70 % ("ajustar a la hoja") o cortada a la derecha, sin Teléfono, Música ni Observaciones
(tamaño real). Y las líneas entre renglones (`#D6DAE0`, 0,4 pt) y la mesa en verde casi no se marcaban.

**Ahora:**
- **La planilla del sorteo tiene dos hojas: parada y acostada** (`PlanillaSorteoPdf.construir(vertical:)`). El cartel
  (`opciones_planilla_sorteo_dialog.dart`) pregunta "La hoja: Parada · Acostada", **con Parada elegida**. Parada lleva lo mismo con la
  letra del mismo tamaño: los acompañantes debajo del egresado, el reparto debajo de las sillas y, en la interna, la música debajo del
  teléfono (`_filaVertical`, `columnasVertical`). Entran 21 alumnos por hoja (acostada, 17). El resumen va con las tarjetas de a cuatro y
  las tablas de "a quién llamar" a todo el ancho.
- **Los grises, los fondos y las líneas de `PlanillaTema` van un paso más oscuros** (las líneas de 0,4 a 0,6 pt). Vale para la del
  sorteo, la de entrega y el pie del plano.
- **La planilla de entrega y el plano siguen acostados:** la de entrega tiene la columna para escribir a mano el nombre de quien retira,
  y el plano sigue la forma del salón. Se imprimen eligiendo orientación Horizontal.

Tests: `test/planilla_sorteo_test.dart` (grupo "la hoja parada": el tamaño de la hoja, que lleve lo mismo, los títulos repetidos al
seguir en otra hoja) y `test/opciones_planilla_sorteo_dialog_test.dart`. Muestra: `tool/planilla_sorteo_muestra_test.dart`
(`…_parada.pdf`).

## Etapa 7 · El recibo de un evento particular (10-nov)

**Lo que contó el usuario:** el recibo de los particulares salía recortado, "el encabezado es como que no sale bien". Es
`PdfService._buildDocument` (RECIBO DE CUENTA y COMPROBANTE DIGITAL, desde `detalle_evento_particular_screen.dart` y Mi Empresa), el
único recibo que seguía armado a la manera vieja.

**Reproducido** con `tool/recibo_particular_muestra_test.dart`:
- **El encabezado se salía de la hoja por la derecha.** A la derecha iba un `pw.Column` sin `pw.Expanded`: **en una fila del paquete
  `pdf`, un hijo sin `flex` no tiene tope de ancho y el texto no baja de renglón.** Con festejado y solicitante de nombres comunes, la
  frase "Este evento fue diseñado para …, a solicitud de …" pasaba del ancho y, como la columna se alinea a su renglón más ancho, se
  llevaba afuera la etiqueta RECIBO DE CUENTA y "Emitido".
- **Con 15 filas** entre pagos y servicios, el encabezado quedaba solo en la hoja 1: todo el cuerpo era un solo bloque que no se partía.
- **Con 30 filas no se podía armar** (`TooManyPagesException`; en la app instalada el freno es un `assert` y no corre: no termina nunca).
- La hoja iba sin margen, y las letras se bajaban de internet (`PdfGoogleFonts`).

**Ahora:** el encabezado baja de renglón dentro de la hoja (`pw.Expanded`); la hoja tiene margen (28 y 24 pt); el encabezado, las tablas
y el pie son hijos directos del `pw.MultiPage`, así las tablas se parten por filas con sus títulos repetidos; **entra en una hoja
siempre que puede** (`_ajustarParaPaginas(maxPaginas: 1)` con la escalera de `AjustePdf`: con 30 filas, una hoja); y las letras salen
de la app (`_fuentesOutfit`). `PdfService.construirReciboParticularPdf` devuelve los bytes, para los tests y la muestra.
**`_buildHeaderElite`** (presupuesto, préstamo, rentabilidad y cierre) tenía el mismo defecto y lleva el mismo arreglo; con textos cortos
se ve igual que antes.

**Para los tests quedó `palabrasDelPdf`** (`test/helpers/leer_pdf.dart`): dice dónde cae cada palabra en la hoja y cuánto mide, siguiendo
los `cm` del contenido. Sirve para comprobar que nada se salga del margen: un texto que se sale no da error. Solo con la letra de fábrica
del paquete (`letrasDeLaApp: false`). `test/recibo_particular_test.dart`; **rotura a propósito:** sin el `Expanded`, falla con
`"RECIBO" termina en 641, fuera de la hoja`.

## Etapa 8 · Una mesa reservada para quien no es alumno (10-nov)

**El pedido del jefe**, contado por el usuario: después del sorteo quiere agregar una mesa "que no es de los alumnos", para los profes;
se la regala la empresa, sin contrato ni pago, y la quiere dejar acomodada en el plano, con los nombres de quienes van.

**Es una mesa libre que dice para quién es.** No es un alumno: nada en `contratos_alumnos`, ni en pagos, ni en entradas.
- **Va todo en el motivo de la mesa libre** (`MesaLibre.motivo`, en `planos_evento.config`), como texto:
  `Reservada para Profes: GARCÍA, ANA; LÓPEZ, LUIS`. Lo lee y lo arma **`ReservaDeMesa`** (`plano/modelo/reserva_de_mesa.dart`).
  **Sin claves nuevas:** una PC con una versión anterior la ve como una mesa libre con su motivo, y no pierde nada al guardar.
- **Tiene que empezar con "Reservada para".** Una libre con otro motivo ("Columna", "Paso de mozos") no es una reserva: no se usa y sigue
  tachada. **La coma no separa los nombres** (se escriben "GARCÍA, ANA"): separan el punto y coma y el renglón.
- **El cartel** (`reserva_de_mesa_dialog.dart`): "Dejar libre" pregunta **No se usa · Es para alguien**; en el segundo, para quién y, si
  se quiere, quiénes se sientan, uno por renglón. Una mesa libre tiene además **"Para quién es"** (`_editarLibre`,
  `CambiosDeMesa.cambiarMotivoDeLibre`), para cambiarlo después. Todo pasa por `_cambiarConfig`: solo en modo jefe.
- **En el plano de la pantalla**, debajo de la reservada van los nombres en un renglón ("GARCÍA +3", `ReservaDeMesa.rotuloEnPantalla`;
  pedido del usuario: "en vez de decir profe, que digan los nombres, con posibilidad de desplegar") y la lista entera se despliega al
  tocarla. **En el papel**, debajo va "PROFES", sin la tachadura, y la lista sale al pie de su hoja; la leyenda distingue "Libre: no se
  usa" de "Reservada: no es de un alumno".
- **El sorteo no se la da a nadie**, tampoco al sortear a los que faltan: para el sorteo es una libre más.
- `InfoMesa.reservada`, `quienesEnUnRenglon`, `nombreDeReservada` (papel) y `rotuloDeReservada` (pantalla). Una reservada que quedó
  ocupada o fijada es un conflicto y no se muestra como reservada.

Tests: `test/reserva_de_mesa_test.dart` (19). Muestra del papel: `tool/plano_pdf_muestra_test.dart`, "a medida del playón".

## Etapa 9 · Los profes en Recepción y en el tótem (10-nov)

**El pedido del usuario:** que los nombres "también salten en el buscador con su animación de dónde está ubicada, igual que los alumnos".

- **Salen del plano:** `reservadosDeLaPuerta(eventoId, plano)` (`recepcion/services/reservados_de_la_puerta.dart`) da uno por nombre de
  cada mesa reservada. **Una reserva sin nombres no pone a nadie en la puerta.**
- **El id de su fila es fijo** (`idInvitadoReserva`: la fiesta, la mesa y el nombre sin mayúsculas ni acentos). **La fila se crea al
  marcar el ingreso** (`ingresarDesdeLaPuerta`), como la de un alumno antes del sorteo: anda sin internet y no hay nada que armar ni
  que limpiar en `PuertaAlDia`. Corregir una letra del nombre es otra persona: quien ya había entrado con el nombre viejo queda en la
  lista como cargado a mano (no se esconde a nadie).
- **En Recepción** (`PuertaDelEvento.masivo(reservados:)`): **un grupo por mesa**, con todos los que se sientan; `GrupoPuerta.reservadaPara`
  es la distinción ("PROFES", marcada en ámbar en `PanelPuerta`). No son alumnos ni acompañan a nadie; `contratoId` es null, así que
  **no hay SUMAR SILLA ni SILLA SUELTA** (`decidirSilla` lo rechaza). Viaja al celular en el JSON de siempre (clave `reservada`; una
  central de antes no la manda y son una familia más).
- **Lo lee `reservadosDeLaPuertaProvider`**: cuando baja un cambio del plano de la otra PC y cada minuto (lo que el jefe cargó en esta
  misma PC). No frena la lista: mientras se lee, Recepción va sin ellos.
- **En el tótem:** `armarFichaTotem(leerReservados:)` (la ventana) y `TotemLocal` (por `puertaDelEventoProvider`). `PersonaFicha.grupo`
  ("Profes", clave `g`) va en la tarjeta donde un acompañante dice a quién acompaña; los de una misma mesa comparten `familia`, así que
  si llegan juntos se los saluda juntos. La mesa encendida y el camino salen solos: la ficha trae su mesa.
- **En el plano de la recepcionista** (`SalonEntero`), su mesa lleva "GARCÍA +3" y tocarla abre el grupo.
- **El tótem de la web (`?totem`) no tiene ficha:** ahí el profe se saluda con el nombre, sin mesa (su fila sube sin mesa, como la de
  un alumno).

Tests: `test/reservados_de_la_puerta_test.dart` (19) y `test/panel_puerta_test.dart` (grupo "una mesa reservada…": se monta Recepción
de verdad, se busca a un profe y Enter lo ingresa con su id fijo). Muestras: `tool/puerta_plano_muestra_test.dart` (6 a 8).

## Pendiente · La Encargada de barra con su PIN en la web del iPhone

**Decidido con el usuario el 10-nov, sin empezar.** La chica a cargo de la barra puede terminar usando un iPhone: "que el iPhone se
pueda loguear con su PIN de encargada desde la web… y de última, si quiere vales de sillas, que use una tablet".

**Por qué hoy no anda:** el PIN de operador se busca en la base del equipo (`OperadoresCajaRepository.findByPin`, SQLite), que en la web
no existe; y `BarraHomeScreen` abre por `barraDeLaCajaProvider` (`BarraLocal`). Lo que el usuario vio en el navegador el 8-nov ("Romi
7777") era la ventana de prueba (`tool/barra_prueba_web.dart`, en memoria), no la web de verdad. En la web de hoy, la barra del iPhone es
la del jefe: cuenta, MODO JEFE, BARRA → CAJAS.

**Cómo queda para ella:** el jefe deja la web abierta con la cuenta en su iPhone, una vez. Ella toca OPERADOR, pone su PIN y entra
derecho a la barra: elige la fiesta y ve **LAS CAJAS** (los totales, una tarjeta por caja, el stock, cada venta) y **anula con motivo, a
su nombre**. No ve catálogo, precios ni el panel. **No vende ni imprime** (el navegador no usa el Bluetooth de la impresora).
**Necesita internet en el salón:** el iPhone ve lo que las tablets ya subieron a la nube; la central (la red del salón) no llega al
navegador. No hay app para iPhone (haría falta una Mac y la cuenta de Apple paga).

**Cómo hacerlo, sin SQL** (`operadores_caja` y `permisos_operador` ya están en la nube, con permiso para quien tiene la cuenta):
1. **El PIN por la nube, solo en la web.** Con la única llave `enLaWebProvider` (`barra/providers/barra_del_jefe_provider.dart`),
   `AppRoleNotifier.buscarOperador` lee de `supabaseProvider`: `operadores_caja` (pin y activo; **en la nube `activo` es booleano**, y
   `OperadorCaja.fromMap` lo lee como entero) y `permisos_operador` (por `operador_id`), y arma `PermisosEfectivos`. Sin el operador del
   modo jefe (`esOperadorModoJefeId`). Detrás de un provider propio, para que los tests lo reemplacen.
2. **En la web entra solo la encargada.** `OpcionesDeEntrada` (`caja_sesiones/services/entrada_de_operador.dart`): con
   `encargadaBarra`, derecho a la barra; Cobros, Entradas y la cajera de barra, un aviso ("Desde el navegador no se cobra ni se vende:
   usá la app").
3. **`BarraHomeScreen` en la web** (otra pantalla, chica): las fiestas de `eventosDeLaBarraProvider` (`BarraNube.eventos()`), y al tocar
   una, `LasCajasScreen`, que ya usa `barraDelJefeProvider` (`BarraNube` en la web) y la llave `mandaEnLaBarraProvider`. Sin la impresora,
   sin "Todo subido" (`puestaAlDiaBarraProvider` es de `BarraLocal`) y sin VENDER. SALIR, como siempre.
4. **La anulación a su nombre:** revisar `quienEsElJefe(ref)` en `cajas_de_la_fiesta.dart` (la etapa 8 de la barra dice que en la web
   quien firma es "Jefe").
5. **Tests:** con `enLaWebProvider` en `true` y la nube de prueba: entra la encargada, no entra la cajera, anula a su nombre y nunca
   arma el panel (`test/modo_barra_cerrado_test.dart` tiene que seguir en verde). **Recorrido en el navegador a 375 px con la web
   compilada de verdad** (`flutter build web -t …` y un servidor estático, como en la etapa 8 de la barra: el compilador de desarrollo se
   cae con este proyecto).

## Visto el 10-nov, sin tocar

- **En Android, los botones que arman un PDF abren la pantalla de imprimir**, que se pone a buscar impresora, en vez de mostrarlo: casi
  todos hacen `Printing.layoutPdf` cuando no es Windows (unos veinte lugares de `pdf_service.dart`). Los papeles de la barra no:
  van por `PdfService.entregarPdf`, que en Android comparte. Si se arregla, es pasar los demás por ahí.
- **Instalar el APK en un Xiaomi:** abierto desde WhatsApp o Drive, el teléfono lo trata como un documento y ofrece imprimir. Se baja
  con Chrome desde el link directo del release y se abre desde el Administrador de archivos (anduvo en el Redmi Note 14 Pro del usuario).
- **El encabezado del plano en papel** sigue diciendo "2 libres" cuando una es reservada.
