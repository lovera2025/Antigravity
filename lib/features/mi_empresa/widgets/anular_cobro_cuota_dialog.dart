import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../cierre_caja/providers/cierre_caja_provider.dart';
import '../../common/services/pdf_service.dart';
import '../../common/utils/currency_extensions.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../providers/finanzas_provider.dart';
import '../repositories/finanzas_repository.dart';
import 'selector_cobros.dart';

/// Admin: buscar cobros y marcarlos como anulados (no borra filas). Ajusta
/// saldos / totales. Se pueden tildar varios y se anulan todos juntos o ninguno.
class AnularCobroCuotaDialog extends ConsumerStatefulWidget {
  const AnularCobroCuotaDialog({super.key});

  @override
  ConsumerState<AnularCobroCuotaDialog> createState() => _AnularCobroCuotaDialogState();
}

typedef _CobroPdf = ({
  String nombrePagador,
  String referenciaEvento,
  String fuenteLabel,
  double monto,
  String? concepto,
  DateTime? fechaCobroOriginalUtc,
  String? medioPago,
  String idRegistro,
});

class _AnularCobroCuotaDialogState extends ConsumerState<AnularCobroCuotaDialog> {
  final _motivoCtrl = TextEditingController();
  bool _submitting = false;
  bool _generandoPdf = false;
  List<Map<String, dynamic>> _seleccion = [];

  /// Lo anulado, listo para el comprobante. Si no es null, ya se anuló.
  List<_CobroPdf>? _anulados;
  String _motivoAnulado = '';
  DateTime? _fechaAnulado;

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  double get _total => _seleccion.fold<double>(0, (s, r) => s + montoCobro(r));

  Future<void> _compartirPdf() async {
    final lista = _anulados;
    final fecha = _fechaAnulado;
    if (lista == null || fecha == null) return;
    setState(() => _generandoPdf = true);
    try {
      await PdfService.compartirComprobanteAnulacionCobros(
        cobros: lista,
        motivoAnulacion: _motivoAnulado,
        fechaAnulacionUtc: fecha,
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

  /// Freno proporcional, sin PIN: el jefe ya está adentro de Mi Empresa. Lo que
  /// se pierde de verdad es anular de más, así que se muestra qué y cuánto.
  Future<bool> _confirmar() async {
    final n = _seleccion.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == 1 ? '¿Anular este cobro?' : 'Vas a anular $n cobros por ${_total.toCurrency()}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in _seleccion)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${r['titulo'] ?? ''} · ${r['concepto'] ?? ''} · '
                      '${montoCobro(r).toCurrency()}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'No se borra nada: quedan anulados con el motivo y dejan de '
                  'sumar en saldos y caja.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(n == 1 ? 'Anular' : 'Anular $n'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _anular() async {
    final motivo = _motivoCtrl.text.trim();
    if (_seleccion.isEmpty) return;
    if (motivo.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describí el motivo (mínimo 8 caracteres).')),
      );
      return;
    }
    if (!await _confirmar() || !mounted) return;

    setState(() => _submitting = true);
    final seleccion = List<Map<String, dynamic>>.from(_seleccion);

    try {
      final repo = ref.read(finanzasRepositoryProvider);
      final contratos = await repo.anularPagosConMotivo(
        [
          for (final r in seleccion)
            (tabla: r['tabla'].toString(), id: r['id'].toString()),
        ],
        motivo,
      );
      // Una vez por contrato, aunque se hayan anulado varias líneas suyas.
      final contratosRepo = ref.read(contratosRepositoryProvider);
      for (final cid in contratos) {
        await contratosRepo.recalcularProgresoContrato(cid);
      }
      await ref.read(finanzasProvider.notifier).recargar();
      // Si el cierre de caja está abierto en esta PC, que ya no los cuente.
      if (ref.exists(cierreCajaProvider)) {
        await ref.read(cierreCajaProvider.notifier).refrescarTrasAnular();
      }

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _motivoAnulado = motivo;
        _fechaAnulado = ArTime.nowUtc();
        _anulados = [
          for (final r in seleccion)
            (
              nombrePagador: r['titulo']?.toString() ?? '',
              referenciaEvento: r['subtitulo']?.toString() ?? '',
              fuenteLabel: etiquetaFuenteCobro(r['tabla']?.toString() ?? ''),
              monto: montoCobro(r),
              concepto: r['concepto']?.toString(),
              fechaCobroOriginalUtc: DateTime.tryParse(r['fecha_pago']?.toString() ?? ''),
              medioPago: etiquetaMedioCobro(r['medio_pago']),
              idRegistro: r['id']?.toString() ?? '',
            ),
        ];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            seleccion.length == 1
                ? 'Cobro anulado. Podés compartir el comprobante PDF.'
                : '${seleccion.length} cobros anulados. Podés compartir el comprobante PDF.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo anular: $e')),
      );
    }
  }

  bool _puedeAnular() =>
      _seleccion.isNotEmpty && !_submitting && _motivoCtrl.text.trim().length >= 8;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final anulados = _anulados;

    if (anulados != null) {
      final n = anulados.length;
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
                n == 1
                    ? 'El cobro quedó marcado como anulado (la fila no se borró). '
                          'Los saldos se actualizaron automáticamente.'
                    : 'Los $n cobros quedaron marcados como anulados (no se borró '
                          'ninguna fila). Los saldos se actualizaron automáticamente.',
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

    final n = _seleccion.length;
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
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Buscá por nombre del cliente o alumno o por texto del concepto, y '
                'tildá uno o varios. No se borra el registro: queda anulado con '
                'motivo y deja de sumar en cuentas.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
              ),
              const SizedBox(height: 14),
              SelectorCobros(
                habilitado: !_submitting,
                onCambio: (lista) => setState(() => _seleccion = lista),
              ),
              if (_seleccion.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                TextField(
                  controller: _motivoCtrl,
                  enabled: !_submitting,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: n == 1
                        ? 'Motivo de la anulación'
                        : 'Motivo de la anulación (el mismo para los $n)',
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
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _puedeAnular() ? _anular : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(n <= 1 ? 'Anular cobro' : 'Anular $n cobros'),
        ),
      ],
    );
  }
}
