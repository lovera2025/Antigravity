import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/caja_fuerte_movimiento.dart';
import '../../common/utils/currency_extensions.dart';
import '../providers/caja_fuerte_provider.dart';

/// Depósito de efectivo del negocio en el cofre físico.
class CajaFuerteAsignarDialog extends ConsumerStatefulWidget {
  const CajaFuerteAsignarDialog({super.key});

  @override
  ConsumerState<CajaFuerteAsignarDialog> createState() => _CajaFuerteAsignarDialogState();
}

class _CajaFuerteAsignarDialogState extends ConsumerState<CajaFuerteAsignarDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  double _parseMontoAr(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final clean = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final m = _parseMontoAr(_montoCtrl.text);
    if (m <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un monto válido')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(cajaFuerteProvider.notifier).registrarAsignacion(
            m,
            nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const cof = Color(0xFF5D4037);
    return AlertDialog(
      title: const Text('Depositar en caja fuerte'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Registrá cuánto efectivo del negocio guardás en el cofre. Suma al saldo físico de caja fuerte.',
                style: TextStyle(fontSize: 12, height: 1.35, color: isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) return newValue;
                    final value = double.parse(newValue.text) / 100;
                    final formatted = value.toFormattedNumber();
                    return newValue.copyWith(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monto depositado',
                  prefixText: '\$ ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (_parseMontoAr(v) <= 0) return 'Monto mayor a 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notaCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Ej.: cierre del sábado, sobrante del turno…',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _guardar,
          style: FilledButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFFD4AF37) : cof,
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Depositar'),
        ),
      ],
    );
  }
}

/// Retiro desde caja fuerte (resta del saldo físico; bloqueado si supera disponible).
class CajaFuerteRetiroDialog extends ConsumerStatefulWidget {
  final double saldoActual;

  const CajaFuerteRetiroDialog({super.key, required this.saldoActual});

  @override
  ConsumerState<CajaFuerteRetiroDialog> createState() => _CajaFuerteRetiroDialogState();
}

class _CajaFuerteRetiroDialogState extends ConsumerState<CajaFuerteRetiroDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  CajaFuerteMotivoRetiro _motivo = CajaFuerteMotivoRetiro.personal;
  bool _busy = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  double _parseMontoAr(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final clean = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final m = _parseMontoAr(_montoCtrl.text);
    if (m <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un monto válido')),
      );
      return;
    }
    if (m > widget.saldoActual + 1e-6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saldo insuficiente en el cofre (${widget.saldoActual.toCurrency()}). Depositá más o bajá el monto.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(cajaFuerteProvider.notifier).registrarRetiro(
            m,
            motivo: _motivo,
            nota: _notaCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const cof = Color(0xFF5D4037);
    return AlertDialog(
      title: const Text('Retirar del cofre'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'En cofre ahora: ${widget.saldoActual.toCurrency()}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Indicá para qué sacás la plata. El saldo físico del cofre baja; el Resumen de caja del negocio no cambia solo por este movimiento.',
                style: TextStyle(fontSize: 12, height: 1.35, color: isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 14),
              Text(
                '¿Para qué es?',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isDark ? Colors.white54 : Colors.black54),
              ),
              const SizedBox(height: 8),
              SegmentedButton<CajaFuerteMotivoRetiro>(
                showSelectedIcon: false,
                segments: CajaFuerteMotivoRetiro.values
                    .map(
                      (m) => ButtonSegment(
                        value: m,
                        label: Text(m.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    )
                    .toList(),
                selected: {_motivo},
                onSelectionChanged: (s) => setState(() => _motivo = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) return newValue;
                    final value = double.parse(newValue.text) / 100;
                    final formatted = value.toFormattedNumber();
                    return newValue.copyWith(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monto retirado',
                  prefixText: '\$ ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (_parseMontoAr(v) <= 0) return 'Monto mayor a 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notaCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Detalle',
                  hintText: _motivo.hint,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Contanos en pocas palabras para qué fue';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _guardar,
          style: FilledButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFFD4AF37) : cof,
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Registrar retiro'),
        ),
      ],
    );
  }
}

enum _FiltroHistorialCajaFuerte { todos, depositos, personal, negocio }

/// Historial completo de movimientos de caja fuerte.
Future<void> showCajaFuerteHistorialSheet(
  BuildContext context, {
  required CajaFuerteResumen resumen,
  required bool isDark,
  required Color gold,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return _CajaFuerteHistorialSheet(
        resumen: resumen,
        isDark: isDark,
        gold: gold,
      );
    },
  );
}

class _CajaFuerteHistorialSheet extends StatefulWidget {
  final CajaFuerteResumen resumen;
  final bool isDark;
  final Color gold;

  const _CajaFuerteHistorialSheet({
    required this.resumen,
    required this.isDark,
    required this.gold,
  });

  @override
  State<_CajaFuerteHistorialSheet> createState() => _CajaFuerteHistorialSheetState();
}

class _CajaFuerteHistorialSheetState extends State<_CajaFuerteHistorialSheet> {
  _FiltroHistorialCajaFuerte _filtro = _FiltroHistorialCajaFuerte.todos;

  List<CajaFuerteMovimiento> get _filtrados {
    final all = widget.resumen.movimientos;
    switch (_filtro) {
      case _FiltroHistorialCajaFuerte.todos:
        return all;
      case _FiltroHistorialCajaFuerte.depositos:
        return all.where((m) => m.esAsignacion).toList();
      case _FiltroHistorialCajaFuerte.personal:
        return all.where((m) => m.motivoRetiro == CajaFuerteMotivoRetiro.personal).toList();
      case _FiltroHistorialCajaFuerte.negocio:
        return all.where((m) => m.motivoRetiro == CajaFuerteMotivoRetiro.negocio).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF00B894);
    const cof = Color(0xFF5D4037);
    final items = _filtrados;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF121218) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: widget.gold.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HISTORIAL CAJA FUERTE',
                      style: GoogleFonts.oswald(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: cof,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Depositaste ${widget.resumen.totalDepositado.toCurrency()} · Retiraste ${widget.resumen.totalRetirado.toCurrency()} · Queda ${widget.resumen.saldo.toCurrency()}',
                      style: TextStyle(fontSize: 12, height: 1.35, color: widget.isDark ? Colors.white54 : Colors.black54),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final f in _FiltroHistorialCajaFuerte.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            switch (f) {
                              _FiltroHistorialCajaFuerte.todos => 'Todos',
                              _FiltroHistorialCajaFuerte.depositos => 'Depósitos',
                              _FiltroHistorialCajaFuerte.personal => 'Personal',
                              _FiltroHistorialCajaFuerte.negocio => 'Negocio',
                            },
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                          selected: _filtro == f,
                          onSelected: (_) => setState(() => _filtro = f),
                          selectedColor: widget.gold.withValues(alpha: 0.22),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'No hay movimientos con este filtro.',
                          style: TextStyle(color: widget.isDark ? Colors.white38 : Colors.black45, fontWeight: FontWeight.w600),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final m = items[index];
                          final d = ArTime.toAr(m.createdAt);
                          final fechaTxt = ArTime.formatFechaCorta(d);
                          final horaTxt = ArTime.formatHora(m.createdAt);
                          final col = m.esAsignacion ? green : Colors.redAccent;
                          final detalle = m.notaDetalle;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: widget.isDark ? Colors.white12 : Colors.black12),
                            ),
                            child: ListTile(
                              leading: Icon(
                                m.esAsignacion ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                color: col,
                              ),
                              title: Text(
                                '${m.esAsignacion ? '+' : '−'}${m.monto.toCurrency()} · ${m.etiquetaMovimiento}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                              subtitle: Text(
                                '$fechaTxt $horaTxt${detalle != null ? '\n$detalle' : ''}',
                                style: TextStyle(fontSize: 11, height: 1.3, color: widget.isDark ? Colors.white54 : Colors.black54),
                              ),
                              isThreeLine: detalle != null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
