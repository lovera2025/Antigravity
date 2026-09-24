# v4.9.9 — Sorteo de mesas, caja al instante, anular varios y la mesa en la puerta

**Fecha:** 2026-09-24
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Sin migración de base.** Ni local ni en Supabase.

> **Referencia:** `CONTEXTO_v4.9.9` · `sorteo de mesas` · `sillas extra` · `caja: anular varios` ·
> `lista de la puerta` · `Disk IO`
> Plan aprobado, con todo el razonamiento: `C:\Users\lover\.claude\plans\necesito-verifcar-que-todo-prancy-meerkat.md`

**Estado:**
- **Publicada el 24-sep**, con el OK del usuario:
  - release: https://github.com/lovera2025/Antigravity/releases/tag/v4.9.9;
  - tag `v4.9.9` sobre `c205654`;
  - `pubspec.yaml` 4.9.9+55 y el `.iss` coinciden.
- **Falta instalarla en las PCs.** Les aparece el aviso de actualización; 4.9.8 y 4.9.9 conviven sin problema.
- **Commits:**
  - sorteo: `9ce58a0`;
  - script de los 7 alumnos: `f7e1724`;
  - caja y JSON de mesas: `eb359f6`;
  - tótem y puerta: `926fa56`;
  - versión: `c205654`.
- **Datos de los 7 alumnos:** aplicados el 24-sep a las 06:08 y verificados. No dependen de instalar nada.
- **Tests:** `flutter test` completo, 605 pasan.

**Instalación.** Todas las PCs, **antes del sorteo de noviembre**. El orden es fijo, porque el jefe llega tarde:
1. **La PC de desarrollo:** instalada el 24-sep a la mañana.
2. **El operario:** antes de abrir caja.
3. **La oficina del jefe:** cuando llega.

Mientras tanto conviven la 4.9.9 y la 4.9.8, y no pasa nada: una anulación hecha desde la 4.9.8 igual se ve al
instante en el cierre de la 4.9.9.

En cada PC, antes de instalar: caja cerrada y "Subir pendientes" en 0. Después, la prueba sin sortear:
- en un evento masivo, ⋮ → Sortear mesas: mirar las listas de extras y el aviso ámbar, y **cancelar**;
- ⋮ → Planilla de cursos.

No se prueba anulando cobros reales, porque es producción: la primera anulación de verdad sirve de prueba.

Se publicó con `tool/publish_windows_release.ps1 -SoloNotas -NotesFile <notas>`.

---

## Reglas acordadas con el usuario (no romper)

1. **Nada se publica hasta que el usuario lo diga.**
   - Se puede hacer commit y push a `feature/v4.6-cierre-por-sesiones`, y builds de prueba.
   - No se puede, sin su aviso: publicar el release, pasar el instalador, desplegar la web ni instalar en las PCs.
2. **Una sola versión, la 4.9.9, con todo junto:** sorteo, caja y tótem. Así no hay dos instalaciones ni dos
   números de versión. Tiene que estar instalada en las dos PCs **antes de noviembre**, que es cuando se sortea.
3. **La app sigue funcionando como hoy, pero mejor.** Cobros, mora, saldos y recibos no se tocan.
4. **No se borra ningún dato.** Las correcciones se hacen modificando, **solo en los alumnos señalados** y con los
   pagos intactos. La única excepción es el pago de ESMAY que se parte (aprobado).
5. **Prevenir, no manejar.** El sorteo está "hecho para no fallar"; la validación final es solo una red de
   seguridad.
6. **Las correcciones de datos se aplican después de las 20 hs y cuando el usuario avise**, porque durante el día
   se cobra. El esquema es siempre el mismo:
   - foto de solo lectura;
   - script en DRY-RUN;
   - antes → después a la vista del usuario;
   - su OK en el chat;
   - copia de `data.db`;
   - APPLY con la app cerrada;
   - abrir la app y tocar "Subir pendientes";
   - comparar contra la foto, en local y en Supabase.

## Reglas del negocio

- **Mesas:** a cada alumno le toca 1 mesa base + 1 por cada mesa extra que figure en su cuenta, **esté pagada o
  no**. Van juntas, salvo que se marque separarlas.
- **Sillas:** cada mesa (base o extra) trae **8 sillas** y admite **como máximo 2 sillas extra**. El máximo de un
  alumno es `2 × (1 + mesas extra)`.
- **Precios:** silla extra **$8.000**; mesa extra **$70.000** c/u.
- **Qué sillas cuentan:** solo las que figuran en la cuenta, es decir, con precio. Con precio $0 no aparecen, igual
  que en el estado de cuenta.
- **Personas por mesa:** alumno + acompañantes, contra `8 × mesas + sillas extra` lugares.
- **Fechas:**
  - el sorteo se hace en **noviembre**, día a definir;
  - las fiestas son en **diciembre**, cada institución en su propia fecha, a definir;
  - las fechas cargadas en el sistema son de relleno.
- **Cada institución se sortea sola** y numera desde 1. Las mesas del salón se reutilizan de una fiesta a otra.

---

## HECHO — commit `9ce58a0` (subido a origin)

**Motor nuevo** — `lib/features/eventos/services/sorteo_mesas_motor.dart`
- Números únicos por construcción.
- `capacidadMinima` y `esFactible`: el mismo recorrido con el que arranca `sortear`, así que si da factible, el
  sorteo termina.
- Ubicación constructiva de las separadas: nunca quedan pegadas.
- Completa a quien compró una mesa extra después, pegada a su bloque.
- Respeta los números ocupados y los de bajas.
- `validar` como red final y `firma` para detectar si la lista cambió.

**Salón** — `lib/features/eventos/services/salon_mesas.dart`
- Textos de la columna MESA ("12-14 (2 extra)", "12-13 + 40 (separada)"), aviso de mesas ("le falta 1 mesa").
- Sillas repartidas de a 2 por mesa, `OcupacionAsientos` ("3 de 8 lugares"), `PreciosHabituales` (la moda del
  evento) y los avisos de "Revisar antes de sortear".

**Respaldo del deshacer** — `lib/features/eventos/services/respaldo_sorteo.dart`
- Copia JSON en `Documentos/Junior Eventos/respaldos_sorteo/<eventoId>.json`.
- `planRestauracion` devuelve números sin pisar nada.

**Diálogo del sorteo** — `widgets/sorteo_mesas_dialog.dart`
- Demanda, listas "Con mesas extra" (con separar) y "Con sillas extra".
- Aviso ámbar con la casilla "Ya revisé".
- SORTEAR se deshabilita si la capacidad no alcanza.

**Pantalla del evento** — `detalle_evento_masivo_screen.dart`
- `_sortearMesas`:
  - chequea si otra PC tiene mesas sin bajar (`mesasDeOtraPcSinBajar`);
  - relee la lista antes de sortear;
  - ya **no llama a `reconciliarMesasExtrasEvento`**: el sorteo solo escribe `numero_mesa`.
- `_deshacerSorteoMesas` limpia a todos, también bajas, pide casilla y guarda la copia antes de borrar.
- `_restaurarSorteoAnterior`, con su entrada en el menú ⋮ cuando hay copia.
- Celda MESA nueva: `widgets/celda_mesa_alumno.dart`.

**Repositorio** — `contratos_repository.dart`
- `asignarNumerosMesa`: una sola transacción, solo toca `numero_mesa`.
- `mesasDeOtraPcSinBajar`: solo lectura; ignora los alumnos con cambios propios pendientes.

**Planilla de cursos** — `pdf_service.dart`
- `construirPlanillaCursosPdf`: primera hoja "Resumen del salón" (totales y la lista de quienes tienen mesas o
  sillas extra, con reparto por mesa y personas).
- En cada curso: MESA con formato y "(!)", columna "SILLAS EXTRA" y línea de control.
- Muestra sin abrir la app: `tool/planilla_cursos_muestra_test.dart`.

**Editar alumno** — `modal_alumno_premium.dart`
- `datosEdicionAlumno`: el número de mesa se guarda **solo si se cambió**, así otra PC no pisa el sorteo.
- No deja pasar de 2 sillas extra por mesa.
- Avisa precios distintos al habitual o en $0, y familias que no entran en sus lugares.

**`numerosMesaDesdeTexto`** lee "40-42", "40 al 42", "40 y 41" e ignora lo que está entre paréntesis.

**Tests**
- `test/sorteo_mesas_motor_test.dart`:
  - estrés con los 9 tamaños reales;
  - 2000 salones difíciles, con verificación de que más capacidad siempre entra.
- `test/respaldo_y_edicion_mesa_test.dart`.
- **`flutter test` completo: 556 pasan.**

Mesas que pide cada institución (23-sep): Iloza 133, Nacional 126, Sagrado Corazón 117, Pinaroli 97, Güemez 73,
Buena Vista 54, Rotonda 53, Gregoria 41, Puerto Viejo 31.

---

## HECHO 1 — Corregir los datos de 7 alumnos

**Aplicado el 24-sep a las 06:08** (commit del script: `f7e1724`), sin cobros en curso y con la app cerrada.
- Copia previa: `Documents\Junior Eventos\data.db.bak.extras.2026-09-24T06-08-25`.
- **Local:** cambiaron solo los 6 contratos y los pagos de Esmay (1 partido y 1 nuevo); no se borró nada.
- **Supabase**, después de "Subir pendientes":
  - los otros 637 contratos y 3463 pagos quedaron con el mismo hash que antes;
  - los 6 dan exactamente lo acordado;
  - el 25-jun de Esmay suma $57.000 igual que antes.
- El pago nuevo de Esmay se rotuló como la app: "Entrega parcial — Cuota Base (7/9)", misma fecha y medio.

Lo que sigue es cómo se armó el script, para referencia.
- Sigue el patrón de `tool/aplicar_fix_mora_5_test.dart`: sqflite ffi sobre `Documents\Junior Eventos\data.db`,
  DRY-RUN por defecto y `--dart-define=APPLY=1` para escribir.
- Trabaja **solo sobre una lista cerrada de ids**, sin recorrer eventos.
- **Frenos.** Aborta sin escribir si:
  - un valor actual no es el esperado;
  - hay algo en `_sync_queue` para ese id;
  - la reconciliación quisiera renombrar un pago;
  - lo pagado quedaría mayor que el precio.
- **Cálculo con el código de la app:**
  - `recalcularSaldoDesdePagos` (`cobro_abono_acumulado.dart:600`);
  - extraer una función pura `MesasExtraUtils.estadoMesasReconciliado` de `reconciliarMesasEstadoContrato`
    (`contratos_repository.dart:650-747`), que el repositorio también use, con test.
- **APPLY:** una sola transacción, con `UPDATE` más `SyncQueue.enqueue(executor: txn, ...)`. Ningún `DELETE`.

| Alumno (id) | Institución | Cambio | Plata |
|---|---|---|---|
| PONCE, AYELEN MILAGROS (`9544c706-81a2-4e85-89af-281f6322a1af`) | Colegio Nacional B | `mesa_extra_cantidad` 1→**2** (el precio total sigue en 140.000) | total y saldo iguales |
| SILVERO, MAXIMILIANO NAHUEL (`fbbd5418-7c44-4099-be9c-78b07af6baec`) | Técnica Pinaroli 1 | mesas extra 1→**2** | iguales |
| GONZALES, ALINA JAZMÍN (`424c1630-73dd-4839-95e5-3b358e46b0f1`) | Técnica Pinaroli 1RA | mesas extra 1→**2** (sus sillas 2×$16.000 ya están bien) | iguales |
| QUIROZ MEZA, MATÍAS NAHUEL (`3199a441-cc45-41d0-af94-13b820b75ce9`) | Normal Iloza 3 | sillas 2→**4** (total sillas sigue en $32.000) | iguales |
| ESMAY, THIAGO (`dd8af936-8880-4a50-8ee0-4de0086ce0e5`) | Güemez 3 | sillas 2→**4** a $8.000 (total sillas $36.000→$32.000) **y** se parte el pago del 25-jun "Sillas Extras - Entrega" $12.000 en $8.000 de sillas + $4.000 de abono de cuota base (misma fecha, medio y sesión de caja) | total 421.000→417.000, saldo 115.000→111.000 |
| BALDI, JUAN MARTÍN (`d5f01890-84f6-4d6e-be33-670e6e6aa348`) | Técnica Pinaroli 1 | silla 1 × $6.000 → **$8.000** | total +2.000, saldo +2.000 |
| CACERES, ANAEL (`b9fe4391-053a-4582-9758-5da1a7512150`) | Normal Iloza 5 | **NO SE TOCA**: su "2" de sillas sin precio no está en su cuenta; la app ya no lo muestra | — |

- **Orden de aplicación:**
  1. primero los 3 de mesas: Ponce, Silvero, Gonzales;
  2. después Quiroz, Baldi y Esmay.
- **Aprobaciones:** Esmay está aprobado por el usuario (23-sep). Antes de partir su pago hay que revisar dos cosas:
  con qué rótulo guarda la app un abono de cuota base, y que la caja de esa sesión siga sumando igual.
- **Valores al 23-sep** (se vuelven a leer ese día; los frenos comparan):
  - PONCE 410.000 / 260.000, pagado de mesa 60.000;
  - SILVERO 455.000 / 192.500, 87.500;
  - GONZALES 471.000 / 236.000, 60.000;
  - QUIROZ 372.000 / 100.000;
  - ESMAY 421.000 / 115.000;
  - BALDI 391.000 / 105.000.
- **Cómo queda el detalle por mesa:** lo pagado va primero a la Mesa 1. La mora no cambia, porque se calcula solo
  sobre la base.

## HECHO 2 — Caja (24-sep)

**Lo que se encontró al hacerlo:**
- La pantalla de cierre **ya** se refrescaba con el ciclo de 10 s (`operationalSyncRevisionProvider`), pero no con el
  pulso. Por eso tardaba hasta 10 s, y además parpadeaba con cada ciclo.
- El diálogo "Cerrar caja" del operario cargaba los totales **una sola vez**: si el jefe anulaba algo con el
  diálogo abierto, el operario arqueaba contra un total viejo.

**Lo que se hizo:**
- **Motor:** `SyncEngine.cambiosBajadosStream` avisa en qué tablas bajó algo **distinto** de lo que había
  (`filaEsNovedad`: compara `updated_at`, así no avisa por las filas que vuelven a bajar con el marcador
  retenido). Sale del pull, del pulso y de los borrados.
- **Cierre:**
  - `CierreCajaNotifier` escucha ese aviso y refresca en silencio si tocó alguna tabla de `kTablasDelCierre`;
  - el ciclo de 10 s también pasó a ser silencioso;
  - un contador de generación evita que un refresco viejo pise uno nuevo;
  - aviso "El jefe anuló N cobro(s) de esta sesión: ALUMNO · $X", armado por cobro con `agruparIngresosPorCobro`;
  - en sesiones cerradas, la línea "Anulado después del cierre: $X. El arqueo guardado lo incluye.";
  - en la PC del jefe, el cierre se refresca después de anular.
- **Diálogo "Cerrar caja":** se rehace con el aviso y muestra el mismo mensaje.
- **Anular varios:**
  - `SelectorCobros` (compartido) con casillas que se mantienen entre búsquedas;
  - "Tildar todo el cobro", con `lineasDelMismoCobro` y `esDelMismoCobro`: mismo contrato, sesión y 10 s;
  - un motivo, confirmación "Vas a anular N cobros por $X";
  - `anularPagosConMotivo` en **una transacción**, que recalcula cada contrato una vez;
  - un solo PDF (`compartirComprobanteAnulacionCobros`); con uno solo sale el de siempre.
- **Corregir medio de varios:** mismo selector, `corregirMedioPagoVarios` en una transacción. La fecha se
  cambia solo con uno tildado. De paso se arregló que al cambiar la fecha el cobro quedaba **corrido tres
  horas**: se usaba la hora UTC como si fuera local.
- La anulación y la corrección de a uno pasan por los mismos métodos, con los mismos mensajes.
- **Tests:** `test/anular_varios_cobros_test.dart` (base temporal: todo o nada, mora, líneas del mismo cobro) y
  `test/aviso_cambios_caja_test.dart`.

Lo que sigue es el plan original, para referencia.

El usuario pidió dos cosas:
- que cuando el jefe anula un cobro, **desaparezca en el momento** del cierre de caja del operario;
- anular (y corregir el medio de pago de) **varios cobros a la vez**.

**Causa verificada.**
- La anulación marca `anulado=1` (`finanzas_repository.dart:754-792`) y llega a la otra PC en segundos, por el
  pulso o por el ciclo de 10 s.
- El cierre ya descarta los anulados (`finanzas_repository.dart:223`).
- Pero `CierreCajaNotifier` (`cierre_caja/providers/cierre_caja_provider.dart`) **no se actualiza solo**: carga al
  abrir y con `refrescarManual()`.

**T. El cierre se actualiza solo.**
1. En `SyncEngine`, un aviso nuevo, `cambiosBajadosStream` (`Stream<Set<String>>`, broadcast), con un set
   `_tablasConCambios` y `_avisarCambiosBajados()`. **Se había empezado y se revirtió para dejar el repo limpio.**
   Dónde enganchar:
   - en `_pullTable`, después de `batch.commit`: `if (rows.length > skipped) _tablasConCambios.add(table)`;
   - en `_aplicarBorrados`, al borrar;
   - llamar a `_avisarCambiosBajados()` al final de `pullOperationalUpdates`, `_atenderElPulso`, `_pullFromCloud` y
     `_reconcileDeletes`;
   - cerrar el controller en `dispose`.
2. `CierreCajaNotifier` escucha el aviso. Si vienen cambios de `pagos_contrato_alumno`, `sesiones_caja`, `egresos`,
   `transacciones`, `pagos_prestamo_alquiler` o `cierre_caja_*`, hace un `_refrescar(silencioso: true)` con espera de
   aprox. 1 s: sin poner `cargando`, para que no parpadee.
   - El arqueo que se tipea vive en widgets hijos, así que el refresco no lo pisa.
3. Aviso visible "El jefe anuló 1 cobro de esta sesión: ALUMNO · $X", armado comparando los cobros de antes y de
   después.
4. En la PC del jefe, refrescar el cierre después de anular.
5. En una sesión ya cerrada, una línea aparte "Anulado después del cierre: $X". El arqueo guardado no cambia.

**U. Anular varios** (`mi_empresa/widgets/anular_cobro_cuota_dialog.dart`; hoy tiene un solo `_seleccion`).
- Casillas en los resultados, que se mantienen entre búsquedas, y arriba "N seleccionados · $total".
- "Todo el cobro": reusar `cierre_caja/services/cobro_agrupado.dart` (mismo contrato, momento y sesión).
- Un solo motivo, de 8 caracteres o más, y confirmación "Vas a anular N cobros por $total".
- En el repositorio, `anularPagosConMotivo(lista, motivo)` en **una sola transacción**, con la misma lógica que
  `anularPagoConMotivo` por fila (incluido el tracked de mora de las filas de interés).
- Cada contrato se recalcula una sola vez (`recalcularProgresoContrato`).
- Un solo comprobante PDF.

**V. Corregir medio de pago de varios** (`CorregirMedioPagoDialog`): la misma lista con casillas, el medio nuevo
una sola vez y una transacción.

**Tests:** todo o nada; recálculo una vez por contrato; el refresco se dispara solo con las tablas que importan; no
pisa lo tipeado.

## HECHO 3 — Tótem: la mesa en la puerta y el ahorro de Disk IO (24-sep)

**La mesa en la puerta.** Decisión del usuario (24-sep): en la lista de la puerta va el **alumno y su familia**.
Sobre la búsqueda no eligió, así que queda la recomendada: en las fiestas de alumnos se busca **por nombre**
(los alumnos no tienen DNI), y el DNI sigue igual en los particulares.
- **Lo que se encontró:**
  - `invitados` es una lista aparte, sin relación con los alumnos: al 24-sep tenía 7 filas de prueba;
  - los contratos no tienen DNI;
  - ningún alumno tiene acompañantes cargados.
- El tótem y Recepción **no distinguen particular de masivo**: trabajan por evento, y cada evento tiene su lista.
  Lo que cambia es cómo se carga: los particulares a mano o por CSV (con DNI), los masivos ahora desde los
  alumnos.
- **⋮ → "Pasar a la lista de la puerta"** (`detalle_evento_masivo_screen.dart`, `_pasarListaPuerta`):
  - lleva cada alumno activo y cada acompañante con nombre a `invitados`, con la mesa sorteada
    (`SalonMesas.textoMesasPuerta`: "12", "12-14", "12-13 y 40");
  - los ids son fijos por alumno y lugar (`idInvitadoPuerta`, `lista_puerta.dart`): se puede repetir y actualiza
    las mismas filas;
  - a las filas existentes solo les cambia nombre y mesa: **el ingreso no se toca**;
  - lo que sube de una fila nueva no lleva `estado_ingreso`, así un upsert no pisa un ingreso hecho en la otra PC;
  - **no borra nada**: lo que quedó de una pasada anterior (baja, acompañante quitado) se informa como sobrante;
  - no toca filas cargadas a mano o por CSV, ni la lista de otros eventos;
  - antes de comparar, baja la lista de la nube para ver lo que cargó la otra PC.
- **Trampa corregida:** `InvitadosRepository._pullByEvento` borraba de la base local todo lo que no venía en una
  consulta de **una sola página** (PostgREST corta en 1000). Ahora pagina y poda solo con la foto completa, por
  `filasAPodar`.
- **Pendiente:** las pantallas web y el tótem leen hasta 1000 invitados por evento; ver
  `docs/pendientes/invitados-mas-de-1000-en-web.md`. Hoy no se llega ni cerca.

**Ahorro de Disk IO** (sin que se note nada):
- **Tótem escondido:**
  - `KioskLauncher.close()` y el botón de salir del tótem mandan `pausar`;
  - pausado, suelta el stream de invitados, el canal de avisos (`removeChannel`), la relectura de 60 s y la
    config (deja de mirarla y el provider autoDispose cierra su stream);
  - `launch`/`focus` mandan `reanudar`: retoma y recarga en silencio, sin bienvenidas atrasadas.
- **Recepción:** `watchByEvento` era un `async*` parado en un `await for`, y al salir de la pantalla el canal
  seguía abierto hasta el próximo cambio. Ahora es un `StreamController` que suelta el canal en `onCancel`
  (test: `recepcion_suelta_canal_test.dart`).
- **`invitados` en el ciclo de 10 s:** ya no estaba. Solo baja en el pull manual y por Recepción/tótem. No hubo
  que tocar nada.
- **Latido de caja:**
  - sube solo `{id, last_heartbeat, updated_at}`: antes subía la fila entera y podía reabrir en la nube una
    sesión que la otra PC acababa de cerrar;
  - `esSoloLatido` evita el pulso por un latido, y la otra PC lo recibe por el ciclo de 10 s como antes;
  - si hay un cambio real pendiente, la cola lo fusiona y sí va con pulso.

## HECHO 4 — Versión 4.9.9 (24-sep)

- `pubspec.yaml` 4.9.9+55 e `installer/junior_eventos_setup.iss` 4.9.9.
- `flutter build windows --release` e Inno Setup: `installer/dist/Setup Junior Eventos v4.9.9.exe`.
- **Publicar e instalar: solo cuando el usuario lo diga** (ver arriba).

---

## Aviso de Supabase "Disk IO Budget" (llegó el 23-sep a las 19:45)

- Las estadísticas de Query Performance son **acumuladas desde el 11-mar-2026**. Las ~10,2 M lecturas de WAL son
  casi las mismas que en el incidente del 1-sep (ver `CONTEXTO_v4.9.4_2026-09-02.md`). Realtime **no** fue la causa
  de hoy.
- La base pesa 18 MB y vive en memoria (`blks_read` 1.707 contra 18.400 M `blks_hit`). Lo que gasta disco es
  escritura.
- **Punto de partida para medir** (23-sep, 00:35 UTC):
  - `wal_lsn` 59/84000160;
  - lecturas de WAL de Realtime 10.179.536;
  - latidos de caja (`UPDATE sesiones_caja`) 23.677;
  - consultas totales 12.637.597;
  - PostgREST 876.329;
  - 0 conexiones de Realtime.
- **Qué hacer:**
  - volver a medir con la misma consulta de solo lectura y mirar el gráfico **por hora** del mail;
  - **no tocar "Reset report" antes de esa medición**;
  - operativo: cerrar la app entera al terminar el día, porque cerrar solo el tótem no alcanza.
- Si la medición muestra consumo diario en horario de trabajo, se puede ofrecer adelantar solo el arreglo del
  tótem y Recepción.
- **Medición del 24-sep, 09:38 UTC** (misma consulta, solo lectura):
  - lecturas de WAL de Realtime **10.179.536**, igual que el punto de partida: desde entonces nadie escuchó
    cambios de la base;
  - consultas totales 12.638.954 (+1.357, la noche);
  - `wal_lsn` 59/92000000, +224 MB, justo en un borde de segmento de 16 MB: huele a rotación de WAL del propio
    Supabase, no a la app;
  - falta mirar el gráfico por hora del mail. "Reset report" sigue sin tocarse.

## Tarea aparte — RESUELTA (24-sep)

- `mesas_extra_estado` se guardaba como `toString()` de Dart en vez de JSON, en la limpieza del pull. Ahora
  `valorParaSqlite` (`sync_engine.dart`) guarda las listas y mapas de la nube como JSON. Tiene test en
  `test/valor_para_sqlite_test.dart`.
- **Los datos viejos no se tocaron.** Quedan en formato Dart hasta que esa fila se vuelva a escribir. Mientras
  tanto, la app los sigue leyendo como hasta ahora: con la cantidad de mesas del contrato.
- Se vio justo después de corregir a los 7: la nube recibió JSON y, al volver a bajar, la PC lo guardó otra vez
  como texto de Dart.
