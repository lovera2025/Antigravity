import 'package:flutter/material.dart';

import '../../../models/evento.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../estilos/disenio_barra.dart';
import '../services/fiestas_del_jefe.dart';

/// CAMBIAR DE FIESTA: las que vienen, la próxima primero, y las últimas. Devuelve el id de
/// la elegida. La usan BARRA del jefe y la pestaña BARRA del cierre de caja (6.4.0): las
/// dos miran la misma fiesta elegida (`fiestaElegidaDelJefeProvider`).
class ElegirFiestaDelJefe extends StatelessWidget {
  final FiestasDelJefe fiestas;
  final String actual;
  final DateTime hoy;

  const ElegirFiestaDelJefe({
    super.key,
    required this.fiestas,
    required this.actual,
    required this.hoy,
  });

  @override
  Widget build(BuildContext context) {
    Widget fila(Evento e, {required bool proxima}) {
      final fecha = fechaConCuando(e.fechaEvento, hoy, esLaQueAbre: proxima);
      final elegida = e.id == actual;
      return ListTile(
        key: Key('jefe_fiesta_${e.id}'),
        selected: elegida,
        title: Text(
          EventoPresentacion.tituloPrincipal(e),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(fecha),
        trailing: elegida ? const Icon(Icons.check, color: TemaBarra.dorado) : null,
        onTap: () => Navigator.pop(context, e.id),
      );
    }

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            t,
            style: const TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700),
          ),
        );

    return AlertDialog(
      title: const Text('¿En qué fiesta?'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 460,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (fiestas.lasQueVienen.isNotEmpty) titulo('LAS QUE VIENEN'),
            for (final (i, e) in fiestas.lasQueVienen.indexed) fila(e, proxima: i == 0),
            if (fiestas.lasUltimas.isNotEmpty) titulo('LAS ÚLTIMAS'),
            for (final e in fiestas.lasUltimas) fila(e, proxima: false),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('VOLVER')),
      ],
    );
  }
}
