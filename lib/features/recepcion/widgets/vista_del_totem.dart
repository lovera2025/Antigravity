import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers/user_role_provider.dart';
import '../../totem/estilos/fuentes_totem.dart';
import '../../totem/widgets/totem_config_sheet.dart';
import '../../totem/widgets/totem_local.dart';

const _perla = Color(0xFFE2E2E2);

/// Si el usuario puede personalizar el tótem (el permiso del tótem; un admin
/// siempre).
final puedePersonalizarTotemProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(userRoleProvider).maybeWhen(
        data: (d) => d.permisos.puedeTotem,
        orElse: () => false,
      ),
);

/// Lo que va al lado de la lista en Recepción: el tótem de esta PC en chico
/// ([TotemLocal]), con la apariencia del evento arriba y la paleta para
/// personalizarlo. Un solo botón: la apariencia, la foto, los textos y el
/// color cambian con cada evento.
class VistaDelTotem extends ConsumerWidget {
  final String eventoId;

  const VistaDelTotem({super.key, required this.eventoId});

  static const titulo = 'VISTA DEL TÓTEM';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estilo = ref.watch(estiloDelEventoProvider(eventoId));
    final puede = ref.watch(puedePersonalizarTotemProvider);
    return ColoredBox(
      color: const Color(0xFF0B0B0D),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  Icon(
                    Icons.tv_rounded,
                    size: 18,
                    color: _perla.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      estilo == null
                          ? titulo
                          : '$titulo · ${estilo.nombre.toUpperCase()}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: FuentesTotem.cartelera,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  if (puede) BotonPersonalizarTotem(eventoId: eventoId),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TotemLocal(
                key: ValueKey(eventoId),
                eventoId: eventoId,
                encuadrar: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La paleta: abre Personalizar tótem del evento.
class BotonPersonalizarTotem extends StatelessWidget {
  final String eventoId;

  const BotonPersonalizarTotem({super.key, required this.eventoId});

  static const ayuda = 'Personalizar tótem';

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: ayuda,
      style: IconButton.styleFrom(
        backgroundColor: _perla,
        foregroundColor: Colors.black,
      ),
      onPressed: () =>
          showTotemConfigSheet(context: context, eventoId: eventoId),
      icon: const Icon(Icons.palette_rounded, size: 20),
    );
  }
}
