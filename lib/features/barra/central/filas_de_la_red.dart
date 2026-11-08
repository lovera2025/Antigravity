// Lo que viaja por la red del salón entre las cajas de la barra y su central: las filas
// de las cuatro tablas que escribe cada caja, tal como las guarda la base del equipo
// (`toMap()`). La central es la bajada de la nube, pero por el wifi del salón: lo que
// llega de otro equipo se guarda **sin encolarlo para subir** (ya lo sube el equipo que
// lo hizo), así no hay duplicados y la nube sigue siendo la de siempre.

/// Las tablas que se reparten por la red del salón: lo que escribe cada caja. El catálogo,
/// los precios y el recargo no: los pone el jefe con internet, antes de la fiesta.
const tablasDeLaRed = ['barra_cajas', 'barra_ventas', 'barra_anulaciones', 'barra_vales'];

/// Lo que la central y las cajas necesitan de la base del equipo. La implementan
/// `BarraLocal` (la base de la PC o la tablet) y, en las pruebas, la barra en memoria.
abstract interface class BarraDeLaRed {
  /// Guarda [fila] de [tabla], que hizo otro equipo, **sin encolarla para subir**. No la
  /// guarda si este equipo tiene esa fila sin subir (lo suyo manda) ni si la que ya hay
  /// es más nueva. True si cambió algo.
  Future<bool> guardarDeOtroEquipo(String tabla, Map<String, Object?> fila);

  /// Todo lo de la fiesta que tiene este equipo, de todas las cajas: lo que se manda al
  /// conectarse.
  Future<Map<String, List<Map<String, Object?>>>> filasDeLaFiesta(String eventoId);

  /// Una fila de este equipo, para mandarla. Null si no está.
  Future<Map<String, Object?>?> filaDeLaRed(String tabla, String id);

  /// Lo de la barra que espera subir a la nube desde este equipo.
  Future<PendientesDeLaBarra> pendientesDeLaBarra();
}

/// Lo de la barra que espera subir a la nube: las ventas, y el resto (cajas que se
/// abrieron o cerraron, anulaciones y vales).
class PendientesDeLaBarra {
  final int ventas;
  final int otros;

  const PendientesDeLaBarra({this.ventas = 0, this.otros = 0});

  static const nada = PendientesDeLaBarra();

  int get total => ventas + otros;
  bool get vacio => total == 0;

  /// "2 ventas y 1 cambio", "1 venta", "3 cambios". Vacío: "".
  String get enPalabras {
    final partes = [
      if (ventas > 0) ventas == 1 ? '1 venta' : '$ventas ventas',
      if (otros > 0) otros == 1 ? '1 cambio' : '$otros cambios',
    ];
    return partes.join(' y ');
  }

  @override
  bool operator ==(Object other) =>
      other is PendientesDeLaBarra && other.ventas == ventas && other.otros == otros;

  @override
  int get hashCode => Object.hash(ventas, otros);
}

/// Si [fila] de [tabla] es de la fiesta [eventoId] y se puede guardar: una tabla de la
/// red, con id y la fiesta de 36 letras. Lo que no, se ignora (no rompe nada).
bool filaDeLaFiesta(String tabla, Object? fila, String eventoId) {
  if (!tablasDeLaRed.contains(tabla) || fila is! Map) return false;
  final id = fila['id'];
  return id is String && id.length == 36 && fila['evento_id'] == eventoId;
}

/// Si [nueva] tiene que reemplazar a [vieja], la que ya está en el equipo: la de
/// `updated_at` más nuevo gana; con la misma hora, solo si dice otra cosa. Una más vieja
/// nunca pisa: la caja cerrada no vuelve a abierta porque llegó tarde la versión de antes.
bool cambiaLaFila({required Map<String, Object?> nueva, required Map<String, Object?> vieja}) {
  final n = DateTime.tryParse('${nueva['updated_at']}');
  final v = DateTime.tryParse('${vieja['updated_at']}');
  if (n == null) return false;
  if (v != null && n.isBefore(v)) return false;
  if (v == null || n.isAfter(v)) return true;
  for (final e in nueva.entries) {
    if ('${e.value}' != '${vieja[e.key]}') return true;
  }
  return false;
}
