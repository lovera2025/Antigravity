import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/evento.dart';
import '../../../models/contrato_alumno.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/utils/currency_input_formatter.dart';
import '../repositories/contratos_repository.dart';
import '../../../core/utils/uuid_utils.dart';

class ModalAlumnoPremium extends ConsumerStatefulWidget {
  final Evento evento;
  final ContratoAlumno? alumno;

  const ModalAlumnoPremium({
    super.key,
    required this.evento,
    this.alumno,
  });

  @override
  ConsumerState<ModalAlumnoPremium> createState() => _ModalAlumnoPremiumState();
}

class _ModalAlumnoPremiumState extends ConsumerState<ModalAlumnoPremium> {
  final _formKey = GlobalKey<FormState>();

  // Controladores principales
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _cursoDivisionCtrl;
  late final TextEditingController _musicaElegidaCtrl;
  late final TextEditingController _numeroMesaCtrl;

  // Acompañantes
  final TextEditingController _acompNombreCtrl = TextEditingController();
  List<String> _acompanantes = [];

  // Cotización Base
  late final TextEditingController _montoCtrl;
  late final TextEditingController _cuotasCtrl;

  // Mesa Extra
  int _mesasExtraCant = 0;
  late final TextEditingController _mesaPrecioCtrl;
  late final TextEditingController _mesaCuotasCtrl;

  // Sillas Extras
  int _sillasExtraCant = 0;
  late final TextEditingController _sillasPrecioUnitCtrl;
  late final TextEditingController _sillasCuotasCtrl;

  bool _isSubmitting = false;

  bool get isEdit => widget.alumno != null;

  @override
  void initState() {
    super.initState();
    final al = widget.alumno;
    
    _nombreCtrl = TextEditingController(text: al?.nombreAlumno ?? '');
    _telefonoCtrl = TextEditingController(text: al?.telefono ?? '');
    _cursoDivisionCtrl = TextEditingController(text: al?.cursoDivision ?? '');
    _musicaElegidaCtrl = TextEditingController(text: al?.musicaElegida ?? '');
    _numeroMesaCtrl = TextEditingController(text: al?.numeroMesa ?? '');

    if (al != null) {
      _acompanantes = List.from(al.nombresAcompanantes);
      final double montoBaseUI = al.montoTotalPactado - al.mesaExtraPrecio - al.sillasExtraPrecioTotal;
      _montoCtrl = TextEditingController(text: montoBaseUI.toFormattedNumber());
      _cuotasCtrl = TextEditingController(text: al.totalCuotas.toString());
      
      _mesasExtraCant = al.mesaExtraPrecio > 0 ? 1 : 0;
      _mesaPrecioCtrl = TextEditingController(text: _mesasExtraCant > 0 ? al.mesaExtraPrecio.toFormattedNumber() : '');
      _mesaCuotasCtrl = TextEditingController(text: al.mesaExtraCuotas.toString());
      
      _sillasExtraCant = al.sillasExtraCantidad;
      final double sillasUnitInicial = al.sillasExtraCantidad > 0
          ? al.sillasExtraPrecioTotal / al.sillasExtraCantidad
          : 0.0;
      _sillasPrecioUnitCtrl = TextEditingController(
        text: sillasUnitInicial > 0 ? sillasUnitInicial.toFormattedNumber() : '',
      );
      _sillasCuotasCtrl = TextEditingController(text: al.sillasExtraCuotas.toString());
    } else {
      _montoCtrl = TextEditingController();
      _cuotasCtrl = TextEditingController(text: '9');
      _mesaPrecioCtrl = TextEditingController();
      _mesaCuotasCtrl = TextEditingController(text: '1');
      _sillasPrecioUnitCtrl = TextEditingController();
      _sillasCuotasCtrl = TextEditingController(text: '1');
      _cargarUltimoMontoBase();
    }

    _montoCtrl.addListener(_updateTotals);
    _mesaPrecioCtrl.addListener(_updateTotals);
    _sillasPrecioUnitCtrl.addListener(_updateTotals);
  }

  Future<void> _cargarUltimoMontoBase() async {
    final prefs = await SharedPreferences.getInstance();
    final double? ultimoMonto = prefs.getDouble('ultimo_monto_${widget.evento.id}');
    if (ultimoMonto != null && mounted) {
      setState(() {
        _montoCtrl.text = ultimoMonto.toFormattedNumber();
      });
    }
  }

  void _updateTotals() {
    setState(() {});
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _cursoDivisionCtrl.dispose();
    _musicaElegidaCtrl.dispose();
    _numeroMesaCtrl.dispose();
    _acompNombreCtrl.dispose();
    _montoCtrl.dispose();
    _cuotasCtrl.dispose();
    _mesaPrecioCtrl.dispose();
    _mesaCuotasCtrl.dispose();
    _sillasPrecioUnitCtrl.dispose();
    _sillasCuotasCtrl.dispose();
    super.dispose();
  }

  double get _montoBase {
    return CurrencyInputFormatter.parse(_montoCtrl.text);
  }

  double get _montoMesa {
    final unit = CurrencyInputFormatter.parse(_mesaPrecioCtrl.text);
    return unit * _mesasExtraCant;
  }

  double get _montoSillas {
    final unit = CurrencyInputFormatter.parse(_sillasPrecioUnitCtrl.text);
    return unit * _sillasExtraCant;
  }

  double get _totalGeneral {
    return _montoBase + _montoMesa + _montoSillas;
  }

  /// Institución del colegio: viene del cliente del evento masivo (sin campo redundante en el formulario).
  String? _institucionParaPersistir() {
    final n = widget.evento.cliente?.nombreCompleto.trim();
    if (n != null && n.isNotEmpty) return n;
    final prev = widget.alumno?.institucion?.trim();
    if (prev != null && prev.isNotEmpty) return prev;
    return null;
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_montoBase <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto base es requerido'), backgroundColor: Colors.orangeAccent)
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(contratosRepositoryProvider);
      
      final nombre = _nombreCtrl.text.trim();
      final planCuotas = int.tryParse(_cuotasCtrl.text) ?? 9;
      final mesaCuotas = int.tryParse(_mesaCuotasCtrl.text) ?? 1;
      
      final sillasCuotasParsed = int.tryParse(_sillasCuotasCtrl.text) ?? 1;
      final sillasExtraCuotas = sillasCuotasParsed < 1 ? 1 : sillasCuotasParsed;

      final totalSillasParse = double.parse(_montoSillas.toStringAsFixed(2));

      if (isEdit) {
        // Modo Edición
        final al = widget.alumno!;
        final diffMontoPactado = _totalGeneral - al.montoTotalPactado;
        final nuevoSaldoDeudor = al.saldoDeudor + diffMontoPactado;
        
        if (nuevoSaldoDeudor < 0) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('El nuevo total es inferior a lo que el alumno ya pagó. No se puede reducir tanto.'),
                backgroundColor: Colors.redAccent,
            )
          );
          setState(() => _isSubmitting = false);
          return;
        }

        final alumnoEditado = al.copyWith(
          nombreAlumno: nombre,
          telefono: _telefonoCtrl.text.trim(),
          institucion: _institucionParaPersistir(),
          cursoDivision: _cursoDivisionCtrl.text.trim(),
          musicaElegida: _musicaElegidaCtrl.text.trim(),
          numeroMesa: _numeroMesaCtrl.text.trim(),
          nombresAcompanantes: _acompanantes,
          cantidadAcompanantes: _acompanantes.length,
          montoTotalPactado: _totalGeneral,
          saldoDeudor: nuevoSaldoDeudor,
          totalCuotas: planCuotas,
          mesaExtraPrecio: _montoMesa,
          mesaExtraCuotas: mesaCuotas,
          sillasExtraCantidad: _sillasExtraCant,
          sillasExtraPrecioTotal: totalSillasParse,
          sillasExtraCuotas: sillasExtraCuotas,
        );

        await repo.actualizarContrato(al.id, alumnoEditado.toJson());
      } else {
        // Modo Creación
        final nuevoContrato = ContratoAlumno(
          id: UuidUtils.generate(),
          eventoId: widget.evento.id,
          nombreAlumno: nombre,
          cantidadAcompanantes: _acompanantes.length,
          nombresAcompanantes: _acompanantes,
          montoTotalPactado: _totalGeneral,
          saldoDeudor: _totalGeneral,
          porcentajeDescuento: 0.0,
          totalCuotas: planCuotas,
          mesaExtraPrecio: _montoMesa,
          mesaExtraCuotas: mesaCuotas,
          sillasExtraCantidad: _sillasExtraCant,
          sillasExtraCuotas: sillasExtraCuotas,
          sillasExtraPrecioTotal: totalSillasParse,
          institucion: _institucionParaPersistir(),
          cursoDivision: _cursoDivisionCtrl.text.trim().isNotEmpty ? _cursoDivisionCtrl.text.trim() : null,
          musicaElegida: _musicaElegidaCtrl.text.trim().isNotEmpty ? _musicaElegidaCtrl.text.trim() : null,
          numeroMesa: _numeroMesaCtrl.text.trim().isNotEmpty ? _numeroMesaCtrl.text.trim() : null,
          telefono: _telefonoCtrl.text.trim().isNotEmpty ? _telefonoCtrl.text.trim() : null,
          createdAt: DateTime.now(),
        );

        await repo.registrarContrato(nuevoContrato);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('ultimo_monto_${widget.evento.id}', _montoBase);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent)
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 700,
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: gold.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: gold.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEdit ? Icons.edit_note_rounded : Icons.person_add_rounded, 
                    color: gold, 
                    size: 28
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEdit ? 'Editar Alumno' : 'Registrar Nuevo Alumno',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            
            // ── Body ──
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildSectionTitle('Datos Personales', Icons.badge_outlined, gold),
                    _buildCard(
                      isDark: isDark,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nombreCtrl,
                            decoration: _premiumInputDecoration('Nombre completo del alumno *', isDark),
                            validator: (val) => val == null || val.trim().isEmpty ? 'El nombre es obligatorio' : null,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _telefonoCtrl,
                                  keyboardType: TextInputType.phone,
                                  decoration: _premiumInputDecoration('Teléfono (WhatsApp)', isDark, prefixIcon: Icons.phone_outlined),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _cursoDivisionCtrl,
                                  decoration: _premiumInputDecoration('Curso / División (Ej: 6 "A")', isDark),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _musicaElegidaCtrl,
                            decoration: _premiumInputDecoration('Música Elegida', isDark, prefixIcon: Icons.music_note_outlined),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _numeroMesaCtrl,
                            decoration: _premiumInputDecoration('N° de Mesa Asignada / Contrato', isDark, prefixIcon: Icons.table_restaurant_outlined),
                          ),
                        ],
                      )
                    ),
                    const SizedBox(height: 24),
                    
                    _buildSectionTitle('Acompañantes', Icons.group_outlined, gold),
                    _buildCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _acompNombreCtrl,
                                  decoration: _premiumInputDecoration('Agregar nombre de acompañante', isDark),
                                  onFieldSubmitted: (val) {
                                    if (val.trim().isNotEmpty) {
                                      setState(() {
                                        _acompanantes.add(val.trim());
                                        _acompNombreCtrl.clear();
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () {
                                  if (_acompNombreCtrl.text.trim().isNotEmpty) {
                                    setState(() {
                                      _acompanantes.add(_acompNombreCtrl.text.trim());
                                      _acompNombreCtrl.clear();
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: gold.withValues(alpha: 0.2),
                                  foregroundColor: gold,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                          if (_acompanantes.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _acompanantes.map((name) => Chip(
                                label: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                deleteIconColor: Colors.redAccent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
                                onDeleted: () => setState(() => _acompanantes.remove(name)),
                              )).toList(),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total: ${_acompanantes.length} acompañantes',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: gold),
                            ),
                          ],
                        ],
                      )
                    ),
                    const SizedBox(height: 24),

                    _buildSectionTitle('Cotización Base', Icons.attach_money_rounded, gold),
                    _buildCard(
                      isDark: isDark,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _montoCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [CurrencyInputFormatter()],
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              decoration: _premiumInputDecoration('Valor del Contrato Base *', isDark, prefixText: '\$ '),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _cuotasCtrl,
                              keyboardType: TextInputType.number,
                              decoration: _premiumInputDecoration('Cuotas Base', isDark, prefixIcon: Icons.calendar_today_rounded),
                            ),
                          ),
                        ],
                      )
                    ),
                    const SizedBox(height: 24),

                    _buildSectionTitle('Mesa Extra', Icons.table_restaurant_outlined, gold),
                    _buildCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cantidad de Mesas Extras a agregar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildPremiumStepper(
                                isDark, 
                                gold, 
                                _mesasExtraCant, 
                                () {
                                  setState(() {
                                    _mesasExtraCant--;
                                    if (_mesasExtraCant == 0) _mesaPrecioCtrl.clear();
                                  });
                                }, 
                                () => setState(() => _mesasExtraCant++)
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: TextFormField(
                                  controller: _mesaPrecioCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [CurrencyInputFormatter()],
                                  decoration: _premiumInputDecoration('Precio x Mesa', isDark, prefixText: '\$ '),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _mesaCuotasCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _premiumInputDecoration('Cuotas Mesa', isDark),
                                ),
                              ),
                            ],
                          ),
                          if (_mesasExtraCant > 0) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: gold.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: gold.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total Mesas Extras (${_mesasExtraCant}x):',
                                    style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87),
                                  ),
                                  Text(
                                    _montoMesa.toCurrency(),
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFD4AF37)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildSectionTitle('Sillas Extras', Icons.chair_alt_outlined, gold),
                    _buildCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cantidad de Sillas Extras a agregar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildPremiumStepper(
                                isDark, 
                                gold, 
                                _sillasExtraCant, 
                                () => setState(() => _sillasExtraCant--), 
                                () => setState(() => _sillasExtraCant++)
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: TextFormField(
                                  controller: _sillasPrecioUnitCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [CurrencyInputFormatter()],
                                  decoration: _premiumInputDecoration('Precio x Silla', isDark, prefixText: '\$ '),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _sillasCuotasCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _premiumInputDecoration('Cuotas Sillas', isDark),
                                ),
                              ),
                            ],
                          ),
                          if (_sillasExtraCant > 0) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: gold.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: gold.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total Sillas Extras (${_sillasExtraCant}x):',
                                    style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87),
                                  ),
                                  Text(
                                    _montoSillas.toCurrency(),
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFD4AF37)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // ── Footer / Total Bar ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151515) : const Color(0xFFFAFAFA),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(23)),
                border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'TOTAL ACUERDO PACTADO',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _totalGeneral.toCurrency(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFFD4AF37)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_isSubmitting)
                    const CircularProgressIndicator(color: Color(0xFFD4AF37))
                  else
                    ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        isEdit ? 'GUARDAR CAMBIOS' : 'CONFIRMAR REGISTRO',
                        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color gold) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: gold),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: child,
    );
  }

  Widget _buildPremiumStepper(bool isDark, Color gold, int value, VoidCallback onDecrement, VoidCallback onIncrement) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
              onTap: value > 0 ? onDecrement : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Icon(Icons.remove_rounded, color: value > 0 ? gold : Colors.grey),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: gold.withValues(alpha: 0.05),
            child: Text(
              value.toString(),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(11)),
              onTap: value < 100 ? onIncrement : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Icon(Icons.add_rounded, color: value < 100 ? gold : Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _premiumInputDecoration(String label, bool isDark, {String? prefixText, IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20, color: Colors.grey) : null,
      filled: true,
      fillColor: isDark ? Colors.black26 : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
