import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/widgets/admin_gate.dart';
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
import '../../core/services/connectivity_service.dart';
import 'services/calculadora_financiera.dart';
import 'services/mora_cuota_calculator.dart';
import 'widgets/contratos_firmados_bulk_dialog.dart';
import 'widgets/modal_alumno_premium.dart';
import 'widgets/nota_operativa_bottom_sheet.dart';
import '../dashboard/providers/dashboard_provider.dart';
import '../mi_empresa/providers/finanzas_provider.dart';

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
  Map<String, MoraCuotaResumen> _moraCache = {};
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
      if (_lazyScrollController.position.pixels >= _lazyScrollController.position.maxScrollExtent - 200) {
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
      final huboCambios = await repo.ejecutarAuditoriaInteligente(widget.evento.id);

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

      // Procesos pesados de sincronización, recálculo y auditoría inteligente en segundo plano
      Future.microtask(() async {
        if (!mounted) return;
        
        // 1. Sincronizar cambios de Supabase de fondo de forma silenciosa
        final connStatus = ref.read(connectivityServiceProvider).currentStatus;
        if (connStatus == AppConnectivity.online) {
          await repo.forceRefresh(widget.evento.id);
        }

        // 2. Reparar huérfanos locales
        final reparados = await repo.repararContratosHuerfanos(
          widget.evento.id,
        );
        if (reparados > 0) {
          debugPrint(
            '🛠️ Se repararon $reparados contratos huérfanos localmente',
          );
        }

        // 3. Recalcular todo el evento y auditorías inteligentes en lote (súper veloz)
        await repo.recalcularTodoElEvento(widget.evento.id);
        await _forzarAuditoriaInteligente(silencioso: true);

        // 4. Refrescar silenciosamente la interfaz al finalizar
        final alumnosActualizados = await repo.getByEvento(widget.evento.id);
        final moraMap2 = await _cargarMoraHistorialMap(repo, alumnosActualizados);
        final moraPeriodoMap2 =
            await _cargarMoraPeriodoMap(repo, alumnosActualizados);
        if (mounted) {
          _aplicarSnapshotAlumnos(
            alumnosActualizados,
            moraMap2,
            moraCobradaPeriodoPorContrato: moraPeriodoMap2,
          );
        }
        await _cargarNotasOperativas();
      });
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
  ) =>
      repo.sumMoraCobradaHistorialPorContratos(alumnos.map((e) => e.id).toList());

  Future<Map<String, double>> _cargarMoraPeriodoMap(
    ContratosRepository repo,
    List<ContratoAlumno> alumnos,
  ) =>
      repo.sumMoraCobradaPeriodoPorContratos(alumnos);

  /// Aplica lista + mora cobrada y reconstruye [_moraCache] en un solo paso.
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
      _moraCache.clear();
      for (final a in _alumnos) {
        _moraCache[a.id] = MoraCuotaCalculator.calcular(a);
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
      _moraCache[contratoId] = MoraCuotaCalculator.calcular(actualizado);
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
    } catch (_) {}
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
          if (!_isLoading) ...[
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
                    visualDensity:
                        layoutCompact ? VisualDensity.compact : VisualDensity.standard,
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

        final double innerTable = tableWidth - (_modoSeleccionContratos ? 52 : 0);
        final double colAlumno = innerTable * 0.20;
        final double colTelefono = innerTable * 0.11;
        final double colAcomp = innerTable * 0.14;
        final double colContrato = innerTable * 0.08;
        final double colEstado = innerTable * 0.25;
                        final double colAcciones = innerTable * 0.26;

        final int contratosFirmados = alumnosFiltrados
            .where((a) => a.contratoFirmado)
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
                    '${alumnosFiltrados.length}',
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
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.45)),
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
                      '$contratosFirmados/${alumnosFiltrados.length}',
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
                  _modoSeleccionContratos ? Icons.close : Icons.checklist_rounded,
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
                  side: BorderSide(color: Colors.teal.shade700, width: layoutCompact ? 1.2 : 1.5),
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
                      visualDensity:
                          layoutCompact ? VisualDensity.compact : VisualDensity.standard,
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
                                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(Icons.touch_app, size: 20, color: Colors.teal.shade800),
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
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _idsSeleccionContratos.isEmpty
                                  ? null
                                  : () => _aplicarContratoFirmadoSeleccionTabla(true),
                              icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                              label: const Text('Marcar firmado'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _idsSeleccionContratos.isEmpty
                                  ? null
                                  : () => _aplicarContratoFirmadoSeleccionTabla(false),
                              style: FilledButton.styleFrom(
                                foregroundColor: Colors.deepOrange.shade900,
                              ),
                              icon: const Icon(Icons.remove_done_rounded, size: 18),
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
                            width: colContrato,
                            child: Text('CONT.', style: tableHeaderStyle),
                          ),
                        ),
                        DataColumn(
                          label: SizedBox(
                            width: colEstado,
                            child: Text('ESTADO DE DEUDA', style: tableHeaderStyle),
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
                        final mora = _moraCache[a.id] ?? MoraCuotaCalculator.calcular(a);
                        final cobradoMoraHist =
                            _moraCobradaPorContrato[a.id] ?? 0.0;
                        final moraPendienteFila =
                            MoraCuotaCalculator.pendienteDisplay(
                          interesAcumulado: mora.interesAcumulado,
                          moraCobradaHistorial: cobradoMoraHist,
                          moraPendienteTracked: a.moraPendienteTracked,
                          moraCobradaOffset: a.moraCobradaOffset,
                          moraCobradaPeriodo:
                              _moraCobradaPeriodoPorContrato[a.id],
                        );

                        final bool estaLiquidado = a.saldoDeudor <= 0.01;
                        final bool esMoraCalendario =
                            !estaLiquidado && mora.enMora;
                        final bool tieneMoraRemanente =
                            !estaLiquidado && moraPendienteFila > 0.01;

                        final Color estadoColor = estaLiquidado
                            ? Colors.greenAccent
                            : (esMoraCalendario
                                  ? Colors.redAccent
                                  : (tieneMoraRemanente
                                        ? Colors.deepOrangeAccent
                                        : const Color(0xFFD4AF37)));

                        final IconData estadoIcono = estaLiquidado
                            ? Icons.verified_rounded
                            : (esMoraCalendario
                                  ? Icons.warning_amber_rounded
                                  : (tieneMoraRemanente
                                        ? Icons.pending_actions_rounded
                                        : Icons.info_outline_rounded));

                        final String estadoTexto = estaLiquidado
                            ? 'LIQUIDADO'
                            : (esMoraCalendario
                                  ? 'MORA VENCIDA'
                                  : (tieneMoraRemanente
                                        ? 'MORA PENDIENTE'
                                        : 'AL DÍA'));

                        final String montoTexto = estaLiquidado
                            ? ''
                            : 'Saldo: ${_ocultarMontos ? '***' : a.saldoDeudor.toCurrency()}';

                        final int cuotasMostrar = estaLiquidado
                            ? totalCuotas
                            : cPagadas;
                        final cuotaInfo =
                            '($cuotasMostrar/$totalCuotas cuotas)';

                        final notaOp = _notasOperativasPorContrato[a.id];

                        return DataRow(
                          selected:
                              _modoSeleccionContratos && _idsSeleccionContratos.contains(a.id),
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
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        margin: EdgeInsets.only(top: layoutCompact ? 2 : 3),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: layoutCompact ? 6 : 8,
                                          vertical: layoutCompact ? 1 : 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue.withValues(
                                              alpha: 0.3,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          a.cursoDivision!,
                                          style: TextStyle(
                                            fontSize: layoutCompact ? 10 : 11,
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
                                            fontSize: layoutCompact ? 9 : 10,
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
                                child: Text(
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
                                child: GestureDetector(
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 0,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        if (a.nombresAcompanantes.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              a.nombresAcompanantes.join(', '),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade600,
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
                                width: colContrato,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(
                                    minWidth: layoutCompact ? 32 : 36,
                                    minHeight: layoutCompact ? 32 : 36,
                                  ),
                                  visualDensity:
                                      layoutCompact ? VisualDensity.compact : VisualDensity.standard,
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
                                  onPressed: () => _toggleContratoFirmado(a),
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
                                          size: layoutCompact ? 14 : 16,
                                        ),
                                        SizedBox(width: layoutCompact ? 4 : 6),
                                        Flexible(
                                          child: Text(
                                            estadoTexto,
                                            style: TextStyle(
                                              color: estadoColor,
                                              fontWeight: FontWeight.w700,
                                              fontSize: layoutCompact ? 11 : 12,
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
                                          fontSize: layoutCompact ? 10 : 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    Text(
                                      cuotaInfo,
                                      style: TextStyle(
                                        fontSize: layoutCompact ? 9 : 10,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (a.saldoDeudor > 0.01 &&
                                        mora.fechaVencimientoProximaCuota !=
                                            null &&
                                        mora.proximaCuotaNumero != null)
                                      Padding(
                                        padding: EdgeInsets.only(top: layoutCompact ? 1 : 2),
                                        child: Text(
                                          'Vto. cuota ${mora.proximaCuotaNumero}: ${ArTime.formatFechaCorta(mora.fechaVencimientoProximaCuota!)}',
                                          style: TextStyle(
                                            fontSize: layoutCompact ? 8 : 9,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    if (moraPendienteFila > 0.01) ...[
                                      Padding(
                                        padding: EdgeInsets.only(top: layoutCompact ? 1 : 2),
                                        child: Text(
                                          'Mora pendiente: ${moraPendienteFila.toCurrency()}',
                                          style: TextStyle(
                                            fontSize: layoutCompact ? 8 : 9,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                      Builder(builder: (_) {
                                        final desglose = MoraCuotaCalculator.calcularDesglose(a);
                                        if (desglose.isEmpty) return const SizedBox.shrink();
                                        final resumen = desglose
                                            .map((d) => 'C${d.numeroCuota} (${d.mesLabel.split(' ').first}) ${d.diasMora}d')
                                            .join(' · ');
                                        return Padding(
                                          padding: EdgeInsets.only(top: layoutCompact ? 0 : 1),
                                          child: Text(
                                            resumen,
                                            style: TextStyle(
                                              fontSize: layoutCompact ? 7 : 8,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.orange.shade600,
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                                      Icons.edit_outlined,
                                      size: layoutCompact ? 18 : 20,
                                    ),
                                    tooltip: 'Editar alumno/cuotas',
                                    onPressed: () =>
                                        _mostrarModalEditarAlumno(a),
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
                                      Icons.payments_outlined,
                                      size: layoutCompact ? 18 : 20,
                                    ),
                                    tooltip: 'Registrar pago',
                                    onPressed: () => _mostrarModalPagoAlumno(a),
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
                                      Icons.account_balance_wallet_outlined,
                                      size: layoutCompact ? 18 : 20,
                                      color: const Color(0xFFD4AF37),
                                    ),
                                    tooltip: 'Ver Estado de Cuenta',
                                    onPressed: () =>
                                        _mostrarHistorialPagosAlumno(a),
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
                                      Icons.picture_as_pdf_outlined,
                                      size: layoutCompact ? 18 : 20,
                                    ),
                                    tooltip: 'Generar Recibo',
                                    onPressed: () => _imprimirReciboAlumno(a),
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
                                    tooltip:
                                        'Nota operativa — no cambia montos ni cuotas',
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
                                    icon: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.center,
                                      children: [
                                        Icon(
                                          notaOp != null && notaOp.tieneTexto
                                              ? (notaOp.resuelto
                                                  ? Icons.task_alt_rounded
                                                  : Icons.sticky_note_2_outlined)
                                              : Icons.note_add_outlined,
                                          size: layoutCompact ? 18 : 20,
                                          color: notaOp != null && notaOp.tieneTexto
                                              ? (notaOp.resuelto
                                                  ? Colors.teal.shade600
                                                  : const Color(0xFFD4AF37))
                                              : Colors.blueGrey.withValues(alpha: 0.45),
                                        ),
                                        if (notaOp != null &&
                                            notaOp.tieneTexto &&
                                            !notaOp.resuelto)
                                          Positioned(
                                            right: layoutCompact ? -4 : -5,
                                            top: layoutCompact ? -3 : -4,
                                            child: Container(
                                              width: layoutCompact ? 7 : 8,
                                              height: layoutCompact ? 7 : 8,
                                              decoration: BoxDecoration(
                                                color: Colors.deepOrangeAccent,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
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
        content: Text(
          '¿Está seguro de que desea dar de baja a ${alumno.nombreAlumno}? Esta acción conservará el registro pero no contará para los saldos.',
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
            child: const Text('DAR DE BAJA'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final repo = ref.read(contratosRepositoryProvider);
      try {
        await repo.actualizarContrato(alumno.id, {
          'nombre_alumno': '[BAJA] ${alumno.nombreAlumno}',
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
            SnackBar(
              content: Text('Error al dar de baja alumno: $e'),
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
    final maxMesasCtrl = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sortear Mesas al Azar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se asignarán números de mesa a los alumnos que aún no tienen una asignada.',
            ),
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

      final alumnosSinMesa = _alumnos
          .where(
            (a) =>
                !a.nombreAlumno.startsWith('[BAJA]') &&
                (a.numeroMesa == null || a.numeroMesa!.isEmpty),
          )
          .toList();
      if (alumnosSinMesa.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos los alumnos ya tienen mesa asignada.'),
            ),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Se asignaron mesas a $actualizados alumnos.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error en sorteo: $e');
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

  Future<void> _deshacerSorteoMesas() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deshacer Asignación de Mesas'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar las mesas asignadas a TODOS los alumnos de este evento?',
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Se eliminaron las mesas de $actualizados alumnos.'),
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
    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContratosFirmadosBulkDialog(
        alumnos: activos,
        repository: repo,
        eventoTitulo: tituloEvento,
      ),
    );
    if (mounted && guardado == true) {
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
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
    try {
      await ref.read(contratosRepositoryProvider).actualizarContratoFirmadoBulk(map);
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
              firmado ? 'Contratos marcados como firmados.' : 'Se quitó la marca de contrato firmado.',
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
    try {
      await repo.actualizarContrato(alumno.id, {'contrato_firmado': nuevo});
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
    if (mounted && result == true) _refreshAlumnos();
  }

  Future<void> _mostrarModalPagoAlumno(ContratoAlumno alumno) async {
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
    final cRepo = ref.read(contratosRepositoryProvider);
    final moraYaCobradaHist = await cRepo.sumMoraCobradaHistorial(alumno.id);
    final pagosAlumno = await cRepo.getHistorialPagosAlumno(alumno.id);
    final moraResumen = MoraCuotaCalculator.calcular(alumno);
    final moraPeriodo = moraCobradaDelPeriodoVigente(
      pagosAlumno,
      inicioMoraPeriodoVigente(moraResumen.fechaVencimientoProximaCuota),
    );
    final double moraPendienteUi = MoraCuotaCalculator.pendienteDisplay(
      interesAcumulado: moraResumen.interesAcumulado,
      moraCobradaHistorial: moraYaCobradaHist,
      moraPendienteTracked: alumno.moraPendienteTracked,
      moraCobradaOffset: alumno.moraCobradaOffset,
      moraCobradaPeriodo: moraPeriodo,
    );

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

    final double deudaMesaTotal =
        (alumno.mesaExtraPrecio - (alumno.mesaExtraPagado ?? 0)).clamp(
          0.0,
          double.infinity,
        );
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
        (alumno.saldoDeudor - deudaMesaTotal - deudaSillasTotal).clamp(
          0.0,
          double.infinity,
        );

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

    final moraDesglose = MoraCuotaCalculator.calcularDesglose(alumno);
    final moraTotalDesglose = moraDesglose.fold<double>(0, (s, d) => s + d.interesBruto);
    final double moraPendienteEfectivo = moraDesglose.isNotEmpty
        ? math.max(moraPendienteUi, moraTotalDesglose)
        : moraPendienteUi;
    Set<int> moraCuotasSeleccionadas = {};

    if (moraPendienteEfectivo > 0.01) {
      moraMontoCobroCtrl.text = moraPendienteEfectivo.toFormattedNumber();
    }

    bool pagarBase = false;
    bool pagarMesa = false;
    bool pagarSillas = false;
    bool incluirInteresCuota = false;
    Map<String, double> montosManuales = {};
    List<Map<String, dynamic>> previewConceptos = [];

    bool esLineaInteresMora(Map<String, dynamic> c) =>
        c['lineKind'] == 'interes_mora';

    bool esLineaCargoCanal(Map<String, dynamic> c) =>
        c['lineKind'] == 'cargo_canal_ref';

    Map<String, dynamic> lineaPreviewInteresMora(double monto, [List<MoraCuotaDetalle>? cuotasSel]) {
      final g = double.parse(
        monto.clamp(0.0, double.infinity).toStringAsFixed(2),
      );
      final detalles = cuotasSel ?? <MoraCuotaDetalle>[];
      String concepto;
      if (detalles.length == 1) {
        final d = detalles.first;
        concepto = 'Interés mora cuota ${d.numeroCuota} (${d.mesLabel})';
      } else if (detalles.length > 1) {
        final nums = detalles.map((d) => d.numeroCuota).join(', ');
        final meses = detalles.map((d) => d.mesLabel.split(' ').first).join(', ');
        concepto = 'Interés mora cuotas $nums ($meses)';
      } else {
        concepto = 'Interés mora (cuota base — este cobro)';
      }
      return {
        'concepto': concepto,
        'monto': g,
        'gross': g,
        'cuotas': 0,
        'lineKind': 'interes_mora',
        'moraDesglose': detalles.map((d) => <String, dynamic>{
          'numeroCuota': d.numeroCuota,
          'mesLabel': d.mesLabel,
          'monto': d.interesBruto,
          'diasMora': d.diasMora,
        }).toList(),
      };
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
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<MoraCuotaDetalle> moraCuotasSeleccionadasList() {
              return moraDesglose.where((d) => moraCuotasSeleccionadas.contains(d.numeroCuota)).toList();
            }

            double moraMontoSeleccionado() {
              final sel = moraCuotasSeleccionadasList();
              if (sel.isEmpty) return 0;
              return sel.fold<double>(0, (s, d) => s + d.interesBruto);
            }

            double montoMoraLineaIngresado() {
              double v = CurrencyInputFormatter.parse(moraMontoCobroCtrl.text);
              if (v < 0) v = 0;
              if (moraPendienteEfectivo > 0.01 && v > moraPendienteEfectivo + 0.01) {
                v = moraPendienteEfectivo;
              }
              return double.parse(v.toStringAsFixed(2));
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
              final liquidoTr =
                  (sumL - e).clamp(0.0, double.infinity);
              final cargo = informarPctTransferExterno
                  ? cargoSobreLiquidoTransferencia(liquidoTr)
                  : 0.0;
              transferMixCtrl.text =
                  double.parse((liquidoTr + cargo).toStringAsFixed(2))
                      .toFormattedNumber();
              montoPagarCtrl.text =
                  double.parse((sumL + cargo).toStringAsFixed(2))
                      .toFormattedNumber();
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
                liquidoTrParaCargo =
                    (sumL - e).clamp(0.0, double.infinity);
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

              final totalMostrar =
                  double.parse((sumL + cargo).toStringAsFixed(2));
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
              final newE =
                  (sumL - L).clamp(0.0, double.infinity);
              efectivoMixCtrl.text = newE.toFormattedNumber();
              final cargoSync = cargoSobreLiquidoTransferencia(L);
              final totalEsperadoCanal =
                  double.parse((L + cargoSync).toStringAsFixed(2));
              if ((totalEsperadoCanal - T).abs() > 0.03) {
                transferMixCtrl.text =
                    totalEsperadoCanal.toFormattedNumber();
              }
              finalizarPreviewConCargoCanal();
            }

            double montoTransferenciaParaCargoInforme() {
              return liquidoTransferenciaBaseParaCargoInforme();
            }

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

            Map<String, dynamic> calcularDesgloseInteligente(
              String conceptoKey,
              String label,
              double gross,
              double net,
              double qPura,
            ) {
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
                  int proxCuota = (conceptoKey == 'Base')
                      ? (cPagadas + cuotasCompletas + 1)
                      : 0;
                  if (conceptoKey == 'Base') {
                    conceptoFinal =
                        '$cuotasCompletas Cuotas + Adelanto (C$proxCuota)';
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
                'cuotas': cant,
              };
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
              if (!manually) montosManuales.clear();

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
                  } else if (key == 'Mesa') {
                    qPura =
                        alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1);
                    label = 'Mesa Extra';
                  } else if (key == 'Sillas') {
                    qPura =
                        alumno.sillasExtraPrecioTotal /
                        (sCuotas > 0 ? sCuotas : 1);
                    label = 'Sillas Extras';
                  }

                  final desglose = calcularDesgloseInteligente(
                    key,
                    label,
                    gross,
                    net,
                    qPura,
                  );
                  previewConceptos.add(desglose);
                });
                final bool cobrandoBaseManual =
                    montosManuales.containsKey('Base') &&
                    ((montosManuales['Base'] ?? 0) > 0.01);
                if (incluirInteresCuota &&
                    cobrandoBaseManual &&
                    moraPendienteEfectivo > 0.01) {
                  final mm = montoMoraLineaIngresado();
                  if (mm > 0.01) {
                    previewConceptos.add(lineaPreviewInteresMora(mm, moraCuotasSeleccionadasList()));
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

              if (incluirInteresCuota && !pagarBase) {
                incluirInteresCuota = false;
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

                final desglose = calcularDesgloseInteligente(
                  key,
                  label,
                  gross,
                  net,
                  qPura,
                );
                previewConceptos.add(desglose);
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
              if (pagarMesa && deudaMesaTotal > 0.01) {
                procesarConcepto(
                  'Mesa',
                  'Mesa Extra',
                  deudaMesaTotal,
                  alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1),
                );
              }
              if (pagarSillas && deudaSillasTotal > 0.01) {
                procesarConcepto(
                  'Sillas',
                  'Sillas Extras',
                  deudaSillasTotal,
                  alumno.sillasExtraPrecioTotal / (sCuotas > 0 ? sCuotas : 1),
                );
              }

              if (incluirInteresCuota && pagarBase && moraPendienteEfectivo > 0.01) {
                final mm = montoMoraLineaIngresado();
                if (mm > 0.01) {
                  previewConceptos.add(lineaPreviewInteresMora(mm, moraCuotasSeleccionadasList()));
                  totalAcumuladoNeto += mm;
                }
              }

              finalizarPreviewConCargoCanal();
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
                      if (moraResumen.fechaVencimientoProximaCuota != null ||
                          moraResumen.enMora ||
                          moraResumen.diasMora > 0 ||
                          moraDesglose.isNotEmpty ||
                          moraPendienteEfectivo > 0.01)
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
                                  'REFERENCIA MORA / INTERÉS (cuota base)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.orange.shade900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (moraDesglose.isNotEmpty) ...[
                                  ...moraDesglose.map((d) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      children: [
                                        Icon(Icons.event_busy_rounded, size: 14, color: Colors.orange.shade700),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Cuota ${d.numeroCuota} (${d.mesLabel}) — vto. ${ArTime.formatFechaCorta(d.vencimiento)} — ${d.diasMora} días',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                                          ),
                                        ),
                                        Text(
                                          d.interesBruto.toCurrency(),
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange.shade900),
                                        ),
                                      ],
                                    ),
                                  )),
                                ] else ...[
                                  if (moraResumen.fechaVencimientoProximaCuota != null &&
                                      moraResumen.proximaCuotaNumero != null)
                                    Text(
                                      'Próx. venc.: ${ArTime.formatFechaCorta(moraResumen.fechaVencimientoProximaCuota!)} (cuota ${moraResumen.proximaCuotaNumero}/$tCuotas)',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                                    ),
                                  Text(
                                    'Días de atraso: ${moraResumen.diasMora}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                                  ),
                                ],
                                if (moraPendienteEfectivo > 0.01)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Mora pendiente total: ${moraPendienteEfectivo.toCurrency()}${moraYaCobradaHist > 0.01 ? ' · Ya cobrada: ${moraYaCobradaHist.toCurrency()}' : ''}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                  )
                                else if (moraResumen.interesAcumulado > 0.01)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Sin mora pendiente respecto al cálculo de hoy.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'Podés incluir mora en este cobro; no forma parte del saldo del plan ni liquida cuotas extra. Podés abonar un monto parcial; el resto sigue pendiente y se recalcula día a día.',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                if (moraPendienteEfectivo > 0.01) ...[
                                  const SizedBox(height: 8),
                                  if (!pagarBase)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        'Marcá primero CUOTA BASE para aplicar mora a esta liquidación.',
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                                      ),
                                    ),
                                  if (moraDesglose.isNotEmpty) ...[
                                    Text(
                                      'MORA POR CUOTA VENCIDA',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.orange.shade900,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ...moraDesglose.map((d) {
                                      final sel = moraCuotasSeleccionadas.contains(d.numeroCuota);
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: CheckboxListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          controlAffinity: ListTileControlAffinity.leading,
                                          value: sel,
                                          onChanged: pagarBase
                                              ? (v) {
                                                  setModalState(() {
                                                    if (v == true) {
                                                      moraCuotasSeleccionadas.add(d.numeroCuota);
                                                    } else {
                                                      moraCuotasSeleccionadas.remove(d.numeroCuota);
                                                    }
                                                    incluirInteresCuota = moraCuotasSeleccionadas.isNotEmpty;
                                                    if (incluirInteresCuota) {
                                                      moraMontoCobroCtrl.text = moraMontoSeleccionado().toFormattedNumber();
                                                    }
                                                    recalcularDesdeChecks();
                                                  });
                                                }
                                              : null,
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Cuota ${d.numeroCuota} (${d.mesLabel}) — ${d.diasMora} días',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.orange.shade900,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                d.interesBruto.toCurrency(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w900,
                                                  color: sel ? Colors.orange.shade900 : Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                    if (moraCuotasSeleccionadas.isNotEmpty && pagarBase) ...[
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: moraMontoCobroCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [CurrencyInputFormatter()],
                                        decoration: InputDecoration(
                                          labelText: 'Monto mora a cobrar ahora',
                                          prefixIcon: Icon(Icons.percent_rounded, color: Colors.orange.shade800, size: 20),
                                          filled: true,
                                          fillColor: Colors.orange.withValues(alpha: 0.05),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                        onChanged: (_) => setModalState(() => recalcularDesdeChecks()),
                                      ),
                                    ],
                                  ] else ...[
                                    CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      value: incluirInteresCuota,
                                      onChanged: pagarBase
                                          ? (v) {
                                              setModalState(() {
                                                incluirInteresCuota = v ?? false;
                                                if (incluirInteresCuota) {
                                                  moraMontoCobroCtrl.text = moraPendienteEfectivo.toFormattedNumber();
                                                }
                                                recalcularDesdeChecks();
                                              });
                                            }
                                          : null,
                                      title: Text(
                                        'Incluir mora en este cobro (${moraPendienteEfectivo.toCurrency()})',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange.shade900),
                                      ),
                                    ),
                                    if (incluirInteresCuota && pagarBase) ...[
                                      TextField(
                                        controller: moraMontoCobroCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [CurrencyInputFormatter()],
                                        decoration: InputDecoration(
                                          labelText: 'Monto mora a cobrar ahora',
                                          prefixIcon: Icon(Icons.percent_rounded, color: Colors.orange.shade800, size: 20),
                                          filled: true,
                                          fillColor: Colors.orange.withValues(alpha: 0.05),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                        onChanged: (_) => setModalState(() => recalcularDesdeChecks()),
                                      ),
                                    ],
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
                            int restantes = tCuotas - cPagadas;
                            final choice = await _mostrarOpcionesPago(
                              context,
                              'Cuota Base',
                              deudaBaseTotal,
                              cuotaUnica: cuotaPura,
                              cuotasRestantes: restantes,
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
                              final n = await _mostrarDialogoSeleccionCuotas(
                                context,
                                'Cuota Base',
                                restantes,
                              );
                              if (n != null) {
                                setModalState(() {
                                  pagarBase = true;
                                  montosManuales['Base'] = cuotaPura * n;
                                });
                              }
                            } else if (choice == 'PARTE') {
                              final m = await preguntarMontoParcial(
                                'Cuota Base',
                                deudaBaseTotal,
                              );
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
                              incluirInteresCuota = false;
                              montosManuales['Base'] = deudaBaseTotal;
                            });
                          }
                          recalcularDesdeChecks();
                        },
                      ),
                      if (deudaMesaTotal > 0.01)
                        _buildConceptoTile(
                          titulo: 'MESA EXTRA',
                          deuda: deudaMesaTotal,
                          isDark:
                              Theme.of(context).brightness == Brightness.dark,
                          selected: pagarMesa,
                          montoManual: montosManuales['Mesa'],
                          onChanged: (v) async {
                            if (v == true) {
                              double pureMesa =
                                  alumno.mesaExtraPrecio /
                                  (mCuotas > 0 ? mCuotas : 1);
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
                                  montosManuales['Mesa'] = deudaMesaTotal;
                                });
                              } else if (choice == 'UNICA') {
                                setModalState(() {
                                  pagarMesa = true;
                                  montosManuales['Mesa'] = pureMesa;
                                });
                              } else if (choice == 'VARIAS') {
                                final n = await _mostrarDialogoSeleccionCuotas(
                                  context,
                                  'Mesa Extra',
                                  restMesa,
                                );
                                if (n != null) {
                                  setModalState(() {
                                    pagarMesa = true;
                                    montosManuales['Mesa'] = pureMesa * n;
                                  });
                                }
                              } else if (choice == 'PARTE') {
                                final m = await preguntarMontoParcial(
                                  'Mesa Extra',
                                  deudaMesaTotal,
                                );
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
                          },
                        ),
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
                              double pureSilla =
                                  alumno.sillasExtraPrecioTotal /
                                  (sCuotas > 0 ? sCuotas : 1);
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
                                  montosManuales['Sillas'] = deudaSillasTotal;
                                });
                              } else if (choice == 'UNICA') {
                                setModalState(() {
                                  pagarSillas = true;
                                  montosManuales['Sillas'] = pureSilla;
                                });
                              } else if (choice == 'VARIAS') {
                                final n = await _mostrarDialogoSeleccionCuotas(
                                  context,
                                  'Sillas Extras',
                                  restSillas,
                                );
                                if (n != null) {
                                  setModalState(() {
                                    pagarSillas = true;
                                    montosManuales['Sillas'] = pureSilla * n;
                                  });
                                }
                              } else if (choice == 'PARTE') {
                                final m = await preguntarMontoParcial(
                                  'Sillas Extras',
                                  deudaSillasTotal,
                                );
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
                              final cargo =
                                  cargoSobreLiquidoTransferencia(liq);
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
                                (s, c) =>
                                    s + (c['monto'] as num).toDouble(),
                              );
                              if (sumL > 0.01) {
                                final mitad = sumL / 2;
                                efectivoMixCtrl.text =
                                    mitad.toFormattedNumber();
                              } else {
                                final t = CurrencyInputFormatter.parse(
                                  montoPagarCtrl.text,
                                );
                                if (t > 0.01) {
                                  final mitad = t / 2;
                                  efectivoMixCtrl.text =
                                      mitad.toFormattedNumber();
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
                                              moraPendienteUi > 0.01)
                                          ? montoMoraLineaIngresado()
                                          : 0.0;
                                      final capitalParaDialogo =
                                          (total - interesDist).clamp(
                                            0.0,
                                            double.infinity,
                                          );
                                      final result =
                                          await _mostrarDialogoDistribucionManual(
                                            context: context,
                                            total: capitalParaDialogo,
                                            deudaBase: deudaBaseTotal,
                                            deudaMesa: deudaMesaTotal,
                                            deudaSillas: deudaSillasTotal,
                                            currentBase: montosManuales['Base'],
                                            currentMesa: montosManuales['Mesa'],
                                            currentSillas:
                                                montosManuales['Sillas'],
                                          );
                                      if (result != null) {
                                        setModalState(() {
                                          if (result['Base']! > 0)
                                            montosManuales['Base'] =
                                                result['Base']!;
                                          else
                                            montosManuales['Base'] =
                                                deudaBaseTotal;
                                          if (result['Mesa']! > 0)
                                            montosManuales['Mesa'] =
                                                result['Mesa']!;
                                          else
                                            montosManuales.remove('Mesa');
                                          if (result['Sillas']! > 0)
                                            montosManuales['Sillas'] =
                                                result['Sillas']!;
                                          else
                                            montosManuales.remove('Sillas');
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
                              ...previewConceptos.map(
                                (c) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '• ${c['concepto']}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        (c['monto'] as num)
                                            .toDouble()
                                            .toCurrency(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
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
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded),
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
                  onPressed: () async {
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
                      transferCanalMixtoPdf = CurrencyInputFormatter.parse(
                        transferMixCtrl.text,
                      ).clamp(0.0, double.infinity);
                      parteTransferencia = liquidoTransferenciaDesdeTotalMixto(
                        transferCanalMixtoPdf,
                      );
                      if ((parteEfectivo + parteTransferencia - sumLiquidoCobro)
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
                          ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);
                      final double cGross = (conc['gross'] as num).toDouble();
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

                    double saldoRestanteCalculado =
                        alumno.saldoDeudor - totalDeducidoBruto;
                    double saldoRestante = double.parse(
                      saldoRestanteCalculado.toStringAsFixed(2),
                    ).clamp(0.0, double.infinity);

                    int currentBasePagadas = (cPagadas + nuevasBase).clamp(
                      0,
                      tCuotas,
                    );
                    int currentMesaPagadas = (mPagadas + nuevasMesa).clamp(
                      0,
                      mCuotas > 0 ? mCuotas : 1,
                    );
                    int currentSillasPagadas = (sPagadas + nuevasSillas).clamp(
                      0,
                      sCuotas > 0 ? sCuotas : 1,
                    );

                    if (saldoRestante <= 0.01) {
                      currentBasePagadas = tCuotas;
                      currentMesaPagadas =
                          (alumno.mesaExtraPrecio > 0 && mCuotas > 0)
                          ? mCuotas
                          : 0;
                      currentSillasPagadas =
                          (alumno.sillasExtraPrecioTotal > 0 && sCuotas > 0)
                          ? sCuotas
                          : 0;
                    }

                    List<Map<String, dynamic>> conceptosFinales = [];
                    int contadorBaseFinal = 0;
                    int contadorMesaFinal = 0;
                    int contadorSillasFinal = 0;
                    for (var conc in previewConceptos) {
                      // Cargo canal: incluirlo como concepto visible en el PDF
                      if (esLineaCargoCanal(conc)) {
                        final double cargoMonto = double.parse(
                          ((conc['monto'] as num).toDouble())
                              .toStringAsFixed(2),
                        );
                        if (cargoMonto > 0.01) {
                          conceptosFinales.add({
                            'concepto':
                                'Cargo oper. transferencia (MP u otro)',
                            'monto': cargoMonto,
                          });
                        }
                        continue;
                      }
                      final String cTexto = conc['concepto'] as String;
                      final double cMontoRaw = (conc['monto'] as num)
                          .toDouble();
                      final double cMonto = double.parse(
                        cMontoRaw.toStringAsFixed(2),
                      );
                      final int cCuotasConc =
                          ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);

                      String cRico = cTexto;
                      if (esLineaInteresMora(conc)) {
                        final desg = conc['moraDesglose'] as List<Map<String, dynamic>>?;
                        if (desg != null && desg.isNotEmpty) {
                          final double totalBrutoDesg = desg.fold<double>(0, (s, d) => s + (d['monto'] as num).toDouble());
                          for (final d in desg) {
                            final proportion = totalBrutoDesg > 0.01 ? (d['monto'] as num).toDouble() / totalBrutoDesg : 1.0 / desg.length;
                            final montoLinea = double.parse((cMonto * proportion).toStringAsFixed(2));
                            conceptosFinales.add({
                              'concepto': 'Interés mora cuota ${d['numeroCuota']} (${d['mesLabel']})',
                              'monto': montoLinea,
                            });
                          }
                          continue;
                        }
                        cRico = 'Interés mora (cuota base — este cobro)';
                      } else if (cTexto.toUpperCase().contains('MESA')) {
                        if (mCuotas <= 1) {
                          cRico = 'Mesa Extra - Entrega';
                        } else if (cCuotasConc == 1) {
                          cRico =
                              'Mesa Extra (${mPagadas + contadorMesaFinal + 1}/$mCuotas)';
                        } else if (cCuotasConc > 1) {
                          cRico =
                              '$cCuotasConc Cuotas Mesa Extra (${mPagadas + contadorMesaFinal + 1}-${mPagadas + contadorMesaFinal + cCuotasConc}/$mCuotas)';
                        } else {
                          cRico =
                              'Abono Mesa Extra (${mPagadas + contadorMesaFinal + 1}/$mCuotas)';
                        }
                        contadorMesaFinal += cCuotasConc;
                      } else if (cTexto.toUpperCase().contains('SILLA')) {
                        if (sCuotas <= 1) {
                          cRico = 'Sillas Extras - Entrega';
                        } else if (cCuotasConc == 1) {
                          cRico =
                              'Sillas Extras (${sPagadas + contadorSillasFinal + 1}/$sCuotas)';
                        } else if (cCuotasConc > 1) {
                          cRico =
                              '$cCuotasConc Cuotas Sillas Extras (${sPagadas + contadorSillasFinal + 1}-${sPagadas + contadorSillasFinal + cCuotasConc}/$sCuotas)';
                        } else {
                          cRico =
                              'Abono Sillas Extras (${sPagadas + contadorSillasFinal + 1}/$sCuotas)';
                        }
                        contadorSillasFinal += cCuotasConc;
                      } else if (cTexto.toUpperCase().contains('BASE')) {
                        if (cCuotasConc == 1) {
                          cRico =
                              'Cuota Base (${cPagadas + contadorBaseFinal + 1}/$tCuotas)';
                        } else if (cCuotasConc > 1) {
                          cRico =
                              '$cCuotasConc Cuotas Base (${cPagadas + contadorBaseFinal + 1}-${cPagadas + contadorBaseFinal + cCuotasConc}/$tCuotas)';
                        } else {
                          cRico =
                              'Abono Cuota Base (${cPagadas + contadorBaseFinal + 1}/$tCuotas)';
                        }
                        contadorBaseFinal += cCuotasConc;
                      }

                      conceptosFinales.add({
                        'concepto': cRico,
                        'monto': cMonto,
                      });
                    }

                    // 2. CREACIÓN DEL CLON LOCAL INMEDIATO (copyWith directo)
                    final alumnoFresco = alumno.copyWith(
                      saldoDeudor: saldoRestante,
                      cuotasPagadas: currentBasePagadas,
                      mesaExtraCuotasPagadas: currentMesaPagadas,
                      sillasExtraCuotasPagadas: currentSillasPagadas,
                      mesaExtraPagado:
                          (alumno.mesaExtraPagado) + grossMesaPagado,
                      sillasExtraPagado:
                          (alumno.sillasExtraPagado) + grossSillasPagado,
                    );

                    // Actualizamos la pantalla de fondo al instante (sin esperar a Supabase)
                    final index = _alumnos.indexWhere((a) => a.id == alumno.id);
                    if (index != -1) {
                      final moraEste = previewConceptos
                          .where(esLineaInteresMora)
                          .fold<double>(
                            0,
                            (s, c) => s + (c['monto'] as num).toDouble(),
                          );
                      double trackedNuevo = moraPendienteEfectivo;
                      if (moraEste > 0.01) {
                        trackedNuevo = (moraPendienteEfectivo - moraEste)
                            .clamp(0.0, double.infinity);
                      }
                      _patchAlumnoLocal(
                        alumno.id,
                        alumnoFresco.copyWith(moraPendienteTracked: trackedNuevo),
                        moraCobradaExtra: moraEste,
                      );
                    }

                    await prefsMedio.setString(
                      'medio_pago_cobro_masivo',
                      modoMedioPago,
                    );
                    await prefsMedio.setString(
                      'cobro_masivo_pct_transfer_info',
                      pctTransferInfoCtrl.text.trim(),
                    );
                    await prefsMedio.setString(
                      'cobro_masivo_transfer_cargo_modo',
                      transferCargoModo,
                    );
                    await prefsMedio.setString(
                      'cobro_masivo_transfer_cargo_monto',
                      transferCargoMontoCtrl.text.trim(),
                    );
                    await prefsMedio.setBool(
                      'cobro_masivo_informar_pct_transfer',
                      informarPctTransferExterno,
                    );

                    final double pctCargoInforme =
                        double.tryParse(
                          pctTransferInfoCtrl.text.replaceAll(',', '.').trim(),
                        ) ??
                        0;
                    final double montoCargoInformeParsed =
                        CurrencyInputFormatter.parse(
                          transferCargoMontoCtrl.text,
                        );

                    // Cerramos la ventana de cobro y disparamos el recibo PDF con el CLON PERFECTO
                    if (context.mounted) {
                      Navigator.pop(context, true);

                      _imprimirReciboAlumno(
                        alumnoFresco,
                        montoPagado: montoIngresado,
                        saldoPendiente: saldoRestante,
                        conceptosPagados: conceptosFinales,
                        fechaManual: DateTime.now(),
                        medioPago: modoMedioPago == 'Mixto'
                            ? 'Mixto'
                            : modoMedioPago,
                        montoEfectivoDetalle: modoMedioPago == 'Mixto'
                            ? parteEfectivo
                            : null,
                        montoTransferenciaDetalle: modoMedioPago == 'Mixto'
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
                        skipDbRefresh:
                            true, // EXIGE que se use el clon local, ignorando los tiempos de Supabase
                      );
                    }

                    // 3. SINCRONIZACIÓN DE LA BASE DE DATOS EN SEGUNDO PLANO (SILENCIOSA)
                    Future.microtask(() async {
                      try {
                        final repo = ref.read(contratosRepositoryProvider);
                        final descStr = porcentajeDescuentoCtrl.text;
                        final tIng = parteEfectivo + parteTransferencia;
                        final sumNetas = previewConceptos
                            .where((c) => !esLineaCargoCanal(c))
                            .fold<double>(
                              0,
                              (s, c) =>
                                  s + (c['monto'] as num).toDouble(),
                            );

                        Future<void> registrarLineaUna(
                          Map<String, dynamic> conc,
                        ) async {
                          final cTexto = conc['concepto'] as String;
                          final monto = (conc['monto'] as num).toDouble();
                          final gross =
                              (conc['gross'] as num?)?.toDouble() ?? monto;
                          final cCuotas =
                              ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(
                                0,
                                99,
                              );
                          final lineKind = conc['lineKind'] as String?;

                          // Cargo canal: se registra como ingreso real
                          // (Transferencia) para que figure en cierre de caja,
                          // pero con gross=0 para no afectar saldo del alumno.
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
                              );
                            }
                            return;
                          }

                          if (tIng < 0.01 || sumNetas < 0.01) return;

                          double mE;
                          double mT;
                          double gE;
                          double gT;
                          if (modoMedioPago == 'Mixto') {
                            final rE = parteEfectivo / tIng;
                            mE = double.parse((monto * rE).toStringAsFixed(2));
                            mT = double.parse((monto - mE).toStringAsFixed(2));
                            gE = double.parse((gross * rE).toStringAsFixed(2));
                            gT = double.parse((gross - gE).toStringAsFixed(2));
                          } else if (modoMedioPago == 'Efectivo') {
                            mE = monto;
                            mT = 0;
                            gE = gross;
                            gT = 0;
                          } else {
                            mE = 0;
                            mT = monto;
                            gE = 0;
                            gT = gross;
                          }

                          Future<void> uno(
                            double m,
                            double mg,
                            String med,
                            int cq,
                          ) async {
                            if (m <= 0.004) return;
                            await repo.registrarPago(
                              contratoId: alumno.id,
                              monto: m,
                              concepto: cTexto,
                              montoADescontarDeSaldo: mg,
                              descuentoPorcentaje:
                                  double.tryParse(descStr) ?? 0,
                              cuotasLiquidadas: cq,
                              medioPago: med,
                              lineKind: lineKind,
                              // Snapshot pre-lote: evita que el avance de
                              // cuotas_pagadas (por la línea base ya
                              // persistida) borre el remanente de mora.
                              moraPendienteAntesDeLote:
                                  lineKind == kLineKindInteresMora
                                      ? moraPendienteEfectivo
                                      : null,
                            );
                          }

                          if (mE <= 0.004 && mT > 0.004) {
                            await uno(mT, gT, 'Transferencia', cCuotas);
                          } else if (mT <= 0.004 && mE > 0.004) {
                            await uno(mE, gE, 'Efectivo', cCuotas);
                          } else if (mE >= mT) {
                            await uno(mE, gE, 'Efectivo', cCuotas);
                            await uno(mT, gT, 'Transferencia', 0);
                          } else {
                            await uno(mT, gT, 'Transferencia', cCuotas);
                            await uno(mE, gE, 'Efectivo', 0);
                          }
                        }

                        for (final conc in previewConceptos) {
                          await registrarLineaUna(conc);
                        }

                        final Map<String, dynamic> directUpdates = {
                          'saldo_deudor': saldoRestante,
                        };

                        if (saldoRestante <= 0.01) {
                          directUpdates['cuotas_pagadas'] = currentBasePagadas;
                          directUpdates['mesa_extra_cuotas_pagadas'] =
                              currentMesaPagadas;
                          directUpdates['sillas_extra_cuotas_pagadas'] =
                              currentSillasPagadas;
                        } else {
                          // Reconciliar siempre tras cobro base/mesa/sillas (incl. entrega parcial).
                          if (nuevasBase > 0 ||
                              previewConceptos.any(
                                (c) =>
                                    !esLineaCargoCanal(c) &&
                                    !esLineaInteresMora(c) &&
                                    (c['concepto'] as String)
                                        .toUpperCase()
                                        .contains('BASE'),
                              )) {
                            directUpdates['cuotas_pagadas'] =
                                currentBasePagadas;
                          }
                          if (nuevasMesa > 0 ||
                              previewConceptos.any(
                                (c) =>
                                    !esLineaCargoCanal(c) &&
                                    !esLineaInteresMora(c) &&
                                    (c['concepto'] as String)
                                        .toUpperCase()
                                        .contains('MESA'),
                              )) {
                            directUpdates['mesa_extra_cuotas_pagadas'] =
                                currentMesaPagadas;
                          }
                          if (nuevasSillas > 0 ||
                              previewConceptos.any(
                                (c) =>
                                    !esLineaCargoCanal(c) &&
                                    !esLineaInteresMora(c) &&
                                    (c['concepto'] as String)
                                        .toUpperCase()
                                        .contains('SILLA'),
                              )) {
                            directUpdates['sillas_extra_cuotas_pagadas'] =
                                currentSillasPagadas;
                          }
                        }

                        // Persistir montos pagados de extras para mantener sync exacto
                        if (grossMesaPagado > 0.01) {
                          directUpdates['mesa_extra_pagado'] =
                              double.parse(((alumno.mesaExtraPagado ?? 0) + grossMesaPagado).toStringAsFixed(2));
                        }
                        if (grossSillasPagado > 0.01) {
                          directUpdates['sillas_extra_pagado'] =
                              double.parse(((alumno.sillasExtraPagado ?? 0) + grossSillasPagado).toStringAsFixed(2));
                        }

                        final double moraEste = previewConceptos
                            .where(esLineaInteresMora)
                            .fold<double>(
                              0.0,
                              (s, c) => s + (c['monto'] as num).toDouble(),
                            );
                        final double trackedNuevo = (moraPendienteEfectivo - moraEste)
                            .clamp(0.0, double.infinity);
                        directUpdates['mora_pendiente_tracked'] =
                            double.parse(trackedNuevo.toStringAsFixed(2));

                        await repo.actualizarContrato(alumno.id, directUpdates);

                        // Escaneo final automático sin interrumpir al usuario
                        await _forzarAuditoriaInteligente(silencioso: true);
                        ref.invalidate(dashboardStatsProvider);
                      } catch (e) {
                        debugPrint('Registro asíncrono demorado: $e');
                      }
                    });
                  },
                  label: const Text(
                    'CONFIRMAR PAGO',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    moraMontoCobroCtrl.dispose();
    efectivoMixCtrl.dispose();
    transferMixCtrl.dispose();
    pctTransferInfoCtrl.dispose();
    transferCargoMontoCtrl.dispose();
    // No _refreshAlumnos() aquí: compite con la persistencia async y pisaba
    // el update optimista. La auditoría silenciosa del microtask reconcilia DB.
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
          final bool cargando =
              snapshot.connectionState == ConnectionState.waiting;
          final double totalEntregado = pagos.fold(
            0,
            (sum, p) => sum + (p['monto'] as num).toDouble(),
          );

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
              ),
            ),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: const EdgeInsets.all(24),
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
                      const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Color(0xFFD4AF37),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'ESTADO DE CUENTA',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alumno.nombreAlumno.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 500,
              height: 400,
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
                                        size: 48,
                                        color: Colors.grey.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No hay pagos registrados aún.',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : (() {
                                  final cronologico = pagos.reversed.toList();
                                  final Map<String, int> contadores = {};
                                  final List<Map<String, dynamic>>
                                  pagosConDetalle = [];

                                  final int tCuotas = alumno.totalCuotas ?? 9;
                                  final int mCuotas =
                                      alumno.mesaExtraCuotas ?? 1;

                                  for (var p in cronologico) {
                                    final conceptoOriginal =
                                        p['concepto'] as String? ??
                                        'Cuota Base';
                                    String conceptoMejorado = conceptoOriginal;

                                    if (conceptoOriginal.startsWith(
                                      'Cuota Base',
                                    )) {
                                      contadores['Cuota Base'] =
                                          (contadores['Cuota Base'] ?? 0) + 1;
                                      conceptoMejorado =
                                          'Cuota Base (${contadores['Cuota Base']}/$tCuotas)';
                                    } else if (conceptoOriginal.startsWith(
                                      'Mesa Extra',
                                    )) {
                                      contadores['Mesa Extra'] =
                                          (contadores['Mesa Extra'] ?? 0) + 1;
                                      if (mCuotas <= 1) {
                                        conceptoMejorado =
                                            'Mesa Extra - Entrega';
                                      } else {
                                        conceptoMejorado =
                                            'Mesa Extra (${contadores['Mesa Extra']}/$mCuotas)';
                                      }
                                    } else if (conceptoOriginal.startsWith(
                                      'Sillas Extras',
                                    )) {
                                      conceptoMejorado =
                                          'Sillas Extras - Entrega';
                                    }

                                    final pCpy = Map<String, dynamic>.from(p);
                                    pCpy['concepto_detallado'] =
                                        conceptoMejorado;
                                    if ((p['descuento_porcentaje'] as num? ??
                                            0) >
                                        0.01) {
                                      pCpy['label_descuento'] =
                                          '${(p['descuento_porcentaje'] as num).toStringAsFixed(0)}% OFF';
                                    }
                                    pagosConDetalle.add(pCpy);
                                  }

                                  final listaFinal = pagosConDetalle.reversed
                                      .toList();

                                  return ListView.builder(
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

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.03,
                                                )
                                              : Colors.black.withValues(
                                                  alpha: 0.02,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white10
                                                : Colors.black12,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withValues(
                                                  alpha: 0.1,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.check_rounded,
                                                color: Colors.green,
                                                size: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        concepto,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      if (p['label_descuento'] !=
                                                          null) ...[
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
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
                                                    ],
                                                  ),
                                                  Text(
                                                    '${fecha.day}/${fecha.month}/${fecha.year} - ${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')} hs',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey,
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
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 14,
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
                                                    _imprimirReciboAlumno(
                                                      alumno,
                                                      montoPagado: monto,
                                                      saldoPendiente:
                                                          alumno.saldoDeudor,
                                                      conceptosPagados:
                                                          <
                                                            Map<String, dynamic>
                                                          >[
                                                            {
                                                              'concepto':
                                                                  concepto,
                                                              'monto': monto,
                                                            },
                                                          ],
                                                      fechaManual: fechaOrig,
                                                      skipDbRefresh: false,
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
                                                            color: Colors
                                                                .blueAccent,
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
                                  );
                                })(),
                        ),
                        const Divider(height: 32),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFD4AF37,
                            ).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL ENTREGADO:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                totalEntregado.toCurrency(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: Color(0xFFD4AF37),
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

    final int mCuotas = alumno.mesaExtraCuotas ?? 1;

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
            } else if (mp.toLowerCase().contains('transfer') || mp.toLowerCase() == 'transferencia') {
              totalTransferencia += m;
            }
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

          // Group by normalized concept and sum amounts to merge split payments
          final Map<String, double> agrupados = {};
          for (final p in lote) {
            final String raw = (p['concepto'] as String?) ?? 'Pago';
            final String upper = raw.toUpperCase().trim();
            String mapped = raw;
            
            if (upper.contains('MORA') || upper.contains('INTERE')) {
              mapped = raw.contains('cuota ') ? raw : 'Interés mora (cuota base — este cobro)';
            } else if (upper.contains('(') && upper.contains(')')) {
              // Keep detailed rich concept names as-is
              mapped = raw;
            } else if (upper == 'BASE' || upper == 'CUOTA BASE') {
              mapped = 'Cuota Base';
            } else if (upper == 'MESA' || upper == 'MESA EXTRA') {
              mapped = mCuotas <= 1
                  ? 'Mesa Extra - Entrega'
                  : 'Mesa Extra (Abono)';
            } else if (upper == 'SILLA' || upper == 'SILLAS EXTRAS') {
              mapped = 'Sillas Extras - Entrega';
            }
            
            agrupados[mapped] = (agrupados[mapped] ?? 0.0) +
                ((p['monto'] as num?)?.toDouble() ?? 0.0);
          }

          conceptosPagados = agrupados.entries.map<Map<String, dynamic>>((e) {
            return <String, dynamic>{
              'concepto': e.key,
              'monto': double.parse(e.value.toStringAsFixed(2)),
            };
          }).toList();

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
    final baseCtrl = TextEditingController(
      text: currentBase?.toFormattedNumber() ?? '',
    );
    final mesaCtrl = TextEditingController(
      text: currentMesa?.toFormattedNumber() ?? '',
    );
    final sillasCtrl = TextEditingController(
      text: currentSillas?.toFormattedNumber() ?? '',
    );

    return showDialog<Map<String, double>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInternalState) {
          double getSum() =>
              CurrencyInputFormatter.parse(baseCtrl.text) +
              CurrencyInputFormatter.parse(mesaCtrl.text) +
              CurrencyInputFormatter.parse(sillasCtrl.text);

          final double currentSum = getSum();
          final double diff = total - currentSum;
          final bool isValid = diff.abs() < 0.01;

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
                              baseCtrl.text = b > 0
                                  ? b.toFormattedNumber()
                                  : '';
                              mesaCtrl.text = m > 0
                                  ? m.toFormattedNumber()
                                  : '';
                              sillasCtrl.text = s > 0
                                  ? s.toFormattedNumber()
                                  : '';
                            });
                          },
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
        },
      ),
    );
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

  Future<int?> _mostrarDialogoSeleccionCuotas(
    BuildContext context,
    String titulo,
    int max,
  ) {
    int seleccion = 1;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInternalState) => AlertDialog(
          title: Text(
            'Seleccionar Cuotas: $titulo',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '¿Cuántas cuotas desea liquidar?',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: seleccion > 1
                        ? () => setInternalState(() => seleccion--)
                        : null,
                    icon: const Icon(Icons.remove),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$seleccion',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: seleccion < max
                        ? () => setInternalState(() => seleccion++)
                        : null,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Máximo disponible: $max cuotas',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, seleccion),
              child: const Text('ACEPTAR'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _mostrarOpcionesPago(
    BuildContext context,
    String titulo,
    double deuda, {
    double? cuotaUnica,
    int? cuotasRestantes,
  }) {
    final tieneCuotas = (cuotasRestantes ?? 0) > 1;

    return showDialog<String>(
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
      ),
    );
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
