import 'package:shared_preferences/shared_preferences.dart';

/// La impresora de este equipo: con qué id se la encuentra y cómo se llama.
class ImpresoraElegida {
  final String id;
  final String nombre;

  const ImpresoraElegida({required this.id, this.nombre = ''});

  bool esLaMisma(ImpresoraElegida otra) => id == otra.id && nombre == otra.nombre;
}

/// Cuál es la impresora de este equipo, guardada en el equipo y no en la nube: cada
/// tablet tiene la suya. Así la cajera la elige una vez y después se conecta sola.
///
/// **Nunca tira:** si no puede leer, es como si no hubiera ninguna elegida; si no puede
/// guardar, la impresora igual imprime y la próxima vez se elige de nuevo.
class ImpresoraRecordada {
  static const claveId = 'barra.impresora.id';
  static const claveNombre = 'barra.impresora.nombre';

  const ImpresoraRecordada();

  Future<ImpresoraElegida?> leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(claveId);
      if (id == null || id.isEmpty) return null;
      return ImpresoraElegida(id: id, nombre: prefs.getString(claveNombre) ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> guardar(ImpresoraElegida impresora) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(claveId, impresora.id);
      await prefs.setString(claveNombre, impresora.nombre);
    } catch (_) {}
  }

  Future<void> olvidar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(claveId);
      await prefs.remove(claveNombre);
    } catch (_) {}
  }
}
