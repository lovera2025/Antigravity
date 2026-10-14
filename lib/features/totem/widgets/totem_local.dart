import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show kWebBaseUrl;
import '../../recepcion/providers/recepcion_provider.dart';
import '../estilos/escena_totem.dart';
import '../estilos/fondo_totem.dart';
import '../estilos/totem_estilo.dart';
import '../providers/totem_config_provider.dart';
import '../services/contenido_bienvenida.dart';
import '../services/ficha_totem.dart';
import '../services/reproductor_bienvenidas.dart';
import '../totem_orientation.dart';

/// Si el evento es masivo, según los eventos de esta PC. Null mientras se
/// leen; si no se pudieron leer, particular.
final eventoMasivoProvider =
    Provider.autoDispose.family<bool?, String>((ref, eventoId) {
  final eventos = ref.watch(eventosActivosProvider);
  if (eventos.isLoading && !eventos.hasValue) return null;
  final evento = eventos.value?.where((e) => e.id == eventoId).firstOrNull;
  return evento?.modalidad == 'masivo';
});

/// La apariencia del tótem del evento: la elegida en Personalizar o, si nadie
/// eligió, la del tipo de evento (Neón en un masivo, Cristal en un
/// particular). Null mientras no se sabe el tipo.
final estiloDelEventoProvider =
    Provider.autoDispose.family<EstiloTotem?, String>((ref, eventoId) {
  final cfg = ref.watch(totemConfigValueProvider(eventoId));
  final elegida = EstiloTotem.desdeClave(cfg.estilo);
  if (elegida != null) return elegida;
  final masivo = ref.watch(eventoMasivoProvider(eventoId));
  return masivo == null ? null : EstiloTotem.porDefecto(masivo: masivo);
});

/// El tótem de esta PC: la escena del salón, alimentada desde la base de la
/// PC. La usan la vista de Recepción y la pantalla del asesor.
///
/// Lee lo mismo que la lista de Recepción: la lista de la puerta y, en un
/// masivo, los alumnos con sus mesas, sillas y música ([FichaTotem]). Por eso
/// anda sin internet y saluda con la mesa aunque la fila de la puerta todavía
/// no la tenga. A quién se saluda, con quién y cuánto dura lo deciden
/// [ReproductorBienvenidas] y `IngresosTotem`, los mismos del tótem del salón:
/// lo visual se hace una sola vez.
///
/// Va con la clave del evento: otro evento es otro tótem, y su primera lectura
/// va en silencio.
class TotemLocal extends ConsumerStatefulWidget {
  final String eventoId;

  /// En 9:16 o 16:9 en el medio, como quedó el tótem del salón de este evento
  /// (la vista de Recepción). Si no, ocupa todo (la pantalla del asesor).
  final bool encuadrar;

  const TotemLocal({super.key, required this.eventoId, this.encuadrar = false});

  @override
  ConsumerState<TotemLocal> createState() => _TotemLocalState();
}

class _TotemLocalState extends ConsumerState<TotemLocal> {
  final _reproductor = ReproductorBienvenidas(salida: EscenaTotem.salida);
  FichaTotem? _ficha;
  bool _apaisada = false;
  bool _iniciado = false;

  @override
  void initState() {
    super.initState();
    unawaited(FondoTotem.precargar());

    // La ficha antes que la lista: la familia de cada uno tiene que estar
    // cuando llega su ingreso.
    ref.listenManual(
      puertaDelEventoProvider(widget.eventoId),
      (_, puerta) {
        final p = puerta.value;
        if (p != null) _tomarFicha(FichaTotem.desdePuerta(widget.eventoId, p));
      },
      fireImmediately: true,
    );
    ref.listenManual(
      invitadosStreamProvider(widget.eventoId),
      (_, lectura) => lectura.when(
        data: _reproductor.leyo,
        error: (_, _) => _reproductor.noPudoLeer(),
        loading: () {},
      ),
      fireImmediately: true,
    );

    if (widget.encuadrar) {
      TotemOrientationStore.load(widget.eventoId).then((o) {
        if (mounted && o == TotemOrientation.horizontal) {
          setState(() => _apaisada = true);
        }
      });
    }
    _iniciado = true;
  }

  void _tomarFicha(FichaTotem ficha) {
    _reproductor.familiaDe = (i) => ficha.familiaDe(i.id);
    // Durante `initState` todavía no se puede pedir que se redibuje.
    if (_iniciado) {
      setState(() => _ficha = ficha);
    } else {
      _ficha = ficha;
    }
  }

  @override
  void dispose() {
    _reproductor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(totemConfigValueProvider(widget.eventoId));
    final estilo = ref.watch(estiloDelEventoProvider(widget.eventoId));
    final masivo = ref.watch(eventoMasivoProvider(widget.eventoId)) ?? false;

    // Sin saber el tipo de evento no se sabe la apariencia: negro un instante,
    // antes que mostrar la que no es.
    final Widget escena = estilo == null
        ? const ColoredBox(color: Colors.black)
        : AnimatedBuilder(
            animation: _reproductor,
            builder: (context, _) {
              final actual = _reproductor.actual;
              return EscenaTotem(
                estilo: estilo,
                cfg: cfg,
                // El QR, solo en un particular, como en el salón.
                qrUrl: masivo
                    ? null
                    : '$kWebBaseUrl/lista?evento=${widget.eventoId}',
                llegada: actual == null
                    ? null
                    : ContenidoBienvenida.armar(actual, ficha: _ficha, cfg: cfg),
                claveLlegada: actual,
                saliendo: _reproductor.saliendo,
                enCamino: _reproductor.enCamino,
                empezo: actual?.empezo,
                fin: _reproductor.fin,
              );
            },
          );

    if (!widget.encuadrar) return escena;
    return Center(
      child: AspectRatio(
        aspectRatio: _apaisada ? 16 / 9 : 9 / 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: escena,
        ),
      ),
    );
  }
}
