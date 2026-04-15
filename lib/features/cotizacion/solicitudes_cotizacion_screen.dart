import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main.dart';
import '../../models/solicitud_cotizacion.dart';
import '../../models/servicio.dart';
import '../eventos/crear_evento_screen.dart';
import '../common/widgets/admin_gate.dart';

class SolicitudesCotizacionScreen extends ConsumerStatefulWidget {
  const SolicitudesCotizacionScreen({super.key});

  @override
  ConsumerState<SolicitudesCotizacionScreen> createState() => _SolicitudesCotizacionScreenState();
}

class _SolicitudesCotizacionScreenState extends ConsumerState<SolicitudesCotizacionScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<SolicitudCotizacion> _solicitudes = [];
  final Map<String, Servicio> _serviciosCache = {};
  bool _mostrarHistorial = false;

  @override
  void initState() {
    super.initState();
    _fetchSolicitudes();
  }

  Future<void> _fetchSolicitudes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final supabase = ref.read(supabaseProvider);

    try {
      // Cargamos catálogo de servicios una sola vez para poder mostrar nombres "bonitos"
      if (_serviciosCache.isEmpty) {
        final serviciosRes = await supabase
            .from('servicios')
            .select('id, nombre');
        final List servList = serviciosRes as List;
        for (final raw in servList) {
          final srv = Servicio.fromJson(raw as Map<String, dynamic>);
          _serviciosCache[srv.id] = srv;
        }
      }

      final response = await supabase
          .from('solicitudes_cotizacion')
          .select('id, cliente_nombre, cliente_celular, servicios_seleccionados, total_estimado, fecha, estado, comentarios')
          .order('fecha', ascending: false);

      final List data = response as List;
      setState(() {
        _solicitudes = data.map((e) => SolicitudCotizacion.fromJson(e as Map<String, dynamic>)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar solicitudes: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _marcarComoGestionada(SolicitudCotizacion solicitud) async {
    // REQUISITO DE AUTORIZACIÓN: Solo un administrador puede gestionar solicitudes QR
    final authorized = await AdminGate.check(context, ref);
    if (!authorized) return;

    final supabase = ref.read(supabaseProvider);
    try {
      // Marcamos como gestionada Y verificamos la respuesta inmediata
      final response = await supabase
          .from('solicitudes_cotizacion')
          .update({
            'estado': 'gestionada',
          })
          .eq('id', solicitud.id)
          .select();

      final List data = response as List;
      if (data.isEmpty) {
        throw 'No se pudo actualizar. Es probable que necesites aplicar el script SQL en Supabase (fix_rls_public.sql).';
      }

      if (mounted) {
        setState(() {
          final idx = _solicitudes.indexWhere((s) => s.id == solicitud.id);
          if (idx >= 0) {
            _solicitudes[idx] = SolicitudCotizacion(
              id: solicitud.id,
              clienteNombre: solicitud.clienteNombre,
              clienteCelular: solicitud.clienteCelular,
              serviciosIds: solicitud.serviciosIds,
              totalEstimado: solicitud.totalEstimado,
              fecha: solicitud.fecha,
              estado: 'gestionada',
              comentarios: solicitud.comentarios,
            );
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud gestionada con éxito y persistida en base de datos.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('ERROR AL GESTIONAR SOLICITUD: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al gestionar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _mostrarDetalleSolicitud(SolicitudCotizacion solicitud) {
    final primaryGold = const Color(0xFFD4AF37);
    final serviciosElegidos = solicitud.serviciosIds
        .map((id) => _serviciosCache[id]?.nombre ?? 'Servicio $id')
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF141414)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: primaryGold.withValues(alpha: 0.4), width: 1),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INTERÉS QR PREMIUM',
                style: GoogleFonts.oswald(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                solicitud.clienteNombre,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.phone_android_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      solicitud.clienteCelular,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Servicios que le interesan',
                  style: GoogleFonts.oswald(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: serviciosElegidos
                      .map(
                        (nombre) => Chip(
                          label: Text(
                            nombre.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                          backgroundColor: primaryGold.withValues(alpha: 0.12),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                if ((solicitud.comentarios ?? '').trim().isNotEmpty) ...[
                  Text(
                    'Lo que le gustaría',
                    style: GoogleFonts.oswald(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryGold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      solicitud.comentarios!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  'Siguiente movimiento sugerido',
                  style: GoogleFonts.oswald(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contactalo por WhatsApp usando el número que dejó y proponé un presupuesto rápido con esos servicios como base.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CERRAR'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CrearEventoScreen(),
                    settings: RouteSettings(
                      arguments: {
                        'origen': 'solicitud_qr',
                        'nombre': solicitud.clienteNombre,
                        'celular': solicitud.clienteCelular,
                        'comentarios': solicitud.comentarios,
                        'servicios': serviciosElegidos,
                      },
                    ),
                  ),
                );
              },
              child: const Text('CREAR EVENTO', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (solicitud.estado.toLowerCase() == 'pendiente')
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _marcarComoGestionada(solicitud);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('MARCAR COMO GESTIONADA'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryGold = const Color(0xFFD4AF37);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final pendingCount = _solicitudes.where((s) => s.estado.toLowerCase() == 'pendiente').length;
        Navigator.pop(context, pendingCount);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Solicitudes vía QR'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              final pendingCount = _solicitudes.where((s) => s.estado.toLowerCase() == 'pendiente').length;
              Navigator.pop(context, pendingCount);
            },
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [Colors.black, const Color(0xFF121212)]
                  : [Colors.white, const Color(0xFFF5F5F5)],
            ),
          ),
          child: SafeArea(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _fetchSolicitudes,
                              child: const Text('REINTENTAR'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _solicitudes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text(
                                'No hay solicitudes de cotización por el momento.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Cuando alguien complete el formulario del catálogo QR, aparecerá aquí.',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final visiblesPendientes = _solicitudes
                                .where((s) => s.estado.toLowerCase() == 'pendiente')
                                .toList();
                            final visiblesHistorial = _solicitudes
                                .where((s) => s.estado.toLowerCase() != 'pendiente')
                                .toList();
                            final visibles = _mostrarHistorial ? visiblesHistorial : visiblesPendientes;

                            return RefreshIndicator(
                              onRefresh: _fetchSolicitudes,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(24),
                                itemCount: visibles.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _mostrarHistorial ? 'Historial de intereses QR' : 'Solicitudes pendientes',
                                            style: GoogleFonts.oswald(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          SegmentedButton<bool>(
                                            segments: const [
                                              ButtonSegment<bool>(value: false, label: Text('Pendientes')),
                                              ButtonSegment<bool>(value: true, label: Text('Historial')),
                                            ],
                                            selected: {_mostrarHistorial},
                                            onSelectionChanged: (set) {
                                              setState(() {
                                                _mostrarHistorial = set.first;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  final s = visibles[index - 1];
                              final fechaStr =
                                  '${s.fecha.day.toString().padLeft(2, '0')}/${s.fecha.month.toString().padLeft(2, '0')}/${s.fecha.year}';
                              final isPendiente = s.estado.toLowerCase() == 'pendiente';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: isPendiente ? primaryGold : Colors.grey.withValues(alpha: 0.3),
                                  ),
                                ),
                                elevation: 0,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            s.clienteNombre,
                                            style: GoogleFonts.oswald(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isPendiente ? primaryGold : Colors.grey[400],
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              s.estado.toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Cel: ${s.clienteCelular}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Servicios seleccionados: ${s.serviciosIds.length}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Fecha: $fechaStr',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () => _mostrarDetalleSolicitud(s),
                                            child: const Text('VER DETALLE'),
                                          ),
                                          if (isPendiente)
                                            TextButton(
                                              onPressed: () => _marcarComoGestionada(s),
                                              child: const Text('MARCAR COMO GESTIONADA'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
          ),
        ),
      ),
    );
  }
}
