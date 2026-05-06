import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cliente.dart';
import 'selector_servicios_screen.dart';
import '../clientes/repositories/clientes_repository.dart';

class CrearEventoScreen extends ConsumerStatefulWidget {
  const CrearEventoScreen({super.key});

  @override
  ConsumerState<CrearEventoScreen> createState() => _CrearEventoScreenState();
}

class _CrearEventoScreenState extends ConsumerState<CrearEventoScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controladores para autocompletado
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  
  List<Cliente> _todosLosClientes = [];
  String? _selectedClientId;
  
  // Evento Info
  String _tipoEvento = 'Bautismo';
  DateTime _fechaEvento = DateTime.now().add(const Duration(days: 30));
  int _cantidadCuotas = 1;
  String _modalidad = 'particular';
  int _validezDias = 7;

  final List<String> _tiposEventos = ['Boda', '15 Años', 'Bautismo', 'Recepción', 'Otro'];
  final TextEditingController _otroTipoController = TextEditingController();

  // Datos ampliados (Bodas, 15_años, Particulares)
  final _homenajeado1Controller = TextEditingController(); 
  final _homenajeado2Controller = TextEditingController(); 
  final _padresController = TextEditingController();
  final _extrasController = TextEditingController();
  String? _emailCliente;

  @override
  void initState() {
    super.initState();
    // Si venimos desde una solicitud QR, prellenamos nombre / teléfono.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        final origen = args['origen']?.toString();
        if (origen == 'solicitud_qr') {
          final nombre = args['nombre']?.toString();
          final celular = args['celular']?.toString();
          if (nombre != null && nombre.isNotEmpty) {
            _nombreController.text = nombre;
          }
          if (celular != null && celular.isNotEmpty) {
            _telefonoController.text = celular;
          }
        }
      }
    });
    _fetchClientes();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _otroTipoController.dispose();
    _homenajeado1Controller.dispose();
    _homenajeado2Controller.dispose();
    _padresController.dispose();
    _extrasController.dispose();
    super.dispose();
  }

  Future<void> _fetchClientes() async {
    try {
      final repo = ref.read(clientesRepositoryProvider);
      final clientes = await repo.getAll();
      setState(() {
        _todosLosClientes = clientes;
      });
    } catch (e) {
      debugPrint('Error al cargar clientes: $e');
    }
  }

  Future<void> _continuarAlPresupuesto() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    String? observacionesAmpliadas;
    String? lugarPresupuesto;
    String? detalleAnclajeIA;

    if (_modalidad == 'presupuesto') {
      lugarPresupuesto = _extrasController.text;
      detalleAnclajeIA = _padresController.text;
      if (_homenajeado1Controller.text.isNotEmpty) {
        observacionesAmpliadas = 'Homenajeado: ${_homenajeado1Controller.text}';
      }
    } else {
      final tipo = _tipoEvento.toLowerCase();
      if (tipo == 'boda' && (_homenajeado1Controller.text.isNotEmpty || _homenajeado2Controller.text.isNotEmpty)) {
        observacionesAmpliadas = '💒 BODA\n- Novio/a 1: ${_homenajeado1Controller.text}\n- Novio/a 2: ${_homenajeado2Controller.text}\n- Padres: ${_padresController.text}\n- Lugar/Extras: ${_extrasController.text}';
      } else if ((tipo == '15_años' || tipo == '15 años') && _homenajeado1Controller.text.isNotEmpty) {
        observacionesAmpliadas = '👑 15 AÑOS\n- Quinceañera: ${_homenajeado1Controller.text}\n- Padres: ${_padresController.text}\n- Temática/Color: ${_extrasController.text}';
      } else if (tipo == 'bautismo' && _homenajeado1Controller.text.isNotEmpty) {
        observacionesAmpliadas = '✝️ BAUTISMO\n- Bebé: ${_homenajeado1Controller.text}\n- Padrinos: ${_homenajeado2Controller.text}\n- Padres: ${_padresController.text}\n- Iglesia/Lugar: ${_extrasController.text}';
      } else if (tipo.contains('recepc') && _homenajeado1Controller.text.isNotEmpty) {
        observacionesAmpliadas = '🎓 RECEPCIÓN\n- Institución: ${_homenajeado1Controller.text}\n- Grado/Curso: ${_homenajeado2Controller.text}\n- Cant. Alumnos: ${_padresController.text}\n- Detalles: ${_extrasController.text}';
      } else if (_homenajeado1Controller.text.isNotEmpty) {
        observacionesAmpliadas = '📌 EVENTO: ${_tipoEvento.toUpperCase()}\n- Homenajeado/a: ${_homenajeado1Controller.text}\n- Familia: ${_padresController.text}\n- Detalles: ${_extrasController.text}';
      }
    }

    // Proceed to budget builder, passing the basic info
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectorServiciosScreen(
          nombreCliente: _nombreController.text,
          telefonoCliente: _telefonoController.text,
          emailCliente: _emailController.text,
          tipoEvento: _tipoEvento,
          fechaEvento: _fechaEvento,
          cantidadCuotas: _cantidadCuotas,
          clienteId: _selectedClientId,
          modalidad: _modalidad,
          observaciones: observacionesAmpliadas,
          lugar: lugarPresupuesto,
          detalleAnclajeIA: detalleAnclajeIA,
          isPresupuesto: _modalidad == 'presupuesto',
          validezDias: _validezDias,
          instagramPublicidad: _homenajeado2Controller.text.isNotEmpty ? _homenajeado2Controller.text : null,
          telefonoPublicidad: _emailCliente, // Recordemos que usamos este campo temporalmente en el form
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryGold = const Color(0xFFD4AF37);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('NUEVO EVENTO'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          // Fondo Premium con profundidad
          Positioned.fill(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          Positioned(
            top: -150,
            right: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryGold.withValues(alpha: isDark ? 0.08 : 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Sección 1: Cliente
                    _buildStepCard(
                      title: 'CLIENTE',
                      subtitle: 'Identificación del responsable',
                      icon: Icons.person_add_outlined,
                      child: Column(
                        children: [
                          Autocomplete<Cliente>(
                            displayStringForOption: (option) => option.nombreCompleto,
                            optionsBuilder: (textEditingValue) {
                              if (textEditingValue.text.isEmpty) return const Iterable<Cliente>.empty();
                              return _todosLosClientes.where((cliente) =>
                                cliente.nombreCompleto.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                            },
                            onSelected: (cliente) {
                              setState(() {
                                _selectedClientId = cliente.id;
                                _nombreController.text = cliente.nombreCompleto;
                                _telefonoController.text = cliente.telefono ?? '';
                                _emailController.text = cliente.email ?? '';
                              });
                            },
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              if (_nombreController.text.isNotEmpty && controller.text.isEmpty) {
                                 controller.text = _nombreController.text;
                              }
                              return TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre Completo o Empresa',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                                onChanged: (v) {
                                  if (_nombreController.text != v) _selectedClientId = null;
                                  _nombreController.text = v;
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _telefonoController,
                                  decoration: const InputDecoration(
                                    labelText: 'Teléfono',
                                    prefixIcon: Icon(Icons.phone_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _emailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.alternate_email),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Sección 2: Evento
                    _buildStepCard(
                      title: 'DETALLES DEL EVENTO',
                      subtitle: 'Configuración técnica',
                      icon: Icons.event_available_outlined,
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _tiposEventos.contains(_tipoEvento) ? _tipoEvento : 'Otro',
                            decoration: const InputDecoration(
                              labelText: 'Naturaleza del Evento',
                              prefixIcon: Icon(Icons.celebration_outlined),
                            ),
                            items: _tiposEventos
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      e.replaceAll('_', ' ').toUpperCase(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _tipoEvento = v;
                                if (_tipoEvento != 'Otro') {
                                  _otroTipoController.clear();
                                }
                              });
                            },
                          ),
                          if (_tipoEvento == 'Otro') ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _otroTipoController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre del evento (otro)',
                                prefixIcon: Icon(Icons.edit_outlined),
                              ),
                              onSaved: (v) {
                                final nombre = v?.trim();
                                if (nombre != null && nombre.isNotEmpty) {
                                  _tipoEvento = nombre;
                                }
                              },
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Ingresá el nombre del evento';
                                }
                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 20),
                          _buildPremiumDatePicker(),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Modalidad',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Particular'),
                                selected: _modalidad == 'particular',
                                onSelected: (value) {
                                  if (!value) return;
                                  setState(() => _modalidad = 'particular');
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Masivo / Escuela'),
                                selected: _modalidad == 'masivo',
                                onSelected: (value) {
                                  if (!value) return;
                                  setState(() => _modalidad = 'masivo');
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Presupuesto'),
                                avatar: const Icon(Icons.auto_awesome, size: 16),
                                selected: _modalidad == 'presupuesto',
                                onSelected: (value) {
                                  if (!value) return;
                                  setState(() => _modalidad = 'presupuesto');
                                },
                              ),
                            ],
                          ),
                                             if (_modalidad == 'presupuesto') ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: primaryGold.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: primaryGold.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.timer_outlined, color: Color(0xFFD4AF37), size: 18),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Validez de $_validezDias días. El cronómetro iniciará al crear este presupuesto.',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _mostrarModalValidez,
                                    icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFFD4AF37)),
                                    label: const Text(
                                      'MODIFICAR',
                                      style: TextStyle(
                                        color: Color(0xFFD4AF37),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ] else if (_tipoEvento.toLowerCase().contains('recepc')) ...[
                            TextFormField(
                              initialValue: '1',
                              decoration: const InputDecoration(
                                labelText: 'Cuotas pactadas',
                                prefixIcon: Icon(Icons.payments_outlined),
                              ),
                              keyboardType: TextInputType.number,
                              onSaved: (v) => _cantidadCuotas = int.tryParse(v ?? '1') ?? 1,
                              validator: (v) {
                                final n = int.tryParse(v ?? '');
                                if (n == null || n < 1) return 'Mínimo 1';
                                return null;
                              },
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.02)
                                    : Colors.black.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.payments_outlined, size: 18, color: Color(0xFFD4AF37)),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Plan de cobro estándar',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Para estos eventos el sistema toma un anticipo del 30% del valor total. El saldo restante lo podés cobrar de forma flexible desde la pantalla de ingresos.',
                                          style: TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    if (_modalidad == 'particular' || _modalidad == 'presupuesto') ...[
                      const SizedBox(height: 32),
                      _buildStepCard(
                        title: 'DATOS AMPLIADOS',
                        subtitle: _modalidad == 'presupuesto' ? 'Información clave para el presupuesto' : _subtituloAmpliados(_tipoEvento),
                        icon: _modalidad == 'presupuesto' ? Icons.map_outlined : _iconoAmpliados(_tipoEvento),
                        child: _buildCamposAmpliados(),
                      ),
                    ],

                    const SizedBox(height: 56),
                    
                    // Botón de Acción Élite
                    const SizedBox(height: 24),
                    _buildFerrariAction(
                      label: 'DEFINIR SERVICIOS',
                      icon: Icons.auto_awesome,
                      onPressed: _continuarAlPresupuesto,
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({required String title, required String subtitle, required IconData icon, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          if (!isDark) 
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryGold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: primaryGold, size: 24),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: primaryGold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28.0),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumDatePicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _fechaEvento,
          firstDate: DateTime.now(),
          lastDate: DateTime(2030),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.dark(
                  primary: primaryGold,
                  onPrimary: Colors.black,
                  surface: const Color(0xFF1E1E1E),
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) setState(() => _fechaEvento = picked);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, color: primaryGold),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fecha del Evento', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                  Text(
                    '${_fechaEvento.day} de ${_getMonthName(_fechaEvento.month)}, ${_fechaEvento.year}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildFerrariAction({required String label, required IconData icon, required VoidCallback onPressed}) {
    return Container(
      width: double.infinity,
      height: 70,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
        gradient: const LinearGradient(
          colors: [Color(0xFFEBC144), Color(0xFFD4AF37)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.black87, size: 24),
        label: Text(label, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        onPressed: onPressed,
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return months[month - 1];
  }

  void _mostrarModalValidez() {
    final controller = TextEditingController(text: _validezDias.toString());
    final primaryGold = const Color(0xFFD4AF37);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Días de Validez'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Establecé por cuánto tiempo será válido este presupuesto antes de expirar.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Días de vigencia',
                prefixIcon: const Icon(Icons.timer_outlined),
                suffixText: 'días',
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: primaryGold),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val > 0) {
                setState(() => _validezDias = val);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGold,
              foregroundColor: Colors.black,
            ),
            child: const Text('CONFIRMAR'),
          ),
        ],
      ),
    );
  }

  // ─── Helpers para Datos Ampliados ───────────────────────────────────────────

  String _subtituloAmpliados(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'boda': return 'Info de los novios y ceremonia';
      case '15_años':
      case '15 años': return 'Info de la quinceañera';
      case 'bautismo': return 'Info del bebé y padrinos';
      default:
        if (tipo.toLowerCase().contains('recepc')) return 'Info de la institución y egresados';
        return 'Información extra del evento';
    }
  }

  IconData _iconoAmpliados(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'boda': return Icons.favorite_outline;
      case '15_años':
      case '15 años': return Icons.stars_outlined;
      case 'bautismo': return Icons.water_drop_outlined;
      default:
        if (tipo.toLowerCase().contains('recepc')) return Icons.school_outlined;
        return Icons.menu_book_outlined;
    }
  }

  Widget _buildCamposAmpliados() {
    final tipo = _tipoEvento.toLowerCase();

    // Si es presupuesto, mostramos campos genéricos de "Lugar" y "Anclaje IA" 
    // que se sumarán a los específicos del tipo de evento.
    if (_modalidad == 'presupuesto') {
      return Column(children: [
        TextField(
          controller: _extrasController, 
          decoration: const InputDecoration(
            labelText: 'Lugar del Evento / Salón', 
            prefixIcon: Icon(Icons.place_outlined)
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _padresController, 
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Detalles Especiales del Plan', 
            hintText: 'Ej: Estilo bailable, cena formal, 150 invitados...',
            prefixIcon: Icon(Icons.psychology_outlined)
          ),
        ),
        const SizedBox(height: 12),
        // También incluimos el homenajeado si corresponde
        TextField(
          controller: _homenajeado1Controller, 
          decoration: const InputDecoration(
            labelText: 'Homenajeado/a (Opcional)', 
            prefixIcon: Icon(Icons.person_outline)
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _homenajeado2Controller, // Usamos este para IG temporalmente en este modo
                decoration: const InputDecoration(
                  labelText: 'Instagram (@)', 
                  prefixIcon: Icon(Icons.camera_alt_outlined),
                  hintText: 'junior_eventos_ok'
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: 'Adri', 
                decoration: const InputDecoration(
                  labelText: 'Teléfono Pie', 
                  prefixIcon: Icon(Icons.phone_android_outlined),
                ),
                onSaved: (v) => _emailCliente = v, // Usamos este para Tel Pie temporalmente en el form
              ),
            ),
          ],
        ),
      ]);
    }

    if (tipo == 'boda') {
      return Column(children: [
        TextField(controller: _homenajeado1Controller, decoration: const InputDecoration(labelText: 'Nombre del Novio/a 1', prefixIcon: Icon(Icons.favorite_outline))),
        const SizedBox(height: 12),
        TextField(controller: _homenajeado2Controller, decoration: const InputDecoration(labelText: 'Nombre del Novio/a 2', prefixIcon: Icon(Icons.favorite_border_rounded))),
        const SizedBox(height: 12),
        TextField(controller: _padresController, decoration: const InputDecoration(labelText: 'Nombres de los Padres', prefixIcon: Icon(Icons.family_restroom))),
        const SizedBox(height: 12),
        TextField(controller: _extrasController, decoration: const InputDecoration(labelText: 'Lugar de Ceremonia / Extras', prefixIcon: Icon(Icons.church_outlined))),
      ]);
    } else if (tipo == '15_años' || tipo == '15 años') {
      return Column(children: [
        TextField(controller: _homenajeado1Controller, decoration: const InputDecoration(labelText: 'Nombre de la Quinceañera', prefixIcon: Icon(Icons.stars_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _padresController, decoration: const InputDecoration(labelText: 'Nombres de los Padres', prefixIcon: Icon(Icons.family_restroom))),
        const SizedBox(height: 12),
        TextField(controller: _extrasController, decoration: const InputDecoration(labelText: 'Temática / Color Principal', prefixIcon: Icon(Icons.palette_outlined))),
      ]);
    } else if (tipo == 'bautismo') {
      return Column(children: [
        TextField(controller: _homenajeado1Controller, decoration: const InputDecoration(labelText: 'Nombre del Bebé', prefixIcon: Icon(Icons.child_friendly_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _homenajeado2Controller, decoration: const InputDecoration(labelText: 'Padrinos', prefixIcon: Icon(Icons.people_alt_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _padresController, decoration: const InputDecoration(labelText: 'Nombres de los Padres', prefixIcon: Icon(Icons.family_restroom))),
        const SizedBox(height: 12),
        TextField(controller: _extrasController, decoration: const InputDecoration(labelText: 'Iglesia / Lugar de Ceremonia', prefixIcon: Icon(Icons.water_drop_outlined))),
      ]);
    } else if (tipo.contains('recepc')) {
      return Column(children: [
        TextField(controller: _homenajeado1Controller, decoration: const InputDecoration(labelText: 'Institución / Escuela', prefixIcon: Icon(Icons.school_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _homenajeado2Controller, decoration: const InputDecoration(labelText: 'Grado / Curso / Promoción', prefixIcon: Icon(Icons.class_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _padresController, decoration: const InputDecoration(labelText: 'Cantidad de Alumnos', prefixIcon: Icon(Icons.group_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _extrasController, decoration: const InputDecoration(labelText: 'Detalles / Temática', prefixIcon: Icon(Icons.notes_outlined))),
      ]);
    } else {
      // Otro / genérico
      return Column(children: [
        TextField(controller: _homenajeado1Controller, decoration: const InputDecoration(labelText: 'Homenajeado Principal', prefixIcon: Icon(Icons.person_pin_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _padresController, decoration: const InputDecoration(labelText: 'Familia / Organizador', prefixIcon: Icon(Icons.family_restroom))),
        const SizedBox(height: 12),
        TextField(controller: _extrasController, decoration: const InputDecoration(labelText: 'Anotaciones Extras', prefixIcon: Icon(Icons.notes_outlined))),
      ]);
    }
  }
}

