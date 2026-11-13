import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../delegado/datos/link_del_delegado.dart';
import '../../delegado/delegado_providers.dart';
import '../../eventos/detalle_evento_masivo_screen.dart';
import '../../eventos/repositories/eventos_repository.dart';

/// Las alertas del link del delegado en el Centro de Comando (6.8.0): una por
/// fiesta, cuando un delegado **envió** o cuando el link venció con algo sin
/// traer. Nunca por cada alumno que guardan.
///
/// A diferencia de las demás alertas, **se tocan**: abren ese evento masivo
/// directo en la revisión de lo que mandaron. Las ve cualquiera; aceptar y
/// cargar es del jefe, y eso lo frena la pantalla de la fiesta.
///
/// Sin avisos no dibuja nada.
class AlertasDelDelegado extends ConsumerWidget {
  const AlertasDelDelegado({super.key});

  Future<void> _abrir(
    BuildContext context,
    WidgetRef ref,
    AvisoDelDelegado aviso,
  ) async {
    final evento =
        await ref.read(eventosRepositoryProvider).getById(aviso.eventoId);
    if (!context.mounted) return;
    if (evento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esa fiesta todavía no bajó a esta PC. Probá de nuevo en un rato.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetalleEventoMasivoScreen(
          evento: evento,
          abrirLoDelDelegado: true,
        ),
      ),
    );
    // Al volver, lo que había para traer pudo cambiar.
    ref.invalidate(avisosDelDelegadoProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avisos = ref.watch(avisosDelDelegadoProvider).value ?? const [];
    if (avisos.isEmpty) return const SizedBox.shrink();
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    const color = Color(0xFF7E57C2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in avisos)
            Material(
              key: Key('alerta_delegado_${a.eventoId}'),
              color: color.withValues(alpha: oscuro ? 0.16 : 0.09),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: color.withValues(alpha: 0.45)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _abrir(context, ref, a),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.music_note_rounded,
                        color: color,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          a.texto,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: color,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
