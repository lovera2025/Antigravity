import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/entrega_entradas.dart';
import '../services/entrega_por_partes.dart';
import '../services/entregar_parte.dart';

// Los carteles de la entrega sin cargo por partes, **los mismos en ENTRADAS de la
// fiesta y en VENDER** (20-nov-2026): las dos pantallas guardan por
// `EntregarParte` y dicen lo mismo con cada resultado. Acá no se guarda nada.

/// "Sin conexión": lo que pregunta `EntregarParte` cuando no puede mirar la nube.
/// True si quien atiende eligió SEGUIR.
Future<bool> seguirSinInternetEnLaEntrega(
  BuildContext context,
  ParteEntrega parte,
) async {
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sin conexión'),
      content: Text(
        'No se puede ver si otro equipo ya le entregó '
        '${EntregaPorPartes.nombreDe(parte)}. Seguí solo si hoy se entregan '
        'únicamente desde este equipo.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('SEGUIR'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Cómo terminó la entrega de [datos] a [alumno], en palabras:
/// - quedó guardada y subió: un aviso verde ("✓ Entregadas…", "✓ Entregada 1…"
///   si es una sola, o "✓ Todo entregado" con las dos partes);
/// - quedó guardada pero no subió: "Entregado, pero todavía no subió";
/// - otro equipo ya la había entregado: "Ya retiró";
/// - cambió algo mientras se cargaba: "Cambió algo", con el motivo;
/// - sin internet, quien atiende no quiso seguir: nada.
Future<void> mostrarComoTerminoLaEntrega(
  BuildContext context,
  ResultadoDeLaEntrega r, {
  required ContratoAlumno alumno,
  required DatosDeLaParte datos,
}) async {
  if (!context.mounted) return;
  switch (r) {
    case Entregada(:final subio, :final todoEntregado):
      if (!subio) {
        await _avisar(
          context,
          'Entregado, pero todavía no subió',
          'La entrega quedó guardada en este equipo, pero no llegó a la nube '
              '(¿sin internet?). Hasta que suba, los otros equipos no la ven: no '
              'le entreguen ${EntregaPorPartes.nombreDe(datos.parte)} a esta '
              'familia desde otro equipo. Sube sola cuando vuelva la conexión.',
        );
        return;
      }
      final nombre = EntregaEntradas.nombreDeQuienRetira(datos.nombre);
      // El aviso nuevo reemplaza al anterior: en el mostrador se entrega de a
      // muchos seguidos, y esperar que se vaya el de antes confunde.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            todoEntregado
                ? '✓ Todo entregado: ${alumno.nombreAlumno.trim()} ya tiene las '
                    'pulseras y las generales.'
                // Una sola en singular: "✓ Entregada 1 pulsera VIP con cena".
                : '✓ ${datos.cantidad == 1 ? 'Entregada' : 'Entregadas'} '
                    '${datos.parte.cuantas(datos.cantidad)} a '
                    '$nombre (${datos.parentesco.etiqueta.toLowerCase()}).',
          ),
        ),
      );
    case YaEntregadaEnOtroEquipo(:final texto):
      await _avisar(context, 'Ya retiró', texto);
    case CambioAlgo(:final motivo):
      await _avisar(context, 'Cambió algo', motivo);
    case Cancelada():
      break;
  }
}

Future<void> _avisar(BuildContext context, String titulo, String texto) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ENTENDIDO'),
          ),
        ],
      ),
    );
