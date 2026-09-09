# Junior Eventos / Argüello Events

App Flutter de gestión operativa para eventos: presupuestos, finanzas, recepción
con check-in por QR y un tótem que se proyecta en el salón.

- Paquete: `arguello_events` · versión en `pubspec.yaml` (mantener en sync con
  `installer/junior_eventos_setup.iss`).
- Supabase: proyecto `bucnrydgojyzntgesxqb` (ArguelloApp). Credenciales en
  `lib/main.dart:29-34`.
- Web deployada en `https://arguello-events.vercel.app` (`kWebBaseUrl`).

## Antes de tocar nada: la rama

**El desarrollo va en `feature/v4.6-cierre-por-sesiones`, no en `main`.** Esa
rama está ~74 commits adelante y va por la v4.9.4; `main` quedó en la 2.2.0.
Ramificar de `main` significa trabajar sobre código de hace meses.

## Documentación del proyecto

Hay convenciones propias, y conviene respetarlas antes de inventar otras:

- `docs/CONTEXTO_<version>_<fecha>.md` — qué se hizo en cada release y por qué.
  El más reciente es el mejor punto de entrada al estado actual.
- `docs/pendientes/` — trabajo **ya decidido** que se postergó. Un archivo por
  pendiente, con estado, fecha y —lo importante— **por qué** se postergó.
- `docs/ideas/` — lo que capaz nunca se hace. No confundir con pendientes.
- `tool/` — scripts de diagnóstico y arreglo puntuales (`recalcular_contrato.dart`,
  auditorías de mora, reconciliaciones). Muchos son de un solo uso pero
  documentan incidentes reales.

Los mensajes de commit describen el efecto para el usuario, no el cambio
técnico: "el perdón de mora ahora cruza entre las dos PCs", no "fix sync".

## Arquitectura

**Offline-first.** SQLite local (`lib/core/database/local_database.dart`, va por
la versión 38) es la fuente de verdad del escritorio; los cambios se encolan en
`_sync_queue` y suben a Supabase cuando hay red. La web va directo a Supabase.

- Escritorio/móvil: `InvitadosRepository` (SQLite + cola de sync).
- Web: `SupabaseInvitadosRepository` (Supabase directo).
- No comparten interfaz: en `totem_checkin_screen.dart` se elige por `kIsWeb`
  con un cast `as dynamic`.

**Rutas por URL en web** (`lib/main.dart:80-130`): se detectan con `contains()`
sobre `Uri.base`, no con path parsing.

| URL | Pantalla | Login |
|---|---|---|
| `?cotizar` | Catálogo público | No |
| `?totem&evento=<id>` | Tótem | **No** (deliberado: se proyecta desde una smart TV) |
| `?lista&evento=<id>` | Lo que ve el invitado al escanear el QR | No |
| `?buscar&evento=<id>` | Self check-in por DNI | No |
| `/op?evento=<id>` | Operador con PIN | No |

**Ventana secundaria de escritorio.** El tótem nativo corre en otra ventana vía
`desktop_multi_window` (`KioskLauncher`). Esa ventana **no** inicializa el
singleton de Supabase (crashea `app_links`): crea un `SupabaseClient` propio y lo
inyecta con `supabaseProvider.overrideWithValue(...)` (`main.dart:48-64`). Por eso
**todo provider que use Supabase debe leer `supabaseProvider`, nunca
`Supabase.instance`**, si va a correr en el tótem.

Comunicación entre ventanas: `DesktopMultiWindow.invokeMethod` con los métodos
`refresh`, `list_reset`, `guest_checkin`, `guest_removed`.

## Roles y permisos

Solo dos roles en `perfiles.rol`: `Admin` y `Asesor`. La única comparación de rol
de toda la app está en `user_role_provider.dart:66`.

- Admin → `DashboardScreen`, con `UserPermissions.admin()` (todo en true).
- Asesor → `AsesorHomeScreen`, con flags granulares de `permisos_usuario`
  (`puede_eventos`, `puede_totem`, `puede_recepcion`, …). Cada flag prende o
  apaga una tarjeta del menú.

Se asignan desde Mi Empresa → pestaña OPERADORES (`finanzas_view.dart`, ~6500
líneas; el diálogo está en `_showPermissionsDialog`).

**Ojo:** hay un segundo concepto de "admin" totalmente independiente, por PIN
local (`admin_provider.dart`, PIN maestro `2026`, TTL 3 min), que gatea Mi
Empresa. No se cruza con el rol de Supabase.

**El rol se cachea** (`user_role_cache.dart`) y hoy solo se invalida al cambiar
de sesión (`main.dart:567-576`), así que un permiso recién asignado no se ve
hasta re-loguear.

## El tótem

Hay **dos implementaciones casi idénticas** que no comparten código (~800 líneas
duplicadas). Cualquier cambio visual hay que hacerlo dos veces:

- `totem_display.dart` — la pantalla del salón. Va por Supabase directo. Es la
  que se usa en la ventana secundaria, en `?totem` y en la ruta
  `/totem_display`.
- `totem_panel.dart` — panel embebido en Recepción. Va por SQLite.

El tótem **muestra** un QR, no lo lee: no hay dependencia de cámara. El QR apunta
a `/lista?evento=<id>`, que abre el invitado en su celular. Al confirmar el
check-in, esa pantalla emite un broadcast por el canal `totem_<eventoId>`, que es
el bus de baja latencia que evita esperar la replicación de Postgres.

Identidad visual por evento en la tabla `totem_config` (foto, título, subtítulo,
saludo, color). Sin fila, `TotemConfig.defaults()` devuelve los literales
históricos y la pantalla se ve como siempre.

## Trampas conocidas

- **Nada se borra de la base local salvo que alguien lo haya borrado a mano.**
  Un `DELETE` local solo es legítimo si viene con nombre y apellido —una lista
  explícita de ids que una persona eliminó— o si sale de comparar contra una
  foto **completa y contada** de la nube, del mismo alcance que se va a
  recorrer. Un lote incremental, una página que cortó en las 1000 filas de
  PostgREST, o una consulta que falló a medias: ninguna autoriza a borrar nada.

  Es la misma clase de trampa que la de `REPLICA IDENTITY` de acá abajo: parece
  gratis y rompe en silencio. El prune de `_pullTable` comparaba el delta
  incremental —las pocas líneas que alguien acababa de tocar en la otra PC—
  contra **todas** las filas locales de `presupuesto_servicios`, y borraba el
  resto. Como el monto del presupuesto no existe como columna, es la suma de sus
  líneas, los presupuestos aparecían en **$0**: sin excepción, sin log, y solo
  en la PC que más sincronizaba. La nube nunca se tocó —los `delete` a Supabase
  salen solo de la cola— y por eso el pull forzado devolvía todo.

  Hoy la decisión vive en `filasAPodar` (`sync_engine.dart`), con su test en
  `test/filas_a_podar_test.dart`. **Cualquier camino nuevo que borre tiene que
  pasar por ahí**, no reimplementar la comparación al lado.

- **El `updated_at` de Supabase lo mantiene un trigger, no los repos.** Hay un
  `before insert or update` sobre cada tabla sincronizada que corre
  `public.update_updated_at_column()`. Estuvo aplicado a mano y sin versionar
  desde 2026 hasta que se versionó en
  `supabase/migrations/20260908120000_updated_at_trigger.sql` — leyendo solo el
  repo la conclusión razonable era que no existía, y eso ya mandó a un plan a
  "arreglar" algo que funcionaba. Si agregás una tabla al sync, **agregale el
  trigger**: sin él sus ediciones no cruzan nunca, porque el motor no rellena
  `updated_at` y varios repos tampoco.

- **El marcador del pull sale del servidor, no de la PC.** `marcaDeLoBajado`
  toma el `updated_at` más alto de lo que bajó. No volver a usar `DateTime.now()`
  para eso: se compara contra el reloj de Postgres, y la diferencia entre los
  dos relojes entra directo en el filtro.

- **`REPLICA IDENTITY` y los DELETE.** Cualquier suscripción de Realtime
  **filtrada por una columna** —sea `.stream().eq(...)` o un
  `PostgresChangeFilter`— **descarta los DELETE** si la tabla está en
  `REPLICA IDENTITY DEFAULT`: el payload del borrado lleva solo la primary key,
  el servidor no puede evaluar el filtro y tira el evento. Por eso `invitados`
  necesita `REPLICA IDENTITY FULL` (ver `supabase/migracion_totem_config.sql`).

  Vale la pena entender el orden en que pasó, porque es fácil repetirlo: el
  panel de Recepción funcionaba porque su `onPostgresChanges` **no tenía
  filtro**. Al agregarle el filtro por `evento_id` el 2026-09-02 —una
  optimización correcta y necesaria— quedó ciego a los borrados, igual que el
  tótem. Agregar un filtro a una suscripción es gratis en apariencia y rompe
  los DELETE en silencio. Si una lista filtrada no se actualiza al borrar,
  empezar por acá.
- **Realtime no cubre todas las tablas.** Verificar con `pg_publication_tables`
  antes de suscribirse: varias tablas no están en la publicación
  `supabase_realtime`.
- **IDs malformados.** Supabase tira 22P02 con un UUID inválido. Los repos
  abortan si `eventoId.length != 36`; conviene mantener ese blindaje.
- **Branding inconsistente.** Los títulos de app dicen "Argüello Events" y la UI
  del tótem decía "Junior Eventos".
- **`flutter analyze` no corre en las sesiones remotas de Claude Code**: el
  contenedor no trae Flutter ni Dart. Hay que correrlo localmente.

## Archivos grandes

`finanzas_view.dart` (~6500), `totem_display.dart` (~1900),
`totem_panel.dart` (~1500), `local_database.dart` (~1200 con todas las
migraciones). Leer por tramos, no enteros.

## SQL

Las migraciones se versionan en `supabase/` y se corren a mano en el SQL Editor.
No hay CLI de Supabase configurado. Convención: cada sentencia riesgosa lleva su
`ROLLBACK` escrito arriba, comentado.
