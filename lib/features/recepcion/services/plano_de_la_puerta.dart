import '../../../models/invitado.dart';
import '../../../models/totem_config.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../plano/modelo/armado_salon.dart';
import '../../plano/modelo/estado_plano.dart';
import '../../totem/services/bienvenidas_totem.dart';
import '../../totem/services/cuadro_del_salon.dart';
import '../../totem/services/plano_de_la_llegada.dart';
import 'puerta_del_evento.dart';

/// Lo que la puerta muestra del salón (6.5.0, pedido del usuario el 9-nov): la
/// recepcionista toca una familia y ve, **en su pantalla**, el salón con su mesa
/// encendida y el camino desde el Ingreso, y si quiere vuelve a ver la llegada
/// como en la tele. La tele del salón no se entera de nada de esto.
///
/// Sin pantalla ni base: el salón y la config los pone `salonDeLaPuertaProvider`
/// (en la PC, de la base; en el celular, de la central).
class SalonParaLaPuerta {
  final ArmadoSalon armado;

  /// La del tótem de esa noche: la apariencia, el color y los segundos de la
  /// llegada. En el celular va sin foto ni fondo propio (no hay internet).
  final TotemConfig cfg;

  const SalonParaLaPuerta({required this.armado, required this.cfg});

  /// El salón, si tiene mesas: sin mesas no hay nada que mostrar.
  static SalonParaLaPuerta? de(ArmadoSalon? armado, TotemConfig cfg) =>
      armado == null || armado.mesas.isEmpty
          ? null
          : SalonParaLaPuerta(armado: armado, cfg: cfg);

  /// La config como viaja al celular: sin la foto ni el fondo, que están en
  /// internet. Con "Tu fondo" sin imagen, el tótem usa la apariencia del tipo.
  static Map<String, dynamic> cfgParaElCelular(TotemConfig cfg) =>
      cfg.toJson()
        ..['imagen_url'] = null
        ..['fondo_url'] = null;

  /// Si [g] tiene alguna mesa que el plano tiene. Barato: se pregunta por cada
  /// tarjeta de la lista, sin buscar el camino.
  bool tieneMesaDe(GrupoPuerta g) => MesasExtraUtils.numerosMesaDesdeTexto(
        g.titular.mesa,
      ).any(armado.existe);

  /// La familia en el salón, como en la llegada del tótem: su mesa encendida y
  /// el camino. Null sin mesa (antes del sorteo) o con un número que el plano
  /// no tiene (uno cargado a mano).
  PlanoDeLaLlegada? deLaFamilia(GrupoPuerta g) => PlanoDeLaLlegada.para(
        armado,
        mesa: g.titular.mesa,
        nombre: g.titular.nombre,
      );

  /// La bienvenida de [g], para volver a verla: el titular, como lo saluda el
  /// tótem (con la ficha, sale la familia y su mesa).
  static BienvenidaTotem llegadaDe(
    String eventoId,
    GrupoPuerta g,
    DateTime ahora,
  ) {
    final t = g.titular;
    return BienvenidaTotem(
      familia: t.id,
      personas: [
        t.fila ??
            Invitado(
              id: t.id,
              eventoId: eventoId,
              nombreCompleto: t.nombre,
              dni: t.dni,
              numeroMesa: t.mesa,
              estadoIngreso: EstadoIngreso.ingresado,
            ),
      ],
      empezo: ahora,
    );
  }

  /// El salón entero, con cada familia en su mesa.
  SalonEntero entero(PuertaDelEvento puerta) => SalonEntero.de(armado, puerta);
}

/// El salón entero como lo ve la puerta: cada familia en su mesa, y cuáles
/// faltan entrar.
class SalonEntero {
  /// La hoja que se abre: la del Ingreso, como en la tele.
  final String hoja;
  final EstadoPlano estado;

  /// De quién es cada mesa del plano.
  final Map<int, GrupoPuerta> familiaDeMesa;

  /// Las mesas de las familias en las que todavía no entró nadie.
  final Set<int> faltan;

  /// Cuántas familias faltan.
  final int familiasQueFaltan;

  const SalonEntero._({
    required this.hoja,
    required this.estado,
    required this.familiaDeMesa,
    required this.faltan,
    required this.familiasQueFaltan,
  });

  factory SalonEntero.de(ArmadoSalon armado, PuertaDelEvento puerta) {
    final ocupantes = <OcupantePlano>[];
    final familiaDeMesa = <int, GrupoPuerta>{};
    final faltan = <int>{};
    var familiasQueFaltan = 0;
    for (final g in puerta.grupos) {
      final numeros = [
        for (final n in MesasExtraUtils.numerosMesaDesdeTexto(g.titular.mesa))
          if (armado.existe(n)) n,
      ];
      if (numeros.isEmpty) continue;
      ocupantes.add(OcupantePlano(
        id: g.titular.id,
        nombre: g.titular.nombre,
        numeros: numeros,
        division: g.division,
      ));
      for (final n in numeros) {
        familiaDeMesa.putIfAbsent(n, () => g);
      }
      if (!g.personas.any((p) => p.ingresado)) {
        faltan.addAll(numeros);
        familiasQueFaltan++;
      }
    }
    return SalonEntero._(
      hoja: CuadroDelSalon.hojaPrincipal(armado) ?? armado.hojas.first.id,
      estado: EstadoPlano.desde(armado: armado, ocupantes: ocupantes),
      familiaDeMesa: familiaDeMesa,
      faltan: faltan,
      familiasQueFaltan: familiasQueFaltan,
    );
  }
}
