import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/widgets/admin_gate.dart';
import '../../mi_empresa/providers/finanzas_provider.dart';
import '../repositories/contratos_repository.dart';
import '../services/mora_cuota_calculator.dart';
import '../services/mora_tracked_origen.dart';

/// Diálogo de perdón por alumno (grilla masivo, modo jefe).
class PerdonarMoraAlumnoDialog extends ConsumerWidget {
  final ContratoAlumno contrato;

  const PerdonarMoraAlumnoDialog({super.key, required this.contrato});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.cleaning_services_rounded,
            color: Colors.redAccent.shade200,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Perdonar mora',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Colors.redAccent.shade200,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: PerdonarMoraForm(
            contrato: contrato,
            emptyMessage:
                'Este alumno está limpio. No hay mora para perdonar.',
            onApplied: () {
              if (context.mounted) Navigator.of(context).pop(true);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Panel de perdón sin mover Reg. Lo usan Mi Empresa y [PerdonarMoraAlumnoDialog].
class PerdonarMoraForm extends ConsumerStatefulWidget {
  final ContratoAlumno contrato;
  final bool enabled;
  final String emptyMessage;
  final VoidCallback? onApplied;

  const PerdonarMoraForm({
    super.key,
    required this.contrato,
    this.enabled = true,
    this.emptyMessage = 'No hay mora operativa para perdonar en este alumno.',
    this.onApplied,
  });

  @override
  ConsumerState<PerdonarMoraForm> createState() => _PerdonarMoraFormState();
}

class _PerdonarMoraFormState extends ConsumerState<PerdonarMoraForm> {
  bool _loading = true;
  bool _submitting = false;
  double _moraHist = 0;
  List<MoraCuotaDetalle> _desgloseNeto = [];
  final Set<int> _cuotasSeleccion = {};

  /// El remanente en ficha, abierto por cuota de origen. Es un solo número en
  /// la base; de qué cuotas salió se reconstruye del historial.
  List<MoraPendientePreviaDetalle> _origenTracked = [];

  /// Cuotas del remanente tildadas. `0` es la parte sin origen reconstruible.
  final Set<int> _trackedSeleccion = {};

  bool get _busy => !widget.enabled || _submitting;

  /// Cuánto del remanente está tildado.
  double get _trackedPerdonado => double.parse(
    _origenTracked
        .where((d) => _trackedSeleccion.contains(d.numeroCuota))
        .fold<double>(0, (s, d) => s + d.montoAtribuido)
        .clamp(0.0, widget.contrato.moraPendienteTracked)
        .toStringAsFixed(2),
  );

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant PerdonarMoraForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contrato.id != widget.contrato.id) {
      _cargar();
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _desgloseNeto = [];
      _origenTracked = [];
      _cuotasSeleccion.clear();
      _trackedSeleccion.clear();
      _moraHist = 0;
    });
    try {
      final repo = ref.read(contratosRepositoryProvider);
      final hist = await repo.sumMoraCobradaHistorial(widget.contrato.id);
      if (!mounted) return;
      final hoy = ArTime.nowAr();
      final fifo = MoraCuotaCalculator.moraCobradaParaFifo(
        moraCobradaHistorial: hist,
        moraCobradaOffset: widget.contrato.moraCobradaOffset,
      );
      final bruto =
          MoraCuotaCalculator.calcularDesglose(widget.contrato, hoy);
      final neto = MoraCuotaCalculator.desglosePendiente(bruto, fifo);

      final tracked =
          widget.contrato.moraPendienteTracked.clamp(0.0, double.infinity);
      final origen = tracked > 0.01
          ? await _origenDelRemanente(repo, tracked)
          : const <MoraPendientePreviaDetalle>[];
      if (!mounted) return;
      setState(() {
        _moraHist = hist;
        _desgloseNeto = neto;
        _origenTracked = origen;
        _cuotasSeleccion.addAll(neto.map((d) => d.numeroCuota));
        _trackedSeleccion.addAll(origen.map((d) => d.numeroCuota));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el desglose de mora: $e')),
      );
    }
  }

  /// Abre el remanente por cuota. Lo que el historial no alcance a explicar
  /// queda como una entrada residual (cuota 0), tildable igual que las demás:
  /// es plata que está en la ficha y tiene que poder perdonarse.
  Future<List<MoraPendientePreviaDetalle>> _origenDelRemanente(
    ContratosRepository repo,
    double tracked,
  ) async {
    final pagos = await repo.getHistorialPagosAlumno(widget.contrato.id);
    final origen = MoraTrackedOrigen.inferir(
      contratoBase: widget.contrato,
      pagos: pagos,
      trackedMonto: tracked,
      recorte: MoraOrigenRecorte.loQueQueda,
    );
    final atribuido = origen.fold<double>(0, (s, d) => s + d.montoAtribuido);
    final resto = double.parse((tracked - atribuido).toStringAsFixed(2));
    return [
      ...origen,
      if (resto > 0.01)
        MoraPendientePreviaDetalle(
          numeroCuota: 0,
          mesLabel: '',
          montoAtribuido: resto,
        ),
    ];
  }

  /// El remanente se perdona de la más vieja a la más nueva, igual que se
  /// cobra: tildar un mes incluye los anteriores. El orden es el de la cola que
  /// devuelve `inferir`, no el número de cuota — la entrada sin origen lleva el
  /// 0 y va al final.
  void _toggleTracked(int numeroCuota, bool marcar) {
    setState(() {
      final nueva = MoraCuotaCalculator.seleccionPerdonRemanentePrefijo(
        ordenViejoANuevo: _origenTracked.map((d) => d.numeroCuota).toList(),
        seleccionActual: _trackedSeleccion,
        tocado: numeroCuota,
        marcar: marcar,
      );
      _trackedSeleccion
        ..clear()
        ..addAll(nueva);
    });
  }

  void _toggleCuota(int numeroCuota, bool marcar) {
    setState(() {
      final disponibles =
          _desgloseNeto.map((d) => d.numeroCuota).toList()..sort();
      if (marcar) {
        _cuotasSeleccion.addAll(
          disponibles.where((n) => n <= numeroCuota),
        );
      } else {
        _cuotasSeleccion.removeWhere((n) => n >= numeroCuota);
      }
    });
  }

  MoraPerdonSimulacion? get _sim {
    final sel = widget.contrato;
    final tracked = _trackedPerdonado;
    if (_cuotasSeleccion.isEmpty && tracked <= 0.01) return null;
    return MoraCuotaCalculator.simularPerdonMora(
      contrato: sel,
      numerosCuotaSeleccionados: _cuotasSeleccion,
      moraCobradaHistorial: _moraHist,
      ahoraAr: ArTime.nowAr(),
      trackedPerdonado: tracked,
    );
  }

  /// Cómo se nombra en la confirmación lo que se tildó del remanente. Con el
  /// remanente entero dice el total; con meses sueltos, cuáles.
  String _labelTrackedElegido() {
    final elegidas = _origenTracked
        .where((d) => _trackedSeleccion.contains(d.numeroCuota))
        .toList();
    final monto = _trackedPerdonado.toCurrency();
    if (elegidas.length == _origenTracked.length) {
      return 'la mora de cuotas ya pagadas ($monto)';
    }
    final nombres = elegidas
        .map(
          (d) => d.numeroCuota > 0
              ? 'C${d.numeroCuota}'
              : 'sin origen identificado',
        )
        .join(', ');
    return 'la mora de cuotas ya pagadas de $nombres ($monto)';
  }

  Future<void> _aplicar() async {
    final sel = widget.contrato;
    final sim = _sim;
    if (sim == null || sim.montoPerdonado <= 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Seleccioná al menos una cuota con mora (o el remanente) para perdonar.',
          ),
        ),
      );
      return;
    }

    final labels = sim.cuotasPerdonadas
        .map((d) => 'C${d.numeroCuota} (${d.mesLabel})')
        .join(', ');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          sim.soloTracked
              ? 'Confirmar limpieza de ficha'
              : 'Confirmar perdón de mora',
        ),
        content: Text(
          sim.soloTracked
              ? 'Se limpiará de la ficha ${_labelTrackedElegido()}.\n\n'
                  'Monto ≈ ${sim.montoPerdonado.toCurrency()}\n'
                  'La mora calendario NO se toca'
                  '${sim.cuotasRestantes.isNotEmpty ? ' (queda ${sim.cuotasRestantes.map((d) => 'C${d.numeroCuota}').join(', ')})' : ''}.\n'
                  'Mora operativa: ${sim.moraOperativaPre.toCurrency()} → '
                  '${sim.moraOperativaPost.toCurrency()}.\n\n'
                  '¿Continuar?'
              : 'Se perdonará la mora de: ${labels.isEmpty ? '(ninguna cuota)' : labels}'
                  '${sim.incluyeTracked ? ' + ${_labelTrackedElegido()}' : ''}.\n\n'
                  'Monto ≈ ${sim.montoPerdonado.toCurrency()}\n'
                  '${sim.aplicaExencion ? 'Exención hasta ${ArTime.formatFechaCorta(sim.exentaHasta)}${sim.cubreHastaFinDeMes ? ' (fin de mes)' : ''}.\n' : ''}'
                  'Las cuotas base siguen atrasadas; no se mueve Reg.\n'
                  'Mora operativa: ${sim.moraOperativaPre.toCurrency()} → '
                  '${sim.moraOperativaPost.toCurrency()}.\n\n'
                  '¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(sim.soloTracked ? 'Limpiar ficha' : 'Perdonar mora'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await AdminGate.check(context, ref, forceVerification: true);
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      await ref.read(contratosRepositoryProvider).aplicarPerdonMora(
            contratoId: sel.id,
            sim: sim,
          );
      ref.read(finanzasProvider.notifier).recargar();
      ref.read(contratosMutationTickProvider.notifier).bump();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final msg = sim.soloTracked
          ? 'Ficha limpiada para ${sel.nombreAlumno}. '
              'Mora calendario intacta '
              '(${sim.moraOperativaPost.toCurrency()}).'
          : 'Mora perdonada para ${sel.nombreAlumno}'
              '${sim.aplicaExencion ? ' hasta ${ArTime.formatFechaCorta(sim.exentaHasta)}' : ''}. '
              'Las cuotas siguen pendientes.';
      widget.onApplied?.call();
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo perdonar la mora: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sel = widget.contrato;
    final sim = _sim;
    final tieneTracked = sel.moraPendienteTracked > 0.01;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.cleaning_services_rounded,
                color: Colors.redAccent.shade200,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Perdonar mora (sin mover Reg)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${sel.nombreAlumno}\n'
            'Cuotas vencidas: marcá desde la más vieja; si tildás una, se incluyen '
            'las anteriores (el perdón es una exención hasta una fecha). '
            'La mora de cuotas ya pagadas se elige mes por mes, salteado si querés, '
            'y se puede limpiar sola sin tocar el calendario. '
            'Las cuotas base siguen atrasadas; solo se congela/perdona el interés.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? Colors.white60 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          if (_desgloseNeto.isEmpty && !tieneTracked)
            Text(
              widget.emptyMessage,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            )
          else ...[
            Row(
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _cuotasSeleccion
                              ..clear()
                              ..addAll(
                                _desgloseNeto.map((d) => d.numeroCuota),
                              );
                            _trackedSeleccion
                              ..clear()
                              ..addAll(
                                _origenTracked.map((d) => d.numeroCuota),
                              );
                          }),
                  child: const Text('Todas'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _cuotasSeleccion.clear();
                            _trackedSeleccion.clear();
                          }),
                  child: const Text('Ninguna'),
                ),
                if (tieneTracked && _desgloseNeto.isNotEmpty)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _cuotasSeleccion.clear();
                              _trackedSeleccion
                                ..clear()
                                ..addAll(
                                  _origenTracked.map((d) => d.numeroCuota),
                                );
                            }),
                    child: const Text('Solo ficha'),
                  ),
              ],
            ),
            if (_desgloseNeto.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Text(
                  'CUOTAS VENCIDAS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white54 : Colors.grey.shade700,
                  ),
                ),
              ),
              ..._desgloseNeto.map((d) {
                final checked = _cuotasSeleccion.contains(d.numeroCuota);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  checkboxShape: const CircleBorder(),
                  activeColor: Colors.redAccent,
                  value: checked,
                  onChanged: _busy
                      ? null
                      : (v) => _toggleCuota(d.numeroCuota, v ?? false),
                  title: Text(
                    'C${d.numeroCuota} · ${d.mesLabel}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${d.diasMora}d · ${d.interesBruto.toCurrency()}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                );
              }),
            ],
            if (tieneTracked && _origenTracked.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  'MORA DE CUOTAS YA PAGADAS · '
                  '${sel.moraPendienteTracked.toCurrency()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white54 : Colors.grey.shade700,
                  ),
                ),
              ),
              // Un checkbox por mes de origen, y se perdona de la más vieja a
              // la más nueva: tildar junio incluye abril y mayo. La ficha
              // guarda un monto, no un mes — dejar elegir salteado prometía
              // algo que al releer no se podía sostener.
              ..._origenTracked.map((d) {
                final generica = d.numeroCuota <= 0;
                final mes = d.mesLabel.split(' ').first;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  checkboxShape: const CircleBorder(),
                  activeColor: Colors.redAccent,
                  value: _trackedSeleccion.contains(d.numeroCuota),
                  onChanged: _busy
                      ? null
                      : (v) => _toggleTracked(d.numeroCuota, v ?? false),
                  title: Text(
                    generica
                        ? 'Sin origen identificado'
                        : 'C${d.numeroCuota}${mes.isEmpty ? '' : ' · $mes'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    generica
                        ? '${d.montoAtribuido.toCurrency()} · el historial no '
                              'alcanza para decir de qué cuota salió'
                        : '${d.diasMora > 0 ? '${d.diasMora}d · ' : ''}'
                              '${d.montoAtribuido.toCurrency()}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                );
              }),
              if (_cuotasSeleccion.isEmpty && _trackedPerdonado > 0.01)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Solo limpia ficha, calendario intacto.',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
            if (sim != null) ...[
              const SizedBox(height: 8),
              Text(
                sim.soloTracked
                    ? 'Limpia ficha ≈ ${sim.montoPerdonado.toCurrency()} · '
                        'queda calendario ${sim.moraOperativaPost.toCurrency()}\n'
                        'Mora: ${sim.moraOperativaPre.toCurrency()} → ${sim.moraOperativaPost.toCurrency()}'
                    : 'Perdona ≈ ${sim.montoPerdonado.toCurrency()}'
                        '${sim.aplicaExencion ? ' · exención hasta ${ArTime.formatFechaCorta(sim.exentaHasta)}${sim.cubreHastaFinDeMes ? ' (fin de mes)' : ''}' : ''}'
                        '${sim.incluyeTracked ? ' · +ficha' : ''}\n'
                        'Mora: ${sim.moraOperativaPre.toCurrency()} → ${sim.moraOperativaPost.toCurrency()}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed:
                    _busy || sim == null || sim.montoPerdonado <= 0.01
                        ? null
                        : _aplicar,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_rounded, size: 18),
                label: Text(
                  sim == null
                      ? 'Perdonar mora'
                      : sim.soloTracked
                          ? 'Limpiar ficha'
                          : 'Perdonar (${sim.cuotasPerdonadas.length}'
                              '${sim.incluyeTracked ? '+F' : ''})',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.12),
                  foregroundColor: Colors.redAccent,
                  disabledForegroundColor:
                      Colors.redAccent.withValues(alpha: 0.35),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
