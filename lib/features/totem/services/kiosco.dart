import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// El modo kiosco del tótem (sección 6 de la 6.0.0): pantalla completa en la
// tele del salón, sin bordes ni barra de título. Se sale con Esc, con doble
// clic o con el botón de la barra.
//
// Acá está lo que decide, sin pantalla: cómo se le pide a la ventana
// ([Kiosco]), si está en kiosco y qué se avisa ([ControladorKiosco]), y qué es
// un doble clic ([DobleClic]). Lo dibuja `CapaKiosco`.

/// Pone la ventana en pantalla completa y la saca. Los tests lo reemplazan.
abstract class Kiosco {
  /// Si quedó en pantalla completa.
  Future<bool> entrar();

  /// Si volvió a ser una ventana.
  Future<bool> salir();

  /// Si está en pantalla completa ahora, cuando se puede saber sin pedirlo.
  /// En el navegador se puede salir por fuera (Esc la saca el navegador):
  /// con esto el tótem se entera. Null: no se sabe (la ventana del escritorio,
  /// que solo sale por el tótem).
  bool? get activo => null;
}

/// La ventana del tótem en el escritorio: el canal que le da el runner de
/// Windows a cada ventana secundaria (`windows/runner/kiosco.cpp`).
class KioscoVentana implements Kiosco {
  const KioscoVentana();

  static const canal = MethodChannel('junior_eventos/kiosco');

  Future<bool> _pedir(String metodo) async {
    try {
      return await canal.invokeMethod<bool>(metodo) ?? false;
    } catch (e) {
      // Un ejecutable de antes de la 6.0.0 no tiene el canal.
      debugPrint('Kiosco: no se pudo "$metodo": $e');
      return false;
    }
  }

  @override
  Future<bool> entrar() => _pedir('entrar');

  @override
  Future<bool> salir() => _pedir('salir');

  @override
  bool? get activo => null;
}

/// Si el tótem está en kiosco, y lo que se le avisa al operador.
///
/// Los pedidos van de a uno: un "salir" que llega mientras entra (el tótem se
/// cierra justo) espera a que termine de entrar, y sale.
class ControladorKiosco extends ChangeNotifier {
  ControladorKiosco(this._kiosco, {this.alEntrar = avisoAlEntrar});

  final Kiosco _kiosco;

  static const avisoAlEntrar = 'Pantalla completa · para salir: Esc o doble clic';
  static const avisoAlEntrarEnElNavegador =
      'Pantalla completa · para salir: doble toque o Esc';
  static const avisoSiFalla = 'No se pudo poner en pantalla completa';

  /// Lo que se dice al entrar.
  final String alEntrar;

  /// Se entera si la pantalla completa cambió por fuera (en el navegador, Esc
  /// la saca sin pasar por el tótem). Devuelve si cambió algo.
  bool sincronizar() {
    final activo = _kiosco.activo;
    if (activo == null || activo == _enKiosco) return false;
    _enKiosco = activo;
    if (!activo) {
      _timerAviso?.cancel();
      _aviso = null;
    }
    if (!_cerrado) notifyListeners();
    return true;
  }

  /// Lo que dura el aviso al entrar.
  static const duraAviso = Duration(seconds: 3);

  /// Lo que dura el aviso si no se pudo: un poco más, para que se lea.
  static const duraAvisoSiFalla = Duration(seconds: 5);

  bool _enKiosco = false;
  bool get enKiosco => _enKiosco;

  String? _aviso;

  /// Lo que se dice abajo, en el medio. Null: nada.
  String? get aviso => _aviso;

  Timer? _timerAviso;
  Future<void> _cola = Future.value();
  bool _cerrado = false;

  Future<void> _enOrden(Future<void> Function() paso) =>
      _cola = _cola.then((_) => paso()).catchError((Object e) {
        debugPrint('Kiosco: $e');
      });

  Future<void> entrar() => _enOrden(() async {
        if (_enKiosco || _cerrado) return;
        final ok = await _kiosco.entrar();
        if (_cerrado) return;
        _enKiosco = ok;
        _avisar(ok ? alEntrar : avisoSiFalla,
            ok ? duraAviso : duraAvisoSiFalla);
      });

  /// Vuelve a ser una ventana. Si no estaba en kiosco, no hace nada.
  Future<void> salir() => _enOrden(() async {
        if (!_enKiosco) return;
        await _kiosco.salir();
        _enKiosco = false;
        _timerAviso?.cancel();
        _aviso = null;
        if (!_cerrado) notifyListeners();
      });

  Future<void> alternar() => _enKiosco ? salir() : entrar();

  void _avisar(String texto, Duration dura) {
    _timerAviso?.cancel();
    _aviso = texto;
    notifyListeners();
    _timerAviso = Timer(dura, () {
      if (_cerrado) return;
      _aviso = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _cerrado = true;
    _timerAviso?.cancel();
    super.dispose();
  }
}

/// Dos toques seguidos, cerca uno del otro: un doble clic.
///
/// Se cuenta a mano, con cada toque que llega, en lugar de un detector de
/// doble toque: ese hace esperar a los botones de la barra hasta saber si
/// viene el segundo.
class DobleClic {
  DobleClic({
    this.espera = const Duration(milliseconds: 300),
    this.distancia = 40,
  });

  /// Cuánto puede pasar entre los dos toques.
  final Duration espera;

  /// Cuánto se puede haber movido, en píxeles lógicos.
  final double distancia;

  DateTime? _cuando;
  Offset? _donde;

  /// Llega un toque. Devuelve si con el anterior hacen un doble clic; si es
  /// así, se empieza de cero (un tercero no hace otro).
  bool toque(Offset donde, DateTime cuando) {
    final antes = _cuando, dondeAntes = _donde;
    if (antes != null &&
        dondeAntes != null &&
        !cuando.isBefore(antes) &&
        cuando.difference(antes) <= espera &&
        (donde - dondeAntes).distance <= distancia) {
      _cuando = null;
      _donde = null;
      return true;
    }
    _cuando = cuando;
    _donde = donde;
    return false;
  }
}
