# Revisión antes de las fiestas (13-nov-2026)

Revisión de la **6.8.0** (rama `feature/v4.6-cierre-por-sesiones`, `b3ca309`), la versión que se va a instalar. La hicieron
14 revisores que leyeron el programa por partes (6 de Recepción, 5 del tótem, íconos y letras, botones del resto del
programa y "la noche de punta a punta") y las pruebas en el sandbox. **No se cambió nada del programa.** Lo que se probó
corrió aislado: nada contra la base de `Documentos\Junior Eventos` ni contra Supabase.

Cada hallazgo dice cómo se comprobó:
- **CONFIRMADO con prueba**: una prueba aislada lo reproduce (en `build/revision/probes/`, fuera de git).
- **CONFIRMADO en el código**: el camino se leyó entero y hace eso. No depende del momento.
- **PROBABLE**: el código lo permite, pero depende de algo que acá no se puede reproducir (la red del salón, la tele, dos PCs).

## En corto

- **Las 4.670 pruebas del programa pasan** (3 minutos y medio). Tres de ellas consultan la nube de verdad y se dejaron
  afuera (ver "Otros"). El análisis no marca ningún error en el programa.
- **En el sandbox anduvo todo lo que se probó**: dos celulares en la puerta, buscar sin acentos, ingresar, el otro
  celular se entera, sumar una silla con un vale, frenar un vale usado dos veces, el chat, VER EN EL PLANO, VER LA LLEGADA,
  la página del celular **sin internet** (dibuja y se ven los íconos), y en el tótem una familia, un acompañante y los
  profes juntos con su mesa y el camino.
- **Los íconos están bien**: los 421 existen y la página del celular trae su letra de íconos (lo que falló en la 6.6.0
  está arreglado). Lo que hay son íconos que confunden y botones sin texto (ver "Íconos").
- **Hay 9 cosas que pueden fallar una noche de fiesta.** Las más importantes: el tótem sin internet pierde su
  personalización, y la barra pierde la fiesta después de medianoche. Las dos se arreglan en el código, y hay cosas para
  hacer en el salón mientras tanto (ver "Mientras tanto, en el salón").

## Lo que puede fallar la noche

### 1. Si el tótem abre sin internet, la tele vuelve a "JUNIOR EVENTOS" y no se recupera — CONFIRMADO con prueba
La notebook del salón arranca sin internet (el router propio, sin fibra) y se abre el tótem o Recepción. La config
guardada en la PC (foto, título, apariencia, "Tu fondo") sale un instante y enseguida la tapa la de fábrica: el error de
la nube manda "la de siempre" aunque la de la PC ya estaba en pantalla. Después del error, esa lectura no se vuelve a
intentar: aunque vuelva internet, la tele sigue en la de fábrica hasta esconderla y volverla a mostrar.
- Dónde: `lib/features/totem/providers/totem_config_provider.dart:72-77` (y `80-83`).
- Lo mismo le pasa a la vista del tótem de Recepción y al salón que reciben los celulares.
- **Y encima se puede borrar en la nube**: si alguien abre Personalizar en ese estado y guarda cualquier cosa, se sube la
  fila entera con los valores de fábrica (la foto, el fondo, la apariencia y los textos se pierden).
  `totem_config_sheet.dart:300` lee la config una sola vez al abrir y `:619-644` guarda todo.
- Prueba: `build/revision/probes/config_sin_internet_probe_test.dart` (emite "PROMOCIÓN 2026 | foto" y después
  "JUNIOR EVENTOS | foto=null").
- Arreglo: mandar la de fábrica solo si no salió nada antes (ni la de la PC ni la de la nube), volver a leer cuando vuelve
  la red, y que Personalizar no guarde si no pudo leer la config de verdad.

### 2. Después de las 00:00 la fiesta desaparece de la barra — CONFIRMADO en el código
La cajera y la encargada eligen la fiesta en una lista que cuenta "desde hoy". Pasada la medianoche, la fiesta del día
anterior ya no figura. Si la cajera vuelve atrás, toca SALIR, se le cierra la app o entra otra cajera, **no puede volver a
su caja ni cerrarla**, y la encargada pierde LAS CAJAS de esa fiesta. El jefe y la web ya usan "desde ayer".
- Dónde: `lib/features/barra/services/fiestas_de_la_barra.dart:12-18`. Lo mismo en Entradas:
  `lib/features/entradas/services/fiestas_que_vienen.dart:6-12`.
- Arreglo: contar desde ayer, como `FiestasDelJefe`, o mostrar siempre la fiesta donde hay una caja abierta.

### 3. La encargada que entra directo a LAS CAJAS no está conectada a la central de la barra — CONFIRMADO en el código
Solo VENDER conecta la tablet a la central. Si la tablet de la encargada se reinicia y ella entra con su PIN directo a LAS
CAJAS, sin internet no ve las ventas de las otras cajas ni el aviso de "la Caja N pide cerrar", y **su OK no llega** a la
cajera.
- Dónde: `lib/features/barra/widgets/vender_screen.dart:105-111` (el único que arranca la conexión);
  `barra_home_screen.dart:163-170` (LAS CAJAS) no lo hace.
- Arreglo: conectarse también al abrir LAS CAJAS.

### 4. El OK de la encargada desde el iPhone tarda hasta 5 minutos — PROBABLE
Desde la web el OK se escribe en la nube pero no se avisa a los equipos: la tablet de la cajera lo ve con la vuelta de
5 minutos. A los 3 minutos se le habilita CERRAR SIN ESPERAR, y si lo usa la caja queda "sin el OK" aunque la encargada
haya aceptado.
- Dónde: `lib/features/barra/datos/barra_nube.dart:210-214`. No se probó contra la nube (ya figuraba en lo no probado de
  la 6.6.0).
- Arreglo: que el OK desde la web mande el aviso entre equipos con `tablas: ['barra_cierres']`.

### 5. Cambiar el evento en la notebook mueve la tele, y tocar CELULARES apaga la central — CONFIRMADO en el código
- Cambiar el evento en el desplegable de Recepción **cambia la tele sin preguntar** (a propósito, pero sin aviso). La
  lista va por fecha descendente: el evento de mañana queda justo arriba del de hoy. La central sigue en el de hoy, y el
  tótem saluda a la gente de esta noche sobre la portada del otro. `recepcion_provider.dart:54-56`.
- Con otro evento elegido, abrir CELULARES **apaga la central de la fiesta** y la prende para el otro: los celulares
  quedan en "escribí el código", sin la lista y sin poder marcar. `sumar_celular.dart:78-91`,
  `central_provider.dart:249-255`.
- Arreglo: preguntar antes de mover la tele o la central si ya están en otra fiesta.

### 6. Con las adicionales "Al final", el tótem guía a la mesa del fondo — CONFIRMADO en el código
La "mesa principal" se elige como el tramo de números seguidos más largo. Una familia con la 5 adelante y la 70-71 al
fondo (sorteo con "Las mesas adicionales: Al final" y "Ninguna" pegada) queda con la principal en la **70**: el tótem
dibuja el camino a la 70, el apellido va en la 70 y las sillas extra del contrato se reparten ahí (también en la
planilla). Pasa solo con familias de 3 o más mesas.
- Dónde: `lib/features/plano/modelo/estado_plano.dart:36-56` (`principalDe`), que usan `plano_de_la_llegada.dart:60` y
  `sillas_de_la_puerta.dart:141-153`.
- **A revisar ya: si alguna fiesta se sorteó con "Al final"**, mirar en el plano las familias de 3 o más mesas.
- Arreglo: que la principal salga de lo que dejó el sorteo (el registro `_al_final` sabe cuáles fueron al final).

### 7. Vaciar la lista o deshacer el sorteo con la fiesta empezada hace saludar de nuevo a todos — CONFIRMADO con prueba
Después de un "vaciar" (vaciar la lista, deshacer el sorteo entero, **también de otro evento** en la misma PC, porque el
aviso no dice de qué evento es), la siguiente lectura no va en silencio: todos los que ya entraron vuelven a la cola. Con
el salón, cada saludo dura lo que eligió el jefe: 100 familias son más de 20 minutos de saludos repetidos.
- Dónde: `lib/features/totem/services/bienvenidas_totem.dart:421-427`; el aviso sin evento, `kiosk_launcher.dart:308`.
- Prueba: `build/revision/probes/cola_totem_probe_test.dart` (50 adentro → cola de 50 después de vaciar).
- Arreglo: que después de vaciar la próxima lectura vaya en silencio, y que el aviso lleve el evento.

### 8. La ventana del tótem pisa lo que la PC guarda (también la sesión) — CONFIRMADO en el código; lo de la contraseña, PROBABLE
La ventana del tótem es otro programa por dentro, con su propia copia de las preferencias de la PC, y cada vez que guarda
algo (GIRAR, la config que llega de la nube) **reescribe el archivo entero con lo que leyó al abrirse**. Así se pierden:
el código de la central de los celulares, los segundos de la llegada puestos a mano y **la sesión de Supabase** (que se
renueva cada hora en la ventana principal). Al otro día, el programa puede pedir la contraseña; sin internet, no se puede
entrar.
- Dónde: `shared_preferences_windows` 2.4.1 (lee una vez y reescribe todo), la sesión la guarda `supabase_flutter` en ese
  mismo archivo; escriben desde la ventana del tótem `totem_orientation.dart:58-64` y `totem_config_cache.dart:21-28`.
- Arreglo: que la ventana del tótem no escriba en las preferencias (que se lo pida a la principal por el puente, o un
  archivo propio).

### 9. La notebook se puede dormir en plena fiesta — CONFIRMADO en el código (no hay nada que lo impida)
Si nadie toca la notebook (se marca todo desde los celulares), Windows apaga la pantalla (la tele se va a negro) y
después la suspende: la central deja de contestar. El programa no le pide a Windows que no duerma.
- Arreglo en el código: pedirle a Windows que no duerma mientras están prendidos el tótem o la central. **Mientras tanto,
  en el salón** (ver abajo).

## Molesta (no rompe la noche, pero se va a notar)

**Recepción y la puerta**
- **La lista se corre bajo el dedo**: el aviso "X ingresó", el cartel del chat y el conteo aparecen arriba de la lista y
  la empujan. Visto en el sandbox: el segundo toque cayó fuera del botón (captura 10). Con el filtro "Faltan", un doble
  clic puede ingresar a la persona de abajo. `panel_puerta.dart:168-179`.
- **En un celular angosto, la línea de la silla sumada sale en columna**, palabra por palabra (captura 01).
- **Con "Faltan" elegido, quien ya entró "no existe"**: buscarlo dice "No hay nadie con esa búsqueda" en vez de "ya
  ingresó a las 22:41". Y Enter ingresa al único que falta aunque la persona en la puerta sea otra del mismo apellido que
  ya estaba adentro. `puerta_del_evento.dart:300-308`.
- **El vale sin caja**: escribir solo "17" (el número grande) se acepta; si la barra anula esa venta nunca se pone en rojo.
  Y dos cajas abiertas con el mismo número hacen que la puerta rechace un vale bueno ("ya se usó").
  `hoja_sumar_silla.dart:125`, `vales_anulados.dart:54-57`.
- **"Todo subido" con sillas de la noche sin subir**: la línea cuenta solo los ingresos. `sin_internet_provider.dart:31`.
- **"Lista actualizada" aunque no bajó nada** (sin internet sale verde igual). `recepcion_unified_screen.dart:585-596`.
- **"Sin internet" que no se corrige solo**: si el primer intento al volver el wifi falla, Recepción sigue diciendo "sin
  internet" (y no sube con el atajo rápido) hasta el próximo cambio de red. `connectivity_service.dart:31-73`.
- **Una bajada vieja vuelve a "pendiente" a quien acaba de entrar** (en la hora pico, hasta la siguiente bajada), y cada
  ingreso hace bajar la lista entera en cada PC con Recepción abierta. `invitados_repository.dart:671-796`.
- **Los acompañantes van atados a su lugar en la lista**: sacar al primero con el segundo ya adentro le corre el ingreso
  al que sigue. Solo si se tocan acompañantes con la fiesta empezada. `lista_puerta.dart:75-89`.
- La familia de baja temporal no aparece, y no dice por qué; "profes" no encuentra a los profes.
- Un número de 20 cifras en el buscador deja el panel en gris (hay que salir de Recepción). `puerta_del_evento.dart:677`.

**La central y los celulares**
- **Si la notebook cambia de IP o la central vuelve en otro puerto**, los celulares no la encuentran, y al reescanear lo
  marcado sin señal queda en la pestaña vieja. Recomendación: IP fija para la notebook en el router.
- El código de los celulares vence a las 18 h de haberlo sacado, no de usarlo: una central probada a la mañana vence de
  madrugada.
- **En el iPhone, el vale no se puede escribir como dice la pista** ("2 0017"): en la web sale el teclado de números con
  coma, sin espacio ni guion. Si escribe "200172" el vale queda sin caja. La coma sí separa: "2,0017" anda.
  `hoja_sumar_silla.dart:215-224`.
- **Recargar la página sin la notebook a la vista** deja el celular en "no se puede abrir la página" hasta que vuelva el
  wifi (lo pendiente sigue guardado).
- **Chat**: un mensaje mandado justo cuando se cae el wifi se pierde y quien lo mandó lo ve como enviado; después de
  recargar, lo que le escribieron mientras tanto queda como leído; un emoji sin internet sale como cuadradito.
- Si la PC todavía no tiene la lista, el celular dice "Buscando la PC… tiene que estar en el wifi" (manda a revisar el
  wifi cuando el problema es la PC).

**El tótem**
- **Un ingreso "sin saludo" se saluda igual**: lo que marcó un celular que estuvo más de un minuto sin wifi la central lo
  decide sin saludo, pero la tele lo saluda con la relectura de la nube. `invitados_repository.dart:388-403`.
- **Deshacer un ingreso y que vuelva a saludarlo** si una lectura de la nube llega atrasada.
- **Con el salón, la cola no se acorta** (es como lo pidió el usuario): 60 familias, una cada 6 s, y la última se saluda
  unos 7 minutos tarde. La recepcionista puede bajar los segundos con el reloj de Recepción.
- La tele saluda con la mesa vieja hasta 60 s después de un cambio en la oficina.
- **La ventana nueva del tótem (608×1080) en una notebook de 768 de alto** con la tele conectada sale con la barra de
  título y los botones fuera de la pantalla. GIRAR con la tele como segundo monitor o con la pantalla al 125/150 % saca la
  ventana de la tele.
- **La X de la barra del tótem** está pegada a SALIR DEL KIOSCO, no tiene ayuda ni pregunta: esconde el tótem y la tele
  muestra el escritorio. **Cerrar la ventana principal** cierra también el tótem, sin preguntar.
- Con un color claro (Perla) la mesa encendida casi no se distingue; en un plano de dos hojas la tele salta de hoja en la
  llegada.
- En la web, una clave equivocada en el link se ve como "Sin internet: reconectando" para siempre.
- **Póster corta arriba**: la franja inclinada de la mesa se come la parte de arriba de los números (con "MESAS 128, 129"
  el último pierde la mitad) y el recorte del nombre se lleva los acentos (se ve en la muestra `Totem_llegada_familia`:
  la tilde de "MARTÍN" pegada a la línea de arriba). `escena_poster.dart:167-221`.
- **Neón y Gala con 2 o 3 mesas de 3 cifras**: los números pisan el anillo. `escena_neon.dart:212-236`.
- **La música larga achica la llegada entera** (nombre y mesa incluidos): desde el link del delegado se pueden cargar 300
  letras y el tótem no las recorta. `escena_totem.dart:1621-1659`.
- **Una foto o un fondo que no bajó una vez queda así toda la noche**: si la tele abrió sin internet y sin la foto
  guardada, sigue con el logo aunque vuelva internet (hasta reiniciar el programa). `foto_guardada.dart:65-75`.
- Con 3 o 4 horas prendido, la grilla de Neón empieza a titilar; la foto de Póster y el anillo de Gala dan un salto cada
  minuto. En una notebook sin placa de video o con una tele 4K, el fondo animado puede ir a tirones (no se midió).
- Personalizar: cerrar sin querer pierde lo elegido; las fotos de más de 5 MB se rechazan sin ofrecer achicarlas; lo que
  guarda el jefe desde otro equipo no llega a la tele hasta reiniciar.

**La barra**
- Sin impresora elegida, el vale dice "¿La impresora está prendida y cerca?" en vez de "esta tablet no tiene impresora".
- En VENDER las 5 acciones de arriba son solo íconos; la impresora verde no imprime, abre "elegir impresora".
- El cartel del OK muestra los totales que llegaron al equipo de la encargada, sin avisar si faltan ventas; puede decir
  "Aceptaste el cierre" aunque la cajera ya volvió a vender.
- Una tablet que no vuelve a tener internet: sus ventas nunca llegan a la nube (la notebook no las sube).
- CAMBIAR la impresora y APAGAR la central se hacen sin preguntar.

**Entradas**
- Una entrega hecha sin internet en una PC pisa, al subir, la de la otra PC, sin aviso (se pierden quién retiró y los
  números de talonario). Los talonarios solo se controlan contra lo que ya bajó a esa PC.
- El buscador del mostrador no encuentra "gomez" en "GÓMEZ" ni "juan perez" en "PÉREZ, JUAN".
  `retiro_entradas_screen.dart:870-873`.

**Inicio**
- "Cerrar sesión" no pregunta. Sin internet, después no se puede volver a entrar.

**Papeles**
- **14 papeles bajan la letra de internet** (cierre de caja, hoja de cierre del operario, planilla de mora, entre otros):
  sin internet salen en otra letra y los signos como "—" o "→" salen en blanco. El recibo, las planillas del sorteo y de
  entrega, el plano y los papeles de la barra **no**: usan la letra de la app. `pdf_service.dart` (14 funciones con
  `PdfGoogleFonts`). Arreglo: usar `_fuentesOutfit()`, como el recibo.

## Íconos

- Los 421 íconos existen en la versión de Flutter del proyecto y ninguno está deprecado. Las pantallas de la noche tienen
  ayuda en 41 de sus 42 botones de ícono (falta la flecha de volver de Recepción).
- Los que confunden: la **escoba** es "Saneamiento" (borra) en Mi Empresa y "Perdonar mora" en el alumno; en Clientes
  archivados, **dos papeleras pegadas** (restaurar y borrar para siempre) sin ayuda; en un evento particular el "+"
  flotante **registra un pago**; "Finalizar evento" con una tilde verde que se lee como "Guardar"; la impresora del jefe es
  "configurar" en un lugar e "imprimir" en otro; "anular" es una prohibición en la barra y una flecha atrás en Entradas.
- 31 de 151 botones de ícono no tienen ayuda (ninguno de la noche salvo el de volver).
- El tema de la app pide grosores de Outfit que no vienen con ella: en un equipo que nunca tuvo internet (una tablet recién
  instalada) los títulos salen en otra letra. No se rompe nada.

## Qué arreglaría antes de la fiesta (en este orden)

Son arreglos chicos y acotados, cada uno con su prueba, para una **6.8.1**:
1. El tótem sin internet: que no vuelva a la de fábrica y que Personalizar no guarde sin haber leído la config (punto 1).
2. La barra y Entradas después de medianoche: contar desde ayer (punto 2).
3. La encargada conectada a la central también desde LAS CAJAS (punto 3).
4. Después de vaciar la lista, la lectura siguiente en silencio, y el aviso con su evento (punto 7).
5. La mesa principal con "Al final": la de adelante (punto 6).
6. Preguntar antes de mover la tele o apagar la central de otra fiesta (punto 5).
7. Que la ventana del tótem no escriba en las preferencias de la PC (punto 8).
8. Que la notebook no se duerma con el tótem o la central prendidos (punto 9).
9. Los 14 papeles con la letra de la app (sin internet salen bien).

El OK de la encargada desde el iPhone (punto 4) y lo que "molesta" pueden ir después.

## Mientras tanto, en el salón (sin tocar el código)

1. **Plan de energía de la notebook del salón**: "Apagar la pantalla" y "Suspender" en **Nunca** (enchufada), y "Al cerrar
   la tapa": **No hacer nada**.
2. **IP fija para la notebook** en el router del salón (reserva por dirección MAC).
3. **Abrir el programa y el tótem con internet** antes de la fiesta (aunque sea compartiendo el celular), y recién después
   pasar al router del salón. Si el tótem quedó en "JUNIOR EVENTOS": esconderlo y volverlo a mostrar con internet.
   **No guardar Personalizar si la tele muestra "JUNIOR EVENTOS".**
4. **En la notebook, no cambiar el evento del desplegable ni tocar CELULARES de otra fiesta** con la fiesta en marcha.
5. **Barra después de medianoche: que la cajera no salga de VENDER** ni cierre la app hasta cerrar su caja. **La encargada
   entra primero a VENDER** (aunque no venda) y desde ahí a LAS CAJAS.
6. **No vaciar la lista ni deshacer el sorteo** con la fiesta empezada.
7. **Con "Al final" en el sorteo**: mirar en el plano las familias de 3 o más mesas.
8. **Escribir el vale entero** (caja y número, como dice el papel). En el iPhone, con coma: "2,0017".
9. **En los celulares de la puerta**: bloqueo automático en "Nunca", sin pestaña privada, y **no recargar la página** si
   dice "Sin conexión con la PC": seguir marcando, se manda solo al volver.

## Lo que no se pudo probar acá

- La tele de verdad, el kiosco en la tele y la notebook del salón con su pantalla (el arnés del kiosco no pasa por el
  mismo camino que la app; los riesgos salen de leer el código).
- El router del salón, celulares de verdad, la impresora y dos PCs contra la nube.
- El OK de la encargada desde el iPhone contra la nube.

## Otros

- **Tres pruebas consultan la nube de verdad** cada vez que se corre la suite entera (`test/verify_supabase_content_test.dart`,
  `test/query_supabase_id_test.dart`, `test/search_supabase_broad_test.dart`, con la clave anónima escrita). Van contra la
  regla de no probar contra Supabase: conviene sacarlas o pasarlas a `tool/`.
- `docs/pendientes/rls-invitados.md` dice que faltan los SQL, que se corrieron el 15-oct.
- La ruta `/totem_display` de `main.dart` no la abre nadie.
- El análisis tiene 41 avisos (variables sin usar, código muerto), ninguno en Recepción, el tótem ni la barra.

## Capturas

En `build/revision/` (fuera de git): `01` la silla en columna en el celular, `02` el vale repetido frenado, `03` el chat,
`04` VER EN EL PLANO, `05` VER LA LLEGADA, `06` el celular sin internet, `07` a `09` el tótem (familia, acompañante,
profes), `10` el aviso que corre la lista. Las muestras de todas las pantallas, en `build/revision/muestras/` (53).
