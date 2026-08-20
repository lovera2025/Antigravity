import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../models/cliente.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../../mi_empresa/providers/finanzas_provider.dart';
import '../providers/egresos_provider.dart';
import '../repositories/egresos_repository.dart';
import '../services/egreso_concepto_sugerencias.dart';

class RegistrarEgresoGlobalDialog extends ConsumerStatefulWidget {
  const RegistrarEgresoGlobalDialog({super.key});

  @override
  ConsumerState<RegistrarEgresoGlobalDialog> createState() =>
      _RegistrarEgresoGlobalDialogState();
}

class _RegistrarEgresoGlobalDialogState
    extends ConsumerState<RegistrarEgresoGlobalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _proveedorController = TextEditingController();
  final _montoController = TextEditingController();

  static const _gold = Color(0xFFD4AF37);
  static const _blue = Colors.blueAccent;
  static const _red = Color(0xFFE74C3C);

  bool _isLoadingEventos = true;
  bool _isSubmitting = false;
  List<Evento> _eventosActivos = [];
  Evento? _eventoSeleccionado;
  EgresoConceptoSugerencias _sugerencias =
      EgresoConceptoSugerencias.fromFilas(const []);

  String _categoriaSeleccionada = kCategoriaComboDefault;
  String _medioPagoSeleccionado = 'Efectivo';
  double? _tarifaSugerida;

  List<String> get _categoriasCombo {
    final list = List<String>.from(kCategoriasEgresoNegocioCombo);
    if (_categoriaSeleccionada.isNotEmpty &&
        !list.contains(_categoriaSeleccionada)) {
      list.add(_categoriaSeleccionada);
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _proveedorController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final repo = ref.read(egresosRepositoryProvider);
    try {
      final filas = await repo.getFilasSugerenciasConcepto();
      if (mounted) {
        setState(() {
          _sugerencias = EgresoConceptoSugerencias.fromFilas(filas);
        });
      }
    } catch (e) {
      debugPrint('RegistrarEgresoGlobalDialog: sugerencias: $e');
    }

    try {
      final db = await LocalDatabase.instance;
      final localRows = await db.rawQuery('''
        SELECT e.id, e.tipo, e.fecha_evento, e.cliente_id,
               c.nombre_completo as cliente_nombre
        FROM eventos e
        LEFT JOIN clientes c ON e.cliente_id = c.id
        WHERE COALESCE(e.estado, '') != 'Cancelado'
        ORDER BY e.fecha_evento DESC
        LIMIT 50
      ''');
      final eventos = <Evento>[];
      for (final r in localRows) {
        final id = r['id']?.toString();
        final tipo = r['tipo']?.toString();
        final fechaRaw = r['fecha_evento']?.toString();
        if (id == null || id.isEmpty || tipo == null || fechaRaw == null) {
          continue;
        }
        final fecha = DateTime.tryParse(fechaRaw);
        if (fecha == null) continue;
        eventos.add(
          Evento(
            id: id,
            clienteId: r['cliente_id']?.toString() ?? '',
            tipo: tipo,
            fechaEvento: fecha,
            estado: EstadoEvento.planificacion,
            cliente: Cliente(
              id: r['cliente_id']?.toString() ?? '',
              nombreCompleto:
                  (r['cliente_nombre'] as String?)?.trim().isNotEmpty == true
                      ? r['cliente_nombre'] as String
                      : 'N/N',
            ),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _eventosActivos = eventos;
          _isLoadingEventos = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingEventos = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar eventos: $e')),
        );
      }
    }
  }

  void _aplicarConcepto(String nombre, {double? monto}) {
    final canon = _sugerencias.nombreCanonico(nombre);
    _proveedorController.text = canon;
    final combo = _sugerencias.categoriaComboAlElegir(canon);
    setState(() {
      if (combo != null) _categoriaSeleccionada = combo;
      _tarifaSugerida = _sugerencias.montoSugeridoOperador(
        canon,
        tipoEvento: _eventoSeleccionado?.tipo,
      );
      if (monto != null) {
        _montoController.text = monto.toFormattedNumber();
      }
    });
  }

  void _onProveedorTyped(String val) {
    _proveedorController.text = val;
    final combo = _sugerencias.categoriaComboAlElegir(val);
    setState(() {
      if (combo != null) _categoriaSeleccionada = combo;
      _tarifaSugerida = _sugerencias.montoSugeridoOperador(
        val,
        tipoEvento: _eventoSeleccionado?.tipo,
      );
    });
  }

  void _onEventoChanged(Evento? val) {
    setState(() => _eventoSeleccionado = val);
    final nombre = _proveedorController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _tarifaSugerida = null);
      return;
    }
    setState(() {
      _tarifaSugerida = _sugerencias.montoSugeridoOperador(
        nombre,
        tipoEvento: val?.tipo,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final cleanText = _montoController.text
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final monto = double.parse(cleanText);
      final proveedor =
          _sugerencias.nombreCanonico(_proveedorController.text);
      final categoria = categoriaEgresoParaGuardar(_categoriaSeleccionada);

      final repo = ref.read(egresosRepositoryProvider);
      final evento = _eventoSeleccionado;
      if (evento != null) {
        await repo.registrarEgreso(
          eventoId: evento.id,
          monto: monto,
          proveedor: proveedor,
          categoria: categoria,
          medioPago: _medioPagoSeleccionado,
        );
      } else {
        await repo.registrarEgresoSinEvento(
          monto: monto,
          proveedor: proveedor,
          categoria: categoria,
          fecha: DateTime.now(),
          medioPago: _medioPagoSeleccionado,
        );
      }

      ref.read(egresosProvider.notifier).refresh();
      await ref.read(finanzasProvider.notifier).recargar();

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago registrado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar pago: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chips = _eventoSeleccionado == null
        ? const <MapEntry<String, double>>[]
        : _sugerencias.operadoresParaTipo(_eventoSeleccionado!.tipo);

    return AlertDialog(
      title: const Text('Registrar pago'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoadingEventos)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  DropdownButtonFormField<Evento>(
                    initialValue: _eventoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Vincular a evento (opcional)',
                      helperText:
                          'Dejalo vacío si es un gasto general del negocio',
                      prefixIcon: Icon(Icons.event),
                    ),
                    isExpanded: true,
                    hint: const Text('Sin evento · gasto del negocio'),
                    items: [
                      const DropdownMenuItem<Evento>(
                        value: null,
                        child: Text('Sin evento · gasto del negocio'),
                      ),
                      ..._eventosActivos.map((evt) {
                        return DropdownMenuItem<Evento>(
                          value: evt,
                          child: Text(
                            '${evt.cliente?.nombreCompleto ?? "N/N"} - ${evt.tipoParaMostrar} (${evt.fechaEvento.day}/${evt.fechaEvento.month})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: _onEventoChanged,
                  ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 12, color: _gold),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final e in chips)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () =>
                                _aplicarConcepto(e.key, monto: e.value),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _blue.withValues(
                                  alpha: isDark ? 0.15 : 0.1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _blue.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    e.key,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _blue,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    e.value.toCurrency(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Autocomplete<String>(
                  optionsBuilder: (textEditingValue) {
                    return _sugerencias.filtrarNombres(textEditingValue.text);
                  },
                  onSelected: (val) => _aplicarConcepto(val),
                  fieldViewBuilder:
                      (context, ctrl, focusNode, onFieldSubmitted) {
                    if (ctrl.text != _proveedorController.text) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        ctrl.text = _proveedorController.text;
                        ctrl.selection = TextSelection.collapsed(
                          offset: ctrl.text.length,
                        );
                      });
                    }
                    return TextFormField(
                      controller: ctrl,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Proveedor / Concepto',
                        hintText: 'Buscá uno ya cargado o escribí uno nuevo',
                        prefixIcon: Icon(Icons.business_center),
                      ),
                      onChanged: _onProveedorTyped,
                      onFieldSubmitted: (_) {
                        _onProveedorTyped(ctrl.text);
                        onFieldSubmitted();
                        FocusScope.of(context).nextFocus();
                      },
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                    );
                  },
                ),
                if (_tarifaSugerida != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _montoController.text =
                            _tarifaSugerida!.toFormattedNumber();
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: isDark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _gold.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded,
                              color: _gold, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tarifa sugerida (histórico): ${_tarifaSugerida!.toCurrency()}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color:
                                    isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
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
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(_categoriaSeleccionada),
                  initialValue: _categoriaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: _categoriasCombo
                      .map(
                        (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _categoriaSeleccionada = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
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
                        selection:
                            TextSelection.collapsed(offset: newText.length),
                      );
                    }),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Monto (\$)',
                    prefixIcon: Icon(Icons.attach_money),
                    hintText: '0,00',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_isSubmitting && !_isLoadingEventos) _submit();
                  },
                  validator: (value) =>
                      (value == null || value == '0,00') ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _medioPagoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Medio de Pago',
                    prefixIcon: Icon(Icons.account_balance_wallet_rounded),
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
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _medioPagoSeleccionado = val);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || _isLoadingEventos ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _red,
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('REGISTRAR PAGO'),
        ),
      ],
    );
  }
}
