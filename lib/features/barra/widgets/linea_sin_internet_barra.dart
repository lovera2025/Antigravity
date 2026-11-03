import 'package:flutter/material.dart';

import '../services/barra_sin_internet.dart';

/// La línea "Lista para trabajar sin internet" de la barra, arriba de la pantalla de
/// la cajera. Lo que dice lo decide [EstadoSinInternetBarra].
class LineaSinInternetBarra extends StatelessWidget {
  final PuestaAlDiaBarra puesta;
  final DateTime Function() ahora;

  const LineaSinInternetBarra({super.key, required this.puesta, this.ahora = DateTime.now});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: puesta,
        builder: (context, _) {
          final estado = EstadoSinInternetBarra.de(puesta.datos, ahora: ahora());
          final (icono, color) = switch (estado.tipo) {
            TipoSinInternet.lista => (Icons.cloud_done_outlined, Colors.green.shade700),
            TipoSinInternet.falta => (Icons.cloud_sync_outlined, Colors.orange.shade800),
            TipoSinInternet.sinInternet => (Icons.cloud_off_outlined, Colors.blueGrey.shade700),
            TipoSinInternet.sinLista => (Icons.error_outline, Colors.red.shade700),
          };
          return Material(
            key: const Key('barra_sin_internet'),
            color: color.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icono, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(estado.texto, style: TextStyle(fontSize: 13, color: color)),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
