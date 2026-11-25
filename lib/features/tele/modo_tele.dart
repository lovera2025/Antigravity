import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/evento.dart';
import '../common/utils/dia_de_la_fiesta.dart';

/// Qué es este equipo en el salón (la tele es el tótem, 24-nov-2026).
///
/// - **Tele 1 (principal):** dibuja el tótem y **es la central de la puerta**:
///   los celulares de las recepcionistas escanean su QR y marcan en su base. La
///   Tele 2 se le engancha.
/// - **Tele 2:** dibuja el tótem con una copia de la lista de la Tele 1, y
///   saluda lo de su recepcionista.
enum PapelDeLaTele {
  principal,
  segunda;

  int get numero => this == principal ? 1 : 2;
  String get nombre => 'Tele $numero';
}

/// El modo tele de este equipo: se elige una vez, en modo jefe, y queda. Desde
/// ahí la app abre derecho en el tótem, sin PIN, y **desde la tele no hay
/// camino al panel ni a cobrar**: salir pide el PIN del jefe.
@immutable
class ModoTele {
  final PapelDeLaTele papel;

  /// La dirección de la Tele 1 escrita a mano en la Tele 2 ("192.168.0.10:8787"),
  /// si el router no deja que se encuentren solas.
  final String? direccionAMano;

  /// El fondo animado del tótem cuesta en una tele chica: con esto va quieto.
  final bool fondoQuieto;

  const ModoTele(
    this.papel, {
    this.direccionAMano,
    this.fondoQuieto = false,
  });

  int get numero => papel.numero;

  ModoTele con({String? direccionAMano, bool? fondoQuieto, bool sinDireccion = false}) =>
      ModoTele(
        papel,
        direccionAMano: sinDireccion ? null : (direccionAMano ?? this.direccionAMano),
        fondoQuieto: fondoQuieto ?? this.fondoQuieto,
      );

  Map<String, Object?> toJson() => {
        'papel': papel.name,
        if (direccionAMano != null) 'direccion': direccionAMano,
        if (fondoQuieto) 'fondo_quieto': true,
      };

  static ModoTele? fromJson(Object? json) {
    if (json is! Map) return null;
    final papel = PapelDeLaTele.values.where((p) => p.name == json['papel']).firstOrNull;
    if (papel == null) return null;
    final d = json['direccion'];
    return ModoTele(
      papel,
      direccionAMano: d is String && d.trim().isNotEmpty ? d.trim() : null,
      fondoQuieto: json['fondo_quieto'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ModoTele &&
      other.papel == papel &&
      other.direccionAMano == direccionAMano &&
      other.fondoQuieto == fondoQuieto;

  @override
  int get hashCode => Object.hash(papel, direccionAMano, fondoQuieto);
}

/// El modo tele guardado en este equipo. Se lee antes de abrir la app
/// (`main.dart`): así la tele arranca derecho en el tótem.
class ModoTeleGuardado {
  static const clave = 'modo_tele_v1';

  /// La fiesta que se eligió con el control, si había más de una esa noche.
  static const claveFiesta = 'modo_tele_fiesta_v1';

  static ModoTele? _leido;
  static ModoTele? get leido => _leido;

  static Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(clave);
      _leido = crudo == null ? null : ModoTele.fromJson(jsonDecode(crudo));
    } catch (e) {
      debugPrint('El modo tele no se pudo leer: $e');
      _leido = null;
    }
  }

  static Future<void> guardar(ModoTele? modo) async {
    _leido = modo;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (modo == null) {
        await prefs.remove(clave);
        await prefs.remove(claveFiesta);
      } else {
        await prefs.setString(clave, jsonEncode(modo.toJson()));
      }
    } catch (e) {
      debugPrint('El modo tele no se pudo guardar: $e');
    }
  }

  static Future<String?> fiestaElegida() async {
    try {
      return (await SharedPreferences.getInstance()).getString(claveFiesta);
    } catch (_) {
      return null;
    }
  }

  static Future<void> elegirFiesta(String eventoId) async {
    try {
      await (await SharedPreferences.getInstance()).setString(claveFiesta, eventoId);
    } catch (_) {}
  }
}

/// El modo tele de este equipo, o null (lo de siempre). Las pruebas lo
/// reemplazan: en la ventana de prueba hay dos teles en el mismo proceso.
final modoTeleProvider = NotifierProvider<ModoTeleNotifier, ModoTele?>(ModoTeleNotifier.new);

class ModoTeleNotifier extends Notifier<ModoTele?> {
  @override
  ModoTele? build() => ModoTeleGuardado.leido;

  Future<void> poner(ModoTele? modo) async {
    state = modo;
    await ModoTeleGuardado.guardar(modo);
  }
}

/// Qué fiesta muestra la tele.
///
/// **La que viene**, empezando por la de hoy (y la de anoche hasta el mediodía:
/// [primerDiaDeLasFiestasQueVienen]): en la oficina, el día antes, la tele ya
/// muestra la del sábado para ver que quedó lista. Si ese día hay más de una,
/// [paraElegir] trae las de ese día y la tele pregunta con el control; si ya se
/// eligió una ([elegida]) y sigue en la lista, va esa.
@immutable
class FiestaDeLaTele {
  /// La que se muestra, o null si hay que elegir (o no hay ninguna).
  final Evento? fiesta;

  /// Las del mismo día que la primera, si son más de una.
  final List<Evento> paraElegir;

  /// Todas las que vienen, para cambiar con el control.
  final List<Evento> todas;

  const FiestaDeLaTele({this.fiesta, this.paraElegir = const [], this.todas = const []});

  bool get hayQueElegir => fiesta == null && paraElegir.length > 1;
  bool get ninguna => fiesta == null && paraElegir.isEmpty;

  static FiestaDeLaTele de(List<Evento> eventos, DateTime ahora, {String? elegida}) {
    final vienen = enElOrdenDeLasFiestas(
      eventos.where((e) => !laFiestaYaPaso(e, ahora)),
      ahora,
    );
    if (vienen.isEmpty) return const FiestaDeLaTele();
    final yaElegida = vienen.where((e) => e.id == elegida).firstOrNull;
    if (yaElegida != null) {
      return FiestaDeLaTele(fiesta: yaElegida, todas: vienen);
    }
    final primera = vienen.first.fechaEvento;
    final delMismoDia = [
      for (final e in vienen)
        if (e.fechaEvento.year == primera.year &&
            e.fechaEvento.month == primera.month &&
            e.fechaEvento.day == primera.day)
          e,
    ];
    if (delMismoDia.length > 1) {
      return FiestaDeLaTele(paraElegir: delMismoDia, todas: vienen);
    }
    return FiestaDeLaTele(fiesta: vienen.first, todas: vienen);
  }
}
