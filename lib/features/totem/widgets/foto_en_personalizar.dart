import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/totem_config.dart';
import '../estilos/forma_foto.dart';

// La foto y las frases de la espera en Personalizar (6.2.1): la forma de la
// foto, el tamaño de la foto y de las frases, dónde van, y sobre la vista del
// tótem las manijas para agrandarlas y el arrastre para moverlas. Lo que se
// elige acá lo dibuja la misma escena de la pantalla del salón.

const _gold = TotemConfig.acentoPorDefecto;
const _oroClaro = Color(0xFFF3DC8A);

/// Las formas para elegir, cada una con su dibujo.
class FormasDeLaFoto extends StatelessWidget {
  final FormaFoto elegida;

  /// Null mientras se guarda.
  final ValueChanged<FormaFoto>? onChanged;

  const FormasDeLaFoto({
    super.key,
    required this.elegida,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in FormaFoto.values)
          _Forma(
            key: ValueKey('forma_${f.clave}'),
            forma: f,
            elegida: f == elegida,
            onTap: onChanged == null ? null : () => onChanged!(f),
          ),
      ],
    );
  }
}

class _Forma extends StatelessWidget {
  final FormaFoto forma;
  final bool elegida;
  final VoidCallback? onTap;

  const _Forma({
    super.key,
    required this.forma,
    required this.elegida,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = elegida ? _oroClaro : Colors.white70;
    return Material(
      color: elegida
          ? _gold.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: elegida ? _gold : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 84,
          height: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CustomPaint(painter: _DibujoForma(forma, color)),
              ),
              const SizedBox(height: 6),
              Text(forma.nombre, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// La forma en chico: llena; "Tal cual", un recuadro de puntos.
class _DibujoForma extends CustomPainter {
  final FormaFoto forma;
  final Color color;

  _DibujoForma(this.forma, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final medida = forma.medida(1);
    final escala = math.min(size.width / medida.width, size.height / medida.height);
    final r = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: medida.width * escala,
      height: medida.height * escala,
    );
    if (forma == FormaFoto.talCual) {
      final trazo = Paint()
        ..color = color
        ..strokeWidth = 1.5;
      // El recuadro de puntos: lo que se ve es la imagen entera.
      for (var x = r.left; x < r.right; x += 4) {
        canvas.drawLine(Offset(x, r.top), Offset(math.min(x + 2, r.right), r.top), trazo);
        canvas.drawLine(Offset(x, r.bottom), Offset(math.min(x + 2, r.right), r.bottom), trazo);
      }
      for (var y = r.top; y < r.bottom; y += 4) {
        canvas.drawLine(Offset(r.left, y), Offset(r.left, math.min(y + 2, r.bottom)), trazo);
        canvas.drawLine(Offset(r.right, y), Offset(r.right, math.min(y + 2, r.bottom)), trazo);
      }
      return;
    }
    canvas.drawPath(forma.camino(r), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DibujoForma old) => old.forma != forma || old.color != color;
}

/// Un tamaño en %: − y + de a [paso], o la barra. [clave] nombra los botones
/// (`achicar_<clave>`, `tamano_<clave>`, `agrandar_<clave>`).
class BarraDeTamano extends StatelessWidget {
  final String clave;
  final int valor;
  final int minimo;
  final int maximo;

  /// Null mientras se guarda.
  final ValueChanged<int>? onChanged;

  const BarraDeTamano({
    super.key,
    required this.clave,
    required this.valor,
    required this.minimo,
    required this.maximo,
    required this.onChanged,
  });

  static const paso = 10;

  @override
  Widget build(BuildContext context) {
    final cambiar = onChanged;
    void poner(num v) => cambiar?.call(v.round().clamp(minimo, maximo));
    return Row(
      children: [
        IconButton(
          key: ValueKey('achicar_$clave'),
          tooltip: 'Achicar',
          onPressed: cambiar == null || valor <= minimo ? null : () => poner(valor - paso),
          icon: const Icon(Icons.remove_rounded),
          color: Colors.white70,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _gold,
              thumbColor: _gold,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              overlayColor: _gold.withValues(alpha: 0.15),
            ),
            child: Slider(
              key: ValueKey('tamano_$clave'),
              value: valor.clamp(minimo, maximo).toDouble(),
              min: minimo.toDouble(),
              max: maximo.toDouble(),
              divisions: (maximo - minimo) ~/ paso,
              onChanged: cambiar == null ? null : poner,
            ),
          ),
        ),
        IconButton(
          key: ValueKey('agrandar_$clave'),
          tooltip: 'Agrandar',
          onPressed: cambiar == null || valor >= maximo ? null : () => poner(valor + paso),
          icon: const Icon(Icons.add_rounded),
          color: Colors.white70,
        ),
        SizedBox(
          width: 52,
          child: Text(
            '$valor %',
            key: ValueKey('valor_$clave'),
            textAlign: TextAlign.right,
            style: const TextStyle(color: _oroClaro, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

/// Dónde van la foto y las frases: nueve lugares para tocar. El elegido es el
/// más cercano a donde están (también si se movieron arrastrando).
class UbicacionDeLaEspera extends StatelessWidget {
  final int x;
  final int y;

  /// Null mientras se guarda.
  final void Function(int x, int y)? onChanged;

  const UbicacionDeLaEspera({
    super.key,
    required this.x,
    required this.y,
    required this.onChanged,
  });

  static int _cerca(int v) => v <= -50 ? -100 : (v >= 50 ? 100 : 0);

  @override
  Widget build(BuildContext context) {
    final cx = _cerca(x), cy = _cerca(y);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          height: 120,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  for (final fy in const [-100, 0, 100])
                    Expanded(
                      child: Row(
                        children: [
                          for (final fx in const [-100, 0, 100])
                            Expanded(
                              child: _Lugar(
                                key: ValueKey('ubicacion_${fx}_$fy'),
                                elegido: fx == cx && fy == cy,
                                onTap: onChanged == null
                                    ? null
                                    : () => onChanged!(fx, fy),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextButton.icon(
            key: const ValueKey('ubicacion_al_medio'),
            onPressed: onChanged == null || (x == 0 && y == 0)
                ? null
                : () => onChanged!(0, 0),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
            label: const Text('Volver al medio'),
          ),
        ),
      ],
    );
  }
}

class _Lugar extends StatelessWidget {
  final bool elegido;
  final VoidCallback? onTap;

  const _Lugar({super.key, required this.elegido, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: elegido ? 16 : 10,
          height: elegido ? 16 : 10,
          decoration: BoxDecoration(
            color: elegido ? _gold : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// Las manijas sobre la foto o las frases, en la vista de Personalizar:
/// arrastrar una esquina hacia afuera agranda y hacia adentro achica, entre
/// [minimo] y [maximo]. Van pegadas a lo que agrandan y no cambian lo que mide:
/// la vista es igual al tótem. [clave] nombra las esquinas
/// (`manija_<clave>_<x>_<y>`).
class ManijasParaAgrandar extends StatefulWidget {
  final String clave;
  final Widget child;
  final int tamano;
  final int minimo;
  final int maximo;
  final ValueChanged<int> onTamano;

  const ManijasParaAgrandar({
    super.key,
    required this.clave,
    required this.child,
    required this.tamano,
    required this.minimo,
    required this.maximo,
    required this.onTamano,
  });

  /// El lado de la manija que se ve, y el de la zona que se puede agarrar.
  static const manija = 12.0;
  static const agarre = 26.0;

  @override
  State<ManijasParaAgrandar> createState() => _ManijasParaAgrandarState();
}

class _ManijasParaAgrandarState extends State<ManijasParaAgrandar> {
  /// Al apretar: el medio, lo lejos que estaba el dedo y el tamaño. El nuevo
  /// tamaño sale de cuánto se alejó o se acercó el dedo del medio.
  Offset? _medio;
  double _lejos = 1;
  int _tamano = 100;

  void _empieza(DragStartDetails d) {
    final caja = context.findRenderObject() as RenderBox?;
    if (caja == null || !caja.hasSize) return;
    _medio = caja.localToGlobal(caja.size.center(Offset.zero));
    _lejos = math.max(8, (d.globalPosition - _medio!).distance);
    _tamano = widget.tamano;
  }

  void _mueve(DragUpdateDetails d) {
    final medio = _medio;
    if (medio == null) return;
    final nuevo = (_tamano * (d.globalPosition - medio).distance / _lejos)
        .round()
        .clamp(widget.minimo, widget.maximo);
    if (nuevo != widget.tamano) widget.onTamano(nuevo);
  }

  Widget _esquina(Alignment donde, MouseCursor cursor) {
    return Align(
      alignment: donde,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          key: ValueKey('manija_${widget.clave}_${donde.x}_${donde.y}'),
          behavior: HitTestBehavior.opaque,
          onPanStart: _empieza,
          onPanUpdate: _mueve,
          onPanEnd: (_) => _medio = null,
          child: SizedBox(
            width: ManijasParaAgrandar.agarre,
            height: ManijasParaAgrandar.agarre,
            child: Align(
              alignment: donde,
              child: Container(
                width: ManijasParaAgrandar.manija,
                height: ManijasParaAgrandar.manija,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: _gold, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Stack(
            children: [
              _esquina(Alignment.topLeft, SystemMouseCursors.resizeUpLeftDownRight),
              _esquina(Alignment.topRight, SystemMouseCursors.resizeUpRightDownLeft),
              _esquina(Alignment.bottomLeft, SystemMouseCursors.resizeUpRightDownLeft),
              _esquina(Alignment.bottomRight, SystemMouseCursors.resizeUpLeftDownRight),
            ],
          ),
        ),
      ],
    );
  }
}

/// La foto y las frases juntas, en la vista de Personalizar: arrastrarlas las
/// mueve. Llegan hasta el borde del lugar que deja la apariencia, nunca afuera.
/// Las manijas de adentro ganan: agarrar una esquina agranda, no mueve.
class ArrastrarParaUbicar extends StatefulWidget {
  final Widget child;

  /// Lo que mide la pantalla del tótem en la vista.
  final Size pantalla;
  final int x;
  final int y;
  final void Function(int x, int y) onUbicacion;

  const ArrastrarParaUbicar({
    super.key,
    required this.child,
    required this.pantalla,
    required this.x,
    required this.y,
    required this.onUbicacion,
  });

  @override
  State<ArrastrarParaUbicar> createState() => _ArrastrarParaUbicarState();
}

class _ArrastrarParaUbicarState extends State<ArrastrarParaUbicar> {
  /// Al apretar: dónde estaba el dedo, dónde estaba lo de la espera, y cuánto
  /// lugar libre le queda en cada sentido (en la vista, ya achicado).
  Offset? _desde;
  int _x = 0, _y = 0;
  Size _libre = const Size(1, 1);

  void _empieza(DragStartDetails d) {
    final caja = context.findRenderObject() as RenderBox?;
    if (caja == null || !caja.hasSize) return;
    final a = caja.localToGlobal(Offset.zero);
    final b = caja.localToGlobal(caja.size.bottomRight(Offset.zero));
    _libre = Size(
      math.max(40, widget.pantalla.width - (b.dx - a.dx)),
      math.max(40, widget.pantalla.height - (b.dy - a.dy)),
    );
    _desde = d.globalPosition;
    _x = widget.x;
    _y = widget.y;
  }

  void _mueve(DragUpdateDetails d) {
    final desde = _desde;
    if (desde == null) return;
    final corrido = d.globalPosition - desde;
    // Con la alineación, de -1 a 1 es todo el lugar libre: 200 puntos.
    final x = (_x + corrido.dx / _libre.width * 200).round().clamp(-100, 100);
    final y = (_y + corrido.dy / _libre.height * 200).round().clamp(-100, 100);
    if (x != widget.x || y != widget.y) widget.onUbicacion(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        key: const ValueKey('arrastrar_espera'),
        behavior: HitTestBehavior.opaque,
        onPanStart: _empieza,
        onPanUpdate: _mueve,
        onPanEnd: (_) => _desde = null,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
