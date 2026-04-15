import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedBackground extends StatefulWidget {
  final Widget? child;
  const AnimatedBackground({super.key, this.child});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20), // Un poco más lento pero más amplio
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Colores para el fondo dinámico
    final Color color1 = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF2F0EB);
    
    return Stack(
      children: [
        // Fondo base sólido
        Positioned.fill(child: Container(color: color1)),
        
        // Selector de Animación según el Modo
        isDark ? _buildNightAnimation() : _buildDayAnimation(),
        
        // Efecto de textura sutil blindado (Red)
        Positioned.fill(
          child: Opacity(
            opacity: isDark ? 0.02 : 0.03,
            child: Image.network(
              'https://www.transparenttextures.com/patterns/pinstriped-suit.png',
              repeat: ImageRepeat.repeat,
              filterQuality: FilterQuality.low,
              errorBuilder: (context, error, stackTrace) {
                // Failsafe: Si falla la red, no cargamos nada o usamos un fallback invisible.
                debugPrint('⚠️ AnimatedBackground: Error textura red ($error)');
                return const SizedBox.shrink();
              },
            ),
          ),
        ),

        // Contenido del usuario
        if (widget.child != null) widget.child!,
      ],
    );
  }

  Widget _buildNightAnimation() {
    final primaryGold = const Color(0xFFD4AF37);
    final accent1 = primaryGold.withValues(alpha: 0.18);
    final accent2 = primaryGold.withValues(alpha: 0.12);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            _OffsetCircle(
              controller: _controller,
              color: accent1,
              size: 1080,
              offset: const Offset(-300, -300),
              frequencyX: 1,
              frequencyY: 1,
            ),
            _OffsetCircle(
              controller: _controller,
              color: accent2,
              size: 960,
              offset: const Offset(480, 360),
              frequencyX: 2,
              frequencyY: 1,
              reverse: true,
            ),
            _OffsetCircle(
              controller: _controller,
              color: accent1.withValues(alpha: 0.08),
              size: 1320,
              offset: const Offset(60, 60),
              frequencyX: 1,
              frequencyY: 2,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDayAnimation() {
    final primaryGold = const Color(0xFFD4AF37);
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: List.generate(12, (index) {
            final double t = (_controller.value + (index / 12)) % 1.0;
            final double angle = t * 2 * math.pi;
            
            final double dx = math.sin(angle * (1 + index % 3)) * 120;
            final double dy = math.cos(angle * 0.8) * 180;
            
            final double baseLeft = (index * 150) % (MediaQuery.of(context).size.width + 200) - 100;
            final double baseTop = (index * 200) % (MediaQuery.of(context).size.height + 200) - 100;

            return Positioned(
              left: baseLeft + dx,
              top: baseTop + dy,
              child: Opacity(
                opacity: 0.20 + (math.sin(t * math.pi) * 0.1),
                child: Container(
                  width: 180 + (index % 5) * 48,
                  height: 180 + (index % 5) * 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primaryGold.withValues(alpha: 0.25),
                        primaryGold.withValues(alpha: 0.05),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: -5,
                      )
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _OffsetCircle extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  final double size;
  final Offset offset;
  final double frequencyX;
  final double frequencyY;
  final bool reverse;

  const _OffsetCircle({
    required this.controller,
    required this.color,
    required this.size,
    required this.offset,
    this.frequencyX = 1.0,
    this.frequencyY = 1.0,
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final double t = controller.value * 2 * math.pi;
        final double factor = reverse ? -1.0 : 1.0;
        final double dx = math.sin(t * frequencyX) * 180 * factor;
        final double dy = math.cos(t * frequencyY) * 144; // Movimiento más amplio (+20%)
        
        return Positioned(
          left: offset.dx + dx,
          top: offset.dy + dy,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color,
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
