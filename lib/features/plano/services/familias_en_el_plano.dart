import '../modelo/armado_salon.dart';
import '../modelo/estado_plano.dart';
import 'mesas_juntas.dart';

/// Lo que lleva una mesa de una familia con más de una mesa.
class MarcaDeMesa {
  /// La mesa principal, la que lleva el apellido: "P". Las demás son "A".
  final bool principal;

  /// La familia no quedó toda pegada: la mesa lleva un aro punteado.
  final bool separada;

  /// El número de la otra mesa de la familia, para la flecha. Null si no es
  /// [separada].
  final int? otra;

  /// El apellido de la familia.
  final String apellido;

  const MarcaDeMesa({
    required this.principal,
    required this.apellido,
    this.separada = false,
    this.otra,
  });

  /// El apellido que esta mesa tiene que escribir además del de siempre. Una mesa
  /// de una familia separada lo lleva aunque no sea la principal: lejos de las
  /// otras, si no, no se sabe de quién es (lo pidió el usuario el 2-nov, mirando la
  /// tercera mesa de una familia). Null si no hace falta: junta con las suyas se
  /// lee por la línea, o [yaLoLleva] porque es la principal.
  String? apellidoQueFalta({required bool yaLoLleva}) =>
      separada && !yaLoLleva ? apellido : null;
}

/// Qué familias tienen adicional en el salón, y si quedaron juntas o separadas.
/// Sin dato nuevo: se mide con [MesasJuntas], lo mismo que usa el control final
/// del sorteo (mesas seguidas y pegadas, o una detrás de la otra: 16-nov-2026).
///
/// - **Una mesa:** nada.
/// - **Un solo grupo de dos o más:** juntas. Una cápsula une sus mesas
///   ([MesasJuntas.capsulas]: la serpentina y, si hace falta, la mesa de atrás).
/// - **Más de un grupo:** separadas. Un aro punteado en cada mesa y la flecha a la
///   otra. Un grupo de dos o más dentro de una familia separada lleva su cápsula.
///
/// Antes del sorteo vale lo mismo con las mesas fijadas. Lo dibujan la pantalla y
/// el papel: nunca es solo un color, así se lee igual en blanco y negro.
class FamiliasEnElPlano {
  /// Mesa → su marca.
  final Map<int, MarcaDeMesa> marcas;

  /// Cada cápsula: las mesas por las que pasa su línea, en ese orden.
  final List<List<int>> capsulas;
  final bool hayJuntas;
  final bool haySeparadas;

  const FamiliasEnElPlano({
    this.marcas = const {},
    this.capsulas = const [],
    this.hayJuntas = false,
    this.haySeparadas = false,
  });

  bool get hayAlguna => marcas.isNotEmpty;

  factory FamiliasEnElPlano.desde(ArmadoSalon armado, EstadoPlano estado) {
    // Las mesas de cada familia que están en este salón: las que ocupa y las que
    // tiene fijadas. Una mesa que el armado no tiene no se puede dibujar.
    final porFamilia = <String, Set<int>>{};
    final apellidos = <String, String>{};
    for (final i in estado.mesas) {
      final fijada = i.fijadaPara;
      for (final o in [...i.ocupantes, ?fijada]) {
        porFamilia.putIfAbsent(o.id, () => {}).add(i.numero);
        apellidos[o.id] = o.apellido;
      }
    }

    final marcas = <int, MarcaDeMesa>{};
    final capsulas = <List<int>>[];
    var hayJuntas = false;
    var haySeparadas = false;
    final familias = porFamilia.keys.toList()..sort();
    for (final id in familias) {
      final numeros = porFamilia[id]!;
      if (numeros.length < 2) continue;
      final grupos = MesasJuntas.grupos(armado, numeros);
      final separada = grupos.length > 1;
      if (separada) {
        haySeparadas = true;
      } else {
        hayJuntas = true;
      }
      for (final (i, grupo) in grupos.indexed) {
        capsulas.addAll(MesasJuntas.capsulas(armado, grupo));
        for (final n in grupo) {
          // Una mesa de dos familias es un conflicto, que ya se avisa: se queda
          // con la primera marca.
          marcas.putIfAbsent(
            n,
            () => MarcaDeMesa(
              principal: estado.info(n).principal,
              apellido: apellidos[id]!,
              separada: separada,
              otra: separada ? grupos[(i + 1) % grupos.length].first : null,
            ),
          );
        }
      }
    }
    return FamiliasEnElPlano(
      marcas: Map.unmodifiable(marcas),
      capsulas: List.unmodifiable(capsulas),
      hayJuntas: hayJuntas,
      haySeparadas: haySeparadas,
    );
  }
}
