import 'package:supabase_flutter/supabase_flutter.dart';

/// El link del delegado, del lado de la página (6.8.0): lo que le pide a la
/// nube quien **no tiene usuario**.
///
/// **Solo funciones, nunca una tabla.** Las tablas del link están cerradas del
/// todo; las reglas (el límite, quién cargó qué, los topes) viven en el SQL
/// `supabase/migrations/20261113120000_link_delegado.sql` y, desde la 6.9.2, en
/// `20261118120000_link_delegado_reabrir.sql`.
/// `test/link_delegado_cerrado_test.dart` compara ese SQL con lo que se llama
/// acá y falla si algo de esta carpeta lee una tabla.
///
/// **Desde la 6.9.2 todos corrigen todo** (decisión del usuario, 17-nov-2026):
/// lo que cargó otro, lo ya enviado y lo que ya está en el programa se pueden
/// abrir y corregir; Enviar no cierra; lo único que cierra es la fecha límite.

/// Los topes que también controla la nube. El test los compara con el SQL.
const int kMaxLetrasAcompananteDelegado = 80;
const int kMaxLetrasMusicaDelegado = 300;
const int kMaxDelegadosPorLink = 5;

/// De quién es lo cargado de un alumno, para quien mira la lista.
enum DeQuien {
  /// Ya tiene acompañantes y música en el programa, y nadie lo tocó por el link.
  programa,

  /// Nadie lo cargó todavía.
  libre,

  /// Lo cargó alguien de quien ya no se sabe el nombre (una carga anterior a la
  /// 6.9.2 de un delegado sacado).
  suelto,

  /// Lo cargó este delegado (desde este celular o desde otro).
  mio,

  /// Lo cargó otro delegado. Se puede corregir, con un aviso antes.
  otro,
}

/// En qué quedó lo de un alumno.
enum EstadoDeLaCarga {
  /// Nadie cargó nada (o le falta una de las dos cosas y nadie la completó).
  falta,

  /// Ya estaba en el programa y nadie lo tocó por el link.
  programa,

  /// Guardado, todavía sin enviar (o corregido después de enviar).
  sinEnviar,

  /// Enviado: falta que el jefe lo traiga.
  enviado,

  /// El jefe ya lo trajo a la grilla.
  aceptado;

  static EstadoDeLaCarga deClave(Object? clave) => switch (clave) {
        'programa' => programa,
        'sin_enviar' => sinEnviar,
        'enviado' => enviado,
        'aceptado' => aceptado,
        _ => falta,
      };
}

class AlumnoDelLink {
  final String id;
  final String nombre;
  final String division;

  /// En el programa ya tiene acompañantes / música: ese casillero va fijo.
  final bool progAcomp;
  final bool progMusica;
  final DeQuien de;

  /// Quién lo cargó por el link, si alguien lo cargó.
  final String? cargo;

  /// "jue 19/11 20:14": cuándo se cargó. Lo arma la nube.
  final String? cuandoTexto;

  /// Lo vigente: lo cargado por el link y, en el casillero que vino vacío, lo
  /// que ya está en el programa. Es lo que ve quien lo abre para corregir.
  final List<String> acompanantes;
  final String musica;
  final EstadoDeLaCarga estado;

  const AlumnoDelLink({
    required this.id,
    required this.nombre,
    required this.division,
    required this.progAcomp,
    required this.progMusica,
    required this.de,
    this.cargo,
    this.cuandoTexto,
    this.acompanantes = const [],
    this.musica = '',
    this.estado = EstadoDeLaCarga.falta,
  });

  /// Ya tiene algo: cargado por el link, o en el programa.
  bool get cargado => estado != EstadoDeLaCarga.falta;

  /// Abrirlo es corregir lo de otro (otro delegado, o lo que ya está en el
  /// programa): la página avisa antes de dejar escribir.
  bool get esDeOtro =>
      de == DeQuien.otro || de == DeQuien.suelto || de == DeQuien.programa;

  /// "Ya cargado · LAURA GÓMEZ · jue 19/11 20:14", o lo que corresponda.
  String get rotuloDeCargado {
    if (estado == EstadoDeLaCarga.programa || cargo == null) {
      return 'Ya cargado en el programa';
    }
    return 'Ya cargado · $cargo${cuandoTexto == null ? '' : ' · $cuandoTexto'}';
  }

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
        cuandoTexto: j['cuando_texto'] as String?,
        acompanantes: [
          for (final n in (j['acompanantes'] as List?) ?? const []) '$n',
        ],
        musica: (j['musica'] as String?) ?? '',
        estado: EstadoDeLaCarga.deClave(j['estado']),
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

  /// Ya entraron todos los delegados que se esperaban. **Cuenta personas, no
  /// celulares**: quien ya entró sigue pudiendo entrar con su nombre.
  final bool lleno;

  /// En la entrada: los delegados que ya entraron, para que quien vuelve desde
  /// otro celular toque su nombre.
  final List<String> delegados;
  final String yoNombre;

  /// Ya envió alguna vez. **No cierra nada**: es solo para decírselo.
  final bool yoEntregado;

  /// "jue 19/11 21:40": cuándo fue su último envío.
  final String? yoEnvioTexto;

  /// Cuántos alumnos suyos tiene guardados sin enviar.
  final int yoSinEnviar;
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
    this.delegados = const [],
    this.yoNombre = '',
    this.yoEntregado = false,
    this.yoEnvioTexto,
    this.yoSinEnviar = 0,
    this.total = 0,
    this.cargados = 0,
    this.faltan = 0,
    this.mios = 0,
    this.alumnos = const [],
  });

  /// Adentro, pero ya no se puede cargar ni enviar: **solo por la fecha
  /// límite**. Haber enviado no cierra nada.
  bool get soloLectura => vencido;

  factory ListaDelDelegado.fromJson(Map<String, dynamic> j) {
    final yo = (j['yo'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ListaDelDelegado(
      ok: j['ok'] == true,
      motivo: j['motivo'] as String?,
      fiesta: (j['fiesta'] as String?) ?? '',
      venceTexto: (j['vence_texto'] as String?) ?? '',
      vencido: j['vencido'] == true,
      lleno: j['lleno'] == true,
      delegados: [
        for (final d in (j['delegados'] as List?) ?? const [])
          if (d is Map && '${d['nombre'] ?? ''}'.trim().isNotEmpty)
            '${d['nombre']}',
      ],
      yoNombre: (yo['nombre'] as String?) ?? '',
      yoEntregado: yo['entregado'] == true,
      yoEnvioTexto: yo['envio_texto'] as String?,
      yoSinEnviar: (yo['sin_enviar'] as num?)?.toInt() ?? 0,
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

  /// Quién lo cargó (lo mandaba la versión anterior con `otro`).
  final String? cargo;

  /// Al guardar vacíos los dos casilleros: se sacó lo cargado por el link.
  final bool libre;

  /// Al enviar sin nada nuevo: ya estaba todo enviado.
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
