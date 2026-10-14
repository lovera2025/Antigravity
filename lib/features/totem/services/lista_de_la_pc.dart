import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../models/invitado.dart';

/// Quién ya entró a un evento según la base de esta PC, para el tótem que abre
/// sin poder leer la nube (`IngresosTotem.leyoDeLaPc`).
///
/// La arma la ventana principal y viaja por el puente
/// (`PuenteFichaTotem.metodoLista`). Lleva solo a los que entraron: es lo único
/// que el tótem mira de una lectura, y con 1.100 invitados el mensaje queda
/// chico.
class ListaDeLaPc {
  final String eventoId;

  /// Los ingresados del evento en esta PC.
  final List<Invitado> adentro;

  /// Los que esta PC marcó y todavía no subió a la nube.
  final Set<String> sinSubir;

  const ListaDeLaPc({
    required this.eventoId,
    required this.adentro,
    this.sinSubir = const {},
  });

  String codificar() => jsonEncode({
        'evento_id': eventoId,
        'adentro': [for (final i in adentro) i.toJson()],
        'sin_subir': sinSubir.toList(),
      });

  /// Null si no se puede leer: el tótem sigue como estaba.
  static ListaDeLaPc? decodificar(Object? texto) {
    if (texto is! String) return null;
    try {
      final m = jsonDecode(texto) as Map<String, dynamic>;
      return ListaDeLaPc(
        eventoId: m['evento_id'] as String,
        adentro: [
          for (final f in m['adentro'] as List)
            Invitado.fromJson(Map<String, dynamic>.from(f as Map)),
        ],
        sinSubir: {for (final id in m['sin_subir'] as List) id as String},
      );
    } catch (e) {
      debugPrint('La lista de la PC no se pudo leer: $e');
      return null;
    }
  }
}

/// La lista de un evento con lo que hay en la base de esta PC.
///
/// [leerInvitados] es la lista de la puerta del evento, sin ir a la nube;
/// [leerSinSubir], los ids de ese evento que esperan subir.
Future<ListaDeLaPc> armarListaDeLaPc(
  String eventoId, {
  required Future<List<Invitado>> Function(String eventoId) leerInvitados,
  required Future<Set<String>> Function(String eventoId) leerSinSubir,
}) async {
  final invitados = await leerInvitados(eventoId);
  final adentro = [
    for (final i in invitados)
      if (i.estadoIngreso == EstadoIngreso.ingresado) i,
  ];
  final ids = {for (final i in adentro) i.id};
  final sinSubir = await leerSinSubir(eventoId);
  return ListaDeLaPc(
    eventoId: eventoId,
    adentro: adentro,
    sinSubir: {for (final id in sinSubir) if (ids.contains(id)) id},
  );
}
