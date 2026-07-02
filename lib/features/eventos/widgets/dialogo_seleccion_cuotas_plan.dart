import 'package:flutter/material.dart';

import '../../common/utils/currency_extensions.dart';
import '../services/cobro_abono_acumulado.dart';

class SeleccionCuotasPlanResult {
  final double monto;
  final Set<int> cuotasSeleccionadas;

  const SeleccionCuotasPlanResult({
    required this.monto,
    required this.cuotasSeleccionadas,
  });
}

/// Diálogo con checkboxes por cuota (pagada / parcial / pendiente).
Future<SeleccionCuotasPlanResult?> mostrarDialogoSeleccionCuotasPlan(
  BuildContext context, {
  required String titulo,
  required double cuotaPura,
  required int totalCuotas,
  required double grossHistorico,
  required double deudaMaxima,
}) {
  final desglose = desgloseCuotasPlan(
    grossHistorico: grossHistorico,
    cuotaPura: cuotaPura,
    totalCuotas: totalCuotas,
  );
  if (desglose.isEmpty) return Future.value(null);

  final primera = primeraCuotaSeleccionable(desglose);
  if (primera == null) return Future.value(null);

  return showDialog<SeleccionCuotasPlanResult>(
    context: context,
    builder: (ctx) {
      var seleccionadas = {primera};
      return StatefulBuilder(
        builder: (ctx, setInternal) {
          final monto = montoFaltanteCuotasSeleccionadas(
            seleccionadas,
            desglose,
          );
          final montoOk = monto > 0.01 && monto <= deudaMaxima + 0.01;

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const Text(
                  'SELECCIONAR CUOTAS',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Marcá cuotas consecutivas desde la primera incompleta.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    ...desglose.map((c) {
                      final sel = seleccionadas.contains(c.numero);
                      final estadoLabel = switch (c.estado) {
                        EstadoCuotaPlan.pagada => 'PAGADA',
                        EstadoCuotaPlan.parcial => 'PARCIAL',
                        EstadoCuotaPlan.pendiente => 'PENDIENTE',
                      };
                      final estadoColor = switch (c.estado) {
                        EstadoCuotaPlan.pagada => Colors.green.shade700,
                        EstadoCuotaPlan.parcial => const Color(0xFFD4AF37),
                        EstadoCuotaPlan.pendiente => Colors.blueGrey,
                      };
                      String subtitulo;
                      if (c.estado == EstadoCuotaPlan.parcial) {
                        subtitulo =
                            '${c.pagadoEnCuota.toCurrency()} / ${c.montoCuota.toCurrency()} · faltan ${c.faltante.toCurrency()}';
                      } else if (c.estado == EstadoCuotaPlan.pagada) {
                        subtitulo = c.montoCuota.toCurrency();
                      } else {
                        subtitulo = 'Faltan ${c.faltante.toCurrency()}';
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: c.estado == EstadoCuotaPlan.pagada ? true : sel,
                          tristate: false,
                          onChanged: c.seleccionable
                              ? (v) {
                                  setInternal(() {
                                    seleccionadas = alternarSeleccionCuotaPlan(
                                      numero: c.numero,
                                      seleccionActual: seleccionadas,
                                      desglose: desglose,
                                    );
                                  });
                                }
                              : null,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Cuota ${c.numero}/$totalCuotas',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: c.seleccionable
                                        ? null
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: estadoColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: estadoColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  estadoLabel,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: estadoColor,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            subtitulo,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: c.estado == EstadoCuotaPlan.parcial
                                  ? const Color(0xFFB8960C)
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total a cobrar',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            monto.toCurrency(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Color(0xFFD4AF37),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.white,
                ),
                onPressed: montoOk
                    ? () => Navigator.pop(
                          ctx,
                          SeleccionCuotasPlanResult(
                            monto: monto,
                            cuotasSeleccionadas: Set<int>.from(seleccionadas),
                          ),
                        )
                    : null,
                child: const Text('CONFIRMAR'),
              ),
            ],
          );
        },
      );
    },
  );
}
