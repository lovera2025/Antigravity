import 'package:flutter/material.dart';

import '../datos/barra_repositorio.dart';
import '../services/barras_del_salon.dart';

/// Lo que se elige al abrir una caja de barra: el número y **la barra** (va en `sede`).
typedef CajaElegida = ({int numero, String? sede});

/// Abrir la caja: **el número (1 a 6) y la barra** ("Barra 1 · Barra 2", 25-nov-2026: cada
/// barra tiene su notebook y su router, y la tablet se engancha a la central de su
/// barra). Nada de cambio ni de turno: es de noche, y el cambio se pone después si hay
/// (pedido del 3-nov). [barra] viene elegida: la última de este equipo.
///
/// Si otra caja abierta **de esta noche** ya tiene ese número, lo dice y deja seguir
/// ([abiertas] ya viene solo con las de esta noche, `abiertasDeEstaNoche`): una caja de
/// prueba de otro día que quedó abierta no avisa. Null: no la abrió.
Future<CajaElegida?> pedirAbrirCajaBarra(
  BuildContext context, {
  required String fiesta,
  required List<CajaBarra> abiertas,
  String? barra,
}) =>
    showDialog<CajaElegida>(
      context: context,
      builder: (_) => _AbrirCaja(fiesta: fiesta, abiertas: abiertas, barra: barraDe(barra)),
    );

class _AbrirCaja extends StatefulWidget {
  final String fiesta;
  final List<CajaBarra> abiertas;
  final String? barra;

  const _AbrirCaja({required this.fiesta, required this.abiertas, this.barra});

  @override
  State<_AbrirCaja> createState() => _AbrirCajaState();
}

class _AbrirCajaState extends State<_AbrirCaja> {
  int? _numero;
  late String? _barra = widget.barra;

  /// Quién tiene abierta la caja con ese número esta noche, si alguien.
  CajaBarra? _ocupada(int n) {
    for (final c in widget.abiertas) {
      if (c.numeroCaja == n) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ocupada = _numero == null ? null : _ocupada(_numero!);
    final otraBarra = ocupada == null ? null : barraDe(ocupada.sede);
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
                  'La caja $_numero ya está abierta esta noche'
                  '${ocupada.operadorNombre == null ? '' : ' (${ocupada.operadorNombre}'
                      '${otraBarra == null ? '' : ', $otraBarra'})'}. '
                  'Si no sos vos, elegí otro número.',
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                ),
              ),
            const SizedBox(height: 16),
            const Text('¿En qué barra?'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in kBarrasDelSalon)
                  ChoiceChip(
                    key: Key('caja_barra_${kBarrasDelSalon.indexOf(b) + 1}'),
                    label: Text(b),
                    selected: _barra == b,
                    onSelected: (_) => setState(() => _barra = b),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'La tablet se conecta con la notebook de esa barra.',
                style: TextStyle(fontSize: 12.5),
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
          onPressed: _numero == null || _barra == null
              ? null
              : () => Navigator.pop<CajaElegida>(context, (numero: _numero!, sede: _barra)),
          child: const Text('ABRIR CAJA'),
        ),
      ],
    );
  }
}
