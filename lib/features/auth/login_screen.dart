import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _successMessage;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _errorMessage = null;
      _successMessage = null;
    });
    _animCtrl.reset();
    _animCtrl.forward();
  }

  Future<void> _signIn() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Completá el correo y la contraseña.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final supabase = ref.read(supabaseProvider);
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on AuthException catch (e) {
      setState(() => _errorMessage = _translateError(e.message));
    } catch (_) {
      setState(() =>
          _errorMessage = 'Error inesperado. Verificá tu conexión.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Completá todos los campos.');
      return;
    }
    if (pass != confirm) {
      setState(() => _errorMessage = 'Las contraseñas no coinciden.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _errorMessage =
          'La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final supabase = ref.read(supabaseProvider);
      final res = await supabase.auth.signUp(email: email, password: pass);
      if (res.session != null) {
        // Sesión activa → ingresó directo (confirmación de email OFF en Supabase)
        // El AuthWrapper redirige automáticamente.
      } else {
        // Supabase requiere confirmación por email
        if (mounted) {
          setState(() {
            _successMessage =
                '✅ Cuenta creada. Revisá tu bandeja de entrada ($email) para confirmar y luego ingresá.';
            _isRegisterMode = false;
          });
        }
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = _translateError(e.message));
    } catch (_) {
      setState(
          () => _errorMessage = 'Error inesperado al crear la cuenta.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _translateError(String msg) {
    if (msg.contains('Invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (msg.contains('Email not confirmed')) {
      return 'Confirmá tu correo antes de ingresar.';
    }
    if (msg.contains('already registered')) {
      return 'Este correo ya tiene una cuenta. Ingresá en la pestaña INGRESAR.';
    }
    if (msg.contains('Password should be at least')) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0D0B14), const Color(0xFF0A0A0A)]
                : [const Color(0xFFF8F9FA), const Color(0xFFE9ECEF)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Card(
                  elevation: isDark ? 0 : 10,
                  shadowColor: Colors.black.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: isDark
                        ? BorderSide(
                            color: gold.withValues(alpha: 0.08))
                        : BorderSide.none,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 36, vertical: 44),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Logo ─────────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [
                              gold.withValues(alpha: 0.5),
                              gold.withValues(alpha: 0.1),
                            ]),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark
                                  ? const Color(0xFF141414)
                                  : Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: gold.withValues(alpha: 0.2),
                                  blurRadius: 30,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/icons/isotipo-ej.png',
                                height: 60,
                                width: 60,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.celebration_rounded,
                                  size: 44,
                                  color: gold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Título dinámico ───────────────────────────────
                        Text(
                          _isRegisterMode ? 'Crear cuenta' : 'Bienvenido',
                          style: GoogleFonts.oswald(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isRegisterMode
                              ? 'Registrate para acceder al sistema'
                              : 'Ingresá a Junior Eventos',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color:
                                isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Toggle INGRESAR / CREAR CUENTA ───────────────
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              _buildToggleTab(
                                  'INGRESAR', !_isRegisterMode, gold, isDark),
                              _buildToggleTab(
                                  'CREAR CUENTA', _isRegisterMode, gold, isDark),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Mensajes de estado ────────────────────────────
                        if (_errorMessage != null)
                          _buildStatusBox(_errorMessage!,
                              Colors.redAccent, Icons.error_outline),
                        if (_successMessage != null)
                          _buildStatusBox(_successMessage!,
                              Colors.greenAccent, Icons.check_circle_outline),

                        // ── Campo Email ───────────────────────────────────
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Correo Electrónico',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                        ),
                        const SizedBox(height: 16),

                        // ── Campo Password ────────────────────────────────
                        TextField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon:
                                const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () => setState(
                                  () => _obscurePassword =
                                      !_obscurePassword),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          textInputAction: _isRegisterMode
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onSubmitted:
                              _isRegisterMode ? null : (_) => _signIn(),
                        ),

                        // ── Confirmar password + info PIN (solo registro) ─
                        if (_isRegisterMode) ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _confirmPasswordController,
                            decoration: const InputDecoration(
                              labelText: 'Confirmar contraseña',
                              prefixIcon:
                                  Icon(Icons.lock_reset_outlined),
                            ),
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _signUp(),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: gold.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: gold.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline,
                                    color: gold, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Una vez dentro, configurá tu PIN de administrador en Ajustes → Seguridad.',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: gold,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 28),

                        // ── Botón principal ───────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : (_isRegisterMode
                                    ? _signUp
                                    : _signIn),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: gold,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 4,
                              shadowColor:
                                  gold.withValues(alpha: 0.4),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.black,
                                        strokeWidth: 2),
                                  )
                                : Text(
                                    _isRegisterMode
                                        ? 'CREAR CUENTA'
                                        : 'INGRESAR',
                                    style: GoogleFonts.oswald(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ── Link alternativo ──────────────────────────────
                        TextButton(
                          onPressed: _toggleMode,
                          child: Text(
                            _isRegisterMode
                                ? '¿Ya tenés cuenta? Ingresá aquí'
                                : '¿Primera vez? Creá tu cuenta',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.black38,
                            ),
                          ),
                        ),
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

  Widget _buildToggleTab(
      String label, bool isActive, Color gold, bool isDark) {
    return Expanded(
      child: GestureDetector(
        onTap: isActive ? null : _toggleMode,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? const Color(0xFF1E1538) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8)
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.oswald(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: isActive
                    ? gold
                    : (isDark ? Colors.white38 : Colors.black38),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBox(String msg, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                  color: color, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
