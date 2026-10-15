import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El código de la central de la puerta: cuatro cifras que van en el QR y que
/// se escriben si el celular entra con la dirección.
///
/// **Es uno por evento y por noche, y se guarda en la PC.** Si la notebook se
/// reinicia en medio de la fiesta, la central vuelve con el mismo código y los
/// celulares se reconectan solos, sin volver a escanear. Al día siguiente
/// (pasadas [kCodigoDura]) sale otro: un celular de la fiesta anterior no entra.
///
/// No es una contraseña: en el router de ustedes solo están ustedes. Es para
/// que un celular de alguien que se conectó al router no pueda marcar
/// ingresos. La central además frena a quien erra muchas veces seguidas.
const kCodigoDura = Duration(hours: 18);

/// Cuatro cifras, de 1000 a 9999: sin ceros adelante que alguien se coma al
/// escribirlo.
String nuevoCodigo([Random? azar]) =>
    ((azar ?? Random.secure()).nextInt(9000) + 1000).toString();

/// Si un código creado en [creado] sigue sirviendo en [ahora].
bool codigoVigente(DateTime creado, DateTime ahora) {
  final pasaron = ahora.difference(creado);
  return !pasaron.isNegative && pasaron < kCodigoDura;
}

/// El código de cada evento, guardado en esta PC.
class CodigoCentral {
  static const _prefijo = 'central_puerta_codigo_v1_';

  static String _clave(String eventoId) => '$_prefijo$eventoId';

  /// El de [eventoId] si sigue vigente; si no, uno nuevo que queda guardado.
  static Future<String> delEvento(
    String eventoId, {
    DateTime? ahora,
    Random? azar,
  }) async {
    final cuando = ahora ?? DateTime.now();
    return await vigente(eventoId, ahora: cuando) ??
        await cambiar(eventoId, ahora: cuando, azar: azar);
  }

  /// El de [eventoId] si se sacó esta noche, sin sacar uno nuevo. Que haya
  /// uno quiere decir que la central se usó: al reabrir el programa vuelve
  /// sola (`CentralDeLaPuerta.reanudar`).
  static Future<String?> vigente(String eventoId, {DateTime? ahora}) async {
    final cuando = ahora ?? DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final partes = prefs.getString(_clave(eventoId))?.split('|');
      if (partes != null && partes.length == 2) {
        final creado = DateTime.tryParse(partes[1]);
        if (creado != null &&
            RegExp(r'^\d{4}$').hasMatch(partes[0]) &&
            codigoVigente(creado, cuando)) {
          return partes[0];
        }
      }
    } catch (e) {
      debugPrint('CodigoCentral.vigente: $e');
    }
    return null;
  }

  /// Saca uno nuevo para [eventoId], distinto de [anterior]: los celulares que
  /// estaban conectados tienen que volver a escanear.
  static Future<String> cambiar(
    String eventoId, {
    String? anterior,
    DateTime? ahora,
    Random? azar,
  }) async {
    final sorteo = azar ?? Random.secure();
    var codigo = nuevoCodigo(sorteo);
    while (codigo == anterior) {
      codigo = nuevoCodigo(sorteo);
    }
    final cuando = (ahora ?? DateTime.now()).toUtc().toIso8601String();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave(eventoId), '$codigo|$cuando');
    } catch (e) {
      debugPrint('CodigoCentral.cambiar: $e');
    }
    return codigo;
  }
}
