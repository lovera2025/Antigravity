import 'package:flutter/painting.dart';

import '../../plano/estilos/estilo_plano.dart';
import '../services/plano_de_la_llegada.dart';
import 'fuentes_totem.dart';
import 'totem_estilo.dart';

/// El tema del plano en la llegada del tótem: **se viste como la apariencia**,
/// no con el estilo que la fiesta eligió para el plano impreso. Neón y Gala
/// salen de sus planos; Cristal va con mesas blancas sobre vidrio, y Póster y
/// "Tu fondo" con mesas blancas. En todas, la mesa de la familia va en
/// [acento] (el color del evento, o el brillo de la imagen en "Tu fondo"), y
/// los colores de las divisiones no van: en la puerta importa una sola mesa.
///
/// El fondo es apenas transparente: se ve el fondo animado detrás.
///
/// **Se arma una vez por apariencia y color.** `TemaPlano` no tiene `==`: uno
/// nuevo en cada cuadro haría redibujar el salón entero sesenta veces por
/// segundo.
TemaPlano temaPlanoDelTotem(EstiloTotem estilo, Color acento) =>
    _guardados.putIfAbsent((estilo, acento.toARGB32()), () {
      final numero = acento.computeLuminance() > 0.35
          ? const Color(0xFF1A1406)
          : const Color(0xFFFFFFFF);
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

final _guardados = <(EstiloTotem, int), TemaPlano>{};

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
