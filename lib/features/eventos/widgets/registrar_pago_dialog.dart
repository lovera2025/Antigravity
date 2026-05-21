import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/evento.dart';
import '../../../models/transaccion.dart';
import '../../common/utils/currency_extensions.dart';
import '../../../core/utils/ar_time.dart';
import '../repositories/eventos_repository.dart';
import '../repositories/transacciones_repository.dart';

class RegistrarPagoDialog extends ConsumerStatefulWidget {
  final Evento evento;
  final List<Transaccion> transaccionesExistentes;
  final double presupuestoTotal;
  final List<EventosServicios> servicios;

  const RegistrarPagoDialog({
    super.key,
    required this.evento,
    required this.transaccionesExistentes,
    required this.presupuestoTotal,
    this.servicios = const [],
  });

  @override
  ConsumerState<RegistrarPagoDialog> createState() => _RegistrarPagoDialogState();
}

class _RegistrarPagoDialogState extends ConsumerState<RegistrarPagoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _conceptoController = TextEditingController();
  final _montoController = TextEditingController();
  final _pctBonifController = TextEditingController();

  bool _isSubmitting = false;
  bool _contextoExpandido = false;
  /// Si ya hay % guardado en el evento, el campo queda bloqueado hasta "Cambiar acuerdo".
  bool _pctFieldEditable = true;
  String _medioPago = 'Efectivo';
  DateTime _fechaPago = DateTime.now();

  bool get _esRecepcion =>
      widget.evento.tipo.toLowerCase().contains('recepci');

  bool get _esPrimerPago => widget.transaccionesExistentes.isEmpty;

  double get _sena30 => widget.presupuestoTotal * 0.30;

  double get _totalPagado =>
      widget.transaccionesExistentes.fold(0.0, (s, t) => s + t.monto);

  double get _saldoRestante => widget.presupuestoTotal - _totalPagado;

  bool get _senaYaAbonada => _totalPagado >= _sena30 - 0.01;

  bool get _montoLocked => false;

  double get _montoEfectivoIngresado {
    final cleanText = _montoController.text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleanText) ?? 0.0;
  }

  double get _pctDraft {
    final cleanText = _pctBonifController.text.replaceAll(',', '.').trim();
    if (cleanText.isEmpty) return 0.0;
    return double.tryParse(cleanText) ?? 0.0;
  }

  double get _montoBonifPreview =>
      widget.presupuestoTotal * (_pctDraft / 100.0);

  double get _creditoSinBonifGlobal => widget.transaccionesExistentes
      .where((t) => !t.esBonificacionGlobal)
      .fold(0.0, (s, t) => s + t.monto);

  /// Saldo proyectado luego de aplicar el % mostrado (reemplaza la bonif. global en libro).
  double get _saldoTrasBonifPreview =>
      widget.presupuestoTotal - _creditoSinBonifGlobal - _montoBonifPreview;

  bool _hayCambioBonificacion(double pct) {
    final saved = widget.evento.bonificacionGlobalPct;
    if (saved == null) return pct > 0.001;
    if (pct <= 0.001) return true;
    return (saved - pct).abs() > 0.001;
  }

  @override
  void initState() {
    super.initState();
    final saved = widget.evento.bonificacionGlobalPct;
    if (saved != null && saved > 0.001) {
      _pctBonifController.text = saved == saved.roundToDouble()
          ? saved.toInt().toString()
          : saved.toStringAsFixed(2);
      _pctFieldEditable = false;
    } else {
      _pctFieldEditable = true;
    }

    if (_montoLocked) {
      _conceptoController.text = 'Seña Inicial (30%)';
      _montoController.text = (_sena30).toFormattedNumber();
    } else {
      _cargarUltimoMonto();
    }

    _montoController.addListener(() => setState(() {}));
    _pctBonifController.addListener(() => setState(() {}));
  }

  Future<void> _cargarUltimoMonto() async {
    final prefs = await SharedPreferences.getInstance();
    final ultimoMonto = prefs.getDouble('ultimo_monto_pago_${widget.evento.id}');
    if (ultimoMonto != null && mounted) {
      setState(() {
        _montoController.text = ultimoMonto.toFormattedNumber();
      });
    }
  }

  @override
  void dispose() {
    _conceptoController.dispose();
    _montoController.dispose();
    _pctBonifController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaPago,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD4AF37),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _fechaPago) {
      setState(() {
        final now = DateTime.now();
        _fechaPago = DateTime(
          picked.year,
          picked.month,
          picked.day,
          now.hour,
          now.minute,
          now.second,
        );
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final pct = _pctDraft;
    final bonifCambio = _hayCambioBonificacion(pct);
    final montoBase = _montoEfectivoIngresado;

    if (!bonifCambio && montoBase <= 0.001) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Indicá un porcentaje de bonificación a aplicar o un monto a saldar.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final nuevoBonifMonto = pct > 0.001 ? widget.presupuestoTotal * (pct / 100.0) : 0.0;
    final saldoTrasBonif = widget.presupuestoTotal - _creditoSinBonifGlobal - nuevoBonifMonto;

    if (montoBase > saldoTrasBonif + 0.01) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El valor a saldar (${montoBase.toCurrency()}) supera el saldo disponible tras la bonificación (${saldoTrasBonif.toCurrency()}).',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final transRepo = ref.read(transaccionesRepositoryProvider);
      final eventosRepo = ref.read(eventosRepositoryProvider);

      if (bonifCambio) {
        if (pct <= 0.001) {
          await transRepo.eliminarBonificacionesGlobales(widget.evento.id);
          await eventosRepo.actualizarBonificacionGlobalPct(widget.evento.id, null);
        } else {
          await transRepo.aplicarBonificacionGlobal(
            eventoId: widget.evento.id,
            presupuestoTotal: widget.presupuestoTotal,
            porcentaje: pct,
          );
          await eventosRepo.actualizarBonificacionGlobalPct(widget.evento.id, pct);
        }
      }

      if (montoBase > 0.001) {
        await transRepo.registrarPago(
          eventoId: widget.evento.id,
          monto: montoBase,
          concepto: _conceptoController.text.trim(),
          medioPago: _medioPago,
          fechaPago: _fechaPago,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('ultimo_monto_pago_${widget.evento.id}', montoBase);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Operación registrada exitosamente'),
            backgroundColor: bonifCambio ? const Color(0xFFD4AF37) : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar operación: $e')),
        );
      }
    }
  }

  Widget _buildContextoBanner(bool isDark, Color gold, Color green, Color red) {
    final ev = widget.evento;
    final cliente = ev.cliente;
    final fecha = ev.fechaEvento;
    final fechaStr = '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    final totalPagadoStr = _totalPagado.toCurrency();
    final progreso = widget.presupuestoTotal > 0 ? (_totalPagado / widget.presupuestoTotal).clamp(0.0, 1.0) : 0.0;
    final tipoFormateado = Evento.formatearTipo(ev.tipo);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            gold.withValues(alpha: 0.12),
            gold.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gold.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _contextoExpandido = !_contextoExpandido),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.event_note_rounded, color: Color(0xFFD4AF37), size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente?.nombreCompleto.toUpperCase() ?? 'CLIENTE',
                          style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$tipoFormateado  •  $fechaStr',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _saldoRestante <= 0.01 ? green.withValues(alpha: 0.15) : red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _saldoRestante <= 0.01 ? '✓ SALDADO' : 'DEBE ${_saldoRestante.toCurrency()}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: _saldoRestante <= 0.01 ? green : red,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _contextoExpandido ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(Icons.expand_more_rounded, color: gold, size: 20),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progreso,
                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progreso >= 1.0 ? green : gold,
                ),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_contextoExpandido) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cliente?.telefono != null)
                    _buildContextoFila(
                      icon: Icons.phone_rounded,
                      label: 'Teléfono',
                      valor: cliente!.telefono!,
                      isDark: isDark,
                      gold: gold,
                    ),
                  if (cliente?.email != null)
                    _buildContextoFila(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      valor: cliente!.email!,
                      isDark: isDark,
                      gold: gold,
                    ),
                  _buildContextoFila(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Presupuesto total',
                    valor: widget.presupuestoTotal.toCurrency(),
                    isDark: isDark,
                    gold: gold,
                  ),
                  _buildContextoFila(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Total pagado / Descontado',
                    valor: totalPagadoStr,
                    isDark: isDark,
                    gold: gold,
                    valorColor: progreso >= 1.0 ? green : null,
                  ),
                  _buildContextoFila(
                    icon: Icons.pending_actions_rounded,
                    label: 'Saldo restante',
                    valor: _saldoRestante.toCurrency(),
                    isDark: isDark,
                    gold: gold,
                    valorColor: _saldoRestante <= 0.01 ? green : red,
                  ),
                  if (widget.servicios.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'SERVICIOS CONTRATADOS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...widget.servicios.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              Icon(Icons.storefront_outlined, size: 12, color: gold.withValues(alpha: 0.7)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  s.servicio?.nombre ?? 'Servicio',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                s.precioFinalAcordado.toCurrency(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContextoFila({
    required IconData icon,
    required String label,
    required String valor,
    required bool isDark,
    required Color gold,
    Color? valorColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 12, color: gold.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: valorColor ?? (isDark ? Colors.white70 : Colors.black87),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);
    const green = Color(0xFF00B894);
    const red = Color(0xFFE74C3C);

    final montoBase = _montoEfectivoIngresado;
    final pct = _pctDraft;
    final montoBonif = _montoBonifPreview;
    final saldoTrasBonif = _saldoTrasBonifPreview;
    final saldoFinalProyectado = saldoTrasBonif - montoBase;
    final excedeSaldo = saldoFinalProyectado < -0.01;

    Widget? infoBanner;

    if (!_esRecepcion && _esPrimerPago) {
      infoBanner = Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gold.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: gold, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SEÑA RECOMENDADA — 30%',
                    style: TextStyle(
                      color: gold,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sugerimos un 30% (${_sena30.toCurrency()}) para congelar el precio, pero puede ingresar el monto que el cliente desee entregar.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (!_esRecepcion && !_esPrimerPago && !_senaYaAbonada) {
      infoBanner = Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: red.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: red, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'La seña del 30% (${_sena30.toCurrency()}) aún no fue abonada en su totalidad.',
                style: const TextStyle(fontSize: 11, color: red),
              ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      title: const Text('Registrar Transacción'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildContextoBanner(isDark, gold, green, red),
                ?infoBanner,

                Text(
                  'Bonificación sobre presupuesto total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'El % se calcula sobre el presupuesto global del evento (${widget.presupuestoTotal.toCurrency()}). Queda guardado para este evento al confirmar; podés cambiarlo después si hace falta (poco habitual).',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.35,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _pctBonifController,
                        readOnly: !_pctFieldEditable,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Porcentaje de bonificación (%)',
                          hintText: 'Ej: 10',
                          prefixIcon: const Icon(Icons.percent_rounded, color: Color(0xFFD4AF37)),
                          filled: !_pctFieldEditable,
                          fillColor: !_pctFieldEditable
                              ? (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04))
                              : null,
                        ),
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) {
                          if (_pctFieldEditable) FocusScope.of(context).nextFocus();
                        },
                      ),
                    ),
                  ],
                ),
                if (!_pctFieldEditable && widget.evento.bonificacionGlobalPct != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _pctFieldEditable = true),
                      child: const Text('Cambiar acuerdo'),
                    ),
                  ),
                if (pct > 0 && montoBonif > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: gold.withValues(alpha: 0.4)),
                      color: gold.withValues(alpha: 0.06),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Crédito por bonificación (${pct.toString().replaceAll('.', ',')}%)',
                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                            ),
                            Text(
                              montoBonif.toCurrency(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFD4AF37),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Saldo proyectado tras bonificación: ${saldoTrasBonif.toCurrency()}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Text(
                  'Pago en esta operación (opcional)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Podés solo fijar la bonificación arriba, o además registrar efectivo / transferencia que se imputa al saldo.',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.35,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _conceptoController,
                  readOnly: _montoLocked,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) {
                    if (!_montoLocked) FocusScope.of(context).nextFocus();
                  },
                  decoration: InputDecoration(
                    labelText: 'Concepto del pago',
                    hintText: _esRecepcion
                        ? 'Ej: Cuota 1, Cuota 2...'
                        : 'Ej: Seña, Pago parcial...',
                    prefixIcon: const Icon(Icons.description),
                  ),
                  validator: (value) {
                    if (montoBase > 0.01 && (value == null || value.trim().isEmpty)) {
                      return 'Ingrese un concepto si hay monto a cobrar';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _montoController,
                  readOnly: _montoLocked,
                  keyboardType: _montoLocked ? TextInputType.none : TextInputType.number,
                  inputFormatters: _montoLocked
                      ? []
                      : [
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
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (_isSubmitting) return;
                    if (excedeSaldo) return;
                    _submit();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Valor a saldar (\$)',
                    prefixIcon: Icon(Icons.attach_money),
                    hintText: '0,00',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _medioPago,
                  decoration: const InputDecoration(
                    labelText: 'Medio de Pago',
                    prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _medioPago = val);
                  },
                ),

                const SizedBox(height: 16),
                
                InkWell(
                  onTap: _seleccionarFecha,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Fecha del Pago',
                      prefixIcon: const Icon(Icons.calendar_today_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(
                      ArTime.formatFechaHora(_fechaPago),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: excedeSaldo ? Colors.redAccent : gold.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Presupuesto total', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(
                            widget.presupuestoTotal.toCurrency(),
                            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      if (pct > 0.001 && montoBonif > 0.01) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Bonificación global (${pct.toString().replaceAll('.', ',')}%)',
                              style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12),
                            ),
                            Text(
                              '- ${montoBonif.toCurrency()}',
                              style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Saldo tras bonificación',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            saldoTrasBonif.toCurrency(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: saldoTrasBonif <= 0.01 ? green : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                      if (montoBase > 0.01) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Valor a saldar (esta operación)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text(montoBase.toCurrency(), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Saldo después de cobrar',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: excedeSaldo ? Colors.redAccent : null,
                            ),
                          ),
                          Text(
                            saldoFinalProyectado.toCurrency(),
                            style: TextStyle(
                              color: excedeSaldo ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'EFECTIVO A COBRAR',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: excedeSaldo ? Colors.redAccent : green,
                            ),
                          ),
                          Text(
                            montoBase.toCurrency(),
                            style: TextStyle(
                              color: excedeSaldo ? Colors.redAccent : green,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      if (excedeSaldo) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'El monto a saldar supera el saldo disponible.',
                          style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
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
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || excedeSaldo ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Confirmar operación'),
        ),
      ],
    );
  }
}
