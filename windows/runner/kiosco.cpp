#include "kiosco.h"

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

namespace {

// Lo que hace falta para volver de la pantalla completa a la ventana de antes.
struct EstadoKiosco {
  HWND vista = nullptr;  // La vista de Flutter; su raíz es la ventana.
  bool activo = false;
  LONG_PTR estilo = 0;
  WINDOWPLACEMENT lugar{sizeof(WINDOWPLACEMENT)};
};

HWND Raiz(const EstadoKiosco& e) {
  if (e.vista == nullptr || !IsWindow(e.vista)) return nullptr;
  return GetAncestor(e.vista, GA_ROOT);
}

// Ocupa el monitor donde está la ventana, sin bordes ni barra de título. Como
// cubre el monitor entero, Windows esconde la barra de tareas mientras está
// adelante.
bool Entrar(EstadoKiosco& e) {
  if (e.activo) return true;
  HWND ventana = Raiz(e);
  if (ventana == nullptr) return false;

  MONITORINFO monitor{sizeof(MONITORINFO)};
  WINDOWPLACEMENT lugar{sizeof(WINDOWPLACEMENT)};
  if (!GetWindowPlacement(ventana, &lugar) ||
      !GetMonitorInfo(MonitorFromWindow(ventana, MONITOR_DEFAULTTONEAREST),
                      &monitor)) {
    return false;
  }
  e.lugar = lugar;
  e.estilo = GetWindowLongPtr(ventana, GWL_STYLE);
  SetWindowLongPtr(ventana, GWL_STYLE, e.estilo & ~WS_OVERLAPPEDWINDOW);
  const RECT& r = monitor.rcMonitor;
  SetWindowPos(ventana, HWND_TOP, r.left, r.top, r.right - r.left,
               r.bottom - r.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  e.activo = true;
  return true;
}

// Vuelve al estilo y al lugar de antes. Si la ventana ya está escondida, la
// deja escondida: volver no puede mostrarla.
bool Salir(EstadoKiosco& e) {
  if (!e.activo) return true;
  e.activo = false;
  HWND ventana = Raiz(e);
  if (ventana == nullptr) return false;

  const bool visible = IsWindowVisible(ventana) != FALSE;
  SetWindowLongPtr(ventana, GWL_STYLE, e.estilo);
  WINDOWPLACEMENT lugar = e.lugar;
  if (!visible) lugar.showCmd = SW_HIDE;
  SetWindowPlacement(ventana, &lugar);
  SetWindowPos(ventana, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                   SWP_FRAMECHANGED | (visible ? 0 : SWP_NOACTIVATE));
  return true;
}

// Se llama al crear cada ventana secundaria, antes de que corra su Dart.
//
// El canal y el estado no se destruyen nunca, a propósito: el destructor de un
// canal le habla al motor de su ventana, y al cerrar el programa ese motor ya
// no existe. Es una ventana por noche, unos pocos bytes.
void AlCrearVentana(void* controlador_crudo) {
  auto* controlador =
      static_cast<flutter::FlutterViewController*>(controlador_crudo);
  if (controlador == nullptr || controlador->engine() == nullptr ||
      controlador->view() == nullptr) {
    return;
  }
  auto* estado = new EstadoKiosco();
  estado->vista = controlador->view()->GetNativeWindow();

  auto* canal = new flutter::MethodChannel<flutter::EncodableValue>(
      controlador->engine()->messenger(), "junior_eventos/kiosco",
      &flutter::StandardMethodCodec::GetInstance());
  canal->SetMethodCallHandler(
      [estado](const flutter::MethodCall<flutter::EncodableValue>& llamada,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   resultado) {
        const std::string& metodo = llamada.method_name();
        if (metodo == "entrar") {
          resultado->Success(flutter::EncodableValue(Entrar(*estado)));
        } else if (metodo == "salir") {
          resultado->Success(flutter::EncodableValue(Salir(*estado)));
        } else if (metodo == "estado") {
          resultado->Success(flutter::EncodableValue(estado->activo));
        } else {
          resultado->NotImplemented();
        }
      });
}

}  // namespace

void RegistrarKioscoEnVentanasSecundarias() {
  DesktopMultiWindowSetWindowCreatedCallback(AlCrearVentana);
}
