import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../common/services/pdf_service.dart';
import '../../common/utils/currency_extensions.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../providers/finanzas_provider.dart';
import '../repositories/finanzas_repository.dart';

/// Admin: buscar cobro y marcarlo como anulado (no borra la fila). Ajusta saldos / totales.
class AnularCobroCuotaDialog extends ConsumerStatefulWidget {
  const AnularCobroCuotaDialog({super.key});

  @override
  ConsumerState<AnularCobroCuotaDialog> createState() => _AnularCobroCuotaDialogState();
}

class _PdfPayload {
  final String nombrePagador;
  final String referenciaEvento;
  final String fuenteLabel;
  final double monto;
  final String? concepto;
  final DateTime? fechaCobroUtc;
  final String motivo;
  final DateTime fechaAnulUtc;
  final String idRegistro;

  const _PdfPayload({
    required this.nombrePagador,
    required this.referenciaEvento,
    required this.fuenteLabel,
    required this.monto,
    required this.concepto,
    required this.fechaCobroUtc,
    required this.motivo,
    required this.fechaAnulUtc,
    required this.idRegistro,
  });
}

class _AnularCobroCuotaDialogState extends ConsumerState<AnularCobroCuotaDialog> {
  final _searchCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  bool _searching = false;
  bool _submitting = false;
  bool _generandoPdf = false;
  List<Map<String, dynamic>> _resultados = [];
  Map<String, dynamic>? _seleccion;
  _PdfPayload? _pdfListo;

  static String _etf(String tabla) {
    switch (tabla) {
      case 'pagos_contrato_alumno':
        return 'Masivo';
      case 'transacciones':
        return 'Particular';
      case 'pagos_prestamo_alquiler':
        return 'Alquiler ítems';
      default:
        return tabla;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresá al menos 2 caracteres para buscar.')),
        );
      }
      return;
    }

    setState(() {
      _searching = true;
      _seleccion = null;
      _resultados = [];
      _pdfListo = null;
    });

    try {
      final repo = ref.read(finanzasRepositoryProvider);
      final list = await repo.buscarPagosParaCorregirMedio(q);
      if (!mounted) return;
      setState(() {
        _resultados = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al buscar: $e')),
      );
    }
  }

  Future<void> _compartirPdf() async {
    final p = _pdfListo;
    if (p == null) return;
    setState(() => _generandoPdf = true);
    try {
      await PdfService.compartirComprobanteAnulacionCobro(
        nombrePagador: p.nombrePagador,
        referenciaEvento: p.referenciaEvento,
        fuenteLabel: p.fuenteLabel,
        monto: p.monto,
        concepto: p.concepto,
        fechaCobroOriginalUtc: p.fechaCobroUtc,
        motivoAnulacion: p.motivo,
        fechaAnulacionUtc: p.fechaAnulUtc,
        idRegistro: p.idRegistro,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  Future<void> _anular() async {
    final sel = _seleccion;
    final motivo = _motivoCtrl.text.trim();
    if (sel == null) return;
    if (motivo.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describí el motivo (mínimo 8 caracteres).')),
      );
      return;
    }

    final tabla = sel['tabla']?.toString();
    final id = sel['id']?.toString();
    if (tabla == null || id == null || id.isEmpty) return;

    setState(() => _submitting = true);

    try {
      final repo = ref.read(finanzasRepositoryProvider);
      final contratoId = await repo.anularPagoConMotivo(tabla: tabla, id: id, motivo: motivo);
      if (contratoId != null && contratoId.isNotEmpty) {
        await ref.read(contratosRepositoryProvider).recalcularProgresoContrato(contratoId);
      }
      await ref.read(finanzasProvider.notifier).recargar();

      final fechaAnul = ArTime.nowUtc();
      final fechaCobroRaw = sel['fecha_pago']?.toString();
      final fechaCobro = DateTime.tryParse(fechaCobroRaw ?? '');

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _pdfListo = _PdfPayload(
          nombrePagador: sel['titulo']?.toString() ?? '',
          referenciaEvento: sel['subtitulo']?.toString() ?? '',
          fuenteLabel: _etf(tabla),
          monto: (sel['monto'] as num?)?.toDouble() ?? 0,
          concepto: sel['concepto']?.toString(),
          fechaCobroUtc: fechaCobro,
          motivo: motivo,
          fechaAnulUtc: fechaAnul,
          idRegistro: id,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cobro anulado. Podés compartir el comprobante PDF.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo anular: $e')),
      );
    }
  }

  String _lblMedio(dynamic raw) {
    final mp = raw?.toString().toLowerCase().trim();
    if (mp == null || mp.isEmpty) return '(Sin medio)';
    if (mp == 'transferencia') return 'Transferencia';
    if (mp == 'efectivo') return 'Efectivo';
    return raw.toString();
  }

  bool _puedeAnular() =>
      _seleccion != null && !_searching && !_submitting && _motivoCtrl.text.trim().length >= 8;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_pdfListo != null) {
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: cs.primary.withValues(alpha: 0.95)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Anulación registrada',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'El cobro quedó marcado como anulado (la fila no se borró). '
                'Los saldos se actualizaron automáticamente.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _generandoPdf ? null : _compartirPdf,
                icon: _generandoPdf
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.share_rounded),
                label: Text(_generandoPdf ? 'Generando…' : 'Compartir PDF (WhatsApp / imprimir)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cancel_outlined, color: cs.primary.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Anular cobro por error',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Buscá por nombre del cliente o alumno o por texto del concepto. '
                'No se borra el registro: queda anulado con motivo y deja de sumar en cuentas.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        labelText: 'Buscar',
                        hintText: 'Ej. GARCÍA, cuota…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _buscar(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: (_searching || _submitting) ? null : _buscar,
                    child: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Buscar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_resultados.isEmpty && !_searching && _searchCtrl.text.trim().length >= 2)
                Text('Sin coincidencias.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
              else if (_resultados.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _resultados.length,
                    itemBuilder: (ctx, i) {
                      final r = _resultados[i];
                      final fechaRaw = r['fecha_pago']?.toString();
                      final fecha = DateTime.tryParse(fechaRaw ?? '');
                      final fechaTxt = fecha != null ? ArTime.formatFechaHora(fecha) : '';
                      final selected = _seleccion?['tabla'] == r['tabla'] && _seleccion?['id'] == r['id'];
                      final titulo = r['titulo'] ?? '';
                      final monto = (r['monto'] as num?)?.toDouble() ?? 0;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _seleccion = Map<String, dynamic>.from(r)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                size: 20,
                                color: selected ? const Color(0xFFD4AF37) : Colors.grey,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titulo.toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                    Text(
                                      '${_etf(r['tabla']?.toString() ?? '')} · ${r['subtitulo'] ?? ''}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$fechaTxt · ${_lblMedio(r['medio_pago'])} · ${monto.toCurrency()}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_seleccion != null) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                TextField(
                  controller: _motivoCtrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Motivo de la anulación',
                    hintText: 'Ej. por error se imprimió una cuota de más',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_submitting) ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: (_puedeAnular() && !_submitting) ? _anular : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Anular cobro'),
        ),
      ],
    );
  }
}
