import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/prestamo_alquiler.dart';
import '../clientes/repositories/clientes_repository.dart';
import 'prestamo_alquiler_detalle_screen.dart';
import 'prestamo_alquiler_form_screen.dart';
import 'repositories/prestamos_alquiler_repository.dart';

/// Listado de préstamos operativos (alquiler de sillas, mesas, etc.).
class PrestamosAlquilerListScreen extends ConsumerStatefulWidget {
  const PrestamosAlquilerListScreen({super.key});

  @override
  ConsumerState<PrestamosAlquilerListScreen> createState() => _PrestamosAlquilerListScreenState();
}

class _PrestamosAlquilerListScreenState extends ConsumerState<PrestamosAlquilerListScreen> {
  List<PrestamoAlquiler> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final repo = ref.read(prestamosAlquilerRepositoryProvider);
    final list = await repo.listarVisibles();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);
    final fmt = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ALQUILER DE ÍTEMS',
          style: GoogleFonts.oswald(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const PrestamoAlquilerFormScreen()),
          );
          if (ok == true) _cargar();
        },
        backgroundColor: gold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('NUEVO', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: gold))
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: gold.withValues(alpha: 0.25)),
                      const SizedBox(height: 16),
                      Text(
                        'NO HAY PRÉSTAMOS ACTIVOS',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: isDark ? Colors.white24 : Colors.black38,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Los vencidos se archivan solos; los pagos siguen en Mi empresa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black45),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: gold,
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final p = _items[i];
                      return FutureBuilder(
                        future: ref.read(clientesRepositoryProvider).getById(p.clienteId),
                        builder: (context, snap) {
                          final nombre = snap.data?.nombreCompleto ?? 'Cliente';
                          return Material(
                            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PrestamoAlquilerDetalleScreen(prestamoId: p.id),
                                  ),
                                );
                                _cargar();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: gold.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.handshake_outlined, color: gold),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nombre.toUpperCase(),
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${fmt.format(p.fechaInicio)} → ${fmt.format(p.fechaFin)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white54 : Colors.black54,
                                            ),
                                          ),
                                          if (p.aplicaIva)
                                            Text(
                                              'IVA ${p.alicuotaIva.toStringAsFixed(0)}%',
                                              style: TextStyle(fontSize: 10, color: gold.withValues(alpha: 0.8)),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          p.total.toStringAsFixed(2),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: gold,
                                          ),
                                        ),
                                        const Text('TOTAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
