# La 6.5.0: la puerta ve el plano, sillas sueltas, chat entre puestos y dónde van las mesas lejos (sin publicar)

9-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. **Programada y probada, sin publicar.** Sin SQL. **La versión sigue diciendo
`6.4.0+66`**: el número nuevo se pone al publicar, con el usuario (lo dijo el 9-nov: "Aún no publiques hasta que yo diga"; y antes,
"se publica con mi orden y o yo presente"). El plan aprobado es `docs/PLAN_PUERTA_PLANO_Y_SORTEO_2026-11-09.md`.

## Para retomar en otro chat

**Está todo programado y probado (etapas 0 a 5 del plan).** Falta solo publicar, cuando el usuario diga. Lo que lleva, en una línea cada uno:

- **El modal del cobro se cierra apenas el pago queda guardado** (etapa 0, `a5458f6`).
- **La recepcionista ve el plano** en la PC y en el celular: VER EN EL PLANO, VER LA LLEGADA (solo en su pantalla, la tele no se
  entera) y "Ver el plano entero" en MÁS (etapa 1, `50065e7`).
- **Sillas sueltas:** la barra vende "Silla suelta" y la puerta la anota con SILLA SUELTA, al lado de SUMAR SILLA, sin tope
  (etapa 2, `84a9361`).
- **El chat de la puerta:** CHAT, se elige a quién (Todos o una recepcionista) y salta "Juli, a vos: …" (etapa 3, `695c64c`).
- **Las mesas de más van lejos:** en el cartel del sorteo, una familia con más de 3 mesas viene tildada sola, y "Donde yo elija" abre
  el plano encima del cartel para tocar la zona (etapa 4, `e654fb0`).
- **La prueba en el sandbox** (etapa 5): dos celulares en pestañas del navegador de la app y la central de prueba, sin base ni nube.

**Lo que hay que saber antes de publicar:**
- **Los sorteos empiezan el 10-nov.** Hasta que se instale la 6.5.0, el cartel del sorteo es el de la 6.4.0: nadie viene tildado y no
  hay "Donde yo elija". Las familias con más de 3 mesas hay que tildarlas a mano, como hasta ahora.
- **No crear el producto "Silla suelta" en el catálogo de la barra hasta que las tablets y las notebooks tengan la 6.5.0.** Una 6.4.0
  lo vende igual (tiene "silla" en el nombre), pero su vale dice lo de la silla extra, sin "no va a la mesa".
- **No usar SILLA SUELTA hasta que las tres PCs tengan la 6.5.0.** Una silla suelta es una fila de `sillas_puerta` con la mesa en 0; una
  PC con la 6.4.0 que la baje la muestra "fuera de sus mesas: revisar". No rompe nada, pero confunde.
- **La 6.4.0 todavía no estaba instalada en las tres PCs** al cerrar esto (falta que el usuario avise). Si la instala antes, primero la foto de
  la mora "después de 6.4.0"; después la de "antes de 6.5.0".

**Publicar, paso a paso (cada paso con su OK y con el usuario presente):**
1. Foto de la mora "antes de 6.5.0" (`supabase/mora_fotos.sql`).
2. **Sin SQL.** Nada nuevo en la nube: la silla suelta es la mesa 0, el chat vive en la memoria de la notebook, la zona va dentro del
   registro del sorteo con la clave `_zonas`.
3. Versión **`6.5.0+67`** en `pubspec.yaml` y `#define MyAppVersion "6.5.0"` en `installer/junior_eventos_setup.iss`. Novedades
   (propuesta, elige el usuario): **"La puerta ve el plano, sillas sueltas, chat entre puestos y dónde van las mesas lejos"**, en
   `build/novedades_6.5.0.md`.
4. `powershell -File installer\build_installer.ps1`, sin redirigir el stderr (necesita `android\key.properties`): deja el Setup y el APK
   firmado en `installer\dist`. La página del celular (`{app}\puesto`) sale en el mismo instalador: el chat y el plano del celular
   viajan ahí.
5. Release: `tool/publish_windows_release.ps1 -SoloNotas -NotesFile build/novedades_6.5.0.md`. La web a Vercel (ver CLAUDE.md).
6. Instalar las tres PCs y la tablet, y abrirlas.
7. Foto "después de 6.5.0" y la comparación: tiene que dar vacía.
8. Recién ahí: el producto "Silla suelta" en el catálogo de la barra, con su precio.

> Frase para retomar: "Seguimos con la 6.5.0: leé 'Para retomar en otro chat' de docs/CONTEXTO_v6.5.0_2026-11-09.md."

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
