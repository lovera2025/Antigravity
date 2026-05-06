import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/cliente.dart';
import '../../models/prestamo_alquiler.dart';
import '../clientes/repositories/clientes_repository.dart';
import '../common/utils/currency_extensions.dart';
import '../common/utils/currency_input_formatter.dart';
import '../mi_empresa/providers/finanzas_provider.dart';
import 'prestamo_redaccion_helper.dart';
import 'repositories/prestamos_alquiler_repository.dart';

/// Interpreta montos sin obligar a escribir $ ni ceros a la izquierda; acepta `10`, `10,5`, `1.234,56`.
double parseMontoFlexible(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[\$\s]'), '');
  if (s.isEmpty) return 0;
  if (s.contains(',') && s.contains('.')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (s.contains(',')) {
    s = s.replaceAll(',', '.');
  }
  return double.tryParse(s) ?? 0;
}

class _LineaDraft {
  /// Vacío en alta; id de SQLite al editar.
  final String lineaId;
  final TextEditingController desc;
  final TextEditingController cant;
  final TextEditingController precio;

  _LineaDraft({
    this.lineaId = '',
    String descText = '',
    String cantText = '1',
    String precioText = '',
  })  : desc = TextEditingController(text: descText),
        cant = TextEditingController(text: cantText),
        precio = TextEditingController(text: precioText);

  factory _LineaDraft.fromPrestamoLine(PrestamoAlquilerLinea l) {
    final cantStr = l.cantidad % 1 == 0 ? l.cantidad.toInt().toString() : l.cantidad.toString();
    return _LineaDraft(
      lineaId: l.id,
      descText: l.descripcion,
      cantText: cantStr,
      precioText: l.precioUnitario.toFormattedNumber(),
    );
  }

  void dispose() {
    desc.dispose();
    cant.dispose();
    precio.dispose();
  }
}

double _precioUnitFromDraft(_LineaDraft l) {
  final t = l.precio.text.trim();
  if (t.isEmpty) return 0.0;
  return CurrencyInputFormatter.parse(t);
}

/// Alta o edición de préstamo / alquiler de ítems con IVA opcional y redacción para PDF.
class PrestamoAlquilerFormScreen extends ConsumerStatefulWidget {
  final String? prestamoId;

  const PrestamoAlquilerFormScreen({super.key, this.prestamoId});

  @override
  ConsumerState<PrestamoAlquilerFormScreen> createState() => _PrestamoAlquilerFormScreenState();
}

class _PrestamoAlquilerFormScreenState extends ConsumerState<PrestamoAlquilerFormScreen> {
  final _nombreCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _alicuotaCtrl = TextEditingController(text: '21');
  final _redaccionCtrl = TextEditingController();
  final _disclaimerCtrl = TextEditingController();

  String? _clienteIdSeleccionado;
  DateTime _inicio = DateTime.now();
  DateTime _fin = DateTime.now().add(const Duration(days: 1));
  bool _aplicaIva = false;
  bool _guardando = false;
  bool _editLoadDone = false;

  /// Un solo Future para el dropdown; si se recrea en cada build, el valor del cliente
  /// deja de coincidir con [items] mientras carga y Flutter lanza error al hacer scroll.
  Future<List<Cliente>>? _clientesFutureCached;

  late List<_LineaDraft> _lineas = [_LineaDraft()];

  @override
  void initState() {
    super.initState();
    if (widget.prestamoId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cargarEdicion());
    } else {
      _editLoadDone = true;
    }
  }

  @override
  void didUpdateWidget(PrestamoAlquilerFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prestamoId != widget.prestamoId) {
      _clientesFutureCached = null;
    }
  }

  /// Activos + el cliente del préstamo si está archivado o fuera del listado activo.
  Future<List<Cliente>> _clientesParaDropdown() async {
    final repo = ref.read(clientesRepositoryProvider);
    final activos = await repo.getAll(archived: false);
    final sid = _clienteIdSeleccionado;
    if (sid == null || sid.isEmpty) return activos;
    if (activos.any((c) => c.id == sid)) return activos;
    final extra = await repo.getById(sid);
    if (extra == null) return activos;
    final merged = [...activos, extra];
    merged.sort((a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()));
    return merged;
  }

  Future<void> _cargarEdicion() async {
    final id = widget.prestamoId;
    if (id == null) return;
    final repo = ref.read(prestamosAlquilerRepositoryProvider);
    final p = await repo.obtenerPorId(id);
    if (!mounted) return;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Préstamo no encontrado.')));
      Navigator.pop(context);
      return;
    }
    final lineasDb = await repo.lineasDe(id);
    final cli = await ref.read(clientesRepositoryProvider).getById(p.clienteId);

    for (final l in _lineas) {
      l.dispose();
    }
    _lineas = lineasDb.isEmpty
        ? [_LineaDraft()]
        : lineasDb.map(_LineaDraft.fromPrestamoLine).toList();

    setState(() {
      _clienteIdSeleccionado = p.clienteId.isNotEmpty ? p.clienteId : null;
      _nombreCtrl.text = cli?.nombreCompleto ?? '';
      _telCtrl.text = cli?.telefono ?? '';
      _emailCtrl.text = cli?.email ?? '';
      _inicio = p.fechaInicio;
      _fin = p.fechaFin;
      _aplicaIva = p.aplicaIva;
      _alicuotaCtrl.text = p.alicuotaIva % 1 == 0
          ? p.alicuotaIva.toInt().toString()
          : p.alicuotaIva.toString().replaceAll('.', ',');
      _redaccionCtrl.text = p.textoRedaccion ?? '';
      _disclaimerCtrl.text = p.textoDisclaimer ?? '';
      _editLoadDone = true;
    });
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    _alicuotaCtrl.dispose();
    _redaccionCtrl.dispose();
    _disclaimerCtrl.dispose();
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  void _regenerarTexto(PrestamosAlquilerRepository repo) {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completá el nombre del cliente para generar la redacción.')),
      );
      return;
    }
    final lineas = _lineasSnapshot();
    if (lineas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregá al menos una línea con descripción y precio.')),
      );
      return;
    }
    final alicuota = double.tryParse(_alicuotaCtrl.text.replaceAll(',', '.')) ?? 21;
    final tot = PrestamosAlquilerRepository.calcularTotales(
      lineas: lineas,
      aplicaIva: _aplicaIva,
      alicuotaIva: alicuota,
    );
    _redaccionCtrl.text = PrestamoRedaccionHelper.generarCuerpo(
      nombreCliente: nombre,
      fechaInicio: _inicio,
      fechaFin: _fin,
      lineas: lineas,
      subtotalNeto: tot['subtotal_neto']!,
      montoIva: tot['monto_iva']!,
      total: tot['total']!,
      aplicaIva: _aplicaIva,
      alicuotaIva: alicuota,
    );
    if (_disclaimerCtrl.text.trim().isEmpty) {
      _disclaimerCtrl.text = PrestamoRedaccionHelper.disclaimerPredeterminado();
    }
  }

  List<PrestamoAlquilerLinea> _lineasSnapshot() {
    final out = <PrestamoAlquilerLinea>[];
    var orden = 0;
    for (final l in _lineas) {
      final d = l.desc.text.trim();
      if (d.isEmpty) continue;
      final c = parseMontoFlexible(l.cant.text);
      final pu = _precioUnitFromDraft(l);
      if (c <= 0 || pu < 0) continue;
      out.add(PrestamoAlquilerLinea(
        id: l.lineaId,
        prestamoId: widget.prestamoId ?? '',
        descripcion: d,
        cantidad: c,
        precioUnitario: pu,
        lineaTotal: c * pu,
        orden: orden++,
      ));
    }
    return out;
  }

  Future<void> _pickDate({required bool fin}) async {
    final initial = fin ? _fin : _inicio;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (fin) {
        _fin = d;
      } else {
        _inicio = d;
      }
    });
  }

  Future<void> _guardar() async {
    final repo = ref.read(prestamosAlquilerRepositoryProvider);
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre del cliente es obligatorio.')),
      );
      return;
    }

    final lineas = _lineasSnapshot();
    if (lineas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregá al menos un ítem válido (descripción, cantidad y precio).')),
      );
      return;
    }

    final alicuota = double.tryParse(_alicuotaCtrl.text.replaceAll(',', '.')) ?? 21;

    setState(() => _guardando = true);
    try {
      final pid = widget.prestamoId;
      if (pid != null) {
        await repo.actualizarPrestamo(
          prestamoId: pid,
          clienteId: _clienteIdSeleccionado,
          nombreCliente: nombre,
          telefonoCliente: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
          emailCliente: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          fechaInicio: _inicio,
          fechaFin: _fin,
          aplicaIva: _aplicaIva,
          alicuotaIva: alicuota,
          lineasEntrada: lineas,
          textoRedaccion: _redaccionCtrl.text.trim().isEmpty ? null : _redaccionCtrl.text.trim(),
          textoDisclaimer: _disclaimerCtrl.text.trim().isEmpty ? null : _disclaimerCtrl.text.trim(),
        );
      } else {
        await repo.crearPrestamo(
          clienteId: _clienteIdSeleccionado,
          nombreCliente: nombre,
          telefonoCliente: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
          emailCliente: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          fechaInicio: _inicio,
          fechaFin: _fin,
          aplicaIva: _aplicaIva,
          alicuotaIva: alicuota,
          lineasSinId: lineas,
          textoRedaccion: _redaccionCtrl.text.trim().isEmpty ? null : _redaccionCtrl.text.trim(),
          textoDisclaimer: _disclaimerCtrl.text.trim().isEmpty ? null : _disclaimerCtrl.text.trim(),
        );
      }
      if (mounted) {
        ref.invalidate(finanzasProvider);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final esEdicion = widget.prestamoId != null;

    if (esEdicion && !_editLoadDone) {
      return Scaffold(
        appBar: AppBar(
          title: Text('PRÉSTAMO', style: GoogleFonts.oswald(fontWeight: FontWeight.w900, letterSpacing: 2)),
        ),
        body: const Center(child: CircularProgressIndicator(color: gold)),
      );
    }

    _clientesFutureCached ??= _clientesParaDropdown();
    final clientesFuture = _clientesFutureCached!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          esEdicion ? 'EDITAR PRÉSTAMO' : 'NUEVO PRÉSTAMO',
          style: GoogleFonts.oswald(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        actions: [
          TextButton(
            onPressed: _guardando ? null : () => _regenerarTexto(ref.read(prestamosAlquilerRepositoryProvider)),
            child: const Text('TEXTO PDF', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('CLIENTE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
          const SizedBox(height: 8),
          FutureBuilder<List<Cliente>>(
            future: clientesFuture,
            builder: (context, snap) {
              final clientes = snap.data ?? [];
              final valorDropdown = (_clienteIdSeleccionado != null &&
                      clientes.any((c) => c.id == _clienteIdSeleccionado))
                  ? _clienteIdSeleccionado
                  : null;
              return DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: valorDropdown,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: 'Elegir existente o completar abajo como nuevo',
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('— Nuevo / manual —')),
                  ...clientes.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.nombreCompleto)),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _clienteIdSeleccionado = v;
                    if (v != null) {
                      final c = clientes.firstWhere((x) => x.id == v);
                      _nombreCtrl.text = c.nombreCompleto;
                      _telCtrl.text = c.telefono ?? '';
                      _emailCtrl.text = c.email ?? '';
                    }
                  });
                },
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nombreCtrl,
            decoration: InputDecoration(
              labelText: 'Nombre completo *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _telCtrl,
                  decoration: InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('VIGENCIA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(fin: false),
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text('Inicio: ${_inicio.day}/${_inicio.month}/${_inicio.year}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(fin: true),
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text('Fin: ${_fin.day}/${_fin.month}/${_fin.year}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _aplicaIva,
            onChanged: (v) => setState(() => _aplicaIva = v),
            title: const Text('Aplicar IVA sobre el subtotal'),
            subtitle: const Text('Los precios de ítems son sin IVA; se suma al pie.'),
            activeThumbColor: gold,
          ),
          if (_aplicaIva)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _alicuotaCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  labelText: 'Alícuota IVA %',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ÍTEMS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
              TextButton.icon(
                onPressed: () => setState(() => _lineas.add(_LineaDraft())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Línea'),
              ),
            ],
          ),
          ..._lineas.asMap().entries.map((e) {
            final l = e.value;
            final subLinea = parseMontoFlexible(l.cant.text) * _precioUnitFromDraft(l);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: l.desc,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Qué prestás (ej. Sillas)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: l.cant,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Cant.',
                        hintText: '200',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: l.precio,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'P. unitario',
                        hintText: '0,00',
                        helperText: 'Solo números; centavos automáticos',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  if (_lineas.length > 1)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          l.dispose();
                          _lineas.removeAt(e.key);
                        });
                      },
                      icon: Icon(Icons.remove_circle_outline, color: Colors.red.withValues(alpha: 0.7)),
                    ),
                ],
              ),
                  if (l.desc.text.trim().isNotEmpty && subLinea > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        'Subtotal línea: ${subLinea.toCurrency()}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: gold.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          Builder(
            builder: (context) {
              final snap = _lineasSnapshot();
              final tot = PrestamosAlquilerRepository.calcularTotales(
                lineas: snap,
                aplicaIva: _aplicaIva,
                alicuotaIva: double.tryParse(_alicuotaCtrl.text.replaceAll(',', '.')) ?? 21,
              );
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Subtotal: ${tot['subtotal_neto']!.toCurrency()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_aplicaIva && (tot['monto_iva'] ?? 0) > 0)
                      Text('IVA: ${tot['monto_iva']!.toCurrency()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Total: ${tot['total']!.toCurrency()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: gold)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text('TEXTO PDF (editable)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(
            controller: _redaccionCtrl,
            maxLines: 5,
            decoration: InputDecoration(
              alignLabelWithHint: true,
              labelText: 'Cuerpo / redacción',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _disclaimerCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Disclaimer / condiciones',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _guardando ? null : _guardar,
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _guardando
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      esEdicion ? 'GUARDAR CAMBIOS' : 'GUARDAR PRÉSTAMO',
                      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
