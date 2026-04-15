import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/invitado.dart';
import 'repositories/invitados_repository.dart';

class BuscarInvitadoScreen extends ConsumerStatefulWidget {
  final String eventoId;
  const BuscarInvitadoScreen({required this.eventoId, super.key});

  @override
  ConsumerState<BuscarInvitadoScreen> createState() => _BuscarInvitadoScreenState();
}

enum _PageState { loading, error, searching, confirming, verifyingDni, registered, alreadyIn }

class _BuscarInvitadoScreenState extends ConsumerState<BuscarInvitadoScreen>
    with TickerProviderStateMixin {
  static const _gold = Color(0xFFD4AF37);

  List<Invitado> _allInvitados = [];
  List<Invitado> _filtered = [];
  Invitado? _selected;
  String _searchQuery = '';
  _PageState _state = _PageState.loading;
  String _errorMsg = '';

  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _dniCtrl = TextEditingController();
  final _dniFocusNode = FocusNode();
  String _dniError = '';
  int _dniIntentos = 0;
  static const _maxIntentos = 3;

  late final AnimationController _cardCtrl;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cardFade = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));

    _loadInvitados();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    _dniCtrl.dispose();
    _dniFocusNode.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInvitados() async {
    if (widget.eventoId.isEmpty) {
      setState(() {
        _state = _PageState.error;
        _errorMsg = 'No se especificó un evento. Escaneá el QR del tótem nuevamente.';
      });
      return;
    }

    try {
      final repo = ref.read(invitadosRepositoryProvider);
      final invitados = await repo.getByEvento(widget.eventoId);

      if (mounted) {
        setState(() {
          _allInvitados = invitados;
          _filtered = invitados
              .where((i) => i.estadoIngreso == EstadoIngreso.pendiente)
              .toList();
          _state = _PageState.searching;
        });
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _focusNode.requestFocus();
        });
      }
    } catch (e) {
      setState(() {
        _state = _PageState.error;
        _errorMsg = 'No se pudo cargar la lista de invitados. Verificá tu conexión.';
      });
    }
  }

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
      _state = _PageState.confirming;
    });
  }

  void _onCancelConfirm() {
    setState(() {
      _selected = null;
      _state = _PageState.searching;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onGoToDni() {
    if (_selected == null) return;
    // Si el invitado no tiene DNI cargado, saltear verificación
    if (_selected!.dni.trim().isEmpty) {
      _doCheckin();
      return;
    }
    _dniCtrl.clear();
    _dniError = '';
    _dniIntentos = 0;
    setState(() => _state = _PageState.verifyingDni);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _dniFocusNode.requestFocus();
    });
  }

  void _onCancelDni() {
    setState(() {
      _dniCtrl.clear();
      _dniError = '';
      _state = _PageState.confirming;
    });
  }

  Future<void> _onVerifyDni() async {
    if (_selected == null) return;
    final ingresado = _dniCtrl.text.trim();
    if (ingresado.isEmpty) {
      setState(() => _dniError = 'Ingresá tu DNI para continuar.');
      return;
    }

    final correcto = _selected!.dni.trim();
    if (ingresado == correcto) {
      await _doCheckin();
    } else {
      _dniIntentos++;
      if (_dniIntentos >= _maxIntentos) {
        setState(() {
          _dniError = 'Demasiados intentos fallidos. Consultá en recepción.';
        });
      } else {
        setState(() {
          _dniError = 'DNI incorrecto. Intento $_dniIntentos de $_maxIntentos.';
          _dniCtrl.clear();
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _dniFocusNode.requestFocus();
        });
      }
    }
  }

  Future<void> _doCheckin() async {
    if (_selected == null) return;

    final existing = _allInvitados.firstWhere(
      (i) => i.id == _selected!.id,
      orElse: () => _selected!,
    );
    if (existing.estadoIngreso == EstadoIngreso.ingresado) {
      setState(() => _state = _PageState.alreadyIn);
      _cardCtrl.forward(from: 0);
      return;
    }

    try {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.marcarIngreso(_selected!.id);

      setState(() => _state = _PageState.registered);
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
          _state = _PageState.searching;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: switch (_state) {
          _PageState.loading => _buildLoading(),
          _PageState.error => _buildError(),
          _PageState.searching => _buildSearch(),
          _PageState.confirming => _buildConfirm(),
          _PageState.verifyingDni => _buildDniVerification(),
          _PageState.registered => _buildRegistered(),
          _PageState.alreadyIn => _buildAlreadyIn(),
        },
      ),
    );
  }

  // ── LOADING ────────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: _gold, strokeWidth: 2),
          const SizedBox(height: 24),
          Text(
            'Cargando invitados...',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: Colors.white38,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ── ERROR ──────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 64),
            const SizedBox(height: 24),
            Text(
              _errorMsg,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 15,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            _GoldButton(
              label: 'REINTENTAR',
              icon: Icons.refresh_rounded,
              onTap: () {
                setState(() => _state = _PageState.loading);
                _loadInvitados();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── SEARCH ─────────────────────────────────────────────────────────────────

  Widget _buildSearch() {
    final pending = _allInvitados.where((i) => i.estadoIngreso == EstadoIngreso.pendiente).length;
    final ingresados = _allInvitados.length - pending;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
          child: Column(
            children: [
              Text(
                'JUNIOR EVENTOS',
                style: GoogleFonts.oswald(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 5,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Registro de ingreso',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 20),
              // Mini stats
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MiniStat(label: 'Total', value: '${_allInvitados.length}', color: Colors.white54),
                  const SizedBox(width: 16),
                  _MiniStat(label: 'Ingresados', value: '$ingresados', color: Colors.greenAccent),
                  const SizedBox(width: 16),
                  _MiniStat(label: 'Pendientes', value: '$pending', color: _gold),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _focusNode,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Buscá tu nombre...',
              hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 15),
              prefixIcon: const Icon(Icons.search_rounded, color: _gold, size: 22),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
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
                borderSide: BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _gold, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // List
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
                        size: 56,
                        color: Colors.white12,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Todos los invitados ya ingresaron'
                            : 'No se encontraron resultados',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: Colors.white30,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final inv = _filtered[i];
                    return _InvitadoTile(
                      invitado: inv,
                      onTap: () => _onSelectInvitado(inv),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── CONFIRMING ─────────────────────────────────────────────────────────────

  Widget _buildConfirm() {
    final inv = _selected!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.person_rounded, color: _gold, size: 52),
            ),
            const SizedBox(height: 28),
            Text(
              '¿Sos vos?',
              style: GoogleFonts.oswald(
                fontSize: 28,
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
              child: Text(
                inv.nombreCompleto,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _gold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 36),
            _GoldButton(
              label: 'SÍ, SOY YO',
              icon: Icons.check_rounded,
              onTap: _onGoToDni,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _onCancelConfirm,
              child: Text(
                'No soy yo, buscar de nuevo',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.white38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DNI VERIFICATION ───────────────────────────────────────────────────────

  Widget _buildDniVerification() {
    final inv = _selected!;
    final bloqueado = _dniIntentos >= _maxIntentos;
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
              child: const Icon(Icons.badge_rounded, color: _gold, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Verificá tu identidad',
              style: GoogleFonts.oswald(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              inv.nombreCompleto,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _gold,
              ),
            ),
            const SizedBox(height: 28),
            if (!bloqueado) ...[
              TextField(
                controller: _dniCtrl,
                focusNode: _dniFocusNode,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: GoogleFonts.oswald(
                  fontSize: 28,
                  color: Colors.white,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
                onSubmitted: (_) => _onVerifyDni(),
                decoration: InputDecoration(
                  hintText: '12345678',
                  hintStyle: GoogleFonts.oswald(
                    fontSize: 28,
                    color: Colors.white12,
                    letterSpacing: 4,
                  ),
                  counterText: '',
                  labelText: 'Número de DNI',
                  labelStyle: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white38,
                    letterSpacing: 1,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _dniError.isNotEmpty ? Colors.redAccent : Colors.white12,
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
                label: 'INGRESAR',
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
                      'Acceso bloqueado',
                      style: GoogleFonts.oswald(
                        fontSize: 20,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Demasiados intentos fallidos.\nConsultá en recepción.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Colors.white54,
                        height: 1.5,
                      ),
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
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.white38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── REGISTERED ─────────────────────────────────────────────────────────────

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
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.celebration_rounded, color: _gold, size: 72),
                ),
                const SizedBox(height: 32),
                Text(
                  '¡Bienvenido!',
                  style: GoogleFonts.oswald(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _gold.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    inv.nombreCompleto,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _gold,
                    ),
                  ),
                ),
                if (inv.numeroMesa != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.table_restaurant_rounded,
                          color: Colors.white54,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tu mesa',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: Colors.white38,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              'Nº ${inv.numeroMesa}',
                              style: GoogleFonts.oswald(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Text(
                  '¡Que disfrutes el evento!',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white38,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── ALREADY IN ─────────────────────────────────────────────────────────────

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
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.greenAccent,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                'Ya estás registrado',
                style: GoogleFonts.oswald(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                inv.nombreCompleto,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _gold,
                ),
              ),
              if (inv.numeroMesa != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Mesa Nº ${inv.numeroMesa}',
                  style: GoogleFonts.oswald(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Text(
                '¡Que disfrutes el evento!',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── WIDGETS AUXILIARES ─────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_rounded, color: _gold, size: 20),
            ),
            const SizedBox(width: 16),
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
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white38,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 22),
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
          style: GoogleFonts.oswald(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
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
