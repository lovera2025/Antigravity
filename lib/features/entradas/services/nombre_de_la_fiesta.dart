import '../../../models/evento.dart';
import '../../eventos/utils/evento_presentacion.dart';

/// Cómo se nombra una fiesta en la venta de entradas (la pantalla, la caja y el
/// comprobante): la institución, como en ENTRADAS de la fiesta; si el evento no
/// la trae, su título de siempre. Nunca un "Evento" a secas.
String nombreDeLaFiesta(Evento evento) {
  final institucion = evento.cliente?.nombreCompleto.trim() ?? '';
  return institucion.isNotEmpty
      ? institucion
      : EventoPresentacion.tituloPrincipal(evento);
}
