import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../models/totem_config.dart';
import 'fuentes_totem.dart';

// "Tu fondo" (`docs/PLAN_TU_FONDO_2026-10-23.md`): una imagen propia es el
// fondo del tótem. Acá está lo que se puede elegir —la animación de la imagen,
// los efectos que van encima y las letras— y cómo se lee de la config. Qué
// receta le toca a cada imagen lo decide `LecturaDelFondo`; cómo se dibuja,
// `FondoPropio` y `EscenaTuFondo`.

/// Lo que hace la imagen misma. **El orden importa:** el shader
/// (`totem_tu_fondo.frag`) recibe [index]. Una nueva va al final.
enum AnimacionFondo {
  quieta('quieta', 'Quieta', 'La imagen tal cual'),
  acercarse('acercarse', 'Acercarse', 'Se acerca despacio a lo importante'),
  recorrer('recorrer', 'Recorrer', 'Va y vuelve hacia lo importante'),
  flotar('flotar', 'Flotar', 'Flota y gira apenas'),
  respirar('respirar', 'Respirar', 'Late suave, en tamaño y en luz'),
  ondular('ondular', 'Ondular', 'Se mueve como agua');

  /// Lo que se guarda en `totem_config.fondo_animacion`.
  final String clave;
  final String nombre;
  final String explicacion;

  const AnimacionFondo(this.clave, this.nombre, this.explicacion);

  /// La de una imagen sin receta.
  static const porDefecto = AnimacionFondo.acercarse;

  static AnimacionFondo? desdeClave(String? clave) {
    final c = clave?.trim().toLowerCase();
    for (final a in values) {
      if (a.clave == c) return a;
    }
    return null;
  }

  /// La guardada; vacía o una que esta versión no conoce, [porDefecto].
  static AnimacionFondo de(String? clave) => desdeClave(clave) ?? porDefecto;
}

/// Lo que va encima de la imagen, sin tocarla. Se combinan.
enum EfectoFondo {
  destellos('destellos', 'Destellos', 'Chispas que suben'),
  polvo('polvo', 'Polvo de luz', 'Polvo fino que flota hacia arriba'),
  bokeh('bokeh', 'Bokeh', 'Luces desenfocadas que flotan'),
  titileo('titileo', 'Titileo', 'Puntos que se prenden y se apagan'),
  barrido('barrido', 'Barrido de luz', 'Una franja de luz que cruza'),
  marco('marco', 'Marco que respira', 'El borde se enciende y se apaga'),
  glitch('glitch', 'Glitch', 'Cortes y colores corridos, en ráfagas'),
  bruma('bruma', 'Bruma', 'Niebla de luz que pasa');

  /// Lo que se guarda, separado por comas, en `totem_config.fondo_efectos`.
  final String clave;
  final String nombre;
  final String explicacion;

  const EfectoFondo(this.clave, this.nombre, this.explicacion);

  /// Los de una imagen sin receta.
  static const porDefecto = [EfectoFondo.polvo];

  static EfectoFondo? desdeClave(String? clave) {
    final c = clave?.trim().toLowerCase();
    for (final e in values) {
      if (e.clave == c) return e;
    }
    return null;
  }

  /// Los guardados que esta versión conoce, sin repetir. Null (nunca se
  /// guardaron): [porDefecto]. Vacía: ninguno.
  static List<EfectoFondo> de(List<String>? claves) {
    if (claves == null) return porDefecto;
    final lista = <EfectoFondo>[];
    for (final c in claves) {
      final e = desdeClave(c);
      if (e != null && !lista.contains(e)) lista.add(e);
    }
    return lista;
  }
}

/// Una letra del tótem: la familia (de las que vienen con la app), el peso y
/// si va en cursiva.
typedef LetraFondo = ({String familia, FontWeight peso, FontStyle estilo});

/// Las letras de "Tu fondo". Todas vienen con la app (`fuentes_totem.dart`):
/// sin internet tienen que estar.
enum LetrasFondo {
  /// Cormorant Garamond: el título en serif y el saludo en cursiva.
  clasica(
    'clasica',
    'Clásica',
    (familia: FuentesTotem.gala, peso: FontWeight.w600, estilo: FontStyle.normal),
    (familia: FuentesTotem.gala, peso: FontWeight.w500, estilo: FontStyle.italic),
  ),

  /// Outfit liviana para el título y Cormorant en cursiva para el saludo.
  suave(
    'suave',
    'Suave',
    (familia: FuentesTotem.linea, peso: FontWeight.w400, estilo: FontStyle.normal),
    (familia: FuentesTotem.gala, peso: FontWeight.w500, estilo: FontStyle.italic),
  ),

  /// Oswald negrita y el saludo en letra de tubo (Tilt Neon).
  fiesta(
    'fiesta',
    'Fiesta',
    (
      familia: FuentesTotem.cartelera,
      peso: FontWeight.w700,
      estilo: FontStyle.normal,
    ),
    (familia: FuentesTotem.tubo, peso: FontWeight.w400, estilo: FontStyle.normal),
  ),

  /// Outfit con aire para el título y el saludo en letra de tubo.
  moderna(
    'moderna',
    'Moderna',
    (familia: FuentesTotem.linea, peso: FontWeight.w400, estilo: FontStyle.normal),
    (familia: FuentesTotem.tubo, peso: FontWeight.w400, estilo: FontStyle.normal),
  );

  /// Lo que se guarda en `totem_config.fondo_letras`.
  final String clave;
  final String nombre;

  /// El título, el nombre de la llegada y el número de la mesa.
  final LetraFondo titulo;

  /// El saludo.
  final LetraFondo saludo;

  const LetrasFondo(this.clave, this.nombre, this.titulo, this.saludo);

  static const porDefecto = LetrasFondo.clasica;

  static LetrasFondo? desdeClave(String? clave) {
    final c = clave?.trim().toLowerCase();
    for (final l in values) {
      if (l.clave == c) return l;
    }
    return null;
  }

  static LetrasFondo de(String? clave) => desdeClave(clave) ?? porDefecto;

  /// La palabra chica de arriba del título ("PROMOCIÓN"): en negrita, con la
  /// misma familia (Outfit en las que llevan Outfit).
  LetraFondo get chico => (
        familia: titulo.familia,
        peso: titulo.familia == FuentesTotem.cartelera
            ? FontWeight.w400
            : (titulo.familia == FuentesTotem.gala
                ? FontWeight.w600
                : FontWeight.w700),
        estilo: FontStyle.normal,
      );
}

/// Los tres colores de "Tu fondo": el brillo (el marco, el resplandor del
/// título, el borde del círculo, la mesa en el plano), el saludo y la tarjeta
/// de la llegada.
@immutable
class ColoresDelFondo {
  final Color brillo;
  final Color saludo;
  final Color tarjeta;

  const ColoresDelFondo(this.brillo, this.saludo, this.tarjeta);

  /// Los guardados con la imagen; sin ellos, salen del color del evento.
  factory ColoresDelFondo.de(TotemConfig cfg) {
    final p = cfg.fondoPaleta;
    if (p != null && p.length == 3) return ColoresDelFondo(p[0], p[1], p[2]);
    final a = cfg.colorAcento;
    return ColoresDelFondo(
      a,
      Color.lerp(a, const Color(0xFFFFFFFF), 0.55)!,
      Color.lerp(a, const Color(0xFF000000), 0.6)!,
    );
  }

  List<Color> get lista => [brillo, saludo, tarjeta];

  @override
  bool operator ==(Object other) =>
      other is ColoresDelFondo &&
      other.brillo == brillo &&
      other.saludo == saludo &&
      other.tarjeta == tarjeta;

  @override
  int get hashCode => Object.hash(brillo, saludo, tarjeta);
}

/// Si el texto va oscuro: la imagen es clara y casi no se oscurece (un fondo
/// pastel). Con [luz] de 0 a 100 y [oscurecer] de 0 a 80.
bool textoOscuroSobre({required int? luz, required int oscurecer}) =>
    (luz ?? 0) / 100 * (1 - 1.2 * oscurecer / 100) > 0.55;

/// Lo del fondo de [cfg], ya interpretado: lo que no se conoce va a lo de
/// siempre.
@immutable
class RecetaDibujada {
  final AnimacionFondo animacion;
  final List<EfectoFondo> efectos;

  /// De 0 a 1.
  final double intensidad;
  final double intensidadEfectos;
  final double oscurecer;

  final ColoresDelFondo colores;
  final Offset foco;
  final LetrasFondo letras;
  final bool textoOscuro;

  /// Para que dos imágenes no queden iguales (por dónde suben los destellos,
  /// para qué lado flota): sale de la dirección de la imagen.
  final int semilla;

  const RecetaDibujada({
    required this.animacion,
    required this.efectos,
    required this.intensidad,
    required this.intensidadEfectos,
    required this.oscurecer,
    required this.colores,
    required this.foco,
    required this.letras,
    required this.textoOscuro,
    required this.semilla,
  });

  factory RecetaDibujada.de(TotemConfig cfg) => RecetaDibujada(
        animacion: AnimacionFondo.de(cfg.fondoAnimacion),
        efectos: EfectoFondo.de(cfg.fondoEfectos),
        intensidad: cfg.fondoIntensidad.clamp(0, 100) / 100,
        intensidadEfectos: cfg.fondoIntensidadEfectos.clamp(0, 100) / 100,
        oscurecer:
            cfg.fondoOscurecer.clamp(0, TotemConfig.oscurecerMaximo) / 100,
        colores: ColoresDelFondo.de(cfg),
        foco: cfg.fondoFoco ?? const Offset(0.5, 0.5),
        letras: LetrasFondo.de(cfg.fondoLetras),
        textoOscuro: textoOscuroSobre(
          luz: cfg.fondoLuz,
          oscurecer: cfg.fondoOscurecer,
        ),
        semilla: semillaDe(cfg.fondoUrl),
      );

  bool tiene(EfectoFondo e) => efectos.contains(e);
}

/// Un número que sale siempre igual de [texto], en la PC y en la web
/// (`String.hashCode` no lo promete): FNV-1a de 32 bits.
///
/// El primo de FNV es 2²⁴ + 403, y se multiplica en dos partes: en la web los
/// enteros son de 53 bits y el producto entero no entra.
int semillaDe(String? texto) {
  var h = 0x811C9DC5;
  for (final c in (texto ?? '').codeUnits) {
    h = (h ^ c) & 0xFFFFFFFF;
    h = (h * 403 + ((h & 0xFF) << 24)) & 0xFFFFFFFF;
  }
  return h;
}
