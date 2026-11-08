import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../recepcion/services/lista_sin_internet.dart';
import '../central/filas_de_la_red.dart';

export '../../recepcion/services/lista_sin_internet.dart' show TipoSinInternet;
export '../central/filas_de_la_red.dart' show PendientesDeLaBarra;

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

  /// Todo lo de la barra que espera subir: las ventas y los demás cambios (cajas,
  /// anulaciones, vales). Null: solo se contaron las ventas ([sinSubir]).
  final PendientesDeLaBarra? pendientes;

  const DatosSinInternetBarra({
    required this.hayInternet,
    this.alDia,
    this.bajando = false,
    this.fallo = false,
    this.fiestas = 0,
    this.sinSubir = 0,
    this.pendientes,
  });

  /// Lo que espera subir, con lo que se haya contado.
  PendientesDeLaBarra get porSubir => pendientes ?? PendientesDeLaBarra(ventas: sinSubir);

  DatosSinInternetBarra copyWith({
    bool? hayInternet,
    DateTime? alDia,
    bool? bajando,
    bool? fallo,
    int? fiestas,
    int? sinSubir,
    PendientesDeLaBarra? pendientes,
  }) =>
      DatosSinInternetBarra(
        hayInternet: hayInternet ?? this.hayInternet,
        alDia: alDia ?? this.alDia,
        bajando: bajando ?? this.bajando,
        fallo: fallo ?? this.fallo,
        fiestas: fiestas ?? this.fiestas,
        sinSubir: sinSubir ?? this.sinSubir,
        pendientes: pendientes ?? this.pendientes,
      );
}

/// Lo que dice la línea.
@immutable
class EstadoSinInternetBarra {
  final TipoSinInternet tipo;
  final String texto;

  const EstadoSinInternetBarra(this.tipo, this.texto);

  /// "Todo subido": con internet, cuando no queda nada de la barra por subir (pedido del
  /// 7-nov, "para quedarnos tranquilos").
  static const todoSubido = 'Todo subido';

  static EstadoSinInternetBarra de(DatosSinInternetBarra d, {required DateTime ahora}) {
    EstadoSinInternetBarra es(TipoSinInternet t, String texto) => EstadoSinInternetBarra(t, texto);
    final porSubir = d.porSubir;

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
        porSubir.vacio ? 'nada por subir' : '${porSubir.enPalabras} sin subir: se suben solas al volver',
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
        porSubir.vacio ? todoSubido : '${porSubir.enPalabras} subiendo',
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

  /// Todo lo de la barra que espera subir. Null: solo las ventas ([contarSinSubir]).
  final Future<PendientesDeLaBarra> Function()? contarPendientes;
  final Future<DateTime?> Function() leerAlDia;
  final Future<void> Function(DateTime cuando) anotarAlDia;
  final DateTime Function() ahora;

  const AccesosBarra({
    required this.bajar,
    required this.contarFiestas,
    required this.contarSinSubir,
    this.contarPendientes,
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
/// - Cuántas fiestas tiene y cuánto espera subir: al abrir, al escribir ([escribio]), al
///   cambiar la conexión y al bajar; y cada [cadaCuenta] **solo mientras hay internet y
///   queda algo por subir** (pedido del usuario el 7-nov: ahorrar también eso).
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
    await Future.wait([recontar(), if (_datos.hayInternet) ponerAlDia()]);
  }

  /// Se cortó o volvió internet.
  void conexion(bool hay) {
    if (hay == _datos.hayInternet) return;
    _poner(_datos.copyWith(hayInternet: hay));
    if (hay && _arrancada) unawaited(ponerAlDia());
    if (!hay) _otraCuenta();
  }

  /// Este equipo escribió algo (una venta, un vale, la caja): hay que volver a contar.
  void escribio() {
    if (_arrancada) unawaited(recontar());
  }

  /// La próxima cuenta: **solo mientras hay internet y queda algo por subir**, que es cuando
  /// el número cambia solo (la cola sube). Sin nada pendiente no se cuenta de nuevo hasta
  /// que el equipo escriba, cambie la conexión o baje algo. Es la base de este equipo, nunca
  /// la nube.
  void _otraCuenta() {
    final hace = !_cerrada && _datos.hayInternet && !_datos.porSubir.vacio;
    if (!hace) {
      _timerCuenta?.cancel();
      _timerCuenta = null;
      return;
    }
    _timerCuenta ??= Timer(cadaCuenta, () {
      _timerCuenta = null;
      unawaited(recontar());
    });
  }

  /// Si la cuenta de lo pendiente está andando (para las pruebas).
  @visibleForTesting
  bool get cuentaAndando => _timerCuenta != null;

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

  /// Cuántas fiestas tiene y cuánto espera subir.
  Future<void> recontar() async {
    try {
      final fiestas = await accesos.contarFiestas();
      final sinSubir = await accesos.contarSinSubir();
      final pendientes = await accesos.contarPendientes?.call();
      if (!_cerrada &&
          (fiestas != _datos.fiestas || sinSubir != _datos.sinSubir || pendientes != _datos.pendientes)) {
        _poner(_datos.copyWith(fiestas: fiestas, sinSubir: sinSubir, pendientes: pendientes));
      }
    } catch (e) {
      debugPrint('No se pudo contar lo de la barra: $e');
    }
    _otraCuenta();
  }

  @override
  void dispose() {
    _cerrada = true;
    _timer?.cancel();
    _timerCuenta?.cancel();
    super.dispose();
  }
}
