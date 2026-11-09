import 'dart:js_interop';

@JS('navigator')
external _Navegador get _navegador;

extension type _Navegador(JSObject _) implements JSObject {
  external JSFunction? get vibrate;
  @JS('vibrate')
  external bool vibrar(JSArray<JSNumber> patron);
}

/// En el celular: dos vibraciones cortas, si el navegador las tiene (Android sí,
/// iPhone no).
Future<void> avisarMensajeNuevo() async {
  try {
    if (_navegador.vibrate == null) return;
    _navegador.vibrar([180.toJS, 90.toJS, 180.toJS].toJS);
  } catch (_) {}
}
