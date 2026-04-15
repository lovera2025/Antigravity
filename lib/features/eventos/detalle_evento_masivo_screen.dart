import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/widgets/admin_gate.dart';
import '../../core/config/app_config.dart';

import '../../models/evento.dart';
import '../../models/contrato_alumno.dart';

import '../common/services/pdf_service.dart';
import '../common/utils/currency_extensions.dart';
import '../common/utils/currency_input_formatter.dart';
import 'repositories/eventos_repository.dart';
import 'repositories/contratos_repository.dart';
import '../../core/utils/uuid_utils.dart';
import 'services/calculadora_financiera.dart';

class DetalleEventoMasivoScreen extends ConsumerStatefulWidget {
  final Evento evento;

  const DetalleEventoMasivoScreen({super.key, required this.evento});

  @override
  ConsumerState<DetalleEventoMasivoScreen> createState() => _DetalleEventoMasivoScreenState();
}

class _DetalleEventoMasivoScreenState extends ConsumerState<DetalleEventoMasivoScreen> {
  bool _isLoading = true;
  bool _ocultarMontos = false;
  late DateTime _fechaEventoActual;
  List<ContratoAlumno> _alumnos = [];
  String _busquedaAlumno = '';
  String? _cursoDivisionFiltro;
  bool _ordenAlfabetico = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _fechaEventoActual = widget.evento.fechaEvento;
    _cargarPreferenciaOcultarMontos();
    _fetchDatos();
    _setupRealtime();
  }

  void _setupRealtime() {
    // Escuchar cambios remotos para mantener la UI sincronizada en tiempo real
    final repo = ref.read(contratosRepositoryProvider);
    _realtimeChannel = repo.subscribeToChanges(widget.evento.id, () {
      if (mounted) {
        // Recargar datos de forma silenciosa al detectar un cambio externo
        _fetchDatos(cargaSilenciosa: true);
      }
    });
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _cargarPreferenciaOcultarMontos() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ocultarMontos_${widget.evento.id}';
    if (mounted) {
      setState(() {
        _ocultarMontos = prefs.getBool(key) ?? false;
      });
    }
  }

  Future<void> _guardarPreferenciaOcultarMontos(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ocultarMontos_${widget.evento.id}';
    await prefs.setBool(key, valor);
  }

  Future<void> _forzarAuditoriaInteligente({bool silencioso = false}) async {
    if (!silencioso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ejecutando Auditoría Inteligente en la Base de Datos...'), backgroundColor: Colors.blueAccent),
      );
      setState(() => _isLoading = true);
    }

    try {
      final repo = ref.read(contratosRepositoryProvider);
      final alumnosFrescos = await repo.getByEvento(widget.evento.id);
      bool huboCambios = false;

      for (var a in alumnosFrescos) {
          if (a.nombreAlumno.startsWith('[BAJA]')) continue;

          final pagos = await repo.getHistorialPagosAlumno(a.id);
          if (pagos.isEmpty) continue; 

          double pagadoBase = 0;
          double pagadoMesa = 0;
          double pagadoSillas = 0;

          for (var p in pagos) {
              final concepto = (p['concepto'] as String).toUpperCase();
              double montoNeto = double.parse((p['monto'] as num).toDouble().toStringAsFixed(2));
              double dto = (p['descuento_porcentaje'] as num?)?.toDouble() ?? 0.0;
              
              double montoBruto = montoNeto;
              if (dto > 0 && dto < 100) {
                  montoBruto = montoNeto / (1 - (dto / 100));
              }

              if (concepto.contains('BASE')) pagadoBase += montoBruto;
              else if (concepto.contains('MESA')) pagadoMesa += montoBruto;
              else if (concepto.contains('SILLA')) pagadoSillas += montoBruto;
              else pagadoBase += montoBruto; 
          }

          final int tCuotas = a.totalCuotas ?? 9;
          final int cPagadas = a.cuotasPagadas ?? 0;
          final int mCuotas = a.mesaExtraCuotas ?? 1;
          final int mPagadas = a.mesaExtraCuotasPagadas ?? 0;
          final int sCuotas = a.sillasExtraCuotas ?? 1;
          final int sPagadas = a.sillasExtraCuotasPagadas ?? 0;

          final double totalBase = (a.montoTotalPactado - a.mesaExtraPrecio - a.sillasExtraPrecioTotal);
          final double cuotaPura = tCuotas > 0 ? (totalBase / tCuotas) : totalBase;
          int cuotasBasePagadas = cuotaPura > 0 ? ((pagadoBase + 0.01) / cuotaPura).floor() : 0;

          final double cuotaMesa = a.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1);
          int cuotasMesaPagadas = cuotaMesa > 0 ? ((pagadoMesa + 0.01) / cuotaMesa).floor() : 0;

          final double cuotaSillas = a.sillasExtraPrecioTotal / (sCuotas > 0 ? sCuotas : 1);
          int cuotasSillasPagadas = cuotaSillas > 0 ? ((pagadoSillas + 0.01) / cuotaSillas).floor() : 0;

          final double saldoRealCalculado = a.montoTotalPactado - pagadoBase - pagadoMesa - pagadoSillas;
          final double saldoReal = double.parse(saldoRealCalculado.toStringAsFixed(2)).clamp(0.0, double.infinity);

          if (saldoReal <= 0.01) {
              cuotasBasePagadas = tCuotas;
              cuotasMesaPagadas = (a.mesaExtraPrecio > 0 && mCuotas > 0) ? mCuotas : 0;
              cuotasSillasPagadas = (a.sillasExtraPrecioTotal > 0 && sCuotas > 0) ? sCuotas : 0;
          } else {
              cuotasBasePagadas = cuotasBasePagadas.clamp(0, tCuotas);
              cuotasMesaPagadas = a.mesaExtraPrecio > 0 ? cuotasMesaPagadas.clamp(0, mCuotas) : 0;
              cuotasSillasPagadas = a.sillasExtraPrecioTotal > 0 ? cuotasSillasPagadas.clamp(0, sCuotas) : 0;
          }

          if (cPagadas != cuotasBasePagadas || 
              mPagadas != cuotasMesaPagadas || 
              sPagadas != cuotasSillasPagadas ||
              (a.saldoDeudor - saldoReal).abs() > 0.01) {
              
              await repo.actualizarContrato(a.id, {
                  'cuotas_pagadas': cuotasBasePagadas,
                  'mesa_extra_cuotas_pagadas': cuotasMesaPagadas,
                  'sillas_extra_cuotas_pagadas': cuotasSillasPagadas,
                  'saldo_deudor': saldoReal,
              });
              huboCambios = true;
          }
      }

      final listos = await repo.getByEvento(widget.evento.id);
      if (mounted) {
          setState(() {
            _alumnos = listos;
            _isLoading = false;
          });
          if (!silencioso) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('¡Auditoría completada! Saldos y cuotas sincronizados.'), backgroundColor: Colors.green),
            );
          }
      }
      
    } catch (e) {
        debugPrint('Error en auditoria: $e');
        if (!silencioso && mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error en auditoría: $e')));
        }
    }
  }

  Future<void> _fetchDatos({bool cargaSilenciosa = false}) async {
    if (!cargaSilenciosa) setState(() => _isLoading = true);
    
    try {
      final repo = ref.read(contratosRepositoryProvider);
      
      final alumnos = await repo.getByEvento(widget.evento.id);
      if (mounted) {
        setState(() {
          _alumnos = alumnos;
          _isLoading = false; 
        });
      }

      Future.microtask(() async {
        final reparados = await repo.repararContratosHuerfanos(widget.evento.id);
        if (reparados > 0) {
          debugPrint('🛠️ Se repararon $reparados contratos huérfanos localmente');
        }

        await repo.recalcularTodoElEvento(widget.evento.id);

        await _forzarAuditoriaInteligente(silencioso: true);

        final alumnosActualizados = await repo.getByEvento(widget.evento.id);
        if (mounted) {
          setState(() {
            _alumnos = alumnosActualizados;
          });
        }
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
      debugPrint('Error al cargar datos en DetalleEvento: $e');
      if (mounted && !cargaSilenciosa) setState(() => _isLoading = false);
    }
  }

  /// Refresh ligero: solo recarga la lista desde DB sin auditoría.
  Future<void> _refreshAlumnos() async {
    try {
      final repo = ref.read(contratosRepositoryProvider);
      final alumnos = await repo.getByEvento(widget.evento.id);
      if (mounted) {
        setState(() => _alumnos = alumnos);
      }
    } catch (_) {}
  }

  void _mostrarNotificacionDeuda(ContratoAlumno alumno) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).cardColor,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    AppConfig.tituloGestionCobro,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: Colors.redAccent.withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    'El alumno ${alumno.nombreAlumno} presenta un saldo pendiente de ${alumno.saldoDeudor.toCurrency()}.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'VER PERFIL',
          textColor: const Color(0xFFD4AF37),
          onPressed: () => _mostrarModalEditarAlumno(alumno),
        ),
      ),
    );
  }

  Future<void> _eliminarEvento() async {
    final hasAccess = await AdminGate.check(context, ref);
    if (!hasAccess) return;

    final alumnosActivosEl = _alumnos.where((a) => !a.nombreAlumno.startsWith('[BAJA]')).toList();
    final double saldoAlEliminar = alumnosActivosEl.fold(0, (sum, a) => sum + a.saldoDeudor);
    final bool tieneDeudaAlEliminar = saldoAlEliminar > 0.01;

    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: tieneDeudaAlEliminar ? Colors.deepOrangeAccent : Colors.redAccent,
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              tieneDeudaAlEliminar ? Icons.warning_amber_rounded : Icons.delete_forever_rounded,
              color: tieneDeudaAlEliminar ? Colors.deepOrangeAccent : Colors.redAccent,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              tieneDeudaAlEliminar ? '¡SALDO PENDIENTE!' : 'ATENCIÓN TITÁN',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
          ],
        ),
        content: Text(
          tieneDeudaAlEliminar
              ? 'Este evento tiene ${saldoAlEliminar.toCurrency()} de saldo sin cobrar de alumnos activos. Al eliminarlo, esta deuda desaparecerá del Dashboard. ¿Estás seguro?'
              : 'El evento se ocultará de la lista de eventos activos. Los ingresos y egresos de esta fiesta se conservan en Mi Empresa para tu historial financiero.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tieneDeudaAlEliminar ? Colors.deepOrangeAccent : Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tieneDeudaAlEliminar ? 'ELIMINAR CON DEUDA' : 'ELIMINAR AHORA',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      if (!mounted) return;
      
      setState(() => _isLoading = true);
      final repo = ref.read(eventosRepositoryProvider);
      
      try {
        await repo.actualizarEstado(widget.evento.id, EstadoEvento.cancelado);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Evento dado de baja. Los movimientos siguen en Mi Empresa.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          Navigator.pop(context, true); 
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e')),
          );
        }
      }
    }
  }

  Future<void> _finalizarEvento() async {
    final hasAccess = await AdminGate.check(context, ref);
    if (!hasAccess) return;

    final alumnosActivos = _alumnos.where((a) => !a.nombreAlumno.startsWith('[BAJA]')).toList();
    final double saldoPendiente = alumnosActivos.fold(0, (sum, a) => sum + a.saldoDeudor);
    final bool tieneDeuda = saldoPendiente > 0.01;

    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: tieneDeuda ? Colors.orangeAccent : Colors.greenAccent, 
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              tieneDeuda ? Icons.warning_amber_rounded : Icons.verified_rounded, 
              color: tieneDeuda ? Colors.orangeAccent : Colors.greenAccent, 
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              tieneDeuda ? 'ATENCIÓN: DEUDA ACTIVA' : 'FINALIZAR EVENTO', 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
          ],
        ),
        content: Text(
          tieneDeuda 
            ? 'Este evento aún tiene ${saldoPendiente.toCurrency()} de saldo pendiente. Al finalizarlo, este monto DEJARÁ de figurar en tu capital activo del Dashboard. ¿Deseas archivarlo de todos modos?'
            : '¡Ciclo completado! No hay saldos pendientes. El evento se archivará y dejará de contar como capital cautivo en el Dashboard.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tieneDeuda ? Colors.orangeAccent : Colors.greenAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tieneDeuda ? 'FINALIZAR CON DEUDA' : 'FINALIZAR AHORA', 
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      final repo = ref.read(eventosRepositoryProvider);
      try {
        await repo.actualizarEstado(widget.evento.id, EstadoEvento.finalizado);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Evento finalizado con éxito!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); 
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al finalizar: $e')),
          );
        }
      }
    }
  }

  Future<void> _editarFecha() async {
    final hasAccess = await AdminGate.check(context, ref);
    if (!hasAccess) return;

    if (!mounted) return;
    final nuevaFecha = await showDatePicker(
      context: context,
      initialDate: _fechaEventoActual,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD4AF37),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (nuevaFecha != null && nuevaFecha.isAtSameMomentAs(_fechaEventoActual) == false) {
      setState(() => _isLoading = true);
      try {
        final repo = ref.read(eventosRepositoryProvider);
        await repo.actualizarFecha(widget.evento.id, nuevaFecha);
        if (mounted) {
          setState(() {
            _fechaEventoActual = nuevaFecha;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fecha actualizada correctamente'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al actualizar fecha: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text((widget.evento.cliente?.nombreCompleto ?? 'DETALLE MASIVO').toUpperCase(), style: const TextStyle(fontSize: 14, letterSpacing: 1)),
        backgroundColor: Colors.transparent,
        actions: [
          if (!_isLoading) ...[
            IconButton(
              icon: const Icon(Icons.sync_rounded, color: Color(0xFFD4AF37)),
              onPressed: () => _forzarAuditoriaInteligente(silencioso: false),
              tooltip: 'Auditar y Sincronizar DB',
            ),
            IconButton(
              icon: const Icon(Icons.edit_calendar_outlined, color: Colors.blueAccent),
              onPressed: _editarFecha,
              tooltip: 'Editar Fecha',
            ),
            IconButton(
              icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent),
              onPressed: _finalizarEvento,
              tooltip: 'Finalizar Evento',
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
              onPressed: _eliminarEvento,
              tooltip: 'Eliminar',
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),

      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryGold.withValues(alpha: isDark ? 0.03 : 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (!_isLoading) _buildMetricsPanel(),
                Expanded(child: _buildAlumnosTab()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // FAB ya está definido inline en el build method

  Widget _buildMetricsPanel() {
    final alumnosActivos = _alumnos.where((a) => !a.nombreAlumno.startsWith('[BAJA]')).toList();
    final totalPactado = alumnosActivos.fold<double>(0, (sum, a) => sum + a.montoTotalPactado);
    final saldoPendiente = alumnosActivos.fold<double>(0, (sum, a) => sum + a.saldoDeudor);
    final recaudado = totalPactado - saldoPendiente;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL PACTADO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              Row(
                children: [
                   Text(_ocultarMontos ? '***' : totalPactado.toCurrency(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                   const SizedBox(width: 12),
                   IconButton(
                     icon: Icon(_ocultarMontos ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 20),
                     onPressed: () {
                       setState(() {
                         _ocultarMontos = !_ocultarMontos;
                       });
                       _guardarPreferenciaOcultarMontos(_ocultarMontos);
                     },
                   ),
                ]
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RECAUDADO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(_ocultarMontos ? '***' : recaudado.toCurrency(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.green)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('SALDO PENDIENTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(_ocultarMontos ? '***' : saldoPendiente.toCurrency(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.amber)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlumnosTab() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_alumnos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No hay alumnos registrados para este evento.'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _mostrarModalRegistrarAlumno,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('REGISTRAR ALUMNO'),
            ),
          ],
        ),
      );
    }

    final query = _busquedaAlumno.trim().toLowerCase();

    final divisionesDisponibles = _alumnos
        .where((a) => !a.nombreAlumno.startsWith('[BAJA]'))
        .map((a) => a.cursoDivision?.trim())
        .where((v) => v != null && v.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();

    final alumnosFiltrados = _alumnos.where((a) {
      if (a.nombreAlumno.startsWith('[BAJA]')) return false;
      if (_cursoDivisionFiltro != null &&
          (_cursoDivisionFiltro!.isNotEmpty) &&
          (a.cursoDivision ?? '').trim() != _cursoDivisionFiltro) {
        return false;
      }
      if (query.isEmpty) return true;
      final nombre = a.nombreAlumno.toLowerCase();
      final curso = (a.cursoDivision ?? '').toLowerCase();
      return nombre.contains(query) || curso.contains(query);
    }).toList();

    if (_ordenAlfabetico) {
      alumnosFiltrados.sort((a, b) => a.nombreAlumno.toLowerCase().compareTo(b.nombreAlumno.toLowerCase()));
    } else {
      alumnosFiltrados.sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        final double horizontalPad = availableWidth > 800 ? 32 : 16;
        final double tableWidth = availableWidth - (horizontalPad * 2);

        final double colAlumno = tableWidth * 0.22;
        final double colTelefono = tableWidth * 0.13;
        final double colAcomp = tableWidth * 0.16;
        final double colEstado = tableWidth * 0.24;
        final double colAcciones = tableWidth * 0.25;

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(horizontalPad, 24, horizontalPad, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'ALUMNOS INSCRIPTOS',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.2,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFFD4AF37)),
                                const SizedBox(width: 6),
                                Text(
                                  '${alumnosFiltrados.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: Color(0xFFD4AF37),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: _mostrarModalRegistrarAlumno,
                            icon: const Icon(Icons.person_add_alt_1, size: 18),
                            label: const Text('REGISTRAR ALUMNO',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 0.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                            ),
                          ),
                        ],
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _ordenAlfabetico = !_ordenAlfabetico;
                                  });
                                },
                                icon: Icon(_ordenAlfabetico ? Icons.sort_by_alpha : Icons.schedule, size: 16),
                                label: Text(_ordenAlfabetico ? 'ORDEN A-Z' : 'FECHA', style: const TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                  foregroundColor: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  if (_alumnos.isNotEmpty) {
                                    PdfService.generarPlanillaCursos(widget.evento, _alumnos);
                                  }
                                },
                                icon: const Icon(Icons.print_rounded, size: 18),
                                label: const Text('PLANILLA CURSOS', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white12,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _sortearMesas,
                                icon: const Icon(Icons.casino, size: 18),
                                label: const Text('SORTEAR MESAS', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _deshacerSorteoMesas,
                                icon: const Icon(Icons.undo, size: 18),
                                label: const Text('DESHACER MESAS', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepOrange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Buscar por alumno o curso',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _busquedaAlumno = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: _cursoDivisionFiltro,
                        hint: const Text('Todos'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...divisionesDisponibles.map(
                            (div) => DropdownMenuItem<String>(
                              value: div,
                              child: Text(div),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _cursoDivisionFiltro = value;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: availableWidth),
                    child: DataTable(
                      columnSpacing: availableWidth > 1000 ? 24 : 16,
                      horizontalMargin: horizontalPad,
                      headingRowHeight: 48,
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 90,
                      columns: [
                        DataColumn(label: SizedBox(width: colAlumno, child: const Text('ALUMNO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)))),
                        DataColumn(label: SizedBox(width: colTelefono, child: const Text('TELÉFONO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)))),
                        DataColumn(label: SizedBox(width: colAcomp, child: const Text('ACOMP.', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)))),
                        DataColumn(label: SizedBox(width: colEstado, child: const Text('ESTADO DE DEUDA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)))),
                        DataColumn(label: SizedBox(width: colAcciones, child: const Text('ACCIONES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)))),
                      ],
                      rows: alumnosFiltrados.map((a) {
                        final int tCuotas = a.totalCuotas ?? 9;
                        final int cPagadas = a.cuotasPagadas ?? 0;
                        final int cantAcomp = a.cantidadAcompanantes ?? 0;

                        final now = DateTime.now();
                        final int diaVencimiento = a.diaVencimientoMensual;
                        final int totalCuotas = tCuotas > 0 ? tCuotas : 9;

                        final fechaInicio = a.createdAt ?? now;
                        final inicioMes = DateTime(fechaInicio.year, fechaInicio.month, 1);
                        final mesCorriente = DateTime(now.year, now.month, 1);
                        int mesesTranscurridos = (mesCorriente.year - inicioMes.year) * 12 +
                            (mesCorriente.month - inicioMes.month);
                        if (now.day >= diaVencimiento) mesesTranscurridos += 1;
                        final int cuotasEsperadas = mesesTranscurridos.clamp(0, totalCuotas);
                        
                        // REGLA SUPREMA: Si la deuda es $0.00, está LIQUIDADO, sin importar los contadores parciales.
                        final bool estaLiquidado = a.saldoDeudor <= 0.01;
                        final bool esMoraReal = !estaLiquidado && (cuotasEsperadas - cPagadas) > 0;

                        final Color estadoColor = estaLiquidado 
                            ? Colors.greenAccent 
                            : (esMoraReal ? Colors.redAccent : const Color(0xFFD4AF37));

                        final IconData estadoIcono = estaLiquidado
                            ? Icons.verified_rounded
                            : (esMoraReal ? Icons.warning_amber_rounded : Icons.info_outline_rounded);

                        final String estadoTexto = estaLiquidado
                            ? 'LIQUIDADO'
                            : (esMoraReal ? 'MORA VENCIDA' : 'AL DÍA');
                        
                        final String montoTexto = estaLiquidado 
                            ? ''
                            : 'Saldo: ${_ocultarMontos ? '***' : a.saldoDeudor.toCurrency()}';

                        final int cuotasMostrar = estaLiquidado ? totalCuotas : cPagadas;
                        final cuotaInfo = '($cuotasMostrar/$totalCuotas cuotas)';

                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: colAlumno,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      a.nombreAlumno,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                    if (a.cursoDivision != null && a.cursoDivision!.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(top: 3),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          a.cursoDivision!,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue),
                                        ),
                                      ),
                                    if (a.createdAt != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4, left: 2),
                                        child: Text(
                                          'Reg: ${a.createdAt!.day}/${a.createdAt!.month}/${a.createdAt!.year % 100}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.withValues(alpha: 0.6),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            DataCell(
                              SizedBox(
                                width: colTelefono,
                                child: Text(
                                  a.telefono?.isNotEmpty == true ? a.telefono! : '-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: a.telefono?.isNotEmpty == true ? null : Colors.grey.shade500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),

                            DataCell(
                              SizedBox(
                                width: colAcomp,
                                child: GestureDetector(
                                  onTap: () => _mostrarModalDetalleAcompanantes(a),
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Chip(
                                          label: Text(
                                            '+$cantAcomp',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                                          side: BorderSide(
                                            color: Colors.blue.withValues(alpha: 0.3),
                                          ),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        if (a.nombresAcompanantes.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              a.nombresAcompanantes.join(', '),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: colEstado,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          estadoIcono,
                                          color: estadoColor,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            estadoTexto,
                                            style: TextStyle(
                                              color: estadoColor,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (montoTexto.isNotEmpty)
                                      Text(
                                        montoTexto,
                                        style: TextStyle(
                                          color: estadoColor.withValues(alpha: 0.8),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    Text(
                                      cuotaInfo,
                                      style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    tooltip: 'Editar alumno/cuotas',
                                    onPressed: () => _mostrarModalEditarAlumno(a),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.payments_outlined, size: 20),
                                    tooltip: 'Registrar pago',
                                    onPressed: () => _mostrarModalPagoAlumno(a),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 20, color: Color(0xFFD4AF37)),
                                    tooltip: 'Ver Estado de Cuenta',
                                    onPressed: () => _mostrarHistorialPagosAlumno(a),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                                    tooltip: 'Generar Recibo',
                                    onPressed: () => _imprimirReciboAlumno(a),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    tooltip: 'Eliminar alumno',
                                    onPressed: () => _eliminarAlumno(a),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _eliminarAlumno(ContratoAlumno alumno) async {
    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Baja'),
        content: Text('¿Está seguro de que desea dar de baja a ${alumno.nombreAlumno}? Esta acción conservará el registro pero no contará para los saldos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DAR DE BAJA'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final repo = ref.read(contratosRepositoryProvider);
      try {
        await repo.actualizarContrato(alumno.id, {
          'nombre_alumno': '[BAJA] ${alumno.nombreAlumno}'
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alumno dado de baja correctamente')),
          );
          _fetchDatos(cargaSilenciosa: true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al dar de baja alumno: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  void _mostrarModalDetalleAcompanantes(ContratoAlumno alumno) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LISTA DE ACOMPAÑANTES',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            Text(
              alumno.nombreAlumno,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: alumno.nombresAcompanantes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No hay acompañantes registrados nominalmente.',
                        style: TextStyle(
                            fontStyle: FontStyle.italic, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: alumno.nombresAcompanantes.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue),
                          ),
                        ),
                        title: Text(
                          alumno.nombresAcompanantes[index],
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 14),
                        ),
                        dense: true,
                      );
                    },
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _sortearMesas() async {
    final maxMesasCtrl = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sortear Mesas al Azar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se asignarán números de mesa a los alumnos que aún no tienen una asignada.'),
            const SizedBox(height: 16),
            TextField(
              controller: maxMesasCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cantidad Total de Mesas Posibles (ej: 100)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(maxMesasCtrl.text);
              if (val != null && val > 0) {
                Navigator.pop(context, val);
              }
            },
            child: const Text('SORTEAR'),
          ),
        ],
      ),
    );

    if (result == null) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(contratosRepositoryProvider);
      
      final todosGlobal = await repo.getAllContratos();
      final ocupadas = <int>{};
      for (final c in todosGlobal) {
        if (c.numeroMesa != null && c.numeroMesa!.isNotEmpty) {
          final parts = c.numeroMesa!.split(',');
          for (final p in parts) {
            final num = int.tryParse(p.trim());
            if (num != null) ocupadas.add(num);
          }
        }
      }

      final alumnosSinMesa = _alumnos.where((a) => !a.nombreAlumno.startsWith('[BAJA]') && (a.numeroMesa == null || a.numeroMesa!.isEmpty)).toList();
      if (alumnosSinMesa.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todos los alumnos ya tienen mesa asignada.')));
        return;
      }

      final disponibles = <int>[];
      for (int i = 1; i <= result; i++) {
        if (!ocupadas.contains(i)) disponibles.add(i);
      }
      disponibles.shuffle();

      int actualizados = 0;
      for (final alumno in alumnosSinMesa) {
        if (disponibles.isEmpty) break;

        final necesitaExtra = alumno.mesaExtraPrecio > 0;
        String asignacion = '';

        if (necesitaExtra) {
          disponibles.sort();
          int idxConsec = -1;
          for (int i = 0; i < disponibles.length - 1; i++) {
            if (disponibles[i + 1] == disponibles[i] + 1) {
              idxConsec = i;
              break;
            }
          }

          if (idxConsec != -1) {
            final m1 = disponibles.removeAt(idxConsec);
            final m2 = disponibles.removeAt(idxConsec);
            asignacion = '$m1, $m2';
            disponibles.shuffle();
          } else {
            disponibles.shuffle();
            if (disponibles.length >= 2) {
              final m1 = disponibles.removeLast();
              final m2 = disponibles.removeLast();
              asignacion = '$m1, $m2';
            } else {
              asignacion = '${disponibles.removeLast()}';
            }
          }
        } else {
          asignacion = '${disponibles.removeLast()}';
        }

        if (asignacion.isNotEmpty) {
          await repo.actualizarContrato(alumno.id, {'numero_mesa': asignacion});
          actualizados++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Se asignaron mesas a $actualizados alumnos.')));
      }
    } catch (e) {
      debugPrint('Error en sorteo: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        _fetchDatos(cargaSilenciosa: true);
      }
    }
  }

  Future<void> _deshacerSorteoMesas() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deshacer Asignación de Mesas'),
        content: const Text('¿Estás seguro de que deseas eliminar las mesas asignadas a TODOS los alumnos de este evento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DESHACER MESAS'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(contratosRepositoryProvider);
      
      final alumnosConMesa = _alumnos.where((a) => !a.nombreAlumno.startsWith('[BAJA]') && a.numeroMesa != null && a.numeroMesa!.isNotEmpty).toList();
      
      if (alumnosConMesa.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay alumnos con mesa asignada para deshacer.')));
        return;
      }

      int actualizados = 0;
      for (final alumno in alumnosConMesa) {
        await repo.actualizarContrato(alumno.id, {'numero_mesa': null});
        actualizados++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Se eliminaron las mesas de $actualizados alumnos.')));
      }
    } catch (e) {
      debugPrint('Error al deshacer mesas: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        _fetchDatos(cargaSilenciosa: true);
      }
    }
  }

  Future<void> _mostrarModalRegistrarAlumno() async {
    final prefs = await SharedPreferences.getInstance();
    final double? ultimoMonto = prefs.getDouble('ultimo_monto_${widget.evento.id}');
    if (!mounted) return;

    final nombreCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final acompNombreCtrl = TextEditingController();
    final montoCtrl = TextEditingController(text: ultimoMonto != null ? ultimoMonto.toFormattedNumber() : '');
    final institucionCtrl = TextEditingController();
    final cursoDivisionCtrl = TextEditingController();
    final musicaElegidaCtrl = TextEditingController();
    final numeroMesaCtrl = TextEditingController();
    final cuotasCtrl = TextEditingController(text: '9');
    final mesaPrecioCtrl = TextEditingController();
    final mesaCuotasCtrl = TextEditingController(text: '1');
    int sillasExtraCant = 0;
    final sillasPrecioCtrl = TextEditingController();
    List<String> acompanantes = [];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Registrar Alumno'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del alumno',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono del alumno',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: cursoDivisionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Curso / División (ej: 6 "A")',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: musicaElegidaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Música Elegida',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: numeroMesaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mesa',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const Text(
                  'GESTIÓN DE ACOMPAÑANTES',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: acompNombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del acompañante',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            setModalState(() {
                              acompanantes.add(val.trim());
                              acompNombreCtrl.clear();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () {
                        if (acompNombreCtrl.text.trim().isNotEmpty) {
                          setModalState(() {
                            acompanantes.add(acompNombreCtrl.text.trim());
                            acompNombreCtrl.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: acompanantes
                      .map((name) => Chip(
                            label: Text(name, style: const TextStyle(fontSize: 11)),
                            onDeleted: () => setModalState(() {
                              acompanantes.remove(name);
                            }),
                            deleteIconColor: Colors.redAccent,
                            backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          ))
                      .toList(),
                ),
                if (acompanantes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${acompanantes.length} invitados',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blue,
                    ),
                  ),
                ],
                const Divider(height: 32),
                TextField(
                  controller: montoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Monto total pactado',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cuotasCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Plan de cuotas (Total)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const Text('EXTRAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: mesaPrecioCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: const InputDecoration(labelText: 'Mesa Extra (Precio)', prefixText: '\$ ', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: mesaCuotasCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Cuotas Mesa', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: sillasExtraCant,
                        decoration: const InputDecoration(labelText: 'Sillas Extras', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('0 Sillas')),
                          DropdownMenuItem(value: 1, child: Text('1 Silla')),
                          DropdownMenuItem(value: 2, child: Text('2 Sillas')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => sillasExtraCant = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: sillasPrecioCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: const InputDecoration(labelText: 'Precio Total Sillas', prefixText: '\$ ', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                final telefono = telefonoCtrl.text.trim();
                final montoBaseBruto = CurrencyInputFormatter.parse(montoCtrl.text);
                final institucion = institucionCtrl.text.trim();
                final cursoDivision = cursoDivisionCtrl.text.trim();
                final musicaElegida = musicaElegidaCtrl.text.trim();
                final planCuotas = int.tryParse(cuotasCtrl.text) ?? 9;
                final mesaPrecio = CurrencyInputFormatter.parse(mesaPrecioCtrl.text);
                final mesaCuotas = int.tryParse(mesaCuotasCtrl.text) ?? 1;
                final sillasPrecio = CurrencyInputFormatter.parse(sillasPrecioCtrl.text);

                final totalGeneralBruto = montoBaseBruto + mesaPrecio + sillasPrecio;

                if (nombre.isEmpty || montoBaseBruto <= 0) return;

                final alumnoExistente = _alumnos.any((a) => a.nombreAlumno.toLowerCase() == nombre.toLowerCase());
                if (alumnoExistente) {
                    final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                            title: const Text('⚠️ Alumno Duplicado', style: TextStyle(color: Colors.orangeAccent)),
                            content: Text('El sistema detectó que ya existe un alumno registrado con el nombre "$nombre" en este evento.\n\n¿Estás seguro que deseas registrarlo nuevamente?'),
                            actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('REVISAR')),
                                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), child: const Text('SÍ, REGISTRAR IGUAL')),
                            ],
                        )
                    );
                    if (confirm != true) return;
                }

                final repo = ref.read(contratosRepositoryProvider);
                final nuevoContrato = ContratoAlumno(
                  id: UuidUtils.generate(),
                  eventoId: widget.evento.id,
                  nombreAlumno: nombre,
                  cantidadAcompanantes: acompanantes.length,
                  nombresAcompanantes: acompanantes,
                  montoTotalPactado: totalGeneralBruto,
                  saldoDeudor: totalGeneralBruto,
                  porcentajeDescuento: 0.0,
                  totalCuotas: planCuotas,
                  mesaExtraPrecio: mesaPrecio,
                  mesaExtraCuotas: mesaCuotas,
                  sillasExtraCantidad: sillasExtraCant,
                  sillasExtraPrecioTotal: sillasPrecio,
                  institucion: institucion.isNotEmpty ? institucion : null,
                  cursoDivision: cursoDivision.isNotEmpty ? cursoDivision : null,
                  musicaElegida: musicaElegida.isNotEmpty ? musicaElegida : null,
                  numeroMesa: numeroMesaCtrl.text.trim().isNotEmpty ? numeroMesaCtrl.text.trim() : null,
                  telefono: telefono.isNotEmpty ? telefono : null,
                  createdAt: DateTime.now(),
                );

                await repo.registrarContrato(nuevoContrato);

                await prefs.setDouble('ultimo_monto_${widget.evento.id}', montoBaseBruto);

                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('GUARDAR'),
            ),
          ],
        ),
      ),
    );

    if (mounted && result == true) {
      _refreshAlumnos();
    }
  }

  Future<void> _mostrarModalEditarAlumno(ContratoAlumno alumno) async {
    final nombreCtrl = TextEditingController(text: alumno.nombreAlumno);
    final telefonoCtrl = TextEditingController(text: alumno.telefono ?? '');
    final acompNombreCtrl = TextEditingController();
    final double montoBaseUI = alumno.montoTotalPactado - alumno.mesaExtraPrecio - alumno.sillasExtraPrecioTotal;
    final montoCtrl = TextEditingController(text: montoBaseUI.toFormattedNumber());
    final institucionCtrl = TextEditingController(text: alumno.institucion ?? '');
    final cursoDivisionCtrl = TextEditingController(text: alumno.cursoDivision ?? '');
    final musicaElegidaCtrl = TextEditingController(text: alumno.musicaElegida ?? '');
    final numeroMesaCtrl = TextEditingController(text: alumno.numeroMesa ?? '');
    
    final cuotasCtrl = TextEditingController(text: (alumno.totalCuotas ?? 9).toString());
    final cuotasPagadasCtrl = TextEditingController(text: (alumno.cuotasPagadas ?? 0).toString());
    
    final mesaPrecioCtrl = TextEditingController(text: alumno.mesaExtraPrecio > 0 ? alumno.mesaExtraPrecio.toFormattedNumber() : '');
    final mesaCuotasCtrl = TextEditingController(text: (alumno.mesaExtraCuotas ?? 1).toString());
    final mesaCuotasPagadasCtrl = TextEditingController(text: (alumno.mesaExtraCuotasPagadas ?? 0).toString());
    
    int sillasExtraCant = alumno.sillasExtraCantidad ?? 0;
    final sillasPrecioCtrl = TextEditingController(text: alumno.sillasExtraPrecioTotal > 0 ? alumno.sillasExtraPrecioTotal.toFormattedNumber() : '');
    
    List<String> acompanantes = List.from(alumno.nombresAcompanantes);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Editar Alumno'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nombre del alumno',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono del alumno',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: cursoDivisionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Curso / División (ej: 6 "A")',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: musicaElegidaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Música Elegida',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: numeroMesaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mesa',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(),
                const Text(
                  'GESTIÓN DE ACOMPAÑANTES',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: acompNombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del acompañante',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            setModalState(() {
                              acompanantes.add(val.trim());
                              acompNombreCtrl.clear();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () {
                        if (acompNombreCtrl.text.trim().isNotEmpty) {
                          setModalState(() {
                            acompanantes.add(acompNombreCtrl.text.trim());
                            acompNombreCtrl.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: acompanantes
                      .map((name) => Chip(
                            label: Text(name, style: const TextStyle(fontSize: 11)),
                            onDeleted: () => setModalState(() {
                              acompanantes.remove(name);
                            }),
                            deleteIconColor: Colors.redAccent,
                            backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          ))
                      .toList(),
                ),
                if (acompanantes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${acompanantes.length} invitados',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blue,
                    ),
                  ),
                ],
                const Divider(height: 32),
                TextField(
                  controller: montoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'Monto total pactado',
                      prefixText: '\$ ',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cuotasCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Plan de cuotas (Total)',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: cuotasPagadasCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Cuotas ya pagadas',
                            border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const Text('EXTRAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: mesaPrecioCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: const InputDecoration(labelText: 'Mesa Extra (Precio)', prefixText: '\$ ', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: mesaCuotasCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Cuotas Mesa (Total)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: mesaCuotasPagadasCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Cuotas Pagadas (Mesa)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: sillasExtraCant,
                        decoration: const InputDecoration(labelText: 'Sillas Extras', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('0 Sillas')),
                          DropdownMenuItem(value: 1, child: Text('1 Silla')),
                          DropdownMenuItem(value: 2, child: Text('2 Sillas')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => sillasExtraCant = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: sillasPrecioCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: const InputDecoration(labelText: 'Precio Total Sillas', prefixText: '\$ ', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                final montoBaseBruto = CurrencyInputFormatter.parse(montoCtrl.text);
                final mesaPrecio = CurrencyInputFormatter.parse(mesaPrecioCtrl.text);
                final sillasPrecio = CurrencyInputFormatter.parse(sillasPrecioCtrl.text);

                final institucion = institucionCtrl.text.trim();
                final telefono = telefonoCtrl.text.trim();
                final cursoDivision = cursoDivisionCtrl.text.trim();
                final musicaElegida = musicaElegidaCtrl.text.trim();
                final numeroMesa = numeroMesaCtrl.text.trim();
                
                final planCuotas = int.tryParse(cuotasCtrl.text) ?? (alumno.totalCuotas ?? 9);
                final cuotasPagadas = int.tryParse(cuotasPagadasCtrl.text) ?? (alumno.cuotasPagadas ?? 0);
                
                final mesaCuotas = int.tryParse(mesaCuotasCtrl.text) ?? (alumno.mesaExtraCuotas ?? 1);
                final mesaCuotasPagadas = int.tryParse(mesaCuotasPagadasCtrl.text) ?? (alumno.mesaExtraCuotasPagadas ?? 0);

                final nuevoTotalBruto = montoBaseBruto + mesaPrecio + sillasPrecio;

                if (nombre.isEmpty) return;

                final repo = ref.read(contratosRepositoryProvider);

                final Map<String, dynamic> updates = {
                  'nombre_alumno': nombre,
                  'cantidad_acompanantes': acompanantes.length,
                  'nombres_acompanantes': acompanantes,
                  'monto_total_pactado': double.parse(nuevoTotalBruto.toStringAsFixed(2)),
                  'saldo_deudor': double.parse((nuevoTotalBruto - (alumno.montoTotalPactado - alumno.saldoDeudor)).clamp(0, double.infinity).toStringAsFixed(2)),
                  'total_cuotas': planCuotas,
                  'cuotas_pagadas': cuotasPagadas,
                  'mesa_extra_precio': double.parse(mesaPrecio.toStringAsFixed(2)),
                  'mesa_extra_cuotas': mesaCuotas,
                  'mesa_extra_cuotas_pagadas': mesaCuotasPagadas,
                  'sillas_extra_cantidad': sillasExtraCant,
                  'sillas_extra_precio_total': double.parse(sillasPrecio.toStringAsFixed(2)),
                };

                if (institucion.isNotEmpty) {
                  updates['institucion'] = institucion;
                } else if (alumno.institucion != null && alumno.institucion!.isNotEmpty) {
                  updates['institucion'] = null;
                }

                if (cursoDivision.isNotEmpty) {
                  updates['curso_division'] = cursoDivision;
                } else if (alumno.cursoDivision != null && alumno.cursoDivision!.isNotEmpty) {
                  updates['curso_division'] = null;
                }

                if (musicaElegida.isNotEmpty) {
                  updates['musica_elegida'] = musicaElegida;
                } else if (alumno.musicaElegida != null && alumno.musicaElegida!.isNotEmpty) {
                  updates['musica_elegida'] = null;
                }

                if (numeroMesa.isNotEmpty) {
                  updates['numero_mesa'] = numeroMesa;
                } else if (alumno.numeroMesa != null && alumno.numeroMesa!.isNotEmpty) {
                  updates['numero_mesa'] = null;
                }

                if (telefono.isNotEmpty) {
                  updates['telefono'] = telefono;
                } else if (alumno.telefono != null && alumno.telefono!.isNotEmpty) {
                  updates['telefono'] = null;
                }

                await repo.actualizarContrato(alumno.id, updates);

                // ACTUALIZACIÓN LOCAL INSTANTÁNEA
                final nuevoSaldoDeudor = double.parse((nuevoTotalBruto - (alumno.montoTotalPactado - alumno.saldoDeudor)).clamp(0, double.infinity).toStringAsFixed(2));
                final alumnoEditado = alumno.copyWith(
                  nombreAlumno: nombre,
                  telefono: telefono.isNotEmpty ? telefono : null,
                  cantidadAcompanantes: acompanantes.length,
                  nombresAcompanantes: acompanantes,
                  montoTotalPactado: double.parse(nuevoTotalBruto.toStringAsFixed(2)),
                  saldoDeudor: nuevoSaldoDeudor,
                  totalCuotas: planCuotas,
                  cuotasPagadas: cuotasPagadas,
                  mesaExtraPrecio: double.parse(mesaPrecio.toStringAsFixed(2)),
                  mesaExtraCuotas: mesaCuotas,
                  mesaExtraCuotasPagadas: mesaCuotasPagadas,
                  sillasExtraCantidad: sillasExtraCant,
                  sillasExtraPrecioTotal: double.parse(sillasPrecio.toStringAsFixed(2)),
                  institucion: institucion.isNotEmpty ? institucion : null,
                  cursoDivision: cursoDivision.isNotEmpty ? cursoDivision : null,
                  musicaElegida: musicaElegida.isNotEmpty ? musicaElegida : null,
                  numeroMesa: numeroMesa.isNotEmpty ? numeroMesa : null,
                );

                if (context.mounted) Navigator.pop(context, true);

                // Aplicar el cambio instantáneamente en la UI
                final idx = _alumnos.indexWhere((a) => a.id == alumno.id);
                if (idx != -1 && mounted) {
                  setState(() => _alumnos[idx] = alumnoEditado);
                }
              },
              child: const Text('GUARDAR CAMBIOS'),
            ),
          ],
        ),
      ),
    );

    // Refresh en segundo plano para sincronizar con la DB
    if (mounted && result == true) _refreshAlumnos();
  }

  Future<void> _mostrarModalPagoAlumno(ContratoAlumno alumno) async {
    if (alumno.saldoDeudor <= 0) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este alumno no tiene saldo pendiente.'), backgroundColor: Colors.green));
        }
        return;
    }

    final int tCuotas = alumno.totalCuotas ?? 9;
    final int cPagadas = alumno.cuotasPagadas ?? 0;
    final int mCuotas = alumno.mesaExtraCuotas ?? 1;
    final int mPagadas = alumno.mesaExtraCuotasPagadas ?? 0;
    final int sCuotas = alumno.sillasExtraCuotas ?? 1;
    final int sPagadas = alumno.sillasExtraCuotasPagadas ?? 0;

    final double deudaMesaTotal = (alumno.mesaExtraPrecio - (alumno.mesaExtraPagado ?? 0)).clamp(0.0, double.infinity);
    final double deudaSillasTotal = (alumno.sillasExtraPrecioTotal - (alumno.sillasExtraPagado ?? 0)).clamp(0.0, double.infinity);
    final double totalBase = (alumno.montoTotalPactado - alumno.mesaExtraPrecio - alumno.sillasExtraPrecioTotal);
    final double cuotaPura = tCuotas > 0 ? (totalBase / tCuotas) : totalBase;
    
    final double deudaBaseTotal = (alumno.saldoDeudor - deudaMesaTotal - deudaSillasTotal).clamp(0.0, double.infinity);

    final montoPagarCtrl = TextEditingController();
    final porcentajeDescuentoCtrl = TextEditingController();
    
    bool pagarBase = false;
    bool pagarMesa = false;
    bool pagarSillas = false;
    Map<String, double> montosManuales = {}; 
    List<Map<String, dynamic>> previewConceptos = [];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          
          String getConceptoDetallado(String raw, int cuotaOffset) {
            if (raw == 'Cuota Base' || raw.contains('CUOTA BASE')) {
              final num = cPagadas + cuotaOffset;
              return 'Cuota Base ($num/$tCuotas)';
            }
            if (raw == 'Mesa Extra' || raw.contains('MESA EXTRA')) {
              if (mCuotas <= 1) return 'Mesa Extra - Entrega';
              final num = mPagadas + cuotaOffset;
              return 'Mesa Extra ($num/$mCuotas)';
            }
            if (raw == 'Sillas Extras' || raw.contains('SILLAS EXTRAS')) {
              if (sCuotas <= 1) return 'Sillas Extras - Entrega';
              final num = sPagadas + cuotaOffset;
              return 'Sillas Extras ($num/$sCuotas)';
            }
            return raw;
          }

          Map<String, dynamic> calcularDesgloseInteligente(String conceptoKey, String label, double gross, double net, double qPura) {
              int cuotasCompletas = 0;
              int cant = 0;
              String conceptoFinal = label;

              if (qPura > 0) {
                  cuotasCompletas = (gross / qPura).floor();
                  double resto = gross - (cuotasCompletas * qPura);
                  bool esExacto = resto.abs() < 0.1;

                  if (cuotasCompletas > 1 && esExacto) {
                    conceptoFinal = '$cuotasCompletas Cuotas (${label})';
                    cant = cuotasCompletas;
                  } else if (cuotasCompletas >= 1 && !esExacto) {
                    int proxCuota = (conceptoKey == 'Base') ? (cPagadas + cuotasCompletas + 1) : 0;
                    if (conceptoKey == 'Base') {
                       conceptoFinal = '$cuotasCompletas Cuotas + Adelanto (C$proxCuota)';
                    } else {
                       conceptoFinal = '$cuotasCompletas Enteras + Adelanto';
                    }
                    cant = cuotasCompletas; 
                  } else if (cuotasCompletas == 1 && esExacto) {
                    conceptoFinal = getConceptoDetallado(label, 1);
                    cant = 1;
                  } else {
                    conceptoFinal = 'Abono a ${getConceptoDetallado(label, 1)}';
                    cant = 0;
                  }
              } else {
                conceptoFinal = getConceptoDetallado(label, 1);
              }

              return {
                'concepto': conceptoFinal,
                'monto': double.parse(net.toStringAsFixed(2)),
                'gross': double.parse(gross.toStringAsFixed(2)),
                'cuotas': cant
              };
          }

          Future<double?> preguntarMontoParcial(String titulo, double deudaMax) async {
            final ctrl = TextEditingController();
            return showDialog<double>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Entrega Parcial: $titulo', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Deuda pendiente: ${deudaMax.toCurrency()}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Monto a entregar',
                        prefixText: r'$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
                  ElevatedButton(
                    onPressed: () {
                      final val = CurrencyInputFormatter.parse(ctrl.text);
                      if (val > 0 && (val <= (deudaMax + 0.01) || deudaMax == 0)) {
                        Navigator.pop(ctx, val);
                      } else {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Monto inválido')));
                      }
                    },
                    child: const Text('ACEPTAR'),
                  ),
                ],
              ),
            );
          }

          void recalcularDesdeMonto(double monto, {bool manually = false}) {
              previewConceptos.clear();
              if (!manually) montosManuales.clear(); 
              
              final double dtoPerc = double.tryParse(porcentajeDescuentoCtrl.text) ?? 0.0;

              if (manually && montosManuales.isNotEmpty) {
                montosManuales.forEach((key, gross) {
                  final double net = CalculadoraFinanciera.brutoANeto(gross, dtoPerc);
                  double qPura = 0;
                  String label = key;

                  if (key == 'Base') {
                    qPura = cuotaPura;
                    label = 'Cuota Base';
                  } else if (key == 'Mesa') {
                    qPura = alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1);
                    label = 'Mesa Extra';
                  } else if (key == 'Sillas') {
                    qPura = alumno.sillasExtraPrecioTotal / (sCuotas > 0 ? sCuotas : 1);
                    label = 'Sillas Extras';
                  }

                  final desglose = calcularDesgloseInteligente(key, label, gross, net, qPura);
                  previewConceptos.add(desglose);
                });
              }

              pagarSillas = previewConceptos.any((c) => c['concepto'].toString().contains('Sillas'));
              pagarMesa = previewConceptos.any((c) => c['concepto'].toString().contains('Mesa'));
              pagarBase = previewConceptos.any((c) => c['concepto'].toString().contains('Cuota'));
          }

          void recalcularDesdeChecks() {
              previewConceptos.clear();
              double totalAcumuladoNeto = 0;
              final double dtoPerc = double.tryParse(porcentajeDescuentoCtrl.text) ?? 0.0;

              void procesarConcepto(String key, String label, double deudaTotal, double qPura) {
                double gross = montosManuales[key] ?? deudaTotal;
                double net = CalculadoraFinanciera.brutoANeto(gross, dtoPerc);
                
                final desglose = calcularDesgloseInteligente(key, label, gross, net, qPura);
                previewConceptos.add(desglose);
                totalAcumuladoNeto += net;
              }

              if (pagarBase && deudaBaseTotal > 0.01) {
                procesarConcepto('Base', 'Cuota Base', deudaBaseTotal, cuotaPura);
              }
              if (pagarMesa && deudaMesaTotal > 0.01) {
                procesarConcepto('Mesa', 'Mesa Extra', deudaMesaTotal, alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1));
              }
              if (pagarSillas && deudaSillasTotal > 0.01) {
                procesarConcepto('Sillas', 'Sillas Extras', deudaSillasTotal, alumno.sillasExtraPrecioTotal / (sCuotas > 0 ? sCuotas : 1));
              }

              final double actualMonto = CurrencyInputFormatter.parse(montoPagarCtrl.text);
              if ((actualMonto - totalAcumuladoNeto).abs() > 0.01) {
                montoPagarCtrl.text = totalAcumuladoNeto > 0 ? totalAcumuladoNeto.toFormattedNumber() : '';
              }
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.payments_outlined, color: Color(0xFFD4AF37)),
                const SizedBox(width: 12),
                Expanded(child: Text('Cobro: ${alumno.nombreAlumno}', style: const TextStyle(fontSize: 16))),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Container(
                       padding: const EdgeInsets.all(16),
                       decoration: BoxDecoration(
                         gradient: LinearGradient(colors: [Colors.blue.withValues(alpha: 0.1), Colors.blue.withValues(alpha: 0.02)]),
                         borderRadius: BorderRadius.circular(16),
                         border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
                       ),
                       child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    const Text('SALDO GLOBAL PENDIENTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blue, letterSpacing: 1)),
                                    Text(alumno.saldoDeudor.toCurrency(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24)),
                                ]
                            ),
                            const Icon(Icons.account_balance_wallet_rounded, color: Colors.blue, size: 32),
                          ],
                       ),
                     ),
                     const SizedBox(height: 18),
                     _buildConceptoTile(
                         titulo: 'CUOTA BASE (Mensualidad)',
                         deuda: deudaBaseTotal,
                         isDark: Theme.of(context).brightness == Brightness.dark,
                         selected: pagarBase,
                         montoManual: montosManuales['Base'],
                         onChanged: (v) async {
                             if (v == true) {
                                 int restantes = tCuotas - cPagadas;
                                 final choice = await _mostrarOpcionesPago(
                                   context, 
                                   'Cuota Base', 
                                   deudaBaseTotal, 
                                   cuotaUnica: cuotaPura, 
                                   cuotasRestantes: restantes
                                 );
                                 if (choice == 'TOTAL') {
                                     setModalState(() {
                                         pagarBase = true;
                                         montosManuales['Base'] = deudaBaseTotal;
                                     });
                                 } else if (choice == 'UNICA') {
                                     setModalState(() {
                                         pagarBase = true;
                                         montosManuales['Base'] = cuotaPura;
                                     });
                                 } else if (choice == 'VARIAS') {
                                     final n = await _mostrarDialogoSeleccionCuotas(context, 'Cuota Base', restantes);
                                     if (n != null) {
                                       setModalState(() {
                                           pagarBase = true;
                                           montosManuales['Base'] = cuotaPura * n;
                                       });
                                     }
                                 } else if (choice == 'PARTE') {
                                     final m = await preguntarMontoParcial('Cuota Base', deudaBaseTotal);
                                     if (m != null) {
                                         setModalState(() {
                                             pagarBase = true;
                                             montosManuales['Base'] = m;
                                         });
                                     }
                                 }
                             } else {
                                 setModalState(() {
                                     pagarBase = false;
                                     montosManuales['Base'] = deudaBaseTotal;
                                 });
                             }
                             recalcularDesdeChecks();
                         }
                     ),
                     if (deudaMesaTotal > 0.01)
                     _buildConceptoTile(
                         titulo: 'MESA EXTRA',
                         deuda: deudaMesaTotal,
                         isDark: Theme.of(context).brightness == Brightness.dark,
                         selected: pagarMesa,
                         montoManual: montosManuales['Mesa'],
                         onChanged: (v) async {
                             if (v == true) {
                                 double pureMesa = alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1);
                                 int restMesa = mCuotas - mPagadas;
                                 final choice = await _mostrarOpcionesPago(
                                   context, 
                                   'Mesa Extra', 
                                   deudaMesaTotal,
                                   cuotaUnica: pureMesa,
                                   cuotasRestantes: restMesa,
                                 );
                                 if (choice == 'TOTAL') {
                                     setModalState(() {
                                         pagarMesa = true;
                                         montosManuales.remove('Mesa');
                                     });
                                 } else if (choice == 'UNICA') {
                                     setModalState(() {
                                         pagarMesa = true;
                                         montosManuales['Mesa'] = pureMesa;
                                     });
                                 } else if (choice == 'VARIAS') {
                                     final n = await _mostrarDialogoSeleccionCuotas(context, 'Mesa Extra', restMesa);
                                     if (n != null) {
                                       setModalState(() {
                                           pagarMesa = true;
                                           montosManuales['Mesa'] = pureMesa * n;
                                       });
                                     }
                                 } else if (choice == 'PARTE') {
                                     final m = await preguntarMontoParcial('Mesa Extra', deudaMesaTotal);
                                     if (m != null) {
                                         setModalState(() {
                                             pagarMesa = true;
                                             montosManuales['Mesa'] = m;
                                         });
                                     }
                                 }
                             } else {
                                 setModalState(() {
                                     pagarMesa = false;
                                     montosManuales.remove('Mesa');
                                 });
                             }
                             recalcularDesdeChecks();
                         }
                     ),
                     if (deudaSillasTotal > 0.01)
                     _buildConceptoTile(
                         titulo: 'SILLAS EXTRAS',
                         deuda: deudaSillasTotal,
                         isDark: Theme.of(context).brightness == Brightness.dark,
                         selected: pagarSillas,
                         montoManual: montosManuales['Sillas'],
                         onChanged: (v) async {
                             if (v == true) {
                                 double pureSilla = alumno.sillasExtraPrecioTotal / (sCuotas > 0 ? sCuotas : 1);
                                 int restSillas = sCuotas - sPagadas;
                                 
                                 final choice = await _mostrarOpcionesPago(
                                   context, 
                                   'Sillas Extras', 
                                   deudaSillasTotal,
                                   cuotaUnica: pureSilla,
                                   cuotasRestantes: restSillas,
                                 );
                                 if (choice == 'TOTAL') {
                                     setModalState(() {
                                         pagarSillas = true;
                                         montosManuales.remove('Sillas');
                                     });
                                 } else if (choice == 'UNICA') {
                                     setModalState(() {
                                         pagarSillas = true;
                                         montosManuales['Sillas'] = pureSilla;
                                     });
                                 } else if (choice == 'VARIAS') {
                                     final n = await _mostrarDialogoSeleccionCuotas(context, 'Sillas Extras', restSillas);
                                     if (n != null) {
                                       setModalState(() {
                                           pagarSillas = true;
                                           montosManuales['Sillas'] = pureSilla * n;
                                       });
                                     }
                                 } else if (choice == 'PARTE') {
                                     final m = await preguntarMontoParcial('Sillas Extras', deudaSillasTotal);
                                     if (m != null) {
                                         setModalState(() {
                                             pagarSillas = true;
                                             montosManuales['Sillas'] = m;
                                         });
                                     }
                                 }
                             } else {
                                 setModalState(() {
                                     pagarSillas = false;
                                     montosManuales.remove('Sillas');
                                 });
                             }
                             recalcularDesdeChecks();
                         }
                     ),
                     const SizedBox(height: 16),
                     const Divider(),
                     const SizedBox(height: 16),
                     Row(
                       children: [
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               const Text('MONTO DE ENTREGA:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1.2)),
                               const SizedBox(height: 8),
                               TextField(
                                  controller: montoPagarCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [CurrencyInputFormatter()],
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFD4AF37)),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.attach_money_rounded, color: Color(0xFFD4AF37)),
                                    hintText: '0,00',
                                    filled: true,
                                    fillColor: const Color(0xFFD4AF37).withValues(alpha: 0.05),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) {
                                      final m = CurrencyInputFormatter.parse(val);
                                      setModalState(() {
                                          recalcularDesdeMonto(m);
                                          pagarBase = previewConceptos.any((c) => c['concepto'].toString().contains('Cuota'));
                                          pagarMesa = previewConceptos.any((c) => c['concepto'].toString().contains('Mesa'));
                                          pagarSillas = previewConceptos.any((c) => c['concepto'].toString().contains('Sillas'));
                                      });
                                  },
                               ),
                             ],
                           ),
                         ),
                         const SizedBox(width: 16),
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               const Text('DESC. LIQUIDACIÓN:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.blue, letterSpacing: 1.2)),
                               const SizedBox(height: 8),
                               TextField(
                                  controller: porcentajeDescuentoCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.percent_rounded, color: Colors.blue),
                                    hintText: '0',
                                    filled: true,
                                    fillColor: Colors.blue.withValues(alpha: 0.05),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) {
                                      setModalState(() {
                                          recalcularDesdeChecks();
                                      });
                                  },
                               ),
                             ],
                           ),
                         ),
                       ],
                     ),
                     if (montoPagarCtrl.text.isNotEmpty && CurrencyInputFormatter.parse(montoPagarCtrl.text) > 0.01)
                     Container(
                         margin: const EdgeInsets.only(top: 16),
                         padding: const EdgeInsets.all(16),
                         width: double.infinity,
                         decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.05))),
                         child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('DESGLOSE LIMPIO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Colors.grey, letterSpacing: 1)),
                                      TextButton.icon(
                                        onPressed: () async {
                                          final total = CurrencyInputFormatter.parse(montoPagarCtrl.text);
                                          final result = await _mostrarDialogoDistribucionManual(
                                            context: context,
                                            total: total,
                                            deudaBase: deudaBaseTotal,
                                            deudaMesa: deudaMesaTotal,
                                            deudaSillas: deudaSillasTotal,
                                            currentBase: montosManuales['Base'],
                                            currentMesa: montosManuales['Mesa'],
                                            currentSillas: montosManuales['Sillas'],
                                          );
                                          if (result != null) {
                                            setModalState(() {
                                              if (result['Base']! > 0) montosManuales['Base'] = result['Base']!; else montosManuales['Base'] = deudaBaseTotal;
                                              if (result['Mesa']! > 0) montosManuales['Mesa'] = result['Mesa']!; else montosManuales.remove('Mesa');
                                              if (result['Sillas']! > 0) montosManuales['Sillas'] = result['Sillas']!; else montosManuales.remove('Sillas');
                                              recalcularDesdeMonto(total, manually: true);
                                            });
                                          }
                                        },
                                        icon: const Icon(Icons.edit_note_rounded, size: 14),
                                        label: const Text('EDITAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor: const Color(0xFFD4AF37),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ...previewConceptos.map((c) => Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                              Expanded(child: Text('• ${c['concepto']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                              Text((c['monto'] as num).toDouble().toCurrency(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.green)),
                                          ],
                                      ),
                                  )),
                                  (() {
                                    final double sum = previewConceptos.fold(0, (s, c) => s + (c['monto'] as num).toDouble());
                                    final double totalTotal = CurrencyInputFormatter.parse(montoPagarCtrl.text);
                                    final double diff = totalTotal - sum;
                                    if (diff.abs() > 0.01) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('REMANENTE:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.redAccent)),
                                            Text(diff.toCurrency(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.redAccent)),
                                          ],
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  })(),
                             ],
                         ),
                     ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline_rounded),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final montoIngresado = CurrencyInputFormatter.parse(montoPagarCtrl.text);
                  if (montoIngresado <= 0) return;
                  if (montoIngresado > (alumno.saldoDeudor + 0.01)) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('ERROR: El monto excede el saldo pendiente (${alumno.saldoDeudor.toCurrency()}).'),
                        backgroundColor: Colors.redAccent,
                      ));
                      return;
                  }
                  
                  if (previewConceptos.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Seleccioná al menos un concepto de pago.'),
                      backgroundColor: Colors.orangeAccent,
                    ));
                    return;
                  }

                  // 1. CALCULOS MATEMÁTICOS EXACTOS Y BLINDADOS
                  int nuevasBase = 0;
                  int nuevasMesa = 0;
                  int nuevasSillas = 0;
                  double totalDeducidoBruto = 0.0;

                  double grossMesaPagado = 0.0;
                  double grossSillasPagado = 0.0;

                  for (var conc in previewConceptos) {
                      final String cTexto = conc['concepto'] as String;
                      final int cCuotas = ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);
                      final double cGross = (conc['gross'] as num).toDouble();
                      if (cTexto.toUpperCase().contains('BASE')) nuevasBase += cCuotas;
                      if (cTexto.toUpperCase().contains('MESA')) { nuevasMesa += cCuotas; grossMesaPagado += cGross; }
                      if (cTexto.toUpperCase().contains('SILLA')) { nuevasSillas += cCuotas; grossSillasPagado += cGross; }
                      
                      totalDeducidoBruto += cGross;
                  }

                  double saldoRestanteCalculado = alumno.saldoDeudor - totalDeducidoBruto;
                  double saldoRestante = double.parse(saldoRestanteCalculado.toStringAsFixed(2)).clamp(0.0, double.infinity);
                  
                  int currentBasePagadas = (cPagadas + nuevasBase).clamp(0, tCuotas);
                  int currentMesaPagadas = (mPagadas + nuevasMesa).clamp(0, mCuotas > 0 ? mCuotas : 1);
                  int currentSillasPagadas = (sPagadas + nuevasSillas).clamp(0, sCuotas > 0 ? sCuotas : 1);

                  if (saldoRestante <= 0.01) {
                      currentBasePagadas = tCuotas;
                      currentMesaPagadas = (alumno.mesaExtraPrecio > 0 && mCuotas > 0) ? mCuotas : 0;
                      currentSillasPagadas = (alumno.sillasExtraPrecioTotal > 0 && sCuotas > 0) ? sCuotas : 0;
                  }

                  List<Map<String, dynamic>> conceptosFinales = [];
                  int contadorBaseFinal = 0;
                  int contadorMesaFinal = 0;
                  int contadorSillasFinal = 0;
                  for (var conc in previewConceptos) {
                      final String cTexto = conc['concepto'] as String;
                      final double cMontoRaw = (conc['monto'] as num).toDouble();
                      final double cMonto = double.parse(cMontoRaw.toStringAsFixed(2));
                      final int cCuotasConc = ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);
                      
                      String cRico = cTexto;
                      if (cTexto.toUpperCase().contains('MESA')) {
                          if (mCuotas <= 1) {
                              cRico = 'Mesa Extra - Entrega';
                          } else if (cCuotasConc == 1) {
                              cRico = 'Mesa Extra (${mPagadas + contadorMesaFinal + 1}/$mCuotas)';
                          } else if (cCuotasConc > 1) {
                              cRico = '$cCuotasConc Cuotas Mesa Extra (${mPagadas + contadorMesaFinal + 1}-${mPagadas + contadorMesaFinal + cCuotasConc}/$mCuotas)';
                          } else {
                              cRico = 'Abono Mesa Extra (${mPagadas + contadorMesaFinal + 1}/$mCuotas)';
                          }
                          contadorMesaFinal += cCuotasConc;
                      } else if (cTexto.toUpperCase().contains('SILLA')) {
                          if (sCuotas <= 1) {
                              cRico = 'Sillas Extras - Entrega';
                          } else if (cCuotasConc == 1) {
                              cRico = 'Sillas Extras (${sPagadas + contadorSillasFinal + 1}/$sCuotas)';
                          } else if (cCuotasConc > 1) {
                              cRico = '$cCuotasConc Cuotas Sillas Extras (${sPagadas + contadorSillasFinal + 1}-${sPagadas + contadorSillasFinal + cCuotasConc}/$sCuotas)';
                          } else {
                              cRico = 'Abono Sillas Extras (${sPagadas + contadorSillasFinal + 1}/$sCuotas)';
                          }
                          contadorSillasFinal += cCuotasConc;
                      } else if (cTexto.toUpperCase().contains('BASE')) {
                          if (cCuotasConc == 1) {
                              cRico = 'Cuota Base (${cPagadas + contadorBaseFinal + 1}/$tCuotas)';
                          } else if (cCuotasConc > 1) {
                              cRico = '$cCuotasConc Cuotas Base (${cPagadas + contadorBaseFinal + 1}-${cPagadas + contadorBaseFinal + cCuotasConc}/$tCuotas)';
                          } else {
                              cRico = 'Abono Cuota Base (${cPagadas + contadorBaseFinal + 1}/$tCuotas)';
                          }
                          contadorBaseFinal += cCuotasConc;
                      }

                      conceptosFinales.add({'concepto': cRico, 'monto': cMonto});
                  }

                  // 2. CREACIÓN DEL CLON LOCAL INMEDIATO (copyWith directo)
                  final alumnoFresco = alumno.copyWith(
                      saldoDeudor: saldoRestante,
                      cuotasPagadas: currentBasePagadas,
                      mesaExtraCuotasPagadas: currentMesaPagadas,
                      sillasExtraCuotasPagadas: currentSillasPagadas,
                      mesaExtraPagado: (alumno.mesaExtraPagado) + grossMesaPagado,
                      sillasExtraPagado: (alumno.sillasExtraPagado) + grossSillasPagado,
                  );

                  // Actualizamos la pantalla de fondo al instante (sin esperar a Supabase)
                  final index = _alumnos.indexWhere((a) => a.id == alumno.id);
                  if (index != -1) {
                      setState(() {
                          _alumnos[index] = alumnoFresco;
                      });
                  }

                  // Cerramos la ventana de cobro y disparamos el recibo PDF con el CLON PERFECTO
                  if (context.mounted) {
                    Navigator.pop(context, true); 
                    
                    _imprimirReciboAlumno(
                      alumnoFresco, 
                      montoPagado: montoIngresado,
                      saldoPendiente: saldoRestante, 
                      conceptosPagados: conceptosFinales,
                      fechaManual: DateTime.now(),
                      skipDbRefresh: true, // EXIGE que se use el clon local, ignorando los tiempos de Supabase
                    );
                  }

                  // 3. SINCRONIZACIÓN DE LA BASE DE DATOS EN SEGUNDO PLANO (SILENCIOSA)
                  Future.microtask(() async {
                      try {
                          final repo = ref.read(contratosRepositoryProvider);
                          for (var conc in previewConceptos) {
                              final String cTexto = conc['concepto'] as String;
                              
                              final double cMontoRaw = (conc['monto'] as num).toDouble();
                              final double cMonto = double.parse(cMontoRaw.toStringAsFixed(2));
                              
                              final double? grossRaw = conc['gross'] as double?;
                              final double? cGross = grossRaw != null ? double.parse(grossRaw.toStringAsFixed(2)) : null;

                              final int cCuotas = ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);

                              await repo.registrarPago(
                                contratoId: alumno.id, 
                                monto: cMonto, 
                                concepto: cTexto,
                                montoADescontarDeSaldo: cGross, 
                                descuentoPorcentaje: double.tryParse(porcentajeDescuentoCtrl.text) ?? 0,
                                cuotasLiquidadas: cCuotas,
                              );
                          }
                          
                          final Map<String, dynamic> directUpdates = {
                              'saldo_deudor': saldoRestante,
                          };
                          
                          if (saldoRestante <= 0.01) {
                              directUpdates['cuotas_pagadas'] = currentBasePagadas;
                              directUpdates['mesa_extra_cuotas_pagadas'] = currentMesaPagadas;
                              directUpdates['sillas_extra_cuotas_pagadas'] = currentSillasPagadas;
                          } else {
                              if (nuevasBase > 0) directUpdates['cuotas_pagadas'] = currentBasePagadas;
                              if (nuevasMesa > 0) directUpdates['mesa_extra_cuotas_pagadas'] = currentMesaPagadas;
                              if (nuevasSillas > 0) directUpdates['sillas_extra_cuotas_pagadas'] = currentSillasPagadas;
                          }
                          
                          await repo.actualizarContrato(alumno.id, directUpdates);

                          // Escaneo final automático sin interrumpir al usuario
                          await _forzarAuditoriaInteligente(silencioso: true);
                      } catch (e) {
                          debugPrint('Registro asíncrono demorado: $e'); 
                      }
                  });
                },
                label: const Text('CONFIRMAR PAGO', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          );
        },
      ),
    );

    if (mounted && result == true) {
      _refreshAlumnos();
    }
  }

  Future<void> _mostrarHistorialPagosAlumno(ContratoAlumno alumno) async {
    final repo = ref.read(contratosRepositoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.getHistorialPagosAlumno(alumno.id),
        builder: (context, snapshot) {
          final pagos = snapshot.data ?? [];
          final bool cargando = snapshot.connectionState == ConnectionState.waiting;
          final double totalEntregado = pagos.fold(0, (sum, p) => sum + (p['monto'] as num).toDouble());

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
            ),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFD4AF37)),
                      const SizedBox(width: 12),
                      const Text(
                        'ESTADO DE CUENTA',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alumno.nombreAlumno.toUpperCase(),
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: cargando 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                : Column(
                    children: [
                      Expanded(
                        child: pagos.isEmpty 
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.history_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                                  const SizedBox(height: 12),
                                  const Text('No hay pagos registrados aún.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                                ],
                              ),
                            )
                          : (() {
                              final cronologico = pagos.reversed.toList();
                              final Map<String, int> contadores = {};
                              final List<Map<String, dynamic>> pagosConDetalle = [];

                              final int tCuotas = alumno.totalCuotas ?? 9;
                              final int mCuotas = alumno.mesaExtraCuotas ?? 1;

                              for (var p in cronologico) {
                                final conceptoOriginal = p['concepto'] as String? ?? 'Cuota Base';
                                String conceptoMejorado = conceptoOriginal;

                                if (conceptoOriginal.startsWith('Cuota Base')) {
                                  contadores['Cuota Base'] = (contadores['Cuota Base'] ?? 0) + 1;
                                  conceptoMejorado = 'Cuota Base (${contadores['Cuota Base']}/$tCuotas)';
                                } else if (conceptoOriginal.startsWith('Mesa Extra')) {
                                  contadores['Mesa Extra'] = (contadores['Mesa Extra'] ?? 0) + 1;
                                  if (mCuotas <= 1) {
                                    conceptoMejorado = 'Mesa Extra - Entrega';
                                  } else {
                                    conceptoMejorado = 'Mesa Extra (${contadores['Mesa Extra']}/$mCuotas)';
                                  }
                                } else if (conceptoOriginal.startsWith('Sillas Extras')) {
                                  conceptoMejorado = 'Sillas Extras - Entrega';
                                }

                                final pCpy = Map<String, dynamic>.from(p);
                                pCpy['concepto_detallado'] = conceptoMejorado;
                                if ((p['descuento_porcentaje'] as num? ?? 0) > 0.01) {
                                  pCpy['label_descuento'] = '${(p['descuento_porcentaje'] as num).toStringAsFixed(0)}% OFF';
                                }
                                pagosConDetalle.add(pCpy);
                              }
                              
                              final listaFinal = pagosConDetalle.reversed.toList();

                              return ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: listaFinal.length,
                                itemBuilder: (context, index) {
                                  final p = listaFinal[index];
                                  final fecha = DateTime.parse(p['fecha_pago']);
                                  final monto = double.parse((p['monto'] as num).toDouble().toStringAsFixed(2));
                                  final concepto = p['concepto_detallado'] as String;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.check_rounded, color: Colors.green, size: 16),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    concepto,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                  if (p['label_descuento'] != null) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        p['label_descuento'],
                                                        style: const TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              Text(
                                                '${fecha.day}/${fecha.month}/${fecha.year} - ${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')} hs',
                                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              monto.toCurrency(),
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.green),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                final fechaOrig = DateTime.tryParse(p['fecha_pago'] ?? '') ?? DateTime.now();
                                                _imprimirReciboAlumno(
                                                  alumno,
                                                  montoPagado: monto,
                                                  saldoPendiente: alumno.saldoDeudor,
                                                  conceptosPagados: <Map<String, dynamic>>[{'concepto': concepto, 'monto': monto}],
                                                  fechaManual: fechaOrig,
                                                  skipDbRefresh: false, 
                                                );
                                              },
                                              child: const Padding(
                                                padding: EdgeInsets.only(top: 4),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.print_rounded, size: 10, color: Colors.blueAccent),
                                                    SizedBox(width: 4),
                                                    Text('REIMPRIMIR', style: TextStyle(fontSize: 9, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            })()),
                      const Divider(height: 32),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL ENTREGADO:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                            Text(
                              totalEntregado.toCurrency(),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFFD4AF37)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CERRAR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _imprimirReciboAlumno(
      ContratoAlumno alumno, {
      double? montoPagado, 
      double? saldoPendiente, 
      String? conceptoCuotas, 
      List<Map<String, dynamic>>? conceptosPagados, 
      DateTime? fechaManual,
      bool skipDbRefresh = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Generando Recibo...'), duration: Duration(seconds: 2)),
    );

    double valPago = montoPagado ?? 0;
    double valSaldo = saldoPendiente ?? alumno.saldoDeudor;
    String? valConcepto = conceptoCuotas;
    ContratoAlumno alumnoParaPdf = alumno;

    final int mCuotas = alumno.mesaExtraCuotas ?? 1;

    try {
      final repo = ref.read(contratosRepositoryProvider);

      if (conceptosPagados == null || conceptosPagados.isEmpty) {
        final lote = await repo.getUltimosPagosLote(alumno.id);

        if (lote.isNotEmpty) {
          conceptosPagados = lote.map<Map<String, dynamic>>((p) {
            String raw = (p['concepto'] as String?) ?? 'Pago';
            if (raw.toUpperCase().contains('MESA')) {
              raw = mCuotas <= 1 ? 'Mesa Extra - Entrega' : 'Mesa Extra (Abono)';
            } else if (raw.toUpperCase().contains('SILLA')) {
              raw = 'Sillas Extras - Entrega';
            } else if (raw.toUpperCase().contains('BASE')) {
              raw = 'Cuota Base';
            }
            return <String, dynamic>{
              'concepto': raw,
              'monto': double.parse((p['monto'] as num).toDouble().toStringAsFixed(2)),
            };
          }).toList();

          valPago = conceptosPagados.fold<double>(0, (sum, c) => sum + ((c['monto'] as num?)?.toDouble() ?? 0.0));
        } else {
          valPago = 0;
        }
      }

      if (!skipDbRefresh) {
          final alumnosFrescos = await repo.getByEvento(alumno.eventoId);
          final fresco = alumnosFrescos.cast<ContratoAlumno?>().firstWhere((a) => a!.id == alumno.id, orElse: () => null);
          if (fresco != null) {
              if (saldoPendiente == null) valSaldo = fresco.saldoDeudor;
              alumnoParaPdf = fresco;
          }
      }

      await PdfService.generarReciboAlumno(
        alumno: alumnoParaPdf,
        evento: widget.evento,
        montoPagado: valPago,
        saldoPendiente: double.parse(valSaldo.toStringAsFixed(2)),
        conceptoCuotas: valConcepto,
        conceptosPagados: conceptosPagados,
        fechaManual: fechaManual,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error al generar PDF: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<Map<String, double>?> _mostrarDialogoDistribucionManual({
    required BuildContext context,
    required double total,
    required double deudaBase,
    required double deudaMesa,
    required double deudaSillas,
    double? currentBase,
    double? currentMesa,
    double? currentSillas,
  }) {
    final baseCtrl = TextEditingController(text: currentBase?.toFormattedNumber() ?? '');
    final mesaCtrl = TextEditingController(text: currentMesa?.toFormattedNumber() ?? '');
    final sillasCtrl = TextEditingController(text: currentSillas?.toFormattedNumber() ?? '');

    return showDialog<Map<String, double>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInternalState) {
          double getSum() => CurrencyInputFormatter.parse(baseCtrl.text) +
                             CurrencyInputFormatter.parse(mesaCtrl.text) +
                             CurrencyInputFormatter.parse(sillasCtrl.text);
          
          final double currentSum = getSum();
          final double diff = total - currentSum;
          final bool isValid = diff.abs() < 0.01;

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('REPARTO MANUAL DE PAGO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Total a distribuir: ${total.toCurrency()}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            double rem = total;
                            double b = rem >= deudaBase ? deudaBase : rem;
                            rem -= b;
                            double m = rem >= deudaMesa ? deudaMesa : rem;
                            rem -= m;
                            double s = rem >= deudaSillas ? deudaSillas : rem;
                            
                            setInternalState(() {
                              baseCtrl.text = b > 0 ? b.toFormattedNumber() : '';
                              mesaCtrl.text = m > 0 ? m.toFormattedNumber() : '';
                              sillasCtrl.text = s > 0 ? s.toFormattedNumber() : '';
                            });
                          },
                          icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                          label: const Text('AUTO-COMPLETAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    _buildManualField(label: 'CUOTA BASE (Máx: ${deudaBase.toCurrency()})', ctrl: baseCtrl, onCh: (_) => setInternalState((){})),
                    const SizedBox(height: 12),
                    _buildManualField(label: 'MESA EXTRA (Máx: ${deudaMesa.toCurrency()})', ctrl: mesaCtrl, onCh: (_) => setInternalState((){})),
                    const SizedBox(height: 12),
                    _buildManualField(label: 'SILLAS EXTRAS (Máx: ${deudaSillas.toCurrency()})', ctrl: sillasCtrl, onCh: (_) => setInternalState((){})),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('REMANENTE:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          diff.toCurrency(),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: isValid ? Colors.green : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isValid ? Colors.green : Colors.grey,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(ctx, {
                    'Base': CurrencyInputFormatter.parse(baseCtrl.text),
                    'Mesa': CurrencyInputFormatter.parse(mesaCtrl.text),
                    'Sillas': CurrencyInputFormatter.parse(sillasCtrl.text),
                  });
                },
                child: const Text('CONFIRMAR REPARTO'),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildManualField({required String label, required TextEditingController ctrl, required Function(String) onCh}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [CurrencyInputFormatter()],
      onChanged: onCh,
      decoration: InputDecoration(
        labelText: label,
        prefixText: r'$ ',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Future<int?> _mostrarDialogoSeleccionCuotas(BuildContext context, String titulo, int max) {
    int seleccion = 1;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInternalState) => AlertDialog(
          title: Text('Seleccionar Cuotas: $titulo', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Cuántas cuotas desea liquidar?', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: seleccion > 1 ? () => setInternalState(() => seleccion--) : null,
                    icon: const Icon(Icons.remove),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$seleccion',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37)),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: seleccion < max ? () => setInternalState(() => seleccion++) : null,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Máximo disponible: $max cuotas', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, seleccion),
              child: const Text('ACEPTAR'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _mostrarOpcionesPago(BuildContext context, String titulo, double deuda, {double? cuotaUnica, int? cuotasRestantes}) {
      final tieneCuotas = (cuotasRestantes ?? 0) > 1;

      return showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                  const Text('TIPO DE PAGO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    _buildOpcionPagoItem(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'LIQUIDAR EL TOTAL',
                      sub: deuda.toCurrency(),
                      color: Colors.green,
                      onTap: () => Navigator.pop(ctx, 'TOTAL'),
                    ),
                    if (tieneCuotas && cuotaUnica != null) ...[
                        const SizedBox(height: 8),
                        _buildOpcionPagoItem(
                            icon: Icons.one_x_mobiledata_rounded,
                            label: 'LIQUIDAR SOLO 1 CUOTA',
                            sub: cuotaUnica.toCurrency(),
                            color: const Color(0xFFD4AF37),
                            onTap: () => Navigator.pop(ctx, 'UNICA'),
                        ),
                        const SizedBox(height: 8),
                        _buildOpcionPagoItem(
                            icon: Icons.calendar_month_rounded,
                            label: 'ELEGIR CANTIDAD DE CUOTAS',
                            sub: 'Hasta $cuotasRestantes cuotas',
                            color: Colors.blueAccent,
                            onTap: () => Navigator.pop(ctx, 'VARIAS'),
                        ),
                    ],
                    const SizedBox(height: 8),
                    _buildOpcionPagoItem(
                      icon: Icons.edit_note_rounded,
                      label: 'ENTREGA PARCIAL',
                      sub: 'Monto a elección',
                      color: Colors.white60,
                      onTap: () => Navigator.pop(ctx, 'PARTE'),
                    ),
                ],
              ),
              actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                  ),
              ],
          )
      );
  }

  Widget _buildOpcionPagoItem({required IconData icon, required String label, required String sub, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.05),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  Text(sub, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildConceptoTile({
      required String titulo, 
      required double deuda, 
      required bool isDark, 
      required bool selected, 
      required Function(bool?) onChanged,
      double? montoManual
  }) {
      if (deuda <= 0.01) return const SizedBox.shrink();
      
      final bool esParcial = montoManual != null;

      return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              color: selected ? const Color(0xFFD4AF37).withValues(alpha: 0.1) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? const Color(0xFFD4AF37).withValues(alpha: 0.3) : Colors.transparent),
          ),
          child: CheckboxListTile(
              value: selected,
              onChanged: onChanged,
              activeColor: const Color(0xFFD4AF37),
              title: Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text('Deuda: ${deuda.toCurrency()}', style: TextStyle(fontSize: 11, color: selected ? const Color(0xFFD4AF37) : Colors.grey)),
                if (esParcial)
                  Text('ENTREGA: ${montoManual.toCurrency()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.green)),
                ],
              ),
              secondary: Icon(
                  titulo.contains('BASE') ? Icons.calendar_month_rounded : (titulo.contains('MESA') ? Icons.table_bar_rounded : Icons.chair_rounded),
                  color: selected ? const Color(0xFFD4AF37) : Colors.grey.shade600,
                  size: 20,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
      );
  }
}