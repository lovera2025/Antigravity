import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/invitado.dart';
import '../recepcion/repositories/invitados_repository.dart';
import '../../../main.dart' show kWebBaseUrl;

enum TotemPanelMode { panel, fullscreen, focus }

class TotemPanel extends ConsumerStatefulWidget {
  final String eventoId;
  final VoidCallback? onModeChanged;
  final bool showModeButtons;

  const TotemPanel({
    required this.eventoId,
    this.onModeChanged,
    this.showModeButtons = true,
    super.key,
  });

  @override
  ConsumerState<TotemPanel> createState() => _TotemPanelState();
}

class _TotemPanelState extends ConsumerState<TotemPanel> with TickerProviderStateMixin {
  static const _gold = Color(0xFFD4AF37);

  TotemPanelMode _currentMode = TotemPanelMode.panel;

  // ── Animaciones bienvenida ─────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _particleCtrl;
  late final AnimationController _shimmerCtrl;

  late final Animation<double> _bgFade;
  late final Animation<double> _goldBloom;
  late final Animation<double> _shockwave;
  late final Animation<double> _cardScale;
  late final Animation<double> _iconFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _nameReveal;
  late final Animation<Offset> _mesaSlide;

  // ── Stream / cola ──────────────────────────────────────────────────────────
  StreamSubscription<List<Invitado>>? _sub;
  final _queue = <Invitado>[];
  final _processedIds = <String>{};
  Invitado? _current;
  bool _initialized = false;

  // ── Lista ingresados ───────────────────────────────────────────────────────
  final _ingresados = <Invitado>[];
  final _recentIds = <String>{};

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer? _displayTimer;
  Timer? _cleanupTimer;

  // ── Focus mode timers ──────────────────────────────────────────────────────
  Timer? _focusModeTimer;
  int _focusTapCount = 0;

  // ── Reconexión ────────────────────────────────────────────────────────────
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _isConnected = true;


  @override
  void initState() {
    super.initState();
    _setupSystemUI();
    _setupAnimations();
    _startCleanupTimer();
    // Conectar al stream SOLO en initState para evitar reconexiones
    // cuando el árbol de widgets se reconstruye (didChangeDependencies).
    // Usamos WidgetsBinding para garantizar que el contexto de Riverpod esté listo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connect();
    });
  }

  @override
  void didUpdateWidget(covariant TotemPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventoId != widget.eventoId) {
      // Limpiar estado al cambiar de evento
      _sub?.cancel();
      _displayTimer?.cancel();
      _queue.clear();
      _processedIds.clear();
      _ingresados.clear();
      _recentIds.clear();
      _current = null;
      _initialized = false;
      _connect();
    }
  }

  void _setupSystemUI() {
    if (_currentMode == TotemPanelMode.focus) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else if (_currentMode == TotemPanelMode.fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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
  }

  void _connect() {
    try {
      _sub?.cancel();
      // Usamos el stream del repositorio o vigilamos el provider
      final repository = ref.read(invitadosRepositoryProvider);
      _sub = repository.watchByEvento(widget.eventoId).listen(
        _onData,
        onError: _onError,
        cancelOnError: false,
      );
      setState(() {
        _isConnected = true;
        _reconnectAttempts = 0;
      });
    } catch (e) {
      debugPrint('Error connecting to stream: $e');
      _onError(e);
    }
  }

  void _onData(List<Invitado> invitados) {
    if (!mounted) return;

    final ingresadosActualesIds = invitados
        .where((i) => i.estadoIngreso == EstadoIngreso.ingresado)
        .map((i) => i.id)
        .toSet();

    if (!_initialized) {
      final yaIngresados = invitados
          .where((i) => i.estadoIngreso == EstadoIngreso.ingresado)
          .toList();
      for (var inv in yaIngresados) {
        _processedIds.add(inv.id);
      }
      setState(() {
        _ingresados
          ..clear()
          ..addAll(yaIngresados.reversed);
      });
      _initialized = true;
      if (!_isConnected) setState(() => _isConnected = true);
      return;
    }

    // 1. Limpiar borrados o reseteados en la UI local
    bool changed = false;
    final originalLength = _ingresados.length;
    _ingresados.removeWhere((inv) => !ingresadosActualesIds.contains(inv.id));
    if (_ingresados.length != originalLength) changed = true;
    _processedIds.retainAll(ingresadosActualesIds);
    _queue.removeWhere((inv) => !ingresadosActualesIds.contains(inv.id));

    if (changed) {
      setState(() {});
    }

    // 2. Agregar los nuevos ingresos
    for (var invitado in invitados) {
      if (invitado.estadoIngreso == EstadoIngreso.ingresado &&
          !_processedIds.contains(invitado.id)) {
        if (_current?.id == invitado.id) continue;
        if (_queue.any((i) => i.id == invitado.id)) continue;
        _queue.add(invitado);
        _processedIds.add(invitado.id);

        setState(() => _ingresados.insert(0, invitado));
      }
    }

    if (_current == null && _queue.isNotEmpty) _showNext();

    if (!_isConnected) {
      setState(() => _isConnected = true);
      _reconnectAttempts = 0;
    }
  }

  void _onError(dynamic error) {
    debugPrint('Stream error: $error');
    if (!mounted) return;
    setState(() => _isConnected = false);
    _reconnectWithBackoff();
  }

  void _reconnectWithBackoff() {
    _reconnectTimer?.cancel();
    const baseDelay = 2;
    const maxDelay = 32;
    final delay = (baseDelay * (1 << _reconnectAttempts)).clamp(baseDelay, maxDelay);
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!mounted) return;
      _reconnectAttempts++;
      _connect();
    });
  }

  void _showNext() {
    if (_queue.isEmpty || !mounted) return;

    final next = _queue.removeAt(0);
    setState(() {
      _current = next;
      _recentIds.add(next.id);
    });
    _entryCtrl.forward(from: 0);

    Timer(const Duration(minutes: 2), () {
      if (mounted) setState(() => _recentIds.remove(next.id));
    });

    _displayTimer?.cancel();
    _displayTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      _entryCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _current = null);
        if (_queue.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 300), _showNext);
        }
      });
    });
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_processedIds.length > 1000) {
        final toRemove = _processedIds.length - 500;
        _processedIds.removeAll(_processedIds.take(toRemove));
      }
    });
  }

  void _changeMode(TotemPanelMode newMode) {
    setState(() => _currentMode = newMode);
    _setupSystemUI();
    widget.onModeChanged?.call();
  }

  void _handleFocusModeExit() {
    _focusTapCount++;

    if (_focusTapCount == 1) {
      _focusModeTimer?.cancel();
      _focusModeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _currentMode == TotemPanelMode.focus) {
          _changeMode(TotemPanelMode.fullscreen);
          _focusTapCount = 0;
        }
      });
    } else if (_focusTapCount >= 2) {
      _focusModeTimer?.cancel();
      _focusTapCount = 0;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _displayTimer?.cancel();
    _reconnectTimer?.cancel();
    _cleanupTimer?.cancel();
    _focusModeTimer?.cancel();
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _particleCtrl.dispose();
    _shimmerCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _currentMode == TotemPanelMode.focus
          ? (_) => _handleFocusModeExit()
          : null,
      child: Scaffold(
        body: Stack(
          children: [
            const _FestiveBackground(),
            if (_currentMode == TotemPanelMode.panel) _buildPanelMode(),
            if (_currentMode == TotemPanelMode.fullscreen) _buildFullscreenMode(),
            if (_currentMode == TotemPanelMode.focus) _buildFocusMode(),
            if (_current != null) _buildWelcomeCard(),
            _buildConnectionIndicator(),
          ],
        ),
      ),
    );
  }

  // ── PANEL MODE ─────────────────────────────────────────────────────────────

  Widget _buildPanelMode() {
    return Column(
      children: [
        Expanded(flex: 55, child: _buildQRSection()),
        Expanded(flex: 45, child: _buildIngresadosPanel()),
      ],
    );
  }

  // ── FULLSCREEN MODE ────────────────────────────────────────────────────────

  Widget _buildFullscreenMode() {
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.portrait) {
          return Column(
            children: [
              Expanded(flex: 55, child: _buildQRSection()),
              Expanded(flex: 45, child: _buildIngresadosPanel()),
            ],
          );
        } else {
          return Row(
            children: [
              Expanded(flex: 55, child: _buildQRSection()),
              Expanded(flex: 45, child: _buildIngresadosPanel()),
            ],
          );
        }
      },
    );
  }

  // ── FOCUS MODE (Immersive) ─────────────────────────────────────────────────

  Widget _buildFocusMode() {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(flex: 55, child: _buildQRSection()),
            Expanded(flex: 45, child: _buildIngresadosPanel()),
          ],
        ),
        Positioned(
          top: 20,
          right: 20,
          child: AnimatedOpacity(
            opacity: _focusTapCount > 0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Modo Focus Activo',
                style: GoogleFonts.oswald(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Sección superior: Logo + QR ────────────────────────────────────────────

  Widget _buildQRSection() {
    final qrUrl = '$kWebBaseUrl/lista?evento=${widget.eventoId}';

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _pulseCtrl.drive(Tween(begin: 0.15, end: 0.45)),
              child: SizedBox(
                height: 110,
                child: Container(
                  width: 160,
                  height: 160,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.06),
                        blurRadius: 36,
                        spreadRadius: 6,
                      ),
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.06),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/icons/logo-transparent-final.png',
                    width: 130,
                    height: 130,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.event_rounded,
                      size: 70,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Junior Eventos',
              style: GoogleFonts.oswald(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, child) => Opacity(
                opacity: 0.55 + _pulseCtrl.value * 0.45,
                child: child,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.25),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: qrUrl,
                      version: QrVersions.auto,
                      size: 150,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0A0A0A),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0A0A0A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CONSULTÁ TU MESA',
                    style: GoogleFonts.oswald(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: _gold.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Escaneá con la cámara de tu celular',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
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
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A0A2E), Color(0xFF0D0618), Color(0xFF080808)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  'YA LLEGARON',
                  style: GoogleFonts.oswald(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: _gold.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                if (_ingresados.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _gold.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      '${_ingresados.length}',
                      style: GoogleFonts.oswald(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _gold.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.cleaning_services, size: 16, color: Colors.white38),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Limpiar lista visual',
                    onPressed: () {
                      setState(() {
                         _ingresados.clear();
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
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
                  ),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta de bienvenida — Spotlight Entrance ────────────────────────────

  Widget _buildWelcomeCard() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([_entryCtrl, _particleCtrl, _shimmerCtrl]),
        builder: (context, _) {
          return Stack(
            children: [
              Opacity(
                opacity: (_bgFade.value * 0.90).clamp(0.0, 1.0),
                child: Container(color: Colors.black),
              ),
              Opacity(
                opacity: (_goldBloom.value * 0.42).clamp(0.0, 1.0),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.1,
                      colors: [_gold, Colors.transparent],
                      stops: [0.0, 1.0],
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _ShockwavePainter(_shockwave.value),
                  child: const SizedBox.expand(),
                ),
              ),
              if (_bgFade.value > 0.4)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ParticlePainter(_particleCtrl.value),
                    child: const SizedBox.expand(),
                  ),
                ),
              Center(
                child: Transform.scale(
                  scale: _cardScale.value.clamp(0.0, 1.05),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 38,
                      vertical: 42,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1C0F35), Color(0xFF0C0518)],
                      ),
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(
                        color: _gold.withValues(alpha: 0.50),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.32),
                          blurRadius: 70,
                          spreadRadius: 18,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 30,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(34),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
  // Shimmer periódico
  Positioned.fill(
    child: CustomPaint(
      painter: _ShimmerPainter(_shimmerCtrl.value),
    ),
  ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FadeTransition(
                                opacity: _iconFade,
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: _gold.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _gold.withValues(alpha: 0.30),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Text(
                                    '🥳',
                                    style: TextStyle(fontSize: 72),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              ClipRect(
                                child: SlideTransition(
                                  position: _titleSlide,
                                  child: FadeTransition(
                                    opacity: _titleFade,
                                    child: Text(
                                      '¡Bienvenido!',
                                      style: GoogleFonts.oswald(
                                        fontSize: 50,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              ClipRect(
                                child: Align(
                                  alignment: Alignment.center,
                                  widthFactor: _nameReveal.value.clamp(0.0, 1.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          _gold.withValues(alpha: 0.22),
                                          _gold.withValues(alpha: 0.08),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _gold.withValues(alpha: 0.40),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      _current!.nombreCompleto,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                        fontSize: 42,
                                        fontWeight: FontWeight.w800,
                                        color: _gold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_current!.numeroMesa != null) ...[
                                const SizedBox(height: 22),
                                ClipRect(
                                  child: SlideTransition(
                                    position: _mesaSlide,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.07),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.table_restaurant_rounded,
                                            color: Colors.white60,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Tu mesa',
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w400,
                                                color: Colors.white54,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                            Text(
                                              'Nº ${_current!.numeroMesa}',
                                              style: GoogleFonts.oswald(
                                                fontSize: 34,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Indicador de conexión ──────────────────────────────────────────────────

  Widget _buildConnectionIndicator() {
    return Positioned(
      top: 16,
      right: 16,
      child: AnimatedOpacity(
        opacity: _isConnected ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                'Reconectando...',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Festive animated background ─────────────────────────────────────────────

class _FestiveBackground extends StatefulWidget {
  const _FestiveBackground();

  @override
  State<_FestiveBackground> createState() => _FestiveBackgroundState();
}

class _FestiveBackgroundState extends State<_FestiveBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 28))..repeat();
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
      builder: (_, _) {
        final t = _ctrl.value;

        return Positioned.fill(
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                for (var i = 0; i < 5; i++)
                  Positioned(
                    left: (0.1 + 0.8 * ((i + 1) / 6)) * MediaQuery.of(context).size.width +
                        120 * sin(t * (0.5 + i * 0.17) * 2 * pi),
                    top: (0.15 + 0.7 * ((5 - i) / 6)) * MediaQuery.of(context).size.height +
                        80 * cos(t * (0.4 + i * 0.13) * 2 * pi),
                    child: IgnorePointer(
                      child: Container(
                        width: 300.0 + i * 80,
                        height: 300.0 + i * 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 0.8,
                            colors: [
                              HSVColor.fromAHSV(1, (260 + i * 40 + t * 120) % 360, 0.85, 0.45)
                                  .toColor()
                                  .withValues(alpha: 0.22),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                for (var i = 0; i < 4; i++)
                  Positioned(
                    left: (0.2 + 0.6 * sin(t * (0.3 + i * 0.2) * 2 * pi)) *
                        MediaQuery.of(context).size.width,
                    top: (0.1 + 0.8 * cos(t * (0.25 + i * 0.15) * 2 * pi)) *
                        MediaQuery.of(context).size.height,
                    child: IgnorePointer(
                      child: Transform.rotate(
                        angle: (t * (i + 1) * 0.6),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                HSVColor.fromAHSV(1, (200 + i * 30 + t * 90) % 360, 0.6, 0.7)
                                    .toColor()
                                    .withValues(alpha: 0.06),
                                Colors.transparent
                              ],
                            ),
                            borderRadius: BorderRadius.circular(60),
                          ),
                        ),
                      ),
                    ),
                  ),
                ...List.generate(12, (i) {
                  final phase = (t + i / 12) * 2 * pi * (1 + (i % 3) * 0.12);
                  final dx = 0.15 + 0.7 * ((i % 4) / 4) + 0.18 * cos(phase);
                  final dy = 0.2 + 0.6 * ((i % 5) / 5) + 0.18 * sin(phase);
                  final size = 8.0 + 22.0 * (0.5 + 0.5 * sin(phase));
                  final color = HSVColor.fromAHSV(
                    1,
                    (180 + i * 25 + t * 200) % 360,
                    0.8,
                    0.7,
                  ).toColor();
                  return Positioned(
                    left: dx * MediaQuery.of(context).size.width - size / 2,
                    top: dy * MediaQuery.of(context).size.height - size / 2,
                    child: Opacity(
                      opacity: 0.04 + 0.06 * (0.5 + 0.5 * sin(phase)),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.12),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.22),
                              blurRadius: 12,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.0, 0.0),
                          radius: 1.0,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                          stops: const [0.6, 1.0],
                        ),
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
  const _CascadeNames({required this.ingresados, required this.recentIds});

  @override
  State<_CascadeNames> createState() => _CascadeNamesState();
}

class _CascadeNamesState extends State<_CascadeNames>
    with SingleTickerProviderStateMixin {
  static const _itemH = 58.0;

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
        final copies = listH > 0
            ? (viewportH * 3 / listH).ceil().clamp(3, 60)
            : 3;

        return Stack(
      children: [
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

  static const _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isRecent
              ? _gold.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRecent
                ? _gold.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.05),
            width: isRecent ? 1.5 : 1,
          ),
          boxShadow: isRecent
              ? [BoxShadow(color: _gold.withValues(alpha: 0.12), blurRadius: 10)]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isRecent ? Icons.celebration_rounded : Icons.check_rounded,
              size: 14,
              color: isRecent ? _gold : Colors.white24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                invitado.nombreCompleto,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: isRecent ? FontWeight.w700 : FontWeight.w500,
                  color: isRecent ? _gold : Colors.white54,
                ),
              ),
            ),
            if (invitado.numeroMesa != null)
              Text(
                'Mesa ${invitado.numeroMesa}',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isRecent
                      ? _gold.withValues(alpha: 0.65)
                      : Colors.white24,
                  fontWeight: isRecent ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Painters customizados ──────────────────────────────────────────────────

class _ShockwavePainter extends CustomPainter {
  final double progress;
  const _ShockwavePainter(this.progress);

  static const _gold = Color(0xFFD4AF37);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.longestSide * 0.88;

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
  bool shouldRepaint(_ShockwavePainter old) => old.progress != progress;
}

class _ParticlePainter extends CustomPainter {
  final double t;
  const _ParticlePainter(this.t);

  static const _gold = Color(0xFFD4AF37);

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
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

class _ShimmerPainter extends CustomPainter {
  final double t;
  const _ShimmerPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const windowEnd = 0.28;
    if (t > windowEnd) return;

    final localT = t / windowEnd;
    final sweepX = -size.width * 0.45 + localT * size.width * 1.9;

    final shader = LinearGradient(
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.10),
        Colors.white.withValues(alpha: 0.18),
        Colors.white.withValues(alpha: 0.10),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      transform: const GradientRotation(0.45),
    ).createShader(
      Rect.fromLTWH(sweepX, 0, size.width * 0.55, size.height),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}
