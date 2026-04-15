import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/invitado.dart';
import '../../models/evento.dart';
import '../../services/supabase_service_provider.dart';
import 'package:intl/intl.dart';

// ── Pantalla principal de check-in para operadores ─────────────────────────
// Flujo: PIN Entry → Buscar nombre → Verificar DNI → Bienvenida

class OpCheckinScreen extends ConsumerStatefulWidget {
  final String eventoId;
  const OpCheckinScreen({required this.eventoId, super.key});

  @override
  ConsumerState<OpCheckinScreen> createState() => _OpCheckinScreenState();
}

enum _OpState { loading, error, pinEntry, pinBlocked, searching, confirming, verifyingDni, registered, alreadyIn }

class _OpCheckinScreenState extends ConsumerState<OpCheckinScreen> with TickerProviderStateMixin {
  static const _gold = Color(0xFFD4AF37);
  static const _maxPinIntentos = 3;

  // ── Datos del evento ───────────────────────────────────────────────────────
  Evento? _evento;
  List<Invitado> _allInvitados = [];
  List<Invitado> _filtered = [];
  Invitado? _selected;
  String _errorMsg = '';
  _OpState _state = _OpState.loading;

  // ── PIN ────────────────────────────────────────────────────────────────────
  final _pinCtrl = TextEditingController();
  final _pinFocus = FocusNode();
  int _pinIntentos = 0;
  String _pinError = '';

  // ── Búsqueda ───────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';

  // ── DNI ────────────────────────────────────────────────────────────────────
  final _dniCtrl = TextEditingController();
  final _dniFocus = FocusNode();
  String _dniError = '';
  int _dniIntentos = 0;
  static const _maxDniIntentos = 3;

  // ── Animaciones ────────────────────────────────────────────────────────────
  late final AnimationController _cardCtrl;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _cardFade = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));
    _loadEvento();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pinFocus.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _dniCtrl.dispose();
    _dniFocus.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  // ── Carga datos ─────────────────────────────────────────────────────────────

  Future<void> _loadEvento() async {
    if (widget.eventoId.isEmpty) {
      setState(() {
        _state = _OpState.error;
        _errorMsg = 'No se especificó un evento. Pedile el link correcto al organizador.';
      });
      return;
    }

    try {
      final svc = ref.read(supabaseServiceProvider);
      final evento = await svc.fetchEvento(widget.eventoId);

      if (evento == null) {
        setState(() {
          _state = _OpState.error;
          _errorMsg = 'No se encontró el evento solicitado.';
        });
        return;
      }

      if (evento.pinOperador == null || evento.pinOperador!.trim().isEmpty) {
        setState(() {
          _state = _OpState.error;
          _errorMsg = 'El acceso operador no está habilitado para este evento.\nContactá al organizador.';
        });
        return;
      }

      setState(() {
        _evento = evento;
        _state = _OpState.pinEntry;
      });
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _pinFocus.requestFocus();
      });
    } catch (e) {
      setState(() {
        _state = _OpState.error;
        _errorMsg = 'No se pudo cargar el evento. Verificá tu conexión.';
      });
    }
  }

  Future<void> _loadInvitados() async {
    try {
      final svc = ref.read(supabaseServiceProvider);
      final invitados = await svc.fetchInvitados(widget.eventoId);

      setState(() {
        _allInvitados = invitados;
        _filtered = invitados
            .where((i) => i.estadoIngreso == EstadoIngreso.pendiente)
            .toList();
        _state = _OpState.searching;
      });
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _searchFocus.requestFocus();
      });
    } catch (e) {
      setState(() {
        _state = _OpState.error;
        _errorMsg = 'No se pudo cargar la lista de invitados.';
      });
    }
  }

  // ── PIN ─────────────────────────────────────────────────────────────────────

  void _onVerifyPin() {
    final entered = _pinCtrl.text.trim();
    final correct = _evento!.pinOperador!.trim();

    if (entered == correct) {
      _pinCtrl.clear();
      _loadInvitados();
    } else {
      _pinIntentos++;
      if (_pinIntentos >= _maxPinIntentos) {
        setState(() => _state = _OpState.pinBlocked);
      } else {
        setState(() {
          _pinError = 'PIN incorrecto. Intento $_pinIntentos de $_maxPinIntentos.';
          _pinCtrl.clear();
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _pinFocus.requestFocus();
        });
      }
    }
  }

  // ── Búsqueda ────────────────────────────────────────────────────────────────

  void _onSearchChanged(String q) {
    setState(() {
      _searchQuery = q.toLowerCase().trim();
      _filtered = _allInvitados
          .where((i) =>
              i.estadoIngreso == EstadoIngreso.pendiente &&
              i.nombreCompleto.toLowerCase().contains(_searchQuery))
          .toList();
    });
  }

  void _onSelectInvitado(Invitado inv) {
    setState(() {
      _selected = inv;
      _state = _OpState.confirming;
    });
  }

  void _onCancelConfirm() {
    setState(() {
      _selected = null;
      _state = _OpState.searching;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  // ── DNI ─────────────────────────────────────────────────────────────────────

  void _onGoToDni() {
    if (_selected == null) return;
    if (_selected!.dni.trim().isEmpty) {
      _doCheckin();
      return;
    }
    _dniCtrl.clear();
    _dniError = '';
    _dniIntentos = 0;
    setState(() => _state = _OpState.verifyingDni);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _dniFocus.requestFocus();
    });
  }

  void _onCancelDni() {
    setState(() {
      _dniCtrl.clear();
      _dniError = '';
      _state = _OpState.confirming;
    });
  }

  Future<void> _onVerifyDni() async {
    if (_selected == null) return;
    final entered = _dniCtrl.text.trim();
    if (entered.isEmpty) {
      setState(() => _dniError = 'Ingresá el DNI para continuar.');
      return;
    }
    if (entered == _selected!.dni.trim()) {
      await _doCheckin();
    } else {
      _dniIntentos++;
      if (_dniIntentos >= _maxDniIntentos) {
        setState(() => _dniError = 'Demasiados intentos. Consultá al organizador.');
      } else {
        setState(() {
          _dniError = 'DNI incorrecto. Intento $_dniIntentos de $_maxDniIntentos.';
          _dniCtrl.clear();
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _dniFocus.requestFocus();
        });
      }
    }
  }

  // ── Check-in ────────────────────────────────────────────────────────────────

  Future<void> _doCheckin() async {
    if (_selected == null) return;
    final existing = _allInvitados.firstWhere(
      (i) => i.id == _selected!.id,
      orElse: () => _selected!,
    );
    if (existing.estadoIngreso == EstadoIngreso.ingresado) {
      setState(() => _state = _OpState.alreadyIn);
      _cardCtrl.forward(from: 0);
      return;
    }
    try {
      final svc = ref.read(supabaseServiceProvider);
      await svc.marcarIngresado(_selected!.id);

      // Actualizar lista local
      final idx = _allInvitados.indexWhere((i) => i.id == _selected!.id);
      if (idx != -1) {
        _allInvitados[idx] = _allInvitados[idx].copyWith(estadoIngreso: EstadoIngreso.ingresado);
      }
      setState(() => _state = _OpState.registered);
      _cardCtrl.forward(from: 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al registrar el ingreso. Intentá de nuevo.'),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
        setState(() {
          _selected = null;
          _state = _OpState.searching;
        });
      }
    }
  }

  void _onNuevoIngreso() {
    setState(() {
      _selected = null;
      _dniCtrl.clear();
      _dniError = '';
      _filtered = _allInvitados
          .where((i) => i.estadoIngreso == EstadoIngreso.pendiente)
          .toList();
      _state = _OpState.searching;
      _searchCtrl.clear();
      _searchQuery = '';
    });
    _cardCtrl.reset();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: switch (_state) {
          _OpState.loading => _buildLoading(),
          _OpState.error => _buildError(),
          _OpState.pinEntry => _buildPinEntry(),
          _OpState.pinBlocked => _buildPinBlocked(),
          _OpState.searching => _buildSearching(),
          _OpState.confirming => _buildConfirming(),
          _OpState.verifyingDni => _buildDniVerification(),
          _OpState.registered => _buildRegistered(),
          _OpState.alreadyIn => _buildAlreadyIn(),
        },
      ),
    );
  }

  // ── LOADING ─────────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: _gold, strokeWidth: 2),
          const SizedBox(height: 24),
          Text(
            'Cargando...',
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.white30, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  // ── ERROR ───────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 64),
            const SizedBox(height: 24),
            Text(
              _errorMsg,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 15, color: Colors.white60, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ── PIN ENTRY ───────────────────────────────────────────────────────────────

  Widget _buildPinEntry() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Header modo operador
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge_rounded, color: Colors.purpleAccent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'MODO OPERADOR',
                    style: GoogleFonts.oswald(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.purpleAccent,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Evento info
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _gold.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    _evento?.tipoParaMostrar.toUpperCase() ?? '',
                    style: GoogleFonts.oswald(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _gold,
                      letterSpacing: 2,
                    ),
                  ),
                  if (_evento?.fechaEvento != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatFecha(_evento!.fechaEvento),
                      style: GoogleFonts.outfit(fontSize: 13, color: Colors.white38),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            Text(
              'Ingresá el PIN de operador',
              style: GoogleFonts.oswald(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 24),

            // PIN input
            TextField(
              controller: _pinCtrl,
              focusNode: _pinFocus,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.oswald(
                fontSize: 36,
                color: Colors.white,
                letterSpacing: 12,
              ),
              textAlign: TextAlign.center,
              onSubmitted: (_) => _onVerifyPin(),
              decoration: InputDecoration(
                hintText: '• • • •',
                hintStyle: GoogleFonts.outfit(fontSize: 24, color: Colors.white12),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: _pinError.isNotEmpty ? Colors.redAccent : Colors.white10,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: _pinError.isNotEmpty ? Colors.redAccent : _gold,
                    width: 1.5,
                  ),
                ),
              ),
            ),

            if (_pinError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _pinError,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 28),

            _GoldButton(
              label: 'INGRESAR',
              icon: Icons.lock_open_rounded,
              onTap: _onVerifyPin,
            ),
          ],
        ),
      ),
    );
  }

  // ── PIN BLOCKED ─────────────────────────────────────────────────────────────

  Widget _buildPinBlocked() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, color: Colors.redAccent, size: 72),
            const SizedBox(height: 24),
            Text(
              'Acceso bloqueado',
              style: GoogleFonts.oswald(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Demasiados intentos fallidos.\nContactá al organizador del evento.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 14, color: Colors.white54, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ── SEARCHING ───────────────────────────────────────────────────────────────

  Widget _buildSearching() {
    final pending = _allInvitados.where((i) => i.estadoIngreso == EstadoIngreso.pendiente).length;
    final ingresados = _allInvitados.length - pending;

    return Column(
      children: [
        // Header operador
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.badge_rounded, color: Colors.purpleAccent, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'OPERADOR',
                          style: GoogleFonts.oswald(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.purpleAccent,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _evento?.tipoParaMostrar ?? '',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MiniStat(label: 'Total', value: '${_allInvitados.length}', color: Colors.white38),
                  const SizedBox(width: 20),
                  _MiniStat(label: 'Ingresados', value: '$ingresados', color: Colors.greenAccent),
                  const SizedBox(width: 20),
                  _MiniStat(label: 'Pendientes', value: '$pending', color: _gold),
                ],
              ),
            ],
          ),
        ),

        // Buscador
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
            onChanged: _onSearchChanged,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Buscá el nombre del invitado...',
              hintStyle: GoogleFonts.outfit(color: Colors.white24, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: _gold, size: 22),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 20),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _gold, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Lista
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isEmpty
                            ? Icons.check_circle_outline_rounded
                            : Icons.search_off_rounded,
                        size: 52,
                        color: Colors.white12,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Todos los invitados ya ingresaron'
                            : 'No se encontraron resultados',
                        style: GoogleFonts.outfit(fontSize: 14, color: Colors.white30),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _InvitadoTile(
                    invitado: _filtered[i],
                    onTap: () => _onSelectInvitado(_filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  // ── CONFIRMING ──────────────────────────────────────────────────────────────

  Widget _buildConfirming() {
    final inv = _selected!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.person_rounded, color: _gold, size: 52),
            ),
            const SizedBox(height: 24),
            Text(
              '¿Es este invitado?',
              style: GoogleFonts.oswald(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  Text(
                    inv.nombreCompleto,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _gold,
                    ),
                  ),
                  if (inv.numeroMesa != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Mesa Nº ${inv.numeroMesa}',
                      style: GoogleFonts.outfit(fontSize: 13, color: Colors.white38),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            _GoldButton(
              label: 'SÍ, CONFIRMAR',
              icon: Icons.check_rounded,
              onTap: _onGoToDni,
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _onCancelConfirm,
              child: Text(
                '← No es este, buscar de nuevo',
                style: GoogleFonts.outfit(fontSize: 13, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DNI VERIFICATION ────────────────────────────────────────────────────────

  Widget _buildDniVerification() {
    final inv = _selected!;
    final bloqueado = _dniIntentos >= _maxDniIntentos;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.badge_rounded, color: _gold, size: 48),
            ),
            const SizedBox(height: 22),
            Text(
              'Verificar DNI',
              style: GoogleFonts.oswald(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              inv.nombreCompleto,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: _gold),
            ),
            const SizedBox(height: 28),

            if (!bloqueado) ...[
              TextField(
                controller: _dniCtrl,
                focusNode: _dniFocus,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.oswald(fontSize: 30, color: Colors.white, letterSpacing: 5),
                textAlign: TextAlign.center,
                onSubmitted: (_) => _onVerifyDni(),
                decoration: InputDecoration(
                  hintText: '12345678',
                  hintStyle: GoogleFonts.oswald(fontSize: 30, color: Colors.white12, letterSpacing: 5),
                  counterText: '',
                  labelText: 'Número de DNI',
                  labelStyle: GoogleFonts.outfit(fontSize: 13, color: Colors.white38, letterSpacing: 1),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _dniError.isNotEmpty ? Colors.redAccent : Colors.white10,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _dniError.isNotEmpty ? Colors.redAccent : _gold,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              if (_dniError.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _dniError,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _GoldButton(
                label: 'VERIFICAR',
                icon: Icons.login_rounded,
                onTap: _onVerifyDni,
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.block_rounded, color: Colors.redAccent, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'DNI bloqueado',
                      style: GoogleFonts.oswald(fontSize: 20, color: Colors.redAccent, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Demasiados intentos fallidos.\nDerivá al organizador del evento.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(fontSize: 13, color: Colors.white54, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: _onCancelDni,
              child: Text(
                '← Volver',
                style: GoogleFonts.outfit(fontSize: 13, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── REGISTERED ──────────────────────────────────────────────────────────────

  Widget _buildRegistered() {
    final inv = _selected!;
    return FadeTransition(
      opacity: _cardFade,
      child: SlideTransition(
        position: _cardSlide,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.greenAccent.withValues(alpha: 0.2),
                        blurRadius: 40,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 72),
                ),
                const SizedBox(height: 28),
                Text(
                  'Ingreso registrado',
                  style: GoogleFonts.oswald(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _gold.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    inv.nombreCompleto,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: _gold),
                  ),
                ),
                if (inv.numeroMesa != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.table_restaurant_rounded, color: Colors.white38, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          'Mesa Nº ${inv.numeroMesa}',
                          style: GoogleFonts.oswald(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                _GoldButton(
                  label: 'SIGUIENTE INVITADO',
                  icon: Icons.person_add_rounded,
                  onTap: _onNuevoIngreso,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── ALREADY IN ──────────────────────────────────────────────────────────────

  Widget _buildAlreadyIn() {
    final inv = _selected!;
    return FadeTransition(
      opacity: _cardFade,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_rounded, color: Colors.amberAccent, size: 72),
              const SizedBox(height: 24),
              Text(
                'Ya estaba ingresado',
                style: GoogleFonts.oswald(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                inv.nombreCompleto,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: _gold),
              ),
              if (inv.numeroMesa != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Mesa Nº ${inv.numeroMesa}',
                  style: GoogleFonts.oswald(fontSize: 22, color: Colors.white54),
                ),
              ],
              const SizedBox(height: 32),
              _GoldButton(
                label: 'SIGUIENTE INVITADO',
                icon: Icons.person_add_rounded,
                onTap: _onNuevoIngreso,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatFecha(DateTime d) {
    return DateFormat('EEEE d \'de\' MMMM', 'es_AR').format(d);
  }
}

// ── Widgets auxiliares ──────────────────────────────────────────────────────

class _InvitadoTile extends StatelessWidget {
  final Invitado invitado;
  final VoidCallback onTap;
  const _InvitadoTile({required this.invitado, required this.onTap});

  static const _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_rounded, color: _gold, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invitado.nombreCompleto,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (invitado.numeroMesa != null)
                    Text(
                      'Mesa Nº ${invitado.numeroMesa}',
                      style: GoogleFonts.outfit(fontSize: 12, color: Colors.white30),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GoldButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AF37),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.oswald(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.oswald(fontSize: 22, fontWeight: FontWeight.w900, color: color),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white30,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
