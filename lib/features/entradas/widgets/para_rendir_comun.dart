import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/entradas_retiro.dart' show TramoTalonario;
import '../cuentas/para_rendir.dart';
import '../cuentas/pedido_de_entradas.dart' show PedidoDeEntradas;
import 'vender_a_pagar.dart' show ChipDeVender;

// Lo que dicen igual PARA RENDIR (el jefe) y RENDIR (quien cobra, en VENDER)
// de unas entradas para rendir (21-nov-2026): el día, el nombre del precio,
// qué se llevó y el chip de quién se las llevó. **Solo palabras**: las cuentas
// son de `ParaRendir`.

const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

String _dos(int n) => n.toString().padLeft(2, '0');

/// "lun 16/11", en hora de Argentina. Vacío si no se entiende.
String diaParaRendir(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final ar = ArTime.toAr(t);
  return '${_dias[(ar.weekday - 1).clamp(0, 6)]} ${_dos(ar.day)}/${_dos(ar.month)}';
}

/// "mié 18/11 18:20", en hora de Argentina. Vacío si no se entiende.
String momentoParaRendir(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final ar = ArTime.toAr(t);
  return '${diaParaRendir(iso)} ${_dos(ar.hour)}:${_dos(ar.minute)}';
}

/// El nombre del precio como se lee: "Entrada anticipada" o "Entrada general".
/// El renglón de la venta dice "Entrada" a secas para la general (como VENDER),
/// y eso, solo, no dice nada a quien mira.
String nombreDelPrecioParaRendir(String? nombre) {
  final n = (nombre ?? '').trim();
  return n.isEmpty || n == PedidoDeEntradas.nombreSuelta ? 'Entrada general' : n;
}

/// "se llevó 20 el lun 16/11 · del 1201 al 1220".
String seLlevoParaRendir(BloqueParaRendir b) =>
    'se llevó ${b.cantidad} el ${diaParaRendir(b.dadoAt)} · '
    'del ${TramoTalonario.legible(b.tramos)}';

/// El chip de quién se las llevó: "alumno · 6° A" (o "alumno de la fiesta" si
/// no se sabe la división) o "de afuera".
class ChipDeQuienLleva extends StatelessWidget {
  const ChipDeQuienLleva({super.key, required this.esAlumno, this.division});

  final bool esAlumno;
  final String? division;

  @override
  Widget build(BuildContext context) {
    final d = (division ?? '').trim();
    return esAlumno
        ? ChipDeVender(
            d.isEmpty ? 'alumno de la fiesta' : 'alumno · $d',
            color: Colors.blue.shade800,
          )
        : ChipDeVender('de afuera', color: Colors.blueGrey.shade600);
  }
}
