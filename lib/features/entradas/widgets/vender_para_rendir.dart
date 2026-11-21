import 'package:flutter/material.dart';

/// El aviso de VENDER **"Entradas para rendir: 3 personas · RENDIR"**
/// (21-nov-2026, `docs/SPEC_entradas_para_rendir_2026-11-20.md`, sección 5):
/// arriba, solo si alguien tiene entradas sin rendir.
///
/// **Sin ninguna suma de plata, a propósito**: quien cobra cuenta su caja a
/// ciegas (como VENTAS y CERRAR CAJA), y "lo que falta rendir" le diría cuánto
/// tendría que entrar. Por eso el aviso recibe solo cuántas personas son: no
/// tiene de dónde sacar un monto. La única plata a la vista es "A cobrar", en
/// RENDIR, como en una venta.
class AvisoParaRendirEnVender extends StatelessWidget {
  const AvisoParaRendirEnVender({
    super.key,
    required this.personas,
    required this.alRendir,
  });

  /// Cuántas personas tienen algo sin rendir.
  final int personas;

  /// RENDIR. Null: apagado (VENDER está guardando).
  final VoidCallback? alRendir;

  @override
  Widget build(BuildContext context) {
    const oro = Color(0xFF6D5A10);
    return Container(
      key: const Key('vender_para_rendir'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0x26D4AF37),
        border: Border.all(color: const Color(0xB3D4AF37)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_return_outlined, size: 20, color: oro),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Entradas para rendir: '
              '${personas == 1 ? '1 persona' : '$personas personas'}',
              key: const Key('vender_para_rendir_texto'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: oro),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('vender_rendir'),
            onPressed: alRendir,
            child: const Text('RENDIR'),
          ),
        ],
      ),
    );
  }
}
