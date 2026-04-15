import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/servicio.dart';
import '../common/utils/currency_extensions.dart';
import 'repositories/eventos_repository.dart';
import 'repositories/presupuestos_repository.dart';
import '../../core/utils/uuid_utils.dart';

class SelectorServiciosScreen extends ConsumerStatefulWidget {
  final String? clienteId;
  final String? nombreCliente;
  final String? telefonoCliente;
  final String? emailCliente;
  final String? tipoEvento;
  final DateTime? fechaEvento;
  final int cantidadCuotas;
  final String? eventoId;
  final Map<String, double>? serviciosIniciales;
  final String modalidad;
  final String? observaciones;
  final String? lugar;
  final String? detalleAnclajeIA;
  final bool isPresupuesto;
  final int validezDias;
  final String? presupuestoId;
  final Map<String, String?>? descripcionesIniciales;
  final String? instagramPublicidad;
  final Map<String, String?>? gruposIniciales;
  final Map<String, double>? cantidadesIniciales;
  final String? telefonoPublicidad;

  const SelectorServiciosScreen({
    super.key,
    this.clienteId,
    this.nombreCliente,
    this.telefonoCliente,
    this.emailCliente,
    this.tipoEvento,
    this.fechaEvento,
    this.cantidadCuotas = 1,
    this.eventoId,
    this.serviciosIniciales,
    this.modalidad = 'particular',
    this.observaciones,
    this.lugar,
    this.detalleAnclajeIA,
    this.isPresupuesto = false,
    this.validezDias = 7,
    this.presupuestoId,
    this.descripcionesIniciales,
    this.instagramPublicidad,
    this.telefonoPublicidad,
    this.gruposIniciales,
    this.cantidadesIniciales,
  });

  @override
  ConsumerState<SelectorServiciosScreen> createState() => _SelectorServiciosScreenState();
}

class _SelectorServiciosScreenState extends ConsumerState<SelectorServiciosScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Servicio> _catalogo = [];
  List<Servicio> _catalogoFiltrado = [];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  
  // Map recording Selected Service ID -> {precio, cantidad, grupo}
  final Map<String, Map<String, dynamic>> _serviciosSeleccionados = {};
  
  // Panel Control
  bool _showPanel = true;
  
  // Nuevo: Map recording Selected Service ID -> Technical Description
  final Map<String, String?> _detallesServicios = {};

  // Inteligencia de Sesión
  late final String _tempEventoId;
  bool _confirmado = false;
  final Set<String> _serviciosTemporalesIds = {};

  // Mapa de nombres para servicios Ad-hoc (Sesión)
  final Map<String, String> _nombresAdHoc = {};

  // Sugerencia Inteligente
  Servicio? _suggestedService;

  List<String> get _sugerenciasVinculacion {
    final grupos = _serviciosSeleccionados.values
        .map((v) => v['grupo'] as String?)
        .where((g) => g != null && g.isNotEmpty)
        .cast<String>()
        .toSet();
    
    final nombresServicios = _serviciosSeleccionados.keys.map((id) {
      final srv = _catalogo.where((s) => s.id == id).firstOrNull;
      return srv?.nombre;
    }).whereType<String>().toSet();

    return {...grupos, ...nombresServicios}.toList();
  }



  @override
  void initState() {
    super.initState();
    // VINCULACIÓN CORREGIDA: Ahora respeta el ID del presupuesto si existe
    _tempEventoId = widget.eventoId ?? widget.presupuestoId ?? UuidUtils.generate();
    
    // Iniciar el proceso de reconstrucción y limpieza
    if (widget.serviciosIniciales != null) {
      for (var entry in widget.serviciosIniciales!.entries) {
        _serviciosSeleccionados[entry.key] = {
          'precio': entry.value,
          'cantidad': widget.cantidadesIniciales?[entry.key] ?? 1.0,
          'grupo': widget.gruposIniciales?[entry.key],
        };
      }
    }

    if (widget.descripcionesIniciales != null) {
      _detallesServicios.addAll(widget.descripcionesIniciales!);
    }

    // Ejecutar limpieza de servicios huérfanos al entrar si estamos en un evento existente
    if (widget.eventoId != null) {
      final repo = ref.read(eventosRepositoryProvider);
      final idsEnPresupuesto = widget.serviciosIniciales?.keys.toList() ?? [];
      repo.purgarServiciosHuerfanos(widget.eventoId!, idsEnPresupuesto).then((_) {
        if (mounted) _fetchCatalogo();
      });
    } else {
      _fetchCatalogo();
    }
    
    _searchController.addListener(_filtrarCatalogo);
  }

  String _normalize(String text) {
    return text.toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }

  void _filtrarCatalogo() {
    final query = _normalize(_searchController.text);
    setState(() {
      _catalogoFiltrado = _catalogo.where((s) => 
        _normalize(s.nombre).contains(query) || 
        _normalize(s.categoria).contains(query)
      ).toList();

      // Identificar sugerencia inteligente
      if (query.isNotEmpty && _catalogoFiltrado.isNotEmpty) {
        // Priorizar coincidencia exacta o comienzo
        final exactMatch = _catalogoFiltrado.where((s) => _normalize(s.nombre).startsWith(query)).toList();
        _suggestedService = exactMatch.isNotEmpty ? exactMatch.first : _catalogoFiltrado.first;
      } else {
        _suggestedService = null;
      }
    });
  }




  void _onSearchSubmitted(String val) {
    if (_suggestedService != null && !_serviciosSeleccionados.containsKey(_suggestedService!.id)) {
      _solicitarPrecio(_suggestedService!);
    }
  }

  void _mostrarDialogoEditarGrupo(String nombreGrupo) {
    final groupRenameController = TextEditingController(text: nombreGrupo);
    final idsEnGrupo = _serviciosSeleccionados.entries
        .where((e) => e.value['grupo'] == nombreGrupo)
        .map((e) => e.key)
        .toList();
    
    final primaryGold = const Color(0xFFD4AF37);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('GESTIÓN DE GRUPO: ${nombreGrupo.toUpperCase()}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: groupRenameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Renombrar Grupo (Maestro)',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.edit, color: primaryGold),
                  ),
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('COMPONENTES DEL GRUPO', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: idsEnGrupo.length,
                    itemBuilder: (context, index) {
                      final id = idsEnGrupo[index];
                      final srv = _catalogo.firstWhere(
                        (s) => s.id == id, 
                        orElse: () {
                          final nombreRespaldo = _detallesServicios[id] ?? 'Servicio Ad-hoc';
                          return Servicio(id: id, nombre: nombreRespaldo, categoria: 'Personalizado');
                        }
                      );
                      final data = _serviciosSeleccionados[id]!;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          dense: true,
                          title: Text(srv.nombre.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          subtitle: Text(((data['precio'] as num) * (data['cantidad'] as num)).toCurrency(), style: TextStyle(color: primaryGold, fontSize: 10)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.settings, size: 18, color: Colors.blueAccent),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _solicitarPrecio(srv, isEditing: true);
                                },
                                tooltip: 'Editar inversión/descripción',
                              ),
                              IconButton(
                                icon: const Icon(Icons.link_off, size: 18, color: Colors.grey),
                                onPressed: () {
                                  setState(() {
                                    _serviciosSeleccionados[id]?['grupo'] = null;
                                  });
                                  setModalState(() {
                                    idsEnGrupo.remove(id);
                                  });
                                  if (idsEnGrupo.isEmpty) Navigator.pop(ctx);
                                },
                                tooltip: 'Sacar del grupo',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryGold, foregroundColor: Colors.black),
              onPressed: () {
                final nuevoNombre = groupRenameController.text.trim();
                if (nuevoNombre.isNotEmpty) {
                  setState(() {
                    for (final id in idsEnGrupo) {
                      _serviciosSeleccionados[id]?['grupo'] = nuevoNombre;
                    }
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('GUARDAR CAMBIOS MAESTROS', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _fetchCatalogo() async {


    setState(() => _isLoading = true);
    try {
      final repo = ref.read(eventosRepositoryProvider);
      final catalogo = await repo.getCatalogo(eventoId: widget.eventoId ?? _tempEventoId);
      if (!mounted) return;
      
      setState(() {
        _catalogo = catalogo;
        _catalogoFiltrado = catalogo;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _ejecutarLimpiezaSiCorresponde();
    super.dispose();
  }


  void _ejecutarLimpiezaSiCorresponde() {
    if (!_confirmado && _serviciosTemporalesIds.isNotEmpty) {
      final repo = ref.read(eventosRepositoryProvider);
      debugPrint('🧹 Inteligencia: Limpiando ${_serviciosTemporalesIds.length} servicios efímeros...');
      for (final id in _serviciosTemporalesIds) {
        repo.eliminarServicio(id);
      }
    }
  }


  double get _totalPresupuesto {
    return _serviciosSeleccionados.values.fold(0, (sum, val) => sum + ((val['precio'] as num? ?? 0) * (val['cantidad'] as num? ?? 1)));
  }

  Future<void> _guardarPresupuesto() async {
    if (_serviciosSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar al menos un servicio')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final repo = ref.read(eventosRepositoryProvider);

    try {
      if (widget.isPresupuesto) {
        // MODO PRESUPUESTO
        final pRepo = ref.read(presupuestosRepositoryProvider);
        
        final List<Map<String, dynamic>> serviciosFinales = [];
        for (final entry in _serviciosSeleccionados.entries) {
          final data = entry.value;
          serviciosFinales.add({
            'servicio_id': entry.key,
            'precio_final': data['precio'] ?? 0.0,
            'cantidad': data['cantidad'] ?? 1.0,
            'detalle_servicio': _detallesServicios[entry.key],
            'grupo': data['grupo'],
          });
        }

        if (widget.presupuestoId != null) {
          await pRepo.actualizar(
            id: widget.presupuestoId!,
            tipoEvento: widget.tipoEvento ?? 'Otro',
            lugar: widget.lugar,
            detalleAnclaje: widget.detalleAnclajeIA,
            servicios: serviciosFinales,
            diasValidez: widget.validezDias,
          );
        } else {
          await pRepo.crearPresupuesto(
            id: _tempEventoId, // VINCULACIÓN CORREGIDA: Pasamos el ID exacto aquí
            clienteId: widget.clienteId,
            nombreCliente: widget.nombreCliente,
            telefonoCliente: widget.telefonoCliente,
            emailCliente: widget.emailCliente,
            tipoEvento: widget.tipoEvento ?? 'Otro',
            lugar: widget.lugar,
            detalleAnclaje: widget.detalleAnclajeIA,
            instagram: widget.instagramPublicidad ?? 'junior_eventos_ok',
            telefonoPublicidad: widget.telefonoPublicidad ?? 'Maxi',
            servicios: serviciosFinales,
            diasValidez: widget.validezDias,
          );
        }
        // MODO EDICIÓN EVENTO
        final Map<String, Map<String, dynamic>> serviciosConDescripcion = {
          for (final entry in _serviciosSeleccionados.entries)
            entry.key: {
              ...entry.value,
              'detalle_servicio': _detallesServicios[entry.key],
            }
        };

        if (widget.eventoId != null) {
          await repo.actualizarPresupuesto(widget.eventoId!, serviciosConDescripcion);
        }
      } else {
        // MODO EVENTOS (Creación o Edición)
        final Map<String, Map<String, dynamic>> serviciosConDescripcion = {
          for (final entry in _serviciosSeleccionados.entries)
            entry.key: {
              ...entry.value,
              'detalle_servicio': _detallesServicios[entry.key],
            }
        };

        if (widget.eventoId != null) {
          // MODO EDICIÓN EVENTO EXISTENTE (Agenda)
          await repo.actualizarPresupuesto(widget.eventoId!, serviciosConDescripcion);
          // Sincronizamos también cambios en tipo u observaciones si los hubiera
          if (widget.tipoEvento != null || widget.observaciones != null) {
            await repo.actualizarEventoInfo(
              widget.eventoId!, 
              tipo: widget.tipoEvento, 
              observaciones: widget.observaciones
            );
          }
        } else {
          // MODO CREACIÓN EVENTO NUEVO
          await repo.crearEventoCompleto(
            id: _tempEventoId,
            clienteId: widget.clienteId,
            nombreCliente: widget.nombreCliente,
            telefonoCliente: widget.telefonoCliente,
            emailCliente: widget.emailCliente,
            tipoEvento: widget.tipoEvento ?? 'Otro',
            fechaEvento: widget.fechaEvento ?? DateTime.now(),
            cantidadCuotas: widget.cantidadCuotas,
            modalidad: widget.modalidad,
            observaciones: widget.observaciones,
            serviciosSeleccionados: serviciosConDescripcion,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isPresupuesto 
                ? (widget.presupuestoId != null ? 'Presupuesto actualizado correctamente' : 'Presupuesto de Élite generado exitosamente')
                : (widget.eventoId != null 
                    ? 'Presupuesto actualizado correctamente' 
                    : 'Evento y Presupuesto generados exitosamente')),
            backgroundColor: Colors.green
          ),
        );
        
        setState(() => _confirmado = true);
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _solicitarPrecio(Servicio servicio, {bool isEditing = false}) {
    // Si ya está seleccionado y NO forzamos la edición, lo deseleccionamos.
    if (!isEditing && _serviciosSeleccionados.containsKey(servicio.id)) {
      setState(() {
        _serviciosSeleccionados.remove(servicio.id);
        _detallesServicios.remove(servicio.id);
      });
      return;
    }

    // Siempre mostrar modal de precio/cantidad en modo Elite (salvo presupuestos que tiene su modal propio)
    if (widget.isPresupuesto) {
       _mostrarModalPrecioCompleto(servicio);
    } else {
       _mostrarModalPrecioCantidad(servicio);
    }
  }

  void _mostrarModalPrecioCantidad(Servicio servicio) {
    final bool existe = _serviciosSeleccionados.containsKey(servicio.id);
    final double precioActual = existe 
        ? (_serviciosSeleccionados[servicio.id]?['precio'] as num).toDouble()
        : (servicio.costoBase ?? 0.0);
    final double cantidadActual = existe 
        ? (_serviciosSeleccionados[servicio.id]?['cantidad'] as num).toDouble()
        : 1.0;

    final priceController = TextEditingController(text: precioActual.toFormattedNumber());
    final quantityController = TextEditingController(text: cantidadActual.toStringAsFixed(cantidadActual == cantidadActual.toInt() ? 0 : 2));
    final descController = TextEditingController(text: _detallesServicios[servicio.id] ?? '');
    final groupController = TextEditingController(text: _serviciosSeleccionados[servicio.id]?['grupo']?.toString() ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFD4AF37), width: 1)),
        title: Text(servicio.nombre.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                TextInputFormatter.withFunction((oldValue, newValue) {
                  if (newValue.text.isEmpty) return newValue;
                  final double value = double.parse(newValue.text) / 100;
                  final String newText = value.toFormattedNumber();
                  return newValue.copyWith(
                    text: newText,
                    selection: TextSelection.collapsed(offset: newText.length),
                  );
                }),
              ],
              decoration: const InputDecoration(
                labelText: 'Precio Unitario (\$)',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.attach_money, color: Color(0xFFD4AF37)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad / Personas',
                      labelStyle: TextStyle(color: Colors.grey),
                      prefixIcon: Icon(Icons.people_outline, color: Color(0xFFD4AF37)),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    // Acción rápida para "Por Persona" - contexto Adri
                    setState(() {
                      _showPanel = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), minimumSize: const Size(40, 40)),
                  child: const Icon(Icons.calculate, color: Colors.black, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Detalles Técnicos / Nota PDF',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.description_outlined, color: Color(0xFFD4AF37)),
                hintText: 'Ej: Incluye 2 operadores, traslados...',
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: groupController.text),
              optionsBuilder: (TextEditingValue textEditingValue) {
                final suggestions = _sugerenciasVinculacion;
                if (textEditingValue.text.isEmpty) {
                  return suggestions;
                }
                return suggestions.where((String option) {
                  return _normalize(option).contains(_normalize(textEditingValue.text));
                });
              },

              onSelected: (String selection) {
                groupController.text = selection;
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                // Sincronizar con nuestro groupController principal
                controller.addListener(() {
                  groupController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Agrupar con (Nombre de Grupo opcional)',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.link, color: Color(0xFFD4AF37)),
                    hintText: 'Ej: Ambientación & Deco',
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4.0,
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 300,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final String option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text(option, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),

          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () {
              final cleanPrice = priceController.text.replaceAll('.', '').replaceAll(',', '.');
              final price = double.tryParse(cleanPrice) ?? 0;
              final quantity = double.tryParse(quantityController.text) ?? 1.0;
              
              if (price >= 0) {
                final groupName = groupController.text.trim();
                setState(() {
                  _serviciosSeleccionados[servicio.id] = {
                    'precio': price,
                    'cantidad': quantity,
                    'grupo': groupName.isEmpty ? null : groupName,
                  };
                  _detallesServicios[servicio.id] = descController.text.trim().isEmpty ? null : descController.text.trim();
                  
                  // MAGIA DE VINCULACIÓN AUTOMÁTICA
                  if (groupName.isNotEmpty) {
                    final normalizedGroup = _normalize(groupName);
                    final matchingUnselected = _catalogo.where((c) =>
                        _normalize(c.nombre) == normalizedGroup &&
                        !_serviciosSeleccionados.containsKey(c.id)).firstOrNull;
                    if (matchingUnselected != null) {
                      _serviciosSeleccionados[matchingUnselected.id] = {
                        'precio': 0.0, // <-- LÓGICA VINCULACIÓN: El primer ítem ya cubre el bloque
                        'cantidad': 1.0,
                        'grupo': groupName,
                      };
                    }
                  }
                  
                  _showPanel = true; // Abrir panel al agregar
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('AÑADIR AL EVENTO', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _crearServicioPersonalizado() {
    final nameController = TextEditingController();
    final priceController = TextEditingController(text: '0,00');
    bool isPermanent = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.blueAccent, width: 1)),
          title: const Text('NUEVO SERVICIO AD-HOC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nombre del Servicio', 
                  labelStyle: TextStyle(color: Colors.grey),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                ),
                // Quitamos autofocus para evitar que teclados virtuales disparen saltos o clics accidentales
                autofocus: false, 
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) return newValue;
                    final double value = double.parse(newValue.text) / 100;
                    final String newText = value.toFormattedNumber();
                    return newValue.copyWith(
                      text: newText,
                      selection: TextSelection.collapsed(offset: newText.length),
                    );
                  }),
                ],
                decoration: const InputDecoration(labelText: 'Precio Sugerido', labelStyle: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('¿Agregar a catálogo permanente?', style: TextStyle(color: Colors.white70, fontSize: 12)),
                value: isPermanent,
                activeColor: const Color(0xFFD4AF37),
                onChanged: (val) => setModalState(() => isPermanent = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                
                final cleanPrice = priceController.text.replaceAll('.', '').replaceAll(',', '.');
                final price = double.tryParse(cleanPrice) ?? 0;
                
                final repo = ref.read(eventosRepositoryProvider);
                final nuevoId = await repo.crearServicio(
                  nombre: nameController.text,
                  categoria: 'Personalizado',
                  costoBase: price,
                  eventoId: isPermanent ? null : _tempEventoId,
                );
                
                if (!isPermanent) {
                  _serviciosTemporalesIds.add(nuevoId);
                }
                
                // --- INYECCIÓN OPTIMISTA (ELITE) ---
                // Añadimos el servicio a la memoria local inmediatamente para evitar el 'Desconocido'
                final nuevoSrvModel = Servicio(
                  id: nuevoId,
                  nombre: nameController.text,
                  categoria: 'Personalizado',
                  costoBase: price,
                  eventoId: isPermanent ? null : _tempEventoId,
                );
                
                setState(() {
                  _nombresAdHoc[nuevoId] = nameController.text;
                  _catalogo = [..._catalogo, nuevoSrvModel];
                  _catalogoFiltrado = [..._catalogo, nuevoSrvModel];
                });
                
                // Refrescamos en segundo plano por seguridad
                _fetchCatalogo();
                
                if (mounted) {
                  Navigator.pop(ctx);
                  _solicitarPrecio(nuevoSrvModel);
                }
              },
              child: const Text('CREAR Y AGREGAR'),
            ),
          ],
        ),
      ),
    );
  }


  /// Modal completo para presupuestos: precio + descripción técnica para PDF.
  void _mostrarModalPrecioCompleto(Servicio servicio) {
    final controller = TextEditingController(text: (_serviciosSeleccionados[servicio.id]?['precio'] as num? ?? servicio.costoBase ?? 0).toFormattedNumber());
    final quantityController = TextEditingController(text: (_serviciosSeleccionados[servicio.id]?['cantidad'] as num? ?? 1).toStringAsFixed(0));
    final descController = TextEditingController(text: _detallesServicios[servicio.id] ?? '');
    final groupController = TextEditingController(text: _serviciosSeleccionados[servicio.id]?['grupo']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('DEFINIR DETALLES: ${servicio.nombre.toUpperCase()}'),
        content: SizedBox(
          width: 450, // Ancho fijo para forzar el wrapping del texto
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) return newValue;
                    final double value = double.parse(newValue.text) / 100;
                    final String newText = value.toFormattedNumber();
                    return newValue.copyWith(
                      text: newText,
                      selection: TextSelection.collapsed(offset: newText.length),
                    );
                  }),
                ],
                decoration: InputDecoration(
                  labelText: 'Inversión por este servicio (\$)',
                  prefixIcon: const Icon(Icons.attach_money, color: Color(0xFFD4AF37)),
                  hintText: '0,00',
                  helperText: (servicio.costoBase != null) 
                      ? 'Tarifa sugerida: ${servicio.costoBase!.toCurrency()}'
                      : null,
                  helperStyle: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 10),
                ),
                autofocus: false,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cantidad / Personas',
                  prefixIcon: Icon(Icons.people_outline, color: Color(0xFFD4AF37)),
                  hintText: '1',
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: descController,
                minLines: 4,
                maxLines: 8,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Descripción Técnica Humanizada (Para el PDF)',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 50),
                    child: Icon(Icons.description_outlined),
                  ),
                  hintText: 'Ej: Incluimos sonorización lineal de alta fidelidad con 8 cabezales móviles y efectos atmosféricos profesionales...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Esta descripción aparecerá debajo del título del servicio en el presupuesto final.',
                style: TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: groupController.text),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final suggestions = _sugerenciasVinculacion;
                  if (textEditingValue.text.isEmpty) {
                    return suggestions;
                  }
                  return suggestions.where((String option) {
                    return _normalize(option).contains(_normalize(textEditingValue.text));
                  });
                },

                onSelected: (String selection) {
                  groupController.text = selection;
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  controller.addListener(() {
                    groupController.text = controller.text;
                  });
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Vincular / Nombre de Grupo (Opcional)',
                      prefixIcon: Icon(Icons.link, color: Color(0xFFD4AF37)),
                      hintText: 'Ej: DISEÑO DE ESPACIOS',
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 400,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final String option = options.elementAt(index);
                            return InkWell(
                              onTap: () => onSelected(option),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Text(option, style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 4),
              const Text(
                'Los servicios con el mismo grupo saldrán unificados en el PDF y el panel.',
                style: TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final cleanText = controller.text
                  .replaceAll('.', '')
                  .replaceAll(',', '.');
              
              final precio = double.tryParse(cleanText);
              if (precio != null && precio >= 0) {
                final groupName = groupController.text.trim();
                final quantity = double.tryParse(quantityController.text) ?? 1.0;
                setState(() {
                  _serviciosSeleccionados[servicio.id] = {
                    'precio': precio,
                    'cantidad': quantity,
                    'grupo': groupName.isEmpty ? null : groupName,
                  };
                  _detallesServicios[servicio.id] = descController.text;

                  // MAGIA DE VINCULACIÓN AUTOMÁTICA
                  if (groupName.isNotEmpty) {
                    final normalizedGroup = _normalize(groupName);
                    final matchingUnselected = _catalogo.where((c) =>
                        _normalize(c.nombre) == normalizedGroup &&
                        !_serviciosSeleccionados.containsKey(c.id)).firstOrNull;
                    if (matchingUnselected != null) {
                      _serviciosSeleccionados[matchingUnselected.id] = {
                        'precio': 0.0, // <-- LÓGICA VINCULACIÓN: El primer ítem ya cubre el bloque
                        'cantidad': 1.0,
                        'grupo': groupName,
                      };
                    }
                  }
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('CONFIRMAR DETALLES', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('SISTEMA DE SERVICIOS ELITE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business_rounded, color: Colors.blueAccent),
            tooltip: 'Nuevo Servicio',
            onPressed: _crearServicioPersonalizado,
          ),
          IconButton(
            icon: Icon(_showPanel ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined, color: const Color(0xFFD4AF37)),
            onPressed: () => setState(() => _showPanel = !_showPanel),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: Theme.of(context).scaffoldBackgroundColor)),
          SafeArea(
            child: Row(
              children: [
                // LISTA DE SERVICIOS (70%)
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      _buildSearchBar(),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                              : Builder(
                                  builder: (context) {
                                    // Ordenar: No seleccionados primero, seleccionados al final
                                    final List<Servicio> sortedList = List.from(_catalogoFiltrado);
                                    sortedList.sort((a, b) {
                                      final aSelected = _serviciosSeleccionados.containsKey(a.id);
                                      final bSelected = _serviciosSeleccionados.containsKey(b.id);
                                      if (aSelected && !bSelected) return 1;
                                      if (!aSelected && bSelected) return -1;
                                      return 0;
                                    });

                                    return ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                      itemCount: sortedList.length,
                                      itemBuilder: (context, index) {
                                        final servicio = sortedList[index];
                                        final isSelected = _serviciosSeleccionados.containsKey(servicio.id);
                                        return _buildServiceListItem(servicio, isSelected);
                                      },
                                    );
                                  },
                                ),

                      ),
                    ],
                  ),
                ),

                // PANEL LATERAL (30% si está abierto)
                if (_showPanel)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: MediaQuery.of(context).size.width * (MediaQuery.of(context).size.width > 1200 ? 0.25 : 0.35),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      border: const Border(left: BorderSide(color: Colors.white10, width: 1)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40)],
                    ),
                    child: _buildSidePanel(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        style: const TextStyle(fontSize: 14),
        onSubmitted: _onSearchSubmitted,
        decoration: InputDecoration(
          hintText: 'Buscar servicios...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty 
              ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchController.clear()) 
              : null,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }


  Widget _buildServiceListItem(Servicio servicio, bool isSelected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);
    final esPropio = servicio.eventoId != null;
    
    // Lógica de vinculación
    final String? grupoActual = _serviciosSeleccionados[servicio.id]?['grupo'];
    final bool isSuggested = _suggestedService?.id == servicio.id;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      curve: Curves.easeOutCubic,
      transform: isSelected ? (Matrix4.identity()..scale(1.01)) : Matrix4.identity(),
      decoration: BoxDecoration(
        color: isSelected 
            ? primaryGold.withValues(alpha: 0.12) 
            : (isSuggested 
                ? Colors.blueAccent.withValues(alpha: 0.15)
                : (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02))),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected 
              ? primaryGold 
              : (isSuggested ? Colors.blueAccent : Colors.transparent), 
          width: isSelected ? 1.5 : (isSuggested ? 2.0 : 1),
        ),
        boxShadow: (isSelected || isSuggested) ? [
          BoxShadow(
            color: (isSelected ? primaryGold : Colors.blueAccent).withValues(alpha: 0.3),
            blurRadius: (isSelected ? 15 : 20),
            spreadRadius: (isSelected ? -2 : 0),
            offset: const Offset(0, 4),
          )
        ] : null,

      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // BARRA DE GRUPO (Vinculación)
            if (grupoActual != null)
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: primaryGold,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                ),
              ),
              
            Expanded(
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryGold.withValues(alpha: 0.1) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIconFor(servicio.nombre), 
                    size: 18, 
                    color: isSelected ? primaryGold : (isSuggested ? Colors.blueAccent : Colors.grey),
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      servicio.nombre.toUpperCase(), 
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold, 
                        fontSize: 11, 
                        letterSpacing: 0.5,
                        color: isSelected ? primaryGold : (isSuggested ? Colors.blueAccent : null),
                      ),
                    ),
                    if (esPropio) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
                        child: const Text('AD-HOC', style: TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                    if (grupoActual != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.link, size: 10, color: primaryGold),
                      const SizedBox(width: 4),
                      Text(grupoActual.toUpperCase(), style: TextStyle(fontSize: 8, color: primaryGold, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ],
                  ],
                ),
                subtitle: Text(servicio.categoria, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSuggested && !isSelected)
                      const Text('ENTER PARA AÑADIR ', style: TextStyle(fontSize: 8, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                    isSelected 
                        ? Icon(Icons.check_circle, color: primaryGold, size: 20)
                        : Text((servicio.costoBase ?? 0).toCurrency(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                onTap: () => _solicitarPrecio(servicio),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSidePanel() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
          child: const Row(
            children: [
              Icon(Icons.shopping_bag_outlined, color: Color(0xFFD4AF37), size: 18),
              SizedBox(width: 12),
              Text('RESUMEN DE INVERSIÓN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2)),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _serviciosSeleccionados.isEmpty
                ? const Center(
                    key: ValueKey('empty'),
                    child: Text('No hay servicios seleccionados', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  )
                : Builder(builder: (context) {
                    final Map<String, List<String>> groupsMap = {};
                    final List<String> ungroupedIds = [];

                    for (final id in _serviciosSeleccionados.keys) {
                      final grupo = _serviciosSeleccionados[id]?['grupo'] as String?;
                      if (grupo != null && grupo.isNotEmpty) {
                        groupsMap.putIfAbsent(grupo, () => []).add(id);
                      } else {
                        ungroupedIds.add(id);
                      }
                    }

                    return ListView(
                      key: const ValueKey('list'),
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Individuales (Primero)
                        ...ungroupedIds.map((id) {
                          final data = _serviciosSeleccionados[id];
                          if (data == null) return const SizedBox.shrink();
                          
                          final srv = _catalogo.firstWhere(
                            (s) => s.id == id, 
                            orElse: () {
                              // RESPALDO DE SEGURIDAD (ELITE): Si no está en catálogo, buscar en sesión o detalles
                              final nombreRespaldo = _nombresAdHoc[id] ?? _detallesServicios[id] ?? 'Servicio Ad-hoc';
                              return Servicio(id: id, nombre: nombreRespaldo, categoria: 'Personalizado');
                            }
                          );
                          return _buildPanelItem(srv, (data['precio'] as num? ?? 0).toDouble(), (data['cantidad'] as num? ?? 1).toDouble());
                        }),
                        
                        // Grupos (Al Final)
                        ...groupsMap.entries.map((entry) {
                          final grupoNombre = entry.key;
                          final ids = entry.value;
                          final listServicios = ids.map((id) => _catalogo.firstWhere(
                            (s) => s.id == id, 
                            orElse: () {
                              final nombreRespaldo = _nombresAdHoc[id] ?? _detallesServicios[id] ?? 'Servicio Ad-hoc';
                              return Servicio(id: id, nombre: nombreRespaldo, categoria: 'Personalizado');
                            }
                          )).toList();
                          
                          final totalGrupo = ids.fold(0.0, (sum, id) {
                            final data = _serviciosSeleccionados[id];
                            if (data == null) return sum;
                            return sum + ((data['precio'] as num? ?? 0) * (data['cantidad'] as num? ?? 1));
                          });

                          return _buildGroupedPanelItem(grupoNombre, listServicios, totalGrupo);
                        }),
                      ],
                    );
                  }),
          ),
        ),
        _buildPanelFooter(),
      ],
    );
  }

  Widget _buildPanelItem(Servicio srv, double precio, double cantidad) {
    return InkWell(
      onTap: () => _solicitarPrecio(srv, isEditing: true),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(srv.nombre.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 16),
                  onPressed: () => setState(() => _serviciosSeleccionados.remove(srv.id)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${cantidad.toStringAsFixed(0)} x ${precio.toCurrency()}', style: const TextStyle(color: Colors.grey, fontSize: 9)),
                Text((cantidad * precio).toCurrency(), style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedPanelItem(String nombre, List<Servicio> servicios, double total) {
    final primaryGold = const Color(0xFFD4AF37);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryGold.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ENCABEZADO DE GRUPO PREMIUM
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryGold.withValues(alpha: 0.15), Colors.transparent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: primaryGold, shape: BoxShape.circle),
                  child: const Icon(Icons.link, color: Colors.black, size: 10),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre.toUpperCase(), 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.5)
                      ),
                      Text(
                        'BLOQUE CONSOLIDADO', 
                        style: TextStyle(color: primaryGold.withValues(alpha: 0.7), fontSize: 7, fontWeight: FontWeight.bold)
                      ),
                    ],
                  ),
                ),
                Text(
                  total.toCurrency(), 
                  style: TextStyle(color: primaryGold, fontWeight: FontWeight.w900, fontSize: 12)
                ),
              ],
            ),
          ),
          
          // LISTA DE SUB-SERVICIOS
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: servicios.map((s) {
                final data = _serviciosSeleccionados[s.id];
                if (data == null) return const SizedBox.shrink();
                
                final itemTotal = (data['precio'] as num? ?? 0) * (data['cantidad'] as num? ?? 1);
                
                return InkWell(
                  onTap: () => _solicitarPrecio(s, isEditing: true),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right, color: primaryGold.withValues(alpha: 0.4), size: 12),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.nombre.toUpperCase(), 
                          style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)
                        )
                      ),
                      Text(
                        itemTotal.toCurrency(), 
                        style: const TextStyle(color: Colors.grey, fontSize: 8)
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.link_off, color: Colors.grey, size: 14),
                        onPressed: () => setState(() => _serviciosSeleccionados[s.id]?['grupo'] = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Desvincular',
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            ),
          ),
          
          // ACCIÓN DE GRUPO
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _mostrarDialogoEditarGrupo(nombre),
                  icon: Icon(Icons.edit_note, size: 12, color: primaryGold.withValues(alpha: 0.6)),
                  label: Text('EDITAR BLOQUE', style: TextStyle(color: primaryGold.withValues(alpha: 0.6), fontSize: 8, fontWeight: FontWeight.bold)),
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPanelFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL ESTIMADO', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10)),
              Text(_totalPresupuesto.toCurrency(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSaving ? null : _guardarPresupuesto,
              child: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('CONFIRMAR EVENTO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildServiceCard(Servicio servicio, bool isSelected, double? agreedPrice) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);

    return InkWell(
      onTap: () => _solicitarPrecio(servicio),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryGold.withValues(alpha: 0.12)
              : (isDark ? Colors.white.withValues(alpha: 0.03) : Theme.of(context).cardColor),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryGold : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              _getIconFor(servicio.nombre),
              size: 20,
              color: isSelected ? primaryGold : (isDark ? Colors.white38 : Colors.black38),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                servicio.nombre.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: isSelected ? primaryGold : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryGold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  (agreedPrice ?? 0).toCurrency(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
            ] else
              Icon(Icons.add_circle_outline, size: 16,
                  color: isDark ? Colors.white24 : Colors.black26),
          ],
        ),
      ),
    );
  }

  double get _baseTotal {
    double total = 0;
    for (var id in _serviciosSeleccionados.keys) {
      final srv = _catalogo.firstWhere((s) => s.id == id, orElse: () => Servicio(id: '', nombre: '', categoria: ''));
      total += srv.costoBase ?? 0;
    }
    return total;
  }

  Widget _buildFloatingBottomBar() {
    final primaryGold = const Color(0xFFD4AF37);
    final baseTotal = _baseTotal;
    final percentage = baseTotal > 0 ? (_totalPresupuesto / baseTotal) : 1.0;
    
    Color healthColor = Colors.greenAccent;
    String healthLabel = 'RENTABLE';

    if (percentage < 0.8) {
      healthColor = Colors.redAccent;
      healthLabel = 'BAJO MARGEN';
    } else if (percentage < 0.9) {
      healthColor = Colors.orangeAccent;
      healthLabel = 'AJUSTADO';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_serviciosSeleccionados.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage.clamp(0.0, 1.0),
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  healthLabel,
                  style: TextStyle(color: healthColor, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('INVERSIÓN TOTAL', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  Text(
                    (_totalPresupuesto).toCurrency(),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                onPressed: _isSaving ? null : _guardarPresupuesto,
                child: _isSaving 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Row(
                        children: [
                          Text('CONFIRMAR', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                          SizedBox(width: 8),
                          Icon(Icons.check_circle_outline, size: 18),
                        ],
                      ),
              )
            ],
          ),
        ],
      ),
    );
  }

  IconData _getIconFor(String nombre) {
    switch (nombre.toLowerCase()) {
      case 'sonido': return Icons.speaker;
      case 'iluminación': return Icons.lightbulb_outline;
      case 'ambientación': return Icons.event_seat;
      case 'escenario': return Icons.podcasts; // Close enough icon
      case 'monitoreo': return Icons.monitor;
      case 'pantallas led': return Icons.tv;
      case 'decoración': return Icons.celebration;
      case 'fotografía': return Icons.camera_alt;
      case 'efectos especiales': return Icons.flare;
      case 'espejo mágico': return Icons.photo_camera_front;
      case 'estructuras': return Icons.construction;
      default: return Icons.widgets;
    }
  }
}