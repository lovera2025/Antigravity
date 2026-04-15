import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/cliente.dart';
import '../../../models/evento.dart';
import '../repositories/clientes_repository.dart';
import '../../eventos/detalle_evento_masivo_screen.dart';
import '../../eventos/detalle_evento_particular_screen.dart';
import '../../../core/database/local_database.dart';
import 'dart:ui';

class ClienteDetalleSheet extends ConsumerStatefulWidget {
  final Cliente cliente;

  const ClienteDetalleSheet({super.key, required this.cliente});

  @override
  ConsumerState<ClienteDetalleSheet> createState() => _ClienteDetalleSheetState();
}

class _ClienteDetalleSheetState extends ConsumerState<ClienteDetalleSheet> {
  bool _isLoading = true;
  int _totalEventos = 0;
  double _inversionTotal = 0.0;
  bool _tieneDeuda = false;
  List<Map<String, dynamic>> _eventos = [];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    try {
      final repo = ref.read(clientesRepositoryProvider);
      final stats = await repo.getStats(widget.cliente.id);
      final inversion = await repo.getInversionTotal(widget.cliente.id);
      
      // Cargar lista de eventos
      final db = await LocalDatabase.instance;
      final eventosRaw = await db.query(
        'eventos',
        where: 'cliente_id = ?',
        whereArgs: [widget.cliente.id],
        orderBy: 'fecha_evento DESC'
      );

      if (mounted) {
        setState(() {
          _totalEventos = stats['total_eventos'];
          _tieneDeuda = stats['tiene_deuda'];
          _inversionTotal = inversion;
          _eventos = eventosRaw;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Barra superior de cierre
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          Expanded(
            child: _isLoading 
              ? Center(child: CircularProgressIndicator(color: primaryGold))
              : CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // Header con info del cliente
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            Text(
                              widget.cliente.nombreCompleto.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.phone_rounded, size: 14, color: primaryGold),
                                const SizedBox(width: 8),
                                Text(
                                  widget.cliente.telefono ?? 'Sin número registrados',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Dashboard de Stats
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            _buildStatCard('EVENTOS', _totalEventos.toString(), isDark, primaryGold),
                            const SizedBox(width: 12),
                            _buildStatCard('INVERSIÓN', '\$${_inversionTotal.toStringAsFixed(0)}', isDark, primaryGold),
                            const SizedBox(width: 12),
                            _buildStatCard('ESTADO', _tieneDeuda ? 'DEUDOR' : 'AL DÍA', isDark, _tieneDeuda ? Colors.redAccent : Colors.green),
                          ],
                        ),
                      ),
                    ),
                    
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(32, 40, 32, 16),
                        child: Text(
                          'HISTORIAL DE EVENTOS',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, color: Colors.grey),
                        ),
                      ),
                    ),
                    
                    // Lista de Eventos
                    if (_eventos.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text('No hay eventos registrados para este cliente.', style: TextStyle(color: Colors.grey.withValues(alpha: 0.5))),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final ev = _eventos[index];
                              return _buildEventoTile(ev, isDark, primaryGold);
                            },
                            childCount: _eventos.length,
                          ),
                        ),
                      ),
                    
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, bool isDark, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventoTile(Map<String, dynamic> ev, bool isDark, Color gold) {
    final tipo = ev['tipo'] ?? 'EVENTO';
    final fecha = ev['fecha_evento'] ?? 'S/F';
    final modalidad = ev['modalidad'] ?? 'particular';
    final estado = ev['estado'] ?? 'Planificación';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () {
          // Convertir el mapa a Objeto Evento para la navegación
          final eventoObj = Evento.fromJson({
            ...ev,
            'clientes': widget.cliente.toJson(), // Pasar el cliente actual para evitar recargas innecesarias
          });

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => modalidad == 'masivo' 
                ? DetalleEventoMasivoScreen(evento: eventoObj)
                : DetalleEventoParticularScreen(evento: eventoObj),
            ),
          );
        },
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            modalidad == 'masivo' ? Icons.groups_rounded : Icons.person_rounded,
            color: gold.withValues(alpha: 0.6),
            size: 20,
          ),
        ),
        title: Text(
          tipo.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
        subtitle: Text(
          '$fecha — $estado',
          style: TextStyle(color: Colors.grey[600], fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
      ),
    );
  }
}
