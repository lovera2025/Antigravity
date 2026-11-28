import '../../../models/evento.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../datos/barra_repositorio.dart';

/// **Lo que la notebook le manda a la página del iPhone además de lo que viaja por la
/// red** (28-nov-2026): el catálogo, los precios con el stock del jefe, las recetas (el
/// Speed del vodka baja del stock) y el recargo, de su base. **Nunca el precio de
/// lista** (`barra_costos`): no se lee acá.
Future<Map<String, List<Map<String, Object?>>>> catalogoParaLaPagina(BarraDelJefe barra, String eventoId) async {
  final recargo = await barra.recargo(eventoId);
  return {
    'barra_productos': [for (final p in await barra.productos(conBajas: true)) p.toMap()],
    'barra_precios': [for (final p in await barra.precios(eventoId, conBajas: true)) p.toMap()],
    'barra_recetas': [for (final r in await barra.recetas(eventoId)) r.toMap()],
    'barra_recargos': [if (recargo != null) recargo.toMap()],
  };
}

/// La fiesta para la página: el título (antes del PIN) y el evento, **sin el PIN de
/// operador ni las observaciones** (la página no los necesita).
Map<String, Object?> fiestaParaLaPagina(Evento evento) => {
      'titulo': EventoPresentacion.tituloPrincipal(evento),
      'evento': evento.toJson()
        ..remove('pin_operador')
        ..remove('observaciones'),
    };
