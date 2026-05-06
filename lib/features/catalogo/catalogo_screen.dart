import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show ImageFilter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/servicio.dart';
import '../common/widgets/animated_background.dart';
import '../common/widgets/admin_gate.dart';
import '../common/providers/admin_provider.dart';
import '../common/providers/user_role_provider.dart';
import '../common/utils/currency_extensions.dart';
import '../eventos/repositories/eventos_repository.dart';

class CatalogoServiciosScreen extends ConsumerStatefulWidget {
  const CatalogoServiciosScreen({super.key});

  @override
  ConsumerState<CatalogoServiciosScreen> createState() => _CatalogoServiciosScreenState();
}

class _CatalogoServiciosScreenState extends ConsumerState<CatalogoServiciosScreen> {
  bool _isLoading = true;
  bool _hideSensitiveData = true; // Por defecto oculto para Adriana
  bool _mostrarArchivados = false; // Nuevo: Control de archivados
  List<Servicio> _servicios = [];

  @override
  void initState() {
    super.initState();
    _fetchServicios();
  }

  Future<void> _fetchServicios() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(eventosRepositoryProvider);
      final catalogo = await repo.getCatalogo(includeArchived: _mostrarArchivados);
      if (!mounted) return;
      setState(() {
        _servicios = catalogo;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editarServicio(Servicio servicio) async {
    if (!mounted) return;
    final hasAccess = await AdminGate.check(context, ref);
    if (!mounted || !hasAccess) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditarServicioDialog(servicio: servicio),
    );

    if (result == true) {
      _fetchServicios();
    }
  }

  void _borrarServicio(Servicio servicio) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.redAccent, width: 0.5)),
        title: const Text('¿ARCHIVAR SERVICIO?', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('¿Deseas ocultar "${servicio.nombre}" del catálogo activo? Podrás recuperarlo luego desde la sección de archivados.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('ARCHIVAR'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final repo = ref.read(eventosRepositoryProvider);
        await repo.eliminarServicio(servicio.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Servicio archivado con éxito')));
          _fetchServicios();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al archivar: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  void _restaurarServicio(Servicio servicio) async {
    try {
      final repo = ref.read(eventosRepositoryProvider);
      await repo.restaurarServicio(servicio.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Servicio restaurado con éxito'),
          backgroundColor: Colors.green,
        ));
        _fetchServicios();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al restaurar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _borrarDefinitivoServicio(Servicio servicio) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.redAccent, width: 2.0)),
        title: const Text('¿ELIMINACIÓN DEFINITIVA?', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Vas a borrar "${servicio.nombre}" DE FORMA PERMANENTE. Esto no se puede deshacer y podría afectar la integridad de presupuestos antiguos.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('BORRAR PARA SIEMPRE'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final repo = ref.read(eventosRepositoryProvider);
        await repo.eliminarServicioDefinitivo(servicio.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Servicio eliminado permanentemente')));
          _fetchServicios();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(adminAuthProvider).isAdmin;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('CATÁLOGO DE SERVICIOS'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Color(0xFFD4AF37)),
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            tooltip: 'Volver al Inicio',
          ),
          IconButton(
            icon: Icon(
              _hideSensitiveData ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: const Color(0xFFD4AF37),
            ),
            onPressed: () => setState(() => _hideSensitiveData = !_hideSensitiveData),
            tooltip: _hideSensitiveData ? 'Mostrar Precios' : 'Ocultar Precios',
          ),
          if (!ref.watch(adminAuthProvider).isAdmin && !_isLoading)
            IconButton(
              icon: Icon(Icons.admin_panel_settings_outlined, color: const Color(0xFFD4AF37).withValues(alpha: 0.6)),
              onPressed: () => AdminGate.check(context, ref),
              tooltip: 'Activar Modo Admin',
            ),
          IconButton(
            icon: Icon(
              _mostrarArchivados ? Icons.archive_rounded : Icons.archive_outlined,
              color: _mostrarArchivados ? Colors.orangeAccent : const Color(0xFFD4AF37),
            ),
            onPressed: () {
              setState(() => _mostrarArchivados = !_mostrarArchivados);
              _fetchServicios();
            },
            tooltip: _mostrarArchivados ? 'Ver Catálogo Activo' : 'Ver Servicios Archivados',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchServicios,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      floatingActionButton: ref.watch(adminAuthProvider).isAdmin
          ? Container(
              margin: const EdgeInsets.only(bottom: 16, right: 16),
              child: FloatingActionButton.extended(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                elevation: 4,
                highlightElevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onPressed: _crearNuevoServicio,
                icon: const Icon(Icons.add_rounded, size: 24),
                label: const Text(
                  'NUEVO SERVICIO',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          : null,
      body: AnimatedBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
            : _servicios.isEmpty
                ? Center(
                    child: Text(
                      'No hay servicios cargados.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : SafeArea(
                    top: false,
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 1000), // Ampliado para la grilla
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 120, 24, 100),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 320,
                            mainAxisExtent: 180,
                            crossAxisSpacing: 24,
                            mainAxisSpacing: 24,
                          ),
                          itemCount: _servicios.length,
                          itemBuilder: (context, index) {
                            final srv = _servicios[index];
                            return TweenAnimationBuilder<double>(
                              duration: Duration(milliseconds: 600 + (index * 50)), // Animación un poco más rápida
                              curve: Curves.easeOutQuart,
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Transform.scale(
                                  scale: 0.95 + (0.05 * value),
                                  child: Opacity(
                                    opacity: value,
                                    child: child,
                                  ),
                                );
                              },
                              child: _EliteGridCard(
                                srv: srv,
                                isAdmin: isAdmin,
                                hidePrice: _hideSensitiveData,
                                onEdit: () => _editarServicio(srv),
                                onDelete: () => srv.isArchived ? _borrarDefinitivoServicio(srv) : _borrarServicio(srv),
                                onRestore: () => _restaurarServicio(srv),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  void _crearNuevoServicio() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditarServicioDialog(servicio: null),
    );

    if (result == true) {
      _fetchServicios();
    }
  }
}

class _EliteGridCard extends StatefulWidget {
  final Servicio srv;
  final bool isAdmin;
  final bool hidePrice;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRestore;

  const _EliteGridCard({
    required this.srv,
    required this.isAdmin,
    required this.hidePrice,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
  });

  @override
  State<_EliteGridCard> createState() => _EliteGridCardState();
}

class _EliteGridCardState extends State<_EliteGridCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);
    final basePrice = widget.srv.costoBase ?? 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: Matrix4.diagonal3Values(
          _isHovered ? 1.03 : 1.0,
          _isHovered ? 1.03 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    _isHovered 
                      ? (widget.srv.isArchived ? const Color(0xFF2A2020) : const Color(0xFF252525))
                      : (widget.srv.isArchived ? const Color(0xFF1F1A1A) : const Color(0xFF1E1E1E)),
                    const Color(0xFF141414),
                  ]
                : [
                    Colors.white,
                    _isHovered ? const Color(0xFFF5F5F5) : const Color(0xFFFAFAFA),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: widget.srv.isArchived 
              ? Colors.redAccent.withValues(alpha: 0.3)
              : (_isHovered ? primaryGold.withValues(alpha: 0.4) : primaryGold.withValues(alpha: 0.15)),
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.6) : primaryGold.withValues(alpha: 0.1),
              blurRadius: _isHovered ? 30 : 20,
              offset: Offset(0, _isHovered ? 12 : 8),
              spreadRadius: _isHovered ? 2 : 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isAdmin ? widget.onEdit : null,
              splashColor: primaryGold.withValues(alpha: 0.1),
              highlightColor: primaryGold.withValues(alpha: 0.05),
              child: Stack(
                children: [
                  // Decoración de fondo (Círculo difuminado)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    right: _isHovered ? -20 : -30,
                    bottom: _isHovered ? -20 : -30,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: _isHovered ? 140 : 120,
                      height: _isHovered ? 140 : 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryGold.withValues(alpha: _isHovered ? 0.08 : 0.05),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Encabezado de la tarjeta
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: primaryGold.withValues(alpha: _isHovered ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: primaryGold.withValues(alpha: 0.2)),
                                boxShadow: _isHovered ? [BoxShadow(color: primaryGold.withValues(alpha: 0.2), blurRadius: 10)] : null,
                              ),
                              child: Icon(Icons.star_rounded, color: primaryGold, size: 24),
                            ),
                            const Spacer(),
                             if (widget.isAdmin)
                                Row(
                                  children: [
                                    if (widget.srv.isArchived)
                                      _buildIconButton(
                                        icon: Icons.restore_rounded,
                                        color: Colors.greenAccent,
                                        onPressed: widget.onRestore,
                                        tooltip: 'Restaurar',
                                      ),
                                    if (!widget.srv.isArchived)
                                      _buildIconButton(
                                        icon: Icons.edit_rounded,
                                        color: Colors.blueGrey,
                                        onPressed: widget.onEdit,
                                        tooltip: 'Editar',
                                      ),
                                    _buildIconButton(
                                      icon: widget.srv.isArchived ? Icons.delete_forever_rounded : Icons.delete_outline_rounded,
                                      color: Colors.redAccent,
                                      onPressed: widget.onDelete,
                                      tooltip: widget.srv.isArchived ? 'Borrar Definitivamente' : 'Archivar',
                                    ),
                                  ],
                                ),
                          ],
                        ),
                        const Spacer(),
                        // Información
                        AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.srv.categoria.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          widget.srv.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: primaryGold,
                            fontWeight: FontWeight.w900,
                            fontSize: _isHovered ? 22 : 20,
                            letterSpacing: -0.5,
                            fontFamily: 'Outfit', // Aseguramos la fuente para la animación suave
                          ),
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: widget.hidePrice ? 5.0 : 0.0,
                              sigmaY: widget.hidePrice ? 5.0 : 0.0,
                            ),
                            child: Text(basePrice.toCurrency()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, required Color color, required VoidCallback onPressed, required String tooltip}) {
    return Material(
      color: Colors.transparent,
      child: IconButton(
        icon: Icon(icon, color: color, size: 18),
        onPressed: onPressed,
        tooltip: tooltip,
        splashRadius: 20,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class EditarServicioDialog extends ConsumerStatefulWidget {
  final Servicio? servicio; // Null if it's a new service
  const EditarServicioDialog({super.key, this.servicio});

  @override
  ConsumerState<EditarServicioDialog> createState() => _EditarServicioDialogState();
}
class _EditarServicioDialogState extends ConsumerState<EditarServicioDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreController;
  late TextEditingController _costoController;
  late TextEditingController _costoInternoController;
  late String _categoriaSeleccionada;
  bool _isSaving = false;

  final List<String> _categorias = ['General', 'Sonido', 'Iluminación', 'Catering', 'DJ', 'Ambientación', 'Otro'];

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.servicio?.nombre ?? '');
    _costoController = TextEditingController(text: (widget.servicio?.costoBase ?? 0.0).toFormattedNumber());
    _costoInternoController = TextEditingController(text: (widget.servicio?.costoInterno ?? 0.0).toFormattedNumber());
    _categoriaSeleccionada = widget.servicio?.categoria ?? _categorias.first;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _costoController.dispose();
    _costoInternoController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    try {
      final costoText = _costoController.text.replaceAll('.', '').replaceAll(',', '.');
      final costo = double.tryParse(costoText) ?? 0.0;

      final costoInternoText = _costoInternoController.text.replaceAll('.', '').replaceAll(',', '.');
      final costoInterno = double.tryParse(costoInternoText) ?? 0.0;
      
      final Map<String, dynamic> data = {
        'nombre': _nombreController.text.trim(),
        'costo_base': costo,
        'costo_interno': costoInterno,
        'categoria': _categoriaSeleccionada,
      };

      final repo = ref.read(eventosRepositoryProvider);

      if (widget.servicio != null) {
        // UPDATE
        await repo.actualizarServicio(widget.servicio!.id, data);
      } else {
        // INSERT
        await repo.crearServicio(
          nombre: _nombreController.text.trim(),
          costoBase: costo,
          categoria: _categoriaSeleccionada,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.servicio != null;
    final puedeFinanzas = ref.watch(userRoleProvider).maybeWhen(data: (d) => d.permisos.puedeFinanzas, orElse: () => false);

    return AlertDialog(
      title: Text(isEdit ? 'Editar: ${widget.servicio!.nombre}' : 'Nuevo Servicio'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isEdit) ...[
                TextFormField(
                  controller: _nombreController,
                  decoration: const InputDecoration(labelText: 'Nombre del Servicio'),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
              ],
              DropdownButtonFormField<String>(
                key: ValueKey(_categoriaSeleccionada),
                initialValue: _categoriaSeleccionada,
                decoration: const InputDecoration(labelText: 'Categoría de Evento'),
                items: _categorias.map((cat) => DropdownMenuItem(
                  value: cat,
                  child: Text(cat.replaceAll('_', ' ').toUpperCase()),
                )).toList(),
                onChanged: (v) => setState(() => _categoriaSeleccionada = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _costoController,
                decoration: const InputDecoration(
                  labelText: 'Precio de Lista (\$)',
                  hintText: 'Precio oficial del servicio',
                ),
                keyboardType: TextInputType.number,
                autofocus: !isEdit,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) return newValue;
                    final double val = double.parse(newValue.text) / 100;
                    final String newText = val.toFormattedNumber();
                    return newValue.copyWith(text: newText, selection: TextSelection.collapsed(offset: newText.length));
                  }),
                ],
              ),
              const SizedBox(height: 16),
              if (puedeFinanzas)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: const Text('CONFIGURACIÓN AVANZADA (ADMIN)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    children: [
                      TextFormField(
                        controller: _costoInternoController,
                        decoration: const InputDecoration(
                          labelText: 'Costo de Adquisición / Interno (\$)',
                          hintText: 'Lo que te sale a vos',
                          labelStyle: TextStyle(color: Colors.orange),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            if (newValue.text.isEmpty) return newValue;
                            final double val = double.parse(newValue.text) / 100;
                            final String newText = val.toFormattedNumber();
                            return newValue.copyWith(text: newText, selection: TextSelection.collapsed(offset: newText.length));
                          }),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Este valor se usa para alertarte discretamente si el presupuesto total baja mucho.',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.white),
          child: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('GUARDAR'),
        ),
      ],
    );
  }
}
