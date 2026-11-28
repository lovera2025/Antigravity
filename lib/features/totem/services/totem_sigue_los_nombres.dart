import 'dart:async';

/// **El tótem saluda con lo nombrado, al instante** (el locutor, 28-nov-2026;
/// `docs/SPEC_locutor_2026-11-18.md`, etapa 5). Escucha lo que se guarda de "Cómo lo
/// nombran" en esta PC (y lo que baja de otra) y le avisa a la ventana del tótem que
/// vuelva a pedir la ficha (`ficha_cambio`). Se pide, no se empuja: la ventana que recién
/// nace no se pierde nada, y si el aviso se pierde, la ficha de cada minuto es la red.
///
/// Junta los avisos de [espera] por evento: varios guardados seguidos dan uno solo.
class TotemSigueLosNombres {
  TotemSigueLosNombres({
    required this.cambios,
    required this.avisar,
    this.espera = const Duration(milliseconds: 300),
  });

  /// El evento de cada cambio.
  final Stream<String> cambios;
  final Future<void> Function(String eventoId) avisar;
  final Duration espera;

  StreamSubscription<String>? _escucha;
  final _pendientes = <String, Timer>{};

  void arrancar() {
    _escucha ??= cambios.listen((eventoId) {
      _pendientes[eventoId]?.cancel();
      _pendientes[eventoId] = Timer(espera, () {
        _pendientes.remove(eventoId);
        unawaited(avisar(eventoId).catchError((Object _) {}));
      });
    });
  }

  Future<void> parar() async {
    for (final t in _pendientes.values) {
      t.cancel();
    }
    _pendientes.clear();
    await _escucha?.cancel();
    _escucha = null;
  }
}
