import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/ar_time.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/widgets/admin_gate.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/services/cronograma_cuotas_utils.dart';
import '../../eventos/services/mora_cuota_calculator.dart';
import '../providers/finanzas_provider.dart';

/// Perdonar la mora de un curso entero de una vez (Mi Empresa, botón de la
/// barra). Es lo único que quedó del viejo "Restaurar / perdonar mora" (6.2.1):
/// "Restaurar (vencidos)" contaba dos veces la mora y borraba perdones, e
/// "Individual" movía el Reg y ponía mora a mano. El perdón de un alumno solo
/// está en el menú ⋮ de la grilla.
class PerdonarMoraPorCursoDialog extends ConsumerStatefulWidget {
  const PerdonarMoraPorCursoDialog({super.key});

  @override
  ConsumerState<PerdonarMoraPorCursoDialog> createState() =>
      _PerdonarMoraPorCursoDialogState();
}

class _PerdonarMoraPorCursoDialogState
    extends ConsumerState<PerdonarMoraPorCursoDialog> {
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
    _cargarInstitucionesPerdon();
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
    final busy = _submittingPerdonBulk;
    final elegidos = _perdonSeleccionados
        .where(
          (id) => _perdonItems.any(
            (i) => i.contrato.id == id && _itemPuedePerdonarEnModo(i),
          ),
        )
        .length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.volunteer_activism_outlined, color: gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Perdonar mora (por curso)',
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
        height: 480,
        child: _buildPerdonFiltroTab(isDark, gold, busy),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        if (_perdonItems.isNotEmpty)
          FilledButton(
            onPressed: busy || elegidos == 0 ? null : _aplicarPerdonMasivo,
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
                        ? 'Limpiar ficha ($elegidos)'
                        : 'Perdonar ($elegidos)',
                    style: const TextStyle(fontWeight: FontWeight.w900),
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
