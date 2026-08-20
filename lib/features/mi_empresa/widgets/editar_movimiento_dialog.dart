import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/egreso.dart';
import '../../caja_sesiones/models/sesion_caja.dart';
import '../../caja_sesiones/repositories/sesiones_caja_repository.dart';
import '../../cierre_caja/models/turno_caja.dart';
import '../../cierre_caja/providers/cierre_caja_provider.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/utils/currency_input_formatter.dart';
import '../../egresos/providers/egresos_provider.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../bolsa_personal_helpers.dart';
import '../providers/finanzas_provider.dart';
import 'panel_movimientos_sheet.dart';

enum _CategoriaEditable { retiroPersonal, gastoPersonal, gastoEmpresa }

/// Editor de una fila del historial: monto, fecha, concepto y medio de pago.
///
/// Se abre tocando la fila en cualquiera de los dos paneles. Antes existía solo
/// para el bolsillo —y sin ningún lugar que lo abriera—, con el monto como cartel
/// de solo lectura: si un gasto entraba con la cifra o el día equivocados, la
/// única salida era borrarlo y volver a cargarlo.
class EditarMovimientoDialog extends ConsumerStatefulWidget {
  final Egreso egreso;

  /// Desde qué panel se abrió. Solo cambia si se ofrece reclasificar: eso vive
  /// en el bolsillo, que es donde la bolsa de origen significa algo.
  final AmbitoPanel ambito;

  const EditarMovimientoDialog({
    super.key,
    required this.egreso,
    this.ambito = AmbitoPanel.bolsillo,
  });

  @override
  ConsumerState<EditarMovimientoDialog> createState() =>
      _EditarMovimientoDialogState();
}

class _EditarMovimientoDialogState
    extends ConsumerState<EditarMovimientoDialog> {
  late final TextEditingController _conceptoController;
  late final TextEditingController _montoController;
  late _CategoriaEditable _categoria;

  /// Reloj de pared AR del movimiento. Se guarda convertido con
  /// [ArTime.arToUtc]: lo que se ve acá es lo que se ve en el historial.
  late DateTime _fechaAr;
  late String _medioPago;

  bool _isSubmitting = false;
  SesionCaja? _sesion;

  /// "del 06/08/2026" cuando se pudo leer la sesión; vacío mientras carga o si
  /// no está — el aviso se muestra igual, solo que sin nombrar el día.
  String get _cualSesion =>
      _sesion != null ? 'del ${ArTime.formatFechaCorta(_sesion!.abiertaAt)}' : '';

  static const _gold = Color(0xFFD4AF37);
  static const _amber = Color(0xFFFFB74D);
  static const _teal = Color(0xFF26A69A);
  static const _indigo = Color(0xFF5C6BC0);
  static const _violet = Color(0xFF6C63FF);

  bool get _esBolsillo => widget.ambito == AmbitoPanel.bolsillo;

  /// `true` si esta fila entra en el arqueo de una sesión de caja.
  bool get _esDeCaja => (widget.egreso.sesionCajaId ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _conceptoController = TextEditingController(
      text: widget.egreso.proveedorVisible ?? 'Gasto personal',
    );
    _montoController = TextEditingController(
      text: widget.egreso.monto.toFormattedNumber(),
    );

    final f = widget.egreso.fecha;
    _fechaAr = f != null ? ArTime.toAr(f) : ArTime.nowAr();

    _medioPago = (widget.egreso.medioPago ?? '').toLowerCase().trim() ==
            'transferencia'
        ? 'transferencia'
        : 'efectivo';

    final cat = (widget.egreso.categoria ?? '').trim();
    if (cat == kCategoriaRetiroDueno) {
      _categoria = _CategoriaEditable.retiroPersonal;
    } else if (cat == kCategoriaGastoEmpresa) {
      _categoria = _CategoriaEditable.gastoEmpresa;
    } else {
      _categoria = _CategoriaEditable.gastoPersonal;
    }

    if (_esDeCaja) _cargarSesion();
  }

  /// Trae la sesión para poder nombrarla en el aviso ("el cierre del 06/08").
  /// Un aviso que no dice cuál cierre no ayuda a decidir nada.
  Future<void> _cargarSesion() async {
    try {
      final s = await ref
          .read(sesionesCajaRepositoryProvider)
          .getById(widget.egreso.sesionCajaId!.trim());
      if (mounted) setState(() => _sesion = s);
    } catch (_) {
      // Sin la sesión el aviso igual se muestra, solo que sin la fecha.
    }
  }

  @override
  void dispose() {
    _conceptoController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  String get _categoriaDb {
    switch (_categoria) {
      case _CategoriaEditable.retiroPersonal:
        return kCategoriaRetiroDueno;
      case _CategoriaEditable.gastoPersonal:
        return kCategoriaGastoPersonal;
      case _CategoriaEditable.gastoEmpresa:
        return kCategoriaGastoEmpresa;
    }
  }

  String _buildProveedor() {
    final concepto = _conceptoController.text.trim().isEmpty
        ? 'Movimiento'
        : _conceptoController.text.trim();

    // Fuera del bolsillo la categoría no se toca, así que el concepto va tal
    // cual: un `Retiro de caja` o un alquiler no llevan marca de bolsa.
    if (!_esBolsillo) return concepto;

    switch (_categoria) {
      case _CategoriaEditable.retiroPersonal:
      case _CategoriaEditable.gastoEmpresa:
        return concepto;
      case _CategoriaEditable.gastoPersonal:
        // Conservar de qué bolsa salió. Antes esto forzaba `[empresa]` siempre:
        // entrabas a corregirle una letra al concepto, tocabas GUARDAR sin
        // cambiar la categoría, y el gasto pasaba de "salió de tu bolsillo" a
        // "salió del negocio" — el saldo del negocio bajaba por ese monto y el
        // bolsillo subía por el mismo. Plata moviéndose por editar un texto.
        //
        // Si venía como gasto de empresa, esa plata sí salió del negocio y el
        // origen se mantiene aunque cambie el rótulo.
        final veniaDeEmpresa =
            gastoPersonalEsDesdeEmpresa(widget.egreso) ||
            (widget.egreso.categoria ?? '').trim() == kCategoriaGastoEmpresa;
        return veniaDeEmpresa
            ? empaquetarProveedorGastoEmpresa(concepto)
            : empaquetarProveedorGastoPendiente(concepto);
    }
  }

  double get _montoIngresado => CurrencyInputFormatter.parse(_montoController.text);

  /// Solo cambia el día: la hora original se conserva. Sin esto, un movimiento
  /// de las 08:38 se guardaría 00:00 y aparecería a las 21:00 del día anterior.
  Future<void> _elegirFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_fechaAr.year, _fechaAr.month, _fechaAr.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(ArTime.nowAr().year + 1, 12, 31),
      helpText: 'Fecha del movimiento',
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

  /// Refresca lo que quedó viejo. Caja solo si la fila pertenece a una sesión:
  /// no hace falta remover el cierre por editar un alquiler.
  Future<void> _refrescarTodo() async {
    await ref.read(egresosProvider.notifier).refresh();
    await ref.read(finanzasProvider.notifier).recargar();
    if (_esDeCaja) {
      await ref.read(cierreCajaProvider.notifier).refrescarManual();
    }
  }

  Future<void> _guardar() async {
    final monto = _montoIngresado;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto tiene que ser mayor a cero.')),
      );
      return;
    }

    if (!await _confirmarImpactoEnCaja(monto)) return;
    if (!mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(egresosRepositoryProvider);
      await repo.actualizarEgreso(
        id: widget.egreso.id,
        // Fuera del bolsillo la categoría queda como está: reclasificar un
        // `Retiro de caja` a "gasto mío" movería plata entre bolsas sin pedirlo.
        categoria: _esBolsillo ? _categoriaDb : null,
        proveedor: _buildProveedor(),
        medioPago: _medioPago,
        monto: monto,
        fecha: ArTime.arToUtc(_fechaAr),
      );
      await _refrescarTodo();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movimiento actualizado'),
          backgroundColor: Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Aviso solo cuando lo que se tocó puede descuadrar un arqueo.
  ///
  /// El arqueo se guarda congelado y lo esperado se recalcula: si cambia el monto
  /// o el medio de pago de un egreso de una sesión cerrada, esa sesión pasa a
  /// mostrar diferencia. La fecha no mueve ese número —la sesión agarra sus
  /// egresos por id— pero sí deja el papel impreso fechado otro día.
  Future<bool> _confirmarImpactoEnCaja(double monto) async {
    if (!_esDeCaja) return true;

    final montoCambio = (monto - widget.egreso.monto).abs() > 0.01;
    final medioCambio =
        _medioPago != ((widget.egreso.medioPago ?? '').toLowerCase().trim() == 'transferencia'
            ? 'transferencia'
            : 'efectivo');
    final fechaOriginalAr = widget.egreso.fecha != null
        ? ArTime.toAr(widget.egreso.fecha!)
        : null;
    final fechaCambio = fechaOriginalAr == null ||
        fechaOriginalAr.day != _fechaAr.day ||
        fechaOriginalAr.month != _fechaAr.month ||
        fechaOriginalAr.year != _fechaAr.year;

    if (!montoCambio && !medioCambio && !fechaCambio) return true;

    final cerrada = _sesion != null && !_sesion!.estaAbierta;
    final cual = _sesion != null
        ? 'del ${ArTime.formatFechaCorta(_sesion!.abiertaAt)}'
        : 'al que pertenece';

    final lineas = <String>[];
    if (montoCambio || medioCambio) {
      lineas.add(
        cerrada
            ? 'El cierre $cual ya está cerrado. Al cambiar '
                '${montoCambio && medioCambio ? "el monto y el medio de pago" : montoCambio ? "el monto" : "el medio de pago"}, '
                'ese cierre va a mostrar diferencia contra el arqueo que se contó ese día.'
            : 'El cierre $cual sigue abierto, así que el arqueo se va a calcular '
                'con el valor nuevo.',
      );
    }
    if (fechaCambio) {
      lineas.add(
        'El movimiento sigue contando en el cierre $cual, pero va a figurar con '
        'otra fecha: el papel impreso no va a coincidir.',
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Este movimiento es de una caja',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Text(lineas.join('\n\n'), style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.black87),
            child: const Text('GUARDAR IGUAL'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _eliminar() async {
    final avisoCaja = _esDeCaja
        ? '\n\nEs parte de un cierre de caja: ese cierre va a mostrar diferencia '
            'contra el arqueo.'
        : '';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar movimiento?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'Se borra "${widget.egreso.proveedorVisible ?? 'Movimiento'}" por '
          '${widget.egreso.monto.toCurrency()}. Esta acción no se puede deshacer.'
          '$avisoCaja',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(egresosRepositoryProvider);
      await repo.eliminarEgreso(widget.egreso.id);
      await _refrescarTodo();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movimiento eliminado'),
          backgroundColor: Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent;
    if (!_esBolsillo) {
      accent = _indigo;
    } else {
      switch (_categoria) {
        case _CategoriaEditable.retiroPersonal:
          accent = _amber;
          break;
        case _CategoriaEditable.gastoPersonal:
          accent = _teal;
          break;
        case _CategoriaEditable.gastoEmpresa:
          accent = _indigo;
          break;
      }
    }

    return AlertDialog(
      actionsAlignment: MainAxisAlignment.spaceBetween,
      title: Row(
        children: [
          Icon(Icons.edit_rounded, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Editar movimiento',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_esDeCaja) _avisoCaja(isDark),
              _label('MONTO'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _montoController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              _label('FECHA'),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _elegirFecha,
                icon: Icon(Icons.calendar_today_rounded, size: 16, color: accent),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size(double.infinity, 46),
                  side: BorderSide(color: accent.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                label: Text(
                  '${ArTime.formatFechaCorta(ArTime.arToUtc(_fechaAr))} · '
                  '${ArTime.formatHora(ArTime.arToUtc(_fechaAr))}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cambia el día; la hora se mantiene.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
              const SizedBox(height: 16),
              _label('MEDIO DE PAGO'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'efectivo',
                    icon: Icon(Icons.payments_rounded, size: 14),
                    label: Text('Efectivo',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                  ButtonSegment(
                    value: 'transferencia',
                    icon: Icon(Icons.swap_horiz_rounded, size: 14),
                    label: Text('Transferencia',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ],
                selected: {_medioPago},
                onSelectionChanged: (v) => setState(() => _medioPago = v.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  side: WidgetStatePropertyAll(
                    BorderSide(color: _violet.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              if (_esBolsillo) ...[
                const SizedBox(height: 16),
                _label('TIPO DE MOVIMIENTO'),
                const SizedBox(height: 8),
                SegmentedButton<_CategoriaEditable>(
                  segments: const [
                    ButtonSegment(
                      value: _CategoriaEditable.retiroPersonal,
                      icon: Icon(Icons.person_rounded, size: 14),
                      label: Text('Personal',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                    ButtonSegment(
                      value: _CategoriaEditable.gastoEmpresa,
                      icon: Icon(Icons.store_rounded, size: 14),
                      label: Text('Empresa',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                    ButtonSegment(
                      value: _CategoriaEditable.gastoPersonal,
                      icon: Icon(Icons.shopping_bag_rounded, size: 14),
                      label: Text('Gasto mío',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ],
                  selected: {_categoria},
                  onSelectionChanged: (v) => setState(() => _categoria = v.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    side: WidgetStatePropertyAll(
                      BorderSide(color: accent.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _categoria == _CategoriaEditable.retiroPersonal
                      ? 'Plata que sacaste para vos (retiro pendiente).'
                      : _categoria == _CategoriaEditable.gastoEmpresa
                          ? 'Gasto directo del negocio.'
                          : 'Plata que gastaste personalmente.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _label('CONCEPTO'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _conceptoController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ej. Supermercado',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _isSubmitting ? null : _eliminar,
          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
          label: const Text('ELIMINAR',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 11)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _guardar,
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                    )
                  : const Icon(Icons.check_rounded, size: 16),
              label: Text(_isSubmitting ? 'GUARDANDO...' : 'GUARDAR',
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _label(String texto) => Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: _gold,
          letterSpacing: 1,
        ),
      );

  /// Qué se rompe si se toca esta fila, con el cierre nombrado. Un "¿estás
  /// seguro?" genérico no deja decidir nada.
  Widget _avisoCaja(bool isDark) {
    final cual = _cualSesion;
    final cerrada = _sesion != null && !_sesion!.estaAbierta;

    final texto = cerrada
        ? 'Este movimiento es parte del cierre de caja $cual, ya cerrado. Si le '
            'cambiás el monto o el medio de pago, ese cierre va a mostrar '
            'diferencia contra el arqueo.'
        : 'Este movimiento es parte de una caja $cual que sigue abierta. Lo que '
            'cambies acá entra en el arqueo cuando se cierre.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: isDark ? 0.12 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 16, color: _amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto.replaceAll('  ', ' '),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
