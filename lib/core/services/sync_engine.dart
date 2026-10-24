import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_database.dart';
import '../database/sync_queue.dart';
import '../utils/uuid_utils.dart';
import 'borrados_de_otra_pc.dart';
import 'connectivity_service.dart';
import 'contrato_al_bajar.dart';
import 'instalacion_id.dart';
import '../../features/cierre_caja/cierre_caja_sync_config.dart';
import '../../features/eventos/repositories/contratos_repository.dart';
import '../../features/mi_empresa/repositories/finanzas_repository.dart';
import '../../features/eventos/services/mora_tracked_recovery.dart';
import '../../features/eventos/services/revision_mora_constancia.dart';
import '../../models/contrato_alumno.dart';

/// Estado del motor de sincronización.
enum SyncStatus { idle, wakingUp, syncing, probing, error, offline }

/// Resultado del último chequeo remoto (sin descargar datos).
class RemoteProbeInfo {
  final int remoteChangeCount;
  final DateTime? lastProbeAt;
  final bool probeSucceeded;
  final String? probeError;

  const RemoteProbeInfo({
    this.remoteChangeCount = 0,
    this.lastProbeAt,
    this.probeSucceeded = false,
    this.probeError,
  });

  bool get hasRemoteChanges => probeSucceeded && remoteChangeCount > 0;
}

/// Hasta dónde puede avanzar el marcador de "última bajada" de una tabla.
///
/// El pull incremental pide `updated_at > marcador`, así que el marcador es una
/// promesa: *todo lo anterior ya está escrito localmente*. Cuando una fila baja
/// pero no se escribe —porque tiene un cambio local sin subir y no se la quiere
/// pisar— esa promesa se rompe, y si el marcador avanza igual la fila queda del
/// otro lado del filtro y **no se vuelve a pedir nunca**.
///
/// Por eso, si hubo alguna retenida, la marca se queda un milisegundo antes de
/// la más vieja: la próxima pasada la vuelve a traer. Cuesta re-bajar unas pocas
/// filas por ciclo y paga no perder ninguna.
String marcadorPullSeguro({
  required String ahora,
  DateTime? pendienteMasVieja,
}) {
  if (pendienteMasVieja == null) return ahora;
  return pendienteMasVieja
      .toUtc()
      .subtract(const Duration(milliseconds: 1))
      .toIso8601String();
}

/// Hasta dónde llegó de verdad una bajada, según el reloj del servidor.
///
/// El marcador se compara contra `updated_at`, que lo sella Postgres con su
/// propio `now()`. Sacarlo del reloj de la PC —`DateTime.now()`— mete la
/// diferencia entre los dos relojes adentro del filtro: una PC adelantada
/// guarda un marcador del futuro y se saltea, para siempre y sin un solo error
/// en el log, las filas que se escriban en esa ventana. Una atrasada re-baja lo
/// mismo indefinidamente.
///
/// La marca correcta es el `updated_at` más alto de lo que se acaba de bajar:
/// sale del mismo reloj contra el que se va a comparar, no cuesta un request
/// extra, y siempre queda por detrás de "ahora" — o sea que en la duda re-pide,
/// nunca saltea.
///
/// Devuelve `null` si ninguna fila trajo una fecha legible. En ese caso el
/// llamador tiene que **dejar el marcador donde estaba**: no hay de dónde
/// sacarlo, y inventarlo es exactamente cómo se pierden filas.
String? marcaDeLoBajado(
  Iterable<Map<String, dynamic>> filas,
  String columnaFecha,
) {
  DateTime? maxima;
  for (final fila in filas) {
    final crudo = fila[columnaFecha];
    if (crudo == null) continue;
    final fecha = DateTime.tryParse(crudo.toString())?.toUtc();
    if (fecha == null) continue;
    if (maxima == null || fecha.isAfter(maxima)) maxima = fecha;
  }
  return maxima?.toIso8601String();
}

/// Si una fila que bajó de la nube trae algo que acá no estaba.
///
/// Decide si vale la pena avisarles a las pantallas (ver `cambiosBajadosStream`).
/// No alcanza con "bajaron filas": con el marcador retenido por un cambio local
/// sin subir (`marcadorPullSeguro`), cada ciclo vuelve a bajar las mismas filas,
/// y avisar por eso sería refrescar pantallas cada 10 segundos por nada.
///
/// [existeLocal] en `false` es fila nueva. Las fechas se comparan como instante:
/// la base local y Postgres no escriben el mismo texto para la misma hora.
bool filaEsNovedad({
  required bool existeLocal,
  required Object? versionLocal,
  required Object? versionNube,
}) {
  if (!existeLocal) return true;
  final local = DateTime.tryParse(versionLocal?.toString() ?? '')?.toUtc();
  final nube = DateTime.tryParse(versionNube?.toString() ?? '')?.toUtc();
  if (local == null || nube == null) {
    return versionLocal?.toString() != versionNube?.toString();
  }
  return !local.isAtSameMomentAs(nube);
}

/// Si lo que se sube es solo el latido de una sesión de caja y nada más.
///
/// El latido encola `{id, last_heartbeat, updated_at}`. Si en la cola había un
/// cambio real de esa sesión (apertura, cierre, arqueo), la cola fusiona los dos
/// y el payload trae más columnas: eso sí es novedad y sí lleva pulso.
bool esSoloLatido(
  String tabla,
  SyncOperation operacion,
  Map<String, dynamic> payload,
) {
  if (tabla != 'sesiones_caja' || operacion != SyncOperation.update) {
    return false;
  }
  const delLatido = {'id', 'last_heartbeat', 'updated_at'};
  return payload.containsKey('last_heartbeat') &&
      payload.keys.every(delLatido.contains);
}

/// Cómo se guarda en SQLite un valor que bajó de la nube.
///
/// Las columnas `jsonb` (el detalle por mesa, los acompañantes) llegan como
/// lista o mapa y se guardan como **JSON**. Antes se guardaban con `toString()`
/// —`[{n: 1, precio: 70000.0, …}]`—, que no es JSON: `MesaExtraItem.listFromJson`
/// no lo podía leer, el detalle por mesa quedaba vacío en la PC que lo bajaba, y
/// al volver a subir la fila ese texto roto viajaba a la nube.
dynamic valorParaSqlite(dynamic value) {
  if (value is List || value is Map) return jsonEncode(value);
  if (value is bool) return value ? 1 : 0;
  return value;
}

/// Con cuántos intentos fallidos una entrada de la cola se considera trabada.
const int intentosParaTrabado = 10;

/// Qué entradas de la cola se intentan en esta pasada: las frescas siempre, y
/// las trabadas solo cuando les toca el reintento, **todas juntas**.
List<SyncQueueEntry> entradasDeEstaPasada(
  Iterable<SyncQueueEntry> ordenadas, {
  required bool tocaReintentarTrabados,
}) =>
    [
      for (final e in ordenadas)
        if (e.intentos < intentosParaTrabado || tocaReintentarTrabados) e,
    ];

/// Si una fila de `planos_evento` que bajó de la nube lleva el id fijo de su
/// fiesta (`UuidUtils.planoEventoId`).
///
/// Las dos PCs escriben la misma fila porque el id sale de la fiesta. Una fila
/// con otro id solo puede venir de una carga a mano en la nube: guardarla
/// pisaría el plano de esta PC (la tabla local tiene `UNIQUE(evento_id)`) y
/// después el sorteo no podría guardar el suyo.
bool planoTraeIdFijo(Map<String, dynamic> fila) {
  final id = fila['id'];
  final evento = fila['evento_id'];
  return id is String &&
      evento is String &&
      evento.isNotEmpty &&
      id == UuidUtils.planoEventoId(evento);
}

/// Lo que hay que hacer cuando llega un pulso.
class TrabajoDelPulso {
  /// Tablas a bajar. Solo las conocidas por el motor.
  final Set<String> tablas;

  /// Ids a borrar, por tabla. Vienen de un borrado que hizo una persona.
  final Map<String, Set<String>> borrados;

  const TrabajoDelPulso({required this.tablas, required this.borrados});

  static const vacio = TrabajoDelPulso(tablas: {}, borrados: {});

  bool get estaVacio => tablas.isEmpty && borrados.isEmpty;
}

/// Lee un pulso y decide qué hacer con él.
///
/// El payload cruzó la red y lo escribió otro proceso, así que se trata como
/// dato y no como instrucción: solo se aceptan tablas que el motor ya conoce
/// —[tablasConocidas]— e ids con forma de UUID. Un mensaje raro produce trabajo
/// vacío, nunca una consulta a una tabla inventada.
///
/// [yo] es el id de esta instalación, para descartar el eco: un broadcast le
/// vuelve también a quien lo mandó, y sin esto cada PC saldría a bajar lo que
/// acaba de subir. Cuando es `null` —el id todavía no se resolvió— **no se
/// descarta nada**: bajar de más es inocuo; tomar un aviso ajeno por propio
/// sería perderse el cambio.
TrabajoDelPulso trabajoDelPulso(
  Object? datos, {
  required String? yo,
  required Set<String> tablasConocidas,
}) {
  if (datos is! Map) return TrabajoDelPulso.vacio;
  if (yo != null && datos['origen'] == yo) return TrabajoDelPulso.vacio;

  // `is List` y no `as List?`: un campo con otra forma —un string donde se
  // esperaba una lista— tiene que dar trabajo vacío, no una excepción adentro
  // del callback del socket, donde nadie la atrapa.
  final tablas = <String>{};
  final crudasTablas = datos['tablas'];
  for (final t in crudasTablas is List ? crudasTablas : const []) {
    final tabla = t?.toString() ?? '';
    if (tablasConocidas.contains(tabla)) tablas.add(tabla);
  }

  final borrados = <String, Set<String>>{};
  final crudos = datos['borrados'];
  if (crudos is Map) {
    for (final e in crudos.entries) {
      final tabla = e.key.toString();
      if (!tablasConocidas.contains(tabla)) continue;
      final ids = e.value;
      for (final id in ids is List ? ids : const []) {
        final s = id?.toString() ?? '';
        // Mismo blindaje que el resto del motor: un id que no es UUID le saca
        // un 22P02 a Supabase, y acá además apuntaría a un `delete` local.
        if (s.length == 36) (borrados[tabla] ??= <String>{}).add(s);
      }
    }
  }

  return TrabajoDelPulso(tablas: tablas, borrados: borrados);
}

/// ¿Es creíble que la nube esté vacía?
///
/// Contar lo que bajó y contrastarlo contra un `count` del servidor detecta una
/// página truncada, pero **no detecta el caso en que no se pudo leer nada**: si
/// la sesión venció, o RLS niega la tabla, PostgREST no tira error — devuelve
/// cero filas, y el `count` también da cero. Los dos números coinciden, el
/// chequeo canta "foto completa", y comparar eso contra la base local dice que
/// sobra **todo**.
///
/// O sea que la protección de contar, sola, convierte un problema de permisos en
/// un borrado total. Es la misma trampa que vació los presupuestos —creer que
/// "no vino" significa "no existe"— una capa más adentro.
///
/// Por eso: si la nube dice cero y acá hay filas, no se toca nada. Vaciar una
/// tabla entera a propósito existe, pero es raro y se resuelve con un pull
/// manual; no vale la pena hacerle lugar automático al mismo camino por el que
/// se pierde todo.
bool fotoDeLaNubeEsCreible({required int enLaNube, required int local}) =>
    !(enLaNube == 0 && local > 0);

/// Qué filas locales se pueden borrar después de una bajada.
///
/// **Nada se borra de la base local, salvo que alguien lo haya borrado a mano.**
/// Un `DELETE` local solo es legítimo si viene con nombre y apellido —una lista
/// explícita de ids que una persona eliminó— o si sale de comparar contra una
/// foto **completa** de la nube, del mismo alcance que se va a recorrer.
///
/// Contra un lote incremental no vale: lo que no vino no está de más, es lo que
/// simplemente no cambió. Así se vaciaron los presupuestos. El pull bajaba las
/// 22 líneas que alguien acababa de tocar en la otra PC, y el prune borraba las
/// otras 203 de la tabla. Como el monto del presupuesto es la suma de sus líneas
/// —no hay columna de total—, todos los demás presupuestos quedaban en $0 sin
/// que nadie avisara.
///
/// Una página que cortó en el límite del servidor tampoco es una foto completa:
/// quien la traiga tiene que verificar que trajo todo antes de pasar
/// `fotoCompleta: true`.
Set<String> filasAPodar({
  required bool fotoCompleta,
  required Set<String> idsLocales,
  required Set<String> idsEnLaNube,
  required Set<String> idsPendientes,
}) {
  if (!fotoCompleta) return const <String>{};
  return idsLocales.difference(idsEnLaNube).difference(idsPendientes);
}

/// Los pagos de un alumno en esta PC, comparados con los de la nube.
class PagosDelAlumnoEnLaNube {
  const PagosDelAlumnoEnLaNube({required this.deMas, required this.faltan});

  /// Están acá y en la nube ya no, y no esperan subir: los borró alguien en la
  /// otra PC. Se sacan.
  final Set<String> deMas;

  /// Están en la nube y acá todavía no bajaron. Mientras falte alguno no se
  /// rehace la cuenta del alumno: daría que debe más, y esa cuenta sube.
  final Set<String> faltan;
}

/// Compara los pagos de un alumno con la foto de la nube **de ese alumno**.
///
/// Es una foto completa y contada del mismo alcance que se recorre (los pagos
/// de un contrato), así que cumple la regla de [filasAPodar], que es quien
/// decide qué sobra. Sin foto completa no sobra ni falta nada.
PagosDelAlumnoEnLaNube compararPagosDelAlumno({
  required Set<String> locales,
  required Set<String> pendientes,
  required Set<String> enLaNube,
  required bool fotoCompleta,
}) =>
    PagosDelAlumnoEnLaNube(
      deMas: filasAPodar(
        fotoCompleta: fotoCompleta,
        idsLocales: locales,
        idsEnLaNube: enLaNube,
        idsPendientes: pendientes,
      ),
      faltan: fotoCompleta ? enLaNube.difference(locales) : const <String>{},
    );

/// Motor de sincronización — local-first, nube manual.
class SyncEngine {
  final ConnectivityService _connectivity;
  final SupabaseClient _supabase;

  /// Mapa que define qué columna usar para el filtro incremental en cada tabla.
  /// Todas las tablas usan updated_at para detectar creaciones Y ediciones.
  static const Map<String, String> _incrementalColumns = {
    'clientes': 'updated_at',
    'eventos': 'updated_at',
    'servicios': 'updated_at',
    'eventos_servicios': 'updated_at',
    'presupuestos': 'updated_at',
    'presupuesto_servicios': 'updated_at',
    'transacciones': 'updated_at',
    'egresos': 'updated_at',
    'contratos_alumnos': 'updated_at',
    'notas_operativas_contrato': 'updated_at',
    'pagos_contrato_alumno': 'updated_at',
    'invitados': 'updated_at',
    'solicitudes_cotizacion': 'updated_at',
    'prestamos_alquiler': 'updated_at',
    'prestamo_alquiler_lineas': 'updated_at',
    'pagos_prestamo_alquiler': 'updated_at',
    'calculos_rentabilidad': 'updated_at',
    'obligaciones_pago': 'updated_at',
    'caja_fuerte_movimientos': 'updated_at',
    'rentabilidad_config': 'updated_at',
    'cierre_caja_guia_movimientos': 'updated_at',
    'cierre_caja_anotaciones': 'updated_at',
    'operadores_caja': 'updated_at',
    'sesiones_caja': 'updated_at',
    'compromisos_personal': 'updated_at',
    'sillas_reparto': 'updated_at',
    'entradas_retiro': 'updated_at',
    'sorteos_mesas': 'updated_at',
    'planos_evento': 'updated_at',
    'mesas_movimientos': 'updated_at',
    'predios': 'updated_at',
  };

  /// Tablas con fecha calendario mínima para pull/probe (rollout cierre operativo).
  static const Set<String> _tablasFechaCorteCierre = {
    'cierre_caja_guia_movimientos',
    'cierre_caja_anotaciones',
  };

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  RemoteProbeInfo _remoteProbe = const RemoteProbeInfo();
  RemoteProbeInfo get remoteProbe => _remoteProbe;
  int get remotePendingCount => _remoteProbe.remoteChangeCount;

  String? _lastError;
  String? get lastError => _lastError;

  /// Tablas cuyo `_pullTable` falló en la tanda actual.
  ///
  /// `_pullTable` se traga sus excepciones a propósito: si una tabla falla, su
  /// watermark no avanza y el próximo ciclo vuelve a pedir el mismo rango, así
  /// que un corte pasajero se cura solo y no se pierde nada. El problema era
  /// que, como nunca lanzaba, el `Future.wait` no veía el fallo y el estado
  /// quedaba en `idle`: la app decía "sincronizado" aunque no hubiera bajado
  /// una fila. El mismo silencio que escondió el incidente de la mora.
  final Set<String> _tablasConFalloPull = {};

  /// Pasa el estado a error si alguna tabla no bajó, nombrándolas.
  void _reportarFallosDePull() {
    if (_tablasConFalloPull.isEmpty) {
      _updateStatus(SyncStatus.idle);
      return;
    }
    final fallidas = _tablasConFalloPull.toList()..sort();
    _lastError = 'No bajaron: ${fallidas.join(", ")}';
    debugPrint('  ⚠️ Pull incompleto — $_lastError');
    _updateStatus(SyncStatus.error);
  }

  DateTime? _lastUploadTime;
  DateTime? get lastUploadTime => _lastUploadTime;

  DateTime? _lastPullTime;
  DateTime? get lastPullTime => _lastPullTime;

  // Stream de estado
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  final _pendingController = StreamController<int>.broadcast();
  Stream<int> get pendingStream => _pendingController.stream;

  final _remoteProbeController = StreamController<RemoteProbeInfo>.broadcast();
  Stream<RemoteProbeInfo> get remoteProbeStream =>
      _remoteProbeController.stream;

  // ── Aviso de lo que bajó ──────────────────────────────────────────────────
  //
  // Las tablas en las que acaba de bajar algo distinto de lo que había acá.
  //
  // Existe por el cierre de caja: el jefe anulaba un cobro, la anulación
  // llegaba a la PC del operario en segundos por el pulso, y la pantalla seguía
  // mostrando la foto vieja hasta el próximo ciclo de 10 s —o, en el diálogo de
  // cerrar caja, hasta volver a abrirlo—. El dato estaba; nadie le avisaba a la
  // pantalla. Solo avisa: no cambia qué ni cómo se sincroniza.
  final _cambiosBajadosController = StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get cambiosBajadosStream =>
      _cambiosBajadosController.stream;

  final Set<String> _tablasConCambios = {};
  Timer? _timerAvisoCambios;

  /// Un pull baja varias tablas en paralelo: se juntan en un solo aviso.
  static const _esperaAvisoCambios = Duration(milliseconds: 300);

  void _anotarCambioBajado(String tabla) {
    _tablasConCambios.add(tabla);
    _timerAvisoCambios?.cancel();
    _timerAvisoCambios = Timer(_esperaAvisoCambios, _avisarCambiosBajados);
  }

  void _avisarCambiosBajados() {
    if (_tablasConCambios.isEmpty || _cambiosBajadosController.isClosed) return;
    final tablas = Set<String>.unmodifiable(_tablasConCambios);
    _tablasConCambios.clear();
    _cambiosBajadosController.add(tablas);
  }

  StreamSubscription<AppConnectivity>? _connectivitySub;

  SyncEngine({
    required ConnectivityService connectivity,
    SupabaseClient? supabase,
  }) : _connectivity = connectivity,
       _supabase = supabase ?? Supabase.instance.client;

  /// Inicia el motor: el pulso entre PCs y la revisión de borrados. La subida
  /// (a los 2 s de guardar) y el ciclo de bajada de 10 s viven en
  /// `OperationalSyncCoordinator`.
  void start() {
    debugPrint('⚡ SyncEngine iniciado (local primero, sync automático)');

    SyncQueue.onChanged = () {
      unawaited(refreshPendingCount());
      _programarSubida();
    };

    _connectivitySub = _connectivity.stream.listen((status) {
      if (status == AppConnectivity.offline) {
        _updateStatus(SyncStatus.offline);
      } else if (_status == SyncStatus.offline) {
        _updateStatus(SyncStatus.idle);
      }
    });

    if (_connectivity.currentStatus == AppConnectivity.offline) {
      _updateStatus(SyncStatus.offline);
    } else {
      _updateStatus(SyncStatus.idle);
    }

    unawaited(refreshPendingCount());
    _remoteProbeController.add(_remoteProbe);

    // El pulso vive acá y no en un widget a propósito: no depende del rol
    // elegido ni de que haya una pantalla abierta. Una PC de Asesor tiene que
    // enterarse igual.
    _escucharElPulso();
    _arrancarReconciliacion();
  }

  /// Cada cuánto se revisa si en la nube desapareció algo.
  ///
  /// Diez minutos y no diez segundos: en vivo los borrados llegan por el pulso
  /// y, si se pierde, por la cuenta de cada ciclo (`_contarParaVerBorrados`).
  /// Esto es para lo demás y para la PC que estaba apagada cuando pasaron. Son
  /// unas 25 consultas de ids y otros tantos `count` (los pagos, en 5 tandas),
  /// y no tiene sentido pagarlos seguido.
  static const _cadaCuantoSeReconcilia = Duration(minutes: 10);
  Timer? _timerReconciliacion;

  Timer? _reintentoReconciliacion;

  void _arrancarReconciliacion() {
    if (kIsWeb) return;

    // Sin esto la reconciliación se muere de hambre. El pull corre cada 10
    // segundos, así que `_isBusy` está en true buena parte del tiempo: un
    // intento que cae justo ahí se salteaba y se iba a esperar los diez minutos
    // completos, y el siguiente podía caer igual. En la prueba real no llegó a
    // correr ni una vez.
    //
    // Reintentar a los 30 s cuesta nada y le da al turno una ventana libre.
    Future<void> correr() async {
      if (_connectivity.currentStatus == AppConnectivity.offline) return;
      if (_isBusy) {
        _reintentoReconciliacion?.cancel();
        _reintentoReconciliacion = Timer(
          const Duration(seconds: 30),
          () => unawaited(correr()),
        );
        return;
      }
      try {
        await _reconcileDeletes();
      } catch (e) {
        debugPrint('⚠️ Reconciliación de borrados: $e');
      }
    }

    // La primera, apenas arranca: es justo el momento en que esta PC puede venir
    // de estar apagada mientras la otra borraba cosas. Con una espera corta para
    // no pelearse con el pull inicial.
    Timer(const Duration(seconds: 20), () => unawaited(correr()));
    _timerReconciliacion = Timer.periodic(
      _cadaCuantoSeReconcilia,
      (_) => unawaited(correr()),
    );
  }

  /// Espera entre el último encolado y la subida automática.
  ///
  /// Corta pero no cero: un cobro masivo encola decenas de filas seguidas y no
  /// tiene sentido salir a subir con cada una. El timer se reinicia en cada
  /// encolado, así que sube una sola vez, dos segundos después de la última.
  static const _esperaAntesDeSubir = Duration(seconds: 2);
  Timer? _timerSubida;

  /// Vacía la cola poco después de que alguien guarde algo.
  ///
  /// Antes lo único que movía la cola sola era el ciclo de 10 segundos del
  /// coordinador —y solo con un rol operativo— o el latido de la sesión de
  /// caja. Un cambio hecho sin caja abierta podía quedarse parado un rato
  /// largo, o hasta que alguien apretara "Subir pendientes".
  ///
  /// No fuerza nada: si no hay red, o el motor está ocupado, `flushPending`
  /// sale solo y el ciclo de siempre lo reintenta.
  void _programarSubida() {
    _timerSubida?.cancel();
    _timerSubida = Timer(_esperaAntesDeSubir, () async {
      if (_isBusy || _connectivity.currentStatus == AppConnectivity.offline) {
        return;
      }
      if (!await hayTrabajoDeSubida) return;
      await flushPending();
    });
  }

  bool get _isBusy =>
      _status == SyncStatus.syncing ||
      _status == SyncStatus.wakingUp ||
      _status == SyncStatus.probing;

  /// Sube todos los cambios locales pendientes a la nube.
  Future<void> flushPending({DateTime? createdSince}) async {
    if (_isBusy) {
      debugPrint('🔄 Sync ocupado, ignorando flush...');
      return;
    }
    if (_connectivity.currentStatus == AppConnectivity.offline) {
      _lastError = 'Sin conexión';
      _updateStatus(SyncStatus.offline);
      return;
    }

    try {
      _updateStatus(SyncStatus.wakingUp);
      final awake = await _connectivity.wakeUpCloud();
      if (!awake) {
        _lastError = 'Supabase no disponible';
        _updateStatus(SyncStatus.error);
        return;
      }

      _updateStatus(SyncStatus.syncing);
      _lastError = null;

      var rounds = 0;
      const maxRounds = 50;
      while (rounds < maxRounds) {
        final progress = await _flushQueue(
          unlimited: true,
          createdSince: createdSince,
        );
        if (!progress) break;
        rounds++;
      }

      _lastUploadTime = DateTime.now();
      _updateStatus(SyncStatus.idle);
      debugPrint('✅ Subida completada ($_pendingCount pendientes restantes)');

      // Recién acá, con todo arriba: avisarle a la otra PC qué mirar.
      await _emitirPulso();
    } catch (e) {
      debugPrint('❌ Error flushPending: $e');
      _lastError = e.toString();
      _updateStatus(SyncStatus.error);
    } finally {
      await refreshPendingCount();
    }
  }

  /// Baja cambios remotos a SQLite (no sube pendientes locales).
  ///
  /// Desde la 6.1.1 revisa siempre lo borrado en otra PC, antes de la mora (ver
  /// `_pullFromCloud`): [reconcileDeletes] queda por compatibilidad.
  Future<void> pullRemote({bool reconcileDeletes = false}) async {
    if (_isBusy) return;
    if (_connectivity.currentStatus == AppConnectivity.offline) {
      _lastError = 'Sin conexión';
      _updateStatus(SyncStatus.offline);
      return;
    }

    try {
      _updateStatus(SyncStatus.wakingUp);
      final awake = await _connectivity.wakeUpCloud();
      if (!awake) {
        _lastError = 'Supabase no disponible';
        _updateStatus(SyncStatus.error);
        return;
      }

      _updateStatus(SyncStatus.syncing);
      _lastError = null;
      await _pullFromCloud();

      FinanzasRepository.invalidateProyeccionCache();
      _lastPullTime = DateTime.now();
      _updateStatus(SyncStatus.idle);
      debugPrint('✅ Bajada completada');

      await probeRemoteChanges();
    } catch (e) {
      debugPrint('❌ Error pullRemote: $e');
      _lastError = e.toString();
      _updateStatus(SyncStatus.error);
    } finally {
      await refreshPendingCount();
    }
  }

  // ── El pulso ───────────────────────────────────────────────────────────────
  //
  // Un canal de **broadcast** por el que las PCs se avisan qué acaban de
  // cambiar, para no depender del reloj: la que sube manda "toqué presupuestos
  // y sus líneas" y la otra baja **solo esas dos tablas**, en vez de esperar
  // hasta un minuto a que le toque el turno.
  //
  // Broadcast y no `postgres_changes`: los mensajes son WebSocket puro, no
  // consultan el slot de replicación ni disparan `realtime.apply_rls`, que fue
  // lo que agotó el Disk IO del proyecto en septiembre de 2026. **No se agrega
  // ninguna tabla a la publicación de Realtime** — sigue solo `invitados`, que
  // es el tótem. Ver docs/CONTEXTO_v4.9.4_2026-09-02.md.
  //
  // Para las tablas, el pulso es un **acelerador, no un transporte**: lo único
  // que hace es adelantar un pull que igual iba a pasar. Si el socket está
  // caído, o el mensaje se pierde, o la PC estaba apagada, el ciclo de siempre
  // lo cubre. Por eso no hay acuses: un aviso perdido cuesta segundos, no datos.
  //
  // **Para los borrados no es así**: el pull trae lo nuevo y lo cambiado, nunca
  // lo que dejó de existir. Un borrado que se pierde lo repone recién la
  // revisión (`_reconcileDeletes`) o la consulta de un alumno al abrirlo
  // (`revisarPagosDelAlumno`). Por eso los borrados del pulso no se tiran
  // cuando la PC está ocupada: se guardan y se aplican a los pocos segundos. El
  // 19-oct-2026 el jefe borró un pago de DE CARLO y la PC del operario, prendida
  // y cobrando, se lo quedó: al cobrarle contó los dos y le pisó el saldo a la
  // nube.

  static const String _nombreCanalPulso = 'sync_pulse';
  static const String _eventoPulso = 'cambios';

  /// Cuánto se espera antes de reaccionar a un pulso.
  ///
  /// Una subida manda un solo mensaje, pero dos PCs trabajando a la vez pueden
  /// encadenarlos. Agruparlos evita salir a pedir las mismas tablas tres veces
  /// seguidas, y medio segundo no lo nota nadie.
  static const _esperaTrasPulso = Duration(milliseconds: 400);

  RealtimeChannel? _canalPulso;
  Timer? _debouncePulso;

  /// Lo que esta PC subió y todavía no anunció. Se vacía al emitir.
  final Set<String> _tablasSubidas = {};
  final Map<String, Set<String>> _borradosSubidos = {};

  /// Lo que anunciaron las otras y todavía no se aplicó.
  final Set<String> _tablasDelPulso = {};
  final Map<String, Set<String>> _borradosDelPulso = {};

  /// Qué se lleva puesto el borrado de un padre.
  ///
  /// Espeja los `ON DELETE CASCADE` que ya tiene Supabase (verificados sobre el
  /// proyecto). Hace falta escribirlos acá porque **en SQLite local no está
  /// `PRAGMA foreign_keys = ON`**: los `CASCADE` declarados en el esquema local
  /// son decorativos y no borran nada.
  ///
  /// Es lo mismo que hace `PresupuestosRepository.eliminar()` a mano — borra las
  /// líneas y después el presupuesto, y encola solo el padre porque de la nube
  /// se encarga el cascade.
  ///
  /// `presupuesto_servicios → servicios` NO está: en la nube es `NO ACTION`.
  static const Map<String, List<(String, String)>> _hijasEnCascada = {
    'clientes': [('eventos', 'cliente_id')],
    'eventos': [
      ('eventos_servicios', 'evento_id'),
      ('contratos_alumnos', 'evento_id'),
    ],
    'contratos_alumnos': [('pagos_contrato_alumno', 'contrato_alumno_id')],
    'presupuestos': [('presupuesto_servicios', 'presupuesto_id')],
    'servicios': [('eventos_servicios', 'servicio_id')],
  };

  void _anotarParaElPulso(SyncQueueEntry entry) {
    if (!_incrementalColumns.containsKey(entry.tabla)) return;
    // El latido de la caja sube cada minuto: con pulso, la otra PC bajaba datos
    // una vez por minuto todo el día. Le llega igual por el ciclo de 10 s, que
    // es como llegaba antes del pulso y le sobra al margen de 90 s del
    // indicador "caja abierta en otra PC".
    if (esSoloLatido(entry.tabla, entry.operacion, entry.payload)) return;
    _tablasSubidas.add(entry.tabla);
    if (entry.operacion == SyncOperation.delete) {
      (_borradosSubidos[entry.tabla] ??= <String>{}).add(entry.registroId);
    }
  }

  /// Le avisa a la otra PC qué acaba de cambiar.
  Future<void> _emitirPulso() async {
    if (_tablasSubidas.isEmpty) return;

    final origen = InstalacionId.valor;
    final tablas = _tablasSubidas.toList();
    final borrados = {
      for (final e in _borradosSubidos.entries) e.key: e.value.toList(),
    };
    _tablasSubidas.clear();
    _borradosSubidos.clear();

    try {
      final canal = _canalPulso ??= _supabase.channel(_nombreCanalPulso);
      await canal.sendBroadcastMessage(
        event: _eventoPulso,
        payload: {'origen': origen, 'tablas': tablas, 'borrados': borrados},
      );
      debugPrint('  📣 Pulso: ${tablas.join(", ")}');
    } catch (e) {
      // Que no llegue el aviso no rompe nada: el ciclo de siempre lo cubre.
      debugPrint('  ⚠️ El pulso no salió: $e');
    }
  }

  void _escucharElPulso() {
    // En web no: no hay base local que actualizar —esa rama va directo a
    // Supabase— y suscribir un canal por cada visitante del catálogo o del tótem
    // sería pagar sockets para no hacer nada con ellos.
    if (kIsWeb) return;

    _canalPulso ??= _supabase.channel(_nombreCanalPulso);
    _canalPulso!
      ..onBroadcast(event: _eventoPulso, callback: _alRecibirPulso)
      ..subscribe();
  }

  void _alRecibirPulso(Map<String, dynamic> mensaje) {
    final trabajo = trabajoDelPulso(
      mensaje['payload'],
      yo: InstalacionId.valor,
      tablasConocidas: _incrementalColumns.keys.toSet(),
    );
    if (trabajo.estaVacio) return;

    _tablasDelPulso.addAll(trabajo.tablas);
    for (final e in trabajo.borrados.entries) {
      (_borradosDelPulso[e.key] ??= <String>{}).addAll(e.value);
    }

    _debouncePulso?.cancel();
    _debouncePulso = Timer(_esperaTrasPulso, () => unawaited(_atenderElPulso()));
  }

  /// Cuánto se espera para volver a intentar los borrados de un pulso que llegó
  /// con la PC ocupada.
  static const _esperaBorradosDelPulso = Duration(seconds: 3);
  Timer? _reintentoBorradosDelPulso;

  Future<void> _atenderElPulso() async {
    if (_isBusy || _connectivity.currentStatus == AppConnectivity.offline) {
      // Las tablas se sueltan a propósito: el ciclo de 10 s las baja igual, y
      // reencolarlas es cómo se arma una tormenta de reintentos.
      _tablasDelPulso.clear();
      // Los borrados no: no tienen otro camino al instante (ver arriba). Son una
      // lista con nombre y apellido y aplicarlos dos veces no hace nada, así que
      // esperar a que la PC se desocupe no cuesta nada.
      if (_borradosDelPulso.isNotEmpty) {
        _reintentoBorradosDelPulso?.cancel();
        _reintentoBorradosDelPulso = Timer(
          _esperaBorradosDelPulso,
          () => unawaited(_atenderElPulso()),
        );
      }
      return;
    }

    final tablas = _tablasDelPulso.toList();
    final borrados = Map<String, Set<String>>.from(_borradosDelPulso);
    _tablasDelPulso.clear();
    _borradosDelPulso.clear();

    try {
      final db = await LocalDatabase.instance;

      // Los borrados primero: si además bajan filas de esas tablas, que no
      // vuelvan a entrar las que alguien acaba de eliminar.
      for (final e in borrados.entries) {
        await _aplicarBorrados(
          db,
          e.key,
          e.value,
          camino: CaminoDelBorrado.aviso,
        );
      }

      if (tablas.isNotEmpty) {
        _tablasConFalloPull.clear();
        await Future.wait([
          for (final tabla in tablas) _pullTable(db, tabla, 'updated_at'),
        ]);
        _lastPullTime = DateTime.now();
        debugPrint('  ⚡ Pulso atendido: ${tablas.join(", ")}');
      }
    } catch (e) {
      debugPrint('  ⚠️ Error atendiendo el pulso: $e');
    }
  }

  /// Borra local una lista **explícita** de ids, con su cascada.
  ///
  /// Esto cumple la primera mitad de la regla: el borrado viene con nombre y
  /// apellido, o sea que alguien apretó eliminar. No hay comparación de
  /// conjuntos y por lo tanto no hay forma de que se exceda — es el camino
  /// seguro, al lado del que compara contra la nube entera, que necesita foto
  /// completa (ver `filasAPodar`).
  ///
  /// No se encola nada: en la nube ya está borrado, y encolarlo sería mandarle
  /// de vuelta un DELETE por algo que no pasó acá.
  ///
  /// Lo que se saca queda escrito en `borrados_en_otra_pc.txt`, con el
  /// [camino] por el que esta PC se enteró. Y si entre lo sacado hay pagos, la
  /// cuenta de esos alumnos se rehace ([rehacerCuentas]): con el pago adentro,
  /// esta PC pudo haber subido un saldo armado con él. Devuelve cuántas filas
  /// sacó.
  Future<int> _aplicarBorrados(
    Database db,
    String tabla,
    Set<String> ids, {
    required CaminoDelBorrado camino,
    bool rehacerCuentas = true,
  }) async {
    final sacado = _LoSacado();
    await _borrarConSusHijas(db, tabla, ids, sacado);
    if (sacado.estaVacio) return 0;

    for (final t in sacado.tablas) {
      _anotarCambioBajado(t);
    }
    debugPrint(
      '  🗑️ ${sacado.total} fila(s) que en la nube ya no estaban '
      '(${camino.texto}): ${sacado.tablas.join(", ")}',
    );
    try {
      await BorradosConstancia.anotar(sacado.renglones, camino);
    } catch (e) {
      debugPrint('  ⚠️ No pude anotar lo borrado: $e');
    }
    if (rehacerCuentas) {
      await _rehacerCuentas(db, sacado.contratosARehacer);
    }
    return sacado.total;
  }

  Future<void> _borrarConSusHijas(
    Database db,
    String tabla,
    Set<String> ids,
    _LoSacado sacado, {
    int profundidad = 0,
  }) async {
    if (ids.isEmpty || profundidad > 4) return;

    // Lo que está esperando subir no se toca, igual que en el podado: puede ser
    // trabajo local que la nube todavía no vio.
    final pendientes = (await db.query(
      '_sync_queue',
      columns: ['registro_id'],
      where: 'tabla = ?',
      whereArgs: [tabla],
    )).map((r) => r['registro_id'] as String).toSet();

    final aBorrar = ids.difference(pendientes);
    if (aBorrar.isEmpty) return;

    // Primero las hijas, que en SQLite no caen solas.
    final hijas = _hijasEnCascada[tabla] ?? const <(String, String)>[];
    for (final (hija, columna) in hijas) {
      final huerfanas = <String>{};
      for (final id in aBorrar) {
        final filas = await db.query(
          hija,
          columns: ['id'],
          where: '$columna = ?',
          whereArgs: [id],
        );
        huerfanas.addAll(filas.map((r) => (r['id'] as String?) ?? ''));
      }
      huerfanas.remove('');
      await _borrarConSusHijas(
        db,
        hija,
        huerfanas,
        sacado,
        profundidad: profundidad + 1,
      );
    }

    for (final id in aBorrar) {
      // Se lee antes de borrar: para la constancia y, si es un pago, para saber
      // de qué alumno era y rehacerle la cuenta.
      final filas = await db.query(
        tabla,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (filas.isEmpty) continue;
      final fila = filas.first;
      String? alumno;
      if (tabla == 'pagos_contrato_alumno') {
        final contrato = await db.query(
          'contratos_alumnos',
          columns: ['nombre_alumno'],
          where: 'id = ?',
          whereArgs: [fila['contrato_alumno_id']],
          limit: 1,
        );
        if (contrato.isNotEmpty) {
          alumno = contrato.first['nombre_alumno'] as String?;
        }
      }
      await db.delete(tabla, where: 'id = ?', whereArgs: [id]);
      sacado.anotar(tabla, fila, alumno: alumno);
    }
  }

  /// Rehace la cuenta de los alumnos a los que se les sacó un pago.
  ///
  /// Solo si sus pagos en esta PC quedaron iguales a los de la nube: si falta
  /// alguno que todavía no bajó, la cuenta daría que debe más, y esa cuenta
  /// sube (es lo que se llevó puesta la auditoría de septiembre, ver el final
  /// de `contratos_repository.dart`). Si la nube ya tenía el saldo bien, el
  /// recálculo da lo mismo y no sube nada; si esta PC lo había pisado, sube el
  /// bueno.
  Future<void> _rehacerCuentas(Database db, Set<String> contratos) async {
    for (final id in contratos) {
      try {
        final comparados = await _compararPagosConLaNube(db, id);
        if (comparados == null) {
          debugPrint(
            '  ⏸️ $id: no pude leer sus pagos en la nube; la cuenta se rehace '
            'la próxima vez que se lo toque',
          );
          continue;
        }
        if (comparados.faltan.isNotEmpty) {
          debugPrint(
            '  ⏸️ $id: le faltan bajar ${comparados.faltan.length} pago(s); '
            'la cuenta se rehace cuando bajen',
          );
          continue;
        }
        await ContratosRepository(_supabase, _connectivity)
            .recalcularProgresoContrato(id, revisarNube: false);
      } catch (e) {
        debugPrint('  ⚠️ No pude rehacer la cuenta de $id: $e');
      }
    }
  }

  /// Cuánto se espera a la nube al consultar los pagos de un alumno. Corto: lo
  /// espera una pantalla que se está abriendo, o un cobro.
  static const _esperaNubeDelAlumno = Duration(seconds: 3);

  /// Los pagos de un alumno, comparados con la nube, o `null` si no se pudo
  /// leer la nube o lo que vino no es una foto creíble.
  Future<PagosDelAlumnoEnLaNube?> _compararPagosConLaNube(
    Database db,
    String contratoId,
  ) async {
    // Primero lo de esta PC y lo que espera subir; recién después la nube. Un
    // pago que sube mientras se consulta ya estaba en la cola al mirarla, así
    // que no se puede tomar por borrado.
    final locales = (await db.query(
      'pagos_contrato_alumno',
      columns: ['id'],
      where: 'contrato_alumno_id = ?',
      whereArgs: [contratoId],
    )).map((r) => (r['id'] as String?) ?? '').where((id) => id.isNotEmpty)
        .toSet();
    final pendientes = (await db.query(
      '_sync_queue',
      columns: ['registro_id'],
      where: 'tabla = ?',
      whereArgs: ['pagos_contrato_alumno'],
    )).map((r) => r['registro_id'] as String).toSet();

    try {
      final respuesta = await _supabase
          .from('pagos_contrato_alumno')
          .select('id')
          .eq('contrato_alumno_id', contratoId)
          .count(CountOption.exact)
          .timeout(_esperaNubeDelAlumno);
      final enLaNube = <String>{
        for (final f in respuesta.data)
          if (((f['id'] as String?) ?? '').isNotEmpty) f['id'] as String,
      };
      if (enLaNube.length != respuesta.count) {
        debugPrint(
          '  ⏸️ pagos de $contratoId: traje ${enLaNube.length} y la nube dice '
          '${respuesta.count} — no se toca nada',
        );
        return null;
      }

      // Cero pagos en la nube contra alguno acá puede ser de verdad (el jefe le
      // borró el único) o una sesión vencida, que también lee cero. Si el alumno
      // se ve, la sesión anda y el cero es de verdad.
      if (enLaNube.isEmpty && locales.isNotEmpty) {
        final alumno = await _supabase
            .from('contratos_alumnos')
            .select('id')
            .eq('id', contratoId)
            .limit(1)
            .timeout(_esperaNubeDelAlumno);
        if (alumno.isEmpty) {
          debugPrint(
            '  ⏸️ pagos de $contratoId: la nube no devuelve ni el alumno — '
            'eso es sesión o permisos, no un borrado',
          );
          return null;
        }
      }

      return compararPagosDelAlumno(
        locales: locales,
        pendientes: pendientes,
        enLaNube: enLaNube,
        fotoCompleta: true,
      );
    } catch (e) {
      debugPrint('  ⏸️ pagos de $contratoId: no pude leer la nube ($e)');
      return null;
    }
  }

  /// Cuándo se le preguntó a la nube por cada alumno. Una pantalla que se
  /// redibuja vuelve a pedir el historial: no tiene sentido salir a la nube
  /// cada vez.
  final Map<String, DateTime> _revisionDelAlumno = {};
  static const _cadaCuantoSeRevisaUnAlumno = Duration(seconds: 15);

  /// Saca de esta PC los pagos de un alumno que en la nube ya no están.
  ///
  /// Es lo que hace que lo borrado en otra PC desaparezca **al instante** donde
  /// importa: lo llaman el historial de pagos del alumno (la ventana de cobro,
  /// el estado de cuenta, el recibo, perdonar la mora) y el recálculo de su
  /// cuenta, antes de hacerla. No depende del aviso: le pregunta a la nube en
  /// ese momento.
  ///
  /// Sin internet no hace nada y no demora nada: se cobra igual, con lo de la
  /// PC. Con internet espera a la nube como mucho [_esperaNubeDelAlumno].
  ///
  /// Con [rehacerCuenta], si sacó algo y no le falta bajar ningún pago, rehace
  /// la cuenta del alumno. Devuelve cuántos pagos sacó.
  Future<int> revisarPagosDelAlumno(
    String contratoId, {
    CaminoDelBorrado camino = CaminoDelBorrado.alumno,
    bool rehacerCuenta = true,
  }) async {
    if (kIsWeb || contratoId.length != 36) return 0;
    if (_connectivity.currentStatus == AppConnectivity.offline) return 0;
    final ahora = DateTime.now();
    final antes = _revisionDelAlumno[contratoId];
    if (antes != null && ahora.difference(antes) < _cadaCuantoSeRevisaUnAlumno) {
      return 0;
    }
    _revisionDelAlumno[contratoId] = ahora;

    try {
      final db = await LocalDatabase.instance;
      final comparados = await _compararPagosConLaNube(db, contratoId);
      if (comparados == null || comparados.deMas.isEmpty) return 0;

      final sacados = await _aplicarBorrados(
        db,
        'pagos_contrato_alumno',
        comparados.deMas,
        camino: camino,
        rehacerCuentas: false,
      );
      if (sacados > 0 && rehacerCuenta && comparados.faltan.isEmpty) {
        await ContratosRepository(_supabase, _connectivity)
            .recalcularProgresoContrato(contratoId, revisarNube: false);
      }
      return sacados;
    } catch (e) {
      debugPrint('  ⚠️ Revisando los pagos de $contratoId: $e');
      return 0;
    }
  }

  /// Lo que se mueve durante un cobro. Baja en cada ciclo.
  ///
  /// Acá llegar tarde se ve: dos personas cobrando a la vez sobre el mismo
  /// evento, un cierre de caja que tiene que cuadrar contra lo que hizo la otra
  /// PC. Diez segundos es la cadencia que ya tenía y no se toca.
  static const List<String> _tablasDelCobro = [
    'operadores_caja',
    'sesiones_caja',
    'contratos_alumnos',
    'pagos_contrato_alumno',
    'notas_operativas_contrato',
    'egresos',
    'cierre_caja_guia_movimientos',
    'cierre_caja_anotaciones',
    // La entrega de entradas y el reparto de sillas también son de mostrador:
    // si las dos PCs atienden a la vez, cada una tiene que ver en segundos lo
    // que hizo la otra. El pulso los trae en menos de un segundo; esto es la red
    // de seguridad si el aviso no llega.
    'entradas_retiro',
    'sillas_reparto',
  ];

  /// El resto. Baja cada [ciclosEntrePullsLentos] ciclos.
  ///
  /// Son datos que cambian cuando alguien se sienta a cargar algo, no en el
  /// mostrador: un presupuesto, un evento, el catálogo de servicios, un
  /// alquiler. Un minuto de latencia no molesta a nadie — y con el pulso por
  /// broadcast ni siquiera se espera ese minuto: esto es la red de seguridad
  /// para cuando el pulso no llegó.
  ///
  /// Las últimas ocho cruzaban **solo a mano** hasta ahora: se habían dejado
  /// afuera en septiembre de 2026 porque ninguna estaba en la ruta del cobro y
  /// todas tenían entre 0 y 3 filas. Sumarlas acá cuesta un request por minuto
  /// cada una, que es menos de lo que costaba cualquiera de ellas cuando se
  /// bajaba la tabla entera al apretar sincronizar.
  ///
  /// `invitados` no está: se queda con su camino de Realtime, que es el tótem —
  /// el único lugar donde alguien está parado en la puerta esperando.
  static const List<String> _tablasDeCarga = [
    'eventos',
    'clientes',
    'eventos_servicios',
    'transacciones',
    'servicios',
    'presupuestos',
    'presupuesto_servicios',
    'solicitudes_cotizacion',
    'prestamos_alquiler',
    'prestamo_alquiler_lineas',
    'pagos_prestamo_alquiler',
    'calculos_rentabilidad',
    'obligaciones_pago',
    'caja_fuerte_movimientos',
    'rentabilidad_config',
    'compromisos_personal',
    'sorteos_mesas',
    // El plano de cada fiesta y los cambios de mesa: el pulso los trae en un
    // segundo; esto es la red de seguridad si el aviso no llega.
    'planos_evento',
    'mesas_movimientos',
    // Los predios con nombre (6.1.0): se guardan de vez en cuando, desde la
    // oficina. Un minuto de demora no molesta.
    'predios',
  ];

  /// Cada cuántos ciclos entran las tablas de carga: a 10 s por ciclo, un minuto.
  static const int ciclosEntrePullsLentos = 6;

  /// Si ya corrió [revisarMora] en esta sesión del programa.
  bool _moraRevisadaEnEstaSesion = false;

  /// La revisión de la mora: rehace la ficha, lo ya usado (offset) y la
  /// eximición de cada alumno desde sus pagos, **sube** lo que corrige y lo
  /// anota en `revision_mora.txt`. No toca pagos, saldos ni cuotas, ni los
  /// perdones (ver [MoraTrackedRecovery.reconciliarTodos]).
  ///
  /// Corre sola una vez por sesión, después de la primera bajada que sale
  /// bien, y cada vez que alguien aprieta "Bajar" en el menú. Nunca tira: si
  /// falla, la mora queda como estaba.
  ///
  /// [soloContratos]: revisa solo esos alumnos, en el momento. Lo usa
  /// reincorporar una baja temporal (ver [MoraTrackedRecovery.reconciliarTodos]).
  Future<void> revisarMora({Set<String>? soloContratos}) async {
    try {
      final db = await LocalDatabase.instance;
      final recalibrados = await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        encolarSync: true,
        constancia: RevisionMoraConstancia.anotar,
        soloContratos: soloContratos,
      );
      if (recalibrados > 0) {
        debugPrint(
          '  🔧 Revisión de la mora: $recalibrados contrato(s) corregidos desde los pagos',
        );
      }
      // La eximición de un alumno solo ya la resuelve la revisión de arriba.
      final exenciones = soloContratos != null
          ? 0
          : await MoraTrackedRecovery.repararExencionDesdeHistorial(
              db: db,
              encolarSync: true,
            );
      if (exenciones > 0) {
        debugPrint(
          '  🔧 Revisión de la mora: $exenciones contrato(s) con eximición reparada',
        );
      }
      if (recalibrados > 0 || exenciones > 0) {
        await refreshPendingCount();
      }
      // Lo que quedó sin explicar cuota por cuota, después de corregir: solo
      // en la revisión de todos, no en la de un alumno que se reincorpora.
      if (soloContratos == null) {
        final sinExplicar = await MoraTrackedRecovery.fichasSinExplicar(db);
        await RevisionMoraConstancia.anotar(
          sinExplicar,
          queHizo: MoraTrackedRecovery.queHizoFichasSinExplicar,
        );
      }
    } catch (e) {
      debugPrint('  ⚠️ Revisión de la mora: $e');
    }
  }

  /// Pull corto para la operación simultánea de cajas. Nunca sube la cola
  /// local: el jefe conserva sus pendientes manuales.
  ///
  /// Con [incluirTablasDeCarga] en false baja solo las de [_tablasDelCobro].
  /// El llamador lleva la cuenta de los ciclos; ver `OperationalSyncCoordinator`.
  Future<bool> pullOperationalUpdates({
    bool incluirTablasDeCarga = true,
  }) async {
    if (_isBusy || _connectivity.currentStatus == AppConnectivity.offline) {
      return false;
    }
    try {
      _updateStatus(SyncStatus.wakingUp);
      if (!await _connectivity.wakeUpCloud()) {
        _lastError = 'Supabase no disponible';
        _updateStatus(SyncStatus.error);
        return false;
      }
      _updateStatus(SyncStatus.syncing);
      _lastError = null;
      final db = await LocalDatabase.instance;
      _tablasConFalloPull.clear();

      // `eventos` y `clientes` viven en las tablas de carga, pero son las que
      // sostienen el desplegable de Cobros masivos (`eventos LEFT JOIN
      // clientes`). Hasta septiembre de 2026 `eventos` no bajaba sola nunca: sus
      // contratos y cobros sí, pero colgados de un evento_id que localmente no
      // existía. Por eso el ciclo lento no puede saltearse — es red de
      // seguridad, no un extra.
      final tablas = [
        ..._tablasDelCobro,
        if (incluirTablasDeCarga) ..._tablasDeCarga,
      ];
      await Future.wait([
        for (final tabla in tablas) _pullTable(db, tabla, 'updated_at'),
      ]);
      FinanzasRepository.invalidateProyeccionCache();
      _lastPullTime = DateTime.now();
      // Una vez por sesión, con los cobros recién bajados: la revisión de la
      // mora. Antes corría solo si alguien apretaba "Bajar" en el menú, así
      // que lo que corregía podía no correr nunca. Ahora corre sola al abrir
      // el programa (también la primera vez, al instalar una versión nueva).
      if (!_moraRevisadaEnEstaSesion && _tablasConFalloPull.isEmpty) {
        _moraRevisadaEnEstaSesion = true;
        // Antes, lo que se borró en otra PC mientras esta estaba cerrada: la
        // mora se rehace desde los pagos, y con un pago borrado adentro saldría
        // mal y subiría.
        await _reconcileDeletes();
        await revisarMora();
      } else {
        // En cada ciclo: si en la nube hay menos que acá, algo se borró en otra
        // PC y el aviso no llegó.
        await _contarParaVerBorrados(db);
      }
      // Lo que sí bajó tiene que refrescar igual la pantalla, así que esto
      // devuelve true de todos modos: lo único que cambia es dejar de informar
      // "sincronizado" cuando alguna tabla no llegó.
      _reportarFallosDePull();
      return true;
    } catch (e) {
      debugPrint('❌ Error pull operativo: $e');
      _lastError = e.toString();
      _updateStatus(SyncStatus.error);
      return false;
    } finally {
      await refreshPendingCount();
    }
  }

  /// Chequeo liviano: cuántos cambios hay en la nube que aún no bajaste.
  Future<RemoteProbeInfo> probeRemoteChanges() async {
    if (_connectivity.currentStatus == AppConnectivity.offline) {
      _remoteProbe = RemoteProbeInfo(
        remoteChangeCount: _remoteProbe.remoteChangeCount,
        lastProbeAt: _remoteProbe.lastProbeAt,
        probeSucceeded: false,
        probeError: 'Sin conexión',
      );
      _remoteProbeController.add(_remoteProbe);
      return _remoteProbe;
    }

    if (_isBusy) return _remoteProbe;

    try {
      _updateStatus(SyncStatus.probing);
      final awake = await _connectivity.wakeUpCloud();
      if (!awake) {
        _remoteProbe = RemoteProbeInfo(
          remoteChangeCount: _remoteProbe.remoteChangeCount,
          lastProbeAt: DateTime.now(),
          probeSucceeded: false,
          probeError: 'Nube no disponible',
        );
        _remoteProbeController.add(_remoteProbe);
        _updateStatus(SyncStatus.error);
        return _remoteProbe;
      }

      final db = await LocalDatabase.instance;
      var total = 0;
      for (final table in _incrementalColumns.keys) {
        total += await _probeTable(db, table);
      }

      _remoteProbe = RemoteProbeInfo(
        remoteChangeCount: total,
        lastProbeAt: DateTime.now(),
        probeSucceeded: true,
      );
      _remoteProbeController.add(_remoteProbe);
      _updateStatus(SyncStatus.idle);
      debugPrint('🔍 Probe remoto: $total cambios disponibles para bajar');
      return _remoteProbe;
    } catch (e) {
      debugPrint('❌ Error probeRemoteChanges: $e');
      _remoteProbe = RemoteProbeInfo(
        remoteChangeCount: _remoteProbe.remoteChangeCount,
        lastProbeAt: DateTime.now(),
        probeSucceeded: false,
        probeError: e.toString(),
      );
      _remoteProbeController.add(_remoteProbe);
      _updateStatus(SyncStatus.error);
      return _remoteProbe;
    }
  }

  /// Borra todos los timestamps de último pull para forzar pull completo
  /// en la próxima sincronización. Útil para recuperar datos faltantes
  /// cuando se cambió de PC o se detectaron registros perdidos.
  Future<void> resetPullTimestamps() async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_meta');
    debugPrint(
      '🔄 Timestamps de pull reseteados — el próximo pull será completo',
    );
  }

  /// Resetea timestamps y hace pull completo de inmediato.
  Future<void> forceFullPull() async {
    await resetPullTimestamps();
    await pullRemote();
  }

  Future<int> _probeTable(Database db, String table) async {
    final dateColumn = _incrementalColumns[table];
    if (dateColumn == null) return 0;

    try {
      final claveMeta = 'last_pull_$table';
      final metaRows = await db.query(
        '_sync_meta',
        where: 'clave = ?',
        whereArgs: [claveMeta],
      );
      final lastPullStr = metaRows.isNotEmpty
          ? metaRows.first['valor'] as String?
          : null;

      final countRes = await db.rawQuery('SELECT COUNT(*) as c FROM $table');
      final localCount = (countRes.first['c'] as int?) ?? 0;

      dynamic query = _supabase.from(table).select('id');

      if (lastPullStr != null) {
        query = query.gt(dateColumn, lastPullStr);
      } else if (localCount > 0) {
        final maxRes = await db.rawQuery(
          'SELECT MAX($dateColumn) as m FROM $table',
        );
        final maxLocal = maxRes.first['m'] as String?;
        if (maxLocal != null && maxLocal.isNotEmpty) {
          query = query.gt(dateColumn, maxLocal);
        } else {
          return 0;
        }
      }

      if (_tablasFechaCorteCierre.contains(table)) {
        query = query.gte('fecha', kCierreCajaSyncFechaCorte);
      }

      // `planned` en vez de `exact`: esto corre sobre las 24 tablas de una, y
      // con `exact` cada una era un scan completo de conteo — el pico más caro
      // del sistema. Acá el número solo alimenta un "hay N cambios para bajar",
      // así que la estimación del planner alcanza y sobra.
      final response = await query.count(CountOption.planned);
      return response.count;
    } catch (e) {
      debugPrint('  ⚠️ Error probe $table: $e');
      return 0;
    }
  }

  /// Cada cuánto se reintenta lo trabado. No se abandona nunca —un pago que no
  /// subió no se puede dar por perdido— pero tampoco se martilla la nube.
  static const Duration _esperaEntreReintentosTrabados = Duration(minutes: 5);
  DateTime? _ultimoReintentoTrabados;

  bool get _tocaReintentarTrabados {
    final ultimo = _ultimoReintentoTrabados;
    return ultimo == null ||
        DateTime.now().difference(ultimo) >= _esperaEntreReintentosTrabados;
  }

  /// `true` si hay algo que subir ahora: pendientes frescos, o trabados a los
  /// que ya les toca el reintento. Lo consulta el coordinador automático para
  /// no despertar la sincronización cada 10 segundos al pedo.
  Future<bool> get hayTrabajoDeSubida async {
    if (await SyncQueue.readyCount > 0) return true;
    return _tocaReintentarTrabados && await SyncQueue.stuckCount > 0;
  }

  /// Envía los cambios locales pendientes a la nube.
  /// Devuelve true si al menos una operación se completó con éxito.
  Future<bool> _flushQueue({
    bool unlimited = false,
    DateTime? createdSince,
  }) async {
    var pending = await SyncQueue.getPending(limit: unlimited ? null : 50);
    if (createdSince != null) {
      pending = pending
          .where((e) => !e.createdAt.isBefore(createdSince))
          .toList();
    }
    if (pending.isEmpty) return false;

    bool anySuccess = false;

    // ── PRIORIZACIÓN JERÁRQUICA ──────────────────────────────────────────
    // Definimos niveles de importancia para procesar primero los "padres"
    int getPriority(SyncQueueEntry entry) {
      final table = entry.tabla;
      final payload = entry.payload;

      if (table == 'clientes') return 0;
      if (table == 'eventos' ||
          table == 'presupuestos' ||
          table == 'prestamos_alquiler')
        return 1;

      // Los servicios globales son prioridad 0, los ad-hoc (con evento_id) son prioridad 2
      if (table == 'servicios') {
        return (payload['evento_id'] != null) ? 2 : 0;
      }

      if (table == 'pagos_contrato_alumno' ||
          table == 'pagos_prestamo_alquiler')
        return 4;
      if (table == 'notas_operativas_contrato') return 4;
      // Cuelgan del alumno, igual que las notas: el contrato tiene que estar
      // arriba antes, o la FK de la nube rechaza la fila.
      if (table == 'sillas_reparto' || table == 'entradas_retiro') return 4;
      if (table == 'sorteos_mesas') return 2;
      // Cuelgan del evento, como el registro del sorteo.
      if (table == 'planos_evento' || table == 'mesas_movimientos') return 2;
      if (table == 'eventos_servicios' ||
          table == 'presupuesto_servicios' ||
          table == 'prestamo_alquiler_lineas') {
        return 3;
      } // Depende de padre y servicio / préstamo

      // Análisis de rentabilidad: opcionalmente referencia evento/presupuesto; va al final
      if (table == 'calculos_rentabilidad') return 5;
      // Caja fuerte (Mi empresa PERSONAL): sin FK a eventos; cola estable
      if (table == 'caja_fuerte_movimientos') return 5;
      if (table == 'cierre_caja_guia_movimientos' ||
          table == 'cierre_caja_anotaciones')
        return 5;
      if (table == 'operadores_caja') return 1;
      // Antes que los egresos (que caen en el 2 por defecto): el egreso lleva
      // `compromiso_id`, así que la cuenta tiene que existir arriba primero.
      if (table == 'compromisos_personal') return 1;
      // Los predios no cuelgan de nada: son de todas las fiestas.
      if (table == 'predios') return 1;
      if (table == 'sesiones_caja') {
        return entry.operacion == SyncOperation.delete ? 6 : 2;
      }

      // Resto de tablas (transacciones, egresos, invitados, etc) dependen de evento
      return 2;
    }

    // Ordenamos la cola: primero por prioridad, luego por fecha (FIFO dentro de la prioridad)
    final sortedPending = List<SyncQueueEntry>.from(pending);
    sortedPending.sort((a, b) {
      final pA = getPriority(a);
      final pB = getPriority(b);
      if (pA != pB) return pA.compareTo(pB);
      return a.createdAt.compareTo(b.createdAt);
    });

    debugPrint(
      '📤 Procesando ${sortedPending.length} operaciones (Orden Jerárquico)...',
    );

    // Mantenemos un set de los IDs que están en esta cola para detectar dependencias pendientes
    final pendingIdsInQueue = pending.map((e) => e.registroId).toSet();

    // Un registro que falló mucho NO se abandona: se reintenta espaciado.
    // Antes se salteaba para siempre y, como el contador de pendientes
    // tampoco lo mostraba, el cobro moría en el disco de esa PC sin que
    // nadie se enterara (caso OSORIO 07/07, caso VALENTINA 18/04).
    //
    // Si toca o no se decide **una vez por pasada**, antes de recorrer. Cuando
    // se miraba adentro del bucle, el primer trabado sellaba la hora y los
    // demás ya no entraban: se reintentaba uno solo cada cinco minutos, y como
    // van por prioridad, uno que no puede subir nunca (una tabla que todavía no
    // existe en la nube) le sacaba el turno para siempre a un pago trabado.
    final aProcesar = entradasDeEstaPasada(
      sortedPending,
      tocaReintentarTrabados: _tocaReintentarTrabados,
    );
    if (aProcesar.any((e) => e.intentos >= intentosParaTrabado)) {
      _ultimoReintentoTrabados = DateTime.now();
    }

    for (final entry in aProcesar) {
      if (entry.intentos >= intentosParaTrabado) {
        debugPrint(
          '  ↻ Reintentando trabado: ${entry.tabla}/${entry.registroId} '
          '(${entry.intentos} intentos, último error: ${entry.ultimoError})',
        );
      }

      // BLOQUEO REFERENCIAL: Si el padre de este registro está en la MISMA cola pendiente,
      // posponemos este registro para la siguiente vuelta del motor.
      final payload = entry.payload;
      bool hasPendingParent = false;
      String? parentTable;
      String? parentId;

      if (payload['evento_id'] != null &&
          pendingIdsInQueue.contains(payload['evento_id'])) {
        hasPendingParent = true;
        // Detectar si el ID es de un evento o presupuesto en la cola
        final isPresupuesto = sortedPending.any(
          (e) =>
              e.tabla == 'presupuestos' && e.registroId == payload['evento_id'],
        );
        parentTable = isPresupuesto ? 'presupuestos' : 'eventos';
        parentId = payload['evento_id'];
      } else if (payload['presupuesto_id'] != null &&
          pendingIdsInQueue.contains(payload['presupuesto_id'])) {
        hasPendingParent = true;
        parentTable = 'presupuestos';
        parentId = payload['presupuesto_id'];
      } else if (payload['cliente_id'] != null &&
          pendingIdsInQueue.contains(payload['cliente_id'])) {
        hasPendingParent = true;
        parentTable = 'clientes';
        parentId = payload['cliente_id'];
      } else if (payload['contrato_alumno_id'] != null &&
          pendingIdsInQueue.contains(payload['contrato_alumno_id'])) {
        hasPendingParent = true;
        parentTable = 'contratos_alumnos';
        parentId = payload['contrato_alumno_id'];
      } else if (payload['prestamo_id'] != null &&
          pendingIdsInQueue.contains(payload['prestamo_id'])) {
        hasPendingParent = true;
        parentTable = 'prestamos_alquiler';
        parentId = payload['prestamo_id'];
      } else if (entry.tabla == 'eventos_servicios' &&
          payload['servicio_id'] != null &&
          pendingIdsInQueue.contains(payload['servicio_id'])) {
        // Caso especial: línea de servicio cuyo servicio (catálogo o ad-hoc) aún no subió.
        hasPendingParent = true;
        parentTable = 'servicios';
        parentId = payload['servicio_id'];
      }

      if (hasPendingParent) {
        debugPrint(
          '  ⏳ Posponiendo ${entry.tabla}/${entry.registroId}: esperando a $parentTable/$parentId',
        );
        continue;
      }

      try {
        await _executeSyncOperation(entry);
        final salio = await SyncQueue.markCompleted(
          entry.id!,
          leidaCon: entry.createdAt,
        );
        debugPrint(
          salio
              ? '  √ ${entry.operacion.name} ${entry.tabla}/${entry.registroId}'
              : '  ↻ ${entry.tabla}/${entry.registroId} cambió mientras subía: '
                  'queda en la cola para subir lo nuevo',
        );
        anySuccess = true;
        _anotarParaElPulso(entry);

        // ACELERACIÓN TURBO: Si acabamos de subir un "padre", notificamos al loop
        // para que re-intente procesar hijos pausados en esta misma vuelta si es posible.
      } catch (e) {
        debugPrint('  ✗ Error sync ${entry.tabla}/${entry.registroId}: $e');

        bool isNonRetryable = _isNonRetryableError(e);

        // Detección de Código 23503 (FK Violation / Huérfamos) -> AUTOCURACIÓN
        if (e is PostgrestException &&
            (e.code == '23503' || e.message.contains('violates'))) {
          isNonRetryable = false;
          debugPrint(
            '  ⏳ Pausa Referencial (${entry.tabla}/${entry.registroId}): Esperando integridad en la nube.',
          );

          // Intentar Autocuración en silencio
          final healed = await _attemptSelfHealing(entry);

          if (healed) {
            await SyncQueue.markPaused(entry.id!, 'ESPERANDO_PADRE: $e');
          } else {
            // Si el padre no existe localmente, es un error referencial insalvable localmente.
            // Incrementa los intentos. Al llegar a 10 se marcará como ERROR_PERMANENTE.
            final isPermanent = entry.intentos >= 9;
            final errorMsg = isPermanent
                ? 'ERROR_PERMANENTE: Padre no encontrado localmente'
                : 'ESPERANDO_PADRE: Padre no encontrado localmente';
            await SyncQueue.markFailed(entry.id!, errorMsg);
          }
          continue;
        }

        // Sacar algo de la cola sin haberlo subido es perder el dato. Sólo se
        // saca cuando el error prueba que YA está en la nube (unique/duplicate).
        // Todo lo demás queda en cuarentena, contado y visible, reintentando.
        if (isNonRetryable) {
          debugPrint(
            '  = ${entry.tabla}/${entry.registroId} ya existía en la nube: '
            'se saca de la cola',
          );
          await SyncQueue.markCompleted(entry.id!, leidaCon: entry.createdAt);
        } else {
          await SyncQueue.markFailed(entry.id!, e.toString());
        }
      }
    }
    return anySuccess;
  }

  /// Intenta sanar la integridad referencial re-encolando registros padre faltantes.
  /// Devuelve true si encontró y re-encoló al menos un padre localmente.
  Future<bool> _attemptSelfHealing(SyncQueueEntry childEntry) async {
    final payload = childEntry.payload;
    final parentDependencies = {
      'evento_id': 'eventos',
      'presupuesto_id': 'presupuestos',
      'cliente_id': 'clientes',
      'contrato_alumno_id': 'contratos_alumnos',
      'servicio_id': 'servicios',
      'prestamo_id': 'prestamos_alquiler',
    };

    final db = await LocalDatabase.instance;
    bool anyParentHealed = false;
    bool hasAnyFkToCheck = false;

    for (final entry in parentDependencies.entries) {
      final fkField = entry.key;
      final parentTable = entry.value;

      final parentId = payload[fkField] as String?;
      if (parentId == null || parentId.isEmpty) continue;

      hasAnyFkToCheck = true;

      // SOPORTE CASCADA: Si es evento_id, también podría estar en 'presupuestos'
      final potentialTables = (fkField == 'evento_id')
          ? ['eventos', 'presupuestos']
          : [parentTable];

      bool parentFound = false;
      for (final table in potentialTables) {
        final parentRows = await db.query(
          table,
          where: 'id = ?',
          whereArgs: [parentId],
        );
        if (parentRows.isNotEmpty) {
          debugPrint(
            '  [Self-Healing] Re-encolando padre $table/$parentId para desbloquear ${childEntry.tabla}',
          );
          await SyncQueue.enqueue(
            tabla: table,
            operacion: SyncOperation.insert,
            registroId: parentId,
            payload: parentRows.first,
          );
          parentFound = true;
          anyParentHealed = true;
          break;
        }
      }

      if (!parentFound) {
        debugPrint(
          '  [Self-Healing] Padre $parentId no encontrado en ${potentialTables.join('/')} localmente.',
        );
      }
    }

    return hasAnyFkToCheck ? anyParentHealed : false;
  }

  /// Valida que todos los campos UUID en el payload tengan formato correcto (36 chars).
  String? _validateUuidFields(Map<String, dynamic> payload) {
    const uuidFields = [
      'id',
      'evento_id',
      'presupuesto_id',
      'cliente_id',
      'servicio_id',
      'contrato_alumno_id',
      'invitado_id',
      'prestamo_id',
    ];
    for (final field in uuidFields) {
      if (payload.containsKey(field)) {
        final val = payload[field];
        if (val is String && val.isNotEmpty && val.length != 36) {
          return field;
        }
      }
    }
    return null;
  }

  /// Ejecuta una operación individual contra Supabase.
  Future<void> _executeSyncOperation(SyncQueueEntry entry) async {
    final payload = _cleanForRemote(entry.tabla, entry.payload);

    // Pre-validación: rechazar cualquier operación con UUID malformado
    final badField = _validateUuidFields(payload);
    if (badField != null) {
      throw Exception(
        'UUID_INVALIDO: El campo "$badField" contiene un valor no-UUID en ${entry.tabla}',
      );
    }

    switch (entry.operacion) {
      case SyncOperation.insert:
        await _supabase.from(entry.tabla).upsert(payload);
        break;
      case SyncOperation.update:
        await _supabase
            .from(entry.tabla)
            .update(payload)
            .eq('id', entry.registroId);
        break;
      case SyncOperation.delete:
        if (entry.registroId.length == 36) {
          await _supabase.from(entry.tabla).delete().eq('id', entry.registroId);
        } else if (entry.tabla == 'eventos_servicios' ||
            entry.tabla == 'presupuesto_servicios') {
          // Legado: eventoId_servicioId
          final parts = entry.registroId.split('_');
          if (parts.length == 2) {
            final parentField = entry.tabla == 'eventos_servicios'
                ? 'evento_id'
                : 'presupuesto_id';
            await _supabase
                .from(entry.tabla)
                .delete()
                .eq(parentField, parts[0])
                .eq('servicio_id', parts[1]);
          }
        } else {
          await _supabase.from(entry.tabla).delete().eq('id', entry.registroId);
        }
        break;
    }
  }

  Future<void> _pullFromCloud() async {
    final db = await LocalDatabase.instance;

    debugPrint('📥 Pull Cloud → Local (En Paralelo)...');

    _tablasConFalloPull.clear();
    await Future.wait([
      _pullTable(db, 'clientes', 'updated_at'),
      _pullTable(db, 'servicios', 'updated_at'),
      _pullTable(db, 'eventos', 'updated_at'),
      _pullTable(db, 'eventos_servicios', 'updated_at', primaryKey: 'id'),
      _pullTable(db, 'presupuestos', 'updated_at'),
      _pullTable(db, 'presupuesto_servicios', 'updated_at', primaryKey: 'id'),
      _pullTable(db, 'transacciones', 'updated_at'),
      _pullTable(db, 'egresos', 'updated_at'),
      _pullTable(db, 'contratos_alumnos', 'updated_at'),
      _pullTable(db, 'notas_operativas_contrato', 'updated_at'),
      _pullTable(db, 'pagos_contrato_alumno', 'updated_at'),
      _pullTable(db, 'invitados', 'updated_at'),
      _pullTable(db, 'solicitudes_cotizacion', 'updated_at'),
      _pullTable(db, 'prestamos_alquiler', 'updated_at'),
      _pullTable(db, 'prestamo_alquiler_lineas', 'updated_at'),
      _pullTable(db, 'pagos_prestamo_alquiler', 'updated_at'),
      _pullTable(db, 'calculos_rentabilidad', 'updated_at'),
      _pullTable(db, 'obligaciones_pago', 'updated_at'),
      _pullTable(db, 'caja_fuerte_movimientos', 'updated_at'),
      _pullTable(db, 'compromisos_personal', 'updated_at'),
      _pullTable(db, 'rentabilidad_config', 'updated_at'),
      _pullTable(db, 'cierre_caja_guia_movimientos', 'updated_at'),
      _pullTable(db, 'cierre_caja_anotaciones', 'updated_at'),
      _pullTable(db, 'operadores_caja', 'updated_at'),
      _pullTable(db, 'sesiones_caja', 'updated_at'),
      _pullTable(db, 'sillas_reparto', 'updated_at'),
      _pullTable(db, 'entradas_retiro', 'updated_at'),
      _pullTable(db, 'sorteos_mesas', 'updated_at'),
      _pullTable(db, 'planos_evento', 'updated_at'),
      _pullTable(db, 'mesas_movimientos', 'updated_at'),
      _pullTable(db, 'predios', 'updated_at'),
    ]);

    // Lo borrado en otra PC, antes de la mora: la mora se rehace desde los
    // pagos, y con un pago borrado adentro saldría mal y subiría.
    await _reconcileDeletes();
    _moraRevisadaEnEstaSesion = true;
    await revisarMora();

    if (_tablasConFalloPull.isNotEmpty) {
      final fallidas = _tablasConFalloPull.toList()..sort();
      _lastError = 'No bajaron: ${fallidas.join(", ")}';
      debugPrint('📥 Pull incompleto — $_lastError');
    } else {
      debugPrint('📥 Pull completado');
    }
  }

  /// `id → updated_at` local de las filas que acaban de bajar.
  ///
  /// Solo sirve para decidir si avisar (ver [filaEsNovedad]); por eso nunca
  /// lanza: si la consulta falla devuelve `null` y todo cuenta como novedad, que
  /// en el peor caso es un refresco de pantalla de más, no un pull caído.
  Future<Map<String, Object?>?> _versionesLocales(
    Database db,
    String table,
    String dateColumn,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      final ids = [
        for (final r in rows)
          if (r['id'] is String) r['id'] as String,
      ];
      final out = <String, Object?>{};
      const lote = 500;
      for (var i = 0; i < ids.length; i += lote) {
        final parte = ids.sublist(
          i,
          i + lote > ids.length ? ids.length : i + lote,
        );
        final filas = await db.query(
          table,
          columns: ['id', dateColumn],
          where: 'id IN (${List.filled(parte.length, '?').join(',')})',
          whereArgs: parte,
        );
        for (final f in filas) {
          out[f['id'] as String] = f[dateColumn];
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Descarga y upsert de una tabla. Soporta pull incremental mediante _sync_meta.
  ///
  /// Devuelve si bajó bien (también si no había nada nuevo). Si falló, además
  /// la anota en [_tablasConFalloPull].
  Future<bool> _pullTable(
    Database db,
    String table,
    String? orderBy, {
    String primaryKey = 'id',
  }) async {
    try {
      final String claveMeta = 'last_pull_$table';
      // Consultar última fecha de sincronización exitosa
      final metaRows = await db.query(
        '_sync_meta',
        where: 'clave = ?',
        whereArgs: [claveMeta],
      );
      final String? lastSyncStr = metaRows.isNotEmpty
          ? metaRows.first['valor'] as String
          : null;

      final String? dateColumn = _incrementalColumns[table];
      dynamic query = _supabase.from(table).select();

      // El reloj de la PC ya no participa del marcador: la marca sale del
      // `updated_at` más alto que devuelva esta consulta (ver `marcaDeLoBajado`,
      // más abajo). Por eso acá no se toma ninguna hora local.

      if (lastSyncStr != null && dateColumn != null) {
        // Pull Incremental: traer solo lo nuevo/modificado
        query = query.gt(dateColumn, lastSyncStr);
        debugPrint(
          '  📥 $table: Solicitando cambios incremental desde $lastSyncStr (usando $dateColumn)...',
        );
      } else {
        debugPrint('  📥 $table: Solicitando pull completo...');
      }

      if (_tablasFechaCorteCierre.contains(table)) {
        query = query.gte('fecha', kCierreCajaSyncFechaCorte);
      }

      if (orderBy != null) {
        query = query.order(orderBy, ascending: false);
      }

      // Paginación: Supabase devuelve máx. 1000 filas por request.
      // Iteramos en páginas hasta agotar los registros disponibles.
      const int kPageSize = 1000;
      final allData = <Map<String, dynamic>>[];
      int fromIdx = 0;
      while (true) {
        final List<dynamic> page = await query.range(
          fromIdx,
          fromIdx + kPageSize - 1,
        );
        final pageRows = page.cast<Map<String, dynamic>>();
        allData.addAll(pageRows);
        if (pageRows.length < kPageSize) break;
        fromIdx += kPageSize;
      }
      final rows = allData;

      if (rows.isEmpty) {
        // El marcador se queda donde estaba. Antes se lo empujaba a "ahora" con
        // el reloj de la PC, que es justo lo que no hay que hacer: no bajó nada,
        // así que no hay nada nuevo que prometer, y adelantarlo puede dejar del
        // otro lado del filtro a las filas escritas en la diferencia entre los
        // dos relojes. No mover nada no cuesta un request de más: la próxima
        // pasada pide el mismo rango y vuelve a venir vacía.
        return true;
      }

      // No pisar registros con cambios locales pendientes de subir.
      final pendingRows = await db.query(
        '_sync_queue',
        columns: ['registro_id'],
        where: 'tabla = ?',
        whereArgs: [table],
      );
      final pendingIds = pendingRows
          .map((r) => r['registro_id'] as String)
          .toSet();

      // Qué versión de cada fila hay acá, para avisar solo si algo cambió.
      final versionesLocales = dateColumn == null
          ? null
          : await _versionesLocales(db, table, dateColumn, rows);
      var novedades = 0;

      const fkFields = [
        'evento_id',
        'cliente_id',
        'contrato_alumno_id',
        'servicio_id',
        'invitado_id',
        'prestamo_id',
      ];

      Map<String, double?>? preservedBonifPctByEventoId;
      // El vínculo al presupuesto se rellena hacia atrás en la migración v69,
      // local en cada PC. Si la nube todavía no lo tiene (la migración de
      // Supabase se corre a mano), un pull lo pisaría con null y el evento
      // volvería a quedar huérfano. Se conserva el local cuando la nube no trae.
      Map<String, String?>? preservedPresupuestoIdByEventoId;
      if (table == 'eventos') {
        final localPctRows = await db.query(
          'eventos',
          columns: ['id', 'bonificacion_global_pct', 'presupuesto_id'],
        );
        preservedBonifPctByEventoId = {
          for (final r in localPctRows)
            r['id'] as String: r['bonificacion_global_pct'] != null
                ? (r['bonificacion_global_pct'] as num).toDouble()
                : null,
        };
        preservedPresupuestoIdByEventoId = {
          for (final r in localPctRows)
            r['id'] as String: (r['presupuesto_id'] as String?)?.trim(),
        };
      }

      Map<String, MoraLocalDelContrato>? preservedContratoMoraLocal;
      if (table == 'contratos_alumnos') {
        final localMoraRows = await db.query(
          'contratos_alumnos',
          columns: [
            'id',
            'mora_exenta_hasta',
            'mora_fecha_referencia',
            'mora_exencion_reinicia',
            'mora_tracked_ajuste',
          ],
        );
        preservedContratoMoraLocal = {
          for (final r in localMoraRows)
            r['id'] as String: MoraLocalDelContrato.deFila(r),
        };
      }
      // Ajustes de la mora que esta PC tenía y que la nube trae en 0: quedan
      // escritos en `revision_mora.txt` (ver [ajusteQueSeVa]).
      final ajustesQueSeFueron = <String>[];

      final batch = db.batch();
      int skipped = 0;

      // Fila más vieja que bajó de la nube y NO se pudo escribir por tener un
      // cambio local sin subir. El marcador de esta tanda no puede pasarla.
      //
      // Sin esto se pierden datos en silencio: el pull pide
      // `updated_at > marcador`, así que una fila salteada mientras el marcador
      // avanza queda del otro lado y no se vuelve a pedir nunca. Le pegaba justo
      // a la fila más caliente —la que dos personas tocaron a la vez—: el
      // operador cobraba un contrato, el jefe lo modificaba, el pull bajaba la
      // versión del jefe, la salteaba para no pisar el cobro, y movía el
      // marcador igual. Al vaciarse la cola la modificación ya estaba atrás y
      // la otra PC no la veía más.
      //
      // Solo retiene este caso. Un id o una FK malformados también saltean, pero
      // arreglarlos en la nube les bumpea el `updated_at` y vuelven a bajar
      // solos; retener por ellos clavaría el marcador para siempre y la tabla se
      // re-descargaría entera cada 10 segundos. El corte de fecha de cierre es
      // deliberado y permanente, así que tampoco cuenta.
      DateTime? marcaPendienteMasVieja;
      void retenerMarcador(Map<String, dynamic> row) {
        if (dateColumn == null) return;
        final crudo = row[dateColumn]?.toString();
        if (crudo == null || crudo.isEmpty) return;
        final fecha = DateTime.tryParse(crudo)?.toUtc();
        if (fecha == null) return;
        if (marcaPendienteMasVieja == null ||
            fecha.isBefore(marcaPendienteMasVieja!)) {
          marcaPendienteMasVieja = fecha;
        }
      }

      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        if (_tablasFechaCorteCierre.contains(table)) {
          final f = row['fecha']?.toString() ?? '';
          if (!cierreCajaFechaElegibleSync(f)) {
            skipped++;
            continue;
          }
        }
        final id = row['id'] as String?;
        if (id != null && pendingIds.contains(id)) {
          skipped++;
          retenerMarcador(row);
          continue;
        }
        if (id != null && id.length != 36) {
          if (table != 'eventos_servicios' &&
              table != 'presupuesto_servicios') {
            skipped++;
            continue;
          }
        }
        // El plano de una fiesta lleva un id fijo. Uno con otro id (cargado a
        // mano en la nube) pisaría el de esta PC por el UNIQUE de `evento_id`,
        // y después el sorteo de esa fiesta no podría guardar: se saltea.
        if (table == 'planos_evento' && !planoTraeIdFijo(row)) {
          skipped++;
          continue;
        }

        bool hasBadFk = false;
        for (final fk in fkFields) {
          final fkVal = row[fk] as String?;
          if (fkVal != null && fkVal.isNotEmpty && fkVal.length != 36) {
            hasBadFk = true;
            skipped++;
            break;
          }
        }
        if (hasBadFk) continue;

        if (versionesLocales == null ||
            filaEsNovedad(
              existeLocal: id != null && versionesLocales.containsKey(id),
              versionLocal: versionesLocales[id],
              versionNube: row[dateColumn],
            )) {
          novedades++;
        }

        var cleanRow = _cleanForSqlite(table, row);
        if (table == 'eventos_servicios' || table == 'presupuesto_servicios') {
          final insertMap = Map<String, dynamic>.from(cleanRow);
          final rawId = (insertMap['id'] as String?)?.trim() ?? '';
          if (rawId.length != 36) {
            final parentKey = table == 'eventos_servicios'
                ? 'evento_id'
                : 'presupuesto_id';
            final pid = (insertMap[parentKey] as String?)?.trim() ?? '';
            final sid = (insertMap['servicio_id'] as String?)?.trim() ?? '';
            if (pid.isEmpty || sid.isEmpty) {
              skipped++;
              continue;
            }
            final ctx = table == 'eventos_servicios' ? 'es' : 'ps';
            insertMap['id'] = UuidUtils.lineaIdDeterministic(
              ctx,
              pid,
              sid,
              index,
            );
          }
          cleanRow = insertMap;
        }
        if (table == 'eventos' && preservedBonifPctByEventoId != null) {
          final eid = cleanRow['id'] as String;
          final cloudPctRaw = row['bonificacion_global_pct'];
          final insertRow = Map<String, dynamic>.from(cleanRow);
          if (cloudPctRaw != null) {
            insertRow['bonificacion_global_pct'] = double.tryParse(
              cloudPctRaw.toString(),
            );
          } else {
            final preserved = preservedBonifPctByEventoId[eid];
            if (preserved != null) {
              insertRow['bonificacion_global_pct'] = preserved;
            }
          }
          final cloudPresupuestoId =
              (row['presupuesto_id'] as String?)?.trim();
          if (cloudPresupuestoId == null || cloudPresupuestoId.isEmpty) {
            final preservado = preservedPresupuestoIdByEventoId?[eid];
            if (preservado != null && preservado.isNotEmpty) {
              insertRow['presupuesto_id'] = preservado;
            }
          }
          batch.insert(
            table,
            insertRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else if (table == 'contratos_alumnos' &&
            preservedContratoMoraLocal != null) {
          final cid = cleanRow['id'] as String;
          final preserved = preservedContratoMoraLocal[cid];
          // Qué manda la nube y qué conserva la PC: ver [contratoAlBajar].
          final insertRow = contratoAlBajar(cleanRow, preserved);
          final seVa = ajusteQueSeVa(cleanRow, preserved);
          if (seVa != null) {
            ajustesQueSeFueron.add(renglonAjusteQueSeVa(
              (cleanRow['nombre_alumno'] as String?) ?? cid,
              seVa,
            ));
          }
          batch.insert(
            table,
            insertRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          batch.insert(
            table,
            cleanRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
      if (novedades > 0) _anotarCambioBajado(table);
      if (ajustesQueSeFueron.isNotEmpty) {
        try {
          await RevisionMoraConstancia.anotar(
            ajustesQueSeFueron,
            queHizo: queHizoAjustesQueSeFueron,
          );
        } catch (_) {
          // La constancia es un aviso, no puede frenar la bajada.
        }
      }

      // Guardar última marca de tiempo de sincronización exitosa.
      //
      // Sale del `updated_at` más alto que trajo esta bajada, no del reloj de la
      // PC: es el mismo reloj contra el que después se compara. Si ninguna fila
      // trajo fecha legible, el marcador no se toca.
      //
      // Y si algo quedó sin escribirse por tener un cambio local sin subir, el
      // marcador se queda un milisegundo antes de esa fila: el próximo pull la
      // vuelve a pedir en vez de saltearla para siempre. Cuesta re-bajar unas
      // pocas filas por ciclo y paga no perder ninguna.
      if (dateColumn != null) {
        final marcaDelServidor = marcaDeLoBajado(rows, dateColumn);
        if (marcaDelServidor == null) {
          debugPrint(
            '  ⏸️ $table: ninguna fila trajo $dateColumn legible — marcador sin mover',
          );
        } else {
          final marca = marcadorPullSeguro(
            ahora: marcaDelServidor,
            pendienteMasVieja: marcaPendienteMasVieja,
          );
          if (marcaPendienteMasVieja != null) {
            debugPrint(
              '  ⏸️ $table: marcador retenido en $marca — $skipped fila(s) con cambios locales sin subir',
            );
          }
          await db.insert('_sync_meta', {
            'clave': claveMeta,
            'valor': marca,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // Podar duplicados en las tablas de líneas (eventos_servicios /
      // presupuesto_servicios). La migración v35 reasignó UUIDs locales, así que
      // las filas de la nube llegan con su UUID original y conviven con las que
      // se generaron acá → duplicados.
      //
      // Solo se poda cuando la bajada fue COMPLETA, que es cuando `rows` es toda
      // la tabla y "lo que no vino" de verdad no existe. `filasAPodar` es la
      // autoridad sobre eso; el `fotoCompleta` de este `if` solo evita hacer dos
      // consultas al pedo en cada ciclo incremental.
      final fotoCompleta = lastSyncStr == null;
      if (fotoCompleta &&
          (table == 'eventos_servicios' || table == 'presupuesto_servicios')) {
        final cloudIds = <String>{};
        for (var i = 0; i < rows.length; i++) {
          final rawId = (rows[i]['id'] as String?)?.trim() ?? '';
          if (rawId.length == 36) {
            cloudIds.add(rawId);
          } else {
            final parentKey = table == 'eventos_servicios'
                ? 'evento_id'
                : 'presupuesto_id';
            final pid = (rows[i][parentKey] as String?)?.trim() ?? '';
            final sid = (rows[i]['servicio_id'] as String?)?.trim() ?? '';
            if (pid.isNotEmpty && sid.isNotEmpty) {
              final ctx = table == 'eventos_servicios' ? 'es' : 'ps';
              cloudIds.add(UuidUtils.lineaIdDeterministic(ctx, pid, sid, i));
            }
          }
        }

        final pendingRows = await db.query(
          '_sync_queue',
          columns: ['registro_id'],
          where: "tabla = ?",
          whereArgs: [table],
        );
        final pendingIds = pendingRows
            .map((r) => r['registro_id'] as String)
            .toSet();

        final localRows = await db.query(table, columns: ['id']);
        final localIds = localRows
            .map((r) => (r['id'] as String?) ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        final aPodar = filasAPodar(
          fotoCompleta: fotoCompleta,
          idsLocales: localIds,
          idsEnLaNube: cloudIds,
          idsPendientes: pendingIds,
        );
        for (final id in aPodar) {
          await db.delete(table, where: 'id = ?', whereArgs: [id]);
        }
        if (aPodar.isNotEmpty) {
          debugPrint(
            '  🧹 $table: ${aPodar.length} filas huérfanas eliminadas (dedup post-migración)',
          );
        }
      }

      final stored = rows.length - skipped;
      debugPrint(
        '  📥 $table: $stored registros${skipped > 0 ? " ($skipped corruptos omitidos)" : ""}',
      );
      return true;
    } catch (e) {
      // No se relanza: el watermark no avanzó, así que el próximo ciclo
      // reintenta el mismo rango y nada se pierde. Pero se anota, para que
      // quien llamó pueda decir que el pull quedó incompleto en vez de
      // informar "sincronizado".
      _tablasConFalloPull.add(table);
      debugPrint('  ⚠️ Error pull $table: $e');
      return false;
    }
  }

  /// Las tablas que Recepción necesita de un evento masivo: el evento, los
  /// alumnos, cómo repartió cada familia sus sillas y el plano.
  static const tablasDeLaPuerta = [
    'eventos',
    'contratos_alumnos',
    'sillas_reparto',
    'planos_evento',
  ];

  /// Baja ya las [tablasDeLaPuerta], para "Lista para trabajar sin internet"
  /// (sección 5 de la 6.0.0). Devuelve si bajaron todas.
  ///
  /// No espera al ciclo ni cambia el estado del motor: si el ciclo está
  /// bajando las mismas tablas a la vez no pasa nada, porque escribir dos
  /// veces la misma fila deja lo mismo.
  Future<bool> bajarParaLaPuerta() async {
    if (_connectivity.currentStatus == AppConnectivity.offline) return false;
    try {
      final db = await LocalDatabase.instance;
      final bien = await Future.wait([
        for (final tabla in tablasDeLaPuerta)
          _pullTable(db, tabla, 'updated_at'),
      ]);
      return bien.every((b) => b);
    } catch (e) {
      debugPrint('⚠️ No bajaron las tablas de la puerta: $e');
      return false;
    }
  }

  /// Filtra payload antes de subir: solo columnas de nube, sin campos solo SQLite.
  ///
  /// Los cuatro campos de mora operativa (`mora_exenta_hasta`,
  /// `mora_exencion_reinicia`, `mora_cobrada_offset`, `mora_fecha_referencia`)
  /// se borraban acá porque no existían en Supabase. Eso hacía que el perdón de
  /// mora se guardara bien en la PC del jefe y nunca llegara a la de operarios:
  /// subía `mora_tracked_ajuste` —la única de las cinco que sí existía— y la
  /// exención, que es la que apaga el calendario, se perdía en silencio.
  /// Ya están en la nube, así que viajan como cualquier otra columna.
  Map<String, dynamic> _cleanForRemote(String table, Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    copy.remove('line_kind');

    final cleaned = _cleanForSqlite(table, copy);

    if (table == 'contratos_alumnos') {
      if (cleaned.containsKey('nombres_acompanantes')) {
        cleaned['nombres_acompanantes'] = ContratoAlumno.acompanantesForRemote(
          cleaned['nombres_acompanantes'],
        );
      }
      if (cleaned.containsKey('contrato_firmado')) {
        final v = cleaned['contrato_firmado'];
        if (v is int) cleaned['contrato_firmado'] = v != 0;
      }
    }

    return cleaned;
  }

  /// Limpia un mapa de datos para que solo contenga columnas de la tabla SQLite.
  Map<String, dynamic> _cleanForSqlite(String table, Map<String, dynamic> row) {
    const tableColumns = {
      'clientes': [
        'id',
        'nombre_completo',
        'telefono',
        'email',
        'is_archived',
        'created_at',
        'updated_at',
      ],
      'eventos': [
        'id',
        'cliente_id',
        'tipo',
        'fecha_evento',
        'cantidad_cuotas',
        'modalidad',
        'estado',
        'pin_operador',
        'observaciones',
        'titulo_festejado',
        'nombre_festejado',
        'encabezado_evento',
        'bonificacion_global_pct',
        'presupuesto_id',
        'created_at',
        'updated_at',
      ],
      'servicios': [
        'id',
        'nombre',
        'categoria',
        'costo_base',
        'margen_ganancia',
        'costo_interno',
        'evento_id',
        'is_archived',
        'updated_at',
      ],
      'eventos_servicios': [
        'id',
        'evento_id',
        'servicio_id',
        'precio_final_acordado',
        'cantidad',
        'grupo',
        'detalle_servicio',
        'combo_orden',
        'es_extra',
        'updated_at',
      ],
      'presupuestos': [
        'id',
        'cliente_id',
        'tipo_evento',
        'lugar',
        'detalle_anclaje',
        'fecha_vencimiento',
        'fecha_evento',
        'estado',
        'instagram',
        'telefono',
        'vendedor_nombre',
        'titulo_festejado',
        'nombre_festejado',
        'encabezado_evento',
        'notificado_vencimiento',
        'created_at',
        'updated_at',
      ],
      'presupuesto_servicios': [
        'id',
        'presupuesto_id',
        'servicio_id',
        'precio_final',
        'cantidad',
        'detalle_servicio',
        'grupo',
        'combo_orden',
        'es_extra',
        'updated_at',
      ],
      'transacciones': [
        'id',
        'evento_id',
        'monto',
        'concepto',
        'fecha_pago',
        'created_by',
        'medio_pago',
        'anulado',
        'motivo_anulacion',
        'fecha_anulacion',
        'updated_at',
      ],
      'egresos': [
        'id',
        'evento_id',
        'monto',
        'proveedor',
        'categoria',
        'fecha',
        'created_by',
        'medio_pago',
        'sesion_caja_id',
        // Si estas dos faltaran acá, el pull las descartaría en silencio: el
        // pago seguiría existiendo pero dejaría de descontar de su cuenta, y
        // uno que salió del bolsillo volvería a restar del negocio.
        'compromiso_id',
        'origen_fondos',
        'updated_at',
      ],
      'compromisos_personal': [
        'id',
        'persona',
        'tipo',
        'concepto',
        'monto_total',
        'fecha_inicio',
        'estado',
        'nota',
        'created_at',
        'updated_at',
      ],
      'contratos_alumnos': [
        'id',
        'evento_id',
        'nombre_alumno',
        'institucion',
        'cantidad_acompanantes',
        'monto_total_pactado',
        'saldo_deudor',
        'cuotas_pagadas',
        'total_cuotas',
        'nombres_acompanantes',
        'dia_vencimiento_mensual',
        'mesa_extra_precio',
        'mesa_extra_cuotas',
        'mesa_extra_cuotas_pagadas',
        'mesa_extra_cantidad',
        'mesas_extra_estado',
        'sillas_extra_cantidad',
        'sillas_extra_cuotas',
        'sillas_extra_precio_total',
        'sillas_extra_cuotas_pagadas',
        'mesa_extra_pagado',
        'sillas_extra_pagado',
        'curso_division',
        'musica_elegida',
        'numero_mesa',
        'telefono',
        'created_at',
        'contrato_firmado',
        'mora_pendiente_tracked',
        'mora_cobrada_offset',
        'mora_fecha_referencia',
        'mora_exenta_hasta',
        'mora_exencion_reinicia',
        'mora_tracked_ajuste',
        'updated_at',
      ],
      'notas_operativas_contrato': [
        'id',
        'contrato_alumno_id',
        'texto',
        'resuelto',
        'created_at',
        'updated_at',
      ],
      'pagos_contrato_alumno': [
        'id',
        'contrato_alumno_id',
        'monto',
        'monto_gross',
        'descuento_porcentaje',
        'concepto',
        'fecha_pago',
        'created_at',
        'medio_pago',
        'anulado',
        'motivo_anulacion',
        'fecha_anulacion',
        'sesion_caja_id',
        'updated_at',
      ],
      'operadores_caja': [
        'id',
        'nombre',
        'pin',
        'activo',
        'created_at',
        'updated_at',
      ],
      'sesiones_caja': [
        'id',
        'operador_id',
        'abierta_at',
        'cerrada_at',
        'cambio_inicial',
        'nota_apertura',
        'etiqueta',
        'arqueo_cierre',
        'nota_cierre',
        'device_id',
        'last_heartbeat',
        'created_at',
        'updated_at',
      ],
      'invitados': [
        'id',
        'evento_id',
        'nombre_completo',
        'dni',
        'numero_mesa',
        'estado_ingreso',
        'intentos_fallidos',
        'updated_at',
        'created_at',
      ],
      'solicitudes_cotizacion': [
        'id',
        'cliente_nombre',
        'cliente_celular',
        'servicios_seleccionados',
        'estado',
        'updated_at',
      ],
      'prestamos_alquiler': [
        'id',
        'cliente_id',
        'fecha_inicio',
        'fecha_fin',
        'aplica_iva',
        'alicuota_iva',
        'subtotal_neto',
        'monto_iva',
        'total',
        'texto_redaccion',
        'texto_disclaimer',
        'visible_listado',
        'created_at',
        'updated_at',
      ],
      'prestamo_alquiler_lineas': [
        'id',
        'prestamo_id',
        'descripcion',
        'cantidad',
        'precio_unitario',
        'linea_total',
        'orden',
        'updated_at',
      ],
      'pagos_prestamo_alquiler': [
        'id',
        'prestamo_id',
        'monto',
        'concepto',
        'fecha_pago',
        'created_at',
        'medio_pago',
        'anulado',
        'motivo_anulacion',
        'fecha_anulacion',
        'updated_at',
      ],
      'calculos_rentabilidad': [
        'id',
        'evento_id',
        'presupuesto_id',
        'precio_venta',
        'honorario_adrian_monto',
        'honorario_adrian_pct',
        'honorario_modo',
        'costos_variables_json',
        'costos_fijos_json',
        'resultado',
        'notas',
        'created_at',
        'created_by',
        'updated_at',
      ],
      'obligaciones_pago': [
        'id',
        'titulo',
        'tipo_obligacion',
        'fecha_vencimiento',
        'monto_estimado',
        'estado',
        'fecha_pago',
        'created_at',
        'updated_at',
      ],
      'caja_fuerte_movimientos': [
        'id',
        'tipo',
        'monto',
        'nota',
        'created_at',
        'updated_at',
      ],
      'cierre_caja_guia_movimientos': [
        'id',
        'fecha',
        'tipo',
        'monto',
        'saldo_antes',
        'saldo_despues',
        'nota',
        'sesion_caja_id',
        'fecha_mov',
        'created_at',
        'updated_at',
      ],
      'cierre_caja_anotaciones': [
        'id',
        'fecha',
        'turno',
        'sesion_caja_id',
        'texto',
        'created_at',
        'updated_at',
      ],
      'rentabilidad_config': [
        'id',
        'alquiler_local',
        'sueldos_admin',
        'servicios_oficina',
        'impuestos_fijos',
        'honorario_adrian_default_monto',
        'honorario_adrian_default_pct',
        'honorario_modo_default',
        'eventos_estimados_mes',
        'updated_at',
        'updated_by',
      ],
      // Las tres de la v72. Todas sus columnas tienen que estar acá: la bajada
      // escribe con INSERT OR REPLACE, y una que falte vuelve a su default en
      // silencio en cada pull (ver el comentario de `egresos`).
      'sillas_reparto': [
        'id',
        'contrato_alumno_id',
        'sillas_principal',
        'sillas_extra',
        'mesas',
        'hecho_por',
        'created_at',
        'updated_at',
      ],
      'entradas_retiro': [
        'id',
        'contrato_alumno_id',
        'estado',
        'vip',
        'generales',
        'tramos',
        'menores_10',
        'parentesco',
        'retiro_nombre',
        'otra_persona_motivo',
        'autorizacion_firmada',
        'escribio_en_planilla',
        'entregado_por',
        'entregado_at',
        'anulado_por',
        'anulado_at',
        'anulado_motivo',
        'created_at',
        'updated_at',
      ],
      'sorteos_mesas': [
        'id',
        'evento_id',
        'tipo',
        'resultado',
        'alumnos',
        'hecho_por',
        'created_at',
        'updated_at',
      ],
      // v73. Todas las columnas, por la misma razón que las de la v72.
      'planos_evento': [
        'id',
        'evento_id',
        'armado',
        'armado_json',
        'estilo',
        'modo_sorteo',
        'config',
        'hecho_por',
        'created_at',
        'updated_at',
      ],
      'mesas_movimientos': [
        'id',
        'evento_id',
        'tipo',
        'antes',
        'despues',
        'motivo',
        'deshace_id',
        'avisos',
        'hecho_por',
        'created_at',
        'updated_at',
      ],
      // v74. Todas las columnas, por la misma razón que las de la v72.
      'predios': [
        'id',
        'nombre',
        'armado_json',
        'medidas',
        'borrado_at',
        'hecho_por',
        'created_at',
        'updated_at',
      ],
    };

    final validCols = tableColumns[table];
    if (validCols == null) return row;

    final clean = <String, dynamic>{};
    for (final col in validCols) {
      if (row.containsKey(col)) {
        clean[col] = valorParaSqlite(row[col]);
      }
    }

    if (table == 'contratos_alumnos' &&
        row.containsKey('cantidad_acompañantes')) {
      clean['cantidad_acompanantes'] = row['cantidad_acompañantes'];
    }
    if (table == 'contratos_alumnos' &&
        row.containsKey('nombres_acompañantes')) {
      final val = row['nombres_acompañantes'];
      clean['nombres_acompanantes'] = val is List
          ? jsonEncode(val)
          : (val ?? '[]');
    }

    return clean;
  }

  /// Las tablas en las que se revisa qué se borró en otra PC: **todas las que
  /// se pueden borrar a mano**.
  ///
  /// Hasta la 6.1.0 eran solo las seis primeras, con la idea de que "las hijas
  /// caen por cascada". Eso vale cuando se borra el padre, no cuando se borra
  /// una hija suelta con el padre vivo. Un pago se borra solo, con su alumno
  /// vivo, y entonces no lo alcanzaba nada: el 19-oct-2026 el jefe borró un
  /// pago de $60.000 de DE CARLO, MICAELA ESTEFANIA, la PC del operario se lo
  /// quedó y, al cobrarle, contó los dos pagos y le pisó el saldo a la nube
  /// ($176.100 en vez de $236.100). Lo mismo dejaba renglones de presupuesto
  /// borrados en la otra PC, que se veía más caro.
  ///
  /// Van primero los padres: si se fue uno, sus hijas se van con él y quedan
  /// anotadas con su nombre.
  static const List<String> _tablasAReconciliar = [
    'clientes',
    'eventos',
    'presupuestos',
    'contratos_alumnos',
    'prestamos_alquiler',
    'servicios',
    'pagos_contrato_alumno',
    'presupuesto_servicios',
    'eventos_servicios',
    'egresos',
    'transacciones',
    'notas_operativas_contrato',
    'obligaciones_pago',
    'compromisos_personal',
    'cierre_caja_anotaciones',
    'solicitudes_cotizacion',
    'prestamo_alquiler_lineas',
    'pagos_prestamo_alquiler',
    'operadores_caja',
    'sesiones_caja',
  ];

  /// Las tablas que se bajan y **no** se revisan, con el motivo. Una tabla
  /// nueva que se baje tiene que entrar en una lista o en la otra:
  /// `test/borrados_de_otra_pc_test.dart` falla si no.
  static const Map<String, String> _tablasSinRevisarBorrados = {
    'invitados':
        'la lista de la puerta tiene su propio camino: el tótem por Realtime, '
            'el salón la arma o la vacía (PuertaAlDia)',
    'calculos_rentabilidad': 'no se borra a mano',
    'caja_fuerte_movimientos': 'no se borra a mano',
    'rentabilidad_config': 'no se borra a mano',
    'cierre_caja_guia_movimientos': 'no se borra a mano',
    'sillas_reparto': 'una fila por alumno, con id fijo: no se borra a mano',
    'entradas_retiro': 'una fila por alumno, con id fijo: no se borra a mano',
    'sorteos_mesas': 'solo se agregan renglones: deshacer es otro renglón',
    'mesas_movimientos': 'solo se agregan renglones',
    'planos_evento': 'una fila por fiesta, con id fijo: no se borra a mano',
    'predios': 'borrar le pone borrado_at: la fila no se saca',
  };

  /// Para los tests: las tablas que se revisan.
  @visibleForTesting
  static List<String> get tablasQueSeRevisan => _tablasAReconciliar;

  /// Para los tests: las que no, con su motivo.
  @visibleForTesting
  static Map<String, String> get tablasSinRevisarBorrados =>
      _tablasSinRevisarBorrados;

  /// Para los tests: todas las que se bajan.
  @visibleForTesting
  static Set<String> get tablasQueSeBajan => _incrementalColumns.keys.toSet();

  /// Para los tests: la revisión de cada 10 minutos.
  @visibleForTesting
  Future<void> revisarLoBorradoEnOtraPc() => _reconcileDeletes();

  /// Para los tests: la cuenta de cada ciclo de 10 s.
  @visibleForTesting
  Future<void> contarParaVerBorrados() async =>
      _contarParaVerBorrados(await LocalDatabase.instance);

  /// Para los tests: un pulso que llega de otra PC.
  @visibleForTesting
  void recibirPulso(Map<String, dynamic> mensaje) => _alRecibirPulso(mensaje);

  /// Trae **todos** los ids de una tabla de la nube, o `null` si no pudo.
  ///
  /// Devolver `null` en vez de una lista incompleta es el punto entero de esta
  /// función. La versión anterior hacía `select('id')` sin paginar: PostgREST
  /// corta en 1000 filas por defecto y devuelve las primeras mil **sin avisar**.
  /// El llamador las tomaba por "todo lo que hay en la nube" y borraba el resto
  /// de la base local. `contratos_alumnos` iba en 643 filas y sube con cada
  /// alumno: era una bomba con fecha.
  ///
  /// Por eso se pagina y además se contrasta contra un `count` exacto. Si los
  /// números no cierran —una fila que entró entre la primera página y la
  /// última, un error de red a mitad de camino—, no hay foto completa y no se
  /// borra nada. La próxima pasada lo intenta de nuevo, diez minutos después.
  Future<Set<String>?> _idsCompletosDeLaNube(String tabla) async {
    const tamanioPagina = 1000;
    try {
      final ids = <String>{};
      var desde = 0;
      while (true) {
        final pagina = await _supabase
            .from(tabla)
            .select('id')
            .range(desde, desde + tamanioPagina - 1);
        final filas = (pagina as List).cast<Map<String, dynamic>>();
        for (final f in filas) {
          final id = (f['id'] as String?)?.trim() ?? '';
          if (id.isNotEmpty) ids.add(id);
        }
        if (filas.length < tamanioPagina) break;
        desde += tamanioPagina;
      }

      // El contraste. `CountOption.exact` cuesta un scan, pero esto corre una
      // vez cada diez minutos sobre seis tablas y es lo único que separa "la
      // nube no tiene esta fila" de "no llegué a leerla".
      final conteo = await _supabase
          .from(tabla)
          .count(CountOption.exact);

      if (ids.length != conteo) {
        debugPrint(
          '  ⏸️ $tabla: traje ${ids.length} ids y la nube dice $conteo — '
          'no es una foto completa, no se borra nada',
        );
        return null;
      }
      return ids;
    } catch (e) {
      debugPrint('  ⏸️ $tabla: no pude leer la nube ($e) — no se borra nada');
      return null;
    }
  }

  /// Propaga a esta PC los borrados que se hicieron en la otra.
  ///
  /// Es la red de seguridad del pulso: cubre a la máquina que estaba **apagada**
  /// cuando alguien borró algo, que es el único caso que un aviso en vivo no
  /// puede alcanzar.
  ///
  /// Cumple la segunda mitad de la regla —comparar contra una foto completa **y
  /// contada**—, y por eso todo el cuidado está en [_idsCompletosDeLaNube]: sin
  /// esa certeza, `filasAPodar` recibe `fotoCompleta: false` y no borra nada.
  Future<void> _reconcileDeletes({
    CaminoDelBorrado camino = CaminoDelBorrado.revision,
  }) async {
    final db = await LocalDatabase.instance;

    debugPrint('🔄 Reconciliación de borrados remotos...');

    for (final table in _tablasAReconciliar) {
      await _revisarBorradosDe(db, table, camino: camino);
    }
  }

  /// La revisión de una tabla: saca de esta PC lo que en la nube ya no está.
  Future<void> _revisarBorradosDe(
    Database db,
    String table, {
    required CaminoDelBorrado camino,
  }) async {
    try {
      // **Primero lo de esta PC y lo que espera subir; recién después la
      // nube.** Al revés —como fue hasta la 6.1.0— un cobro que se carga y
      // sube mientras se leen las páginas de la nube no está en la foto (se
      // leyó antes) ni en la cola (ya salió), y se tomaba por borrado. Así, lo
      // que estaba en la cola al empezar queda protegido aunque suba en el
      // medio, y lo que entra después no está en la lista de esta PC.
      final localRows = await db.query(table, columns: ['id']);
      final localIds = localRows
          .map((r) => (r['id'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      // Lo que todavía no subió no está de más: la nube no lo vio nunca.
      final pendingRows = await db.query(
        '_sync_queue',
        columns: ['registro_id'],
        where: "tabla = ?",
        whereArgs: [table],
      );
      final pendingIds = pendingRows
          .map((r) => r['registro_id'] as String)
          .toSet();

      final cloudIds = await _idsCompletosDeLaNube(table);

      // Una nube vacía contra una base local con filas no es un borrado
      // masivo: es una lectura que no funcionó. Ver `fotoDeLaNubeEsCreible`.
      final creible =
          cloudIds != null &&
          fotoDeLaNubeEsCreible(
            enLaNube: cloudIds.length,
            local: localIds.length,
          );
      if (cloudIds != null && !creible) {
        debugPrint(
          '  ⏸️ $table: la nube dice 0 filas y acá hay ${localIds.length} — '
          'eso es sesión o permisos, no un borrado. No se toca nada.',
        );
      }

      // La misma función que usa el podado del pull. Un solo lugar decide qué
      // se borra, y un solo test lo cubre.
      final aBorrar = filasAPodar(
        fotoCompleta: creible,
        idsLocales: localIds,
        idsEnLaNube: cloudIds ?? const {},
        idsPendientes: pendingIds,
      );
      if (aBorrar.isEmpty) return;

      // Por el mismo camino que los borrados del pulso, así se llevan sus
      // hijas: en SQLite local el CASCADE del esquema no borra nada.
      await _aplicarBorrados(db, table, aBorrar, camino: camino);
    } catch (e) {
      debugPrint('  ⚠️ Error reconciliando $table: $e');
    }
  }

  /// Las tablas que se cuentan en cada ciclo de 10 s, para enterarse de un
  /// borrado aunque el aviso no llegue: lo que se mueve en el mostrador.
  static const List<String> _tablasQueSeCuentan = [
    'pagos_contrato_alumno',
    'contratos_alumnos',
    'egresos',
  ];

  /// Cuenta en la nube las tablas del mostrador y, si en alguna hay menos que
  /// en esta PC, la revisa en ese momento.
  ///
  /// Es lo que hace que un borrado llegue en 10 segundos como mucho aunque el
  /// aviso se pierda: un `count` por tabla, sin bajar nada. Corre después de
  /// la bajada, cuando esta PC ya tiene todo lo nuevo de la nube: si acá hay
  /// más filas que allá (sin contar lo que espera subir), alguna se borró en
  /// otra PC. Si a la vez entró una fila nueva que todavía no bajó, las cuentas
  /// pueden empatar por un ciclo; el siguiente lo ve.
  Future<void> _contarParaVerBorrados(Database db) async {
    for (final tabla in _tablasQueSeCuentan) {
      try {
        final enLaNube = await _supabase
            .from(tabla)
            .count(CountOption.exact)
            .timeout(_esperaNubeDelAlumno);
        final fila = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM $tabla WHERE id NOT IN '
          '(SELECT registro_id FROM _sync_queue WHERE tabla = ?)',
          [tabla],
        );
        final aca = (fila.first['n'] as num?)?.toInt() ?? 0;
        if (aca > enLaNube) {
          debugPrint(
            '  🔎 $tabla: acá $aca y en la nube $enLaNube — se revisa qué se '
            'borró',
          );
          await _revisarBorradosDe(db, tabla, camino: CaminoDelBorrado.cuenta);
        }
      } catch (e) {
        debugPrint('  ⏸️ $tabla: no pude contar en la nube ($e)');
      }
    }
  }

  /// `true` sólo si el error prueba que el registro YA ESTÁ en la nube. Es la
  /// única razón válida para sacarlo de la cola sin haberlo subido en esta
  /// vuelta. Antes esto también incluía 'not found' y errores de UUID: como el
  /// match es por substring del texto, cualquier error que contuviera esas
  /// palabras hacía desaparecer el registro para siempre. Un payload
  /// malformado no se descarta más: queda en cuarentena para poder verlo.
  bool _isNonRetryableError(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('unique') || msg.contains('duplicate');
  }

  Future<void> refreshPendingCount() async {
    _pendingCount = await SyncQueue.pendingCount;
    _pendingController.add(_pendingCount);
  }

  void _updateStatus(SyncStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void dispose() {
    SyncQueue.onChanged = null;
    _timerSubida?.cancel();
    _timerReconciliacion?.cancel();
    _reintentoReconciliacion?.cancel();
    _debouncePulso?.cancel();
    _reintentoBorradosDelPulso?.cancel();
    _timerAvisoCambios?.cancel();
    unawaited(_canalPulso?.unsubscribe() ?? Future.value());
    _connectivitySub?.cancel();
    _statusController.close();
    _pendingController.close();
    _remoteProbeController.close();
    _cambiosBajadosController.close();
  }
}

/// Lo que sacó una pasada de `_aplicarBorrados`, con su cascada.
class _LoSacado {
  final Map<String, List<Map<String, Object?>>> _filas = {};
  final List<String> renglones = [];
  final Set<String> _contratosConPagosSacados = {};

  void anotar(String tabla, Map<String, Object?> fila, {String? alumno}) {
    (_filas[tabla] ??= []).add(fila);
    renglones.add(renglonDeLoBorrado(tabla, fila, alumno: alumno));
    if (tabla == 'pagos_contrato_alumno') {
      final c = fila['contrato_alumno_id'];
      if (c is String && c.isNotEmpty) _contratosConPagosSacados.add(c);
    }
  }

  bool get estaVacio => _filas.isEmpty;

  int get total => _filas.values.fold(0, (s, l) => s + l.length);

  Iterable<String> get tablas => _filas.keys;

  /// Los alumnos a los que se les sacó un pago y siguen existiendo. Si se fue
  /// el alumno entero, sus pagos se fueron con él y no hay cuenta que rehacer.
  Set<String> get contratosARehacer {
    final sinAlumno = {
      for (final f in _filas['contratos_alumnos'] ?? const [])
        if (f['id'] is String) f['id'] as String,
    };
    return _contratosConPagosSacados.difference(sinAlumno);
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  final engine = SyncEngine(connectivity: connectivity);
  engine.start();
  ref.onDispose(() => engine.dispose());
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.statusStream;
});

final syncPendingCountProvider = StreamProvider<int>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.pendingStream;
});

final remoteProbeProvider = StreamProvider<RemoteProbeInfo>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.remoteProbeStream;
});
