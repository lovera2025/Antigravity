# Para la Técnica del 4-dic: la tele, la barra por día, la encargada en el iPhone y el repositor (25-nov-2026)

## Para retomar en otro chat

**26-nov: retomado después de la 6.9.4** (ya publicada; está en esta rama). Este chat coordina las sesiones en
paralelo: **cuando el usuario dice "actualizá", se actualiza acá y se les manda lo mismo a todas** (memoria
`actualiza-va-para-todas-las-sesiones`). El plan de esta vuelta, aprobado el 26-nov:
`C:\Users\lover\.claude\plans\sigamos-donde-nos-quedamos-expressive-matsumoto-of-dc76a2f7-5e35-44c8-9dc7-efce16acf58a.md`
(hasta el paso 3 de su lista, **y juntar cada rama apenas cierre su revisión**, con la suite, las roturas y el sandbox
sobre lo junto: lo pidió él).

**El plan aprobado** (25-nov, con el usuario):
`C:\Users\lover\.claude\plans\donde-nos-quedamos-porque-inherited-sedgewick-of-b24f55ff-68c4-4d3e-875a-b0916b95685c.md`.
La fiesta es la **Técnica Pinaroli, el 4-dic**: la primera de verdad, **sin internet**, todo por el wifi. El usuario
quiere **todo prolijo, punto por punto, y sin bugs** ("lo importante es que todo esto no tenga bugs, por favor").
**No se publica nada hasta que él lo diga**, cuando no haya más cambios.

### Dónde está cada parte

| Parte | Dónde | Estado (26-nov) |
|---|---|---|
| 0. Maquetas | acá | **Hechas y contestadas**: `docs/maqueta_encargada_iphone_y_repositor_2026-11-25.html` (`preview_start` con `maquetas`) |
| 1. La tele | sesión aparte "La tele: girar, cada tele con su escuela, todo guardado" (`local_054d7dae…`, worktree `claude/peaceful-golick-fa7148`) | programada (etapas 1 a 5); el 26-nov se le mandó cerrar sus puntos 1 a 6 (suite, ventana con dos escuelas, sandbox, capturas, roturas, revisión independiente) y avisar; **no la junta ella** |
| 2. La barra por día de operación y la madrugada | **junta en esta rama el 26-nov** (merge `53303ba`, desde `claude/sleepy-jepsen-bea21a`; su sesión ya no la toca) | revisión independiente con 9 arreglos (`eb07be5`); sobre lo junto: la suite entera **6.424 y 0 fallos**, las roturas **41 de 41** y la huella de la base IGUAL; **el recorrido con el mouse no se hizo** (el usuario no dio el permiso de la pantalla el 26-nov) |
| 3. La encargada en el iPhone por el wifi | acá, **después de juntar la Parte 2** (toca los mismos archivos) | sin empezar |
| 4. El repositor y el stock por barra | acá | **la base (sin pantallas) cerrada el 26-nov**: las pruebas de la segunda revisión, las roturas y el SPEC (ver abajo) |
| 5. Publicar | con el usuario, cuando él diga | — |

Las dos sesiones salieron de la rama feature (comprobado: su base es `2a0a0d2`). A las dos se les mandó el 25-nov
que el usuario pide **sin bugs**: tests, suite entera, roturas, sandbox con la huella IGUAL **y una revisión
independiente**. Cuando terminen, sus ramas hay que juntarlas acá (preguntarle al usuario antes de mezclar).

### Lo que decidió el usuario (todo, para no volver a preguntar)

- **Tele:** girar (Horizontal · Vertical · Dar vuelta), sin PIN; **cada tele con su escuela**, cambiada desde el
  celular de la recepción **sin PIN** (la tele está con la cuenta del jefe), con un cartel que confirma; cuando una
  cambia, a la otra le salta "La Tele 1 cambió a ESCUELA B · MANTENER · CAMBIAR". Todas las escuelas de los
  próximos 30 días guardadas sin internet; Personalizar sigue en la PC y avisa al guardar.
- **Barra por día de operación** ("como un cierre de caja en su fecha"): la caja se abre a la tarde y sigue hasta
  las 7-8; corte al mediodía. El cierre queda igual (a ciegas solo el efectivo, transferencia aparte, el OK de la
  encargada).
- **La central de la barra sigue en la notebook, una por barra.** Cada barra tiene su router **Mercusys MW305R**, en
  las dos puntas, **sin cable**. Se pueden unir por wifi (WDS); la guía está en `docs/GUIA_ROUTERS_DE_LAS_BARRAS.md`
  y **la prueba él en la oficina** (todavía no avisó). El programa tiene que andar unidas o cada barra sola. Las teles
  quizás vayan con un router cada una (no sabe): en redes separadas, las dos como Tele 1.
- **La encargada usa su iPhone**: la notebook le sirve una página por el wifi (sin internet la web no anda). Ve las
  cajas de esta noche y, arriba, los otros días; **acepta cierres y anula ventas con motivo**; el jefe también entra
  con su PIN; el aviso con sonido como en la maqueta (un toque la primera vez). Si el iPhone se bloquea o se apaga,
  retoma solo.
- **El repositor** (permiso Barra con un 3, sin SQL): trabaja con su celular, **la app si es Android y la página de
  la notebook si es iPhone**. El jefe carga el stock general **y reparte con cuánto arranca cada barra**; el depósito
  es **el límite**; "Entró mercadería" lo anota el repositor diciendo de dónde vino; repone del depósito o **de una
  barra a otra con el porqué**; deja dicho cuántas quedan y, si no da (se sabía que eran 70 y hay 68), **el motivo**
  (rota, congelada, vencida, se perdió, otro); el aviso de "está quedando poco" lo pone el jefe **por barra**; **sin
  stock no se vende**, el repositor manda **"voy en camino" a la barra que elija** y al reponer vuelve en verde;
  a las cajeras de esa barra y a la encargada les sale "Se repusieron…".
- Se compran 5 tablets Android; 4 impresoras, una por tablet. Las sillas sueltas ya las vende cualquier cajera.

### La base del repositor (Parte 4): lo hecho, sin pantallas

- `docs/SPEC_repositor_y_stock_por_barra_2026-11-25.md` (**su sección de conteos quedó vieja**: manda el código, ver
  abajo).
- `lib/features/barra/cuentas/nombre_de_barra.dart`: `claveDeBarra` (sin espacios de más, minúsculas, sin acentos)
  y `esElDeposito`. **Todo lo que compara barras pasa por ahí.**
- `lib/features/barra/datos/stock_en_la_barra.dart` (`barra_stock_barras`: el reparto del jefe, id fijo por fiesta,
  producto y clave de barra) y `movimiento_de_stock.dart` (`barra_stock_movimientos`: entrada, reposicion, traspaso,
  faltante, conteo, en_camino, en_camino_no; **solo se agregan filas**; `FotoDeStock`).
- `lib/features/barra/cuentas/stock_por_barra.dart`: **la única cuenta del stock por barra** (`StockPorBarra.de`,
  `sePuedeVender`, `cuantoSePuedeReponer`, `errorAlReponer`, `errorAlPasar`, `errorAlDescontar`, `errorDelReparto`,
  `errorAlSacarDelReparto`, `enCamino`, `enAviso`, `fotoDe`, `ajustePara`).
- **v83** en `local_database.dart` (`crearTablasV83`, solo `CREATE … IF NOT EXISTS`) y en `sync_engine.dart` (las
  listas: columnas, lo del cobro, la bajada, el orden de subida y `_tablasSinRevisarBorrados`). **El locutor pasa a la
  v84.** SQL de la nube `supabase/migrations/20261125120000_barra_stock.sql`, **sin correr**.
- Tests: `test/stock_por_barra_test.dart`, `test/migracion_v83_test.dart`, `test/sync_tablas_v83_test.dart` (y
  `migracion_v82_test.dart` quedó con la versión fija en 82). **106 en verde al 26-nov** (72 del stock, con el grupo
  "LA SEGUNDA REVISIÓN"). Roturas: `tool/roturas_repositor.txt`, **31 de 31 atrapadas el 26-nov** (las 22 de antes,
  cuatro con el texto puesto al día con el código, y 9 nuevas de la segunda revisión).

**Cómo cuenta un conteo (lo más delicado; lo encontraron dos revisiones independientes):** un conteo ("quedan 40")
guarda en `conocido` una `FotoDeStock`: **de toda la fiesta**, la venta más alta que conocía de cada caja y la fila
más nueva que conocía de cada equipo. Después, lo de ese lugar = lo contado + lo que pasó **después de contar**:
- antes de contar = lo que conocía, **o** una venta de esa caja con número menor que la que conocía, **o** una fila
  de un equipo anterior a la última que conocía de él (el orden dentro de una caja y de un equipo es seguro); solo si
  no hay otra forma, la hora;
- un conteo reemplaza a otro **solo si sabía** que el otro fue antes; los que no se conocen valen los dos y se toma
  **el que da menos**; la hora nunca decide entre conteos;
- un producto ya contado **no cambia el reparto ni el stock general** (`errorDelReparto` lo frena): lo que se mueve
  lo anota el repositor.

### Lo que falta, en orden

1. ~~Las pruebas de la segunda revisión, las roturas otra vez y el SPEC~~ **hechos el 26-nov** (9 pruebas nuevas,
   ninguna encontró un error en el código; 31 de 31 roturas; la sección de conteos del SPEC al día). **La tercera
   revisión independiente va con el paso 3**, sobre el stock ya unido con la barra por noche.
2. **Juntar las ramas** (aprobado el 26-nov). **La barra, junta el 26-nov** (ver la tabla; las roturas no corrían en
   esta carpeta: con `core.autocrlf` el archivo de casos sale con CRLF y el `\r` pegado al nombre del test hacía que
   no corriera ninguno; `tool/romper_una_regla.sh` ahora lo limpia y avisa si un test no existe). **Falta la tele.**
   Cada una apenas cierre su revisión, primero la barra y después la tele,
   con `git merge` acá. Sobre lo junto: conflictos, finales de línea LF, que nada nombre a un alumno real (contra
   `build/nombres_reemplazados_2026-11-26.md`), `flutter analyze`, la suite entera, las roturas de esa parte y la
   ventana de prueba con la huella IGUAL (`tool/dos_barras_prueba.dart`; `tool/tele_prueba.dart` con dos escuelas).
3. **Al juntar la Parte 2 con el stock**, con la tercera revisión independiente (lo contestó esa sesión el 25-nov;
   rama `claude/sleepy-jepsen-bea21a`, commits `995be5b`, `927c22f` y `6493a20`):
   - **La barra de cada caja:** una lista fija, `kBarrasDelSalon` (`lib/features/barra/services/barras_del_salon.dart`;
     no hay config por fiesta). La caja la elige obligatoria y se guarda tal cual en `sede`. Para leerla, `barraDe(sede)`
     (trim, sin distinguir mayúsculas; **null si no es de la lista**: las cajas viejas con texto libre). Cada equipo
     recuerda la suya (`barraDelEquipoProvider`) y la central también (`EstadoCentralBarra.barra`). → En
     `StockPorBarra`, el mapa caja → barra tiene que salir de `barraDe(c.sede)` (no de `claveDeBarra` a secas), y el
     reparto del jefe ofrecer las barras de `kBarrasDelSalon`. `claveDeBarra` sigue para comparar.
   - **La noche:** `lib/features/barra/cuentas/dia_de_operacion.dart`. `DiaDeOperacion.de(momento)` y `.deLaCaja(caja)`;
     "esta noche" = `DiaDeOperacion.de(ref.read(relojDeLaBarraProvider)())` (`providers/barra_del_jefe_provider.dart`,
     **la única hora de la barra**). `CajasPorDia.de(cajas)`: `.delDia(dia)`, `.idsDelDia(dia)`,
     `.ventasDelDia(ventas, dia)` (cada venta con su caja) e `.inicial(ahora:, fechaDeLaFiesta:)`. Modelo:
     `StockDeLaBarra.deLaNoche(...)` en `cuentas/stock_de_la_barra.dart`, que usan CAJAS y el "Quedan" de VENDER. →
     A `StockPorBarra.de` se le pasan `porDia.delDia(dia)` y `porDia.ventasDelDia(ventas, dia)`.
   - Lo que viaja por la central (`tablasDeLaRed`, `BarraConLaRed`) y los repositorios (`BarraLocal`, `BarraNube`)
     se hace sobre lo de esa sesión, que tocó la central. `avisos_previos` lo cuenta el repositorio con el equipo que
   va a guardar. En la página del iPhone, cada persona con su propio `device_id` ("pagina:<operador>"), o un aviso de
   un repositor lo cumpliría otro.
4. Las pantallas del repositor y el bloqueo en VENDER (con la maqueta aprobada), y la Parte 3 (la página de la
   encargada).
5. La migración v83 sobre una copia de la base real (`tool/verificar_migracion_v82_test.dart` como modelo), el SQL
   con el OK del usuario, y publicar cuando él diga.

### Pendientes del usuario

- **Confirmar una regla de la barra** (hallazgo 8 de su revisión): una caja abierta antes del mediodía del día de la
  fiesta (por ejemplo, para probar la impresora) cuenta para la noche anterior, como pide el corte al mediodía. VENDER
  lo avisa; la regla no se cambió.

- Probar los routers Mercusys en la oficina (guía en `docs/GUIA_ROUTERS_DE_LAS_BARRAS.md`) y avisar si llegan.
- La foto de "Cómo anda" con la Quint (de antes, sigue pendiente: `docs/CONTEXTO_TELE_COMO_TOTEM_2026-11-24.md`).
