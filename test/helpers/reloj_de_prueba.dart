import 'dart:async';

import 'package:arguello_events/core/services/reloj_del_motor.dart';

/// Un reloj que avanza a mano, para el motor de sincronización (6.3.3).
///
/// Lo programado corre recién cuando la prueba llama a [avanzar], en orden y a
/// su hora: así se ve en un segundo qué le pide el motor a la nube en media
/// hora de reposo. El trabajo que eso arranca es de verdad (la base, la nube de
/// prueba): después de avanzar, `motor.aquietar()` espera a que termine.
class RelojDePrueba implements RelojDelMotor {
  RelojDePrueba([DateTime? inicio])
      : _ahora = inicio ?? DateTime(2026, 11, 10, 9);

  DateTime _ahora;
  var _orden = 0;
  final List<_Programado> _programados = [];

  @override
  DateTime ahora() => _ahora;

  @override
  Timer programar(Duration espera, void Function() accion) =>
      _alta(espera, accion, periodico: false);

  @override
  Timer periodico(Duration cada, void Function() accion) =>
      _alta(cada, accion, periodico: true);

  Timer _alta(Duration d, void Function() accion, {required bool periodico}) {
    final p = _Programado(
      vence: _ahora.add(d),
      cada: d,
      accion: accion,
      periodico: periodico,
      orden: _orden++,
    );
    _programados.add(p);
    return p;
  }

  /// Corre todo lo que vence hasta `ahora + d`, en orden. Lo periódico corre
  /// una vez por cada vuelta que entre en el tramo.
  void avanzar(Duration d) {
    final fin = _ahora.add(d);
    while (true) {
      final vencidos = _programados
          .where((p) => p.isActive && !p.vence.isAfter(fin))
          .toList()
        ..sort((a, b) {
          final c = a.vence.compareTo(b.vence);
          return c != 0 ? c : a.orden.compareTo(b.orden);
        });
      if (vencidos.isEmpty) break;
      final p = vencidos.first;
      _ahora = p.vence;
      p.disparar();
    }
    _programados.removeWhere((p) => !p.isActive);
    _ahora = fin;
  }

  /// Cuánto falta para cada cosa programada que sigue viva, de menor a mayor.
  List<Duration> get pendientes {
    final vivos = _programados.where((p) => p.isActive).toList()
      ..sort((a, b) => a.vence.compareTo(b.vence));
    return [for (final p in vivos) p.vence.difference(_ahora)];
  }

  /// Lo que sigue vivo y no es periódico (los reintentos, no las redes).
  List<Duration> get esperasSueltas {
    final vivos = _programados.where((p) => p.isActive && !p.periodico).toList()
      ..sort((a, b) => a.vence.compareTo(b.vence));
    return [for (final p in vivos) p.vence.difference(_ahora)];
  }
}

class _Programado implements Timer {
  _Programado({
    required this.vence,
    required this.cada,
    required this.accion,
    required this.periodico,
    required this.orden,
  });

  DateTime vence;
  final Duration cada;
  final void Function() accion;
  final bool periodico;
  final int orden;
  var _activo = true;
  var _vueltas = 0;

  void disparar() {
    _vueltas++;
    if (periodico) {
      vence = vence.add(cada);
    } else {
      _activo = false;
    }
    accion();
  }

  @override
  void cancel() => _activo = false;

  @override
  bool get isActive => _activo;

  @override
  int get tick => _vueltas;
}
