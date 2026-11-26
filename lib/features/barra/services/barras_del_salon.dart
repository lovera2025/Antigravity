import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cuentas/nombre_de_barra.dart';

/// **Las barras del salón** (25-nov-2026): en la Técnica hay dos, cada una con su
/// notebook (la central) y su router Mercusys. La caja elige la suya al abrirse y queda
/// en la columna `sede` de `barra_cajas` (sin SQL: la columna ya estaba, como texto
/// libre). La central dice de qué barra es, y la tablet se engancha a la de su barra.
const kBarrasDelSalon = ['Barra 1', 'Barra 2'];

/// La barra de una caja según su `sede`: "Barra 1" (también "barra 1", " BARRA  1 "), o
/// null si la sede es otra cosa (una caja vieja con "Barra del fondo") o no hay. Se
/// compara con [claveDeBarra], como todo lo que compara barras.
String? barraDe(String? sede) {
  if (sede == null || sede.trim().isEmpty) return null;
  final s = claveDeBarra(sede);
  for (final b in kBarrasDelSalon) {
    if (claveDeBarra(b) == s) return b;
  }
  return null;
}

/// Cuántos números de caja tiene cada barra.
const kCajasPorBarra = 6;

/// **Los números de caja de cada barra** (26-nov-2026, la revisión independiente): la
/// Barra 1, de la 1 a la 6; la Barra 2, de la 7 a la 12. Así una "Caja 1" nunca está en
/// las dos barras a la vez: el vale de una silla dice solo la caja y el número ("Caja 1 ·
/// N° 0017"), y la puerta y los vales anulados los comparan así. Con las dos barras en
/// redes que no se ven, el aviso de "ya está abierta" no llega de una a la otra. Sin barra
/// (null), los de la Barra 1.
List<int> numerosDeCaja(String? barra) {
  final i = kBarrasDelSalon.indexOf(barraDe(barra) ?? kBarrasDelSalon.first);
  final desde = i * kCajasPorBarra + 1;
  return [for (var n = desde; n < desde + kCajasPorBarra; n++) n];
}

/// La barra de este equipo, recordada: la que eligió la última caja que se abrió acá, o
/// la de la central de esta notebook. Se ofrece elegida la próxima vez. Los tests la
/// reemplazan.
class BarraDelEquipo {
  const BarraDelEquipo();

  static const _clave = 'barra.barra_del_equipo_v1';

  /// Null: nunca se eligió.
  Future<String?> leer() async {
    try {
      return barraDe((await SharedPreferences.getInstance()).getString(_clave));
    } catch (_) {
      return null;
    }
  }

  Future<void> guardar(String? barra) async {
    final b = barraDe(barra);
    if (b == null) return;
    try {
      await (await SharedPreferences.getInstance()).setString(_clave, b);
    } catch (_) {}
  }
}

final barraDelEquipoProvider = Provider<BarraDelEquipo>((ref) => const BarraDelEquipo());
