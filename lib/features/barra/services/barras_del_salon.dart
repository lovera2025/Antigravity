import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Las barras del salón** (25-nov-2026): en la Técnica hay dos, cada una con su
/// notebook (la central) y su router Mercusys. La caja elige la suya al abrirse y queda
/// en la columna `sede` de `barra_cajas` (sin SQL: la columna ya estaba, como texto
/// libre). La central dice de qué barra es, y la tablet se engancha a la de su barra.
const kBarrasDelSalon = ['Barra 1', 'Barra 2'];

/// La barra de una caja según su `sede`: "Barra 1" (también "barra 1", " BARRA 1 "), o
/// null si la sede es otra cosa (una caja vieja con "Barra del fondo") o no hay.
String? barraDe(String? sede) {
  final s = sede?.trim().toLowerCase();
  if (s == null || s.isEmpty) return null;
  for (final b in kBarrasDelSalon) {
    if (b.toLowerCase() == s) return b;
  }
  return null;
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
