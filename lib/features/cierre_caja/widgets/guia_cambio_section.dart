import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/ar_time.dart';
import '../../common/utils/currency_extensions.dart';
import '../cierre_caja_sync_config.dart';
import '../models/guia_cambio_movimiento.dart';
import '../providers/cierre_caja_provider.dart';

class GuiaCambioSection extends ConsumerStatefulWidget {
  const GuiaCambioSection({super.key});

  @override
  ConsumerState<GuiaCambioSection> createState() => _GuiaCambioSectionState();
}

class _GuiaCambioSectionState extends ConsumerState<GuiaCambioSection> {
  static const _gold = Color(0xFFD4AF37);
  static const _usoColor = Color(0xFFE74C3C);
  static const _repColor = Color(0xFF00B894);

  bool _historialExpandido = false;
  double _saldoAnimado = 0;

  static double _parseMonto(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  Future<void> _dialogReposicion(BuildContext context) async {
    final ctrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _montoDialog(
        ctx: ctx,
        titulo: 'Agregar cambio',
        subtitulo: 'Suma al fondo de vueltos del día.',
        label: 'Monto a agregar',
        ctrl: ctrl,
        error: error,
        onConfirm: (v, setLocal) async {
          if (v <= 0) {
            setLocal(() => error = 'Ingresá un monto mayor a cero.');
            return false;
          }
          try {
            await ref.read(cierreCajaProvider.notifier).registrarReposicionGuia(v);
            return true;
          } catch (e) {
            setLocal(() => error = '$e');
            return false;
          }
        },
        boton: 'Agregar',
      ),
    );
    ctrl.dispose();
  }

  Future<void> _dialogUso(BuildContext context) async {
    final ctrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _montoDialog(
        ctx: ctx,
        titulo: 'Usé cambio del fondo',
        subtitulo: 'Solo guía operativa. No registra egreso ni mueve la caja contable.',
        label: 'Monto usado',
        ctrl: ctrl,
        error: error,
        onConfirm: (v, setLocal) async {
          if (v <= 0) {
            setLocal(() => error = 'Ingresá un monto mayor a cero.');
            return false;
          }
          try {
            await ref.read(cierreCajaProvider.notifier).registrarUsoCambioGuia(v);
            return true;
          } catch (e) {
            setLocal(() => error = '$e');
            return false;
          }
        },
        boton: 'Restar',
      ),
    );
    ctrl.dispose();
  }

  Future<void> _dialogAjuste(BuildContext context) async {
    final state = ref.read(cierreCajaProvider);
    final ctrl = TextEditingController(
      text: state.fondoCambioGuia <= 0 ? '' : state.fondoCambioGuia.toString(),
    );
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _montoDialog(
        ctx: ctx,
        titulo: 'Ajustar tras conteo',
        subtitulo: 'Indicá cuánto hay físicamente en el fondo de cambio.',
        label: 'Saldo real',
        ctrl: ctrl,
        error: error,
        onConfirm: (v, setLocal) async {
          if (v < 0) {
            setLocal(() => error = 'Monto inválido.');
            return false;
          }
          try {
            await ref.read(cierreCajaProvider.notifier).registrarAjusteGuia(v);
            return true;
          } catch (e) {
            setLocal(() => error = '$e');
            return false;
          }
        },
        boton: 'Ajustar',
      ),
    );
    ctrl.dispose();
  }

  Widget _montoDialog({
    required BuildContext ctx,
    required String titulo,
    required String subtitulo,
    required String label,
    required TextEditingController ctrl,
    required String? error,
    required Future<bool> Function(double v, void Function(void Function()) setLocal) onConfirm,
    required String boton,
  }) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        title: Text(
          titulo,
          style: GoogleFonts.oswald(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: _gold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitulo,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              autofocus: true,
              decoration: InputDecoration(
                labelText: label,
                errorText: error,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final ok = await onConfirm(_parseMonto(ctrl.text), setLocal);
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(boton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cierreCajaProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.45);
    final fechaIso = CierreCajaRepositoryFecha.fecha(state.dia);
    final syncOk = cierreCajaFechaElegibleSync(fechaIso);

    if (_saldoAnimado != state.fondoCambioGuia) {
      _saldoAnimado = state.fondoCambioGuia;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold.withValues(alpha: 0.35)),
          color: _gold.withValues(alpha: isDark ? 0.08 : 0.06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.paid_outlined, size: 20, color: _gold.withValues(alpha: 0.95)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GUÍA DE CAMBIO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: _gold.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Solo para vueltos. No afecta el recaudado. El fondo es del día (sync desde $kCierreCajaSyncFechaCorte).',
              style: TextStyle(fontSize: 11, height: 1.25, fontWeight: FontWeight.w600, color: muted),
            ),
            if (!syncOk) ...[
              const SizedBox(height: 4),
              Text(
                'Este día es anterior al corte de sync; la guía no se guarda en nube.',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(end: state.fondoCambioGuia),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) => Text(
                v.toCurrency(),
                style: GoogleFonts.oswald(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            if (state.guiaCantReposiciones > 0 || state.guiaCantUsos > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Reposiciones: ${state.guiaCantReposiciones} (+${state.guiaTotalReposiciones.toCurrency()})  ·  '
                'Usos: ${state.guiaCantUsos} (−${state.guiaTotalUsos.toCurrency()})',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: muted),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: !syncOk || state.cargando ? null : () => _dialogReposicion(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _repColor,
                      side: BorderSide(color: _repColor.withValues(alpha: 0.55)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: const Text('+ CAMBIO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: !syncOk || state.cargando ? null : () => _dialogUso(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold.withValues(alpha: 0.85),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: const Text('USÉ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Ajustar tras conteo',
                  onPressed: !syncOk || state.cargando ? null : () => _dialogAjuste(context),
                  icon: Icon(Icons.tune_rounded, color: _gold.withValues(alpha: 0.9)),
                ),
              ],
            ),
            if (state.guiaCambioMovimientos.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _historialExpandido = !_historialExpandido),
                child: Row(
                  children: [
                    Text(
                      'HISTORIAL (${state.guiaCambioMovimientos.length})',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: _gold.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _historialExpandido ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: muted,
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState:
                    _historialExpandido ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: state.guiaCambioMovimientos.take(12).map((m) {
                    return _filaHistorial(m, muted, isDark);
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaHistorial(GuiaCambioMovimiento m, Color muted, bool isDark) {
    final color = switch (m.tipo) {
      TipoGuiaCambioMovimiento.reposicion => _repColor,
      TipoGuiaCambioMovimiento.uso => _usoColor,
      TipoGuiaCambioMovimiento.ajuste => muted,
    };
    final signo = m.tipo == TipoGuiaCambioMovimiento.uso ? '−' : '+';
    final montoTxt = m.tipo == TipoGuiaCambioMovimiento.ajuste
        ? m.monto.toCurrency()
        : '$signo${m.monto.toCurrency()}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            ArTime.formatHora(m.fechaMov),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              m.tipo.label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
            ),
          ),
          Text(
            montoTxt,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            '→ ${m.saldoDespues.toCurrency()}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper para formatear fecha sin importar el repo en widgets.
class CierreCajaRepositoryFecha {
  static String fecha(DateTime dia) =>
      '${dia.year.toString().padLeft(4, '0')}-'
      '${dia.month.toString().padLeft(2, '0')}-'
      '${dia.day.toString().padLeft(2, '0')}';
}
