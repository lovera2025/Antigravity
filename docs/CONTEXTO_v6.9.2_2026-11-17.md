# CONTEXTO — la 6.9.2: la planilla del sorteo, el descuento según el sorteo, el link del delegado y "a confirmar"

**Estado (18-nov-2026): EN CURSO, sin publicar.** Se llamaba 6.10.0: **el usuario le puso 6.9.2 el 18-nov** (la
versión va a ser `6.9.2+77`). Plan aprobado por el usuario el 17-nov
(`C:\Users\lover\.claude\plans\hay-un-tema-en-precious-owl.md`), en cuatro partes. **Programadas y probadas las
Partes 1, 2 y 3** (la 3, el link del delegado, el 18-nov; guardada en git, falta correr la suite entera); la 4, sin
empezar. Nada instalado, **ningún SQL corrido** (hay uno nuevo del link esperando), `pubspec.yaml` sigue en
`6.9.1+76`. **Plan: 3 de 4 partes.**

## Para retomar en otro chat

### Dónde quedó

- **Parte 1 (la planilla del sorteo): programada, con sus pruebas y las muestras en PDF.**
- **Parte 2 (el descuento solo para lo que la familia tenía al sorteo): programada y probada entera** (18-nov): lo que
  se anota al sortear, la cuenta partida, la entrega, VENDER, los papeles, **la lista de PRECIOS para las fiestas ya
  sorteadas, el guardado de lo aceptado, la puesta al día de la tablet y el simulacro sobre una copia de la base**.
- **Parte 3 (el link del delegado): programada y probada en el sandbox el 18-nov.** El usuario vio la maqueta
  (`docs/maqueta_link_delegado_2026-11-18.html`) y, sobre las dos formas, dijo **"hacé la mejor que a vos te
  parezca"**: se hizo la **B · Todo en una hoja**. Está todo en "Lo programado el 18-nov (la Parte 3)", abajo.
  **El 18-nov cortó a mitad de las roturas a propósito y pidió dejar el contexto**: se comprobó que el corte no
  dejó nada roto (el SQL igual a su respaldo, ninguna marca de rotura en `lib/`), las reglas dan 73 de 73 y las
  pruebas del link 131 en verde. **No se corrió la suite entera después de la Parte 3**, ni se terminaron las
  roturas: es lo primero que sigue.
- **Parte 4 ("a confirmar"): sin empezar.**
- **Lo que tiene para mirar el usuario** (en `build/muestras_6.9.2/`, fuera de git): los PDF de la planilla del sorteo
  y de la de entrega con dos familias que agregaron después; las capturas `Lugares_1` a `Lugares_6` de las pantallas
  nuevas; y `simulacro_lugares_al_sorteo.txt`, la lista de cada fiesta ya sorteada, con nombres. **Se le mandaron el
  18-nov; falta su mirada** (sobre todo la lista del simulacro: es la que va a aceptar en PRECIOS).
- **Las capturas del recorrido del link** (la página del celular y la ventana del programa, de verdad, contra el
  Postgres de prueba) están en `build/capturas_6.9.2/` (fuera de git) y **se le mandaron el 18-nov al cortar; falta
  que las mire.**
- La suite entera, al cortar: ver "Cómo quedó la suite", abajo.

### Qué pidió el usuario (17-nov) y qué decidió

1. **La planilla del sorteo confundía las entradas**: sumaba las sillas extra como "generales" ("1 con cena · 9
   generales") y no nombraba las entradas de la mesa adicional. Era la cuenta del 24-sep; la regla del 4-nov (solo la
   mesa del contrato trae 8 sin cargo) nunca se le había pasado.
2. **Regla nueva del descuento** (confirmada dos veces, con un ejemplo): las entradas de la mesa adicional y las
   sillas extra que la familia **ya tenía cargadas al sorteo, pagadas o no**, van con el descuento de PRECIOS (viene
   en 50) y **las compra cuando quiera, antes o después del sorteo**. **Lo que agrega después del sorteo paga la
   entrada entera.** Quien entra a la fiesta después del sorteo con adicional, entera. Deshacer todo y sortear otro
   día: cuenta el sorteo nuevo. Restaurar: sigue contando el sorteo que se restaura.
3. **Las fiestas ya sorteadas**: pidió que el programa lo deduzca "por huellas, con el horario". Lo que no deja
   huella queda **"para revisar"** (sus palabras), sin cobrarle entera a nadie por una duda.
4. **El link del delegado**: **todos corrigen todo** (lo ya cargado se marca "ya cargado" y se puede abrir, con un
   cartel de aviso: "total, no creo que pase nada malo"); **Enviar no bloquea**; **el único cierre es la fecha
   límite**; reabre las veces que quiera poniendo otra fecha; **lo que él ya aceptó también se puede corregir** y le
   llega para aceptar de nuevo; quiere ver **quién cargó a quién y cuándo**; y una forma mejor de administrarlo.
5. **La mesa adicional "a confirmar"** (la Parte B guardada el 16-nov): **entra en esta versión, al final.**
6. Preguntó si cada cosa lleva sus pruebas: sí, se escriben junto con cada parte.

### Lo programado (17-nov, sin publicar)

**La cuenta, una sola para todos** — `lib/features/eventos/services/retiro_entradas.dart`
- `EntradasDeAlumno` pasó a `{mesas, sillas, vip, alSorteo}`. `generales` son las que completan las 8 de la mesa del
  contrato (las sillas nunca). **`alCincuenta` ya no existe**: ahora `conDescuento`, `sinDescuento`, `aComprar`, y
  `deMesas` / `deSillas` (`LugaresAparte`), para decir cada cosa en su columna.
- Los VIP que pasan de 8 ocupan, sin pagar entrada, en este orden: las mesas que tenía al sorteo, sus sillas, y
  recién después lo agregado. Así agregar un lugar nunca le sube lo que va con descuento.
- `RetiroEntradas.entradasDe(a, {foto})`, `filaPlanilla(..., foto)`, `resumen(..., foto)`; `FilaPlanillaEntrega` y
  `ResumenRetiro` llevan `conDescuento` y `sinDescuento`.
- `alPorcientoQuePaga(descuentoPct)` → "al 50 %": un solo texto para la entrega, la venta y los papeles (el
  porcentaje es el de PRECIOS, ya no va fijo).

**Lo que se anota al sortear** — `lib/models/sorteo_mesas_registro.dart` y el servicio nuevo
`lib/features/eventos/services/lugares_al_sorteo.dart`
- Claves nuevas en el `resultado` del renglón: `_lugares` (alumno → "mesas,sillas", solo de quien tiene algo más que
  la mesa del contrato) y `_lugares_el` (solo al restaurar). **Que `_lugares` esté, aunque vacío, es lo que dice que
  el sorteo los anotó.** `SorteoMesasRegistro.resultadoConLugares(crudo, lugares)` agrega la clave sin perder
  ninguna otra, tampoco una que esta versión no conozca.
- `LugaresCargados`, `FotoDeLosLugares` (`estado`: `sinSorteo`, `sinAnotar`, `anotados`; `de(alumnoId)` da null si no
  hay nada anotado → todo con descuento; con lo anotado, quien no figura tenía solo la mesa del contrato).
- `LugaresAlSorteo.sacar(alumnos)`, `primerDelJefe(registros)`, `vigente(registros)`, `paraRestaurar(registros)`,
  `enDuda(...)` (las huellas) y `alAceptar(...)`.
- **El sorteo de la fiesta es el primer renglón del jefe que sigue en pie** (los `_auto` no cuentan). Se pensó ir
  por división y se descartó: el sorteo por división es un solo renglón para toda la escuela.
- **Cada sorteo del jefe lleva `_lugares`** (`detalle_evento_masivo_screen.dart`: `_registroSorteo` y sus dos
  llamadas de SORTEAR); Restaurar copia los del sorteo que se había deshecho (`paraRestaurar`).

**Quién lo lee**
- `fotoDeLosLugaresProvider` (en `repositories/sorteos_mesas_repository.dart`): del registro de esta PC, anda sin
  internet; **si no se puede leer, todo va con descuento**; en la web no hay base.
- `retiro_entradas_screen.dart` (mira también `sorteos_mesas`), `entrega_entradas_dialog.dart` (la segunda cuenta de
  "quedan" se fue; `VentaAlCincuenta.descuentoPct`), `vender_entradas_screen.dart` (`_foto`; avisa "Agregó N lugares
  después del sorteo…"), `entradas/cuentas/lugares_de_la_familia.dart` (`sinDescuento`).
- Lo agregado después **se vende como entrada común**, sin tipo de renglón nuevo: nada cambia en
  `VentaEntradas.nueva` ni en el cierre.

**Los papeles**
- `planilla_sorteo.dart`: `PlanillaSorteo.fila` usa `RetiroEntradas.entradasDe`; campos nuevos `entradasGenerales`,
  `entradasAdicional`, `entradasSillas`; `ResumenDivision` y `ResumenPlanillaSorteo` suman `generales`,
  `conDescuento`, `sinDescuento`. De paso se fue una alarma falsa: "(!) faltan lugares" comparaba contra la principal
  sola (con dos mesas, 10 con cena entran).
- `planilla_sorteo_pdf.dart`: "8 al 50 %" debajo de la adicional y "2 al 50 %" debajo de las sillas (acostada y
  parada), "N sin descuento" para lo agregado después, los totales en el encabezado de cada división, dos tarjetas en
  el resumen (acostada, con más de 8 van en dos renglones) y la leyenda.
- `planilla_entrega_pdf.dart`: la columna se llama como dice PRECIOS; la celda "8 (+8)" (entre paréntesis, lo
  agregado después) con su leyenda.
- `pdf_service.dart`: `foto` y `descuentoPct` en las cuatro funciones de las dos planillas.

**Pruebas hechas**
- `test/planilla_sorteo_test.dart`: el caso que confundía, 10 con cena en dos mesas, lo agregado después, quien no
  figura en lo anotado, los totales, y las palabras en las cuatro hojas (interna y para repartir, acostada y parada).
- `test/retiro_entradas_test.dart`: pasó de `alCincuenta` a `conDescuento` (sin nada anotado dan lo mismo).
- `test/helpers/entrega_en_memoria.dart`: `SorteosEnMemoria` y su reemplazo; también en
  `tool/venta_entradas_prueba.dart`.

### Lo programado el 18-nov (la Parte 2, lo que quedaba)

- **Las pruebas del servicio** — `test/lugares_al_sorteo_test.dart` (71): `LugaresCargados`, `sacar`, `vigente` (sin
  sorteo, sin anotar, anotados, la pila con un automático, deshacer todo y los últimos, restaurar), `paraRestaurar`,
  la ida y vuelta de las dos claves, **la convivencia** (con y sin `_lugares` dan lo mismo `sorteosEnPie`,
  `esperado`, `resumir`, `lineaParaPlanilla`, `UltimosSorteados.de` y `MesaNuevaSola.ultimoDelJefe`), `enDuda` caso
  por caso y `alAceptar`. Y en `test/retiro_entradas_test.dart`, el grupo "con descuento y sin descuento" (la
  partición sobre una grilla de casos; agregar después nunca sube lo que va con descuento; VIP de más).
- **El guardado** — `SorteosMesasRepository.completarLugaresEn` / `completarLugares`: reescribe el texto crudo del
  renglón con `resultadoConLugares` y encola la fila entera como `insert`. No toca un deshacer ni un texto que no se
  lee. `test/sorteos_mesas_completar_lugares_test.dart` (8, sobre una base en memoria).
- **La lista** — `eventos/services/revision_de_lugares.dart` (`RevisionDeLugares`, `ListaDeLugares`,
  `PuertosDeLaRevision`, puro), su adaptador `eventos/repositories/revision_de_lugares_de_la_app.dart`
  (`revisionDeLugaresProvider`) y la ventana `eventos/widgets/lugares_al_sorteo_dialog.dart`
  (`mostrarRevisionDeLugares`). **Aceptar pide internet y relee todo** (`SyncEngine.bajarParaLosLugares`: alumnos,
  pagos, repartos y registro; con una tabla que no baje, no se guarda). Si la lista cambió mientras se miraba
  (`firma`), muestra la nueva y conserva lo ya decidido; si otra PC ya la aceptó, lo dice y no pisa nada.
  `test/revision_de_lugares_test.dart` (17) y `test/lugares_al_sorteo_dialog_test.dart` (13).
- **PRECIOS** (`precios_de_entradas_dialog.dart`): recibe `lugares` (la foto) y `revisarLugares` de quien lo abre, y
  dice qué rige: sin sorteo, "Vale para lo que cada familia tenga cargado el día del sorteo"; con los lugares
  anotados, "…al sorteo del 12/11/2026 21:40 hs"; sorteada sin revisar, el aviso en rojo y **REVISAR LA LISTA**.
  **La lista no vive en `lib/features/entradas/`**: lee alumnos y pagos (`venta_entradas_no_toca_test`).
- **ENTRADAS** (`retiro_entradas_screen.dart`): `_revisarLugares` (con su llave) y el recordatorio amarillo arriba,
  solo en modo jefe, en la oficina y mientras la fiesta esté sorteada sin la lista aceptada.
- **`sorteos_mesas` en `tablasDeLaPuerta`.**
- **Las llaves** — `test/solo_modo_jefe_test.dart` (dos pruebas nuevas: un solo camino hasta `completarLugares`, la
  segunda llave en la ventana, y el registro con una sola edición) y `test/venta_entradas_no_toca_test.dart`.
- **Roturas a propósito** (`tool/romper_una_regla.sh`): 23 reglas rotas, las 23 detectadas.
- **El simulacro** — `tool/simulacro_lugares_al_sorteo_test.dart`, el 18-nov sobre una copia del día (la base real
  quedó con el mismo SHA-256): 10 fiestas masivas, **5 sorteadas sin revisar**; en total **6 lugares tildados**
  (todos "el programa se la dio sola, sin ningún pago de mesa hasta ese momento") y **8 para revisar**. Sin aceptar
  nada, las entradas de todos dan igual que hoy; aceptando como viene, solo cambian las familias tildadas; y guardar
  lo aceptado sobre otra copia agrega los lugares a 5 renglones **sin cambiar ninguna otra tabla, renglón ni columna**.
- **Las muestras** — `tool/planilla_sorteo_muestra_test.dart` y `tool/planilla_entrega_muestra_test.dart` llevan dos
  familias que agregaron después (y la línea del sorteo como sale desde la 6.6.2, sin "· Jefe · 1 cambio");
  `tool/lugares_al_sorteo_muestra_test.dart` (nuevo) saca las seis capturas de las pantallas nuevas.

### Lo programado el 18-nov (la Parte 3: el link del delegado)

**Por qué no los dejaba entrar** (diagnóstico del 17-nov): el delegado se reconocía por el navegador (un token en
`localStorage`), no por la persona; el cupo contaba aparatos y viene en 1; con el cupo lleno la página ni pedía el
nombre; cambiar la fecha no le reabría a quien ya había enviado; y REABRIRLE actuaba sobre la fila del aparato viejo.

**Las reglas nuevas** (decididas por el usuario el 17-nov; cambian tres de las del 12-nov)
- **El delegado es la persona, no el celular** (`delegado_llave(nombre)`): el mismo nombre entra desde otro celular
  aunque el cupo esté lleno (la entrada dice "¿Ya entraste? Tocá tu nombre"), y el cupo cuenta personas. Tope de 30
  aparatos por link.
- **Todos corrigen todo**: lo que cargó otro delegado y lo que ya está en el programa se abren, con un cartel antes
  ("Vas a cambiar lo que cargó … ¿Seguir?") y lo vigente a la vista mientras pregunta.
- **Enviar no cierra**: avisa al programa y se puede enviar otra vez. Guardar después de enviar deja ese alumno
  "sin enviar" de nuevo.
- **Lo único que cierra es la fecha límite** (o CERRAR AHORA). **Se reabre las veces que quiera**: una fecha futura
  lo prende solo.
- **Quién cargó a quién y cuándo**, y un historial por alumno (tabla nueva `cambios_delegado`, solo se agregan
  filas).
- **Lo aceptado se puede corregir**: si un delegado guarda sobre algo ya aceptado, vuelve a "para traer".
- Sacar a un delegado vale para todos sus celulares; se lo puede volver a dejar entrar (`readmitir`).
- **A la grilla sigue entrando solo lo que el jefe acepta**, por el `onImportar` del Excel. Eso no cambió.

**El SQL** — `supabase/migrations/20261118120000_link_delegado_reabrir.sql`. **SIN CORRER en la nube.** Solo agrega:
la columna `cargas_delegado.enviado_at`, la tabla `cambios_delegado` (cerrada del todo, con `n` de orden) y
funciones. **Ninguna función cambia de firma** (un test lo compara con el SQL del 13-nov); se reescriben por dentro
`delegado_aviso`, `delegado_lista`, `delegado_entrar`, `delegado_guardar`, `delegado_entregar`, `delegado_link`,
`delegado_link_cambiar` y `delegado_cargas`; nuevas con usuario, `delegado_alumnos_estado(uuid)` y
`delegado_historial(uuid)` (`delegado_alumnos` es `returns table`: no se le agrega una columna con
`create or replace`). Las funciones pasan de 17 a 22. Los estados de un alumno: `falta`, `programa`, `sin_enviar`,
`enviado`, `aceptado`. **Una página vieja (la web de la 6.9.1) sigue andando con el SQL nuevo**: lo que se agrega
al JSON lo ignora.

**Las pantallas**
- `lib/features/delegado/pagina/pagina_del_delegado.dart`: la entrada con los nombres, todo se abre, el cartel de
  corregir, Enviar sin diálogo y "Enviar otra vez", "Gracias" con la hora.
- **La ventana propia, forma B**: `lib/features/eventos/widgets/link_del_delegado_ventana.dart` (nueva; reemplaza
  a `link_del_delegado_panel.dart`, **borrado**). Se abre desde **PLANILLAS ▾ → "Link para los delegados"** (solo en
  modo jefe) y desde la alerta del Centro de Comando. Arriba el estado en grande con COPIAR, CAMBIAR LA FECHA /
  REABRIR HASTA… y CERRAR AHORA; los delegados (sacar, volver a dejar entrar); los alumnos con filtro, estado, quién
  y cuándo, y el historial que se despliega; TRAER LO CARGADO abre el "Antes de guardar" de siempre. Lo que pasó se
  dice fijo abajo (`link_dicho`).
- `acompanantes_musica_dialog.dart` ya no tiene la sección del link; con `traerAlAbrir` muestra solo la revisión, y
  dice "lo cargó X · cuándo".
- **`detalle_evento_masivo_screen.dart` es el único que lee `linkDelDelegadoProvider`**
  (`_abrirLinkDeLosDelegados`, con la llave del modo jefe); la ventana recibe el link ya armado
  (`test/solo_modo_jefe_test.dart` lo vigila).
- Datos: `nube_del_delegado.dart` (`EstadoDeLaCarga`, `soloLectura => vencido`) y `link_del_delegado.dart`
  (`DelegadoDelLink`, `AlumnoDelTablero`, `CambioDelHistorial`, y en la interfaz `alumnos` e `historial`).

**Pruebas hechas**
- Las reglas, contra el mismo archivo del SQL: `tool/delegado_sandbox/` (`node pruebas.mjs`), **73 de 73**. El
  sandbox corre los dos SQL en orden (`db.mjs`: `abrir({soloLaPrimera})`, `correrLaSegunda()`), y una prueba pasa
  de la primera parte a la segunda con datos cargados.
- Las pantallas: `test/pagina_del_delegado_test.dart`, `test/link_del_delegado_en_la_ventana_test.dart`,
  `test/link_delegado_cerrado_test.dart`, `test/alertas_del_delegado_test.dart`, `test/grupo_fiesta_toolbar_test.dart`
  y `test/solo_modo_jefe_test.dart`: 131 en verde. El doble es `test/helpers/delegado_en_memoria.dart`.
- **De punta a punta en el navegador** (la página y la ventana de verdad contra el Postgres de prueba): crear el
  link, entrar, guardar, enviar (sigue abierto), **entrar desde otro celular con el cupo lleno tocando el nombre**,
  un segundo delegado corrige lo de la primera con el cartel, la alerta abre la ventana, el historial, TRAER →
  ACEPTAR Y CARGAR → "Aceptado", CERRAR AHORA y REABRIR HASTA… Salió bien. Al recorrerla aparecieron tres cosas, ya
  arregladas: el aviso nombraba a quien ya no tenía nada suyo para traer ("LAURA GÓMEZ (0)"); con el cartel
  "¿Seguir?" no se veía lo que se iba a cambiar; y lo que pasó quedaba al final de la lista, sin verse.
- Para repetirla: compilar `tool/link_delegado_prueba.dart` como la web
  (`flutter build web -t tool/link_delegado_prueba.dart --output build/link_delegado_prueba`) y `preview_start` con
  `delegado-sandbox` (`.claude/launch.json`: `tool/delegado_sandbox/servidor.mjs`, puerto 8800). **La compilación que
  hay en `build/` es anterior a los tres arreglos: compilar de nuevo.** En el navegador de la app, Flutter solo
  dibuja con la pestaña al frente, y los clics van por coordenadas.

### Lo que falta, en orden

1. **Cerrar la Parte 3:**
   - las roturas a propósito (quedaron a medias): las del SQL, cambiando una regla del archivo y corriendo
     `node pruebas.mjs` (siempre con una copia del SQL al lado para devolverlo), y las de las pantallas con
     `bash tool/romper_una_regla.sh <casos>`;
   - **la suite entera** (`bash tool/suite_por_tandas.sh`) y `flutter analyze lib test tool`;
   - que el usuario mire las capturas del recorrido (`build/capturas_6.9.2/`).
2. **Parte 4 — "a confirmar"**: `git stash pop` (`stash@{0}`), y lo que falta está en "La Parte B" de
   `docs/CONTEXTO_v6.9.1_2026-11-16.md`. Su derecho al descuento no cambia (ya la tenía cargada).
3. **Después**: la versión `6.9.2+77` (`pubspec.yaml` y el `.iss`) y publicar con él: foto de la mora, **el SQL del
   link con su OK en el momento** (comprobado con `md5(prosrc)` y una prueba en un bloque `do` que se deshace solo,
   como el 13-nov), instalador por pasos, release y web. **Al publicar, repetir el simulacro de los lugares sobre una
   copia nueva** y decirle: "no vender entradas desde un equipo sin esta versión".
4. **Queda del usuario** (no frena): mirar las muestras de la planilla y `simulacro_lugares_al_sorteo.txt`.

**El orden del SQL del link al publicar:** se corre antes de publicar la web y de instalar. La web vieja sigue
andando con el SQL nuevo; la ventana y la página nuevas **no** andan con el SQL viejo (piden funciones que no
existen).

### Lo que hay que saber antes de tocar

- **Una prueba que monte la entrega o VENDER tiene que reemplazar `sorteosMesasRepositoryProvider`**
  (`EntregaEnMemoria.reemplazos` ya lo hace; quien arme su lista a mano, con `entrega.sorteos`). Sin eso, esas
  pantallas van a leer el registro por `LocalDatabase.instance`: en `flutter test` no falla, se queda esperando (la
  pantalla no termina de cargar y 38 pruebas daban "no encontré el texto"). Se comprobó que la base de la PC no se
  tocó (su última modificación era de antes). En una ventana de prueba, `cerrarParaLaPrueba` lo hace fallar y el
  provider contesta "todo con descuento".
- **Aceptar la lista de una fiesta ya sorteada le agrega `_lugares` al renglón del sorteo que ya existe.** Es la
  única excepción a "solo se agregan renglones", y el usuario la aprobó con el plan: un renglón aparte rompería
  "deshacer solo los últimos" (la pila haría `removeLast` de ese renglón), el HISTORIAL ("Sorteo: 0 familias") y la
  línea de los papeles. Nada de lo que el renglón dice del sorteo cambia. Está en CLAUDE.md, con su test
  (`solo_modo_jefe_test`: "el registro de sorteos: solo se agregan renglones…").
- **Una vez aceptada, la lista queda fija**: `RevisionDeLugares.leer` da null con los lugares anotados y no hay
  pantalla para corregirla. Si el jefe se equivoca, hoy se arregla a mano (el renglón acepta que se le reemplace
  `_lugares`). No se pidió una pantalla para eso.
- **En esta PC no hay con qué pasar un PDF a imagen**, y las muestras se arman con las letras de la app, que
  `palabrasDelPdf` no lee: los PDF se le mandan para que los mire él. Lo que dicen los papeles lo comprueba
  `test/planilla_sorteo_test.dart` con la letra de fábrica.
- **`mora_cambios` no sirve de huella**: el trigger anota solo cuando cambia un campo de la mora, no cuando se
  agrega una mesa.
- **Lo que una huella no puede decir**: una adicional que recibió su número después del sorteo pudo estar cargada
  antes sin pagar (va "para revisar"). La única huella segura de "vino después" es el alumno cargado después del
  sorteo, o una mesa que el programa dio sola **sin ningún pago de mesa hasta ese momento** (solo pasa al agregarla
  con el sorteo hecho, la regla del 11-nov).
- **Un equipo con la 6.9.x no conoce la regla** y vende todo con descuento: al publicar, "no vender entradas desde un
  equipo sin esta versión".
- `ConfigEntradas.kDescuentoDeLosLugares` es una constante **de la clase**, no suelta.

### Cómo quedó la suite

`bash tool/suite_por_tandas.sh`, el 18-nov **después de la Parte 2**: **5.322 pruebas, ninguna falla** (305
archivos). El 17-nov a la noche eran 5.189 en 301. **Después de la Parte 3 no se corrió entera**: solo las pruebas
del link (131, en verde) y las reglas del sandbox (73 de 73).

`flutter analyze` sobre `lib`, `test` y `tool`: ningún error, y nada en los archivos tocados el 18-nov (los avisos que
quedan son de antes: `detalle_evento_masivo_screen.dart`, `dry_run_cobro_simulator.dart`, dos `tool/_tmp_*`).

**Queda para mirar** (del 17-nov): el panel del PLANO usa la misma cuenta que la planilla ("4 con cena · 4
generales") y no dice las entradas que se compran aparte (las de las sillas y la adicional); si hace falta, se le
suma un renglón.

### Lo que no se va a poder probar acá

Un celular de verdad abriendo el link desde WhatsApp, y la venta con la regla nueva en una tablet sin internet.
