import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../repositories/finanzas_repository.dart';
import '../providers/finanzas_provider.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class SmartPurgeDialog extends ConsumerStatefulWidget {
  const SmartPurgeDialog({super.key});

  @override
  ConsumerState<SmartPurgeDialog> createState() => _SmartPurgeDialogState();
}

class _SmartPurgeDialogState extends ConsumerState<SmartPurgeDialog> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _deleting = false;
  Map<String, List<Map<String, dynamic>>> _resultados = {};
  final Map<String, Set<String>> _selectedIds = {
    'clientes': {},
    'eventos': {},
    'transacciones': {},
    'contratos': {},
    'pagos': {},
    'egresos': {},
    'invitados': {},
    'accesos': {},
    'presupuestos': {},
    'solicitudes': {},
    'prestamos_alquiler': {},
    'pagos_alquiler': {},
  };

  final ScrollController _scrollController = ScrollController();
  double _montoTotalImpacto = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final query = _searchCtrl.text.trim();
    if (query.length < 3) return;

    setState(() {
      _searching = true;
      _resultados = {};
      for (var key in _selectedIds.keys) {
        _selectedIds[key]!.clear();
      }
    });

    try {
      final repo = ref.read(finanzasRepositoryProvider);
      final res = await repo.buscarVinculadosPorNombre(query);
      setState(() {
        _resultados = res;
        _montoTotalImpacto = 0;
        // Seleccionar todo por defecto para facilitar limpiezas de prueba
        for (var entry in res.entries) {
          _selectedIds[entry.key] = entry.value.map((e) => e['id'].toString()).toSet();
          
          // Calcular impacto financiero (Solo de items seleccionados, inicialmente todos)
          if (entry.key == 'transacciones' || entry.key == 'pagos' || entry.key == 'pagos_alquiler') {
            for (var item in entry.value) {
              _montoTotalImpacto += double.tryParse(item['monto'].toString()) ?? 0;
            }
          } else if (entry.key == 'egresos') {
            for (var item in entry.value) {
              _montoTotalImpacto -= double.tryParse(item['monto'].toString()) ?? 0;
            }
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _recalcularImpacto() {
    double total = 0;
    for (var key in _resultados.keys) {
      final items = _resultados[key] ?? [];
      final selected = _selectedIds[key] ?? {};
      
      if (key == 'transacciones' || key == 'pagos' || key == 'pagos_alquiler') {
        for (var item in items) {
          if (selected.contains(item['id'].toString())) {
            total += double.tryParse(item['monto'].toString()) ?? 0;
          }
        }
      } else if (key == 'egresos') {
        for (var item in items) {
          if (selected.contains(item['id'].toString())) {
            total -= double.tryParse(item['monto'].toString()) ?? 0;
          }
        }
      }
    }
    setState(() => _montoTotalImpacto = total);
  }

  Future<void> _ejecutarPurga() async {
    final total = _selectedIds.values.fold(0, (sum, set) => sum + set.length);
    if (total == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿CONFIRMAR PURGA DE SEGURIDAD?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se eliminarán $total registros de forma permanente tanto en la nube como localmente.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'IMPACTO EN FINANZAS: -\$${_montoTotalImpacto.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Esta acción es irreversible.', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR AHORA', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      final repo = ref.read(finanzasRepositoryProvider);
      final idsMap = _selectedIds.map((key, value) => MapEntry(key, value.toList()));
      final contratosARecalcular = await repo.eliminarRegistrosVinculados(idsMap);

      if (contratosARecalcular.isNotEmpty) {
        final contratosRepo = ref.read(contratosRepositoryProvider);
        for (final contratoId in contratosARecalcular) {
          await contratosRepo.recalcularProgresoContrato(contratoId);
        }
        ref.read(contratosMutationTickProvider.notifier).bump();
      }

      // Invalidar todos los estados para actualización instantánea
      ref.invalidate(finanzasProvider);
      ref.invalidate(dashboardStatsProvider);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purga completada con éxito. El sistema ha sido saneado.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error durante la purga: $e')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 600,
        height: 700,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: gold.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: -10),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security_rounded, color: gold, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PURGA INTELIGENTE',
                        style: GoogleFonts.oswald(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: gold,
                        ),
                      ),
                      Text(
                        'LIMPIEZA DE DATOS DE PRUEBA Y REGISTROS VINCULADOS',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white38 : Colors.black38,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: gold.withValues(alpha: 0.2)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _buscar(),
                  autofocus: true,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'INGRESAR NOMBRE PARA ANALIZAR...',
                    hintStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    prefixIcon: const Icon(Icons.person_search_rounded, color: gold),
                    suffixIcon: _searching 
                        ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2, color: gold)))
                        : IconButton(icon: const Icon(Icons.search_rounded, color: gold), onPressed: _buscar),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Results Area
            Expanded(
              child: _resultados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, color: gold.withValues(alpha: 0.1), size: 64),
                          const SizedBox(height: 16),
                          Text(
                            _searching ? 'BUSCANDO VÍNCULOS...' : 'NO HAY REGISTROS SELECCIONADOS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white12 : Colors.black12,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Theme(
                      data: Theme.of(context).copyWith(
                        scrollbarTheme: ScrollbarThemeData(
                          thumbColor: WidgetStateProperty.all(gold.withValues(alpha: 0.3)),
                          radius: const Radius.circular(10),
                        ),
                      ),
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              _buildSection('CLIENTES', 'clientes', Icons.person_outline),
                              _buildSection('EVENTOS', 'eventos', Icons.event_note_outlined),
                              _buildSection('TRANSACCIONES', 'transacciones', Icons.monetization_on_outlined),
                              _buildSection('EGRESOS', 'egresos', Icons.receipt_long_outlined),
                              _buildSection('CONTRATOS (ALUMNOS)', 'contratos', Icons.school_outlined),
                              _buildSection('PAGOS DE CUOTAS', 'pagos', Icons.payments_outlined),
                              _buildSection('INVITADOS', 'invitados', Icons.people_outline_rounded),
                              _buildSection('REGISTROS DE ACCESO', 'accesos', Icons.fact_check_outlined),
                              _buildSection('PRESUPUESTOS', 'presupuestos', Icons.description_outlined),
                              _buildSection('PRÉSTAMOS ALQUILER ÍTEMS', 'prestamos_alquiler', Icons.inventory_2_outlined),
                              _buildSection('PAGOS ALQUILER ÍTEMS', 'pagos_alquiler', Icons.paid_outlined),
                              _buildSection('SOLICITUDES DE COTIZACIÓN', 'solicitudes', Icons.send_and_archive_outlined),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),

            // Footer / Actions
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  if (_deleting)
                    const LinearProgressIndicator(color: Colors.red, backgroundColor: Colors.transparent),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _deleting ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                          ),
                          child: const Text('CANCELAR', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: (_resultados.isEmpty || _deleting) ? null : _ejecutarPurga,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: Text(
                            _deleting ? 'PROCESANDO...' : 'EJECUTAR ELIMINACIÓN SELECTIVA',
                            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String key, IconData icon) {
    final items = _resultados[key] ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text(
                '$title (${items.length})',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.blueGrey),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedIds[key]!.length == items.length) {
                      _selectedIds[key]!.clear();
                    } else {
                      _selectedIds[key] = items.map((e) => e['id'].toString()).toSet();
                    }
                    _recalcularImpacto();
                  });
                },
                child: Text(
                  _selectedIds[key]!.length == items.length ? 'DESELECCIONAR' : 'TODO',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        if (key == 'transacciones' || key == 'pagos' || key == 'pagos_alquiler' || key == 'egresos')
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'Impacto financiero estimado: ${key == 'egresos' ? '-' : '+'}\$${items.where((i) => _selectedIds[key]!.contains(i['id'].toString())).fold(0.0, (sum, i) => sum + (double.tryParse(i['monto'].toString()) ?? 0)).toStringAsFixed(2)}',
              style: TextStyle(fontSize: 9, color: Colors.redAccent.withValues(alpha: 0.7), fontWeight: FontWeight.bold),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: items.map((item) {
              final id = item['id'].toString();
              final isSelected = _selectedIds[key]!.contains(id);
              
              String label = '';
              String subLabel = '';

              final textColor = isDark ? Colors.white : Colors.black87;

              switch (key) {
                case 'clientes':
                  label = item['nombre_completo'] ?? 'Sin Nombre';
                  subLabel = 'CLIENTE PRINCIPAL - ID: ${id.substring(0, 8)}...';
                  break;
                case 'eventos':
                  label = '${item['tipo'] ?? 'Evento'} - ${item['fecha_evento'] ?? ''}';
                  subLabel = 'VINCULADO AL CLIENTE ENCONTRADO';
                  break;
                case 'transacciones':
                case 'pagos':
                  label = '${item['concepto'] ?? 'Pago'} - \$${item['monto']}';
                  subLabel = 'RELACIONADO CON EL EVENTO/CONTRATO SELECCIONADO';
                  break;
                case 'pagos_alquiler':
                  label = '${item['concepto'] ?? 'Pago alquiler'} - \$${item['monto']}';
                  subLabel = 'PAGO VINCULADO A PRÉSTAMO DE ÍTEMS';
                  break;
                case 'prestamos_alquiler':
                  label = 'PRÉSTAMO ${item['id'].toString().substring(0, 8)}...';
                  subLabel =
                      'DEL ${item['fecha_inicio'] ?? ''} AL ${item['fecha_fin'] ?? ''} — TOTAL \$${item['total'] ?? 0}';
                  break;
                case 'egresos':
                  label = '${item['concepto'] ?? 'Egreso'} - \$${item['monto']}';
                  subLabel = 'PROVEEDOR: ${item['proveedor'] ?? 'S/D'}';
                  break;
                case 'contratos':
                  label = item['nombre_alumno'] ?? 'Alumno';
                  subLabel = 'INSTITUCIÓN: ${item['institucion'] ?? 'General'}';
                  break;
                case 'invitados':
                  label = item['nombre_completo'] ?? 'Invitado';
                  subLabel = 'DNI: ${item['dni'] ?? '-'} (VINCULADO AL EVENTO)';
                  break;
                case 'accesos':
                  label = 'Check-in: ${item['dni_ingresado'] ?? '-'}';
                  subLabel = 'HORA: ${item['timestamp'] ?? ''}';
                  break;
                case 'presupuestos':
                  label = 'PRESUPUESTO: ${item['tipo_evento'] ?? 'General'}';
                  subLabel = 'EXPIRA: ${item['fecha_vencimiento'] ?? '-'}';
                  break;
                case 'solicitudes':
                  label = 'SOLICITUD: ${item['cliente_nombre'] ?? 'Interesado'}';
                  subLabel = 'ESTADO: ${item['estado']?.toString().toUpperCase() ?? 'PENDIENTE'}';
                  break;
              }

              return CheckboxListTile(
                value: isSelected,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedIds[key]!.add(id);
                    } else {
                      _selectedIds[key]!.remove(id);
                    }
                    _recalcularImpacto();
                  });
                },
                title: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
                subtitle: Text(subLabel, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                activeColor: Colors.redAccent,
                checkColor: Colors.white,
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
