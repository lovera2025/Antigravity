import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../services/salon_mesas.dart';

/// Celda MESA de la grilla del evento masivo: sus números (juntos o
/// separados), un aviso si no coinciden con la cuenta y sus sillas extra.
/// Dice lo mismo que la Planilla, porque sale de [SalonMesas].
class CeldaMesaAlumno extends StatelessWidget {
  final ContratoAlumno alumno;
  final bool compacto;

  const CeldaMesaAlumno({
    super.key,
    required this.alumno,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    final texto = SalonMesas.textoMesas(alumno);
    final falta = SalonMesas.avisoMesas(alumno);
    final aviso = falta == null ? null : '⚠ $falta';
    final sillas = SalonMesas.sillasExtra(alumno);
    final tieneMesa = texto != '-';
    final chico = compacto ? 10.0 : 11.0;

    final detalle = [
      tieneMesa ? 'Mesa: $texto' : 'Sin mesa asignada',
      ?aviso,
      if (sillas > 0)
        'Sillas extra: ${SalonMesas.textoRepartoSillas(alumno)}',
    ].join('\n');

    return Tooltip(
      message: detalle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto,
            style: TextStyle(
              fontSize: compacto ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: tieneMesa ? Colors.indigo : Colors.grey.shade500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          if (aviso != null)
            Text(
              aviso,
              style: TextStyle(
                fontSize: chico,
                fontWeight: FontWeight.w700,
                color: Colors.amber.shade800,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          if (sillas > 0)
            Text(
              '+$sillas ${sillas == 1 ? 'silla extra' : 'sillas extra'}',
              style: TextStyle(
                fontSize: chico,
                fontWeight: FontWeight.w700,
                color: Colors.teal.shade600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
        ],
      ),
    );
  }
}
