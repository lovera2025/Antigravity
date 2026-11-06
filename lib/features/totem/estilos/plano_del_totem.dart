import 'package:flutter/painting.dart';

import '../../plano/estilos/estilo_plano.dart';
import '../services/plano_de_la_llegada.dart';
import 'fuentes_totem.dart';
import 'totem_estilo.dart';

/// El tema del salón en el tótem.
///
/// **Claro** (6.4.0, pedido del usuario: "colores bien claros, que se vean
/// bien las mesas y los números"): el salón entero se ve toda la espera, de
/// lejos y en una tele. Papel blanco hueso, mesas blancas con borde oscuro,
/// números negros y más grandes, y la mesa de la familia y el camino en
/// [acento] (el color del evento, o el brillo de la imagen en "Tu fondo"). Es
/// el mismo en las cinco apariencias: alrededor del salón sigue el fondo
/// animado de cada una.
///
/// [claro] en false da el de antes, vestido como la apariencia (Neón y Gala
/// de sus planos, Cristal sobre vidrio, Póster y "Tu fondo" con mesas
/// blancas sobre oscuro): queda para comparar en las muestras.
///
/// **Se arma una vez por apariencia y color.** `TemaPlano` no tiene `==`: uno
/// nuevo en cada cuadro haría redibujar el salón entero sesenta veces por
/// segundo.
TemaPlano temaPlanoDelTotem(
  EstiloTotem estilo,
  Color acento, {
  bool claro = true,
}) =>
    _guardados.putIfAbsent((claro ? null : estilo, acento.toARGB32()), () {
      final numero = acento.computeLuminance() > 0.35
          ? const Color(0xFF1A1406)
          : const Color(0xFFFFFFFF);
      if (claro) return _claroCon(acento, numeroEnFoco: numero);
      return switch (estilo) {
        EstiloTotem.neon => _con(
            TemaPlano.neon,
            fondo: const Color(0xD90A0F24),
            acento: acento,
            numeroEnFoco: numero,
            ruta: const Color(0xFFFFFFFF),
          ),
        EstiloTotem.gala => _con(
            TemaPlano.gala,
            fondo: const Color(0xD90B0A0D),
            acento: acento,
            numeroEnFoco: numero,
            ruta: Color.lerp(acento, const Color(0xFFFFFFFF), 0.35)!,
          ),
        EstiloTotem.cristal => _con(
            _cristal,
            fondo: const Color(0x2EFFFFFF),
            acento: acento,
            numeroEnFoco: numero,
            ruta: const Color(0xFFFFFFFF),
          ),
        EstiloTotem.poster => _con(
            _poster,
            fondo: const Color(0xCC0A0507),
            acento: acento,
            numeroEnFoco: numero,
            ruta: acento,
          ),
        // Sobre una imagen cualquiera: mesas blancas, como en Póster, sobre un
        // vidrio oscuro, y la mesa en el brillo de la imagen.
        EstiloTotem.tuFondo => _con(
            _poster,
            fondo: const Color(0xD10A0A0D),
            acento: acento,
            numeroEnFoco: numero,
            ruta: Color.lerp(acento, const Color(0xFFFFFFFF), 0.35)!,
          ),
      };
    });

final _guardados = <(EstiloTotem?, int), TemaPlano>{};

/// El salón claro con el color del evento en lo encendido.
///
/// Sobre el papel claro un color claro (el dorado de siempre) se pierde como
/// línea: el camino va en el mismo tono, oscurecido hasta que se lea.
TemaPlano _claroCon(Color acento, {required Color numeroEnFoco}) {
  final hsl = HSLColor.fromColor(acento);
  final camino = hsl.lightness > 0.42
      ? hsl.withLightness(0.36).toColor()
      : acento;
  return TemaPlano(
    estilo: _claro.estilo,
    fondo: _claro.fondo,
    hormigon: _claro.hormigon,
    hormigonBorde: _claro.hormigonBorde,
    sectorRelleno: _claro.sectorRelleno,
    sectorBorde: _claro.sectorBorde,
    sectorTexto: _claro.sectorTexto,
    escenario: _claro.escenario,
    escenarioTexto: _claro.escenarioTexto,
    mesaRelleno: _claro.mesaRelleno,
    mesaBorde: _claro.mesaBorde,
    mesaVacia: _claro.mesaVacia,
    numero: _claro.numero,
    numeroVacia: _claro.numeroVacia,
    divisiones: [acento],
    resaltado: acento,
    resaltadoNumero: numeroEnFoco,
    ruta: camino,
    pasto: _claro.pasto,
    conflicto: _claro.conflicto,
    titulo: _claro.titulo,
    tituloSuave: _claro.tituloSuave,
    fuente: _claro.fuente,
    pesoNumero: _claro.pesoNumero,
    escalaMesa: _claro.escalaMesa,
    escalaNumero: _claro.escalaNumero,
  );
}

/// El salón claro: el dibujo de Arquitecto (sin sillas ni grilla, que de lejos
/// ensucian), en blanco hueso.
const _claro = TemaPlano(
  estilo: EstiloPlano.arquitecto,
  fondo: Color(0xF7F6F3EC),
  hormigon: Color(0xFFFCFBF8),
  hormigonBorde: Color(0xFF9A9488),
  sectorRelleno: Color(0xFFE8E4DA),
  sectorBorde: Color(0xFFB3AC9D),
  sectorTexto: Color(0xFF524D43),
  escenario: Color(0xFF3B3833),
  escenarioTexto: Color(0xFFF6F3EC),
  mesaRelleno: Color(0xFFFFFFFF),
  mesaBorde: Color(0xFF4A463F),
  mesaVacia: Color(0xFF5E594F),
  numero: Color(0xFF1C1A16),
  numeroVacia: Color(0xFF1C1A16),
  divisiones: [Color(0xFF4A463F)],
  resaltado: Color(0xFF185FA5),
  resaltadoNumero: Color(0xFFFFFFFF),
  ruta: Color(0xFF185FA5),
  pasto: Color(0xFF3B6D11),
  conflicto: Color(0xFFA32D2D),
  titulo: Color(0xFF1C1A16),
  tituloSuave: Color(0xFF5E594F),
  fuente: FuentesPlano.linea,
  pesoNumero: FontWeight.w700,
  escalaMesa: 0.92,
  escalaNumero: 1.15,
);

/// [base] con el color del evento en lo encendido y una sola división, la de
/// la familia ([PlanoDeLaLlegada.division]).
TemaPlano _con(
  TemaPlano base, {
  required Color fondo,
  required Color acento,
  required Color numeroEnFoco,
  required Color ruta,
}) =>
    TemaPlano(
      estilo: base.estilo,
      fondo: fondo,
      grilla: null,
      // Más transparente que en su plano: se ve el fondo animado. Se
      // multiplica, no se fija: los de Cristal y Póster ya son casi
      // transparentes.
      hormigon: base.hormigon.withValues(alpha: base.hormigon.a * 0.55),
      hormigonBorde: base.hormigonBorde,
      sectorRelleno:
          base.sectorRelleno.withValues(alpha: base.sectorRelleno.a * 0.7),
      sectorBorde: base.sectorBorde,
      sectorTexto: base.sectorTexto,
      escenario: base.escenario,
      escenarioTexto: base.escenarioTexto,
      mesaRelleno: base.mesaRelleno,
      mesaBorde: base.mesaBorde,
      mesaVacia: base.mesaVacia,
      numero: base.numero,
      numeroVacia: base.numeroVacia,
      divisiones: [acento],
      resaltado: acento,
      resaltadoNumero: numeroEnFoco,
      ruta: ruta,
      pasto: base.pasto,
      conflicto: base.conflicto,
      titulo: base.titulo,
      tituloSuave: base.tituloSuave,
      fuente: base.fuente,
      pesoNumero: base.pesoNumero,
      brillo: base.brillo,
      escalaMesa: base.escalaMesa,
    );

/// Cristal: blanco sobre vidrio, con el brillo de Neón.
const _cristal = TemaPlano(
  estilo: EstiloPlano.neon,
  fondo: Color(0x2EFFFFFF),
  hormigon: Color(0x14FFFFFF),
  hormigonBorde: Color(0x66FFFFFF),
  sectorRelleno: Color(0x1AFFFFFF),
  sectorBorde: Color(0x8CFFFFFF),
  sectorTexto: Color(0xE6FFFFFF),
  escenario: Color(0xB3FFFFFF),
  escenarioTexto: Color(0xFF2B2373),
  mesaRelleno: Color(0x1FFFFFFF),
  mesaBorde: Color(0xE6FFFFFF),
  mesaVacia: Color(0x8CFFFFFF),
  numero: Color(0xFFFFFFFF),
  numeroVacia: Color(0xB3FFFFFF),
  divisiones: [Color(0xFFFFFFFF)],
  resaltado: Color(0xFFFFFFFF),
  resaltadoNumero: Color(0xFF2B2373),
  ruta: Color(0xFFFFFFFF),
  pasto: Color(0xFF8FD14F),
  conflicto: Color(0xFFFF4D5E),
  titulo: Color(0xFFFFFFFF),
  tituloSuave: Color(0xCCFFFFFF),
  fuente: FuentesTotem.linea,
  pesoNumero: FontWeight.w700,
  escalaMesa: 0.9,
);

/// Póster: mesas blancas, macizas, con la letra de cartel.
const _poster = TemaPlano(
  estilo: EstiloPlano.gala,
  fondo: Color(0xCC0A0507),
  hormigon: Color(0x14FFFFFF),
  hormigonBorde: Color(0x59FFFFFF),
  sectorRelleno: Color(0x14FFFFFF),
  sectorBorde: Color(0x73FFFFFF),
  sectorTexto: Color(0xD9FFFFFF),
  escenario: Color(0x8CFFFFFF),
  escenarioTexto: Color(0xFF1C0B12),
  mesaRelleno: Color(0x2EFFFFFF),
  mesaBorde: Color(0xFFFFFFFF),
  mesaVacia: Color(0x73FFFFFF),
  numero: Color(0xFFFFFFFF),
  numeroVacia: Color(0x99FFFFFF),
  divisiones: [Color(0xFFFFFFFF)],
  resaltado: Color(0xFFFFFFFF),
  resaltadoNumero: Color(0xFF1C0B12),
  ruta: Color(0xFFFFFFFF),
  pasto: Color(0xFF8FD14F),
  conflicto: Color(0xFFFF4D5E),
  titulo: Color(0xFFFFFFFF),
  tituloSuave: Color(0xCCFFFFFF),
  fuente: FuentesTotem.cartelera,
  pesoNumero: FontWeight.w700,
  escalaMesa: 0.92,
);
