import 'dart:math';

import '../modelo/armado_salon.dart';
import 'sorteo_con_plano.dart';

/// Cuándo las mesas de una familia están **juntas** en el salón.
///
/// Hasta la 6.9.0, juntas eran solo mesas seguidas y pegadas: los tramos de
/// [SorteoConPlano.tramosPegados], que es lo que entiende el motor del sorteo.
/// Con el salón justo y "Primero las familias de una sola mesa", una familia
/// con adicional puede tapar el hueco que queda junto a la pasarela con sus
/// mesas **una detrás de la otra** (lo eligió el usuario el 16-nov-2026, sobre
/// un dibujo). Esas también están juntas, y el control final del sorteo, la
/// pantalla y el papel lo miden con esta misma cuenta.
///
/// Los tramos, los casilleros y el motor no cambian.
class MesasJuntas {
  MesasJuntas._();

  /// [a] y [b] se tocan en el salón y están en línea: una detrás de la otra (o
  /// una al lado de la otra), nunca en diagonal. Del otro lado de la pasarela
  /// no están pegadas, así que nunca cuentan.
  static bool unaDetrasDeLaOtra(ArmadoSalon armado, int a, int b) {
    if (a == b || !armado.pegadas(a, b)) return false;
    final ma = armado.mesa(a)!;
    final mb = armado.mesa(b)!;
    final dx = (ma.x - mb.x).abs();
    final dy = (ma.y - mb.y).abs();
    return min(dx, dy) < armado.radio;
  }

  /// Seguidas y pegadas: lo de siempre ([SorteoConPlano.tramosPegados]).
  static bool seguidas(ArmadoSalon armado, int a, int b) =>
      (b == a + 1 || a == b + 1) && armado.pegadas(a, b);

  /// Las dos mesas cuentan como juntas: seguidas, o una detrás de la otra.
  static bool unidas(ArmadoSalon armado, int a, int b) =>
      seguidas(armado, a, b) || unaDetrasDeLaOtra(armado, a, b);

  /// Las mesas de una familia en grupos de mesas juntas. Cada grupo va
  /// ordenado por número, y los grupos por su número más bajo.
  static List<List<int>> grupos(ArmadoSalon armado, Iterable<int> numeros) {
    final quedan = numeros.toSet().toList()..sort();
    final out = <List<int>>[];
    while (quedan.isNotEmpty) {
      final grupo = [quedan.removeAt(0)];
      for (var i = 0; i < grupo.length; i++) {
        final tocan = [
          for (final n in quedan)
            if (unidas(armado, grupo[i], n)) n,
        ];
        quedan.removeWhere(tocan.contains);
        grupo.addAll(tocan);
      }
      out.add(grupo..sort());
    }
    return out;
  }

  /// Todas las mesas de la familia quedaron juntas (o tiene una sola).
  static bool juntas(ArmadoSalon armado, Iterable<int> numeros) =>
      grupos(armado, numeros).length <= 1;

  /// Si la familia usa una detrás de la otra: juntas, pero no en un solo tramo
  /// de mesas seguidas.
  static bool usaUnaDetrasDeLaOtra(ArmadoSalon armado, Iterable<int> numeros) =>
      juntas(armado, numeros) &&
      SorteoConPlano.tramosPegados(armado, numeros).length > 1;

  /// Cómo se dibuja la cápsula de un [grupo] de mesas juntas: una o más listas
  /// de mesas, cada una una línea que pasa por sus mesas en ese orden.
  ///
  /// - Un solo tramo de mesas seguidas: ese tramo, como siempre.
  /// - Si no, el recorrido que pasa una sola vez por cada mesa, de una a la
  ///   otra que se toca (una familia de dos o tres mesas siempre tiene uno).
  /// - Si no hay recorrido así, cada tramo y, entre tramos, un trazo corto de
  ///   las dos mesas que quedan una detrás de la otra.
  static List<List<int>> capsulas(ArmadoSalon armado, List<int> grupo) {
    if (grupo.length < 2) return const [];
    final tramos = SorteoConPlano.tramosPegados(armado, grupo);
    if (tramos.length == 1) return [tramos.single];
    final camino = _recorrido(armado, grupo);
    if (camino != null) return [camino];
    final out = <List<int>>[
      for (final t in tramos)
        if (t.length > 1) t,
    ];
    // Un trazo por cada tramo que se suma, desde alguno de los ya unidos.
    final unidos = <int>{...tramos.first};
    final faltan = [...tramos.skip(1)];
    while (faltan.isNotEmpty) {
      var avanzo = false;
      for (final t in [...faltan]) {
        (int, int)? puente;
        for (final x in unidos) {
          for (final y in t) {
            if (unaDetrasDeLaOtra(armado, x, y)) {
              puente = (x, y);
              break;
            }
          }
          if (puente != null) break;
        }
        if (puente == null) continue;
        out.add([puente.$1, puente.$2]);
        unidos.addAll(t);
        faltan.remove(t);
        avanzo = true;
      }
      if (!avanzo) break;
    }
    return out;
  }

  /// Un recorrido que pasa una sola vez por cada mesa del grupo, de una a otra
  /// que se toca, empezando por la de número más bajo que sirva. Null si no
  /// hay (o el grupo es muy grande para buscarlo).
  static List<int>? _recorrido(ArmadoSalon armado, List<int> grupo) {
    if (grupo.length > 8) return null;
    final ordenados = [...grupo]..sort();
    for (final inicio in ordenados) {
      final camino = <int>[inicio];
      bool seguir() {
        if (camino.length == ordenados.length) return true;
        // Primero la seguida: la línea sigue la serpentina cuando puede.
        final siguientes = [
          for (final n in ordenados)
            if (!camino.contains(n) && seguidas(armado, camino.last, n)) n,
          for (final n in ordenados)
            if (!camino.contains(n) &&
                !seguidas(armado, camino.last, n) &&
                unaDetrasDeLaOtra(armado, camino.last, n))
              n,
        ];
        for (final n in siguientes) {
          camino.add(n);
          if (seguir()) return true;
          camino.removeLast();
        }
        return false;
      }

      if (seguir()) return camino;
    }
    return null;
  }
}
