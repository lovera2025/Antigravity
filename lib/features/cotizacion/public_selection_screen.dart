import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../main.dart';
import '../../../models/servicio.dart';
import '../common/widgets/animated_background.dart';

class PublicSelectionScreen extends ConsumerStatefulWidget {
  const PublicSelectionScreen({super.key});

  @override
  ConsumerState<PublicSelectionScreen> createState() => _PublicSelectionScreenState();
}

class _PublicSelectionScreenState extends ConsumerState<PublicSelectionScreen> {
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  List<Servicio> _servicios = [];
  final Set<String> _selectedIds = {};
  
  final _nombreController = TextEditingController();
  final _celularController = TextEditingController();
  final _comentarioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchServicios();
  }

  Widget _buildComentarioInput() {
    return TextField(
      controller: _comentarioController,
      maxLines: 3,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Ej: Fiesta íntima, mucha pista y luces, nada muy formal...',
        hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _celularController.dispose();
    _comentarioController.dispose();
    super.dispose();
  }

  Future<void> _fetchServicios() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    final supabase = ref.read(supabaseProvider);
    
    // Protocolo "Vanguardia": Si en 5 segundos no carga, usamos datos de demostración
    // para que el cliente nunca vea una pantalla de carga infinita.
    try {
      final response = await supabase.from('servicios')
          .select('id, nombre')
          .order('nombre')
          .timeout(const Duration(seconds: 5));

      if (mounted) {
        setState(() {
          _servicios = (response as List).map((e) => Servicio.fromJson({
            'id': e['id'],
            'nombre': e['nombre'],
          })).toList();
          
          if (_servicios.isEmpty) {
            _errorMessage = "No se encontraron servicios. ¿Querés usar el catálogo de prueba?";
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Timeout o Error en PublicSelection: $e. Activando modo Demo Élite.');
      if (mounted) {
        setState(() {
          // Cargamos servicios de prueba para que la experiencia no se rompa
          _servicios = [
            Servicio(id: '1', nombre: 'Sonido Profesional (Demo)', categoria: 'General'),
            Servicio(id: '2', nombre: 'Iluminación Robótica (Demo)', categoria: 'General'),
            Servicio(id: '3', nombre: 'DJ Set Vanguardia (Demo)', categoria: 'General'),
            Servicio(id: '4', nombre: 'Pantallas LED Gigantes (Demo)', categoria: 'General'),
            Servicio(id: '5', nombre: 'Efectos Especiales (Demo)', categoria: 'General'),
          ];
          _isLoading = false;
        });
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _enviarSolicitud() async {
    if (_nombreController.text.isEmpty || _celularController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completá tu nombre y celular para que podamos contactarte')),
      );
      return;
    }

    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná al menos un servicio que te interese')),
      );
      return;
    }

    setState(() => _isSending = true);
    final supabase = ref.read(supabaseProvider);

    try {
      await supabase.from('solicitudes_cotizacion').insert({
        'cliente_nombre': _nombreController.text,
        'cliente_celular': _celularController.text,
        'servicios_seleccionados': _selectedIds.toList(),
        'comentarios': _comentarioController.text.trim().isEmpty
            ? null
            : _comentarioController.text.trim(),
        'estado': 'pendiente',
      });

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFFD4AF37), width: 0.5)),
        title: Text('¡RECIBIDO, TITÁN!', style: GoogleFonts.oswald(color: const Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: const Text(
          'Tu interés ya está en nuestra base. En breve nos comunicaremos con vos para cerrar los detalles de tu evento.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('LISTO'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryGold = const Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const AnimatedBackground(),
          // Capa de oscurecimiento para mejor legibilidad
          Container(color: Colors.black.withValues(alpha: 0.4)),
          // Glow superior
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [primaryGold.withValues(alpha: 0.2), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded, color: Color(0xFFD4AF37), size: 64),
                          const SizedBox(height: 24),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton(
                            onPressed: _fetchServicios,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('REINTENTAR'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPremiumHeader(primaryGold),
                        const SizedBox(height: 32),
                        _buildEliteSectionLabel('TUS DATOS', Icons.contact_mail_outlined),
                      const SizedBox(height: 20),
                      _buildGlassInput(
                        controller: _nombreController,
                        label: 'NOMBRE COMPLETO',
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 16),
                      _buildGlassInput(
                        controller: _celularController,
                        label: 'CELULAR / WHATSAPP',
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 48),
                      _buildEliteSectionLabel('CATÁLOGO DE SERVICIOS', Icons.star_outline_rounded),
                      const SizedBox(height: 20),
                      _buildServicesGrid(primaryGold),
                      const SizedBox(height: 40),
                      _buildEliteSectionLabel('¿CÓMO TE IMAGINÁS TU EVENTO?', Icons.message_outlined),
                      const SizedBox(height: 12),
                      _buildComentarioInput(),
                      const SizedBox(height: 40),
                      _buildEliteSubmitButton(primaryGold),
                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          'JUNIOR EVENTOS • JE 2026',
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 10,
                            letterSpacing: 4,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader(Color primaryGold) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: primaryGold,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'JUNIOR EVENTOS • CATALOGO 2026 V4',
            style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'EXPERIENCIA',
          style: GoogleFonts.oswald(
            fontSize: 56,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            height: 0.8,
            color: Colors.white,
          ),
        ),
        Text(
          'VANGUARDIA',
          style: GoogleFonts.oswald(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 10,
            color: primaryGold,
          ),
        ),
      ],
    );
  }

  Widget _buildEliteSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFD4AF37)),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildGlassInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold),
          prefixIcon: Icon(icon, color: const Color(0xFFD4AF37), size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        ),
      ),
    );
  }

  Widget _buildServicesGrid(Color primaryGold) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _servicios.length,
      itemBuilder: (context, index) {
        final service = _servicios[index];
        final isSelected = _selectedIds.contains(service.id);
        
        return InkWell(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(service.id);
              } else {
                _selectedIds.add(service.id);
              }
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected 
                ? primaryGold.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? primaryGold : Colors.white.withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                if (isSelected) 
                  BoxShadow(color: primaryGold.withValues(alpha: 0.1), blurRadius: 15, spreadRadius: -5),
              ],
            ),
            child: Stack(
              children: [
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(Icons.check_circle_rounded, color: primaryGold, size: 16),
                  ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      service.nombre.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.oswald(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                        color: isSelected ? primaryGold : Colors.white,
                        letterSpacing: 1.5,
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

  Widget _buildEliteSubmitButton(Color primaryGold) {
    return InkWell(
      onTap: _isSending ? null : _enviarSolicitud,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 65,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isSending 
              ? [Colors.grey[800]!, Colors.grey[900]!]
              : [primaryGold, const Color(0xFFB8860B)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            if (!_isSending)
              BoxShadow(
                color: primaryGold.withValues(alpha: 0.3),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Center(
          child: _isSending 
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
              )
            : Text(
                'ENVIAR MI INTERÉS 🚀',
                style: GoogleFonts.oswald(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: Colors.black,
                ),
              ),
        ),
      ),
    );
  }
}
