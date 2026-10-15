import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dónde se suman ahora los celulares de la puerta. Lo dicen `/op` y Mi
/// Empresa → OPERADORES, donde antes se daba el link de `/op`.
const kCelularesDesdeRecepcion =
    'Los celulares de la puerta se suman desde Recepción → CELULARES.';

/// Lo que muestra `/op` desde la 6.0.0 (sección 8).
///
/// `/op` marcaba ingresos con un PIN que se comparaba en el celular y leía la
/// lista de la puerta sin usuario. Ya no andaba (la nube no le deja leer el
/// evento a quien no tiene usuario) y ningún evento tenía PIN. Los celulares
/// de la puerta van por la notebook central (sección 7).
class OpYaNoSeUsa extends StatelessWidget {
  const OpYaNoSeUsa({super.key});

  static const titulo = 'Esta página ya no se usa';
  static const explicacion =
      'Pedile al encargado el QR de CELULARES en la PC de la recepción.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_meeting_room_rounded,
                  color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                explicacion,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(fontSize: 15, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
