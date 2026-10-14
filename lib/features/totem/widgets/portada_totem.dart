import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../models/totem_config.dart';
import '../services/ficha_totem.dart';

/// Si el tótem muestra el QR.
///
/// **En un evento masivo, no.** En la ventana del escritorio, hasta que llega
/// la ficha no se sabe qué evento es, así que tampoco (llega en milisegundos,
/// debajo del fundido de apertura). En la web no hay ficha que pedir: sigue
/// como siempre, con el QR.
bool hayQrEnElTotem({
  required bool enLaVentanaDelEscritorio,
  required FichaTotem? ficha,
}) =>
    !enLaVentanaDelEscritorio || (ficha != null && !ficha.masivo);

/// Lo que el tótem muestra mientras espera: la foto del evento, el título, el
/// subtítulo y, solo en un evento particular, el QR para que cada invitado se
/// busque desde su celular.
///
/// **En un evento masivo no hay QR** (decisión del usuario): los alumnos no
/// tienen DNI, y con el QR a la vista cualquiera podía marcar a otro. A los
/// alumnos los marca Recepción.
///
/// Toda la letra es Outfit regular o negrita, la que viene con la app.
class PortadaTotem extends StatelessWidget {
  final TotemConfig cfg;

  /// Null: sin QR.
  final String? qrUrl;
  final bool apaisado;
  final double escala;

  /// La respiración de la foto y del recuadro del QR.
  final Animation<double> pulso;

  const PortadaTotem({
    super.key,
    required this.cfg,
    required this.qrUrl,
    required this.apaisado,
    required this.escala,
    this.pulso = const AlwaysStoppedAnimation(0),
  });

  static const _perla = Color(0xFFE2E2E2);

  Color get _acento => cfg.colorAcento;

  @override
  Widget build(BuildContext context) {
    final s = escala;
    final qr = qrUrl;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: apaisado ? 48 : 20),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Foto del evento, o el logo de la empresa si nadie cargó una. Sin
            // QR queda más lugar: la foto crece.
            _portada(s * (qr == null ? 1.35 : 1)),
            SizedBox(height: (qr == null ? 30 : 20) * s),
            Text(
              cfg.titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: (qr == null ? 44 : 38) * s,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: _perla.withValues(alpha: 0.4),
              ),
            ),
            if (cfg.subtitulo.isNotEmpty) ...[
              SizedBox(height: 8 * s),
              Text(
                cfg.subtitulo.toUpperCase(),
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 15 * s,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 9,
                  color: _acento.withValues(alpha: 0.85),
                ),
              ),
            ],
            if (qr != null) ...[
              SizedBox(height: 36 * s),
              _recuadroQr(qr, s),
            ],
          ],
        ),
      ),
    );
  }

  /// Foto principal del evento.
  ///
  /// Con `imagen_url` cargada muestra la foto en círculo, con borde y
  /// resplandor del color de acento — es la cara del evento, la de la
  /// quinceañera o los novios. Sin foto cae al logo de la empresa tintado en
  /// perla.
  Widget _portada(double s) {
    final lado = 150 * s;
    final url = cfg.imagenUrl;

    final Widget contenido = url != null
        ? ClipOval(
            child: Image.network(
              url,
              width: lado,
              height: lado,
              fit: BoxFit.cover,
              // Nunca dejamos un hueco: mientras baja, y si falla, se ve el logo.
              loadingBuilder: (context, child, progreso) =>
                  progreso == null ? child : _logoEmpresa(lado),
              errorBuilder: (_, _, _) => _logoEmpresa(lado),
            ),
          )
        : _logoEmpresa(lado);

    return FadeTransition(
      opacity: pulso.drive(
        // La foto se muestra plena; el logo mantiene su respiración tenue.
        Tween(begin: url != null ? 0.92 : 0.3, end: url != null ? 1.0 : 0.6),
      ),
      child: Container(
        width: lado,
        height: lado,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: url != null
              ? Border.all(color: _acento.withValues(alpha: 0.65), width: 3)
              : null,
          boxShadow: [
            BoxShadow(
              color: url != null
                  ? _acento.withValues(alpha: 0.28)
                  : _perla.withValues(alpha: 0.1),
              blurRadius: 40,
              spreadRadius: 10,
            ),
          ],
        ),
        child: contenido,
      ),
    );
  }

  Widget _logoEmpresa(double lado) => Image.asset(
        'assets/icons/logo-transparent-final.png',
        width: lado,
        height: lado,
        fit: BoxFit.contain,
        color: const Color(0xFFF2F0EB), // Plata Perla
        errorBuilder: (_, _, _) => Icon(
          Icons.celebration_rounded,
          size: lado * 0.6,
          color: const Color(0xFFF2F0EB),
        ),
      );

  /// El QR en un recuadro de vidrio, con el texto del evento.
  Widget _recuadroQr(String url, double s) {
    return AnimatedBuilder(
      animation: pulso,
      builder: (_, child) => Transform.scale(
        scale: 1.0 + (pulso.value * 0.02),
        child: child,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _perla.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 180 * s,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF121212),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF121212),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'BIENVENIDO',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: _perla,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cfg.mensajeQr,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 10 * s,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 2,
                    color: _perla.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
