import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/totem_config.dart';
import '../estilos/fuentes_totem.dart';
import '../providers/tiempos_a_mano_provider.dart';
import '../services/tiempos_a_mano.dart';

const _perla = Color(0xFFE2E2E2);
const _oro = TotemConfig.acentoPorDefecto;

/// Los segundos de la llegada, para cambiarlos a mano la noche de la fiesta:
/// "El nombre en grande − 4 s +" y "El salón con el camino − 8 s +". Cada toque
/// se aplica: no hay "Guardar". Lo usan Recepción (en la PC) y el celular de la
/// puerta.
class SegundosDeLaLlegada extends StatelessWidget {
  final TiemposAMano tiempos;

  /// Null mientras no se puede (el celular sin la central).
  final ValueChanged<TiemposAMano>? onCambio;

  const SegundosDeLaLlegada({
    super.key,
    required this.tiempos,
    required this.onCambio,
  });

  @override
  Widget build(BuildContext context) {
    final cambiar = onCambio;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Renglon(
          clave: 'nombre',
          titulo: 'El nombre en grande',
          valor: tiempos.nombre,
          minimo: TotemConfig.llegadaNombreMinimo,
          maximo: TotemConfig.llegadaNombreMaximo,
          onCambio:
              cambiar == null ? null : (s) => cambiar(tiempos.conNombre(s)),
        ),
        const SizedBox(height: 8),
        _Renglon(
          clave: 'camino',
          titulo: 'El salón con el camino',
          valor: tiempos.camino,
          minimo: TotemConfig.llegadaCaminoMinimo,
          maximo: TotemConfig.llegadaCaminoMaximo,
          onCambio:
              cambiar == null ? null : (s) => cambiar(tiempos.conCamino(s)),
        ),
        const SizedBox(height: 10),
        Text(
          'Cada familia dura ${tiempos.nombre + tiempos.camino} s, aunque haya '
          'gente esperando.',
          key: const ValueKey('segundos_total'),
          style: const TextStyle(
            fontFamily: FuentesTotem.linea,
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _Renglon extends StatelessWidget {
  final String clave;
  final String titulo;
  final int valor;
  final int minimo;
  final int maximo;
  final ValueChanged<int>? onCambio;

  const _Renglon({
    required this.clave,
    required this.titulo,
    required this.valor,
    required this.minimo,
    required this.maximo,
    required this.onCambio,
  });

  @override
  Widget build(BuildContext context) {
    final cambiar = onCambio;
    return Row(
      children: [
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(
              fontFamily: FuentesTotem.linea,
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
        IconButton(
          key: ValueKey('menos_$clave'),
          tooltip: 'Menos',
          onPressed:
              cambiar == null || valor <= minimo ? null : () => cambiar(valor - 1),
          icon: const Icon(Icons.remove_rounded),
          color: _perla,
        ),
        SizedBox(
          width: 46,
          child: Text(
            '$valor s',
            key: ValueKey('segundos_$clave'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: FuentesTotem.linea,
              fontWeight: FontWeight.w700,
              color: _oro,
              fontSize: 16,
            ),
          ),
        ),
        IconButton(
          key: ValueKey('mas_$clave'),
          tooltip: 'Más',
          onPressed:
              cambiar == null || valor >= maximo ? null : () => cambiar(valor + 1),
          icon: const Icon(Icons.add_rounded),
          color: _perla,
        ),
      ],
    );
  }
}

/// El reloj al lado de la paleta, en Recepción: abre los segundos de la
/// llegada de esa noche. Para cualquiera que tenga Recepción abierta: la
/// paleta (Personalizar) pide el permiso del tótem, esto no.
class BotonSegundosDeLaLlegada extends ConsumerWidget {
  final String eventoId;

  const BotonSegundosDeLaLlegada({super.key, required this.eventoId});

  static const ayuda = 'Segundos de la llegada';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton.filledTonal(
      key: const ValueKey('boton_segundos_llegada'),
      tooltip: ayuda,
      onPressed: () => abrirSegundosDeLaLlegada(context, eventoId),
      icon: const Icon(Icons.timer_outlined, size: 20),
    );
  }
}

/// La ventanita de los segundos de esa noche, en la PC.
Future<void> abrirSegundosDeLaLlegada(BuildContext context, String eventoId) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _oro.withValues(alpha: 0.35)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Consumer(
              builder: (context, ref, _) {
                final cfg = ref.watch(totemConfigDeLaNocheProvider(eventoId));
                final aMano = ref.watch(tiemposAManoProvider(eventoId));
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'LA LLEGADA · ESTA NOCHE',
                      style: TextStyle(
                        fontFamily: FuentesTotem.cartelera,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 2,
                        color: _oro,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Cuánto queda en la tele cada familia que entra. Cambia en '
                      'el momento, también sin internet.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SegundosDeLaLlegada(
                      tiempos: TiemposAMano.de(cfg),
                      onCambio: (t) => ref
                          .read(tiemposAManoProvider(eventoId).notifier)
                          .poner(t),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (aMano != null)
                          const Expanded(
                            child: Text(
                              'Cambiados a mano: mandan sobre Personalizar.',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('LISTO'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
