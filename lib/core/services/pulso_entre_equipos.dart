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
