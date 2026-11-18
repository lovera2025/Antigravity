import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import '../../../models/sorteo_mesas_registro.dart';
import 'lugares_al_sorteo.dart';

/// Lo que el jefe revisa en PRECIOS de una fiesta **sorteada antes de la regla
/// del descuento** (17-nov-2026): los lugares de los que no hay huella de antes
/// del sorteo, con su porqué.
class ListaDeLugares {
  /// El sorteo de la fiesta: el renglón al que se le agrega lo aceptado.
  final SorteoMesasRegistro sorteo;

  /// Todos los alumnos de la fiesta, como están hoy.
  final List<ContratoAlumno> alumnos;

  final List<LugarEnDuda> enDuda;

  const ListaDeLugares({
    required this.sorteo,
    required this.alumnos,
    required this.enDuda,
  });

  /// Lo que viene tildado "paga entera": solo lo que tiene huella de que vino
  /// después. Lo demás queda para revisar, sin tildar: no se le cobra entera a
  /// nadie por una duda.
  Set<String> get tildadosDeEntrada => {
        for (final d in enDuda)
          if (d.despues) d.clave,
      };

  /// Para saber si la lista es la misma que se mostró: el renglón del sorteo y
  /// cada lugar en duda con su cantidad.
  String get firma => [
        sorteo.id,
        for (final d in enDuda) '${d.clave}|${d.cantidad}',
      ].join(';');

  /// Cuántas entradas pagan entera con lo que está tildado, y de cuántas
  /// familias.
  ({int entradas, int familias}) pagaEntera(Set<String> tildados) {
    var entradas = 0;
    final familias = <String>{};
    for (final d in enDuda) {
      if (!tildados.contains(d.clave)) continue;
      entradas += d.entradas;
      familias.add(d.alumnoId);
    }
    return (entradas: entradas, familias: familias.length);
  }
}

/// De dónde lee y dónde guarda [RevisionDeLugares]. En la app, la base de la
/// PC y la nube; en las pruebas, la memoria.
abstract class PuertosDeLaRevision {
  /// Baja de la nube los alumnos, sus pagos, el reparto de las sillas y el
  /// registro de sorteos. False si no hay internet o no bajó todo.
  Future<bool> ponerAlDia();

  /// Todos los alumnos de la fiesta, también los de baja temporal.
  Future<List<ContratoAlumno>> alumnos(String eventoId);

  Future<Map<String, List<Map<String, dynamic>>>> pagos(List<String> alumnoIds);

  Future<Map<String, SillasReparto>> repartos(List<String> alumnoIds);

  Future<List<SorteoMesasRegistro>> registros(String eventoId);

  /// Le agrega los lugares al renglón del sorteo y lo sube. False: no se
  /// guardó nada.
  Future<bool> guardar(String registroId, Map<String, String> lugares);
}

enum ResultadoDeAceptar {
  /// Quedó anotado: desde ahora rige la regla en esta fiesta.
  aceptado,

  /// No se pudo poner al día con la nube: no se guardó nada.
  sinInternet,

  /// Al poner al día, la lista ya no es la que se mostró (otra PC cargó
  /// algo): se muestra la nueva y el jefe la mira de nuevo.
  cambio,

  /// Al poner al día, la fiesta ya no está "sorteada sin anotar": otra PC la
  /// aceptó, o el sorteo se deshizo.
  yaNoHaceFalta,

  /// La base no lo guardó.
  noSeGuardo,
}

/// Arma la lista de una fiesta ya sorteada y guarda lo que el jefe acepta.
///
/// **Aceptar pide internet y relee todo antes de guardar**: lo anotado sube a
/// todas las PCs y desde ahí decide qué entradas van con descuento, así que no
/// puede salir de una PC atrasada.
class RevisionDeLugares {
  final PuertosDeLaRevision _puertos;

  const RevisionDeLugares(this._puertos);

  /// La lista de la fiesta, con lo que esta PC tiene. Null si no hay nada que
  /// revisar: la fiesta no tiene sorteo del jefe en pie, o ya tiene los lugares
  /// anotados.
  Future<ListaDeLugares?> leer(String eventoId) async {
    final registros = await _puertos.registros(eventoId);
    final sorteo = LugaresAlSorteo.primerDelJefe(registros);
    if (sorteo == null || sorteo.lugares != null) return null;
    final alumnos = await _puertos.alumnos(eventoId);
    final conAlgo = [
      for (final a in alumnos)
        if (LugaresCargados.de(a).tieneAdicionales) a.id,
    ];
    final pagos = conAlgo.isEmpty
        ? const <String, List<Map<String, dynamic>>>{}
        : await _puertos.pagos(conAlgo);
    final repartos = conAlgo.isEmpty
        ? const <String, SillasReparto>{}
        : await _puertos.repartos(conAlgo);
    return ListaDeLugares(
      sorteo: sorteo,
      alumnos: alumnos,
      enDuda: LugaresAlSorteo.enDuda(
        registros: registros,
        alumnos: alumnos,
        pagos: pagos,
        repartos: repartos,
      ),
    );
  }

  /// Guarda lo aceptado: lo que cada familia tiene hoy, menos los lugares de
  /// [mostrada] que quedaron tildados en [pagaEntera].
  ///
  /// Con [ResultadoDeAceptar.cambio] devuelve además la lista nueva.
  Future<({ResultadoDeAceptar resultado, ListaDeLugares? lista})> aceptar(
    String eventoId, {
    required ListaDeLugares mostrada,
    required Set<String> pagaEntera,
  }) async {
    if (!await _puertos.ponerAlDia()) {
      return (resultado: ResultadoDeAceptar.sinInternet, lista: null);
    }
    final hoy = await leer(eventoId);
    if (hoy == null) {
      return (resultado: ResultadoDeAceptar.yaNoHaceFalta, lista: null);
    }
    if (hoy.firma != mostrada.firma) {
      return (resultado: ResultadoDeAceptar.cambio, lista: hoy);
    }
    final lugares = LugaresAlSorteo.alAceptar(
      alumnos: hoy.alumnos,
      enDuda: hoy.enDuda,
      pagaEntera: pagaEntera,
    );
    final bien = await _puertos.guardar(hoy.sorteo.id, lugares);
    return (
      resultado:
          bien ? ResultadoDeAceptar.aceptado : ResultadoDeAceptar.noSeGuardo,
      lista: null,
    );
  }
}
