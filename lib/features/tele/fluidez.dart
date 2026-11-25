import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// **Cuántas imágenes por segundo dibuja la tele** (24-nov-2026): para saber,
/// en la tele de verdad, si el tótem anda suave o si conviene el fondo quieto.
///
/// Mira el tiempo de cada imagen que dibujó (`addTimingsCallback`) y se queda
/// con lo de los últimos segundos. Cerca de 60 anda suave; debajo de 40 se nota.
/// No cuesta nada: Flutter ya mide esto, solo se lo escucha.
class Fluidez extends ChangeNotifier {
  Fluidez({this.ventana = const Duration(seconds: 3)});

  /// Cuánto se mira para atrás.
  final Duration ventana;

  final _tiempos = <Duration>[];
  var _escuchando = false;

  /// Imágenes por segundo de lo último, o null si todavía no dibujó nada.
  double? _porSegundo;
  double? get porSegundo => _porSegundo;

  void arrancar() {
    if (_escuchando) return;
    _escuchando = true;
    SchedulerBinding.instance.addTimingsCallback(_alDibujar);
  }

  void parar() {
    if (!_escuchando) return;
    _escuchando = false;
    SchedulerBinding.instance.removeTimingsCallback(_alDibujar);
  }

  void _alDibujar(List<FrameTiming> tandas) {
    for (final t in tandas) {
      _tiempos.add(t.totalSpan);
    }
    // Una imagen cada 16,7 ms es 60 por segundo: cuántas entran en la ventana.
    final cuantas = (ventana.inMilliseconds / 16.7).round();
    if (_tiempos.length > cuantas) {
      _tiempos.removeRange(0, _tiempos.length - cuantas);
    }
    _porSegundo = porSegundoDe(_tiempos);
    notifyListeners();
  }

  /// Lo que tarda en promedio cada imagen, pasado a imágenes por segundo, con
  /// el tope de la pantalla (60).
  @visibleForTesting
  static double? porSegundoDe(List<Duration> tiempos) {
    if (tiempos.isEmpty) return null;
    final total = tiempos.fold<int>(0, (s, t) => s + t.inMicroseconds);
    final promedio = total / tiempos.length;
    if (promedio <= 0) return 60;
    final fps = 1e6 / promedio;
    return fps > 60 ? 60 : fps;
  }

  /// "57 por segundo · anda suave".
  static String texto(double? fps) {
    if (fps == null) return 'Midiendo…';
    final n = fps.round();
    if (n >= 50) return '$n por segundo · anda suave';
    if (n >= 35) return '$n por segundo · se puede notar';
    return '$n por segundo · va a los saltos: probá el fondo quieto';
  }

  @override
  void dispose() {
    parar();
    super.dispose();
  }
}
