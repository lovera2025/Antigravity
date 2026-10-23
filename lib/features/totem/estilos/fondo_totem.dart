import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'totem_estilo.dart';

/// El fondo animado de una apariencia de la casa ([EstiloTotem.deLaCasa]): su
/// shader (`shaders/`), con el color del evento. El de "Tu fondo" lee una
/// imagen y lo pinta `FondoPropio`.
///
/// El shader se carga **una vez** por apariencia y queda guardado. Si una PC
/// no lo puede usar, o mientras carga, se pinta un degradé del mismo color:
/// **nunca una pantalla rota**.
class FondoTotem extends StatefulWidget {
  final EstiloTotem estilo;

  /// El color del evento.
  final Color color;

  /// 1 en la espera; 0,55 durante una llegada, para que se lea el saludo.
  /// Cristal queda en 1 (lo decide [EscenaTotem]).
  final double atenuado;

  /// El fogonazo de la llegada, de 0 a 1.
  final double fogonazo;

  /// Un instante fijo, en segundos: sin animación (los tests y las muestras).
  final double? tiempoFijo;

  const FondoTotem({
    super.key,
    required this.estilo,
    required this.color,
    this.atenuado = 1,
    this.fogonazo = 0,
    this.tiempoFijo,
  }) : assert(estilo != EstiloTotem.tuFondo, 'Tu fondo lo pinta FondoPropio');

  static final _programas = <EstiloTotem, Future<ui.FragmentProgram?>>{};
  static final _listos = <EstiloTotem, ui.FragmentProgram?>{};

  /// Cómo se carga un shader. Solo los tests lo cambian (para probar el
  /// degradé de respaldo).
  @visibleForTesting
  static Future<ui.FragmentProgram> Function(String asset) cargar =
      ui.FragmentProgram.fromAsset;

  /// Carga el shader de [estilo] si no está; null si no se pudo.
  static Future<ui.FragmentProgram?> programa(EstiloTotem estilo) =>
      _programas[estilo] ??= () async {
        try {
          final p = await cargar(estilo.shader);
          _listos[estilo] = p;
          return p;
        } catch (e) {
          debugPrint('El fondo ${estilo.nombre} no carga; va el degradé: $e');
          _listos[estilo] = null;
          return null;
        }
      }();

  /// Carga las cuatro de antemano (al abrir el tótem, en los tests).
  static Future<void> precargar() =>
      Future.wait([for (final e in EstiloTotem.deLaCasa) programa(e)]);

  /// Olvida lo cargado. Solo los tests.
  @visibleForTesting
  static void olvidar() {
    _programas.clear();
    _listos.clear();
    cargar = ui.FragmentProgram.fromAsset;
  }

  /// Si [estilo] ya se pudo cargar (false: degradé, o todavía cargando).
  @visibleForTesting
  static bool tieneShader(EstiloTotem estilo) => _listos[estilo] != null;

  @override
  State<FondoTotem> createState() => _FondoTotemState();
}

class _FondoTotemState extends State<FondoTotem>
    with SingleTickerProviderStateMixin {
  final _tiempo = ValueNotifier<double>(0);
  Ticker? _ticker;
  ui.FragmentShader? _shader;
  EstiloTotem? _deShader;

  @override
  void initState() {
    super.initState();
    _prepararShader();
    if (widget.tiempoFijo == null) {
      _ticker = createTicker((d) => _tiempo.value = d.inMicroseconds / 1e6)
        ..start();
    } else {
      _tiempo.value = widget.tiempoFijo!;
    }
  }

  @override
  void didUpdateWidget(covariant FondoTotem old) {
    super.didUpdateWidget(old);
    if (old.estilo != widget.estilo) _prepararShader();
    if (widget.tiempoFijo != null) _tiempo.value = widget.tiempoFijo!;
  }

  void _prepararShader() {
    final estilo = widget.estilo;
    if (FondoTotem._listos.containsKey(estilo)) {
      _usar(estilo, FondoTotem._listos[estilo]);
      return;
    }
    _usar(estilo, null);
    FondoTotem.programa(estilo).then((p) {
      if (mounted && widget.estilo == estilo) setState(() => _usar(estilo, p));
    });
  }

  void _usar(EstiloTotem estilo, ui.FragmentProgram? p) {
    _shader?.dispose();
    _shader = p?.fragmentShader();
    _deShader = estilo;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _shader?.dispose();
    _tiempo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PintorFondo(
        tiempo: _tiempo,
        shader: _deShader == widget.estilo ? _shader : null,
        color: widget.color,
        segundo: segundoNeon(widget.color),
        atenuado: widget.atenuado,
        fogonazo: widget.fogonazo,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PintorFondo extends CustomPainter {
  final ValueListenable<double> tiempo;
  final ui.FragmentShader? shader;
  final Color color;
  final Color segundo;
  final double atenuado;
  final double fogonazo;

  _PintorFondo({
    required this.tiempo,
    required this.shader,
    required this.color,
    required this.segundo,
    required this.atenuado,
    required this.fogonazo,
  }) : super(repaint: tiempo);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final s = shader;
    if (s == null) {
      // El respaldo: un degradé del color del evento, oscuro.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.2,
            colors: [
              Color.lerp(color, Colors.black, 0.55)!
                  .withValues(alpha: atenuado.clamp(0.3, 1)),
              const Color(0xFF050308),
            ],
          ).createShader(rect),
      );
      return;
    }
    // El orden de los uniformes es el de los .frag: uRes, uT, uA, uB, uP,
    // uS, uD. uRes va en las mismas unidades que FlutterFragCoord, y uD = 1.
    s
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, tiempo.value)
      ..setFloat(3, color.r)
      ..setFloat(4, color.g)
      ..setFloat(5, color.b)
      ..setFloat(6, segundo.r)
      ..setFloat(7, segundo.g)
      ..setFloat(8, segundo.b)
      ..setFloat(9, fogonazo)
      ..setFloat(10, atenuado)
      ..setFloat(11, 1);
    canvas.drawRect(rect, Paint()..shader = s);
  }

  @override
  bool shouldRepaint(_PintorFondo old) =>
      old.shader != shader ||
      old.color != color ||
      old.atenuado != atenuado ||
      old.fogonazo != fogonazo;
}
