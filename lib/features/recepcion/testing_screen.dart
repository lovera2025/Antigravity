import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/invitado.dart';
import 'providers/recepcion_provider.dart';
import 'repositories/invitados_repository.dart';
import 'recepcion_unified_screen.dart';

class RecepcionTestingScreen extends ConsumerStatefulWidget {
  const RecepcionTestingScreen({super.key});

  @override
  ConsumerState<RecepcionTestingScreen> createState() => _RecepcionTestingScreenState();
}

class _RecepcionTestingScreenState extends ConsumerState<RecepcionTestingScreen> {
  String? _selectedEventoId;
  final _nombreController = TextEditingController();
  final _mesaController = TextEditingController();
  final _dniController = TextEditingController();

  @override
  void dispose() {
    _nombreController.dispose();
    _mesaController.dispose();
    _dniController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.science_rounded, size: 20, color: gold),
            const SizedBox(width: 10),
            Text(
              'TESTING RECEPCIÓN',
              style: GoogleFonts.oswald(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInfoCard(isDark, gold),
              const SizedBox(height: 20),
              _buildEventSelector(isDark, gold),
              if (_selectedEventoId != null) ...[
                const SizedBox(height: 20),
                _buildStatsSection(_selectedEventoId!, isDark, gold),
                const SizedBox(height: 20),
                _buildQuickActions(_selectedEventoId!, isDark, gold),
                const SizedBox(height: 20),
                _buildAddInvitadoSection(_selectedEventoId!, isDark, gold),
                const SizedBox(height: 20),
                _buildInvitadosList(_selectedEventoId!, isDark, gold),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(bool isDark, Color gold) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: gold, size: 20),
              const SizedBox(width: 12),
              Text(
                'Panel de Pruebas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Usa esta pantalla para probar el sistema de check-in sin afectar datos reales. Puedes crear invitados de prueba, simular ingresos y verificar el funcionamiento del tótem.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventSelector(bool isDark, Color gold) {
    final eventosAsync = ref.watch(eventosActivosProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EVENTO DE PRUEBA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 12),
          eventosAsync.when(
            data: (eventos) {
              if (eventos.isEmpty) {
                return const Text('No hay eventos disponibles');
              }
              return DropdownButtonFormField<String>(
                initialValue: _selectedEventoId,
                hint: const Text('Seleccionar evento'),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.event_rounded, color: gold, size: 20),
                ),
                items: eventos.map((evento) {
                  final cliente = evento.cliente?.nombreCompleto ?? 'Sin cliente';
                  return DropdownMenuItem<String>(
                    value: evento.id,
                    child: Text('$cliente - ${evento.tipoParaMostrar}'),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedEventoId = value),
                isExpanded: true,
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(String eventoId, bool isDark, Color gold) {
    final statsAsync = ref.watch(statsEventoProvider(eventoId));

    return statsAsync.when(
      data: (stats) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ESTADÍSTICAS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildStatBadge('Total', stats['total'].toString(), gold),
                  const SizedBox(width: 8),
                  _buildStatBadge('Ingresados', stats['ingresados'].toString(), Colors.greenAccent),
                  const SizedBox(width: 8),
                  _buildStatBadge('Pendientes', stats['pendientes'].toString(), Colors.orangeAccent),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(String eventoId, bool isDark, Color gold) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACCIONES RÁPIDAS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _abrirRecepcionUnificada(),
              icon: const Icon(Icons.dashboard_rounded, size: 18),
              label: const Text('ABRIR RECEPCIÓN UNIFICADA'),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _copiarEventoId(eventoId),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('COPIAR ID'),
            style: OutlinedButton.styleFrom(
              foregroundColor: gold,
              side: BorderSide(color: gold),
              padding: const EdgeInsets.symmetric(vertical: 12),
              minimumSize: const Size(double.infinity, 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddInvitadoSection(String eventoId, bool isDark, Color gold) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AGREGAR INVITADO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nombreController,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dniController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'DNI',
              prefixIcon: Icon(Icons.badge),
              hintText: '12345678',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mesaController,
                  decoration: const InputDecoration(
                    labelText: 'Nº Mesa',
                    prefixIcon: Icon(Icons.table_restaurant),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _agregarInvitado(eventoId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('AGREGAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvitadosList(String eventoId, bool isDark, Color gold) {
    final invitadosAsync = ref.watch(invitadosStreamProvider(eventoId));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LISTA DE INVITADOS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () => ref.invalidate(invitadosStreamProvider(eventoId)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          invitadosAsync.when(
            data: (invitados) {
              if (invitados.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('No hay invitados registrados'),
                  ),
                );
              }
              return Column(
                children: invitados.map((invitado) {
                  return _buildInvitadoTestItem(invitado, isDark, gold);
                }).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Error: $e'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitadoTestItem(Invitado invitado, bool isDark, Color gold) {
    final isIngresado = invitado.estadoIngreso == EstadoIngreso.ingresado;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isIngresado
            ? Colors.greenAccent.withValues(alpha: 0.05)
            : (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isIngresado
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : (isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isIngresado ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isIngresado ? Colors.greenAccent : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitado.nombreCompleto,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: isIngresado ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  'Mesa ${invitado.numeroMesa ?? '-'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          if (!isIngresado)
            IconButton(
              icon: const Icon(Icons.login, size: 18, color: Colors.greenAccent),
              onPressed: () => _simularIngreso(invitado.id),
              tooltip: 'Simular ingreso',
            ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
            onPressed: () => _eliminarInvitado(invitado.id),
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }

  void _abrirRecepcionUnificada() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecepcionUnifiedScreen()),
    );
  }

  void _copiarEventoId(String eventoId) {
    Clipboard.setData(ClipboardData(text: eventoId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ID copiado al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }


  Future<void> _agregarInvitado(String eventoId) async {
    final nombre = _nombreController.text.trim();
    final dni = _dniController.text.trim();
    final mesa = _mesaController.text.trim();

    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre es obligatorio')),
      );
      return;
    }

    if (dni.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El DNI es obligatorio')),
      );
      return;
    }

    try {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.agregar(
        eventoId: eventoId,
        nombreCompleto: nombre,
        dni: dni,
        numeroMesa: mesa.isNotEmpty ? mesa : null,
      );
      _nombreController.clear();
      _dniController.clear();
      _mesaController.clear();
      ref.invalidate(invitadosStreamProvider(eventoId));
      ref.invalidate(statsEventoProvider(eventoId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitado agregado')),
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

  Future<void> _simularIngreso(String invitadoId) async {
    try {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.marcarIngreso(invitadoId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingreso simulado correctamente')),
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



  Future<void> _eliminarInvitado(String invitadoId) async {
    try {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.eliminar(invitadoId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitado eliminado')),
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
}
