import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'kiosco.dart';

@JS('document')
external _Documento get _documento;

extension type _Documento(JSObject _) implements JSObject {
  external JSObject? get fullscreenElement;
  external _Elemento get documentElement;
  external JSPromise<JSAny?> exitFullscreen();
}

extension type _Elemento(JSObject _) implements JSObject {
  external JSPromise<JSAny?> requestFullscreen();
}

/// La pantalla completa del navegador, para el tótem por la web (`?totem`).
///
/// Los navegadores la dan solo desde un toque (`CapaKiosco.entrarAlTocar`), y
/// la sacan solos con Esc: por eso [activo] le pregunta al navegador.
class KioscoNavegador implements Kiosco {
  const KioscoNavegador();

  @override
  bool? get activo {
    try {
      return _documento.fullscreenElement != null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> entrar() async {
    try {
      if (_documento.fullscreenElement != null) return true;
      await _documento.documentElement.requestFullscreen().toDart;
      return true;
    } catch (e) {
      debugPrint('Kiosco: el navegador no dio pantalla completa: $e');
      return false;
    }
  }

  @override
  Future<bool> salir() async {
    try {
      if (_documento.fullscreenElement == null) return true;
      await _documento.exitFullscreen().toDart;
      return true;
    } catch (e) {
      debugPrint('Kiosco: el navegador no dejó la pantalla completa: $e');
      return false;
    }
  }
}
