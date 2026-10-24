import '../../../models/evento.dart';
import '../../../models/presupuesto.dart';
import 'evento_presentacion.dart';

/// El WhatsApp y el Instagram del pie cuando el evento no salió de un
/// presupuesto (o el presupuesto no los tiene).
const kTelefonoPieDeLaCasa = 'Maxi';
const kInstagramDeLaCasa = 'junior_eventos_ok';

/// Arma un [Presupuesto] virtual desde un evento activo para regenerar el PDF élite.
///
/// [origen] es el presupuesto del que salió el evento: de ahí salen el lugar,
/// el WhatsApp y el Instagram del pie y el asesor (6.2.1). Antes el lugar se
/// perdía y el pie salía siempre con los de la casa.
Presupuesto presupuestoVirtualDesdeEvento({
  required Evento evento,
  required List<EventosServicios> servicios,
  Presupuesto? origen,
}) {
  String? deOrigen(String? v) => (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  final legacy = EventoPresentacion.dividirTituloFestejadoLegacy(
    evento.tituloFestejado,
    evento.tipo,
  );
  final nombre = evento.nombreFestejado?.trim().isNotEmpty == true
      ? evento.nombreFestejado!.trim()
      : (legacy.nombreFestejado ??
          EventoPresentacion.homenajeadoDesdeObservaciones(evento.observaciones));
  final encabezado = evento.encabezadoEvento?.trim().isNotEmpty == true
      ? evento.encabezadoEvento!.trim()
      : legacy.encabezadoEvento;
  final tituloLegacy = encabezado ?? nombre;

  final lineas = servicios
      .map(
        (s) => PresupuestoServicio(
          id: s.id,
          presupuestoId: evento.id,
          servicioId: s.servicioId,
          precioFinal: s.precioFinalAcordado,
          cantidad: s.cantidad,
          detalleServicio: s.detalleServicio,
          grupo: s.grupo,
          comboOrden: s.comboOrden,
          esExtra: s.esExtra,
          servicio: s.servicio,
        ),
      )
      .toList();

  final fechaEvt = evento.fechaEvento;
  final vencimiento = fechaEvt.isAfter(DateTime.now())
      ? fechaEvt
      : DateTime.now().add(const Duration(days: 7));

  return Presupuesto(
    id: evento.id,
    clienteId: evento.clienteId,
    tipoEvento: evento.tipo,
    lugar: deOrigen(origen?.lugar),
    vendedorNombre: deOrigen(origen?.vendedorNombre),
    detalleAnclaje: evento.observaciones,
    fechaVencimiento: vencimiento,
    fechaEvento: fechaEvt,
    estado: EstadoPresupuesto.aprobado,
    tituloFestejado: tituloLegacy,
    nombreFestejado: nombre,
    encabezadoEvento: encabezado,
    telefono: deOrigen(origen?.telefono) ?? kTelefonoPieDeLaCasa,
    instagram: deOrigen(origen?.instagram) ?? kInstagramDeLaCasa,
    createdAt: evento.createdAt ?? DateTime.now(),
    cliente: evento.cliente,
    servicios: lineas,
  );
}
