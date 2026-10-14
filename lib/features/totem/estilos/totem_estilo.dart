import 'package:flutter/painting.dart';

import '../services/ficha_totem.dart';

/// Las cuatro apariencias del tótem, aprobadas el 24-sep
/// (`docs/pendientes/totem-apariencias.md`). Se elige una por evento en
/// Personalizar; si nadie eligió, va [EstiloTotem.porDefecto].
enum EstiloTotem {
  neon('neon', 'Neón'),
  cristal('cristal', 'Cristal'),
  poster('poster', 'Póster'),
  gala('gala', 'Gala');

  /// Lo que se guarda en `totem_config.estilo`.
  final String clave;
  final String nombre;

  const EstiloTotem(this.clave, this.nombre);

  /// El fondo animado de la apariencia (`pubspec.yaml`, `shaders:`).
  String get shader => 'shaders/totem_$clave.frag';

  /// Lo guardado, o null si está vacío o es algo que esta versión no conoce:
  /// en ese caso va la de siempre, nunca una pantalla rota.
  static EstiloTotem? desdeClave(String? clave) {
    final c = clave?.trim().toLowerCase();
    for (final e in values) {
      if (e.clave == c) return e;
    }
    return null;
  }

  /// Si nadie eligió: **Neón en un masivo, Cristal en un particular**. Si no
  /// se sabe el tipo (el tótem por el navegador no puede leerlo), Cristal.
  static EstiloTotem porDefecto({required bool? masivo}) =>
      masivo == true ? EstiloTotem.neon : EstiloTotem.cristal;
}

/// La apariencia con que se ve el tótem de un evento: la elegida en
/// Personalizar, o la del tipo de evento.
EstiloTotem estiloDelTotem({String? elegido, FichaTotem? ficha}) =>
    EstiloTotem.desdeClave(elegido) ??
    EstiloTotem.porDefecto(masivo: ficha?.masivo);

/// El segundo color de los neones: cian, o rosa si el color del evento es frío
/// (más azul que rojo, y el azul alto).
Color segundoNeon(Color principal) {
  final esFrio = principal.b > principal.r && principal.b > 0.6;
  return esFrio ? const Color(0xFFFF3CAC) : const Color(0xFF4FE3F0);
}

/// El título partido para la pantalla de espera: si tiene dos palabras, la
/// primera va chica y la segunda grande ("PROMOCIÓN" / "2026"). Si no, va
/// entero, grande.
({String? chico, String grande}) partirTitulo(String titulo) {
  final palabras =
      titulo.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (palabras.length == 2) {
    return (chico: palabras.first, grande: palabras.last);
  }
  return (chico: null, grande: titulo.trim());
}

/// Si el tótem muestra el QR.
///
/// **En un evento masivo, no** (sección 2): los alumnos no tienen DNI, y con
/// el QR a la vista cualquiera podía marcar a otro. En la ventana del
/// escritorio, hasta que llega la ficha no se sabe qué evento es, así que
/// tampoco. En la web no hay ficha que pedir: sigue como siempre, con el QR.
bool hayQrEnElTotem({
  required bool enLaVentanaDelEscritorio,
  required FichaTotem? ficha,
}) =>
    !enLaVentanaDelEscritorio || (ficha != null && !ficha.masivo);
