import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import '../services/reparto_de_sillas.dart';
import '../services/salon_mesas.dart';

/// Celda MESA de la grilla del evento masivo: sus números (juntos o
/// separados), un aviso si no coinciden con la cuenta y sus sillas extra con su
/// reparto ("2P · 1A"). Dice lo mismo que la Planilla, porque sale de
/// [SalonMesas] y de [RepartoDeSillas].
///
/// Cuando hay más de una forma de repartir las sillas, el renglón de las sillas
/// se toca y abre el selector ([onElegirSillas]).
class CeldaMesaAlumno extends StatelessWidget {
  final ContratoAlumno alumno;
  final bool compacto;
  final SillasReparto? reparto;
  final VoidCallback? onElegirSillas;

  const CeldaMesaAlumno({
    super.key,
    required this.alumno,
    this.compacto = false,
    this.reparto,
    this.onElegirSillas,
  });

  @override
  Widget build(BuildContext context) {
    final texto = SalonMesas.textoMesas(alumno);
    final falta = SalonMesas.avisoMesas(alumno);
    final aviso = falta == null ? null : '⚠ $falta';
    final sillas = SalonMesas.sillasExtra(alumno);
    final tieneMesa = texto != '-';
    final chico = compacto ? 10.0 : 11.0;

    final estado = RepartoDeSillas.estado(alumno, reparto);
    final vigente = RepartoDeSillas.vigente(alumno, reparto);
    final hayQueElegir = RepartoDeSillas.opcionesDe(alumno).length > 1;

    final detalle = [
      tieneMesa ? 'Mesa: $texto' : 'Sin mesa asignada',
      ?aviso,
      if (sillas > 0)
        'Sillas extra: ${SalonMesas.textoRepartoSillas(alumno, sillasPrincipal: vigente?.principal)}',
      if (estado == EstadoRepartoSillas.aConfirmar)
        'Falta que la familia elija dónde van las sillas: tocá para elegir.',
      if (estado == EstadoRepartoSillas.revisar)
        'Tiene más sillas de las que entran (2 por mesa): revisá la cuenta.',
    ].join('\n');

    final String? textoSillas;
    final Color colorSillas;
    switch (estado) {
      case EstadoRepartoSillas.noAplica:
        textoSillas = null;
        colorSillas = Colors.teal.shade600;
      case EstadoRepartoSillas.unicaOpcion:
      case EstadoRepartoSillas.elegido:
        textoSillas = '+$sillas ${sillas == 1 ? 'silla' : 'sillas'}: '
            '${vigente?.texto ?? ''}';
        colorSillas = Colors.teal.shade600;
      case EstadoRepartoSillas.aConfirmar:
        textoSillas = '+$sillas ${sillas == 1 ? 'silla' : 'sillas'}: a confirmar';
        colorSillas = Colors.orange.shade800;
      case EstadoRepartoSillas.revisar:
        textoSillas = '+$sillas sillas: revisar';
        colorSillas = Colors.orange.shade800;
    }

    Widget? renglonSillas;
    if (textoSillas != null) {
      final etiqueta = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              textoSillas,
              style: TextStyle(
                fontSize: chico,
                fontWeight: FontWeight.w700,
                color: colorSillas,
                decoration: hayQueElegir && onElegirSillas != null
                    ? TextDecoration.underline
                    : null,
                decorationColor: colorSillas,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (estado == EstadoRepartoSillas.elegido)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(Icons.check_circle, size: chico + 2, color: colorSillas),
            ),
        ],
      );
      renglonSillas = hayQueElegir && onElegirSillas != null
          ? InkWell(
              onTap: onElegirSillas,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: etiqueta,
              ),
            )
          : etiqueta;
    }

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
          ?renglonSillas,
        ],
      ),
    );
  }
}
