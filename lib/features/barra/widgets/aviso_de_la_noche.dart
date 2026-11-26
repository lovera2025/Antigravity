import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../central/central_barra_provider.dart';
import '../datos/barra_repositorio.dart';
import '../providers/barra_providers.dart';

/// Lo que VENDER avisa sobre la noche de la caja (26-nov-2026, la revisión independiente):
/// - **la caja es de una noche anterior** (una de la mañana, de prueba, o la de anoche que
///   siguió pasado el mediodía): lo que se venda va a esa noche y no a la de hoy;
/// - **la hora de la tablet está corrida** contra la de la notebook: sus cajas caerían en
///   otra noche.
///
/// Nada se cambia solo: se avisa, y la cajera cierra su caja o corrige la hora.
List<String> avisosDeLaNoche({
  required CajaBarra caja,
  required DateTime ahora,
  int? relojCorrido,
}) {
  final noche = DiaDeOperacion.deLaCaja(caja);
  return [
    if (!noche.esSinFecha && noche.isBefore(DiaDeOperacion.de(ahora)))
      'Esta caja es de la noche del ${noche.corto}: lo que vendas va a esa noche. Cerrala y '
          'abrí una para esta noche.',
    if (relojCorrido != null)
      'La hora de esta tablet está ${relojCorrido > 0 ? 'atrasada' : 'adelantada'} '
          '${relojCorrido.abs()} minutos contra la de la notebook. Corregila en Ajustes antes de '
          'abrir otra caja.',
  ];
}

/// Los avisos de [avisosDeLaNoche], en ámbar, debajo de la línea de VENDER.
class AvisoDeLaNoche extends ConsumerWidget {
  final CajaBarra caja;

  const AvisoDeLaNoche({super.key, required this.caja});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cliente = ref.watch(clienteDeLaBarraProvider);
    return ListenableBuilder(
      listenable: cliente ?? const _Quieto(),
      builder: (context, _) {
        final avisos = avisosDeLaNoche(
          caja: caja,
          ahora: ref.read(relojDeLaBarraProvider)(),
          relojCorrido: cliente?.relojCorrido,
        );
        if (avisos.isEmpty) return const SizedBox.shrink();
        return Padding(
          key: const Key('vender_aviso_de_la_noche'),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in avisos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF2B84B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          a,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF2B84B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Un Listenable que nunca cambia: sin cliente de la central.
class _Quieto implements Listenable {
  const _Quieto();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
