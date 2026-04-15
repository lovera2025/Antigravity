import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/invitado.dart';
import '../recepcion/repositories/invitados_repository.dart';
import '../recepcion/providers/recepcion_provider.dart';

class TotemCheckinScreen extends ConsumerStatefulWidget {
  final String eventoId;

  const TotemCheckinScreen({
    required this.eventoId,
    super.key,
  });

  @override
  ConsumerState<TotemCheckinScreen> createState() => _TotemCheckinScreenState();
}

class _TotemCheckinScreenState extends ConsumerState<TotemCheckinScreen> {
  static const _gold = Color(0xFFD4AF37);
  
  // Eliminamos SupabaseService
  
  final _searchController = TextEditingController();
  final _dniController = TextEditingController();
  
  List<Invitado> _invitados = [];
  List<Invitado> _filteredInvitados = [];
  Invitado? _selectedInvitado;
  
  bool _isLoading = false;
  bool _isValidating = false;
  String? _errorMessage;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    // Cargamos los datos iniciales
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInvitados();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dniController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitados() async {
    setState(() => _isLoading = true);
    try {
      final repository = kIsWeb 
          ? ref.read(supabaseInvitadosRepositoryProvider) 
          : ref.read(invitadosRepositoryProvider);
      
      // Si es web, usamos el repositorio de Supabase que es tipado igual para estos métodos
      final invitados = await (repository as dynamic).getByEvento(widget.eventoId);
      
      setState(() {
        _invitados = (invitados as List<Invitado>).where((i) => i.estadoIngreso == EstadoIngreso.pendiente).toList();
        _filteredInvitados = [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar invitados';
      });
    }
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() => _filteredInvitados = []);
      return;
    }

    final filtered = _invitados
        .where((inv) => inv.nombreCompleto.toLowerCase().contains(query.toLowerCase()))
        .take(5)
        .toList();

    setState(() => _filteredInvitados = filtered);
  }

  void _selectInvitado(Invitado invitado) {
    setState(() {
      _selectedInvitado = invitado;
      _searchController.clear();
      _filteredInvitados = [];
      _errorMessage = null;
    });
  }

  Future<void> _validarDni() async {
    if (_dniController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Por favor ingresa tu DNI');
      return;
    }

    setState(() {
      _isValidating = true;
      _errorMessage = null;
    });

    try {
      final repository = kIsWeb 
          ? ref.read(supabaseInvitadosRepositoryProvider) 
          : ref.read(invitadosRepositoryProvider);

      final result = await (repository as dynamic).validarDniYMarcarIngreso(
        invitadoId: _selectedInvitado!.id,
        dniIngresado: _dniController.text.trim(),
      );

      if (result['success'] == true) {
        // DNI correcto - mostrar éxito
        setState(() {
          _showSuccess = true;
          _isValidating = false;
        });

        // Esperar 3 segundos y volver al inicio
        await Future.delayed(const Duration(seconds: 3));
        _resetForm();
      } else {
        // DNI incorrecto
        final error = result['error'] as String;
        final message = result['message'] as String;

        setState(() {
          _isValidating = false;
          _errorMessage = message;
          _dniController.clear();
        });

        if (error == 'bloqueado') {
          // Esperar 3 segundos y resetear
          await Future.delayed(const Duration(seconds: 3));
          _resetForm();
        }
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
        _errorMessage = 'Error al validar DNI. Intenta nuevamente.';
      });
    }
  }

  void _resetForm() {
    setState(() {
      _selectedInvitado = null;
      _searchController.clear();
      _dniController.clear();
      _filteredInvitados = [];
      _errorMessage = null;
      _showSuccess = false;
    });
    _loadInvitados();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _showSuccess ? _buildSuccessScreen() : _buildMainScreen(),
      ),
    );
  }

  Widget _buildMainScreen() {
    if (_selectedInvitado != null) {
      return _buildDniValidationScreen();
    }
    return _buildSearchScreen();
  }

  Widget _buildSearchScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo o título
            Icon(
              Icons.search_rounded,
              size: 80,
              color: _gold.withAlpha(153),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onLongPress: () {
                // Ya no hay cerrojos que quitar, solo volvemos al Dashboard
                if (mounted) {
                  Navigator.pop(context);
                }
              },
              child: Text(
                'BUSCÁ TU NOMBRE',
                style: GoogleFonts.oswald(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Escribí tu nombre completo',
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 40),

            // Campo de búsqueda
            Container(
              constraints: const BoxConstraints(maxWidth: 500),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Ej: Juan García',
                  hintStyle: GoogleFonts.outfit(
                    color: Colors.white30,
                  ),
                  prefixIcon: Icon(Icons.person_search, color: _gold, size: 28),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: _gold.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: _gold.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: _gold, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Lista de resultados
            if (_filteredInvitados.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxWidth: 500),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _gold.withValues(alpha: 0.2)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filteredInvitados.length,
                  separatorBuilder: (_, index) => Divider(
                    color: Colors.white.withValues(alpha: 0.1),
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final invitado = _filteredInvitados[index];
                    return ListTile(
                      onTap: () => _selectInvitado(invitado),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      title: Text(
                        invitado.nombreCompleto,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: invitado.numeroMesa != null
                          ? Text(
                              'Mesa ${invitado.numeroMesa}',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: _gold.withValues(alpha: 0.7),
                              ),
                            )
                          : null,
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        color: _gold,
                        size: 20,
                      ),
                    );
                  },
                ),
              ),

            if (_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: CircularProgressIndicator(color: _gold),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDniValidationScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1C0F35),
                const Color(0xFF0C0518),
              ],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: _gold.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono de verificación
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _gold.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.verified_user_rounded,
                  size: 60,
                  color: _gold,
                ),
              ),

              const SizedBox(height: 24),

              // Nombre del invitado
              Text(
                '¿Eres tú?',
                style: GoogleFonts.oswald(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                _selectedInvitado!.nombreCompleto,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                  letterSpacing: 0.5,
                ),
              ),

              if (_selectedInvitado!.numeroMesa != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Mesa ${_selectedInvitado!.numeroMesa}',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    color: Colors.white54,
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Campo DNI
              TextField(
                controller: _dniController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Ingresá tu DNI',
                  hintStyle: GoogleFonts.outfit(
                    color: Colors.white30,
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _gold.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _gold.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _gold, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Botones
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isValidating ? null : _resetForm,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.white30),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'CANCELAR',
                        style: GoogleFonts.oswald(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isValidating ? null : _validarDni,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isValidating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'VERIFICAR',
                              style: GoogleFonts.oswald(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: Colors.black,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animación de éxito
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.greenAccent.withValues(alpha: 0.4),
                width: 3,
              ),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 120,
              color: Colors.greenAccent,
            ),
          ),

          const SizedBox(height: 40),

          Text(
            '¡BIENVENIDO!',
            style: GoogleFonts.oswald(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            _selectedInvitado!.nombreCompleto,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: _gold,
            ),
          ),

          if (_selectedInvitado!.numeroMesa != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _gold.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.table_restaurant_rounded,
                    color: _gold,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Mesa ${_selectedInvitado!.numeroMesa}',
                    style: GoogleFonts.oswald(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: _gold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
