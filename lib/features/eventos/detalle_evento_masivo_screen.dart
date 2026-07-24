import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/widgets/admin_gate.dart';
import '../common/providers/admin_provider.dart';
import '../caja_sesiones/providers/app_role_provider.dart';
import '../caja_sesiones/services/caja_auto_sync_service.dart';
import '../../core/config/app_config.dart';

import '../../models/evento.dart';
import '../../models/contrato_alumno.dart';
import '../../models/nota_operativa_contrato.dart';
import '../common/services/pdf_service.dart';
import 'repositories/notas_operativas_contrato_repository.dart';
import '../common/utils/currency_extensions.dart';
import '../common/utils/currency_input_formatter.dart';
import 'repositories/eventos_repository.dart';
import 'repositories/contratos_repository.dart';
import '../../core/utils/ar_time.dart';
import '../../core/utils/pago_interes_mora.dart';
import 'services/calculadora_financiera.dart';
import 'services/cronograma_cuotas_utils.dart';
import 'services/mora_cuota_calculator.dart';
import 'services/mora_concepto_rotulo.dart';
import 'services/mora_tracked_origen.dart';
import 'services/cobro_abono_acumulado.dart';
import 'services/concepto_pago_display.dart';
import 'services/cobro_masivo_conceptos_pdf.dart';
import 'services/mesas_extra_utils.dart';
import '../../models/mesa_extra_item.dart';
import 'widgets/sorteo_mesas_dialog.dart';
import 'widgets/dialogo_seleccion_cuotas_plan.dart';
import 'widgets/contratos_firmados_bulk_dialog.dart';
import 'widgets/modal_alumno_premium.dart';
import 'widgets/nota_operativa_bottom_sheet.dart';
import '../mi_empresa/providers/finanzas_provider.dart';

/// Evita dispose de controllers mientras el route del diálogo aún se desmonta.
void _deferDisposeTextControllers(Iterable<TextEditingController> controllers) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in controllers) {
        c.dispose();
      }
    });
  });
}

class DetalleEventoMasivoScreen extends ConsumerStatefulWidget {
  final Evento evento;

  const DetalleEventoMasivoScreen({super.key, required this.evento});

  @override
  ConsumerState<DetalleEventoMasivoScreen> createState() =>
      _DetalleEventoMasivoScreenState();
}

class _DetalleEventoMasivoScreenState
    extends ConsumerState<DetalleEventoMasivoScreen> {
  bool _isLoading = true;
  bool _ocultarMontos = false;
  late DateTime _fechaEventoActual;
  List<ContratoAlumno> _alumnos = [];
  int _itemsRenderizados = 50;
  final ScrollController _lazyScrollController = ScrollController();

  /// Suma de pagos `interes_mora` por contrato (local) para mostrar mora pendiente.
  Map<String, double> _moraCobradaPorContrato = {};

  /// Mora cobrada solo en el período vigente (desde el último pago de cuota base).
  Map<String, double> _moraCobradaPeriodoPorContrato = {};

  /// Notas operativas locales por contrato (no sincronizan; no contables).
  Map<String, NotaOperativaContrato> _notasOperativasPorContrato = {};
  String _busquedaAlumno = '';
  String? _cursoDivisionFiltro;
  bool _ordenAlfabetico = true;
  bool _modoSeleccionContratos = false;
  final Set<String> _idsSeleccionContratos = {};
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _lazyScrollController.addListener(() {
      if (_lazyScrollController.position.pixels >=
          _lazyScrollController.position.maxScrollExtent - 200) {
        if (_itemsRenderizados < _alumnos.length) {
          setState(() {
            _itemsRenderizados += 50;
          });
        }
      }
    });
    _fechaEventoActual = widget.evento.fechaEvento;
    _cargarPreferenciaOcultarMontos();
    _fetchDatos();
    _setupRealtime();
  }

  void _setupRealtime() {
    // Local-first: no refrescar desde cambios remotos automáticos.
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
        const SnackBar(
          content: Text(
            'Ejecutando Auditoría Inteligente en la Base de Datos...',
          ),
          backgroundColor: Colors.blueAccent,
        ),
      );
      setState(() => _isLoading = true);
    }

    try {
      final repo = ref.read(contratosRepositoryProvider);

      // Ejecutar la auditoría en lote súper veloz dentro de una sola transacción
      final huboCambios = await repo.ejecutarAuditoriaInteligente(
        widget.evento.id,
      );

      final listos = await repo.getByEvento(widget.evento.id);
      final moraMap = await _cargarMoraHistorialMap(repo, listos);
      final moraPeriodoMap = await _cargarMoraPeriodoMap(repo, listos);
      if (mounted) {
        _aplicarSnapshotAlumnos(
          listos,
          moraMap,
          moraCobradaPeriodoPorContrato: moraPeriodoMap,
          isLoading: false,
        );
        if (!silencioso) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                huboCambios
                    ? '¡Auditoría completada! Saldos y cuotas corregidos e integrados.'
                    : '¡Auditoría completada! Todos los saldos y cuotas están correctos.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error en auditoria: $e');
      if (!silencioso && mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error en auditoría: $e')));
      }
    }
  }

  Future<void> _fetchDatos({bool cargaSilenciosa = false}) async {
    if (!cargaSilenciosa) setState(() => _isLoading = true);

    try {
      final repo = ref.read(contratosRepositoryProvider);

      // Carga inmediata desde base de datos local SQLite (Offline-First)
      final alumnos = await repo.getByEvento(widget.evento.id);
      final moraMap = await _cargarMoraHistorialMap(repo, alumnos);
      final moraPeriodoMap = await _cargarMoraPeriodoMap(repo, alumnos);
      if (mounted) {
        _aplicarSnapshotAlumnos(
          alumnos,
          moraMap,
          moraCobradaPeriodoPorContrato: moraPeriodoMap,
          isLoading: false,
        );
      }
      await _cargarNotasOperativas();
      unawaited(
        repo.reconciliarMesasLegacyPendientesEvento(widget.evento.id).then((n) {
          if (n > 0 && mounted) _refreshAlumnos();
        }),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
      debugPrint('Error al cargar datos en DetalleEvento: $e');
      if (mounted && !cargaSilenciosa) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, double>> _cargarMoraHistorialMap(
    ContratosRepository repo,
    List<ContratoAlumno> alumnos,
  ) => repo.sumMoraCobradaHistorialPorContratos(
    alumnos.map((e) => e.id).toList(),
  );

  Future<Map<String, double>> _cargarMoraPeriodoMap(
    ContratosRepository repo,
    List<ContratoAlumno> alumnos,
  ) => repo.sumMoraCobradaPeriodoPorContratos(alumnos);

  /// Aplica lista + mora cobrada y reconstruye la UI en un solo paso.
  void _aplicarSnapshotAlumnos(
    List<ContratoAlumno> alumnos,
    Map<String, double> moraCobradaPorContrato, {
    Map<String, double>? moraCobradaPeriodoPorContrato,
    bool? isLoading,
  }) {
    if (!mounted) return;
    setState(() {
      _alumnos = alumnos;
      _moraCobradaPorContrato = moraCobradaPorContrato;
      if (moraCobradaPeriodoPorContrato != null) {
        _moraCobradaPeriodoPorContrato = moraCobradaPeriodoPorContrato;
      }
      if (isLoading != null) _isLoading = isLoading;
    });
  }

  /// Actualización optimista de un contrato (p. ej. inmediatamente post-cobro).
  void _patchAlumnoLocal(
    String contratoId,
    ContratoAlumno actualizado, {
    double moraCobradaExtra = 0,
  }) {
    final index = _alumnos.indexWhere((a) => a.id == contratoId);
    if (index == -1 || !mounted) return;
    setState(() {
      if (moraCobradaExtra > 0.01) {
        _moraCobradaPorContrato[contratoId] =
            (_moraCobradaPorContrato[contratoId] ?? 0.0) + moraCobradaExtra;
        _moraCobradaPeriodoPorContrato[contratoId] =
            (_moraCobradaPeriodoPorContrato[contratoId] ?? 0.0) +
            moraCobradaExtra;
      }
      _alumnos[index] = actualizado;
    });
  }

  /// Refresh ligero: solo recarga la lista desde DB sin auditoría.
  Future<void> _refreshAlumnos() async {
    try {
      final repo = ref.read(contratosRepositoryProvider);
      final alumnos = await repo.getByEvento(widget.evento.id);
      final moraMap = await _cargarMoraHistorialMap(repo, alumnos);
      final moraPeriodoMap = await _cargarMoraPeriodoMap(repo, alumnos);
      if (mounted) {
        _aplicarSnapshotAlumnos(
          alumnos,
          moraMap,
          moraCobradaPeriodoPorContrato: moraPeriodoMap,
        );
      }
      await _cargarNotasOperativas();
    } catch (e) {
      debugPrint('⚠️ Error en _refreshAlumnos: $e');
    }
  }

  Future<void> _cargarNotasOperativas() async {
    if (!mounted) return;
    final ids = _alumnos.map((e) => e.id).toList();
    final repo = ref.read(notasOperativasContratoRepositoryProvider);
    final map = ids.isEmpty
        ? <String, NotaOperativaContrato>{}
        : await repo.obtenerPorContratoIds(ids);
    if (!mounted) return;
    setState(() => _notasOperativasPorContrato = map);
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
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
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

    final alumnosActivosEl = _alumnos
        .where((a) => !a.nombreAlumno.startsWith('[BAJA]'))
        .toList();
    final double saldoAlEliminar = alumnosActivosEl.fold(
      0,
      (sum, a) => sum + a.saldoDeudor,
    );
    final bool tieneDeudaAlEliminar = saldoAlEliminar > 0.01;

    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: tieneDeudaAlEliminar
                ? Colors.deepOrangeAccent
                : Colors.redAccent,
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              tieneDeudaAlEliminar
                  ? Icons.warning_amber_rounded
                  : Icons.delete_forever_rounded,
              color: tieneDeudaAlEliminar
                  ? Colors.deepOrangeAccent
                  : Colors.redAccent,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              tieneDeudaAlEliminar ? '¡SALDO PENDIENTE!' : 'ATENCIÓN TITÁN',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
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
            child: const Text(
              'CANCELAR',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tieneDeudaAlEliminar
                  ? Colors.deepOrangeAccent
                  : Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
              content: Text(
                'Evento dado de baja. Los movimientos siguen en Mi Empresa.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
        }
      }
    }
  }

  Future<void> _finalizarEvento() async {
    final hasAccess = await AdminGate.check(context, ref);
    if (!hasAccess) return;

    final alumnosActivos = _alumnos
        .where((a) => !a.nombreAlumno.startsWith('[BAJA]'))
        .toList();
    final double saldoPendiente = alumnosActivos.fold(
      0,
      (sum, a) => sum + a.saldoDeudor,
    );
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
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
            child: const Text(
              'CANCELAR',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tieneDeuda
                  ? Colors.orangeAccent
                  : Colors.greenAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error al finalizar: $e')));
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

    if (nuevaFecha != null &&
        nuevaFecha.isAtSameMomentAs(_fechaEventoActual) == false) {
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
            const SnackBar(
              content: Text('Fecha actualizada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al actualizar fecha: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(contratosMutationTickProvider, (prev, next) {
      if (prev != null && prev != next) {
        _refreshAlumnos();
      }
    });

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);
    final screenW = MediaQuery.sizeOf(context).width;
    final layoutCompactScreen = screenW < 1520;
    final modoJefe = ref.watch(adminAuthProvider).esModoJefe;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: layoutCompactScreen ? 48 : kToolbarHeight,
        title: Text(
          (widget.evento.cliente?.nombreCompleto ?? 'DETALLE MASIVO')
              .toUpperCase(),
          style: TextStyle(
            fontSize: layoutCompactScreen ? 12 : 14,
            letterSpacing: 1,
          ),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          if (!_isLoading && modoJefe) ...[
            IconButton(
              icon: const Icon(Icons.sync_rounded, color: Color(0xFFD4AF37)),
              onPressed: () => _forzarAuditoriaInteligente(silencioso: false),
              tooltip: 'Auditar y Sincronizar DB',
            ),
            IconButton(
              icon: const Icon(
                Icons.edit_calendar_outlined,
                color: Colors.blueAccent,
              ),
              onPressed: _editarFecha,
              tooltip: 'Editar Fecha',
            ),
            IconButton(
              icon: const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.greenAccent,
              ),
              onPressed: _finalizarEvento,
              tooltip: 'Finalizar Evento',
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_forever_outlined,
                color: Colors.redAccent,
              ),
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
            child: Container(color: Theme.of(context).scaffoldBackgroundColor),
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
                if (!_isLoading && modoJefe) _buildMetricsPanel(),
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
    final alumnosActivos = _alumnos
        .where((a) => !a.nombreAlumno.startsWith('[BAJA]'))
        .toList();
    final totalPactado = alumnosActivos.fold<double>(
      0,
      (sum, a) => sum + a.montoTotalPactado,
    );
    final saldoPendiente = alumnosActivos.fold<double>(
      0,
      (sum, a) => sum + a.saldoDeudor,
    );
    final recaudado = totalPactado - saldoPendiente;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenW = MediaQuery.sizeOf(context).width;
    // Misma línea que el tab alumnos: laptops 1366×768 y similares.
    final layoutCompact = screenW < 1520;

    final labelStyle = TextStyle(
      fontSize: layoutCompact ? 8.5 : 10,
      fontWeight: FontWeight.bold,
      color: Colors.grey,
    );
    final totalPactadoStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: layoutCompact ? 13 : 16,
    );
    final montoGrandeStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: layoutCompact ? 15 : 20,
    );

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: layoutCompact ? 8 : 24,
        vertical: layoutCompact ? 2 : 8,
      ),
      padding: EdgeInsets.all(layoutCompact ? 8 : 20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.blue.withValues(alpha: 0.1)
            : Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(layoutCompact ? 14 : 24),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL PACTADO', style: labelStyle),
              Row(
                children: [
                  Text(
                    _ocultarMontos ? '***' : totalPactado.toCurrency(),
                    style: totalPactadoStyle,
                  ),
                  SizedBox(width: layoutCompact ? 4 : 12),
                  IconButton(
                    visualDensity: layoutCompact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    padding: layoutCompact ? EdgeInsets.zero : null,
                    constraints: layoutCompact
                        ? const BoxConstraints(minWidth: 36, minHeight: 36)
                        : null,
                    icon: Icon(
                      _ocultarMontos ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                      size: layoutCompact ? 18 : 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _ocultarMontos = !_ocultarMontos;
                      });
                      _guardarPreferenciaOcultarMontos(_ocultarMontos);
                    },
                  ),
                ],
              ),
            ],
          ),
          Divider(height: layoutCompact ? 8 : 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RECAUDADO', style: labelStyle),
                    SizedBox(height: layoutCompact ? 2 : 4),
                    Text(
                      _ocultarMontos ? '***' : recaudado.toCurrency(),
                      style: montoGrandeStyle.copyWith(color: Colors.green),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('SALDO PENDIENTE', style: labelStyle),
                    SizedBox(height: layoutCompact ? 2 : 4),
                    Text(
                      _ocultarMontos ? '***' : saldoPendiente.toCurrency(),
                      style: montoGrandeStyle.copyWith(color: Colors.amber),
                    ),
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
    final bool modoJefe = ref.watch(adminAuthProvider).esModoJefe;
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

    final divisionesDisponibles =
        _alumnos
            .where((a) => !a.nombreAlumno.startsWith('[BAJA]'))
            .map((a) => a.cursoDivision?.trim())
            .where((v) => v != null && v.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList()
          ..sort();

    final alumnosFiltrados = _alumnos.where((a) {
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
      alumnosFiltrados.sort(
        (a, b) => a.nombreAlumno.toLowerCase().compareTo(
          b.nombreAlumno.toLowerCase(),
        ),
      );
    } else {
      alumnosFiltrados.sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        // Laptops típicas 1366×768 y similares: más aire útil para tabla y toolbar.
        final bool layoutCompact = availableWidth < 1520;
        final double horizontalPad = layoutCompact
            ? 12
            : (availableWidth > 800 ? 32 : 16);
        final double tableWidth = availableWidth - (horizontalPad * 2);

        final double innerTable =
            tableWidth - (_modoSeleccionContratos ? 52 : 0);
        final double colAlumno = innerTable * 0.18;
        final double colTelefono = innerTable * 0.10;
        final double colAcomp = innerTable * 0.12;
        final double colMesa = innerTable * 0.08;
        final double colContrato = innerTable * 0.07;
        final double colEstado = innerTable * 0.22;
        final double colAcciones = innerTable * 0.23;

        final int contratosFirmados = alumnosFiltrados
            .where(
              (a) => a.contratoFirmado && !a.nombreAlumno.startsWith('[BAJA]'),
            )
            .length;

        final double tbIcon = layoutCompact ? 15.0 : 18.0;
        final double tbIconSm = layoutCompact ? 14.0 : 16.0;
        final EdgeInsets tbPadLg = EdgeInsets.symmetric(
          horizontal: layoutCompact ? 10 : 20,
          vertical: layoutCompact ? 6 : 12,
        );
        final EdgeInsets tbPadMd = EdgeInsets.symmetric(
          horizontal: layoutCompact ? 8 : 16,
          vertical: layoutCompact ? 6 : 12,
        );
        final EdgeInsets tbPadSm = EdgeInsets.symmetric(
          horizontal: layoutCompact ? 7 : 12,
          vertical: layoutCompact ? 5 : 8,
        );
        final double tbFs = layoutCompact ? 11.0 : 12.0;
        final double tbFsSm = layoutCompact ? 10.0 : 11.0;
        final double tbRadius = layoutCompact ? 12.0 : 16.0;

        final tableHeaderStyle = TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: layoutCompact ? 10 : 11,
          letterSpacing: 1,
        );

        final Widget secondaryAlumnosToolbarButtons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _ordenAlfabetico = !_ordenAlfabetico;
                });
              },
              icon: Icon(
                _ordenAlfabetico ? Icons.sort_by_alpha : Icons.schedule,
                size: tbIconSm,
              ),
              label: Text(
                _ordenAlfabetico ? 'ORDEN A-Z' : 'FECHA',
                style: TextStyle(fontSize: tbFsSm),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                foregroundColor: isDark ? Colors.white : Colors.black,
                padding: tbPadSm,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tbRadius),
                ),
              ),
            ),
            SizedBox(width: layoutCompact ? 5 : 8),
            Tooltip(
              message: 'Planilla de cursos (PDF)',
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_alumnos.isNotEmpty) {
                    PdfService.generarPlanillaCursos(widget.evento, _alumnos);
                  }
                },
                icon: Icon(Icons.print_rounded, size: tbIcon),
                label: Text(
                  layoutCompact ? 'PLANILLA' : 'PLANILLA CURSOS',
                  style: TextStyle(fontSize: tbFs),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: tbPadSm,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tbRadius),
                  ),
                ),
              ),
            ),
            SizedBox(width: layoutCompact ? 5 : 8),
            Tooltip(
              message: 'Sortear mesas',
              child: ElevatedButton.icon(
                onPressed: _sortearMesas,
                icon: Icon(Icons.casino, size: tbIcon),
                label: Text(
                  layoutCompact ? 'SORTEAR' : 'SORTEAR MESAS',
                  style: TextStyle(fontSize: tbFs),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: tbPadSm,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tbRadius),
                  ),
                ),
              ),
            ),
            SizedBox(width: layoutCompact ? 5 : 8),
            Tooltip(
              message: 'Deshacer sorteo de mesas',
              child: ElevatedButton.icon(
                onPressed: _deshacerSorteoMesas,
                icon: Icon(Icons.undo, size: tbIcon),
                label: Text(
                  layoutCompact ? 'DESHACER' : 'DESHACER MESAS',
                  style: TextStyle(fontSize: tbFs),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: tbPadSm,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tbRadius),
                  ),
                ),
              ),
            ),
          ],
        );
        final Widget primaryAlumnosToolbarButtons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ALUMNOS INSCRIPTOS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: layoutCompact ? 10 : 12,
                letterSpacing: layoutCompact ? 0.7 : 1.2,
                color: Colors.grey,
              ),
            ),
            SizedBox(width: layoutCompact ? 8 : 12),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: layoutCompact ? 6 : 10,
                vertical: layoutCompact ? 2 : 4,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(layoutCompact ? 10 : 12),
                border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_alt_rounded,
                    size: layoutCompact ? 13 : 14,
                    color: const Color(0xFFD4AF37),
                  ),
                  SizedBox(width: layoutCompact ? 4 : 6),
                  Text(
                    '${alumnosFiltrados.where((a) => !a.nombreAlumno.startsWith('[BAJA]')).length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: layoutCompact ? 12 : 13,
                      color: const Color(0xFFD4AF37),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: layoutCompact ? 6 : 10),
            Tooltip(
              message: 'Contratos firmados / alumnos listados',
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: layoutCompact ? 6 : 10,
                  vertical: layoutCompact ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(layoutCompact ? 10 : 12),
                  border: Border.all(
                    color: Colors.teal.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_turned_in_outlined,
                      size: layoutCompact ? 13 : 14,
                      color: Colors.teal.shade700,
                    ),
                    SizedBox(width: layoutCompact ? 4 : 6),
                    Text(
                      '$contratosFirmados/${alumnosFiltrados.where((a) => !a.nombreAlumno.startsWith('[BAJA]')).length}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: layoutCompact ? 12 : 13,
                        color: Colors.teal.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: layoutCompact ? 8 : 16),
            Tooltip(
              message: 'Registrar nuevo alumno',
              child: ElevatedButton.icon(
                onPressed: _mostrarModalRegistrarAlumno,
                icon: Icon(Icons.person_add_alt_1, size: tbIcon),
                label: Text(
                  layoutCompact ? 'REGISTRAR' : 'REGISTRAR ALUMNO',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: tbFs,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.black,
                  padding: tbPadLg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tbRadius),
                  ),
                  elevation: layoutCompact ? 2 : 4,
                ),
              ),
            ),
            SizedBox(width: layoutCompact ? 6 : 10),
            Tooltip(
              message: 'Marcar contratos firmados por alumno',
              child: ElevatedButton.icon(
                onPressed: _mostrarDialogContratosFirmados,
                icon: Icon(Icons.assignment_turned_in_outlined, size: tbIcon),
                label: Text(
                  'CONTRATOS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: tbFs,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: tbPadMd,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tbRadius),
                  ),
                  elevation: layoutCompact ? 2 : 3,
                ),
              ),
            ),
            SizedBox(width: layoutCompact ? 6 : 8),
            Tooltip(
              message:
                  'Seleccionar varios alumnos en la tabla (usa la búsqueda de arriba) y marcar o quitar firma de contrato de una vez.',
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _modoSeleccionContratos = !_modoSeleccionContratos;
                    if (!_modoSeleccionContratos) {
                      _idsSeleccionContratos.clear();
                    }
                  });
                },
                icon: Icon(
                  _modoSeleccionContratos
                      ? Icons.close
                      : Icons.checklist_rounded,
                  size: tbIcon,
                ),
                label: Text(
                  _modoSeleccionContratos ? 'CANCELAR' : 'SELECCIÓN',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: tbFs,
                    letterSpacing: 0.5,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal.shade800,
                  side: BorderSide(
                    color: Colors.teal.shade700,
                    width: layoutCompact ? 1.2 : 1.5,
                  ),
                  padding: tbPadMd,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tbRadius),
                  ),
                ),
              ),
            ),
          ],
        );

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPad,
                layoutCompact ? 6 : 24,
                horizontalPad,
                layoutCompact ? 4 : 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Izquierda: contadores + acciones principales; derecha: orden/planilla/sortear/deshacer
                  // alineados al borde final (ancho del buscador / contenido).
                  Theme(
                    data: Theme.of(context).copyWith(
                      visualDensity: layoutCompact
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: primaryAlumnosToolbarButtons,
                          ),
                        ),
                        SizedBox(width: layoutCompact ? 8 : 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: secondaryAlumnosToolbarButtons,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: layoutCompact ? 8 : 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: 'Buscar por alumno o curso',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: layoutCompact,
                            contentPadding: layoutCompact
                                ? const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  )
                                : null,
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
                  if (_modoSeleccionContratos) ...[
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        border: Border.all(color: Colors.teal.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              Icons.touch_app,
                              size: 20,
                              color: Colors.teal.shade800,
                            ),
                            Text(
                              '${_idsSeleccionContratos.length} seleccionado(s)',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Colors.teal.shade900,
                              ),
                            ),
                            Text(
                              '· Usá los checkboxes o tocá filas. El encabezado marca todos los visibles.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _idsSeleccionContratos.isEmpty
                                  ? null
                                  : () => _aplicarContratoFirmadoSeleccionTabla(
                                      true,
                                    ),
                              icon: const Icon(
                                Icons.assignment_turned_in_outlined,
                                size: 18,
                              ),
                              label: const Text('Marcar firmado'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _idsSeleccionContratos.isEmpty
                                  ? null
                                  : () => _aplicarContratoFirmadoSeleccionTabla(
                                      false,
                                    ),
                              style: FilledButton.styleFrom(
                                foregroundColor: Colors.deepOrange.shade900,
                              ),
                              icon: const Icon(
                                Icons.remove_done_rounded,
                                size: 18,
                              ),
                              label: const Text('Quitar firma'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _lazyScrollController,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: availableWidth),
                    child: DataTable(
                      columnSpacing: layoutCompact
                          ? 10
                          : (availableWidth > 1000 ? 24 : 16),
                      horizontalMargin: horizontalPad,
                      headingRowHeight: layoutCompact ? 36 : 48,
                      dataRowMinHeight: layoutCompact ? 44 : 56,
                      dataRowMaxHeight: layoutCompact ? 72 : 102,
                      showCheckboxColumn: _modoSeleccionContratos,
                      onSelectAll: _modoSeleccionContratos
                          ? (selected) {
                              setState(() {
                                if (selected == true) {
                                  for (final a in alumnosFiltrados) {
                                    _idsSeleccionContratos.add(a.id);
                                  }
                                } else {
                                  for (final a in alumnosFiltrados) {
                                    _idsSeleccionContratos.remove(a.id);
                                  }
                                }
                              });
                            }
                          : null,
                      columns: [
                        DataColumn(
                          label: SizedBox(
                            width: colAlumno,
                            child: Text('ALUMNO', style: tableHeaderStyle),
                          ),
                        ),
                        DataColumn(
                          label: SizedBox(
                            width: colTelefono,
                            child: Text('TELÉFONO', style: tableHeaderStyle),
                          ),
                        ),
                        DataColumn(
                          label: SizedBox(
                            width: colAcomp,
                            child: Text('ACOMP.', style: tableHeaderStyle),
                          ),
                        ),
                        DataColumn(
                          label: SizedBox(
                            width: colMesa,
                            child: Text('MESA', style: tableHeaderStyle),
                          ),
                        ),
                        DataColumn(
                          label: SizedBox(
                            width: colContrato,
                            child: Text('CONT.', style: tableHeaderStyle),
                          ),
                        ),
                        DataColumn(
                          label: SizedBox(
                            width: colEstado,
                            child: Text(
                              'ESTADO DE DEUDA',
                              style: tableHeaderStyle,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: SizedBox(
                            width: colAcciones,
                            child: Text('ACCIONES', style: tableHeaderStyle),
                          ),
                        ),
                      ],
                      rows: alumnosFiltrados.take(_itemsRenderizados).map((a) {
                        final int tCuotas = a.totalCuotas ?? 9;
                        final int cPagadas = a.cuotasPagadas ?? 0;
                        final int cantAcomp = a.cantidadAcompanantes ?? 0;

                        final int totalCuotas = tCuotas > 0 ? tCuotas : 9;

                        /// Misma regla que el vencimiento mostrado abajo (último día del mes por alta + cuota).
                        final mora = MoraCuotaCalculator.calcular(a);
                        final cobradoMoraHist =
                            _moraCobradaPorContrato[a.id] ?? 0.0;
                        final moraPendienteFila =
                            MoraCuotaCalculator.moraPendienteOperativa(
                              contrato: a,
                              moraCobradaHistorial: cobradoMoraHist,
                            );

                        final estadoUi = CronogramaCuotasUtils.resolverEstadoUi(
                          contrato: a,
                          moraEnMora: mora.enMora,
                          moraPendientePesos: moraPendienteFila,
                        );
                        final cronogramaLineas =
                            CronogramaCuotasUtils.lineasInformativas(
                              a,
                              moraPendientePesos: moraPendienteFila,
                            );

                        final bool estaLiquidado = a.saldoDeudor <= 0.01;
                        final Color estadoColor = estadoUi.color;
                        final IconData estadoIcono = estadoUi.icono;
                        final String estadoTexto = estadoUi.texto;

                        final String montoTexto = estaLiquidado
                            ? ''
                            : 'Saldo: ${_ocultarMontos ? '***' : a.saldoDeudor.toCurrency()}';

                        final int cuotasMostrar = estaLiquidado
                            ? totalCuotas
                            : cPagadas;
                        final cuotaInfo =
                            '($cuotasMostrar/$totalCuotas cuotas)';

                        final bool esBajaTemporal = a.nombreAlumno.startsWith(
                          '[BAJA]',
                        );
                        final String nombreLimpio = a.nombreAlumno
                            .replaceFirst('[BAJA]', '')
                            .trim();
                        final notaOp = _notasOperativasPorContrato[a.id];

                        return DataRow(
                          color: WidgetStateProperty.resolveWith<Color?>((
                            states,
                          ) {
                            if (esBajaTemporal) {
                              return isDark
                                  ? Colors.white.withValues(alpha: 0.01)
                                  : Colors.black.withValues(alpha: 0.015);
                            }
                            return null;
                          }),
                          selected:
                              _modoSeleccionContratos &&
                              _idsSeleccionContratos.contains(a.id),
                          onSelectChanged: _modoSeleccionContratos
                              ? (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _idsSeleccionContratos.add(a.id);
                                    } else {
                                      _idsSeleccionContratos.remove(a.id);
                                    }
                                  });
                                }
                              : null,
                          cells: [
                            DataCell(
                              SizedBox(
                                width: colAlumno,
                                child: esBajaTemporal
                                    ? Opacity(
                                        opacity: 0.55,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nombreLimpio,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: layoutCompact
                                                    ? 12
                                                    : 13,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                                fontStyle: FontStyle.italic,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            if (a.cursoDivision != null &&
                                                a.cursoDivision!.isNotEmpty)
                                              Container(
                                                margin: EdgeInsets.only(
                                                  top: layoutCompact ? 2 : 3,
                                                ),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: layoutCompact
                                                      ? 6
                                                      : 8,
                                                  vertical: layoutCompact
                                                      ? 1
                                                      : 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withValues(
                                                    alpha: 0.1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: Colors.blue
                                                        .withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Text(
                                                  a.cursoDivision!,
                                                  style: TextStyle(
                                                    fontSize: layoutCompact
                                                        ? 10
                                                        : 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.blue,
                                                  ),
                                                ),
                                              ),
                                            if (a.createdAt != null)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: layoutCompact ? 2 : 4,
                                                  left: 2,
                                                ),
                                                child: Text(
                                                  'Reg: ${a.createdAt!.day}/${a.createdAt!.month}/${a.createdAt!.year % 100}',
                                                  style: TextStyle(
                                                    fontSize: layoutCompact
                                                        ? 9
                                                        : 10,
                                                    color: Colors.grey
                                                        .withValues(alpha: 0.6),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            a.nombreAlumno,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: layoutCompact ? 12 : 13,
                                            ),
                                          ),
                                          if (a.cursoDivision != null &&
                                              a.cursoDivision!.isNotEmpty)
                                            Container(
                                              margin: EdgeInsets.only(
                                                top: layoutCompact ? 2 : 3,
                                              ),
                                              padding: EdgeInsets.symmetric(
                                                horizontal: layoutCompact
                                                    ? 6
                                                    : 8,
                                                vertical: layoutCompact ? 1 : 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: Colors.blue.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                a.cursoDivision!,
                                                style: TextStyle(
                                                  fontSize: layoutCompact
                                                      ? 10
                                                      : 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ),
                                          if (a.createdAt != null)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                top: layoutCompact ? 2 : 4,
                                                left: 2,
                                              ),
                                              child: Text(
                                                'Reg: ${a.createdAt!.day}/${a.createdAt!.month}/${a.createdAt!.year % 100}',
                                                style: TextStyle(
                                                  fontSize: layoutCompact
                                                      ? 9
                                                      : 10,
                                                  color: Colors.grey.withValues(
                                                    alpha: 0.6,
                                                  ),
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
                                child: esBajaTemporal
                                    ? Opacity(
                                        opacity: 0.55,
                                        child: Text(
                                          a.telefono?.isNotEmpty == true
                                              ? a.telefono!
                                              : '-',
                                          style: TextStyle(
                                            fontSize: layoutCompact ? 11 : 12,
                                            fontWeight: FontWeight.w500,
                                            color:
                                                a.telefono?.isNotEmpty == true
                                                ? null
                                                : Colors.grey.shade500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                    : Text(
                                        a.telefono?.isNotEmpty == true
                                            ? a.telefono!
                                            : '-',
                                        style: TextStyle(
                                          fontSize: layoutCompact ? 11 : 12,
                                          fontWeight: FontWeight.w500,
                                          color: a.telefono?.isNotEmpty == true
                                              ? null
                                              : Colors.grey.shade500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                            ),

                            DataCell(
                              SizedBox(
                                width: colAcomp,
                                child: esBajaTemporal
                                    ? Opacity(
                                        opacity: 0.55,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _mostrarModalDetalleAcompanantes(
                                                a,
                                              ),
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Chip(
                                                  label: Text(
                                                    '+$cantAcomp',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  backgroundColor: Colors.blue
                                                      .withValues(alpha: 0.1),
                                                  side: BorderSide(
                                                    color: Colors.blue
                                                        .withValues(alpha: 0.3),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 0,
                                                      ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                if (a
                                                    .nombresAcompanantes
                                                    .isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                    child: Text(
                                                      a.nombresAcompanantes
                                                          .join(', '),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : GestureDetector(
                                        onTap: () =>
                                            _mostrarModalDetalleAcompanantes(a),
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Chip(
                                                label: Text(
                                                  '+$cantAcomp',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                backgroundColor: Colors.blue
                                                    .withValues(alpha: 0.1),
                                                side: BorderSide(
                                                  color: Colors.blue.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 0,
                                                    ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              if (a
                                                  .nombresAcompanantes
                                                  .isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2,
                                                      ),
                                                  child: Text(
                                                    a.nombresAcompanantes.join(
                                                      ', ',
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
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
                                width: colMesa,
                                child: Opacity(
                                  opacity: esBajaTemporal ? 0.55 : 1,
                                  child: Text(
                                    a.numeroMesa?.isNotEmpty == true
                                        ? a.numeroMesa!
                                        : '-',
                                    style: TextStyle(
                                      fontSize: layoutCompact ? 11 : 12,
                                      fontWeight: FontWeight.w700,
                                      color: a.numeroMesa?.isNotEmpty == true
                                          ? Colors.indigo
                                          : Colors.grey.shade500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ),
                              ),
                            ),

                            DataCell(
                              SizedBox(
                                width: colContrato,
                                child: esBajaTemporal
                                    ? Opacity(
                                        opacity: 0.35,
                                        child: IgnorePointer(
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: BoxConstraints(
                                              minWidth: layoutCompact ? 32 : 36,
                                              minHeight: layoutCompact
                                                  ? 32
                                                  : 36,
                                            ),
                                            visualDensity: layoutCompact
                                                ? VisualDensity.compact
                                                : VisualDensity.standard,
                                            tooltip: 'Contrato inactivo',
                                            icon: Icon(
                                              a.contratoFirmado
                                                  ? Icons.assignment_turned_in
                                                  : Icons
                                                        .pending_actions_outlined,
                                              size: layoutCompact ? 20 : 22,
                                              color: a.contratoFirmado
                                                  ? Colors.teal.shade700
                                                  : Colors.grey.shade500,
                                            ),
                                            onPressed: () {},
                                          ),
                                        ),
                                      )
                                    : IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(
                                          minWidth: layoutCompact ? 32 : 36,
                                          minHeight: layoutCompact ? 32 : 36,
                                        ),
                                        visualDensity: layoutCompact
                                            ? VisualDensity.compact
                                            : VisualDensity.standard,
                                        tooltip: a.contratoFirmado
                                            ? 'Contrato firmado (tocar para desmarcar)'
                                            : 'Marcar contrato firmado',
                                        icon: Icon(
                                          a.contratoFirmado
                                              ? Icons.assignment_turned_in
                                              : Icons.pending_actions_outlined,
                                          size: layoutCompact ? 20 : 22,
                                          color: a.contratoFirmado
                                              ? Colors.teal.shade700
                                              : Colors.grey.shade500,
                                        ),
                                        onPressed: () =>
                                            _toggleContratoFirmado(a),
                                      ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: colEstado,
                                child: esBajaTemporal
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.05,
                                                )
                                              : Colors.black.withValues(
                                                  alpha: 0.04,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.withValues(
                                              alpha: 0.3,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons
                                                  .pause_circle_outline_rounded,
                                              color: Colors.grey.shade600,
                                              size: layoutCompact ? 14 : 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'BAJA TEMPORAL',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w900,
                                                fontSize: layoutCompact
                                                    ? 10
                                                    : 11,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  estadoIcono,
                                                  color: estadoColor,
                                                  size: layoutCompact ? 14 : 16,
                                                ),
                                                SizedBox(
                                                  width: layoutCompact ? 4 : 6,
                                                ),
                                                Flexible(
                                                  child: Text(
                                                    estadoTexto,
                                                    style: TextStyle(
                                                      color: estadoColor,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: layoutCompact
                                                          ? 11
                                                          : 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (montoTexto.isNotEmpty)
                                              Text(
                                                montoTexto,
                                                style: TextStyle(
                                                  color: estadoColor.withValues(
                                                    alpha: 0.8,
                                                  ),
                                                  fontSize: layoutCompact
                                                      ? 10
                                                      : 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            Text(
                                              cuotaInfo,
                                              style: TextStyle(
                                                fontSize: layoutCompact
                                                    ? 9
                                                    : 10,
                                                color: Colors.grey,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            ...MesasExtraUtils.lineasResumenGrilla(
                                              a,
                                            ).map(
                                              (linea) => Padding(
                                                padding: EdgeInsets.only(
                                                  top: layoutCompact ? 1 : 2,
                                                ),
                                                child: Text(
                                                  linea,
                                                  style: TextStyle(
                                                    fontSize: layoutCompact
                                                        ? 8
                                                        : 9,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (cronogramaLineas
                                                    .cuotaPendiente !=
                                                null)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: layoutCompact ? 1 : 2,
                                                ),
                                                child: Text(
                                                  cronogramaLineas
                                                      .cuotaPendiente!,
                                                  style: TextStyle(
                                                    fontSize: layoutCompact
                                                        ? 8
                                                        : 9,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            if (cronogramaLineas
                                                    .proximoVencimiento !=
                                                null)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: layoutCompact ? 1 : 2,
                                                ),
                                                child: Text(
                                                  cronogramaLineas
                                                      .proximoVencimiento!,
                                                  style: TextStyle(
                                                    fontSize: layoutCompact
                                                        ? 8
                                                        : 9,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            if (cronogramaLineas
                                                    .moraCongeladaHasta !=
                                                null)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: layoutCompact ? 1 : 2,
                                                ),
                                                child: Text(
                                                  cronogramaLineas
                                                      .moraCongeladaHasta!,
                                                  style: TextStyle(
                                                    fontSize: layoutCompact
                                                        ? 8
                                                        : 9,
                                                    color: Colors
                                                        .blueGrey
                                                        .shade600,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            if (moraPendienteFila > 0.01) ...[
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: layoutCompact ? 1 : 2,
                                                ),
                                                child: Builder(
                                                  builder: (_) {
                                                    final tracked =
                                                        a.moraPendienteTracked
                                                            .clamp(
                                                              0.0,
                                                              double.infinity,
                                                            );
                                                    final desglose =
                                                        MoraCuotaCalculator
                                                            .calcularDesglose(a);
                                                    final partes = <String>[];
                                                    if (tracked > 0.01) {
                                                      // Heurística grilla (sin historial): el tracked
                                                      // postCobro queda de las últimas liquidadas.
                                                      final n =
                                                          cPagadas.clamp(1, 99);
                                                      partes.add(
                                                        'Pend. C$n ${tracked.toCurrency()}',
                                                      );
                                                    }
                                                    if (desglose.isNotEmpty) {
                                                      partes.add(
                                                        desglose
                                                            .map(
                                                              (d) =>
                                                                  'C${d.numeroCuota} (${d.mesLabel.split(' ').first}) ${d.diasMora}d',
                                                            )
                                                            .join(' · '),
                                                      );
                                                    }
                                                    final titulo =
                                                        'Mora pendiente: ${moraPendienteFila.toCurrency()}';
                                                    final detalle =
                                                        partes.join(' · ');
                                                    return Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          titulo,
                                                          style: TextStyle(
                                                            fontSize:
                                                                layoutCompact
                                                                    ? 8
                                                                    : 9,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Colors.orange
                                                                .shade800,
                                                          ),
                                                        ),
                                                        if (detalle.isNotEmpty)
                                                          Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                              top:
                                                                  layoutCompact
                                                                      ? 0
                                                                      : 1,
                                                            ),
                                                            child: Text(
                                                              detalle,
                                                              style: TextStyle(
                                                                fontSize:
                                                                    layoutCompact
                                                                        ? 7
                                                                        : 8,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Colors
                                                                    .orange
                                                                    .shade700,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  esBajaTemporal
                                      ? Opacity(
                                          opacity: 0.3,
                                          child: IgnorePointer(
                                            child: IconButton(
                                              visualDensity: layoutCompact
                                                  ? VisualDensity.compact
                                                  : VisualDensity.standard,
                                              constraints: BoxConstraints(
                                                minWidth: layoutCompact
                                                    ? 34
                                                    : 40,
                                                minHeight: layoutCompact
                                                    ? 34
                                                    : 40,
                                              ),
                                              padding: EdgeInsets.zero,
                                              icon: Icon(
                                                Icons.edit_outlined,
                                                size: layoutCompact ? 18 : 20,
                                              ),
                                              tooltip: 'Editar alumno/cuotas',
                                              onPressed: () {},
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          visualDensity: layoutCompact
                                              ? VisualDensity.compact
                                              : VisualDensity.standard,
                                          constraints: BoxConstraints(
                                            minWidth: layoutCompact ? 34 : 40,
                                            minHeight: layoutCompact ? 34 : 40,
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            size: layoutCompact ? 18 : 20,
                                          ),
                                          tooltip: 'Editar alumno/cuotas',
                                          onPressed: () =>
                                              _mostrarModalEditarAlumno(a),
                                        ),
                                  esBajaTemporal
                                      ? Opacity(
                                          opacity: 0.3,
                                          child: IgnorePointer(
                                            child: IconButton(
                                              visualDensity: layoutCompact
                                                  ? VisualDensity.compact
                                                  : VisualDensity.standard,
                                              constraints: BoxConstraints(
                                                minWidth: layoutCompact
                                                    ? 34
                                                    : 40,
                                                minHeight: layoutCompact
                                                    ? 34
                                                    : 40,
                                              ),
                                              padding: EdgeInsets.zero,
                                              icon: Icon(
                                                Icons.payments_outlined,
                                                size: layoutCompact ? 18 : 20,
                                              ),
                                              tooltip: 'Registrar pago',
                                              onPressed: () {},
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          visualDensity: layoutCompact
                                              ? VisualDensity.compact
                                              : VisualDensity.standard,
                                          constraints: BoxConstraints(
                                            minWidth: layoutCompact ? 34 : 40,
                                            minHeight: layoutCompact ? 34 : 40,
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            Icons.payments_outlined,
                                            size: layoutCompact ? 18 : 20,
                                          ),
                                          tooltip: 'Registrar pago',
                                          onPressed: () =>
                                              _mostrarModalPagoAlumno(a),
                                        ),
                                  esBajaTemporal
                                      ? Opacity(
                                          opacity: 0.3,
                                          child: IgnorePointer(
                                            child: IconButton(
                                              visualDensity: layoutCompact
                                                  ? VisualDensity.compact
                                                  : VisualDensity.standard,
                                              constraints: BoxConstraints(
                                                minWidth: layoutCompact
                                                    ? 34
                                                    : 40,
                                                minHeight: layoutCompact
                                                    ? 34
                                                    : 40,
                                              ),
                                              padding: EdgeInsets.zero,
                                              icon: Icon(
                                                Icons
                                                    .account_balance_wallet_outlined,
                                                size: layoutCompact ? 18 : 20,
                                                color: const Color(0xFFD4AF37),
                                              ),
                                              tooltip: 'Ver Estado de Cuenta',
                                              onPressed: () {},
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          visualDensity: layoutCompact
                                              ? VisualDensity.compact
                                              : VisualDensity.standard,
                                          constraints: BoxConstraints(
                                            minWidth: layoutCompact ? 34 : 40,
                                            minHeight: layoutCompact ? 34 : 40,
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            Icons
                                                .account_balance_wallet_outlined,
                                            size: layoutCompact ? 18 : 20,
                                            color: const Color(0xFFD4AF37),
                                          ),
                                          tooltip: 'Ver Estado de Cuenta',
                                          onPressed: () =>
                                              _mostrarHistorialPagosAlumno(a),
                                        ),
                                  esBajaTemporal
                                      ? Opacity(
                                          opacity: 0.3,
                                          child: IgnorePointer(
                                            child: IconButton(
                                              visualDensity: layoutCompact
                                                  ? VisualDensity.compact
                                                  : VisualDensity.standard,
                                              constraints: BoxConstraints(
                                                minWidth: layoutCompact
                                                    ? 34
                                                    : 40,
                                                minHeight: layoutCompact
                                                    ? 34
                                                    : 40,
                                              ),
                                              padding: EdgeInsets.zero,
                                              icon: Icon(
                                                Icons.picture_as_pdf_outlined,
                                                size: layoutCompact ? 18 : 20,
                                              ),
                                              tooltip: 'Generar Recibo',
                                              onPressed: () {},
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          visualDensity: layoutCompact
                                              ? VisualDensity.compact
                                              : VisualDensity.standard,
                                          constraints: BoxConstraints(
                                            minWidth: layoutCompact ? 34 : 40,
                                            minHeight: layoutCompact ? 34 : 40,
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            Icons.picture_as_pdf_outlined,
                                            size: layoutCompact ? 18 : 20,
                                          ),
                                          tooltip: 'Generar Recibo',
                                          onPressed: () =>
                                              _imprimirReciboAlumno(a),
                                        ),
                                  _buildNotaOperativaButton(
                                    a,
                                    notaOp,
                                    layoutCompact,
                                  ),
                                  if (modoJefe) ...[
                                    esBajaTemporal
                                        ? IconButton(
                                            visualDensity: layoutCompact
                                                ? VisualDensity.compact
                                                : VisualDensity.standard,
                                            constraints: BoxConstraints(
                                              minWidth: layoutCompact ? 34 : 40,
                                              minHeight: layoutCompact
                                                  ? 34
                                                  : 40,
                                            ),
                                            padding: EdgeInsets.zero,
                                            icon: Icon(
                                              Icons.play_circle_outline_rounded,
                                              color:
                                                  Colors.greenAccent.shade700,
                                              size: layoutCompact ? 18 : 20,
                                            ),
                                            tooltip: 'Reincorporar alumno',
                                            onPressed: () =>
                                                _toggleBajaTemporal(a),
                                          )
                                        : IconButton(
                                            visualDensity: layoutCompact
                                                ? VisualDensity.compact
                                                : VisualDensity.standard,
                                            constraints: BoxConstraints(
                                              minWidth: layoutCompact ? 34 : 40,
                                              minHeight: layoutCompact
                                                  ? 34
                                                  : 40,
                                            ),
                                            padding: EdgeInsets.zero,
                                            icon: Icon(
                                              Icons
                                                  .pause_circle_outline_rounded,
                                              color: Colors.orangeAccent,
                                              size: layoutCompact ? 18 : 20,
                                            ),
                                            tooltip:
                                                'Baja temporal (suspender)',
                                            onPressed: () =>
                                                _toggleBajaTemporal(a),
                                          ),
                                    IconButton(
                                      visualDensity: layoutCompact
                                          ? VisualDensity.compact
                                          : VisualDensity.standard,
                                      constraints: BoxConstraints(
                                        minWidth: layoutCompact ? 34 : 40,
                                        minHeight: layoutCompact ? 34 : 40,
                                      ),
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: layoutCompact ? 18 : 20,
                                      ),
                                      tooltip: 'Eliminar definitivamente',
                                      onPressed: () =>
                                          _eliminarAlumnoPermanente(a),
                                    ),
                                  ],
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

  Widget _buildNotaOperativaButton(
    ContratoAlumno a,
    NotaOperativaContrato? notaOp,
    bool layoutCompact,
  ) {
    final bool tieneNota = notaOp != null && notaOp.tieneTexto;
    final bool resuelto = tieneNota && notaOp.resuelto;

    Color? bgColor;
    Color iconColor;
    IconData iconData;

    if (tieneNota) {
      if (resuelto) {
        bgColor = Colors.teal.withValues(alpha: 0.15);
        iconColor = Colors.teal.shade700;
        iconData = Icons.task_alt_rounded;
      } else {
        bgColor = const Color(0xFFD4AF37).withValues(alpha: 0.15);
        iconColor = const Color(0xFFD4AF37);
        iconData = Icons.description_rounded;
      }
    } else {
      bgColor = Colors.transparent;
      iconColor = Colors.grey.withValues(alpha: 0.4);
      iconData = Icons.note_add_outlined;
    }

    return Container(
      width: layoutCompact ? 34 : 38,
      height: layoutCompact ? 34 : 38,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: tieneNota
            ? Border.all(color: iconColor.withValues(alpha: 0.3), width: 1.5)
            : null,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tieneNota
            ? (resuelto
                  ? 'Nota resuelta: ${notaOp.texto}'
                  : 'Nota pendiente: ${notaOp.texto}')
            : 'Agregar nota operativa',
        icon: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(iconData, size: layoutCompact ? 16 : 18, color: iconColor),
            if (tieneNota && !resuelto)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        onPressed: () async {
          await showNotaOperativaSheet(
            context: context,
            ref: ref,
            alumno: a,
            existente: notaOp,
            onChanged: () {
              _cargarNotasOperativas();
            },
          );
        },
      ),
    );
  }

  Future<void> _toggleBajaTemporal(ContratoAlumno alumno) async {
    if (!mounted) return;
    final bool esBaja = alumno.nombreAlumno.startsWith('[BAJA]');
    final String nombreLimpio = alumno.nombreAlumno
        .replaceFirst('[BAJA]', '')
        .trim();
    final String msg = esBaja
        ? '¿Desea reincorporar a $nombreLimpio como alumno activo? '
              'Podrá cobrarle cuando quiera; la mora seguirá congelada al día '
              'de la baja hasta que liquide.'
        : '¿Desea dar de baja temporal a $nombreLimpio? Se mantendrá en la '
              'lista pero no contará para los saldos. Su saldo y mora quedarán '
              'congelados como hoy hasta que cobre.';
    final String titulo = esBaja
        ? 'Reincorporar Alumno'
        : 'Confirmar Baja Temporal';
    final String btnText = esBaja ? 'REINCORPORAR' : 'DAR DE BAJA';
    final Color btnColor = esBaja
        ? Colors.teal.shade700
        : Colors.orange.shade800;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: btnColor, width: 2),
        ),
        title: Row(
          children: [
            Icon(
              esBaja ? Icons.person_add_rounded : Icons.person_off_outlined,
              color: btnColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              titulo,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        content: Text(msg, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCELAR',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              btnText,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final repo = ref.read(contratosRepositoryProvider);
      try {
        final Map<String, dynamic> updates;
        if (esBaja) {
          updates = {'nombre_alumno': nombreLimpio};
        } else {
          final hoyAr = ArTime.nowAr();
          final hoySolo = DateTime(hoyAr.year, hoyAr.month, hoyAr.day);
          updates = {
            'nombre_alumno': '[BAJA] ${alumno.nombreAlumno}',
            'mora_fecha_referencia':
                MoraCuotaCalculator.fechaReferenciaIsoDesde(hoySolo),
            'baja_temporal_desde': ArTime.nowUtcIso(),
          };
        }
        await repo.actualizarContrato(alumno.id, updates);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                esBaja
                    ? 'Alumno reincorporado. La mora sigue congelada hasta que cobre.'
                    : 'Alumno en baja temporal. Saldo y mora congelados desde hoy.',
              ),
              backgroundColor: esBaja ? Colors.teal : Colors.orange,
            ),
          );
          _fetchDatos(cargaSilenciosa: true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al cambiar estado del alumno: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _eliminarAlumnoPermanente(ContratoAlumno alumno) async {
    if (!mounted) return;
    final nombreLimpio = alumno.nombreAlumno.replaceFirst('[BAJA]', '').trim();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.delete_forever_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'ELIMINAR DEFINITIVO',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        content: Text(
          '¿Está seguro de que desea eliminar a $nombreLimpio de forma permanente? Esta acción borrará el registro y todos sus pagos asociados de la base de datos de forma irreversible.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCELAR',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ELIMINAR DEFINITIVAMENTE',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final repo = ref.read(contratosRepositoryProvider);
      try {
        await repo.eliminarContratoPermanente(alumno.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Alumno eliminado definitivamente de la base de datos',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          _fetchDatos(cargaSilenciosa: true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar alumno: $e'),
              backgroundColor: Colors.redAccent,
            ),
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
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
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
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        title: Text(
                          alumno.nombresAcompanantes[index],
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
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
    final autoSyncCheckpoint = DateTime.now().toUtc();
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(contratosRepositoryProvider);
      await repo.reconciliarMesasExtrasEvento(widget.evento.id);
      await _refreshAlumnos();

      final alumnosSinMesa = _alumnos
          .where(
            (a) =>
                !a.nombreAlumno.startsWith('[BAJA]') &&
                (a.numeroMesa == null || a.numeroMesa!.isEmpty),
          )
          .toList();

      if (alumnosSinMesa.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos los alumnos ya tienen mesa asignada.'),
            ),
          );
        }
        return;
      }

      final demanda = MesasExtraUtils.calcularDemandaSorteo(_alumnos);
      final titulo = widget.evento.cliente?.nombreCompleto ?? 'Evento masivo';

      if (!mounted) return;
      setState(() => _isLoading = false);

      final config = await mostrarSorteoMesasDialog(
        context: context,
        tituloInstitucion: titulo,
        alumnosSinMesa: alumnosSinMesa,
        demanda: demanda,
      );
      if (config == null) return;

      setState(() => _isLoading = true);

      final ocupadas = <int>{};
      for (final c in _alumnos) {
        ocupadas.addAll(MesasExtraUtils.numerosMesaDesdeTexto(c.numeroMesa));
      }

      final asignaciones = MesasExtraUtils.asignarMesasSorteo(
        alumnos: _alumnos,
        capacidadSalon: config.capacidadSalon,
        ocupadasIniciales: ocupadas,
        separaciones: config.separaciones,
      );

      if (asignaciones == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No hay mesas libres suficientes en el rango del salón. '
                'Subí la capacidad e intentá de nuevo.',
              ),
            ),
          );
        }
        return;
      }

      for (final entry in asignaciones.entries) {
        final asignacion = MesasExtraUtils.formatearAsignacionMesas(
          entry.value,
        );
        await repo.actualizarContrato(entry.key, {'numero_mesa': asignacion});
      }
      await ref
          .read(cajaAutoSyncServiceProvider)
          .afterMassiveMutation(
            startedAt: autoSyncCheckpoint,
            isPayment: false,
          );

      if (mounted) {
        final sepTxt = config.separaciones.isEmpty
            ? ''
            : ' · ${config.separaciones.length} alumno(s) con mesa(s) alejada(s)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sorteo listo: ${asignaciones.length} alumno(s) con mesa asignada$sepTxt.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error en sorteo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
        content: const Text(
          'Se eliminarán los números de mesa de TODOS los alumnos de este evento, '
          'incluidas las asignaciones manuales.\n\n'
          'Podés sortear de nuevo cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DESHACER MESAS'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final autoSyncCheckpoint = DateTime.now().toUtc();
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(contratosRepositoryProvider);

      final alumnosConMesa = _alumnos
          .where(
            (a) =>
                !a.nombreAlumno.startsWith('[BAJA]') &&
                a.numeroMesa != null &&
                a.numeroMesa!.isNotEmpty,
          )
          .toList();

      if (alumnosConMesa.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay alumnos con mesa asignada para deshacer.'),
            ),
          );
        return;
      }

      int actualizados = 0;
      for (final alumno in alumnosConMesa) {
        await repo.actualizarContrato(alumno.id, {'numero_mesa': null});
        actualizados++;
      }
      await ref
          .read(cajaAutoSyncServiceProvider)
          .afterMassiveMutation(
            startedAt: autoSyncCheckpoint,
            isPayment: false,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mesas desasignadas ($actualizados). Podés sortear de nuevo.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error al deshacer mesas: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        _fetchDatos(cargaSilenciosa: true);
      }
    }
  }

  Future<void> _mostrarDialogContratosFirmados() async {
    final activos = _alumnos
        .where((a) => !a.nombreAlumno.startsWith('[BAJA]'))
        .toList();
    if (activos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay alumnos activos para gestionar contratos.'),
        ),
      );
      return;
    }
    final repo = ref.read(contratosRepositoryProvider);
    final tituloEvento =
        widget.evento.cliente?.nombreCompleto.trim().isNotEmpty == true
        ? widget.evento.cliente!.nombreCompleto.trim()
        : 'Evento masivo';
    final autoSyncCheckpoint = DateTime.now().toUtc();
    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContratosFirmadosBulkDialog(
        alumnos: activos,
        repository: repo,
        eventoTitulo: tituloEvento,
      ),
    );
    if (mounted && guardado == true) {
      await ref
          .read(cajaAutoSyncServiceProvider)
          .afterMassiveMutation(
            startedAt: autoSyncCheckpoint,
            isPayment: false,
          );
      await _fetchDatos(cargaSilenciosa: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contratos firmados actualizados.')),
        );
      }
    }
  }

  Future<void> _aplicarContratoFirmadoSeleccionTabla(bool firmado) async {
    if (_idsSeleccionContratos.isEmpty) return;
    final ids = List<String>.from(_idsSeleccionContratos);
    final n = ids.length;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          firmado ? 'Marcar contrato firmado' : 'Quitar firma del contrato',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          firmado
              ? '¿Confirmás marcar como firmado el contrato de $n alumno(s) seleccionado(s)? '
                    'Se guardará de inmediato.'
              : '¿Querés quitar la marca de contrato firmado en $n alumno(s) seleccionado(s)? '
                    'Se guardará de inmediato.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: firmado
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange.shade800,
                    foregroundColor: Colors.white,
                  ),
            child: Text(firmado ? 'Confirmar firma' : 'Quitar marca'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final map = {for (final id in ids) id: firmado};
    final autoSyncCheckpoint = DateTime.now().toUtc();
    try {
      await ref
          .read(contratosRepositoryProvider)
          .actualizarContratoFirmadoBulk(map);
      await ref
          .read(cajaAutoSyncServiceProvider)
          .afterMassiveMutation(
            startedAt: autoSyncCheckpoint,
            isPayment: false,
          );
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          final idx = _alumnos.indexWhere((x) => x.id == id);
          if (idx != -1) {
            _alumnos[idx] = _alumnos[idx].copyWith(contratoFirmado: firmado);
          }
        }
        _idsSeleccionContratos.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              firmado
                  ? 'Contratos marcados como firmados.'
                  : 'Se quitó la marca de contrato firmado.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _toggleContratoFirmado(ContratoAlumno alumno) async {
    if (alumno.nombreAlumno.startsWith('[BAJA]')) return;
    final nuevo = !alumno.contratoFirmado;
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          nuevo ? 'Confirmar contrato firmado' : 'Quitar firma del contrato',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          nuevo
              ? '¿Confirmás que ${alumno.nombreAlumno} firmó el contrato? '
                    'Esta acción se guarda de inmediato en el sistema.'
              : '¿Querés quitar la marca de contrato firmado para ${alumno.nombreAlumno}? '
                    'Esta acción se guarda de inmediato.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: nuevo
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange.shade800,
                    foregroundColor: Colors.white,
                  ),
            child: Text(nuevo ? 'Confirmar firma' : 'Quitar marca'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final repo = ref.read(contratosRepositoryProvider);
    final autoSyncCheckpoint = DateTime.now().toUtc();
    try {
      await repo.actualizarContrato(alumno.id, {'contrato_firmado': nuevo});
      await ref
          .read(cajaAutoSyncServiceProvider)
          .afterMassiveMutation(
            startedAt: autoSyncCheckpoint,
            isPayment: false,
          );
      if (!mounted) return;
      final idx = _alumnos.indexWhere((x) => x.id == alumno.id);
      if (idx != -1) {
        setState(() => _alumnos[idx] = alumno.copyWith(contratoFirmado: nuevo));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar el contrato: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _mostrarModalRegistrarAlumno() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ModalAlumnoPremium(evento: widget.evento),
    );
    if (mounted && result == true) {
      _refreshAlumnos();
    }
  }

  Future<void> _mostrarModalEditarAlumno(ContratoAlumno alumno) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ModalAlumnoPremium(evento: widget.evento, alumno: alumno),
    );
    if (mounted && result == true) await _refreshAlumnos();
  }

  Future<void> _mostrarModalPagoAlumno(ContratoAlumno alumno) async {
    final appRole = ref.read(appRoleProvider);
    if (appRole.esCaja && !appRole.tieneSesionCaja) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abrí caja antes de cobrar.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      return;
    }
    final cRepo = ref.read(contratosRepositoryProvider);
    var alumnoFresco = await cRepo.getContratoById(alumno.id) ?? alumno;
    // Reconciliar mesas antes de abrir el modal para que el JSON por mesa
    // esté al día (corrige contratos con pagos legacy sin número de mesa).
    if (alumnoFresco.mesaExtraPrecio > 0.01) {
      await cRepo.reconciliarMesasEstadoContrato(alumnoFresco.id);
      alumnoFresco =
          await cRepo.getContratoById(alumnoFresco.id) ?? alumnoFresco;
    }
    alumno = alumnoFresco;
    if (alumno.saldoDeudor <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este alumno no tiene saldo pendiente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    final prefsMedio = await SharedPreferences.getInstance();
    final moraYaCobradaHist = await cRepo.sumMoraCobradaHistorial(alumno.id);
    final pagosAlumno = await cRepo.getHistorialPagosAlumno(alumno.id);
    final historicoGrossPorClave = grossHistoricoPorConceptoKeyExtended(
      pagosAlumno,
    );
    final moraResumen = MoraCuotaCalculator.calcular(alumno);

    String modoMedioPago =
        prefsMedio.getString('medio_pago_cobro_masivo') ?? 'Efectivo';
    if (modoMedioPago != 'Efectivo' &&
        modoMedioPago != 'Transferencia' &&
        modoMedioPago != 'Mixto') {
      modoMedioPago = 'Efectivo';
    }

    final int tCuotas = alumno.totalCuotas ?? 9;
    final int cPagadas = alumno.cuotasPagadas ?? 0;
    final int mCuotas = alumno.mesaExtraCuotas ?? 1;
    final int mPagadas = alumno.mesaExtraCuotasPagadas ?? 0;
    final int sCuotas = alumno.sillasExtraCuotas ?? 1;
    final int sPagadas = alumno.sillasExtraCuotasPagadas ?? 0;

    final List<MesaExtraItem> mesasEstadoList =
        MesasExtraUtils.estadoDesdeContrato(alumno);
    final List<MesaExtraItem> mesasActivasCobro = MesasExtraUtils.mesasActivas(
      mesasEstadoList,
    );
    final int cantMesas = MesasExtraUtils.cantidadMesasContrato(
      alumno,
      mesasEstadoList,
    );
    final double precioUnitMesa = alumno.precioUnitarioMesaExtra;
    String mesaCobroKey(int n) => MesasExtraUtils.claveCobro(n);

    final double deudaMesaTotal = mesasActivasCobro.isEmpty
        ? (alumno.mesaExtraPrecio - (alumno.mesaExtraPagado)).clamp(
            0.0,
            double.infinity,
          )
        : mesasActivasCobro.fold<double>(0, (s, m) => s + m.deuda);
    final double deudaSillasTotal =
        (alumno.sillasExtraPrecioTotal - (alumno.sillasExtraPagado ?? 0)).clamp(
          0.0,
          double.infinity,
        );
    final double totalBase =
        (alumno.montoTotalPactado -
        alumno.mesaExtraPrecio -
        alumno.sillasExtraPrecioTotal);
    final double cuotaPura = tCuotas > 0
        ? double.parse((totalBase / tCuotas).toStringAsFixed(2))
        : totalBase;

    final double deudaBaseTotal =
        (totalBase -
                (alumno.montoTotalPactado -
                    alumno.saldoDeudor -
                    (alumno.mesaExtraPagado ?? 0) -
                    (alumno.sillasExtraPagado ?? 0)))
            .clamp(0.0, double.infinity);

    final montoPagarCtrl = TextEditingController();
    final porcentajeDescuentoCtrl = TextEditingController();
    final moraMontoCobroCtrl = TextEditingController();
    final efectivoMixCtrl = TextEditingController();
    final transferMixCtrl = TextEditingController();
    final pctTransferInfoCtrl = TextEditingController(
      text: prefsMedio.getString('cobro_masivo_pct_transfer_info') ?? '0',
    );
    String transferCargoModoInit =
        prefsMedio.getString('cobro_masivo_transfer_cargo_modo') ?? 'pct';
    if (transferCargoModoInit != 'pct' && transferCargoModoInit != 'pesos') {
      transferCargoModoInit = 'pct';
    }
    final transferCargoMontoCtrl = TextEditingController(
      text: prefsMedio.getString('cobro_masivo_transfer_cargo_monto') ?? '',
    );
    final bool informarPctTransferExternoInit =
        prefsMedio.getBool('cobro_masivo_informar_pct_transfer') ?? false;

    final moraDesgloseBruto = MoraCuotaCalculator.calcularDesglose(alumno);
    final moraCobradaAjustada = MoraCuotaCalculator.moraCobradaParaFifo(
      moraCobradaHistorial: moraYaCobradaHist,
      moraCobradaOffset: alumno.moraCobradaOffset,
    );
    final moraDesglose = MoraCuotaCalculator.desglosePendiente(
      moraDesgloseBruto,
      moraCobradaAjustada,
    );
    final moraTotalDesglose = moraDesglose.fold<double>(
      0,
      (s, d) => s + d.interesBruto,
    );
    final double remanenteMora = alumno.moraPendienteTracked.clamp(
      0.0,
      double.infinity,
    );
    final List<MoraPendientePreviaDetalle> origenTracked =
        remanenteMora > 0.01
            ? MoraTrackedOrigen.inferir(
                contratoBase: alumno,
                pagos: pagosAlumno,
                trackedMonto: remanenteMora,
              )
            : const <MoraPendientePreviaDetalle>[];
    Set<int> moraCuotasSeleccionadas = {};
    final double moraPendienteEfectivo =
        MoraCuotaCalculator.moraPendienteOperativa(
          contrato: alumno,
          moraCobradaHistorial: moraYaCobradaHist,
        );
    final cronogramaModal = CronogramaCuotasUtils.lineasInformativas(
      alumno,
      moraPendientePesos: moraPendienteEfectivo,
    );
    final cuotasAtrasadasModal =
        CronogramaCuotasUtils.cuotasImpagasVencidas(alumno) > 0;

    bool pagarBase = false;
    bool pagarMesa = false;
    bool pagarSillas = false;
    bool incluirInteresCuota = false;
    bool incluirMoraRemanenteFicha = false;
    Map<String, double> montosManuales = {};
    Map<String, ModoPagoConcepto> modosPagoPorClave = {};
    List<Map<String, dynamic>> previewConceptos = [];

    bool esLineaInteresMora(Map<String, dynamic> c) =>
        c['lineKind'] == kLineKindInteresMora;

    bool esLineaCargoCanal(Map<String, dynamic> c) =>
        c['lineKind'] == 'cargo_canal_ref';

    Map<String, dynamic> lineaPreviewInteresMora(
      double monto, [
      List<MoraCuotaDetalle>? cuotasSel,
    ]) {
      final g = double.parse(
        monto.clamp(0.0, double.infinity).toStringAsFixed(2),
      );
      final detalles = cuotasSel ?? <MoraCuotaDetalle>[];
      final sumDetalles = detalles.fold<double>(
        0,
        (s, d) => s + d.interesBruto,
      );
      // Pendiente de cuotas ya pagadas: checkbox, o excedente sobre el desglose.
      double montoPendiente = 0;
      if (incluirMoraRemanenteFicha && remanenteMora > 0.01) {
        montoPendiente = remanenteMora;
      } else if (g > sumDetalles + 0.01 && remanenteMora > 0.01) {
        montoPendiente = double.parse(
          (g - sumDetalles)
              .clamp(0.0, remanenteMora)
              .toStringAsFixed(2),
        );
      }
      return MoraConceptoRotulo.construirPreviewMora(
        montoTotal: g,
        detallesCalendario: detalles,
        montoPendientePrevias: montoPendiente,
        lineKind: kLineKindInteresMora,
        detallePendiente: montoPendiente > 0.01
            ? origenTracked
            : const <MoraPendientePreviaDetalle>[],
      );
    }

    Map<String, dynamic> lineaPreviewCargoCanal(double monto) {
      final g = double.parse(
        monto.clamp(0.0, double.infinity).toStringAsFixed(2),
      );
      return {
        'concepto': 'Cargo canal / operador (ref. MP u otro)',
        'monto': g,
        'gross': g,
        'cuotas': 0,
        'lineKind': 'cargo_canal_ref',
      };
    }

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        bool informarPctTransferExterno = informarPctTransferExternoInit;
        String transferCargoModo = transferCargoModoInit;
        bool mesasGrupoExpandido = false;
        bool desgloseMesasExpandido = false;
        bool confirmandoCobro = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<MoraCuotaDetalle> moraCuotasSeleccionadasList() {
              return moraDesglose
                  .where((d) => moraCuotasSeleccionadas.contains(d.numeroCuota))
                  .toList();
            }

            double moraMontoDesdeSeleccion() {
              double total = 0;
              final sel = moraCuotasSeleccionadasList();
              if (sel.isNotEmpty) {
                total += sel.fold<double>(0, (s, d) => s + d.interesBruto);
              }
              if (incluirMoraRemanenteFicha && remanenteMora > 0.01) {
                total += remanenteMora;
              }
              return double.parse(total.toStringAsFixed(2));
            }

            void recalcMoraMontoDesdeSeleccion() {
              final total = moraMontoDesdeSeleccion();
              if (total > 0.01) {
                moraMontoCobroCtrl.text = total.toFormattedNumber();
                incluirInteresCuota = true;
              } else {
                moraMontoCobroCtrl.text = '';
                incluirInteresCuota = false;
              }
            }

            void aplicarIncluirMoraRemanenteFicha(bool? v) {
              incluirMoraRemanenteFicha = v ?? false;
              recalcMoraMontoDesdeSeleccion();
            }

            double montoMoraLineaIngresado() {
              double v = CurrencyInputFormatter.parse(moraMontoCobroCtrl.text);
              if (v < 0) v = 0;
              if (moraPendienteEfectivo > 0.01 &&
                  v > moraPendienteEfectivo + 0.01) {
                v = moraPendienteEfectivo;
              }
              return double.parse(v.toStringAsFixed(2));
            }

            bool puedeCobrarMora() => moraPendienteEfectivo > 0.01;

            void sincronizarIncluirInteresCuota() {
              if (!puedeCobrarMora()) {
                incluirInteresCuota = false;
                incluirMoraRemanenteFicha = false;
                moraCuotasSeleccionadas.clear();
                moraMontoCobroCtrl.text = '';
                return;
              }
              incluirInteresCuota = montoMoraLineaIngresado() > 0.01;
            }

            void aplicarSeleccionMoraCuota(int numeroCuota, bool? v) {
              if (v == true) {
                moraCuotasSeleccionadas.add(numeroCuota);
              } else {
                moraCuotasSeleccionadas.remove(numeroCuota);
              }
              recalcMoraMontoDesdeSeleccion();
            }

            double pctCargoInformeDesdeCampo() {
              final s = pctTransferInfoCtrl.text.replaceAll(',', '.').trim();
              return double.tryParse(s) ?? 0.0;
            }

            double montoCargoInformeDesdeCampo() {
              return CurrencyInputFormatter.parse(transferCargoMontoCtrl.text);
            }

            /// Cargo del operador sobre la parte líquida transferida (MP/comisión ref.).
            double cargoSobreLiquidoTransferencia(double liquido) {
              if (!informarPctTransferExterno || liquido <= 0.001) {
                return 0;
              }
              if (transferCargoModo == 'pesos') {
                final c = montoCargoInformeDesdeCampo();
                return double.parse(
                  c.clamp(0.0, double.infinity).toStringAsFixed(2),
                );
              }
              final pct = pctCargoInformeDesdeCampo();
              if (pct <= 0.001) return 0;
              return double.parse((liquido * pct / 100.0).toStringAsFixed(2));
            }

            /// Total mostrado en Transferencia (mixto) incluye cargo; esto recupera la parte líquida.
            double liquidoTransferenciaDesdeTotalMixto(
              double transferTotalMostrado,
            ) {
              final T = double.parse(
                transferTotalMostrado
                    .clamp(0.0, double.infinity)
                    .toStringAsFixed(2),
              );
              if (!informarPctTransferExterno) return T;
              if (transferCargoModo == 'pesos') {
                final cFix = double.parse(
                  montoCargoInformeDesdeCampo()
                      .clamp(0.0, double.infinity)
                      .toStringAsFixed(2),
                );
                return double.parse(
                  (T - cFix).clamp(0.0, double.infinity).toStringAsFixed(2),
                );
              }
              final pct = pctCargoInformeDesdeCampo();
              if (pct <= 0.001) return T;
              final denom = 1.0 + pct / 100.0;
              return double.parse(
                (T / denom).clamp(0.0, double.infinity).toStringAsFixed(2),
              );
            }

            double sumPreviewLiquidoConceptos() {
              return previewConceptos
                  .where((c) => !esLineaCargoCanal(c))
                  .fold<double>(
                    0,
                    (s, c) => s + (c['monto'] as num).toDouble(),
                  );
            }

            double liquidoTransferenciaBaseParaCargoInforme() {
              final sumL = sumPreviewLiquidoConceptos();
              if (sumL <= 0.01) return 0;
              if (modoMedioPago == 'Transferencia') return sumL;
              if (modoMedioPago == 'Mixto') {
                var e = CurrencyInputFormatter.parse(efectivoMixCtrl.text);
                if (e > sumL + 0.01) {
                  e = sumL;
                }
                return (sumL - e).clamp(0.0, double.infinity);
              }
              return 0;
            }

            void syncMixFieldsDesdeTotal() {
              if (modoMedioPago != 'Mixto') return;
              final sumL = sumPreviewLiquidoConceptos();
              if (sumL <= 0.01) {
                efectivoMixCtrl.clear();
                transferMixCtrl.clear();
                return;
              }
              var e = CurrencyInputFormatter.parse(efectivoMixCtrl.text);
              if (e > sumL + 0.01) {
                e = sumL;
              }
              final liquidoTr = (sumL - e).clamp(0.0, double.infinity);
              final cargo = informarPctTransferExterno
                  ? cargoSobreLiquidoTransferencia(liquidoTr)
                  : 0.0;
              transferMixCtrl.text = double.parse(
                (liquidoTr + cargo).toStringAsFixed(2),
              ).toFormattedNumber();
              montoPagarCtrl.text = double.parse(
                (sumL + cargo).toStringAsFixed(2),
              ).toFormattedNumber();
            }

            /// Inserta línea de cargo en preview y actualiza MONTO DE ENTREGA (y mixto).
            void finalizarPreviewConCargoCanal() {
              previewConceptos.removeWhere(esLineaCargoCanal);

              final double sumL = previewConceptos.fold<double>(
                0,
                (s, c) => s + (c['monto'] as num).toDouble(),
              );

              if (sumL <= 0.01) {
                montoPagarCtrl.clear();
                if (modoMedioPago == 'Mixto') {
                  efectivoMixCtrl.clear();
                  transferMixCtrl.clear();
                }
                return;
              }

              double liquidoTrParaCargo = sumL;
              if (modoMedioPago == 'Mixto') {
                var e = CurrencyInputFormatter.parse(efectivoMixCtrl.text);
                if (e > sumL + 0.01) {
                  e = sumL;
                }
                liquidoTrParaCargo = (sumL - e).clamp(0.0, double.infinity);
              } else if (modoMedioPago != 'Transferencia') {
                montoPagarCtrl.text = sumL.toFormattedNumber();
                return;
              }

              final cargo = informarPctTransferExterno
                  ? cargoSobreLiquidoTransferencia(liquidoTrParaCargo)
                  : 0.0;

              if (cargo > 0.01) {
                previewConceptos.add(lineaPreviewCargoCanal(cargo));
              }

              final totalMostrar = double.parse(
                (sumL + cargo).toStringAsFixed(2),
              );
              montoPagarCtrl.text = totalMostrar.toFormattedNumber();

              if (modoMedioPago == 'Mixto') {
                syncMixFieldsDesdeTotal();
              }
            }

            void aplicarEdicionTransferenciaMixto() {
              if (modoMedioPago != 'Mixto') return;
              final sumL = sumPreviewLiquidoConceptos();
              if (sumL <= 0.01) return;
              final T = CurrencyInputFormatter.parse(
                transferMixCtrl.text,
              ).clamp(0.0, double.infinity);
              final L = liquidoTransferenciaDesdeTotalMixto(T);
              final newE = (sumL - L).clamp(0.0, double.infinity);
              efectivoMixCtrl.text = newE.toFormattedNumber();
              final cargoSync = cargoSobreLiquidoTransferencia(L);
              final totalEsperadoCanal = double.parse(
                (L + cargoSync).toStringAsFixed(2),
              );
              if ((totalEsperadoCanal - T).abs() > 0.03) {
                transferMixCtrl.text = totalEsperadoCanal.toFormattedNumber();
              }
              finalizarPreviewConCargoCanal();
            }

            double montoTransferenciaParaCargoInforme() {
              return liquidoTransferenciaBaseParaCargoInforme();
            }

            int? mesaNumeroDesdeConceptoKey(String conceptoKey) {
              return MesasExtraUtils.mesaNumeroDesdeClave(conceptoKey) ??
                  (conceptoKey == 'Mesa' && cantMesas <= 1 ? 1 : null);
            }

            int totalCuotasParaClave(String conceptoKey) {
              if (conceptoKey == 'Base') return tCuotas;
              if (conceptoKey == 'Sillas') return sCuotas;
              return mCuotas;
            }

            double grossHistoricoParaClave(String conceptoKey) {
              return historicoGrossPorClave[conceptoKey] ??
                  (conceptoKey == 'Mesa'
                      ? historicoGrossPorClave['Mesa'] ?? 0.0
                      : 0.0);
            }

            List<Map<String, dynamic>> buildPreviewLineasConcepto({
              required String conceptoKey,
              required String label,
              required double gross,
              required double net,
              required double qPura,
            }) {
              final modo = modosPagoPorClave[conceptoKey];
              final tipo = modo?.tipo ?? ModoPagoConceptoTipo.cuotas;
              final lineas = lineasPreviewDesglosePlan(
                modo: tipo,
                cuotasSeleccionadas: modo?.cuotasSeleccionadas,
                grossTotal: gross,
                cuotaPura: qPura,
                totalCuotas: totalCuotasParaClave(conceptoKey),
                grossHistorico: grossHistoricoParaClave(conceptoKey),
                etiqueta: label,
              );

              if (lineas.isEmpty) {
                return [
                  {
                    'concepto': label,
                    'monto': double.parse(net.toStringAsFixed(2)),
                    'gross': double.parse(gross.toStringAsFixed(2)),
                    'cuotas': 0,
                  },
                ];
              }

              if (lineas.length == 1) {
                final l = lineas.first;
                final mesaN = mesaNumeroDesdeConceptoKey(conceptoKey);
                return [
                  {
                    'concepto': l.concepto,
                    if (l.subtexto != null) 'subtexto': l.subtexto,
                    'monto': double.parse(net.toStringAsFixed(2)),
                    'gross': double.parse(gross.toStringAsFixed(2)),
                    'cuotas': l.cuotasLiquidadas,
                    if (mesaN != null) 'mesaN': mesaN,
                  },
                ];
              }

              var netAcum = 0.0;
              final out = <Map<String, dynamic>>[];
              for (var i = 0; i < lineas.length; i++) {
                final l = lineas[i];
                double netLine;
                if (i == lineas.length - 1) {
                  netLine = double.parse((net - netAcum).toStringAsFixed(2));
                } else if (gross > 0.011) {
                  netLine = double.parse(
                    (net * (l.gross / gross)).toStringAsFixed(2),
                  );
                  netAcum += netLine;
                } else {
                  netLine = 0;
                }
                final mesaN = mesaNumeroDesdeConceptoKey(conceptoKey);
                out.add({
                  'concepto': l.concepto,
                  if (l.subtexto != null) 'subtexto': l.subtexto,
                  'monto': netLine,
                  'gross': l.gross,
                  'cuotas': l.cuotasLiquidadas,
                  if (mesaN != null) 'mesaN': mesaN,
                });
              }
              return out;
            }

            Future<double?> preguntarMontoParcial(
              String titulo,
              double deudaMax,
            ) async {
              final ctrl = TextEditingController();
              return showDialog<double>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    'Entrega Parcial: $titulo',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deuda pendiente: ${deudaMax.toCurrency()}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: ctrl,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('CANCELAR'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final val = CurrencyInputFormatter.parse(ctrl.text);
                        if (val > 0 &&
                            (val <= (deudaMax + 0.01) || deudaMax == 0)) {
                          Navigator.pop(ctx, val);
                        } else {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Monto inválido')),
                          );
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
              if (!manually) {
                montosManuales.clear();
                modosPagoPorClave.clear();
              }

              final double dtoPerc =
                  double.tryParse(porcentajeDescuentoCtrl.text) ?? 0.0;

              if (manually && montosManuales.isNotEmpty) {
                montosManuales.forEach((key, gross) {
                  final double net = CalculadoraFinanciera.brutoANeto(
                    gross,
                    dtoPerc,
                  );
                  double qPura = 0;
                  String label = key;

                  if (key == 'Base') {
                    qPura = cuotaPura;
                    label = 'Cuota Base';
                  } else if (key.startsWith('Mesa:')) {
                    final n = int.tryParse(key.split(':').last) ?? 1;
                    MesaExtraItem item;
                    try {
                      item = mesasActivasCobro.firstWhere((m) => m.n == n);
                    } catch (_) {
                      item = mesasEstadoList.firstWhere(
                        (m) => m.n == n,
                        orElse: () => MesaExtraItem(
                          n: n,
                          precio: alumno.precioUnitarioMesaExtra,
                        ),
                      );
                    }
                    qPura = item.cuotaPura(mCuotas);
                    label = MesasExtraUtils.labelCobro(n, cantMesas);
                  } else if (key == 'Mesa') {
                    qPura =
                        alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1);
                    label = MesasExtraUtils.labelCobro(1, cantMesas);
                  } else if (key == 'Sillas') {
                    qPura =
                        alumno.sillasExtraPrecioTotal /
                        (sCuotas > 0 ? sCuotas : 1);
                    label = 'Sillas Extras';
                  }

                  previewConceptos.addAll(
                    buildPreviewLineasConcepto(
                      conceptoKey: key,
                      label: label,
                      gross: gross,
                      net: net,
                      qPura: qPura,
                    ),
                  );
                });
                final bool cobrandoBaseManual =
                    montosManuales.containsKey('Base') &&
                    ((montosManuales['Base'] ?? 0) > 0.01);
                if (incluirInteresCuota &&
                    (cobrandoBaseManual || deudaBaseTotal <= 0.01) &&
                    moraPendienteEfectivo > 0.01) {
                  final mm = montoMoraLineaIngresado();
                  if (mm > 0.01) {
                    previewConceptos.add(
                      lineaPreviewInteresMora(
                        mm,
                        moraCuotasSeleccionadasList(),
                      ),
                    );
                  }
                }
              }

              pagarSillas = previewConceptos.any(
                (c) =>
                    !esLineaInteresMora(c) &&
                    !esLineaCargoCanal(c) &&
                    c['concepto'].toString().contains('Sillas'),
              );
              pagarMesa = previewConceptos.any(
                (c) =>
                    !esLineaInteresMora(c) &&
                    !esLineaCargoCanal(c) &&
                    c['concepto'].toString().contains('Mesa'),
              );
              pagarBase = previewConceptos.any(
                (c) =>
                    !esLineaInteresMora(c) &&
                    !esLineaCargoCanal(c) &&
                    c['concepto'].toString().contains('Cuota'),
              );

              if (!puedeCobrarMora()) {
                incluirInteresCuota = false;
                incluirMoraRemanenteFicha = false;
                moraCuotasSeleccionadas.clear();
                moraMontoCobroCtrl.text = '';
              } else {
                sincronizarIncluirInteresCuota();
              }
              finalizarPreviewConCargoCanal();
            }

            void recalcularDesdeChecks() {
              previewConceptos.clear();
              double totalAcumuladoNeto = 0;
              final double dtoPerc =
                  double.tryParse(porcentajeDescuentoCtrl.text) ?? 0.0;

              void procesarConcepto(
                String key,
                String label,
                double deudaTotal,
                double qPura,
              ) {
                double gross = montosManuales[key] ?? deudaTotal;
                double net = CalculadoraFinanciera.brutoANeto(gross, dtoPerc);

                previewConceptos.addAll(
                  buildPreviewLineasConcepto(
                    conceptoKey: key,
                    label: label,
                    gross: gross,
                    net: net,
                    qPura: qPura,
                  ),
                );
                totalAcumuladoNeto += net;
              }

              if (pagarBase && deudaBaseTotal > 0.01) {
                procesarConcepto(
                  'Base',
                  'Cuota Base',
                  deudaBaseTotal,
                  cuotaPura,
                );
              }
              if (mesasActivasCobro.isEmpty &&
                  pagarMesa &&
                  deudaMesaTotal > 0.01) {
                procesarConcepto(
                  'Mesa',
                  MesasExtraUtils.labelCobro(1, cantMesas),
                  deudaMesaTotal,
                  alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1),
                );
              } else {
                for (final mesa in mesasActivasCobro) {
                  final key = mesaCobroKey(mesa.n);
                  if (!montosManuales.containsKey(key)) continue;
                  final label = MesasExtraUtils.labelCobro(mesa.n, cantMesas);
                  procesarConcepto(
                    key,
                    label,
                    mesa.deuda,
                    mesa.cuotaPura(mCuotas),
                  );
                }
              }
              if (pagarSillas && deudaSillasTotal > 0.01) {
                procesarConcepto(
                  'Sillas',
                  'Sillas Extras',
                  deudaSillasTotal,
                  alumno.sillasExtraPrecioTotal / (sCuotas > 0 ? sCuotas : 1),
                );
              }

              if (puedeCobrarMora() && moraPendienteEfectivo > 0.01) {
                final mm = montoMoraLineaIngresado();
                if (mm > 0.01) {
                  previewConceptos.add(
                    lineaPreviewInteresMora(mm, moraCuotasSeleccionadasList()),
                  );
                  totalAcumuladoNeto += mm;
                }
              }

              sincronizarIncluirInteresCuota();
              finalizarPreviewConCargoCanal();
            }

            Future<void> emitirResumenAbonarPdf() async {
              finalizarPreviewConCargoCanal();

              if (previewConceptos.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Seleccioná al menos un concepto antes de generar el resumen.',
                    ),
                    backgroundColor: Colors.orangeAccent,
                  ),
                );
                return;
              }

              final double sumLiquido = sumPreviewLiquidoConceptos();
              final double cargoPreview = previewConceptos
                  .where(esLineaCargoCanal)
                  .fold<double>(
                    0,
                    (s, c) => s + (c['monto'] as num).toDouble(),
                  );
              final double totalEsperado = double.parse(
                (sumLiquido + cargoPreview).toStringAsFixed(2),
              );
              final double totalCampo = CurrencyInputFormatter.parse(
                montoPagarCtrl.text,
              );

              if (sumLiquido <= 0.01) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'El resumen necesita al menos un monto de liquidación.',
                    ),
                    backgroundColor: Colors.orangeAccent,
                  ),
                );
                return;
              }

              if ((totalEsperado - totalCampo).abs() > 0.03) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Los montos no cierran (liquidación ${sumLiquido.toCurrency()} '
                      '+ cargo ${cargoPreview.toCurrency()} ≠ total '
                      '${totalCampo.toCurrency()}). Revisá el desglose.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              final conceptosFinales = conceptosFinalesDesdePreviewMasivo(
                previewConceptos: previewConceptos,
                esLineaCargoCanal: esLineaCargoCanal,
                esLineaInteresMora: esLineaInteresMora,
                cPagadas: cPagadas,
                tCuotas: tCuotas,
                mPagadas: mPagadas,
                mCuotas: mCuotas,
                sPagadas: sPagadas,
                sCuotas: sCuotas,
                cantMesas: cantMesas,
              );

              final double moraIncluida = previewConceptos
                  .where(esLineaInteresMora)
                  .fold<double>(
                    0,
                    (s, c) => s + (c['monto'] as num).toDouble(),
                  );
              final double? moraNoIncluida =
                  moraPendienteEfectivo - moraIncluida > 0.01
                  ? double.parse(
                      (moraPendienteEfectivo - moraIncluida)
                          .clamp(0.0, double.infinity)
                          .toStringAsFixed(2),
                    )
                  : null;

              final double pctCargoInforme =
                  double.tryParse(
                    pctTransferInfoCtrl.text.replaceAll(',', '.').trim(),
                  ) ??
                  0;
              final double montoCargoInformeParsed =
                  CurrencyInputFormatter.parse(transferCargoMontoCtrl.text);

              double? efDet;
              double? trDet;
              double? trCanal;
              if (modoMedioPago == 'Mixto') {
                efDet = CurrencyInputFormatter.parse(efectivoMixCtrl.text);
                trCanal = CurrencyInputFormatter.parse(
                  transferMixCtrl.text,
                ).clamp(0.0, double.infinity);
                trDet = trCanal;
              } else if (modoMedioPago == 'Transferencia' &&
                  cargoPreview > 0.01) {
                trCanal = totalEsperado;
              }

              final double pctDescuentoResumen =
                  double.tryParse(
                    porcentajeDescuentoCtrl.text.replaceAll(',', '.').trim(),
                  ) ??
                  0;

              try {
                await PdfService.generarResumenAbonarAlumno(
                  alumno: alumno,
                  evento: widget.evento,
                  saldoActualPlan: alumno.saldoDeudor,
                  subtotalLiquidacion: sumLiquido,
                  totalAbonar: totalEsperado,
                  conceptosLineas: conceptosFinales,
                  medioPago: modoMedioPago,
                  montoEfectivoDetalle: efDet,
                  montoTransferenciaDetalle: trDet,
                  montoTransferenciaCanal: trCanal,
                  informarCargoTransferenciaExterno: informarPctTransferExterno,
                  porcentajeCargoTransferenciaExterno:
                      informarPctTransferExterno &&
                          transferCargoModo == 'pct' &&
                          pctCargoInforme > 0.01
                      ? pctCargoInforme
                      : null,
                  montoCargoTransferenciaInformado:
                      informarPctTransferExterno &&
                          transferCargoModo == 'pesos' &&
                          montoCargoInformeParsed > 0.01
                      ? montoCargoInformeParsed
                      : null,
                  moraPendienteNoIncluida: moraNoIncluida,
                  porcentajeDescuentoLiquidacion: pctDescuentoResumen,
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al generar resumen PDF: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: Color(0xFFD4AF37)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cobro: ${alumno.nombreAlumno}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
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
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.withValues(alpha: 0.1),
                              Colors.blue.withValues(alpha: 0.02),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SALDO GLOBAL PENDIENTE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.blue,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  alumno.saldoDeudor.toCurrency(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 24,
                                  ),
                                ),
                              ],
                            ),
                            const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: Colors.blue,
                              size: 32,
                            ),
                          ],
                        ),
                      ),
                      if (cronogramaModal.tieneAlguna)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cuotasAtrasadasModal
                                  ? Colors.red.withValues(alpha: 0.06)
                                  : Colors.blueGrey.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: cuotasAtrasadasModal
                                    ? Colors.red.withValues(alpha: 0.25)
                                    : Colors.blueGrey.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (cuotasAtrasadasModal)
                                  Text(
                                    'CUOTAS ATRASADAS EN EL PLAN',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.red.shade800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                if (cuotasAtrasadasModal &&
                                    cronogramaModal.cuotaPendiente != null)
                                  const SizedBox(height: 6),
                                if (cronogramaModal.cuotaPendiente != null)
                                  Text(
                                    cronogramaModal.cuotaPendiente!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (cronogramaModal.proximoVencimiento != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      cronogramaModal.proximoVencimiento!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                if (cronogramaModal.moraCongeladaHasta != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      cronogramaModal.moraCongeladaHasta!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blueGrey.shade700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (moraPendienteEfectivo > 0.01)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MORA REMANENTE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.orange.shade900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Total: ${moraPendienteEfectivo.toCurrency()}${moraYaCobradaHist > 0.01 ? ' · Cobrado antes (historial): ${moraYaCobradaHist.toCurrency()}' : ''}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                                if (moraTotalDesglose > 0.01 ||
                                    remanenteMora > 0.01)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      [
                                        if (moraTotalDesglose > 0.01)
                                          'Cuotas vencidas: ${moraTotalDesglose.toCurrency()}',
                                        if (remanenteMora > 0.01)
                                          MoraConceptoRotulo.resumenPendientePrevias(
                                            remanenteMora.toCurrency(),
                                            detalle: origenTracked,
                                          ),
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                if (moraDesglose.isNotEmpty &&
                                    moraResumen.diasMora > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Días de atraso (cuotas vencidas): ${moraResumen.diasMora}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  )
                                else if (moraDesglose.isEmpty &&
                                    remanenteMora > 0.01 &&
                                    moraResumen.fechaVencimientoProximaCuota !=
                                        null &&
                                    moraResumen.proximaCuotaNumero != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Próx. venc. cuota base: ${ArTime.formatFechaCorta(moraResumen.fechaVencimientoProximaCuota!)} (${moraResumen.proximaCuotaNumero}/$tCuotas)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'Según ficha e historial del alumno. No forma parte del saldo del plan. Podés abonar un monto parcial.',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (puedeCobrarMora()) ...[
                                  if (moraDesglose.isNotEmpty) ...[
                                    Text(
                                      'POR CUOTA VENCIDA',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.orange.shade900,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ...moraDesglose.map((d) {
                                      final sel = moraCuotasSeleccionadas
                                          .contains(d.numeroCuota);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 2,
                                        ),
                                        child: CheckboxListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          value: sel,
                                          onChanged: (v) {
                                            setModalState(() {
                                              aplicarSeleccionMoraCuota(
                                                d.numeroCuota,
                                                v,
                                              );
                                              recalcularDesdeChecks();
                                            });
                                          },
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Cuota ${d.numeroCuota} (${d.mesLabel}) — vto. ${ArTime.formatFechaCorta(d.vencimiento)} — ${d.diasMora} días',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        Colors.orange.shade900,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                d.interesBruto.toCurrency(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w900,
                                                  color: sel
                                                      ? Colors.orange.shade900
                                                      : Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                  if (remanenteMora > 0.01) ...[
                                    if (moraDesglose.isNotEmpty)
                                      const SizedBox(height: 4),
                                    CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      value: incluirMoraRemanenteFicha,
                                      onChanged: (v) {
                                        setModalState(() {
                                          aplicarIncluirMoraRemanenteFicha(v);
                                          recalcularDesdeChecks();
                                        });
                                      },
                                      title: Text(
                                        MoraConceptoRotulo.checkboxPendientePrevias(
                                          remanenteMora.toCurrency(),
                                          detalle: origenTracked,
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.orange.shade900,
                                        ),
                                      ),
                                      subtitle: Text(
                                        origenTracked.length == 1
                                            ? origenTracked.first.subtextoDetalle
                                            : MoraConceptoRotulo.checkboxSubtitle,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (incluirInteresCuota) ...[
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: moraMontoCobroCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        CurrencyInputFormatter(),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Monto mora a cobrar ahora',
                                        helperText:
                                            'Máx. ${moraPendienteEfectivo.toCurrency()} — pago parcial permitido',
                                        prefixIcon: Icon(
                                          Icons.attach_money_rounded,
                                          color: Colors.orange.shade800,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: Colors.orange.withValues(
                                          alpha: 0.05,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      onChanged: (_) => setModalState(() {
                                        sincronizarIncluirInteresCuota();
                                        recalcularDesdeChecks();
                                      }),
                                    ),
                                  ],
                                ],
                              ],
                            ),
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
                            final choice = await _mostrarOpcionesPago(
                              context,
                              'Cuota Base',
                              deudaBaseTotal,
                              cuotaPura: cuotaPura,
                              totalCuotas: tCuotas,
                              grossHistorico:
                                  historicoGrossPorClave['Base'] ?? 0.0,
                            );
                            await _aplicarResultadoOpcionPago(
                              context: context,
                              setModalState: setModalState,
                              montosManuales: montosManuales,
                              modosPagoPorClave: modosPagoPorClave,
                              mapKey: 'Base',
                              tituloParcial: 'Cuota Base',
                              deuda: deudaBaseTotal,
                              resultado: choice,
                              onSelected: (sel) => pagarBase = sel,
                              preguntarMontoParcial: preguntarMontoParcial,
                              recalcular: recalcularDesdeChecks,
                            );
                          } else {
                            setModalState(() {
                              pagarBase = false;
                              incluirInteresCuota = false;
                              incluirMoraRemanenteFicha = false;
                              moraCuotasSeleccionadas.clear();
                              moraMontoCobroCtrl.text = '';
                              modosPagoPorClave.remove('Base');
                              montosManuales['Base'] = deudaBaseTotal;
                            });
                          }
                          recalcularDesdeChecks();
                        },
                      ),
                      if (deudaMesaTotal > 0.01)
                        ...(mesasActivasCobro.isEmpty
                            ? [
                                _buildConceptoTile(
                                  titulo: 'MESA EXTRA',
                                  deuda: deudaMesaTotal,
                                  isDark:
                                      Theme.of(context).brightness ==
                                      Brightness.dark,
                                  selected: pagarMesa,
                                  montoManual: montosManuales['Mesa'],
                                  onChanged: (v) async {
                                    await _onMesaExtraCobroChanged(
                                      context: context,
                                      v: v,
                                      mesa: null,
                                      mesaLabel: 'Mesa Extra',
                                      mesaKeyStr: 'Mesa',
                                      deuda: deudaMesaTotal,
                                      cuotaPura:
                                          alumno.mesaExtraPrecio /
                                          (mCuotas > 0 ? mCuotas : 1),
                                      totalCuotasPlan: mCuotas,
                                      grossHistorico:
                                          historicoGrossPorClave['Mesa'] ?? 0.0,
                                      setModalState: setModalState,
                                      montosManuales: montosManuales,
                                      modosPagoPorClave: modosPagoPorClave,
                                      onPagarMesaChanged: (val) =>
                                          pagarMesa = val,
                                      recalcular: recalcularDesdeChecks,
                                      preguntarMontoParcial:
                                          preguntarMontoParcial,
                                      mostrarOpcionesPago: _mostrarOpcionesPago,
                                    );
                                  },
                                ),
                              ]
                            : MesasExtraUtils.usarUiCompactaMesasCobro(
                                mesasActivasCobro.length,
                              )
                            ? [
                                _buildMesasExtraGrupoCompacto(
                                  context: context,
                                  isDark:
                                      Theme.of(context).brightness ==
                                      Brightness.dark,
                                  mesas: mesasActivasCobro,
                                  cantMesas: cantMesas,
                                  deudaMesaTotal: deudaMesaTotal,
                                  montosManuales: montosManuales,
                                  expandido: mesasGrupoExpandido,
                                  onToggleExpandido: () => setModalState(
                                    () => mesasGrupoExpandido =
                                        !mesasGrupoExpandido,
                                  ),
                                  onElegirMesas: () => _mostrarDialogoElegirMesasExtra(
                                    context: context,
                                    mesas: mesasActivasCobro,
                                    cantMesas: cantMesas,
                                    montosManuales: montosManuales,
                                    setModalState: setModalState,
                                    onMesaChanged: (mesa, v) =>
                                        _onMesaExtraCobroChanged(
                                          context: context,
                                          v: v,
                                          mesa: mesa,
                                          mesaLabel: MesasExtraUtils.labelCobro(
                                            mesa.n,
                                            cantMesas,
                                          ),
                                          mesaKeyStr: mesaCobroKey(mesa.n),
                                          deuda: mesa.deuda,
                                          cuotaPura: mesa.cuotaPura(mCuotas),
                                          totalCuotasPlan: mCuotas,
                                          grossHistorico:
                                              historicoGrossPorClave[mesaCobroKey(
                                                mesa.n,
                                              )] ??
                                              historicoGrossPorClave['Mesa'] ??
                                              0.0,
                                          setModalState: setModalState,
                                          montosManuales: montosManuales,
                                          modosPagoPorClave: modosPagoPorClave,
                                          onPagarMesaChanged: (val) =>
                                              pagarMesa = val,
                                          recalcular: recalcularDesdeChecks,
                                          preguntarMontoParcial:
                                              preguntarMontoParcial,
                                          mostrarOpcionesPago:
                                              _mostrarOpcionesPago,
                                        ),
                                  ),
                                  onMesaChanged: (mesa, v) =>
                                      _onMesaExtraCobroChanged(
                                        context: context,
                                        v: v,
                                        mesa: mesa,
                                        mesaLabel: MesasExtraUtils.labelCobro(
                                          mesa.n,
                                          cantMesas,
                                        ),
                                        mesaKeyStr: mesaCobroKey(mesa.n),
                                        deuda: mesa.deuda,
                                        cuotaPura: mesa.cuotaPura(mCuotas),
                                        totalCuotasPlan: mCuotas,
                                        grossHistorico:
                                            historicoGrossPorClave[mesaCobroKey(
                                              mesa.n,
                                            )] ??
                                            historicoGrossPorClave['Mesa'] ??
                                            0.0,
                                        setModalState: setModalState,
                                        montosManuales: montosManuales,
                                        modosPagoPorClave: modosPagoPorClave,
                                        onPagarMesaChanged: (val) =>
                                            pagarMesa = val,
                                        recalcular: recalcularDesdeChecks,
                                        preguntarMontoParcial:
                                            preguntarMontoParcial,
                                        mostrarOpcionesPago:
                                            _mostrarOpcionesPago,
                                      ),
                                ),
                              ]
                            : mesasActivasCobro.map((mesa) {
                                final key = mesaCobroKey(mesa.n);
                                final label = MesasExtraUtils.tituloCobro(
                                  mesa.n,
                                  cantMesas,
                                );
                                return _buildConceptoTile(
                                  titulo: label,
                                  deuda: mesa.deuda,
                                  isDark:
                                      Theme.of(context).brightness ==
                                      Brightness.dark,
                                  selected: montosManuales.containsKey(key),
                                  montoManual: montosManuales[key],
                                  onChanged: (v) async {
                                    await _onMesaExtraCobroChanged(
                                      context: context,
                                      v: v,
                                      mesa: mesa,
                                      mesaLabel: MesasExtraUtils.labelCobro(
                                        mesa.n,
                                        cantMesas,
                                      ),
                                      mesaKeyStr: key,
                                      deuda: mesa.deuda,
                                      cuotaPura: mesa.cuotaPura(mCuotas),
                                      totalCuotasPlan: mCuotas,
                                      grossHistorico:
                                          historicoGrossPorClave[key] ??
                                          historicoGrossPorClave['Mesa'] ??
                                          0.0,
                                      setModalState: setModalState,
                                      montosManuales: montosManuales,
                                      modosPagoPorClave: modosPagoPorClave,
                                      onPagarMesaChanged: (val) =>
                                          pagarMesa = val,
                                      recalcular: recalcularDesdeChecks,
                                      preguntarMontoParcial:
                                          preguntarMontoParcial,
                                      mostrarOpcionesPago: _mostrarOpcionesPago,
                                    );
                                  },
                                );
                              })),
                      if (deudaSillasTotal > 0.01)
                        _buildConceptoTile(
                          titulo: 'SILLAS EXTRAS',
                          deuda: deudaSillasTotal,
                          isDark:
                              Theme.of(context).brightness == Brightness.dark,
                          selected: pagarSillas,
                          montoManual: montosManuales['Sillas'],
                          onChanged: (v) async {
                            if (v == true) {
                              final pureSilla =
                                  alumno.sillasExtraPrecioTotal /
                                  (sCuotas > 0 ? sCuotas : 1);
                              final choice = await _mostrarOpcionesPago(
                                context,
                                'Sillas Extras',
                                deudaSillasTotal,
                                cuotaPura: pureSilla,
                                totalCuotas: sCuotas,
                                grossHistorico:
                                    historicoGrossPorClave['Sillas'] ?? 0.0,
                              );
                              await _aplicarResultadoOpcionPago(
                                context: context,
                                setModalState: setModalState,
                                montosManuales: montosManuales,
                                modosPagoPorClave: modosPagoPorClave,
                                mapKey: 'Sillas',
                                tituloParcial: 'Sillas Extras',
                                deuda: deudaSillasTotal,
                                resultado: choice,
                                onSelected: (sel) => pagarSillas = sel,
                                preguntarMontoParcial: preguntarMontoParcial,
                                recalcular: recalcularDesdeChecks,
                              );
                            } else {
                              setModalState(() {
                                pagarSillas = false;
                                modosPagoPorClave.remove('Sillas');
                                montosManuales.remove('Sillas');
                              });
                            }
                            recalcularDesdeChecks();
                          },
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
                                const Text(
                                  'MONTO DE ENTREGA:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    color: Colors.grey,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: montoPagarCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [CurrencyInputFormatter()],
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFD4AF37),
                                  ),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.attach_money_rounded,
                                      color: Color(0xFFD4AF37),
                                    ),
                                    hintText: '0,00',
                                    filled: true,
                                    fillColor: const Color(
                                      0xFFD4AF37,
                                    ).withValues(alpha: 0.05),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onChanged: (val) {
                                    final m = CurrencyInputFormatter.parse(val);
                                    setModalState(() {
                                      recalcularDesdeMonto(m);
                                      pagarBase = previewConceptos.any(
                                        (c) =>
                                            !esLineaInteresMora(c) &&
                                            !esLineaCargoCanal(c) &&
                                            c['concepto'].toString().contains(
                                              'Cuota',
                                            ),
                                      );
                                      pagarMesa = previewConceptos.any(
                                        (c) =>
                                            !esLineaInteresMora(c) &&
                                            !esLineaCargoCanal(c) &&
                                            c['concepto'].toString().contains(
                                              'Mesa',
                                            ),
                                      );
                                      pagarSillas = previewConceptos.any(
                                        (c) =>
                                            !esLineaInteresMora(c) &&
                                            !esLineaCargoCanal(c) &&
                                            c['concepto'].toString().contains(
                                              'Sillas',
                                            ),
                                      );
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
                                const Text(
                                  'DESC. LIQUIDACIÓN:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    color: Colors.blue,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: porcentajeDescuentoCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.percent_rounded,
                                      color: Colors.blue,
                                    ),
                                    hintText: '0',
                                    filled: true,
                                    fillColor: Colors.blue.withValues(
                                      alpha: 0.05,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
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
                      if (modoMedioPago == 'Transferencia' &&
                          informarPctTransferExterno)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Builder(
                            builder: (ctx) {
                              final liq = sumPreviewLiquidoConceptos();
                              if (liq <= 0.01) {
                                return const SizedBox.shrink();
                              }
                              final cargo = cargoSobreLiquidoTransferencia(liq);
                              if (cargo <= 0.01) {
                                return const SizedBox.shrink();
                              }
                              final canal = double.parse(
                                (liq + cargo).toStringAsFixed(2),
                              );
                              return Text(
                                'Transferencia total canal: ${canal.toCurrency()} '
                                '(liquidación ${liq.toCurrency()} + cargo '
                                '${cargo.toCurrency()}). Mismo total que MONTO DE ENTREGA.',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue.shade800,
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: modoMedioPago,
                        decoration: InputDecoration(
                          labelText: 'Medio de pago',
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_rounded,
                          ),
                          filled: true,
                          fillColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? Colors.black26
                              : Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Efectivo',
                            child: Text('Efectivo'),
                          ),
                          DropdownMenuItem(
                            value: 'Transferencia',
                            child: Text('Transferencia'),
                          ),
                          DropdownMenuItem(
                            value: 'Mixto',
                            child: Text('Mixto (efectivo + transferencia)'),
                          ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          await prefsMedio.setString(
                            'medio_pago_cobro_masivo',
                            v,
                          );
                          setModalState(() {
                            modoMedioPago = v;
                            if (v == 'Mixto') {
                              previewConceptos.removeWhere(esLineaCargoCanal);
                              final sumL = previewConceptos.fold<double>(
                                0,
                                (s, c) => s + (c['monto'] as num).toDouble(),
                              );
                              if (sumL > 0.01) {
                                final mitad = sumL / 2;
                                efectivoMixCtrl.text = mitad
                                    .toFormattedNumber();
                              } else {
                                final t = CurrencyInputFormatter.parse(
                                  montoPagarCtrl.text,
                                );
                                if (t > 0.01) {
                                  final mitad = t / 2;
                                  efectivoMixCtrl.text = mitad
                                      .toFormattedNumber();
                                } else {
                                  efectivoMixCtrl.clear();
                                  transferMixCtrl.clear();
                                }
                              }
                              finalizarPreviewConCargoCanal();
                            } else {
                              efectivoMixCtrl.clear();
                              transferMixCtrl.clear();
                              finalizarPreviewConCargoCanal();
                            }
                          });
                        },
                      ),
                      if (modoMedioPago == 'Mixto') ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: efectivoMixCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: InputDecoration(
                                  labelText: 'Efectivo',
                                  prefixIcon: const Icon(
                                    Icons.payments_rounded,
                                    color: Color(0xFFD4AF37),
                                  ),
                                  filled: true,
                                  fillColor: const Color(
                                    0xFFD4AF37,
                                  ).withValues(alpha: 0.06),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (_) => setModalState(
                                  finalizarPreviewConCargoCanal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: transferMixCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: InputDecoration(
                                  labelText: 'Transferencia (total canal)',
                                  prefixIcon: const Icon(
                                    Icons.account_balance_rounded,
                                    color: Colors.blue,
                                  ),
                                  filled: true,
                                  fillColor: Colors.blue.withValues(
                                    alpha: 0.06,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (_) {
                                  setModalState(
                                    aplicarEdicionTransferenciaMixto,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Liquidación: efectivo + transferencia líquida = monto de entrega. '
                            'El campo Transferencia muestra el total por canal (líquido + cargo operador si aplica).',
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                      if (modoMedioPago == 'Transferencia' ||
                          modoMedioPago == 'Mixto') ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: informarPctTransferExterno,
                          onChanged: (v) => setModalState(() {
                            informarPctTransferExterno = v ?? false;
                            recalcularDesdeChecks();
                          }),
                          title: const Text(
                            'Mostrar costo estimado del operador sobre transferencia',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            'En mixto, Transferencia = líquido + cargo ref. La liquidación sigue siendo el monto de entrega.',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        if (informarPctTransferExterno) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment<String>(
                                    value: 'pct',
                                    label: Text('Por %'),
                                    icon: Icon(Icons.percent_rounded, size: 18),
                                  ),
                                  ButtonSegment<String>(
                                    value: 'pesos',
                                    label: Text(r'Por $'),
                                    icon: Icon(
                                      Icons.payments_outlined,
                                      size: 18,
                                    ),
                                  ),
                                ],
                                selected: {transferCargoModo},
                                onSelectionChanged: (Set<String> sel) {
                                  if (sel.isEmpty) return;
                                  setModalState(() {
                                    transferCargoModo = sel.first;
                                    recalcularDesdeChecks();
                                  });
                                },
                              ),
                            ),
                          ),
                          if (transferCargoModo == 'pct')
                            TextField(
                              controller: pctTransferInfoCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: '% informativo (p. ej. comisión MP)',
                                prefixIcon: const Icon(
                                  Icons.price_change_outlined,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.black26
                                    : Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (_) =>
                                  setModalState(recalcularDesdeChecks),
                            )
                          else
                            TextField(
                              controller: transferCargoMontoCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [CurrencyInputFormatter()],
                              decoration: InputDecoration(
                                labelText:
                                    'Monto estimado del cargo (referencia)',
                                hintText: '0,00',
                                prefixText: r'$ ',
                                prefixIcon: const Icon(
                                  Icons.attach_money_rounded,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.black26
                                    : Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (_) =>
                                  setModalState(recalcularDesdeChecks),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Builder(
                              builder: (ctx) {
                                final mt = double.parse(
                                  montoTransferenciaParaCargoInforme()
                                      .clamp(0.0, double.infinity)
                                      .toStringAsFixed(2),
                                );
                                if (mt <= 0.01) {
                                  return Text(
                                    modoMedioPago == 'Mixto'
                                        ? 'Completá el monto en transferencia para ver la referencia en tiempo real.'
                                        : 'Completá el monto de entrega para ver la referencia en tiempo real.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade700,
                                    ),
                                  );
                                }
                                if (transferCargoModo == 'pct') {
                                  final pctRaw = pctCargoInformeDesdeCampo();
                                  final pct = double.parse(
                                    pctRaw
                                        .clamp(0.0, 1000.0)
                                        .toStringAsFixed(4),
                                  );
                                  if (pct <= 0.001) {
                                    return Text(
                                      'Ingresá el % arriba para ver cuánto representa sobre ${mt.toCurrency()} en transferencia.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey.shade700,
                                      ),
                                    );
                                  }
                                  final estimado = double.parse(
                                    (mt * pct / 100.0).toStringAsFixed(2),
                                  );
                                  final pctStr =
                                      (pct - pct.round()).abs() < 0.001
                                      ? pct.round().toString()
                                      : pct.toStringAsFixed(2);
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(
                                        alpha: 0.06,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.blue.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Costo estimado sobre transferencia',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.4,
                                            color: Colors.blue.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$pctStr% de ${mt.toCurrency()} ≈ ${estimado.toCurrency()}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.blue.shade900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Incluido en MONTO DE ENTREGA y en el desglose. '
                                          'Al confirmar, solo la liquidación actualiza saldos; el cargo es referencia de canal.',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                final montoFijo = double.parse(
                                  montoCargoInformeDesdeCampo()
                                      .clamp(0.0, double.infinity)
                                      .toStringAsFixed(2),
                                );
                                if (montoFijo <= 0.01) {
                                  return Text(
                                    'Ingresá el monto en pesos arriba para fijar la referencia (equivale a un % sobre ${mt.toCurrency()}).',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade700,
                                    ),
                                  );
                                }
                                final eqPct = mt > 0.01
                                    ? (100.0 * montoFijo / mt)
                                    : 0.0;
                                final eqStr = eqPct > 0.01 && eqPct <= 999.0
                                    ? '~${eqPct.toStringAsFixed(1)}% de ${mt.toCurrency()}'
                                    : '';
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.blue.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Costo estimado sobre transferencia',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        eqStr.isNotEmpty
                                            ? '${montoFijo.toCurrency()} ($eqStr)'
                                            : montoFijo.toCurrency(),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Incluido en MONTO DE ENTREGA y en el desglose. '
                                        'Al confirmar, solo la liquidación actualiza saldos; el cargo es referencia de canal.',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                      if (montoPagarCtrl.text.isNotEmpty &&
                          CurrencyInputFormatter.parse(montoPagarCtrl.text) >
                              0.01)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(16),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'DESGLOSE LIMPIO',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      color: Colors.grey,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final total =
                                          CurrencyInputFormatter.parse(
                                            montoPagarCtrl.text,
                                          );
                                      final double interesDist =
                                          (incluirInteresCuota &&
                                              moraPendienteEfectivo > 0.01)
                                          ? montoMoraLineaIngresado()
                                          : 0.0;
                                      final capitalParaDialogo =
                                          (total - interesDist).clamp(
                                            0.0,
                                            double.infinity,
                                          );
                                      final montosMesasActuales =
                                          MesasExtraUtils.montosManualesMesasDesde(
                                            montosManuales,
                                          );
                                      final result =
                                          await _mostrarDialogoDistribucionManual(
                                            context: context,
                                            total: capitalParaDialogo,
                                            deudaBase: deudaBaseTotal,
                                            deudaMesa: deudaMesaTotal,
                                            deudaSillas: deudaSillasTotal,
                                            currentBase: montosManuales['Base'],
                                            currentMesa:
                                                montosManuales['Mesa'] ??
                                                (montosMesasActuales.isEmpty
                                                    ? null
                                                    : MesasExtraUtils.sumaBrutaMesasSeleccionadasCobro(
                                                        montosManuales,
                                                      )),
                                            currentSillas:
                                                montosManuales['Sillas'],
                                            mesasParaReparto:
                                                cantMesas > 1 &&
                                                    mesasActivasCobro.isNotEmpty
                                                ? mesasActivasCobro
                                                : null,
                                            cantMesas: cantMesas,
                                            montosMesasActuales:
                                                montosMesasActuales,
                                          );
                                      if (result != null) {
                                        setModalState(() {
                                          modosPagoPorClave.clear();
                                          _aplicarResultadoDistribucionManual(
                                            montosManuales: montosManuales,
                                            result: result,
                                            deudaBaseTotal: deudaBaseTotal,
                                            deudaSillasTotal: deudaSillasTotal,
                                            mesasActivasCobro:
                                                mesasActivasCobro,
                                            cantMesas: cantMesas,
                                          );
                                          recalcularDesdeMonto(
                                            total,
                                            manually: true,
                                          );
                                        });
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      'EDITAR',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: const Color(0xFFD4AF37),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ..._buildFilasDesglosePreview(
                                previewConceptos: previewConceptos,
                                usarCompactoMesas:
                                    MesasExtraUtils.usarUiCompactaMesasCobro(
                                      mesasActivasCobro.length,
                                    ),
                                desgloseMesasExpandido: desgloseMesasExpandido,
                                onToggleDesgloseMesas: () => setModalState(
                                  () => desgloseMesasExpandido =
                                      !desgloseMesasExpandido,
                                ),
                              ),
                              (() {
                                final double sum = previewConceptos.fold(
                                  0,
                                  (s, c) => s + (c['monto'] as num).toDouble(),
                                );
                                final double totalTotal =
                                    CurrencyInputFormatter.parse(
                                      montoPagarCtrl.text,
                                    );
                                final double diff = totalTotal - sum;
                                if (diff.abs() > 0.01) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'REMANENTE:',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                        Text(
                                          diff.toCurrency(),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.redAccent,
                                          ),
                                        ),
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
                TextButton(
                  onPressed: confirmandoCobro
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('CANCELAR'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('RESUMEN PDF'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD4AF37),
                    side: const BorderSide(color: Color(0xFFD4AF37)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: confirmandoCobro ? null : emitirResumenAbonarPdf,
                ),
                ElevatedButton.icon(
                  icon: confirmandoCobro
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: confirmandoCobro
                      ? null
                      : () async {
                          final montoIngresado = CurrencyInputFormatter.parse(
                            montoPagarCtrl.text,
                          );
                          if (montoIngresado <= 0) return;
                          final double sumLiquidoCobro = previewConceptos
                              .where((c) => !esLineaCargoCanal(c))
                              .fold<double>(
                                0,
                                (s, c) => s + (c['monto'] as num).toDouble(),
                              );
                          final double interesIncluido = previewConceptos
                              .where(esLineaInteresMora)
                              .fold(
                                0.0,
                                (s, c) => s + (c['monto'] as num).toDouble(),
                              );
                          final double topePermitido =
                              alumno.saldoDeudor + interesIncluido;
                          if (sumLiquidoCobro > topePermitido + 0.01) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'ERROR: El monto excede lo permitido (${topePermitido.toCurrency()} = saldo ${alumno.saldoDeudor.toCurrency()}'
                                  '${interesIncluido > 0.01 ? ' + interés ${interesIncluido.toCurrency()}' : ''}).',
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }

                          if (previewConceptos.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Seleccioná al menos un concepto de pago.',
                                ),
                                backgroundColor: Colors.orangeAccent,
                              ),
                            );
                            return;
                          }

                          double parteEfectivo = montoIngresado;
                          double parteTransferencia = 0;
                          double transferCanalMixtoPdf = 0;
                          if (modoMedioPago == 'Mixto') {
                            parteEfectivo = CurrencyInputFormatter.parse(
                              efectivoMixCtrl.text,
                            );
                            transferCanalMixtoPdf =
                                CurrencyInputFormatter.parse(
                                  transferMixCtrl.text,
                                ).clamp(0.0, double.infinity);
                            parteTransferencia =
                                liquidoTransferenciaDesdeTotalMixto(
                                  transferCanalMixtoPdf,
                                );
                            if ((parteEfectivo +
                                        parteTransferencia -
                                        sumLiquidoCobro)
                                    .abs() >
                                0.03) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'La parte liquidada — efectivo (${parteEfectivo.toCurrency()}) '
                                    '+ transferencia líquida (${parteTransferencia.toCurrency()}) — debe '
                                    'coincidir con el desglose (${sumLiquidoCobro.toCurrency()}). '
                                    'Monto total (con canal): ${montoIngresado.toCurrency()}; '
                                    'transferencia canal: ${transferCanalMixtoPdf.toCurrency()}.',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              return;
                            }
                          } else if (modoMedioPago == 'Transferencia') {
                            parteEfectivo = 0;
                            parteTransferencia = sumLiquidoCobro;
                          }

                          // 1. CALCULOS MATEMÁTICOS EXACTOS Y BLINDADOS
                          int nuevasBase = 0;
                          int nuevasMesa = 0;
                          int nuevasSillas = 0;
                          double totalDeducidoBruto = 0.0;

                          double grossMesaPagado = 0.0;
                          double grossSillasPagado = 0.0;

                          for (var conc in previewConceptos) {
                            if (esLineaCargoCanal(conc)) continue;
                            if (esLineaInteresMora(conc)) continue;
                            final String cTexto = conc['concepto'] as String;
                            final int cCuotas =
                                ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(
                                  0,
                                  99,
                                );
                            final double cGross = (conc['gross'] as num)
                                .toDouble();
                            if (cTexto.toUpperCase().contains('BASE'))
                              nuevasBase += cCuotas;
                            if (cTexto.toUpperCase().contains('MESA')) {
                              nuevasMesa += cCuotas;
                              grossMesaPagado += cGross;
                            }
                            if (cTexto.toUpperCase().contains('SILLA')) {
                              nuevasSillas += cCuotas;
                              grossSillasPagado += cGross;
                            }

                            totalDeducidoBruto += cGross;
                          }

                          // Saldo desde historial gross (no desde saldo_deudor incremental):
                          // evita arrastrar fantasmas cuando hubo adelantos/parciales previos.
                          final grossHistoricoPlan =
                              (historicoGrossPorClave['Base'] ?? 0.0) +
                              (historicoGrossPorClave['Mesa'] ?? 0.0) +
                              (historicoGrossPorClave['Sillas'] ?? 0.0);
                          double saldoRestanteCalculado =
                              alumno.montoTotalPactado -
                              grossHistoricoPlan -
                              totalDeducidoBruto;
                          double saldoRestante = double.parse(
                            saldoRestanteCalculado.toStringAsFixed(2),
                          ).clamp(0.0, double.infinity);

                          int currentBasePagadas = (cPagadas + nuevasBase)
                              .clamp(0, tCuotas);
                          int currentMesaPagadas = (mPagadas + nuevasMesa)
                              .clamp(0, mCuotas > 0 ? mCuotas : 1);
                          int currentSillasPagadas = (sPagadas + nuevasSillas)
                              .clamp(0, sCuotas > 0 ? sCuotas : 1);

                          if (saldoRestante <= 0.01) {
                            currentBasePagadas = tCuotas;
                            currentMesaPagadas =
                                (alumno.mesaExtraPrecio > 0 && mCuotas > 0)
                                ? mCuotas
                                : 0;
                            currentSillasPagadas =
                                (alumno.sillasExtraPrecioTotal > 0 &&
                                    sCuotas > 0)
                                ? sCuotas
                                : 0;
                          }

                          final conceptosFinales =
                              conceptosFinalesDesdePreviewMasivo(
                                previewConceptos: previewConceptos,
                                esLineaCargoCanal: esLineaCargoCanal,
                                esLineaInteresMora: esLineaInteresMora,
                                cPagadas: cPagadas,
                                tCuotas: tCuotas,
                                mPagadas: mPagadas,
                                mCuotas: mCuotas,
                                sPagadas: sPagadas,
                                sCuotas: sCuotas,
                                cantMesas: cantMesas,
                              );

                          final mesasPatchOptimista =
                              grossMesaPagado > 0.01 &&
                                  mesasEstadoList.isNotEmpty
                              ? MesasExtraUtils.aplicarCobroPreviewAEstado(
                                  estado: mesasEstadoList,
                                  lineasPreview: previewConceptos,
                                  cuotasPlan: mCuotas,
                                )
                              : mesasEstadoList;

                          final alumnoFresco = alumno.copyWith(
                            saldoDeudor: saldoRestante,
                            cuotasPagadas: currentBasePagadas,
                            mesaExtraCuotasPagadas: currentMesaPagadas,
                            sillasExtraCuotasPagadas: currentSillasPagadas,
                            mesaExtraPagado:
                                (alumno.mesaExtraPagado) + grossMesaPagado,
                            sillasExtraPagado:
                                (alumno.sillasExtraPagado) + grossSillasPagado,
                            mesasExtraEstadoRaw:
                                grossMesaPagado > 0.01 &&
                                    mesasPatchOptimista.isNotEmpty
                                ? mesasPatchOptimista
                                      .map((e) => e.toJson())
                                      .toList()
                                : alumno.mesasExtraEstadoRaw,
                          );

                          final moraEsteCobro = previewConceptos
                              .where(esLineaInteresMora)
                              .fold<double>(
                                0,
                                (s, c) => s + (c['monto'] as num).toDouble(),
                              );

                          final cuotasLiquidadasEnCobro =
                              (currentBasePagadas - cPagadas).clamp(0, tCuotas);
                          // Recalcular desglose al confirmar (estado pre-cobro real).
                          final moraDesgloseBrutoConfirm =
                              MoraCuotaCalculator.calcularDesglose(alumno);
                          final moraDesgloseNetoPreCobro =
                              MoraCuotaCalculator.desglosePendiente(
                                moraDesgloseBrutoConfirm,
                                MoraCuotaCalculator.moraCobradaParaFifo(
                                  moraCobradaHistorial: moraYaCobradaHist,
                                  moraCobradaOffset: alumno.moraCobradaOffset,
                                ),
                              );
                          final moraDesgloseNetoTotal = moraDesgloseNetoPreCobro
                              .fold<double>(0, (s, d) => s + d.interesBruto);

                          final postTrackedOffset =
                              MoraCuotaCalculator.postCobroTrackedOffset(
                                moraPendienteTrackedActual: remanenteMora,
                                moraCobradaOffsetActual:
                                    alumno.moraCobradaOffset,
                                moraEsteCobro: moraEsteCobro,
                                cuotasBaseLiquidadasEnCobro:
                                    cuotasLiquidadasEnCobro,
                                cuotasBasePagadasPostCobro: currentBasePagadas,
                                moraDesglosePreCobro: moraDesgloseBrutoConfirm,
                                moraDesgloseNetoPreCobro:
                                    moraDesgloseNetoPreCobro,
                                moraDesgloseNetoTotal: moraDesgloseNetoTotal,
                              );

                          final moraHistPostCobro =
                              moraYaCobradaHist + moraEsteCobro;
                          final contratoSimPost = alumnoFresco.copyWith(
                            moraPendienteTracked: postTrackedOffset.tracked,
                            moraCobradaOffset: postTrackedOffset.offset,
                            moraFechaReferencia: alumno.moraFechaReferencia,
                          );
                          final moraRestantePost =
                              MoraCuotaCalculator.moraPendienteOperativa(
                                contrato: contratoSimPost,
                                moraCobradaHistorial: moraHistPostCobro,
                              );
                          final limpiarMoraRef =
                              MoraCuotaCalculator.debeDescongelarMoraReferencia(
                                contrato: alumno,
                                moraPendienteOperativaPost: moraRestantePost,
                                saldoDeudorPost: saldoRestante,
                              );

                          // Exención: si el cobro pagó toda la mora que estaba
                          // pendiente PRE-cobro, eximir hasta fin de mes.
                          // Con liquidación de cuota → reinicia; solo mora/abono → permanente.
                          final double moraPendientePreCobro =
                              moraDesgloseNetoTotal + remanenteMora;
                          final DateTime? nuevaExencion;
                          final bool nuevaExencionReinicia;
                          if (moraEsteCobro > 0.01 &&
                              moraEsteCobro >= moraPendientePreCobro - 0.01 &&
                              saldoRestante > 0.01) {
                            nuevaExencion =
                                MoraCuotaCalculator.calcularFechaExencion(
                                  DateTime.now(),
                                );
                            nuevaExencionReinicia = cuotasLiquidadasEnCobro > 0;
                          } else {
                            nuevaExencion = alumno.moraExentaHasta;
                            nuevaExencionReinicia = alumno.moraExencionReinicia;
                          }

                          final alumnoPatchLocal = alumnoFresco.copyWith(
                            moraPendienteTracked: postTrackedOffset.tracked,
                            moraCobradaOffset: postTrackedOffset.offset,
                            moraFechaReferencia: limpiarMoraRef
                                ? null
                                : alumno.moraFechaReferencia,
                            moraExentaHasta: nuevaExencion,
                            moraExencionReinicia: nuevaExencionReinicia,
                          );

                          // Capturar valores del modal antes de cerrarlo (evita usar
                          // controllers tras dispose en el microtask de persistencia).
                          final descStrPersist = porcentajeDescuentoCtrl.text;
                          final prefsPctStr = pctTransferInfoCtrl.text.trim();
                          final prefsCargoMontoStr = transferCargoMontoCtrl.text
                              .trim();
                          final previewSnapshot = previewConceptos
                              .map((c) => Map<String, dynamic>.from(c))
                              .toList();
                          final mesasEstadoPatchCaptura =
                              grossMesaPagado > 0.01 &&
                                  mesasPatchOptimista.isNotEmpty
                              ? List<MesaExtraItem>.from(mesasPatchOptimista)
                              : <MesaExtraItem>[];
                          final trackedNuevoPersist = postTrackedOffset.tracked;
                          final offsetNuevoPersist = postTrackedOffset.offset;
                          final limpiarMoraRefPersist = limpiarMoraRef;
                          final exencionPersist = nuevaExencion;
                          final exencionReiniciaPersist = nuevaExencionReinicia;
                          final sesionCajaIdCobro = await ref
                              .read(appRoleProvider.notifier)
                              .sesionCajaIdParaCobro();
                          final double pctCargoInforme =
                              double.tryParse(
                                prefsPctStr.replaceAll(',', '.'),
                              ) ??
                              0;
                          final double montoCargoInformeParsed =
                              CurrencyInputFormatter.parse(prefsCargoMontoStr);

                          setModalState(() => confirmandoCobro = true);
                          final autoSyncCheckpoint = DateTime.now().toUtc();

                          try {
                            final repo = ref.read(contratosRepositoryProvider);
                            final pulled = await ref
                                .read(cajaAutoSyncServiceProvider)
                                .refreshBeforePayment();
                            if (!pulled && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Sin conexión con la nube: el cobro se guardará '
                                    'localmente, pero no se puede descartar un cobro '
                                    'simultáneo hasta reconectar.',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                            if (pulled) {
                              final remoto = await repo.getContratoById(
                                alumno.id,
                              );
                              final base = alumnoFresco;
                              final cambioRemoto =
                                  remoto != null &&
                                  ((remoto.saldoDeudor - base.saldoDeudor)
                                              .abs() >
                                          0.01 ||
                                      remoto.cuotasPagadas !=
                                          base.cuotasPagadas ||
                                      (remoto.mesaExtraPagado -
                                                  base.mesaExtraPagado)
                                              .abs() >
                                          0.01 ||
                                      (remoto.sillasExtraPagado -
                                                  base.sillasExtraPagado)
                                              .abs() >
                                          0.01);
                              if (cambioRemoto) {
                                throw StateError(
                                  'Este alumno recibió cambios desde otra caja. '
                                  'Cerrá el cobro, revisá el saldo actualizado y '
                                  'volvé a intentarlo.',
                                );
                              }
                            }
                            final descStr = descStrPersist;
                            final tIng = parteEfectivo + parteTransferencia;
                            final sumNetas = previewSnapshot
                                .where((c) => !esLineaCargoCanal(c))
                                .fold<double>(
                                  0,
                                  (s, c) => s + (c['monto'] as num).toDouble(),
                                );
                            final loteHistAcum = Map<String, double>.from(
                              historicoGrossPorClave,
                            );

                            Future<void> registrarLineaUna(
                              Map<String, dynamic> conc,
                            ) async {
                              final cTexto = conc['concepto'] as String;
                              final conceptoPersistido =
                                  MesasExtraUtils.conceptoPagoPersistido(
                                    previewLinea: conc,
                                    conceptoOriginal: cTexto,
                                    cantidadMesas: cantMesas,
                                  );
                              final monto = (conc['monto'] as num).toDouble();
                              final gross =
                                  (conc['gross'] as num?)?.toDouble() ?? monto;
                              final cCuotas =
                                  ((conc['cuotas'] as num?)?.toInt() ?? 0)
                                      .clamp(0, 99);
                              final lineKind = conc['lineKind'] as String?;

                              if (lineKind == 'cargo_canal_ref') {
                                if (monto > 0.004) {
                                  await repo.registrarPago(
                                    contratoId: alumno.id,
                                    monto: monto,
                                    concepto: cTexto,
                                    montoADescontarDeSaldo: 0,
                                    descuentoPorcentaje: 0,
                                    cuotasLiquidadas: 0,
                                    medioPago: 'Transferencia',
                                    lineKind: lineKind,
                                    sesionCajaId: sesionCajaIdCobro,
                                  );
                                }
                                return;
                              }

                              // Mixto se registra agregado más abajo (no por línea).
                              if (modoMedioPago == 'Mixto') return;

                              if (tIng < 0.01 || sumNetas < 0.01) return;

                              final mE = modoMedioPago == 'Efectivo'
                                  ? monto
                                  : 0.0;
                              final mT = modoMedioPago == 'Transferencia'
                                  ? monto
                                  : 0.0;
                              final gE = modoMedioPago == 'Efectivo'
                                  ? gross
                                  : 0.0;
                              final gT = modoMedioPago == 'Transferencia'
                                  ? gross
                                  : 0.0;

                              Future<void> uno(
                                double m,
                                double mg,
                                String med,
                                int cq, {
                                String? conceptoRegistro,
                                String? lineKindOverride,
                              }) async {
                                if (m <= 0.004) return;
                                await repo.registrarPago(
                                  contratoId: alumno.id,
                                  monto: m,
                                  concepto:
                                      conceptoRegistro ?? conceptoPersistido,
                                  montoADescontarDeSaldo: mg,
                                  descuentoPorcentaje:
                                      double.tryParse(descStr) ?? 0,
                                  cuotasLiquidadas: cq,
                                  medioPago: med,
                                  lineKind: lineKindOverride ?? lineKind,
                                  moraPendienteAntesDeLote:
                                      (lineKindOverride ?? lineKind) ==
                                          kLineKindInteresMora
                                      ? moraPendienteEfectivo
                                      : null,
                                  sesionCajaId: sesionCajaIdCobro,
                                );
                              }

                              final esPlanLinea =
                                  lineKind != kLineKindCargoCanal &&
                                  lineKind != kLineKindInteresMora &&
                                  !esLineaCargoCanal(conc) &&
                                  !esLineaInteresMora(conc);

                              if (mE <= 0.004 && mT > 0.004) {
                                await uno(mT, gT, 'Transferencia', cCuotas);
                              } else if (mT <= 0.004 && mE > 0.004) {
                                await uno(mE, gE, 'Efectivo', cCuotas);
                              }

                              if (esPlanLinea) {
                                ConceptoPagoDisplay.acumularGrossLoteEnHistorial(
                                  loteHistAcum,
                                  conc,
                                  gross,
                                );
                              }
                            }

                            if (modoMedioPago == 'Mixto') {
                              // Cargo canal primero (siempre transferencia).
                              for (final conc in previewSnapshot) {
                                if (!esLineaCargoCanal(conc)) continue;
                                final monto = (conc['monto'] as num).toDouble();
                                if (monto <= 0.004) continue;
                                await repo.registrarPago(
                                  contratoId: alumno.id,
                                  monto: monto,
                                  concepto: conc['concepto'] as String,
                                  montoADescontarDeSaldo: 0,
                                  descuentoPorcentaje: 0,
                                  cuotasLiquidadas: 0,
                                  medioPago: 'Transferencia',
                                  lineKind: kLineKindCargoCanal,
                                  sesionCajaId: sesionCajaIdCobro,
                                );
                              }

                              final partes =
                                  ConceptoPagoDisplay.armarRegistroMixtoAgregado(
                                    contrato: alumno,
                                    previewLineas: previewSnapshot,
                                    parteEfectivo: parteEfectivo,
                                    parteTransferencia: parteTransferencia,
                                    historicoGrossPorClave: loteHistAcum,
                                    esLineaCargoCanal: esLineaCargoCanal,
                                    esLineaInteresMora: esLineaInteresMora,
                                  );
                              for (final part in partes) {
                                if (part.net <= 0.004) continue;
                                await repo.registrarPago(
                                  contratoId: alumno.id,
                                  monto: part.net,
                                  concepto: part.concepto,
                                  montoADescontarDeSaldo: part.gross,
                                  descuentoPorcentaje:
                                      double.tryParse(descStr) ?? 0,
                                  cuotasLiquidadas: part.cuotasLiquidadas,
                                  medioPago: part.medio,
                                  lineKind: part.lineKind,
                                  moraPendienteAntesDeLote:
                                      part.lineKind == kLineKindInteresMora
                                      ? moraPendienteEfectivo
                                      : null,
                                  sesionCajaId: sesionCajaIdCobro,
                                );
                              }
                            } else {
                              for (final conc in previewSnapshot) {
                                await registrarLineaUna(conc);
                              }
                            }

                            await repo.reconciliarMesasEstadoContrato(
                              alumno.id,
                            );

                            if (mesasEstadoPatchCaptura.isNotEmpty) {
                              await repo.actualizarContrato(alumno.id, {
                                'mesas_extra_estado': mesasEstadoPatchCaptura
                                    .map((e) => e.toJson())
                                    .toList(),
                                'mesa_extra_pagado': double.parse(
                                  MesasExtraUtils.totalPagado(
                                    mesasEstadoPatchCaptura,
                                  ).toStringAsFixed(2),
                                ),
                                'mesa_extra_cuotas_pagadas':
                                    MesasExtraUtils.maxCuotasPagadas(
                                      mesasEstadoPatchCaptura,
                                    ),
                              });
                            }

                            await repo.actualizarContrato(alumno.id, {
                              'mora_pendiente_tracked': double.parse(
                                trackedNuevoPersist.toStringAsFixed(2),
                              ),
                              'mora_cobrada_offset': offsetNuevoPersist,
                              if (limpiarMoraRefPersist)
                                'mora_fecha_referencia': null,
                              if (exencionPersist != null)
                                'mora_exenta_hasta':
                                    '${exencionPersist.year.toString().padLeft(4, '0')}-'
                                    '${exencionPersist.month.toString().padLeft(2, '0')}-'
                                    '${exencionPersist.day.toString().padLeft(2, '0')}',
                              'mora_exencion_reinicia': exencionReiniciaPersist
                                  ? 1
                                  : 0,
                            });

                            await repo.recalcularProgresoContrato(alumno.id);
                            await ref
                                .read(cajaAutoSyncServiceProvider)
                                .afterMassiveMutation(
                                  startedAt: autoSyncCheckpoint,
                                  isPayment: true,
                                );

                            final fresco = await repo.getContratoById(
                              alumno.id,
                            );

                            await prefsMedio.setString(
                              'medio_pago_cobro_masivo',
                              modoMedioPago,
                            );
                            await prefsMedio.setString(
                              'cobro_masivo_pct_transfer_info',
                              prefsPctStr,
                            );
                            await prefsMedio.setString(
                              'cobro_masivo_transfer_cargo_modo',
                              transferCargoModo,
                            );
                            await prefsMedio.setString(
                              'cobro_masivo_transfer_cargo_monto',
                              prefsCargoMontoStr,
                            );
                            await prefsMedio.setBool(
                              'cobro_masivo_informar_pct_transfer',
                              informarPctTransferExterno,
                            );

                            final double pctDescuentoConfirm =
                                double.tryParse(
                                  descStrPersist.replaceAll(',', '.').trim(),
                                ) ??
                                0;

                            if (context.mounted) {
                              Navigator.pop(context, true);
                            }

                            if (!mounted) return;

                            final paraUi = fresco ?? alumnoPatchLocal;
                            _patchAlumnoLocal(
                              alumno.id,
                              paraUi,
                              moraCobradaExtra: moraEsteCobro,
                            );

                            // PDF solo tras lote OK; mismos conceptos que se persistieron.
                            _imprimirReciboAlumno(
                              fresco ?? alumnoFresco,
                              montoPagado: montoIngresado,
                              saldoPendiente:
                                  fresco?.saldoDeudor ?? saldoRestante,
                              conceptosPagados: conceptosFinales,
                              fechaManual: DateTime.now(),
                              porcentajeDescuentoLiquidacion:
                                  pctDescuentoConfirm,
                              medioPago: modoMedioPago == 'Mixto'
                                  ? 'Mixto'
                                  : modoMedioPago,
                              montoEfectivoDetalle: modoMedioPago == 'Mixto'
                                  ? parteEfectivo
                                  : null,
                              montoTransferenciaDetalle:
                                  modoMedioPago == 'Mixto'
                                  ? transferCanalMixtoPdf
                                  : null,
                              informarCargoTransferenciaExterno:
                                  informarPctTransferExterno,
                              porcentajeCargoTransferenciaExterno:
                                  informarPctTransferExterno &&
                                      transferCargoModo == 'pct' &&
                                      pctCargoInforme > 0.01
                                  ? pctCargoInforme
                                  : null,
                              montoCargoTransferenciaInformado:
                                  informarPctTransferExterno &&
                                      transferCargoModo == 'pesos' &&
                                      montoCargoInformeParsed > 0.01
                                  ? montoCargoInformeParsed
                                  : null,
                              skipDbRefresh: true,
                            );

                            ref
                                .read(contratosMutationTickProvider.notifier)
                                .bump();
                          } catch (e) {
                            debugPrint('Error al registrar cobro masivo: $e');
                            if (context.mounted) {
                              setModalState(() => confirmandoCobro = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'No se pudo guardar el cobro. Reintentá. ($e)',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            } else if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'No se pudo guardar el cobro. Reintentá. ($e)',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        },
                  label: Text(
                    confirmandoCobro ? 'GUARDANDO...' : 'CONFIRMAR PAGO',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    _deferDisposeTextControllers([
      montoPagarCtrl,
      porcentajeDescuentoCtrl,
      moraMontoCobroCtrl,
      efectivoMixCtrl,
      transferMixCtrl,
      pctTransferInfoCtrl,
      transferCargoMontoCtrl,
    ]);
  }

  Future<void> _mostrarHistorialPagosAlumno(ContratoAlumno alumno) async {
    final repo = ref.read(contratosRepositoryProvider);
    final alumnoUi = await repo.getContratoById(alumno.id) ?? alumno;
    final mesasResumen = MesasExtraUtils.estadoDesdeContrato(alumnoUi);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.getHistorialPagosAlumno(alumno.id),
        builder: (context, snapshot) {
          final pagos = (snapshot.data ?? [])
              .where((p) => ((p['anulado'] as num?)?.toInt() ?? 0) == 0)
              .toList();
          final bool cargando =
              snapshot.connectionState == ConnectionState.waiting;
          final listaFinal = pagos.isEmpty
              ? <Map<String, dynamic>>[]
              : ConceptoPagoDisplay.enriquecerPagosHistorial(alumnoUi, pagos);
          final double totalEntregado = listaFinal.fold<double>(
            0,
            (sum, p) => sum + (p['monto'] as num).toDouble(),
          );

          final screen = MediaQuery.sizeOf(context);
          final fs = (screen.width / 1440).clamp(0.82, 1.0);
          final dialogW = (screen.width * 0.92).clamp(320.0, 560.0);
          final dialogH = (screen.height * 0.72).clamp(360.0, 640.0);
          double s(double base) => base * fs;

          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: screen.width * 0.04,
              vertical: screen.height * 0.06,
            ),
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
              ),
            ),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: EdgeInsets.all(s(24)),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        color: const Color(0xFFD4AF37),
                        size: s(22),
                      ),
                      SizedBox(width: s(12)),
                      Text(
                        'ESTADO DE CUENTA',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: s(14),
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: s(4)),
                  Text(
                    alumnoUi.nombreAlumno.toUpperCase(),
                    style: TextStyle(
                      fontSize: s(11),
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (mesasResumen.isNotEmpty) ...[
                    SizedBox(height: s(8)),
                    ...mesasResumen.map((m) {
                      final cuotas = alumnoUi.mesaExtraCuotas;
                      final linea = m.liquidada
                          ? 'Mesa ${m.n} · Liquidada · ${m.precio.toCurrency()}'
                          : 'Mesa ${m.n} · Cuota ${m.cuotasPagadas}/$cuotas · Deuda ${m.deuda.toCurrency()}';
                      return Padding(
                        padding: EdgeInsets.only(top: s(2)),
                        child: Text(
                          linea,
                          style: TextStyle(
                            fontSize: s(10),
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
            content: SizedBox(
              width: dialogW,
              height: dialogH,
              child: cargando
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFD4AF37),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: pagos.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.history_rounded,
                                        size: s(40),
                                        color: Colors.grey.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                      SizedBox(height: s(12)),
                                      Text(
                                        'No hay pagos registrados aún.',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                          fontSize: s(12),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  itemCount: listaFinal.length,
                                  itemBuilder: (context, index) {
                                    final p = listaFinal[index];
                                    final fecha = DateTime.parse(
                                      p['fecha_pago'],
                                    );
                                    final monto = double.parse(
                                      (p['monto'] as num)
                                          .toDouble()
                                          .toStringAsFixed(2),
                                    );
                                    final concepto =
                                        p['concepto_detallado'] as String;
                                    final bool esLineaMora =
                                        ConceptoPagoDisplay.esMora(p);
                                    final bool esLineaCargo =
                                        ConceptoPagoDisplay.esCargoCanal(p);

                                    return Container(
                                      margin: EdgeInsets.only(bottom: s(12)),
                                      padding: EdgeInsets.all(s(10)),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.03,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.02,
                                              ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: esLineaMora
                                              ? Colors.orange.withValues(
                                                  alpha: 0.45,
                                                )
                                              : esLineaCargo
                                              ? Colors.blue.withValues(
                                                  alpha: 0.35,
                                                )
                                              : isDark
                                              ? Colors.white10
                                              : Colors.black12,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.all(s(7)),
                                            decoration: BoxDecoration(
                                              color:
                                                  (esLineaMora
                                                          ? Colors.orange
                                                          : Colors.green)
                                                      .withValues(alpha: 0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              esLineaMora
                                                  ? Icons.schedule_rounded
                                                  : Icons.check_rounded,
                                              color: esLineaMora
                                                  ? Colors.orange.shade800
                                                  : Colors.green,
                                              size: s(14),
                                            ),
                                          ),
                                          SizedBox(width: s(12)),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        concepto,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: s(12),
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (esLineaMora) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange
                                                              .withValues(
                                                                alpha: 0.15,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          'MORA',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            color: Colors
                                                                .orange
                                                                .shade900,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                    if (p['label_descuento'] !=
                                                        null) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange
                                                              .withValues(
                                                                alpha: 0.15,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          p['label_descuento'],
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 9,
                                                                color: Colors
                                                                    .orange,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                    if (p['es_liquidacion_mesa'] ==
                                                        true) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green
                                                              .withValues(
                                                                alpha: 0.15,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'Liquidada',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            color: Colors.green,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                Text(
                                                  ArTime.formatFechaHora(fecha),
                                                  style: TextStyle(
                                                    fontSize: s(10),
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                if (p['subtitulo_medio'] !=
                                                        null &&
                                                    (p['subtitulo_medio']
                                                            as String)
                                                        .isNotEmpty)
                                                  Text(
                                                    p['subtitulo_medio']
                                                        as String,
                                                    style: TextStyle(
                                                      fontSize: s(9),
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                monto.toCurrency(),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: s(12),
                                                  color: Colors.green,
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () {
                                                  final fechaOrig =
                                                      DateTime.tryParse(
                                                        p['fecha_pago'] ?? '',
                                                      ) ??
                                                      DateTime.now();
                                                  double sumPagosPlanHistorico =
                                                      0;
                                                  for (final rec
                                                      in listaFinal) {
                                                    final isMora =
                                                        rec['line_kind'] ==
                                                            'interes_mora' ||
                                                        (rec['concepto']
                                                                ?.toString()
                                                                .toLowerCase()
                                                                .contains(
                                                                  'interés',
                                                                ) ??
                                                            false) ||
                                                        (rec['concepto_detallado']
                                                                ?.toString()
                                                                .toLowerCase()
                                                                .contains(
                                                                  'interés',
                                                                ) ??
                                                            false);
                                                    final conc = rec['concepto']
                                                        ?.toString();
                                                    final concDet =
                                                        rec['concepto_detallado']
                                                            ?.toString();
                                                    final isCargo =
                                                        rec['line_kind'] ==
                                                            kLineKindCargoCanal ||
                                                        esPagoCargoCanalPorConcepto(
                                                          conc,
                                                        ) ||
                                                        esPagoCargoCanalPorConcepto(
                                                          concDet,
                                                        );
                                                    final recDate =
                                                        DateTime.tryParse(
                                                          rec['fecha_pago'] ??
                                                              '',
                                                        ) ??
                                                        DateTime.now();
                                                    if (!isMora &&
                                                        !isCargo &&
                                                        recDate.compareTo(
                                                              fechaOrig,
                                                            ) <=
                                                            0) {
                                                      sumPagosPlanHistorico +=
                                                          (rec['monto'] as num)
                                                              .toDouble();
                                                    }
                                                  }
                                                  final double historicoSaldo =
                                                      (alumno.montoTotalPactado -
                                                              sumPagosPlanHistorico)
                                                          .clamp(
                                                            0.0,
                                                            double.infinity,
                                                          );

                                                  _imprimirReciboAlumno(
                                                    alumno,
                                                    montoPagado: monto,
                                                    saldoPendiente:
                                                        historicoSaldo,
                                                    conceptosPagados:
                                                        <Map<String, dynamic>>[
                                                          {
                                                            'concepto':
                                                                concepto,
                                                            'monto': monto,
                                                          },
                                                        ],
                                                    fechaManual: fechaOrig,
                                                    medioPago:
                                                        p['medio_pago']
                                                            as String?,
                                                  );
                                                },
                                                child: const Padding(
                                                  padding: EdgeInsets.only(
                                                    top: 4,
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.print_rounded,
                                                        size: 10,
                                                        color:
                                                            Colors.blueAccent,
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'REIMPRIMIR',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          color:
                                                              Colors.blueAccent,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
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
                                ),
                        ),
                        const Divider(height: 32),
                        Container(
                          padding: EdgeInsets.all(s(14)),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFD4AF37,
                            ).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL ENTREGADO:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: s(11),
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                totalEntregado.toCurrency(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: s(15),
                                  color: const Color(0xFFD4AF37),
                                ),
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
                child: const Text(
                  'CERRAR',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
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
    String? medioPago,
    double? montoEfectivoDetalle,
    double? montoTransferenciaDetalle,
    bool informarCargoTransferenciaExterno = false,
    double? porcentajeCargoTransferenciaExterno,
    double? montoCargoTransferenciaInformado,
    double porcentajeDescuentoLiquidacion = 0,
    bool skipDbRefresh = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Generando Recibo...'),
        duration: Duration(seconds: 2),
      ),
    );

    double valPago = montoPagado ?? 0;
    double valSaldo = saldoPendiente ?? alumno.saldoDeudor;
    String? valConcepto = conceptoCuotas;
    ContratoAlumno alumnoParaPdf = alumno;
    double pctDescuentoPdf = porcentajeDescuentoLiquidacion;

    try {
      final repo = ref.read(contratosRepositoryProvider);

      if (conceptosPagados == null || conceptosPagados.isEmpty) {
        final lote = await repo.getUltimosPagosLote(alumno.id);

        if (lote.isNotEmpty) {
          // Detect if there are both Efectivo and Transferencia payments in the batch (Mixto)
          double totalEfectivo = 0.0;
          double totalTransferencia = 0.0;
          for (final p in lote) {
            final double m = (p['monto'] as num?)?.toDouble() ?? 0.0;
            final String mp = (p['medio_pago'] as String?)?.trim() ?? '';
            if (mp.toLowerCase() == 'efectivo') {
              totalEfectivo += m;
            } else if (mp.toLowerCase().contains('transfer') ||
                mp.toLowerCase() == 'transferencia') {
              totalTransferencia += m;
            }
            final d = (p['descuento_porcentaje'] as num?)?.toDouble() ?? 0;
            if (d > pctDescuentoPdf) pctDescuentoPdf = d;
          }

          if (totalEfectivo > 0.01 && totalTransferencia > 0.01) {
            medioPago = 'Mixto';
            montoEfectivoDetalle = totalEfectivo;
            montoTransferenciaDetalle = totalTransferencia;
          } else if (totalEfectivo > 0.01) {
            medioPago = 'Efectivo';
          } else if (totalTransferencia > 0.01) {
            medioPago = 'Transferencia';
          }

          conceptosPagados = ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
            alumno,
            lote,
            historialCompleto: await repo.getHistorialPagosAlumno(alumno.id),
          );

          valPago = conceptosPagados.fold<double>(
            0,
            (sum, c) => sum + ((c['monto'] as num?)?.toDouble() ?? 0.0),
          );
        } else {
          valPago = 0;
        }
      }

      if (!skipDbRefresh) {
        final alumnosFrescos = await repo.getByEvento(alumno.eventoId);
        final fresco = alumnosFrescos.cast<ContratoAlumno?>().firstWhere(
          (a) => a!.id == alumno.id,
          orElse: () => null,
        );
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
        medioPago: medioPago,
        montoEfectivoDetalle: montoEfectivoDetalle,
        montoTransferenciaDetalle: montoTransferenciaDetalle,
        informarCargoTransferenciaExterno: informarCargoTransferenciaExterno,
        porcentajeCargoTransferenciaExterno:
            porcentajeCargoTransferenciaExterno,
        montoCargoTransferenciaInformado: montoCargoTransferenciaInformado,
        porcentajeDescuentoLiquidacion: pctDescuentoPdf,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al generar PDF: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _aplicarResultadoDistribucionManual({
    required Map<String, double> montosManuales,
    required Map<String, double> result,
    required double deudaBaseTotal,
    required double deudaSillasTotal,
    required List<MesaExtraItem> mesasActivasCobro,
    required int cantMesas,
  }) {
    final base = result['Base'] ?? 0;
    if (base > 0.01) {
      montosManuales['Base'] = base;
    } else {
      montosManuales['Base'] = deudaBaseTotal;
    }

    MesasExtraUtils.limpiarClavesMesasEnMontosManuales(montosManuales);

    final bool repartoPorMesa = cantMesas > 1 && mesasActivasCobro.length > 1;

    if (repartoPorMesa) {
      for (final mesa in mesasActivasCobro) {
        final key = MesasExtraUtils.claveCobro(mesa.n);
        final val = result[key] ?? 0;
        if (val > 0.01) {
          montosManuales[key] = double.parse(val.toStringAsFixed(2));
        }
      }
    } else if (cantMesas > 1 && mesasActivasCobro.length == 1) {
      final mesa = result['Mesa'] ?? 0;
      if (mesa > 0.01) {
        montosManuales[MesasExtraUtils.claveCobro(mesasActivasCobro.first.n)] =
            double.parse(mesa.toStringAsFixed(2));
      }
    } else {
      final mesa = result['Mesa'] ?? 0;
      if (mesa > 0.01) {
        montosManuales['Mesa'] = mesa;
      }
    }

    final sillas = result['Sillas'] ?? 0;
    if (sillas > 0.01) {
      montosManuales['Sillas'] = sillas;
    } else {
      montosManuales.remove('Sillas');
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
    List<MesaExtraItem>? mesasParaReparto,
    int cantMesas = 1,
    Map<String, double>? montosMesasActuales,
  }) {
    final bool repartoPorMesa =
        mesasParaReparto != null && mesasParaReparto.length > 1;

    final baseCtrl = TextEditingController(
      text: currentBase?.toFormattedNumber() ?? '',
    );
    final mesaCtrl = TextEditingController(
      text: !repartoPorMesa && (currentMesa ?? 0) > 0.01
          ? currentMesa!.toFormattedNumber()
          : '',
    );
    final sillasCtrl = TextEditingController(
      text: currentSillas?.toFormattedNumber() ?? '',
    );

    final Map<String, TextEditingController> mesaCtrlsPorClave = {};
    if (repartoPorMesa) {
      final actuales = montosMesasActuales ?? {};
      for (final mesa in mesasParaReparto) {
        final key = MesasExtraUtils.claveCobro(mesa.n);
        final prev = actuales[key];
        mesaCtrlsPorClave[key] = TextEditingController(
          text: prev != null && prev > 0.01 ? prev.toFormattedNumber() : '',
        );
      }
    }

    void disposeCtrls() {
      baseCtrl.dispose();
      mesaCtrl.dispose();
      sillasCtrl.dispose();
      for (final c in mesaCtrlsPorClave.values) {
        c.dispose();
      }
    }

    return showDialog<Map<String, double>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInternalState) {
          double sumMesasIndividuales() {
            var s = 0.0;
            for (final c in mesaCtrlsPorClave.values) {
              s += CurrencyInputFormatter.parse(c.text);
            }
            return s;
          }

          double getSum() {
            var s =
                CurrencyInputFormatter.parse(baseCtrl.text) +
                CurrencyInputFormatter.parse(sillasCtrl.text);
            if (repartoPorMesa) {
              s += sumMesasIndividuales();
            } else {
              s += CurrencyInputFormatter.parse(mesaCtrl.text);
            }
            return s;
          }

          final double currentSum = getSum();
          final double diff = total - currentSum;
          final bool isValid = diff.abs() < 0.01;

          void autoCompletar() {
            double rem = total;
            double b = rem >= deudaBase ? deudaBase : rem;
            rem = double.parse((rem - b).toStringAsFixed(2));

            if (repartoPorMesa) {
              for (final mesa in mesasParaReparto) {
                final key = MesasExtraUtils.claveCobro(mesa.n);
                final ctrl = mesaCtrlsPorClave[key]!;
                if (rem <= 0.01) {
                  ctrl.text = '';
                  continue;
                }
                final assign = rem >= mesa.deuda ? mesa.deuda : rem;
                ctrl.text = assign > 0.01 ? assign.toFormattedNumber() : '';
                rem = double.parse((rem - assign).toStringAsFixed(2));
              }
            } else {
              final m = rem >= deudaMesa ? deudaMesa : rem;
              rem = double.parse((rem - m).toStringAsFixed(2));
              mesaCtrl.text = m > 0.01 ? m.toFormattedNumber() : '';
            }

            final s = rem >= deudaSillas ? deudaSillas : rem;
            setInternalState(() {
              baseCtrl.text = b > 0.01 ? b.toFormattedNumber() : '';
              sillasCtrl.text = s > 0.01 ? s.toFormattedNumber() : '';
            });
          }

          Map<String, double> buildResult() {
            final out = <String, double>{
              'Base': CurrencyInputFormatter.parse(baseCtrl.text),
              'Sillas': CurrencyInputFormatter.parse(sillasCtrl.text),
            };
            if (repartoPorMesa) {
              for (final entry in mesaCtrlsPorClave.entries) {
                out[entry.key] = CurrencyInputFormatter.parse(entry.value.text);
              }
              out['Mesa'] = 0;
            } else {
              out['Mesa'] = CurrencyInputFormatter.parse(mesaCtrl.text);
            }
            return out;
          }

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REPARTO MANUAL DE PAGO',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Total a distribuir: ${total.toCurrency()}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: autoCompletar,
                          icon: const Icon(
                            Icons.auto_fix_high_rounded,
                            size: 14,
                          ),
                          label: const Text(
                            'AUTO-COMPLETAR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _buildManualField(
                      label: 'CUOTA BASE (Máx: ${deudaBase.toCurrency()})',
                      ctrl: baseCtrl,
                      onCh: (_) => setInternalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    if (repartoPorMesa) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'MESAS EXTRA (${mesasParaReparto.length})',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.grey.shade700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...mesasParaReparto.map((mesa) {
                        final key = MesasExtraUtils.claveCobro(mesa.n);
                        final label = MesasExtraUtils.tituloCobro(
                          mesa.n,
                          cantMesas,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildManualField(
                            label: '$label (Máx: ${mesa.deuda.toCurrency()})',
                            ctrl: mesaCtrlsPorClave[key]!,
                            onCh: (_) => setInternalState(() {}),
                          ),
                        );
                      }),
                    ] else
                      _buildManualField(
                        label: 'MESA EXTRA (Máx: ${deudaMesa.toCurrency()})',
                        ctrl: mesaCtrl,
                        onCh: (_) => setInternalState(() {}),
                      ),
                    const SizedBox(height: 12),
                    _buildManualField(
                      label: 'SILLAS EXTRAS (Máx: ${deudaSillas.toCurrency()})',
                      ctrl: sillasCtrl,
                      onCh: (_) => setInternalState(() {}),
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'REMANENTE:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
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
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isValid ? Colors.green : Colors.grey,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (!isValid) return;
                  Navigator.pop(ctx, buildResult());
                },
                child: const Text('CONFIRMAR REPARTO'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(disposeCtrls);
  }

  Widget _buildManualField({
    required String label,
    required TextEditingController ctrl,
    required Function(String) onCh,
  }) {
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

  Future<({String tipo, double? monto, Set<int>? cuotasSeleccionadas})?>
  _mostrarOpcionesPago(
    BuildContext context,
    String titulo,
    double deuda, {
    required double cuotaPura,
    required int totalCuotas,
    required double grossHistorico,
  }) {
    final desglose = desgloseCuotasPlan(
      grossHistorico: grossHistorico,
      cuotaPura: cuotaPura,
      totalCuotas: totalCuotas,
    );
    CuotaPlanDetalle? primeraIncompleta;
    for (final c in desglose) {
      if (c.seleccionable) {
        primeraIncompleta = c;
        break;
      }
    }
    final haySeleccionables =
        primeraIncompleta != null && cuotaPura > 0.01 && totalCuotas > 0;
    final subCuotas = primeraIncompleta != null
        ? '${primeraIncompleta.faltante.toCurrency()} (cuota ${primeraIncompleta.numero}/$totalCuotas)'
        : '';

    return showDialog<
      ({String tipo, double? monto, Set<int>? cuotasSeleccionadas})
    >(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1,
              ),
            ),
            const Text(
              'TIPO DE PAGO',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
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
              onTap: () => Navigator.pop(ctx, (
                tipo: 'TOTAL',
                monto: null,
                cuotasSeleccionadas: null,
              )),
            ),
            if (haySeleccionables) ...[
              const SizedBox(height: 8),
              _buildOpcionPagoItem(
                icon: Icons.checklist_rounded,
                label: 'SELECCIONAR CUOTAS',
                sub: subCuotas,
                color: const Color(0xFFD4AF37),
                onTap: () async {
                  final sel = await mostrarDialogoSeleccionCuotasPlan(
                    ctx,
                    titulo: titulo,
                    cuotaPura: cuotaPura,
                    totalCuotas: totalCuotas,
                    grossHistorico: grossHistorico,
                    deudaMaxima: deuda,
                  );
                  if (ctx.mounted && sel != null) {
                    Navigator.pop(ctx, (
                      tipo: 'CUOTAS',
                      monto: sel.monto,
                      cuotasSeleccionadas: sel.cuotasSeleccionadas,
                    ));
                  }
                },
              ),
            ],
            const SizedBox(height: 8),
            _buildOpcionPagoItem(
              icon: Icons.edit_note_rounded,
              label: 'ENTREGA PARCIAL',
              sub: 'Monto a elección',
              color: Colors.white60,
              onTap: () => Navigator.pop(ctx, (
                tipo: 'PARTE',
                monto: null,
                cuotasSeleccionadas: null,
              )),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Future<void> _aplicarResultadoOpcionPago({
    required BuildContext context,
    required StateSetter setModalState,
    required Map<String, double> montosManuales,
    required Map<String, ModoPagoConcepto> modosPagoPorClave,
    required String mapKey,
    required String tituloParcial,
    required double deuda,
    required ({String tipo, double? monto, Set<int>? cuotasSeleccionadas})?
    resultado,
    required void Function(bool selected) onSelected,
    required Future<double?> Function(String titulo, double maximo)
    preguntarMontoParcial,
    required VoidCallback recalcular,
  }) async {
    if (resultado == null) return;
    switch (resultado.tipo) {
      case 'TOTAL':
        setModalState(() {
          onSelected(true);
          montosManuales[mapKey] = deuda;
          modosPagoPorClave[mapKey] = const ModoPagoConcepto(
            tipo: ModoPagoConceptoTipo.total,
          );
        });
      case 'CUOTAS':
        final m = resultado.monto;
        if (m != null && m > 0.01) {
          setModalState(() {
            onSelected(true);
            montosManuales[mapKey] = m;
            modosPagoPorClave[mapKey] = ModoPagoConcepto(
              tipo: ModoPagoConceptoTipo.cuotas,
              cuotasSeleccionadas: resultado.cuotasSeleccionadas,
            );
          });
        }
      case 'PARTE':
        final m = await preguntarMontoParcial(tituloParcial, deuda);
        if (m != null) {
          setModalState(() {
            onSelected(true);
            montosManuales[mapKey] = m;
            modosPagoPorClave[mapKey] = const ModoPagoConcepto(
              tipo: ModoPagoConceptoTipo.parcialLibre,
            );
          });
        }
    }
    recalcular();
  }

  Future<void> _onMesaExtraCobroChanged({
    required BuildContext context,
    required bool? v,
    required MesaExtraItem? mesa,
    required String mesaLabel,
    required String mesaKeyStr,
    required double deuda,
    required double cuotaPura,
    required int totalCuotasPlan,
    required double grossHistorico,
    required StateSetter setModalState,
    required Map<String, double> montosManuales,
    required Map<String, ModoPagoConcepto> modosPagoPorClave,
    required void Function(bool) onPagarMesaChanged,
    required VoidCallback recalcular,
    required Future<double?> Function(String titulo, double maximo)
    preguntarMontoParcial,
    required Future<
      ({String tipo, double? monto, Set<int>? cuotasSeleccionadas})?
    >
    Function(
      BuildContext context,
      String titulo,
      double deuda, {
      required double cuotaPura,
      required int totalCuotas,
      required double grossHistorico,
    })
    mostrarOpcionesPago,
  }) async {
    if (v == true) {
      final choice = await mostrarOpcionesPago(
        context,
        mesaLabel,
        deuda,
        cuotaPura: cuotaPura,
        totalCuotas: totalCuotasPlan,
        grossHistorico: grossHistorico,
      );
      await _aplicarResultadoOpcionPago(
        context: context,
        setModalState: setModalState,
        montosManuales: montosManuales,
        modosPagoPorClave: modosPagoPorClave,
        mapKey: mesaKeyStr,
        tituloParcial: mesaLabel,
        deuda: deuda,
        resultado: choice,
        onSelected: onPagarMesaChanged,
        preguntarMontoParcial: preguntarMontoParcial,
        recalcular: recalcular,
      );
    } else {
      setModalState(() {
        montosManuales.remove(mesaKeyStr);
        modosPagoPorClave.remove(mesaKeyStr);
        onPagarMesaChanged(
          montosManuales.keys.any((k) => k == 'Mesa' || k.startsWith('Mesa:')),
        );
      });
      recalcular();
    }
  }

  Widget _buildOpcionPagoItem({
    required IconData icon,
    required String label,
    required String sub,
    required Color color,
    required VoidCallback onTap,
  }) {
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
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: color.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilaDesglosePreview(
    Map<String, dynamic> c, {
    bool indentada = false,
    bool mostrarBullet = true,
  }) {
    final sub = c['subtexto'] as String?;
    return Padding(
      padding: EdgeInsets.only(bottom: 6, left: indentada ? 16 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mostrarBullet ? '• ${c['concepto']}' : '${c['concepto']}',
                  style: TextStyle(
                    fontSize: indentada ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: indentada ? Colors.grey.shade700 : null,
                  ),
                ),
                if (sub != null && sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 12),
                    child: Text(
                      sub,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            ((c['monto'] as num?)?.toDouble() ?? 0).toCurrency(),
            style: TextStyle(
              fontSize: indentada ? 12 : 13,
              fontWeight: FontWeight.w900,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFilasDesglosePreview({
    required List<Map<String, dynamic>> previewConceptos,
    required bool usarCompactoMesas,
    required bool desgloseMesasExpandido,
    required VoidCallback onToggleDesgloseMesas,
  }) {
    if (previewConceptos.isEmpty) return const [];

    final lineasMesas = previewConceptos
        .where(MesasExtraUtils.esLineaPreviewMesa)
        .toList();
    final agruparMesas = usarCompactoMesas && lineasMesas.isNotEmpty;

    if (!agruparMesas) {
      final widgets = <Widget>[];
      for (final c in previewConceptos) {
        if (c['lineKind'] == kLineKindInteresMora &&
            (c['moraDesglose'] != null ||
                ((c['moraPendientePrevias'] as num?)?.toDouble() ?? 0) > 0.01)) {
          for (final fila in MoraConceptoRotulo.filasPreviewDesdeMora(c)) {
            widgets.add(_buildFilaDesglosePreview(fila));
          }
        } else {
          widgets.add(_buildFilaDesglosePreview(c));
        }
      }
      return widgets;
    }

    final widgets = <Widget>[];
    var grupoMesasEmitido = false;

    for (final c in previewConceptos) {
      if (MesasExtraUtils.esLineaPreviewMesa(c)) {
        if (grupoMesasEmitido) continue;
        grupoMesasEmitido = true;

        final titulo = MesasExtraUtils.tituloGrupoDesgloseMesas(lineasMesas);
        final total = MesasExtraUtils.sumaMontosPreview(lineasMesas);

        widgets.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '• $titulo',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      total.toCurrency(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.green,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: desgloseMesasExpandido
                          ? 'Ocultar detalle'
                          : 'Ver detalle',
                      onPressed: onToggleDesgloseMesas,
                      icon: Icon(
                        desgloseMesasExpandido
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (desgloseMesasExpandido)
                ...lineasMesas.map(
                  (linea) => _buildFilaDesglosePreview(
                    linea,
                    indentada: true,
                    mostrarBullet: false,
                  ),
                ),
            ],
          ),
        );
      } else if (c['lineKind'] == kLineKindInteresMora &&
          (c['moraDesglose'] != null ||
              ((c['moraPendientePrevias'] as num?)?.toDouble() ?? 0) > 0.01)) {
        for (final fila in MoraConceptoRotulo.filasPreviewDesdeMora(c)) {
          widgets.add(_buildFilaDesglosePreview(fila));
        }
      } else {
        widgets.add(_buildFilaDesglosePreview(c));
      }
    }

    return widgets;
  }

  Widget _buildMesasExtraFilaCompacta({
    required MesaExtraItem mesa,
    required int cantMesas,
    required bool isDark,
    required bool selected,
    required double? montoManual,
    required Future<void> Function(bool? v) onChanged,
  }) {
    final label = MesasExtraUtils.tituloCobro(mesa.n, cantMesas);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: selected,
                  onChanged: onChanged,
                  activeColor: const Color(0xFFD4AF37),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Deuda: ${mesa.deuda.toCurrency()}',
                      style: TextStyle(
                        fontSize: 10,
                        color: selected ? const Color(0xFFD4AF37) : Colors.grey,
                      ),
                    ),
                    if (montoManual != null)
                      Text(
                        'ENTREGA: ${montoManual.toCurrency()}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.green,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMesasExtraGrupoCompacto({
    required BuildContext context,
    required bool isDark,
    required List<MesaExtraItem> mesas,
    required int cantMesas,
    required double deudaMesaTotal,
    required Map<String, double> montosManuales,
    required bool expandido,
    required VoidCallback onToggleExpandido,
    required Future<void> Function() onElegirMesas,
    required Future<void> Function(MesaExtraItem mesa, bool? v) onMesaChanged,
  }) {
    final seleccionadas = MesasExtraUtils.contarMesasSeleccionadasCobro(
      montosManuales,
    );
    final cobrandoBruto = MesasExtraUtils.sumaBrutaMesasSeleccionadasCobro(
      montosManuales,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: seleccionadas > 0
            ? const Color(0xFFD4AF37).withValues(alpha: 0.1)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: seleccionadas > 0
              ? const Color(0xFFD4AF37).withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggleExpandido,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.table_bar_rounded,
                    color: seleccionadas > 0
                        ? const Color(0xFFD4AF37)
                        : Colors.grey.shade600,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MESAS EXTRA ($cantMesas)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Deuda total: ${deudaMesaTotal.toCurrency()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (seleccionadas > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Cobrando: $seleccionadas mesa(s) · ${cobrandoBruto.toCurrency()}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    expandido
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onElegirMesas,
                icon: const Icon(Icons.checklist_rounded, size: 16),
                label: const Text(
                  'ELEGIR MESAS…',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD4AF37),
                  side: const BorderSide(color: Color(0xFFD4AF37)),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),
          if (expandido)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: mesas.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                  itemBuilder: (context, index) {
                    final mesa = mesas[index];
                    final key = MesasExtraUtils.claveCobro(mesa.n);
                    final selected = montosManuales.containsKey(key);
                    return _buildMesasExtraFilaCompacta(
                      mesa: mesa,
                      cantMesas: cantMesas,
                      isDark: isDark,
                      selected: selected,
                      montoManual: montosManuales[key],
                      onChanged: (v) => onMesaChanged(mesa, v),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoElegirMesasExtra({
    required BuildContext context,
    required List<MesaExtraItem> mesas,
    required int cantMesas,
    required Map<String, double> montosManuales,
    required StateSetter setModalState,
    required Future<void> Function(MesaExtraItem mesa, bool? v) onMesaChanged,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Elegir mesas extra',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 420,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: mesas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final mesa = mesas[index];
                    final key = MesasExtraUtils.claveCobro(mesa.n);
                    final selected = montosManuales.containsKey(key);
                    return _buildMesasExtraFilaCompacta(
                      mesa: mesa,
                      cantMesas: cantMesas,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                      selected: selected,
                      montoManual: montosManuales[key],
                      onChanged: (v) async {
                        await onMesaChanged(mesa, v);
                        if (ctx.mounted) {
                          setDialogState(() {});
                          setModalState(() {});
                        }
                      },
                    );
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('LISTO'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConceptoTile({
    required String titulo,
    required double deuda,
    required bool isDark,
    required bool selected,
    required Function(bool?) onChanged,
    double? montoManual,
  }) {
    if (deuda <= 0.01) return const SizedBox.shrink();

    final bool esParcial = montoManual != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFD4AF37).withValues(alpha: 0.1)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? const Color(0xFFD4AF37).withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: onChanged,
        activeColor: const Color(0xFFD4AF37),
        title: Text(
          titulo,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deuda: ${deuda.toCurrency()}',
              style: TextStyle(
                fontSize: 11,
                color: selected ? const Color(0xFFD4AF37) : Colors.grey,
              ),
            ),
            if (esParcial)
              Text(
                'ENTREGA: ${montoManual.toCurrency()}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.green,
                ),
              ),
          ],
        ),
        secondary: Icon(
          titulo.contains('BASE')
              ? Icons.calendar_month_rounded
              : (titulo.contains('MESA')
                    ? Icons.table_bar_rounded
                    : Icons.chair_rounded),
          color: selected ? const Color(0xFFD4AF37) : Colors.grey.shade600,
          size: 20,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
