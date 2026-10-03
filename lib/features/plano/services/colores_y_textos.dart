import '../../../models/plano_evento.dart';
import '../modelo/armado_salon.dart';
import 'cambios_de_mesa.dart';

/// Lo que se elige en Personalizar → Colores y textos: el color de cada
/// división, el título y el subtítulo del plano, y los textos de los sectores.
///
/// Todo es cuenta pura: no lee ni guarda nada.
class ColoresYTextos {
  /// División (la clave de `Divisiones.clave`) → índice en la paleta del
  /// estilo. Las que no figuran llevan el color de su lugar en la leyenda.
  final Map<String, int> colores;

  /// Vacío: el plano no lleva título.
  final String titulo;
  final String subtitulo;

  /// Los sectores a los que se les cambia el texto, cada uno como está hoy en
  /// el armado, con su texto nuevo.
  final List<({SectorPlano sector, String texto})> sectores;

  const ColoresYTextos({
    this.colores = const {},
    this.titulo = '',
    this.subtitulo = '',
    this.sectores = const [],
  });

  static const int largoTitulo = 60;
  static const int largoSubtitulo = 90;
  static const int largoSector = 40;

  /// Lo que tiene guardado el plano de la fiesta.
  factory ColoresYTextos.de(ConfigPlano config) => ColoresYTextos(
        colores: config.colores,
        titulo: config.titulo?.trim() ?? '',
        subtitulo: config.subtitulo?.trim() ?? '',
      );

  /// Cambia si cambia algo de lo que esta pestaña muestra. Quien la dibuja la
  /// mira para saber si lo guardado es otro (se guardó, o bajó de la otra PC).
  static String firmaDe(ConfigPlano config, List<SectorPlano> sectores) {
    final colores = config.colores.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final e in colores) '${e.key}=${e.value}',
      '|${config.titulo?.trim() ?? ''}|${config.subtitulo?.trim() ?? ''}|',
      for (final s in sectores) '${s.tipo.name}:${s.hoja}:${s.texto}',
    ].join(';');
  }

  static bool _mismoSector(SectorPlano a, SectorPlano b) =>
      a.tipo == b.tipo &&
      a.hoja == b.hoja &&
      a.caja == b.caja &&
      a.texto == b.texto &&
      a.vertical == b.vertical;

  /// ¿Es lo mismo que ya está guardado?
  bool igualA(ConfigPlano config) {
    final guardado = ColoresYTextos.de(config);
    if (titulo != guardado.titulo || subtitulo != guardado.subtitulo) {
      return false;
    }
    if (sectores.isNotEmpty) return false;
    if (colores.length != guardado.colores.length) return false;
    for (final e in colores.entries) {
      if (guardado.colores[e.key] != e.value) return false;
    }
    return true;
  }

  /// El armado con los textos nuevos de los sectores. Null si alguno de los
  /// sectores ya no está como se lo vio (la otra PC acomodó el salón): un
  /// texto no se le pone a otro sector por las dudas.
  ArmadoSalon? armadoCon(ArmadoSalon armado) {
    if (sectores.isEmpty) return armado;
    final nuevos = [...armado.sectores];
    for (final cambio in sectores) {
      final i = nuevos.indexWhere((s) => _mismoSector(s, cambio.sector));
      if (i < 0) return null;
      nuevos[i] = nuevos[i].copyWith(texto: cambio.texto.trim());
    }
    return armado.copyWith(sectores: nuevos);
  }

  /// La configuración con los colores y los títulos. Lo demás (mesas fijas,
  /// libres, bloques, medidas) queda como está.
  ConfigPlano configCon(ConfigPlano config) => config.copyWith(
        colores: Map.unmodifiable(colores),
        titulo: titulo.trim(),
        subtitulo: subtitulo.trim(),
        borrarTitulo: titulo.trim().isEmpty,
        borrarSubtitulo: subtitulo.trim().isEmpty,
      );

  /// El cambio listo para guardar sobre el plano que hay de verdad, o por qué
  /// no se puede.
  CambioDeConfig aplicar(ArmadoSalon armado, ConfigPlano config) {
    final nuevo = armadoCon(armado);
    if (nuevo == null) {
      return const CambioDeConfig.noSePuede(
        'El salón cambió en la otra PC y uno de los sectores ya no está como '
        'se veía. Los textos no se guardaron: revisalos y probá de nuevo.',
      );
    }
    return CambioDeConfig.ok(
      configCon(config),
      const [],
      armado: identical(nuevo, armado) ? null : nuevo,
    );
  }
}
