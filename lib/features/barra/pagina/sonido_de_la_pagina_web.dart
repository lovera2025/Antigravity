import 'dart:js_interop';

/// Un pitido corto con el sonido del navegador (Web Audio), sin archivos: la página
/// anda sin internet. Dos tonos, como el aviso de la PC.
@JS('AudioContext')
extension type _Audio._(JSObject _) implements JSObject {
  external _Audio();
  external JSPromise<JSAny?> resume();
  external _Oscilador createOscillator();
  external _Volumen createGain();
  external JSObject get destination;
  external double get currentTime;
}

extension type _Oscilador._(JSObject _) implements JSObject {
  external _Parametro get frequency;
  external void connect(JSObject destino);
  external void start(double cuando);
  external void stop(double cuando);
}

extension type _Volumen._(JSObject _) implements JSObject {
  external _Parametro get gain;
  external void connect(JSObject destino);
}

extension type _Parametro._(JSObject _) implements JSObject {
  external set value(double v);
}

_Audio? _audio;

void desbloquear() {
  try {
    final a = _audio ??= _Audio();
    a.resume();
  } catch (_) {}
}

void sonar() {
  try {
    final a = _audio ??= _Audio();
    a.resume();
    var t = a.currentTime;
    for (final f in [880.0, 1320.0]) {
      final o = a.createOscillator();
      final v = a.createGain();
      o.frequency.value = f;
      v.gain.value = 0.25;
      o.connect(v);
      v.connect(a.destination);
      o.start(t);
      o.stop(t + 0.18);
      t += 0.22;
    }
  } catch (_) {}
}
