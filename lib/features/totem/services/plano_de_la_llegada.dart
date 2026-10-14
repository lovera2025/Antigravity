import '../../eventos/services/mesas_extra_utils.dart';
import '../../plano/modelo/armado_salon.dart';
import '../../plano/modelo/estado_plano.dart';

/// Lo que el tótem dibuja del salón cuando llega una familia de un evento
/// masivo: la hoja de su mesa, con su mesa (o sus mesas) encendida.
///
/// Sin pantalla ni base. Lo arma la escena una vez por llegada.
class PlanoDeLaLlegada {
  final ArmadoSalon armado;

  /// La hoja de la mesa principal: es la que se ve.
  final String hoja;

  /// Las mesas de la familia en esa hoja: se encienden.
  final Set<int> mesas;

  /// La principal: la que lleva el apellido y adonde llega el camino.
  final int principal;

  /// El salón con un solo ocupante, la familia. Uno por familia y no por fila
  /// de la lista de la puerta: cada acompañante es una fila con la misma mesa,
  /// y dos ocupantes en una mesa son un "conflicto".
  final EstadoPlano estado;

  const PlanoDeLaLlegada._({
    required this.armado,
    required this.hoja,
    required this.mesas,
    required this.principal,
    required this.estado,
  });

  /// La división con que va la familia: el tema del tótem le da el color del
  /// evento.
  static const division = 'llegada';

  /// Null si no hay qué mostrar: sin plano, sin mesa (antes del sorteo) o con
  /// un número que el plano no tiene (uno cargado a mano).
  static PlanoDeLaLlegada? para(
    ArmadoSalon? armado, {
    required String? mesa,
    required String nombre,
  }) {
    if (armado == null) return null;
    final enElPlano = [
      for (final n in MesasExtraUtils.numerosMesaDesdeTexto(mesa))
        if (armado.existe(n)) n,
    ];
    final principal = OcupantePlano.principalDe(enElPlano);
    if (principal == null) return null;
    final hoja = armado.mesa(principal)!.hoja;
    final familia = OcupantePlano(
      id: 'llegada',
      nombre: nombre,
      numeros: enElPlano,
      division: division,
    );
    return PlanoDeLaLlegada._(
      armado: armado,
      hoja: hoja,
      mesas: {
        for (final n in enElPlano)
          if (armado.mesa(n)!.hoja == hoja) n,
      },
      principal: principal,
      estado: EstadoPlano.desde(armado: armado, ocupantes: [familia]),
    );
  }
}
