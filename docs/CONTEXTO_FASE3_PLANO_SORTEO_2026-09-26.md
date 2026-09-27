# Fase 3: el plano del salón, el sorteo por bloques y la personalización

**Fecha:** 2026-09-26
**Rama:** `feature/v4.6-cierre-por-sesiones` (sobre la Fase 2, que sigue sin publicar)
**Estado:** en curso. Hay partes programadas y otras que faltan (ver la tabla). **Nada está publicado**: las PCs
siguen con la 5.0.0.

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
| M2 | Los tres estilos (dibujo, vista, letras) | Sí, tests en verde | **No** | Workflow corriendo |
| M3 | Base v73 y sincronización | Sí, tests en verde | **No** | Workflow corriendo (estricto) |
| M5 | Sorteo por bloques o entero, diálogo y flujo | Sí, tests en verde | **No** | **Falta lanzarla** |
| M4 | Selector de estilo y armado, pantalla del plano | No | — | — |
| M6 | Fijar, dejar libres, cambiar o mover familias, historial | No | — | Workflow |
| M7 | Plano impreso y planilla con bloques y pasto | No | — | — |
| M8 | Botones a la vista y lista de la puerta trabada | No | — | — |
| M9 | Acomodar el salón, colores y textos | No | — | Workflow |

**Tests:** la suite entera pasa, **849 tests** (727 al cerrar la Fase 2). `flutter analyze`: 313 avisos, los mismos de
antes; ninguno es de los archivos nuevos.

**M2, M3 y M5 están sin commit a propósito:** el plan dice que se commitean después de la revisión y de aplicar lo
confirmado. Van en tres commits separados, en ese orden, porque el modelo de la v73 usa el estilo del plano.

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
    divisiones, bloques, colores, título y subtítulo; las claves desconocidas se conservan);
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
- **Tests:**
  - `test/migracion_v73_test.dart`: 71→73, 72→73, dos veces, vuelta a la 5.0.0, copia y unicidad;
  - `test/plano_evento_test.dart`;
  - `test/sql_v73_coherencia_test.dart`: el SQL contra `toMap()`.
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

## Lo que falta, en orden

1. **Revisiones de M2 y M3.** Los workflows se relanzaron el 26-sep (el primer intento lo cortó el límite de uso):
   - M2: run `wf_d9687b4f-590`;
   - M3: run `wf_ee0caa28-d13`.

   Los resultados quedan en
   `C:\Users\lover\.claude\projects\C--Users-lover-Documents-Antigravity--Gemini--arguello-events\d2c3c2e7-1db7-4f91-aa4c-2ccd69573cc6\subagents\workflows\<run>\journal.jsonl`,
   una línea `"type":"result"` por agente. Si no terminaron, relanzar los scripts de `...\workflows\scripts\`.
   Aplicar lo confirmado, correr la suite y hacer los commits: **M2 primero, después M3**.
2. **Revisión de M5 con workflow** (no se llegó a lanzar), aplicar lo confirmado y hacer su commit. Foco:
   `sorteo_con_plano.dart`, el diálogo y el flujo.
3. **M4:** `widgets/elegir_plano_sheet.dart` y `plano_evento_screen.dart`. El detalle está en el plan.
4. **M6:** fijar y dejar libres en `config`; cambiar y mover familias con motivo, deshacer y `mesas_movimientos`;
   `RegistroSorteo.resumir` con movimientos; `historial_sorteo_sheet.dart`. Lleva workflow.
5. **M7:** `plano_pdf.dart` (sin `pw.Page` de alto fijo), y pasto y bloques en la planilla del sorteo.
6. **M8:** `grupo_fiesta_toolbar.dart` y la lista de la puerta trabada (`kListaPuertaHabilitada = false`).
7. **M9:** acomodar el salón (`services/editar_armado.dart`) y colores y textos. Lleva workflow.
8. **Verificación final:**
   - PNG y PDF de muestra para el usuario;
   - `tool/verificar_migracion_v73_test.dart` sobre una copia de la base real, mostrándole la tabla de antes y
     después. El OK ya está dado en el plan.
9. **Documentación:** cerrar este CONTEXTO, poner CLAUDE.md al día (base v73, tablas nuevas, `lib/features/plano/`)
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
(secciones "Estado de cada parte" y "Lo que falta, en orden"), el plan en
C:\Users\lover\.claude\plans\donde-nos-quedamos-glittery-waffle.md y la memoria
del proyecto. M2, M3 y M5 están programados con tests en verde pero sin commit:
primero mirá el resultado de las revisiones de M2 y M3 (o relanzalas), aplicá
lo confirmado y commiteá M2 y después M3; después revisá M5 con un workflow y
commitealo. Seguí con M4, M6, M7, M8 y M9, en ese orden. No se publica ni se
corre SQL hasta que yo lo diga.
```
