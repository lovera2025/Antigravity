import '../../../models/contrato_alumno.dart';
import '../../../models/movimiento_mesas.dart';
import '../../../models/sorteo_mesas_registro.dart';
import 'mesas_extra_utils.dart';
import 'registro_sorteo.dart';

/// Una familia del último sorteo que "deshacer solo los últimos" deja como
/// está, con el porqué en palabras.
class FamiliaQueNoSeToca {
  final String alumnoId;
  final String nombre;
  final String motivo;

  const FamiliaQueNoSeToca({
    required this.alumnoId,
    required this.nombre,
    required this.motivo,
  });
}

/// Los últimos sorteados de una fiesta: las familias del sorteo más nuevo que
/// sigue valiendo, y qué pasaría si se deshiciera solo ese.
///
/// Sirve para "sortear a los que faltan": el primer sorteo sentó a casi todos y
/// después se le dio mesa al que se sumó tarde, terminó de pagar o compró otra.
/// Si eso último salió mal, se vuelve atrás sin tocar a los del primero.
class UltimosSorteados {
  /// Los sorteos que siguen valiendo, del más viejo al más nuevo. Nunca vacío.
  final List<SorteoMesasRegistro> enPie;

  /// Las familias del último sorteo que siguen en la fiesta.
  final Set<String> familias;

  /// El nombre de cada una, para mostrarlas.
  final Map<String, String> nombres;

  /// Cuántos tienen mesa hoy y no son del último sorteo.
  final int otrosConMesa;

  /// Alumno → cómo queda al deshacer solo los últimos. `null`: sin mesa.
  final Map<String, String?> aGuardar;

  /// Alumno → lo que tiene hoy, de los que se revierten. Va al registro y a
  /// la copia.
  final Map<String, String> tenian;

  /// Alumno → lo que conserva, de los que no quedan sin mesa: ya tenían alguna
  /// y el sorteo les sumó otra.
  final Map<String, String> quedan;

  /// Los del último sorteo que no se revierten.
  final List<FamiliaQueNoSeToca> noSeTocan;

  const UltimosSorteados._({
    required this.enPie,
    required this.familias,
    required this.nombres,
    required this.otrosConMesa,
    required this.aGuardar,
    required this.tenian,
    required this.quedan,
    required this.noSeTocan,
  });

  /// El sorteo del que se habla.
  SorteoMesasRegistro get sorteo => enPie.last;

  /// No queda otro sorteo debajo: al deshacerlo, los bloques de cada división
  /// dejan de valer, igual que cuando se deshace todo.
  bool get eraElUnico => enPie.length == 1;

  /// Deshacer solo los últimos no es lo mismo que deshacer todo: alguien
  /// conserva su mesa.
  bool get deshacerSoloCambiaAlgo =>
      aGuardar.isNotEmpty && (otrosConMesa > 0 || quedan.isNotEmpty);

  /// La planilla solo de los últimos no es la de toda la escuela.
  bool get planillaSolaCambiaAlgo => familias.isNotEmpty && otrosConMesa > 0;

  static List<SorteoMesasRegistro> _enOrden(
    List<SorteoMesasRegistro> registros,
  ) =>
      List<SorteoMesasRegistro>.from(registros)
        ..sort((a, b) {
          final c = a.createdAt.compareTo(b.createdAt);
          return c != 0 ? c : a.id.compareTo(b.id);
        });

  /// Los sorteos que siguen valiendo. Un sorteo o una restauración se apilan;
  /// deshacer todo los saca a todos; deshacer solo los últimos saca el de
  /// arriba.
  static List<SorteoMesasRegistro> sorteosEnPie(
    List<SorteoMesasRegistro> registros,
  ) {
    final pila = <SorteoMesasRegistro>[];
    for (final r in _enOrden(registros)) {
      switch (r.tipo) {
        case TipoRegistroSorteo.sorteo:
        case TipoRegistroSorteo.restaurar:
          pila.add(r);
        case TipoRegistroSorteo.deshacer:
          if (!r.esDeshacerDeUltimos) {
            pila.clear();
          } else if (pila.isNotEmpty) {
            pila.removeLast();
          }
      }
    }
    return pila;
  }

  static String _texto(Set<int> numeros) =>
      MesasExtraUtils.formatearAsignacionMesas(numeros.toList()..sort());

  static bool _iguales(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  /// `null` si no hay ningún sorteo en pie.
  ///
  /// Una familia del último sorteo se revierte solo si hoy tiene exactamente lo
  /// que ese sorteo le dejó. Si después la mudaron o le cambiaron la mesa a
  /// mano, deshacerle "el sorteo" sería pisar ese cambio: no se toca y se dice.
  static UltimosSorteados? de(
    List<SorteoMesasRegistro> registros,
    Iterable<ContratoAlumno> alumnos, {
    List<MovimientoMesas> movimientos = const [],
  }) {
    final enPie = sorteosEnPie(registros);
    if (enPie.isEmpty) return null;
    final sorteo = enPie.last;

    // Un renglón de antes de que se anotara qué tenía cada uno: sale de
    // repasar el registro hasta ese sorteo.
    Map<String, Set<int>>? segunElRegistro;
    Set<int> teniaAntes(String id) {
      final anotado = sorteo.antes;
      if (anotado != null) {
        return MesasExtraUtils.numerosMesaDesdeTexto(anotado[id]);
      }
      final ordenados = _enOrden(registros);
      segunElRegistro ??= RegistroSorteo.esperado(
        ordenados.sublist(0, ordenados.indexOf(sorteo)),
        [
          for (final m in movimientos)
            if (m.createdAt.isBefore(sorteo.createdAt)) m,
        ],
      );
      return segunElRegistro![id] ?? const {};
    }

    final familias = <String>{};
    final nombres = <String, String>{};
    final aGuardar = <String, String?>{};
    final tenian = <String, String>{};
    final quedan = <String, String>{};
    final noSeTocan = <FamiliaQueNoSeToca>[];
    var otrosConMesa = 0;

    for (final a in alumnos) {
      final hoy = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa);
      final sinNada = a.numeroMesa?.trim().isEmpty ?? true;
      final dejado = sorteo.resultado[a.id];
      if (dejado == null) {
        if (!sinNada) otrosConMesa++;
        continue;
      }
      familias.add(a.id);
      nombres[a.id] = a.nombreAlumno;
      final dejo = MesasExtraUtils.numerosMesaDesdeTexto(dejado);
      void noSeToca(String motivo) => noSeTocan.add(FamiliaQueNoSeToca(
            alumnoId: a.id,
            nombre: a.nombreAlumno,
            motivo: motivo,
          ));
      if (!_iguales(hoy, dejo)) {
        noSeToca(sinNada
            ? 'ya no tiene mesa'
            : 'le cambiaron la mesa después de ese sorteo');
        continue;
      }
      final antes = teniaAntes(a.id);
      if (!dejo.containsAll(antes)) {
        noSeToca('no quedó anotado qué mesa tenía antes');
        continue;
      }
      if (_iguales(antes, dejo)) continue;
      tenian[a.id] = a.numeroMesa!.trim();
      if (antes.isEmpty) {
        aGuardar[a.id] = null;
      } else {
        // Tal como estaba escrito, si quedó anotado: una mesa cargada a mano
        // vuelve con sus mismas palabras.
        final escrito = sorteo.antes?[a.id]?.trim() ?? '';
        final queda = escrito.isNotEmpty ? escrito : _texto(antes);
        aGuardar[a.id] = queda;
        quedan[a.id] = queda;
      }
    }
    noSeTocan.sort((x, y) => x.nombre.compareTo(y.nombre));

    return UltimosSorteados._(
      enPie: enPie,
      familias: familias,
      nombres: nombres,
      otrosConMesa: otrosConMesa,
      aGuardar: aGuardar,
      tenian: tenian,
      quedan: quedan,
      noSeTocan: noSeTocan,
    );
  }

  /// Lo que hay que anotar en un sorteo o una restauración: qué tenía cada
  /// familia de [numeros] que ya tenía mesa.
  static Map<String, String> antesDe(
    Iterable<ContratoAlumno> alumnos,
    Map<String, String> numeros,
  ) =>
      {
        for (final a in alumnos)
          if (numeros.containsKey(a.id) &&
              (a.numeroMesa?.trim().isNotEmpty ?? false))
            a.id: a.numeroMesa!.trim(),
      };
}
