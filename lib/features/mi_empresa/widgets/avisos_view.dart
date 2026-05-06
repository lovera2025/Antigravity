import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/obligacion_pago.dart';
import '../providers/obligaciones_provider.dart';
import '../../common/utils/currency_extensions.dart';
import 'nuevo_aviso_dialog.dart';
import 'pagar_aviso_dialog.dart';

class AvisosView extends ConsumerStatefulWidget {
  final bool isDark;
  final Color gold;

  const AvisosView({super.key, required this.isDark, required this.gold});

  @override
  ConsumerState<AvisosView> createState() => _AvisosViewState();
}

class _AvisosViewState extends ConsumerState<AvisosView> {
  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(obligacionesProvider);

    if (stateAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final obligacionesFull = stateAsync.value ?? [];
    final pendientes = obligacionesFull.where((o) => o.estado == 'pendiente').toList();
    final pagados = obligacionesFull.where((o) => o.estado == 'pagado').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SISTEMA DE AVISOS Y VENCIMIENTOS',
                  style: GoogleFonts.oswald(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
                Text(
                  'Gestión de impuestos, expensas y cuentas recurrentes',
                  style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.white54 : Colors.black54),
                ),
              ],
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add_alert_rounded, size: 16),
              label: const Text('Nuevo Aviso', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: widget.gold,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const NuevoAvisoDialog(),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 32),

        _sectionTitle('PENDIENTES', Icons.timer_outlined, Colors.orange),
        const SizedBox(height: 16),
        if (pendientes.isEmpty)
          Center(
             child: Padding(
               padding: const EdgeInsets.all(32.0),
               child: Text('Sin obligaciones pendientes.', style: TextStyle(color: widget.isDark ? Colors.white38 : Colors.black38)),
             )
          )
        else
          ...pendientes.map((o) => _buildCard(o, true)),

        const SizedBox(height: 32),
        _sectionTitle('HISTORIAL RECIENTE', Icons.check_circle_outline, Colors.green),
        const SizedBox(height: 16),
        ...pagados.map((o) => _buildCard(o, false)),
      ],
    );
  }

  Widget _sectionTitle(String t, IconData i, Color c) {
    return Row(
      children: [
        Icon(i, size: 16, color: c),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.5, color: Colors.grey)),
      ],
    );
  }

  Widget _buildCard(ObligacionPago o, bool isPendiente) {
    final now = DateTime.now();
    final dias = o.fechaVencimiento.difference(DateTime(now.year, now.month, now.day)).inDays;
    
    Color accent = Colors.grey;
    String status = 'Pagado';
    if (isPendiente) {
      if (dias < 0) {
        accent = Colors.redAccent;
        status = 'Vencido hace ${dias.abs()} días';
      } else if (dias == 0) {
        accent = Colors.redAccent;
        status = 'VENCE HOY';
      } else if (dias <= 3) {
        accent = Colors.orangeAccent;
        status = 'Vence en $dias días';
      } else {
        accent = widget.gold;
        status = 'Vence en $dias días';
      }
    }

    final isEmpresa = o.tipoObligacion == 'empresa';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
               color: isEmpresa ? Colors.blue.withValues(alpha: 0.1) : Colors.purple.withValues(alpha: 0.1),
               borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isEmpresa ? Icons.domain_rounded : Icons.person_rounded, 
              color: isEmpresa ? Colors.blue : Colors.purple,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      o.titulo.toUpperCase(),
                      style: GoogleFonts.oswald(fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: accent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isEmpresa ? 'Gastos Empresa' : 'Gastos Personal / Adrián',
                  style: TextStyle(fontSize: 10, color: widget.isDark ? Colors.white54 : Colors.black54),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
               Text(
                 o.montoEstimado > 0 ? o.montoEstimado.toCurrency() : 'Monto Variable',
                 style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
               ),
               if (o.fechaPago != null)
                 Text(
                   'Pagado el ${o.fechaPago!.day}/${o.fechaPago!.month}/${o.fechaPago!.year}',
                   style: const TextStyle(fontSize: 9, color: Colors.green),
                 ),
            ],
          ),
          if (isPendiente) ...[
            const SizedBox(width: 20),
            IconButton.filled(
              icon: const Icon(Icons.check_circle_outline, size: 20),
              color: Colors.white,
              style: IconButton.styleFrom(backgroundColor: const Color(0xFF00B894)),
              tooltip: 'Marcar Pagado',
              onPressed: () {
                if (isEmpresa) {
                  showDialog(
                    context: context,
                    builder: (_) => PagarAvisoDialog(obligacion: o),
                  );
                } else {
                  // Pago personal -> Desactivar alarma directo
                  _marcarPagadoPersonal(o);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  void _marcarPagadoPersonal(ObligacionPago o) async {
    final act = o.copyWith(estado: 'pagado', fechaPago: DateTime.now());
    await ref.read(obligacionesProvider.notifier).guardar(act);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aviso descartado (no deducido de finanzas)')));

    // Preguntar si duplica
    final dup = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Recrear para el mes que viene?'),
        content: const Text('Se guardará un nuevo aviso para el mes próximo con el mismo monto estimado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, duplicar')),
        ]
      )
    );

    if (dup == true) {
      final next = ObligacionPago(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        titulo: o.titulo,
        tipoObligacion: o.tipoObligacion,
        fechaVencimiento: DateTime(o.fechaVencimiento.year, o.fechaVencimiento.month + 1, o.fechaVencimiento.day),
        montoEstimado: o.montoEstimado,
        createdAt: DateTime.now(),
      );
      await ref.read(obligacionesProvider.notifier).guardar(next);
    }
  }
}
