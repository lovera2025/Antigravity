import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../repositories/egresos_repository.dart';
import '../providers/egresos_provider.dart';
import '../../mi_empresa/providers/finanzas_provider.dart';

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
    'Sueldos',
    'Operadores',
    'Alquiler local',
    'Proveedores',
    'Logística',
    'Marketing',
    'Impuestos',
    'Otro',
  ];
  String _categoriaSeleccionada = 'Proveedores';
  String _medioPagoSeleccionado = 'Efectivo';

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
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final cleanText = _montoController.text
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final monto = double.parse(cleanText);

      // Usamos el repositorio centralizado
      final repo = ref.read(egresosRepositoryProvider);
      final evento = _eventoSeleccionado;
      if (evento != null) {
        await repo.registrarEgreso(
          eventoId: evento.id,
          monto: monto,
          proveedor: _proveedorController.text.trim(),
          categoria: _categoriaSeleccionada,
          medioPago: _medioPagoSeleccionado,
        );
      } else {
        // Gasto general del negocio (alquiler, impuestos, insumos): no es de
        // ningún evento. Antes el formulario lo exigía y no había otra forma
        // de cargarlo.
        await repo.registrarEgresoSinEvento(
          monto: monto,
          proveedor: _proveedorController.text.trim(),
          categoria: _categoriaSeleccionada,
          fecha: DateTime.now(),
          medioPago: _medioPagoSeleccionado,
        );
      }

      // Notificamos al provider de egresos para que se refresque (aunque el stream lo haría)
      ref.read(egresosProvider.notifier).refresh();
      // …y a Finanzas, que es donde se ve el saldo del negocio. Sin esto la
      // tarjeta quedaba con el número viejo hasta que entrara el realtime.
      await ref.read(finanzasProvider.notifier).recargar();

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
                    labelText: 'Vincular a evento (opcional)',
                    helperText: 'Dejalo vacío si es un gasto general del negocio',
                    prefixIcon: Icon(Icons.event),
                  ),
                  isExpanded: true,
                  hint: const Text('Sin evento · gasto del negocio'),
                  items: [
                    const DropdownMenuItem<Evento>(
                      value: null,
                      child: Text('Sin evento · gasto del negocio'),
                    ),
                    ..._eventosActivos.map((evt) {
                      return DropdownMenuItem<Evento>(
                        value: evt,
                        child: Text('${evt.cliente?.nombreCompleto ?? "N/N"} - ${evt.tipoParaMostrar} (${evt.fechaEvento.day}/${evt.fechaEvento.month})'),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _eventoSeleccionado = val),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _proveedorController,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_isSubmitting && !_isLoadingEventos) _submit();
                },
                validator: (value) => (value == null || value == '0,00') ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _medioPagoSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Medio de Pago',
                  prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _medioPagoSeleccionado = val);
                },
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
