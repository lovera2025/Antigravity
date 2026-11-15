import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../barra/cuentas/cierre_de_barra.dart' show diferenciaEnPalabras;
import '../../barra/cuentas/pesos.dart';
import '../../barra/jefe/barra_jefe_providers.dart';
import '../../barra/jefe/elegir_fiesta.dart';
import '../../barra/services/fiestas_del_jefe.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../../../models/evento.dart';

/// Lo que comparten BARRA y ENTRADAS en el cierre de caja: los colores, cómo
/// se dice la diferencia y la tarjeta de la fiesta con CAMBIAR DE FIESTA.
const oroDelSector = Color(0xFFD4AF37);
const efectivoDelSector = Color(0xFF00B894);
const transferenciaDelSector = Color(0xFF6C63FF);

Color colorDeLaDiferencia(double d) {
  final c = centavos(d);
  if (c == 0) return const Color(0xFF2E9E5B);
  return c < 0 ? const Color(0xFFE74C3C) : const Color(0xFFD68A00);
}

/// "Justo", "Sobran $ 500", "Faltan $ 1.500".
String diferenciaCorta(double d) =>
    diferenciaEnPalabras(d).replaceFirst('Justo, sin diferencia', 'Justo');

/// La fiesta elegida (la próxima, o la de anoche hasta el día siguiente) con
/// CAMBIAR DE FIESTA. **La elección es una sola para BARRA y ENTRADAS**
/// (`fiestaElegidaDelJefeProvider`). [clave] arma las claves de la prueba:
/// `<clave>_fiesta` y `<clave>_cambiar_fiesta`.
class FiestaDelCierre extends ConsumerWidget {
  final FiestasDelJefe fiestas;
  final Evento fiesta;
  final bool isDark;
  final String clave;

  const FiestaDelCierre({
    super.key,
    required this.fiestas,
    required this.fiesta,
    required this.isDark,
    required this.clave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoy = ref.read(relojDelJefeProvider)();
    final fecha = fechaConCuando(
      fiesta.fechaEvento,
      hoy,
      esLaQueAbre: fiesta.id == fiestas.laQueAbre?.id,
    );
    Future<void> cambiar() async {
      final id = await showDialog<String>(
        context: context,
        builder: (_) => ElegirFiestaDelJefe(fiestas: fiestas, actual: fiesta.id, hoy: hoy),
      );
      if (id != null) ref.read(fiestaElegidaDelJefeProvider.notifier).elegir(id);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: oroDelSector.withValues(alpha: 0.35)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LA FIESTA',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                  color: oroDelSector,
                ),
              ),
              Text(
                EventoPresentacion.tituloPrincipal(fiesta),
                key: Key('${clave}_fiesta'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                fecha,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
          OutlinedButton(
            key: Key('${clave}_cambiar_fiesta'),
            onPressed: fiestas.todas.length > 1 ? cambiar : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: oroDelSector,
              side: const BorderSide(color: oroDelSector),
            ),
            child: const Text(
              'CAMBIAR DE FIESTA',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
