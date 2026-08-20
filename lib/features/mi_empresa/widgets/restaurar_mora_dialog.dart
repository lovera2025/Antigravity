import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/widgets/admin_gate.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/services/cronograma_cuotas_utils.dart';
import '../../eventos/services/mora_cuota_calculator.dart';
import '../../eventos/widgets/perdonar_mora_alumno_dialog.dart';
import '../providers/finanzas_provider.dart';

/// Diálogo administrativo para restaurar mora persistida (`mora_pendiente_tracked`).
/// Pestaña individual: un alumno. Pestaña masiva: todos los vencidos de eventos masivos.
class RestaurarMoraDialog extends ConsumerStatefulWidget {
  const RestaurarMoraDialog({super.key});

  @override
  ConsumerState<RestaurarMoraDialog> createState() => _RestaurarMoraDialogState();
}

enum AjusteMoraModo { monto, dias }

class _RestaurarMoraDialogState extends ConsumerState<RestaurarMoraDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // ── Individual ──
  final _searchCtrl = TextEditingController();
  final _moraCtrl = TextEditingController();
  bool _searching = false;
  bool _submitting = false;
  List<ContratoAlumno> _resultados = [];
  ContratoAlumno? _seleccion;
  DateTime _fechaCalculo = DateTime.now();

  AjusteMoraModo _ajusteModo = AjusteMoraModo.monto;
  bool _ajustarReg = true;
  bool _modificarSoloReg = false;
  DateTime? _nuevaFechaReg;

  // ── Masivo (restaurar) ──
  bool _scanning = false;
  bool _submittingBulk = false;
  bool _excluirBuenaVista = true;
  List<MoraRestauracionCandidato> _candidatos = [];
  final Set<String> _seleccionados = {};
  String? _institucionFiltro;

  // ── Perdonar (filtro) ──
  bool _loadingPerdon = false;
  bool _submittingPerdonBulk = false;
  List<String> _institucionesPerdon = [];
  String? _institucionPerdon;
  int? _cuotasPagadasFiltro; // null = todas
  List<MoraPerdonListadoItem> _perdonItems = [];
  final Set<String> _perdonSeleccionados = {};
  /// null = todos | true = solo con mora | false = solo al día / sin mora operable
  bool? _filtroSoloConMora;
  /// Si true, el masivo limpia solo saldo en ficha (tracked), sin eximir calendario.
  bool _perdonMasivoSoloFicha = false;
  /// Filtro extra: solo alumnos con tracked > 0.
  bool _filtroSoloFicha = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _cargarInstitucionesPerdon();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _moraCtrl.dispose();
    super.dispose();
  }

  // ── Individual ─────────────────────────────────────────────────────────────

  Future<void> _buscar() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, ingrese al menos 2 caracteres para buscar.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _searching = true;
      _seleccion = null;
      _resultados = [];
    });

    try {
      final repo = ref.read(contratosRepositoryProvider);
      final list = await repo.buscarContratosParaMora(q);
      if (!mounted) return;
      setState(() {
        _resultados = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al realizar la búsqueda: $e')),
      );
    }
  }

  void _seleccionarContrato(ContratoAlumno contrato) {
    setState(() {
      _seleccion = contrato;
      _fechaCalculo = ArTime.nowAr();
      _nuevaFechaReg = contrato.createdAt != null
          ? ArTime.toAr(contrato.createdAt!)
          : ArTime.nowAr();
    });
    _recalcularMora();
  }

  void _recalcularMora() {
    final sel = _seleccion;
    if (sel == null) return;
    final resumen = MoraCuotaCalculator.calcular(sel, _fechaCalculo);
    setState(() {
      _ajusteModo = AjusteMoraModo.monto;
      _moraCtrl.text = resumen.interesAcumulado.toStringAsFixed(2);
    });
  }

  MoraRestauracionSimulacion? get _simulacion {
    final sel = _seleccion;
    if (sel == null) return null;

    if (_modificarSoloReg) {
      final regSug = _nuevaFechaReg ??
          (sel.createdAt != null
              ? ArTime.toAr(sel.createdAt!)
              : ArTime.nowAr());
      final tempContrato = sel.copyWith(
        createdAt: DateTime.utc(regSug.year, regSug.month, regSug.day, 3, 0, 0),
      );
      final resumen =
          MoraCuotaCalculator.calcular(tempContrato, _fechaCalculo);
      final cuota = MoraCuotaCalculator.cuotaBaseDe(sel);
      final tasa = double.parse((cuota * 0.01).toStringAsFixed(2));

      return MoraRestauracionSimulacion(
        diasMoraSolicitados: resumen.diasMora,
        diasMoraEfectivos: resumen.diasMora,
        cuotaBase: cuota,
        tasaDiaria: tasa,
        montoMora: resumen.interesAcumulado,
        proximaCuotaNumero: resumen.proximaCuotaNumero,
        vencimientoActual: sel.createdAt != null
            ? MoraCuotaCalculator.vencimientoCuotaDesdeRegAr(
                ArTime.toAr(sel.createdAt!),
                resumen.proximaCuotaNumero ?? 1,
              )
            : null,
        vencimientoCoherente: resumen.fechaVencimientoProximaCuota,
        regActual: sel.createdAt != null ? ArTime.toAr(sel.createdAt!) : null,
        regSugerido: regSug,
      );
    }

    if (_ajusteModo == AjusteMoraModo.monto) {
      final m = double.tryParse(_moraCtrl.text.trim()) ?? 0.0;
      return MoraCuotaCalculator.simularPorMonto(sel, m, ahoraAr: _fechaCalculo);
    } else {
      final d = int.tryParse(_moraCtrl.text.trim()) ?? 0;
      return MoraCuotaCalculator.simularPorDias(sel, d, ahoraAr: _fechaCalculo);
    }
  }

  Future<void> _cambiarFecha() async {
    final nowAr = ArTime.nowAr();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaCalculo.isAfter(nowAr) ? nowAr : _fechaCalculo,
      firstDate: DateTime(2020),
      lastDate: nowAr.add(const Duration(days: 30)),
      helpText: 'Seleccionar fecha para simulación',
    );

    if (picked != null) {
      setState(() {
        _fechaCalculo = DateTime(
          picked.year,
          picked.month,
          picked.day,
          12,
          0,
          0,
        );
      });
      _recalcularMora();
    }
  }

  Future<void> _elegirFechaRegManual() async {
    final sel = _seleccion;
    if (sel == null) return;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _nuevaFechaReg ?? ArTime.nowAr(),
      firstDate: DateTime(2020),
      lastDate: ArTime.nowAr().add(const Duration(days: 365)),
      helpText: 'Seleccionar fecha de registro (alta)',
    );

    if (picked != null) {
      setState(() {
        _nuevaFechaReg = DateTime(
          picked.year,
          picked.month,
          picked.day,
          12,
          0,
          0,
        );
      });
    }
  }

  Future<void> _aplicarIndividual() async {
    final sel = _seleccion;
    if (sel == null) return;

    final sim = _simulacion;
    if (sim == null) return;

    final ok = await AdminGate.check(context, ref, forceVerification: true);
    if (!ok || !mounted) return;

    setState(() => _submitting = true);

    try {
      final repo = ref.read(contratosRepositoryProvider);
      final cambiaReg = _modificarSoloReg ||
          (_ajustarReg && sim.puedeAjustarReg);
      final trackedDeseado = cambiaReg ? 0.0 : sim.montoMora;
      final extra = <String, dynamic>{};

      ContratoAlumno? contratoParaObjetivo;
      if (_modificarSoloReg) {
        if (_nuevaFechaReg == null) {
          throw Exception('Debe seleccionar una fecha de registro válida.');
        }
        extra['created_at'] =
            MoraCuotaCalculator.regArAUtcIso(_nuevaFechaReg!);
        contratoParaObjetivo = sel.copyWith(
          createdAt: DateTime.parse(extra['created_at'] as String),
        );
      } else if (_ajustarReg && sim.puedeAjustarReg) {
        extra['created_at'] =
            MoraCuotaCalculator.regArAUtcIso(sim.regSugerido!);
        contratoParaObjetivo = sel.copyWith(
          createdAt: DateTime.parse(extra['created_at'] as String),
        );
      }

      await repo.aplicarTrackedDeseado(
        sel.id,
        trackedDeseado: trackedDeseado,
        extraUpdates: extra,
        contratoParaObjetivo: contratoParaObjetivo,
      );
      ref.read(finanzasProvider.notifier).recargar();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _modificarSoloReg
                ? 'Fecha de registro modificada y mora del momento aplicada para ${sel.nombreAlumno}.'
                : cambiaReg
                    ? 'Reg ajustado para ${sel.nombreAlumno}; la mora queda según el calendario de cuotas.'
                    : 'Mora para ${sel.nombreAlumno} restaurada a ${sim.montoMora.toCurrency()}.',
          ),
          backgroundColor: const Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo restaurar la mora: $e')),
      );
    }
  }

  // ── Masivo ─────────────────────────────────────────────────────────────────

  Future<void> _escanearVencidos() async {
    setState(() {
      _scanning = true;
      _candidatos = [];
      _seleccionados.clear();
      _institucionFiltro = null;
    });

    try {
      final repo = ref.read(contratosRepositoryProvider);
      final list = await repo.listarCandidatosRestauracionMora(
        excluirBuenaVista: _excluirBuenaVista,
      );
      if (!mounted) return;
      setState(() {
        _candidatos = list;
        _seleccionados.addAll(list.map((c) => c.contrato.id));
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al escanear: $e')),
      );
    }
  }

  List<MoraRestauracionCandidato> get _candidatosVisibles {
    if (_institucionFiltro == null) return _candidatos;
    return _candidatos
        .where((c) => c.institucionLabel == _institucionFiltro)
        .toList();
  }

  List<MapEntry<String, int>> get _institucionesConVencidos {
    final counts = <String, int>{};
    for (final c in _candidatos) {
      final k = c.institucionLabel;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return entries;
  }

  double get _totalMoraSeleccionada {
    var t = 0.0;
    for (final c in _candidatos) {
      if (_seleccionados.contains(c.contrato.id)) {
        t += c.moraAplicar;
      }
    }
    return double.parse(t.toStringAsFixed(2));
  }

  Future<void> _aplicarMasivo() async {
    if (_seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione al menos un alumno.')),
      );
      return;
    }

    final n = _seleccionados.length;
    final total = _totalMoraSeleccionada;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar restauración masiva'),
        content: Text(
          'Se restaurará la mora persistida en $n alumno${n == 1 ? '' : 's'} '
          'con cuotas vencidas.\n\nTotal mora: ${total.toCurrency()}\n\n'
          '¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await AdminGate.check(context, ref, forceVerification: true);
    if (!ok || !mounted) return;

    setState(() => _submittingBulk = true);

    try {
      final repo = ref.read(contratosRepositoryProvider);
      final updates = <String, double>{};
      for (final c in _candidatos) {
        if (_seleccionados.contains(c.contrato.id) &&
            c.contrato.cuotasPagadas > 0) {
          updates[c.contrato.id] = c.moraAplicar;
        }
      }

      final count = await repo.restaurarMoraBulk(updates);
      ref.read(finanzasProvider.notifier).recargar();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mora restaurada en $count contrato${count == 1 ? '' : 's'} '
            '(${total.toCurrency()} total).',
          ),
          backgroundColor: const Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingBulk = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo restaurar la mora: $e')),
      );
    }
  }

  // ── Perdonar (filtro) ──────────────────────────────────────────────────────

  Future<void> _cargarInstitucionesPerdon() async {
    try {
      final repo = ref.read(contratosRepositoryProvider);
      final list = await repo.listarInstitucionesMasivosActivos();
      if (!mounted) return;
      setState(() => _institucionesPerdon = list);
    } catch (_) {}
  }

  List<MoraPerdonListadoItem> get _perdonItemsVisibles {
    Iterable<MoraPerdonListadoItem> list = _perdonItems;
    if (_filtroSoloFicha) {
      list = list.where((i) => i.tieneTracked);
    }
    if (_filtroSoloConMora == true) {
      list = list.where((i) => _itemPuedePerdonarEnModo(i));
    } else if (_filtroSoloConMora == false) {
      list = list.where((i) => !_itemPuedePerdonarEnModo(i));
    }
    return list.toList();
  }

  bool _itemPuedePerdonarEnModo(MoraPerdonListadoItem i) =>
      _perdonMasivoSoloFicha ? i.puedePerdonarSoloFicha : i.puedePerdonarCompleto;

  MoraPerdonSimulacion? _simParaItem(MoraPerdonListadoItem i) =>
      _perdonMasivoSoloFicha ? i.simPerdonSoloTracked : i.simPerdonCompleto;

  double get _totalPerdonSeleccionado {
    var t = 0.0;
    for (final i in _perdonItems) {
      if (!_perdonSeleccionados.contains(i.contrato.id)) continue;
      t += _simParaItem(i)?.montoPerdonado ?? 0;
    }
    return double.parse(t.toStringAsFixed(2));
  }

  Future<void> _cargarListadoPerdon() async {
    final inst = _institucionPerdon;
    if (inst == null || inst.isEmpty) {
      setState(() {
        _perdonItems = [];
        _perdonSeleccionados.clear();
      });
      return;
    }

    setState(() => _loadingPerdon = true);
    try {
      final repo = ref.read(contratosRepositoryProvider);
      final list = await repo.listarParaPerdonMora(
        institucion: inst,
        cuotasPagadasExactas: _cuotasPagadasFiltro,
      );
      if (!mounted) return;
      setState(() {
        _perdonItems = list;
        _perdonSeleccionados
          ..clear()
          ..addAll(
            list.where(_itemPuedePerdonarEnModo).map((i) => i.contrato.id),
          );
        _loadingPerdon = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPerdon = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al listar: $e')),
      );
    }
  }

  Future<void> _aplicarPerdonMasivo() async {
    final elegibles = _perdonItems
        .where(
          (i) =>
              _perdonSeleccionados.contains(i.contrato.id) &&
              _itemPuedePerdonarEnModo(i),
        )
        .toList();
    if (elegibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccioná al menos un alumno con mora para perdonar.'),
        ),
      );
      return;
    }

    final n = elegibles.length;
    final total = _totalPerdonSeleccionado;
    final modoFicha = _perdonMasivoSoloFicha;
    final hasta = elegibles.first.simPerdonCompleto?.exentaHasta;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          modoFicha
              ? 'Confirmar perdón (solo ficha)'
              : 'Confirmar perdón masivo',
        ),
        content: Text(
          modoFicha
              ? 'Se limpiará la mora de cuotas ya pagadas de $n alumno'
                  '${n == 1 ? '' : 's'} '
                  '(${_institucionPerdon ?? ''}'
                  '${_cuotasPagadasFiltro != null ? ', cuota $_cuotasPagadasFiltro' : ''}).\n\n'
                  'Total ≈ ${total.toCurrency()}\n'
                  'La mora calendario (cuotas vencidas) NO se toca.\n'
                  'No se modifica el Reg ni la exención.\n\n'
                  '¿Continuar?'
              : 'Se perdonará la mora de $n alumno${n == 1 ? '' : 's'} '
                  '(${_institucionPerdon ?? ''}'
                  '${_cuotasPagadasFiltro != null ? ', cuota $_cuotasPagadasFiltro' : ''}).\n\n'
                  'Total ≈ ${total.toCurrency()}\n'
                  'Exención hasta ${hasta != null ? ArTime.formatFechaCorta(hasta) : '—'} (fin de mes).\n'
                  'No se modifica el Reg.\n'
                  'Las cuotas base siguen pendientes.\n\n'
                  '¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(modoFicha ? 'Limpiar ficha' : 'Perdonar mora'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await AdminGate.check(context, ref, forceVerification: true);
    if (!ok || !mounted) return;

    setState(() => _submittingPerdonBulk = true);
    try {
      final repo = ref.read(contratosRepositoryProvider);
      final map = <String, MoraPerdonSimulacion>{
        for (final i in elegibles) i.contrato.id: _simParaItem(i)!,
      };
      final count = await repo.perdonarMoraBulk(map);
      ref.read(finanzasProvider.notifier).recargar();
      ref.read(contratosMutationTickProvider.notifier).bump();
      if (!mounted) return;

      // Refresco en vivo del listado (mismos filtros).
      await _cargarListadoPerdon();
      if (!mounted) return;
      setState(() => _submittingPerdonBulk = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            modoFicha
                ? 'Ficha limpiada en $count contrato${count == 1 ? '' : 's'} '
                    '(${total.toCurrency()}). Sync encolado.'
                : 'Mora perdonada en $count contrato${count == 1 ? '' : 's'} '
                    '(${total.toCurrency()}). Sync encolado.',
          ),
          backgroundColor: const Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingPerdonBulk = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo perdonar la mora: $e')),
      );
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);
    final busy = _submitting || _submittingBulk || _submittingPerdonBulk;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_backup_restore_rounded, color: gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Restaurar / perdonar mora',
              style: GoogleFonts.oswald(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: gold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabCtrl,
              labelColor: gold,
              unselectedLabelColor: isDark ? Colors.white54 : Colors.grey.shade600,
              indicatorColor: gold,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Individual'),
                Tab(text: 'Restaurar (vencidos)'),
                Tab(text: 'Perdonar (filtro)'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 440,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildIndividualTab(isDark, gold, busy),
                  _buildMasivoTab(isDark, gold, busy),
                  _buildPerdonFiltroTab(isDark, gold, busy),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        if (_tabCtrl.index == 0 && _seleccion != null)
          FilledButton(
            onPressed: busy ? null : _aplicarIndividual,
            style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : Text(
                    _modificarSoloReg ? 'Modificar solo Reg' : 'Restaurar Mora + Reg',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
          ),
        if (_tabCtrl.index == 1 && _candidatos.isNotEmpty)
          FilledButton(
            onPressed: busy || _seleccionados.isEmpty ? null : _aplicarMasivo,
            style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _submittingBulk
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : Text(
                    'Restaurar (${_seleccionados.length})',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
          ),
        if (_tabCtrl.index == 2 && _perdonItems.isNotEmpty)
          FilledButton(
            onPressed: busy ||
                    !_perdonItems.any(
                      (i) =>
                          _perdonSeleccionados.contains(i.contrato.id) &&
                          _itemPuedePerdonarEnModo(i),
                    )
                ? null
                : _aplicarPerdonMasivo,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _submittingPerdonBulk
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _perdonMasivoSoloFicha
                        ? 'Limpiar ficha (${_perdonSeleccionados.where((id) => _perdonItems.any((i) => i.contrato.id == id && _itemPuedePerdonarEnModo(i))).length})'
                        : 'Perdonar (${_perdonSeleccionados.where((id) => _perdonItems.any((i) => i.contrato.id == id && _itemPuedePerdonarEnModo(i))).length})',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
          ),
      ],
    );
  }

  Widget _buildIndividualTab(bool isDark, Color gold, bool busy) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Busque al alumno por nombre o colegio. Simule y restaure mora en un contrato.',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Buscar Alumno o Colegio',
                    hintText: 'Ej. Maximiliano, Arguello...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscar(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: (_searching || busy) ? null : _buscar,
                style: FilledButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: _searching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Buscar', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_resultados.isEmpty && !_searching && _searchCtrl.text.trim().length >= 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No se encontraron coincidencias.',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (_resultados.isNotEmpty && _seleccion == null)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _resultados.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final a = _resultados[i];
                  return ListTile(
                    title: Text(
                      a.nombreAlumno,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      '${a.institucion ?? 'Sin colegio'} · Saldo: ${a.saldoDeudor.toCurrency()}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, size: 20, color: gold),
                    onTap: () => _seleccionarContrato(a),
                  );
                },
              ),
            ),
          if (_seleccion != null) ...[
            const SizedBox(height: 16),
            _buildDetalleContrato(isDark, gold),
            const SizedBox(height: 16),
            if (!_modificarSoloReg) ...[
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<AjusteMoraModo>(
                      segments: const [
                        ButtonSegment(value: AjusteMoraModo.monto, label: Text('Por monto')),
                        ButtonSegment(value: AjusteMoraModo.dias, label: Text('Por días')),
                      ],
                      selected: {_ajusteModo},
                      onSelectionChanged: (set) {
                        setState(() {
                          _ajusteModo = set.first;
                          _moraCtrl.clear();
                        });
                      },
                      style: SegmentedButton.styleFrom(
                        selectedForegroundColor: Colors.black,
                        selectedBackgroundColor: gold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _moraCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _ajusteModo == AjusteMoraModo.monto ? 'Monto a Aplicar (\$)' : 'Días de atraso',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                        prefixIcon: Icon(_ajusteModo == AjusteMoraModo.monto ? Icons.monetization_on_rounded : Icons.calendar_today_rounded, color: gold, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.restart_alt_rounded, color: gold),
                          tooltip: 'Restablecer al sugerido',
                          onPressed: _recalcularMora,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: gold,
                title: const Text('Ajustar Reg (info) al restaurar', style: TextStyle(fontWeight: FontWeight.w600)),
                value: _ajustarReg,
                onChanged: (v) => setState(() => _ajustarReg = v ?? true),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.05),
                  border: Border.all(color: gold.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit_calendar_rounded, color: gold, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fecha de registro (alta) a aplicar:',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _nuevaFechaReg != null
                                ? ArTime.formatFechaCorta(_nuevaFechaReg!)
                                : 'Seleccione una fecha',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _submitting ? null : _elegirFechaRegManual,
                      icon: const Icon(Icons.calendar_month_rounded, size: 16, color: Colors.black),
                      label: const Text('Elegir fecha', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: TextButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: gold,
              title: const Text('Modificar solo Reg (alta de inscripción)', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _modificarSoloReg,
              onChanged: (v) {
                setState(() {
                  _modificarSoloReg = v ?? false;
                  if (_modificarSoloReg) {
                    _ajustarReg = true;
                    final sim = _simulacion;
                    if (sim != null && sim.regSugerido != null) {
                      _nuevaFechaReg = sim.regSugerido;
                    } else if (_seleccion != null && _seleccion!.createdAt != null) {
                      _nuevaFechaReg = ArTime.toAr(_seleccion!.createdAt!);
                    } else {
                      _nuevaFechaReg = ArTime.nowAr();
                    }
                  }
                });
              },
            ),
            if (_simulacion != null) ...[
              const SizedBox(height: 8),
              _buildVistaPrevia(isDark, gold),
            ],
            const SizedBox(height: 20),
            PerdonarMoraForm(
              key: ValueKey(_seleccion!.id),
              contrato: _seleccion!,
              enabled: !busy,
              onApplied: () {
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetalleContrato(bool isDark, Color gold) {
    final sel = _seleccion!;
    final resumen = MoraCuotaCalculator.calcular(sel, _fechaCalculo);
    final createdAt = sel.createdAt != null ? ArTime.toAr(sel.createdAt!) : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sel.nombreAlumno, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
          const SizedBox(height: 4),
          Text('Colegio: ${sel.institucion ?? 'No especificado'}', style: const TextStyle(fontSize: 12.5)),
          Text(
            '${sel.totalCuotas} cuotas (${sel.cuotasPagadas} pagadas) · Saldo: ${sel.saldoDeudor.toCurrency()}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reg actual: ${createdAt != null ? ArTime.formatFechaCorta(createdAt) : 'N/A'}\n'
                  'Vto. próximo: ${resumen.fechaVencimientoProximaCuota != null ? ArTime.formatFechaCorta(resumen.fechaVencimientoProximaCuota!) : 'N/A'}\n'
                  'Mora actual: ${sel.moraPendienteTracked.toCurrency()}',
                  style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.4),
                ),
              ),
              IconButton(
                icon: Icon(Icons.calendar_month_rounded, color: gold, size: 18),
                tooltip: 'Cambiar fecha de simulación',
                onPressed: _submitting ? null : _cambiarFecha,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVistaPrevia(bool isDark, Color gold) {
    final sim = _simulacion!;
    final okReg = sim.puedeAjustarReg;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _modificarSoloReg
                ? 'Mora del momento (cálculo dinámico)'
                : 'Vista previa al restaurar mora',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: gold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _modificarSoloReg ? 'Mora resultante:' : 'Monto:',
                style: const TextStyle(fontSize: 12),
              ),
              Text(sim.montoMora.toCurrency(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Días (mes vencido):', style: const TextStyle(fontSize: 12)),
              Text('${sim.diasMoraEfectivos}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          if (_ajustarReg || _modificarSoloReg) ...[
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _modificarSoloReg ? 'Fecha Reg a aplicar:' : 'Reg sugerido:',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _modificarSoloReg
                      ? (_nuevaFechaReg != null ? ArTime.formatFechaCorta(_nuevaFechaReg!) : 'N/A')
                      : (okReg ? ArTime.formatFechaCorta(sim.regSugerido!) : 'No aplica'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: (_modificarSoloReg || okReg)
                        ? (isDark ? Colors.greenAccent : Colors.green)
                        : Colors.red,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Vto. cuota ${sim.proximaCuotaNumero ?? '?'}:', style: const TextStyle(fontSize: 12)),
                Text(
                  (_modificarSoloReg || okReg)
                      ? (sim.vencimientoCoherente != null ? ArTime.formatFechaCorta(sim.vencimientoCoherente!) : 'N/A')
                      : 'N/A',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildMasivoTab(bool isDark, Color gold, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escanea alumnos con cuota vencida. Mora = 1% de la cuota base por cada '
          'día de atraso (ej. cuota \$30.000 → \$300/día × 20 d = \$6.000). '
          'Descontando interés mora ya cobrado.',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? Colors.white70 : Colors.grey.shade700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Excluir Colegio Buena Vista', style: TextStyle(fontSize: 13)),
                value: _excluirBuenaVista,
                activeColor: gold,
                onChanged: busy
                    ? null
                    : (v) => setState(() => _excluirBuenaVista = v ?? true),
              ),
            ),
            FilledButton.icon(
              onPressed: (_scanning || busy) ? null : _escanearVencidos,
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.radar_rounded, size: 18),
              label: Text(
                _scanning ? 'Escaneando...' : 'Escanear vencidos',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (_candidatos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Instituciones con vencidos (${_institucionesConVencidos.length}):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text('Todas (${_candidatos.length})'),
                    selected: _institucionFiltro == null,
                    onSelected: busy
                        ? null
                        : (_) => setState(() => _institucionFiltro = null),
                    selectedColor: gold.withValues(alpha: 0.25),
                    checkmarkColor: gold,
                  ),
                ),
                for (final e in _institucionesConVencidos)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(
                        '${e.key} (${e.value})',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      selected: _institucionFiltro == e.key,
                      onSelected: busy
                          ? null
                          : (_) => setState(() => _institucionFiltro = e.key),
                      selectedColor: gold.withValues(alpha: 0.25),
                      checkmarkColor: gold,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _seleccionados.addAll(
                          _candidatosVisibles.map((c) => c.contrato.id),
                        );
                      }),
                child: const Text('Todos', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        for (final c in _candidatosVisibles) {
                          _seleccionados.remove(c.contrato.id);
                        }
                      }),
                child: const Text('Ninguno', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              Text(
                '${_seleccionados.length}/${_candidatos.length} · ${_totalMoraSeleccionada.toCurrency()}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: gold),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Expanded(
          child: _candidatos.isEmpty
              ? Center(
                  child: Text(
                    _scanning
                        ? 'Buscando alumnos vencidos...'
                        : 'Pulse "Escanear vencidos" para ver la lista.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    itemCount: _candidatosVisibles.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final c = _candidatosVisibles[i];
                      final id = c.contrato.id;
                      final checked = _seleccionados.contains(id);
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        activeColor: gold,
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _seleccionados.add(id);
                                } else {
                                  _seleccionados.remove(id);
                                }
                              }),
                        title: Text(
                          c.contrato.nombreAlumno,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        subtitle: Text(
                          _institucionFiltro == null
                              ? '${c.institucionLabel} · ${c.diasMora} d × ${c.tasaDiariaMora.toCurrency()}/d · '
                                  'actual ${c.moraActual.toCurrency()} → ${c.moraAplicar.toCurrency()}'
                              : '${c.diasMora} d × ${c.tasaDiariaMora.toCurrency()}/d · '
                                  'actual ${c.moraActual.toCurrency()} → ${c.moraAplicar.toCurrency()}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPerdonFiltroTab(bool isDark, Color gold, bool busy) {
    final visibles = _perdonItemsVisibles;
    final maxCuotas = _perdonItems.fold<int>(
      9,
      (m, i) => math.max(m, i.contrato.totalCuotas > 0 ? i.contrato.totalCuotas : 9),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Filtrá por institución y cuotas pagadas. Podés perdonar todo (calendario + ficha) '
          'o solo la mora de cuotas ya pagadas, dejando viva la mora de cuotas vencidas.',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? Colors.white70 : Colors.grey.shade700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              label: Text('Todo (cal+ficha)', style: TextStyle(fontSize: 11.5)),
              icon: Icon(Icons.cleaning_services_rounded, size: 16),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Solo ficha', style: TextStyle(fontSize: 11.5)),
              icon: Icon(Icons.folder_shared_outlined, size: 16),
            ),
          ],
          selected: {_perdonMasivoSoloFicha},
          onSelectionChanged: busy
              ? null
              : (s) {
                  setState(() {
                    _perdonMasivoSoloFicha = s.first;
                    if (_perdonMasivoSoloFicha) {
                      _filtroSoloFicha = true;
                    }
                    _perdonSeleccionados
                      ..clear()
                      ..addAll(
                        _perdonItems
                            .where(_itemPuedePerdonarEnModo)
                            .map((i) => i.contrato.id),
                      );
                  });
                },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return _perdonMasivoSoloFicha ? Colors.deepOrange : gold;
              }
              return isDark ? Colors.white70 : Colors.grey.shade700;
            }),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use — value controla selección (no solo inicial).
                value: _institucionPerdon,
                isExpanded: true,
                hint: const Text('Elegir institución…'),
                decoration: InputDecoration(
                  labelText: 'Institución',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: [
                  for (final inst in _institucionesPerdon)
                    DropdownMenuItem(value: inst, child: Text(inst, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        setState(() => _institucionPerdon = v);
                        _cargarListadoPerdon();
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int?>(
                // ignore: deprecated_member_use — value controla selección (no solo inicial).
                value: _cuotasPagadasFiltro,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Cuotas pagadas',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todas'),
                  ),
                  for (var n = 0; n <= maxCuotas; n++)
                    DropdownMenuItem<int?>(
                      value: n,
                      child: Text('$n'),
                    ),
                ],
                onChanged: busy || _institucionPerdon == null
                    ? null
                    : (v) {
                        setState(() => _cuotasPagadasFiltro = v);
                        _cargarListadoPerdon();
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text('Todos (${_perdonItems.length})'),
                  selected: _filtroSoloConMora == null && !_filtroSoloFicha,
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                            _filtroSoloConMora = null;
                            _filtroSoloFicha = false;
                          }),
                  selectedColor: gold.withValues(alpha: 0.25),
                  checkmarkColor: gold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(
                    'Con mora (${_perdonItems.where(_itemPuedePerdonarEnModo).length})',
                  ),
                  selected: _filtroSoloConMora == true && !_filtroSoloFicha,
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                            _filtroSoloConMora = true;
                            _filtroSoloFicha = false;
                          }),
                  selectedColor: Colors.redAccent.withValues(alpha: 0.2),
                  checkmarkColor: Colors.redAccent,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(
                    'Solo ficha (${_perdonItems.where((i) => i.tieneTracked).length})',
                  ),
                  selected: _filtroSoloFicha,
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                            _filtroSoloFicha = true;
                            _filtroSoloConMora = null;
                          }),
                  selectedColor: Colors.deepOrange.withValues(alpha: 0.2),
                  checkmarkColor: Colors.deepOrange,
                ),
              ),
              FilterChip(
                label: Text(
                  'Al día / sin mora (${_perdonItems.where((i) => !_itemPuedePerdonarEnModo(i)).length})',
                ),
                selected: _filtroSoloConMora == false && !_filtroSoloFicha,
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                          _filtroSoloConMora = false;
                          _filtroSoloFicha = false;
                        }),
                selectedColor: CronogramaCuotasUtils.colorAlDia.withValues(alpha: 0.2),
                checkmarkColor: CronogramaCuotasUtils.colorAlDia,
              ),
            ],
          ),
        ),
        if (_perdonItems.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                          _perdonSeleccionados.addAll(
                            visibles
                                .where(_itemPuedePerdonarEnModo)
                                .map((i) => i.contrato.id),
                          );
                        }),
                child: Text(
                  _perdonMasivoSoloFicha ? 'Todos con ficha' : 'Todos con mora',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                          for (final i in visibles) {
                            _perdonSeleccionados.remove(i.contrato.id);
                          }
                        }),
                child: const Text('Ninguno', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              if (_loadingPerdon)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  '${_perdonSeleccionados.where((id) => _perdonItems.any((i) => i.contrato.id == id && _itemPuedePerdonarEnModo(i))).length}'
                  '/${_perdonItems.where(_itemPuedePerdonarEnModo).length}'
                  ' · ${_totalPerdonSeleccionado.toCurrency()}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.redAccent,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Expanded(
          child: _institucionPerdon == null
              ? Center(
                  child: Text(
                    'Elegí una institución para listar alumnos.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                )
              : _loadingPerdon
                  ? const Center(child: CircularProgressIndicator())
                  : visibles.isEmpty
                      ? Center(
                          child: Text(
                            'Sin alumnos con esos filtros.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                            ),
                          ),
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.separated(
                            itemCount: visibles.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final item = visibles[i];
                              final c = item.contrato;
                              final id = c.id;
                              final estado = CronogramaCuotasUtils.resolverEstadoUi(
                                contrato: c,
                                moraEnMora: item.enMoraCalendario,
                                moraPendientePesos: item.moraOperativa,
                              );
                              final tCuotas =
                                  c.totalCuotas > 0 ? c.totalCuotas : 1;
                              final puede = _itemPuedePerdonarEnModo(item);
                              final simModo = _simParaItem(item);
                              final checked = _perdonSeleccionados.contains(id);
                              final tracked = c.moraPendienteTracked;

                              return CheckboxListTile(
                                dense: true,
                                value: puede ? checked : false,
                                activeColor: _perdonMasivoSoloFicha
                                    ? Colors.deepOrange
                                    : Colors.redAccent,
                                onChanged: busy || !puede
                                    ? null
                                    : (v) => setState(() {
                                        if (v == true) {
                                          _perdonSeleccionados.add(id);
                                        } else {
                                          _perdonSeleccionados.remove(id);
                                        }
                                      }),
                                title: Text(
                                  c.nombreAlumno,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          estado.icono,
                                          size: 14,
                                          color: estado.color,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          estado.texto,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: estado.color,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Cuotas ${c.cuotasPagadas}/$tCuotas',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _perdonMasivoSoloFicha
                                          ? (puede
                                              ? 'Ya pagadas ${tracked.toCurrency()} → limpia · '
                                                  'queda cal. ${simModo!.moraOperativaPost.toCurrency()}'
                                              : tracked > 0.01
                                                  ? 'Ya pagadas ${tracked.toCurrency()}'
                                                  : 'Sin mora de cuotas ya pagadas')
                                          : puede
                                              ? 'Mora ${item.moraOperativa.toCurrency()}'
                                                  '${simModo != null ? ' → perdón ≈ ${simModo.montoPerdonado.toCurrency()}${simModo.aplicaExencion ? ' hasta ${ArTime.formatFechaCorta(simModo.exentaHasta)}' : ''}' : ''}'
                                                  '${tracked > 0.01 ? ' · ya pagadas ${tracked.toCurrency()}' : ''}'
                                              : item.moraOperativa > 0.01
                                                  ? 'Mora ${item.moraOperativa.toCurrency()}'
                                                      '${tracked > 0.01 ? ' · ya pagadas ${tracked.toCurrency()}' : ''}'
                                                  : 'Sin mora operable',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
