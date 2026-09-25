# Que el tótem no se desconecte ni salude tarde

**Estado:** pendiente
**Postergado el:** 2026-09-24

## Por qué se postergó

El usuario priorizó el sorteo de noviembre. Esto es para las fiestas de diciembre, aunque los particulares también
lo aprovechan. Es chico y conviene hacerlo **antes** que las apariencias ([totem-apariencias.md](totem-apariencias.md)),
porque toca las mismas pantallas.

## Qué está bien

En la misma PC, `InvitadosRepository.marcarIngreso` (`invitados_repository.dart:319`) le avisa al tótem por el
puente entre ventanas (`KioskLauncher.notifyGuestCheckin`), que no necesita internet: la bienvenida sale al instante.

Para tótems en otra PC o en la web hay además:
- broadcast en `totem_<eventoId>`;
- una relectura cada 60 s (`_reconciliar`).

Nadie se saluda dos veces, gracias a `_processedIds`.

## Qué falla

1. **Un aviso que falla una sola vez desconecta el tótem por el resto de la noche.**
   - `KioskLauncher._invocar` (`kiosk_launcher.dart:99`) borra `_totemWindowId` ante cualquier error. Para
     `guest_checkin` no hay reintentos.
   - Desde ahí `isTotemActive` da `false`: Recepción deja de avisar por el puente y esconde los controles.
   - Si alguien reabre el tótem, `launch` **crea una segunda ventana**, y la primera sigue viva escuchando la nube.
2. **Después de un corte de internet, repite bienvenidas atrasadas.**
   - `_onError` → `_reconnectWithBackoff` → `_connect()` → `_reconciliar()` → `_onData`, con `_initialized` en `true`.
   - Encola a todos los que entraron por la otra PC durante el corte, 7 s cada uno: minutos de saludos viejos.
   - `_reanudar` ya hace lo correcto (primera lectura en silencio), pero la reconexión no.
3. **Sin internet, el tótem le muestra "Reconectando..." en rojo al público** (`_buildConnectionIndicator`). Mientras
   tanto sigue andando por el puente.
4. **Al abrir, muestra el cartel "ESTABLECIENDO CONEXIÓN — JUNIOR EVENTOS • ELITE SYSTEM"**
   (`_buildHandshakeOverlay`). Miente sin internet y dice otra marca.

Además, los botones de Recepción "maximizar" y "minimizar" no hacen nada: la ventana del tótem no atiende esos
mensajes en su `setMethodHandler`. Van a salir con el rediseño de Recepción
([recepcion-redisenio.md](recepcion-redisenio.md)).

## Qué habría que hacer

1. **En `KioskLauncher._invocar`:**
   - antes de olvidar la ventana, confirmar con `DesktopMultiWindow.getAllSubWindowIds()` que ya no existe;
   - reintentar una vez el `guest_checkin`;
   - en `_launchInterno`, si no hay id pero sigue abierta una ventana secundaria, adoptarla. Es el único tipo de
     ventana secundaria de la app.
2. **En `totem_display.dart`:** al reconectar después de un error, poner `_initialized = false` para que la primera
   lectura vaya en silencio.
   - La decisión de qué ingresos llevan bienvenida conviene sacarla a una función pura, con test: la primera carga y la
     reconexión van en silencio, y los ingresos nuevos llevan bienvenida.
3. **El estado de conexión** pasa a la barra del operador, la que aparece al mover el mouse: "Sin internet: esta PC
   sigue avisando al tótem".
4. **El cartel de apertura** se cambia por un fundido de entrada.

**Queda para el modo local simple:** lo que se marca en otra PC llega al tótem solo con internet.
