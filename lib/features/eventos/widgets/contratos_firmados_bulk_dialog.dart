import 'package:flutter/material.dart';

import '../../common/services/pdf_service.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../repositories/contratos_repository.dart';

/// Diálogo para marcar en bloque si cada alumno tiene contrato firmado (`contrato_firmado`).
class ContratosFirmadosBulkDialog extends StatefulWidget {
  final List<ContratoAlumno> alumnos;
  final ContratosRepository repository;
  final String eventoTitulo;

  const ContratosFirmadosBulkDialog({
    super.key,
    required this.alumnos,
    required this.repository,
    required this.eventoTitulo,
  });

  @override
  State<ContratosFirmadosBulkDialog> createState() => _ContratosFirmadosBulkDialogState();
}

class _ContratosFirmadosBulkDialogState extends State<ContratosFirmadosBulkDialog> {
  late Map<String, bool> _firmadoPorId;
  late Map<String, bool> _originalPorId;
  bool _guardando = false;
  bool _exportandoPdf = false;
  late ScrollController _scrollController;
  late TextEditingController _busquedaCtrl;

  @override
  void initState() {
    super.initState();
    _firmadoPorId = {for (final a in widget.alumnos) a.id: a.contratoFirmado};
    _originalPorId = Map<String, bool>.from(_firmadoPorId);
    _scrollController = ScrollController();
    _busquedaCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  List<ContratoAlumno> get _ordenados {
    final list = List<ContratoAlumno>.from(widget.alumnos);
    list.sort((a, b) => a.nombreAlumno.toLowerCase().compareTo(b.nombreAlumno.toLowerCase()));
    return list;
  }

  String get _q => _busquedaCtrl.text.trim().toLowerCase();

  /// Filtra por nombre o curso (misma idea que la tabla principal).
  List<ContratoAlumno> _filtrar(List<ContratoAlumno> lista) {
    final q = _q;
    if (q.isEmpty) return lista;
    return lista.where((a) {
      final nombre = a.nombreAlumno.toLowerCase();
      final curso = (a.cursoDivision ?? '').toLowerCase();
      return nombre.contains(q) || curso.contains(q);
    }).toList();
  }

  int get _totalEnLista => widget.alumnos.length;

  int get _cuentaFirmados => _firmadoPorId.values.where((v) => v).length;

  int get _cuentaPendientes => _firmadoPorId.length - _cuentaFirmados;

  List<ContratoAlumno> get _pendientes =>
      _ordenados.where((a) => !(_firmadoPorId[a.id] ?? false)).toList();

  List<ContratoAlumno> get _firmados =>
      _ordenados.where((a) => _firmadoPorId[a.id] ?? false).toList();

  void _marcarTodosEnPantalla(bool valor) {
    setState(() {
      for (final id in _firmadoPorId.keys) {
        _firmadoPorId[id] = valor;
      }
    });
  }

  Future<void> _confirmarMarcarTodos(bool marcarComoFirmado) async {
    final n = _totalEnLista;
    if (n == 0 || _guardando) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          marcarComoFirmado ? 'Marcar todos como firmados' : 'Quitar firma a todos',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          marcarComoFirmado
              ? 'Se marcarán los $n alumnos de esta lista como «contrato firmado» '
                    'solo en esta pantalla. Recordá pulsar Guardar para que quede registrado.'
              : 'Se quitará la marca de contrato firmado a los $n alumnos de esta lista '
                    'solo en esta pantalla. Recordá pulsar Guardar para que quede registrado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: marcarComoFirmado
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange.shade800,
                    foregroundColor: Colors.white,
                  ),
            child: Text(marcarComoFirmado ? 'Marcar todos' : 'Quitar marca a todos'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      _marcarTodosEnPantalla(marcarComoFirmado);
    }
  }

  void _setFirmado(String id, bool valor) {
    setState(() => _firmadoPorId[id] = valor);
  }

  Future<void> _guardar() async {
    final cambios = <String, bool>{};
    for (final e in _firmadoPorId.entries) {
      if (_originalPorId[e.key] != e.value) {
        cambios[e.key] = e.value;
      }
    }

    if (cambios.isEmpty) {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }

    setState(() => _guardando = true);
    try {
      await widget.repository.actualizarContratoFirmadoBulk(cambios);
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudieron guardar los contratos: $err'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _exportarPdf() async {
    if (_exportandoPdf) return;
    setState(() => _exportandoPdf = true);
    try {
      final ordenados = _ordenados;
      final pendientes = ordenados.where((a) => !(_firmadoPorId[a.id] ?? false)).toList();
      final firmados = ordenados.where((a) => _firmadoPorId[a.id] ?? false).toList();
      await PdfService.generarListadoContratosFirmadosPdf(
        eventoTitulo: widget.eventoTitulo,
        generadoEn: ArTime.nowUtc(),
        pendientes: pendientes,
        firmados: firmados,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar el PDF: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportandoPdf = false);
    }
  }

  Widget _resumenContadores(Color teal) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, size: 18, color: teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lista completa: $_totalEnLista ${_totalEnLista == 1 ? 'alumno activo' : 'alumnos activos'} (sin bajas)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _chipEstado(
                label: 'Firmados',
                valor: _cuentaFirmados,
                color: teal,
                icon: Icons.assignment_turned_in_outlined,
              ),
              _chipEstado(
                label: 'Pendientes',
                valor: _cuentaPendientes,
                color: Colors.deepOrange.shade700,
                icon: Icons.pending_actions_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipEstado({
    required String label,
    required int valor,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
          Text(
            '$valor',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }

  Widget _encabezadoSeccion(String titulo, int count, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$titulo · $count',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.4,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaAlumno(ContratoAlumno a, bool firmadoActual) {
    final teal = Colors.teal.shade700;
    final curso = (a.cursoDivision ?? '').trim();
    final bg = firmadoActual
        ? Colors.teal.withValues(alpha: 0.07)
        : Colors.deepOrange.withValues(alpha: 0.04);
    final border = firmadoActual
        ? BorderSide(color: teal.withValues(alpha: 0.22))
        : BorderSide(color: Colors.deepOrange.withValues(alpha: 0.18));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _guardando ? null : () => _setFirmado(a.id, !firmadoActual),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border.color),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  firmadoActual ? Icons.assignment_turned_in : Icons.edit_document,
                  size: 22,
                  color: firmadoActual ? teal : Colors.grey.shade600,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.nombreAlumno,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      if (curso.isNotEmpty)
                        Text(
                          curso,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          label: Text(
                            firmadoActual ? 'Contrato firmado' : 'Sin firmar',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: firmadoActual ? teal : Colors.deepOrange.shade800,
                            ),
                          ),
                          backgroundColor: firmadoActual
                              ? teal.withValues(alpha: 0.14)
                              : Colors.deepOrange.withValues(alpha: 0.12),
                          side: BorderSide.none,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: firmadoActual,
                  activeThumbColor: Colors.white,
                  activeTrackColor: teal,
                  onChanged: _guardando ? null : (v) => _setFirmado(a.id, v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _construirSlivers(Color teal) {
    final pendBase = _pendientes;
    final firmBase = _firmados;
    final pendientes = _filtrar(pendBase);
    final firmados = _filtrar(firmBase);
    final slivers = <Widget>[];
    final q = _q;

    if (q.isNotEmpty && pendientes.isEmpty && firmados.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Ningún alumno coincide con la búsqueda.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
      );
      return slivers;
    }

    if (pendientes.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _encabezadoSeccion(
            'Pendientes de firmar',
            pendientes.length,
            Colors.deepOrange.shade800,
          ),
        ),
      );
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _filaAlumno(pendientes[i], false),
            childCount: pendientes.length,
          ),
        ),
      );
    }

    if (firmados.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: pendientes.isNotEmpty ? 6 : 0),
            child: _encabezadoSeccion('Ya firmaron', firmados.length, teal),
          ),
        ),
      );
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _filaAlumno(firmados[i], true),
            childCount: firmados.length,
          ),
        ),
      );
    }

    if (slivers.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No hay alumnos en la lista.')),
          ),
        ),
      );
    }

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final teal = Colors.teal.shade700;
    final pendVis = _filtrar(_pendientes);
    final firmVis = _filtrar(_firmados);
    final visCount = pendVis.length + firmVis.length;
    final hayBusqueda = _q.isNotEmpty;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.assignment_turned_in_outlined, color: teal),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Contratos firmados',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _resumenContadores(teal),
            const SizedBox(height: 10),
            TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar por nombre o curso…',
                prefixIcon: const Icon(Icons.search, size: 22),
                suffixIcon: _busquedaCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.clear),
                        onPressed: _guardando
                            ? null
                            : () {
                                _busquedaCtrl.clear();
                                setState(() {});
                              },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (hayBusqueda) ...[
              const SizedBox(height: 6),
              Text(
                'Mostrando $visCount coincidencia(s) en esta vista ($_totalEnLista en la lista total).',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '«Marcar / desmarcar todos» afecta a la lista completa ($_totalEnLista). Tocá Guardar para persistir.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: _guardando ? null : () => _confirmarMarcarTodos(true),
                  child: const Text('Marcar todos'),
                ),
                TextButton(
                  onPressed: _guardando ? null : () => _confirmarMarcarTodos(false),
                  child: const Text('Desmarcar todos'),
                ),
                OutlinedButton.icon(
                  onPressed: (_guardando || _exportandoPdf) ? null : _exportarPdf,
                  icon: _exportandoPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(_exportandoPdf ? 'Generando PDF…' : 'Exportar PDF'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 10,
                radius: const Radius.circular(8),
                interactive: true,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: _construirSlivers(teal),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}
