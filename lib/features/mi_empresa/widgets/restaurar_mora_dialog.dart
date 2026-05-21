import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/widgets/admin_gate.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/services/mora_cuota_calculator.dart';
import '../providers/finanzas_provider.dart';

/// Diálogo administrativo para restaurar mora persistida (`mora_pendiente_tracked`).
/// Pestaña individual: un alumno. Pestaña masiva: todos los vencidos de eventos masivos.
class RestaurarMoraDialog extends ConsumerStatefulWidget {
  const RestaurarMoraDialog({super.key});

  @override
  ConsumerState<RestaurarMoraDialog> createState() => _RestaurarMoraDialogState();
}

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

  // ── Masivo ──
  bool _scanning = false;
  bool _submittingBulk = false;
  bool _excluirBuenaVista = true;
  List<MoraRestauracionCandidato> _candidatos = [];
  final Set<String> _seleccionados = {};
  String? _institucionFiltro;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
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
    });
    _recalcularMora();
  }

  void _recalcularMora() {
    final sel = _seleccion;
    if (sel == null) return;
    final resumen = MoraCuotaCalculator.calcular(sel, _fechaCalculo);
    setState(() {
      _moraCtrl.text = resumen.interesAcumulado.toStringAsFixed(2);
    });
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

  Future<void> _aplicarIndividual() async {
    final sel = _seleccion;
    if (sel == null) return;

    final double? montoMora = double.tryParse(_moraCtrl.text.trim());
    if (montoMora == null || montoMora < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingrese un monto de mora válido.')),
      );
      return;
    }

    final ok = await AdminGate.check(context, ref, forceVerification: true);
    if (!ok || !mounted) return;

    setState(() => _submitting = true);

    try {
      final repo = ref.read(contratosRepositoryProvider);
      await repo.actualizarContrato(sel.id, {
        'mora_pendiente_tracked': montoMora,
      });
      ref.read(finanzasProvider.notifier).recargar();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mora para ${sel.nombreAlumno} restaurada a ${montoMora.toCurrency()}.',
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
        if (_seleccionados.contains(c.contrato.id)) {
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

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);
    final busy = _submitting || _submittingBulk;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_backup_restore_rounded, color: gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Restaurar mora persistida',
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
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabCtrl,
              labelColor: gold,
              unselectedLabelColor: isDark ? Colors.white54 : Colors.grey.shade600,
              indicatorColor: gold,
              tabs: const [
                Tab(text: 'Individual'),
                Tab(text: 'Masivo (vencidos)'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 420,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildIndividualTab(isDark, gold, busy),
                  _buildMasivoTab(isDark, gold, busy),
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
                : const Text('Restaurar Mora', style: TextStyle(fontWeight: FontWeight.w900)),
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
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _resultados.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
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
            TextField(
              controller: _moraCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monto de Mora a Aplicar (\$)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                prefixIcon: Icon(Icons.monetization_on_rounded, color: gold, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(Icons.restart_alt_rounded, color: gold),
                  tooltip: 'Restablecer al sugerido',
                  onPressed: _recalcularMora,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetalleContrato(bool isDark, Color gold) {
    final sel = _seleccion!;
    final resumen = MoraCuotaCalculator.calcular(sel, _fechaCalculo);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gold.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withOpacity(0.3), width: 1.5),
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
          Text(
            'Mora persistida actual: ${sel.moraPendienteTracked.toCurrency()}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: gold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child:           Text(
            'Sugerido ${ArTime.formatFechaCorta(_fechaCalculo)}: '
            '${resumen.interesAcumulado.toCurrency()} '
            '(${resumen.diasMora} d × ${(resumen.montoCuotaBaseAprox * 0.01).toCurrency()}/d)',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
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
                    selectedColor: gold.withOpacity(0.25),
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
                      selectedColor: gold.withOpacity(0.25),
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
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    itemCount: _candidatosVisibles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
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
}
