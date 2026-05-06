import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/cliente.dart';
import '../repositories/clientes_repository.dart';

class ClienteFormDialog extends ConsumerStatefulWidget {
  final Cliente? cliente; // Si es null, es creación. Si no, es edición.

  const ClienteFormDialog({super.key, this.cliente});

  @override
  ConsumerState<ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends ConsumerState<ClienteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreController;
  late TextEditingController _telefonoController;
  late TextEditingController _emailController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.cliente?.nombreCompleto ?? '');
    _telefonoController = TextEditingController(text: widget.cliente?.telefono ?? '');
    _emailController = TextEditingController(text: widget.cliente?.email ?? '');
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final repo = ref.read(clientesRepositoryProvider);

    try {
      if (widget.cliente == null) {
        // Creación
        await repo.crear(
          nombreCompleto: _nombreController.text.trim(),
          telefono: _telefonoController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        );
      } else {
        // Edición
        await repo.actualizar(
          id: widget.cliente!.id,
          nombreCompleto: _nombreController.text.trim(),
          telefono: _telefonoController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.cliente == null ? 'Cliente creado con éxito' : 'Cliente actualizado')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.cliente != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Cliente' : 'Registrar Nuevo Cliente'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreController,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Ingrese el nombre' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoController,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Teléfono / Celular',
                  prefixIcon: Icon(Icons.phone),
                  hintText: 'Ej: +54 9 11 ...',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Ingrese un teléfono' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_isLoading) _submit();
                },
                decoration: const InputDecoration(
                  labelText: 'Email (Opcional)',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: Colors.white,
          ),
          child: _isLoading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(isEditing ? 'Guardar Cambios' : 'Crear Cliente'),
        ),
      ],
    );
  }
}
