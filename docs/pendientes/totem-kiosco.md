# Modo kiosco en la ventana del tótem

**Estado:** pendiente
**Postergado el:** 2026-09-24

## Por qué se postergó

El usuario priorizó el sorteo de noviembre. El kiosco es para las fiestas de diciembre, y para los particulares.

## Qué se pidió

Poder poner el tótem en **modo kiosco** y sacarlo con **Esc** o con **doble clic**.

Comportamiento acordado:

- **Qué hace:** pantalla completa sin bordes ni barra de título, en el monitor donde está la ventana. Se arrastra la
  ventana a la pantalla del salón y se toca "Kiosco" en la barra del operador.
- **Cómo se sale:** con Esc, con doble clic en cualquier lugar o con el botón de la barra.
- **El puntero** se esconde a los 3 s sin moverse.
- **Al esconder el tótem** (`KioskLauncher.close`), sale del kiosco antes.
- **En la web** (`?totem`, en una tablet o TV): pantalla completa del navegador al primer toque, porque los
  navegadores lo exigen así. Se sale con doble toque o Esc.

## Por qué hoy no se puede

La ventana del tótem es secundaria (`desktop_multi_window`) y **no tiene `window_manager`**:
- el runner de Windows no registra plugins para ventanas secundarias. Ver el comentario en `main.dart:56` y
  `windows/runner/flutter_window.cpp`, que solo llama a `RegisterPlugins` para la principal;
- `WindowController` de `desktop_multi_window` 0.2 tiene `setFrame`, `show`, `hide` y `center`, pero no tiene
  pantalla completa ni forma de sacar la barra de título.

## Qué habría que hacer

1. **En `windows/runner/flutter_window.cpp`** (`OnCreate`), registrar un callback con
   `DesktopMultiWindowSetWindowCreatedCallback`.
   - Recibe el `FlutterViewController*` de cada ventana secundaria.
   - Sobre `controller->engine()->messenger()` crea un `flutter::MethodChannel` `junior_eventos/kiosco`, con:
     - **`entrar`:** busca la ventana raíz con `GetAncestor(controller->view()->GetNativeWindow(), GA_ROOT)`, guarda
       `GWL_STYLE`, `GWL_EXSTYLE` y `GetWindowRect`, pasa a `WS_POPUP | WS_VISIBLE`, y ocupa el monitor con
       `MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)`, `GetMonitorInfo` y `SetWindowPos(..., SWP_FRAMECHANGED)`;
     - **`salir`:** restaura estilo y tamaño;
     - **`estado`:** devuelve si está en kiosco.
   - Los canales se guardan vivos mientras exista la ventana.
2. **En `totem_display.dart`:**
   - botón "Kiosco" en la barra del operador;
   - `Shortcuts`/`Focus` con autofocus para Esc;
   - `onDoubleTap` sobre toda la pantalla;
   - cursor oculto por inactividad.
3. **En web:** `requestFullscreen` sobre el documento, desde el primer toque.

## Cómo probarlo

Es código nativo: se prueba con `flutter run -d windows` en esta PC.
- Entrar y salir por las tres vías.
- Pasar la ventana a otro monitor y entrar ahí.
- Cerrar el tótem estando en kiosco.
- Volver a abrirlo.
