import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/evento.dart';
import '../../../models/transaccion.dart';
import '../../common/utils/currency_extensions.dart';
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
  final _porcentajeController = TextEditingController(); 
  
  bool _isSubmitting = false;
  bool _contextoExpandido = false;
  bool _esDescuento = false; 

  bool get _esRecepcion =>
      widget.evento.tipo.toLowerCase().contains('recepci');

  bool get _esPrimerPago => widget.transaccionesExistentes.isEmpty;

  double get _sena30 => widget.presupuestoTotal * 0.30;

  double get _totalPagado =>
      widget.transaccionesExistentes.fold(0, (s, t) => s + t.monto);
      
  double get _saldoRestante => widget.presupuestoTotal - _totalPagado;

  bool get _senaYaAbonada => _totalPagado >= _sena30 - 0.01;

  bool get _montoLocked => false; 

  double get _descuentoCalculado {
    final cleanText = _porcentajeController.text.replaceAll(',', '.');
    final porcentaje = double.tryParse(cleanText) ?? 0.0;
    return widget.presupuestoTotal * (porcentaje / 100);
  }

  @override
  void initState() {
    super.initState();
    if (_montoLocked) {
      _conceptoController.text = 'Seña Inicial (30%)';
      _montoController.text = (_sena30).toFormattedNumber();
    } else {
      _cargarUltimoMonto();
    }
    
    _porcentajeController.addListener(() {
      if (_esDescuento) setState(() {});
    });
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
    _porcentajeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(transaccionesRepositoryProvider);
      
      double montoFinal = 0.0;
      String conceptoFinal = '';

      if (_esDescuento) {
        final cleanText = _porcentajeController.text.replaceAll(',', '.');
        final porcentaje = double.tryParse(cleanText) ?? 0.0;
        montoFinal = _descuentoCalculado;
        conceptoFinal = 'Descuento Aplicado (${porcentaje.toStringAsFixed(porcentaje == porcentaje.truncateToDouble() ? 0 : 1)}%)';
      } else {
        final cleanText = _montoController.text.replaceAll('.', '').replaceAll(',', '.');
        montoFinal = double.parse(cleanText);
        conceptoFinal = _conceptoController.text.trim();
      }

      // --- ESCUDO DE TRANSACCIÓN ---
      if (montoFinal > _saldoRestante + 0.01) {
        setState(() => _isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: El monto (${montoFinal.toCurrency()}) excede el saldo a liquidar (${_saldoRestante.toCurrency()})'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      // ---------------------------------

      await repo.registrarPago(
        eventoId: widget.evento.id,
        monto: montoFinal,
        concepto: conceptoFinal,
      );

      if (!_esDescuento) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('ultimo_monto_pago_${widget.evento.id}', montoFinal);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_esDescuento ? 'Descuento aplicado con éxito' : 'Pago registrado exitosamente'),
            backgroundColor: _esDescuento ? const Color(0xFFD4AF37) : Colors.green,
            action: _esDescuento ? SnackBarAction(label: 'OK', textColor: Colors.black, onPressed: (){}) : null,
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
          if (_contextoExpandido) ...
            [
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
    
    final nuevoSaldoCalculado = _saldoRestante - _descuentoCalculado;
    final descuentoExcedido = nuevoSaldoCalculado < 0;

    Widget? infoBanner;

    if (!_esRecepcion && _esPrimerPago && !_esDescuento) {
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
    } else if (!_esRecepcion && !_esPrimerPago && !_senaYaAbonada && !_esDescuento) {
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
      title: Text(
        _esDescuento ? 'Aplicar Descuento' : 'Registrar Transacción',
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildContextoBanner(isDark, gold, green, red),
                if (infoBanner != null) infoBanner,
                
                // ── Campos de Pago Normal ──
                TextFormField(
                  controller: _conceptoController,
                  readOnly: _montoLocked || _esDescuento,
                  enabled: !_esDescuento, // Se atenúa si el descuento está activo
                  decoration: InputDecoration(
                    labelText: 'Concepto',
                    hintText: _esRecepcion
                        ? 'Ej: Cuota 1, Cuota 2...'
                        : 'Ej: Seña, Pago parcial...',
                    prefixIcon: const Icon(Icons.description),
                  ),
                  validator: (value) {
                    if (_esDescuento) return null; // Ignora validación en modo descuento
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingrese un concepto válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _montoController,
                  readOnly: _montoLocked || _esDescuento,
                  enabled: !_esDescuento, // Se atenúa si el descuento está activo
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
                  decoration: const InputDecoration(
                    labelText: 'Monto a Registrar (\$)',
                    prefixIcon: Icon(Icons.attach_money),
                    hintText: '0,00',
                  ),
                  validator: (value) {
                    if (_esDescuento) return null; // Ignora validación en modo descuento
                    if (value == null || value.trim().isEmpty || value == '0,00') {
                      return 'Ingrese un monto';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),

                // ── Switch de Descuento ──
                if (!_montoLocked)
                  Container(
                    decoration: BoxDecoration(
                      color: _esDescuento ? gold.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _esDescuento ? gold.withValues(alpha: 0.5) : (isDark ? Colors.white12 : Colors.black12),
                      ),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        'Descuento Especial',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Bonifica una parte de la deuda en lugar del pago',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      activeColor: gold,
                      value: _esDescuento,
                      onChanged: (val) {
                        setState(() {
                          _esDescuento = val;
                          _formKey.currentState?.reset(); 
                        });
                      },
                    ),
                  ),

                // ── Ticket Dinámico de Descuento ──
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  child: !_esDescuento
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            key: const ValueKey('modo_descuento'),
                            children: [
                              TextFormField(
                                controller: _porcentajeController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Porcentaje de Descuento (%)',
                                  hintText: 'Ej: 10',
                                  prefixIcon: const Icon(Icons.percent_rounded, color: Color(0xFFD4AF37)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) return 'Ingrese un porcentaje';
                                  final val = double.tryParse(value.replaceAll(',', '.'));
                                  if (val == null || val <= 0) return 'Ingrese un valor válido';
                                  if (val > 100) return 'No puede superar el 100%';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              // --- TICKET VISUALIZADOR EN TIEMPO REAL ---
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: descuentoExcedido ? Colors.redAccent : gold.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Deuda Actual:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                        Text(_saldoRestante.toCurrency(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Bonificación (${_porcentajeController.text.isEmpty ? '0' : _porcentajeController.text}%):', style: const TextStyle(color: Colors.green, fontSize: 12)),
                                        Text('- ${_descuentoCalculado.toCurrency()}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8.0),
                                      child: Divider(height: 1),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('NUEVO SALDO:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: descuentoExcedido ? Colors.redAccent : null)),
                                        Text(
                                          nuevoSaldoCalculado.toCurrency(),
                                          style: TextStyle(
                                            color: descuentoExcedido ? Colors.redAccent : gold,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (descuentoExcedido) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        '⚠️ El descuento supera la deuda actual.',
                                        style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                      )
                                    ]
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(_montoLocked 
                  ? 'Registrar Seña' 
                  : (_esDescuento ? 'Aplicar Descuento' : 'Guardar Pago')),
        ),
      ],
    );
  }
}