import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/rentabilidad_config.dart';
import '../../common/utils/currency_extensions.dart';
import '../repositories/rentabilidad_config_repository.dart';

class RentabilidadConfigView extends ConsumerStatefulWidget {
  final bool isDark;
  final Color gold;

  const RentabilidadConfigView({
    super.key,
    required this.isDark,
    required this.gold,
  });

  @override
  ConsumerState<RentabilidadConfigView> createState() => _RentabilidadConfigViewState();
}

class _RentabilidadConfigViewState extends ConsumerState<RentabilidadConfigView> {
  bool _isLoading = true;
  RentabilidadConfig? _config;

  late TextEditingController _alquilerCtrl;
  late TextEditingController _sueldosCtrl;
  late TextEditingController _serviciosCtrl;
  late TextEditingController _impuestosCtrl;
  late TextEditingController _honorarioMontoCtrl;
  late TextEditingController _honorarioPctCtrl;
  late TextEditingController _eventosMesCtrl;

  String _honorarioModo = 'monto'; // 'monto' o 'porcentaje'
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _alquilerCtrl = TextEditingController(text: '0');
    _sueldosCtrl = TextEditingController(text: '0');
    _serviciosCtrl = TextEditingController(text: '0');
    _impuestosCtrl = TextEditingController(text: '0');
    _honorarioMontoCtrl = TextEditingController(text: '0');
    _honorarioPctCtrl = TextEditingController(text: '0');
    _eventosMesCtrl = TextEditingController(text: '1');

    _cargarMetadata();
  }

  @override
  void dispose() {
    _alquilerCtrl.dispose();
    _sueldosCtrl.dispose();
    _serviciosCtrl.dispose();
    _impuestosCtrl.dispose();
    _honorarioMontoCtrl.dispose();
    _honorarioPctCtrl.dispose();
    _eventosMesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarMetadata() async {
    try {
      final repo = ref.read(rentabilidadConfigRepositoryProvider);
      final c = await repo.getConfig();
      if (!mounted) return;

      _alquilerCtrl.text = c.alquilerLocal.toInt().toString();
      _sueldosCtrl.text = c.sueldosAdmin.toInt().toString();
      _serviciosCtrl.text = c.serviciosOficina.toInt().toString();
      _impuestosCtrl.text = c.impuestosFijos.toInt().toString();
      _honorarioMontoCtrl.text = c.honorarioAdrianDefaultMonto.toInt().toString();
      _honorarioPctCtrl.text = c.honorarioAdrianDefaultPct.toString();
      _eventosMesCtrl.text = c.eventosEstimadosMes.toString();
      _honorarioModo = c.honorarioModoDefault;

      setState(() {
        _config = c;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error cargando config: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _guardar() async {
    setState(() => _isSaving = true);
    try {
      final param = RentabilidadConfig(
        id: _config?.id ?? 'default',
        alquilerLocal: double.tryParse(_alquilerCtrl.text) ?? 0.0,
        sueldosAdmin: double.tryParse(_sueldosCtrl.text) ?? 0.0,
        serviciosOficina: double.tryParse(_serviciosCtrl.text) ?? 0.0,
        impuestosFijos: double.tryParse(_impuestosCtrl.text) ?? 0.0,
        honorarioAdrianDefaultMonto: double.tryParse(_honorarioMontoCtrl.text) ?? 0.0,
        honorarioAdrianDefaultPct: double.tryParse(_honorarioPctCtrl.text) ?? 0.0,
        honorarioModoDefault: _honorarioModo,
        eventosEstimadosMes: int.tryParse(_eventosMesCtrl.text) ?? 1,
        updatedAt: DateTime.now(),
      );

      final repo = ref.read(rentabilidadConfigRepositoryProvider);
      await repo.saveConfig(param);

      if (!mounted) return;
      setState(() {
        _config = param;
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Configuración guardada exitosamente'), backgroundColor: widget.gold, behavior: SnackBarBehavior.floating,),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando config: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: widget.gold));
    }

    final double tfListVal = (double.tryParse(_alquilerCtrl.text) ?? 0) +
        (double.tryParse(_sueldosCtrl.text) ?? 0) +
        (double.tryParse(_serviciosCtrl.text) ?? 0) +
        (double.tryParse(_impuestosCtrl.text) ?? 0);
    final int evMes = int.tryParse(_eventosMesCtrl.text) ?? 1;
    final double prorrateado = evMes > 0 ? (tfListVal / evMes) : 0;

    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.black45 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.gold.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business_center, color: widget.gold),
              const SizedBox(width: 8),
              Text(
                'COSTOS FIJOS (OPERATIVIDAD EMPRESA)',
                style: GoogleFonts.oswald(fontSize: 18, color: widget.gold, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ingresá los costos operativos fijos mensuales de la empresa. Estos se utilizarán para prorratear el costo fijo real por cada evento en el simulador de rentabilidad.',
            style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // Formularios
          Row(
            children: [
              Expanded(child: _buildNumField('Alquiler de Local', _alquilerCtrl)),
              const SizedBox(width: 16),
              Expanded(child: _buildNumField('Sueldos Administrativos', _sueldosCtrl)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildNumField('Servicios / Suscripciones', _serviciosCtrl)),
              const SizedBox(width: 16),
              Expanded(child: _buildNumField('Impuestos Fijos', _impuestosCtrl)),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Prorrateo preview
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Eventos Promedio / Mes', style: TextStyle(fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 8),
                    _buildNumField('Cant. Eventos', _eventosMesCtrl),
                    const SizedBox(height: 4),
                    const Text('Divisor para calcular costo por evento', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.gold.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.gold.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      const Text('COSTO FIJO PRORRATEADO POR EVENTO', style: TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        prorrateado.toCurrency(),
                        style: GoogleFonts.oswald(fontSize: 28, color: widget.gold, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('(${tfListVal.toCurrency()} ÷ $evMes)', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Honorarios Socio Default
          Row(
            children: [
              Icon(Icons.person, color: widget.gold),
              const SizedBox(width: 8),
              Text(
                'PRECARGA DE HONORARIOS DE SOCIO (ADRIÁN)',
                style: GoogleFonts.oswald(fontSize: 16, color: widget.gold, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RadioGroup<String>(
            groupValue: _honorarioModo,
            onChanged: (v) => setState(() => _honorarioModo = v ?? _honorarioModo),
            child: const Row(
              children: [
                Expanded(child: RadioListTile<String>(title: Text('Monto Fijo \$'), value: 'monto')),
                Expanded(child: RadioListTile<String>(title: Text('Porcentaje %'), value: 'porcentaje')),
              ],
            ),
          ),
          _buildNumField('Valor Default', _honorarioModo == 'monto' ? _honorarioMontoCtrl : _honorarioPctCtrl),
          const SizedBox(height: 32),

          // Botón Guardar
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _guardar,
                icon: const Icon(Icons.save),
                label: Text(_isSaving ? 'GUARDANDO...' : 'GUARDAR CONFIGURACIÓN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        prefixText: label.contains('Cant') || _honorarioModo == 'porcentaje' && controller == _honorarioPctCtrl ? '' : '\$ ',
        suffixText: _honorarioModo == 'porcentaje' && controller == _honorarioPctCtrl ? '%' : '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
