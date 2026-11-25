import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'modo_tele.dart';

/// "Usar este equipo como tótem" (la tele es el tótem, 24-nov-2026): lo abre
/// la tarjeta TÓTEM del Centro de Comando en una tele, una tablet o un celular,
/// **solo en modo jefe**. Se elige una vez y queda: desde ahí la app abre
/// derecho en el tótem.
Future<void> elegirModoTele(BuildContext context, WidgetRef ref) async {
  const oro = Color(0xFFD4AF37);
  TextStyle letra(double s, {Color c = Colors.white, bool negrita = false}) =>
      GoogleFonts.outfit(
        fontSize: s,
        color: c,
        fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
      );

  final papel = await showDialog<PapelDeLaTele>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1C0F35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: oro.withValues(alpha: 0.3)),
      ),
      title: Text('Usar este equipo como tótem', style: letra(20, negrita: true)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Desde ahora la app abre directo en el tótem de la fiesta, sin '
              'pedir PIN. Para volver al programa: OK en el control → "Salir '
              'del modo tele", con el PIN del jefe.',
              style: letra(15, c: Colors.white70),
            ),
            const SizedBox(height: 14),
            Text(
              'Antes de cada fiesta, dejala un rato con internet en la oficina: '
              'baja la lista, las mesas y la foto.',
              style: letra(15, c: Colors.white70),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        OutlinedButton(
          key: const ValueKey('modo_tele_segunda'),
          onPressed: () => Navigator.of(context).pop(PapelDeLaTele.segunda),
          child: const Text('TELE 2 (SE ENGANCHA A LA 1)'),
        ),
        FilledButton(
          key: const ValueKey('modo_tele_principal'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(PapelDeLaTele.principal),
          child: const Text('TELE 1 (LLEVA LA LISTA)'),
        ),
      ],
    ),
  );
  if (papel == null) return;
  await ref.read(modoTeleProvider.notifier).poner(ModoTele(papel));
}
