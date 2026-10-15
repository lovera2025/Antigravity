import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/invitado.dart';

/// Alguien que encontró la búsqueda de la página del QR (`puerta_buscar`).
/// Sin DNI: solo si tiene uno cargado.
class EncontradoEnLaPuerta {
  final String id;
  final String nombre;
  final String? mesa;
  final bool ingresado;
  final bool tieneDni;

  const EncontradoEnLaPuerta({
    required this.id,
    required this.nombre,
    this.mesa,
    this.ingresado = false,
    this.tieneDni = false,
  });

  factory EncontradoEnLaPuerta.fromJson(Map<String, dynamic> json) =>
      EncontradoEnLaPuerta(
        id: json['id'] as String,
        nombre: json['nombre_completo'] as String,
        mesa: json['numero_mesa'] as String?,
        ingresado: json['ingresado'] == true,
        tieneDni: json['tiene_dni'] == true,
      );
}

/// Lo que contesta `puerta_checkin`.
enum ResultadoIngreso {
  /// Entró. Con [IngresoConDni.invitado] para avisarle al tótem.
  ok,
  yaIngresado,

  /// Con [IngresoConDni.quedan], los intentos que le quedan.
  dniIncorrecto,

  /// Tres intentos fallidos: lo anotan en la recepción.
  bloqueado,

  /// No tiene DNI cargado: lo anotan en la recepción.
  sinDni,

  /// Los de un evento masivo se anotan en la recepción.
  masivo,
  noEncontrado,
}

class IngresoConDni {
  final ResultadoIngreso resultado;
  final Invitado? invitado;
  final int? quedan;

  const IngresoConDni(this.resultado, {this.invitado, this.quedan});

  static const _porClave = {
    'ok': ResultadoIngreso.ok,
    'ya_ingresado': ResultadoIngreso.yaIngresado,
    'dni_incorrecto': ResultadoIngreso.dniIncorrecto,
    'bloqueado': ResultadoIngreso.bloqueado,
    'no_dni': ResultadoIngreso.sinDni,
    'masivo': ResultadoIngreso.masivo,
    'no_encontrado': ResultadoIngreso.noEncontrado,
  };

  factory IngresoConDni.fromJson(Map<String, dynamic> json) {
    final resultado = _porClave[json['resultado']];
    if (resultado == null) {
      throw FormatException('puerta_checkin contestó algo que no se conoce',
          '${json['resultado']}');
    }
    final inv = json['invitado'];
    return IngresoConDni(
      resultado,
      invitado: inv is Map
          ? Invitado.fromJson(Map<String, dynamic>.from(inv))
          : null,
      quedan: (json['quedan'] as num?)?.toInt(),
    );
  }
}

/// La lista de la puerta para quien no tiene usuario: la página del QR
/// (`/lista`) y `?buscar`, en la web.
///
/// **Desde la sección 8 de la 6.0.0 no lee la tabla `invitados`**: busca y
/// anota por las funciones de la nube (`puerta_buscar` y `puerta_checkin`,
/// `supabase/migrations/20261016120000_puerta_funciones.sql`). Así el celular
/// nunca recibe la lista entera ni el DNI de nadie: el DNI lo compara la
/// nube. Antes bajaba la lista con los DNI y los comparaba en el celular.
class SupabaseInvitadosRepository {
  SupabaseInvitadosRepository(SupabaseClient supabase)
      : _llamar = ((funcion, params) => supabase.rpc(funcion, params: params)),
        _avisar = _avisoPorElCanal(supabase);

  /// Sin nube, para los tests.
  @visibleForTesting
  SupabaseInvitadosRepository.con({
    required Future<dynamic> Function(String funcion, Map<String, dynamic> params)
        llamar,
    required Future<void> Function(Invitado invitado) avisar,
  })  : _llamar = llamar,
        _avisar = avisar;

  final Future<dynamic> Function(String funcion, Map<String, dynamic> params)
      _llamar;
  final Future<void> Function(Invitado invitado) _avisar;

  /// Hacen falta 3 letras entre todas para buscar (lo mismo pide la nube).
  static const letrasParaBuscar = 3;

  static int letrasDe(String texto) =>
      texto.replaceAll(RegExp(r'[\s,.;]'), '').length;

  /// Hasta 10, por nombre. En un evento masivo, nadie.
  Future<List<EncontradoEnLaPuerta>> buscar(String eventoId, String texto) async {
    if (eventoId.length != 36 || letrasDe(texto) < letrasParaBuscar) return [];
    final r = await _llamar(
      'puerta_buscar',
      {'p_evento': eventoId, 'p_texto': texto.trim()},
    );
    if (r is! List) {
      throw FormatException('puerta_buscar no devolvió una lista', '$r');
    }
    return [
      for (final f in r)
        EncontradoEnLaPuerta.fromJson(Map<String, dynamic>.from(f as Map)),
    ];
  }

  /// Anota el ingreso con el DNI, que compara la nube. Si entró, le avisa al
  /// tótem por el canal del evento (sin el DNI).
  Future<IngresoConDni> ingresarConDni({
    required String invitadoId,
    required String dni,
  }) async {
    final r = await _llamar(
      'puerta_checkin',
      {'p_invitado': invitadoId, 'p_dni': dni.trim()},
    );
    if (r is! Map) {
      throw FormatException('puerta_checkin no devolvió un resultado', '$r');
    }
    final ingreso = IngresoConDni.fromJson(Map<String, dynamic>.from(r));
    final inv = ingreso.invitado;
    if (ingreso.resultado == ResultadoIngreso.ok && inv != null) {
      try {
        await _avisar(inv);
      } catch (e) {
        // Entró igual: el tótem lo ve en su próxima lectura.
        debugPrint('No se pudo avisar al tótem: $e');
      }
    }
    return ingreso;
  }

  /// El aviso al tótem por el canal `totem_<evento>`, como hace Recepción.
  /// `sendBroadcastMessage` no necesita suscripción: sin socket, va por REST.
  static Future<void> Function(Invitado) _avisoPorElCanal(SupabaseClient s) {
    final canales = <String, RealtimeChannel>{};
    return (inv) => (canales[inv.eventoId] ??= s.channel('totem_${inv.eventoId}'))
        .sendBroadcastMessage(event: 'checkin', payload: inv.paraAviso());
  }
}
