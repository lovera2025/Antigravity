import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/invitado.dart';
import 'bienvenidas_totem.dart';

/// La cola de bienvenidas del tótem, en el tiempo: a quién se está saludando,
/// cuándo se va su tarjeta y cuándo sigue el próximo.
///
/// A quién se saluda, con quién y cuánto dura lo decide [IngresosTotem] (la
/// familia junta, 7 s sin cola y 3 s con cola). Esto pone los temporizadores y
/// avisa a la pantalla. Lo comparten el tótem del salón (`totem_display.dart`)
/// y el de esta PC en Recepción (`TotemLocal`), así no hay dos copias.
class ReproductorBienvenidas extends ChangeNotifier {
  ReproductorBienvenidas({
    DateTime Function()? ahora,
    this.salida = const Duration(milliseconds: 700),
    this.pausa = const Duration(milliseconds: 300),
  }) : _ahora = ahora ?? DateTime.now;

  final DateTime Function() _ahora;

  /// Lo que tarda en irse una tarjeta (la animación de salida de la escena).
  final Duration salida;

  /// Lo que se espera entre una tarjeta y la siguiente.
  final Duration pausa;

  /// La lista, la cola y la tarjeta en pantalla.
  final IngresosTotem sala = IngresosTotem();

  /// Antes de saludar a la cola, si hace falta prepararla (el tótem del salón
  /// vuelve a pedir la ficha si llegó alguien que no conoce). Se la espera
  /// como mucho un segundo.
  Future<void> Function(List<Invitado> cola)? prepararCola;

  BienvenidaTotem? _actual;
  bool _saliendo = false;
  Timer? _timer;
  bool _cerrado = false;

  /// La tarjeta que se dibuja: la que está en pantalla y, mientras se va, la
  /// que se está yendo ([saliendo]).
  BienvenidaTotem? get actual => _actual;
  bool get saliendo => _saliendo;

  /// Cuándo se va la tarjeta en pantalla. Null si no hay o se está yendo.
  DateTime? get fin => _saliendo ? null : sala.fin;

  /// "N más en camino".
  int get enCamino => sala.enCamino;

  /// Los que ya llegaron, los más recientes primero.
  List<Invitado> get ingresados => sala.ingresados;

  bool get conectado => sala.conectado;

  set familiaDe(String Function(Invitado) f) => sala.familiaDe = f;

  int get _cuantos =>
      sala.cola.length + (sala.enPantalla?.personas.length ?? 0);

  /// Llegó una lectura completa de la lista de la puerta.
  void leyo(List<Invitado> lectura) {
    final antes = _cuantos;
    final estaba = sala.conectado;
    sala.leyo(lectura, ahora: _ahora());
    if (_cuantos != antes || estaba != sala.conectado) _avisar();
    if (_cuantos != antes) _despuesDeLlegar();
  }

  /// Llegó un aviso de ingreso. Devuelve si era nuevo.
  bool aviso(Invitado invitado, {bool porElPuente = false}) {
    final nuevo =
        sala.aviso(invitado, porElPuente: porElPuente, ahora: _ahora());
    if (nuevo) {
      _avisar();
      _despuesDeLlegar();
    }
    return nuevo;
  }

  /// No se pudo leer la nube.
  void noPudoLeer() {
    final estaba = sala.conectado;
    sala.noPudoLeer(_ahora());
    if (estaba != sala.conectado) _avisar();
  }

  /// Se borró a alguien o se deshizo su ingreso.
  void baja(String id) {
    final habia = sala.enPantalla;
    sala.baja(id);
    if (habia != null && sala.enPantalla == null && !_saliendo) {
      // Era el único de la tarjeta: se va enseguida, sin animación.
      _timer?.cancel();
      _actual = null;
      _avisar();
      _mostrarSiguiente();
      return;
    }
    _avisar();
    _programarFin();
  }

  /// Se vació la lista o se deshicieron todos los ingresos.
  void vaciar() {
    _timer?.cancel();
    sala.vaciar();
    _actual = null;
    _saliendo = false;
    _avisar();
  }

  /// Como recién abierto: otro evento, o la ventana que vuelve de estar
  /// escondida. La próxima lectura va en silencio.
  void reiniciar() {
    _timer?.cancel();
    sala.reiniciar();
    _actual = null;
    _saliendo = false;
    _avisar();
  }

  /// La ventana se esconde: nadie queda esperando su bienvenida.
  void pausar() {
    _timer?.cancel();
    sala.pausar();
    _actual = null;
    _saliendo = false;
    _avisar();
  }

  Future<void> _despuesDeLlegar() async {
    final preparar = prepararCola;
    if (_actual == null && preparar != null && sala.cola.isNotEmpty) {
      await preparar(List.of(sala.cola))
          .timeout(const Duration(seconds: 1), onTimeout: () {});
      if (_cerrado) return;
    }
    if (_actual == null) {
      _mostrarSiguiente();
    } else {
      _programarFin();
    }
  }

  void _mostrarSiguiente() {
    if (_cerrado || _actual != null) return;
    final b = sala.siguiente(_ahora());
    if (b == null) return;
    _actual = b;
    _saliendo = false;
    _avisar();
    _programarFin();
  }

  /// Vuelve a poner la hora en que se va la tarjeta: con gente esperando se
  /// acorta, y si ya pasaron los 3 s se va enseguida.
  void _programarFin() {
    // Mientras se va, el temporizador es el de la salida: no se toca, o la
    // tarjeta quedaría trabada a medio irse.
    if (_saliendo) return;
    _timer?.cancel();
    final f = fin;
    if (_cerrado || _actual == null || f == null) return;
    final falta = f.difference(_ahora());
    _timer = Timer(falta.isNegative ? Duration.zero : falta, _terminar);
  }

  void _terminar() {
    if (_cerrado || _actual == null || _saliendo) return;
    // Para la cola, la tarjeta ya terminó: el que llega mientras se va espera
    // la suya.
    sala.termino();
    _saliendo = true;
    _avisar();
    _timer = Timer(salida, () {
      if (_cerrado) return;
      _actual = null;
      _saliendo = false;
      _avisar();
      if (sala.cola.isNotEmpty) _timer = Timer(pausa, _mostrarSiguiente);
    });
  }

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _timer?.cancel();
    super.dispose();
  }
}
