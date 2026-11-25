import 'dart:ui' show FrameTiming, FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Una imagen dibujada: cuándo empezó y cuánto tardó cada parte, en
/// microsegundos. Lo que da `FrameTiming`, en algo que una prueba puede armar.
typedef ImagenDibujada = ({int empezo, int armado, int dibujo});

/// Cómo anduvo lo último: imágenes por segundo de verdad y lo que tardó, en
/// promedio, cada parte de una imagen.
class MedidaDeFluidez {
  const MedidaDeFluidez({
    required this.porSegundo,
    required this.msArmado,
    required this.msDibujo,
    required this.imagenes,
  });

  /// Las que de verdad salieron por segundo (contadas por cuándo empezó cada
  /// una), con el tope de la pantalla.
  final double porSegundo;

  /// Lo que tarda el procesador en armar una imagen.
  final double msArmado;

  /// Lo que tarda la placa de video en dibujarla.
  final double msDibujo;

  /// Cuántas imágenes se midieron.
  final int imagenes;

  /// La medida de [lista], o null si son muy pocas para decir algo. [tope]:
  /// las imágenes por segundo de la pantalla.
  static MedidaDeFluidez? de(List<ImagenDibujada> lista, {double tope = 60}) {
    if (lista.length < 2) return null;
    final ordenadas = [...lista]..sort((a, b) => a.empezo.compareTo(b.empezo));
    final lapso = ordenadas.last.empezo - ordenadas.first.empezo;
    if (lapso <= 0) return null;
    final fps = (ordenadas.length - 1) * 1e6 / lapso;
    final armado = lista.fold<int>(0, (s, i) => s + i.armado) / lista.length;
    final dibujo = lista.fold<int>(0, (s, i) => s + i.dibujo) / lista.length;
    return MedidaDeFluidez(
      porSegundo: fps > tope ? tope : fps,
      msArmado: armado / 1000,
      msDibujo: dibujo / 1000,
      imagenes: lista.length,
    );
  }
}

/// **Cuántas imágenes por segundo dibuja la tele** (24-nov-2026; 25-nov, con
/// lo que tarda cada parte): para que la tele se ajuste sola
/// (`CalidadDeLaTele`) y, en la app de prueba, para la foto de "Cómo anda".
///
/// Escucha lo que Flutter ya mide de cada imagen (`addTimingsCallback`) y se
/// queda con lo de los últimos segundos. No cuesta nada.
class Fluidez extends ChangeNotifier {
  Fluidez({this.ventana = const Duration(seconds: 4), this.tope = 60});

  /// Cuánto se mira para atrás.
  final Duration ventana;

  /// Las imágenes por segundo de la pantalla.
  double tope;

  final _imagenes = <ImagenDibujada>[];
  var _escuchando = false;

  MedidaDeFluidez? _medida;
  MedidaDeFluidez? get medida => _medida;

  /// Imágenes por segundo de lo último, o null si todavía no hay medida.
  double? get porSegundo => _medida?.porSegundo;

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

  /// Olvida lo medido (después de cambiar algo, para medir lo nuevo).
  void olvidar() {
    _imagenes.clear();
    _medida = null;
    notifyListeners();
  }

  void _alDibujar(List<FrameTiming> tandas) {
    for (final t in tandas) {
      anotar((
        empezo: t.timestampInMicroseconds(FramePhase.vsyncStart),
        armado: t.buildDuration.inMicroseconds,
        dibujo: t.rasterDuration.inMicroseconds,
      ));
    }
  }

  /// Anota una imagen (lo usa `_alDibujar`; las pruebas, directo).
  @visibleForTesting
  void anotar(ImagenDibujada i) {
    _imagenes.add(i);
    final desde = i.empezo - ventana.inMicroseconds;
    _imagenes.removeWhere((x) => x.empezo < desde);
    _medida = MedidaDeFluidez.de(_imagenes, tope: tope);
    notifyListeners();
  }

  /// "57 por segundo · anda suave".
  static String texto(double? fps) {
    if (fps == null) return 'Midiendo…';
    final n = fps.round();
    if (n >= 50) return '$n por segundo · anda suave';
    if (n >= 35) return '$n por segundo · se puede notar';
    return '$n por segundo · va a los saltos';
  }

  /// Lo de "Cómo anda" con todo (solo la app de prueba): "57 por segundo ·
  /// anda suave · dibujo 9 ms · armado 3 ms".
  static String detalle(MedidaDeFluidez? m) {
    if (m == null) return 'Midiendo…';
    return '${texto(m.porSegundo)} · dibujo ${m.msDibujo.toStringAsFixed(1)} ms'
        ' · armado ${m.msArmado.toStringAsFixed(1)} ms';
  }

  @override
  void dispose() {
    parar();
    super.dispose();
  }
}
