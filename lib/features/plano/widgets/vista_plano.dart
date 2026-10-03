import 'package:flutter/material.dart';

import '../dibujo/pintor_plano.dart';
import '../estilos/estilo_plano.dart';
import '../modelo/armado_salon.dart';
import '../modelo/estado_plano.dart';
import '../modelo/medidas_salon.dart';

/// Una hoja del plano, dibujada en un estilo, con las mesas tocables.
///
/// No sabe de base ni de Riverpod: recibe el armado, el estado y el tema. Así
/// la misma vista sirve para la pantalla de la fiesta, la vista previa del
/// selector de estilo y, en diciembre, el tótem.
class VistaPlano extends StatefulWidget {
  const VistaPlano({
    super.key,
    required this.armado,
    required this.hoja,
    required this.tema,
    required this.estado,
    this.resaltadas = const {},
    this.seleccionada,
    this.onTapMesa,
    this.onHoverMesa,
    this.ruta,
    this.progresoRuta = 1,
    this.animar = true,
    this.pulsoFijo = 0.35,
    this.mostrarRegla = false,
    this.mostrarMedidas = false,
    this.lugares,
    this.encima,
    this.onApretar,
    this.onArrastrar,
    this.onSoltar,
  });

  final ArmadoSalon armado;
  final String hoja;
  final TemaPlano tema;
  final EstadoPlano estado;
  final Set<int> resaltadas;
  final int? seleccionada;
  final ValueChanged<int>? onTapMesa;
  final ValueChanged<int?>? onHoverMesa;

  /// Camino desde el ingreso, en coordenadas del plano (tótem, diciembre).
  final List<Offset>? ruta;
  final double progresoRuta;

  /// Si es false, el pulso queda quieto en [pulsoFijo] (tests y muestras).
  final bool animar;
  final double pulsoFijo;

  /// La regla en metros, abajo a la izquierda.
  final bool mostrarRegla;

  /// Lo que mide cada lado del hormigón, en los armados a medida.
  final bool mostrarMedidas;

  /// Con las medidas de la fiesta, cada mesa lleva el círculo de lugar que
  /// pide, en rojo si no lo tiene (para acomodar el salón).
  final MedidasPlano? lugares;

  /// Algo más para dibujar encima del plano (la regla al acomodar el salón).
  final CustomPainter? encima;

  /// Para acomodar el salón arrastrando. Se aprieta en un punto, **en
  /// coordenadas del plano**; si devuelve true se agarró algo, y lo que se
  /// mueva hasta soltar llega por [onArrastrar].
  final bool Function(Offset enPlano)? onApretar;
  final ValueChanged<Offset>? onArrastrar;
  final VoidCallback? onSoltar;

  @override
  State<VistaPlano> createState() => _VistaPlanoState();
}

class _VistaPlanoState extends State<VistaPlano>
    with SingleTickerProviderStateMixin {
  // Un solo controller para toda la vida del widget: el mixin admite un solo
  // ticker, así que prender y apagar el pulso es `repeat()` y `stop()`.
  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late Animation<double> _quieto = AlwaysStoppedAnimation(widget.pulsoFijo);
  int? _bajoMouse;

  /// El puntero con el que se agarró algo para arrastrar.
  int? _agarrado;

  Offset? _enPlano(Size size, Offset punto) {
    final h = widget.armado.hoja(widget.hoja);
    return h == null ? null : EncuadrePlano.de(h.caja, size).aPlano(punto);
  }

  void _soltar(PointerEvent e) {
    if (_agarrado != e.pointer) return;
    _agarrado = null;
    widget.onSoltar?.call();
  }

  @override
  void initState() {
    super.initState();
    _ajustarAnimacion();
  }

  @override
  void didUpdateWidget(VistaPlano old) {
    super.didUpdateWidget(old);
    if (old.pulsoFijo != widget.pulsoFijo) {
      _quieto = AlwaysStoppedAnimation(widget.pulsoFijo);
    }
    _ajustarAnimacion();
  }

  /// Lo resaltado que está en esta hoja. Lo de la otra hoja no lleva pulso
  /// acá.
  Set<int> get _resaltadas => mesasEnHoja(widget.armado, widget.hoja, {
        ...widget.resaltadas,
        if (widget.seleccionada != null) widget.seleccionada!,
      });

  bool get _hayQueResaltar => _resaltadas.isNotEmpty || widget.ruta != null;

  /// El pulso corre solo si hay algo que lo muestre: si no, la app nunca
  /// queda quieta (y un `pumpAndSettle` no termina).
  void _ajustarAnimacion() {
    final mover = widget.animar && _hayQueResaltar;
    if (mover && !_pulso.isAnimating) {
      _pulso.repeat();
    } else if (!mover && _pulso.isAnimating) {
      _pulso.stop();
    }
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final tocable = widget.onTapMesa != null || widget.onHoverMesa != null;
        Widget plano = Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: PintorPlano(
                  armado: widget.armado,
                  hoja: widget.hoja,
                  tema: widget.tema,
                  estado: widget.estado,
                  resaltadas: widget.resaltadas,
                  seleccionada: widget.seleccionada,
                  regla: widget.mostrarRegla,
                  cotas: widget.mostrarMedidas,
                  lugares: widget.lugares,
                ),
              ),
            ),
            if (_hayQueResaltar)
              // Su propia capa: el pulso repinta solo los anillos, no lo que
              // haya alrededor del plano.
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: PintorResaltado(
                      armado: widget.armado,
                      hoja: widget.hoja,
                      tema: widget.tema,
                      estado: widget.estado,
                      resaltadas: _resaltadas,
                      pulso: widget.animar ? _pulso : _quieto,
                      ruta: widget.ruta,
                      progresoRuta: widget.progresoRuta,
                    ),
                  ),
                ),
              ),
            if (widget.encima != null)
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: widget.encima),
                ),
              ),
          ],
        );
        if (widget.onApretar != null) {
          // Con eventos crudos y no con un gesto: así no compite con el zoom
          // y el desplazamiento del plano, que escuchan los mismos toques.
          plano = Listener(
            onPointerDown: (e) {
              final p = _enPlano(size, e.localPosition);
              if (_agarrado != null || p == null) return;
              if (widget.onApretar!(p)) _agarrado = e.pointer;
            },
            onPointerMove: (e) {
              final p = _enPlano(size, e.localPosition);
              if (_agarrado == e.pointer && p != null) {
                widget.onArrastrar?.call(p);
              }
            },
            onPointerUp: _soltar,
            onPointerCancel: _soltar,
            child: plano,
          );
        }
        if (!tocable) return plano;
        plano = MouseRegion(
          cursor: _bajoMouse != null && widget.onTapMesa != null
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          onHover: (e) => _hover(size, e.localPosition),
          onExit: (_) => _hover(size, null),
          child: plano,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final n = mesaEnPunto(
              widget.armado,
              widget.hoja,
              size,
              d.localPosition,
            );
            if (n != null) widget.onTapMesa?.call(n);
          },
          child: plano,
        );
      },
    );
  }

  void _hover(Size size, Offset? punto) {
    final n = punto == null
        ? null
        : mesaEnPunto(widget.armado, widget.hoja, size, punto);
    if (n == _bajoMouse) return;
    setState(() => _bajoMouse = n);
    widget.onHoverMesa?.call(n);
  }
}
