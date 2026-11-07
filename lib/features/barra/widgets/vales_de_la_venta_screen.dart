import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja_sesiones/providers/app_role_provider.dart';
import '../cuentas/pesos.dart';
import '../cuentas/vales_de_barra.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/modelo_ticket.dart';
import '../providers/barra_providers.dart';
import 'elegir_vales.dart';

/// Quién queda anotado en lo que hace la cajera: su nombre al entrar, o el de la caja.
String quienEnLaBarra(WidgetRef ref, CajaBarra caja) =>
    ref.read(appRoleProvider).operador?.nombre ?? caja.operadorNombre ?? 'Barra';

/// Anota un vale que salió y lo manda a subir. Si no se puede anotar, el vale igual
/// salió: lo dice el registro de la app, no frena.
Future<void> anotarValeQueSalio(
  WidgetRef ref, {
  required VentaBarra venta,
  required CajaBarra caja,
  required Vale vale,
  CopiaDeVale? copia,
}) async {
  final anotado = await ref.read(barraDeLaCajaProvider).anotarVale(ValeBarra.salio(
        venta: venta,
        bebidas: vale.bebidas,
        porSeparado: vale.porSeparado,
        numeroVale: vale.numero,
        copiaNumero: copia?.numero ?? 0,
        motivo: copia?.motivo,
        hechoPor: quienEnLaBarra(ref, caja),
        ahora: DateTime.now(),
      ));
  unawaited(ref.read(subirDeLaBarraProvider)('barra_vales', anotado.id));
}

/// Saca el ticket con precios de una venta, si el cliente lo pide. **Sin logo**, para
/// ahorrar papel (como los vales). True si salió.
Future<bool> imprimirTicketConPrecios(
  WidgetRef ref, {
  required VentaBarra venta,
  required CajaBarra caja,
  required String fiesta,
}) async {
  try {
    return await ref
        .read(papelDeLaBarraProvider)
        .imprimir(ModeloTicket.deVenta(venta, caja: caja, fiesta: fiesta));
  } catch (_) {
    return false;
  }
}

/// Los vales de una venta (`ElegirVales`): después de cobrar, con la venta guardada y el
/// vuelto; o más tarde, desde VENTAS, para imprimir los que no salieron ([yaSalieron]).
/// Cada vale que sale queda anotado. Abajo, el ticket con precios por si lo piden.
class ValesDeLaVentaScreen extends ConsumerStatefulWidget {
  final VentaBarra venta;
  final CajaBarra caja;
  final String fiesta;

  /// Los vales que ya salieron de esta venta. Vacío: recién cobrada.
  final List<ValeBarra> yaSalieron;

  /// Recién cobrada: arriba, "Venta guardada" con el vuelto.
  final bool recienCobrada;

  const ValesDeLaVentaScreen({
    super.key,
    required this.venta,
    required this.caja,
    required this.fiesta,
    this.yaSalieron = const [],
    this.recienCobrada = true,
  });

  @override
  ConsumerState<ValesDeLaVentaScreen> createState() => _ValesDeLaVentaScreenState();
}

class _ValesDeLaVentaScreenState extends ConsumerState<ValesDeLaVentaScreen> {
  bool _todoImpreso = false;
  bool _ticketImprimiendo = false;
  String? _avisoTicket;

  Future<void> _listo() async {
    if (!_todoImpreso) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(widget.recienCobrada
              ? 'Quedan bebidas sin vale. ¿Volver a vender igual?'
              : 'Quedan bebidas sin vale. ¿Salir igual?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NO, IMPRIMIR')),
            FilledButton(
              key: const Key('vales_salir_igual'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SÍ, VOLVER'),
            ),
          ],
        ),
      );
      if (seguir != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _ticket() async {
    setState(() {
      _ticketImprimiendo = true;
      _avisoTicket = null;
    });
    final salio = await imprimirTicketConPrecios(
      ref,
      venta: widget.venta,
      caja: widget.caja,
      fiesta: widget.fiesta,
    );
    if (!mounted) return;
    setState(() {
      _ticketImprimiendo = false;
      _avisoTicket = salio
          ? 'Salió el ticket con precios.'
          : 'No salió el ticket. ¿La impresora está prendida y cerca?';
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.venta;
    final papel = ref.read(papelDeLaBarraProvider);
    final numero = v.numero.toString().padLeft(4, '0');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) unawaited(_listo());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Vales · N° $numero'),
          actions: [
            TextButton(
              key: const Key('vales_listo'),
              onPressed: _listo,
              child: Text(widget.recienCobrada ? 'LISTO, OTRA VENTA' : 'LISTO'),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                if (widget.recienCobrada)
                  Card(
                    key: const Key('vales_venta_guardada'),
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    // Sobre el fondo oscuro del diseño: verde tenue, no el claro de antes.
                    color: Colors.green.withValues(alpha: 0.16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade400),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Venta guardada: ${pesos(v.cobrado)}')),
                          if (v.vuelto > 0)
                            Text(
                              'Vuelto ${pesos(v.vuelto)}',
                              key: const Key('vales_vuelto'),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: ElegirVales(
                    venta: v,
                    caja: widget.caja,
                    fiesta: widget.fiesta,
                    imprimir: papel.imprimir,
                    yaSalieron: widget.yaSalieron,
                    anotar: (vale) => anotarValeQueSalio(ref, venta: v, caja: widget.caja, vale: vale),
                    alImprimir: (todo) => setState(() => _todoImpreso = todo),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (_avisoTicket != null)
                        Text(_avisoTicket!, key: const Key('vales_aviso_ticket')),
                      OutlinedButton.icon(
                        key: const Key('vales_ticket'),
                        onPressed: _ticketImprimiendo ? null : _ticket,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('TICKET CON PRECIOS'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
