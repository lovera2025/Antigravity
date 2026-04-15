import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../repositories/egresos_repository.dart';
import '../providers/egresos_provider.dart';

class RegistrarEgresoGlobalDialog extends ConsumerStatefulWidget {
  const RegistrarEgresoGlobalDialog({super.key});

  @override
  ConsumerState<RegistrarEgresoGlobalDialog> createState() => _RegistrarEgresoGlobalDialogState();
}

class _RegistrarEgresoGlobalDialogState extends ConsumerState<RegistrarEgresoGlobalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _proveedorController = TextEditingController();
  final _montoController = TextEditingController();
  
  bool _isLoadingEventos = true;
  bool _isSubmitting = false;
  List<Evento> _eventosActivos = [];
  Evento? _eventoSeleccionado;

  final List<String> _categorias = [
    'Proveedor',
    'Personal',
    'Alquiler',
    'Catering',
    'Bebida',
    'Impuestos',
    'Otro'
  ];
  String _categoriaSeleccionada = 'Proveedor';

  @override
  void initState() {
    super.initState();
    _fetchEventosActivos();
  }

  @override
  void dispose() {
    _proveedorController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _fetchEventosActivos() async {
    final supabase = ref.read(supabaseProvider);
    try {
      final response = await supabase
          .from('eventos')
          .select('*, clientes(*)')
          .not('estado', 'eq', 'Finalizado')
          .not('estado', 'eq', 'Cancelado')
          .order('fecha_evento', ascending: true);
      
      setState(() {
        _eventosActivos = (response as List).map((e) => Evento.fromJson(e)).toList();
        _isLoadingEventos = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingEventos = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar eventos: $e')));
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _eventoSeleccionado == null) {
      if (_eventoSeleccionado == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debe seleccionar un evento'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final cleanText = _montoController.text
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final monto = double.parse(cleanText);
      
      // Usamos el repositorio centralizado
      final repo = ref.read(egresosRepositoryProvider);
      await repo.registrarEgreso(
        eventoId: _eventoSeleccionado!.id,
        monto: monto,
        proveedor: _proveedorController.text.trim(),
        categoria: _categoriaSeleccionada,
      );

      // Notificamos al provider de egresos para que se refresque (aunque el stream lo haría)
      ref.read(egresosProvider.notifier).refresh();

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gasto registrado exitosamente'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar gasto: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar Gasto Global'),
      content: SizedBox(
        width: 450,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoadingEventos)
                const Center(child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ))
              else
                DropdownButtonFormField<Evento>(
                  initialValue: _eventoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Vincular a Evento',
                    prefixIcon: Icon(Icons.event),
                  ),
                  isExpanded: true,
                  hint: const Text('Seleccionar Evento Activo'),
                  items: _eventosActivos.map((evt) {
                    return DropdownMenuItem<Evento>(
                      value: evt,
                      child: Text('${evt.cliente?.nombreCompleto ?? "N/N"} - ${evt.tipoParaMostrar} (${evt.fechaEvento.day}/${evt.fechaEvento.month})'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _eventoSeleccionado = val),
                  validator: (v) => v == null ? 'Requerido' : null,
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _proveedorController,
                decoration: const InputDecoration(
                  labelText: 'Proveedor / Concepto',
                  prefixIcon: Icon(Icons.business_center),
                ),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _categoriaSeleccionada,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  prefixIcon: Icon(Icons.category),
                ),
                items: _categorias.map((String cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (val) => setState(() => _categoriaSeleccionada = val!),
              ),
              const SizedBox(height: 16),
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
                decoration: const InputDecoration(
                  labelText: 'Monto (\$)',
                  prefixIcon: Icon(Icons.attach_money),
                  hintText: '0,00',
                ),
                validator: (value) => (value == null || value == '0,00') ? 'Requerido' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        ElevatedButton(
          onPressed: _isSubmitting || _isLoadingEventos ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE74C3C), foregroundColor: Colors.white),
          child: _isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('GUARDAR GASTO'),
        ),
      ],
    );
  }
}
