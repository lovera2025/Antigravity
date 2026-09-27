# Fase 3: el plano del salón, el sorteo por bloques y la personalización

**Fecha:** 2026-09-26, puesto al día el 2026-09-27
**Rama:** `feature/v4.6-cierre-por-sesiones` (sobre la Fase 2, que sigue sin publicar)
**Estado:** en curso. Hay partes programadas y otras que faltan (ver la tabla). **Nada está publicado**: las PCs
siguen con la 5.0.0.

> **Para retomar:** leer "Estado de cada parte", "Qué pasó el 27-sep" y "Lo que falta, en orden". El texto para pegar
> en otro chat está al final.

> **Referencia:** `Fase 3` · `plano` · `armados` · `sorteo por bloques` · `planos_evento` · `mesas_movimientos` · `v73`
> Plan aprobado: `C:\Users\lover\.claude\plans\donde-nos-quedamos-glittery-waffle.md`, partes M0 a M9.
> Anterior: [CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25](CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25.md).

## De dónde salió (decisiones del usuario del 26-sep)

- **Los tres estilos del plano quedan, y cada fiesta elige el suyo:**
  - **Gala:** negro y dorado, con serif.
  - **Arquitecto:** claro, con las sillas dibujadas.
  - **Neón:** luz de fiesta por división.

  Nada viene elegido: se elige la primera vez que se abre el plano.
- **Acomodar el salón a mano y los colores y textos van sí o sí antes del sorteo.** Es la parte M9.
- **Se publica más adelante, cuando el usuario diga.** La fecha del sorteo todavía no existe.
- **Para lo difícil, un workflow de revisión** (pedido del usuario): M2, M3, M5, M6 y M9. La migración (M3) lleva el
  más estricto, con cuatro revisores.
- **Al publicar, lo primero es correr los dos SQL en la nube**, antes de instalar (ver "Al publicar").
- **La navegación nueva:** cuatro botones a la vista en la fiesta (PLANO, SORTEO, PLANILLAS, ENTRADAS). En "MÁS" no se
  saca nada; lo de la fiesta cambia de lugar. "Pasar a la lista de la puerta" queda trabado hasta diciembre.

## Estado de cada parte

| # | Parte | Programado | Guardado en la rama | Revisión |
|---|---|---|---|---|
| M0 | Arreglos de planillas ("Confirmado", "RETIRÓ", renglón que se achica si ahorra una hoja) | Sí | Sí, `b49e87c` | No hacía falta |
| M1 | Armados del Canva | Sí | Sí, `6f5b60f` | No hacía falta |
| M2 | Los tres estilos (dibujo, vista, letras) | Sí, tests en verde | **No** | **Hecha el 27-sep: 24 hallazgos confirmados, sin aplicar** |
| M3 | Base v73 y sincronización | Sí, tests en verde | **No** | SQL: hecha el 27-sep y **aplicada**. Base, sync y tests: **falta relanzarlas** |
| M5 | Sorteo por bloques o entero, diálogo y flujo | Sí, tests en verde | **No** | **Falta lanzarla** |
| M4 | Selector de estilo y armado, pantalla del plano | No | — | — |
| M6 | Fijar, dejar libres, cambiar o mover familias, historial | No | — | Workflow |
| M7 | Plano impreso y planilla con bloques y pasto | No | — | — |
| M8 | Botones a la vista y lista de la puerta trabada | No | — | — |
| M9 | Acomodar el salón, colores y textos | No | — | Workflow |

**Tests:** la suite entera pasa, **854 tests** el 27-sep (849 el 26, más 5 de los arreglos del SQL; 727 al cerrar la
Fase 2). `flutter analyze`: 313 avisos, los mismos de antes; ninguno es de los archivos nuevos.

**M2, M3 y M5 están sin commit a propósito:** el plan dice que se commitean después de la revisión y de aplicar lo
confirmado. Van en tres commits separados, en ese orden, porque el modelo de la v73 usa el estilo del plano. `git add
-p` no anda en estas sesiones, así que cada commit se arma por rutas y ningún archivo es de dos partes:
- **M2:**
  - `assets/google_fonts/` (las dos `.ttf` nuevas y sus `OFL-*.txt`) y `pubspec.yaml`;
  - `lib/features/plano/estilos/`, `dibujo/`, `widgets/vista_plano.dart`, `modelo/estado_plano.dart` y
    `services/divisiones.dart` (pasa de M5 a M2 por el hallazgo 18);
  - `test/estado_plano_test.dart`, `vista_plano_test.dart`, `pdf_assets_test.dart` y `divisiones_test.dart`;
  - `tool/plano_muestra_test.dart`.
- **M3:**
  - `lib/core/database/local_database.dart` y `sync_queue.dart`, `lib/core/services/sync_engine.dart` y
    `lib/core/utils/uuid_utils.dart`;
  - `lib/features/eventos/repositories/contratos_repository.dart`, `lib/models/plano_evento.dart` y
    `movimiento_mesas.dart`, y `lib/features/plano/repositories/`;
  - `supabase/migrations/20260926120000_planos_y_cambios_de_mesa.sql`;
  - `test/migracion_v73_test.dart`, `plano_evento_test.dart`, `planos_evento_repository_test.dart` y
    `sql_v73_coherencia_test.dart`;
  - `tool/verificar_migracion_v73_test.dart`.
- **M5:**
  - `lib/features/plano/services/sorteo_con_plano.dart`;
  - `lib/features/eventos/widgets/sorteo_mesas_dialog.dart`, `services/mesas_extra_utils.dart` y
    `detalle_evento_masivo_screen.dart`;
  - `test/sorteo_con_plano_test.dart` y `sorteo_mesas_dialog_plano_test.dart`.

## Qué hay programado

### M0 · Planillas (commit `b49e87c`)
- **Planilla del sorteo, versión interna:** la columna Reparto ya no corta "Confirmado". Toma el ancho de
  Observaciones.
- **Planilla de entrega:**
  - "RETIRÓ" y "Hermano/a mayor" entran en una línea;
  - el renglón pasa de 19 a 17 solo si con eso la división entra en menos hojas (`altoParaDivision`);
  - una división de 26 entra en una hoja.

### M1 · Armados (commit `6f5b60f`) — `lib/features/plano/modelo/`
- `armado_salon.dart`: mesas con número, hoja y posición, sectores, pasto y `ingreso`.
  - **`cortes` se calcula solo:** n y n+1 no están pegadas si están en otra hoja o a más de 4,2 radios.
  - `problemas()` y el JSON con `formato: 1`.
- `armados_predefinidos.dart`:
  - `normal_2a_p3@1`: las 78 mesas con la numeración del jefe, sin cortes;
  - `normal_2a_p45@1`: 100 mesas. Reproduce los bloques 1–24, 25–49, 50–51, 52–54, 55–80 y 81–100. Cortes en 49 y 51;
  - `normal_2a_2b@1`: 100 + la hoja B **provisoria** (filas de 6+2+6 desde el 101; por defecto 3 filas, 142 mesas);
  - `tecnica_1a_1b@1`: 130 comunes y 20 de pasto (131–150 en U).
- **Las numeraciones de las páginas 4-5 y de Técnica son propuestas**, a confirmar con el jefe. Una numeración
  publicada no se cambia: se hace `@2`.

### M2 · Los tres estilos (sin commit)
- **Estilos** (`lib/features/plano/estilos/`):
  - `estilo_plano.dart`: `EstiloPlano`, `TemaPlano` con los tres temas y `NivelDetalle`, que da cuánto detalle
    entra según el tamaño de la mesa;
  - `fuentes_plano.dart`: `cargarFuentesPlano()`, para tests y `tool/`.
- **Dibujo** (`lib/features/plano/dibujo/pintor_plano.dart`):
  - `PintorPlano` dibuja el salón;
  - `PintorResaltado` dibuja encima el pulso y el camino del tótem (diciembre);
  - `EncuadrePlano` y `mesaEnPunto`.
- **Vista** (`lib/features/plano/widgets/vista_plano.dart`): `VistaPlano`, sin base ni Riverpod, reusable por el
  tótem.
- **Estado** (`lib/features/plano/modelo/estado_plano.dart`): `OcupantePlano` y `EstadoPlano` (ocupada, vacía,
  libre, fijada, conflicto, fuera del plano).
- **Letras:**
  - `assets/google_fonts/CormorantGaramond-SemiBold.ttf` y `TiltNeon-Regular.ttf`, bajadas de Google Fonts, con sus
    licencias `OFL-*.txt`;
  - `pubspec.yaml` declara `fonts:` PlanoGala, PlanoNeon y PlanoLinea.
- **Tests:** `test/vista_plano_test.dart`, `test/estado_plano_test.dart` y `test/pdf_assets_test.dart`, que ahora
  también lee las letras nuevas.
- **Muestras:** `flutter test tool/plano_muestra_test.dart --dart-define=salida=<carpeta>` genera PNG de los tres
  estilos lado a lado y de cada armado y hoja. El usuario ya vio la primera versión.

### M3 · Base v73 (sin commit)
- **`local_database.dart`:**
  - `_version = 73`;
  - `crearTablasV73`, con solo `CREATE ... IF NOT EXISTS`;
  - el bloque `if (oldVersion < 73 && newVersion >= 73)`. La guarda de `newVersion` es obligatoria para los tests de
    la v72;
  - `_onCreate` y la red de `_initDb`, que reintenta v72 y v73 por separado;
  - la copia automática, que queda como `antes_de_v73.db`.
- **Tablas:**
  - `planos_evento`: una fila por fiesta. Id fijo `UuidUtils.planoEventoId`, `evento_id` UNIQUE, `armado`,
    `armado_json` (la copia del armado), `estilo`, `modo_sorteo` y `config` (JSON: fijadas, libres, orden de
    divisiones, bloques, colores, título y subtítulo; las claves desconocidas se conservan). **Desde el 27-sep el id
    no lo elige nadie:** `PlanoEvento.nuevo` ya no recibe `id` y lo arma solo, y `PlanosEventoRepository.guardarEn`
    tira `ArgumentError` si le llega un plano con otro id (`tieneIdFijo`). Dentro del sorteo eso deshace la
    transacción entera;
  - `mesas_movimientos`: solo se agregan renglones (`tipo`, `antes`, `despues`, `motivo`, `deshace_id`, `avisos`).
- **Modelos y repositorios:**
  - `lib/models/plano_evento.dart` (`PlanoEvento`, `ConfigPlano`, `ModoSorteo`, `MesaFijada`, `MesaLibre`,
    `BloqueDivision`);
  - `lib/models/movimiento_mesas.dart`;
  - `lib/features/plano/repositories/planos_evento_repository.dart` (con `traerDeLaNube`) y
    `mesas_movimientos_repository.dart`.
- **`ContratosRepository.asignarNumerosMesa`** suma `movimiento` y `plano` opcionales, en la misma transacción. Sin
  ellos hace lo mismo que antes.
- **Sync:**
  - las dos tablas están en `_incrementalColumns`, `_tablasDeCarga`, `getPriority` (2), `_pullFromCloud`,
    `_cleanForSqlite` (todas las columnas) y en las relaciones de `sync_queue.dart` bajo `eventos`;
  - no están en ninguna lista que borre.
- **Nube:** `supabase/migrations/20260926120000_planos_y_cambios_de_mesa.sql`, **sin correr**.
  - **Sin CHECK** en estilo, modo y tipo, por la trampa del "violates" del motor de sync.
  - `unique (evento_id)`, RLS authenticated, triggers de `updated_at`, ROLLBACK y verificación.
  - Desde el 27-sep, el ROLLBACK de la sección 3 lleva también `alter table ... disable row level security` y la
    verificación consulta `pg_policies` (tiene que dar dos filas). Sin eso, deshacer solo esa sección dejaba las
    tablas cerradas para la app, y el control decía que estaba todo bien.
  - **Queda así a propósito:** `_hijasEnCascada` (`sync_engine.dart`) no tiene las tablas nuevas, igual que las de la
    v72. Al borrar una fiesta quedan filas huérfanas locales que nadie lee; sumarlas sería otro camino que borra.
- **Tests:**
  - `test/migracion_v73_test.dart`: 71→73, 72→73, dos veces, vuelta a la 5.0.0, copia y unicidad;
  - `test/plano_evento_test.dart` (con el id fijo);
  - `test/planos_evento_repository_test.dart` (27-sep): `guardarEn` guarda y encola el plano con su id, y uno con
    otro id no se guarda y deshace la transacción;
  - `test/sql_v73_coherencia_test.dart`: el SQL contra `toMap()`, el ROLLBACK completo y la consulta de la policy.
- **Herramienta:** `tool/verificar_migracion_v73_test.dart`, para correr sobre una copia de la base real. Espera las
  cinco tablas nuevas vacías. **Todavía no se corrió**: va en la verificación final.

### M5 · Sorteo con plano (sin commit)
- **`lib/features/plano/services/sorteo_con_plano.dart`: el motor del sorteo no se toca.**
  - **`CasillerosPlano`:** las mesas en fila para el motor, con un casillero fantasma ocupado en cada corte y el pasto
    al final.
  - **`preparar`:** la vista previa. Por bloques simula el sorteo con una semilla fija, así lo que muestra es lo mismo
    que hace el sorteo.
  - **`sortear`**, que es la que reparte de verdad.
  - **`validar`**, la red final antes de guardar.
  - **Por bloques:**
    - cada división va en el bloque más chico donde entra, seguido del anterior;
    - el bloque arranca en la primera mesa disponible;
    - se completan primero los que ya tienen algo o tienen mesas fijadas;
    - los que llegan tarde van al hueco de su bloque; si no, a la reserva; si no, a cualquier mesa libre, con aviso;
    - con números ya repartidos y sin bloques guardados, se sortea entero (`modoForzado`).
  - **Entero:** "de la mesa 1 a la N", con la N mínima propuesta.
  - **Pasto:** solo si se tilda; `necesitaPasto` avisa cuando sin él no entra.
- **`lib/features/plano/services/divisiones.dart`:** agrupa "5° a" con "5° A", orden natural, y avisa las parecidas
  ("1"/"1RA").
- **Diálogo `sorteo_mesas_dialog.dart`:** con plano, en vez de la capacidad muestra la sección del salón:
  - los modos;
  - el orden de divisiones con flechas, A-Z y al azar;
  - el rango de cada bloque;
  - "Usar de la mesa 1 a la";
  - la casilla del pasto.

  Sin plano queda idéntico. `SorteoMesasDialogResult` suma `modo`, `ordenDivisiones`, `usarPasto` y `hastaMesa`.
- **Flujo `detalle_evento_masivo_screen.dart`:**
  - `_sortearMesas` carga el plano (nube y, si falla, local) y controla que no hayan cambiado las divisiones ni el
    plano;
  - `_ejecutarSorteoConPlano` guarda números, registro y bloques en una transacción y llama a `subirYa`;
  - "Deshacer" borra los bloques guardados, para que el próximo sorteo los arme de nuevo.
- **Tests:**
  - `test/sorteo_con_plano_test.dart`: casilleros, entero, pasto, los bloques exactos del Canva del jefe, orden,
    fijadas y libres, el que llega tarde, la red final y **estrés con los tamaños reales de las nueve escuelas**;
  - `test/divisiones_test.dart`;
  - `test/sorteo_mesas_dialog_plano_test.dart`.

## Qué pasó el 27-sep

### Las revisiones del 26 no terminaron
Se cortaron entre las 23:43 y las 23:50:
- cinco revisores quedaron frenados en un permiso rechazado (querían correr `flutter test`, Python o `grep` en el pub
  cache);
- el sexto chocó con el límite de uso.

Terminó uno solo, el del SQL de M3. Sus dos hallazgos se aplicaron (ver M3 arriba): el id fijo del plano y el ROLLBACK
con la verificación de la policy.

### Cómo se lanzan ahora, para que no se corten
- **Los revisores solo leen:** Read, Grep y Glob, dentro del proyecto y del scratchpad. Nada de Bash, PowerShell ni
  `flutter`.
- **Antes de lanzarlos, lo que necesitan lo preparo yo:**
  - la suite completa;
  - los PNG (`tool/plano_muestra_test.dart`) y sus recortes a tamaño real;
  - los `git diff` de los archivos que ya existían, guardados en el scratchpad.
- **De a una revisión por vez**, para no chocar con el límite.
- **Los scripts:**
  - M2, que sirve de molde para las demás:
    `C:\Users\lover\.claude\projects\C--Users-lover-Documents-Antigravity--Gemini--arguello-events\7a5dcc54-5f1a-4889-9d89-eabbe7eed6ed\workflows\scripts\revision-estilos-plano-wf_2aa2aac0-a4a.js`;
  - M3, el del 26:
    `...\d2c3c2e7-1db7-4f91-aa4c-2ccd69573cc6\workflows\scripts\revision-migracion-v73-wf_ee0caa28-d13.js`. Para
    relanzarlo:
    - sacarle el revisor del SQL, que ya está;
    - sacarle el "podés correr flutter test";
    - sumarle lo ya aplicado (el id fijo y el ROLLBACK) y que `_hijasEnCascada` queda así a propósito;
    - pasarle el diff y las copias de la 5.0.0 (`git show 36e8958:<archivo>`).
  - M5: falta escribirlo. Tres revisores (el motor, el diálogo con el flujo, los tests con `divisiones.dart`) y un
    verificador, como el de M2.

### Revisión de M2: 24 hallazgos confirmados, sin aplicar
Run `wf_2aa2aac0-a4a`: tres revisores (lo que se ve, el código, los tests) y un verificador. Hubo 33 hallazgos: 24
confirmados y 9 descartados. El detalle completo, con la razón de cada uno, está en
`C:\Users\lover\.claude\projects\C--Users-lover-Documents-Antigravity--Gemini--arguello-events\7a5dcc54-5f1a-4889-9d89-eabbe7eed6ed\subagents\workflows\wf_2aa2aac0-a4a\journal.jsonl`
(la última línea `"type":"result"` es la del verificador).

Lo que está bien, según los revisores:
- Gala sale con cifras de altura pareja;
- ninguna silla toca otra mesa;
- el encuadre y `mesaEnPunto` coinciden en cualquier tamaño;
- `save`/`restore` están balanceados;
- la caché de textos tiene tope.

**El dibujo** (`pintor_plano.dart` y `estilo_plano.dart`):
1. **(alta) El anillo del pulso cruza el apellido de la familia resaltada** (`PintorResaltado.paint`, ~632): en Gala
   y Neón pasa por la mitad del nombre. Arreglo: recortar la franja del apellido antes de dibujar el anillo
   (`clipRect` con `ClipOp.difference`, con el mismo `abajo` de la línea 234).
2. **(alta) Los apellidos no tienen ancho máximo** (~228): dos de 9 letras en columnas vecinas (a 90 u) casi se tocan;
   uno más largo se pisa con el de al lado o se sale de la hoja. Arreglo: tope de ~2,15 radios, achicar hasta el 75 %
   y después cortar con "…"; que no salga de la caja de la hoja.
3. **(media) El atenuado deja la mesa transparente**: con una familia resaltada, el resto queda al 37 %, se ve la
   grilla a través de las mesas y los apellidos quedan ilegibles (~2:1). Arreglo: un disco opaco de fondo debajo y
   alfa ~0x99.
4. **(baja) Una capa por mesa apagada** (~203): 76 a 100 `saveLayer` por repintado, y recortan los apellidos largos.
   Arreglo: una sola capa alrededor del bucle de las apagadas (junto con el 3).
5. **(baja) Una familia resaltada en la otra hoja apaga la hoja entera** (~86). Arreglo: foco solo con las mesas de
   la hoja, también en `VistaPlano` (línea 112).
6. **(media) Neón: los sectores no tienen línea, solo el halo** (~143), y el escenario no se distingue de los demás.
   Arreglo: trazo nítido después de `_conBrillo`, relleno propio del escenario, y escenario + pasarela en un solo
   `Path` (une la T y saca la muesca de las esquinas también en Gala y Arquitecto).
7. **(media) La grilla termina con dientes y la hoja B queda como una franja** (~123). Arreglo: grilla sobre todo el
   rectángulo visible, desde el múltiplo de 50 anterior.
8. **(media) Neón: todos los apellidos van en el rosa de la división 2** (`tituloSuave`). Arreglo: un neutro, por
   ejemplo `#A9AFFF`.
9. **(media) Gala: la joya "topacio" es del mismo dorado que el anillo** (5.ª división). Arreglo: cambiar la paleta
   (turquesa al 5.º lugar, reemplazar el topacio; ojo que rubí y granate también se parecen).
10. **(baja) Neón: la 1.ª división tiene el mismo color que una familia sin división y que la ruta**, y el pasto es
    igual a la 8.ª. Arreglo: `mesaBorde` y pasto propios, y un test de paleta por tema (sin colores repetidos,
    `numeroDivision` del mismo largo).
11. **(media) La mesa fijada muestra el candado pero no para quién**. Arreglo: dibujar el apellido de `fijadaPara`.
12. **(baja) Gala: el candado tapa la joya**. Arreglo: el candado a las once (`Offset(-r * 0.72, -r * 0.72)`).
13. **(media) Neón: una mesa vacía seleccionada queda con el número casi invisible** (~348). Arreglo: con foco y sin
    familia, rellenar con `tema.resaltado`.
14. **(baja) "Escenario" es el rótulo más chico del plano** (~164). Arreglo: `alto * 0.6` con tope 30, y achicar si
    no entra en el lado largo.

**La vista** (`vista_plano.dart`):
15. **(media) Volver a prender `animar` rompe en debug**: `SingleTickerProviderStateMixin` admite un solo ticker.
    Arreglo: un solo controller, con `repeat()`/`stop()`.
16. **(media) El pulso corre siempre, aunque no haya nada resaltado**: la app nunca queda quieta y un `pumpAndSettle`
    se cuelga. Arreglo: animar solo si hay algo resaltado en la hoja o hay ruta.
17. **(baja) El pulso repinta toda la pantalla de alrededor**. Arreglo: `RepaintBoundary` propio y el
    `AlwaysStoppedAnimation` guardado en el State.

**El estado** (`estado_plano.dart`):
18. **(media) Agrupa las divisiones por texto exacto, pero el orden guardado está en claves.** Arreglo:
    - agrupar por `Divisiones.clave`, con `''` y null como "sin división", sin color y al final;
    - el orden en claves, sin las que no tienen familias;
    - un mapa clave → nombre para la leyenda;
    - una fijada sin números se ordena por su mesa.

    **Por eso `lib/features/plano/services/divisiones.dart` y `test/divisiones_test.dart` pasan al commit de M2.**
19. **(media) Pierde la marca de fijada o libre si la mesa además tiene familia.** Arreglo: `InfoMesa` con `libre` y
    `fijadaPara` siempre, y conflicto si está fijada para otra familia o si es libre y está ocupada.
20. **(baja) Una fijada o libre que el armado no tiene desaparece sin aviso.** Arreglo: listas propias, para que la
    pantalla avise.
21. **(baja) Si la mesa principal cae fuera del plano o en conflicto, el apellido no sale en ninguna.** Arreglo: la
    principal sobre las mesas que se dibujan.

**Los tests:**
22. **(media) Nada controla que las letras coincidan** entre `FuentesPlano`, `pubspec.yaml` y `cargarFuentesPlano()`,
    y `vista_plano_test` dibuja con la letra de prueba. Arreglo: `setUpAll(cargarFuentesPlano)` y un test que lea
    `FontManifest.json`.
23. **(media) `pdf_assets_test` no prueba que el PDF lea las letras nuevas** (`Font.ttf` no puede fallar). Arreglo:
    `fontName` y un `pw.Document` con "0123456789 ÁÉÍÓÚÑ 5° A" que se guarde.
24. **(baja) `vista_plano_test` solo recorre la hoja A de la página 3.** Arreglo: el toque en la hoja B (la 102 está
    donde la 1 de la A) y el dibujo con fijada, conflicto, libre, pasto y seleccionada.

**Descartados (9):**
- cinco duplicados;
- el anillo del pasto sobre las sillas en Arquitecto: se mete ~1 px, es un gusto;
- tocar afuera para deseleccionar: es el contrato elegido; si M4 o M6 lo necesitan, se suma `onTapFuera`;
- la cobertura de `NivelDetalle`: es un gusto;
- lo que le falta al plano para el tótem: es cierto, pero es de diciembre. Quedó anotado en
  `docs/pendientes/totem-apariencias.md`.

### Puntos a mirar en la revisión de M5 (sin confirmar)
- **Una fijada con un número que el armado no tiene rompe el sorteo.** Entra en `actuales` sin control, y
  `aCasilleros` hace `cas.casillero(n)!` (`sorteo_con_plano.dart:357`). Lo vio el verificador de M2.
- **La vista previa y el sorteo pueden no coincidir.** La vista previa usa `Random(0)` y el sorteo `Random.secure()`.
  En dos pasos el azar decide qué mesas quedan ocupadas antes de los bloques siguientes:
  - el paso 1, que completa en todo el salón a los que ya tienen algo;
  - la reserva de los que llegan tarde.

  ¿Puede cambiar un bloque entre lo que muestra el diálogo y lo que se guarda?
- **Deshacer y después Restaurar pierde los bloques.** Deshacer borra los bloques guardados; Restaurar devuelve los
  números pero no los bloques. Después, el sorteo por bloques se fuerza a entero y la planilla (M7) no tiene bloques.
- **"Usar de la mesa 1 a la N" se ignora sin avisar** si N pasa la última mesa o no existe: se usa la mínima.
- **El control de cambios mira solo lo local.** `_sortearMesas` lee el plano de la nube al abrir el diálogo, pero
  `planoFresco` lee solo el de esta PC.
- **Un `armado_json` roto** hace fallar `plano.armado` (es `late final`) al abrir el diálogo.

## Lo que falta, en orden

1. **Aplicar los 24 hallazgos de M2** ("Revisión de M2", arriba), con los tests que propone cada uno. Después:
   - regenerar los PNG y **mandarle al usuario `Plano_3_estilos.png`** y alguno con una familia resaltada;
   - suite completa y `flutter analyze` sin avisos nuevos;
   - commit de M2, "el plano en tres estilos", con las rutas de arriba.
2. **Relanzar la revisión de M3**, solo base, sync y tests (ver "Cómo se lanzan ahora"). Aplicar lo confirmado, suite
   y commit de M3, "lugar propio para el plano y los cambios de mesa", que lleva también los arreglos del SQL.
3. **Revisión de M5**, con un script nuevo y los "Puntos a mirar". Aplicar, suite y commit de M5, "sorteo por bloques
   o entero".
4. **M4:** `widgets/elegir_plano_sheet.dart` y `plano_evento_screen.dart`. El detalle está en el plan.
5. **M6:** fijar y dejar libres en `config`; cambiar y mover familias con motivo, deshacer y `mesas_movimientos`;
   `RegistroSorteo.resumir` con movimientos; `historial_sorteo_sheet.dart`. Lleva workflow.
6. **M7:** `plano_pdf.dart` (sin `pw.Page` de alto fijo), y pasto y bloques en la planilla del sorteo.
7. **M8:** `grupo_fiesta_toolbar.dart` y la lista de la puerta trabada (`kListaPuertaHabilitada = false`).
8. **M9:** acomodar el salón (`services/editar_armado.dart`) y colores y textos. Lleva workflow.
9. **Verificación final:**
   - PNG y PDF de muestra para el usuario;
   - `tool/verificar_migracion_v73_test.dart` sobre una copia de la base real, mostrándole la tabla de antes y
     después. El OK ya está dado en el plan.
10. **Documentación:** cerrar este CONTEXTO, poner CLAUDE.md al día (base v73, tablas nuevas, `lib/features/plano/`)
    y la memoria.

## Al publicar (recién cuando el usuario diga)

1. **Primero, una noche después de las 20 hs y con su OK, correr en la nube los dos SQL:**
   - `supabase/migrations/20260925120000_sillas_retiro_sorteos.sql` (Fase 2);
   - `supabase/migrations/20260926120000_planos_y_cambios_de_mesa.sql` (Fase 3).

   Cada uno con los conteos de antes y después.
2. Instalar unos días antes del sorteo: primero el operario, después el jefe. No sortear ni entregar entradas hasta
   que las dos PCs tengan la versión nueva.

## Lo que tiene que traer el usuario (no frena la programación)

- **La página 6 del Canva (Normal 2B), entera.** La Normal necesita 132 mesas: no alcanzan ni la página 3 (78) ni la
  4-5 (100).
- **La fecha del sorteo.**
- **Las respuestas del jefe** (ver "Queda para el jefe" en el CONTEXTO de la Fase 2):
  - qué armado usa cada escuela;
  - si aprueba las numeraciones propuestas;
  - si el pasto va desde el 131 y se usa solo si hace falta;
  - qué escuelas van por división y cuáles enteras;
  - por qué Técnica usó el pasto si le sobran mesas.

## Para seguir en otro chat, pegar

```text
Seguimos con la Fase 3 del plan de mesas (plano en tres estilos, sorteo por
bloques, personalización). Leé primero docs/CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26.md
(secciones "Estado de cada parte", "Qué pasó el 27-sep" y "Lo que falta, en
orden"), el plan en C:\Users\lover\.claude\plans\donde-nos-quedamos-glittery-waffle.md
y la memoria del proyecto. M2, M3 y M5 están programados, con 854 tests en verde,
pero sin commit. La revisión de M2 ya se hizo: aplicá sus 24 hallazgos, mandame
las imágenes nuevas y commiteá M2. Después relanzá la revisión de M3 (faltan base,
sync y tests; los arreglos del SQL ya están aplicados), aplicá y commiteá M3.
Después revisá M5 con un workflow nuevo y commitealo. Los revisores solo leen:
los tests, las imágenes y los diffs los preparás vos antes. Seguí con M4, M6, M7,
M8 y M9, en ese orden. No se publica ni se corre SQL hasta que yo lo diga.
```
