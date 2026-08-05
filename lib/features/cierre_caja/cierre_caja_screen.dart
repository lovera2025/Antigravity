import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/ar_time.dart';
import '../../models/egreso.dart';
import '../common/services/pdf_service.dart';
import '../common/utils/currency_extensions.dart';
import '../common/widgets/admin_gate.dart';
import '../common/widgets/operational_sync_coordinator.dart';
import '../common/providers/admin_provider.dart';
import '../egresos/providers/egresos_provider.dart';
import '../egresos/repositories/egresos_repository.dart';
import '../mi_empresa/models/ingreso_detallado.dart';
import '../mi_empresa/providers/finanzas_provider.dart';
import '../caja_sesiones/models/modo_jefe_caja.dart';
import '../caja_sesiones/repositories/sesiones_caja_repository.dart';
import 'models/resumen_sesion_pdf.dart';
import 'models/turno_caja.dart';
import 'providers/cierre_caja_provider.dart';
import 'widgets/anotacion_pdf_section.dart';
import 'widgets/guia_cambio_section.dart';
import 'widgets/registrar_retiro_dialog.dart';

class CierreCajaScreen extends ConsumerStatefulWidget {
  const CierreCajaScreen({super.key});

  @override
  ConsumerState<CierreCajaScreen> createState() => _CierreCajaScreenState();
}

class _CierreCajaScreenState extends ConsumerState<CierreCajaScreen> {
  static const _gold = Color(0xFFD4AF37);
  static const _efectivoColor = Color(0xFF00B894);
  static const _transferColor = Color(0xFF6C63FF);
  static const _redAccent = Color(0xFFE74C3C);
  bool _forzoHoyOperativo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _forzoHoyOperativo) return;
      if (!ref.read(adminAuthProvider).esModoJefe) {
        _forzoHoyOperativo = true;
        ref.read(cierreCajaProvider.notifier).aplicarRestriccionOperativa();
      }
    });
  }

  Future<void> _elegirDia(BuildContext context, DateTime actual) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(2023),
      lastDate: DateTime(ArTime.nowAr().year + 1, 12, 31),
      helpText: 'Día de cierre',
    );
    if (picked == null) return;
    await ref.read(cierreCajaProvider.notifier).setDia(picked);
  }

  Future<void> _abrirRegistrarRetiro(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const RegistrarRetiroDialog(),
    );
  }

  Future<void> _eliminarSesionSeleccionada(
    BuildContext context,
    CierreCajaState state,
  ) async {
    final sesion = state.sesionSeleccionada;
    if (sesion == null) return;
    final total = await ref
        .read(sesionesCajaRepositoryProvider)
        .totalCobradoSesion(sesion.id);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar sesión de caja'),
        content: Text(
          '¿Eliminar ${state.alcanceLabel}?'
          '${total > 0.01 ? '\nTiene ${total.toCurrency()} en cobros; los pagos no se borrarán, solo quedarán sin sesión.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(sesionesCajaRepositoryProvider).eliminar(sesion.id);
    await ref.read(cierreCajaProvider.notifier).setConsolidado();
  }

  Future<void> _eliminarRetiroCajaPorEgreso(
    BuildContext context,
    Egreso e,
  ) async {
    if ((e.id).length != 36) return;
    final okPin = await AdminGate.check(context, ref);
    if (!okPin || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar este retiro?'),
        content: Text(
          'Se borrará el retiro "${e.proveedor ?? 'Retiro de caja'}" por ${e.monto.toCurrency()} (local y nube). Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(egresosRepositoryProvider).eliminarEgreso(e.id);
      await ref.read(egresosProvider.notifier).refresh();
      await ref.read(finanzasProvider.notifier).recargar();
      await ref.read(cierreCajaProvider.notifier).refrescarManual();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retiro eliminado'),
          backgroundColor: Color(0xFF00B894),
        ),
      );
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $err')));
    }
  }

  /// Desglose del día: una fila por sesión con lo cobrado y su arqueo.
  List<ResumenSesionPdf> _resumenPorSesion(CierreCajaState state) {
    return state.sesionesDia.map((s) {
      double efectivo = 0;
      double transferencia = 0;
      for (final i in state.ingresosTurno) {
        if (i.sesionCajaId != s.id) continue;
        final mp = i.medioPago?.toLowerCase().trim();
        if (mp == 'transferencia') {
          transferencia += i.monto;
        } else {
          efectivo += i.monto;
        }
      }
      double egresosEfectivo = 0;
      for (final e in state.egresosTurno) {
        if (e.sesionCajaId != s.id) continue;
        if ((e.medioPago ?? '').toLowerCase().trim() != 'transferencia') {
          egresosEfectivo += e.monto;
        }
      }
      final esJefe = esOperadorModoJefeId(s.operadorId);
      return ResumenSesionPdf(
        operador: esJefe
            ? kOperadorModoJefeNombre
            : (s.operadorNombre ?? 'Operario'),
        etiqueta: esJefe ? 'Día' : (s.etiqueta ?? '—'),
        horaApertura: ArTime.formatHora(s.abiertaAt),
        horaCierre: s.cerradaAt == null ? null : ArTime.formatHora(s.cerradaAt!),
        efectivo: efectivo,
        transferencia: transferencia,
        cambioInicial: s.cambioInicial,
        egresosEfectivo: egresosEfectivo,
        arqueo: s.arqueoCierre,
        cierreAutomatico: s.cierreAutomatico,
      );
    }).toList();
  }

  Future<void> _exportarPdf(BuildContext context, CierreCajaState state) async {
    try {
      final sesion = state.sinSesiones || state.consolidado
          ? null
          : state.sesionSeleccionada;
      await PdfService.generarCierreCajaPdfTicket(
        diaCalendarioAr: state.dia,
        turno: state.turno,
        ingresosTurno: state.ingresosTurno,
        retirosTurno: state.retirosTurno,
        otrosEgresosTurno: state.otrosEgresosTurno,
        efectivoBruto: state.efectivoBruto,
        transferenciaBruta: state.transferenciaBruta,
        retirosEfectivo: state.egresosEfectivo,
        retirosTransferencia: state.egresosTransferencia,
        emitidoPor: state.alcanceLabel,
        anotacionTurno: state.anotacionTurno.trim().isEmpty
            ? null
            : state.anotacionTurno.trim(),
        guiaCambioSaldo: state.fondoCambioGuia,
        guiaCantReposiciones: state.guiaCantReposiciones,
        guiaCantUsos: state.guiaCantUsos,
        guiaTotalReposiciones: state.guiaTotalReposiciones,
        guiaTotalUsos: state.guiaTotalUsos,
        sesionCambioInicial: sesion?.cambioInicial,
        sesionArqueo: sesion?.arqueoCierre,
        sesionNotaCierre: sesion?.notaCierre,
        sesionAbiertaAt: sesion?.abiertaAt,
        sesionCerradaAt: sesion?.cerradaAt,
        resumenSesiones: state.consolidado && !state.sinSesiones
            ? _resumenPorSesion(state)
            : const [],
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    }
  }

  Future<void> _nuevaJornadaVisual(BuildContext context) async {
    await ref.read(cierreCajaProvider.notifier).avanzarANuevaJornadaVisual();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Nueva jornada lista. Solo cambió la vista; el historial sigue intacto.',
        ),
      ),
    );
  }

  void _abrirDetalleBucket(
    BuildContext context,
    CierreCajaState state,
    String bucket,
  ) {
    final isEfectivo = bucket == 'efectivo';
    final ingresos = state.ingresosTurno.where((i) {
      final mp = i.medioPago?.toLowerCase().trim();
      if (isEfectivo) return mp != 'transferencia';
      return mp == 'transferencia';
    }).toList();
    // Todos los egresos del turno para ese medio (retiros + otros).
    final egresos = state.egresosTurno.where((e) {
      final mp = (e.medioPago ?? '').toLowerCase().trim();
      if (isEfectivo) return mp != 'transferencia';
      return mp == 'transferencia';
    }).toList();
    final accent = isEfectivo ? _efectivoColor : _transferColor;
    final icon = isEfectivo
        ? Icons.payments_outlined
        : Icons.swap_horiz_rounded;
    final titulo = isEfectivo ? 'EFECTIVO' : 'TRANSFERENCIA';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _DetalleBucketSheet(
          accent: accent,
          icon: icon,
          titulo: titulo,
          ingresos: ingresos,
          egresos: egresos,
          scrollController: controller,
          onEliminarRetiro: (r) async {
            Navigator.of(context).pop();
            await _eliminarRetiroCajaPorEgreso(context, r);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cierreCajaProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.black54;
    final modoJefe = ref.watch(adminAuthProvider).esModoJefe;

    ref.listen(adminAuthProvider, (prev, next) {
      if (prev == null) return;
      if (prev.modoJefe && !next.modoJefe) {
        ref.read(cierreCajaProvider.notifier).aplicarRestriccionOperativa();
      } else if (prev.modoJefe != next.modoJefe) {
        ref.read(cierreCajaProvider.notifier).refrescarManual();
      }
    });
    ref.listen<int>(operationalSyncRevisionProvider, (prev, next) {
      if (prev != next) {
        ref.read(cierreCajaProvider.notifier).refrescarManual();
      }
    });

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
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  'CIERRE DE CAJA',
                  style: GoogleFonts.oswald(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: _gold,
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Recargar',
                    icon: state.cargando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _gold,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, color: _gold),
                    onPressed: state.cargando
                        ? null
                        : () => ref
                              .read(cierreCajaProvider.notifier)
                              .refrescarManual(),
                  ),
                  if (modoJefe)
                    IconButton(
                      tooltip: 'Nueva jornada (solo visual)',
                      icon: const Icon(
                        Icons.event_available_rounded,
                        color: _gold,
                      ),
                      onPressed: state.cargando
                          ? null
                          : () => _nuevaJornadaVisual(context),
                    ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _selectorDia(
                        context,
                        state,
                        isDark,
                        muted,
                        puedeCambiarDia: modoJefe,
                      ),
                      const SizedBox(height: 14),
                      if (modoJefe) ...[
                        _selectorSesiones(state, isDark),
                        const SizedBox(height: 10),
                        _botonSinSesiones(state),
                        if (state.sinSesiones) ...[
                          const SizedBox(height: 10),
                          _selectorTurnoSinSesiones(state),
                        ],
                      ] else
                        _sesionOperativaChip(state, isDark, muted),
                      const SizedBox(height: 14),
                      if (!state.consolidado && !state.sinSesiones) ...[
                        const GuiaCambioSection(),
                        const SizedBox(height: 10),
                        const AnotacionPdfSection(),
                      ],
                      if (state.error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Aviso: ${state.error}',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey(
                            '${state.sinSesiones ? 'sin' : (state.sesionSeleccionadaId ?? 'dia')}_'
                            '${state.turno.slug}_'
                            '${state.dia.toIso8601String()}',
                          ),
                          child: _bucketsRow(context, state, isDark),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _resumenLine(state, muted),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(
                    children: [
                      Container(width: 3, height: 14, color: _gold),
                      const SizedBox(width: 8),
                      Text(
                        state.sinSesiones
                            ? 'MOVIMIENTOS SIN SESIÓN'
                            : state.consolidado
                            ? 'MOVIMIENTOS DEL DÍA'
                            : 'MOVIMIENTOS DE LA SESIÓN',
                        style: GoogleFonts.oswald(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: _gold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${state.ingresosTurno.length + state.egresosTurno.length} ítem(s)',
                        style: TextStyle(
                          fontSize: 11,
                          color: muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.ingresosTurno.isEmpty && state.egresosTurno.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _emptyState(state, muted, isDark),
                )
              else
                SliverList.list(
                  children: _movimientosUnificados(state)
                      .map((m) => _movimientoTile(context, m, isDark, muted))
                      .toList(),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomBar(context, state, isDark),
    );
  }

  Widget _selectorDia(
    BuildContext context,
    CierreCajaState state,
    bool isDark,
    Color muted, {
    required bool puedeCambiarDia,
  }) {
    final txt = ArTime.formatFechaLarga(state.dia);
    final esHoy = ArTime.mismoDia(state.dia, ArTime.nowAr());
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: puedeCambiarDia ? () => _elegirDia(context, state.dia) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.04,
            ),
            border: Border.all(color: _gold.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 18, color: _gold),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DÍA',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      esHoy ? '$txt · HOY' : txt,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!puedeCambiarDia) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Solo jornada de hoy (modo operativo)',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (puedeCambiarDia)
                const Icon(
                  Icons.edit_calendar_outlined,
                  size: 18,
                  color: _gold,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorSesiones(CierreCajaState state, bool isDark) {
    const allKey = '__all__';
    final value = state.sinSesiones
        ? allKey
        : state.consolidado
        ? allKey
        : (state.sesionSeleccionadaId ??
              (state.sesionesDia.isEmpty
                  ? allKey
                  : state.sesionesDia.first.id));
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(
              'sesion_${state.sinSesiones}_${state.consolidado}_'
              '${state.sesionSeleccionadaId ?? allKey}',
            ),
            initialValue: value,
            decoration: InputDecoration(
              labelText: state.sinSesiones
                  ? 'Sesión de caja (vista sin sesiones)'
                  : 'Sesión de caja',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            items: [
              const DropdownMenuItem(
                value: allKey,
                child: Text('Día completo · todas las sesiones'),
              ),
              for (final s in state.sesionesDia)
                DropdownMenuItem(
                  value: s.id,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          esOperadorModoJefeId(s.operadorId)
                              ? [
                                  kOperadorModoJefeNombre,
                                  ArTime.formatHora(s.abiertaAt),
                                ].join(' · ')
                              : [
                                  s.operadorNombre ?? 'Operario',
                                  s.etiqueta ?? 'Turno',
                                  ArTime.formatHora(s.abiertaAt),
                                ].join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // El turno que nadie cerró tiene que distinguirse del que
                      // se cerró y arqueó: es el dato por el que el jefe entra
                      // acá. No se pierde ningún cobro, pero se ve.
                      if (s.cierreAutomatico) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: s.notaCierre ?? 'Cerrada por el sistema',
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 15,
                                color: Colors.orangeAccent,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'cerrada automáticamente · sin arqueo',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
            onChanged: state.cargando || state.sinSesiones
                ? null
                : (id) {
                    if (id == null) return;
                    final notifier = ref.read(cierreCajaProvider.notifier);
                    if (id == allKey) {
                      notifier.setConsolidado();
                    } else {
                      notifier.setSesion(id);
                    }
                  },
          ),
        ),
        if (!state.consolidado &&
            !state.sinSesiones &&
            state.sesionSeleccionadaId != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Eliminar sesión',
            color: Colors.redAccent,
            onPressed: state.cargando
                ? null
                : () => _eliminarSesionSeleccionada(context, state),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ],
    );
  }

  Widget _botonSinSesiones(CierreCajaState state) {
    final activo = state.sinSesiones;
    return Align(
      alignment: Alignment.centerLeft,
      child: FilterChip(
        selected: activo,
        avatar: Icon(
          activo ? Icons.history_toggle_off : Icons.history,
          size: 18,
          color: activo ? Colors.black : _gold,
        ),
        label: Text(
          activo ? 'SIN SESIONES (activo)' : 'SIN SESIONES',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            fontSize: 12,
            color: activo ? Colors.black : null,
          ),
        ),
        selectedColor: _gold,
        checkmarkColor: Colors.black,
        onSelected: state.cargando
            ? null
            : (v) => ref
                  .read(cierreCajaProvider.notifier)
                  .setSinSesiones(activo: v),
      ),
    );
  }

  Widget _selectorTurnoSinSesiones(CierreCajaState state) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in [TurnoCaja.manana, TurnoCaja.tarde, TurnoCaja.dia])
          ChoiceChip(
            label: Text(t.labelCorto),
            selected: state.turno == t,
            onSelected: state.cargando
                ? null
                : (sel) {
                    if (!sel) return;
                    ref.read(cierreCajaProvider.notifier).setTurno(t);
                  },
          ),
      ],
    );
  }

  Widget _sesionOperativaChip(CierreCajaState state, bool isDark, Color muted) {
    final sesion = state.sesionSeleccionada;
    final accent = switch (state.turno) {
      TurnoCaja.manana => const Color(0xFFE8A317),
      TurnoCaja.tarde => const Color(0xFF6C63FF),
      TurnoCaja.dia => _gold,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TU SESIÓN DE CAJA',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withValues(alpha: 0.65),
              width: 1.5,
            ),
            color: accent.withValues(alpha: isDark ? 0.2 : 0.14),
          ),
          child: Column(
            children: [
              Text(
                state.alcanceLabel.toUpperCase(),
                style: GoogleFonts.oswald(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sesion == null
                    ? 'No hay sesión activa'
                    : 'Abrió ${ArTime.formatFechaHora(sesion.abiertaAt)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: accent.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Solo movimientos ligados a esta sesión',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bucketsRow(BuildContext context, CierreCajaState state, bool isDark) {
    final cantEgEfectivo = state.egresosTurno
        .where(
          (e) => (e.medioPago ?? '').toLowerCase().trim() != 'transferencia',
        )
        .length;
    final cantEgTransf = state.egresosTurno
        .where(
          (e) => (e.medioPago ?? '').toLowerCase().trim() == 'transferencia',
        )
        .length;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _bucketCard(
              context: context,
              isDark: isDark,
              label: 'EFECTIVO',
              accent: _efectivoColor,
              icon: Icons.payments_outlined,
              ingresoBruto: state.efectivoBruto,
              egresosBruto: state.egresosEfectivo,
              neto: state.efectivoNeto,
              cantEgresos: cantEgEfectivo,
              onTap: () => _abrirDetalleBucket(context, state, 'efectivo'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _bucketCard(
              context: context,
              isDark: isDark,
              label: 'TRANSFERENCIA',
              accent: _transferColor,
              icon: Icons.swap_horiz_rounded,
              ingresoBruto: state.transferenciaBruta,
              egresosBruto: state.egresosTransferencia,
              neto: state.transferenciaNeta,
              cantEgresos: cantEgTransf,
              onTap: () => _abrirDetalleBucket(context, state, 'transferencia'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bucketCard({
    required BuildContext context,
    required bool isDark,
    required String label,
    required Color accent,
    required IconData icon,
    required double ingresoBruto,
    required double egresosBruto,
    required double neto,
    required int cantEgresos,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
                color: accent.withValues(alpha: isDark ? 0.10 : 0.07),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: accent, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: accent,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      neto.toCurrency(),
                      style: GoogleFonts.oswald(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ingresos: ${ingresoBruto.toCurrency()}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                  if (egresosBruto > 0)
                    Text(
                      'Egresos: −${egresosBruto.toCurrency()}'
                      '${cantEgresos > 1 ? '  ($cantEgresos egresos)' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _redAccent,
                      ),
                    )
                  else
                    Text(
                      'Sin egresos',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.35),
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

  Widget _resumenLine(CierreCajaState state, Color muted) {
    return Row(
      children: [
        Icon(Icons.account_balance_wallet_outlined, size: 14, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'TOTAL NETO · ${state.alcanceLabel.toUpperCase()}: '
            '${state.totalNeto.toCurrency()}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(CierreCajaState state, Color muted, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 56,
              color: muted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              state.sinSesiones
                  ? 'Sin movimientos sin sesión en este turno'
                  : state.consolidado
                  ? 'Sin movimientos en las sesiones del día'
                  : 'Sin movimientos en esta sesión',
              style: GoogleFonts.oswald(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              state.sinSesiones
                  ? 'Acá se listan cobros del build viejo (sin sesion_caja_id).'
                  : state.consolidado
                  ? 'Elegí otro día o verificá las sesiones abiertas.'
                  : 'Los cobros deben estar ligados a la sesión seleccionada.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  /// Lista unificada y ordenada por hora descendente para la sección "Movimientos".
  List<_Movimiento> _movimientosUnificados(CierreCajaState state) {
    final lista = <_Movimiento>[];
    for (final i in state.ingresosTurno) {
      lista.add(_Movimiento.ingreso(i));
    }
    for (final r in state.retirosTurno) {
      lista.add(_Movimiento.retiroCaja(r));
    }
    for (final e in state.otrosEgresosTurno) {
      lista.add(_Movimiento.otroEgreso(e));
    }
    lista.sort((a, b) => b.fecha.compareTo(a.fecha));
    return lista;
  }

  Widget _movimientoTile(
    BuildContext context,
    _Movimiento m,
    bool isDark,
    Color muted,
  ) {
    final Color accent;
    final IconData icon;
    switch (m.kind) {
      case _MovKind.ingreso:
        accent = (m.medioPago ?? '').toLowerCase().trim() == 'transferencia'
            ? _transferColor
            : _efectivoColor;
        icon = (m.medioPago ?? '').toLowerCase().trim() == 'transferencia'
            ? Icons.swap_horiz_rounded
            : Icons.payments_outlined;
      case _MovKind.retiroCaja:
        accent = _redAccent;
        icon = Icons.south_west_rounded;
      case _MovKind.otroEgreso:
        accent = const Color(0xFFCA6F1E);
        icon = Icons.receipt_long_outlined;
    }
    final hora = ArTime.formatHora(m.fecha);
    final montoTxt = m.kind == _MovKind.ingreso
        ? m.monto.toCurrency()
        : '−${m.monto.toCurrency()}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accent, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.titulo,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      hora,
                      if ((m.medioPago ?? '').isNotEmpty) m.medioPago!,
                      if (m.subtitulo != null) m.subtitulo!,
                    ].join(' · '),
                    style: TextStyle(fontSize: 11, color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              montoTxt,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
            if (m.kind == _MovKind.retiroCaja &&
                (m.retiroParaEliminar?.id ?? '').length == 36)
              IconButton(
                tooltip: 'Eliminar retiro',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: muted,
                  size: 20,
                ),
                onPressed: () {
                  final e = m.retiroParaEliminar;
                  if (e != null) _eliminarRetiroCajaPorEgreso(context, e);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(BuildContext context, CierreCajaState state, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101010) : Colors.white,
        border: Border(top: BorderSide(color: _gold.withValues(alpha: 0.25))),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed:
                  state.sinSesiones ||
                      state.consolidado ||
                      state.sesionSeleccionadaId == null
                  ? null
                  : () => _abrirRegistrarRetiro(context),
              icon: const Icon(Icons.south_west_rounded, size: 18),
              label: const Text(
                'REGISTRAR RETIRO',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  state.ingresosTurno.isEmpty && state.egresosTurno.isEmpty
                  ? null
                  : () => _exportarPdf(context, state),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(
                state.sinSesiones
                    ? 'PDF · SIN SESIÓN'
                    : state.consolidado
                    ? 'PDF · DÍA'
                    : 'PDF · SESIÓN',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: _gold),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _MovKind { ingreso, retiroCaja, otroEgreso }

class _Movimiento {
  final DateTime fecha;
  final double monto;
  final String titulo;
  final String? subtitulo;
  final String? medioPago;
  final _MovKind kind;

  /// Solo [retiroCaja]: permite anular el egreso desde la lista (PIN admin).
  final Egreso? retiroParaEliminar;

  const _Movimiento({
    required this.fecha,
    required this.monto,
    required this.titulo,
    required this.kind,
    this.subtitulo,
    this.medioPago,
    this.retiroParaEliminar,
  });

  factory _Movimiento.ingreso(IngresoDetallado i) => _Movimiento(
    fecha: i.fecha,
    monto: i.monto,
    titulo: i.concepto,
    subtitulo: i.alumnoOCliente,
    medioPago: i.medioPago,
    kind: _MovKind.ingreso,
  );

  factory _Movimiento.retiroCaja(Egreso e) => _Movimiento(
    fecha: e.fecha ?? ArTime.nowUtc(),
    monto: e.monto,
    titulo: e.proveedor ?? 'Retiro de caja',
    subtitulo: 'Retiro de caja',
    medioPago: e.medioPago,
    kind: _MovKind.retiroCaja,
    retiroParaEliminar: e,
  );

  /// Gastos ya guardados en [egresos] (p. ej. personal): mismo registro que Finanzas.
  factory _Movimiento.otroEgreso(Egreso e) => _Movimiento(
    fecha: e.fecha ?? ArTime.nowUtc(),
    monto: e.monto,
    titulo: e.proveedor ?? 'Egreso',
    subtitulo: (e.categoria ?? '').trim().isEmpty ? 'Egreso' : e.categoria,
    medioPago: e.medioPago,
    kind: _MovKind.otroEgreso,
  );
}

class _DetalleBucketSheet extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String titulo;
  final List<IngresoDetallado> ingresos;

  /// Todos los egresos del bucket (retiros formales + otros). Solo los de
  /// categoría [kCategoriaRetiroCaja] muestran el botón de eliminar.
  final List<Egreso> egresos;
  final ScrollController scrollController;
  final Future<void> Function(Egreso r)? onEliminarRetiro;

  const _DetalleBucketSheet({
    required this.accent,
    required this.icon,
    required this.titulo,
    required this.ingresos,
    required this.egresos,
    required this.scrollController,
    this.onEliminarRetiro,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.black54;
    final totalIng = ingresos.fold<double>(0, (s, i) => s + i.monto);
    final totalEg = egresos.fold<double>(0, (s, e) => s + e.monto);
    final neto = totalIng - totalEg;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.oswald(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: accent,
                      ),
                    ),
                    Text(
                      'NETO ${neto.toCurrency()}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (ingresos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Sin ingresos en este bucket.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            )
          else ...[
            Text('INGRESOS', style: _headerStyle(accent)),
            const SizedBox(height: 6),
            ...ingresos.map((i) => _filaIngreso(i, muted, isDark)),
          ],
          const SizedBox(height: 14),
          if (egresos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Sin egresos en este bucket.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            )
          else ...[
            Text('EGRESOS', style: _headerStyle(const Color(0xFFE74C3C))),
            const SizedBox(height: 6),
            ...egresos.map(
              (e) => _filaEgreso(e, muted, isDark, onEliminarRetiro),
            ),
          ],
        ],
      ),
    );
  }

  TextStyle _headerStyle(Color color) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.5,
    color: color,
  );

  Widget _filaIngreso(IngresoDetallado i, Color muted, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i.concepto,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${ArTime.formatHora(i.fecha)} · ${i.alumnoOCliente}',
                  style: TextStyle(fontSize: 11, color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            i.monto.toCurrency(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaEgreso(
    Egreso e,
    Color muted,
    bool isDark,
    Future<void> Function(Egreso)? onEliminarRetiro,
  ) {
    final hora = e.fecha != null ? ArTime.formatHora(e.fecha!) : '—';
    final esRetiroFormal = (e.categoria ?? '').trim() == kCategoriaRetiroCaja;
    final cat = (e.categoria ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.proveedor ?? (esRetiroFormal ? 'Retiro de caja' : 'Egreso'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$hora · ${e.medioPago ?? '—'}${cat.isNotEmpty ? ' · $cat' : ''}',
                  style: TextStyle(fontSize: 11, color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (esRetiroFormal && onEliminarRetiro != null && e.id.length == 36)
            IconButton(
              tooltip: 'Eliminar retiro',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: Color(0xFFE74C3C),
              ),
              onPressed: () => onEliminarRetiro(e),
            ),
          Text(
            '−${e.monto.toCurrency()}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFFE74C3C),
            ),
          ),
        ],
      ),
    );
  }
}
