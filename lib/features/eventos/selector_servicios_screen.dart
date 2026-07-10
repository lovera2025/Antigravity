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
  /// Si las claves de [serviciosIniciales] son **id de línea** (36 chars), mapea línea → servicio del catálogo. Si es null, las claves se asumen `servicio_id` (comportamiento previo, una fila por servicio).
  final Map<String, String>? servicioIdPorLineaInicial;
  final String modalidad;
  final String? observaciones;
  final String? tituloFestejado;
  /// Nombre corto del festejado/a (Maestro Pro). Si null, se usa [tituloFestejado].
  final String? nombreFestejado;
  /// Encabezado PDF/UI opcional (Maestro Pro).
  final String? encabezadoEvento;
  final String? lugar;
  final String? detalleAnclajeIA;
  final bool isPresupuesto;
  final int validezDias;
  final String? presupuestoId;
  final Map<String, String?>? descripcionesIniciales;
  final String? instagramPublicidad;
  final Map<String, String?>? gruposIniciales;
  /// Orden dentro del combo por servicio (0 = primero, lleva el precio del bloque).
  final Map<String, int>? comboOrdenIniciales;
  final Map<String, double>? cantidadesIniciales;
  final Map<String, bool>? extrasIniciales;
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
    this.servicioIdPorLineaInicial,
    this.modalidad = 'particular',
    this.observaciones,
    this.tituloFestejado,
    this.nombreFestejado,
    this.encabezadoEvento,
    this.lugar,
    this.detalleAnclajeIA,
    this.isPresupuesto = false,
    this.validezDias = 7,
    this.presupuestoId,
    this.descripcionesIniciales,
    this.instagramPublicidad,
    this.telefonoPublicidad,
    this.gruposIniciales,
    this.comboOrdenIniciales,
    this.cantidadesIniciales,
    this.extrasIniciales,
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
  final ScrollController _catalogScrollController = ScrollController();
  final ScrollController _panelScrollController = ScrollController();

  
  // Clave = id de **línea** (UUID); el mismo [servicio_id] del catálogo puede repetirse en varias claves.
  final Map<String, Map<String, dynamic>> _serviciosSeleccionados = {};
  
  // Panel Control
  bool _showPanel = true;
  
  // Map: lineaId -> descripción técnica
  final Map<String, String?> _detallesServicios = {};

  // Inteligencia de Sesión
  late final String _tempEventoId;
  bool _confirmado = false;
  final Set<String> _serviciosTemporalesIds = {};

  // Mapa de nombres para servicios Ad-hoc (Sesión)
  final Map<String, String> _nombresAdHoc = {};

  // Sugerencia Inteligente
  Servicio? _suggestedService;

  static const String _kGrupoDropdownNuevo = '__nuevo__';

  List<String> get _gruposComboExistentes {
    final set = <String>{};
    for (final v in _serviciosSeleccionados.values) {
      final g = (v['grupo'] as String?)?.trim();
      if (g != null && g.isNotEmpty) set.add(g);
    }
    final list = set.toList()..sort();
    return list;
  }

  String? _normGrupo(String? g) {
    if (g == null) return null;
    final t = g.trim();
    return t.isEmpty ? null : t;
  }

  String _grupoDropdownInicial(String rawText) {
    final t = rawText.trim();
    if (t.isEmpty) return '';
    if (_gruposComboExistentes.contains(t)) return t;
    return _kGrupoDropdownNuevo;
  }

  int _computeComboOrdenForSave({
    String? lineaIdEnEdicion,
    required String? grupoResuelto,
    required bool isEditing,
  }) {
    final g = _normGrupo(grupoResuelto);
    if (g == null) return 0;

    if (isEditing && lineaIdEnEdicion != null) {
      final prevG = _normGrupo(_serviciosSeleccionados[lineaIdEnEdicion]?['grupo'] as String?);
      if (prevG == g) {
        return (_serviciosSeleccionados[lineaIdEnEdicion]?['combo_orden'] as num?)?.toInt() ?? 0;
      }
    }

    var maxO = -1;
    for (final e in _serviciosSeleccionados.entries) {
      if (lineaIdEnEdicion != null && e.key == lineaIdEnEdicion) continue;
      if (_normGrupo(e.value['grupo'] as String?) != g) continue;
      final o = (e.value['combo_orden'] as num?)?.toInt() ?? 0;
      if (o > maxO) maxO = o;
    }
    return maxO + 1;
  }

  bool _algunaLineaConServicio(String servicioId) => _serviciosSeleccionados.values
      .any((v) => (v['servicio_id'] as String? ?? '') == servicioId);

  int _lineasMismoCatalogo(String servicioId) => _serviciosSeleccionados.values
      .where((v) => (v['servicio_id'] as String? ?? '') == servicioId)
      .length;

  bool _esExtraData(Map<String, dynamic>? data) =>
      data != null && (data['es_extra'] == true || data['es_extra'] == 1);

  @override
  void initState() {
    super.initState();
    // VINCULACIÓN CORREGIDA: Ahora respeta el ID del presupuesto si existe
    _tempEventoId = widget.eventoId ?? widget.presupuestoId ?? UuidUtils.generate();
    
    // Iniciar el proceso de reconstrucción y limpieza
    if (widget.serviciosIniciales != null) {
      for (var entry in widget.serviciosIniciales!.entries) {
        final k = entry.key;
        final bool clavesSonLineaId = widget.servicioIdPorLineaInicial != null;
        final String lineaId = clavesSonLineaId ? k : UuidUtils.generate();
        final String servicioId =
            clavesSonLineaId ? (widget.servicioIdPorLineaInicial![k] ?? k) : k;
        final String auxK = clavesSonLineaId ? k : servicioId;
        _serviciosSeleccionados[lineaId] = {
          'servicio_id': servicioId,
          'precio': entry.value,
          'cantidad': widget.cantidadesIniciales?[auxK] ?? 1.0,
          'grupo': widget.gruposIniciales?[auxK],
          'combo_orden': widget.comboOrdenIniciales?[auxK] ?? 0,
          'es_extra': widget.extrasIniciales?[auxK] ?? false,
        };
      }
    }

    if (widget.descripcionesIniciales != null) {
      for (final e in widget.descripcionesIniciales!.entries) {
        if (widget.servicioIdPorLineaInicial != null) {
          if (widget.servicioIdPorLineaInicial!.containsKey(e.key) ||
              _serviciosSeleccionados.containsKey(e.key)) {
            _detallesServicios[e.key] = e.value;
          }
        } else {
          for (final linea in _serviciosSeleccionados.entries) {
            if ((linea.value['servicio_id'] as String? ?? linea.key) == e.key) {
              _detallesServicios[linea.key] = e.value;
            }
          }
        }
      }
    }

    // Ejecutar limpieza de servicios huérfanos al entrar si estamos en un evento existente
    if (widget.eventoId != null) {
      final repo = ref.read(eventosRepositoryProvider);
      final List<String> idsEnPresupuesto;
      if (widget.serviciosIniciales == null || widget.serviciosIniciales!.isEmpty) {
        idsEnPresupuesto = [];
      } else if (widget.servicioIdPorLineaInicial != null) {
        idsEnPresupuesto = widget.servicioIdPorLineaInicial!.values.toSet().toList();
      } else {
        idsEnPresupuesto = widget.serviciosIniciales!.keys.toList();
      }
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
    if (_suggestedService != null) {
      _solicitarPrecio(_suggestedService!);
    }
  }

  void _mostrarDialogoEditarGrupo(String nombreGrupo) {
    final groupRenameController = TextEditingController(text: nombreGrupo);
    final idsEnGrupo = _serviciosSeleccionados.entries
        .where((e) => e.value['grupo'] == nombreGrupo)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) {
        final oa = (_serviciosSeleccionados[a]?['combo_orden'] as num?)?.toInt() ?? 0;
        final ob = (_serviciosSeleccionados[b]?['combo_orden'] as num?)?.toInt() ?? 0;
        return oa.compareTo(ob);
      });
    
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
                      final data = _serviciosSeleccionados[id]!;
                      final sid = (data['servicio_id'] as String?) ?? id;
                      final srv = _catalogo.firstWhere(
                        (s) => s.id == sid, 
                        orElse: () {
                          final nombreRespaldo = _nombresAdHoc[sid] ?? _detallesServicios[id] ?? 'Servicio Ad-hoc';
                          return Servicio(id: sid, nombre: nombreRespaldo, categoria: 'Personalizado');
                        }
                      );
                      final ord = (data['combo_orden'] as num?)?.toInt() ?? 0;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          dense: true,
                          title: Text(srv.nombre.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            ord == 0
                                ? '1º del combo • ${((data['precio'] as num) * (data['cantidad'] as num)).toCurrency()} (lleva el total)'
                                : '${ord + 1}º • ${((data['precio'] as num) * (data['cantidad'] as num)).toCurrency()}',
                            style: TextStyle(color: primaryGold, fontSize: 10),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.settings, size: 18, color: Colors.blueAccent),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _solicitarPrecio(srv, isEditing: true, lineaId: id);
                                },
                                tooltip: 'Editar inversión/descripción',
                              ),
                              IconButton(
                                icon: const Icon(Icons.link_off, size: 18, color: Colors.grey),
                                onPressed: () {
                                  setState(() {
                                    _serviciosSeleccionados[id]?['grupo'] = null;
                                    _serviciosSeleccionados[id]?['combo_orden'] = 0;
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
    _catalogScrollController.dispose();
    _panelScrollController.dispose();
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
    return _serviciosSeleccionados.values.fold(0, (sum, val) {
      if (_esExtraData(val)) return sum;
      return sum + ((val['precio'] as num? ?? 0) * (val['cantidad'] as num? ?? 1));
    });
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
          final sid = data['servicio_id'] as String? ?? entry.key;
          serviciosFinales.add({
            'id': entry.key,
            'servicio_id': sid,
            'precio_final': data['precio'] ?? 0.0,
            'cantidad': data['cantidad'] ?? 1.0,
            'detalle_servicio': _detallesServicios[entry.key],
            'grupo': data['grupo'],
            'combo_orden': data['combo_orden'] ?? 0,
            'es_extra': _esExtraData(data),
          });
        }

        if (widget.presupuestoId != null) {
          await pRepo.actualizar(
            id: widget.presupuestoId!,
            tipoEvento: widget.tipoEvento ?? 'Otro',
            lugar: widget.lugar,
            detalleAnclaje: widget.detalleAnclajeIA,
            fechaEvento: widget.fechaEvento,
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
            nombreFestejado: widget.nombreFestejado ?? widget.tituloFestejado,
            encabezadoEvento: widget.encabezadoEvento,
            tituloFestejado: widget.encabezadoEvento ??
                widget.tituloFestejado ??
                widget.nombreFestejado,
            fechaEvento: widget.fechaEvento,
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
              observaciones: widget.observaciones,
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
            nombreFestejado: widget.nombreFestejado ?? widget.tituloFestejado,
            encabezadoEvento: widget.encabezadoEvento,
            tituloFestejado: widget.encabezadoEvento ??
                widget.tituloFestejado ??
                widget.nombreFestejado,
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
        // Edición: volver al detalle/lista que abrió el selector (refresca).
        // Creación: volver al root (flujo crear_evento → selector).
        final esEdicion =
            widget.eventoId != null || widget.presupuestoId != null;
        if (esEdicion) {
          Navigator.pop(context, true);
        } else {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _solicitarPrecio(Servicio servicio, {bool isEditing = false, String? lineaId}) {
    if (widget.isPresupuesto) {
      _mostrarModalPrecioCompleto(servicio, lineaId: lineaId, isEditingLine: isEditing);
    } else {
      _mostrarModalPrecioCantidad(servicio, lineaId: lineaId, isEditingLine: isEditing);
    }
  }

  void _mostrarModalPrecioCantidad(Servicio servicio, {String? lineaId, bool isEditingLine = false}) {
    final bool existe = lineaId != null && isEditingLine && _serviciosSeleccionados.containsKey(lineaId);
    final String? lid = lineaId;
    final double precioActual = (existe && lid != null)
        ? (_serviciosSeleccionados[lid]!['precio'] as num).toDouble()
        : (servicio.costoBase ?? 0.0);
    final double cantidadActual = (existe && lid != null)
        ? (_serviciosSeleccionados[lid]!['cantidad'] as num).toDouble()
        : 1.0;

    final priceController = TextEditingController(text: precioActual.toFormattedNumber());
    final quantityController = TextEditingController(text: cantidadActual.toStringAsFixed(cantidadActual == cantidadActual.toInt() ? 0 : 2));
    final descController = TextEditingController(text: (existe && lid != null) ? (_detallesServicios[lid] ?? '') : '');
    showDialog(
      context: context,
      builder: (ctx) {
        String grupoDd = _grupoDropdownInicial(
          (existe && lid != null) ? (_serviciosSeleccionados[lid]!['grupo']?.toString() ?? '') : '',
        );
        final nuevoNombreCtrl = TextEditingController(
          text: grupoDd == _kGrupoDropdownNuevo
              ? (existe && lid != null ? (_serviciosSeleccionados[lid]!['grupo']?.toString() ?? '').trim() : '')
              : '',
        );

        // ─── Estado local extras combo ──────────────────────────────────
        final Set<String> extrasIds = {};
        final Map<String, TextEditingController> extrasPrecios = {};
        // true = incluido en combo (precio 0), false = precio propio
        final Map<String, bool> extrasIncluidos = {};
        String extraBusqueda = '';
        bool marcarExtra =
            existe && lid != null ? _esExtraData(_serviciosSeleccionados[lid]) : false;
        // ────────────────────────────────────────────────────────────────

        String resolvedGrupoNombre() {
          if (grupoDd.isEmpty) return '';
          if (grupoDd == _kGrupoDropdownNuevo) return nuevoNombreCtrl.text.trim();
          return grupoDd;
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final resolvedPreview = resolvedGrupoNombre();
            final coPreview = _computeComboOrdenForSave(
              lineaIdEnEdicion: existe ? lid : null,
              grupoResuelto: resolvedPreview.isEmpty ? null : resolvedPreview,
              isEditing: existe,
            );

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFD4AF37), width: 1),
              ),
              title: Text(
                servicio.nombre.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      decoration: InputDecoration(
                        labelText: 'Precio Unitario (\$)',
                        labelStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.attach_money, color: Color(0xFFD4AF37)),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        helperText: _normGrupo(resolvedPreview) == null
                            ? null
                            : (coPreview > 0
                                ? 'Incluido en el combo: el total del bloque va en el 1.er ítem. Aquí se guarda \$0.'
                                : '1.er ítem del combo: este importe es el total del bloque en el PDF.'),
                        helperMaxLines: 3,
                        helperStyle: TextStyle(
                          fontSize: 9,
                          color: coPreview > 0 ? Colors.amber.shade200 : Colors.greenAccent.shade100,
                        ),
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
                            setState(() {
                              _showPanel = true;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            minimumSize: const Size(40, 40),
                          ),
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
                    CheckboxListTile(
                      value: marcarExtra,
                      onChanged: (v) => setModalState(() => marcarExtra = v ?? false),
                      checkColor: Colors.black,
                      fillColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return const Color(0xFFD4AF37);
                        }
                        return null;
                      }),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'MARCAR COMO EXTRA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'No suma al total. En el PDF va abajo en la sección EXTRAS con su precio.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 9),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(grupoDd),
                      initialValue: () {
                        const nuevo = _kGrupoDropdownNuevo;
                        final allowed = ['', ..._gruposComboExistentes, nuevo];
                        if (allowed.contains(grupoDd)) return grupoDd;
                        return nuevo;
                      }(),
                      decoration: const InputDecoration(
                        labelText: 'Combo / grupo (PDF unificado)',
                        labelStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.link, color: Color(0xFFD4AF37)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      ),
                      dropdownColor: const Color(0xFF2A2A2A),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Sin combo')),
                        ..._gruposComboExistentes.map(
                          (g) => DropdownMenuItem(value: g, child: Text(g)),
                        ),
                        const DropdownMenuItem(
                          value: _kGrupoDropdownNuevo,
                          child: Text('+ Nuevo combo (nombre propio)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() {
                          grupoDd = v;
                          if (v == _kGrupoDropdownNuevo) {
                            nuevoNombreCtrl.clear();
                          }
                        });
                      },
                    ),
                    if (grupoDd == _kGrupoDropdownNuevo) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: nuevoNombreCtrl,
                        onChanged: (_) => setModalState(() {}),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Nombre del nuevo combo',
                          labelStyle: TextStyle(color: Colors.grey),
                          hintText: 'Ej: Pack Sonido Premium',
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Este servicio es el 1.º del combo: definí acá el precio total del paquete.',
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                    ),
                    // ─── Sección: agregar más servicios al mismo combo ──────
                    if (_normGrupo(resolvedPreview) != null) ...[
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      Row(children: const [
                        Icon(Icons.playlist_add, color: Color(0xFFD4AF37), size: 16),
                        SizedBox(width: 6),
                        Text('INCLUIR EN ESTE COMBO', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8)),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        'Tildados = incluidos sin precio extra. Destildalos si querés que sumen su propio importe.',
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (v) => setModalState(() => extraBusqueda = _normalize(v)),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Buscar servicio del catálogo...',
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                          prefixIcon: Icon(Icons.search, color: Colors.grey, size: 18),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: Builder(builder: (_) {
                          final disponibles = _catalogo.where((s) {
                            if (s.id == servicio.id) return false;
                            if (extrasIds.contains(s.id)) return true;
                            if (extraBusqueda.isEmpty) return true;
                            return _normalize(s.nombre).contains(extraBusqueda);
                          }).toList();
                          if (disponibles.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Sin resultados en el catálogo', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: disponibles.length,
                            itemBuilder: (context, i) {
                              final s = disponibles[i];
                              final isChecked = extrasIds.contains(s.id);
                              final isIncluido = extrasIncluidos[s.id] ?? true;
                              final pCtrl = extrasPrecios[s.id];
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CheckboxListTile(
                                    dense: true,
                                    checkColor: Colors.black,
                                    fillColor: WidgetStateProperty.resolveWith((states) {
                                      if (states.contains(WidgetState.selected)) {
                                        return const Color(0xFFD4AF37);
                                      }
                                      return null;
                                    }),
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(s.nombre.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      s.costoBase != null ? s.costoBase!.toCurrency() : 'Sin tarifa base',
                                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                                    ),
                                    value: isChecked,
                                    onChanged: (v) {
                                      setModalState(() {
                                        if (v == true) {
                                          extrasIds.add(s.id);
                                          extrasIncluidos[s.id] = true;
                                          extrasPrecios[s.id] = TextEditingController(
                                            text: (s.costoBase ?? 0).toFormattedNumber(),
                                          );
                                        } else {
                                          extrasIds.remove(s.id);
                                          extrasIncluidos.remove(s.id);
                                          extrasPrecios[s.id]?.dispose();
                                          extrasPrecios.remove(s.id);
                                        }
                                      });
                                    },
                                  ),
                                  if (isChecked) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12, right: 4, bottom: 2),
                                      child: Row(
                                        children: [
                                          Switch(
                                            value: isIncluido,
                                            activeThumbColor: const Color(0xFFD4AF37),
                                            onChanged: (v) => setModalState(() => extrasIncluidos[s.id] = v),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isIncluido ? 'Incluido en combo' : 'Precio propio',
                                            style: TextStyle(
                                              color: isIncluido ? const Color(0xFFD4AF37) : Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isIncluido && pCtrl != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 40, right: 4, bottom: 8),
                                        child: TextField(
                                          controller: pCtrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(color: Colors.white, fontSize: 12),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.digitsOnly,
                                            TextInputFormatter.withFunction((oldValue, newValue) {
                                              if (newValue.text.isEmpty) return newValue;
                                              final double value = double.parse(newValue.text) / 100;
                                              final String newText = value.toFormattedNumber();
                                              return newValue.copyWith(text: newText, selection: TextSelection.collapsed(offset: newText.length));
                                            }),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Precio propio (\$)',
                                            labelStyle: TextStyle(color: Colors.grey, fontSize: 11),
                                            prefixIcon: Icon(Icons.attach_money, color: Color(0xFFD4AF37), size: 16),
                                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              );
                            },
                          );
                        }),
                      ),
                    ],
                    // ────────────────────────────────────────────────────────
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    final cleanPrice = priceController.text.replaceAll('.', '').replaceAll(',', '.');
                    var price = double.tryParse(cleanPrice) ?? 0;
                    final quantity = double.tryParse(quantityController.text) ?? 1.0;

                    var resolvedGrupo = resolvedGrupoNombre();
                    if (grupoDd == _kGrupoDropdownNuevo && resolvedGrupo.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Escribí un nombre para el nuevo combo.')),
                      );
                      return;
                    }

                    final co = _computeComboOrdenForSave(
                      lineaIdEnEdicion: existe ? lid : null,
                      grupoResuelto: resolvedGrupo.isEmpty ? null : resolvedGrupo,
                      isEditing: existe,
                    );
                    if (co > 0) price = 0;

                    if (price >= 0) {
                      setState(() {
                        final String lineaPrincipal =
                            (existe && lid != null) ? lid : UuidUtils.generate();
                        _serviciosSeleccionados[lineaPrincipal] = {
                          'servicio_id': servicio.id,
                          'precio': price,
                          'cantidad': quantity,
                          'grupo': resolvedGrupo.isEmpty ? null : resolvedGrupo,
                          'combo_orden': co,
                          'es_extra': marcarExtra,
                        };
                        _detallesServicios[lineaPrincipal] =
                            descController.text.trim().isEmpty ? null : descController.text.trim();

                        for (final extraId in List<String>.from(extrasIds)) {
                          final incluido = extrasIncluidos[extraId] ?? true;
                          final extCtrl = extrasPrecios[extraId];
                          final rawExtra = extCtrl?.text ?? '0,00';
                          final cleanExtra = rawExtra.replaceAll('.', '').replaceAll(',', '.');
                          final extraPrecio = incluido ? 0.0 : (double.tryParse(cleanExtra) ?? 0.0);
                          final extraCo = _computeComboOrdenForSave(
                            lineaIdEnEdicion: null,
                            grupoResuelto: resolvedGrupo.isEmpty ? null : resolvedGrupo,
                            isEditing: false,
                          );
                          _serviciosSeleccionados[UuidUtils.generate()] = {
                            'servicio_id': extraId,
                            'precio': extraPrecio,
                            'cantidad': 1.0,
                            'grupo': resolvedGrupo.isEmpty ? null : resolvedGrupo,
                            'combo_orden': extraCo,
                            'es_extra': marcarExtra,
                          };
                        }

                        _showPanel = true;
                      });
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('AÑADIR AL EVENTO', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
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
                activeThumbColor: const Color(0xFFD4AF37),
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
                  _catalogoFiltrado = [..._catalogo];
                });
                
                // Refrescamos en segundo plano por seguridad
                _fetchCatalogo();
                
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
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
  void _mostrarModalPrecioCompleto(
    Servicio servicio, {
    String? lineaId,
    bool isEditingLine = false,
  }) {
    final bool existeP = lineaId != null && isEditingLine && _serviciosSeleccionados.containsKey(lineaId);
    final String? lidP = lineaId;
    final controller = TextEditingController(
      text: (existeP && lidP != null
              ? (_serviciosSeleccionados[lidP]!['precio'] as num? ?? servicio.costoBase ?? 0)
              : (servicio.costoBase ?? 0))
          .toFormattedNumber(),
    );
    final quantityController = TextEditingController(
      text: (existeP && lidP != null
              ? (_serviciosSeleccionados[lidP]!['cantidad'] as num? ?? 1)
              : 1)
          .toStringAsFixed(0),
    );
    final descController = TextEditingController(
      text: (existeP && lidP != null) ? (_detallesServicios[lidP] ?? '') : '',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        String grupoDd = _grupoDropdownInicial(
          (existeP && lidP != null) ? (_serviciosSeleccionados[lidP]!['grupo']?.toString() ?? '') : '',
        );
        final nuevoNombreCtrl = TextEditingController(
          text: grupoDd == _kGrupoDropdownNuevo
              ? (existeP && lidP != null
                  ? (_serviciosSeleccionados[lidP]!['grupo']?.toString() ?? '').trim()
                  : '')
              : '',
        );

        // ─── Estado local extras combo ──────────────────────────────────
        final Set<String> extrasIds = {};
        final Map<String, TextEditingController> extrasPrecios = {};
        final Map<String, bool> extrasIncluidos = {};
        String extraBusqueda = '';
        bool marcarExtra =
            existeP && lidP != null ? _esExtraData(_serviciosSeleccionados[lidP]) : false;
        // ────────────────────────────────────────────────────────────────

        String resolvedGrupoNombre() {
          if (grupoDd.isEmpty) return '';
          if (grupoDd == _kGrupoDropdownNuevo) return nuevoNombreCtrl.text.trim();
          return grupoDd;
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final resolvedPreview = resolvedGrupoNombre();
            final coPreview = _computeComboOrdenForSave(
              lineaIdEnEdicion: existeP ? lidP : null,
              grupoResuelto: resolvedPreview.isEmpty ? null : resolvedPreview,
              isEditing: existeP,
            );

            String? helperInversion;
            Color? helperColor;
            if (_normGrupo(resolvedPreview) != null) {
              helperInversion = coPreview > 0
                  ? 'Incluido en el combo: el total del bloque va en el 1.er ítem. Aquí se guarda \$0.'
                  : '1.er ítem del combo: este importe es el total del bloque en el PDF (títulos unidos con •).';
              helperColor = coPreview > 0 ? Colors.deepOrange : const Color(0xFFD4AF37);
            } else if (servicio.costoBase != null) {
              helperInversion = 'Tarifa sugerida: ${servicio.costoBase!.toCurrency()}';
              helperColor = const Color(0xFFD4AF37);
            }

            return AlertDialog(
              title: Text('DEFINIR DETALLES: ${servicio.nombre.toUpperCase()}'),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setModalState(() {}),
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
                          helperText: helperInversion,
                          helperStyle: TextStyle(
                            color: helperColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                          helperMaxLines: 3,
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
                          hintText:
                              'Ej: Incluimos sonorización lineal de alta fidelidad con 8 cabezales móviles y efectos atmosféricos profesionales...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Esta descripción aparecerá debajo del bloque unificado en el presupuesto final.',
                        style: TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: marcarExtra,
                        onChanged: (v) => setModalState(() => marcarExtra = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'MARCAR COMO EXTRA',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        subtitle: const Text(
                          'No suma al total. En el PDF va abajo en EXTRAS con su precio.',
                          style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>(grupoDd),
                        initialValue: () {
                          final allowed = ['', ..._gruposComboExistentes, _kGrupoDropdownNuevo];
                          if (allowed.contains(grupoDd)) return grupoDd;
                          return _kGrupoDropdownNuevo;
                        }(),
                        decoration: const InputDecoration(
                          labelText: 'Combo / grupo (lista + nuevo)',
                          prefixIcon: Icon(Icons.link, color: Color(0xFFD4AF37)),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('Sin combo')),
                          ..._gruposComboExistentes.map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          ),
                          const DropdownMenuItem(
                            value: _kGrupoDropdownNuevo,
                            child: Text('+ Nuevo combo (nombre propio)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setModalState(() {
                            grupoDd = v;
                            if (v == _kGrupoDropdownNuevo) {
                              nuevoNombreCtrl.clear();
                            }
                          });
                        },
                      ),
                      if (grupoDd == _kGrupoDropdownNuevo) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: nuevoNombreCtrl,
                          onChanged: (_) => setModalState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Nombre del nuevo combo',
                            hintText: 'Ej: Pack Sonido + Ambientación',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Este servicio es el 1.º del combo: definí acá el precio total del paquete.',
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                      ),
                      // ─── Sección: agregar más servicios al mismo combo ───
                      if (_normGrupo(resolvedPreview) != null) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(children: const [
                          Icon(Icons.playlist_add, color: Color(0xFFD4AF37), size: 16),
                          SizedBox(width: 6),
                          Text('INCLUIR EN ESTE COMBO', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Tildados = incluidos sin precio extra. Destildalos si querés que sumen su propio importe.',
                          style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 8),
                      TextField(
                        onChanged: (v) => setModalState(() => extraBusqueda = _normalize(v)),
                        decoration: const InputDecoration(
                          hintText: 'Buscar servicio del catálogo...',
                          prefixIcon: Icon(Icons.search, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: Builder(builder: (_) {
                          final disponibles = _catalogo.where((s) {
                            if (s.id == servicio.id) return false;
                            if (extrasIds.contains(s.id)) return true;
                            if (extraBusqueda.isEmpty) return true;
                            return _normalize(s.nombre).contains(extraBusqueda);
                          }).toList();
                          if (disponibles.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Sin resultados en el catálogo', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: disponibles.length,
                            itemBuilder: (context, i) {
                              final s = disponibles[i];
                              final isChecked = extrasIds.contains(s.id);
                              final isIncluido = extrasIncluidos[s.id] ?? true;
                              final pCtrl = extrasPrecios[s.id];
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CheckboxListTile(
                                    dense: true,
                                    checkColor: Colors.black,
                                    fillColor: WidgetStateProperty.resolveWith((states) {
                                      if (states.contains(WidgetState.selected)) {
                                        return const Color(0xFFD4AF37);
                                      }
                                      return null;
                                    }),
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(s.nombre.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    subtitle: Text(
                                      s.costoBase != null ? s.costoBase!.toCurrency() : 'Sin tarifa base',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    value: isChecked,
                                    onChanged: (v) {
                                      setModalState(() {
                                        if (v == true) {
                                          extrasIds.add(s.id);
                                          extrasIncluidos[s.id] = true;
                                          extrasPrecios[s.id] = TextEditingController(
                                            text: (s.costoBase ?? 0).toFormattedNumber(),
                                          );
                                        } else {
                                          extrasIds.remove(s.id);
                                          extrasIncluidos.remove(s.id);
                                          extrasPrecios[s.id]?.dispose();
                                          extrasPrecios.remove(s.id);
                                        }
                                      });
                                    },
                                  ),
                                  if (isChecked) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12, right: 4, bottom: 2),
                                      child: Row(
                                        children: [
                                          Switch(
                                            value: isIncluido,
                                            activeThumbColor: const Color(0xFFD4AF37),
                                            onChanged: (v) => setModalState(() => extrasIncluidos[s.id] = v),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isIncluido ? 'Incluido en combo' : 'Precio propio',
                                            style: TextStyle(
                                              color: isIncluido ? const Color(0xFFD4AF37) : Colors.black87,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isIncluido && pCtrl != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 40, right: 4, bottom: 8),
                                        child: TextField(
                                          controller: pCtrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.digitsOnly,
                                            TextInputFormatter.withFunction((oldValue, newValue) {
                                              if (newValue.text.isEmpty) return newValue;
                                              final double value = double.parse(newValue.text) / 100;
                                              final String newText = value.toFormattedNumber();
                                              return newValue.copyWith(text: newText, selection: TextSelection.collapsed(offset: newText.length));
                                            }),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Precio propio (\$)',
                                            prefixIcon: Icon(Icons.attach_money, color: Color(0xFFD4AF37), size: 16),
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              );
                            },
                          );
                        }),
                      ),
                    ],
                    // ────────────────────────────────────────────────────────
                  ],
                ),
              ),
            ),
            actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    final cleanText = controller.text.replaceAll('.', '').replaceAll(',', '.');
                    var precio = double.tryParse(cleanText);
                    if (precio == null || precio < 0) return;

                    var resolvedGrupo = resolvedGrupoNombre();
                    if (grupoDd == _kGrupoDropdownNuevo && resolvedGrupo.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Escribí un nombre para el nuevo combo.')),
                      );
                      return;
                    }

                    final co = _computeComboOrdenForSave(
                      lineaIdEnEdicion: existeP ? lidP : null,
                      grupoResuelto: resolvedGrupo.isEmpty ? null : resolvedGrupo,
                      isEditing: existeP,
                    );
                    if (co > 0) precio = 0;

                    final quantity = double.tryParse(quantityController.text) ?? 1.0;
                    setState(() {
                      final String lineaPrincipal =
                          (existeP && lidP != null) ? lidP : UuidUtils.generate();
                      _serviciosSeleccionados[lineaPrincipal] = {
                        'servicio_id': servicio.id,
                        'precio': precio,
                        'cantidad': quantity,
                        'grupo': resolvedGrupo.isEmpty ? null : resolvedGrupo,
                        'combo_orden': co,
                        'es_extra': marcarExtra,
                      };
                      _detallesServicios[lineaPrincipal] = descController.text;

                      for (final extraId in List<String>.from(extrasIds)) {
                        final incluido = extrasIncluidos[extraId] ?? true;
                        final extCtrl = extrasPrecios[extraId];
                        final rawExtra = extCtrl?.text ?? '0,00';
                        final cleanExtra = rawExtra.replaceAll('.', '').replaceAll(',', '.');
                        final extraPrecio = incluido ? 0.0 : (double.tryParse(cleanExtra) ?? 0.0);
                        final extraCo = _computeComboOrdenForSave(
                          lineaIdEnEdicion: null,
                          grupoResuelto: resolvedGrupo.isEmpty ? null : resolvedGrupo,
                          isEditing: false,
                        );
                        _serviciosSeleccionados[UuidUtils.generate()] = {
                          'servicio_id': extraId,
                          'precio': extraPrecio,
                          'cantidad': 1.0,
                          'grupo': resolvedGrupo.isEmpty ? null : resolvedGrupo,
                          'combo_orden': extraCo,
                          'es_extra': marcarExtra,
                        };
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('CONFIRMAR DETALLES', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
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
                                      final aSelected = _algunaLineaConServicio(a.id);
                                      final bSelected = _algunaLineaConServicio(b.id);
                                      if (aSelected && !bSelected) return 1;
                                      if (!aSelected && bSelected) return -1;
                                      return 0;
                                    });

                                    return ListView.builder(
                                      controller: _catalogScrollController,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                      itemCount: sortedList.length,
                                      itemBuilder: (context, index) {
                                        final servicio = sortedList[index];
                                        final isSelected = _algunaLineaConServicio(servicio.id);
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
    
    String? primerGrupoDeServicio() {
      for (final e in _serviciosSeleccionados.entries) {
        if ((e.value['servicio_id'] as String? ?? e.key) == servicio.id) {
          return e.value['grupo'] as String?;
        }
      }
      return null;
    }

    final String? grupoActual = primerGrupoDeServicio();
    final bool isSuggested = _suggestedService?.id == servicio.id;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      curve: Curves.easeOutCubic,
      transform: isSelected
          ? Matrix4.diagonal3Values(1.01, 1.01, 1.0)
          : Matrix4.identity(),
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
                    if (_lineasMismoCatalogo(servicio.id) > 1) ...[
                      const SizedBox(width: 4),
                      Text(
                        '×${_lineasMismoCatalogo(servicio.id)}',
                        style: TextStyle(
                          fontSize: 8,
                          color: isSelected ? primaryGold : Colors.white54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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
                    final tieneExtras = _serviciosSeleccionados.values.any(_esExtraData);

                    return ListView(
                      key: const ValueKey('list'),
                      controller: _panelScrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        ..._buildPanelServiciosList(soloExtras: false),
                        if (tieneExtras) ...[
                          const SizedBox(height: 8),
                          const Divider(color: Colors.white24),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.add_circle_outline, color: Color(0xFFD4AF37).withValues(alpha: 0.8), size: 14),
                              const SizedBox(width: 8),
                              Text(
                                'EXTRAS (no suman)',
                                style: TextStyle(
                                  color: Color(0xFFD4AF37).withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._buildPanelServiciosList(soloExtras: true),
                        ],
                      ],
                    );
                  }),
          ),
        ),
        _buildPanelFooter(),
      ],
    );
  }

  List<Widget> _buildPanelServiciosList({required bool soloExtras}) {
    final Map<String, List<String>> groupsMap = {};
    final List<String> ungroupedIds = [];

    for (final id in _serviciosSeleccionados.keys) {
      final data = _serviciosSeleccionados[id];
      if (data == null) continue;
      if (soloExtras != _esExtraData(data)) continue;

      final grupo = data['grupo'] as String?;
      if (grupo != null && grupo.isNotEmpty) {
        groupsMap.putIfAbsent(grupo, () => []).add(id);
      } else {
        ungroupedIds.add(id);
      }
    }

    return [
      ...ungroupedIds.map((id) {
        final data = _serviciosSeleccionados[id];
        if (data == null) return const SizedBox.shrink();
        final sid = (data['servicio_id'] as String?) ?? id;
        final srv = _catalogo.firstWhere(
          (s) => s.id == sid,
          orElse: () {
            final nombreRespaldo = _nombresAdHoc[sid] ?? _detallesServicios[id] ?? 'Servicio Ad-hoc';
            return Servicio(id: sid, nombre: nombreRespaldo, categoria: 'Personalizado');
          },
        );
        return _buildPanelItem(
          id,
          srv,
          (data['precio'] as num? ?? 0).toDouble(),
          (data['cantidad'] as num? ?? 1).toDouble(),
        );
      }),
      ...groupsMap.entries.map((entry) {
        final grupoNombre = entry.key;
        final ids = List<String>.from(entry.value)
          ..sort((a, b) {
            final oa = (_serviciosSeleccionados[a]?['combo_orden'] as num?)?.toInt() ?? 0;
            final ob = (_serviciosSeleccionados[b]?['combo_orden'] as num?)?.toInt() ?? 0;
            return oa.compareTo(ob);
          });
        final listLineasData = <({String lineaId, Servicio srv})>[];
        for (final lineaId in ids) {
          final data = _serviciosSeleccionados[lineaId];
          if (data == null) continue;
          final sid = (data['servicio_id'] as String?) ?? lineaId;
          final srv = _catalogo.firstWhere(
            (s) => s.id == sid,
            orElse: () {
              final nombreRespaldo = _nombresAdHoc[sid] ?? _detallesServicios[lineaId] ?? 'Servicio Ad-hoc';
              return Servicio(id: sid, nombre: nombreRespaldo, categoria: 'Personalizado');
            },
          );
          listLineasData.add((lineaId: lineaId, srv: srv));
        }

        final totalGrupo = ids.fold(0.0, (sum, id) {
          final data = _serviciosSeleccionados[id];
          if (data == null) return sum;
          return sum + ((data['precio'] as num? ?? 0) * (data['cantidad'] as num? ?? 1));
        });

        return _buildGroupedPanelItem(grupoNombre, listLineasData, totalGrupo);
      }),
    ];
  }

  Widget _buildPanelItem(String lineaId, Servicio srv, double precio, double cantidad) {
    return InkWell(
      onTap: () => _solicitarPrecio(srv, isEditing: true, lineaId: lineaId),
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
                  onPressed: () {
                    setState(() {
                      _serviciosSeleccionados.remove(lineaId);
                      _detallesServicios.remove(lineaId);
                    });
                  },
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

  Widget _buildGroupedPanelItem(String nombre, List<({String lineaId, Servicio srv})> lineas, double total) {
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
              children: lineas.map((e) {
                final data = _serviciosSeleccionados[e.lineaId];
                if (data == null) return const SizedBox.shrink();
                final s = e.srv;
                final itemTotal = (data['precio'] as num? ?? 0) * (data['cantidad'] as num? ?? 1);
                
                return InkWell(
                  onTap: () => _solicitarPrecio(s, isEditing: true, lineaId: e.lineaId),
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
                        onPressed: () => setState(() {
                          _serviciosSeleccionados[e.lineaId]?['grupo'] = null;
                          _serviciosSeleccionados[e.lineaId]?['combo_orden'] = 0;
                        }),
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