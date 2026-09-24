import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../common/utils/currency_extensions.dart';
import '../repositories/finanzas_repository.dart';

/// Nombre corto de la tabla de un cobro, para mostrar.
String etiquetaFuenteCobro(String tabla) {
  switch (tabla) {
    case 'pagos_contrato_alumno':
      return 'Masivo';
    case 'transacciones':
      return 'Particular';
    case 'pagos_prestamo_alquiler':
      return 'Alquiler ítems';
    default:
      return tabla;
  }
}

String etiquetaMedioCobro(dynamic raw) {
  final mp = raw?.toString().toLowerCase().trim();
  if (mp == null || mp.isEmpty) return '(Sin medio)';
  if (mp == 'transferencia') return 'Transferencia';
  if (mp == 'efectivo') return 'Efectivo';
  return raw.toString();
}

double montoCobro(Map<String, dynamic> r) =>
    (r['monto'] as num?)?.toDouble() ?? 0;

/// Buscar cobros y tildar varios. Lo usan "Anular cobro por error" y "Corregir
/// medio de pago".
///
/// Lo tildado se mantiene aunque se cambie la búsqueda, así se juntan cobros de
/// distintos alumnos. Al tildar una línea de un cobro masivo se ofrecen las
/// otras del mismo cobro: un cobro de plan con mora son 4 o 5 filas, y anular
/// solo la cuota dejaría la mora viva.
class SelectorCobros extends ConsumerStatefulWidget {
  final ValueChanged<List<Map<String, dynamic>>> onCambio;
  final bool habilitado;
  final String hintBusqueda;

  const SelectorCobros({
    super.key,
    required this.onCambio,
    this.habilitado = true,
    this.hintBusqueda = 'Ej. GARCÍA, cuota…',
  });

  @override
  ConsumerState<SelectorCobros> createState() => _SelectorCobrosState();
}

class _SugerenciaCobro {
  final String claveBase;
  final String alumno;
  final List<Map<String, dynamic>> lineas;

  const _SugerenciaCobro({
    required this.claveBase,
    required this.alumno,
    required this.lineas,
  });
}

class _SelectorCobrosState extends ConsumerState<SelectorCobros> {
  static const _gold = Color(0xFFD4AF37);

  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _buscado = false;
  List<Map<String, dynamic>> _resultados = [];

  /// En orden de tildado.
  final Map<String, Map<String, dynamic>> _seleccion = {};
  _SugerenciaCobro? _sugerencia;

  static String _clave(Map<String, dynamic> r) => '${r['tabla']}|${r['id']}';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _avisar() => widget.onCambio(_seleccion.values.toList());

  Future<void> _buscar() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresá al menos 2 caracteres para buscar.'),
        ),
      );
      return;
    }
    setState(() {
      _searching = true;
      _resultados = [];
    });
    try {
      final list = await ref
          .read(finanzasRepositoryProvider)
          .buscarPagosParaCorregirMedio(q);
      if (!mounted) return;
      setState(() {
        _resultados = list;
        _searching = false;
        _buscado = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al buscar: $e')));
    }
  }

  Future<void> _alternar(Map<String, dynamic> r) async {
    final clave = _clave(r);
    if (_seleccion.containsKey(clave)) {
      setState(() {
        _seleccion.remove(clave);
        if (_sugerencia?.claveBase == clave) _sugerencia = null;
      });
      _avisar();
      return;
    }
    setState(() {
      _seleccion[clave] = Map<String, dynamic>.from(r);
      _sugerencia = null;
    });
    _avisar();

    if (r['tabla'] != 'pagos_contrato_alumno') return;
    try {
      final hermanas = await ref
          .read(finanzasRepositoryProvider)
          .lineasDelMismoCobro(r['id'].toString());
      final faltan = hermanas
          .where((h) => !_seleccion.containsKey(_clave(h)))
          .toList();
      if (!mounted || faltan.isEmpty || !_seleccion.containsKey(clave)) return;
      setState(() {
        _sugerencia = _SugerenciaCobro(
          claveBase: clave,
          alumno: r['titulo']?.toString() ?? '',
          lineas: faltan,
        );
      });
    } catch (_) {
      // Sin sugerencia: se puede tildar a mano.
    }
  }

  void _tildarCobroCompleto() {
    final s = _sugerencia;
    if (s == null) return;
    setState(() {
      for (final l in s.lineas) {
        _seleccion[_clave(l)] = Map<String, dynamic>.from(l);
      }
      _sugerencia = null;
    });
    _avisar();
  }

  @override
  Widget build(BuildContext context) {
    final grey = Colors.grey.shade600;
    final seleccion = _seleccion.values.toList();
    final total = seleccion.fold<double>(0, (s, r) => s + montoCobro(r));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                enabled: widget.habilitado,
                decoration: InputDecoration(
                  labelText: 'Buscar',
                  hintText: widget.hintBusqueda,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _buscar(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: (_searching || !widget.habilitado) ? null : _buscar,
              child: _searching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Buscar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_resultados.isEmpty && !_searching && _buscado)
          Text('Sin coincidencias.', style: TextStyle(color: grey, fontSize: 13))
        else if (_resultados.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _resultados.length,
              itemBuilder: (ctx, i) => _fila(_resultados[i]),
            ),
          ),
        if (_sugerencia != null) ...[
          const SizedBox(height: 10),
          _cajaSugerencia(_sugerencia!),
        ],
        if (seleccion.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${seleccion.length == 1 ? '1 seleccionado' : '${seleccion.length} seleccionados'}'
            ' · ${total.toCurrency()}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in seleccion)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${r['titulo'] ?? ''} · ${r['concepto'] ?? ''} · '
                          '${montoCobro(r).toCurrency()}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: widget.habilitado
                            ? () => _alternar(r)
                            : null,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _fila(Map<String, dynamic> r) {
    final fecha = DateTime.tryParse(r['fecha_pago']?.toString() ?? '');
    final fechaTxt = fecha != null ? ArTime.formatFechaHora(fecha) : '';
    final tildado = _seleccion.containsKey(_clave(r));
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: widget.habilitado ? () => _alternar(r) : null,
      child: Container(
        decoration: BoxDecoration(
          color: tildado ? _gold.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              tildado ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: tildado ? _gold : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (r['titulo'] ?? '').toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${etiquetaFuenteCobro(r['tabla']?.toString() ?? '')} · '
                    '${r['subtitulo'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  if ((r['concepto'] ?? '').toString().isNotEmpty)
                    Text(
                      r['concepto'].toString(),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '$fechaTxt · ${etiquetaMedioCobro(r['medio_pago'])} · '
                    '${montoCobro(r).toCurrency()}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cajaSugerencia(_SugerenciaCobro s) {
    final monto = s.lineas.fold<double>(0, (t, r) => t + montoCobro(r));
    final n = s.lineas.length;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.orangeAccent.withValues(alpha: 0.12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ese cobro de ${s.alumno} tiene ${n == 1 ? '1 línea más' : '$n líneas más'}'
            ' (${monto.toCurrency()}): '
            '${s.lineas.map((l) => l['concepto'] ?? '').join(', ')}.',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() => _sugerencia = null),
                child: const Text('Solo esa línea'),
              ),
              FilledButton.tonal(
                onPressed: widget.habilitado ? _tildarCobroCompleto : null,
                child: const Text('Tildar todo el cobro'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
