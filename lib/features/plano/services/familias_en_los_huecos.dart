import 'dart:math';

import '../modelo/armado_salon.dart';
import 'mesas_juntas.dart';
import 'sorteo_con_plano.dart';

/// Una familia que hay que ubicar en los huecos: quién es y cuántas mesas lleva.
typedef FamiliaParaUbicar = ({String id, int mesas});

/// Dónde quedó cada familia, y cuántas usan una detrás de la otra.
class AcomodoEnLosHuecos {
  /// Familia → sus mesas, ordenadas.
  final Map<String, List<int>> mesas;

  /// Cuántas familias quedaron con sus mesas una detrás de la otra (no en un
  /// solo tramo de mesas seguidas).
  final int unaDetrasDeLaOtra;

  const AcomodoEnLosHuecos({
    required this.mesas,
    required this.unaDetrasDeLaOtra,
  });
}

/// Las familias con adicional en los huecos del salón justo (16-nov-2026).
///
/// Con "Primero las familias de una sola mesa" y las mesas exactas, detrás de
/// las de una sola mesa quedan huecos de una mesa junto a la pasarela que una
/// familia con adicional no puede usar en mesas seguidas: el motor no la parte
/// en la pasarela. **Solo en ese caso**, la familia tapa el hueco con sus mesas
/// una detrás de la otra, del mismo lado de la pasarela (lo eligió el usuario
/// sobre un dibujo). Nadie de una sola mesa se mueve y ninguna familia se
/// separa ([MesasJuntas]).
///
/// Es una búsqueda con vuelta atrás sobre [libres], en el orden en que se
/// recorre el salón: la primera mesa libre que queda la toma alguna familia (o
/// queda vacía, si sobran mesas). Cada familia, en mesas seguidas o una detrás
/// de la otra; **las menos familias posibles con una detrás de la otra**. El
/// motor del sorteo no se toca.
class FamiliasEnLosHuecos {
  FamiliasEnLosHuecos._();

  /// Cuántos pasos se buscan como mucho antes de decir que no entra: con las
  /// mesas que tiene un salón de verdad alcanza de sobra, y nunca se cuelga.
  static const int tope = 400000;

  /// Ubica a [familias] en [libres] (los números de mesa, en el orden en que
  /// se recorre el salón). Null si no entran.
  ///
  /// - Sin [rng] la respuesta es siempre la misma, y la familia que va primero
  ///   en [familias] toma el primer lugar que se pueda (Cumplimiento debido:
  ///   la que mejor cumplió). Con [rng], el orden de las familias y de las
  ///   formas sale del azar (el sorteo).
  /// - [desde]: con cuántas familias una detrás de la otra se empieza a
  ///   probar. El sorteo empieza en 1: con 0 ya sabe que no entra.
  static AcomodoEnLosHuecos? acomodar({
    required ArmadoSalon armado,
    required List<int> libres,
    required List<FamiliaParaUbicar> familias,
    Random? rng,
    int desde = 0,
    int presupuesto = tope,
  }) {
    if (familias.isEmpty) {
      return const AcomodoEnLosHuecos(mesas: {}, unaDetrasDeLaOtra: 0);
    }
    if (familias.any((f) => f.mesas < 1)) return null;
    final necesarias = familias.fold<int>(0, (s, f) => s + f.mesas);
    final n = libres.length;
    if (necesarias > n) return null;

    // Las vecinas de cada mesa: primero la seguida, después la de atrás.
    final vecinas = List.generate(n, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i != j && MesasJuntas.seguidas(armado, libres[i], libres[j])) {
          vecinas[i].add(j);
        }
      }
      for (var j = 0; j < n; j++) {
        if (i != j &&
            !MesasJuntas.seguidas(armado, libres[i], libres[j]) &&
            MesasJuntas.unaDetrasDeLaOtra(armado, libres[i], libres[j])) {
          vecinas[i].add(j);
        }
      }
    }

    final orden = [...familias];
    if (rng != null) orden.shuffle(rng);
    // -1: libre; -2: queda vacía; si no, la familia (su lugar en [orden]).
    final duenio = List<int>.filled(n, -1);
    final usada = List<bool>.filled(orden.length, false);
    var pasos = 0;

    bool enUnTramo(List<int> indices) =>
        SorteoConPlano.tramosPegados(armado, [for (final i in indices) libres[i]])
            .length ==
        1;

    /// Las formas que puede tomar una familia de [k] mesas cuya primera mesa
    /// es [t]: un recorrido de mesas que se tocan, que crece por las dos
    /// puntas. Primero las de un solo tramo de mesas seguidas.
    List<List<int>> formas(int t, int k) {
      if (k == 1) return [[t]];
      final vistas = <String>{};
      final seguidas = <List<int>>[];
      final otras = <List<int>>[];
      final camino = <int>[t];
      void crecer() {
        if (camino.length == k) {
          final forma = [...camino]..sort();
          if (vistas.add(forma.join(','))) {
            (enUnTramo(forma) ? seguidas : otras).add(forma);
          }
          return;
        }
        final puntas = camino.length == 1
            ? [camino.first]
            : [camino.first, camino.last];
        for (final (p, punta) in puntas.indexed) {
          for (final v in vecinas[punta]) {
            if (v < t || duenio[v] != -1 || camino.contains(v)) continue;
            if (p == 0 && camino.length > 1) {
              camino.insert(0, v);
              crecer();
              camino.removeAt(0);
            } else {
              camino.add(v);
              crecer();
              camino.removeLast();
            }
          }
        }
      }

      crecer();
      if (rng != null) {
        seguidas.shuffle(rng);
        otras.shuffle(rng);
      }
      return [...seguidas, ...otras];
    }

    // Lo que ya se sabe que no entra: desde qué mesa, qué mesas de más
    // adelante ya están tomadas, cuántas familias de cada tamaño faltan y
    // cuántas vacías y una detrás de la otra quedan. Sin esto, un salón grande
    // que no entra se buscaría de mil maneras iguales.
    final fallidas = <String>{};
    String estado(int t, int vacias, int detras) {
      final b = StringBuffer('$t|$vacias|$detras|');
      for (var i = t + 1; i < n; i++) {
        if (duenio[i] != -1) b.write('$i,');
      }
      b.write('|');
      final porTamanio = <int, int>{};
      for (var f = 0; f < orden.length; f++) {
        if (!usada[f]) {
          porTamanio[orden[f].mesas] = (porTamanio[orden[f].mesas] ?? 0) + 1;
        }
      }
      final tamanios = porTamanio.keys.toList()..sort();
      for (final k in tamanios) {
        b.write('$k:${porTamanio[k]},');
      }
      return b.toString();
    }

    bool buscar(int desdeIndice, int vacias, int detras, int faltan) {
      if (++pasos > presupuesto) throw const _SinTiempo();
      if (faltan == 0) return true;
      var t = desdeIndice;
      while (t < n && duenio[t] != -1) {
        t++;
      }
      if (t >= n) return false;
      final clave = estado(t, vacias, detras);
      if (fallidas.contains(clave)) return false;
      // Dos familias con la misma cantidad de mesas son iguales para lo que
      // queda: si una no pudo, la otra tampoco.
      final probadas = <int>{};
      for (var f = 0; f < orden.length; f++) {
        if (usada[f]) continue;
        final k = orden[f].mesas;
        if (!probadas.add(k)) continue;
        for (final forma in formas(t, k)) {
          final usaDetras = forma.length > 1 && !enUnTramo(forma);
          if (usaDetras && detras == 0) continue;
          for (final i in forma) {
            duenio[i] = f;
          }
          usada[f] = true;
          if (buscar(t + 1, vacias, usaDetras ? detras - 1 : detras,
              faltan - 1)) {
            return true;
          }
          usada[f] = false;
          for (final i in forma) {
            duenio[i] = -1;
          }
        }
      }
      if (vacias > 0) {
        duenio[t] = -2;
        if (buscar(t + 1, vacias - 1, detras, faltan)) return true;
        duenio[t] = -1;
      }
      fallidas.add(clave);
      return false;
    }

    try {
      for (var l = max(0, desde); l <= orden.length; l++) {
        for (var i = 0; i < n; i++) {
          duenio[i] = -1;
        }
        for (var f = 0; f < orden.length; f++) {
          usada[f] = false;
        }
        // Lo que no entró con menos "una detrás de la otra" sigue sin entrar:
        // [fallidas] se guarda de una vuelta a la otra (la clave lleva
        // cuántas quedan).
        if (!buscar(0, n - necesarias, l, orden.length)) continue;
        final mesas = <String, List<int>>{};
        for (var i = 0; i < n; i++) {
          final f = duenio[i];
          if (f >= 0) (mesas[orden[f].id] ??= <int>[]).add(libres[i]);
        }
        for (final suyas in mesas.values) {
          suyas.sort();
        }
        final conDetras = mesas.values
            .where((m) => MesasJuntas.usaUnaDetrasDeLaOtra(armado, m))
            .length;
        return AcomodoEnLosHuecos(
          mesas: Map.unmodifiable(mesas),
          unaDetrasDeLaOtra: conDetras,
        );
      }
    } on _SinTiempo {
      return null;
    }
    return null;
  }
}

class _SinTiempo implements Exception {
  const _SinTiempo();
}
