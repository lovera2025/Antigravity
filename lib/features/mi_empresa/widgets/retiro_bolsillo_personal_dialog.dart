import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cierre_caja/models/turno_caja.dart';
import '../../common/utils/currency_extensions.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../providers/finanzas_provider.dart';

/// Plata que pasa del negocio al bolsillo personal del dueño ([kCategoriaRetiroDueno]).
///
/// Hace UNA sola cosa. Tenía arriba un selector "¿Qué tipo de retiro es?" con
/// la opción "Del negocio", que no era un retiro sino un gasto de la empresa:
/// dos diálogos disfrazados de uno. Sobraba por partida doble — quien llega
/// acá ya apretó "APARTAR PARA MÍ" o "TRAER DEL NEGOCIO", así que preguntarle
/// de nuevo es hacerlo elegir dos veces; y el gasto del negocio tiene su
/// propio botón en el panel, con categorías reales en vez de una genérica.
class RetiroBolsilloPersonalDialog extends ConsumerStatefulWidget {
  const RetiroBolsilloPersonalDialog({super.key});

  @override
  ConsumerState<RetiroBolsilloPersonalDialog> createState() => _RetiroBolsilloPersonalDialogState();
}

class _RetiroBolsilloPersonalDialogState extends ConsumerState<RetiroBolsilloPersonalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _conceptoController = TextEditingController(text: 'Retiro bolsillo personal');

  bool _isSubmitting = false;

  /// Sin medio elegido de entrada: venía en Efectivo, y el 21-sep se apartaron
  /// $49M "en efectivo" cuando en efectivo había $28,7M. El total del negocio
  /// alcanzaba, así que pasó, y desde ahí el efectivo del negocio dio negativo.
  String? _medioPago;

  static const _gold = Color(0xFFD4AF37);
  static const _amber = Color(0xFFFFB74D);

  /// Umbral por redondeo de moneda / coma en el campo.
  static const _excedeTol = 0.009;

  @override
  void initState() {
    super.initState();
    _montoController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _montoController.dispose();
    _conceptoController.dispose();
    super.dispose();
  }

  /// Lo disponible en [medio] ('Efectivo' o 'Transferencia'), nunca negativo.
  static double _disponibleEnMedio(FinanzasState s, String medio) {
    final v = medio == 'Transferencia'
        ? s.hudTransferenciaNetaHistorica
        : s.hudEfectivoNetoHistorico;
    return v > 0 ? v : 0.0;
  }

  static String _otroMedio(String medio) =>
      medio == 'Transferencia' ? 'Efectivo' : 'Transferencia';

  static double _centavos(double v) => double.parse(v.toStringAsFixed(2));

  /// Guarda uno o dos retiros (partido entre los dos medios) y cierra.
  Future<void> _guardar(List<({double monto, String medio})> partes) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final monto = partes.fold<double>(0, (s, p) => s + p.monto);
      if (monto <= 0) {
        throw Exception('El monto debe ser mayor a cero');
      }
      final finState = ref.read(finanzasProvider).whenOrNull(data: (s) => s);
      if (finState != null) {
        final disp = finState.hudPlataDelNegocio;
        final dispClamped = disp > 0 ? disp : 0.0;
        if (monto > dispClamped + _excedeTol) {
          throw Exception('El monto supera lo disponible en empresa (${dispClamped.toCurrency()})');
        }
        for (final p in partes) {
          final enMedio = _disponibleEnMedio(finState, p.medio);
          if (p.monto > enMedio + _excedeTol) {
            throw Exception('En ${p.medio.toLowerCase()} hay '
                '${enMedio.toCurrency()}: no alcanza para ${p.monto.toCurrency()}');
          }
        }
      }

      final repo = ref.read(egresosRepositoryProvider);
      final conceptoBase = _conceptoController.text.trim().isEmpty
          ? 'Retiro bolsillo personal'
          : _conceptoController.text.trim();

      final fecha = DateTime.now();
      for (final p in partes) {
        if (p.monto <= 0.009) continue;
        await repo.registrarEgresoSinEvento(
          monto: p.monto,
          proveedor: conceptoBase,
          categoria: kCategoriaRetiroDueno,
          fecha: fecha,
          medioPago: p.medio,
        );
      }

      await ref.read(finanzasProvider.notifier).recargar();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apartado para vos. Ya está en tu bolsillo.'),
          backgroundColor: Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  double? _parseMontoField() {
    final t = _montoController.text.trim();
    if (t.isEmpty || t == '0,00') return null;
    try {
      final cleanText = t.replaceAll('.', '').replaceAll(',', '.');
      return double.parse(cleanText);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final finanzasAsync = ref.watch(finanzasProvider);

    final double? disponibleEmpresa = finanzasAsync.whenOrNull(
      data: (s) {
        final neto = s.hudPlataDelNegocio;
        return neto > 0 ? neto : 0.0;
      },
    );

    final montoIngresado = _parseMontoField();
    final excedeDisponible = disponibleEmpresa != null &&
        montoIngresado != null &&
        montoIngresado > disponibleEmpresa + _excedeTol;
    final restaria =
        (disponibleEmpresa != null && montoIngresado != null) ? disponibleEmpresa - montoIngresado : null;

    // Lo que hay en el medio elegido. Si no alcanza pero entre los dos sí, se
    // ofrece partirlo: lo que haya en ese medio, y el resto del otro.
    final finState = finanzasAsync.whenOrNull(data: (s) => s);
    final medio = _medioPago;
    final double? enMedio = (finState != null && medio != null)
        ? _disponibleEnMedio(finState, medio)
        : null;
    final excedeMedio = enMedio != null &&
        montoIngresado != null &&
        montoIngresado > enMedio + _excedeTol;
    final double? enOtro = (finState != null && medio != null)
        ? _disponibleEnMedio(finState, _otroMedio(medio))
        : null;
    final puedePartir = enMedio != null &&
        enOtro != null &&
        montoIngresado != null &&
        excedeMedio &&
        !excedeDisponible &&
        enMedio > 0.009 &&
        montoIngresado <= enMedio + enOtro + _excedeTol;

    const accentColor = _amber;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.savings_outlined,
            color: accentColor.withValues(alpha: 0.95),
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Apartar plata para mí',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    'Sacás plata del negocio para vos. Se suma a tu bolsillo y podés '
                    'registrar tus gastos contra eso.\n\n'
                    '¿Buscabas cargar un gasto del negocio? Ese es el botón '
                    '«REGISTRAR GASTO» del panel SALDO DEL NEGOCIO.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                finanzasAsync.when(
                  data: (s) => _buildSaldoDisponiblePanel(
                    context,
                    isDark,
                    state: s,
                    disponibleEmpresa: disponibleEmpresa ?? 0,
                    restaria: restaria,
                    excedeDisponible: excedeDisponible,
                    montoIngresado: montoIngresado,
                  ),
                  loading: () => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _amber.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Actualizando saldo asignable…',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No se pudo cargar el saldo: $e. Podés intentar de nuevo desde Finanzas.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.error,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                Text('MONTO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _montoController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final double value = double.parse(newValue.text) / 100;
                      final String newText = value.toFormattedNumber();
                      return newValue.copyWith(
                        text: newText,
                        selection: TextSelection.collapsed(offset: newText.length),
                      );
                    }),
                  ],
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    hintText: '0,00',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty || v == '0,00') return 'Ingresá el monto';
                    final disp = disponibleEmpresa;
                    if (disp != null) {
                      final cleanText = v.replaceAll('.', '').replaceAll(',', '.');
                      final monto = double.tryParse(cleanText);
                      if (monto != null && monto > disp + _excedeTol) {
                        return 'No podés retirar más que lo disponible (${disp.toCurrency()})';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Text('MEDIO DE PAGO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _medioPago,
                  hint: const Text('¿De dónde sale la plata?'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.swap_vert_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                  ],
                  validator: (v) => v == null ? 'Elegí si sale en efectivo o por transferencia' : null,
                  onChanged: (val) {
                    if (val != null) setState(() => _medioPago = val);
                  },
                ),
                if (excedeMedio && medio != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    puedePartir
                        ? 'En ${medio.toLowerCase()} hay ${enMedio.toCurrency()}. '
                            'Podés partirlo: ${enMedio.toCurrency()} en '
                            '${medio.toLowerCase()} y el resto por '
                            '${_otroMedio(medio).toLowerCase()}.'
                        : 'En ${medio.toLowerCase()} hay ${enMedio.toCurrency()}: '
                            'no alcanza. Elegí ${_otroMedio(medio).toLowerCase()} '
                            'o un monto menor.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text('CONCEPTO (OPCIONAL)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _conceptoController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Ej. Retiro fin de semana',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
        ),
        if (puedePartir)
          OutlinedButton(
            onPressed: _isSubmitting
                ? null
                : () => _guardar([
                      (monto: _centavos(enMedio), medio: medio!),
                      (
                        monto: _centavos(montoIngresado - enMedio),
                        medio: _otroMedio(medio),
                      ),
                    ]),
            child: const Text(
              'PARTIR EN LOS DOS',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6),
            ),
          ),
        FilledButton.icon(
          onPressed: (_isSubmitting ||
                  disponibleEmpresa == null ||
                  excedeDisponible ||
                  excedeMedio ||
                  montoIngresado == null ||
                  medio == null)
              ? null
              : () => _guardar([(monto: montoIngresado, medio: medio)]),
          style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(
            _isSubmitting ? 'GUARDANDO...' : 'APARTAR PARA MÍ',
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildSaldoDisponiblePanel(
    BuildContext context,
    bool isDark, {
    required FinanzasState state,
    required double disponibleEmpresa,
    required double? restaria,
    required bool excedeDisponible,
    required double? montoIngresado,
  }) {
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white70 : Colors.black87,
    );
    final valStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w900,
      color: excedeDisponible
          ? Theme.of(context).colorScheme.error
          : (isDark ? Colors.white : Colors.black87),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: excedeDisponible
              ? Theme.of(context).colorScheme.error.withValues(alpha: isDark ? 0.14 : 0.08)
              : const Color(0xFF00B894).withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: excedeDisponible
                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.45)
                : const Color(0xFF00B894).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  excedeDisponible ? Icons.warning_rounded : Icons.pie_chart_outline_rounded,
                  size: 18,
                  color: excedeDisponible ? Theme.of(context).colorScheme.error : const Color(0xFF00B894),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saldo contable del negocio',
                    style: baseStyle.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(disponibleEmpresa.toCurrency(), style: valStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Cobros − operadores − gastos personales − retiros pendientes. '
              'No es plata física en un cajón: comparalo con caja + banco + cofre.',
              style: baseStyle.copyWith(fontSize: 10, height: 1.35, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Disponible en efectivo ${state.hudEfectivoNetoHistorico.toCurrency()} · '
              'en transferencia ${state.hudTransferenciaNetaHistorica.toCurrency()}',
              style: baseStyle.copyWith(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF00B894)),
            ),
            if (restaria != null && montoIngresado != null && montoIngresado > _excedeTol) ...[
              const SizedBox(height: 8),
              Text(
                excedeDisponible
                    ? 'Este monto supera lo que tenés en empresa.'
                    : 'Después del retiro quedaría en empresa:',
                style: baseStyle.copyWith(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              if (!excedeDisponible) ...[
                const SizedBox(height: 2),
                Text(
                  restaria.toCurrency(),
                  style: baseStyle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: restaria < 0.02 ? (isDark ? Colors.white38 : Colors.black38) : const Color(0xFF00B894),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
