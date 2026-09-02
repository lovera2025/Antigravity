import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../../models/cliente.dart';
import '../common/widgets/animated_background.dart';
import '../common/widgets/operational_sync_coordinator.dart';
import '../common/widgets/admin_gate.dart';
import 'widgets/cliente_form_dialog.dart';
import 'widgets/cliente_detalle_sheet.dart';
import 'repositories/clientes_repository.dart';

class ClientesScreen extends ConsumerStatefulWidget {
  const ClientesScreen({super.key});

  @override
  ConsumerState<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends ConsumerState<ClientesScreen> {
  bool _isLoading = true;
  bool _showArchived = false;
  int _archivedCount = 0;
  List<Cliente> _clientes = [];
  List<Cliente> _filteredClientes = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchClientes();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchClientes({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final repo = ref.read(clientesRepositoryProvider);
      final data = await repo.getAll(archived: _showArchived);
      final count = await repo.getArchivedCount();

      setState(() {
        _clientes = data;
        _filteredClientes = data;
        _archivedCount = count;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted && showLoading) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleArchive(Cliente cliente) async {
    final hasAccess = await AdminGate.check(context, ref);
    if (!hasAccess) return;

    try {
      final repo = ref.read(clientesRepositoryProvider);
      await repo.setArchived(cliente.id, !cliente.isArchived);
      _fetchClientes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(cliente.isArchived ? 'Cliente restaurado' : 'Cliente archivado')),
        );
      }
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _eliminarDefinitivamente(Cliente cliente) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar DEFINITIVAMENTE?'),
        content: Text('ESTA ACCIÓN ES IRREVERSIBLE. Se borrarán todos los datos, eventos y registros de ${cliente.nombreCompleto}.\n\n¿Proceder con el borrado nuclear?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR TODO'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final repo = ref.read(clientesRepositoryProvider);
        await repo.eliminarDefinitivamente(cliente.id);
        _fetchClientes();
      } catch (e) {
         if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredClientes = _clientes.where((c) {
        return c.nombreCompleto.toLowerCase().contains(query) ||
            (c.telefono?.contains(query) ?? false) ||
            (c.email?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // El canal de Realtime sobre `clientes` se retiró el 2026-09-02: como el de
    // `eventos`, escuchaba una tabla que nunca estuvo publicada. Ahora
    // `clientes` baja en el pull incremental y esto refresca la lista.
    ref.listen<int>(operationalSyncRevisionProvider, (prev, next) {
      if (prev != next && mounted && !_isLoading) {
        _fetchClientes(showLoading: false);
      }
    });

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_showArchived ? 'CLIENTES ARCHIVADOS' : 'AGENDA DE CLIENTES'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(_showArchived ? Icons.person_search_rounded : Icons.archive_outlined, color: primaryGold),
                onPressed: () {
                  setState(() => _showArchived = !_showArchived);
                  _fetchClientes();
                },
                tooltip: _showArchived ? 'Ver Activos' : 'Ver Archivados',
              ),
              if (!_showArchived && _archivedCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_archivedCount',
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchClientes,
          ),
        ],
      ),
      floatingActionButton: _showArchived ? null : _buildPremiumFAB(),
      body: AnimatedBackground(
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildSearchBar(isDark, primaryGold),
                  Expanded(
                    child: _isLoading
                        ? Center(child: CircularProgressIndicator(color: primaryGold))
                        : _buildMainContent(isDark, primaryGold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, Color gold) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o contacto...',
                hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5), fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: gold, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(bool isDark, Color gold) {
    if (_filteredClientes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off_rounded, size: 60, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              _showArchived ? 'No hay clientes archivados.' : 'No se encontraron clientes.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: _filteredClientes.length,
      itemBuilder: (context, index) {
        final cliente = _filteredClientes[index];
        return _EliteClienteCard(
          cliente: cliente,
          isDark: isDark,
          gold: gold,
          isArchivedMode: _showArchived,
          onRefresh: _fetchClientes,
          onToggleArchive: () => _toggleArchive(cliente),
          onDelete: () => _eliminarDefinitivamente(cliente),
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => ClienteDetalleSheet(cliente: cliente),
            ).then((_) => _fetchClientes(showLoading: false));
          },
        );
      },
    );
  }

  Widget _buildPremiumFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () async {
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => const ClienteFormDialog(),
          );
          if (result == true) _fetchClientes();
        },
        backgroundColor: const Color(0xFFD4AF37),
        elevation: 0,
        label: const Text('NUEVO CLIENTE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
        icon: const Icon(Icons.add_rounded, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _EliteClienteCard extends ConsumerStatefulWidget {
  final Cliente cliente;
  final bool isDark;
  final Color gold;
  final bool isArchivedMode;
  final VoidCallback onRefresh;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _EliteClienteCard({
    required this.cliente,
    required this.isDark,
    required this.gold,
    required this.isArchivedMode,
    required this.onRefresh,
    required this.onToggleArchive,
    required this.onDelete,
    required this.onTap,
  });

  @override
  ConsumerState<_EliteClienteCard> createState() => _EliteClienteCardState();
}

class _EliteClienteCardState extends ConsumerState<_EliteClienteCard> {
  int _totalEventos = 0;
  bool _tieneDeuda = false;
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final repo = ref.read(clientesRepositoryProvider);
      final stats = await repo.getStats(widget.cliente.id);
      if (mounted) {
        setState(() {
          _totalEventos = stats['total_eventos'];
          _tieneDeuda = stats['tiene_deuda'];
          _loadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.cliente.createdAt != null && 
                  DateTime.now().difference(widget.cliente.createdAt!).inDays < 30;
    final isVip = _totalEventos >= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.2 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.gold.withValues(alpha: 0.15),
                width: 0.5,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: widget.isDark ? 0.05 : 0.1),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(24),
              child: Row(
                children: [
                // Avatar Minimalista
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.gold.withValues(alpha: 0.2), widget.gold.withValues(alpha: 0.05)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      widget.cliente.nombreCompleto.isNotEmpty ? widget.cliente.nombreCompleto[0].toUpperCase() : '?',
                      style: TextStyle(color: widget.gold, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Info Principal
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.cliente.nombreCompleto.isNotEmpty 
                            ? widget.cliente.nombreCompleto.toUpperCase() 
                            : '[DATO AUSENTE - REVISIÓN]',
                        style: TextStyle(
                          fontWeight: FontWeight.w900, 
                          fontSize: 14, 
                          letterSpacing: 0.5,
                          color: widget.cliente.nombreCompleto.isEmpty ? Colors.redAccent : (widget.isDark ? Colors.white : Colors.black),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.cliente.telefono ?? 'Sin contacto',
                        style: TextStyle(color: Colors.grey.withValues(alpha: 0.6), fontSize: 12),
                      ),
                      if (!_loadingStats) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (isNew) _buildSmallTag('NUEVO', Colors.blue),
                            if (isVip) _buildSmallTag('VIP', widget.gold),
                            if (_tieneDeuda) _buildSmallTag('SALDO', Colors.redAccent),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Acciones Premium
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 20),
                      onPressed: () async {
                        final result = await showDialog<bool>(
                          context: context,
                          builder: (context) => ClienteFormDialog(cliente: widget.cliente),
                        );
                        if (result == true) widget.onRefresh();
                      },
                      color: Colors.blueGrey.withValues(alpha: 0.6),
                    ),
                    IconButton(
                      icon: Icon(
                        widget.isArchivedMode ? Icons.restore_from_trash_rounded : Icons.archive_outlined,
                        size: 20,
                        color: widget.isArchivedMode ? Colors.green : Colors.grey.withValues(alpha: 0.5),
                      ),
                      onPressed: widget.onToggleArchive,
                    ),
                    if (widget.isArchivedMode)
                      IconButton(
                        icon: const Icon(Icons.delete_forever_rounded, size: 20, color: Colors.redAccent),
                        onPressed: widget.onDelete,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildSmallTag(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: widget.isDark ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }
}
