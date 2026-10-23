import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// "Lista para trabajar sin internet" (sección 5 de la 6.0.0): la línea de
// Recepción que dice, antes de la fiesta, si esta PC tiene todo lo del evento;
// y, sin internet, con qué se está trabajando y cuántos ingresos esperan subir.
//
// Lo que decide está acá, sin pantalla ni base: qué dice la línea
// ([EstadoSinInternet.de]) y cuándo se pone al día el evento
// ([PuestaAlDiaPuerta]). La línea es `LineaSinInternet`.

/// Lo que Recepción sabe del evento en esta PC.
@immutable
class DatosSinInternet {
  final bool hayInternet;

  /// La última vez que esta PC bajó todo lo del evento: la lista de la puerta
  /// y, en un masivo, los alumnos, sus sillas y el plano. Null: nunca.
  final DateTime? alDia;

  /// Poniéndose al día ahora.
  final bool bajando;

  /// La última vez que intentó ponerse al día, no pudo.
  final bool fallo;

  /// Si la foto del tótem está guardada en la PC. Null: el evento no tiene
  /// foto.
  final bool? fotoGuardada;

  /// Si el fondo de "Tu fondo" está guardado en la PC. Null: el tótem no usa
  /// un fondo propio.
  final bool? fondoGuardado;

  /// Ingresos marcados en esta PC que todavía no subieron.
  final int sinSubir;

  const DatosSinInternet({
    required this.hayInternet,
    this.alDia,
    this.bajando = false,
    this.fallo = false,
    this.fotoGuardada,
    this.fondoGuardado,
    this.sinSubir = 0,
  });

  DatosSinInternet copyWith({
    bool? hayInternet,
    DateTime? alDia,
    bool? bajando,
    bool? fallo,
    bool? fotoGuardada,
    bool sinFoto = false,
    bool? fondoGuardado,
    bool sinFondo = false,
    int? sinSubir,
  }) =>
      DatosSinInternet(
        hayInternet: hayInternet ?? this.hayInternet,
        alDia: alDia ?? this.alDia,
        bajando: bajando ?? this.bajando,
        fallo: fallo ?? this.fallo,
        fotoGuardada: sinFoto ? null : (fotoGuardada ?? this.fotoGuardada),
        fondoGuardado:
            sinFondo ? null : (fondoGuardado ?? this.fondoGuardado),
        sinSubir: sinSubir ?? this.sinSubir,
      );
}

enum TipoSinInternet {
  /// Con internet y todo en la PC.
  lista,

  /// Con internet, pero falta algo (o se está bajando).
  falta,

  /// Sin internet: se trabaja con lo de la PC.
  sinInternet,

  /// Sin internet, y la PC no tiene la lista del evento.
  sinLista,
}

/// Lo que dice la línea, y el detalle que se ve al tocarla.
@immutable
class EstadoSinInternet {
  final TipoSinInternet tipo;
  final String texto;

  /// Personas, al día, foto, el fondo (si el tótem va con "Tu fondo") y sin
  /// subir.
  final List<(String, String)> detalle;

  const EstadoSinInternet(this.tipo, this.texto, this.detalle);

  /// Con internet, si la última puesta al día falló y es más vieja que esto,
  /// se dice.
  static const vencido = Duration(minutes: 15);

  static EstadoSinInternet de(
    DatosSinInternet d, {
    required int personas,
    required DateTime ahora,
  }) {
    final detalle = <(String, String)>[
      ('Personas en esta PC', personas == 0 ? 'ninguna' : miles(personas)),
      (
        'Al día',
        d.alDia != null
            ? _cuando(d.alDia!, ahora, hoy: true)
            : (d.bajando ? 'bajando…' : 'todavía no bajó'),
      ),
      (
        'Foto del tótem',
        switch (d.fotoGuardada) {
          null => 'el evento no tiene',
          true => 'guardada',
          false => d.hayInternet ? 'no bajó · se reintenta' : 'no está guardada',
        },
      ),
      // Solo si el tótem va con "Tu fondo": a los demás no les cambia nada.
      if (d.fondoGuardado != null)
        (
          'Fondo del tótem',
          d.fondoGuardado!
              ? 'guardado'
              : (d.hayInternet ? 'no bajó · se reintenta' : 'no está guardado'),
        ),
      (
        'Ingresos sin subir',
        d.sinSubir == 0
            ? 'ninguno'
            : '${miles(d.sinSubir)}, '
                '${d.hayInternet ? 'subiendo' : 'se suben solos al volver'}',
      ),
    ];
    EstadoSinInternet es(TipoSinInternet t, String texto) =>
        EstadoSinInternet(t, texto, detalle);

    if (!d.hayInternet) {
      if (personas == 0) {
        return es(
          TipoSinInternet.sinLista,
          'Sin internet, y esta PC no tiene la lista de este evento: '
          'conectala un momento a internet.',
        );
      }
      final partes = [
        'Sin internet',
        d.alDia == null
            ? 'se sigue con lo de esta PC'
            : 'se sigue con lo de esta PC (al día ${_cuando(d.alDia!, ahora)})',
        if (d.sinSubir > 0)
          '${d.sinSubir == 1 ? '1 ingreso' : '${miles(d.sinSubir)} ingresos'} '
              'sin subir: se suben solos al volver',
      ];
      return es(TipoSinInternet.sinInternet, partes.join(' · '));
    }

    const falta = 'Todavía no está lista para trabajar sin internet';
    final alDia = d.alDia;
    if (alDia == null) {
      if (d.fallo && !d.bajando) {
        return es(TipoSinInternet.falta,
            '$falta: no se pudo bajar la lista. Se vuelve a intentar sola.');
      }
      return es(TipoSinInternet.falta, 'Poniéndose al día para trabajar sin internet…');
    }
    if (d.fallo && ahora.difference(alDia) > vencido) {
      return es(
        TipoSinInternet.falta,
        'No se pudo poner al día la lista desde las ${_hora(alDia)}. '
        'Se vuelve a intentar sola.',
      );
    }
    if (personas == 0) {
      return es(TipoSinInternet.falta, 'La lista de este evento está vacía.');
    }
    if (d.fotoGuardada == false) {
      return es(TipoSinInternet.falta, '$falta: falta guardar la foto del tótem.');
    }
    if (d.fondoGuardado == false) {
      return es(TipoSinInternet.falta, '$falta: falta guardar el fondo del tótem.');
    }
    return es(
      TipoSinInternet.lista,
      'Lista para trabajar sin internet · al día ${_cuando(alDia, ahora)}',
    );
  }

  static String _hora(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  /// "21:40", "ayer 21:40" o "12/12 21:40"; con [hoy], "hoy 21:40".
  static String _cuando(DateTime t, DateTime ahora, {bool hoy = false}) {
    final l = t.toLocal(), a = ahora.toLocal();
    final dia = DateTime(l.year, l.month, l.day);
    final hoyDia = DateTime(a.year, a.month, a.day);
    final dias = hoyDia.difference(dia).inDays;
    if (dias == 0) return hoy ? 'hoy ${_hora(l)}' : _hora(l);
    if (dias == 1) return 'ayer ${_hora(l)}';
    return '${l.day}/${l.month} ${_hora(l)}';
  }

  /// 1100 → "1.100".
  static String miles(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// Con qué se pone al día un evento. La app usa los de la base, la nube y la
/// carpeta de fotos de la PC (`accesosPuertaProvider`); los tests, unos en
/// memoria.
class AccesosPuerta {
  /// La lista de la puerta del evento, entera. Si bajó bien.
  final Future<bool> Function(String eventoId) bajarLista;

  /// En un masivo: el evento, los alumnos, sus sillas y el plano. Si bajaron.
  final Future<bool> Function() bajarAlumnos;

  /// Baja la foto si falta. Si quedó en la PC.
  final Future<bool> Function(String url, String eventoId) guardarFoto;

  /// Si la foto ya está en la PC, sin bajar nada.
  final Future<bool> Function(String url, String eventoId) fotoGuardada;

  /// Lo mismo con el fondo de "Tu fondo", que va en su propia carpeta.
  final Future<bool> Function(String url, String eventoId) guardarFondo;
  final Future<bool> Function(String url, String eventoId) fondoGuardado;

  final Future<int> Function(String eventoId) contarSinSubir;
  final Future<DateTime?> Function(String eventoId) leerAlDia;
  final Future<void> Function(String eventoId, DateTime cuando) anotarAlDia;
  final DateTime Function() ahora;

  const AccesosPuerta({
    required this.bajarLista,
    required this.bajarAlumnos,
    required this.guardarFoto,
    required this.fotoGuardada,
    required this.guardarFondo,
    required this.fondoGuardado,
    required this.contarSinSubir,
    this.leerAlDia = AlDiaDeLaPuerta.leer,
    this.anotarAlDia = AlDiaDeLaPuerta.anotar,
    this.ahora = DateTime.now,
  });
}

/// Cuándo se puso al día por última vez cada evento en esta PC. Se guarda,
/// así se sabe también al abrir el programa sin internet.
class AlDiaDeLaPuerta {
  AlDiaDeLaPuerta._();

  static String _clave(String eventoId) => 'puerta_al_dia_v1_$eventoId';

  static Future<DateTime?> leer(String eventoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(_clave(eventoId));
      return crudo == null ? null : DateTime.tryParse(crudo);
    } catch (e) {
      debugPrint('No se pudo leer cuándo se puso al día la puerta: $e');
      return null;
    }
  }

  static Future<void> anotar(String eventoId, DateTime cuando) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave(eventoId), cuando.toUtc().toIso8601String());
    } catch (e) {
      debugPrint('No se pudo anotar cuándo se puso al día la puerta: $e');
    }
  }
}

/// Pone al día un evento en esta PC y cuenta lo que espera subir.
///
/// - Con internet: al abrir el evento, cada [cada] y cuando vuelve internet,
///   baja la lista de la puerta entera y, en un masivo, los alumnos, sus
///   sillas y el plano; y guarda la foto del tótem. Si todo bajó, anota la
///   hora ([AccesosPuerta.anotarAlDia]).
/// - Sin internet no intenta nada: dice con qué hora quedó.
/// - Cada [cadaCuenta], cuántos ingresos esperan subir.
class PuestaAlDiaPuerta extends ChangeNotifier {
  PuestaAlDiaPuerta({
    required this.eventoId,
    required this.accesos,
    required bool hayInternet,
    this.cada = const Duration(minutes: 5),
    this.cadaCuenta = const Duration(seconds: 10),
  }) : _datos = DatosSinInternet(hayInternet: hayInternet);

  final String eventoId;
  final AccesosPuerta accesos;
  final Duration cada;
  final Duration cadaCuenta;

  DatosSinInternet _datos;
  DatosSinInternet get datos => _datos;

  bool _masivo = false;
  String? _fotoUrl;
  String? _fondoUrl;
  bool _arrancada = false;
  bool _cerrada = false;
  Future<void>? _enCurso;
  Timer? _timer;
  Timer? _timerCuenta;

  void _poner(DatosSinInternet d) {
    _datos = d;
    if (!_cerrada) notifyListeners();
  }

  /// Empieza: lee la hora guardada, cuenta, y si hay internet se pone al día.
  Future<void> arrancar() async {
    if (_arrancada) return;
    _arrancada = true;
    final alDia = await accesos.leerAlDia(eventoId);
    if (_cerrada) return;
    if (alDia != null) _poner(_datos.copyWith(alDia: alDia));
    _timer = Timer.periodic(cada, (_) {
      if (_datos.hayInternet) unawaited(ponerAlDia());
    });
    _timerCuenta = Timer.periodic(cadaCuenta, (_) => unawaited(recontar()));
    await Future.wait([
      recontar(),
      if (_datos.hayInternet) ponerAlDia() else ...[_mirarFoto(), _mirarFondo()],
    ]);
  }

  /// Se cortó o volvió internet.
  void conexion(bool hay) {
    if (hay == _datos.hayInternet) return;
    _poner(_datos.copyWith(hayInternet: hay));
    if (hay && _arrancada) unawaited(ponerAlDia());
  }

  /// Si el evento es masivo. Si pasa a serlo con internet, se baja lo suyo,
  /// después de la puesta al día que esté en curso.
  set masivo(bool m) {
    if (m == _masivo) return;
    _masivo = m;
    if (m && _arrancada && _datos.hayInternet) {
      unawaited((_enCurso ?? Future<void>.value()).then((_) => ponerAlDia()));
    }
  }

  /// La foto del tótem del evento. Si cambia, se guarda la nueva.
  set fotoUrl(String? url) {
    if (url == _fotoUrl) return;
    _fotoUrl = url;
    if (!_arrancada) return;
    unawaited(_datos.hayInternet ? _guardarFoto() : _mirarFoto());
  }

  /// El fondo de "Tu fondo", si el tótem lo usa (null: no). Si cambia, se
  /// guarda el nuevo.
  set fondoUrl(String? url) {
    if (url == _fondoUrl) return;
    _fondoUrl = url;
    if (!_arrancada) return;
    unawaited(_datos.hayInternet ? _guardarFondo() : _mirarFondo());
  }

  /// Baja todo lo del evento. Si ya está bajando, espera a esa.
  Future<void> ponerAlDia() => _enCurso ??= _ponerAlDia().whenComplete(() {
        _enCurso = null;
      });

  Future<void> _ponerAlDia() async {
    if (_cerrada || !_datos.hayInternet) return;
    _poner(_datos.copyWith(bajando: true));
    var bien = false;
    try {
      final resultados = await Future.wait([
        accesos.bajarLista(eventoId),
        if (_masivo) accesos.bajarAlumnos(),
        _guardarFoto(),
        _guardarFondo(),
      ]);
      bien = resultados.every((r) => r != false);
    } catch (e) {
      debugPrint('Recepción no pudo ponerse al día: $e');
    }
    if (_cerrada) return;
    final cuando = accesos.ahora();
    if (bien) await accesos.anotarAlDia(eventoId, cuando);
    if (_cerrada) return;
    _poner(_datos.copyWith(
      bajando: false,
      fallo: !bien,
      alDia: bien ? cuando : null,
    ));
    await recontar();
  }

  /// Devuelve null: la foto no cuenta para "todo bajó" (falta se dice aparte).
  Future<bool?> _guardarFoto() async {
    final url = _fotoUrl;
    if (url == null) {
      _poner(_datos.copyWith(sinFoto: true));
      return null;
    }
    final ok = await accesos.guardarFoto(url, eventoId);
    if (!_cerrada && url == _fotoUrl) {
      _poner(_datos.copyWith(fotoGuardada: ok));
    }
    return null;
  }

  Future<void> _mirarFoto() async {
    final url = _fotoUrl;
    if (url == null) {
      _poner(_datos.copyWith(sinFoto: true));
      return;
    }
    final ok = await accesos.fotoGuardada(url, eventoId);
    if (!_cerrada && url == _fotoUrl) {
      _poner(_datos.copyWith(fotoGuardada: ok));
    }
  }

  /// Como [_guardarFoto]: el fondo tampoco cuenta para "todo bajó".
  Future<bool?> _guardarFondo() async {
    final url = _fondoUrl;
    if (url == null) {
      _poner(_datos.copyWith(sinFondo: true));
      return null;
    }
    final ok = await accesos.guardarFondo(url, eventoId);
    if (!_cerrada && url == _fondoUrl) {
      _poner(_datos.copyWith(fondoGuardado: ok));
    }
    return null;
  }

  Future<void> _mirarFondo() async {
    final url = _fondoUrl;
    if (url == null) {
      _poner(_datos.copyWith(sinFondo: true));
      return;
    }
    final ok = await accesos.fondoGuardado(url, eventoId);
    if (!_cerrada && url == _fondoUrl) {
      _poner(_datos.copyWith(fondoGuardado: ok));
    }
  }

  /// Cuántos ingresos esperan subir.
  Future<void> recontar() async {
    try {
      final n = await accesos.contarSinSubir(eventoId);
      if (!_cerrada && n != _datos.sinSubir) {
        _poner(_datos.copyWith(sinSubir: n));
      }
    } catch (e) {
      debugPrint('No se pudo contar lo que espera subir: $e');
    }
  }

  @override
  void dispose() {
    _cerrada = true;
    _timer?.cancel();
    _timerCuenta?.cancel();
    super.dispose();
  }
}
