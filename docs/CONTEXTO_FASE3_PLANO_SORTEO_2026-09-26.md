# Fase 3: el plano del salón, el sorteo por bloques y la personalización

**Fecha:** 2026-09-26, puesto al día el 2026-10-01 (ver "Qué pasó el 1-oct": las medidas del playón)
**Rama:** `feature/v4.6-cierre-por-sesiones` (sobre la Fase 2, que sigue sin publicar)
**Estado:** en curso. Las etapas 1 a 4 del plan de la 6.0.0 y la 4b (las medidas del salón) están hechas y subidas;
faltan M4, M6, M7, M8 y M9 (ver la tabla). **Nada está publicado**: las PCs siguen con la 5.0.0.

> **Para retomar:** leer "Estado de cada parte", "Qué pasó el 1-oct" y "Lo que falta, en orden". El texto para pegar
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
| M2 | Los tres estilos (dibujo, vista, letras) | Sí | Sí, `1b8afed` (30-sep) | Hecha el 27-sep; **los 24 hallazgos aplicados el 30-sep** |
| M3 | Base v73 y sincronización | Sí | Sí, `e335e00` (30-sep) | Hecha y **aplicada el 30-sep** (SQL, base, sync y tests) |
| M5 | Sorteo por bloques o entero, diálogo y flujo | Sí | Sí, `aaa0034` (30-sep) | Hecha y **aplicada el 30-sep** |
| — | Mesas y sillas de cada uno en la grilla, con su filtro (pedido del 30-sep) | Sí | Sí, `087e904` (30-sep) | No hacía falta |
| 4b | Las medidas del salón: el plano en metros, cuántas mesas entran y "armar a medida" del playón (pedido del 1-oct) | Sí | Sí, `0f46110` (1-oct) | No hacía falta |
| M4 | Selector de estilo y armado, pantalla del plano | No | — | — |
| M6 | Fijar, dejar libres, cambiar o mover familias, historial | No | — | Workflow |
| M7 | Plano impreso y planilla con bloques y pasto | No | — | — |
| M8 | Botones a la vista y lista de la puerta trabada | No | — | — |
| M9 | Acomodar el salón, colores y textos | No | — | Workflow |

**Tests:** la suite entera pasa, **1.118 tests** el 1-oct, al cerrar la etapa 4b (1.039 el 30-sep a la noche; 913 al
cerrar M2, 984 con M3, 1.034 con M5; 854 el 27-sep; 727 al cerrar la Fase 2). `flutter analyze`: 313 avisos, los mismos de antes; ninguno es de los
archivos nuevos.

**Todo lo programado está commiteado y subido.** El working tree queda limpio. Lo que falta programar es M4, M6, M7,
M8 y M9 (ver "Lo que falta, en orden").

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

### M2 · Los tres estilos (commit `1b8afed`)
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

### M3 · Base v73 (commit `e335e00`)
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

### M5 · Sorteo con plano (commit `aaa0034`)
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

## Qué pasó el 29-sep (fuera de la Fase 3)

La Fase 3 no avanzó: M2, M3 y M5 siguen programados y sin commit, igual que el 27. Antes de seguir, el usuario
pidió otras cosas. El código quedó subido a la rama y **no está instalado** (las PCs siguen con la 5.0.0). Los
cambios de datos (puntos 3 a 5) sí están aplicados en la base y en la nube.
Plan: `C:\Users\lover\.claude\plans\donde-nos-quedamos-compressed-stallman.md`.

1. **El recibo reimpreso contaba mal las cuotas** (`0c679ad`).
   - GAUNA, GERALDINE (Puerto Viejo) tenía 6 cuotas y el papel decía 4/9; SEGOVIA, PABLO daba 5 o 4.
   - La causa: el recuadro dividía por el total del contrato, que incluye las mesas y sillas extra. Le pasaba a 42
     alumnos.
   - Ahora cuenta desde los pagos hasta esa fecha (`progresoAlDia`, en `cobro_abono_acumulado.dart`), por los dos
     caminos: la ficha y Finanzas.
   - Con `tool/recibo_reimpreso_muestra_test.dart` se revisaron 538 alumnos con los datos reales. Solo uno no
     coincide: MONTENEGRO, FRANCISCO NAHUEL (Colegio Nacional). La ficha dice 6 cuotas, pero no existe el pago de la
     cuota 4, ni en la base local ni en la nube. **Falta contárselo al usuario.**
2. **Mi Empresa, panel SALDO DEL NEGOCIO** (`9faf522`):
   - "Disponible en efectivo" y "Disponible en transferencia" debajo del total;
   - "En qué se fue" muestra solo los gastos. Las extracciones van en una sección aparte que arranca cerrada, y en
     el historial se ven con su propio chip (`lib/features/mi_empresa/extracciones.dart`);
   - "Traer del negocio" y "Registrar pago" vienen sin medio elegido y controlan contra lo disponible en el medio.
   - Las categorías mal cargadas (EXTRACCION, COMPRA BEAM y AUTO 408 dentro de "Operadores") **no se tocan**, por
     decisión del usuario.
   - La cuenta del recibo reimpreso marca a MONTENEGRO como único alumno que no coincide (ver abajo).
3. **ESMAY, THIAGO**, aplicado en la base real con OK y copia (`tool/revertir_sillas_esmay_test.dart`):
   - el pago de sillas del 25/06 volvió de $8.000 a $12.000;
   - las sillas quedaron en $36.000, pagadas;
   - el saldo sigue en $70.000 y las cuotas en 7.
4. **El retiro de $49M del 21-sep**, aplicado con OK y copia (`tool/partir_retiro_21sep_test.dart`). Quedó en
   $28.733.965,83 en efectivo y $20.266.034,17 por transferencia, así el efectivo del negocio deja de dar negativo.
   El total apartado no cambió.

5. **MI BOLSILLO pasó de $0 a $20,3M después del punto 4.**
   - El bolsillo se contaba por medio y sumaba solo el que daba positivo: en efectivo −$20,3M, en transferencia
     +$20,3M.
   - Arreglo en la base, con OK y copia (`tool/partir_gasto_personal_21sep_test.dart`): el gasto personal de $69M
     del 21-sep se partió igual que el retiro, $48.733.965,83 en efectivo y $20.266.034,17 por transferencia. El
     bolsillo volvió a $0 en los dos medios, verificado en Supabase; el negocio no cambió.
   - Arreglo en el código (`0f4a799`): el total del bolsillo ahora es lo apartado menos lo gastado, y cada medio
     queda entre cero y ese total (`saldoBolsillo`, en `bolsa_personal_helpers.dart`).

Los tres cambios de datos (Esmay, el retiro y el gasto) se subieron con "Subir pendientes" y se verificaron en
Supabase. Las copias de antes están en `Documents\Junior Eventos\data.db.bak.{esmay,retiro,gasto}.*`. La suite pasa:
**873 tests**.

**MONTENEGRO, FRANCISCO NAHUEL (Colegio Nacional): quedó pendiente el 29 y lo resolvió el usuario el 30-sep** (ver
"Qué pasó el 30-sep"). Lo de abajo es cómo estaba el 29.
- Tiene 5 pagos de cuota, pero la ficha dice 6 cuotas y una deuda de $150.235. Contado desde los pagos serían 5 y
  $180.235.
- Los pagos del 19/09 se guardaron como "Cuota Base (5/9)" y "(6/9)". Los cobró otra PC (`pc-1786747234482`, Maxi,
  turno Mañana), que al recalcular contó 6 pagos de cuota. O sea que esa PC tenía un pago de cuota 4 que no está ni
  en esta PC (`pc-1784250399472`) ni en la nube. En las copias de esta PC, al 03-sep había 3 pagos y la ficha decía
  3.
- La cuota vence el 30-sep y la mora se ve desde el 1-oct.
- El usuario va a buscar el comprobante: los pagos por transferencia se mandan por WhatsApp y él les pasa el PDF
  del recibo.
  - **Si la cuota 4 está pagada:** revisar en esa PC si el pago quedó sin subir ("Subir pendientes"). Si no aparece,
    volver a cargarlo con la fecha y el monto del comprobante. La ficha queda en 6/9.
  - **Si no está pagada:** corregir la ficha a 5/9 y $180.235 (DRY-RUN, OK, copia, después de las 20 hs).

**Ojo:** no correr la app (`flutter run`) desde este working tree. La v73 (M3) todavía está ahí sin commit, y como
usa la `data.db` real, la migraría.

## Qué pasó el 30-sep

**Plan aprobado: el camino hasta la 6.0.0.** Está en
`C:\Users\lover\.claude\plans\en-que-nos-quedamos-radiant-gadget.md`. Decisiones del usuario:
- **Todo va en una sola versión, la 6.0.0** (`6.0.0+57`): lo que ya está en la rama desde la 5.0.0 (lo del 29-sep, la
  Fase 2, M0 y M1), el resto de la Fase 3 y el pedido nuevo de la grilla. Sin versiones intermedias.
- **Build y publicación incluidos.** Los dos SQL de la nube siguen yendo después de las 20 hs y con su OK en el
  momento.
- **Los datos siguen al día:** la versión es solo el programa. La copia `antes_de_v73.db` es la última red y no el
  camino para volver atrás, porque restaurarla dejaría afuera lo cobrado después de instalar.
- Para volver atrás en el código quedó el tag `antes-de-6.0.0` sobre `af2970d`.

**MONTENEGRO, FRANCISCO NAHUEL: resuelto por el usuario el 30-sep.** En la nube la ficha dice 5 cuotas y $180.235.
Los dos cobros del 19/09 de las 13:36 (cuota 4, mora $39.300 y cargo $3.465), que estaban trabados en la otra PC,
quedaron anulados; el de las 13:45 quedó como cuotas 4/9 y 5/9. No hay nada más que hacer.

**CACERES, ANAEL** (Normal Mariano Iloza) tiene 2 sillas extra guardadas sin precio desde antes de agosto: figura así
en todas las copias locales desde el 3-ago. Es el único caso de la base. **Decisión del usuario: lo que no tiene
precio no cuenta ni se muestra**, igual que hoy. Se toma como un error de carga y no se avisa.

**Pedido nuevo, para la 6.0.0: las mesas y sillas de cada uno en la grilla.** Es la etapa 4 del plan; va después del
commit de M5 porque toca `detalle_evento_masivo_screen.dart`.
- Antes del sorteo, la columna Mesa dice cuántas mesas tiene cada uno: "1 mesa" sin destacar, y la agregada
  resaltada ("1 mesa +1 extra").
- Al pasar el mouse, cuánto pagó de cada cosa, leído de los pagos, y cuántas mesas le da hoy el sorteo.
- Un filtro "Mesas y sillas" como el de mora: pagadas del todo, en cuotas, sin pagar, y "Revisar" (los avisos de
  `SalonMesas.avisos`).
- **El reparto de sillas ("2P · 1A") se elige recién con las mesas sorteadas:** antes del sorteo el renglón dice solo
  "+3 sillas" y no se toca.
- Un control de solo lectura con los datos reales (`tool/extras_muestra_test.dart`), para revisarlo con el usuario
  antes del sorteo.

**Etapa 1 hecha: M2 con los 24 hallazgos aplicados** (`1b8afed`). La suite pasa, **913 tests**, y `flutter analyze`
sigue en 313. Lo que cambió respecto de lo anotado en "Revisión de M2":
- `EstadoPlano.divisiones` va en claves de `Divisiones.clave`, sin la vacía. "Sin división" se sabe por
  `haySinDivision`, y su nombre está en `nombresDivision['']`.
- `InfoMesa` lleva `libre` y `fijadaPara` siempre. El dibujo pone el candado y la raya por dato, no por estado.
- `franjaApellido`, `familiaConApellido`, `mesasEnHoja` y `lineasGrilla` son funciones sueltas de
  `pintor_plano.dart`, con test. `PintorResaltado` ahora recibe el `estado`.
- En Gala, el rubí pasó a uno más magenta, porque el anterior quedaba pegado al rojo del conflicto, y entraron el
  peridoto y el cuarzo rosa. En Neón, la 7.ª división es azul.

**Correr los tests ya no abre pestañas** (`3944fbe`). `PdfService` abría con `cmd /c start` el recibo que generan los
tests de `recibo_alto_test.dart`, y al usuario le quedaban pestañas en "no se ha podido acceder al archivo". En
`flutter test` se guarda y no se abre; en la app no cambia nada.

### Etapa 2 hecha: la base v73 revisada (`e335e00`)

Tres revisores de solo lectura (migración, sync y tests). **Nada grave:** la v73 solo crea las dos tablas, y la 5.0.0
abre una base ya migrada. Lo aplicado:
- **La copia antes de migrar ya no da por buena una copia vieja.** Si existe `antes_de_v73.db`, saca otra con la
  fecha y la hora (`antes_de_v73_2026-10-05_0930.db`), escrita a un `.tmp` y renombrada. Era el caso del camino de
  vuelta atrás: reinstalar la 5.0.0, seguir cobrando y volver a instalar dejaba la copia del primer día.
- **Lo trabado en la cola se reintenta todo junto** (`entradasDeEstaPasada`, en `sync_engine.dart`). Antes el primer
  trabado sellaba la hora y los demás no entraban: uno por ventana de cinco minutos, y uno que no podía subir (una
  tabla que todavía no existe en la nube) le sacaba el turno a un pago. **Este problema ya estaba en la 5.0.0.**
- **Un plano de la nube con otro id no pisa el local** (`planoTraeIdFijo` en la bajada, y `traerDeLaNube`).
- **El modelo aguanta datos mal escritos:** `PlanoEvento.armadoONull` (un `armado_json` roto o sin mesas da null en vez
  de tirar) y `ConfigPlano.fromJson` sin casts duros.
- **`huella` ya no lleva `updatedAt`:** la fecha la reescribe el trigger al subir y daba un "la lista cambió" falso.
- **Tests nuevos:** `test/sync_tablas_v73_test.dart` (las dos tablas en todas las listas del motor, con todas sus
  columnas, y en ninguna que borre: lee el texto de `sync_engine.dart`), el esquema de lo que ya existía igual antes y
  después, la vuelta a la 5.0.0 con datos cargados, y el SQL sin los comentarios (solo crea las dos tablas).
- **`tool/verificar_migracion_v73_test.dart`** ahora exige que la base esté en una versión anterior, que aparezcan las
  dos tablas, que el esquema viejo no cambie, que la vuelta a la 5.0.0 conserve los datos y que la base real quede con
  el mismo tamaño, fecha y SHA-256. **Todavía no se corrió sobre la base real**: va en la verificación final.

**Queda así a propósito:** si la copia falla (disco lleno), se migra igual y solo queda en el log; `_aplicarBorrados`
no limpia de la cola las hijas de un evento borrado (ya era así); un `modo_sorteo` desconocido se reescribe como
`entera`.

### Etapa 3 hecha: el sorteo por bloques revisado (`aaa0034`)

Tres revisores (motor, diálogo con el guardado, y tests). Lo aplicado:
- **Antes de sortear, de deshacer y de restaurar se lee el plano de la nube** (`leerPlanoParaSortear`, en
  `lib/features/plano/services/plano_para_sortear.dart`). El plano sube como una fila entera: con el de esta PC se
  pisaba una mesa que la otra acababa de fijar. Ante la duda no deja sortear: si no se puede saber si hay plano, o el
  armado no se puede leer, avisa y corta. Si la nube dice que no hay plano, se sortea como siempre aunque la tabla
  local no se pueda leer.
- **"Restaurar sorteo anterior" devuelve los bloques** (`RespaldoSorteo.bloques` y `bloquesARestaurar`). Deshacer los
  borra del plano; antes Restaurar devolvía solo los números.
- **A quien ya tenía mesa y compró otra, se le da pegada.** En modo entero la capacidad mínima podía quedar por debajo
  de la mesa más alta ya asignada, y la mesa nueva caía en un hueco del principio. Lo encontró el test de propiedades,
  no los revisores (`_Base.masAltoAsignado`).
- **La vista previa y el sorteo dicen lo mismo.** `SorteoConPlano.sortear` reintenta con azar de verdad y, como última
  red, usa el reparto con el que se armó la vista previa; `preparar` prueba varios repartos antes de decir "no
  entra". Solo importa para los que llegan tarde a un sorteo por bloques ya hecho.
- **Mesas fijadas:** una que el plano no tiene, que ya es de otra familia, que también está libre o que es de una
  familia de baja se avisa y no se usa. La de quien ya tiene mesa y compró otra, se le da.
- **`validar`** mira solo lo que dio el sorteo: no frena por dos familias con el mismo número de antes, acepta la
  fijada propia en el pasto y la separación pedida a los dos lados de un corte, y rechaza dar una mesa que ya era de
  otra familia.
- **Diálogo:** "usar hasta la mesa N" no acepta una mesa que el salón no tiene; un aviso nuevo destilda "ya revisé";
  las flechas mueven entre las divisiones que se ven; un plano ilegible lo dice y apaga SORTEAR.
- **Avisos del flujo:** "no había nada para sortear" en vez de "sorteo listo: 0 familias"; el "quedó en esta PC" mira
  también los números y el plano (`quedaEnCola`, en `subir_ya.dart`).
- **`Divisiones.clave`** también saca guiones, comillas y "ª" ("5-A" es "5A"), y `parecidas` avisa "5to A" con "5 A".
- **Tests nuevos:** `test/sorteo_con_plano_invariantes_test.dart` (480 escuelas al azar sobre los cuatro armados, con
  una segunda vuelta de los que llegan tarde, comprobando las reglas del salón sin usar `validar`),
  `test/plano_para_sortear_test.dart`, y más casos en el diálogo, el respaldo y las divisiones.

**Queda así a propósito:** la reserva es todo o nada por división (si 3 familias tardías no entran en los 2 huecos de
su bloque, van las 3 después del último bloque); el modo forzado a entero deja guardado `modo_sorteo: bloques`.

### Etapa 4 hecha: mesas y sillas de cada uno en la grilla (`087e904`)

- **`ExtrasSegunPago`** (`pago_para_sorteo.dart`): lo cargado y lo pagado de las mesas agregadas y de las sillas, y
  cuántas mesas le da hoy el sorteo. `candidatosPorPago` come de ahí.
- **`CeldaMesaAlumno`:** antes del sorteo dice "1 mesa" o "1 mesa +1 extra" (la agregada resaltada) y "+3 sillas" sin
  reparto. Con el filtro puesto, cómo está pagado cada extra. El tooltip trae el detalle, con o sin montos.
- **`FiltroExtras`** (`filtro_mesas_sillas.dart`) y **`ChipMesasSillas`** (`widgets/chip_mesas_sillas.dart`): el chip
  de la barra, con su menú en tres grupos.
- **El reparto de sillas se elige con las mesas sorteadas:** `RepartoDeSillas.faltaElegirConMesas`. El chip "Sillas a
  confirmar" cuenta solo a los ya sorteados.
- **`tool/extras_muestra_test.dart`**: el control de solo lectura con los datos reales, por fiesta. Se corrió el
  30-sep a las 23:19; es una foto del momento y hay que volver a correrlo cerca del sorteo. Lo que dio:
  - 9 fiestas con alumnos, ninguna sorteada todavía;
  - mesas agregadas sin pagar: 19 alumnos en total; sillas sin pagar: 5; sin pago de la base: 99;
  - un solo aviso: ESMAY, THIAGO, 4 sillas a $9.000 (lo habitual es $8.000). Ya se sabía: es el redondeo del 29-sep.
- **`tool/grilla_mesas_muestra_test.dart`**: la imagen de muestra de la columna, con familias inventadas. El usuario
  ya la vio.

## Qué pasó el 1-oct

**Plan aprobado: las medidas reales del playón, dentro de la 6.0.0.** Está en
`C:\Users\lover\.claude\plans\donde-nos-quedamos-porque-piped-lightning.md`. Suma la etapa 4b y agrega cosas a M4
y a M9. La base no cambia: sigue en la v73.

### De dónde salió
- El usuario trajo el dato de que el playón del predio tiene "900 m²".
- **El predio es Costa Surubí (Goya), frente al Escenario Mayor Juan Melero.** Los 900 m² salen de una nota de
  goyasurubi.com y son solo **la primera etapa** del playón, sin año y sin largo ni ancho.
- **Medido el 1-oct sobre la foto satelital de Google Maps** (error estimado ±10 %): un trapecio que se abre desde el
  escenario. 30 m contra el escenario, 46 m al fondo, 39 a 41 m de profundidad, unos **1.490 m²**.
- **Coincide con el Canva del jefe a 2 m de centro a centro:** el escenario del Canva mide 29,3 m, y la hoja B tiene
  más columnas que la A, como el trapecio.

### Decisiones del usuario
- **Los 2 m son de centro a centro** de mesa (105 unidades del Canva). La mesa sola queda de 1,45 m.
- **La app mide, avisa y arma a medida.**
- **En Personalizar:** ver las sillas reales, más lugar para la mesa con sillas extra, correr mesas con regla, y
  separar o juntar un bloque.
- **Todo lo nuevo tiene que ser intuitivo**, con el camino a cada cosa escrito en el plan y una maqueta para probar
  antes de programar cada pantalla.
- **Se trabaja por secciones:** cada etapa cierra sola. Con "actualizá el contexto" se frena, se anota y se sigue en
  otro chat.

### Etapa 4b hecha: las medidas del salón (`0f46110`)

- **`armado_salon.dart`:**
  - `kMetrosPorUnidadCanva = 2.0 / 105` y `ArmadoSalon.metrosPorUnidad` (clave `m_u` del JSON; si falta, la del
    Canva);
  - `distanciaPegadas` (clave `pegadas_u`): un armado con las mesas más separadas trae su propia distancia para
    decidir qué mesas están pegadas. Sin ella vale la regla de siempre, 4,2 radios;
  - `ContornoPlano` y `HojaPlano.contorno` (clave `borde`): el borde del hormigón;
  - `aMetros`, `aUnidades`, `distanciaM`, `diametroMesaM` y `tieneBorde`;
  - `problemas()` avisa "queda fuera del hormigón" (las del pasto no cuentan).
- **`modelo/medidas_salon.dart`:**
  - `PlayonReal` (frente, fondo, profundidad, `aproximado`), con `costaSurubi` = 30 / 46 / 39;
  - `costadoM` y `PlayonReal.conCostado`: con cinta se miden los cuatro lados, no la profundidad;
  - `MedidasPlano`: `lugarM(sillasExtra)` da 2,0, 2,15 y 2,3 m.
- **`ConfigPlano.medidas`** (clave `medidas` de `config`). Las de fábrica no se guardan: si se corrige la medida del
  playón en el programa, las fiestas que no la cambiaron la toman.
- **`services/medir_salon.dart`** (`MedirSalon`, todo cuenta pura):
  - `ocupa`, `apretadas`, `fueraDelHormigon`, `reglaPara` y `metros`;
  - **`revisar(armado, medidas, sillasExtraDe)`** es la única entrada para la pantalla y el dibujo. Devuelve
    `SinLugar`: los pares apretados y las mesas fuera del hormigón;
  - de cada par apretado queda marcada la que pide más (la de las sillas extra), no su vecina.
- **`services/armar_a_medida.dart`** (`ArmarAMedida`):
  - `armar(OpcionesAMedida)`: filas desde el escenario, simétricas, con pasarela y 2,5 m libres a cada lado, como en
    el Canva;
  - la numeración es la serpentina del jefe. De los dos sentidos posibles queda el que corta menos;
  - `capacidad` y `lugarMasHolgado` ("usar todo el playón");
  - `partirEnFila` arma dos hojas. La clave del armado es `a_medida@1`.
- **Dibujo** (`pintor_plano.dart`, `vista_plano.dart`, `estilo_plano.dart`):
  - el piso y el borde del hormigón (`TemaPlano.hormigon` y `hormigonBorde`);
  - `VistaPlano(mostrarRegla:, mostrarMedidas:, lugares:)`: la regla, la medida de cada lado y el círculo de lugar
    de cada mesa, en rojo la que no lo tiene;
  - Gala y Neón marcan las sillas extra con puntos a los costados;
  - la grilla es de un metro. `lineasGrilla` va por índice: sumando un paso que no es entero se comía la última
    línea.
- **Las cuentas con el playón de hoy:**
  - a 2 m entran hasta **284 mesas**; a 2,5 m, hasta **180**;
  - las 132 de la escuela más grande entran hasta a **2,9 m**.
- **Tests nuevos:** `test/medir_salon_test.dart` y `test/armar_a_medida_test.dart` (cinco playones, cinco distancias,
  con y sin pasarela, en una y en dos hojas). Los dos armados a medida se sumaron al estrés del sorteo
  (`sorteo_con_plano_invariantes_test.dart`).
- **Muestras:** `tool/plano_muestra_test.dart` genera `Medida_*.png`. El usuario ya las vio.

**Queda así a propósito:**
- **Los armados del Canva no llevan el borde del hormigón.** Su geometría sale de fotos, y un "queda afuera" sobre
  los dibujos del jefe sería falso. Tampoco avisan entre mesas comunes (el bloque derecho de la página 3 está
  dibujado a menos de 2 m): solo por las que llevan sillas extra.
- **El armado a medida no pone mesas en el pasto.** Si no entran, dice cuántas faltan.
- **Con pasarela, el paso de la izquierda a la derecha es un corte**: quedan 5 m de pasillo en el medio.

## Lo que falta, en orden

Es el orden del plan de la 6.0.0 (`C:\Users\lover\.claude\plans\en-que-nos-quedamos-radiant-gadget.md`), con lo
que sumó el plan de las medidas (`donde-nos-quedamos-porque-piped-lightning.md`). Cada etapa termina con la suite en
verde, commit y push, y un aviso al usuario de qué se hizo y cómo quedó.

1. ~~M2: los 24 hallazgos.~~ **Hecho** (`1b8afed`).
2. ~~Revisión de M3.~~ **Hecho** (`e335e00`).
3. ~~Revisión de M5.~~ **Hecho** (`aaa0034`).
4. ~~Mesas y sillas en la grilla.~~ **Hecho** (`087e904`).
   - 4b. ~~Las medidas del salón.~~ **Hecho** (`0f46110`).
5. **M4:** `widgets/elegir_plano_sheet.dart` y `plano_evento_screen.dart`. El detalle está en el plan de la Fase 3
   (`donde-nos-quedamos-glittery-waffle.md`). Tener en cuenta lo que cambió el 30-sep:
   - `EstadoPlano.divisiones` va en claves, con `nombresDivision` para la leyenda y `haySinDivision`;
   - `fijadasFueraDelPlano` y `libresFueraDelPlano`, para avisar;
   - el armado se lee con `plano.armadoONull`;
   - `sillasExtraPorMesa` del plano sale de `SalonMesas.repartoSillas` con el reparto vigente.

   **Lo que suma el plan de las medidas:**
   - **antes de programar, mostrarle al usuario la maqueta** de la pantalla del plano y de los tres pasos del primer
     ingreso (armado, estilo, sorteo), con todo ya completado;
   - en el selector, cada armado dice "78 mesas · 33 × 23 m · entra / faltan N", y hay una quinta opción, "A medida
     del playón" (cantidad, distancia y pasarela, con vista previa y "entran N"; `ArmarAMedida` y `lugarMasHolgado`);
   - en la pantalla: la regla siempre, el encabezado con "Entran las 132" o "Faltan N", y los avisos de
     `MedirSalon.revisar`, que se tocan y llevan a la mesa;
   - la tarjeta de la familia dice las sillas de cada mesa;
   - **de la grilla al plano:** en `celda_mesa_alumno.dart`, tocar los números de mesa abre el plano con la familia
     resaltada.
6. **M6:** fijar y dejar libres en `config`; cambiar y mover familias con motivo, deshacer y `mesas_movimientos`;
   `RegistroSorteo.resumir` con movimientos; `historial_sorteo_sheet.dart`. Lleva workflow.
   - Cada escritura del plano tiene que leerlo antes de la nube (`leerPlanoParaSortear` es el molde): gana la fila
     entera del último que sube.
   - `MesasMovimientosRepository.registrarEn` y `PlanosEventoRepository.guardar` ya existen y tienen test; hoy nadie
     los llama.
7. **M7:** `plano_pdf.dart` (sin `pw.Page` de alto fijo), y pasto y bloques en la planilla del sorteo.
8. **M8:** `grupo_fiesta_toolbar.dart` y la lista de la puerta trabada (`kListaPuertaHabilitada = false`). El chip
   "Mesas y sillas" ya está en la barra, entre el de mora y el de sillas.
9. **M9:** acomodar el salón (`services/editar_armado.dart`) y colores y textos. Lleva workflow. Suma, por el plan
   de las medidas:
   - el panel Medidas (distancia por mesa, extra por silla y el playón, que se carga con el frente, el fondo y un
     costado: `PlayonReal.conCostado`);
   - correr mesas con ajuste de 0,25 m y la distancia a las tres vecinas;
   - `separar`: estirar o juntar un bloque, con vista previa y APLICAR o CANCELAR;
   - en un armado del Canva, una mesa que el usuario corrió sí tiene que avisar si queda apretada
     (`MedirSalon.apretadas` sin `soloSiPideMasDe` para esas).
10. **Verificación final:**
    - PNG y PDF de muestra para el usuario;
    - `tool/verificar_migracion_v73_test.dart` sobre una copia de la base real, con la app cerrada, mostrándole la
      tabla de antes y después. El OK ya está dado en el plan;
    - `tool/extras_muestra_test.dart` otra vez, para revisar con el usuario lo que marca.
11. **Documentación:** `docs/CONTEXTO_v6.0.0_<fecha>.md`, CLAUDE.md al día (base v73, tablas nuevas,
    `lib/features/plano/`, la copia con fecha, el reintento de trabados) y la memoria.
12. **Versión y build:** `pubspec.yaml` a `6.0.0+57`, `installer/junior_eventos_setup.iss` a `6.0.0`, `flutter build
    windows --release` e Inno Setup. El `installer.iss` de la raíz está viejo y no se usa. Mandarle al usuario el
    texto de novedades antes de publicar.
13. **Publicar** (abajo). El usuario ya dijo "publicalo" el 30-sep; igual, los dos SQL van después de las 20 hs y con
    su OK en el momento.

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
- **Los cuatro lados del hormigón, con cinta.** Hasta entonces la app usa 30, 46 y 39 m, marcados como aproximados.
- **Del jefe, por las medidas:** cuánto mide la mesa sola (se supone 1,45 m), si con el playón de hoy sigue haciendo
  falta el pasto, y si quiere pasillos para los mozos entre filas.
- **Las respuestas del jefe** (ver "Queda para el jefe" en el CONTEXTO de la Fase 2):
  - qué armado usa cada escuela;
  - si aprueba las numeraciones propuestas;
  - si el pasto va desde el 131 y se usa solo si hace falta;
  - qué escuelas van por división y cuáles enteras;
  - por qué Técnica usó el pasto si le sobran mesas.

## Para seguir en otro chat, pegar

```text
Seguimos con el camino a la 6.0.0 (plano del salón, sorteo por bloques, entradas
mesas y sillas en la grilla y las medidas del playón). Leé primero
docs/CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26.md (secciones "Estado de cada parte",
"Qué pasó el 1-oct" y "Lo que falta, en orden"), el plan de la 6.0.0 en
C:\Users\lover\.claude\plans\en-que-nos-quedamos-radiant-gadget.md, el de las
medidas en
C:\Users\lover\.claude\plans\donde-nos-quedamos-porque-piped-lightning.md, el
detalle técnico de M4 a M9 en
C:\Users\lover\.claude\plans\donde-nos-quedamos-glittery-waffle.md, y la
memoria del proyecto. Están hechas y subidas las etapas 1 a 4 y la 4b: el plano
en tres estilos (1b8afed), la base v73 (e335e00), el sorteo por bloques
(aaa0034), las mesas y sillas en la grilla (087e904) y las medidas del salón
(0f46110). La suite da 1.118 tests en verde y el working tree está limpio. Seguí
por la etapa 5: M4 (la pantalla del plano y el selector de estilo y armado, con
la opción "A medida del playón"), y después M6, M7, M8 y M9, la verificación
final, la documentación de la 6.0.0, la versión y el build, en ese orden. Antes
de programar cada pantalla mostrame la maqueta para probarla. M6 y M9 llevan
revisores de solo lectura: los tests, las imágenes y los diffs los preparás vos
antes. Trabajá por secciones: avisame cada etapa que termines y cómo quedó, con
un commit y push por paso, y cuando te diga "actualizá el contexto" frená y
dejá todo anotado. Mandame las imágenes y los PDF de muestra de cada
etapa. Todo va en una sola versión, la 6.0.0: no se instala nada antes. No
corras la app desde el working tree (la v73 migraría la base real). Ya dije
"publicalo", pero los dos SQL de la nube van después de las 20 hs y con mi OK en
el momento: frená ahí y recordámelo. Lo que toque la base real, después de las
20 hs. Para volver atrás en el código está el tag antes-de-6.0.0.
```
