import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/widgets/admin_gate.dart';


import '../../models/evento.dart';
import '../../models/transaccion.dart';
import 'widgets/registrar_pago_dialog.dart';
import 'selector_servicios_screen.dart';
import '../common/services/pdf_service.dart';
import '../common/utils/currency_extensions.dart';
import 'repositories/eventos_repository.dart';
import 'repositories/transacciones_repository.dart';

class DetalleEventoParticularScreen extends ConsumerStatefulWidget {
  final Evento evento;

  const DetalleEventoParticularScreen({super.key, required this.evento});

  @override
  ConsumerState<DetalleEventoParticularScreen> createState() => _DetalleEventoParticularScreenState();
}

class _DetalleEventoParticularScreenState extends ConsumerState<DetalleEventoParticularScreen> {
  bool _isLoading = true;
  late DateTime _fechaEventoActual;
  List<EventosServicios> _servicios = [];
  List<Transaccion> _transacciones = [];
  RealtimeChannel? _eventoChannel;
  RealtimeChannel? _transaccionesChannel;

  @override
  void initState() {
    super.initState();
    _fechaEventoActual = widget.evento.fechaEvento;
    _fetchDatos();
    _setupRealtime();
  }

  void _setupRealtime() {
    final eventoRepo = ref.read(eventosRepositoryProvider);
    final transRepo = ref.read(transaccionesRepositoryProvider);

    _eventoChannel = eventoRepo.subscribeToEvent(widget.evento.id, () {
      if (mounted) _fetchDatos(cargaSilenciosa: true);
    });

    _transaccionesChannel = transRepo.subscribeToChanges(widget.evento.id, () {
      if (mounted) _fetchDatos(cargaSilenciosa: true);
    });
  }

  Future<void> _fetchDatos({bool cargaSilenciosa = false}) async {
    if (!cargaSilenciosa) setState(() => _isLoading = true);
    try {
      final eventosRepo = ref.read(eventosRepositoryProvider);
      final transaccionesRepo = ref.read(transaccionesRepositoryProvider);

      // 1. Fetch Presupuesto (Servicios)
      final presData = await eventosRepo.getPresupuesto(widget.evento.id);

      // 2. Fetch Ledger (Transacciones)
      final transData = await transaccionesRepo.getByEvento(widget.evento.id);

      if (mounted) {
        setState(() {
          _servicios = presData;
          _transacciones = transData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
      debugPrint('Error al cargar datos en DetalleEvento: $e');
      if (mounted && !cargaSilenciosa) setState(() => _isLoading = false);
    }
  }

  Future<void> _imprimirComprobante() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12),
          Text('Generando PDF...'),
        ]),
        duration: Duration(seconds: 10),
      ),
    );
    try {
      final totalPresupuesto = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));
      final totalPagado = _transacciones.fold<double>(0, (sum, item) => sum + item.monto);
      final saldoRestante = totalPresupuesto - totalPagado;

      await PdfService.generarReciboCompacto(
        evento: widget.evento,
        montoEntregado: totalPagado,
        saldoActual: saldoRestante,
        transacciones: _transacciones,
        servicios: _servicios,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('✓ PDF abierto correctamente'), duration: Duration(seconds: 3)),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Error al generar PDF: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _compartirComprobante() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12),
          Text('Preparando comprobante...'),
        ]),
        duration: Duration(seconds: 10),
      ),
    );
    try {
      final totalPresupuesto = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));
      final totalPagado = _transacciones.fold<double>(0, (sum, item) => sum + item.monto);
      final saldoRestante = totalPresupuesto - totalPagado;

      await PdfService.compartirRecibo(
        evento: widget.evento,
        montoEntregado: totalPagado,
        saldoActual: saldoRestante,
        transacciones: _transacciones,
        servicios: _servicios,
      );
      messenger.hideCurrentSnackBar();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Error al compartir PDF: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _eliminarEvento() async {
    final hasAccess = await AdminGate.check(context, ref);
    if (!hasAccess) return;

    // Calcular saldo al momento de eliminar
    final totalPresupuestoEl = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));
    final totalPagadoEl = _transacciones.fold<double>(0, (sum, item) => sum + item.monto);
    final double saldoAlEliminar = totalPresupuestoEl - totalPagadoEl;
    final bool tieneDeudaAlEliminar = saldoAlEliminar > 0.01;

    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: tieneDeudaAlEliminar ? Colors.deepOrangeAccent : Colors.redAccent,
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              tieneDeudaAlEliminar ? Icons.warning_amber_rounded : Icons.delete_forever_rounded,
              color: tieneDeudaAlEliminar ? Colors.deepOrangeAccent : Colors.redAccent,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              tieneDeudaAlEliminar ? '¡SALDO PENDIENTE!' : 'ATENCIÓN TITÁN',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
          ],
        ),
        content: Text(
          tieneDeudaAlEliminar
              ? 'Este evento tiene ${saldoAlEliminar.toCurrency()} de saldo sin cobrar. Al eliminarlo, esta deuda desaparecerá del Dashboard. ¿Estás seguro?'
              : 'El evento se ocultará de la lista de eventos activos. Los ingresos y egresos de esta fiesta se conservan en Mi Empresa para tu historial financiero.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tieneDeudaAlEliminar ? Colors.deepOrangeAccent : Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tieneDeudaAlEliminar ? 'ELIMINAR CON DEUDA' : 'ELIMINAR AHORA',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );


    if (confirmar == true) {
      if (!mounted) return;
      
      setState(() => _isLoading = true);
      final repo = ref.read(eventosRepositoryProvider);
      
      try {
        await repo.actualizarEstado(widget.evento.id, EstadoEvento.cancelado);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Evento dado de baja. Los movimientos siguen en Mi Empresa.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          Navigator.pop(context, true); // Regresar al listado indicando éxito
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e')),
          );
        }
      }
    }
  }

  Future<void> _finalizarEvento() async {
    final hasAccess = await AdminGate.check(context, ref);
    if (!hasAccess) return;

    // Calcular saldo deudor total (Guardia de Deuda) usando los datos cargados en pantalla
    final totalPresupuesto = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));
    final totalPagado = _transacciones.fold<double>(0, (sum, item) => sum + item.monto);
    final double saldoPendiente = totalPresupuesto - totalPagado;
    final bool tieneDeuda = saldoPendiente > 0.01;

    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: tieneDeuda ? Colors.orangeAccent : Colors.greenAccent, 
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              tieneDeuda ? Icons.warning_amber_rounded : Icons.verified_rounded, 
              color: tieneDeuda ? Colors.orangeAccent : Colors.greenAccent, 
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              tieneDeuda ? 'ATENCIÓN: DEUDA ACTIVA' : 'FINALIZAR EVENTO', 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
          ],
        ),
        content: Text(
          tieneDeuda 
            ? 'Este evento aún tiene ${saldoPendiente.toCurrency()} de saldo pendiente. Al finalizarlo, este monto DEJARÁ de figurar en tu capital activo del Dashboard. ¿Deseas archivarlo de todos modos?'
            : '¡Ciclo completado! No hay saldos pendientes. El evento se archivará y dejará de contar como capital cautivo en el Dashboard.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tieneDeuda ? Colors.orangeAccent : Colors.greenAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tieneDeuda ? 'FINALIZAR CON DEUDA' : 'FINALIZAR AHORA', 
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      final repo = ref.read(eventosRepositoryProvider);
      try {
        await repo.actualizarEstado(widget.evento.id, EstadoEvento.finalizado);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Evento finalizado con éxito!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); 
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al finalizar: $e')),
          );
        }
      }
    }
  }

  Future<void> _editarServicios() async {
    final Map<String, double> serviciosIniciales = {
      for (var s in _servicios) s.servicioId: s.precioFinalAcordado
    };
    final Map<String, double> cantidadesIniciales = {
      for (var s in _servicios) s.servicioId: s.cantidad
    };
    final Map<String, String?> gruposIniciales = {
      for (var s in _servicios) s.servicioId: s.grupo
    };
    final Map<String, String?> descripcionesIniciales = {
      for (var s in _servicios) s.servicioId: s.detalleServicio
    };

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectorServiciosScreen(
          eventoId: widget.evento.id,
          clienteId: widget.evento.clienteId,
          serviciosIniciales: serviciosIniciales,
          cantidadesIniciales: cantidadesIniciales,
          gruposIniciales: gruposIniciales,
          descripcionesIniciales: descripcionesIniciales,
          modalidad: widget.evento.modalidad,
          observaciones: widget.evento.observaciones,
          tipoEvento: widget.evento.tipo,
        ),
      ),
    );

    if (result == true) {
      _fetchDatos();
    }
  }

  Future<void> _editarInformacionEvento() async {
    final tipoController = TextEditingController(text: widget.evento.tipo);
    final obsController = TextEditingController(text: widget.evento.observaciones);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFFF5F5F5), // Gris Perla suave
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.6, // Más ancho
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   Container(
                     padding: const EdgeInsets.all(10),
                     decoration: BoxDecoration(color: const Color(0xFFD4AF37).withValues(alpha: 0.1), shape: BoxShape.circle),
                     child: const Icon(Icons.edit_note_rounded, color: Color(0xFFD4AF37), size: 28),
                   ),
                   const SizedBox(width: 16),
                   const Text(
                    'DETALLES DEL EVENTO', 
                    style: TextStyle(
                      color: Color(0xFF2C3E50), 
                      fontWeight: FontWeight.w900, 
                      fontSize: 18, 
                      letterSpacing: 1.5
                    )
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              const Text('TIPO DE CELEBRACIÓN', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 8),
              TextField(
                controller: tipoController,
                style: const TextStyle(color: Color(0xFF2C3E50), fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Ej: 15 Años, Boda, Recepción...',
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD4AF37))),
                ),
              ),
              
              const SizedBox(height: 24),
              
              const Text('OBSERVACIONES / GUION DEL EVENTO', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 8),
              TextField(
                controller: obsController,
                maxLines: 12, // Mucho más espacio para esplayarse
                style: const TextStyle(color: Color(0xFF2C3E50), height: 1.5),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Describa aquí el cronograma, nombres de los agasajados, temática...',
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD4AF37))),
                ),
              ),
              
              const SizedBox(height: 32),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context), 
                    child: const Text('DESCARTAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37), 
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    onPressed: () async {
                      final repo = ref.read(eventosRepositoryProvider);
                      await repo.actualizarEventoInfo(
                        widget.evento.id,
                        tipo: tipoController.text,
                        observaciones: obsController.text,
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    },
                    child: const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      // Forzamos recarga de la pantalla (el objeto widget.evento es inmutable, pero el repo/realtime actualizará la vista)
      _fetchDatos();
    }
  }


  Future<void> _ajustarCuotas() async {
    final TextEditingController controller = TextEditingController(text: widget.evento.cantidadCuotas.toString());
    
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajustar Plan de Pagos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Modifica la cantidad de cuotas pactadas para este evento.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cantidad de Cuotas',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () async {
              final nuevasCuotas = int.tryParse(controller.text);
              if (nuevasCuotas == null || nuevasCuotas < 1) return;
              
              final repo = ref.read(eventosRepositoryProvider);
              await repo.actualizarCuotas(widget.evento.id, nuevasCuotas);
              
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );

    if (mounted && result == true) {
      // Idealmente recargaríamos el objeto evento, pero por simplicidad refrescamos la pantalla
      _fetchDatos();
    }
  }

  Future<void> _editarFecha() async {
    final hasAccess = await AdminGate.check(context, ref);
    if (!hasAccess) return;

    if (!mounted) return;
    final nuevaFecha = await showDatePicker(
      context: context,
      initialDate: _fechaEventoActual,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD4AF37),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (nuevaFecha != null && nuevaFecha.isAtSameMomentAs(_fechaEventoActual) == false) {
      setState(() => _isLoading = true);
      try {
        final repo = ref.read(eventosRepositoryProvider);
        await repo.actualizarFecha(widget.evento.id, nuevaFecha);
        if (mounted) {
          setState(() {
            _fechaEventoActual = nuevaFecha;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fecha actualizada correctamente'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al actualizar fecha: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _eventoChannel?.unsubscribe();
    _transaccionesChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);
    final expenseRed = const Color(0xFFE74C3C);
    final incomeGreen = const Color(0xFF00B894);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text((widget.evento.cliente?.nombreCompleto ?? 'DETALLE PARTICULAR').toUpperCase(), style: const TextStyle(fontSize: 14, letterSpacing: 1)),
        backgroundColor: Colors.transparent,
        actions: [
          if (!_isLoading) ...[
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFD4AF37)),
              onPressed: _mostrarHistorialPagos,
              tooltip: 'Ver Estado de Cuenta',
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _imprimirComprobante,
              tooltip: 'Imprimir',
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: _compartirComprobante,
              tooltip: 'Compartir',
            ),
            IconButton(
              icon: const Icon(Icons.edit_calendar_outlined, color: Colors.blueAccent),
              onPressed: _editarFecha,
              tooltip: 'Editar Fecha',
            ),
            IconButton(
              icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent),
              onPressed: _finalizarEvento,
              tooltip: 'Finalizar Evento',
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
              onPressed: _eliminarEvento,
              tooltip: 'Eliminar',
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      floatingActionButton: _buildPremiumFAB(primaryGold, expenseRed),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryGold.withValues(alpha: isDark ? 0.03 : 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (!_isLoading) _buildEliteStatusBanner(incomeGreen, expenseRed),
                Expanded(
                  child: _buildPanelContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumFAB(Color gold, Color red) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gold.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () async {
            final presupuesto = _servicios.fold<double>(0, (s, i) => s + (i.precioFinalAcordado * i.cantidad));
            if (!mounted) return;
            final result = await showDialog<bool>(
              context: context,
              builder: (context) => RegistrarPagoDialog(
                evento: widget.evento,
                transaccionesExistentes: _transacciones,
                presupuestoTotal: presupuesto,
                servicios: _servicios,
              ),
            );
            if (result == true) _fetchDatos();
        },
        backgroundColor: gold,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildEliteStatusBanner(Color green, Color red) {
    final totalPresupuesto = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));
    final totalPagado = _transacciones.fold<double>(0, (sum, item) => sum + item.monto);
    final saldoDeudor = totalPresupuesto - totalPagado;
    final isDesbloqueado = saldoDeudor <= 0;
    final esRecepcion = widget.evento.tipo.toLowerCase().contains('recepci');

    late String titulo;
    late String subtitulo;
    late IconData icono;
    late Color bannerColor;
    Widget? badgeWidget;

    if (isDesbloqueado) {
      titulo = 'EVENTO LIBERADO';
      subtitulo = 'TODO LISTO PARA EL DESPEGUE.';
      icono = Icons.verified_rounded;
      bannerColor = green;
    } else if (esRecepcion) {
      final cuotaIdeal = totalPresupuesto / (widget.evento.cantidadCuotas > 0 ? widget.evento.cantidadCuotas : 1);
      final cuotasFaltantes = cuotaIdeal > 0 ? (saldoDeudor / cuotaIdeal).ceil() : 0;
      titulo = 'ACCESO RESTRINGIDO';
      subtitulo = 'FALTAN $cuotasFaltantes CUOTAS PARA DESBLOQUEAR.';
      icono = Icons.lock_clock_rounded;
      bannerColor = red;
      badgeWidget = GestureDetector(
        onTap: _ajustarCuotas,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${widget.evento.cantidadCuotas} CUOTAS',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
          ),
        ),
      );
    } else {
      final sena30 = totalPresupuesto * 0.30;
      final senaAbonada = totalPagado >= sena30 - 0.01;
      if (!senaAbonada) {
        titulo = 'SEÑA EN PROCESO';
        subtitulo = 'Ref. sugerida 30%: ${sena30.toCurrency()}.';
        icono = Icons.info_outline_rounded;
        bannerColor = const Color(0xFF636E72); // Gris profesional
        badgeWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            '30%',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        );
      } else {
        titulo = 'SEÑA COBRADA';
        subtitulo = 'SALDO RESTANTE: ${saldoDeudor.toCurrency()}.';
        icono = Icons.paid_rounded;
        bannerColor = const Color(0xFFD4AF37);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bannerColor.withValues(alpha: 0.8), bannerColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: bannerColor.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icono, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (badgeWidget != null) badgeWidget!,
        ],
      ),
    );
  }

  Widget _buildPanelContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    // CORRECCIÓN APLICADA: Ahora multiplica correctamente el precio por la cantidad.
    final presupuestoTotal = _servicios.fold<double>(0, (sum, item) => sum + (item.precioFinalAcordado * item.cantidad));
    final totalPagado = _transacciones.fold<double>(0, (sum, item) => sum + item.monto);
    final saldo = presupuestoTotal - totalPagado; 

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResumenCards(presupuestoTotal, saldo),
          const SizedBox(height: 24),
          _buildSeccionInformacionEvento(),
          const SizedBox(height: 24),
          _buildSeccionServicios(),
          const SizedBox(height: 24),
          _buildSeccionPagos(totalPagado),
        ],
      ),
    );
  }

  Widget _buildResumenCards(double presupuestoTotal, double saldo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      children: [
        Expanded(
          child: _buildMiniCard(
            titulo: 'PRESUPUESTO G.',
            monto: presupuestoTotal,
            color: isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.1),
            icon: Icons.account_balance_wallet_rounded,
            iconColor: Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMiniCard(
            titulo: 'Saldo a liquidar',
            monto: saldo,
            color: isDark ? Colors.orange.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.1),
            icon: Icons.money_off_csred_rounded,
            iconColor: Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniCard({required String titulo, required double monto, required Color color, required IconData icon, required Color iconColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: iconColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            monto.toCurrency(),
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: iconColor, letterSpacing: -0.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionServicios() {
    if (_servicios.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Text('No hay servicios asignados.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _editarServicios,
                icon: const Icon(Icons.add),
                label: const Text('Asignar Proveedores'),
              )
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'PROVEEDORES ASIGNADOS',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2, color: Colors.grey),
            ),
            TextButton.icon(
              onPressed: _editarServicios,
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('EDITAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFD4AF37)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._servicios.map((srv) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const CircleAvatar(
              backgroundColor: Colors.transparent,
              child: Icon(Icons.storefront_rounded, color: Color(0xFFD4AF37)),
            ),
            title: Text(srv.servicio?.nombre ?? 'Desconocido', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: srv.cantidad > 1 
                ? Text('CANTIDAD: ${srv.cantidad.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))
                : null,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(srv.precioFinalAcordado.toCurrency(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFD4AF37))),
                if (srv.cantidad > 1) 
                  Text('TOTAL: ${(srv.cantidad * srv.precioFinalAcordado).toCurrency()}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ))
      ],
    );
  }

  Widget _buildSeccionInformacionEvento() {
    final observaciones = widget.evento.observaciones;
    if (observaciones == null || observaciones.trim().isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'DETALLES DEL EVENTO',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2, color: Colors.grey),
            ),
            TextButton.icon(
              onPressed: _editarInformacionEvento,
              icon: const Icon(Icons.edit_note_rounded, size: 16),
              label: const Text('EDITAR INFO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: primaryGold.withValues(alpha: 0.2)),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: primaryGold, size: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'REGISTRO DE DATOS',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 0.5),
              Text(
                observaciones,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _mostrarHistorialPagos() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double totalPagado = _transacciones.fold(0, (sum, t) => sum + t.monto);
    final double totalPresupuesto = _servicios.fold(0, (sum, s) => sum + (s.precioFinalAcordado * s.cantidad));
    final double saldo = totalPresupuesto - totalPagado;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
        ),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFD4AF37)),
                  SizedBox(width: 12),
                  Text(
                    'ESTADO DE CUENTA',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                (widget.evento.cliente?.nombreCompleto ?? 'CLIENTE').toUpperCase(),
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 500,
          height: 450,
          child: Column(
            children: [
              Expanded(
                child: _transacciones.isEmpty 
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          const Text('No hay pagos registrados aún.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _transacciones.length,
                      itemBuilder: (context, index) {
                        final tr = _transacciones[index];
                        final fecha = tr.fechaPago ?? DateTime.now();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check_rounded, color: Colors.green, size: 16),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr.concepto ?? 'Entrega / Pago',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      '${fecha.day}/${fecha.month}/${fecha.year} - ${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')} hs',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                tr.monto.toCurrency(),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.green),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
              ),
              const Divider(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.1)),
                ),
                child: Column(
                  children: [
                    _buildResumenRow('PRESUPUESTO:', totalPresupuesto.toCurrency(), Colors.grey, 12),
                    const SizedBox(height: 4),
                    _buildResumenRow('TOTAL PAGADO:', totalPagado.toCurrency(), Colors.green, 14),
                    const Divider(height: 16),
                    _buildResumenRow('SALDO PENDIENTE:', saldo.toCurrency(), const Color(0xFFD4AF37), 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CERRAR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenRow(String label, String value, Color color, double fontSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: fontSize, color: color)),
      ],
    );
  }

  Widget _buildSeccionPagos(double totalPagado) {
    if (_transacciones.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             const Text(
               'HISTORIAL DE PAGOS',
               style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2, color: Colors.grey),
             ),
             Text(
                'TOTAL: ${totalPagado.toCurrency()}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.green),
             )
           ],
        ),
        const SizedBox(height: 8),
        ..._transacciones.map((tr) {
           final fecha = tr.fechaPago != null ? "${tr.fechaPago!.day}/${tr.fechaPago!.month}/${tr.fechaPago!.year}" : "Sin fecha";
           return Card(
             margin: const EdgeInsets.only(bottom: 8),
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
             child: ListTile(
               leading: Container(
                 padding: const EdgeInsets.all(8),
                 decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                 child: const Icon(Icons.payments_rounded, color: Colors.green, size: 16),
               ),
               title: Text(tr.concepto ?? 'Pago', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
               subtitle: Text(fecha, style: const TextStyle(fontSize: 12)),
               trailing: Text('+${tr.monto.toCurrency()}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
             ),
           );
        }),
      ],
    );
  }
}