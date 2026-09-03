import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/invitado.dart';
import '../../models/totem_config.dart';
import '../../services/supabase_service_provider.dart';
import '../recepcion/providers/recepcion_provider.dart';
import '../totem/providers/totem_config_provider.dart';

class ListaInvitadosScreen extends ConsumerStatefulWidget {
  final String eventoId;
  const ListaInvitadosScreen({required this.eventoId, super.key});

  @override
  ConsumerState<ListaInvitadosScreen> createState() => _ListaInvitadosScreenState();
}

enum _ListaState { loading, error, browsing, verifyingDni, welcome }

class _ListaInvitadosScreenState extends ConsumerState<ListaInvitadosScreen>
    with SingleTickerProviderStateMixin {
  /// Misma config que el tótem del salón: el invitado ve en su celular la
  /// misma foto y el mismo saludo que están proyectados en la pantalla.
  late TotemConfig _cfg = TotemConfig.defaults(widget.eventoId);

  Color get _gold => _cfg.colorAcento;

  List<Invitado> _all = [];
  List<Invitado> _filtered = [];
  Invitado? _selected;
  String _query = '';
  _ListaState _state = _ListaState.loading;
  String _errorMsg = '';

  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _dniCtrl = TextEditingController();
  final _dniFocusNode = FocusNode();
  String _dniError = '';
  int _dniIntentos = 0;
  static const _maxIntentos = 3;

  late final AnimationController _welcomeCtrl;
  late final Animation<double> _welcomeFade;
  late final Animation<Offset> _welcomeSlide;

  RealtimeChannel? _broadcastChannel;

  @override
  void initState() {
    super.initState();
    _welcomeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _welcomeFade = CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeOut);
    _welcomeSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeOutCubic));

    // Configurar canal de emisión (broadcast) para avisar al tótem en tiempo real
    if (widget.eventoId.isNotEmpty && widget.eventoId.length == 36) {
      _broadcastChannel = Supabase.instance.client.channel('totem_${widget.eventoId}');
      _broadcastChannel!.subscribe();
    }

    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    _dniCtrl.dispose();
    _dniFocusNode.dispose();
    _welcomeCtrl.dispose();
    _broadcastChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.eventoId.isEmpty || widget.eventoId.length != 36) {
      setState(() {
        _state = _ListaState.error;
        _errorMsg = widget.eventoId.length > 36 
          ? 'Error de compatibilidad: ID de evento obsoleto.\nCerrá y volvé a abrir el QR en la PC.'
          : 'No se especificó un evento válido.\nEscaneá el QR del tótem nuevamente.';
      });
      return;
    }

    try {
      final repo = ref.read(supabaseInvitadosRepositoryProvider);
      final invitados = await repo.getByEvento(widget.eventoId);
      setState(() {
        _all = invitados;
        _filtered = _solosPendientes(invitados);
        _state = _ListaState.browsing;
      });
    } catch (_) {
      setState(() {
        _state = _ListaState.error;
        _errorMsg = 'No se pudo cargar la lista.\nVerificá tu conexión e intentá de nuevo.';
      });
    }
  }

  List<Invitado> _solosPendientes(List<Invitado> lista) =>
      lista.where((i) => i.estadoIngreso == EstadoIngreso.pendiente).toList();

  void _onSearch(String q) {
    setState(() {
      _query = q.toLowerCase().trim();
      final pendientes = _solosPendientes(_all);
      _filtered = _query.isEmpty
          ? pendientes
          : pendientes.where((i) => i.nombreCompleto.toLowerCase().contains(_query)).toList();
    });
  }

  void _onSelect(Invitado inv) {
    // Si no tiene DNI cargado, saltear verificación
    if (inv.dni.trim().isEmpty) {
      _doWelcome(inv);
      return;
    }
    _dniCtrl.clear();
    _dniError = '';
    _dniIntentos = 0;
    setState(() {
      _selected = inv;
      _state = _ListaState.verifyingDni;
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _dniFocusNode.requestFocus();
    });
  }

  void _doWelcome(Invitado inv) {
    setState(() {
      _selected = inv;
      _state = _ListaState.welcome;
    });
    _welcomeCtrl.forward(from: 0);
    _registrarIngreso(inv);
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
      _doWelcome(_selected!);
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

  void _onCancelDni() {
    setState(() {
      _selected = null;
      _dniCtrl.clear();
      _dniError = '';
      _state = _ListaState.browsing;
    });
  }

  Future<void> _registrarIngreso(Invitado inv) async {
    if (inv.estadoIngreso == EstadoIngreso.ingresado) return;
    try {
      final svc = ref.read(supabaseServiceProvider);
      await svc.marcarIngresado(inv.id);

      // Disparar broadcast instantáneo al tótem para evitar la latencia del sync regular
      if (_broadcastChannel != null) {
        final checkedInGuest = inv.copyWith(estadoIngreso: EstadoIngreso.ingresado);
        await _broadcastChannel!.sendBroadcastMessage(
          event: 'checkin',
          payload: checkedInGuest.toJson(),
        );
      }

      // Marcar localmente como ingresado → desaparece de la lista al volver
      if (mounted) {
        setState(() {
          final idx = _all.indexWhere((i) => i.id == inv.id);
          if (idx != -1) {
            _all[idx] = _all[idx].copyWith(estadoIngreso: EstadoIngreso.ingresado);
          }
          final pendientes = _solosPendientes(_all);
          _filtered = _query.isEmpty
              ? pendientes
              : pendientes
                  .where((i) => i.nombreCompleto.toLowerCase().contains(_query))
                  .toList();
        });
      }
    } catch (e) {
      debugPrint('Error al registrar ingreso: $e');
    }
  }

  void _onBack() {
    setState(() {
      _selected = null;
      _state = _ListaState.browsing;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Misma fuente de verdad que el tótem: si el jefe cambia la foto o el
    // saludo, el celular del invitado lo refleja al instante.
    _cfg = ref.watch(totemConfigValueProvider(widget.eventoId));

    return Scaffold(
      backgroundColor: const Color(0xFFF2F0EB), // Gris Perla
      body: SafeArea(
        child: switch (_state) {
          _ListaState.loading => _buildLoading(),
          _ListaState.error => _buildError(),
          _ListaState.browsing => _buildBrowsing(),
          _ListaState.verifyingDni => _buildDniVerification(),
          _ListaState.welcome => _buildWelcome(),
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
          CircularProgressIndicator(color: _gold, strokeWidth: 2),
          const SizedBox(height: 24),
          Text(
            'SINCRONIZANDO...',
            style: GoogleFonts.oswald(fontSize: 12, color: Colors.black26, letterSpacing: 2, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ── ERROR ──────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 56),
            const SizedBox(height: 24),
            Text(
              _errorMsg,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 15,
                color: Colors.white60,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            _GoldButton(
              label: 'REINTENTAR',
              icon: Icons.refresh_rounded,
              onTap: () {
                setState(() => _state = _ListaState.loading);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── BROWSING ───────────────────────────────────────────────────────────────

  Widget _buildBrowsing() {
    return Column(
      children: [
        // ── Header ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
          child: Column(
            children: [
              // Logo / marca
              Text(
                _cfg.titulo,
                style: GoogleFonts.oswald(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                  color: Colors.black.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'LOCALIZÁ TU REGISTRO',
                style: GoogleFonts.oswald(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_solosPendientes(_all).length} INVITADOS POR LLEGAR',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: Colors.black26,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // ── Buscador ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _focusNode,
            style: GoogleFonts.outfit(color: Colors.black87, fontSize: 16),
            onChanged: _onSearch,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'ESCRIBÍ TU NOMBRE...',
              hintStyle: GoogleFonts.outfit(color: Colors.black26, fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: _gold, size: 22),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.black26, size: 20),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearch('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: _gold, width: 1.5),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Lista ───────────────────────────────────────────────────────────
        Expanded(
          child: _filtered.isEmpty ? _buildEmpty() : _buildList(),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _InvitadoTile(
        invitado: _filtered[i],
        onTap: () => _onSelect(_filtered[i]),
        acento: _gold,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_search_rounded, size: 56, color: Colors.white10),
            const SizedBox(height: 20),
            Text(
              _query.isEmpty
                  ? 'No hay invitados en la lista aún'
                  : 'No encontramos a "$_query"',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 15,
                color: Colors.white30,
                height: 1.5,
              ),
            ),
            if (_query.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Revisá la ortografía o acercate\nal personal del evento',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.white24,
                  height: 1.5,
                ),
              ),
            ],
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Icon(Icons.badge_rounded, color: _gold, size: 52),
            ),
            const SizedBox(height: 24),
            Text(
              'VERIFICACIÓN ELITE',
              style: GoogleFonts.oswald(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              inv.nombreCompleto.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.oswald(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _gold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 32),
            if (!bloqueado) ...[
              TextField(
                controller: _dniCtrl,
                focusNode: _dniFocusNode,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: GoogleFonts.oswald(
                  fontSize: 34,
                  color: Colors.black87,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
                onSubmitted: (_) => _onVerifyDni(),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  hintStyle: GoogleFonts.oswald(
                    fontSize: 34,
                    color: Colors.black12,
                    letterSpacing: 8,
                  ),
                  counterText: '',
                  labelText: 'DNI PARA ACCESO',
                  labelStyle: GoogleFonts.oswald(
                    fontSize: 10,
                    color: Colors.black26,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: _dniError.isNotEmpty ? Colors.redAccent.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: _dniError.isNotEmpty ? Colors.redAccent : _gold,
                      width: 2,
                    ),
                  ),
                ),
              ),
              if (_dniError.isNotEmpty) ...[
                const SizedBox(height: 12),
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
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.block_rounded, color: Colors.redAccent, size: 44),
                    const SizedBox(height: 14),
                    Text(
                      'Acceso bloqueado',
                      style: GoogleFonts.oswald(
                        fontSize: 22,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Demasiados intentos fallidos.\nConsultá al personal del evento.',
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
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _onCancelDni,
              icon: const Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white30),
              label: Text(
                'No soy yo, buscar de nuevo',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.white30,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WELCOME ────────────────────────────────────────────────────────────────

  Widget _buildWelcome() {
    final inv = _selected!;

    return FadeTransition(
      opacity: _welcomeFade,
      child: SlideTransition(
        position: _welcomeSlide,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Foto del evento, o el ícono de siempre ─────────────────
                Container(
                  padding: EdgeInsets.all(_cfg.imagenUrl != null ? 0 : 26),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _gold.withValues(
                          alpha: _cfg.imagenUrl != null ? 0.7 : 0.3),
                      width: _cfg.imagenUrl != null ? 3 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.2),
                        blurRadius: 48,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: _cfg.imagenUrl != null
                      ? ClipOval(
                          child: Image.network(
                            _cfg.imagenUrl!,
                            width: 138,
                            height: 138,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Padding(
                              padding: const EdgeInsets.all(26),
                              child: Icon(Icons.celebration_rounded,
                                  color: _gold, size: 64),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.celebration_rounded,
                          color: _gold,
                          size: 64,
                        ),
                ),

                const SizedBox(height: 32),

                // ── Bienvenida ─────────────────────────────────────────────
                Text(
                  _cfg.mensajeBienvenida.toUpperCase(),
                  style: GoogleFonts.oswald(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withValues(alpha: 0.8),
                    letterSpacing: 4,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'LOCALIZAMOS TU REGISTRO',
                  style: GoogleFonts.oswald(
                    fontSize: 12,
                    color: Colors.black26,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Nombre ────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _gold.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Sos',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.white30,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        inv.nombreCompleto,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _gold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Mesa ──────────────────────────────────────────────────
                if (inv.numeroMesa != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.table_restaurant_rounded,
                            color: Colors.white54,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TU MESA ES LA',
                              style: GoogleFonts.oswald(
                                fontSize: 10,
                                color: Colors.black26,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Nº ${inv.numeroMesa}',
                              style: GoogleFonts.oswald(
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                color: Colors.black.withValues(alpha: 0.8),
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      'Mesa por asignar — consultá al personal',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: Colors.white30,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),

                const SizedBox(height: 28),

                Text(
                  '¡Que disfrutes el evento!',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white24,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w300,
                  ),
                ),

                const SizedBox(height: 36),

                // ── Volver ────────────────────────────────────────────────
                TextButton.icon(
                  onPressed: _onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18, color: Colors.white30),
                  label: Text(
                    'No soy yo, buscar de nuevo',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: Colors.white30,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── WIDGETS AUXILIARES ──────────────────────────────────────────────────────

class _InvitadoTile extends StatelessWidget {
  final Invitado invitado;
  final VoidCallback onTap;

  /// Color de acento del evento (dorado por defecto).
  final Color _gold;

  const _InvitadoTile({
    required this.invitado,
    required this.onTap,
    required Color acento,
  }) : _gold = acento;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
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
              child: Icon(Icons.person_rounded, color: _gold, size: 18),
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
                    )
                  else
                    Text(
                      'Mesa por asignar',
                      style: GoogleFonts.outfit(fontSize: 12, color: Colors.white24),
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
              color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
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
