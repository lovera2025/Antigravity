// Una nube de mentira para el link del delegado: hace lo que hacen las
// funciones del SQL, lo justo para probar las pantallas. **Las reglas de
// verdad se prueban contra el SQL** (`tool/delegado_sandbox/pruebas.mjs`).
//
// Desde la 6.9.2 (`20261118120000_link_delegado_reabrir.sql`): el delegado es
// la persona (su nombre), todos corrigen todo, Enviar no cierra y queda el
// historial.
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
  final String entro;

  /// Cuándo fue el último envío de esta persona. Null: no envió.
  String? envio;
  bool sacado = false;
  _Celular(this.id, this.sesion, this.nombre, this.entro);
}

class _Carga {
  String? celularId;
  List<String> acompanantes;
  String musica;
  String cuando;
  bool traido = false;
  bool enviado = false;
  _Carga(this.celularId, this.acompanantes, this.musica, this.cuando);
}

/// Sin acentos ni mayúsculas: lo que hace de "la persona".
String _llave(String nombre) {
  const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const sin = 'aaaaaeeeeiiiiooooouuuun';
  final b = StringBuffer();
  for (final c in nombre.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase().split('')) {
    final i = con.indexOf(c);
    b.write(i < 0 ? c : sin[i]);
  }
  return b.toString();
}

/// La nube en memoria, de los dos lados: la página y el programa.
class DelegadoEnMemoria implements NubeDelDelegado, LinkDelDelegado {
  final String eventoId;
  final List<AlumnoDeMentira> alumnosDeLaFiesta;

  String? clave;
  String fiesta = '';
  String venceTexto = 'jueves 19/11 a las 20:00';
  String venceLocal = '2026-11-19 20:00';
  int cupo = 1;
  bool apagado = false;
  bool vencido = false;

  /// "Ahora", como lo dice la nube al anotar cuándo pasó algo. La prueba lo
  /// cambia para ver quién hizo qué y cuándo.
  String reloj = 'jue 12/11 15:00';

  /// Hay algo enviado (o vencido) que todavía no se trajo.
  bool hayAviso = false;

  /// La nube no contesta.
  bool sinRed = false;

  final _celulares = <_Celular>[];
  final _cargas = <String, _Carga>{};
  final _cambios = <CambioDelHistorial>[];

  /// Lo que se pidió, en orden: para comprobar qué se le avisó a la nube.
  final pedidos = <String>[];

  DelegadoEnMemoria({
    required this.eventoId,
    required List<AlumnoDeMentira> alumnos,
  }) : alumnosDeLaFiesta = alumnos;

  void _red() {
    if (sinRed) throw Exception('sin red');
  }

  _Celular? _de(String? sesion) =>
      _celulares.where((c) => c.sesion == sesion).firstOrNull;

  _Celular? _celular(String? id) =>
      _celulares.where((c) => c.id == id).firstOrNull;

  Iterable<_Celular> _deLaPersona(String nombre) =>
      _celulares.where((c) => _llave(c.nombre) == _llave(nombre));

  /// Los ids de los celulares de la misma persona que [celularId].
  Set<String> _aparatosDe(String? celularId) {
    final c = _celular(celularId);
    return c == null ? {} : {for (final x in _deLaPersona(c.nombre)) x.id};
  }

  /// Una persona por nombre, en el orden en que entraron.
  List<_Celular> get _personas {
    final vistas = <String>{};
    return [
      for (final c in _celulares)
        if (vistas.add(_llave(c.nombre))) c,
    ];
  }

  Iterable<AlumnoDeMentira> get _activos =>
      alumnosDeLaFiesta.where((a) => a.activo);

  bool _enPrograma(AlumnoDeMentira a) =>
      a.acompanantes.isNotEmpty && a.musica.isNotEmpty;

  EstadoDeLaCarga _estadoDe(AlumnoDeMentira a) {
    final g = _cargas[a.id];
    if (g == null) {
      return _enPrograma(a) ? EstadoDeLaCarga.programa : EstadoDeLaCarga.falta;
    }
    if (g.traido) return EstadoDeLaCarga.aceptado;
    return g.enviado ? EstadoDeLaCarga.enviado : EstadoDeLaCarga.sinEnviar;
  }

  List<String> _acompanantesVigentes(AlumnoDeMentira a) {
    final g = _cargas[a.id];
    return g != null && g.acompanantes.isNotEmpty ? g.acompanantes : a.acompanantes;
  }

  String _musicaVigente(AlumnoDeMentira a) {
    final g = _cargas[a.id];
    return g != null && g.musica.isNotEmpty ? g.musica : a.musica;
  }

  void _anotar(String alumnoId, String quien, String que, [_Carga? g]) =>
      _cambios.add(CambioDelHistorial(
        alumnoId: alumnoId,
        quien: quien,
        que: que,
        cuandoTexto: reloj,
        acompanantes: g?.acompanantes ?? const [],
        musica: g?.musica ?? '',
      ));

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
      final activas = _personas.where((c) => !c.sacado).toList();
      return ListaDelDelegado(
        ok: false,
        motivo: 'entrar',
        fiesta: fiesta,
        venceTexto: venceTexto,
        vencido: vencido,
        lleno: activas.length >= cupo,
        delegados: [for (final c in activas) c.nombre],
      );
    }
    if (yo.sacado) {
      return ListaDelDelegado(ok: false, motivo: 'sacado', fiesta: fiesta);
    }
    final mios = _aparatosDe(yo.id);
    final lista = <AlumnoDelLink>[];
    var sinEnviar = 0;
    for (final a in _activos) {
      final g = _cargas[a.id];
      final estado = _estadoDe(a);
      final esMio = g != null && mios.contains(g.celularId);
      if (esMio && estado == EstadoDeLaCarga.sinEnviar) sinEnviar++;
      lista.add(AlumnoDelLink(
        id: a.id,
        nombre: a.nombre,
        division: a.division,
        progAcomp: a.acompanantes.isNotEmpty,
        progMusica: a.musica.isNotEmpty,
        de: g == null
            ? (_enPrograma(a) ? DeQuien.programa : DeQuien.libre)
            : g.celularId == null
                ? DeQuien.suelto
                : esMio
                    ? DeQuien.mio
                    : DeQuien.otro,
        cargo: _celular(g?.celularId)?.nombre,
        cuandoTexto: g?.cuando,
        acompanantes: _acompanantesVigentes(a),
        musica: _musicaVigente(a),
        estado: estado,
      ));
    }
    final cargados = lista.where((a) => a.cargado).length;
    return ListaDelDelegado(
      ok: true,
      fiesta: fiesta,
      venceTexto: venceTexto,
      vencido: vencido,
      yoNombre: yo.nombre,
      yoEntregado: yo.envio != null,
      yoEnvioTexto: yo.envio,
      yoSinEnviar: sinEnviar,
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
    var limpio = nombre.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    if (limpio.length < 5 || !limpio.contains(' ')) return no('nombre');
    final suyos = _deLaPersona(limpio).toList();
    String? envio;
    if (suyos.isNotEmpty) {
      // El mismo nombre desde otro celular: es la misma persona.
      if (suyos.any((c) => c.sacado)) return no('sacado');
      limpio = suyos.first.nombre;
      envio = suyos.first.envio;
    } else if (_personas.where((c) => !c.sacado).length >= cupo) {
      return no('lleno');
    }
    final n = _celulares.length + 1;
    _celulares.add(_Celular('celular-$n', 'sesion-$n', limpio, reloj)..envio = envio);
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
    RespuestaDelegado no(String m, {String? campo}) =>
        RespuestaDelegado(ok: false, motivo: m, campo: campo);
    if (this.clave == null || clave != this.clave) return no('link');
    if (apagado) return no('apagado');
    if (vencido) return no('vencido');
    final yo = _de(sesion);
    if (yo == null) return no('sesion');
    if (yo.sacado) return no('sacado');
    final a = _activos.where((x) => x.id == alumnoId).firstOrNull;
    if (a == null) return no('alumno');
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
    // Todos corrigen todo: no importa quién lo cargó, si ya se envió ni si ya
    // está en el programa.
    if (nombres.isEmpty && tema.isEmpty) {
      if (_cargas.remove(alumnoId) == null) return no('vacio');
      _anotar(alumnoId, yo.nombre, 'vacio');
      return const RespuestaDelegado(ok: true, libre: true);
    }
    final g = _cargas[alumnoId] = _Carga(yo.id, nombres, tema, reloj);
    _anotar(alumnoId, yo.nombre, 'guardo', g);
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
    final mios = _aparatosDe(yo.id);
    final suyas = _cargas.values.where((g) => mios.contains(g.celularId)).toList();
    if (suyas.isEmpty) return no('nada');
    final nuevas = suyas.where((g) => !g.enviado).toList();
    // Sin nada nuevo no cambia nada: Enviar no cierra, y tampoco avisa de más.
    if (nuevas.isEmpty) return const RespuestaDelegado(ok: true, ya: true);
    for (final g in nuevas) {
      g.enviado = true;
    }
    for (final c in _deLaPersona(yo.nombre)) {
      c.envio = reloj;
    }
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
    int cuantos(EstadoDeLaCarga e) => activos.where((a) => _estadoDe(a) == e).length;
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
            entroTexto: c.entro,
            cargados: _cargas.values.where((g) => g.celularId == c.id).length,
            entregado: c.envio != null,
            entregadoTexto: c.envio,
            sacado: c.sacado,
          ),
      ],
      delegados: [
        for (final p in _personas)
          DelegadoDelLink(
            id: p.id,
            nombre: p.nombre,
            entroTexto: p.entro,
            aparatos: _deLaPersona(p.nombre).length,
            cargados: _cargas.values
                .where((g) => _aparatosDe(p.id).contains(g.celularId))
                .length,
            sinEnviar: _cargas.values
                .where((g) =>
                    _aparatosDe(p.id).contains(g.celularId) &&
                    !g.enviado &&
                    !g.traido)
                .length,
            envioTexto: p.envio,
            sacado: p.sacado,
          ),
      ],
      total: activos.length,
      enPrograma: cuantos(EstadoDeLaCarga.programa),
      cargados: activos
          .where((a) => !_enPrograma(a) && _cargas.containsKey(a.id))
          .length,
      faltan: cuantos(EstadoDeLaCarga.falta),
      sinEnviar: cuantos(EstadoDeLaCarga.sinEnviar),
      enviados: cuantos(EstadoDeLaCarga.enviado),
      aceptados: cuantos(EstadoDeLaCarga.aceptado),
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
    const deUnDelegado = {'reabrir', 'sacar_dejando', 'sacar_borrando', 'readmitir'};
    if (deUnDelegado.contains(accion) && _celular(valor) == null) {
      return const RespuestaDelegado(ok: false, motivo: 'celular');
    }
    final suyos = deUnDelegado.contains(accion)
        ? _deLaPersona(_celular(valor)!.nombre).toList()
        : const <_Celular>[];
    switch (accion) {
      case 'apagar':
        apagado = true;
      case 'prender':
        apagado = false;
      case 'vence':
        venceLocal = valor!;
        venceTexto = 'el nuevo límite';
        // Una fecha futura reabre: también un link cerrado a mano.
        if (valor.compareTo('2026-11-12 15:00') > 0) {
          apagado = false;
          vencido = false;
        } else {
          vencido = true;
        }
      case 'cupo':
        cupo = int.parse(valor!);
      case 'reabrir':
        for (final c in suyos) {
          c.envio = null;
        }
      case 'sacar_dejando':
        // Lo que cargó sigue diciendo que lo cargó esa persona.
        for (final c in suyos) {
          c.sacado = true;
        }
      case 'sacar_borrando':
        final ids = {for (final c in suyos) c.id};
        for (final c in suyos) {
          c.sacado = true;
        }
        for (final e in _cargas.entries.toList()) {
          if (!ids.contains(e.value.celularId)) continue;
          _anotar(e.key, 'Junior Eventos', 'borrado', e.value);
          _cargas.remove(e.key);
        }
      case 'readmitir':
        for (final c in suyos) {
          c.sacado = false;
        }
      case 'traido':
        for (final id in (jsonDecode(valor!) as List)) {
          final g = _cargas[id];
          if (g == null) continue;
          if (!g.traido) _anotar('$id', 'Junior Eventos', 'aceptado', g);
          g.traido = true;
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
      for (final a in alumnosDeLaFiesta)
        if (_cargas[a.id] case final g?)
          CargaDelDelegado(
            alumnoId: a.id,
            alumno: a.nombre,
            division: a.division,
            activo: a.activo,
            acompanantes: g.acompanantes,
            musica: g.musica,
            cargo: _celular(g.celularId)?.nombre,
            entregado: g.enviado,
            cuandoTexto: g.cuando,
            traido: g.traido,
          ),
    ];
  }

  @override
  Future<List<AlumnoDelTablero>> alumnos(String eventoId) async {
    _red();
    return [
      for (final a in _activos)
        AlumnoDelTablero(
          alumnoId: a.id,
          alumno: a.nombre,
          division: a.division,
          acompanantes: _acompanantesVigentes(a),
          musica: _musicaVigente(a),
          estado: _estadoDe(a),
          cargo: _celular(_cargas[a.id]?.celularId)?.nombre,
          delegadoId: switch (_celular(_cargas[a.id]?.celularId)) {
            final c? => _deLaPersona(c.nombre).first.id,
            null => null,
          },
          cuandoTexto: _cargas[a.id]?.cuando,
          otraVez: _cargas[a.id] != null &&
              !_cargas[a.id]!.traido &&
              (a.acompanantes.isNotEmpty || a.musica.isNotEmpty),
        ),
    ];
  }

  @override
  Future<List<CambioDelHistorial>> historial(String eventoId) async {
    _red();
    return List.of(_cambios);
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

  /// El jefe trae a la grilla lo de [alumnoIds] y queda en el programa, como
  /// hace ACEPTAR Y CARGAR.
  Future<void> aceptar(Iterable<String> alumnoIds) async {
    for (final id in alumnoIds) {
      final g = _cargas[id];
      final a = alumnosDeLaFiesta.firstWhere((x) => x.id == id);
      if (g == null) continue;
      if (g.acompanantes.isNotEmpty) a.acompanantes = List.of(g.acompanantes);
      if (g.musica.isNotEmpty) a.musica = g.musica;
    }
    await cambiar(eventoId, 'traido', jsonEncode(alumnoIds.toList()));
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
