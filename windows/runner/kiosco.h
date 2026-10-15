#ifndef RUNNER_KIOSCO_H_
#define RUNNER_KIOSCO_H_

// El modo kiosco de la ventana del tótem (sección 6 de la 6.0.0): pantalla
// completa en el monitor donde está la ventana, sin bordes ni barra de título.
//
// La ventana del tótem es secundaria (desktop_multi_window) y no tiene
// window_manager: a cada ventana secundaria se le da el canal
// "junior_eventos/kiosco", con "entrar", "salir" y "estado". La ventana
// principal no se toca.
void RegistrarKioscoEnVentanasSecundarias();

#endif  // RUNNER_KIOSCO_H_
