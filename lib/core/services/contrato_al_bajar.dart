/// Lo que la PC conserva de la mora de un contrato cuando baja su fila de la
/// nube.
class MoraLocalDelContrato {
  const MoraLocalDelContrato({
    this.exentaHasta,
    this.reinicia = 1,
    this.fechaReferencia,
    this.ajuste = 0,
  });

  final String? exentaHasta;
  final int reinicia;
  final String? fechaReferencia;

  /// El ajuste de la mora que tenía la PC (`mora_tracked_ajuste`). No se
  /// conserva: sirve para avisar si se va (ver [ajusteQueSeVa]).
  final double ajuste;

  factory MoraLocalDelContrato.deFila(Map<String, Object?> r) {
    final v = r['mora_exencion_reinicia'];
    return MoraLocalDelContrato(
      exentaHasta: (r['mora_exenta_hasta'] as String?)?.trim(),
      fechaReferencia: (r['mora_fecha_referencia'] as String?)?.trim(),
      reinicia: v == null
          ? 1
          : v is num
              ? v.toInt()
              : int.tryParse(v.toString()) ?? 1,
      ajuste: (r['mora_tracked_ajuste'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// El ajuste que la PC tenía y que se va porque la nube lo trae en 0, o null.
///
/// Es lo normal cuando alguien sacó un perdón en otra PC, o cuando se puso en 0
/// una mora cargada a mano. Pero si alguna vez fuera un perdón de esta PC que
/// nunca llegó a subir, quedaría escrito en `revision_mora.txt` con el nombre y
/// el monto, para volver a cargarlo.
double? ajusteQueSeVa(
  Map<String, dynamic> filaNube,
  MoraLocalDelContrato? local,
) {
  final enLaPc = local?.ajuste ?? 0;
  final enLaNube = (filaNube['mora_tracked_ajuste'] as num?)?.toDouble() ?? 0;
  if (enLaPc.abs() <= 0.01 || enLaNube.abs() > 0.01) return null;
  return enLaPc;
}

/// El renglón de `revision_mora.txt` para un ajuste que se fue al bajar.
String renglonAjusteQueSeVa(String nombre, double ajuste) =>
    '$nombre: ajuste de la mora en esta PC \$${ajuste.toStringAsFixed(0)}'
    ' -> \$0, como en la nube';

/// Encabezado del bloque de esos renglones en `revision_mora.txt`.
const queHizoAjustesQueSeFueron =
    'al bajar de la nube, la mora cargada a mano o perdonada quedó en 0 en';

/// La fila de un contrato como queda en la PC al bajarla de la nube.
///
/// La nube ya tiene las columnas de mora, así que manda ella. Las filas con
/// cambios locales sin subir ni llegan acá: el pull las saltea (`pendingIds`).
///
/// Dos excepciones, de cuando esas columnas no existían en la nube y el
/// `_cleanForRemote` de entonces no las dejaba subir:
/// - **La eximición** viaja como par (hasta + reinicia): de nada sirve la fecha
///   sin la permanencia, porque la mora vuelve apenas la fecha pasa. Si la
///   nube no la trae, es un perdón viejo que nunca subió: se conserva el par
///   de la PC, que es la única copia que existe.
/// - **La fecha de la baja** (`mora_fecha_referencia`) se conserva igual. Desde
///   la 6.1.0 no cambia la cuenta: queda para una PC con la 6.0.0.
///
/// **El ajuste de la mora (`mora_tracked_ajuste`) lo manda siempre la nube**
/// (6.1.0). Esa columna existió en la nube desde el principio (era la única de
/// la mora que subía), así que no hay ajustes viejos que solo estén en una PC.
/// Antes, si la nube traía 0, la PC se quedaba con el suyo: sacar un perdón en
/// una PC no llegaba a las otras, y el arreglo a mano de la nube del 16-oct
/// (TOÑANEZ, AGUSTINA: los $166.200 cargados a mano, puestos en 0) no le
/// llegaba a la PC del jefe.
Map<String, dynamic> contratoAlBajar(
  Map<String, dynamic> filaNube,
  MoraLocalDelContrato? local,
) {
  final fila = Map<String, dynamic>.from(filaNube);

  final nubeExenta = (fila['mora_exenta_hasta'] as String?)?.trim();
  if (nubeExenta == null || nubeExenta.isEmpty) {
    final localExenta = local?.exentaHasta;
    if (localExenta != null && localExenta.isNotEmpty) {
      fila['mora_exenta_hasta'] = localExenta;
      fila['mora_exencion_reinicia'] = local?.reinicia ?? 1;
    }
  }

  final nubeFechaRef = (fila['mora_fecha_referencia'] as String?)?.trim();
  if (nubeFechaRef == null || nubeFechaRef.isEmpty) {
    final localFechaRef = local?.fechaReferencia;
    if (localFechaRef != null && localFechaRef.isNotEmpty) {
      fila['mora_fecha_referencia'] = localFechaRef;
    }
  }

  fila['mora_tracked_ajuste'] =
      (fila['mora_tracked_ajuste'] as num?)?.toDouble() ?? 0;
  return fila;
}
