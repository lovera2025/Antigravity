# SPEC — El aviso entre PCs se tira cuando llega por el socket (parche 6.3.4)

**Archivo:** `docs/SPEC_pulso_por_el_socket_2026-11-07.md`
**Rama:** `release/6.3.x` (hoy en 6.3.3+65). El commit se lleva también a la rama de desarrollo.
**SQL:** ninguno. **Migración local:** ninguna.

> **Decidido el 7-nov (a la noche), pasa por encima de lo de abajo:** no sale como 6.3.4 sola desde `release/6.3.x`. Entra en el
> plan general y **se publica todo junto al final**, en la 6.4.0, desde `feature/v4.6-cierre-por-sesiones` (con el cambio de fecha de
> un cobro, la barra y Entradas). El usuario no veía la falla porque la otra PC se pone al día cuando alguien vuelve a la ventana de
> la app; lo que falta es que se ponga al día sola, también minimizada.
>
> Revisado contra el código el mismo día: la app lee `mensaje['payload']` desde el 8-sep (`26df5c0`), la librería 2.7.1 hace lo que
> dice la sección 3, y en los registros de la nube se ve igual (8:24 por REST, la otra PC baja en 1 s; 9:26 por el socket, la otra
> baja recién a las 9:27:24 al traer la ventana al frente).
>
> **La prueba del punto 9 (contra Supabase de verdad) necesita el OK del usuario**: su regla es no probar contra la nube. Sin ella,
> la falla ya está a la vista en los registros, y el arreglo se comprueba igual con los registros después de instalar (sección 9).

---

## 1. Qué pasa

Con la 6.3.3 instalada en las dos PCs, **lo que se cobra o se cambia en una no aparece solo en la otra**. Aparece:

- cuando alguien trae la otra ventana al frente y pasó más de un minuto desde su última bajada (`bajarAlMirar`). Por eso a simple vista "llega al instante";
- o con la red de seguridad: 5 minutos para lo del cobro, 30 para lo demás.

El aviso entre PCs (el pulso) **sale bien, llega bien y la PC que lo recibe lo tira sin error**. Desde la 6.3.3 era lo único que traía las cosas al instante, porque ya no está el ciclo de 10 s. Lo más probable es que el error venga desde que existe el pulso (4.9.4) y que el ciclo de 10 s lo haya tapado hasta ahora.

## 2. Lo medido el 7-nov (edge logs de Supabase, hora de Argentina)

| Hora | Qué pasó | Qué hizo la otra PC | ¿Funcionó? |
|---|---|---|---|
| 8:24:42 | La PC de Maxi abre caja recién arrancada. Su canal todavía no estaba conectado, así que el aviso salió por **REST** (`POST /realtime/v1/api/broadcast`) | `GET sesiones_caja` 1 s después; lo mismo con `cierre_caja_guia_movimientos` a las 8:24:51 | **Sí** |
| 9:26:19 | Cobro en la PC del jefe, con el canal conectado: el aviso sale por el **socket** | La de Maxi baja recién a las 9:27:24, 65 s después, con las 14 tablas del cobro (el patrón de `bajarAlMirar`) | No |
| 10:00:17 | Cobro, aviso por el socket | La otra baja a las 10:01:20 (63 s), otra vez por `bajarAlMirar` | No |
| 10:39:29 | Cobro en la PC de Maxi; la del jefe estaba abierta desde las 10:33 | La del jefe baja a las 10:43:20, con la red de 5 min | No |
| 10:33–11:05 | Unos 12 latidos de cada PC (desde la 6.3.3 cada latido manda aviso) | Ningún `GET sesiones_caja` en la otra en los segundos siguientes | No |

Un aviso atendido se ve así en los logs: **en menos de un segundo, uno o dos `GET` con solo las tablas del aviso**. Desde que los canales están conectados, eso no aparece nunca.

(El cobro de las 10:28 no cuenta: la PC del jefe estuvo cerrada entre las 10:01 y las 10:33.)

## 3. La causa (verificada en los tres lugares)

El mismo aviso llega con **dos formas distintas** según por dónde salió, y la app lee una sola.

**La app** (`lib/core/services/sync_engine.dart`):

- `_emitirPulso` (≈1106) manda `{origen, tablas, borrados, latido?}` con `canal.sendBroadcastMessage(event: 'cambios', payload: payload)` por **el mismo canal** que escucha (`_canalPulso`, ≈1129 y ≈1144). Ese canal está suscripto, así que en uso normal sale por el socket.
- `_alRecibirPulso` (≈1200) lee `mensaje['payload']` y se lo pasa a `trabajoDelPulso`. Si eso no es un `Map`, devuelve `TrabajoDelPulso.vacio` y no pasa nada: sin log y sin error.

**La librería** (`realtime_client` 2.7.1, que trae `supabase_flutter` 2.12.2 según `pubspec.lock`; protocolo `vsn=1.0.0`, visto en los logs), en `lib/src/realtime_channel.dart`:

- `sendBroadcastMessage` (583-592) le pasa **el mismo mapa** a `send`.
- `send` (595-647) le agrega `type` y `event` a ese mapa (603-606).
  - **Con el canal unido** (`canPush`, 486-488) lo empuja por el socket **tal cual** (648).
  - **Sin unir**, cae al REST (608-646) con `{topic, payload: <el mapa>, event, private}`.
- `onBroadcast` (349-358) y `trigger` (809-835) le pasan al callback el mensaje **tal como llegó**.

**El servidor** (`supabase/realtime`, rama principal leída el 7-nov):

- Por el socket (`realtime_channel/broadcast_handler.ex`, `build_broadcast`): reenvía el mensaje **tal cual**.
- Por REST (`tenants/batch_broadcast.ex:146`): lo **envuelve**, `%{"payload" => message.payload, "event" => ..., "type" => "broadcast"}`.

**Resultado:**

| Salió por | Le llega al callback | `mensaje['payload']` |
|---|---|---|
| Socket (lo normal) | `{origen, tablas, borrados, latido?, type, event}` | `null` → **se tira** |
| REST (canal sin unir) | `{type, event, payload: {origen, tablas, …}}` | el aviso → **funciona** |

## 4. Por qué los tests dieron verde

Todos arman el aviso **envuelto**, con la forma del REST: `aviso()` en `test/sync_en_reposo_test.dart:486`, el mensaje de `:692`, `test/trabajo_del_pulso_test.dart` y `test/borrados_de_otra_pc_test.dart`. Ninguno pasó por la librería ni por Supabase, y el motor se arma con `conCanalDelPulso: false`. La forma que llega en producción no la probó nadie.

## 5. Qué arrastra hoy (6.3.3 en las PCs)

- **Lo nuevo de la otra PC** llega al traer la ventana al frente (si pasó más de un minuto), y si no, con la red de 5 o 30 minutos. **Si la PC ya está al frente y nadie la toca** (el jefe mirando el panel), no se actualiza hasta la red de 5 minutos.
- **Los borrados** no llegan al instante. Los traen la cuenta de cada 5 minutos (pagos, alumnos, egresos), la revisión de cada 10, la del arranque o abrir el alumno.
- **La plata no corre riesgo inmediato**: antes de cobrar se baja todo (`refreshBeforePayment`, no se toca).
- **El latido no se ve afectado**: la otra PC lo ve con hasta ~10 minutos de atraso, y `kLatidoSesionVivo` es de 11 (`sesion_caja.dart:15`). La caja no se pone en duda por esto.

## 6. El arreglo

### 6.1 Leer las dos formas, en un solo lugar

Una función nueva, por ejemplo en `lib/core/services/cuerpo_del_broadcast.dart`:

```dart
/// Lo que mandó quien emitió un broadcast, llegue por donde llegue.
///
/// Por el socket, Supabase reenvía el mensaje tal cual: los datos vienen
/// sueltos, más `type` y `event`, que agrega la librería. Por REST (cuando
/// el canal de quien manda todavía no se unió) el servidor los envuelve en
/// `payload`. Ver docs/SPEC_pulso_por_el_socket_2026-11-07.md.
///
/// Regla: ningún aviso nuestro lleva una clave propia llamada `payload`.
Map<String, dynamic>? cuerpoDelBroadcast(Map<String, dynamic> mensaje) {
  final envuelto = mensaje['payload'];
  if (envuelto is Map) return Map<String, dynamic>.from(envuelto);
  if (envuelto != null) return null; // un `payload` con otra forma: no se adivina
  return Map<String, dynamic>.from(mensaje)
    ..remove('type')
    ..remove('event');
}
```

### 6.2 El pulso

En `_alRecibirPulso`:

```dart
    final trabajo = trabajoDelPulso(
      cuerpoDelBroadcast(mensaje),
      yo: InstalacionId.valor,
      tablasConocidas: _incrementalColumns.keys.toSet(),
    );
```

`trabajoDelPulso` ya trata `null` como trabajo vacío, así que no cambia.

### 6.3 El canal del tótem (mismo error)

`InvitadosRepository._canalEmisor` (`invitados_repository.dart:39-41`) manda por `_activeChannels[eventoId]` cuando Recepción tiene el panel abierto, y ese canal está suscripto: el aviso sale por el socket. `totem_display.dart:549-562` lee `payload['payload']` en `checkin` y `guest_removed`, así que **un tótem que no corre en esa PC** (el de la web, `?totem`, u otra máquina) no saluda al instante. Recién se entera con `totem_lista` a los 20 s.

- El tótem de la notebook no se ve afectado, porque recibe los ingresos por el puente entre ventanas.
- La página del QR (`supabase_invitados_repository.dart:166`) manda por un canal sin suscribir: sale por REST y hoy funciona.

**Arreglo:** `checkin` y `guest_removed` leen con `cuerpoDelBroadcast(payload)`. `Invitado.fromJson` ignora `type` y `event` (lee solo sus nueve claves), pero igual la función los saca.

### 6.4 Lo que NO se cambia

- **Quien manda, igual: el aviso sigue saliendo por el socket.** Mandar siempre por REST le sumaría un pedido HTTP a la nube por cada aviso, justo lo contrario del sync en reposo.
- `refreshBeforePayment`, la red de 5 y 30 minutos, el latido, la revisión de borrados: sin cambios.
- **Versiones mezcladas:** una PC con la 6.3.3 sigue tirando los avisos del socket, igual que hoy. No empeora nada. Igual, las PCs se instalan el mismo día.

## 7. Pruebas

En este orden: **primero en rojo con el código de la 6.3.3**, después el arreglo, después en verde.

1. **El pulso por el socket** (`sync_en_reposo_test.dart`): `recibirPulso({'origen': 'pc-del-jefe', 'tablas': ['pagos_contrato_alumno', 'contratos_alumnos'], 'borrados': {}, 'type': 'broadcast', 'event': 'cambios'})` baja exactamente esas dos tablas a los 400 ms. **Con la 6.3.3 tiene que fallar.**
2. **Un borrado por el socket** (`borrados_de_otra_pc_test.dart`): saca el pago local por el camino `aviso`, con su cascada y la cuenta rehecha.
3. **Un latido por el socket** (`'latido': true`): baja `sesiones_caja` sin refrescar las pantallas.
4. **El eco propio por el socket** (`origen == InstalacionId.valor`): no hace nada.
5. **La forma del REST**: los tests que ya hay, sin tocarlos, siguen en verde.
6. **`cuerpoDelBroadcast`**:
   - las dos formas dan el mismo cuerpo;
   - un `payload` que no es `Map` da `null`;
   - un mensaje vacío da un cuerpo vacío;
   - del socket, `type` y `event` no quedan en el cuerpo.
7. **El tótem**: `checkin` y `guest_removed` por el socket se atienden. Si `totem_display` no se puede montar, alcanza con la prueba de la función más un test que lea `totem_display.dart` y falle si vuelve a aparecer `payload['payload']`, como los que ya leen pantallas.
8. **La regla**: el mapa que arma `_emitirPulso` (`ultimoPulsoArmado`) y `Invitado.sinDatosPrivados(...)` no tienen una clave `payload`.
9. **La prueba que faltó, contra Supabase de verdad**: `tool/pulso_prueba.dart`. **Antes de publicar es obligatoria** y se corre en la PC, porque la sesión remota no tiene Flutter.
   - Dos `SupabaseClient` contra el proyecto real, en un canal **de prueba**: `sync_pulse_prueba`, **nunca `sync_pulse`**, para que las PCs no reaccionen.
   - El receptor se suscribe. Desde un emisor suscripto (socket) y desde uno sin suscribir (REST) se manda el mismo aviso.
   - Imprime la forma cruda de cada uno y comprueba que `trabajoDelPulso(cuerpoDelBroadcast(m), …)` dé lo mismo en los dos casos.
   - No lee ni escribe ninguna tabla.

## 8. Publicación

1. Parche **6.3.4** desde `release/6.3.x`, solo con este arreglo y sus pruebas. Llevar el commit también a la rama de desarrollo.
2. `flutter analyze` y `flutter test` en la PC, y después `tool/pulso_prueba.dart` con su salida a la vista.
3. Las PCs se instalan el mismo día. La rutina de la foto de la mora sigue como siempre, aunque este cambio no toca la mora.

**Commits** (el efecto para el usuario):

- "lo que se cobra o se cambia en una PC aparece en la otra en un segundo, sin tener que tocarla: el aviso entre PCs se tiraba cuando llegaba por el socket, que es por donde llega casi siempre"
- "el tótem de la web saluda al instante también cuando Recepción tiene la lista abierta"

## 9. Cómo se comprueba en las PCs (con los logs de Supabase)

1. Con la PC del jefe al frente y **sin tocarla**, cobrar en la de Maxi.
   - **Tiene que verse:** en menos de un segundo, la del jefe hace `GET pagos_contrato_alumno` y `GET contratos_alumnos` (y `sesiones_caja` si cambió), solo esas tablas.
   - **No deben aparecer** las 14 tablas del cobro, que son de `bajarAlMirar`.
   - En la pantalla del jefe el cobro aparece solo.
2. Cada latido de una PC: `GET sesiones_caja` en la otra, en alrededor de un segundo.
3. Lo mismo al revés: cobrar en la del jefe y mirar la de Maxi.

## 10. Fuera de alcance (anotado, no va en este parche)

- **La revisión de borrados cada 10 minutos es lo más pesado que queda**: unos 45 pedidos por PC, con los ids de todos los pagos bajados en 5 páginas de 1.000. Por eso el reposo queda en ~8 pedidos por minuto por PC y no en ~5. Lo resuelve la etapa 6 de `SPEC_sync_en_reposo_2026-11-06.md`.
- **La librería avisa que la caída automática al REST va a quedar obsoleta** (`send() is automatically falling back to REST API…`). Si una versión futura la saca, un aviso mandado con el canal sin unir fallaría y lo cubriría la red de seguridad. Mirarlo al actualizar `supabase_flutter`.
