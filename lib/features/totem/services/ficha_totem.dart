import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../plano/modelo/armado_salon.dart';
import '../../recepcion/services/puerta_del_evento.dart';
import 'tiempos_a_mano.dart';

/// Lo que el tótem sabe de cada persona de un evento para saludarla completa.
///
/// El tótem lee la lista de la puerta (`invitados`), que tiene nombre y mesa y
/// nada más: no sabe quién es alumno, con quién viene, cuántas sillas le tocan
/// ni qué música eligió. Eso está en los alumnos, en la base de la PC. La
/// ventana principal arma esta ficha con lo mismo que ve Recepción
/// ([PuertaDelEvento]) y se la pasa al tótem por el puente entre ventanas. Así
/// saluda completo aunque el ingreso llegue de otra PC por la nube, y también
/// sin internet.
///
/// Sin pantalla ni base.
class FichaTotem {
  final String eventoId;

  /// Un evento masivo: sin QR, y la familia se saluda junta.
  final bool masivo;

  /// Las personas de un masivo, por el id de su fila en la lista de la puerta.
  /// En un particular está vacía: el tótem usa la fila, como siempre.
  final Map<String, PersonaFicha> personas;

  /// El salón de la fiesta (el armado de su plano, con lo que se acomodó a
  /// mano), para mostrar en la llegada dónde queda la mesa. Null: sin plano.
  final ArmadoSalon? plano;

  /// Los segundos de la llegada cambiados a mano esa noche en esta PC. Null:
  /// los de Personalizar. Viajan en la ficha por si se perdió el aviso.
  final TiemposAMano? tiempos;

  const FichaTotem({
    required this.eventoId,
    required this.masivo,
    this.personas = const {},
    this.plano,
    this.tiempos,
  });

  /// Un evento particular: el tótem saluda con lo que dice la lista.
  const FichaTotem.particular(this.eventoId)
      : masivo = false,
        personas = const {},
        plano = null,
        tiempos = null;

  /// La misma, con los segundos de esa noche.
  FichaTotem conTiempos(TiemposAMano? t) => FichaTotem(
        eventoId: eventoId,
        masivo: masivo,
        personas: personas,
        plano: plano,
        tiempos: t,
      );

  /// La ficha de lo que se ve en Recepción.
  ///
  /// De un masivo entran los alumnos que no están de baja y sus acompañantes
  /// con nombre. Lo cargado a mano en esa lista no entra: el tótem lo saluda
  /// con su fila, como en un particular. Las sillas van sin el "a confirmar"
  /// de Recepción: eso es para el operador, no para el salón.
  ///
  /// [plano] va solo en un masivo **ya sorteado**: un particular no tiene
  /// plano, y antes del sorteo el tótem espera como siempre, sin el salón (con
  /// el salón entero en la espera, 6.4.0, mostrarlo sin nadie sentado sería
  /// anunciar un salón que todavía no es).
  factory FichaTotem.desdePuerta(
    String eventoId,
    PuertaDelEvento puerta, {
    ArmadoSalon? plano,
  }) {
    if (!puerta.masivo) return FichaTotem.particular(eventoId);
    final personas = <String, PersonaFicha>{};
    for (final g in puerta.grupos) {
      if (g.cargadoAMano) continue;
      final titular = g.titular;
      // Una mesa reservada para quien no es alumno (los profes, 6.5.0): se
      // saludan juntos si llegan juntos, con su mesa y su distinción, y
      // ninguno acompaña a otro.
      final para = g.reservadaPara;
      if (para != null) {
        for (final p in g.personas) {
          personas[p.id] = PersonaFicha(
            id: p.id,
            nombre: p.nombre,
            familia: titular.id,
            esAlumno: false,
            mesa: p.mesa,
            grupo: para,
          );
        }
        continue;
      }
      personas[titular.id] = PersonaFicha(
        id: titular.id,
        nombre: titular.nombre,
        familia: titular.id,
        esAlumno: true,
        mesa: titular.mesa,
        sillas: titular.mesa == null ? null : g.sillas,
        musica: g.musica,
      );
      for (final a in g.acompanantes) {
        personas[a.id] = PersonaFicha(
          id: a.id,
          nombre: a.nombre,
          familia: titular.id,
          esAlumno: false,
          mesa: a.mesa,
          sillas: a.mesa == null ? null : g.sillas,
          titular: titular.nombre,
        );
      }
    }
    return FichaTotem(
      eventoId: eventoId,
      masivo: true,
      personas: personas,
      plano: puerta.sorteado ? plano : null,
    );
  }

  /// Esta ficha, con el plano de [anterior] si es el mismo salón. La ficha
  /// llega por el puente cada minuto y trae un plano recién leído: otra
  /// instancia del mismo salón haría rearmar todo lo que el tótem guarda por
  /// plano (el lugar del cuadro, la guía de la llegada) y redibujar el salón
  /// entero.
  FichaTotem conPlanoDe(FichaTotem? anterior) {
    final nuevo = plano;
    final viejo = anterior?.plano;
    if (nuevo == null || viejo == null || identical(nuevo, viejo)) return this;
    if (jsonEncode(nuevo.toJson()) != jsonEncode(viejo.toJson())) return this;
    return FichaTotem(
      eventoId: eventoId,
      masivo: masivo,
      personas: personas,
      plano: viejo,
      tiempos: tiempos,
    );
  }

  PersonaFicha? de(String id) => personas[id];

  /// Con quién se saluda a alguien: el id de su alumno. Quien no está en la
  /// ficha (un particular, lo cargado a mano) es su propia familia.
  String familiaDe(String id) => personas[id]?.familia ?? id;

  // Un armado de 140 mesas suma unos 15 KB.
  Map<String, dynamic> toJson() => {
        'evento_id': eventoId,
        'masivo': masivo,
        'personas': [for (final p in personas.values) p.toJson()],
        if (plano != null) 'plano': plano!.toJson(),
        if (tiempos != null) 'tiempos': tiempos!.toJson(),
      };

  /// `null` si no se puede leer: el tótem sigue con la que tenía. Un plano que
  /// no se puede leer no tira la ficha: va sin plano.
  static FichaTotem? fromJson(Object? json) {
    if (json is! Map) return null;
    final evento = json['evento_id'];
    if (evento is! String) return null;
    final lista = json['personas'];
    final personas = <String, PersonaFicha>{};
    if (lista is List) {
      for (final item in lista) {
        final p = PersonaFicha.fromJson(item);
        if (p != null) personas[p.id] = p;
      }
    }
    return FichaTotem(
      eventoId: evento,
      masivo: json['masivo'] == true,
      personas: personas,
      plano: _leerPlano(json['plano']),
      tiempos: TiemposAMano.fromJson(json['tiempos']),
    );
  }

  static ArmadoSalon? _leerPlano(Object? json) {
    if (json is! Map) return null;
    try {
      final armado = ArmadoSalon.fromJson(Map<String, dynamic>.from(json));
      return armado.mesas.isEmpty ? null : armado;
    } catch (e) {
      debugPrint('El plano de la ficha del tótem no se puede leer: $e');
      return null;
    }
  }

  /// Lo que viaja por el puente.
  String codificar() => jsonEncode(toJson());

  static FichaTotem? decodificar(Object? texto) {
    if (texto is! String || texto.isEmpty) return null;
    try {
      return fromJson(jsonDecode(texto));
    } catch (_) {
      return null;
    }
  }
}

/// Una persona de un evento masivo, como la saluda el tótem.
class PersonaFicha {
  final String id;
  final String nombre;

  /// El id del alumno con quien viene; el suyo, si es el alumno.
  final String familia;
  final bool esAlumno;

  /// "12", "14-15". Null si no tiene: el masivo no se sorteó, o él quedó sin
  /// mesa. En el salón nunca se dice "sin mesa".
  final String? mesa;

  /// "10 sillas (8 + 2 extra)", "14: 10 sillas · 15: 9 sillas".
  final String? sillas;

  /// La música que eligió el alumno. Solo en el alumno.
  final String? musica;

  /// En un acompañante, el nombre del alumno al que acompaña.
  final String? titular;

  /// En quien se sienta en una mesa reservada para quien no es alumno (6.5.0),
  /// para quién es ("Profes"): va en la tarjeta, donde un acompañante dice a
  /// quién acompaña.
  final String? grupo;

  const PersonaFicha({
    required this.id,
    required this.nombre,
    required this.familia,
    required this.esAlumno,
    this.mesa,
    this.sillas,
    this.musica,
    this.titular,
    this.grupo,
  });

  // Claves cortas: con 1.100 personas, el puente lleva unos 120 KB.
  Map<String, dynamic> toJson() => {
        'id': id,
        'n': nombre,
        'f': familia,
        if (esAlumno) 'a': true,
        'm': ?mesa,
        's': ?sillas,
        'mu': ?musica,
        't': ?titular,
        'g': ?grupo,
      };

  static PersonaFicha? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final nombre = json['n'];
    if (id is! String || nombre is! String) return null;
    String? texto(String clave) {
      final v = json[clave];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    return PersonaFicha(
      id: id,
      nombre: nombre,
      familia: texto('f') ?? id,
      esAlumno: json['a'] == true,
      mesa: texto('m'),
      sillas: texto('s'),
      musica: texto('mu'),
      titular: texto('t'),
      grupo: texto('g'),
    );
  }
}
