import 'package:flutter/material.dart';

/// Los tres estilos del plano. Cada fiesta elige el suyo; se usa en la
/// pantalla, en el tótem (diciembre) y define cómo se dibuja el papel.
enum EstiloPlano {
  gala,
  arquitecto,
  neon;

  String get nombre => switch (this) {
        EstiloPlano.gala => 'Gala',
        EstiloPlano.arquitecto => 'Arquitecto',
        EstiloPlano.neon => 'Neón',
      };

  String get descripcion => switch (this) {
        EstiloPlano.gala => 'Negro y dorado, con serif',
        EstiloPlano.arquitecto => 'Claro y preciso, con sillas',
        EstiloPlano.neon => 'Luz de fiesta por división',
      };

  /// Lo que se guarda en la base. Un valor desconocido no se rompe: queda sin
  /// estilo y la pantalla pide elegir.
  static EstiloPlano? deClave(String? clave) {
    for (final e in EstiloPlano.values) {
      if (e.name == clave) return e;
    }
    return null;
  }
}

/// Familias de letra registradas en `pubspec.yaml` (y en los tests con
/// `cargarFuentesPlano()`).
class FuentesPlano {
  FuentesPlano._();
  static const gala = 'PlanoGala';
  static const neon = 'PlanoNeon';
  static const linea = 'PlanoLinea';
}

/// Todo lo que hace falta para dibujar el plano en un estilo: colores, letra y
/// qué adornos lleva. El dibujo no decide colores por su cuenta.
@immutable
class TemaPlano {
  final EstiloPlano estilo;
  final Color fondo;

  /// Grilla de fondo (Arquitecto y Neón). Null: sin grilla.
  final Color? grilla;

  /// El piso de hormigón del playón y su borde (armados a medida).
  final Color hormigon;
  final Color hormigonBorde;
  final Color sectorRelleno;
  final Color sectorBorde;
  final Color sectorTexto;
  final Color escenario;
  final Color escenarioTexto;
  final Color mesaRelleno;
  final Color mesaBorde;
  final Color mesaVacia;
  final Color numero;
  final Color numeroVacia;

  /// Un color por división, en el orden de la leyenda. Se repiten si hay más
  /// divisiones que colores.
  final List<Color> divisiones;

  /// Arquitecto: el número va en el tono oscuro de su división.
  final List<Color>? numeroDivision;
  final Color resaltado;
  final Color resaltadoNumero;
  final Color ruta;
  final Color pasto;
  final Color conflicto;
  final Color titulo;
  final Color tituloSuave;
  final String fuente;
  final FontWeight pesoNumero;

  /// Arquitecto dibuja las 8 sillas de cada mesa (y las extra).
  final bool sillas;

  /// Neón y Gala llevan brillo en los anillos.
  final bool brillo;

  /// Cuánto del radio de la mesa se usa al dibujarla (Arquitecto achica la
  /// mesa para que entren las sillas sin tocarse).
  final double escalaMesa;

  const TemaPlano({
    required this.estilo,
    required this.fondo,
    this.grilla,
    required this.hormigon,
    required this.hormigonBorde,
    required this.sectorRelleno,
    required this.sectorBorde,
    required this.sectorTexto,
    required this.escenario,
    required this.escenarioTexto,
    required this.mesaRelleno,
    required this.mesaBorde,
    required this.mesaVacia,
    required this.numero,
    required this.numeroVacia,
    required this.divisiones,
    this.numeroDivision,
    required this.resaltado,
    required this.resaltadoNumero,
    required this.ruta,
    required this.pasto,
    required this.conflicto,
    required this.titulo,
    required this.tituloSuave,
    required this.fuente,
    required this.pesoNumero,
    this.sillas = false,
    this.brillo = false,
    this.escalaMesa = 0.92,
  });

  Color colorDivision(int? i) =>
      i == null || i < 0 ? mesaBorde : divisiones[i % divisiones.length];

  Color numeroDeDivision(int? i) {
    final l = numeroDivision;
    if (l == null || i == null || i < 0) return numero;
    return l[i % l.length];
  }

  // ── En papel ────────────────────────────────────────────────────────────
  //
  // El plano impreso va siempre sobre blanco, con el número oscuro. Lo que no
  // puede cambiar es el color: el que la fiesta eligió para una división es el
  // que tiene que salir. Antes la hoja usaba siempre la paleta de Arquitecto
  // por posición, y en una fiesta en Gala el verde salía celeste.

  /// El relleno de cada división en la hoja, en el mismo orden que
  /// [divisiones]: el mismo color, en su tono claro. Arquitecto ya es de tonos
  /// claros y sale tal cual.
  List<Color> get papel => estilo == EstiloPlano.arquitecto
      ? divisiones
      : [for (final c in divisiones) enPapel(c)];

  /// El anillo y el número de cada división en la hoja: el mismo color, oscuro.
  List<Color> get papelNumero =>
      (estilo == EstiloPlano.arquitecto ? numeroDivision : null) ??
      [for (final c in divisiones) tintaDePapel(c)];

  /// Un color de pantalla llevado a papel blanco: conserva el tono, y se aclara
  /// hasta que un número oscuro se lea encima.
  ///
  /// El más fuerte en pantalla sale más fuerte en papel (el rubí de Gala y su
  /// cuarzo rosa tienen el mismo tono, y así siguen siendo dos). Un neutro (la
  /// perla) queda neutro.
  static Color enPapel(Color c) {
    final hsl = HSLColor.fromColor(c);
    final t = ((hsl.lightness - 0.45) / 0.45).clamp(0.0, 1.0);
    final s = hsl.saturation;
    return hsl
        .withLightness(0.80 + 0.12 * t)
        .withSaturation(
          s < _neutro ? s : (s * (0.95 - 0.25 * t)).clamp(0.35, 0.85),
        )
        .toColor();
  }

  /// El mismo color, oscuro: para el anillo y el número sobre [enPapel].
  static Color tintaDePapel(Color c) {
    final hsl = HSLColor.fromColor(c);
    final s = hsl.saturation;
    return hsl
        .withLightness(0.24)
        .withSaturation(s < _neutro ? s : s.clamp(0.50, 0.85))
        .toColor();
  }

  /// Con menos color que esto es un gris: no se le inventa un tono.
  static const double _neutro = 0.12;

  /// El mismo tema con los colores de las divisiones elegidos por la fiesta:
  /// la división `i` de la leyenda lleva el color [indices]`[i]` de la paleta.
  ///
  /// Con la lista vacía, o con cada división en el color de su lugar, devuelve
  /// este mismo tema.
  TemaPlano conColores(List<int> indices) {
    final n = divisiones.length;
    var cambia = false;
    for (final (i, k) in indices.indexed) {
      if (k % n != i % n) cambia = true;
    }
    if (!cambia) return this;
    List<Color> elegir(List<Color> paleta) => [
          for (final k in indices) paleta[k % paleta.length],
        ];
    final numeros = numeroDivision;
    return TemaPlano(
      estilo: estilo,
      fondo: fondo,
      grilla: grilla,
      hormigon: hormigon,
      hormigonBorde: hormigonBorde,
      sectorRelleno: sectorRelleno,
      sectorBorde: sectorBorde,
      sectorTexto: sectorTexto,
      escenario: escenario,
      escenarioTexto: escenarioTexto,
      mesaRelleno: mesaRelleno,
      mesaBorde: mesaBorde,
      mesaVacia: mesaVacia,
      numero: numero,
      numeroVacia: numeroVacia,
      divisiones: elegir(divisiones),
      numeroDivision: numeros == null ? null : elegir(numeros),
      resaltado: resaltado,
      resaltadoNumero: resaltadoNumero,
      ruta: ruta,
      pasto: pasto,
      conflicto: conflicto,
      titulo: titulo,
      tituloSuave: tituloSuave,
      fuente: fuente,
      pesoNumero: pesoNumero,
      sillas: sillas,
      brillo: brillo,
      escalaMesa: escalaMesa,
    );
  }

  static TemaPlano de(EstiloPlano e) => switch (e) {
        EstiloPlano.gala => gala,
        EstiloPlano.arquitecto => arquitecto,
        EstiloPlano.neon => neon,
      };

  static const gala = TemaPlano(
    estilo: EstiloPlano.gala,
    fondo: Color(0xFF0B0A0D),
    hormigon: Color(0xFF131116),
    hormigonBorde: Color(0xFF4F4026),
    sectorRelleno: Color(0xFF16130F),
    sectorBorde: Color(0xFF7A6238),
    sectorTexto: Color(0xFFC9AA6B),
    escenario: Color(0xFFC9A45C),
    escenarioTexto: Color(0xFF1A1406),
    mesaRelleno: Color(0xFF17141A),
    mesaBorde: Color(0xFFC9A45C),
    mesaVacia: Color(0xFF5C4B2C),
    numero: Color(0xFFF2E4C0),
    numeroVacia: Color(0xFF8A7650),
    // Joyas: esmeralda, zafiro, rubí, amatista, turquesa, peridoto, cuarzo
    // rosa, perla. Ninguna dorada (se confundía con el anillo) ni roja (es el
    // color del conflicto).
    divisiones: [
      Color(0xFF3FAF7F),
      Color(0xFF5B83D6),
      Color(0xFFD94FA3),
      Color(0xFFA27BD8),
      Color(0xFF4CC3C1),
      Color(0xFF8FD14F),
      Color(0xFFE89AC7),
      Color(0xFFE9E3D5),
    ],
    resaltado: Color(0xFFE6C47E),
    resaltadoNumero: Color(0xFF1A1406),
    ruta: Color(0xFFE6C47E),
    pasto: Color(0xFF6E8F4E),
    conflicto: Color(0xFFE0525E),
    titulo: Color(0xFFF2E4C0),
    tituloSuave: Color(0xFFC2A567),
    fuente: FuentesPlano.gala,
    pesoNumero: FontWeight.w600,
    brillo: true,
    escalaMesa: 0.92,
  );

  static const arquitecto = TemaPlano(
    estilo: EstiloPlano.arquitecto,
    fondo: Color(0xFFF7F5F0),
    hormigon: Color(0xFFFCFBF8),
    hormigonBorde: Color(0xFF888780),
    grilla: Color(0xFFE6E3DA),
    sectorRelleno: Color(0xFFECE9E1),
    sectorBorde: Color(0xFFB4B2A9),
    sectorTexto: Color(0xFF5F5E5A),
    escenario: Color(0xFF444441),
    escenarioTexto: Color(0xFFF7F5F0),
    mesaRelleno: Color(0xFFFFFFFF),
    mesaBorde: Color(0xFF444441),
    mesaVacia: Color(0xFFB4B2A9),
    numero: Color(0xFF2C2C2A),
    numeroVacia: Color(0xFF888780),
    divisiones: [
      Color(0xFFCFE3F4),
      Color(0xFFF6D5C8),
      Color(0xFFD8EDD3),
      Color(0xFFEADCF3),
      Color(0xFFFBEFC4),
      Color(0xFFD3EEEC),
      Color(0xFFF3D9E6),
      Color(0xFFE3E3E3),
    ],
    numeroDivision: [
      Color(0xFF0C447C),
      Color(0xFF712B13),
      Color(0xFF27500A),
      Color(0xFF3C3489),
      Color(0xFF633806),
      Color(0xFF085041),
      Color(0xFF72243E),
      Color(0xFF444441),
    ],
    resaltado: Color(0xFF185FA5),
    resaltadoNumero: Color(0xFFFFFFFF),
    ruta: Color(0xFF185FA5),
    pasto: Color(0xFF3B6D11),
    conflicto: Color(0xFFA32D2D),
    titulo: Color(0xFF2C2C2A),
    tituloSuave: Color(0xFF5F5E5A),
    fuente: FuentesPlano.linea,
    pesoNumero: FontWeight.w700,
    sillas: true,
    escalaMesa: 0.8,
  );

  static const neon = TemaPlano(
    estilo: EstiloPlano.neon,
    fondo: Color(0xFF0A0F24),
    hormigon: Color(0xFF0D1432),
    hormigonBorde: Color(0xFF3A4585),
    grilla: Color(0xFF151C3D),
    sectorRelleno: Color(0xFF0E1433),
    sectorBorde: Color(0xFF5B52E0),
    sectorTexto: Color(0xFFA9AFFF),
    escenario: Color(0xFF6D5CFF),
    escenarioTexto: Color(0xFF0A0F24),
    mesaRelleno: Color(0xFF0B1030),
    // Un neutro propio: una familia sin división no se confunde con la 1.ª.
    mesaBorde: Color(0xFFC8CDF0),
    mesaVacia: Color(0xFF2B335E),
    numero: Color(0xFFEEF8FF),
    numeroVacia: Color(0xFF5B6391),
    // La 7.ª es azul y no coral: el rojo queda para el conflicto.
    divisiones: [
      Color(0xFF4FE3F0),
      Color(0xFFFF3CAC),
      Color(0xFFB6FF3B),
      Color(0xFFFFB03B),
      Color(0xFFA974FF),
      Color(0xFFFFF35C),
      Color(0xFF3D8BFF),
      Color(0xFF7CF5C4),
    ],
    resaltado: Color(0xFFFFFFFF),
    resaltadoNumero: Color(0xFF0A0F24),
    ruta: Color(0xFFFFFFFF),
    pasto: Color(0xFF5BD65B),
    conflicto: Color(0xFFFF4D5E),
    titulo: Color(0xFFFFFFFF),
    // Los apellidos van en un neutro, no en el color de una división.
    tituloSuave: Color(0xFFA9AFFF),
    fuente: FuentesPlano.neon,
    pesoNumero: FontWeight.w400,
    brillo: true,
    escalaMesa: 0.9,
  );
}

/// Cuánto detalle entra según el tamaño en pantalla de una mesa (en píxeles).
/// Función pura, con test: el mismo plano sirve para una miniatura, la
/// pantalla y el tótem.
@immutable
class NivelDetalle {
  final bool numeros;
  final bool sillas;
  final bool adornos;
  final bool etiquetas;
  final bool apellidos;

  const NivelDetalle({
    required this.numeros,
    required this.sillas,
    required this.adornos,
    required this.etiquetas,
    required this.apellidos,
  });

  static NivelDetalle para(double radioPx) => NivelDetalle(
        numeros: radioPx >= 9,
        sillas: radioPx >= 12,
        adornos: radioPx >= 12,
        etiquetas: radioPx >= 8,
        apellidos: radioPx >= 26,
      );
}
