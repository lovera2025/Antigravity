# Que el tótem no se desconecte ni salude tarde

**Estado:** hecho el 2026-10-13 (`0404bad`), en la 6.0.0. Sin publicar.
**Postergado el:** 2026-09-24

## Qué salió distinto de lo previsto

- **Había una tercera forma de saludar tarde, que este archivo no tenía.** Sin internet, lo que se marca en esa PC
  llega al tótem por el puente y se saluda bien; pero a la nube sube después. Al volver internet el tótem leía
  primero, sacaba a esos de la lista y, cuando subían, los saludaba de nuevo. Ahora lo que avisó el puente queda
  protegido hasta que la nube lo confirme.
- **Poner `_initialized = false` al reconectar no alcanzaba:** la lista se rearmaba entera, en otro orden, y un
  corte de dos segundos se comía el saludo del que justo entraba. Quedó así: el silencio es solo para un corte de
  **más de un minuto**, y los que entraron mientras tanto se suman arriba sin mover a los demás.
- **El corte también es una relectura que falla**, no solo un error del stream: cubre la conexión muda.
- **La decisión salió de la pantalla.** `IngresosTotem` (`totem/services/bienvenidas_totem.dart`) lleva la lista,
  la cola y el estado de la conexión, con sus tests; `totem_display.dart` solo le cuenta lo que pasó.
- **El tótem de más se esconde y se pausa, no se cierra:** es lo mismo que hace `KioskLauncher.close()`, que ya
  está probado en las PCs. Cerrar una ventana secundaria desde el programa no se pudo probar sin abrir la app.
- La espera entre reintentos volvía siempre a 2 segundos (se reiniciaba al intentar, no al leer). Ahora crece de 2
  a 32 y se queda ahí.
- **No se tocó el panel del tótem que está adentro de Recepción** (`totem_panel.dart`): lee de la base de la PC, y
  después de un corte largo puede saludar de corrido a los que bajan juntos. Va con el rediseño de Recepción.
  - **14-oct, sección 3c:** ese panel se borró. Recepción y la pantalla del asesor usan `TotemLocal`, con el mismo
    `IngresosTotem`.
  - **Lo de saludar de corrido sigue igual:** `TotemLocal` lee la base de la PC, que no se corta. Lo que baja de
    otra PC después de un corte llega todo junto y se saluda en cola, de a 3 s. Va con la sección 7 (dos puestos,
    [modo-local-sin-internet.md](modo-local-sin-internet.md)).
- **No se probó con el tótem de verdad:** no se abre la app desde el código mientras la v73 no esté publicada. Lo
  prueban 43 tests y, de verdad, el ensayo: marcar ingresos, cortar el wifi un par de minutos, seguir marcando,
  volver a conectar y mirar que no salude a nadie de nuevo.

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
