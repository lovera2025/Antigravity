import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import '../common/services/pdf_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Controladores de Animación
  late AnimationController _bgController;
  late AnimationController _emblemController;
  late AnimationController _textController;
  late AnimationController _shimmerController;

  // Animaciones
  late Animation<double> _bgOpacity;
  late Animation<double> _emblemScale;
  late Animation<double> _textOpacity;
  late Animation<double> _shimmerPosition;

  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    // 1. Configuración de Controladores
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _emblemController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // 2. Definición de Tweens
    _bgOpacity = Tween<double>(
      begin: 0.0,
      end: 0.15,
    ).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));

    _emblemScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _emblemController, curve: Curves.elasticOut),
    );

    _textOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeIn));

    _shimmerPosition = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );

    // Las fuentes de los PDF se resuelven durante el splash, en paralelo con la
    // animación: la espera de red se paga acá, donde no se nota, en vez de en el
    // cierre de caja con la plata en la mano. No se espera el resultado.
    PdfService.precalentarFuentes();

    // 3. Orquestación de la Animación (Nacimiento de Marca)
    _startSequence();
  }

  Future<void> _startSequence() async {
    // Fase 1: Enciende el patrón de fondo
    _bgController.forward();
    await Future.delayed(const Duration(milliseconds: 1000));

    // Fase 2: Emerge el emblema JE
    if (mounted) _emblemController.forward();
    await Future.delayed(const Duration(milliseconds: 800));

    // Fase 3: Aparece el texto Junior Eventos
    if (mounted) _textController.forward();

    // 4. Temporizador de Navegación
    _navigationTimer = Timer(
      const Duration(seconds: 5),
      () => _navigateToNext(),
    );
  }

  Future<void> _navigateToNext() async {
    if (!mounted) return;

    // Si ya navegamos manualmente a otra ruta (por ejemplo por URL en Web), abortar
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute != null &&
        currentRoute != '/' &&
        currentRoute != '/splash')
      return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AuthWrapper(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _bgController.dispose();
    _emblemController.dispose();
    _textController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Paleta Premium sugerida por el Director de Arte
    const Color charcoalDeep = Color(0xFF0D0D0D);
    const Color navyShade = Color(0xFF050B18);
    const Color primaryGold = Color(0xFFD4AF37);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [navyShade, charcoalDeep],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Patrón Geométrico de Fondo (CustomPainter) ──
            FadeTransition(
              opacity: _bgOpacity,
              child: const PremiumBackgroundPainterWidget(),
            ),

            // ── Capa Central: Emblema y Texto ──
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Emblema JE con Efecto Shimmer y Escala
                ScaleTransition(
                  scale: _emblemScale,
                  child: AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, child) {
                      return ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: const [
                              Colors.transparent,
                              Colors.white24,
                              Colors.white,
                              Colors.white24,
                              Colors.transparent,
                            ],
                            stops: [
                              0.0,
                              _shimmerPosition.value - 0.2,
                              _shimmerPosition.value,
                              _shimmerPosition.value + 0.2,
                              1.0,
                            ],
                          ).createShader(bounds);
                        },
                        child: child,
                      );
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Logo base (dorado metálico)
                        Image.asset(
                          'assets/icons/LOGO-3D-CROMADO-SIN-FONDO 2.png',
                          width: 280,
                          height: 280,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.celebration_rounded,
                                size: 140,
                                color: primaryGold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Texto Junior Eventos (Serif Playfair Display)
                FadeTransition(
                  opacity: _textOpacity,
                  child: Column(
                    children: [
                      Text(
                        'Junior Eventos',
                        style: GoogleFonts.playfairDisplay(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 42,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ESTÁNDAR EMPRESARIAL DE ÉLITE',
                        style: GoogleFonts.outfit(
                          color: primaryGold.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter para las líneas doradas sutiles que aportan profundidad táctil al fondo.
class PremiumBackgroundPainterWidget extends StatelessWidget {
  const PremiumBackgroundPainterWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: _PremiumLinesPainter());
  }
}

class _PremiumLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.3)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;

    // Dibujamos un patrón de malla inclinada 45 grados (look geométrico luxury)
    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }

    for (double i = 0; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i - size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
