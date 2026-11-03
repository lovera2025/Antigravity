import 'package:flutter/material.dart';

import '../datos/barra_repositorio.dart';

/// Lo que se elige al abrir una caja de barra.
typedef CajaElegida = ({int numero, String? sede});

/// Abrir la caja: **solo el número (1 a 6) y, si hace falta, dónde está**. Nada de
/// cambio ni de turno: es de noche, y el cambio se pone después si hay (pedido del
/// 3-nov). Si otra caja abierta de la fiesta ya tiene ese número, lo dice y deja
/// seguir. Null: no la abrió.
Future<CajaElegida?> pedirAbrirCajaBarra(
  BuildContext context, {
  required String fiesta,
  required List<CajaBarra> abiertas,
}) =>
    showDialog<CajaElegida>(
      context: context,
      builder: (_) => _AbrirCaja(fiesta: fiesta, abiertas: abiertas),
    );

class _AbrirCaja extends StatefulWidget {
  final String fiesta;
  final List<CajaBarra> abiertas;

  const _AbrirCaja({required this.fiesta, required this.abiertas});

  @override
  State<_AbrirCaja> createState() => _AbrirCajaState();
}

class _AbrirCajaState extends State<_AbrirCaja> {
  int? _numero;
  final _sede = TextEditingController();

  @override
  void dispose() {
    _sede.dispose();
    super.dispose();
  }

  /// Quién tiene abierta la caja con ese número, si alguien.
  CajaBarra? _ocupada(int n) {
    for (final c in widget.abiertas) {
      if (c.numeroCaja == n) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ocupada = _numero == null ? null : _ocupada(_numero!);
    return AlertDialog(
      title: const Text('Abrir tu caja'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.fiesta, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('¿Qué caja sos?'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var n = 1; n <= 6; n++)
                  ChoiceChip(
                    key: Key('caja_numero_$n'),
                    label: Text('Caja $n'),
                    selected: _numero == n,
                    onSelected: (_) => setState(() => _numero = n),
                  ),
              ],
            ),
            if (ocupada != null)
              Padding(
                key: const Key('caja_numero_ocupada'),
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'La caja $_numero ya está abierta'
                  '${ocupada.operadorNombre == null ? '' : ' (${ocupada.operadorNombre})'}. '
                  'Si no sos vos, elegí otro número.',
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('caja_sede'),
              controller: _sede,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Dónde está (si hace falta)',
                hintText: 'Barra del fondo',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          key: const Key('caja_abrir'),
          onPressed: _numero == null
              ? null
              : () => Navigator.pop<CajaElegida>(
                    context,
                    (numero: _numero!, sede: _sede.text.trim().isEmpty ? null : _sede.text.trim()),
                  ),
          child: const Text('ABRIR CAJA'),
        ),
      ],
    );
  }
}
