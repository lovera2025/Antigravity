import 'package:flutter/material.dart';

class AnimatedBrandLogo extends StatefulWidget {
  final double height;
  final String assetPath;

  const AnimatedBrandLogo({
    super.key,
    required this.height,
    this.assetPath = 'assets/icons/2.png',
  });

  @override
  State<AnimatedBrandLogo> createState() => _AnimatedBrandLogoState();
}

class _AnimatedBrandLogoState extends State<AnimatedBrandLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reset();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Opacity(
                  opacity: 1.0 - _animation.value,
                  child: Transform.scale(
                    scale: 1.0 + (_animation.value * 0.5),
                    child: Container(
                      width: widget.height * 1.8,
                      height: widget.height * 1.8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                            blurRadius: 10 * _animation.value,
                            spreadRadius: 5 * _animation.value,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Image.asset(
              widget.assetPath,
              height: widget.height,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.business,
                size: widget.height,
                color: const Color(0xFFD4AF37),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
