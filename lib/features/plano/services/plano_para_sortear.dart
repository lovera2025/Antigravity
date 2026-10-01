import '../../../models/plano_evento.dart';

/// Lo que se pudo leer del plano de una fiesta antes de sortear o de deshacer.
class LecturaPlano {
  /// El plano, o null si la fiesta no tiene: ahí el sorteo es el de siempre.
  final PlanoEvento? plano;

  /// Por qué no se puede seguir, en palabras para quien sortea. Null si se
  /// puede.
  final String? problema;

  const LecturaPlano.conPlano(PlanoEvento this.plano) : problema = null;
  const LecturaPlano.sinPlano()
      : plano = null,
        problema = null;
  const LecturaPlano.conProblema(String this.problema) : plano = null;

  bool get sePuedeSeguir => problema == null;
}

/// Lee el plano de la fiesta para sortear: primero la nube, por si la otra PC
/// lo tocó hace un momento (fijó una mesa, dejó una libre), y si no hay red, el
/// de esta PC.
///
/// Nunca tira. Y **ante la duda no deja sortear**: el sorteo se hace una vez,
/// delante de las familias, y sortear ignorando un plano que existe (sus mesas
/// fijas, sus libres, su armado) no tiene vuelta sin deshacer todo.
///
/// - La fiesta no tiene plano: [LecturaPlano.sinPlano]. Si la tabla de esta PC
///   no se puede leer, alcanza con que la nube diga que no hay.
/// - No se puede saber si tiene (ni la nube ni esta PC): problema.
/// - Tiene plano pero su armado no se puede leer: problema. No es "sin plano".
///
/// [consultarNube] en false saltea la nube: cuando ya se sabe que no hay
/// conexión, no vale esperar el tiempo de espera para nada.
Future<LecturaPlano> leerPlanoParaSortear({
  required Future<PlanoEvento?> Function() deLaNube,
  required Future<PlanoEvento?> Function() deEstaPc,
  bool consultarNube = true,
}) async {
  PlanoEvento? plano;
  var laNubeDiceQueNoHay = false;
  if (consultarNube) {
    try {
      plano = await deLaNube();
      laNubeDiceQueNoHay = plano == null;
    } catch (_) {
      // Sin red, o la tabla todavía no existe en la nube: manda esta PC.
    }
  }
  if (plano == null) {
    try {
      plano = await deEstaPc();
    } catch (_) {
      if (!laNubeDiceQueNoHay) {
        return const LecturaPlano.conProblema(
          'No se pudo leer el plano de la fiesta en esta PC. Cerrá la app y '
          'volvé a abrirla; si sigue igual, no sortees desde esta PC.',
        );
      }
    }
  }
  if (plano == null) return const LecturaPlano.sinPlano();
  if (plano.armadoONull == null) {
    return const LecturaPlano.conProblema(
      'El plano de esta fiesta no se puede leer. Abrí PLANO y elegí el armado '
      'de nuevo antes de sortear.',
    );
  }
  return LecturaPlano.conPlano(plano);
}
