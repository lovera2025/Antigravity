import '../../../models/invitado.dart';
import '../../../models/totem_config.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import 'bienvenidas_totem.dart';
import 'ficha_totem.dart';

/// Lo que dice la tarjeta de bienvenida del tótem. Sin pantalla: la tarjeta
/// solo lo dibuja.
///
/// - **Una familia de un masivo:** el alumno en grande y "con GÓMEZ, ANA y
///   PÉREZ, LUIS" debajo; la mesa; la música si está cargada y prendida en
///   Personalizar. **Sin las sillas** (6.4.0, pedido del usuario): en el salón
///   importa el nombre y la mesa; las sillas las ve la recepcionista.
/// - **Un acompañante que llega sin el alumno:** su nombre y "acompaña a
///   PÉREZ, JUAN MARTÍN".
/// - **Sin mesa** (un masivo sin sortear, o un alumno que quedó sin mesa): el
///   saludo sin mesa. En el salón nunca se dice "sin mesa".
/// - **Un particular, o alguien que la ficha no tiene:** el nombre y la mesa de
///   su fila en la lista de la puerta, como siempre.
class ContenidoBienvenida {
  final String saludo;

  /// Los nombres en grande: el alumno, o los que llegaron sin él.
  final List<String> nombres;

  /// "con GÓMEZ, ANA y PÉREZ, LUIS".
  final String? conQuien;

  /// "acompaña a PÉREZ, JUAN MARTÍN".
  final String? acompanaA;

  /// "12", "14-15". Null: el saludo va sin mesa.
  final String? mesa;

  /// "Mesa" o "Mesas".
  final String rotuloMesa;

  /// "Tusa · Karol G".
  final String? musica;

  const ContenidoBienvenida({
    required this.saludo,
    required this.nombres,
    this.conQuien,
    this.acompanaA,
    this.mesa,
    this.rotuloMesa = 'Mesa',
    this.musica,
  });

  factory ContenidoBienvenida.armar(
    BienvenidaTotem bienvenida, {
    FichaTotem? ficha,
    required TotemConfig cfg,
  }) {
    final personas = bienvenida.personas;
    PersonaFicha? deFicha(Invitado i) => ficha?.de(i.id);
    String nombreDe(Invitado i) =>
        (deFicha(i)?.nombre ?? i.nombreCompleto).trim();

    final alumno = personas.where((i) => deFicha(i)?.esAlumno ?? false);
    final titular = alumno.isEmpty ? null : alumno.first;
    final otros = [
      for (final i in personas)
        if (!identical(i, titular)) i,
    ];

    final List<String> nombres;
    String? conQuien;
    String? acompanaA;
    if (titular != null) {
      nombres = [nombreDe(titular)];
      if (otros.isNotEmpty) {
        conQuien = 'con ${_enumerar([for (final i in otros) nombreDe(i)])}';
      }
    } else {
      nombres = [for (final i in personas) nombreDe(i)];
      // Acompañantes que llegaron sin el alumno: con quién vienen.
      final aQuien = {
        for (final i in personas) ?deFicha(i)?.titular,
      };
      if (aQuien.length == 1) {
        acompanaA = personas.length > 1
            ? 'acompañan a ${aQuien.single}'
            : 'acompaña a ${aQuien.single}';
      }
    }

    // La mesa es de la familia. Si la persona está en la ficha, manda la
    // ficha, también cuando dice que no tiene mesa: la fila puede traer una
    // mesa de un sorteo que ya se deshizo.
    final primera = personas.isEmpty ? null : personas.first;
    final p = titular != null
        ? deFicha(titular)
        : (primera == null ? null : deFicha(primera));
    final String? mesa;
    if (p != null) {
      mesa = p.mesa;
    } else {
      final enLaFila = primera?.numeroMesa?.trim() ?? '';
      mesa = enLaFila.isEmpty ? null : enLaFila;
    }

    final musica = (cfg.mostrarMusica && titular != null)
        ? deFicha(titular)?.musica
        : null;

    final saludo =
        personas.length > 1 && cfg.mensajeBienvenida == TotemConfig.saludoPorDefecto
            ? '¡Bienvenidos!'
            : cfg.mensajeBienvenida;

    return ContenidoBienvenida(
      saludo: saludo,
      nombres: nombres,
      conQuien: conQuien,
      acompanaA: acompanaA,
      mesa: mesa,
      rotuloMesa:
          MesasExtraUtils.numerosMesaDesdeTexto(mesa).length > 1 ? 'Mesas' : 'Mesa',
      musica: musica,
    );
  }

  /// "A", "A y B", "A · B y C". Sin comas entre nombres: los nombres ya
  /// llevan una ("PÉREZ, JUAN").
  static String _enumerar(List<String> nombres) {
    if (nombres.length < 2) return nombres.join();
    return '${nombres.sublist(0, nombres.length - 1).join(' · ')} '
        'y ${nombres.last}';
  }
}
