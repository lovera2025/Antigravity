// Una nube de mentira para el link del delegado: hace lo que hacen las
// funciones del SQL, lo justo para probar las pantallas. **Las reglas de
// verdad se prueban contra el SQL** (`tool/delegado_sandbox/pruebas.mjs`).
import 'dart:convert';

import 'package:arguello_events/features/delegado/datos/link_del_delegado.dart';
import 'package:arguello_events/features/delegado/datos/nube_del_delegado.dart';

class AlumnoDeMentira {
  final String id;
  final String nombre;
  final String division;
  List<String> acompanantes;
  String musica;
  bool activo;

  AlumnoDeMentira(
    this.id,
    this.nombre,
    this.division, {
    List<String>? acompanantes,
    this.musica = '',
    this.activo = true,
  }) : acompanantes = acompanantes ?? [];
}

class _Celular {
  final String id;
  final String sesion;
  final String nombre;
  bool entregado = false;
  bool sacado = false;
  _Celular(this.id, this.sesion, this.nombre);
}

class _Carga {
  String? celularId;
  List<String> acompanantes;
  String musica;
  bool traido = false;
  _Carga(this.celularId, this.acompanantes, this.musica);
}

/// La nube en memoria, de los dos lados: la página y el programa.
class DelegadoEnMemoria implements NubeDelDelegado, LinkDelDelegado {
  final String eventoId;
  final List<AlumnoDeMentira> alumnos;

  String? clave;
  String fiesta = '';
  String venceTexto = 'jueves 19/11 a las 20:00';
  String venceLocal = '2026-11-19 20:00';
  int cupo = 1;
  bool apagado = false;
  bool vencido = false;

  /// Hay algo enviado (o vencido) que todavía no se trajo.
  bool hayAviso = false;

  /// La nube no contesta.
  bool sinRed = false;

  final _celulares = <_Celular>[];
  final _cargas = <String, _Carga>{};

  /// Lo que se pidió, en orden: para comprobar qué se le avisó a la nube.
  final pedidos = <String>[];

  DelegadoEnMemoria({required this.eventoId, required this.alumnos});

  void _red() {
    if (sinRed) throw Exception('sin red');
  }

  _Celular? _de(String? sesion) =>
      _celulares.where((c) => c.sesion == sesion).firstOrNull;

  Iterable<AlumnoDeMentira> get _activos => alumnos.where((a) => a.activo);

  bool _enPrograma(AlumnoDeMentira a) =>
      a.acompanantes.isNotEmpty && a.musica.isNotEmpty;

  // ── La página ─────────────────────────────────────────────────────────────

  @override
  Future<ListaDelDelegado> lista(String clave, String? sesion) async {
    _red();
    if (this.clave == null || clave != this.clave) {
      return const ListaDelDelegado(ok: false, motivo: 'link');
    }
    if (apagado) {
      return ListaDelDelegado(ok: false, motivo: 'apagado', fiesta: fiesta);
    }
    final yo = _de(sesion);
    if (yo == null) {
      return ListaDelDelegado(
        ok: false,
        motivo: 'entrar',
        fiesta: fiesta,
        venceTexto: venceTexto,
        vencido: vencido,
        lleno: _celulares.where((c) => !c.sacado).length >= cupo,
      );
    }
    if (yo.sacado) {
      return ListaDelDelegado(ok: false, motivo: 'sacado', fiesta: fiesta);
    }
    final lista = <AlumnoDelLink>[];
    for (final a in _activos) {
      final g = _cargas[a.id];
      final de = _enPrograma(a)
          ? DeQuien.programa
          : g == null
              ? DeQuien.libre
              : g.celularId == null
                  ? DeQuien.suelto
                  : g.celularId == yo.id
                      ? DeQuien.mio
                      : DeQuien.otro;
      final veLoCargado = de == DeQuien.mio || de == DeQuien.suelto;
      lista.add(AlumnoDelLink(
        id: a.id,
        nombre: a.nombre,
        division: a.division,
        progAcomp: a.acompanantes.isNotEmpty,
        progMusica: a.musica.isNotEmpty,
        de: de,
        cargo: de == DeQuien.otro
            ? _celulares.firstWhere((c) => c.id == g!.celularId).nombre
            : null,
        acompanantes: veLoCargado ? g!.acompanantes : const [],
        musica: veLoCargado ? g!.musica : '',
      ));
    }
    final cargados =
        lista.where((a) => a.de != DeQuien.libre).length;
    return ListaDelDelegado(
      ok: true,
      fiesta: fiesta,
      venceTexto: venceTexto,
      vencido: vencido,
      yoNombre: yo.nombre,
      yoEntregado: yo.entregado,
      total: lista.length,
      cargados: cargados,
      faltan: lista.length - cargados,
      mios: lista.where((a) => a.de == DeQuien.mio).length,
      alumnos: lista,
    );
  }

  @override
  Future<RespuestaDelegado> entrar(String clave, String nombre) async {
    _red();
    RespuestaDelegado no(String m) => RespuestaDelegado(ok: false, motivo: m);
    if (this.clave == null || clave != this.clave) return no('link');
    if (apagado) return no('apagado');
    if (vencido) return no('vencido');
    final limpio = nombre.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    if (limpio.length < 5 || !limpio.contains(' ')) return no('nombre');
    if (_celulares.where((c) => !c.sacado).length >= cupo) return no('lleno');
    final n = _celulares.length + 1;
    _celulares.add(_Celular('celular-$n', 'sesion-$n', limpio));
    return RespuestaDelegado(ok: true, sesion: 'sesion-$n');
  }

  @override
  Future<RespuestaDelegado> guardar({
    required String clave,
    required String sesion,
    required String alumnoId,
    required List<String> acompanantes,
    required String musica,
  }) async {
    _red();
    RespuestaDelegado no(String m, {String? campo, String? cargo}) =>
        RespuestaDelegado(ok: false, motivo: m, campo: campo, cargo: cargo);
    if (this.clave == null || clave != this.clave) return no('link');
    if (apagado) return no('apagado');
    if (vencido) return no('vencido');
    final yo = _de(sesion);
    if (yo == null) return no('sesion');
    if (yo.sacado) return no('sacado');
    if (yo.entregado) return no('entregado');
    final a = _activos.where((x) => x.id == alumnoId).firstOrNull;
    if (a == null) return no('alumno');
    if (_enPrograma(a)) return no('ya_cargado');
    final nombres = [
      for (final n in acompanantes)
        if (n.trim().isNotEmpty) n.trim(),
    ];
    final tema = musica.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (nombres.length > 2) return no('tope');
    if (nombres.any((n) => n.length > kMaxLetrasAcompananteDelegado)) {
      return no('largo', campo: 'acompanantes');
    }
    if (tema.length > kMaxLetrasMusicaDelegado) {
      return no('largo', campo: 'musica');
    }
    if (a.acompanantes.isNotEmpty && nombres.isNotEmpty) {
      return no('ya_cargado', campo: 'acompanantes');
    }
    if (a.musica.isNotEmpty && tema.isNotEmpty) {
      return no('ya_cargado', campo: 'musica');
    }
    final g = _cargas[alumnoId];
    if (g != null && g.celularId != null && g.celularId != yo.id) {
      return no(
        'otro',
        cargo: _celulares.firstWhere((c) => c.id == g.celularId).nombre,
      );
    }
    if (nombres.isEmpty && tema.isEmpty) {
      if (g == null) return no('vacio');
      _cargas.remove(alumnoId);
      return const RespuestaDelegado(ok: true, libre: true);
    }
    _cargas[alumnoId] = _Carga(yo.id, nombres, tema);
    return const RespuestaDelegado(ok: true);
  }

  @override
  Future<RespuestaDelegado> entregar(String clave, String sesion) async {
    _red();
    RespuestaDelegado no(String m) => RespuestaDelegado(ok: false, motivo: m);
    if (this.clave == null || clave != this.clave) return no('link');
    if (apagado) return no('apagado');
    if (vencido) return no('vencido');
    final yo = _de(sesion);
    if (yo == null) return no('sesion');
    if (yo.sacado) return no('sacado');
    if (yo.entregado) return const RespuestaDelegado(ok: true, ya: true);
    if (!_cargas.values.any((g) => g.celularId == yo.id)) return no('nada');
    yo.entregado = true;
    hayAviso = true;
    return const RespuestaDelegado(ok: true);
  }

  // ── El programa ───────────────────────────────────────────────────────────

  @override
  Future<EstadoDelLink> estado(String eventoId) async {
    _red();
    if (clave == null || eventoId != this.eventoId) {
      return const EstadoDelLink.sinLink();
    }
    final activos = _activos.toList();
    final enPrograma = activos.where(_enPrograma).length;
    final cargados = activos
        .where((a) => !_enPrograma(a) && _cargas.containsKey(a.id))
        .length;
    return EstadoDelLink(
      hay: true,
      clave: clave!,
      venceTexto: venceTexto,
      venceLocal: venceLocal,
      estado: apagado
          ? EstadoLink.apagado
          : vencido
              ? EstadoLink.vencido
              : EstadoLink.abierto,
      cupo: cupo,
      celulares: [
        for (final c in _celulares)
          CelularDelLink(
            id: c.id,
            nombre: c.nombre,
            entroTexto: 'jueves 12/11 a las 21:00',
            cargados: _cargas.values.where((g) => g.celularId == c.id).length,
            entregado: c.entregado,
            entregadoTexto: c.entregado ? 'jueves 12/11 a las 21:30' : null,
            sacado: c.sacado,
          ),
      ],
      total: activos.length,
      enPrograma: enPrograma,
      cargados: cargados,
      faltan: activos.length - enPrograma - cargados,
      aviso: hayAviso ? 'Acompañantes y música para traer: $fiesta' : null,
    );
  }

  @override
  Future<RespuestaDelegado> crear({
    required String eventoId,
    required String fiesta,
    required String venceLocal,
    required int cupo,
  }) async {
    _red();
    pedidos.add('crear|$fiesta|$venceLocal|$cupo');
    if (clave != null) {
      return const RespuestaDelegado(ok: false, motivo: 'ya_existe');
    }
    if (venceLocal.compareTo('2026-11-12 15:00') <= 0) {
      return const RespuestaDelegado(ok: false, motivo: 'pasada');
    }
    clave = 'c1a2b3';
    this.fiesta = fiesta;
    this.venceLocal = venceLocal;
    this.cupo = cupo;
    return RespuestaDelegado(ok: true, clave: clave);
  }

  @override
  Future<RespuestaDelegado> cambiar(
    String eventoId,
    String accion, [
    String? valor,
  ]) async {
    _red();
    pedidos.add('$accion|${valor ?? ''}');
    switch (accion) {
      case 'apagar':
        apagado = true;
      case 'prender':
        apagado = false;
      case 'vence':
        venceLocal = valor!;
        venceTexto = 'el nuevo límite';
      case 'cupo':
        cupo = int.parse(valor!);
      case 'reabrir':
        _celulares.firstWhere((c) => c.id == valor).entregado = false;
      case 'sacar_dejando':
        _celulares.firstWhere((c) => c.id == valor).sacado = true;
        for (final g in _cargas.values) {
          if (g.celularId == valor) g.celularId = null;
        }
      case 'sacar_borrando':
        _celulares.firstWhere((c) => c.id == valor).sacado = true;
        _cargas.removeWhere((_, g) => g.celularId == valor);
      case 'traido':
        for (final id in (jsonDecode(valor!) as List)) {
          _cargas[id]?.traido = true;
        }
        hayAviso = false;
      default:
        return const RespuestaDelegado(ok: false, motivo: 'accion');
    }
    return const RespuestaDelegado(ok: true);
  }

  @override
  Future<List<CargaDelDelegado>> cargas(String eventoId) async {
    _red();
    return [
      for (final a in alumnos)
        if (_cargas[a.id] case final g?)
          CargaDelDelegado(
            alumnoId: a.id,
            alumno: a.nombre,
            division: a.division,
            activo: a.activo,
            acompanantes: g.acompanantes,
            musica: g.musica,
            cargo: g.celularId == null
                ? null
                : _celulares.firstWhere((c) => c.id == g.celularId).nombre,
            entregado: g.celularId != null &&
                _celulares.firstWhere((c) => c.id == g.celularId).entregado,
          ),
    ];
  }

  @override
  Future<List<AvisoDelDelegado>> pendientes() async {
    _red();
    final texto = (await estado(eventoId)).aviso;
    return [
      if (texto != null) AvisoDelDelegado(eventoId: eventoId, texto: texto),
    ];
  }

  // ── Atajos para armar un caso ─────────────────────────────────────────────

  /// Crea el link y deja entrar a [nombre]. Devuelve su sesión.
  Future<String> conDelegado(String nombre, {int cupo = 3}) async {
    if (clave == null) {
      await crear(
        eventoId: eventoId,
        fiesta: 'Escuela Normal · Promo 2026',
        venceLocal: '2026-11-19 20:00',
        cupo: cupo,
      );
    }
    return (await entrar(clave!, nombre)).sesion!;
  }

  /// Lo que la nube tiene cargado para [alumnoId], y si ya se trajo.
  ({List<String> acompanantes, String musica, bool traido})? cargaDe(
    String alumnoId,
  ) {
    final g = _cargas[alumnoId];
    return g == null
        ? null
        : (acompanantes: g.acompanantes, musica: g.musica, traido: g.traido);
  }
}
