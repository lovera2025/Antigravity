import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../models/invitado.dart';
import '../../../main.dart' show kWebBaseUrl;

class TotemDisplay extends StatefulWidget {
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
  State<TotemDisplay> createState() => _TotemDisplayState();
}

class _TotemDisplayState extends State<TotemDisplay> with TickerProviderStateMixin {
  static const _gold = Color(0xFFD4AF37);

  // ── Animaciones bienvenida ─────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _particleCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _handshakeCtrl; // Nueva animación de apertura

  late final Animation<double> _bgFade;
  late final Animation<double> _goldBloom;
  late final Animation<double> _shockwave;
  late final Animation<double> _cardScale;
  late final Animation<double> _iconFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _nameReveal;
  late final Animation<Offset> _mesaSlide;
  late final Animation<double> _handshakeFade;
  late final Animation<double> _handshakeScale;

  // ── Stream / cola ──────────────────────────────────────────────────────────
  StreamSubscription<List<Invitado>>? _sub;
  RealtimeChannel? _broadcastChannel;
  
  final _queue = <Invitado>[];
  final _processedIds = <String>{};
  Invitado? _current;
  bool _initialized = false;

  // ── Lista ingresados ───────────────────────────────────────────────────────
  final _ingresados = <Invitado>[];   // orden: más recientes primero
  final _recentIds = <String>{};      // destacados con brillo dorado

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer? _displayTimer;
  Timer? _cleanupTimer;

  // ── Reconexión ────────────────────────────────────────────────────────────
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _isConnected = true;

  late final SupabaseService svc;

  @override
  void initState() {
    super.initState();
    _setupSystemUI();
    svc = widget.svc ?? SupabaseService();
    _setupAnimations();
    _connect();
    _startCleanupTimer();
    _setupInterWindowChannel();
  }

  void _setupInterWindowChannel() {
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      switch (call.method) {
        case 'refresh':
          _connect(); // Forzar reconexión del stream
          return null;
        case 'list_reset':
          _handleListReset();
          return null;
        case 'guest_checkin':
          if (call.arguments != null) {
            final data = jsonDecode(call.arguments as String);
            final guest = Invitado.fromJson(data);
            _handleManualIncoming(guest);
          }
          return null;
      }
      return null;
    });
  }

  void _handleManualIncoming(Invitado guest) {
    if (!mounted) return;
    if (_processedIds.contains(guest.id)) return;
    
    _queue.add(guest);
    _processedIds.add(guest.id);
    setState(() => _ingresados.insert(0, guest));
    
    if (_current == null) _showNext();
  }

  void _handleListReset() {
    if (!mounted) return;
    setState(() {
      _ingresados.clear();
      _queue.clear();
      _processedIds.clear();
      _recentIds.clear();
      _current = null;
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

    // Handshake
    _handshakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _handshakeFade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _handshakeCtrl, curve: Curves.easeInOut));

    _handshakeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 60),
    ]).animate(CurvedAnimation(parent: _handshakeCtrl, curve: Curves.easeOutCubic));

    _handshakeCtrl.forward();
  }

  // ── Conexión y datos ───────────────────────────────────────────────────────

  void _connect() {
    try {
      _sub?.cancel();
      _sub = svc.streamInvitados(widget.eventoId).listen(
        _onData,
        onError: _onError,
        cancelOnError: false,
      );

      // Usar Supabase Realtime Broadcast para reacción INMEDIATA sin esperar replicación
      if (_broadcastChannel == null) {
        _broadcastChannel = svc.client.channel('totem_${widget.eventoId}');
        _broadcastChannel!.onBroadcast(event: 'checkin', callback: (payload) {
          final data = payload['payload'];
          if (data != null && mounted) {
            final guest = Invitado.fromJson(data);
            _handleManualIncoming(guest);
          }
        });
        _broadcastChannel!.subscribe();
      }

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

    if (!_initialized) {
      // Primera carga: poblar lista y processedIds sin disparar bienvenidas.
      final yaIngresados = invitados
          .where((i) => i.estadoIngreso == EstadoIngreso.ingresado)
          .toList();
      for (var inv in yaIngresados) {
        _processedIds.add(inv.id);
      }
      setState(() {
        _ingresados
          ..clear()
          ..addAll(yaIngresados.reversed); // más recientes al fondo en carga inicial
      });
      _initialized = true;
      if (!_isConnected) setState(() => _isConnected = true);
      return;
    }

    // Cargas siguientes: detectar nuevos ingresos.
    for (var invitado in invitados) {
      if (invitado.estadoIngreso == EstadoIngreso.ingresado &&
          !_processedIds.contains(invitado.id)) {
        if (_current?.id == invitado.id) continue;
        if (_queue.any((i) => i.id == invitado.id)) continue;
        _queue.add(invitado);
        _processedIds.add(invitado.id);

        // Agregar al inicio de la lista (más reciente primero)
        setState(() => _ingresados.insert(0, invitado));
      }
    }

    // Remover los que ya no están en la lista (vaciar lista o deshacer ingreso)
    final actualesIngresadosIds = invitados
        .where((i) => i.estadoIngreso == EstadoIngreso.ingresado)
        .map((i) => i.id)
        .toSet();

    if (_ingresados.any((inv) => !actualesIngresadosIds.contains(inv.id))) {
      setState(() {
        _ingresados.removeWhere((inv) => !actualesIngresadosIds.contains(inv.id));
        _processedIds.removeWhere((id) => !actualesIngresadosIds.contains(id));
      });
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

  // ── Mostrar tarjeta de bienvenida ──────────────────────────────────────────

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

  @override
  void dispose() {
    _broadcastChannel?.unsubscribe();
    _sub?.cancel();
    _displayTimer?.cancel();
    _reconnectTimer?.cancel();
    _cleanupTimer?.cancel();
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _particleCtrl.dispose();
    _shimmerCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWidescreen = constraints.maxWidth > constraints.maxHeight * 1.2;
          
          return Stack(
            children: [
              const _EliteAtmosphericBackground(),
              Column(
                children: [
                  Expanded(
                    flex: isWidescreen ? 100 : 55,
                    child: _buildQRSection(constraints),
                  ),
                  if (!isWidescreen)
                    Expanded(
                      flex: 45,
                      child: _buildIngresadosPanel(),
                    ),
                ],
              ),
              // En widescreen, el panel de ingresados flota a un lado
              if (isWidescreen)
                Positioned(
                  top: 80,
                  right: 40,
                  bottom: 40,
                  width: constraints.maxWidth * 0.3,
                  child: _buildIngresadosPanel(),
                ),
                
              if (_current != null) _buildWelcomeCard(constraints),
              _buildHandshakeOverlay(), 
              _buildConnectionIndicator(),
              _buildStatsIndicator(),
              if (widget.showExitButton) _buildExitButton(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHandshakeOverlay() {
    return AnimatedBuilder(
      animation: _handshakeCtrl,
      builder: (context, child) {
        if (_handshakeFade.value <= 0) return const SizedBox.shrink();
        
        return Opacity(
          opacity: _handshakeFade.value,
          child: Container(
            color: const Color(0xFFF2F0EB), // Gris Perla
            child: Center(
              child: Transform.scale(
                scale: _handshakeScale.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _gold.withValues(alpha: 0.2), width: 1),
                      ),
                      child: Image.asset(
                        'assets/icons/logo-transparent-final.png',
                        width: 180,
                        height: 180,
                        color: _gold,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'ESTABLECIENDO CONEXIÓN'.toUpperCase(),
                      style: GoogleFonts.oswald(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: _gold.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'JUNIOR EVENTOS • ELITE SYSTEM',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2,
                        color: Colors.black.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExitButton(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: _ExitButton(
        onExit: () async {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          if (widget.windowId != null) {
            await WindowController.fromWindowId(widget.windowId!).hide();
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        },
      ),
    );
  }

  // ── Sección superior: Logo + QR ────────────────────────────────────────────

  Widget _buildQRSection(BoxConstraints constraints) {
    final qrUrl = '$kWebBaseUrl/lista?evento=${widget.eventoId}';
    final isWidescreen = constraints.maxWidth > constraints.maxHeight * 1.2;
    final scale = (constraints.maxHeight / 900).clamp(0.7, 1.2);

    return Container(
      padding: EdgeInsets.only(
        left: isWidescreen ? 60 : 20,
        right: isWidescreen ? constraints.maxWidth * 0.35 : 20,
      ),
      alignment: isWidescreen ? Alignment.centerLeft : Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: isWidescreen ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Logo con resplandor Plata Perla
            FadeTransition(
              opacity: _pulseCtrl.drive(Tween(begin: 0.3, end: 0.6)),
              child: Container(
                width: 140 * scale,
                height: 140 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE2E2E2).withValues(alpha: 0.1),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/icons/logo-transparent-final.png',
                  fit: BoxFit.contain,
                  color: const Color(0xFFF2F0EB), // Plata Perla
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'JUNIOR EVENTOS',
              style: GoogleFonts.oswald(
                fontSize: 38 * scale,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: const Color(0xFFE2E2E2).withValues(alpha: 0.4),
              ),
            ),
            SizedBox(height: 40 * scale),
            // QR en contenedor Glassmorphic de Lujo
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, child) => Transform.scale(
                scale: 1.0 + (_pulseCtrl.value * 0.02),
                child: child,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: const Color(0xFFE2E2E2).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data: qrUrl,
                            version: QrVersions.auto,
                            size: 180 * scale,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF121212),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF121212),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'BIENVENIDO',
                          style: GoogleFonts.oswald(
                            fontSize: 14 * scale,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 6,
                            color: const Color(0xFFE2E2E2),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'ESCANEÁ PARA INGRESAR',
                          style: GoogleFonts.outfit(
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 2,
                            color: const Color(0xFFE2E2E2).withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
          // ── Header ─────────────────────────────────────────────────────────
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
                if (_ingresados.isNotEmpty)
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
                  ),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta de bienvenida — Spotlight Entrance ────────────────────────────

  Widget _buildWelcomeCard(BoxConstraints constraints) {
    final scale = (constraints.maxHeight / 900).clamp(0.7, 1.4);
    const perla = Color(0xFFE2E2E2);

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

              // ── Onda de choque ────────────────────────────────────────────
              IgnorePointer(
                child: CustomPaint(
                  painter: _ShockwavePainter(_shockwave.value),
                  child: const SizedBox.expand(),
                ),
              ),

              // ── Partículas doradas flotantes ──────────────────────────────
              if (_bgFade.value > 0.4)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ParticlePainter(_particleCtrl.value),
                    child: const SizedBox.expand(),
                  ),
                ),

              // ── Tarjeta central ───────────────────────────────────────────
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
                              // Icono de celebración
                              FadeTransition(
                                opacity: _iconFade,
                                child: Container(
                                  padding: EdgeInsets.all(20 * scale),
                                  decoration: BoxDecoration(
                                    color: perla.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: perla.withValues(alpha: 0.30),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '🤝',
                                    style: TextStyle(fontSize: 72 * scale),
                                  ),
                                ),
                              ),
                              SizedBox(height: 22 * scale),

                              // "¡Bienvenido!" con slide desde abajo
                              ClipRect(
                                child: SlideTransition(
                                  position: _titleSlide,
                                  child: FadeTransition(
                                    opacity: _titleFade,
                                    child: Text(
                                      '¡Bienvenido!',
                                      style: GoogleFonts.oswald(
                                        fontSize: 50 * scale,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 18 * scale),

                              // Nombre — reveal desde el centro hacia afuera
                              ClipRect(
                                child: Align(
                                  alignment: Alignment.center,
                                  widthFactor: _nameReveal.value.clamp(0.0, 1.0),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 22 * scale,
                                      vertical: 11 * scale,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          perla.withValues(alpha: 0.22),
                                          perla.withValues(alpha: 0.08),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: perla.withValues(alpha: 0.40),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      _current!.nombreCompleto,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                        fontSize: 42 * scale,
                                        fontWeight: FontWeight.w800,
                                        color: perla,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Mesa — desliza desde la derecha
                              if (_current!.numeroMesa != null) ...[
                                SizedBox(height: 22 * scale),
                                ClipRect(
                                  child: SlideTransition(
                                    position: _mesaSlide,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10 * scale),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.07),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.table_restaurant_rounded,
                                            color: Colors.white60,
                                            size: 24 * scale,
                                          ),
                                        ),
                                        SizedBox(width: 14 * scale),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Tu mesa',
                                              style: GoogleFonts.outfit(
                                                fontSize: 14 * scale,
                                                fontWeight: FontWeight.w400,
                                                color: Colors.white54,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                            Text(
                                              'Nº ${_current!.numeroMesa}',
                                              style: GoogleFonts.oswald(
                                                fontSize: 34 * scale,
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
  const _ShockwavePainter(this.progress);

  static const _gold = Color(0xFFD4AF37);

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
  bool shouldRepaint(_ShockwavePainter old) => old.progress != progress;
}

// ── Partículas doradas flotantes ──────────────────────────────────────────

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

// ── Barrido de brillo diagonal (shimmer) ─────────────────────────────────

class _ShimmerPainter extends CustomPainter {
  final double t;
  const _ShimmerPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Dispara una sola vez por ciclo en la ventana 0.0 → 0.28
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

// ── Botón de salida para modo tótem web ──────────────────────────────────────

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
