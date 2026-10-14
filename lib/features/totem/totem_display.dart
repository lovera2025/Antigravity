import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../core/services/totem_config_cache.dart';
import '../../models/invitado.dart';
import '../../models/totem_config.dart';
import '../../../main.dart' show kWebBaseUrl;
import 'providers/totem_config_provider.dart';
import 'services/bienvenidas_totem.dart';
import 'services/contenido_bienvenida.dart';
import 'services/ficha_totem.dart';
import 'services/puente_ficha.dart';
import 'totem_orientation.dart';
import 'widgets/aviso_sin_internet.dart';
import 'widgets/portada_totem.dart';
import 'widgets/tarjeta_bienvenida.dart';

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

class _TotemDisplayState extends ConsumerState<TotemDisplay> with TickerProviderStateMixin {
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

  /// Color de acento. Se sigue llamando `_gold` porque durante años ESE fue el
  /// color; ahora sale de la config del evento (dorado por defecto).
  Color get _gold => _cfg.colorAcento;

  // ── Orientación ────────────────────────────────────────────────────────────
  TotemOrientation _orientacion = TotemOrientation.auto;

  /// Los controles flotantes se esconden solos: un botón fijo arruina la
  /// proyección en el salón.
  bool _controlesVisibles = true;
  Timer? _ocultarControlesTimer;

  /// Escala vigente, calculada en el build y usada por los sub-widgets que no
  /// reciben los constraints (el panel de ingresados, por ejemplo).
  double _escalaPanel = 1.0;

  // ── Animaciones bienvenida ─────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _particleCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _aperturaCtrl;

  late final Animation<double> _bgFade;
  late final Animation<double> _goldBloom;
  late final Animation<double> _shockwave;
  late final Animation<double> _cardScale;
  late final Animation<double> _iconFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _nameReveal;
  late final Animation<Offset> _mesaSlide;
  late final Animation<double> _aperturaFade;

  // ── Stream / cola ──────────────────────────────────────────────────────────
  StreamSubscription<List<Invitado>>? _sub;
  RealtimeChannel? _broadcastChannel;
  
  /// La lista de los que llegaron, la cola de bienvenidas y si se viene
  /// pudiendo leer la nube. A quién se saluda lo decide esto, no la pantalla:
  /// tiene sus tests en `test/bienvenidas_totem_test.dart`.
  final _sala = IngresosTotem();
  List<Invitado> get _queue => _sala.cola;

  /// Orden: más recientes primero.
  List<Invitado> get _ingresados => _sala.ingresados;

  /// La bienvenida que se dibuja: la que está en pantalla y, mientras se va,
  /// la que se está yendo ([_saliendo]). Para [IngresosTotem], la que se va
  /// ya terminó: el que llega en ese momento espera la suya.
  BienvenidaTotem? _current;
  bool _saliendo = false;
  final _recentIds = <String>{};      // destacados con brillo dorado

  /// Lo que la ventana principal sabe de cada persona del evento: si es
  /// masivo, quién es alumno, con quién viene, su mesa, sus sillas y su
  /// música (`ficha_totem.dart`). Solo en la ventana del escritorio: la web no
  /// tiene ventana principal a quién pedírsela.
  FichaTotem? _ficha;

  /// Vuelve a pedir la ficha cada minuto: un sorteo, un alumno nuevo o el
  /// Excel del delegado pueden cambiarla con el tótem abierto.
  Timer? _fichaTimer;

  /// El QR para que cada invitado se busque. **En un masivo no va**: los
  /// alumnos no tienen DNI y cualquiera podía marcar a otro. Ver
  /// [hayQrEnElTotem].
  bool get _mostrarQr => hayQrEnElTotem(
        enLaVentanaDelEscritorio: widget.windowId != null,
        ficha: _ficha,
      );

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer? _displayTimer;

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
    _setupAnimations();
    _connect();
    // Solo en su propia ventana. Montado en la ventana principal (la ruta
    // `/totem_display`) le sacaría a esa ventana el manejador que contesta la
    // ficha del evento: hay uno solo por ventana.
    if (widget.windowId != null) _setupInterWindowChannel();
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
      _sala.familiaDe = (i) => ficha.familiaDe(i.id);
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

  /// En un masivo, si llegó alguien que la ficha no tiene: un alumno o un
  /// acompañante cargado después de que se pidió.
  bool _fichaNoConoce(Iterable<Invitado> personas) {
    final ficha = _ficha;
    if (ficha == null || !ficha.masivo) return false;
    return personas.any((i) => ficha.de(i.id) == null);
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
  /// embebido no hay ventana propia que redimensionar: ahí alcanza con que
  /// cambie el layout, que es justo lo que hace falta cuando la pantalla del
  /// salón ya está rotada pero el navegador informa apaisado.
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
  ///
  /// Es el `didUpdateWidget` de [TotemPanel] más lo que el panel no necesita por
  /// vivir en el mismo proceso que Recepción.
  void _cambiarEvento(String nuevo) {
    if (!mounted || nuevo == _eventoId) return;

    _sub?.cancel();
    _sub = null;
    _displayTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconciliarTimer?.cancel();

    // IMPRESCINDIBLE: el canal se llama `totem_<eventoId>` y `_connect()` solo
    // lo crea si es null. Sin esto el tótem seguiría escuchando los check-ins
    // del evento viejo, y sería un bug mudo porque la lista de Postgres sí
    // cambia.
    _broadcastChannel?.unsubscribe();
    _broadcastChannel = null;

    // Corta en seco una bienvenida del evento anterior que esté en pantalla.
    _entryCtrl.reset();

    setState(() {
      _eventoId = nuevo;
      // Como recién abierto: la primera lectura del evento nuevo va en
      // silencio, y la gente que ya había ingresado aparece sin bienvenida.
      _sala.reiniciar();
      _recentIds.clear();
      _current = null;
      _saliendo = false;
      _reconnectAttempts = 0;
      // Evita un frame con el branding del evento anterior.
      _cfg = TotemConfig.defaults(nuevo);
      // La ficha es del evento anterior: hasta que llegue la nueva, cada uno
      // es su propia familia y no hay QR.
      _ficha = null;
      _sala.familiaDe = cadaUnoSuFamilia;
    });

    _cargarOrientacion();
    // Escondido, se conecta recién al volver a mostrarse.
    if (!_pausado) {
      _connect();
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
    _displayTimer?.cancel();
    _fichaTimer?.cancel();
    // `removeChannel` y no solo `unsubscribe`: sin canales, el cliente suelta
    // el socket de Realtime.
    final canal = _broadcastChannel;
    _broadcastChannel = null;
    if (canal != null) unawaited(svc.client.removeChannel(canal));
    _entryCtrl.reset();
    setState(() {
      _pausado = true;
      _sala.pausar();
      _current = null;
      _saliendo = false;
    });
  }

  /// Vuelve a conectarse y recarga la lista, en silencio: quien ingresó
  /// mientras estaba escondido aparece en la lista sin bienvenida atrasada.
  void _reanudar() {
    if (!_pausado || !mounted) return;
    setState(() {
      _pausado = false;
      _sala.reiniciar();
      _recentIds.clear();
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
    // Para el tótem embebido y el web, donde el evento llega por constructor y
    // no por el puente. Deja las tres superficies con el mismo comportamiento.
    if (oldWidget.eventoId != widget.eventoId) {
      _cambiarEvento(widget.eventoId);
    }
  }

  /// Un ingreso que llega por un aviso, sin esperar a la nube: por el puente
  /// entre ventanas ([porElPuente], lo marcó esta misma PC) o por el canal de
  /// avisos (lo marcó otra PC o un celular).
  void _handleManualIncoming(Invitado guest, {bool porElPuente = false}) {
    if (!mounted) return;
    var nuevo = false;
    setState(() {
      nuevo = _sala.aviso(
        guest,
        porElPuente: porElPuente,
        ahora: DateTime.now(),
      );
      // Si se sumó a la tarjeta de su familia, también se lo destaca.
      if (nuevo && _sala.enPantalla?.tiene(guest.id) == true) {
        _destacar([guest.id]);
      }
    });
    if (nuevo) _despuesDeLlegar();
  }

  /// Llegó alguien: a la tarjeta de su familia o a la cola. Si no hay nadie
  /// en pantalla, se saluda al que sigue; si hay, puede que su tarjeta tenga
  /// que irse antes (hay cola) o quedarse un poco más (se sumó alguien).
  ///
  /// Si la ficha no conoce a alguien de la cola, se la pide de nuevo antes de
  /// saludar, como mucho un segundo: es un alumno o un acompañante cargado
  /// después, y sin la ficha se lo saludaría sin su familia ni sus sillas.
  Future<void> _despuesDeLlegar() async {
    if (_current == null && _fichaNoConoce(_queue)) {
      await _pedirFicha().timeout(const Duration(seconds: 1), onTimeout: () {});
      if (!mounted || _pausado) return;
    }
    if (_current == null) {
      _showNext();
    } else {
      _programarFin();
    }
  }

  void _handleListReset() {
    if (!mounted) return;
    _displayTimer?.cancel();
    setState(() {
      _sala.vaciar();
      _recentIds.clear();
      _current = null;
      _saliendo = false;
    });
  }

  void _setupSystemUI() {
    // Ya no usamos modo inmersivo para permitir ver la barra de Windows
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  void _setupAnimations() {
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _bgFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.0, 0.30, curve: Curves.easeOut),
      ),
    );

    _goldBloom = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.0, 0.26, curve: Curves.easeOut),
      ),
    );

    _shockwave = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.0, 0.46, curve: Curves.easeOut),
      ),
    );

    _cardScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.05, 0.65, curve: Curves.elasticOut),
        reverseCurve: const Interval(0.0, 0.55, curve: Curves.easeInBack),
      ),
    );

    _iconFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.38, 0.65, curve: Curves.easeOut),
      ),
    );

    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.48, 0.76, curve: Curves.easeOut),
      ),
    );

    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.48, 0.76, curve: Curves.easeOutCubic),
    ));

    _nameReveal = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.60, 0.94, curve: Curves.easeOut),
      ),
    );

    _mesaSlide = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.72, 1.0, curve: Curves.easeOutBack),
    ));

    // Apertura: la pantalla aparece de a poco desde el negro del fondo.
    _aperturaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _aperturaFade = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _aperturaCtrl, curve: Curves.easeOut),
    );
    _aperturaCtrl.forward();
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
    var seVacio = false;
    setState(() {
      final enPantalla = _sala.enPantalla;
      _sala.baja(invitadoId);
      _recentIds.remove(invitadoId);
      // Era el único de la tarjeta: la tarjeta se va enseguida, sin animación,
      // como siempre.
      seVacio = enPantalla != null && _sala.enPantalla == null;
      if (seVacio) {
        _displayTimer?.cancel();
        _entryCtrl.reset();
        _current = null;
        _saliendo = false;
      }
    });
    if (seVacio && _queue.isNotEmpty) {
      _showNext();
    } else if (_current != null) {
      // Si era el único que esperaba, la tarjeta vuelve a durar lo de siempre.
      _programarFin();
    }
  }

  /// Una lectura completa de los invitados, del stream o de la relectura.
  ///
  /// A quién se saluda, a quién se pone en la lista callado y a quién se saca
  /// lo decide [IngresosTotem]. Acá solo se le cuenta que se leyó.
  void _onData(List<Invitado> invitados) {
    if (!mounted) return;
    final antes = _queue.length + (_sala.enPantalla?.personas.length ?? 0);
    setState(() {
      _sala.leyo(invitados, ahora: DateTime.now());
      _reconnectAttempts = 0;
    });
    final despues = _queue.length + (_sala.enPantalla?.personas.length ?? 0);
    if (despues != antes) _despuesDeLlegar();
  }

  void _onError(dynamic error) {
    debugPrint('Stream error: $error');
    if (!mounted || _pausado) return;
    final estabaConectado = _sala.conectado;
    _sala.noPudoLeer(DateTime.now());
    if (estabaConectado) setState(() {});
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

  // ── Mostrar tarjeta de bienvenida ──────────────────────────────────────────

  /// Saluda al que sigue en la cola, con los de su familia que esperaban.
  /// Cuánto dura lo decide [IngresosTotem] ([finDeBienvenida]): 7 s si nadie
  /// espera, 3 s si hay cola.
  void _showNext() {
    if (!mounted || _pausado || _current != null) return;
    final siguiente = _sala.siguiente(DateTime.now());
    if (siguiente == null) return;

    setState(() {
      _current = siguiente;
      _saliendo = false;
      _destacar([for (final i in siguiente.personas) i.id]);
    });
    _entryCtrl.forward(from: 0);
    _programarFin();
  }

  /// Los que acaban de llegar brillan en la lista dos minutos.
  void _destacar(List<String> ids) {
    _recentIds.addAll(ids);
    Timer(const Duration(minutes: 2), () {
      if (mounted) setState(() => _recentIds.removeAll(ids));
    });
  }

  /// Vuelve a poner la hora en que se va la tarjeta. Se llama cada vez que
  /// cambia la cola o se suma alguien: con gente esperando, la que está en
  /// pantalla se acorta; si ya pasaron los 3 s, se va enseguida.
  void _programarFin() {
    _displayTimer?.cancel();
    final fin = _sala.fin;
    if (!mounted || _current == null || _saliendo || fin == null) return;
    final falta = fin.difference(DateTime.now());
    _displayTimer = Timer(
      falta.isNegative ? Duration.zero : falta,
      _terminarBienvenida,
    );
  }

  void _terminarBienvenida() {
    if (!mounted || _current == null || _saliendo) return;
    // Para la cola, la tarjeta ya terminó: el que llega mientras se va espera
    // la suya.
    _sala.termino();
    _saliendo = true;
    _entryCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _current = null;
        _saliendo = false;
      });
      if (_queue.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), _showNext);
      }
    });
  }

  @override
  void dispose() {
    _broadcastChannel?.unsubscribe();
    _sub?.cancel();
    _displayTimer?.cancel();
    _reconnectTimer?.cancel();
    _ocultarControlesTimer?.cancel();
    _reconciliarTimer?.cancel();
    _fichaTimer?.cancel();
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _particleCtrl.dispose();
    _shimmerCtrl.dispose();
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

    // La config del evento entra por acá y se propaga a todos los _build*.
    // Si el evento no tiene fila, son los valores de siempre.
    _cfg = ref.watch(totemConfigValueProvider(_eventoId));

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWidescreen = _esWidescreen(constraints);
          _escalaPanel = _escala(constraints);

          return Stack(
            children: [
              const _EliteAtmosphericBackground(),

              // Vertical: marca arriba, lista abajo.
              // Horizontal: dos columnas que reparten el ancho entre ellas.
              //
              // Antes el panel de ingresados iba en un Positioned con un ancho
              // del 30% mientras la sección del QR reservaba un padding del
              // 35%: dos números sueltos que había que mantener sincronizados a
              // mano. Con Row/Expanded el reparto lo hace el layout y no hay
              // forma de que se pisen al cambiar el tamaño de la ventana.
              if (isWidescreen)
                Row(
                  children: [
                    Expanded(flex: 60, child: _buildPortada(constraints)),
                    Expanded(
                      flex: 40,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
                        child: _buildIngresadosPanel(),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    Expanded(flex: 62, child: _buildPortada(constraints)),
                    Expanded(flex: 38, child: _buildIngresadosPanel()),
                  ],
                ),

              if (_current != null) _buildWelcomeCard(constraints),
              _buildApertura(),
              _buildStatsIndicator(),
              _buildFloatingControls(context),
            ],
          );
        },
      ),
    );
  }

  /// Foto, título, subtítulo y, solo en un particular, el QR
  /// (`widgets/portada_totem.dart`).
  Widget _buildPortada(BoxConstraints constraints) => PortadaTotem(
        cfg: _cfg,
        qrUrl: _mostrarQr ? '$kWebBaseUrl/lista?evento=$_eventoId' : null,
        apaisado: _esWidescreen(constraints),
        escala: _escala(constraints),
        pulso: _pulseCtrl,
      );

  /// Decide el layout. En `auto` conserva el criterio histórico (la forma de
  /// la ventana); si el operador eligió una orientación, manda esa.
  bool _esWidescreen(BoxConstraints c) => switch (_orientacion) {
        TotemOrientation.vertical => false,
        TotemOrientation.horizontal => true,
        TotemOrientation.auto => c.maxWidth > c.maxHeight * 1.2,
      };

  /// Escala tipográfica.
  ///
  /// Antes salía siempre de `maxHeight / 900`, calibrado para 720p: en una
  /// pantalla vertical de 1920 saturaba el tope y quedaba todo diminuto. Ahora
  /// se calcula sobre la dimensión que realmente limita en cada orientación.
  double _escala(BoxConstraints c) {
    final base = _esWidescreen(c) ? c.maxHeight / 780 : c.maxWidth / 620;
    if (!base.isFinite) return 1.0; // constraints sin límite (scroll, tests)
    return base.clamp(0.7, 1.8).toDouble();
  }

  /// La pantalla aparece de a poco desde el negro del fondo.
  ///
  /// Antes acá había un cartel "ESTABLECIENDO CONEXIÓN" con otra marca: se
  /// mostraba igual sin internet, y no establecía nada.
  Widget _buildApertura() {
    return AnimatedBuilder(
      animation: _aperturaCtrl,
      builder: (context, child) {
        if (_aperturaFade.value <= 0) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: const Color(0xFF050505)
                  .withValues(alpha: _aperturaFade.value),
            ),
          ),
        );
      },
    );
  }

  /// Barra flotante: girar y salir, y el aviso de que no hay internet.
  ///
  /// El aviso va acá y no a la vista del salón: es para quien opera el tótem.
  ///
  /// Cubre toda la pantalla con un detector transparente para que cualquier
  /// movimiento del mouse o toque los traiga de vuelta, y a los 5 segundos se
  /// desvanecen. Así se puede operar el tótem sin que la proyección tenga un
  /// par de botones encima toda la noche.
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_sala.conectado) ...[
                        Flexible(
                          child: AvisoSinInternet(
                            // Solo la ventana del tótem tiene puente con
                            // Recepción; en la web y embebido no hay.
                            conPuente: widget.windowId != null,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
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
    );
  }

  // ── Panel inferior: cascade animada de ingresados ─────────────────────────

  Widget _buildIngresadosPanel() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _gold.withValues(alpha: 0.2), width: 1),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Con el dorado de siempre es el violeta de toda la vida; con un
          // acento elegido, se deriva de ese tono.
          colors: _cfg.gradientePanel,
        ),
      ),
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              20 * _escalaPanel,
              10 * _escalaPanel,
              20 * _escalaPanel,
              6 * _escalaPanel,
            ),
            child: Row(
              children: [
                Text('🎉', style: TextStyle(fontSize: 14 * _escalaPanel)),
                SizedBox(width: 8 * _escalaPanel),
                Text(
                  'YA LLEGARON',
                  style: GoogleFonts.oswald(
                    fontSize: 12 * _escalaPanel,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: _gold.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                if (_ingresados.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10 * _escalaPanel,
                      vertical: 3 * _escalaPanel,
                    ),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _gold.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      '${_ingresados.length}',
                      style: GoogleFonts.oswald(
                        fontSize: 13 * _escalaPanel,
                        fontWeight: FontWeight.w700,
                        color: _gold.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Cascade animada ────────────────────────────────────────────────
          Expanded(
            child: _ingresados.isEmpty
                ? Center(
                    child: Text(
                      'Esperando el primer invitado...',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: Colors.white12,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  )
                : _CascadeNames(
                    ingresados: List.unmodifiable(_ingresados),
                    recentIds: Set.unmodifiable(_recentIds),
                    scale: _escalaPanel,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta de bienvenida — Spotlight Entrance ────────────────────────────

  Widget _buildWelcomeCard(BoxConstraints constraints) {
    final scale = _escala(constraints);

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([_entryCtrl, _particleCtrl, _shimmerCtrl]),
        builder: (context, _) {
          return Stack(
            children: [
              // ── Overlay oscuro ────────────────────────────────────────────
              Opacity(
                opacity: (_bgFade.value * 0.90).clamp(0.0, 1.0),
                child: Container(color: Colors.black),
              ),

              // ── Gold bloom radial desde el centro ─────────────────────────
              Opacity(
                opacity: (_goldBloom.value * 0.42).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.1,
                      colors: [_gold, Colors.transparent],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Onda de choque ────────────────────────────────────────────
              IgnorePointer(
                child: CustomPaint(
                  painter: _ShockwavePainter(_shockwave.value, _gold),
                  child: const SizedBox.expand(),
                ),
              ),

              // ── Partículas del color del evento ───────────────────────────
              if (_bgFade.value > 0.4)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ParticlePainter(_particleCtrl.value, _gold),
                    child: const SizedBox.expand(),
                  ),
                ),

              // ── Tarjeta central ───────────────────────────────────────────
              // Lo que dice lo decide ContenidoBienvenida; cómo se ve,
              // TarjetaBienvenida (los dos con sus tests).
              Center(
                child: TarjetaBienvenida(
                  contenido: ContenidoBienvenida.armar(
                    _current!,
                    ficha: _ficha,
                    cfg: _cfg,
                  ),
                  cfg: _cfg,
                  escala: scale,
                  enCamino: _sala.enCamino,
                  tamanio: _cardScale,
                  apareceFoto: _iconFade,
                  apareceSaludo: _titleFade,
                  subeSaludo: _titleSlide,
                  abreNombre: _nameReveal,
                  entraMesa: _mesaSlide,
                  brillo: _shimmerCtrl,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Indicador de estadísticas ──────────────────────────────────────────────

  Widget _buildStatsIndicator() {
    return Positioned(
      top: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _gold.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_rounded,
              color: _gold,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '${_ingresados.length}',
              style: GoogleFonts.oswald(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: _gold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'invitados',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Elite atmospheric background ─────────────────────────────────────────────

class _EliteAtmosphericBackground extends StatefulWidget {
  const _EliteAtmosphericBackground();

  @override
  State<_EliteAtmosphericBackground> createState() => _EliteAtmosphericBackgroundState();
}

class _EliteAtmosphericBackgroundState extends State<_EliteAtmosphericBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        const perla = Color(0xFFE2E2E2);

        return Positioned.fill(
          child: Container(
            color: const Color(0xFF050505),
            child: Stack(
              children: [
                // Nebulosas lentas
                for (var i = 0; i < 4; i++)
                  Positioned(
                    left: -200 + sin(t * 2 * pi + i) * 100 + (i * 200),
                    top: -200 + cos(t * 2 * pi * 0.5 + i) * 100 + (i * 150),
                    child: IgnorePointer(
                      child: Container(
                        width: 600,
                        height: 600,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              [
                                Colors.blueAccent.withValues(alpha: 0.08),
                                Colors.purpleAccent.withValues(alpha: 0.08),
                                perla.withValues(alpha: 0.04),
                                Colors.indigo.withValues(alpha: 0.08),
                              ][i % 4],
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Estrellas titilantes
                ...List.generate(30, (i) {
                  final phase = (t * 5 + i * 0.7) % 1.0;
                  final opacity = (0.5 + 0.5 * sin(phase * 2 * pi)).clamp(0.1, 0.4);
                  return Positioned(
                    left: (i * 137.5) % MediaQuery.of(context).size.width,
                    top: (i * 243.1) % MediaQuery.of(context).size.height,
                    child: Container(
                      width: 2,
                      height: 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: opacity),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: opacity * 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // Viñeta premium
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Colors.transparent, Color(0xFF000000)],
                        stops: [0.4, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Cascade animada de nombres ─────────────────────────────────────────────

class _CascadeNames extends StatefulWidget {
  final List<Invitado> ingresados;
  final Set<String> recentIds;

  /// Escala tipográfica del tótem. Sin esto, en una pantalla vertical de 1920
  /// los nombres quedaban diminutos al lado de la foto.
  final double scale;

  const _CascadeNames({
    required this.ingresados,
    required this.recentIds,
    this.scale = 1.0,
  });

  @override
  State<_CascadeNames> createState() => _CascadeNamesState();
}

class _CascadeNamesState extends State<_CascadeNames>
    with SingleTickerProviderStateMixin {
  static const _itemBase = 58.0;

  double get _itemH => _itemBase * widget.scale;

  late final Ticker _ticker;
  late final ScrollController _scrollCtrl;
  Duration? _prev;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onTick(Duration now) {
    if (_prev == null) { _prev = now; return; }
    final dt = (now - _prev!).inMicroseconds / 1e6;
    _prev = now;
    if (!mounted || widget.ingresados.isEmpty) return;
    if (!_scrollCtrl.hasClients) return;

    final loopH = widget.ingresados.length * _itemH;
    final speed = (loopH / 35.0).clamp(16.0, 55.0);

    double next = _scrollCtrl.offset + speed * dt;
    // Bucle seamless: cuando llega al final de la primera copia, vuelve al inicio
    if (next >= loopH) next -= loopH;
    _scrollCtrl.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.ingresados;

    if (items.isEmpty) {
      return Center(
        child: Text(
          'Esperando el primer invitado...',
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: Colors.white12,
            letterSpacing: 1,
            fontWeight: FontWeight.w300,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportH = constraints.maxHeight;
        final listH = items.length * _itemH;
        // Copias suficientes para que la lista sea siempre ~3x el viewport,
        // garantizando el loop seamless sin que la repetición sea visible.
        final copies = listH > 0
            ? (viewportH * 3 / listH).ceil().clamp(3, 60)
            : 3;

        return Stack(
      children: [
        // ── Lista en bucle (copias dinámicas para loop seamless) ──────────
        ListView.builder(
          controller: _scrollCtrl,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length * copies,
          itemBuilder: (_, i) {
            final inv = items[i % items.length];
            return SizedBox(
              height: _itemH,
              child: _IngresadoItem(
                invitado: inv,
                isRecent: widget.recentIds.contains(inv.id),
              ),
            );
          },
        ),
        // ── Fade superior ─────────────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0, height: 52,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A0A2E), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        // ── Fade inferior ─────────────────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0, height: 52,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF0D0618), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ],
        );
      },
    );
  }
}

class _IngresadoItem extends StatelessWidget {
  final Invitado invitado;
  final bool isRecent;
  const _IngresadoItem({required this.invitado, required this.isRecent});

  @override
  Widget build(BuildContext context) {
    const perla = Color(0xFFE2E2E2);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isRecent
              ? perla.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isRecent
                ? perla.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.1),
            width: isRecent ? 1.5 : 0.5,
          ),
          boxShadow: isRecent
              ? [
                  BoxShadow(
                    color: perla.withValues(alpha: 0.15),
                    blurRadius: 15,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecent ? perla : Colors.white24,
                boxShadow: isRecent ? [
                  BoxShadow(color: perla.withValues(alpha: 0.5), blurRadius: 4)
                ] : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                invitado.nombreCompleto.toUpperCase(),
                style: GoogleFonts.oswald(
                  fontSize: 13,
                  fontWeight: isRecent ? FontWeight.w800 : FontWeight.w500,
                  letterSpacing: 1.5,
                  color: isRecent ? perla : Colors.white60,
                ),
              ),
            ),
            if (invitado.numeroMesa != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isRecent ? perla.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isRecent ? perla.withValues(alpha: 0.2) : Colors.white10),
                ),
                child: Text(
                  'MESA ${invitado.numeroMesa}',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    color: isRecent ? perla : Colors.white38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Onda de choque dorada ─────────────────────────────────────────────────

class _ShockwavePainter extends CustomPainter {
  final double progress;

  /// Color de acento del evento (dorado por defecto).
  final Color _gold;

  const _ShockwavePainter(this.progress, this._gold);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.longestSide * 0.88;

    // Anillo 1: dorado
    final r1 = maxR * progress;
    final opacity1 = (1 - progress) * 0.55;
    canvas.drawCircle(
      center,
      r1,
      Paint()
        ..color = _gold.withValues(alpha: opacity1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * (1 - progress),
    );

    // Anillo 2: blanco, ligeramente detrás
    if (progress > 0.13) {
      final r2 = maxR * (progress - 0.13);
      final opacity2 = (1 - (progress - 0.13)) * 0.22;
      canvas.drawCircle(
        center,
        r2,
        Paint()
          ..color = Colors.white.withValues(alpha: opacity2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1 - progress),
      );
    }

    // Anillo 3: más delgado, muy detrás
    if (progress > 0.28) {
      final r3 = maxR * (progress - 0.28);
      final opacity3 = (1 - (progress - 0.28)) * 0.14;
      canvas.drawCircle(
        center,
        r3,
        Paint()
          ..color = _gold.withValues(alpha: opacity3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * (1 - progress),
      );
    }
  }

  @override
  bool shouldRepaint(_ShockwavePainter old) =>
      old.progress != progress || old._gold != _gold;
}

// ── Partículas doradas flotantes ──────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final double t;

  /// Color de acento del evento (dorado por defecto).
  final Color _gold;

  const _ParticlePainter(this.t, this._gold);

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(54321);
    for (var i = 0; i < 28; i++) {
      final baseX = rng.nextDouble();
      final speed = 0.55 + rng.nextDouble() * 0.9;
      final phase = (t * speed + i / 28) % 1.0;
      final wobble = sin(phase * 2 * pi * 1.5 + i * 1.3) * 18;
      final x = baseX * size.width + wobble;
      final y = size.height * (1.06 - phase * 1.12);
      final opacity = phase < 0.80 ? (1 - phase) * 0.55 : 0.0;
      final sz = 1.8 + rng.nextDouble() * 3.2;

      if (opacity <= 0.0) continue;

      final isWhite = i % 4 == 0;
      final color = isWhite
          ? Colors.white.withValues(alpha: opacity * 0.7)
          : _gold.withValues(alpha: opacity);

      canvas.drawCircle(Offset(x, y), sz, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.t != t || old._gold != _gold;
}

// ── Botón de salida para modo tótem web ──────────────────────────────────────

/// Botón cápsula de la barra flotante del tótem: ícono + etiqueta.
///
/// La etiqueta importa: sin ella no habría forma de saber si el tótem quedó en
/// AUTO, VERTICAL u HORIZONTAL sin ponerse a mirar la forma de la pantalla.
class _ControlPill extends StatefulWidget {
  final IconData icono;
  final String etiqueta;
  final Color color;
  final VoidCallback onTap;

  const _ControlPill({
    required this.icono,
    required this.etiqueta,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ControlPill> createState() => _ControlPillState();
}

class _ControlPillState extends State<_ControlPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
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
                style: GoogleFonts.oswald(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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
