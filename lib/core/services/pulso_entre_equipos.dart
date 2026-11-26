/// El aviso entre equipos ("el pulso"): por dónde va y qué forma tiene.
///
/// Lo manda el motor de cada PC y tablet cuando sube algo (`SyncEngine`), y
/// desde la 6.9.0 también la web cuando escribe directo en la nube algo que
/// otro equipo está esperando (`BarraNube.anotarPasoDelCierre`). Quien lo
/// recibe baja las tablas nombradas (`trabajoDelPulso`).
///
/// Vive acá, y no adentro del motor, para que la web lo mande sin traerse el
/// motor entero.
library;

/// El canal de Realtime por donde va.
const kCanalDelPulso = 'sync_pulse';

/// El nombre del evento de broadcast.
const kEventoDelPulso = 'cambios';

/// El cuerpo de un aviso de que cambiaron [tablas], mandado por [origen] (el id
/// de la instalación: quien lo recibe descarta el propio).
///
/// **Sin una clave `payload`**: por REST el servidor envuelve el aviso en una, y
/// quien lee ([cuerpoDelBroadcast]) las distingue por eso.
Map<String, dynamic> avisoDeTablas({
  required String origen,
  required Iterable<String> tablas,
}) =>
    {
      'origen': origen,
      'tablas': tablas.toList(),
      'borrados': <String, List<String>>{},
    };

/// La clave del aviso de que cambió la apariencia del tótem de unas fiestas
/// (25-nov-2026). `totem_config` no es una tabla del motor (no se baja entera:
/// la lee el tótem), así que no va en `tablas`.
const kAparienciaDelPulso = 'totem_config';

/// El aviso de que se guardó la apariencia del tótem de [eventoId]
/// (Personalizar, o los segundos de la llegada): la tele que la muestra la
/// vuelve a leer al momento.
Map<String, dynamic> avisoDeLaApariencia({
  required String origen,
  required String eventoId,
}) =>
    {
      ...avisoDeTablas(origen: origen, tablas: const []),
      kAparienciaDelPulso: [eventoId],
    };

/// Las fiestas cuya apariencia cambió según un aviso ([avisoDeLaApariencia]).
/// Como `trabajoDelPulso`: el aviso cruzó la red, así que solo se aceptan ids
/// con forma de UUID, y el aviso propio ([yo]) no cuenta.
Set<String> aparienciasDelPulso(Object? datos, {required String? yo}) {
  if (datos is! Map) return const {};
  if (yo != null && datos['origen'] == yo) return const {};
  final ids = datos[kAparienciaDelPulso];
  return {
    for (final id in ids is List ? ids : const [])
      if (id is String && id.length == 36) id,
  };
}
