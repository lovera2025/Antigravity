import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/prestamo_alquiler.dart';
import '../clientes/repositories/clientes_repository.dart';
import '../common/services/pdf_service.dart';
import '../common/utils/currency_extensions.dart';
import '../mi_empresa/providers/finanzas_provider.dart';
import 'prestamo_alquiler_form_screen.dart';
import 'prestamo_redaccion_helper.dart';
import 'repositories/prestamos_alquiler_repository.dart';

/// Detalle de un préstamo: líneas, pagos, PDF y archivo operativo.
class PrestamoAlquilerDetalleScreen extends ConsumerStatefulWidget {
  final String prestamoId;

  const PrestamoAlquilerDetalleScreen({super.key, required this.prestamoId});

  @override
  ConsumerState<PrestamoAlquilerDetalleScreen> createState() => _PrestamoAlquilerDetalleScreenState();
}

class _PrestamoAlquilerDetalleScreenState extends ConsumerState<PrestamoAlquilerDetalleScreen> {
  bool _loading = true;
  PrestamoAlquiler? _prestamo;
  List<PrestamoAlquilerLinea> _lineas = [];
  List<PagoPrestamoAlquiler> _pagos = [];
  String _clienteNombre = '';
  String? _clienteTel;
  double _sumaPagos = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final repo = ref.read(prestamosAlquilerRepositoryProvider);
    final p = await repo.obtenerPorId(widget.prestamoId);
    if (p == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final lineas = await repo.lineasDe(widget.prestamoId);
    final pagos = await repo.pagosDe(widget.prestamoId);
    final suma = await repo.sumaPagos(widget.prestamoId);
    final cli = await ref.read(clientesRepositoryProvider).getById(p.clienteId);

    if (mounted) {
      setState(() {
        _prestamo = p;
        _lineas = lineas;
        _pagos = pagos;
        _sumaPagos = suma;
        _clienteNombre = cli?.nombreCompleto ?? 'Cliente';
        _clienteTel = cli?.telefono;
        _loading = false;
      });
    }
  }

  Future<void> _abrirEdicionPrestamo() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PrestamoAlquilerFormScreen(prestamoId: widget.prestamoId),
      ),
    );
    if (ok == true && mounted) await _cargar();
  }

  Future<void> _editarRedaccionPdf() async {
    final p = _prestamo;
    if (p == null) return;
    if (_lineas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay ítems para generar la redacción.')),
        );
      }
      return;
    }

    final lineasOrdenadas = List<PrestamoAlquilerLinea>.from(_lineas)
      ..sort((a, b) => a.orden.compareTo(b.orden));
    final tot = PrestamosAlquilerRepository.calcularTotales(
      lineas: lineasOrdenadas,
      aplicaIva: p.aplicaIva,
      alicuotaIva: p.alicuotaIva,
    );
    final redGenerada = PrestamoRedaccionHelper.generarCuerpo(
      nombreCliente: _clienteNombre,
      fechaInicio: p.fechaInicio,
      fechaFin: p.fechaFin,
      lineas: lineasOrdenadas,
      subtotalNeto: tot['subtotal_neto']!,
      montoIva: tot['monto_iva']!,
      total: tot['total']!,
      aplicaIva: p.aplicaIva,
      alicuotaIva: p.alicuotaIva,
    );
    final disInicial = (p.textoDisclaimer ?? '').trim().isEmpty
        ? PrestamoRedaccionHelper.disclaimerPredeterminado()
        : p.textoDisclaimer!.trim();
    final textoGuardado = (p.textoRedaccion ?? '').trim();

    final redCtrl = TextEditingController(text: redGenerada);
    final disCtrl = TextEditingController(text: disInicial);
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar texto del PDF'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Texto generado desde los ítems actuales; podés ajustarlo y guardar solo si hay cambios.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (textoGuardado.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              setDialogState(() => redCtrl.text = textoGuardado);
                            },
                            child: const Text('USAR TEXTO GUARDADO'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      const Text('Cuerpo / redacción', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      TextField(controller: redCtrl, maxLines: 10),
                      const SizedBox(height: 16),
                      const Text('Disclaimer / condiciones', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      TextField(controller: disCtrl, maxLines: 6),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('GUARDAR')),
              ],
            );
          },
        ),
      );
      if (ok != true || !mounted) return;

      final nuevoRed = redCtrl.text.trim();
      final nuevoDis = disCtrl.text.trim();
      final viejoRed = (p.textoRedaccion ?? '').trim();
      final viejoDis = (p.textoDisclaimer ?? '').trim();
      if (nuevoRed == viejoRed && nuevoDis == viejoDis) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sin cambios respecto al texto guardado.')),
        );
        return;
      }

      await ref.read(prestamosAlquilerRepositoryProvider).actualizarTextos(
            prestamoId: widget.prestamoId,
            textoRedaccion: nuevoRed,
            textoDisclaimer: nuevoDis,
          );
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Texto del PDF actualizado')),
        );
      }
    } finally {
      redCtrl.dispose();
      disCtrl.dispose();
    }
  }

  Future<void> _pdf() async {
    final p = _prestamo;
    if (p == null) return;
    await PdfService.generarPrestamoAlquilerPdf(
      prestamo: p,
      lineas: _lineas,
      clienteNombre: _clienteNombre,
      clienteTelefono: _clienteTel,
    );
  }

  Future<void> _archivar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archivar préstamo'),
        content: const Text(
          'Oculta este préstamo del listado. Los pagos registrados siguen en Mi empresa.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ARCHIVAR')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(prestamosAlquilerRepositoryProvider).archivarOperativo(widget.prestamoId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _registrarPago() async {
    final montoCtrl = TextEditingController();
    final conceptoCtrl = TextEditingController(text: 'Pago alquiler');
    String medioPagoSeleccionado = 'Efectivo';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Registrar pago'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(labelText: 'Monto (\$)', prefixIcon: Icon(Icons.attach_money)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: conceptoCtrl,
                  decoration: const InputDecoration(labelText: 'Concepto (ej. Seña, saldo)', prefixIcon: Icon(Icons.description)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: medioPagoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Medio de Pago',
                    prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                  ],
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => medioPagoSeleccionado = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('GUARDAR'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final m = double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
    final conceptoTxt = conceptoCtrl.text.trim();
    montoCtrl.dispose();
    conceptoCtrl.dispose();
    if (m <= 0) return;
    try {
      await ref.read(prestamosAlquilerRepositoryProvider).registrarPago(
            prestamoId: widget.prestamoId,
            monto: m,
            concepto: conceptoTxt.isEmpty ? null : conceptoTxt,
            medioPago: medioPagoSeleccionado,
          );
      ref.invalidate(finanzasProvider);
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago registrado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('dd/MM/yyyy');

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: gold)));
    }
    if (_prestamo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Préstamo')),
        body: const Center(child: Text('No encontrado')),
      );
    }

    final p = _prestamo!;
    final total = p.total;
    final saldo = total - _sumaPagos;

    return Scaffold(
      appBar: AppBar(
        title: Text('PRÉSTAMO', style: GoogleFonts.oswald(fontWeight: FontWeight.w900, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: _abrirEdicionPrestamo,
            tooltip: 'Editar préstamo',
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            onPressed: _editarRedaccionPdf,
            tooltip: 'Solo texto PDF',
          ),
          IconButton(icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: _pdf, tooltip: 'PDF'),
          if (p.visibleListado == true)
            IconButton(icon: const Icon(Icons.archive_outlined), onPressed: _archivar, tooltip: 'Archivar'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registrarPago,
        backgroundColor: gold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.payments_rounded),
        label: const Text('PAGO', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_clienteNombre.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            '${fmt.format(p.fechaInicio)} — ${fmt.format(p.fechaFin)}',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _chip('Total ${total.toCurrency()}', gold),
              const SizedBox(width: 8),
              _chip('Pagado ${_sumaPagos.toCurrency()}', Colors.greenAccent.shade700),
              const SizedBox(width: 8),
              _chip('Saldo ${saldo.toCurrency()}', saldo > 0.009 ? Colors.orangeAccent : Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 24),
          const Text('ÍTEMS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 8),
          ..._lineas.map((l) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.descripcion, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${l.cantidad} × ${l.precioUnitario.toCurrency()}'),
              trailing: Text(l.lineaTotal.toCurrency(), style: const TextStyle(fontWeight: FontWeight.w900)),
            );
          }),
          const Divider(height: 32),
          const Text('PAGOS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
          if (_pagos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Sin pagos aún', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)),
            )
          else
            ..._pagos.map((pago) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, color: gold),
                title: Text(pago.concepto ?? 'Pago', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(pago.fechaPago)),
                trailing: Text('+${pago.monto.toCurrency()}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900)),
              );
            }),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: c)),
    );
  }
}
