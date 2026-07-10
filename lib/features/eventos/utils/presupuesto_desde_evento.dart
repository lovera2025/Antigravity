import '../../../models/evento.dart';
import '../../../models/presupuesto.dart';
import 'evento_presentacion.dart';

/// Arma un [Presupuesto] virtual desde un evento activo para regenerar el PDF élite.
Presupuesto presupuestoVirtualDesdeEvento({
  required Evento evento,
  required List<EventosServicios> servicios,
}) {
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
    detalleAnclaje: evento.observaciones,
    fechaVencimiento: vencimiento,
    fechaEvento: fechaEvt,
    estado: EstadoPresupuesto.aprobado,
    tituloFestejado: tituloLegacy,
    nombreFestejado: nombre,
    encabezadoEvento: encabezado,
    telefono: 'Maxi',
    instagram: 'junior_eventos_ok',
    createdAt: evento.createdAt ?? DateTime.now(),
    cliente: evento.cliente,
    servicios: lineas,
  );
}
