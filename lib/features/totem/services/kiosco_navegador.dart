// La pantalla completa del navegador, para el tótem por la web (`?totem`, la
// tele con navegador). En el escritorio no hay navegador: ahí es
// `KioscoVentana`.
export 'kiosco_navegador_io.dart'
    if (dart.library.js_interop) 'kiosco_navegador_web.dart';
