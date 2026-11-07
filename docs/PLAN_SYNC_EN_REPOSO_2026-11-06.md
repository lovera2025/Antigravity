# Spec — Sync en reposo: la nube se toca solo cuando algo cambia

**Fecha:** 6 de noviembre de 2026
**Rama base:** `feature/v4.6-cierre-por-sesiones` (6.3.1+63, commit del 6-nov 14:20)
**Va en:** ~~la versión en curso (barra + Entradas 4 a 6)~~ **la 6.3.3, sola** (decisión del usuario, 6-nov a la noche: "de inmediato, bien hecho y probado en el sandbox"), desde la rama `release/6.3.x` después del parche 6.3.2 de la mora. Etapas 1 a 5, sin SQL; la etapa 6 (la RPC) queda para más adelante. La barra 5-10 y Entradas 4-6 esperan a que salga.
**Archivo:** `docs/PLAN_SYNC_EN_REPOSO_2026-11-06.md`

> **Lo decidido al revisar contra el código (6-nov), distinto de lo que dice abajo:** los relojes se prueban con un reloj
> inyectado en el motor (`RelojDelMotor`), no con `fake_async` (el motor hace I/O real); `_pullTable` devuelve
> `({bool ok, int filas})`, porque `bajarParaLaPuerta`/`bajarParaLaBarra` ya usan el "salió bien"; los tres refrescos de
> pantalla salen del coordinador y se cuelgan de `cambiosBajadosStream`; `wakeUpCloud()` se saca también de
> `flushPending` (el latido pasa por ahí); `puedeSubirSolo` desaparece (la subida ya no mira el rol desde la 6.0.0);
> una sola bajada a la vez (el pulso se marca ocupado); `marcarNubeCaida` arma su propio reintento con un sondeo del
> motor, o la app quedaría sin sync con la Nano dormida. El detalle, con archivos y líneas, en el plan aprobado de esa
> sesión (copiado en el CONTEXTO de la 6.3.3 cuando se haga).

---

## 1. Por qué

Decisión del usuario (6-nov): **el proyecto sigue en el plan Free de Supabase.** Eso es una instancia Nano (0,5 GB de RAM compartidos entre Postgres, PostgREST, Auth y Realtime; CPU compartida). Lo único que está en nuestra mano sin pagar es que la app la moleste lo menos posible.

Hoy el motor ya tiene lo central: la subida es por evento (`_programarSubida`, 2 s después de encolar) y las PCs se avisan por **el pulso** (broadcast `sync_pulse`), que baja solo las tablas que cambiaron. Pero el pulso es "un acelerador, no un transporte" (comentario en `sync_engine.dart:694`): abajo sigue corriendo un reloj de 10 s que baja 16 tablas haya o no haya novedades, más el ping, más tres `count`, más el latido cada minuto. **La regla nueva es: en reposo, silencio.** La nube se toca cuando esta PC cambia algo, cuando otra avisa que cambió algo, al arrancar, al volver la red, antes de cobrar, y como red de seguridad muy espaciada.

### Lo medido el 6-nov (edge logs de Supabase, todas las PCs juntas)

| Momento | Requests | Qué estaba pasando |
|---|---|---|
| 12:10–12:30 y 14:40–15:00 (pico) | ~150 por minuto (2,5 por segundo) | cobrando con todo abierto |
| 15:10–18:40 (reposo) | ~6 por minuto | pings + latidos + la revisión de 10 min |
| 15:51–16:13 | ~1 por minuto | **la base no respondía** (timeouts 504/522/524) |

Dos cosas que salen de ahí y que la spec no tiene que contradecir:

- **La caída de hoy no fue por carga**: pasó en el momento más quieto del día, con la base de 21 MB recibiendo 6 requests por minuto. Fue la Nano. Esta spec baja la carga de fondo, que es lo que podemos hacer; no promete que una Nano no se vuelva a trabar.
- **Realtime sobre Postgres está quieto**: `realtime.list_changes` no sumó ni una llamada en un minuto medido (lo de septiembre ya está resuelto). `invitados` sigue siendo la única tabla en la publicación. **No se toca.**

---

## 2. Lo que corre hoy por reloj, por PC

| Fuente | Dónde | Cada | Cuesta en la nube |
|---|---|---|---|
| Ciclo operativo | `OperationalSyncCoordinator._tick` (`operational_sync_coordinator.dart:75`) → `SyncEngine.pullOperationalUpdates` (`sync_engine.dart:1313`) | 10 s | 1 ping (`wakeUpCloud`) + 16 GET (`_tablasDelCobro`) + 3 `count` (`_contarParaVerBorrados`) = **20**; cada 6 ciclos, 23 GET más (`_tablasDeCarga`) |
| Latido de la caja | `_heartbeatTimer` en `app_role_provider.dart:546`, `kLatidoSesionPeriodo` (`sesion_caja.dart:4`) | 60 s | 1 PATCH a `sesiones_caja` |
| Revisión de borrados | `_arrancarReconciliacion` (`sync_engine.dart:521`), `_cadaCuantoSeReconcilia` | 10 min | ~25 GET de ids (`_tablasAReconciliar`) |
| Chip de cajas | `SesionCajaStatusChip._poll` (`sesion_caja_status_chip.dart:35`) | 10 s | **nada** (lee la base de la PC) — no se toca |
| Ping de conectividad | `ConnectivityService._pingSupabase` | solo al cambiar la red | 1 GET — no se toca |

Con una PC activa el ciclo operativo es **~120 requests por minuto**. Es el 95 % de lo que la app le pide a la nube.

---

## 3. Qué cambia

### Etapa 1 — El coordinador deja el reloj de 10 s

`OperationalSyncCoordinator` no tiene más `Timer.periodic(10 s)`. Lo que hacía el tick se reparte:

- **Subir**: ya es por evento. `_programarSubida` sube 2 s después del último encolado. Lo que faltaba es el **reintento con espera creciente** cuando la subida falla o no había red: 30 s, 1, 2, 5 min, y se queda en 5 min **para siempre, hasta que suba**; se reinicia al éxito y también en cuanto vuelve la red. **Nada se saca de la cola por fallar**: la cola vive en `_sync_queue` (SQLite) y sobrevive a cerrar la app; lo único que la vacía es que la nube confirme (regla de `_isNonRetryableError`, que no cambia). Solo corre mientras `SyncQueue.readyCount > 0`. Los trabados siguen entrando cada 5 min (`_esperaEntreReintentosTrabados`), pero el timer existe solo mientras `stuckCount > 0`. Con la cola vacía, no hay timer.
- **Bajar**: por el pulso (etapa 2) y por la red de seguridad (etapa 3).
- **`_autocierreCajas`** se queda, pero disparado por lo que ya lo dispara (arranque, foco de ventana, `didChangeAppLifecycleState`) y por el latido (etapa 4); sin el tick de 10 s ya no hace falta el throttle de un minuto, pero no molesta dejarlo.
- **`_ciclos` y `ciclosEntrePullsLentos`** desaparecen: la cadencia por niveles pasa a ser dos relojes de la etapa 3.
- `onWindowFocus` / `onWindowRestore` / volver a `resumed` disparan **una bajada de `_tablasDelCobro`** solo si la última bajada tiene más de 60 s. Es el momento en que alguien mira la pantalla.

### Etapa 2 — El pulso pasa de acelerador a transporte

Hoy, si el pulso llega con la PC ocupada, **las tablas se tiran** (`_atenderElPulso`, `sync_engine.dart:828`: "el ciclo de 10 s las baja igual"). Sin ese ciclo, tirarlas es perder la novedad hasta la red de seguridad. Cambia:

- `_tablasDelPulso` **no se vacía** cuando la PC está ocupada: se reintenta a los 3 s, igual que `_borradosDelPulso` (mismo `_reintentoBorradosDelPulso`, renombrar a `_reintentoDelPulso`). Un pulso que llega mientras se está atendiendo otro se acumula en los mismos sets (ya es así) y lo atiende la vuelta siguiente.
- **Pulso también para lo que se borra** (ya está) y **para lo que se sube desde la barra, Entradas y la puerta** (ya entra por `_anotarParaElPulso` porque todas están en `_incrementalColumns`; verificar con un test que `barra_ventas`, `barra_anulaciones`, `sillas_puerta`, `entradas_retiro` y `permisos_operador` lo disparan).
- **Catch-up al reconectar el canal.** `_escucharElPulso` pasa a `subscribe((status, error) { ... })` con `RealtimeSubscribeStatus` (el repo ya lo usa así en `asesor_home_screen.dart:52`; la firma es la de `realtime_client` 2.7.1 que está en el `pubspec.lock`). Se anota el instante de cada `subscribed`. Si entre un `closed`/`channelError`/`timedOut` y el siguiente `subscribed` pasaron más de 20 s, se corre una bajada de `_tablasDelCobro` (los pulsos de ese hueco se perdieron). `supabase_flutter` reconecta solo el socket; esto solo escucha lo que ya hace.
- **Sin acuses.** Un pulso perdido lo cubre la red de seguridad y el catch-up. Agregar acuses es sumar mensajes para el caso raro.
- El latido sigue sin disparar pulso (`esSoloLatido`): no cambia.

### Etapa 3 — Red de seguridad espaciada

Dos relojes en `SyncEngine` (no en el widget, como el pulso y la revisión: no dependen de la pantalla):

| Reloj | Cada | Baja |
|---|---|---|
| `_redDeSeguridadCobro` | **5 min** | `_tablasDelCobro` + `_contarParaVerBorrados` |
| `_redDeSeguridadCarga` | **30 min** | `_tablasDeCarga` |

Y las bajadas por disparador, que son las que importan:

| Cuándo | Qué baja |
|---|---|
| Al arrancar (primer ciclo de hoy) | todo, como hoy (`incluirTablasDeCarga: true`) y después `_reconcileDeletes` + `revisarMora` como está en `pullOperationalUpdates:1350` |
| Al volver la red (`ConnectivityService` pasa a `online`) | `_tablasDelCobro` |
| Catch-up del canal (etapa 2) | `_tablasDelCobro` |
| Antes de cobrar / abrir caja (`refreshBeforePayment`, `refreshBeforeOpen`) | como hoy: `pullOperationalUpdates()` completo. **No se toca**: es la garantía de que no se cobra con datos viejos |
| Foco de ventana con más de 60 s sin bajar | `_tablasDelCobro` |
| Pulso | solo las tablas del aviso |

`_contarParaVerBorrados` sale de "cada ciclo" y entra solo en la red de 5 min. Los borrados en vivo llegan por el pulso (con reintento, etapa 2) y la revisión de 10 min sigue igual (`_cadaCuantoSeReconcilia` no cambia: ya es espaciada). La revisión del arranque también.

El pedido del usuario fue "solo cuando algo cambia". Los 5 minutos son el precio de tres cosas que no se pueden garantizar: que el socket estuviera conectado cuando el pulso salió, que el mensaje haya llegado, y que esta PC no estuviera apagada. Si se quiere menos, la etapa 6 deja la red en una sola consulta.

### Etapa 4 — El latido, cada 5 minutos

`kLatidoSesionPeriodo` pasa de 60 s a **5 min**; `kLatidoSesionVivo` a **11 min** (dos latidos y margen: uno puede perderse y la otra PC no la pone en naranja); `kLatidoSesionMuerto` a **20 min** (`sesion_caja.dart:4-14`). Siempre `periodo < vivo < muerto`, y el comentario de `app_role_provider.dart:544` dice que los tres van juntos: un test lo exige.

**El latido ahora sí dispara el pulso.** `_anotarParaElPulso` deja de saltear `esSoloLatido` (`sync_engine.dart:758`). La exclusión existía porque el latido era cada minuto y despertaba a la otra PC 60 veces por hora; cada 5 min es 1 GET de `sesiones_caja` por PC cada 5 min, y sin eso la otra PC se enteraría del latido recién por la red de seguridad, con hasta 10 min de atraso y la caja en naranja sin motivo. `esSoloLatido` se queda para lo demás (que el latido no refresque las pantallas: el `bump` de los providers solo cuando bajan filas que no sean latido).

**Lo que el usuario pidió** ("que la caja del operario o del jefe quede en verde en el dashboard mientras está abierta, y que cambie cuando cierra") se mantiene y por el mismo camino de hoy: abrir caja sube la fila a los 2 s y manda el pulso, la otra PC la baja en el acto, y `SesionCajaStatusChip` —que lee la base de la PC cada 10 s, sin tocar la nube— la pinta en verde. `enUsoAhora()` (`sesion_caja.dart:90`) sigue decidiendo el verde con la antigüedad del latido; el cierre llega por su propio pulso. El chip no cambia de código.

**Por qué no se saca el latido del todo**: sin él, una PC que se apaga sin cerrar la caja (corte de luz, se cuelga Windows) queda "abierta" para siempre en la otra, y la sesión zombi fue el incidente de los 17 pagos invisibles. Con 5 min la otra PC la ve en naranja a los 7,5 min y como cerrada a los 20. Es 12 PATCH por hora en vez de 60.

`_autocierreCajas` corre además en cada latido (es el único reloj que queda).

### Etapa 5 — Sin ping previo y sin invalidar en vano

- `pullOperationalUpdates` **no llama más a `wakeUpCloud()`**. El primer GET real es el ping: si falla con error de red, se pasa `ConnectivityService` a `cloudUnavailable` y la bajada corta ahí (hoy el ping valía un request de 20; con la red de seguridad vale uno de 16, y en el pulso uno de uno o dos). `_pingSupabase` queda solo para el cambio de red.
- `_pullTable` devuelve **cuántas filas guardó** (es `docs/pendientes/pull-devolver-cambios-reales.md`, que queda resuelta acá). `pullOperationalUpdates` suma; `FinanzasRepository.invalidateProyeccionCache()` y el `bump` de `dashboardStatsProvider` / `contratosMutationTickProvider` / `operationalSyncRevisionProvider` corren **solo si bajó alguna fila**. Cuidado del pendiente: el refresco por mutación local sigue por `contratosMutationTickProvider`, no por esto.

### Etapa 6 (opcional, SQL que solo agrega) — La red de seguridad en una consulta

Una función `sync_novedades(marcas jsonb) returns jsonb` que recibe `{tabla: last_pull_<tabla>}` y devuelve solo las tablas cuyo `max(updated_at)` es mayor. La red de 5 min pasa de 16 GET a **1 POST**, y baja solo lo que la función marcó. Es `security definer` sobre las mismas tablas que ya lee el usuario (sin abrir nada a anónimos), con `ROLLBACK` comentado arriba y verificación abajo, como siempre. Se corre antes de instalar, y hasta que no esté corrido la app usa el camino de la etapa 3 (si la RPC da 404, cae a las 16 GET: nunca se queda sin red de seguridad).

Si se hace, el reposo de una PC queda en **~1 request cada 5 min más 1 cada 30, más el latido**: unos 30 por hora. Sin la etapa 6, unos 290 por hora (16 GET y 3 counts cada 5 min, 23 GET cada 30, 12 latidos). Hoy, activa, son unos 7.000.

---

## 4. Dónde tocar

- `lib/features/common/widgets/operational_sync_coordinator.dart` — sacar el `Timer.periodic`, `_ciclos`, el `return` por `changed`; dejar los disparadores de foco/lifecycle con el "más de 60 s".
- `lib/core/services/sync_engine.dart`:
  - `_escucharElPulso` / `_atenderElPulso` (etapa 2);
  - `pullOperationalUpdates` (ping, `_contarParaVerBorrados`, retorno con filas);
  - `_pullTable` → `Future<int>`; llamadores en `pullOperationalUpdates`, `_pullFromCloud`, `_atenderElPulso`, `tablasDeLaPuerta`;
  - los dos relojes nuevos y el reintento de subida con espera creciente, al lado de `_arrancarReconciliacion`;
  - `_tocaReintentarTrabados` / `hayTrabajoDeSubida`: el timer de trabados solo mientras haya trabados.
- `lib/features/caja_sesiones/models/sesion_caja.dart` — los tres `kLatido*`.
- `lib/features/caja_sesiones/providers/app_role_provider.dart:546` — el latido llama a `autocerrarSesionesVencidas` después de latir.
- `lib/core/services/connectivity_service.dart` — exponer `marcarNubeCaida()` (o el nombre que pegue) para la etapa 5.
- `lib/features/mi_empresa/repositories/finanzas_repository.dart` — `invalidateProyeccionCache` solo con filas.
- `docs/pendientes/pull-devolver-cambios-reales.md` → estado "hecho", con el "cómo se resolvió" como en `pull-cadencia-por-niveles.md`.

## 5. Lo que no se toca

- El pulso como está: canal `sync_pulse`, evento `cambios`, `trabajoDelPulso`, el eco por `InstalacionId`.
- `refreshBeforePayment` / `refreshBeforeOpen` (`caja_auto_sync_service.dart`): antes de cobrar o abrir caja se baja todo, como hoy.
- `_reconcileDeletes` y sus 10 min; `revisarMora` al arrancar; `filasAPodar`.
- `invitados`, el tótem (`ListaDelTotem` cada 20 s solo con el tótem abierto), Recepción y la central: en la fiesta van por wifi local sin internet, y en la oficina solo corren con esa pantalla abierta.
- La web (`kIsWeb`): no tiene base local ni escucha el pulso; lee directo. La central del jefe en el iPhone para la barra queda como está.
- `SesionCajaStatusChip`: lee la PC, no la nube.

## 6. Cuidado con

- **Mientras se baja una tabla, `_isBusy` está en true.** Hoy el pulso se descartaba ahí porque había otro ciclo atrás; después de esto **no hay otro ciclo** hasta 5 min. Todo lo que hoy diga "lo cubre el ciclo de 10 s" (hay varios comentarios así en `sync_engine.dart`) hay que releerlo: o lo cubre el reintento a 3 s, o lo cubre la red de 5 min, y el comentario tiene que decir cuál.
- **El hueco del canal se mide con el reloj de la PC**, no contra el servidor: es solo para decidir si hacer catch-up, así que no entra en ningún marcador. `marcaDeLoBajado` sigue saliendo del `updated_at` de la nube.
- **No reencolar el pulso en loop.** El reintento a 3 s corre una vez por tanda; si a los 3 s sigue ocupada, otra vez a los 3 s, pero una sola cadena viva (cancelar antes de rearmar, como hoy con `_reintentoBorradosDelPulso`).
- **Versiones mezcladas.** Una PC vieja (latido de 60 s, muerto a 5 min) ve el latido de 5 min de una PC nueva como "sin señales" entre los minutos 1,5 y 5 y la muestra naranja o cerrada. Es solo el chip: `refreshBeforeOpen` informa, no bloquea, y `autocerrarSesionesVencidas` cierra por cambio de día, no por latido. Igual: **instalar las tres PCs el mismo día.**
- **La barra en la fiesta** sube cuando vuelve internet (`puedeSubirSolo` con `role.esBarra`): el reintento con espera creciente tiene que reiniciarse en `online`, no esperar los 5 min.
- **Un `Timer` por PC, no por pantalla.** Los relojes nuevos viven en `SyncEngine` (singleton por `syncEngineProvider`), nunca en un widget: una pantalla montada dos veces no puede duplicar la red de seguridad.
- La trampa del `async*` con `await for` (CLAUDE.md) vale para cualquier stream nuevo que escuche el estado del canal.

## 7. Pruebas (sandbox, sin la base real ni la nube)

Con un `SupabaseClient` falso que cuente requests por tabla y un reloj controlado (`fake_async`):

1. **Reposo**: app arrancada, cola vacía, sin pulsos. En 4 min simulados: **0 GET a tablas, 0 counts, 0 pings**; a los 5 min, exactamente una tanda de `_tablasDelCobro` y los 3 counts; a los 30, una de `_tablasDeCarga`.
2. **Latido**: con caja abierta, 1 PATCH a `sesiones_caja` cada 5 min y un pulso con esa tabla; la otra PC (simulada) baja solo `sesiones_caja` y su chip la sigue viendo "en uso" sin pasar por naranja aunque se pierda un latido; `kLatidoSesionPeriodo < kLatidoSesionVivo < kLatidoSesionMuerto` y `vivo > 2 × periodo` (test que lee las tres constantes).
3. **Pulso con la PC ocupada**: `_isBusy` en true al llegar un pulso de `pagos_contrato_alumno`; a los 3 s se desocupa; la tabla **se baja** (hoy se perdería).
4. **Catch-up**: `closed` → 25 s → `subscribed`: una bajada de `_tablasDelCobro`. Con 10 s de hueco: ninguna.
5. **Vuelve la red**: `offline` → `online`: una bajada de `_tablasDelCobro` y, si la cola tiene algo, la subida en el acto.
6. **Subida que falla**: la nube devuelve error; reintentos a 30 s, 1, 2, 5, 5 min; al éxito, nada más.
7. **Invalidar solo con filas**: una bajada que trae 0 filas no toca `invalidateProyeccionCache` ni los providers; una con 1 fila sí.
8. **Pulso desde la barra, Entradas y la puerta**: encolar una venta, una entrega y una silla de la noche dispara un pulso con esas tablas.
9. Lo que ya hay sigue en verde: `test/borrados_de_otra_pc_test.dart`, `test/filas_a_podar_test.dart`, los de sesiones de caja y los de la barra.

## 8. Publicación

- Sin SQL (etapas 1 a 5). La etapa 6, si se hace, se corre antes de instalar como siempre.
- Entra en la misma versión que la barra y Entradas. Instalar las tres PCs el mismo día.
- Foto de la mora antes y después, como con toda versión.
- **Cómo verificar después, desde el MCP de Supabase** (logs, ventana de 20 min con la oficina abierta y nadie cobrando):

```sql
select log_attributes['request.method'] as m, log_attributes['request.path'] as p, count(*) as n
from logs where source = 'edge_logs'
group by 1, 2 order by n desc
```

  Lo esperado: `PATCH /rest/v1/sesiones_caja` ~4 por PC, las 16 tablas ~4 veces cada una, y ningún `GET /rest/v1/servicios`. Hoy, activa, la misma consulta da ~2.400 requests por PC.

## Diseño aprobado (6-nov-2026, al revisar contra el código)

Copiado del plan aprobado esa noche. Manda sobre lo de arriba donde no coincidan.

### Etapa B — versión 6.3.3

Se programa en `release/6.3.x` después del parche, etapa por etapa (1 a 5), cada una con sus pruebas en verde antes de la siguiente, y cada commit al mismo tiempo a la rama feature por `cherry-pick` (en `sync_engine.dart` el único roce posible son las líneas de `sillas_puerta`). Al terminar la 5: `flutter test` entero en las dos ramas, versión `6.3.3+65`, tag, CONTEXTO, y la publicación con el procedimiento de siempre (foto de la mora antes y después también: toda versión la lleva). **Sin SQL.** La etapa 6 (la RPC) queda para más adelante.

#### B0. Transversal

- **`RelojDelMotor`** (`lib/core/services/reloj_del_motor.dart`): `ahora()`, `programar(Duration, accion)`, `periodico(Duration, accion)`, `const RelojDelMotor.real()`. `SyncEngine({..., RelojDelMotor reloj = const RelojDelMotor.real()})`. Todos los `Timer`, `Timer.periodic` y `DateTime.now()` que deciden algo en el motor pasan por `_reloj` (subida, reconciliación, debounce del pulso, trabados, relojes nuevos, `_lastPullTime`). `test/helpers/reloj_de_prueba.dart`: `avanzar(Duration)` dispara los vencidos, `pendientes` lista las esperas. `@visibleForTesting Future<void> aquietar()` espera la bajada o subida en curso. Los tests que ya construyen el motor sin `start()` siguen con timers reales y sin cambios.
- **Dónde viven los relojes nuevos**: en `SyncEngine`, al lado de `_arrancarReconciliacion` (521-556), armados en `start()` con `if (kIsWeb) return`, cancelados en `dispose()`. Nada en widgets (una pantalla montada dos veces no puede duplicarlos).
- **Una sola bajada a la vez**: todo camino automático que baja respeta `_isBusy` y se marca `syncing` mientras baja (hoy `_atenderElPulso` no). Ocupado: el pulso rearma su única cadena a 3 s; las redes y disparadores a 30 s. `bajarParaLaPuerta`/`bajarParaLaBarra` siguen por fuera (es su contrato). `refreshBeforePayment` no se toca (sus 3×350 ms cubren un pulso de 2-3 tablas; informa, no bloquea).
- Lo que anota el motor con `_reloj.ahora()`: `_ultimaBajadaDelCobro`, `_ultimaBajadaDeCarga`, `_canalCaidoDesde`. Nunca entran en marcadores (`marcaDeLoBajado` sigue saliendo del `updated_at` de la nube).

#### B1. El coordinador deja el reloj de 10 s

`lib/features/common/widgets/operational_sync_coordinator.dart`: se van el `Timer.periodic` (75), `_ciclos`, `_running`, `puedeSubirSolo` y el bloque de subida (144-161), `incluirTablasDeCarga` y los tres bumps (168-174); en el motor se borra `ciclosEntrePullsLentos`. Queda: `_autocierreCajas`; primer frame → `engine.bajarAlArrancar()` (todo, con la primera vez por sesión de `_reconcileDeletes` + `revisarMora` como está); `resumed`/`onWindowFocus`/`onWindowRestore` → `engine.bajarAlMirar()` (baja `_tablasDelCobro` solo si `ahora − _ultimaBajadaDelCobro > 60 s`); `initState` escucha `engine.cambiosBajadosStream` y hace los tres bumps.

**Reintento de subida con espera creciente** (motor): `esperaCreciente(int intento)` pura top-level (30 s, 1, 2, 5 min, y 5 min para siempre), con test. Al terminar `flushPending` (en el `finally`): si `readyCount > 0` → `_timerReintentoSubida = _reloj.programar(esperaCreciente(_intentoSubida++))`; si 0 → reinicia y cancela. Cubre el fallo de red y el rechazo fila por fila. Un encolado nuevo sigue disparando `_programarSubida` a los 2 s. Vuelve la red → `_intentoSubida = 0` y subida inmediata. Trabados: `_timerTrabados` de 5 min solo mientras `stuckCount > 0`. Nada se saca de la cola por fallar (`_isNonRetryableError` no cambia).

#### B2. El pulso pasa a transporte

`_atenderElPulso` (819-872): ocupado u offline → **no** se vacía `_tablasDelPulso`; una sola cadena `_reintentoDelPulso` (renombrar `_reintentoBorradosDelPulso`) a 3 s para tablas y borrados; mientras baja, `syncing` y al final `_reportarFallosDePull()`.

**Catch-up del canal** (`_escucharElPulso`, 790-800): `subscribe((status, error) => _estadoDelCanal(status))` (firma de `realtime_client` 2.7.1, como `asesor_home_screen.dart:52`). `closed`/`channelError`/`timedOut` → `_canalCaidoDesde ??= ahora` y `_reintentoCanal` con `esperaCreciente` que vuelve a `subscribe` (por si `supabase_flutter` no rejoinea solo; verificar en el sandbox cortando el socket); `subscribed` → si el hueco > 20 s, una bajada de `_tablasDelCobro`; el primer `subscribed` del arranque no hace nada. `@visibleForTesting recibirEstadoDelCanal(status)` al lado de `recibirPulso`. Sin acuses.

#### B3. La red de seguridad

En el motor: `_redDeSeguridadCobro` cada **5 min** (`_tablasDelCobro` + `_contarParaVerBorrados`; ocupado → reintento único a 30 s; si alguien bajó todo hace < 1 min, se saltea) y `_redDeSeguridadCarga` cada **30 min** (`_tablasDeCarga`). Las dos listas no cambian de nombre ni de contenido (los `sync_tablas_v7x_test` leen su declaración). `pullOperationalUpdates` deja de llamar `_contarParaVerBorrados` en cada corrida; la primera vez por sesión (`_moraRevisadaEnEstaSesion`) sigue tal cual. Disparadores: arrancar, vuelve la red (`_connectivitySub`: `online` desde `offline`/`cloudUnavailable` → subida inmediata si hay trabajo + `_tablasDelCobro`), catch-up, antes de cobrar (sin tocar), foco, pulso. `_cadaCuantoSeReconcilia` (10 min) no cambia.

#### B4. El latido cada 5 minutos

`sesion_caja.dart:4-14`: `kLatidoSesionPeriodo` 5 min, `kLatidoSesionVivo` 11 min, `kLatidoSesionMuerto` 20 min. `app_role_provider.dart:539-572` no cambia de código (ya llama `autocerrarSesionesVencidas()` en cada latido y usa la constante); solo el comentario. `sesion_caja_status_chip.dart` no se toca.

**El latido dispara pulso sin refrescar pantallas**: `_anotarParaElPulso` (752-763) saca el `return` de 758; `esSoloLatido` se sigue usando para marcar `_soloLatidoEnEstaTanda`; `_emitirPulso` manda `'latido': true` en ese caso; `trabajoDelPulso` lo lee como `soloLatido`; `_atenderElPulso` baja con `_pullTable(..., avisar: false)` que no llama `_anotarCambioBajado`. La bajada del latido por la red de 5 min sí bumpea (12 veces por hora como mucho): aceptable.

`test/latido_sesion_test.dart` nuevo: `periodo < vivo < muerto`, `vivo > 2 × periodo`, `muerto ≥ 3 × periodo`, y lee `app_role_provider.dart` para exigir `Timer.periodic(kLatidoSesionPeriodo`.

#### B5. Sin ping y sin invalidar en vano

- `connectivity_service.dart`: `marcarNubeCaida({required Future<bool> Function() sondeo})` pone `cloudUnavailable` y arma un reintento con `esperaCreciente` que corre el sondeo que le pasa el motor (con el cliente inyectado, no el global); al dar bien, `online`. `marcarNubeViva()` tras cualquier request que salió bien. `_pingSupabase` queda solo para el cambio de red y el chequeo inicial. **Sin ese reintento es una regresión**: una Nano que tardó 40 s en despertar dejaría la app sin sync hasta que cambie la red.
- Motor: sacar `wakeUpCloud()` de `pullOperationalUpdates` (1320-1325) y `flushPending` (604-610); dejarlo en `pullRemote`/`probeRemoteChanges` (manuales). `esCaidaDeLaNube(Object e)` pura (`SocketException`, `ClientException`, `TimeoutException`, Postgrest 5xx/PGRST0xx), con test; en el `catch` de `_pullTable` y de `_flushQueue` → `marcarNubeCaida`. **La primera tabla es el ping**: `pullOperationalUpdates` baja `sesiones_caja` sola y secuencial; si quedó `cloudUnavailable`, corta; si no, `Future.wait` del resto. El motor frena también en `cloudUnavailable` (`_sinNube => currentStatus != online` reemplaza las ~10 comparaciones con `offline`); `_connectivitySub` lo mapea a `SyncStatus.error` con "Nube no disponible".
- `_pullTable` → `Future<({bool ok, int filas})>` (`filas` = novedades, 2306), parámetro `bool avisar = true`. Llamadores: `_atenderElPulso` 864, `pullOperationalUpdates` 1342, `bajarParaLaPuerta` 2460-2464, `bajarParaLaBarra` 2490-2493.
- `FinanzasRepository.invalidateProyeccionCache()`: una sola llamada en `_avisarCambiosBajados` (459-464); se borran las de 666 y 1344. `@visibleForTesting static int vecesInvalidada` para el test.

#### B6. (opcional, última, separable) La red en una consulta

SQL `supabase/migrations/2026xxxx_sync_novedades.sql`: `sync_novedades(marcas jsonb) returns jsonb`, `security definer`, lista **fija** de tablas escrita en la función (nunca las claves del JSON), devuelve `{tabla: {max, n}}` solo si `max > marca`; `revoke` a `public`/`anon`, `grant` a `authenticated`; `ROLLBACK` comentado arriba y verificación abajo. `n` reemplaza los 3 `count`. Motor: la red prueba `rpc('sync_novedades')`; con PGRST202/404 cae a las 16 GET + 3 count por el resto de la sesión. Se corre antes de instalar; sin correrlo la app anda igual. Verificar que `test/puerta_cerrada_test.dart` no la tome por función de anónimos.

#### B7. Tests (sandbox, sin la base real ni la nube)

Arnés común nuevo: `test/helpers/nube_de_prueba.dart` (sacar `_Nube` de `borrados_de_otra_pc_test.dart:95-144`, con `fallan` para PATCH/POST y `pedidas` como `'GET tabla'`/`'PATCH tabla'`/`'HEAD tabla'`), `test/helpers/reloj_de_prueba.dart`, y `ConexionDePrueba` (ya existe en `puerta_en_memoria.dart:91-106`; moverla a `test/helpers/`). El motor se construye con `start()` y `addTearDown(motor.dispose)`.

| # | Test (sección 7 de la spec) | Archivo | Reloj simulado |
|---|---|---|---|
| 1 | Reposo: 4 min → 0 GET/0 count/0 ping; a los 5 min exactamente 16 GET + 3 HEAD; a los 30, 23 GET | `test/sync_en_reposo_test.dart` | sí |
| 2 | Latido: constantes (`latido_sesion_test`); el pulso del latido trae `sesiones_caja` y `latido: true` (`@visibleForTesting ultimoPulsoArmado`); la otra PC baja solo esa tabla y `cambiosBajadosStream` calla; `SesionCaja(lastHeartbeat: ahora − 9 min).enUsoAhora()` true | ambos | debounce |
| 3 | Pulso con la PC ocupada: `frenadas` + pull en vuelo; pulso; 400 ms → nada; soltar; 3 s → `GET pagos_contrato_alumno` | `sync_en_reposo_test.dart` | sí |
| 4 | Catch-up: `closed` → 25 s → `subscribed`: una tanda; con 10 s, ninguna | ídem | sí |
| 5 | Vuelve la red: `offline` → `online`: una tanda y, con cola, la subida en el acto. **Es el caso del campo** (pregunta del usuario, 6-nov): abrir caja sin internet, cobrar todo el día en local, llegar a la oficina y que suba solo. El test cobra varios pagos `offline` y comprueba que al pasar a `online` suben todos y nada queda en la cola | ídem | no |
| 6 | Subida que falla: `pendientes` = 30 s → 1 → 2 → 5 → 5 min; al éxito, nada | ídem | sí |
| 7 | Invalidar solo con filas: 0 novedades → `vecesInvalidada` igual y stream mudo; 1 fila → +1 y un evento | ídem | 300 ms |
| 8 | Pulso desde la barra, Entradas y la puerta: encolar `barra_ventas`, `entradas_retiro`, `sillas_puerta` → el pulso los trae, sin `latido` | ídem | no |
| 9 | Lo que ya hay sigue en verde: `borrados_de_otra_pc_test` (su test 527-574 sigue con `Future.delayed` reales), `filas_a_podar_test`, sesiones de caja, barra, `revision_mora_test` grupo 5 | — | — |

Más dos puros: `esperaCreciente` y `esCaidaDeLaNube`.

#### B8. Comentarios a releer (cada uno dice qué lo cubre ahora)

- **El reintento a 3 s**: `sync_engine.dart:826-827` y `694-697` (el pulso deja de ser "acelerador, no transporte").
- **La red de 5 min**: `sync_engine.dart:511-512, 785, 1159-1163, 1358, 2474, 3182, 3330, 3341-3346, 2424-2427, 398, 2163`; `borrados_de_otra_pc.dart:20`; `contratos_repository.dart:1017`; `finanzas_repository.dart:337-338`; `finanzas_provider.dart:335`; `cierre_caja_provider.dart:297`; `detalle_evento_masivo_screen.dart:155`.
- **El reintento con espera creciente**: `sync_engine.dart:568-574, 1516`; `sync_queue.dart:199, 244`; `subir_ya.dart:18, 60, 65`.
- **Ya no aplica**: `sync_engine.dart:101-102, 440, 475-476, 524-528, 755-757, 1195, 1244-1245`; `operational_sync_coordinator.dart:157`; `cierre_caja_screen.dart:358`; `cierre_caja_provider.dart:430`; nombres de tests "cada 10 s" en `sync_tablas_v75/v77/v78_test`.
- **No tocar** (falsos positivos): `cobro_agrupado.dart:12, 171`; `finanzas_provider.dart:829`.

#### B9. Requests por PC en reposo

| | Hoy | Etapas 1-5 | Con la 6 |
|---|---|---|---|
| Ciclo operativo | ~7.200/h | 0 | 0 |
| Red del cobro | — | 12 × (16 GET + 3 count) = 228/h | 12/h |
| Red de carga | — | 46/h | 2/h |
| Revisión de borrados (10 min, no se toca) | ~150-300/h | igual | igual |
| Latido con caja abierta | 60 PATCH + 60 pings/h | 12 PATCH/h | igual |
| **Total** | **~7.500/h** | **~430-590/h** | **~175-330/h** |

Con la etapa 6 hecha, el 90 % del reposo pasa a ser la revisión de borrados de 10 min: no se toca ahora; queda como pendiente (`docs/pendientes/revision-de-borrados-por-rpc.md`).

---
