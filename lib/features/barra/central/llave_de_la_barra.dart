import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../cuentas/reglas_de_la_barra.dart';

/// **Quién se conecta a la central de la barra** (26-nov-2026). Hasta acá cualquier
/// aparato del wifi que supiera el número de la fiesta podía anular, mandar un OK falso o
/// cerrar una caja. Ahora la central solo deja entrar a quien puso su PIN en ese aparato:
/// la cajera, la encargada o el repositor con el suyo, el jefe (y la central de la otra
/// barra) con el PIN maestro de la notebook.
///
/// **El PIN no viaja**: la tablet guarda una llave sacada del PIN y con ella firma lo que
/// la central le pregunta (un número que cambia en cada conexión). La central, que tiene
/// los operadores en su base, saca la misma llave y compara. Y al revés: la central firma
/// lo que le preguntó la tablet, así una notebook de afuera no puede hacerse pasar por la
/// central.
class CredencialDeLaBarra {
  /// `operador` o `maestro` (el jefe, o la central de la otra barra).
  final String quien;
  final String? operadorId;
  final List<int> llave;

  const CredencialDeLaBarra._(this.quien, this.operadorId, this.llave);

  /// La de un operador: su id y su PIN.
  factory CredencialDeLaBarra.operador(String operadorId, String pin) =>
      CredencialDeLaBarra._('operador', operadorId, LlaveDeLaBarra.deOperador(pin));

  /// La del jefe o de la central: el PIN maestro.
  factory CredencialDeLaBarra.maestro(String pinMaestro) =>
      CredencialDeLaBarra._('maestro', null, LlaveDeLaBarra.deMaestro(pinMaestro));
}

/// Una persona que la central conoce, con su PIN y su rol.
class PersonaDeLaBarra {
  final String id;
  final String nombre;
  final String pin;
  final RolEnLaBarra? rol;

  const PersonaDeLaBarra({required this.id, required this.nombre, required this.pin, required this.rol});
}

/// Lo que la central necesita de su base para saber quién es quién. La implementa la
/// app con los operadores y sus permisos de esta notebook; las pruebas, en memoria.
abstract interface class QuienEsQuienEnLaBarra {
  /// El operador [id], activo, o null si esta notebook no lo tiene.
  Future<PersonaDeLaBarra?> operador(String id);

  /// El PIN maestro de esta notebook.
  Future<String?> pinMaestro();

  /// Si [nombre] es el de una encargada de barra activa (el OK que se da en la tablet de
  /// la cajera lo firma con su nombre).
  Future<bool> esEncargada(String nombre);
}

/// Las cuentas de la llave: puras.
abstract final class LlaveDeLaBarra {
  static List<int> deOperador(String pin) => sha256.convert(utf8.encode('barra-central|operador|${pin.trim()}')).bytes;

  static List<int> deMaestro(String pin) => sha256.convert(utf8.encode('barra-central|maestro|${pin.trim()}')).bytes;

  /// Lo que firma un lado ([lado]: `caja` o `central`) sobre el número [reto] del otro.
  static String firma(List<int> llave, {required String lado, required String reto, required String evento, required String equipo}) =>
      Hmac(sha256, llave).convert(utf8.encode('$lado|$reto|$evento|$equipo')).toString();

  /// Compara dos firmas sin cortar en la primera diferencia.
  static bool iguales(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  static final _azar = Random.secure();

  /// Un número para preguntar, distinto en cada conexión.
  static String reto() => [for (var i = 0; i < 16; i++) _azar.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}
