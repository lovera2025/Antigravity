/// Lo que mandó quien emitió un broadcast, llegue por donde llegue.
///
/// Por el socket (lo normal, con el canal de quien manda unido) Supabase
/// reenvía el mensaje tal cual: los datos vienen sueltos, más `type` y `event`,
/// que agrega la librería (`RealtimeChannel.send`). Por REST (el canal de quien
/// manda todavía no se unió) el servidor los envuelve en `payload`. Hasta la
/// 6.4.0 la app leía solo `payload`, y lo del socket, que es casi todo, se
/// tiraba sin error. Ver docs/SPEC_pulso_por_el_socket_2026-11-07.md.
///
/// **Regla:** ningún aviso nuestro lleva una clave propia llamada `payload`
/// (`test/pulso_por_el_socket_test.dart`). Devuelve un mapa nuevo, sin `type`
/// ni `event`; null si `payload` vino con otra forma: no se adivina.
Map<String, dynamic>? cuerpoDelBroadcast(Map<String, dynamic> mensaje) {
  final envuelto = mensaje['payload'];
  if (envuelto != null && envuelto is! Map) return null;
  final datos = envuelto is Map ? envuelto : mensaje;
  return {
    for (final e in datos.entries)
      if (e.key != 'type' && e.key != 'event') e.key.toString(): e.value,
  };
}
