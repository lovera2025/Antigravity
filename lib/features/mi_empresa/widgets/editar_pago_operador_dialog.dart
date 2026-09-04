import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/egreso.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../providers/compromisos_personal_provider.dart';

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

  /// Reloj de pared AR del pago. Se guarda con [ArTime.arToUtc].
  ///
  /// Antes esto era el `DateTime` UTC crudo del egreso: el diálogo mostraba
  /// "18/08" para un pago de las 21:30 del 17, y si tocabas el selector y
  /// elegías lo que te estaba mostrando, el pago se corría un día. Guardaba
  /// además `toIso8601String()` de un `DateTime` local, sin marca de zona.
  late DateTime _fechaAr;
  String _medioPagoSeleccionado = 'Efectivo';

  static const _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _operadorController.text = widget.egreso.proveedor ?? '';
    _montoController.text = widget.egreso.monto.toFormattedNumber();
    final rawId = widget.egreso.eventoId;
    _eventoIdSeleccionado = rawId.isEmpty ? 'OPEX' : rawId;
    final f = widget.egreso.fecha;
    _fechaAr = f != null ? ArTime.toAr(f) : ArTime.nowAr();
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

  /// Solo cambia el día: la hora original se conserva. Sin esto, un pago de las
  /// 21:30 volvía a las 00:00 y cambiaba de día al guardarse.
  Future<void> _elegirFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_fechaAr.year, _fechaAr.month, _fechaAr.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(ArTime.nowAr().year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fechaAr = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _fechaAr.hour,
        _fechaAr.minute,
        _fechaAr.second,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_eventoIdSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná evento o Gasto empresa')),
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
        // Misma política que el resto: instante UTC armado desde el reloj AR.
        'fecha': ArTime.arToUtc(_fechaAr).toIso8601String(),
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

  /// Banda de aviso cuando el egreso está aplicado a una cuenta pendiente.
  /// Vacío —sin ocupar lugar— para los pagos sueltos, que son la mayoría.
  Widget _avisoCuentaPendiente(bool isDark) {
    final compromisoId = (widget.egreso.compromisoId ?? '').trim();
    if (compromisoId.isEmpty) return const SizedBox.shrink();

    final cuentas = ref.watch(compromisosPersonalProvider).value ?? const [];
    final cuenta = cuentas
        .where((c) => c.compromiso.id == compromisoId)
        .map((c) => c.compromiso)
        .firstOrNull;
    if (cuenta == null) return const SizedBox.shrink();

    final detalle = cuenta.concepto?.isNotEmpty == true
        ? '${cuenta.tipo} · ${cuenta.concepto}'
        : cuenta.tipo;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _gold.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.link_rounded, size: 15, color: _gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Aplicado a: $detalle',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            if (widget.egreso.salioDelBolsillo)
              Text(
                'de mi bolsillo',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
          ],
        ),
      ),
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
              // Si el pago descuenta de una cuenta pendiente, conviene saberlo
              // antes de cambiarle el monto: el saldo de esa cuenta se recalcula
              // solo con lo que se guarde acá.
              _avisoCuentaPendiente(isDark),
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
                      '🏢 Gasto empresa (sin evento puntual)',
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
                validator: (v) => v == null ? 'Seleccioná evento o Gasto empresa' : null,
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
                    '${ArTime.formatFechaCorta(ArTime.arToUtc(_fechaAr))} · '
                    '${ArTime.formatHora(ArTime.arToUtc(_fechaAr))}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
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
