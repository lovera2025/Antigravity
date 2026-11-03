import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../recepcion/services/lista_sin_internet.dart';

export '../../recepcion/services/lista_sin_internet.dart' show TipoSinInternet;

// "Lista para trabajar sin internet" de la barra: la línea de la pantalla de la cajera
// que dice si este equipo tiene lo que hace falta para vender sin internet (las fiestas,
// los PIN, el catálogo y los precios), y cuántas ventas esperan subir.
//
// Es la de la puerta (`recepcion/services/lista_sin_internet.dart`), más chica: no hay
// foto ni fondo, y lo que se baja es lo mismo para todas las fiestas.

/// Lo que la barra sabe de este equipo.
@immutable
class DatosSinInternetBarra {
  final bool hayInternet;

  /// La última vez que este equipo bajó todo lo de la barra. Null: nunca.
  final DateTime? alDia;
  final bool bajando;

  /// La última vez que intentó ponerse al día, no pudo.
  final bool fallo;

  /// Cuántas fiestas tienen precios en este equipo.
  final int fiestas;

  /// Ventas hechas en este equipo que todavía no subieron.
  final int sinSubir;

  const DatosSinInternetBarra({
    required this.hayInternet,
    this.alDia,
    this.bajando = false,
    this.fallo = false,
    this.fiestas = 0,
    this.sinSubir = 0,
  });

  DatosSinInternetBarra copyWith({
    bool? hayInternet,
    DateTime? alDia,
    bool? bajando,
    bool? fallo,
    int? fiestas,
    int? sinSubir,
  }) =>
      DatosSinInternetBarra(
        hayInternet: hayInternet ?? this.hayInternet,
        alDia: alDia ?? this.alDia,
        bajando: bajando ?? this.bajando,
        fallo: fallo ?? this.fallo,
        fiestas: fiestas ?? this.fiestas,
        sinSubir: sinSubir ?? this.sinSubir,
      );
}

/// Lo que dice la línea.
@immutable
class EstadoSinInternetBarra {
  final TipoSinInternet tipo;
  final String texto;

  const EstadoSinInternetBarra(this.tipo, this.texto);

  static String _ventas(int n) => n == 1 ? '1 venta' : '${EstadoSinInternet.miles(n)} ventas';

  static EstadoSinInternetBarra de(DatosSinInternetBarra d, {required DateTime ahora}) {
    EstadoSinInternetBarra es(TipoSinInternet t, String texto) => EstadoSinInternetBarra(t, texto);

    if (!d.hayInternet) {
      if (d.fiestas == 0) {
        return es(
          TipoSinInternet.sinLista,
          'Sin internet, y este equipo no tiene los precios de la barra: '
          'conectalo un momento a internet.',
        );
      }
      final partes = [
        'Sin internet',
        d.alDia == null
            ? 'se sigue con lo de este equipo'
            : 'se sigue con lo de este equipo (al día ${EstadoSinInternet.cuandoFue(d.alDia!, ahora)})',
        if (d.sinSubir > 0) '${_ventas(d.sinSubir)} sin subir: se suben solas al volver',
      ];
      return es(TipoSinInternet.sinInternet, partes.join(' · '));
    }

    const falta = 'Todavía no está lista para trabajar sin internet';
    final alDia = d.alDia;
    if (alDia == null) {
      if (d.fallo && !d.bajando) {
        return es(TipoSinInternet.falta, '$falta: no se pudo bajar. Se vuelve a intentar sola.');
      }
      return es(TipoSinInternet.falta, 'Poniéndose al día para trabajar sin internet…');
    }
    if (d.fallo && ahora.difference(alDia) > EstadoSinInternet.vencido) {
      return es(
        TipoSinInternet.falta,
        'No se pudo poner al día desde las ${EstadoSinInternet.horaDe(alDia)}. '
        'Se vuelve a intentar sola.',
      );
    }
    return es(
      TipoSinInternet.lista,
      [
        'Lista para trabajar sin internet · al día ${EstadoSinInternet.cuandoFue(alDia, ahora, hoy: true)}',
        if (d.sinSubir > 0) '${_ventas(d.sinSubir)} subiendo',
      ].join(' · '),
    );
  }
}

/// Con qué se pone al día la barra. La app usa el motor de sync y la base
/// (`accesosBarraProvider`); los tests, unos en memoria.
class AccesosBarra {
  /// Baja las fiestas, los PIN, el catálogo y los precios. Si bajó todo.
  final Future<bool> Function() bajar;
  final Future<int> Function() contarFiestas;
  final Future<int> Function() contarSinSubir;
  final Future<DateTime?> Function() leerAlDia;
  final Future<void> Function(DateTime cuando) anotarAlDia;
  final DateTime Function() ahora;

  const AccesosBarra({
    required this.bajar,
    required this.contarFiestas,
    required this.contarSinSubir,
    this.leerAlDia = AlDiaDeLaBarra.leer,
    this.anotarAlDia = AlDiaDeLaBarra.anotar,
    this.ahora = DateTime.now,
  });
}

/// Cuándo se puso al día la barra por última vez en este equipo. Se guarda, así se
/// sabe también al abrir sin internet.
class AlDiaDeLaBarra {
  AlDiaDeLaBarra._();

  static const _clave = 'barra_al_dia_v1';

  static Future<DateTime?> leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(_clave);
      return crudo == null ? null : DateTime.tryParse(crudo);
    } catch (e) {
      debugPrint('No se pudo leer cuándo se puso al día la barra: $e');
      return null;
    }
  }

  static Future<void> anotar(DateTime cuando) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave, cuando.toUtc().toIso8601String());
    } catch (e) {
      debugPrint('No se pudo anotar cuándo se puso al día la barra: $e');
    }
  }
}

/// Pone al día la barra en este equipo y cuenta lo que espera subir.
///
/// - Con internet: al abrir, cada [cada] y cuando vuelve internet, baja todo lo de la
///   barra. Si bajó, anota la hora.
/// - Sin internet no intenta nada: dice con qué hora quedó.
/// - Cada [cadaCuenta], cuántas fiestas tiene y cuántas ventas esperan subir.
class PuestaAlDiaBarra extends ChangeNotifier {
  PuestaAlDiaBarra({
    required this.accesos,
    required bool hayInternet,
    this.cada = const Duration(minutes: 5),
    this.cadaCuenta = const Duration(seconds: 10),
  }) : _datos = DatosSinInternetBarra(hayInternet: hayInternet);

  final AccesosBarra accesos;
  final Duration cada;
  final Duration cadaCuenta;

  DatosSinInternetBarra _datos;
  DatosSinInternetBarra get datos => _datos;

  bool _arrancada = false;
  bool _cerrada = false;
  Future<void>? _enCurso;
  Timer? _timer;
  Timer? _timerCuenta;

  void _poner(DatosSinInternetBarra d) {
    _datos = d;
    if (!_cerrada) notifyListeners();
  }

  /// Empieza: lee la hora guardada, cuenta, y si hay internet se pone al día.
  Future<void> arrancar() async {
    if (_arrancada) return;
    _arrancada = true;
    final alDia = await accesos.leerAlDia();
    if (_cerrada) return;
    if (alDia != null) _poner(_datos.copyWith(alDia: alDia));
    _timer = Timer.periodic(cada, (_) {
      if (_datos.hayInternet) unawaited(ponerAlDia());
    });
    _timerCuenta = Timer.periodic(cadaCuenta, (_) => unawaited(recontar()));
    await Future.wait([recontar(), if (_datos.hayInternet) ponerAlDia()]);
  }

  /// Se cortó o volvió internet.
  void conexion(bool hay) {
    if (hay == _datos.hayInternet) return;
    _poner(_datos.copyWith(hayInternet: hay));
    if (hay && _arrancada) unawaited(ponerAlDia());
  }

  /// Baja todo. Si ya está bajando, espera a esa.
  Future<void> ponerAlDia() => _enCurso ??= _ponerAlDia().whenComplete(() {
        _enCurso = null;
      });

  Future<void> _ponerAlDia() async {
    if (_cerrada || !_datos.hayInternet) return;
    _poner(_datos.copyWith(bajando: true));
    var bien = false;
    try {
      bien = await accesos.bajar();
    } catch (e) {
      debugPrint('La barra no pudo ponerse al día: $e');
    }
    if (_cerrada) return;
    final cuando = accesos.ahora();
    if (bien) await accesos.anotarAlDia(cuando);
    if (_cerrada) return;
    _poner(_datos.copyWith(bajando: false, fallo: !bien, alDia: bien ? cuando : null));
    await recontar();
  }

  /// Cuántas fiestas tiene y cuántas ventas esperan subir.
  Future<void> recontar() async {
    try {
      final fiestas = await accesos.contarFiestas();
      final sinSubir = await accesos.contarSinSubir();
      if (!_cerrada && (fiestas != _datos.fiestas || sinSubir != _datos.sinSubir)) {
        _poner(_datos.copyWith(fiestas: fiestas, sinSubir: sinSubir));
      }
    } catch (e) {
      debugPrint('No se pudo contar lo de la barra: $e');
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
