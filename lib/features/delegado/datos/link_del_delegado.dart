import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../eventos/services/planilla_delegado.dart';
import 'nube_del_delegado.dart';

/// El link del delegado, del lado del programa (6.8.0): lo que hace el jefe,
/// **con usuario**. También solo por funciones.

enum EstadoLink { abierto, vencido, apagado }

class CelularDelLink {
  final String id;

  /// Quién dijo ser al entrar.
  final String nombre;
  final String entroTexto;
  final int cargados;
  final bool entregado;
  final String? entregadoTexto;
  final bool sacado;

  const CelularDelLink({
    required this.id,
    required this.nombre,
    required this.entroTexto,
    required this.cargados,
    required this.entregado,
    this.entregadoTexto,
    required this.sacado,
  });

  factory CelularDelLink.fromJson(Map<String, dynamic> j) => CelularDelLink(
        id: j['id'] as String,
        nombre: (j['nombre'] as String?) ?? '',
        entroTexto: (j['entro_texto'] as String?) ?? '',
        cargados: (j['cargados'] as num?)?.toInt() ?? 0,
        entregado: j['entregado'] == true,
        entregadoTexto: j['entregado_texto'] as String?,
        sacado: j['sacado'] == true,
      );
}

/// Cómo está el link de una fiesta.
class EstadoDelLink {
  /// La fiesta todavía no tiene link.
  final bool hay;
  final String clave;
  final String venceTexto;

  /// "2026-11-19 20:00", en hora de Argentina: para volver a mostrarlo.
  final String venceLocal;
  final EstadoLink estado;
  final int cupo;
  final List<CelularDelLink> celulares;
  final int total;
  final int enPrograma;
  final int cargados;
  final int faltan;

  /// El aviso para el inicio, si hay algo para traer.
  final String? aviso;

  const EstadoDelLink({
    required this.hay,
    this.clave = '',
    this.venceTexto = '',
    this.venceLocal = '',
    this.estado = EstadoLink.abierto,
    this.cupo = 1,
    this.celulares = const [],
    this.total = 0,
    this.enPrograma = 0,
    this.cargados = 0,
    this.faltan = 0,
    this.aviso,
  });

  const EstadoDelLink.sinLink() : this(hay: false);

  factory EstadoDelLink.fromJson(Map<String, dynamic> j) {
    if (j['ok'] != true) return const EstadoDelLink.sinLink();
    return EstadoDelLink(
      hay: true,
      clave: (j['clave'] as String?) ?? '',
      venceTexto: (j['vence_texto'] as String?) ?? '',
      venceLocal: (j['vence_local'] as String?) ?? '',
      estado: switch (j['estado']) {
        'vencido' => EstadoLink.vencido,
        'apagado' => EstadoLink.apagado,
        _ => EstadoLink.abierto,
      },
      cupo: (j['cupo'] as num?)?.toInt() ?? 1,
      celulares: [
        for (final c in (j['celulares'] as List?) ?? const [])
          CelularDelLink.fromJson((c as Map).cast<String, dynamic>()),
      ],
      total: (j['total'] as num?)?.toInt() ?? 0,
      enPrograma: (j['en_programa'] as num?)?.toInt() ?? 0,
      cargados: (j['cargados'] as num?)?.toInt() ?? 0,
      faltan: (j['faltan'] as num?)?.toInt() ?? 0,
      aviso: j['aviso'] as String?,
    );
  }
}

/// Lo que cargó un delegado para un alumno, como lo da `delegado_cargas`.
class CargaDelDelegado {
  final String alumnoId;
  final String alumno;
  final String division;

  /// Sigue activo en la fiesta. Si no, no se carga.
  final bool activo;
  final List<String> acompanantes;
  final String musica;

  /// Quién lo cargó. Null si a esa persona se la sacó dejando lo cargado.
  final String? cargo;

  /// Quien lo cargó ya apretó Enviar.
  final bool entregado;

  const CargaDelDelegado({
    required this.alumnoId,
    required this.alumno,
    required this.division,
    required this.activo,
    required this.acompanantes,
    required this.musica,
    this.cargo,
    required this.entregado,
  });

  factory CargaDelDelegado.fromJson(Map<String, dynamic> j) => CargaDelDelegado(
        alumnoId: j['alumno_id'] as String,
        alumno: (j['alumno'] as String?) ?? '',
        division: (j['division'] as String?) ?? '',
        activo: j['activo'] == true,
        acompanantes: [
          for (final n in (j['acompanantes'] as List?) ?? const []) '$n',
        ],
        musica: (j['musica'] as String?) ?? '',
        cargo: j['cargo'] as String?,
        entregado: j['entregado'] == true,
      );
}

/// Un aviso para ALERTAS del Centro de Comando: uno por fiesta.
class AvisoDelDelegado {
  final String eventoId;
  final String texto;
  const AvisoDelDelegado({required this.eventoId, required this.texto});
}

/// Lo que el programa le pide a la nube.
abstract class LinkDelDelegado {
  Future<EstadoDelLink> estado(String eventoId);

  /// [venceLocal]: "2026-11-19 20:00", hora de Argentina. La nube lo convierte.
  Future<RespuestaDelegado> crear({
    required String eventoId,
    required String fiesta,
    required String venceLocal,
    required int cupo,
  });

  /// `apagar`, `prender`, `vence`, `cupo`, `sacar_dejando`, `sacar_borrando`,
  /// `reabrir` o `traido`.
  Future<RespuestaDelegado> cambiar(
    String eventoId,
    String accion, [
    String? valor,
  ]);
  Future<List<CargaDelDelegado>> cargas(String eventoId);
  Future<List<AvisoDelDelegado>> pendientes();
}

Map<String, dynamic> _mapa(dynamic r) =>
    r is Map ? r.cast<String, dynamic>() : const <String, dynamic>{};

class LinkDelDelegadoSupabase implements LinkDelDelegado {
  final SupabaseClient _nube;
  const LinkDelDelegadoSupabase(this._nube);

  @override
  Future<EstadoDelLink> estado(String eventoId) async =>
      EstadoDelLink.fromJson(_mapa(await _nube.rpc(
        'delegado_link',
        params: {'p_evento': eventoId},
      )));

  @override
  Future<RespuestaDelegado> crear({
    required String eventoId,
    required String fiesta,
    required String venceLocal,
    required int cupo,
  }) async =>
      RespuestaDelegado.fromJson(_mapa(await _nube.rpc(
        'delegado_link_crear',
        params: {
          'p_evento': eventoId,
          'p_fiesta': fiesta,
          'p_vence_local': venceLocal,
          'p_cupo': cupo,
        },
      )));

  @override
  Future<RespuestaDelegado> cambiar(
    String eventoId,
    String accion, [
    String? valor,
  ]) async =>
      RespuestaDelegado.fromJson(_mapa(await _nube.rpc(
        'delegado_link_cambiar',
        params: {'p_evento': eventoId, 'p_accion': accion, 'p_valor': valor},
      )));

  @override
  Future<List<CargaDelDelegado>> cargas(String eventoId) async {
    final r = await _nube.rpc('delegado_cargas', params: {'p_evento': eventoId});
    return [
      for (final c in (r as List?) ?? const [])
        CargaDelDelegado.fromJson((c as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<List<AvisoDelDelegado>> pendientes() async {
    // Con `params`, aunque no lleve ninguno: sin eso la librería manda `null`
    // de cuerpo en vez de `{}`, y la nube lo rechaza.
    final r = await _nube.rpc(
      'delegado_pendientes',
      params: const <String, dynamic>{},
    );
    return [
      for (final a in (r as List?) ?? const [])
        AvisoDelDelegado(
          eventoId: '${(a as Map)['evento_id']}',
          texto: '${a['texto']}',
        ),
    ];
  }
}

/// "2026-11-19 20:00": cómo se le manda el límite a la nube.
String venceLocalDe(DateTime dia, int hora, int minuto) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dia.year}-${dos(dia.month)}-${dos(dia.day)} ${dos(hora)}:${dos(minuto)}';
}

/// La lista de ids que se le avisa a la nube que ya se trajeron.
String idsTraidos(Iterable<String> alumnoIds) => jsonEncode(alumnoIds.toList());

/// Lo que cargaron los delegados, como lo espera [PlanillaDelegado.comparar]:
/// la misma revisión del Excel, sin escribir nada.
///
/// Cada acompañante ya viene en su casillero, así que no se separa por ningún
/// signo (un apellido con " y " o con una barra no se parte) y la coma no es
/// un aviso.
LecturaPlanilla lecturaDeLasCargas({
  required String eventoId,
  required String fiesta,
  required Iterable<CargaDelDelegado> cargas,
}) {
  var fila = 0;
  return LecturaPlanilla(
    eventoId: eventoId.toLowerCase(),
    institucion: fiesta,
    delLink: true,
    renglones: [
      for (final c in cargas)
        RenglonDelegado(
          fila: ++fila,
          codigo: 'K${c.alumnoId.replaceAll('-', '').toUpperCase()}',
          alumno: c.alumno,
          acompanantes: c.acompanantes.join(' / '),
          nombres: c.acompanantes,
          musica: c.musica.trim().replaceAll(RegExp(r'\s+'), ' '),
        ),
    ],
  );
}
