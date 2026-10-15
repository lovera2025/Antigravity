import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../estilos/fuentes_totem.dart';
import '../services/kiosco.dart';

/// Envuelve al tótem para el modo kiosco (sección 6 de la 6.0.0): en kiosco,
/// Esc o un doble clic en cualquier lugar lo sacan, el puntero se esconde a
/// los [puntero] sin moverse, y abajo se dice lo que pasó ("para salir: Esc o
/// doble clic", o que no se pudo).
///
/// Fuera del kiosco no hace nada: ni Esc ni el doble clic cambian algo.
class CapaKiosco extends StatefulWidget {
  final ControladorKiosco controlador;
  final Widget child;

  /// A los cuánto sin moverse se esconde el puntero.
  final Duration puntero;

  /// La hora, para el doble clic. Los tests ponen la suya.
  final DateTime Function() reloj;

  const CapaKiosco({
    super.key,
    required this.controlador,
    required this.child,
    this.puntero = const Duration(seconds: 3),
    this.reloj = DateTime.now,
  });

  @override
  State<CapaKiosco> createState() => _CapaKioscoState();
}

class _CapaKioscoState extends State<CapaKiosco> {
  final _doble = DobleClic();
  bool _quieto = false;
  Timer? _timerPuntero;

  ControladorKiosco get _c => widget.controlador;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tecla);
    _c.addListener(_cambio);
  }

  @override
  void didUpdateWidget(covariant CapaKiosco old) {
    super.didUpdateWidget(old);
    if (old.controlador != widget.controlador) {
      old.controlador.removeListener(_cambio);
      widget.controlador.addListener(_cambio);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tecla);
    _c.removeListener(_cambio);
    _timerPuntero?.cancel();
    super.dispose();
  }

  void _cambio() {
    if (!mounted) return;
    if (_c.enKiosco) {
      _programarPuntero();
    } else {
      _timerPuntero?.cancel();
      _quieto = false;
    }
    setState(() {});
  }

  bool _tecla(KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.escape &&
        _c.enKiosco) {
      unawaited(_c.salir());
      return true;
    }
    return false;
  }

  void _programarPuntero() {
    _timerPuntero?.cancel();
    if (!_c.enKiosco) return;
    _timerPuntero = Timer(widget.puntero, () {
      if (mounted && _c.enKiosco) setState(() => _quieto = true);
    });
  }

  void _movio() {
    if (_quieto) setState(() => _quieto = false);
    _programarPuntero();
  }

  void _abajo(PointerDownEvent e) {
    _movio();
    if (_c.enKiosco && _doble.toque(e.position, widget.reloj())) {
      unawaited(_c.salir());
    }
  }

  /// El último aviso, para que se vea mientras se desvanece.
  String? _ultimoAviso;

  @override
  Widget build(BuildContext context) {
    final aviso = _c.aviso;
    if (aviso != null) _ultimoAviso = aviso;
    final texto = _ultimoAviso;
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _abajo,
          onPointerHover: (_) => _movio(),
          onPointerMove: (_) => _movio(),
          child: MouseRegion(
            cursor: _quieto && _c.enKiosco
                ? SystemMouseCursors.none
                : MouseCursor.defer,
            child: widget.child,
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: aviso == null ? 0 : 1,
                duration: const Duration(milliseconds: 400),
                child: texto == null
                    ? const SizedBox.shrink()
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          texto,
                          textAlign: TextAlign.center,
                          // La letra que viene con la app: anda sin internet.
                          style: TextStyle(
                            fontFamily: FuentesTotem.linea,
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
