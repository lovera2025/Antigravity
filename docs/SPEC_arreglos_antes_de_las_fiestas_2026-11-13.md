# SPEC: los problemas de la revisión del 13-nov, para revisar y arreglar (6.8.1)

**Para quien lo lea:** este documento junta los problemas que encontró la revisión del 13-nov-2026 sobre la versión
6.8.0, la que se va a instalar antes de las fiestas. Se pide **revisar si cada uno es real**, si el arreglo propuesto es el
correcto o hay uno mejor, y qué riesgo tiene. Nada de esto está programado: el código está como en `b3ca309`.
El informe para el usuario, con capturas, es `docs/REVISION_ANTES_DE_LAS_FIESTAS_2026-11-13.md`.

## 0. Contexto mínimo

- App Flutter (Windows, Android para tablets, web), offline-first: SQLite local + cola de subida a Supabase.
  Repo: `C:\Users\lover\Documents\Antigravity (Gemini)\arguello_events`, rama `feature/v4.6-cierre-por-sesiones`
  (`main` está vieja). **`CLAUDE.md` de la raíz es obligatorio**: tiene las trampas del proyecto.
- La noche de una fiesta: una notebook en el salón con Recepción, la tele del tótem (una **segunda ventana** de
  Flutter, `desktop_multi_window`, otro motor y otro isolate) y la **central de la puerta** (servidor WebSocket al que se
  conectan los celulares de las recepcionistas por un router propio, muchas veces **sin internet**). En la barra, otra
  notebook con la **central de la barra** y tablets Android que venden.
- Reglas del proyecto que tocan estos arreglos:
  - Nunca probar contra la base real (`Documentos\Junior Eventos\data.db`) ni contra Supabase: tests y arneses en memoria
    (`test/helpers/`, `tool/*_prueba.dart`).
  - No agregar columnas a `contratos_alumnos` (un dato nuevo del alumno va en una tabla aparte).
  - Lo que cambia el salón es solo en modo jefe, con doble llave (`test/solo_modo_jefe_test.dart` lee las pantallas).
  - **Sin SQL ni migración en esta tanda**, salvo que sea imprescindible: las PCs conviven con versiones distintas.
  - Tests que leen el código como texto y tienen que seguir pasando: `solo_modo_jefe_test`, `puerta_sigue_al_salon_test`,
    `puerta_cerrada_test`, `kiosco_en_el_totem_test`, `modo_barra_cerrado_test`, `barra_en_la_web_test`,
    `borrados_de_otra_pc_test`, `sync_en_reposo_test`, `pulso_por_el_socket_test`.
  - Mensajes de commit en español, describiendo el efecto para el usuario. Publicar es siempre con el usuario presente.
- **Correr la suite**: `flutter test` con la lista de `test/` **sin** `verify_supabase_content_test.dart`,
  `query_supabase_id_test.dart` y `search_supabase_broad_test.dart` (consultan la nube de verdad). En Windows, el
  comando entero no entra en `cmd`: se corre por tandas de ~45 archivos. Hoy pasan 4.667 (+3 excluidos = 4.670), en unos
  3,5 minutos.

## 1. Cómo se comprobó cada uno

- **CONFIRMADO con prueba**: una prueba aislada lo reproduce (el código está en la sección 5).
- **CONFIRMADO en el código**: el camino se leyó entero y hace eso, siempre.
- **PROBABLE**: el código lo permite, pero depende de algo que no se pudo reproducir (red del salón, tele, dos PCs, nube).

Los problemas los encontraron 14 revisores que leyeron por partes, y se comprobaron después. Varios los encontraron dos
revisores por separado (se indica).

## 2. Los 9 que pueden fallar la noche

### P1. El tótem que abre sin internet vuelve a la config de fábrica, y Personalizar puede borrar la de la nube — CONFIRMADO con prueba (lo vieron 3 revisores)

**Síntoma.** La notebook arranca sin internet y se abre el tótem (o Recepción). La tele muestra un instante la config
guardada en la PC (foto, título, apariencia, "Tu fondo") y enseguida queda "JUNIOR EVENTOS", sin foto, en Neón o
Cristal. Aunque vuelva internet, sigue así hasta esconder y volver a mostrar el tótem (o reiniciar). Lo mismo en la vista
del tótem de Recepción, en la página del QR y en el salón que la central les manda a los celulares.

**Causa.** `lib/features/totem/providers/totem_config_provider.dart`:
- `:41-50` emite la caché de disco (`TotemConfigCache.load`) si `!emitioAlgoDelServidor`.
- `:72-77` en `onError` del stream de Supabase, emite `TotemConfig.defaults` si `!emitioAlgoDelServidor`, **aunque la
  caché ya se haya emitido**. La caché siempre llega antes que el error (SharedPreferences ya está en memoria).
- `:80-83` lo mismo si no se pudo suscribir.
- El stream de `supabase` 2.10.4 se cierra con el error (`supabase_stream_builder.dart:278-284`): nadie lo vuelve a
  pedir.

**Agravante.** `lib/features/totem/widgets/totem_config_sheet.dart:300` (Personalizar) lee la config **una sola vez** con
`ref.read(totemConfigValueProvider(...))` y `:619-644` guarda la fila **entera** (upsert con todas las columnas): si se
abre en ese estado (o mientras carga, o con algo viejo) y se guarda cualquier cosa, se pisan en la nube la foto, el fondo,
la apariencia y los textos. Si `_guardada.fondoUrl` es null entra `limpiarFondo` y borra el fondo.

**Arreglo propuesto.**
1. En el provider: una sola marca `emitioAlgo` (caché o nube); en `onError`, emitir la de fábrica **solo si no salió
   nada**. Volver a suscribirse con espera creciente (o cuando la conectividad pasa a `online`), porque el stream muerto
   no vuelve.
2. En Personalizar: antes del upsert, leer la fila de la nube con tope corto (unos 5 s) y partir de ella (o frenar si su
   `updated_at` es más nuevo que lo que se abrió). Si no se puede leer, **no guardar** y decirlo ("Sin internet: no se
   puede guardar ahora").
3. Opcional: que el provider exponga de dónde viene el valor (fábrica / caché / nube) para que Personalizar no abra sobre
   la de fábrica sin avisar.

**Cómo probarlo.** La prueba P1 de la sección 5 tiene que terminar mostrando "PROMOCIÓN 2026 | foto". Sumar a
`test/personalizar_totem_test.dart`: abrir con un stream que emite la de fábrica y después la guardada; tocar un color y
guardar; la fila guardada no puede perder `imagenUrl`.

**Cuidado.** `totemConfigValueProvider` lo usan `totem_display.dart:740`, `totem_local.dart`, `lista_invitados_screen.dart`,
`sin_internet_provider.dart`, `tiempos_a_mano_provider.dart` y `central_provider.dart:302`. El provider corre en las dos
ventanas (la del tótem lee `supabaseProvider`, nunca `Supabase.instance`).

### P2. Después de las 00:00 la fiesta desaparece de la barra (y de Entradas) — CONFIRMADO en el código (lo vieron 2 revisores)

**Síntoma.** La lista de fiestas de la cajera y de la encargada cuenta "desde hoy". Pasada la medianoche, la fiesta del día
anterior desaparece: si la cajera vuelve atrás, toca SALIR, se le cierra la app o entra otra cajera, no puede volver a su
caja ni cerrarla; la encargada pierde LAS CAJAS. Si eligen otra fiesta con precios, la caja queda en otro evento y la
central de la barra la rechaza.

**Causa.** `lib/features/barra/services/fiestas_de_la_barra.dart:12-18`: `desde = hoy` y `!fecha.isBefore(desde)`. Igual
`lib/features/entradas/services/fiestas_que_vienen.dart:6-12`. El jefe (`barra/services/fiestas_del_jefe.dart`) y la
encargada en la web (`barra_home_web.dart:68-74`) ya usan "desde ayer".

**Arreglo propuesto.** Contar desde ayer, como `FiestasDelJefe`. Además (o en vez): mostrar siempre la fiesta donde este
equipo tiene una caja abierta.

**Cómo probarlo.** `fiestasParaLaBarra` con hoy = `DateTime(2026,11,15,1)` y una fiesta del 14/11: tiene que figurar. Igual
`fiestasQueVienen`. Revisar los tests que hoy fijan "las de ayer no".

### P3. La encargada que entra directo a LAS CAJAS no se conecta a la central de la barra — CONFIRMADO en el código

**Síntoma.** Si la tablet de la encargada se reinicia y ella entra con su PIN directo a LAS CAJAS (sin abrir su VENDER),
sin internet no ve las ventas de las otras cajas ni el aviso "la Caja N pide cerrar", y su OK no sale por la red del salón
(nunca le llega a la cajera).

**Causa.** El único lugar que arranca `clienteDeLaBarraProvider` es `lib/features/barra/widgets/vender_screen.dart:105-111`
(`ref.read(clienteDeLaBarraProvider.notifier).arrancar(...)`). `barra_home_screen.dart:163-170` (botón LAS CAJAS) y
`cajas_de_la_fiesta.dart` no lo hacen. `AvisoDePedidosDeCierre` lee la base de la tablet.

**Arreglo propuesto.** Arrancar el cliente también al abrir `LasCajasScreen` (o al elegir la fiesta en el inicio de la
barra), con el nombre de la encargada. Ojo si la encargada usa la misma notebook donde corre la central.

**Cómo probarlo.** Con `tool/central_barra_prueba.dart` (dos tablets y la notebook): la encargada entra directo a LAS
CAJAS, una cajera pide cerrar; a la encargada le tiene que saltar el aviso, y su OK tiene que llegar.

### P4. El OK de la encargada desde el iPhone (web) tarda hasta 5 minutos en llegar — PROBABLE

**Síntoma.** Desde la web el OK se escribe directo en la nube pero no se avisa a los equipos: la tablet de la cajera lo
baja con la red de seguridad de 5 minutos. A los 3 minutos se le habilita CERRAR SIN ESPERAR; si lo usa, la caja queda
"Cerró sin el OK" aunque el OK exista ("sin OK" gana).

**Causa.** `lib/features/barra/datos/barra_nube.dart:210-214` (`anotarPasoDelCierre`) no manda el pulso. El pulso entre
equipos solo sale cuando un equipo sube algo de su cola (`sync_engine.dart` `_emitirPulso`). Ya figuraba como no probado en
el CONTEXTO de la 6.6.0.

**Arreglo propuesto.** Que `BarraNube.anotarPasoDelCierre` mande también el broadcast `sync_pulse` con
`tablas: ['barra_cierres']` (mismo formato que `_emitirPulso`; leer `cuerpoDelBroadcast` y su test). Es solo la web: se
publica con la web.

**Cómo probarlo.** Test con `NubeDePrueba`: anotar desde la web y verificar el broadcast. Contra la nube de verdad solo con
el OK del usuario.

### P5. Cambiar el evento en la notebook mueve la tele, y CELULARES de otra fiesta apaga la central — CONFIRMADO en el código (lo vieron 3 revisores)

**Síntoma.**
- Cambiar el evento en el desplegable de Recepción cambia la tele del salón sin preguntar. La lista va por fecha
  descendente, así que el evento de mañana queda justo arriba del de hoy. La central sigue en el de hoy y el tótem saluda
  a la gente de esta noche sobre la portada del otro (el aviso por el puente no dice de qué evento es).
- Con otro evento elegido, abrir CELULARES apaga la central de la fiesta y la prende para el otro: los celulares reciben
  4001 y quedan en "escribí el código", sin lista y sin poder marcar (ni siquiera sin conexión). Volver al evento correcto
  no los recupera solos.

**Causa.** `lib/features/recepcion/providers/recepcion_provider.dart:54-56` (`SelectedEventNotifier.select` llama a
`KioskLauncher.setEvento` si el tótem está activo; es a propósito, comentario incluido). `widgets/sumar_celular.dart:78-91`
llama a `prender`; `central/central_provider.dart:249-255` suelta la central anterior; `central/cliente_central.dart:405-407`
no reintenta con 4001.

**Arreglo propuesto.** Si la tele (o la central con celulares) ya está en otro evento, preguntar: "La tele muestra X:
¿pasarla a Y? · Solo mirar acá" (y lo mismo para la central). En el celular, con 4001, seguir mostrando la lista guardada y
reintentar con el código guardado.

**Decisión del usuario.** Si la tele tiene que seguir al desplegable o no.

### P6. Con las mesas adicionales "Al final", la principal es la del fondo — CONFIRMADO en el código (lo vieron 2 revisores)

**Síntoma.** Familia de 3 o más mesas sorteada con "Las mesas adicionales: Al final" y "Ninguna" pegada (viene elegido
así al tildar "Al final"): queda, por ejemplo, con la 5 adelante y la 70-71 al fondo. La "principal" pasa a ser la **70**:
el tótem dibuja el camino a la 70 y pone el apellido ahí; la puerta muestra "Mesa 70" y "Mesa adicional 5"; las sillas
extra del contrato se reparten en la 70 (también en la planilla).

**Causa.** `lib/features/plano/modelo/estado_plano.dart:36-56` (`OcupantePlano.principalDe`): la primera del **tramo de
números seguidos más largo**. La usan `totem/services/plano_de_la_llegada.dart:60`,
`recepcion/services/sillas_de_la_puerta.dart:141-153` (vía `SalonMesas.tramos`, `salon_mesas.dart:160-167`) y la planilla
del sorteo ("es la misma regla").

**Arreglo propuesto (a decidir).** La regla del tramo más largo existe por las mesas "lejos" (3 juntas + 1 lejos de número
más bajo): "la más baja" no sirve. Opciones:
- (a) tomar del registro del último sorteo (`sorteos_mesas.resultado`, clave `_al_final`) cuáles fueron al final y elegir
  la principal entre las otras;
- (b) guardar la principal elegida por el sorteo en la `config` del plano (clave nueva con guion bajo, que una versión vieja
  ignora; **no** en `contratos_alumnos`).

Cualquiera de las dos tiene que dar lo mismo en el tótem, la puerta, la planilla y el plano.

**Cómo probarlo.** `PlanoDeLaLlegada.para(armado, mesa: '5, 70, 71', ...).principal` tiene que dar 5 cuando el sorteo dejó
70-71 al final, y seguir dando 40 con "40-42 y 10 lejos". Correr `tool/simulacro_adicionales_al_final_test.dart` contando
"principal ≠ mesa de adelante".

**Para el usuario, ya:** si alguna fiesta se sorteó con "Al final", mirar en el plano las familias de 3 o más mesas.

### P7. Vaciar la lista o deshacer el sorteo con la fiesta empezada: la tele vuelve a saludar a todos — CONFIRMADO con prueba (lo vieron 3 revisores)

**Síntoma.** Después de un `list_reset`, la siguiente lectura de la nube (≤20 s) no va en silencio: todos los que ya
entraron vuelven a la cola de bienvenidas. Con el salón, cada saludo dura lo que eligió el jefe y la cola no se acorta: 100
familias son más de 20 minutos. El `list_reset` por el puente **no dice de qué evento es**: vaciar la lista o deshacer el
sorteo de **otra fiesta** en la misma PC lo dispara igual.

**Causa.** `lib/features/totem/services/bienvenidas_totem.dart:421-427` (`vaciar` borra los vistos pero deja
`_leyoAlgunaVez` en true, así que la lectura siguiente no es silenciosa; `resolverLectura` `:186-215`).
`lib/core/services/kiosk_launcher.dart:308` (`notifyListReset` sin evento); lo mandan
`recepcion/repositories/invitados_repository.dart:316` (deshacer el sorteo entero: `plan.sinSorteo`) y `:582`
(`vaciarEvento`); lo atiende `totem_display.dart:404-405` (y `:598` por el canal). Además `guest_checkin` (`:407-412`) no
compara `eventoId`.

**Arreglo propuesto.** Después de `vaciar`, que la próxima lectura vaya en silencio. Que `list_reset` y `guest_checkin` por
el puente lleven el evento y el tótem ignore los de otro.

**Cómo probarlo.** La prueba P7 de la sección 5 tiene que dar cola 0 después de vaciar y volver a leer.

### P8. La ventana del tótem reescribe las preferencias de la PC con una copia vieja (también la sesión) — CONFIRMADO en el código; que pida la contraseña, PROBABLE (lo vieron 2 revisores)

**Síntoma.** Cada ventana de Flutter tiene su propio isolate con su copia de SharedPreferences. En Windows,
`shared_preferences_windows` 2.4.1 lee el archivo una vez (`_cachedPreferences`, `:50-57`) y **cada `setValue` reescribe el
archivo entero** con esa copia (`:129-138`). Cuando la ventana del tótem guarda algo (GIRAR, la caché de la config que
llega de la nube, la clave), vuelve el archivo a como estaba cuando ella se abrió. Se pierde lo que la principal guardó
después: el código de la central de los celulares, los segundos de la llegada puestos a mano y **la sesión de Supabase**
(`supabase_flutter` 2.12.2 la guarda en SharedPreferences por defecto: `local_storage.dart:66`, `supabase.dart:115`; se
renueva cada hora en la principal). Si el programa se cierra antes de que la principal vuelva a escribir, al otro día el
token de refresco guardado es uno ya usado: puede pedir la contraseña (sin internet, no se entra). Al revés, la principal
borra lo que guardó el tótem (la orientación de GIRAR).

**Causa.** Escriben desde la ventana del tótem: `totem/totem_orientation.dart:58-64`, `core/services/totem_config_cache.dart:21-28`
(llamado desde `totem_config_provider.dart:69`, que corre en las dos ventanas), y quizás `totem/services/clave_totem.dart`.

**Arreglo propuesto.** Que la ventana del tótem no escriba en las preferencias compartidas: lo que necesite guardar, que se
lo pida a la principal por el puente, o que use un archivo propio (`SharedPreferencesAsync` con
`SharedPreferencesWindowsOptions(fileName: ...)`, verificar que la 2.4.1 lo soporte). Un test que lea los archivos que
corren en la ventana del tótem y falle si usan `SharedPreferences.getInstance`.

**Cómo probarlo.** Con dos isolates en un test (o el arnés `tool/kiosco_prueba.dart`): guardar una clave desde "la
principal" después de abrir "el tótem", guardar algo desde el tótem, y comprobar que la clave sigue en el archivo.

### P9. La notebook puede apagar la pantalla o suspenderse en plena fiesta — CONFIRMADO en el código (no hay nada que lo impida)

**Síntoma.** Si nadie toca la notebook (todo se marca desde los celulares), Windows apaga la pantalla (la tele se va a
negro) y después la suspende: la central deja de contestar y nada sube.

**Causa.** No hay `SetThreadExecutionState` en `windows/` ni en `lib/`. `PantallaDespierta` solo actúa en Android.

**Arreglo propuesto.** Pedirle a Windows `ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED` mientras estén prendidos
el tótem (visible) o la central, por el mismo canal nativo del kiosco (`windows/runner/kiosco.cpp`), y soltarlo al
apagarlos. **Sin código, en el salón:** plan de energía con pantalla y suspensión en "Nunca" y la tapa en "No hacer nada".

## 3. Los que molestan (no rompen la noche)

| Dónde | Qué pasa | Arreglo propuesto | Cómo se comprobó |
|---|---|---|---|
| `recepcion/widgets/panel_puerta.dart:168-179` | El aviso "X ingresó", el cartel del chat y el conteo aparecen arriba de la lista y la corren bajo el dedo; con "Faltan", un doble clic ingresa a la persona de abajo | Avisos en un lugar de alto fijo o encima de la lista (Stack); ignorar INGRESAR ~500 ms después de un ingreso | Visto en el sandbox (captura 10) |
| `panel_puerta.dart` (tarjeta, celular de 375 px) | La línea de la silla sumada sale en columna, palabra por palabra | Dar ancho a la línea (Wrap o renglón propio) | Visto en el sandbox (captura 01) |
| `recepcion/services/puerta_del_evento.dart:300-308` | Con "Faltan" elegido, quien ya entró "no existe"; Enter ingresa al único que falta aunque otro del mismo apellido ya esté adentro | Si el filtro deja vacío, avisar con `FiltroPuerta.todos` ("ya ingresó a las…"); con Enter, ingresar solo si coincide una sola persona en total | CONFIRMADO en el código |
| `puerta_del_evento.dart:677` | `int.parse` de un número de 20 cifras tira y deja el panel en gris | `int.tryParse` | CONFIRMADO en el código |
| `widgets/hoja_sumar_silla.dart:125, 215-224`; `services/vales_anulados.dart:54-57` | El vale sin caja se acepta y nunca se marca anulado; en el iPhone el teclado (`inputmode=decimal`) no tiene espacio ni guion; dos cajas con el mismo número chocan | Exigir caja y número y mostrar "Caja 2 · N° 17" antes de confirmar; pista "2,0017"; no dejar abrir una caja con un número ya usado en la fiesta | CONFIRMADO en el código |
| `providers/sin_internet_provider.dart:31` | "Todo subido" no cuenta las `sillas_puerta` en la cola | Sumarlas | CONFIRMADO en el código |
| `recepcion_unified_screen.dart:585-596` | "Lista actualizada" aunque no bajó nada | Que `forceRefresh` devuelva si bajó | CONFIRMADO en el código |
| `core/services/connectivity_service.dart:31-73` | Si el primer ping al volver el wifi falla, queda "sin internet" hasta otro cambio de red (la puerta no sube con `_subirYa`) | Reprobar cada 30-60 s con tope mientras no esté `online` | PROBABLE |
| `repositories/invitados_repository.dart:671-796` | Una bajada vieja vuelve a "pendiente" a quien acaba de entrar; cada ingreso hace bajar la lista entera en cada PC | No pisar ids tocados desde que arrancó la bajada; una sola bajada a la vez; aplicar la fila del aviso | PROBABLE |
| `invitados_repository.dart:833-834, 592-596` | `_syncImmediately` y `vaciarEvento` borran de la cola sin `leidaCon` (la trampa de CLAUDE.md) | Pasar por `_subirYa` / `markCompleted(leidaCon:)` | CONFIRMADO en el código |
| `services/lista_puerta.dart:75-89` | El id del acompañante va por su posición: sacar al primero con el segundo adentro le corre el ingreso | Id por nombre normalizado (como `idInvitadoReserva`) o mover el estado por nombre | CONFIRMADO en el código |
| `invitados_repository.dart:388-403` | Un ingreso "sin saludo" (celular que volvió de un corte) se saluda igual por la relectura de la nube | Avisar por el puente un ingreso "mudo" que se anote como visto | CONFIRMADO en el código |
| `totem/services/bienvenidas_totem.dart:207-210, 408-418` | Una lectura atrasada saluda dos veces o vuelve a saludar a quien se le deshizo el ingreso | Marcas que venzan a ~60 s o cuando la nube lo confirme | PROBABLE |
| `totem/totem_display.dart:255-277` | La tele saluda con la mesa vieja hasta 60 s después de un cambio en la oficina | Pedir la ficha cuando bajan `contratos_alumnos`, `planos_evento` o `sillas_reparto` de ese evento | PROBABLE |
| `core/services/kiosk_launcher.dart:133-137, 190-208`; `totem_display.dart:332-365` | La ventana nueva (608×1080) en una notebook de 768 de alto sale con la barra fuera de la pantalla; GIRAR con la tele de segundo monitor o DPI 125/150 % la saca de la tele | Tamaño según el área útil del monitor en píxeles reales; tomar el rectángulo del monitor actual | PROBABLE |
| `totem_display.dart:922-935`; `windows/runner/main.cpp:33` | La X de la barra del tótem (pegada a SALIR DEL KIOSCO) esconde la tele sin ayuda ni pregunta; cerrar la principal cierra el tótem | Tooltip y separarla; preguntar antes de cerrar con el tótem activo | CONFIRMADO en el código |
| `kiosk_launcher.dart:270-274` | `setEvento` anota el evento antes de saber si llegó | Anotarlo solo si llegó | CONFIRMADO en el código |
| `totem/estilos/escena_poster.dart:167-221` | Póster corta arriba los números de la mesa (franja inclinada) y los acentos del nombre | Recortar solo a lo ancho / solo abajo; `height` 1,15 | Visto en la muestra `Totem_llegada_familia` |
| `escena_neon.dart:212-236`; `escena_gala.dart:203-231` | Con 2 o 3 mesas de 3 cifras, los números pisan el anillo | `FittedBox` en el cuadrado inscripto | PROBABLE (cuenta) |
| `escena_totem.dart:1621-1659`; `escena_tu_fondo.dart:316-359` | La música larga (el link del delegado deja 300 letras) achica toda la llegada | `maxLines: 2` y `ellipsis` en el tótem | PROBABLE |
| `totem/services/foto_guardada.dart:65-75`; `estilos/fondo_propio.dart:45-72` | Una foto o un fondo que no bajó una vez queda así toda la noche (no sale del caché de imágenes) | `imageCache.evict(key)` al fallar; reintentar | CONFIRMADO en el código |
| `fondo_totem.dart:97`; `shaders/totem_neon.frag:63-68`; `escena_poster.dart:28`; `escena_gala.dart:52` | La grilla de Neón titila a las 3-4 h; Póster y Gala saltan cada minuto | Dar la vuelta al tiempo (`% 3600`); períodos que dividan 60 | PROBABLE |
| `estilos/plano_del_totem.dart:102-104` | Con un color claro (Perla) la mesa encendida casi no se ve | Oscurecer el resaltado como la ruta | PROBABLE |
| `cuadro_del_salon.dart:161, 228-246`; `escena_totem.dart:623` | En un plano de dos hojas, la tele salta de hoja en la llegada | Cuadro por hoja | CONFIRMADO en el código |
| `totem_config_sheet.dart` (varios) | Cerrar sin querer pierde lo elegido; cerrar mientras guarda deja a medias; fotos > 5 MB rechazadas; GUARDAR mientras "Leyendo la imagen…"; quitar foto/fondo borra del bucket antes del upsert | Ver el informe | CONFIRMADO en el código |
| `totem_config_provider.dart` / `totem_config` | La tabla no está en Realtime: lo que guarda el jefe desde otro equipo no llega a la tele hasta reiniciar | Releer al reanudar y al volver a la ventana | PROBABLE |
| `barra/widgets/elegir_vales.dart:200-202`; `services/papel_de_la_barra.dart:62-72` | Sin impresora elegida, el vale dice "¿La impresora está prendida y cerca?" | Distinguir "sin elegir" como "sin papel" | CONFIRMADO en el código |
| `barra/widgets/ok_del_cierre.dart:113-136, 263-291` | El OK muestra totales del equipo de la encargada sin avisar ventas faltantes; "Aceptaste el cierre" aunque la cajera volvió a vender | Avisar huecos en la numeración; releer antes de anotar | PROBABLE |
| `barra/datos/barra_local.dart:542-567` | Ventas de una tablet que nunca vuelve a tener internet no llegan a la nube | "Subir lo de esta caja desde acá" | CONFIRMADO en el código |
| `eventos/retiro_entradas_screen.dart:416-493`; `sync_engine.dart:2337` | Entrega sin internet en una PC pisa la de la otra al subir, sin aviso; talonarios controlados solo contra lo local | Avisar "dos entregas"; bajar las entregas de la fiesta antes de validar | CONFIRMADO en el código |
| `retiro_entradas_screen.dart:870-873` | El buscador del mostrador no encuentra "gomez" en "GÓMEZ" | `coincideTextoBusqueda` (`common/utils/texto_busqueda.dart`) | CONFIRMADO en el código |
| `dashboard/dashboard_screen.dart:170, 257-261` | "Cerrar sesión" no pregunta; sin internet después no se entra | Confirmar y avisar | CONFIRMADO en el código |
| `common/services/pdf_service.dart` (14 funciones con `PdfGoogleFonts`, entre ellas `:4800`, `:5920`, `:6367`) | Buscan `google_fonts/Outfit-*.ttf` pero el asset está en `assets/google_fonts/`: siempre van a internet; sin red salen en Helvetica y "—", "→", "…" en blanco; con red a medias, `http.get` sin tope | Usar `_fuentesOutfit()` (`:273`), como el recibo | CONFIRMADO en el código |
| `recepcion/central/codigo_central.dart:17, 50-67` | El código de los celulares vence a las 18 h de sacarlo, no de usarlo | Renovar al prender o reanudar | CONFIRMADO en el código |
| `central/central_puerta.dart:525-528` | Íconos y canvaskit con `max-age=86400`: una versión nueva puede mostrar cuadraditos un día | `Last-Modified` + 304, o `no-cache` | CONFIRMADO en el código |
| `puesto_main.dart:20-23`; `cliente_central.dart:420-422, 686-689` | Si la notebook cambia de IP o de puerto, los celulares no la encuentran; al reescanear, lo marcado sin señal queda en la pestaña vieja | IP fija (sin código); ofrecer "escribí la dirección nueva" y reconectar sin recargar | CONFIRMADO en el código |
| `recepcion/chat/chat_del_puesto.dart:168-214` | Un mensaje mandado al caerse el wifi se pierde; después de recargar, lo nuevo queda leído; un emoji sin internet sale como cuadradito | "Enviando" hasta que vuelva; reenviar al reconectar | CONFIRMADO en el código |

## 4. Decisiones que son del usuario

- **La cola del tótem con el salón no se acorta** (lo pidió así): 60 familias, una cada 6 s, y la última se saluda unos
  7 minutos tarde. ¿Acortar con más de N en la cola?
- **La tele sigue al desplegable de Recepción** (P5): ¿preguntar, o que deje de seguirlo?
- **P6**: cuál es "la principal" con "Al final" (debería ser la de adelante, pero conviene confirmarlo con él).

## 5. Las pruebas aisladas

Están en `build/revision/probes/` (fuera de git). Se corren con `flutter test build/revision/probes/<archivo>`.

**P1** (`config_sin_internet_probe_test.dart`). Hoy imprime `EMITIDOS: [PROMOCIÓN 2026 | foto=https://ejemplo/foto.jpg,
JUNIOR EVENTOS | foto=null]` y `QUEDA EN PANTALLA: JUNIOR EVENTOS | foto=null`.

```dart
import 'dart:async';
import 'dart:convert';

import 'package:arguello_events/features/totem/providers/totem_config_provider.dart';
import 'package:arguello_events/main.dart';
import 'package:arguello_events/models/totem_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const evento = '11111111-2222-4333-8444-555555555555';

  test('sin internet: lo que emite la config del tótem, en orden', () async {
    final guardada = TotemConfig.defaults(evento).copyWith(
      titulo: 'PROMOCIÓN 2026',
      imagenUrl: 'https://ejemplo/foto.jpg',
    );
    SharedPreferences.setMockInitialValues({
      'totem_config_v1_$evento': jsonEncode(guardada.toJson()),
    });
    final nube = SupabaseClient('http://127.0.0.1:1', 'x'); // nadie escucha
    final c = ProviderContainer(overrides: [
      supabaseProvider.overrideWithValue(nube),
    ]);
    final emitidos = <String>[];
    c.listen<AsyncValue<TotemConfig>>(totemConfigProvider(evento), (_, v) {
      v.whenData((cfg) => emitidos.add('${cfg.titulo} | foto=${cfg.imagenUrl}'));
    }, fireImmediately: true);
    await Future<void>.delayed(const Duration(seconds: 6));
    final valor = c.read(totemConfigValueProvider(evento));
    print('EMITIDOS: $emitidos');
    print('QUEDA EN PANTALLA: ${valor.titulo} | foto=${valor.imagenUrl}');
    c.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
```

**P7** (`cola_totem_probe_test.dart`). Hoy imprime `COLA después de la primera lectura: 0` y `COLA después de vaciar y
volver a leer: 50`.

```dart
import 'package:arguello_events/features/totem/services/bienvenidas_totem.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_test/flutter_test.dart';

const evento = '11111111-2222-4333-8444-555555555555';

Invitado adentro(String id, String nombre) => Invitado(
      id: id,
      eventoId: evento,
      nombreCompleto: nombre,
      dni: '',
      estadoIngreso: EstadoIngreso.ingresado,
      updatedAt: DateTime(2026, 11, 14, 22),
    );

void main() {
  test('vaciar y la lectura siguiente', () {
    final t0 = DateTime(2026, 11, 14, 23);
    final s = IngresosTotem();
    final gente = [for (var i = 0; i < 50; i++) adentro('p$i', 'PERSONA $i')];
    s.leyo(gente, ahora: t0); // primera lectura: en silencio
    print('COLA después de la primera lectura: ${s.cola.length}');
    s.vaciar(); // list_reset por el puente
    s.leyo(gente, ahora: t0.add(const Duration(seconds: 20)));
    print('COLA después de vaciar y volver a leer: ${s.cola.length}');
  });
}
```

## 6. Lo que se probó y anduvo (para no tocarlo de más)

- La suite entera (4.667 + 3 excluidos) y el análisis sin errores en `lib/`.
- En el sandbox: la central de prueba (`tool/central_prueba_test.dart`) con dos celulares en el navegador: buscar sin
  acentos, ingresar (el otro celular se entera), sumar silla con vale, frenar un vale repetido, el chat a una persona,
  VER EN EL PLANO, VER LA LLEGADA. La página del celular en Edge sin salida a internet (`--host-resolver-rules`) dibuja con
  sus íconos. El tótem (`tool/totem_salon_prueba.dart` como web): familia con mesa y camino, acompañante, profes juntos.
- Los 421 íconos existen en Flutter 3.41.9; la página del celular trae FontManifest, MaterialIcons y Roboto.
- Las funciones de la nube (`puerta_buscar`, `puerta_checkin`, `totem_lista`, `totem_clave`) coinciden con lo que llama la
  app; `sillas_puerta` está bien en el sync; ningún `async*` con `await for`.

## 7. Lo que no se puede probar sin el salón

La tele de verdad y el kiosco en ella, la notebook del salón (pantalla, DPI, plan de energía), el router propio, celulares y
tablets de verdad, la impresora, dos PCs contra la nube y el OK de la encargada desde el iPhone contra la nube.

## 8. Otros (fuera de la noche)

- Tres tests de `test/` consultan Supabase de verdad con la clave anónima escrita (`verify_supabase_content_test.dart`,
  `query_supabase_id_test.dart`, `search_supabase_broad_test.dart`): sacarlos o pasarlos a `tool/`.
- `docs/pendientes/rls-invitados.md` dice que faltan los SQL (se corrieron el 15-oct).
- La ruta `/totem_display` de `main.dart` no la abre nadie.
- Íconos que confunden: la escoba es "Saneamiento" (borra) y "Perdonar mora"; dos papeleras pegadas en Clientes
  archivados; el "+" del evento particular registra un pago; "Finalizar evento" con tilde verde; 31 de 151 botones de ícono
  sin tooltip (de la noche, solo la flecha de volver de Recepción).

## 9. Segunda revisión y qué se hizo (13-nov, noche)

Otra pasada, punto por punto contra el código en `b3ca309`, antes de tocar nada.

**Los 9 de la sección 2 son reales**, y las citas de archivo y línea coinciden. De la tabla de la sección 3 se
comprobaron 35 de 37 filas: 26 reales y 9 a medias, ninguna inventada (las otras dos son de mirar en pantalla).

**Correcciones a lo que dice arriba:**

- **P4 no es "probable": es seguro.** El aviso entre equipos baja solo las tablas que nombra, así que el OK dado desde
  la web llegaba con la red de seguridad de 5 minutos.
- **P2: "desde ayer" no.** Con fiestas dos noches seguidas, la de anoche saldría primera en la lista de la cajera. Se
  hizo "hasta el mediodía siguiente".
- **P1:** en el error conviene no emitir nada (la caché ya garantiza un valor), en vez de sumar una marca; y en
  Personalizar, frenar si lo de la nube no es lo que se abrió, en vez de "partir de la fila de la nube".
- **P5:** que el celular siga mostrando la lista después de un 4001 choca con "Cambiar el código", que usa el mismo
  4001 para echar un celular. Se resolvió del lado de la notebook: pregunta antes de pasar la central.
- **P8:** el archivo propio no sirve para la orientación (la guarda el tótem y la lee la principal). Se hizo por el
  puente.
- **`totem_config` no está en Realtime: es seguro, no "probable"** (los SQL versionados la dejan afuera a propósito).
- **Rutas:** `lib/common/...` no existe, es `lib/features/common/...`; `cuadro_del_salon.dart` está en
  `totem/services/`.
- "Si el primer ping falla queda sin internet": queda en "nube no disponible"; el motor sigue subiendo, pero el
  subir-ya de la puerta y "hay internet" quedan apagados hasta otro cambio de red.
- "El código de los celulares vence a las 18 h": con la central prendida no vence; solo al volver a prenderla.
- Vales: además, "17" y "2-17" cuentan como vales distintos, así que el mismo vale puede entrar dos veces.
- Los PDF sin internet: las 14 funciones son esas; dos piden además Outfit Light, que no viene con la app.

**P6 no se toca** (decisión del usuario, 13-nov): cuál es la mesa "principal" con "Al final" queda como está. "Si el
jefe no dijo o no modificó, debe permanecer así." Se vio en un sorteo real del 12-nov (la fiesta del 1-dic): de 11
familias con mesas al final, en las 2 de tres mesas el programa toma como principal la del fondo. **El sorteo está
bien y nadie perdió ni cambió de mesa**; solo cambia qué mesa muestran primero la tele y la puerta esa noche. Si el
jefe lo pide, el registro del sorteo ya guarda las mesas exactas que fueron al final (clave `_al_final`): la opción
(a) alcanza, sin clave nueva.

**Hecho** (en la rama, sin publicar; detalle en `docs/CONTEXTO_v6.9.0_2026-11-13.md`): P1, P2, P3, P4, P5, P7, P8, P9,
y de la tabla: el número de 20 cifras, "Todo subido" con las sillas, "Lista actualizada", la cola sin `leidaCon`, la
música larga, la foto y el fondo que no bajaron, el vale sin impresora elegida y el buscador del mostrador.

**Sin hacer, para después:** todo lo demás de la sección 3 y la sección 8.
