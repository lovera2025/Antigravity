import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/totem_config.dart';
import '../services/contenido_bienvenida.dart';

/// La tarjeta de bienvenida del tótem, y debajo cuántos esperan la suya.
///
/// Lo que dice lo decide [ContenidoBienvenida]; acá solo se dibuja. La
/// pantalla del tótem le pasa sus animaciones de entrada; quieta (los tests y
/// las muestras) se ve como al terminar de entrar.
///
/// Toda la letra es Outfit regular o negrita, la que viene con la app: el
/// tótem tiene que poder saludar sin internet, y la que se baja no está.
class TarjetaBienvenida extends StatelessWidget {
  final ContenidoBienvenida contenido;
  final TotemConfig cfg;
  final double escala;

  /// "N más en camino". Con 0 no se muestra.
  final int enCamino;

  final Animation<double> tamanio;
  final Animation<double> apareceFoto;
  final Animation<double> apareceSaludo;
  final Animation<Offset> subeSaludo;
  final Animation<double> abreNombre;
  final Animation<Offset> entraMesa;
  final Animation<double> brillo;

  const TarjetaBienvenida({
    super.key,
    required this.contenido,
    required this.cfg,
    required this.escala,
    this.enCamino = 0,
    this.tamanio = const AlwaysStoppedAnimation(1),
    this.apareceFoto = const AlwaysStoppedAnimation(1),
    this.apareceSaludo = const AlwaysStoppedAnimation(1),
    this.subeSaludo = const AlwaysStoppedAnimation(Offset.zero),
    this.abreNombre = const AlwaysStoppedAnimation(1),
    this.entraMesa = const AlwaysStoppedAnimation(Offset.zero),
    this.brillo = const AlwaysStoppedAnimation(1),
  });

  static const _perla = Color(0xFFE2E2E2);

  Color get _acento => cfg.colorAcento;

  @override
  Widget build(BuildContext context) {
    // Una familia con la mesa, las sillas y la música puede no entrar a lo
    // alto en una pantalla apaisada: se achica entera, nunca se corta. A lo
    // ancho los nombres se parten en renglones, como siempre.
    return LayoutBuilder(
      builder: (context, c) => FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: c.maxWidth),
          child: _tarjeta(),
        ),
      ),
    );
  }

  Widget _tarjeta() {
    final s = escala;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: tamanio.value.clamp(0.0, 1.05),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 42),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: cfg.gradienteCard,
              ),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: _acento.withValues(alpha: 0.50),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _acento.withValues(alpha: 0.32),
                  blurRadius: 70,
                  spreadRadius: 18,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 30,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: PintorBrillo(brillo.value)),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(opacity: apareceFoto, child: _foto(s)),
                      SizedBox(height: 22 * s),
                      ClipRect(
                        child: SlideTransition(
                          position: subeSaludo,
                          child: FadeTransition(
                            opacity: apareceSaludo,
                            child: Text(
                              contenido.saludo,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 50 * s,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 18 * s),
                      _nombres(s),
                      if (contenido.conQuien != null ||
                          contenido.acompanaA != null) ...[
                        SizedBox(height: 12 * s),
                        Opacity(
                          opacity: abreNombre.value.clamp(0.0, 1.0),
                          child: Text(
                            (contenido.conQuien ?? contenido.acompanaA)!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 22 * s,
                              fontWeight: FontWeight.w400,
                              color: _perla.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                      ],
                      if (contenido.mesa != null ||
                          contenido.musica != null) ...[
                        SizedBox(height: 22 * s),
                        ClipRect(
                          child: SlideTransition(
                            position: entraMesa,
                            child: _mesaSillasYMusica(s),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (enCamino > 0) ...[
          SizedBox(height: 26 * s),
          Text(
            '$enCamino más en camino',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 18 * s,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: _acento.withValues(alpha: 0.9),
            ),
          ),
        ],
      ],
    );
  }

  /// La foto del evento; sin foto, o si no baja, el logo de la empresa, como
  /// en la pantalla de espera.
  Widget _foto(double s) {
    final lado = 128 * s;
    final logo = Image.asset(
      'assets/icons/logo-transparent-final.png',
      width: lado * 0.62,
      height: lado * 0.62,
      fit: BoxFit.contain,
      color: const Color(0xFFF2F0EB),
      errorBuilder: (_, _, _) => Icon(
        Icons.celebration_rounded,
        size: lado * 0.5,
        color: const Color(0xFFF2F0EB),
      ),
    );
    final url = cfg.imagenUrl;
    return Container(
      width: lado,
      height: lado,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: url == null ? _perla.withValues(alpha: 0.12) : null,
        border: Border.all(
          color: url == null
              ? _perla.withValues(alpha: 0.30)
              : _acento.withValues(alpha: 0.75),
          width: url == null ? 1 : 3,
        ),
        boxShadow: url == null
            ? null
            : [
                BoxShadow(
                  color: _acento.withValues(alpha: 0.45),
                  blurRadius: 40,
                  spreadRadius: 6,
                ),
              ],
      ),
      child: url == null
          ? logo
          : ClipOval(
              child: Image.network(
                url,
                width: lado,
                height: lado,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(child: logo),
              ),
            ),
    );
  }

  /// Los nombres en grande, que se abren desde el centro.
  Widget _nombres(double s) {
    return ClipRect(
      child: Align(
        alignment: Alignment.center,
        widthFactor: abreNombre.value.clamp(0.0, 1.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, nombre) in contenido.nombres.indexed) ...[
              if (i > 0) SizedBox(height: 10 * s),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 22 * s,
                  vertical: 11 * s,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _perla.withValues(alpha: 0.22),
                      _perla.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _perla.withValues(alpha: 0.40),
                    width: 1,
                  ),
                ),
                child: Text(
                  nombre,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: (contenido.nombres.length > 1 ? 36 : 42) * s,
                    fontWeight: FontWeight.w700,
                    color: _perla,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// La mesa, debajo las sillas que le tocan, y la música.
  Widget _mesaSillasYMusica(double s) {
    final mesa = contenido.mesa;
    final musica = contenido.musica;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mesa != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(10 * s),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.table_restaurant_rounded,
                  color: Colors.white60,
                  size: 24 * s,
                ),
              ),
              SizedBox(width: 14 * s),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      contenido.rotuloMesa,
                      style: GoogleFonts.outfit(
                        fontSize: 14 * s,
                        fontWeight: FontWeight.w400,
                        color: Colors.white54,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      'Nº $mesa',
                      style: GoogleFonts.outfit(
                        fontSize: 36 * s,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (contenido.sillas != null) ...[
            SizedBox(height: 10 * s),
            Text(
              contenido.sillas!,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 20 * s,
                fontWeight: FontWeight.w400,
                color: _perla.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
        if (musica != null) ...[
          SizedBox(height: (mesa != null ? 16 : 0) * s),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícono y no el carácter de la nota: la letra no lo tiene.
              Icon(Icons.music_note_rounded, size: 22 * s, color: _acento),
              SizedBox(width: 8 * s),
              Flexible(
                child: Text(
                  musica,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20 * s,
                    fontWeight: FontWeight.w400,
                    color: _acento,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// El brillo que cruza la tarjeta una vez por vuelta de [t] (de 0 a 1).
class PintorBrillo extends CustomPainter {
  final double t;
  const PintorBrillo(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Dispara una sola vez por ciclo en la ventana 0.0 → 0.28
    const windowEnd = 0.28;
    if (t > windowEnd) return;

    final localT = t / windowEnd;
    final sweepX = -size.width * 0.45 + localT * size.width * 1.9;

    final shader = LinearGradient(
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.10),
        Colors.white.withValues(alpha: 0.18),
        Colors.white.withValues(alpha: 0.10),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      transform: const GradientRotation(0.45),
    ).createShader(
      Rect.fromLTWH(sweepX, 0, size.width * 0.55, size.height),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(PintorBrillo old) => old.t != t;
}
