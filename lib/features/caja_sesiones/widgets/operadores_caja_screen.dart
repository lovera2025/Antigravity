import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/operador_caja.dart';
import '../repositories/operadores_caja_repository.dart';

class OperadoresCajaScreen extends ConsumerStatefulWidget {
  const OperadoresCajaScreen({super.key});

  @override
  ConsumerState<OperadoresCajaScreen> createState() =>
      _OperadoresCajaScreenState();
}

class _OperadoresCajaScreenState extends ConsumerState<OperadoresCajaScreen> {
  List<OperadorCaja> _ops = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(operadoresCajaRepositoryProvider)
          .listar(soloActivos: true);
      if (mounted) {
        setState(() {
          _ops = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _eliminar(OperadorCaja op) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar operador'),
        content: Text(
          '¿Eliminar a ${op.nombre}? No podrá iniciar caja con su PIN. '
          'Si tiene caja abierta, se cerrará automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(operadoresCajaRepositoryProvider).eliminar(op.id);
      await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _editar([OperadorCaja? existing]) async {
    final nombreCtrl = TextEditingController(text: existing?.nombre ?? '');
    final pinCtrl = TextEditingController(text: existing?.pin ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nuevo operador' : 'Editar operador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              decoration: const InputDecoration(labelText: 'PIN (mín. 4)'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      nombreCtrl.dispose();
      pinCtrl.dispose();
      return;
    }
    try {
      final repo = ref.read(operadoresCajaRepositoryProvider);
      if (existing == null) {
        await repo.crear(nombre: nombreCtrl.text, pin: pinCtrl.text);
      } else {
        await repo.actualizar(
          existing.copyWith(nombre: nombreCtrl.text, pin: pinCtrl.text),
        );
      }
      await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      nombreCtrl.dispose();
      pinCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPERADORES DE CAJA'),
        actions: [
          IconButton(
            tooltip: 'Nuevo',
            onPressed: () => _editar(),
            icon: const Icon(Icons.person_add_alt_1, color: gold),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: gold))
          : _error != null
          ? Center(child: Text(_error!))
          : _ops.isEmpty
          ? const Center(
              child: Text(
                'No hay operadores.\nCreá uno con el botón +',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _ops.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final op = _ops[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: op.activo
                          ? gold.withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.2),
                      child: Icon(
                        Icons.person,
                        color: op.activo ? gold : Colors.grey,
                      ),
                    ),
                    title: Text(
                      op.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text('PIN configurado'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editar(op),
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () => _eliminar(op),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
