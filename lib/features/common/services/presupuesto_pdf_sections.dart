import '../../../models/evento.dart';
import '../../../models/presupuesto.dart';

/// Una fila visible del PDF: combo (agrupado) o ítem sin grupo.
///
/// El orden producido debe coincidir con el uso histórico: primero todos los grupos en el orden
/// de primera aparición de cada nombre de grupo en [Presupuesto.servicios]; después los ítems sin grupo en el mismo orden que en la lista.
class PresupuestoPdfSeccion {
  const PresupuestoPdfSeccion._({
    required this.esGrupo,
    required this.grupoNombre,
    required this.lineasOrdenadas,
  });

  final bool esGrupo;
  final String grupoNombre;
  final List<PresupuestoServicio> lineasOrdenadas;

  factory PresupuestoPdfSeccion.grupo(String nombreCombo, List<PresupuestoServicio> ordenadosPorCombo) {
    return PresupuestoPdfSeccion._(
      esGrupo: true,
      grupoNombre: nombreCombo,
      lineasOrdenadas: ordenadosPorCombo,
    );
  }

  factory PresupuestoPdfSeccion.individual(PresupuestoServicio s) {
    return PresupuestoPdfSeccion._(
      esGrupo: false,
      grupoNombre: '',
      lineasOrdenadas: [s],
    );
  }

  double get precioVisual {
    double t = 0;
    for (final s in lineasOrdenadas) {
      t += s.precioFinal * s.cantidad;
    }
    return t;
  }
}

/// Misma clasificación que en [PdfService] (combo vs suelto) y mismo orden dentro de combo (combo orden, nombre).
List<PresupuestoPdfSeccion> buildPresupuestoPdfSecciones(
  Presupuesto p, {
  bool soloExtras = false,
}) {
  final serviciosFiltrados = p.servicios.where((s) => soloExtras ? s.esExtra : !s.esExtra);
  final grouped = <String, List<PresupuestoServicio>>{};
  final singles = <PresupuestoServicio>[];

  for (final s in serviciosFiltrados) {
    if (s.grupo != null && s.grupo!.isNotEmpty) {
      grouped.putIfAbsent(s.grupo!, () => []).add(s);
    } else {
      singles.add(s);
    }
  }

  final secciones = <PresupuestoPdfSeccion>[];
  for (final e in grouped.entries) {
    final ordenados = List<PresupuestoServicio>.from(e.value)..sort(_sortCombo);
    secciones.add(PresupuestoPdfSeccion.grupo(e.key, ordenados));
  }
  for (final s in singles) {
    secciones.add(PresupuestoPdfSeccion.individual(s));
  }
  return secciones;
}

int _sortCombo(PresupuestoServicio a, PresupuestoServicio b) {
  final c = a.comboOrden.compareTo(b.comboOrden);
  if (c != 0) return c;
  return (a.nombre ?? '').compareTo(b.nombre ?? '');
}

/// Payload para prompts (solo datos que ya muestra la app; sin secretos).
Map<String, dynamic> payloadRedaccionSecciones(
  Presupuesto p,
  List<PresupuestoPdfSeccion> secciones,
  int variationSeed,
) {
  return {
    'variation_seed': variationSeed,
    'cliente_o_solicitante': p.cliente?.nombreCompleto ?? '',
    'titulo_festejado': p.tituloFestejado ?? '',
    'tipo_evento': Evento.formatearTipo(p.tipoEvento),
    if (p.lugar != null && p.lugar!.trim().isNotEmpty) 'lugar': p.lugar,
    if (p.fechaEvento != null)
      'fecha_evento_hint': '${p.fechaEvento!.day}/${p.fechaEvento!.month}/${p.fechaEvento!.year}',
    'secciones': secciones.map((sec) {
      if (!sec.esGrupo) {
        final s = sec.lineasOrdenadas.single;
        return {
          'tipo': 'individual',
          'lineas': [_lineaMap(s)],
        };
      }
      return {
        'tipo': 'grupo_combo',
        'nombre_combo': sec.grupoNombre,
        'lineas': sec.lineasOrdenadas.map(_lineaMap).toList(),
      };
    }).toList(),
  };
}

Map<String, dynamic> _lineaMap(PresupuestoServicio s) {
  return {
    'nombre_servicio': s.nombre ?? '',
    'cantidad': s.cantidad,
    'precio_final_unitario_hint': s.precioFinal,
    'detalle_cargado_por_usuario_para_pdf': s.detalleServicio ?? '',
    'categoria': s.categoria ?? '',
  };
}
