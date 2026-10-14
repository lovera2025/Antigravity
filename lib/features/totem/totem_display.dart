import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../core/services/totem_config_cache.dart';
import '../../models/invitado.dart';
import '../../models/totem_config.dart';
import '../../../main.dart' show kWebBaseUrl;
import 'estilos/escena_totem.dart';
import 'estilos/fondo_totem.dart';
import 'estilos/fuentes_totem.dart';
import 'estilos/totem_estilo.dart';
import 'providers/totem_config_provider.dart';
import 'services/bienvenidas_totem.dart';
import 'services/contenido_bienvenida.dart';
import 'services/ficha_totem.dart';
import 'services/puente_ficha.dart';
import 'services/reproductor_bienvenidas.dart';
import 'totem_orientation.dart';
import 'widgets/aviso_sin_internet.dart';

/// El tótem del salón: la ventana que se proyecta, la tele por el navegador
/// (`?totem`) y la ruta `/totem_display`.
///
/// Lo que se ve es una escena en la apariencia del evento (`estilos/`): la
/// espera a pantalla completa, o una llegada. A quién se saluda y cuánto dura
/// lo deciden [IngresosTotem] y [ReproductorBienvenidas]; qué dice la llegada,
/// [ContenidoBienvenida]. Acá queda la conexión con la nube, el puente con la
/// ventana principal y la barra del operador.
class TotemDisplay extends ConsumerStatefulWidget {
  final String eventoId;
  final SupabaseService? svc;
  final bool showExitButton;
  final int? windowId;

  const TotemDisplay({
    required this.eventoId,
    super.key,
    this.svc,
    this.showExitButton = false,
    this.windowId,
  });

  @override
  ConsumerState<TotemDisplay> createState() => _TotemDisplayState();
}

class _TotemDisplayState extends ConsumerState<TotemDisplay>
    with SingleTickerProviderStateMixin {
  /// Evento que se está proyectando ahora mismo.
  ///
  /// Es estado y no `widget.eventoId` porque en la ventana secundaria el evento
  /// llega **una sola vez**, en los argumentos con que se creó la ventana. Sin
  /// esto, cambiar de evento en Recepción dejaba el salón proyectando el
  /// anterior para siempre. Recepción lo cambia en caliente por el puente
  /// (`set_evento`), sin recrear la ventana.
  late String _eventoId = widget.eventoId;

  /// Config visual del evento. Se refresca sola en cada build desde el stream;
  /// mientras no haya fila en `totem_config` son los valores de siempre.
  late TotemConfig _cfg = TotemConfig.defaults(widget.eventoId);

  Color get _gold => _cfg.colorAcento;

  // ── Orientación ────────────────────────────────────────────────────────────
  TotemOrientation _orientacion = TotemOrientation.auto;

  /// Los controles flotantes se esconden solos: un botón fijo arruina la
  /// proyección en el salón.
  bool _controlesVisibles = true;
  Timer? _ocultarControlesTimer;

  // ── La apertura: la pantalla aparece de a poco desde el negro ──────────────
  late final AnimationController _aperturaCtrl;

  // ── Stream / cola ──────────────────────────────────────────────────────────
  StreamSubscription<List<Invitado>>? _sub;
  RealtimeChannel? _broadcastChannel;

  /// La lista de los que llegaron, la cola de bienvenidas, la tarjeta en
  /// pantalla y sus tiempos. Tiene sus tests en
  /// `test/bienvenidas_totem_test.dart` y `test/reproductor_bienvenidas_test.dart`.
  final _reproductor = ReproductorBienvenidas(salida: EscenaTotem.salida);

  /// Lo que la ventana principal sabe de cada persona del evento: si es
  /// masivo, quién es alumno, con quién viene, su mesa, sus sillas y su
  /// música (`ficha_totem.dart`). Solo en la ventana del escritorio: la web no
  /// tiene ventana principal a quién pedírsela.
  FichaTotem? _ficha;

  /// Vuelve a pedir la ficha cada minuto: un sorteo, un alumno nuevo o el
  /// Excel del delegado pueden cambiarla con el tótem abierto.
  Timer? _fichaTimer;

  /// En la ventana del escritorio, hasta que llega la ficha no se sabe si el
  /// evento es masivo, ni entonces qué apariencia le toca si nadie eligió: la
  /// pantalla queda negra (llega en milisegundos, debajo de la apertura). Si a
  /// los tres segundos no llegó, se sigue sin ella.
  bool _fichaTardo = false;
  Timer? _fichaTardoTimer;

  bool get _mostrarQr => hayQrEnElTotem(
        enLaVentanaDelEscritorio: widget.windowId != null,
        ficha: _ficha,
      );

  /// Reconciliación periódica contra la base.
  ///
  /// El tótem corre ocho horas sin que nadie lo mire. Si el websocket queda
  /// mudo (no caído — mudo), el backoff no se entera porque solo reacciona a
  /// errores explícitos, y la pantalla se congela con una lista vieja. Este
  /// timer vuelve a leer la verdad cada minuto.
  Timer? _reconciliarTimer;

  /// La ventana del tótem está escondida (se "cerró" desde Recepción o con su
  /// propio botón). `KioskLauncher.close()` solo la esconde, para que vuelva al
  /// instante y en el mismo lugar; pero escondida no tiene por qué seguir
  /// hablando con la nube. Pausada no escucha invitados ni configuración, no
  /// tiene canal de avisos y no relee cada minuto: fue parte del consumo de
  /// Disk IO de Supabase del 23-sep. Al volver a mostrarse retoma y recarga.
  bool _pausado = false;

  // ── Reconexión ────────────────────────────────────────────────────────────
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  late final SupabaseService svc;

  @override
  void initState() {
    super.initState();
    _setupSystemUI();
    svc = widget.svc ?? SupabaseService();
    _aperturaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    // Los cuatro fondos, de antemano: el de este evento está listo al
    // primer cuadro, y cambiar de apariencia no tiene que esperar.
    unawaited(FondoTotem.precargar());
    _reproductor.prepararCola = _prepararCola;
    _connect();
    // Solo en su propia ventana. Montado en la ventana principal (la ruta
    // `/totem_display`) le sacaría a esa ventana el manejador que contesta la
    // ficha del evento: hay uno solo por ventana.
    if (widget.windowId != null) _setupInterWindowChannel();
    _esperarFicha();
    _pedirFicha();
    _iniciarFichaPeriodica();
    _cargarOrientacion();
    _programarOcultadoControles();
  }

  // ── La ficha del evento ────────────────────────────────────────────────────

  /// Le pide la ficha a la ventana principal. Sale de la base de la PC: anda
  /// sin internet. Si no llega, se sigue con la que había.
  Future<void> _pedirFicha() async {
    if (widget.windowId == null || _pausado) return;
    final evento = _eventoId;
    if (evento.length != 36) return;
    final ficha = await PuenteFichaTotem.pedir(evento);
    if (!mounted || ficha == null || evento != _eventoId) return;
    setState(() {
      _ficha = ficha;
      _reproductor.familiaDe = (i) => ficha.familiaDe(i.id);
    });
  }

  void _iniciarFichaPeriodica() {
    _fichaTimer?.cancel();
    if (widget.windowId == null) return;
    _fichaTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _pedirFicha(),
    );
  }

  void _esperarFicha() {
    _fichaTardoTimer?.cancel();
    _fichaTardo = false;
    if (widget.windowId == null) return;
    _fichaTardoTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _ficha == null) setState(() => _fichaTardo = true);
    });
  }

  /// Antes de saludar: si en un masivo llegó alguien que la ficha no tiene (un
  /// alumno o un acompañante cargado después), se la pide de nuevo. Sin ella
  /// se lo saludaría sin su familia ni sus sillas.
  Future<void> _prepararCola(List<Invitado> cola) async {
    final ficha = _ficha;
    if (ficha == null || !ficha.masivo) return;
    if (cola.every((i) => ficha.de(i.id) != null)) return;
    await _pedirFicha();
  }

  // ── Orientación ────────────────────────────────────────────────────────────

  Future<void> _cargarOrientacion() async {
    final guardada = await TotemOrientationStore.load(_eventoId);
    if (!mounted || guardada == _orientacion) return;
    setState(() => _orientacion = guardada);
    _aplicarFrameVentana(guardada);
  }

  /// Cicla auto → vertical → horizontal. En la ventana secundaria de escritorio
  /// además da vuelta la ventana de verdad, no solo el layout.
  Future<void> _girarPantalla() async {
    final siguiente = _orientacion.siguiente;
    setState(() => _orientacion = siguiente);
    _mostrarControles();
    await TotemOrientationStore.save(_eventoId, siguiente);
    await _aplicarFrameVentana(siguiente);
  }

  /// Redimensiona la ventana real a 9:16 o 16:9.
  ///
  /// Solo aplica a la ventana secundaria de escritorio. En web y en el panel
  /// embebido no hay ventana propia que redimensionar: ahí la escena se
  /// encuadra en 9:16 o 16:9 dentro de la pantalla.
  Future<void> _aplicarFrameVentana(TotemOrientation orientacion) async {
    if (kIsWeb || widget.windowId == null) return;
    if (orientacion == TotemOrientation.auto) return;
    if (!mounted) return;

    try {
      final vista = View.of(context);
      final dpr = vista.display.devicePixelRatio;
      final pantalla = vista.display.size / dpr;

      // Dejamos margen para que la barra de tareas siga alcanzable.
      final altoUtil = pantalla.height * 0.92;
      final anchoUtil = pantalla.width * 0.92;

      final Size destino;
      if (orientacion == TotemOrientation.vertical) {
        var alto = altoUtil;
        var ancho = alto * 9 / 16;
        if (ancho > anchoUtil) {
          ancho = anchoUtil;
          alto = ancho * 16 / 9;
        }
        destino = Size(ancho, alto);
      } else {
        var ancho = anchoUtil;
        var alto = ancho * 9 / 16;
        if (alto > altoUtil) {
          alto = altoUtil;
          ancho = alto * 16 / 9;
        }
        destino = Size(ancho, alto);
      }

      final origen = Offset(
        (pantalla.width - destino.width) / 2,
        (pantalla.height - destino.height) / 2,
      );

      await WindowController.fromWindowId(widget.windowId!)
          .setFrame(origen & destino);
    } catch (e) {
      // Si la ventana ya no existe o la plataforma no lo soporta, el cambio de
      // layout igual se aplicó. No es motivo para romper la pantalla.
      debugPrint('No se pudo redimensionar la ventana del tótem: $e');
    }
  }

  // ── Controles flotantes ────────────────────────────────────────────────────

  void _mostrarControles() {
    if (!_controlesVisibles && mounted) {
      setState(() => _controlesVisibles = true);
    }
    _programarOcultadoControles();
  }

  void _programarOcultadoControles() {
    _ocultarControlesTimer?.cancel();
    _ocultarControlesTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _controlesVisibles = false);
    });
  }

  void _setupInterWindowChannel() {
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      switch (call.method) {
        case 'pausar':
          _pausar();
          return null;
        case 'reanudar':
          _reanudar();
          return null;
        case 'refresh':
          if (!_pausado) _connect(); // Forzar reconexión del stream
          return null;
        case 'list_reset':
          _handleListReset();
          return null;
        case 'guest_checkin':
          if (call.arguments != null && !_pausado) {
            final data = jsonDecode(call.arguments as String);
            final guest = Invitado.fromJson(data);
            _handleManualIncoming(guest, porElPuente: true);
          }
          return null;
        case 'guest_removed':
          if (call.arguments != null) {
            _handleGuestRemoved(call.arguments as String);
          }
          return null;
        case 'set_evento':
          final nuevo = call.arguments as String?;
          // Mismo blindaje de UUID que usan los repos: un id malformado le saca
          // un 22P02 a Supabase y dejaría la pantalla del salón en error.
          if (nuevo != null && nuevo.length == 36) _cambiarEvento(nuevo);
          return null;
        case 'config_updated':
          if (call.arguments != null) {
            final data = jsonDecode(call.arguments as String);
            _handleConfigUpdated(TotemConfig.fromJson(data));
          }
          return null;
      }
      return null;
    });
  }

  /// Cambia de evento sin recrear la ventana.
  void _cambiarEvento(String nuevo) {
    if (!mounted || nuevo == _eventoId) return;

    _sub?.cancel();
    _sub = null;
    _reconnectTimer?.cancel();
    _reconciliarTimer?.cancel();

    // IMPRESCINDIBLE: el canal se llama `totem_<eventoId>` y `_connect()` solo
    // lo crea si es null. Sin esto el tótem seguiría escuchando los check-ins
    // del evento viejo, y sería un bug mudo porque la lista de Postgres sí
    // cambia.
    _broadcastChannel?.unsubscribe();
    _broadcastChannel = null;

    setState(() {
      _eventoId = nuevo;
      // Como recién abierto: la primera lectura del evento nuevo va en
      // silencio, y la gente que ya había ingresado aparece sin bienvenida.
      // Corta en seco una bienvenida del evento anterior que esté en pantalla.
      _reproductor.reiniciar();
      _reconnectAttempts = 0;
      // Evita un frame con el branding del evento anterior.
      _cfg = TotemConfig.defaults(nuevo);
      // La ficha es del evento anterior: hasta que llegue la nueva, cada uno
      // es su propia familia y no hay QR.
      _ficha = null;
      _reproductor.familiaDe = cadaUnoSuFamilia;
    });

    _cargarOrientacion();
    // Escondido, se conecta recién al volver a mostrarse.
    if (!_pausado) {
      _connect();
      _esperarFicha();
      _pedirFicha();
    }
  }

  /// Corta todo lo que habla con la nube. Ver [_pausado].
  void _pausar() {
    if (_pausado || !mounted) return;
    _sub?.cancel();
    _sub = null;
    _reconciliarTimer?.cancel();
    _reconnectTimer?.cancel();
    _fichaTimer?.cancel();
    // `removeChannel` y no solo `unsubscribe`: sin canales, el cliente suelta
    // el socket de Realtime.
    final canal = _broadcastChannel;
    _broadcastChannel = null;
    if (canal != null) unawaited(svc.client.removeChannel(canal));
    setState(() {
      _pausado = true;
      _reproductor.pausar();
    });
  }

  /// Vuelve a conectarse y recarga la lista, en silencio: quien ingresó
  /// mientras estaba escondido aparece en la lista sin bienvenida atrasada.
  void _reanudar() {
    if (!_pausado || !mounted) return;
    setState(() {
      _pausado = false;
      _reproductor.reiniciar();
      _reconnectAttempts = 0;
    });
    _connect();
    // Mientras estuvo escondido pudo cambiar: un sorteo, un alumno nuevo.
    _pedirFicha();
    _iniciarFichaPeriodica();
  }

  /// Aplica una config recién guardada desde el editor.
  ///
  /// Viene por el puente con el JSON entero porque `SharedPreferences` cachea en
  /// memoria por proceso: hay que reescribir la caché **de este** proceso para
  /// que el provider la levante. El `setState` solo pinta un frame; el que
  /// manda es el invalidate.
  void _handleConfigUpdated(TotemConfig cfg) {
    if (!mounted || cfg.eventoId != _eventoId) return;
    TotemConfigCache.save(cfg);
    setState(() => _cfg = cfg);
    ref.invalidate(totemConfigProvider(_eventoId));
  }

  @override
  void didUpdateWidget(covariant TotemDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Para el tótem web y la ruta, donde el evento llega por constructor y no
    // por el puente.
    if (oldWidget.eventoId != widget.eventoId) {
      _cambiarEvento(widget.eventoId);
    }
  }

  /// Un ingreso que llega por un aviso, sin esperar a la nube: por el puente
  /// entre ventanas ([porElPuente], lo marcó esta misma PC) o por el canal de
  /// avisos (lo marcó otra PC o un celular).
  void _handleManualIncoming(Invitado guest, {bool porElPuente = false}) {
    if (!mounted) return;
    _reproductor.aviso(guest, porElPuente: porElPuente);
  }

  void _handleListReset() {
    if (!mounted) return;
    _reproductor.vaciar();
  }

  void _setupSystemUI() {
    // Ya no usamos modo inmersivo para permitir ver la barra de Windows
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // ── Conexión y datos ───────────────────────────────────────────────────────

  void _connect() {
    try {
      _sub?.cancel();
      _sub = svc.streamInvitados(_eventoId).listen(
        _onData,
        onError: _onError,
        cancelOnError: false,
      );

      // Usar Supabase Realtime Broadcast para reacción INMEDIATA sin esperar replicación
      if (_broadcastChannel == null) {
        _broadcastChannel = svc.client.channel('totem_$_eventoId');
        _broadcastChannel!.onBroadcast(event: 'checkin', callback: (payload) {
          final data = payload['payload'];
          if (data != null && mounted) {
            final guest = Invitado.fromJson(data);
            _handleManualIncoming(guest);
          }
        });
        // Borrado instantáneo para tótems que no corren en la PC de Recepción.
        _broadcastChannel!.onBroadcast(event: 'guest_removed', callback: (payload) {
          final data = payload['payload'];
          final id = data is Map ? data['id']?.toString() : null;
          if (id != null && mounted) _handleGuestRemoved(id);
        });
        // Vaciar lista / deshacer todos los ingresos. Sin esto, un tótem que no
        // corre en la PC de Recepción se enteraba solo por la reconciliación.
        _broadcastChannel!.onBroadcast(event: 'list_reset', callback: (_) {
          if (mounted) _handleListReset();
        });
        _broadcastChannel!.subscribe();
      }

      // Acá no se da por conectado: eso lo dice la primera lectura que llega
      // (`_onData`). Dándolo por bueno al intentar, la espera entre reintentos
      // volvía siempre a 2 segundos y el aviso de conexión parpadeaba.

      // Al (re)conectar, repoblar de una. El stream solo avisa de lo que pasa
      // de acá en adelante: si estuvimos caídos treinta segundos, todo lo que
      // ocurrió en el medio no llega nunca.
      _reconciliar();
      _iniciarReconciliacionPeriodica();
    } catch (e) {
      debugPrint('Error connecting to stream: $e');
      _onError(e);
    }
  }

  void _iniciarReconciliacionPeriodica() {
    _reconciliarTimer?.cancel();
    _reconciliarTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _reconciliar(),
    );
  }

  /// Vuelve a leer los invitados del evento y los pasa por el mismo camino que
  /// el stream.
  ///
  /// Reutiliza [_onData] a propósito: por ahí pasa todo lo que se lee, y es lo
  /// que evita volver a disparar la bienvenida de gente que ya entró. Si esto
  /// armara la lista por su cuenta, cada minuto se llenaría la pantalla de
  /// saludos repetidos.
  Future<void> _reconciliar() async {
    if (!mounted || _pausado || _eventoId.length != 36) return;
    final evento = _eventoId;
    final List<dynamic> filas;
    try {
      filas = await svc.client
          .from('invitados')
          .select()
          .eq('evento_id', evento)
          .order('nombre_completo');
    } catch (e) {
      debugPrint('Reconciliación del tótem falló: $e');
      // No poder leer es un corte, aunque el stream no haya dado error: es lo
      // que pasa cuando la conexión queda muda.
      if (mounted && !_pausado && evento == _eventoId) _onError(e);
      return;
    }

    // Mientras se esperaba la respuesta pudo cambiar el evento o esconderse la
    // ventana: esa lectura ya no es de lo que se está mostrando.
    if (!mounted || _pausado || evento != _eventoId) return;
    try {
      final invitados = filas
          .map((f) => Invitado.fromJson(f as Map<String, dynamic>))
          .toList();
      _onData(invitados);
    } catch (e) {
      debugPrint('Reconciliación del tótem: no se pudo leer una fila: $e');
    }
  }

  /// Saca a un invitado de la pantalla al instante.
  ///
  /// Lo llama Recepción por el puente entre ventanas cuando se borra a alguien
  /// en la misma PC, sin esperar a la nube.
  void _handleGuestRemoved(String invitadoId) {
    if (!mounted) return;
    _reproductor.baja(invitadoId);
  }

  /// Una lectura completa de los invitados, del stream o de la relectura.
  ///
  /// A quién se saluda, a quién se pone en la lista callado y a quién se saca
  /// lo decide [IngresosTotem]. Acá solo se le cuenta que se leyó.
  void _onData(List<Invitado> invitados) {
    if (!mounted) return;
    _reconnectAttempts = 0;
    _reproductor.leyo(invitados);
  }

  void _onError(dynamic error) {
    debugPrint('Stream error: $error');
    if (!mounted || _pausado) return;
    _reproductor.noPudoLeer();
    _reconnectWithBackoff();
  }

  void _reconnectWithBackoff() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(esperaDeReintento(_reconnectAttempts), () {
      if (!mounted || _pausado) return;
      _reconnectAttempts++;
      _connect();
    });
  }

  @override
  void dispose() {
    _broadcastChannel?.unsubscribe();
    _sub?.cancel();
    _reconnectTimer?.cancel();
    _ocultarControlesTimer?.cancel();
    _reconciliarTimer?.cancel();
    _fichaTimer?.cancel();
    _fichaTardoTimer?.cancel();
    _reproductor.dispose();
    _aperturaCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Escondido: sin mirar la config, así su stream de Supabase se suelta
    // (el provider es autoDispose). Nadie ve esta pantalla.
    if (_pausado) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    // La config del evento entra por acá. Si el evento no tiene fila, son los
    // valores de siempre.
    _cfg = ref.watch(totemConfigValueProvider(_eventoId));

    // En la ventana del escritorio, sin la ficha no se sabe si es masivo: si
    // nadie eligió apariencia, se espera un instante en negro antes que
    // mostrar la que no es.
    final esperandoFicha = widget.windowId != null &&
        _ficha == null &&
        !_fichaTardo &&
        EstiloTotem.desdeClave(_cfg.estilo) == null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!esperandoFicha) _encuadrado(_escena()),
          _buildApertura(),
          _buildFloatingControls(context),
        ],
      ),
    );
  }

  /// La escena, con lo que dice el reproductor.
  Widget _escena() {
    final estilo = estiloDelTotem(elegido: _cfg.estilo, ficha: _ficha);
    return AnimatedBuilder(
      animation: _reproductor,
      builder: (context, _) {
        final actual = _reproductor.actual;
        return EscenaTotem(
          estilo: estilo,
          cfg: _cfg,
          qrUrl: _mostrarQr ? '$kWebBaseUrl/lista?evento=$_eventoId' : null,
          llegada: actual == null
              ? null
              : ContenidoBienvenida.armar(actual, ficha: _ficha, cfg: _cfg),
          plano: _ficha?.plano,
          claveLlegada: actual,
          saliendo: _reproductor.saliendo,
          enCamino: _reproductor.enCamino,
          empezo: actual?.empezo,
          fin: _reproductor.fin,
        );
      },
    );
  }

  /// En la ventana del escritorio la ventana ya tiene la forma elegida. En la
  /// web, si se eligió vertical u horizontal y la pantalla dice otra cosa, la
  /// escena se encuadra en 9:16 o 16:9 en el medio.
  Widget _encuadrado(Widget escena) {
    final forzada = switch (_orientacion) {
      TotemOrientation.vertical => 9 / 16,
      TotemOrientation.horizontal => 16 / 9,
      TotemOrientation.auto => null,
    };
    if (forzada == null || widget.windowId != null) {
      return Positioned.fill(child: escena);
    }
    return Positioned.fill(
      child: Center(
        child: AspectRatio(aspectRatio: forzada, child: escena),
      ),
    );
  }

  /// La pantalla aparece de a poco desde el negro del fondo.
  ///
  /// Antes acá había un cartel "ESTABLECIENDO CONEXIÓN" con otra marca: se
  /// mostraba igual sin internet, y no establecía nada.
  Widget _buildApertura() {
    return AnimatedBuilder(
      animation: _aperturaCtrl,
      builder: (context, child) {
        final opacidad = 1 - Curves.easeOut.transform(_aperturaCtrl.value);
        if (opacidad <= 0) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: const Color(0xFF050505).withValues(alpha: opacidad),
            ),
          ),
        );
      },
    );
  }

  /// Barra flotante del operador: cuántos llegaron, el aviso de que no hay
  /// internet, girar y salir.
  ///
  /// Va acá y no a la vista del salón: es para quien opera el tótem. Cubre
  /// toda la pantalla con un detector transparente para que cualquier
  /// movimiento del mouse o toque la traiga de vuelta, y a los 5 segundos se
  /// desvanece.
  Widget _buildFloatingControls(BuildContext context) {
    return Positioned.fill(
      child: MouseRegion(
        opaque: false,
        onHover: (_) => _mostrarControles(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _mostrarControles(),
          child: Align(
            alignment: Alignment.topRight,
            child: AnimatedOpacity(
              opacity: _controlesVisibles ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: IgnorePointer(
                ignoring: !_controlesVisibles,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AnimatedBuilder(
                    animation: _reproductor,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_reproductor.conectado) ...[
                          Flexible(
                            child: AvisoSinInternet(
                              // Solo la ventana del tótem tiene puente con
                              // Recepción; en la web no hay.
                              conPuente: widget.windowId != null,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        _ControlPill(
                          icono: Icons.how_to_reg_rounded,
                          etiqueta: _llegaron(_reproductor.ingresados.length),
                          color: _gold,
                        ),
                        const SizedBox(width: 10),
                        _ControlPill(
                          icono: Icons.screen_rotation_rounded,
                          etiqueta: _orientacion.etiqueta,
                          color: _gold,
                          onTap: _girarPantalla,
                        ),
                        if (widget.showExitButton) ...[
                          const SizedBox(width: 10),
                          _ExitButton(
                            onExit: () async {
                              SystemChrome.setEnabledSystemUIMode(
                                  SystemUiMode.edgeToEdge);
                              if (widget.windowId != null) {
                                _pausar();
                                await WindowController.fromWindowId(
                                        widget.windowId!)
                                    .hide();
                              } else if (context.mounted &&
                                  Navigator.canPop(context)) {
                                Navigator.pop(context);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _llegaron(int n) => n == 1 ? '1 LLEGÓ' : '$n LLEGARON';
}

/// Botón cápsula de la barra flotante del tótem: ícono + etiqueta. Sin
/// [onTap], es solo un dato (cuántos llegaron).
///
/// La etiqueta importa: sin ella no habría forma de saber si el tótem quedó en
/// AUTO, VERTICAL u HORIZONTAL sin ponerse a mirar la forma de la pantalla.
class _ControlPill extends StatefulWidget {
  final IconData icono;
  final String etiqueta;
  final Color color;
  final VoidCallback? onTap;

  const _ControlPill({
    required this.icono,
    required this.etiqueta,
    required this.color,
    this.onTap,
  });

  @override
  State<_ControlPill> createState() => _ControlPillState();
}

class _ControlPillState extends State<_ControlPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tocable = widget.onTap != null;
    return MouseRegion(
      cursor: tocable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = tocable),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: _hovered ? 0.85 : 0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: widget.color.withValues(alpha: _hovered ? 0.9 : 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icono, color: widget.color, size: 18),
              const SizedBox(width: 8),
              Text(
                widget.etiqueta,
                // La negrita que viene con la app: anda sin internet.
                style: TextStyle(
                  fontFamily: FuentesTotem.linea,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExitButton extends StatefulWidget {
  final VoidCallback onExit;
  const _ExitButton({required this.onExit});

  @override
  State<_ExitButton> createState() => _ExitButtonState();
}

class _ExitButtonState extends State<_ExitButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onExit,
        child: AnimatedOpacity(
          opacity: _hovered ? 0.9 : 0.18,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white24,
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
