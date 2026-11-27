import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_engine.dart';
import '../../core/services/totem_config_cache.dart';
import '../../main.dart' show supabaseProvider;
import '../../models/evento.dart';
import '../../models/totem_config.dart';
import '../common/utils/dia_de_la_fiesta.dart';
import '../recepcion/providers/recepcion_provider.dart';
import '../recepcion/repositories/invitados_repository.dart';
import '../recepcion/services/lista_sin_internet.dart';
import '../totem/estilos/totem_estilo.dart';
import '../totem/services/apariencia_en_la_pc.dart';
import '../totem/services/foto_guardada.dart';

/// **Todas las escuelas listas sin internet** (pedido del jefe, 25-nov-2026).
///
/// La tele se prepara en la oficina, con internet, y esa noche en el salón no
/// hay. Así que, con internet, la tele baja **todo lo de las fiestas de los
/// próximos [dias] días** (hasta [hasta]), no solo la de esta noche: la lista
/// de la puerta, los alumnos con sus sillas y el plano, la apariencia del
/// tótem (Personalizar), la foto y el fondo. Esa noche cambiar de escuela no
/// necesita nada de afuera.
///
/// - La lista de cada una con `bajarListaDelEvento`; las tablas de la puerta
///   (`bajarParaLaPuerta`) **una sola vez por vuelta**: son las mismas para
///   todas.
/// - Las apariencias de todas **en una sola consulta** ([AparienciaEnLaPc]),
///   guardadas en [TotemConfigCache]; la foto y el fondo con [FotosDelTotem],
///   solo si faltan.
/// - Una fiesta con todo queda "al día" ([AlDiaDeLaPuerta]): la misma hora que
///   anota Recepción, así la línea "Lista para trabajar sin internet" de esa
///   fiesta lo sabe.
///
/// En LA FIESTA del menú de la tele se ve cómo quedó cada una ([como]).
class PrepararLasFiestas extends ChangeNotifier {
  PrepararLasFiestas({required this.accesos});

  final AccesosDeLasFiestas accesos;

  static const dias = 30;
  static const hasta = 10;

  /// Cada cuánto se vuelve a preparar todo, con internet. Un cambio en una
  /// fiesta llega antes: lo guardado en Personalizar avisa
  /// ([releerApariencia]), y la lista de la fiesta que se muestra la pone al
  /// día la puesta al día de siempre.
  static const cada = Duration(minutes: 30);

  final _como = <String, ComoQuedoLaFiesta>{};

  /// Cómo quedó cada fiesta, por id.
  Map<String, ComoQuedoLaFiesta> get como => Map.unmodifiable(_como);

  bool _preparando = false;
  bool get preparando => _preparando;

  DateTime? _ultimaVuelta;
  Set<String> _ultimas = const {};
  bool _cerrado = false;

  /// Las fiestas que se preparan: las que vienen ([enElOrdenDeLasFiestas],
  /// desde la de anoche hasta el mediodía), de acá a [dias] días, las primeras
  /// [hasta].
  static List<Evento> cuales(List<Evento> eventos, DateTime ahora) {
    final tope = DateTime(ahora.year, ahora.month, ahora.day + dias + 1);
    return enElOrdenDeLasFiestas(
      eventos.where((e) => !laFiestaYaPaso(e, ahora) && e.fechaEvento.isBefore(tope)),
      ahora,
    ).take(hasta).toList();
  }

  /// La línea de LA FIESTA de una que todavía no tiene cómo quedó (26-nov-2026:
  /// salía sin ninguna). LA FIESTA lista todas las que vienen; se preparan solo
  /// [cuales].
  static String sinPreparar(Evento e, List<Evento> eventos, DateTime ahora) {
    if (cuales(eventos, ahora).any((f) => f.id == e.id)) {
      return 'Preparándose para trabajar sin internet…';
    }
    final tope = DateTime(ahora.year, ahora.month, ahora.day + dias + 1);
    return e.fechaEvento.isBefore(tope)
        ? 'Todavía no se prepara: primero las $hasta que vienen antes'
        : 'Se prepara sola cuando falte un mes';
  }

  void _poner(String id, ComoQuedoLaFiesta c) {
    _como[id] = c;
    if (!_cerrado) notifyListeners();
  }

  /// Con internet: baja todo lo de cada fiesta que viene. Si ya se preparó
  /// hace menos de [cada] y son las mismas fiestas, no hace nada (salvo
  /// [forzar]: volvió internet).
  Future<void> preparar(List<Evento> eventos, {bool forzar = false}) async {
    if (_preparando || _cerrado) return;
    final ahora = accesos.ahora();
    final fiestas = cuales(eventos, ahora);
    final ids = {for (final e in fiestas) e.id};
    final ultima = _ultimaVuelta;
    if (!forzar &&
        ultima != null &&
        setEquals(ids, _ultimas) &&
        ahora.difference(ultima) < cada) {
      return;
    }
    _preparando = true;
    _ultimas = ids;
    _ultimaVuelta = ahora;
    _como.removeWhere((id, _) => !ids.contains(id));
    for (final e in fiestas) {
      _poner(e.id, (_como[e.id] ?? ComoQuedoLaFiesta(eventoId: e.id)).bajando());
    }
    try {
      // Una vez por vuelta: los alumnos, sus sillas, el plano, lo de la venta.
      final puerta = await _sinFallar(accesos.bajarParaLaPuerta, false);
      // Todas las apariencias en una sola consulta (null: no se pudo).
      Map<String, TotemConfig>? apariencias;
      try {
        apariencias = await accesos.leerApariencias(ids.toList());
      } catch (e) {
        debugPrint('La tele no pudo leer las apariencias: $e');
      }
      for (final e in fiestas) {
        if (_cerrado) return;
        await _prepararUna(e, puerta: puerta, apariencias: apariencias);
      }
    } finally {
      _preparando = false;
      if (!_cerrado) notifyListeners();
    }
  }

  Future<void> _prepararUna(
    Evento e, {
    required bool puerta,
    required Map<String, TotemConfig>? apariencias,
  }) async {
    final lista = await _sinFallar(() => accesos.bajarLista(e.id), false);
    // La apariencia: la de la nube, guardada; si no se pudo leer, la que ya
    // estaba guardada sirve.
    final guardada = await _sinFallar(() => accesos.aparienciaGuardada(e.id), null);
    bool? apariencia;
    TotemConfig? cfg;
    if (apariencias != null) {
      cfg = apariencias[e.id];
      if (cfg != null) {
        await _sinFallar(() => accesos.guardarApariencia(cfg!), null);
        apariencia = true;
      }
    } else {
      cfg = guardada;
      apariencia = guardada != null ? true : false;
    }
    final foto = await _imagen(cfg?.imagenUrl, e.id, accesos.guardarFoto);
    final fondo = await _imagen(_fondoQueUsa(cfg), e.id, accesos.guardarFondo);
    var c = ComoQuedoLaFiesta(
      eventoId: e.id,
      // En un masivo, también los alumnos y el plano.
      lista: lista && (puerta || e.modalidad != 'masivo'),
      apariencia: apariencia,
      foto: foto,
      fondo: fondo,
    );
    if (c.completa) {
      final cuando = accesos.ahora();
      await _sinFallar(() => accesos.anotarAlDia(e.id, cuando), null);
      c = c.conAlDia(cuando);
    } else {
      c = c.conAlDia(await _sinFallar(() => accesos.leerAlDia(e.id), null));
    }
    _poner(e.id, c);
  }

  /// Sin internet: lo que ya está guardado de cada fiesta (al arrancar en el
  /// salón).
  Future<void> mirar(List<Evento> eventos) async {
    if (_cerrado) return;
    final fiestas = cuales(eventos, accesos.ahora());
    final ids = {for (final e in fiestas) e.id};
    _como.removeWhere((id, _) => !ids.contains(id));
    for (final e in fiestas) {
      if (_cerrado) return;
      final alDia = await _sinFallar(() => accesos.leerAlDia(e.id), null);
      final cfg = await _sinFallar(() => accesos.aparienciaGuardada(e.id), null);
      final url = cfg?.imagenUrl;
      final fondoUrl = _fondoQueUsa(cfg);
      _poner(
        e.id,
        ComoQuedoLaFiesta(
          eventoId: e.id,
          lista: alDia != null,
          // Lo anotado al día ya tenía la apariencia (o la de siempre).
          apariencia: cfg != null ? true : (alDia != null ? null : false),
          foto: url == null || url.isEmpty
              ? null
              : await _sinFallar(() => accesos.fotoGuardada(url, e.id), false),
          fondo: fondoUrl == null
              ? null
              : await _sinFallar(() => accesos.fondoGuardado(fondoUrl, e.id), false),
          alDia: alDia,
          sinInternet: true,
        ),
      );
    }
  }

  /// Personalizar guardó la apariencia de [eventoId] en otra PC (el pulso): la
  /// lee de nuevo, con su foto y su fondo.
  Future<void> releerApariencia(String eventoId) async {
    if (_cerrado || !_como.containsKey(eventoId)) return;
    try {
      final cfg = (await accesos.leerApariencias([eventoId]))[eventoId];
      if (cfg == null) return;
      await accesos.guardarApariencia(cfg);
      final foto = await _imagen(cfg.imagenUrl, eventoId, accesos.guardarFoto);
      final fondo = await _imagen(_fondoQueUsa(cfg), eventoId, accesos.guardarFondo);
      final antes = _como[eventoId];
      if (antes == null) return;
      _poner(eventoId, antes.con(apariencia: true, foto: foto, fondo: fondo));
    } catch (e) {
      debugPrint('La tele no pudo releer la apariencia: $e');
    }
  }

  /// El fondo que hace falta: solo si el tótem va con "Tu fondo".
  static String? _fondoQueUsa(TotemConfig? cfg) {
    if (cfg == null) return null;
    final usa = EstiloTotem.elegida(cfg.estilo, fondoUrl: cfg.fondoUrl) == EstiloTotem.tuFondo;
    return usa ? cfg.fondoUrl : null;
  }

  /// Guarda la imagen si falta (null: la fiesta no tiene).
  Future<bool?> _imagen(
    String? url,
    String eventoId,
    Future<bool> Function(String url, String eventoId) guardar,
  ) async {
    if (url == null || url.isEmpty) return null;
    return _sinFallar(() => guardar(url, eventoId), false);
  }

  static Future<T> _sinFallar<T>(Future<T> Function() f, T siFalla) async {
    try {
      return await f();
    } catch (e) {
      debugPrint('Preparar las fiestas: $e');
      return siFalla;
    }
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}

/// Cómo quedó una fiesta para trabajar sin internet.
@immutable
class ComoQuedoLaFiesta {
  const ComoQuedoLaFiesta({
    required this.eventoId,
    this.lista = false,
    this.apariencia,
    this.foto,
    this.fondo,
    this.alDia,
    this.preparando = false,
    this.sinInternet = false,
  });

  final String eventoId;

  /// La lista de la puerta (y, en un masivo, los alumnos y el plano) bajó.
  final bool lista;

  /// La apariencia del tótem: true guardada, false no se pudo, null la de
  /// siempre.
  final bool? apariencia;

  /// La foto y el fondo: true guardados, false no se pudo, null no tiene.
  final bool? foto;
  final bool? fondo;

  /// La última vez que quedó con todo.
  final DateTime? alDia;

  final bool preparando;

  /// Lo que se sabe sin internet (lo guardado).
  final bool sinInternet;

  bool get completa => lista && apariencia != false && foto != false && fondo != false;

  ComoQuedoLaFiesta bajando() => ComoQuedoLaFiesta(
        eventoId: eventoId,
        lista: lista,
        apariencia: apariencia,
        foto: foto,
        fondo: fondo,
        alDia: alDia,
        preparando: true,
      );

  ComoQuedoLaFiesta conAlDia(DateTime? cuando) => ComoQuedoLaFiesta(
        eventoId: eventoId,
        lista: lista,
        apariencia: apariencia,
        foto: foto,
        fondo: fondo,
        alDia: cuando,
        sinInternet: sinInternet,
      );

  ComoQuedoLaFiesta con({bool? apariencia, bool? foto, bool? fondo}) => ComoQuedoLaFiesta(
        eventoId: eventoId,
        lista: lista,
        apariencia: apariencia ?? this.apariencia,
        foto: foto,
        fondo: fondo,
        alDia: alDia,
        sinInternet: sinInternet,
      );

  /// Lo que falta, para decirlo: "la lista", "la apariencia"...
  List<String> get falta => [
        if (!lista) 'la lista',
        if (apariencia == false) 'la apariencia',
        if (foto == false) 'la foto',
        if (fondo == false) 'el fondo',
      ];

  /// La línea de LA FIESTA, en el menú de la tele.
  String texto(DateTime ahora) {
    if (preparando) return 'Preparándose para trabajar sin internet…';
    if (completa) {
      final cuando = alDia;
      return cuando == null
          ? 'Lista sin internet'
          : 'Lista sin internet · al día ${EstadoSinInternet.cuandoFue(cuando, ahora, hoy: true)}';
    }
    final f = falta;
    final lista = f.length == 1 ? f.first : '${f.sublist(0, f.length - 1).join(', ')} y ${f.last}';
    return sinInternet
        ? 'Sin internet, y no tiene guardado: $lista'
        : 'Falta $lista · se vuelve a intentar sola';
  }
}

/// Con qué se prepara cada fiesta. La app usa la base, la nube y las carpetas
/// de fotos del equipo ([accesosDeLasFiestasProvider]); las pruebas y la app
/// de prueba, unos en memoria.
class AccesosDeLasFiestas {
  const AccesosDeLasFiestas({
    required this.bajarLista,
    required this.bajarParaLaPuerta,
    required this.leerApariencias,
    required this.guardarApariencia,
    required this.aparienciaGuardada,
    required this.guardarFoto,
    required this.fotoGuardada,
    required this.guardarFondo,
    required this.fondoGuardado,
    this.leerAlDia = AlDiaDeLaPuerta.leer,
    this.anotarAlDia = AlDiaDeLaPuerta.anotar,
    this.ahora = DateTime.now,
  });

  final Future<bool> Function(String eventoId) bajarLista;
  final Future<bool> Function() bajarParaLaPuerta;

  /// Las de la nube, en una consulta; tira si no se pudo.
  final Future<Map<String, TotemConfig>> Function(List<String> eventoIds) leerApariencias;
  final Future<void> Function(TotemConfig cfg) guardarApariencia;
  final Future<TotemConfig?> Function(String eventoId) aparienciaGuardada;
  final Future<bool> Function(String url, String eventoId) guardarFoto;
  final Future<bool> Function(String url, String eventoId) fotoGuardada;
  final Future<bool> Function(String url, String eventoId) guardarFondo;
  final Future<bool> Function(String url, String eventoId) fondoGuardado;
  final Future<DateTime?> Function(String eventoId) leerAlDia;
  final Future<void> Function(String eventoId, DateTime cuando) anotarAlDia;
  final DateTime Function() ahora;
}

final accesosDeLasFiestasProvider = Provider<AccesosDeLasFiestas>((ref) {
  final invitados = ref.watch(invitadosRepositoryProvider);
  final motor = ref.watch(syncEngineProvider);
  final apariencia = AparienciaEnLaPc(ref.watch(supabaseProvider));
  return AccesosDeLasFiestas(
    bajarLista: invitados.bajarListaDelEvento,
    bajarParaLaPuerta: motor.bajarParaLaPuerta,
    leerApariencias: apariencia.leer,
    guardarApariencia: TotemConfigCache.save,
    aparienciaGuardada: TotemConfigCache.load,
    guardarFoto: (url, id) => FotosDelTotem.enLaPc.guardar(url, eventoId: id),
    fotoGuardada: (url, id) => FotosDelTotem.enLaPc.estaGuardada(url, eventoId: id),
    guardarFondo: (url, id) => FotosDelTotem.fondosEnLaPc.guardar(url, eventoId: id),
    fondoGuardado: (url, id) => FotosDelTotem.fondosEnLaPc.estaGuardada(url, eventoId: id),
  );
});

/// Las fiestas de la tele, preparadas: con internet, al abrir, al volver
/// internet y cada [PrepararLasFiestas.cada]; sin internet, lo guardado. Solo
/// lo mira la tele (`PantallaTele`): en la PC no corre.
final prepararLasFiestasProvider = Provider<PrepararLasFiestas>((ref) {
  final p = PrepararLasFiestas(accesos: ref.watch(accesosDeLasFiestasProvider));
  final conexion = ref.watch(connectivityServiceProvider);
  var eventos = const <Evento>[];
  bool hay() => conexion.currentStatus == AppConnectivity.online;
  void vuelta({bool forzar = false}) =>
      unawaited(hay() ? p.preparar(eventos, forzar: forzar) : p.mirar(eventos));
  ref.listen(eventosActivosProvider, (_, e) {
    if (!e.hasValue) return;
    eventos = e.value!;
    vuelta();
  }, fireImmediately: true);
  final sub = conexion.stream.listen((s) {
    if (s == AppConnectivity.online) vuelta(forzar: true);
  });
  final cada = Timer.periodic(PrepararLasFiestas.cada, (_) => vuelta(forzar: true));
  final apariencias = ref.watch(syncEngineProvider).aparienciasCambiadasStream.listen((ids) {
    for (final id in ids) {
      unawaited(p.releerApariencia(id));
    }
  });
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(apariencias.cancel());
    cada.cancel();
    p.dispose();
  });
  return p;
});
