import 'dart:async';

/// El reloj con el que el motor de sincronización programa lo que hace solo
/// (6.3.3): la subida a los 2 s, el pulso, los reintentos, la red de seguridad.
///
/// En la app es el reloj de siempre. Las pruebas le pasan uno que avanza a mano
/// (`test/helpers/reloj_de_prueba.dart`): así se ve qué le pide el motor a la
/// nube en media hora de reposo sin esperar media hora. No se usa `fake_async`
/// porque el motor trabaja con una base SQLite de verdad, y esa espera no
/// avanza con un reloj falso.
abstract class RelojDelMotor {
  const RelojDelMotor();

  const factory RelojDelMotor.real() = _RelojReal;

  DateTime ahora();

  /// Corre [accion] una vez, dentro de [espera].
  Timer programar(Duration espera, void Function() accion);

  /// Corre [accion] cada [cada], hasta que se cancele.
  Timer periodico(Duration cada, void Function() accion);
}

class _RelojReal extends RelojDelMotor {
  const _RelojReal();

  @override
  DateTime ahora() => DateTime.now();

  @override
  Timer programar(Duration espera, void Function() accion) =>
      Timer(espera, accion);

  @override
  Timer periodico(Duration cada, void Function() accion) =>
      Timer.periodic(cada, (_) => accion());
}
