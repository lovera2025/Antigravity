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

/// Un delegado: **la persona**, con todos los celulares desde los que entró
/// (6.9.2). Lo que se le hace (sacarlo, dejarlo entrar de nuevo) vale para
/// todos sus celulares.
class DelegadoDelLink {
  /// El id de uno de sus celulares: con ese se le habla a la nube.
  final String id;
  final String nombre;

  /// "mar 17/11 19:02": cuándo entró por primera vez.
  final String entroTexto;

  /// Desde cuántos celulares entró.
  final int aparatos;

  /// Cuántos alumnos tienen hoy lo que cargó.
  final int cargados;

  /// De esos, cuántos guardó y no envió.
  final int sinEnviar;

  /// "mar 17/11 21:40": su último envío. Null: todavía no envió.
  final String? envioTexto;
  final bool sacado;

  const DelegadoDelLink({
    required this.id,
    required this.nombre,
    this.entroTexto = '',
    this.aparatos = 1,
    this.cargados = 0,
    this.sinEnviar = 0,
    this.envioTexto,
    this.sacado = false,
  });

  factory DelegadoDelLink.fromJson(Map<String, dynamic> j) => DelegadoDelLink(
        id: j['id'] as String,
        nombre: (j['nombre'] as String?) ?? '',
        entroTexto: (j['entro_texto'] as String?) ?? '',
        aparatos: (j['aparatos'] as num?)?.toInt() ?? 1,
        cargados: (j['cargados'] as num?)?.toInt() ?? 0,
        sinEnviar: (j['sin_enviar'] as num?)?.toInt() ?? 0,
        envioTexto: j['envio_texto'] as String?,
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

  /// Los delegados, por persona (6.9.2).
  final List<DelegadoDelLink> delegados;
  final int total;
  final int enPrograma;
  final int cargados;
  final int faltan;

  /// Guardados sin enviar · enviados que falta traer · ya traídos.
  final int sinEnviar;
  final int enviados;
  final int aceptados;

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
    this.delegados = const [],
    this.total = 0,
    this.enPrograma = 0,
    this.cargados = 0,
    this.faltan = 0,
    this.sinEnviar = 0,
    this.enviados = 0,
    this.aceptados = 0,
    this.aviso,
  });

  const EstadoDelLink.sinLink() : this(hay: false);

  /// Los delegados pueden cargar y corregir.
  bool get abierto => hay && estado == EstadoLink.abierto;

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
      delegados: [
        for (final d in (j['delegados'] as List?) ?? const [])
          DelegadoDelLink.fromJson((d as Map).cast<String, dynamic>()),
      ],
      total: (j['total'] as num?)?.toInt() ?? 0,
      enPrograma: (j['en_programa'] as num?)?.toInt() ?? 0,
      cargados: (j['cargados'] as num?)?.toInt() ?? 0,
      faltan: (j['faltan'] as num?)?.toInt() ?? 0,
      sinEnviar: (j['sin_enviar'] as num?)?.toInt() ?? 0,
      enviados: (j['enviados'] as num?)?.toInt() ?? 0,
      aceptados: (j['aceptados'] as num?)?.toInt() ?? 0,
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

  /// Quién lo cargó.
  final String? cargo;

  /// **Esta carga está enviada**: quien la cargó apretó Enviar después de
  /// guardarla. Lo corregido después de enviar vuelve a "sin enviar".
  final bool entregado;

  /// "jue 12/11 16:00": cuándo se cargó (6.9.2).
  final String? cuandoTexto;

  /// El jefe ya la había traído a la grilla.
  final bool traido;

  const CargaDelDelegado({
    required this.alumnoId,
    required this.alumno,
    required this.division,
    required this.activo,
    required this.acompanantes,
    required this.musica,
    this.cargo,
    required this.entregado,
    this.cuandoTexto,
    this.traido = false,
  });

  /// "Lo cargó LAURA GÓMEZ · jue 12/11 16:00".
  String? get quienYCuando => cargo == null
      ? null
      : 'Lo cargó $cargo${cuandoTexto == null ? '' : ' · $cuandoTexto'}';

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
        cuandoTexto: j['cuando_texto'] as String?,
        traido: j['traido'] == true,
      );
}

/// Un alumno en la lista ALUMNOS de la ventana del link (6.9.2): lo vigente,
/// quién lo cargó, cuándo y en qué quedó.
class AlumnoDelTablero {
  final String alumnoId;
  final String alumno;
  final String division;
  final List<String> acompanantes;
  final String musica;
  final EstadoDeLaCarga estado;
  final String? cargo;

  /// El [DelegadoDelLink.id] de quien lo cargó.
  final String? delegadoId;
  final String? cuandoTexto;

  /// Hay algo del link sin traer sobre un alumno que ya tenía datos en el
  /// programa: al traerlo, lo corrige.
  final bool otraVez;

  const AlumnoDelTablero({
    required this.alumnoId,
    required this.alumno,
    this.division = '',
    this.acompanantes = const [],
    this.musica = '',
    this.estado = EstadoDeLaCarga.falta,
    this.cargo,
    this.delegadoId,
    this.cuandoTexto,
    this.otraVez = false,
  });

  factory AlumnoDelTablero.fromJson(Map<String, dynamic> j) => AlumnoDelTablero(
        alumnoId: j['alumno_id'] as String,
        alumno: (j['alumno'] as String?) ?? '',
        division: (j['division'] as String?) ?? '',
        acompanantes: [
          for (final n in (j['acompanantes'] as List?) ?? const []) '$n',
        ],
        musica: (j['musica'] as String?) ?? '',
        estado: EstadoDeLaCarga.deClave(j['estado']),
        cargo: j['cargo'] as String?,
        delegadoId: j['delegado_id'] as String?,
        cuandoTexto: j['cuando_texto'] as String?,
        otraVez: j['otra_vez'] == true,
      );
}

/// Un renglón del historial: quién hizo qué con un alumno, y cuándo.
class CambioDelHistorial {
  final String alumnoId;
  final String quien;

  /// `guardo`, `vacio`, `aceptado` o `borrado`.
  final String que;
  final String cuandoTexto;
  final List<String> acompanantes;
  final String musica;

  const CambioDelHistorial({
    required this.alumnoId,
    required this.quien,
    required this.que,
    required this.cuandoTexto,
    this.acompanantes = const [],
    this.musica = '',
  });

  factory CambioDelHistorial.fromJson(Map<String, dynamic> j) =>
      CambioDelHistorial(
        alumnoId: j['alumno_id'] as String,
        quien: (j['quien'] as String?) ?? '',
        que: (j['que'] as String?) ?? '',
        cuandoTexto: (j['cuando_texto'] as String?) ?? '',
        acompanantes: [
          for (final n in (j['acompanantes'] as List?) ?? const []) '$n',
        ],
        musica: (j['musica'] as String?) ?? '',
      );

  /// "Guardó: GÓMEZ, ANA · PAZ, LUIS — Música: Tusa", en palabras.
  String get enPalabras {
    final datos = [
      if (acompanantes.isNotEmpty) acompanantes.join(' · '),
      if (musica.isNotEmpty) 'Música: $musica',
    ].join(' — ');
    return switch (que) {
      'guardo' => 'Guardó${datos.isEmpty ? '' : ': $datos'}',
      'vacio' => 'Sacó lo que había cargado',
      'aceptado' => 'Aceptado y cargado en el programa',
      'borrado' => 'Se borró al sacar al delegado',
      _ => que,
    };
  }
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

  /// `apagar`, `prender`, `vence` (con una fecha futura también prende),
  /// `cupo`, `sacar_dejando`, `sacar_borrando`, `readmitir` o `traido`.
  Future<RespuestaDelegado> cambiar(
    String eventoId,
    String accion, [
    String? valor,
  ]);
  Future<List<CargaDelDelegado>> cargas(String eventoId);
  Future<List<AvisoDelDelegado>> pendientes();

  /// Todos los alumnos de la fiesta, con lo vigente y su estado (6.9.2).
  Future<List<AlumnoDelTablero>> alumnos(String eventoId);

  /// Cada vez que alguien guardó, vació, aceptó o borró, del más viejo al más
  /// nuevo (6.9.2).
  Future<List<CambioDelHistorial>> historial(String eventoId);
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
  Future<List<AlumnoDelTablero>> alumnos(String eventoId) async {
    final r = await _nube.rpc(
      'delegado_alumnos_estado',
      params: {'p_evento': eventoId},
    );
    return [
      for (final a in (r as List?) ?? const [])
        AlumnoDelTablero.fromJson((a as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<List<CambioDelHistorial>> historial(String eventoId) async {
    final r = await _nube.rpc(
      'delegado_historial',
      params: {'p_evento': eventoId},
    );
    return [
      for (final h in (r as List?) ?? const [])
        CambioDelHistorial.fromJson((h as Map).cast<String, dynamic>()),
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
