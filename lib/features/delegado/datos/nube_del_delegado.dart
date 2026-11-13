import 'package:supabase_flutter/supabase_flutter.dart';

/// El link del delegado, del lado de la página (6.8.0): lo que le pide a la
/// nube quien **no tiene usuario**.
///
/// **Solo funciones, nunca una tabla.** Las tablas del link están cerradas del
/// todo; las reglas (el límite, quién cargó qué, los topes) viven en el SQL
/// `supabase/migrations/20261113120000_link_delegado.sql`.
/// `test/link_delegado_cerrado_test.dart` compara ese SQL con lo que se llama
/// acá y falla si algo de esta carpeta lee una tabla.

/// Los topes que también controla la nube. El test los compara con el SQL.
const int kMaxLetrasAcompananteDelegado = 80;
const int kMaxLetrasMusicaDelegado = 300;
const int kMaxDelegadosPorLink = 5;

/// De quién es lo cargado de un alumno, para quien mira la lista.
enum DeQuien {
  /// Ya tiene acompañantes y música en el programa: no se toca desde el link.
  programa,

  /// Nadie lo cargó todavía.
  libre,

  /// Lo cargó alguien a quien después se sacó: cualquiera lo puede corregir.
  suelto,

  /// Lo cargó este celular.
  mio,

  /// Lo cargó otro delegado: cerrado.
  otro,
}

class AlumnoDelLink {
  final String id;
  final String nombre;
  final String division;

  /// En el programa ya tiene acompañantes / música: ese casillero va fijo.
  final bool progAcomp;
  final bool progMusica;
  final DeQuien de;

  /// Quién lo cargó, si fue otro delegado.
  final String? cargo;

  /// Lo cargado. Vacío si es de otro: la nube no lo manda.
  final List<String> acompanantes;
  final String musica;

  const AlumnoDelLink({
    required this.id,
    required this.nombre,
    required this.division,
    required this.progAcomp,
    required this.progMusica,
    required this.de,
    this.cargo,
    this.acompanantes = const [],
    this.musica = '',
  });

  /// No se puede abrir: ya está en el programa o lo cargó otro.
  bool get cerrado => de == DeQuien.programa || de == DeQuien.otro;

  factory AlumnoDelLink.fromJson(Map<String, dynamic> j) => AlumnoDelLink(
        id: j['id'] as String,
        nombre: (j['nombre'] as String?) ?? '',
        division: (j['division'] as String?) ?? '',
        progAcomp: j['prog_acomp'] == true,
        progMusica: j['prog_musica'] == true,
        de: switch (j['de']) {
          'programa' => DeQuien.programa,
          'suelto' => DeQuien.suelto,
          'mio' => DeQuien.mio,
          'otro' => DeQuien.otro,
          _ => DeQuien.libre,
        },
        cargo: j['cargo'] as String?,
        acompanantes: [
          for (final n in (j['acompanantes'] as List?) ?? const []) '$n',
        ],
        musica: (j['musica'] as String?) ?? '',
      );
}

/// Lo que contesta `delegado_lista`.
class ListaDelDelegado {
  final bool ok;

  /// Por qué no: `link`, `apagado`, `entrar` o `sacado`.
  final String? motivo;
  final String fiesta;

  /// "jueves 19/11 a las 20:00", ya en hora de Argentina. **Lo arma la nube:**
  /// la página no usa el reloj del celular para nada.
  final String venceTexto;
  final bool vencido;

  /// Ya entraron todos los delegados que se esperaban.
  final bool lleno;
  final String yoNombre;
  final bool yoEntregado;
  final int total;
  final int cargados;
  final int faltan;
  final int mios;
  final List<AlumnoDelLink> alumnos;

  const ListaDelDelegado({
    required this.ok,
    this.motivo,
    this.fiesta = '',
    this.venceTexto = '',
    this.vencido = false,
    this.lleno = false,
    this.yoNombre = '',
    this.yoEntregado = false,
    this.total = 0,
    this.cargados = 0,
    this.faltan = 0,
    this.mios = 0,
    this.alumnos = const [],
  });

  /// Adentro, pero ya no se puede cargar ni enviar.
  bool get soloLectura => yoEntregado || vencido;

  factory ListaDelDelegado.fromJson(Map<String, dynamic> j) {
    final yo = (j['yo'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ListaDelDelegado(
      ok: j['ok'] == true,
      motivo: j['motivo'] as String?,
      fiesta: (j['fiesta'] as String?) ?? '',
      venceTexto: (j['vence_texto'] as String?) ?? '',
      vencido: j['vencido'] == true,
      lleno: j['lleno'] == true,
      yoNombre: (yo['nombre'] as String?) ?? '',
      yoEntregado: yo['entregado'] == true,
      total: (j['total'] as num?)?.toInt() ?? 0,
      cargados: (j['cargados'] as num?)?.toInt() ?? 0,
      faltan: (j['faltan'] as num?)?.toInt() ?? 0,
      mios: (j['mios'] as num?)?.toInt() ?? 0,
      alumnos: [
        for (final a in (j['alumnos'] as List?) ?? const [])
          AlumnoDelLink.fromJson((a as Map).cast<String, dynamic>()),
      ],
    );
  }
}

/// Lo que contestan las funciones que cambian algo.
class RespuestaDelegado {
  final bool ok;
  final String? motivo;

  /// Con `largo` o `ya_cargado`: `acompanantes` o `musica`.
  final String? campo;

  /// Con `otro`: quién lo cargó.
  final String? cargo;

  /// Al guardar vacío un alumno propio: quedó libre.
  final bool libre;

  /// Al enviar por segunda vez: ya estaba enviado.
  final bool ya;

  /// Al entrar: la sesión de este celular.
  final String? sesion;

  /// Al crear el link: su clave.
  final String? clave;

  const RespuestaDelegado({
    required this.ok,
    this.motivo,
    this.campo,
    this.cargo,
    this.libre = false,
    this.ya = false,
    this.sesion,
    this.clave,
  });

  factory RespuestaDelegado.fromJson(Map<String, dynamic> j) =>
      RespuestaDelegado(
        ok: j['ok'] == true,
        motivo: j['motivo'] as String?,
        campo: j['campo'] as String?,
        cargo: j['cargo'] as String?,
        libre: j['libre'] == true,
        ya: j['ya'] == true,
        sesion: j['sesion'] as String?,
        clave: j['clave'] as String?,
      );
}

/// Lo que la página le pide a la nube.
abstract class NubeDelDelegado {
  Future<ListaDelDelegado> lista(String clave, String? sesion);
  Future<RespuestaDelegado> entrar(String clave, String nombre);
  Future<RespuestaDelegado> guardar({
    required String clave,
    required String sesion,
    required String alumnoId,
    required List<String> acompanantes,
    required String musica,
  });
  Future<RespuestaDelegado> entregar(String clave, String sesion);
}

Map<String, dynamic> _mapa(dynamic r) =>
    r is Map ? r.cast<String, dynamic>() : const <String, dynamic>{};

class NubeDelDelegadoSupabase implements NubeDelDelegado {
  final SupabaseClient _nube;
  const NubeDelDelegadoSupabase(this._nube);

  @override
  Future<ListaDelDelegado> lista(String clave, String? sesion) async =>
      ListaDelDelegado.fromJson(_mapa(await _nube.rpc(
        'delegado_lista',
        params: {'p_clave': clave, 'p_sesion': sesion},
      )));

  @override
  Future<RespuestaDelegado> entrar(String clave, String nombre) async =>
      RespuestaDelegado.fromJson(_mapa(await _nube.rpc(
        'delegado_entrar',
        params: {'p_clave': clave, 'p_nombre': nombre},
      )));

  @override
  Future<RespuestaDelegado> guardar({
    required String clave,
    required String sesion,
    required String alumnoId,
    required List<String> acompanantes,
    required String musica,
  }) async =>
      RespuestaDelegado.fromJson(_mapa(await _nube.rpc(
        'delegado_guardar',
        params: {
          'p_clave': clave,
          'p_sesion': sesion,
          'p_alumno': alumnoId,
          'p_acompanantes': acompanantes,
          'p_musica': musica,
        },
      )));

  @override
  Future<RespuestaDelegado> entregar(String clave, String sesion) async =>
      RespuestaDelegado.fromJson(_mapa(await _nube.rpc(
        'delegado_entregar',
        params: {'p_clave': clave, 'p_sesion': sesion},
      )));
}
