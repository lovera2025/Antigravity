import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../models/egreso.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';

/// Diálogo para editar un pago a personal (egreso categoría Personal).
class EditarPagoOperadorDialog extends ConsumerStatefulWidget {
  final Egreso egreso;

  const EditarPagoOperadorDialog({super.key, required this.egreso});

  @override
  ConsumerState<EditarPagoOperadorDialog> createState() =>
      _EditarPagoOperadorDialogState();
}

class _EditarPagoOperadorDialogState
    extends ConsumerState<EditarPagoOperadorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _operadorController = TextEditingController();
  final _montoController = TextEditingController();

  bool _isSubmitting = false;
  List<Map<String, dynamic>> _eventos = [];
  String? _eventoIdSeleccionado;
  DateTime? _fecha;
  String _medioPagoSeleccionado = 'Efectivo';

  static const _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _operadorController.text = widget.egreso.proveedor ?? '';
    _montoController.text = widget.egreso.monto.toFormattedNumber();
    final rawId = widget.egreso.eventoId;
    _eventoIdSeleccionado = rawId.isEmpty ? 'OPEX' : rawId;
    _fecha = widget.egreso.fecha ?? DateTime.now();
    final mp = widget.egreso.medioPago;
    if (mp == 'Efectivo' || mp == 'Transferencia') {
      _medioPagoSeleccionado = mp!;
    }
    _cargarEventos();
  }

  /// Carga primero desde SQLite local (offline-first); intenta refrescar desde la nube
  /// solo si hay red, de manera no-bloqueante para el guardado.
  Future<void> _cargarEventos() async {
    try {
      final db = await LocalDatabase.instance;
      final localRows = await db.rawQuery('''
        SELECT e.id, e.tipo, e.fecha_evento, c.nombre_completo as cliente_nombre
        FROM eventos e
        LEFT JOIN clientes c ON e.cliente_id = c.id
        WHERE COALESCE(e.estado, '') != 'Cancelado'
        ORDER BY e.fecha_evento DESC
        LIMIT 50
      ''');
      var lista = localRows.map<Map<String, dynamic>>((r) => {
            'id': r['id'],
            'tipo': r['tipo'],
            'fecha_evento': r['fecha_evento'],
            'clientes': {'nombre_completo': r['cliente_nombre']},
          }).toList();

      // Si el evento del egreso ya no está visible (cancelado / archivado), lo agregamos al inicio
      // para que el dropdown pueda hidratarse correctamente con su valor actual.
      final sel = _eventoIdSeleccionado;
      if (sel != null && sel != 'OPEX' && !lista.any((e) => e['id'] == sel)) {
        final extra = await db.rawQuery('''
          SELECT e.id, e.tipo, e.fecha_evento, c.nombre_completo as cliente_nombre
          FROM eventos e
          LEFT JOIN clientes c ON e.cliente_id = c.id
          WHERE e.id = ?
          LIMIT 1
        ''', [sel]);
        if (extra.isNotEmpty) {
          final r = extra.first;
          lista = [
            {
              'id': r['id'],
              'tipo': r['tipo'],
              'fecha_evento': r['fecha_evento'],
              'clientes': {'nombre_completo': r['cliente_nombre']},
            },
            ...lista,
          ];
        }
      }

      if (mounted) setState(() => _eventos = lista);
    } catch (e) {
      debugPrint('EditarPagoOperadorDialog: error cargando eventos: $e');
    }
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

  Future<void> _elegirFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _fecha = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_eventoIdSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná evento u OPEX')),
      );
      return;
    }
    if (_fecha == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná la fecha del pago')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final cleanText =
          _montoController.text.replaceAll('.', '').replaceAll(',', '.');
      final monto = double.parse(cleanText);
      final dbEventoId =
          _eventoIdSeleccionado == 'OPEX' ? null : _eventoIdSeleccionado;

      final row = <String, dynamic>{
        'evento_id': dbEventoId,
        'monto': monto,
        'proveedor': _operadorController.text.trim(),
        'categoria': 'Personal',
        'fecha': _fecha!.toIso8601String(),
        'medio_pago': _medioPagoSeleccionado,
      };

      // Offline-first: 1) actualizar local, 2) encolar para sync, 3) si hay red disparar sync.
      final db = await LocalDatabase.instance;
      await db.update('egresos', row, where: 'id = ?', whereArgs: [widget.egreso.id]);

      // Payload completo (incluye id) para que SyncEngine pueda hacer update remoto.
      final remotePayload = {'id': widget.egreso.id, ...row};
      await SyncQueue.enqueue(
        tabla: 'egresos',
        operacion: SyncOperation.update,
        registroId: widget.egreso.id,
        payload: remotePayload,
      );

      final connectivity = ref.read(connectivityServiceProvider);
      if (connectivity.currentStatus == AppConnectivity.online) {
        unawaited(ref.read(syncEngineProvider).syncNow());
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago actualizado'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              color: _gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_rounded, color: _gold, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'EDITAR PAGO',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('EVENTO', Icons.event_note_outlined),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: ValueKey<String>('ev_${_eventoIdSeleccionado}_${_eventos.length}'),
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
                      '🏢 Gasto operativo / OPEX (sin evento)',
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
                onChanged: (val) => setState(() => _eventoIdSeleccionado = val),
                validator: (v) => v == null ? 'Seleccioná evento u OPEX' : null,
              ),
              const SizedBox(height: 16),
              _buildLabel('OPERADOR / PERSONAL', Icons.badge_outlined),
              const SizedBox(height: 6),
              TextFormField(
                controller: _operadorController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: InputDecoration(
                  hintText: 'Nombre del operador...',
                  prefixIcon: const Icon(Icons.person_outline, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresá el nombre';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildLabel('MONTO', Icons.attach_money_rounded),
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
              const SizedBox(height: 16),
              _buildLabel('MEDIO DE PAGO', Icons.account_balance_wallet_rounded),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _medioPagoSeleccionado,
                isExpanded: true,
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
              const SizedBox(height: 16),
              _buildLabel('FECHA DEL PAGO', Icons.calendar_today_rounded),
              const SizedBox(height: 6),
              InkWell(
                onTap: _elegirFecha,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.date_range_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  child: Text(
                    _fecha != null
                        ? '${_fecha!.day.toString().padLeft(2, '0')}/${_fecha!.month.toString().padLeft(2, '0')}/${_fecha!.year}'
                        : 'Elegir fecha',
                    style: TextStyle(
                      fontSize: 14,
                      color: _fecha != null
                          ? (isDark ? Colors.white : Colors.black87)
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
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
            backgroundColor: _gold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text(
            'GUARDAR CAMBIOS',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }
}
