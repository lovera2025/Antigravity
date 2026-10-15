import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// El aviso de que el tótem no puede leer la nube.
///
/// Va en la barra del operador, la que aparece al mover el mouse sobre el
/// tótem. Antes era un cartel rojo "Reconectando..." a la vista del salón: al
/// público no le dice nada, y mientras tanto el tótem sigue saludando a los
/// que se marcan en esa PC.
class AvisoSinInternet extends StatelessWidget {
  /// El tótem corre en su ventana, en la PC de Recepción: sin internet, lo que
  /// se marca en esa PC le sigue llegando por el puente entre ventanas. En la
  /// web no hay puente.
  final bool conPuente;

  /// El tótem por el navegador se abrió con un link sin la clave del tótem
  /// (sección 8 de la 6.0.0): sin ella no puede leer la lista. No es un corte:
  /// hay que abrir el link que da la PC.
  final bool sinClave;

  const AvisoSinInternet({
    super.key,
    required this.conPuente,
    this.sinClave = false,
  });

  static const sigueAvisando = 'Sin internet: esta PC sigue avisando al tótem';
  static const reconectando = 'Sin internet: reconectando';
  static const faltaLaClave =
      'Falta la clave: abrí el link de Personalizar tótem, en la PC';

  static const _color = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _color.withValues(alpha: 0.55), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sinClave ? Icons.key_off_rounded : Icons.cloud_off_rounded,
            color: _color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              sinClave
                  ? faltaLaClave
                  : conPuente
                      ? sigueAvisando
                      : reconectando,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Negrita y no seminegrita: es el peso que viene con la app. El
              // otro habría que bajarlo de internet justo cuando no hay.
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
