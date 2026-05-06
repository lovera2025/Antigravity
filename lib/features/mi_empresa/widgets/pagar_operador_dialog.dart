import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../../egresos/repositories/egresos_repository.dart';

class PagarOperadorDialog extends ConsumerStatefulWidget {
  /// Si se pasa [eventoIdInicial] se preselecciona ese evento.
  final String? eventoIdInicial;
  final String? tipoEventoInicial;

  const PagarOperadorDialog({
    super.key,
    this.eventoIdInicial,
    this.tipoEventoInicial,
  });

  @override
  ConsumerState<PagarOperadorDialog> createState() => _PagarOperadorDialogState();
}

class _PagarOperadorDialogState extends ConsumerState<PagarOperadorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _operadorController = TextEditingController();
  final _montoController = TextEditingController();

  bool _isSubmitting = false;
  bool _cargandoSugerencia = false;

  // Datos de eventos
  List<Map<String, dynamic>> _eventos = [];
  String? _eventoIdSeleccionado;
  String? _tipoEventoSeleccionado;

  // Algoritmo histórico
  double? _tarifaSugerida;
  List<String> _operadoresConocidos = [];

  // Para este tipo de evento: personas a las que ya les pagaste y monto sugerido
  List<MapEntry<String, double>> _operadoresParaEsteTipo = [];
  bool _cargandoOperadoresTipo = false;

  String _medioPagoSeleccionado = 'Efectivo';

  static const _gold = Color(0xFFD4AF37);
  static const _blue = Colors.blueAccent;

  @override
  void initState() {
    super.initState();
    _eventoIdSeleccionado = widget.eventoIdInicial;
    _tipoEventoSeleccionado = widget.tipoEventoInicial;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final supabase = ref.read(supabaseProvider);

    // 1. Cargar lista de eventos activos (y recientes finalizados)
    try {
      final res = await supabase
          .from('eventos')
          .select('id, tipo, fecha_evento, clientes(nombre_completo)')
          .not('estado', 'eq', 'Cancelado')
          .order('fecha_evento', ascending: false)
          .limit(50);

      final lista = (res as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _eventos = lista;
          // Si venía con un evento preseleccionado, actualizar el tipo
          if (_eventoIdSeleccionado != null && _tipoEventoSeleccionado == null) {
            final ev = lista.firstWhere(
              (e) => e['id'] == _eventoIdSeleccionado,
              orElse: () => {},
            );
            _tipoEventoSeleccionado = ev['tipo'] as String?;
          }
        });
      }
    } catch (e) {
      debugPrint('PagarOperadorDialog: error cargando eventos: $e');
    }

    // 2. Cargar nombres de operadores conocidos (autocomplete)
    try {
      final res = await supabase
          .from('egresos')
          .select('proveedor')
          .eq('categoria', 'Personal');

      final nombres = (res as List)
          .map((r) => (r['proveedor'] ?? '') as String)
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (mounted) setState(() => _operadoresConocidos = nombres);
    } catch (e) {
      debugPrint('PagarOperadorDialog: error cargando operadores: $e');
    }

    // 3. Si ya tenemos tipo de evento, cargar "a quién pagar para este tipo"
    if (_tipoEventoSeleccionado != null && _tipoEventoSeleccionado!.trim().isNotEmpty) {
      _cargarOperadoresParaEsteTipo();
    }
  }

  /// Según el tipo de evento elegido, carga a quiénes sueles pagar y con qué monto (histórico).
  Future<void> _cargarOperadoresParaEsteTipo() async {
    final tipo = _tipoEventoSeleccionado?.trim();
    if (tipo == null || tipo.isEmpty) {
      setState(() => _operadoresParaEsteTipo = []);
      return;
    }

    setState(() => _cargandoOperadoresTipo = true);

    try {
      final supabase = ref.read(supabaseProvider);
      final res = await supabase
          .from('egresos')
          .select('proveedor, monto, eventos(tipo)')
          .eq('categoria', 'Personal')
          .order('fecha', ascending: false)
          .limit(300);

      final lista = (res as List).cast<Map<String, dynamic>>();
      final tipoLower = Evento.normalizarTipo(tipo);

      // Filtrar solo los de este tipo de evento y agrupar por proveedor
      final porProveedor = <String, List<double>>{};
      for (final r in lista) {
        final eventoTipo = (r['eventos'] as Map<String, dynamic>?)?['tipo'] as String?;
        if (eventoTipo == null || Evento.normalizarTipo(eventoTipo) != tipoLower) continue;
        final prov = (r['proveedor'] ?? '').toString().trim();
        if (prov.isEmpty) continue;
        final m = double.tryParse(r['monto'].toString()) ?? 0;
        if (m <= 0) continue;
        porProveedor.putIfAbsent(prov, () => []).add(m);
      }

      // Para cada proveedor, calcular moda/último monto y armar la lista
      final sugeridos = <MapEntry<String, double>>[];
      for (final e in porProveedor.entries) {
        final montoSugerido = _calcularModaOUltimo(e.value);
        sugeridos.add(MapEntry(e.key, montoSugerido));
      }
      // Ordenar por cantidad de pagos (más frecuente primero); si empatan, por nombre
      sugeridos.sort((a, b) {
        final countA = porProveedor[a.key]!.length;
        final countB = porProveedor[b.key]!.length;
        if (countB != countA) return countB.compareTo(countA);
        return a.key.compareTo(b.key);
      });

      if (mounted) {
        setState(() {
          _operadoresParaEsteTipo = sugeridos;
          _cargandoOperadoresTipo = false;
        });
      }
    } catch (e) {
      debugPrint('PagarOperadorDialog: error cargando operadores por tipo: $e');
      if (mounted) {
        setState(() {
          _operadoresParaEsteTipo = [];
          _cargandoOperadoresTipo = false;
        });
      }
    }
  }

  /// Aplica operador y monto sugerido para este tipo (un toque).
  void _aplicarOperadorYMonto(String nombre, double monto) {
    _operadorController.text = nombre;
    _montoController.text = monto.toFormattedNumber();
    setState(() => _tarifaSugerida = monto);
  }

  /// Calcula la moda de una lista de montos (valor más frecuente).
  /// Si hay empate, devuelve el último monto registrado.
  double _calcularModaOUltimo(List<double> montos) {
    if (montos.isEmpty) return 0;
    if (montos.length == 1) return montos.first;

    final freq = <double, int>{};
    for (final m in montos) {
      freq[m] = (freq[m] ?? 0) + 1;
    }
    final maxFreq = freq.values.reduce((a, b) => a > b ? a : b);
    final candidatos = freq.entries.where((e) => e.value == maxFreq).map((e) => e.key).toList();

    // Si hay un único ganador, retornarlo; si hay empate, el último de la lista original
    if (candidatos.length == 1) return candidatos.first;
    // Empate → último monto (primer elemento porque la query trae orden desc)
    return montos.first;
  }

  Future<void> _buscarTarifaSugerida() async {
    final nombre = _operadorController.text.trim();
    final tipo = _tipoEventoSeleccionado;
    if (nombre.isEmpty || tipo == null || tipo.isEmpty) {
      setState(() => _tarifaSugerida = null);
      return;
    }

    setState(() => _cargandoSugerencia = true);

    try {
      final supabase = ref.read(supabaseProvider);
      final res = await supabase
          .from('egresos')
          .select('monto, eventos(tipo)')
          .eq('categoria', 'Personal')
          .ilike('proveedor', nombre)
          .order('fecha', ascending: false)
          .limit(20);

      final montos = (res as List)
          .where((r) {
            final eventoTipo = r['eventos']?['tipo'] as String?;
            return eventoTipo != null &&
                Evento.normalizarTipo(eventoTipo) == Evento.normalizarTipo(tipo);
          })
          .map((r) => double.tryParse(r['monto'].toString()) ?? 0.0)
          .where((m) => m > 0)
          .toList();

      if (mounted) {
        setState(() {
          _tarifaSugerida = montos.isNotEmpty ? _calcularModaOUltimo(montos) : null;
          _cargandoSugerencia = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargandoSugerencia = false);
    }
  }

  void _aplicarSugerencia() {
    if (_tarifaSugerida == null) return;
    final formatted = _tarifaSugerida!.toFormattedNumber();
    setState(() => _montoController.text = formatted);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_eventoIdSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un evento o Gasto Operativo')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final cleanText = _montoController.text.replaceAll('.', '').replaceAll(',', '.');
      final monto = double.parse(cleanText);
      final dbEventoId = _eventoIdSeleccionado == 'OPEX' ? null : _eventoIdSeleccionado;
      final egresosRepo = ref.read(egresosRepositoryProvider);

      if (dbEventoId != null) {
        // ── Offline-first: escribe en SQLite + encola sync ─────────────────
        await egresosRepo.registrarEgreso(
          eventoId: dbEventoId,
          monto: monto,
          proveedor: _operadorController.text.trim(),
          categoria: 'Personal',
          fecha: DateTime.now(),
          medioPago: _medioPagoSeleccionado,
        );
      } else {
        // ── OPEX: sin evento, uso del repo directo para SQLite + sync ──
        await egresosRepo.registrarEgresoSinEvento(
          monto: monto,
          proveedor: _operadorController.text.trim(),
          categoria: 'Personal',
          fecha: DateTime.now(),
          medioPago: _medioPagoSeleccionado,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago al operador registrado'),
            backgroundColor: Color(0xFF00B894),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _operadorController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  String _labelEvento(Map<String, dynamic> ev) {
    final cliente = ev['clientes']?['nombre_completo'] ?? 'Sin cliente';
    final tipo = Evento.formatearTipo(ev['tipo'] as String?);
    final fecha = ev['fecha_evento'] != null
        ? DateTime.tryParse(ev['fecha_evento'])
        : null;
    final fechaStr = fecha != null
        ? '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}'
        : '';
    return '$cliente · $tipo · $fechaStr';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: _gold.withValues(alpha: 0.2)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.engineering_outlined, color: _blue, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'PAGAR OPERADOR',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Selector de Evento ─────────────────────────────────────────
              _buildLabel('EVENTO', Icons.event_note_outlined),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _eventoIdSeleccionado,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: 'Seleccioná el evento...',
                  prefixIcon: const Icon(Icons.celebration_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: 'OPEX',
                    child: Text(
                      '🏢 Gasto Operativo / OPEX (Administrativo)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _gold),
                    ),
                  ),
                  ..._eventos.map((ev) {
                    return DropdownMenuItem<String>(
                      value: ev['id'] as String,
                      child: Text(
                        _labelEvento(ev),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  if (val == 'OPEX') {
                    setState(() {
                      _eventoIdSeleccionado = val;
                      _tipoEventoSeleccionado = null;
                      _tarifaSugerida = null;
                    });
                    if (_operadorController.text.trim().isNotEmpty) {
                      _buscarTarifaSugerida();
                    }
                    return;
                  }
                  
                  final ev = _eventos.firstWhere((e) => e['id'] == val, orElse: () => {});
                  setState(() {
                    _eventoIdSeleccionado = val;
                    _tipoEventoSeleccionado = ev['tipo'] as String?;
                    _tarifaSugerida = null;
                  });
                  // Cargar "a quién sueles pagar" para este tipo de evento
                  _cargarOperadoresParaEsteTipo();
                  if (_operadorController.text.trim().isNotEmpty) {
                    _buscarTarifaSugerida();
                  }
                },
                validator: (v) => v == null ? 'Seleccioná un evento' : null,
              ),

              // ── Para este tipo de evento: a quién sueles pagar ───────────────
              if (_tipoEventoSeleccionado != null &&
                  (_cargandoOperadoresTipo || _operadoresParaEsteTipo.isNotEmpty)) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: _gold),
                    const SizedBox(width: 6),
                    Text(
                      'Para este tipo de evento suelen pagar a:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_cargandoOperadoresTipo)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                        ),
                        SizedBox(width: 8),
                        Text('Buscando...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _operadoresParaEsteTipo.map((e) {
                      final nombre = e.key;
                      final monto = e.value;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _aplicarOperadorYMonto(nombre, monto),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _blue.withValues(alpha: isDark ? 0.15 : 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _blue.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  nombre,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _blue,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  monto.toCurrency(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 14),
              ],

              const SizedBox(height: 16),

              // ── Nombre del Operador ────────────────────────────────────────
              _buildLabel('OPERADOR / PERSONAL', Icons.badge_outlined),
              const SizedBox(height: 6),
              Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                  return _operadoresConocidos.where(
                    (op) => op.toLowerCase().contains(textEditingValue.text.toLowerCase()),
                  );
                },
                onSelected: (val) {
                  _operadorController.text = val;
                  _buscarTarifaSugerida();
                },
                fieldViewBuilder: (context, ctrl, focusNode, onSubmitted) {
                  // Sincronizar con nuestro controller de forma segura post-frame
                  if (ctrl.text != _operadorController.text) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        ctrl.text = _operadorController.text;
                        ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
                      }
                    });
                  }

                  return TextFormField(
                    controller: ctrl,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'Nombre del operador...',
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (val) {
                      _operadorController.text = val;
                      // Buscar sugerencia con debounce implícito al perder foco
                    },
                    onFieldSubmitted: (_) {
                      _operadorController.text = ctrl.text;
                      _buscarTarifaSugerida();
                      onSubmitted();
                      FocusScope.of(context).nextFocus();
                    },
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ingresá el nombre del operador';
                      return null;
                    },
                  );
                },
              ),
              const SizedBox(height: 10),

              // ── Banner de tarifa sugerida ───────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _cargandoSugerencia
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Buscando histórico...',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : _tarifaSugerida != null
                        ? GestureDetector(
                            key: const ValueKey('sugerencia'),
                            onTap: _aplicarSugerencia,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: isDark ? 0.12 : 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _gold.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.history_rounded, color: _gold, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                        children: [
                                          const TextSpan(text: 'Tarifa sugerida (Histórico): '),
                                          TextSpan(
                                            text: _tarifaSugerida!.toCurrency(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: _gold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _gold,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'APLICAR',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
              ),
              const SizedBox(height: 14),

              // ── Monto ──────────────────────────────────────────────────────
              _buildLabel('HONORARIO / MONTO', Icons.attach_money_rounded),
              const SizedBox(height: 6),
              TextFormField(
                controller: _montoController,
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
                  prefixText: '\$ ',
                  hintText: '0,00',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_isSubmitting) _submit();
                },
                validator: (v) {
                  if (v == null || v.trim().isEmpty || v == '0,00') return 'Ingresá el monto';
                  return null;
                },
              ),

              const SizedBox(height: 14),
              _buildLabel('MEDIO DE PAGO', Icons.account_balance_wallet_rounded),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _medioPagoSeleccionado,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: const [
                  DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _medioPagoSeleccionado = val);
                },
              ),

              if (_tipoEventoSeleccionado != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 13, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'Tipo de evento: ${Evento.formatearTipo(_tipoEventoSeleccionado).toUpperCase()}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text(
            'REGISTRAR PAGO',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _gold),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
