import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../common/utils/currency_extensions.dart';
import '../common/services/pdf_service.dart';
import '../../../models/evento.dart';
import '../common/providers/admin_provider.dart';
import '../common/providers/user_role_provider.dart';
import '../../../models/calculo_rentabilidad.dart';
import '../../../models/presupuesto.dart';
import '../../../core/utils/uuid_utils.dart';
import 'services/calculador_rentabilidad_service.dart';
import 'repositories/rentabilidad_repository.dart';
import '../mi_empresa/repositories/rentabilidad_config_repository.dart';

/// Texto legible para un registro de descuento (fila del ítem + resumen agrupado).
String _textoRegistroDescuentoRent(int n, RegistroDescuentoRent r) {
  final tipo = r.modoAjuste == 'porcentaje' ? 'Porcentaje' : 'Pesos';
  final String pref;
  if (r.modoAjuste == 'porcentaje') {
    final p = r.sacarPorcentaje;
    pref = p == p.roundToDouble() ? '${p.round()} % sobre saldo' : '${p.toStringAsFixed(1).replaceAll('.', ',')} % sobre saldo';
  } else {
    pref = '${r.sacarPesos.toCurrency()} del saldo';
  }
  final det = r.detalle.isNotEmpty ? ' · ${r.detalle}' : '';
  return '#$n · $tipo: $pref → − ${r.montoDescontado.toCurrency()}$det';
}

/// Colores tema claro (legible en oficina / día).
class _RentabilidadLight {
  static const Color fondo = Color(0xFFF3F4F6);
  static const Color tarjeta = Colors.white;
  static const Color borde = Color(0xFFE5E7EB);
  static const Color texto = Color(0xFF111827);
  static const Color textoSec = Color(0xFF6B7280);
  static const Color gold = Color(0xFFD4AF37);
  static const Color costos = Color(0xFFDC2626);
  static const Color ok = Color(0xFF059669);
}

class CalculadorRentabilidadScreen extends ConsumerStatefulWidget {
  final Presupuesto? presupuestoPreCargado;

  const CalculadorRentabilidadScreen({super.key, this.presupuestoPreCargado});

  @override
  ConsumerState<CalculadorRentabilidadScreen> createState() => _CalculadorRentabilidadScreenState();
}

class _CalculadorRentabilidadScreenState extends ConsumerState<CalculadorRentabilidadScreen> {
  final _service = CalculadorRentabilidadService();

  late TextEditingController _precioVentaCtrl;
  late TextEditingController _honorarioCtrl;
  late TextEditingController _notasCtrl;

  String _honorarioModo = 'monto';
  List<CostoItem> _costosVariables = [];
  List<CostoItem> _costosFijos = [];

  ResultadoRentabilidad? _resultado;

  bool get _accesoPermitido {
    final admin = ref.watch(adminAuthProvider).isAdmin;
    final finanzas = ref.watch(userRoleProvider).maybeWhen(
          data: (d) => d.permisos.puedeFinanzas,
          orElse: () => false,
        );
    return admin || finanzas;
  }

  @override
  void initState() {
    super.initState();
    _precioVentaCtrl = TextEditingController(text: '0');
    _honorarioCtrl = TextEditingController(text: '0');
    _notasCtrl = TextEditingController();

    _precioVentaCtrl.addListener(_recalcular);
    _honorarioCtrl.addListener(_recalcular);

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapSimulador());
  }

  List<CostoItem> _clonarLineasCosto(List<CostoItem> src) {
    return src
        .map((e) => CostoItem.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>))
        .toList();
  }

  void _aplicarCalculoGuardado(CalculoRentabilidad c) {
    setState(() {
      _precioVentaCtrl.text = _montoParaCampo(c.precioVenta);
      _honorarioModo = c.honorarioModo;
      if (c.honorarioModo == 'monto') {
        _honorarioCtrl.text = _montoParaCampo(c.honorarioAdrianMonto);
      } else {
        _honorarioCtrl.text = _montoParaCampo(c.honorarioAdrianPct);
      }
      _costosVariables = _clonarLineasCosto(c.costosVariables);
      _costosFijos = _clonarLineasCosto(c.costosFijos);
      _notasCtrl.text = c.notas ?? '';
    });
    _recalcular();
  }

  /// Con presupuesto: solo el historial de ese id (nunca mezcla con otros).
  /// Sin presupuesto: el cálculo guardado más reciente en general.
  Future<void> _bootstrapSimulador() async {
    final repo = ref.read(rentabilidadRepositoryProvider);
    List<CalculoRentabilidad> hist = [];
    try {
      if (widget.presupuestoPreCargado != null) {
        hist = await repo.getHistorial(presupuestoId: widget.presupuestoPreCargado!.id);
      } else {
        hist = await repo.getHistorial();
      }
    } catch (e) {
      debugPrint('Rentabilidad: error leyendo historial: $e');
    }
    if (!mounted) return;

    if (hist.isNotEmpty) {
      _aplicarCalculoGuardado(hist.first);
      return;
    }

    setState(() {
      if (widget.presupuestoPreCargado != null) {
        final p = widget.presupuestoPreCargado!;
        _precioVentaCtrl.text = p.total.toInt().toString();
        for (var s in p.servicios) {
          if (s.servicio != null) {
            final tc = ((s.servicio!.costoBase ?? 0) + (s.servicio!.costoInterno ?? 0)) * s.cantidad;
            if (tc > 0) {
              _costosVariables.add(CostoItem(concepto: s.nombre ?? 'Servicio', montoBase: tc));
            }
          }
        }
      }
    });
    await _cargarConfigFija();
  }

  Future<void> _cargarConfigFija() async {
    try {
      final repo = ref.read(rentabilidadConfigRepositoryProvider);
      final cfg = await repo.getConfig();
      if (!mounted) return;

      setState(() {
        if (cfg.costoFijoPorEvento > 0) {
          _costosFijos.add(CostoItem(
            concepto: 'Operatividad empresa (prorrateo fijo)',
            montoBase: cfg.costoFijoPorEvento,
          ));
        }

        _honorarioModo = cfg.honorarioModoDefault;
        if (_honorarioModo == 'monto') {
          _honorarioCtrl.text = cfg.honorarioAdrianDefaultMonto.toInt().toString();
        } else {
          _honorarioCtrl.text = cfg.honorarioAdrianDefaultPct.toString();
        }
      });
      _recalcular();
    } catch (e) {
      debugPrint('Error cargando config en simulador: $e');
      if (mounted) _recalcular();
    }
  }

  @override
  void dispose() {
    _precioVentaCtrl.dispose();
    _honorarioCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  void _recalcular() {
    final param = CalculoRentabilidad(
      id: '',
      precioVenta: double.tryParse(_precioVentaCtrl.text) ?? 0.0,
      honorarioAdrianMonto: _honorarioModo == 'monto' ? (double.tryParse(_honorarioCtrl.text) ?? 0.0) : 0.0,
      honorarioAdrianPct: _honorarioModo == 'porcentaje' ? (double.tryParse(_honorarioCtrl.text) ?? 0.0) : 0.0,
      honorarioModo: _honorarioModo,
      costosVariables: _costosVariables,
      costosFijos: _costosFijos,
      createdAt: DateTime.now(),
    );

    setState(() {
      _resultado = _service.calcular(param);
    });
  }

  Future<void> _guardar() async {
    final param = CalculoRentabilidad(
      id: UuidUtils.generate(),
      presupuestoId: widget.presupuestoPreCargado?.id,
      precioVenta: double.tryParse(_precioVentaCtrl.text) ?? 0.0,
      honorarioAdrianMonto: _honorarioModo == 'monto' ? (double.tryParse(_honorarioCtrl.text) ?? 0.0) : 0.0,
      honorarioAdrianPct: _honorarioModo == 'porcentaje' ? (double.tryParse(_honorarioCtrl.text) ?? 0.0) : 0.0,
      honorarioModo: _honorarioModo,
      costosVariables: _costosVariables,
      costosFijos: _costosFijos,
      resultado: _resultado?.gananciaNetaEmpresa,
      notas: _notasCtrl.text.trim(),
      createdAt: DateTime.now(),
    );

    await ref.read(rentabilidadRepositoryProvider).guardarCalculo(param);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cálculo guardado correctamente'),
        backgroundColor: _RentabilidadLight.ok,
      ),
    );
  }

  Future<void> _exportarPdf() async {
    if (_resultado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calculá primero (ingresá precio y costos).')),
      );
      return;
    }
    final p = widget.presupuestoPreCargado;
    try {
      await PdfService.generarRentabilidadPdf(
        resultado: _resultado!,
        costosVariables: List<CostoItem>.from(_costosVariables),
        costosFijos: List<CostoItem>.from(_costosFijos),
        honorarioModo: _honorarioModo,
        honorarioAdrianMonto: _honorarioModo == 'monto' ? (double.tryParse(_honorarioCtrl.text) ?? 0.0) : 0.0,
        honorarioAdrianPct: _honorarioModo == 'porcentaje' ? (double.tryParse(_honorarioCtrl.text) ?? 0.0) : 0.0,
        presupuestoClienteNombre: p?.cliente?.nombreCompleto,
        tipoEventoLabel: p != null ? Evento.formatearTipo(p.tipoEvento) : null,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF generado'), backgroundColor: _RentabilidadLight.ok),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el PDF: $e'), backgroundColor: _RentabilidadLight.costos),
      );
    }
  }

  String _montoParaCampo(double m) {
    if (m == m.roundToDouble()) return m.round().toString();
    return m.toString();
  }

  /// Solo muta listas locales del simulador. No toca presupuesto ni evento en base de datos.
  void _agregarOEditarCosto(bool esFijo, {CostoItem? existing}) {
    final esEdicion = existing != null;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cNombre = TextEditingController(text: existing?.concepto ?? '');
        final cMonto = TextEditingController(
          text: existing != null ? _montoParaCampo(existing.montoBase) : '',
        );
        return AlertDialog(
          backgroundColor: _RentabilidadLight.tarjeta,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            esEdicion
                ? (esFijo ? 'Editar costo fijo' : 'Editar costo variable')
                : (esFijo ? 'Agregar costo fijo' : 'Agregar costo variable'),
            style: GoogleFonts.oswald(
              fontWeight: FontWeight.w700,
              color: _RentabilidadLight.texto,
              fontSize: 20,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cNombre,
                decoration: InputDecoration(
                  labelText: 'Concepto (ej. operador, combustible)',
                  filled: true,
                  fillColor: _RentabilidadLight.fondo,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cMonto,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Monto base de referencia (\$)',
                  helperText: 'Es el costo de referencia; lo que sacás se define en la fila con \$ o %.',
                  filled: true,
                  fillColor: _RentabilidadLight.fondo,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _RentabilidadLight.gold,
                foregroundColor: Colors.black87,
              ),
              onPressed: () {
                final m = double.tryParse(cMonto.text.replaceAll(',', '.')) ?? 0;
                final nombre = cNombre.text.trim();
                if (nombre.isEmpty || m <= 0) return;
                if (esEdicion) {
                  setState(() {
                    existing.concepto = nombre;
                    existing.montoBase = m;
                    if (existing.sacarPesos > m) existing.sacarPesos = m;
                    existing.sacarPorcentaje = existing.sacarPorcentaje.clamp(0.0, 100.0);
                  });
                } else {
                  setState(() {
                    final linea = CostoItem(concepto: nombre, montoBase: m);
                    if (esFijo) {
                      _costosFijos.add(linea);
                    } else {
                      _costosVariables.add(linea);
                    }
                  });
                }
                _recalcular();
                Navigator.pop(ctx);
              },
              child: Text(esEdicion ? 'Guardar' : 'Agregar'),
            ),
          ],
        );
      },
    );
  }

  void _eliminarCostoDelAnalisis(bool esFijo, CostoItem c) {
    setState(() {
      if (esFijo) {
        _costosFijos.remove(c);
      } else {
        _costosVariables.remove(c);
      }
    });
    _recalcular();
  }

  Widget _tarjeta({
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color colorAcento,
    required Widget child,
    Border? bordeDestacado,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _RentabilidadLight.tarjeta,
        borderRadius: BorderRadius.circular(16),
        border: bordeDestacado ?? Border.all(color: _RentabilidadLight.borde),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: colorAcento, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.oswald(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _RentabilidadLight.texto,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: const TextStyle(fontSize: 12, color: _RentabilidadLight.textoSec, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label, {String? prefix, String? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixText: prefix,
      suffixText: suffix,
      filled: true,
      fillColor: _RentabilidadLight.fondo,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _RentabilidadLight.gold, width: 2),
      ),
    );
  }

  Widget _buildStatusSemaforo(EstadoRentabilidad e) {
    late Color bg;
    late Color fg;
    late String label;
    late IconData icon;

    switch (e) {
      case EstadoRentabilidad.saludable:
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF047857);
        label = 'Excedente saludable';
        icon = Icons.trending_up_rounded;
        break;
      case EstadoRentabilidad.ajustado:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        label = 'Margen ajustado';
        icon = Icons.trending_flat_rounded;
        break;
      case EstadoRentabilidad.equilibrio:
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFC2410C);
        label = 'Punto de equilibrio';
        icon = Icons.balance_rounded;
        break;
      case EstadoRentabilidad.perdida:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        label = 'Pérdida neta';
        icon = Icons.trending_down_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_accesoPermitido) {
      return Scaffold(
        backgroundColor: _RentabilidadLight.fondo,
        appBar: AppBar(
          backgroundColor: _RentabilidadLight.tarjeta,
          foregroundColor: _RentabilidadLight.texto,
          elevation: 0,
          title: Text('Rentabilidad', style: GoogleFonts.oswald(fontWeight: FontWeight.w700)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No tenés permiso para esta herramienta. Pedí acceso de finanzas o usala desde MI EMPRESA con PIN.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _RentabilidadLight.textoSec, fontSize: 16, height: 1.4),
            ),
          ),
        ),
      );
    }

    final totalCV = _costosVariables.fold<double>(0, (s, e) => s + e.montoEfectivo);
    final totalCF = _costosFijos.fold<double>(0, (s, e) => s + e.montoEfectivo);
    final hAdrian = _resultado?.honorarioAdrian ?? 0;
    final totalCostos = totalCV + totalCF + hAdrian;

    return Scaffold(
      backgroundColor: _RentabilidadLight.fondo,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _RentabilidadLight.tarjeta,
        foregroundColor: _RentabilidadLight.texto,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rentabilidad del evento', style: GoogleFonts.oswald(fontWeight: FontWeight.w800, fontSize: 22)),
            Text(
              'Uso interno: no modifica presupuestos ni precios del cliente',
              style: TextStyle(fontSize: 12, color: _RentabilidadLight.textoSec, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final cols = <Widget>[
              _tarjeta(
                titulo: 'Ingresos',
                subtitulo: 'Lo que cobrás al cliente y el honorario del socio',
                icono: Icons.trending_up_rounded,
                colorAcento: _RentabilidadLight.gold,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _precioVentaCtrl,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.oswald(fontSize: 22, fontWeight: FontWeight.w700, color: _RentabilidadLight.texto),
                      decoration: _inputDec('Precio al cliente', prefix: '\$ '),
                    ),
                    const SizedBox(height: 20),
                    const Text('Honorario Adrián', style: TextStyle(fontWeight: FontWeight.w700, color: _RentabilidadLight.texto)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'monto', label: Text('Monto fijo'), icon: Icon(Icons.payments_outlined, size: 18)),
                        ButtonSegment(value: 'porcentaje', label: Text('% del precio'), icon: Icon(Icons.percent_rounded, size: 18)),
                      ],
                      selected: {_honorarioModo},
                      onSelectionChanged: (s) {
                        setState(() => _honorarioModo = s.first);
                        _recalcular();
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _honorarioCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDec(
                        _honorarioModo == 'monto' ? 'Monto honorario' : 'Porcentaje',
                        prefix: _honorarioModo == 'monto' ? '\$ ' : null,
                        suffix: _honorarioModo == 'porcentaje' ? ' %' : null,
                      ),
                    ),
                    if (widget.presupuestoPreCargado != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _RentabilidadLight.gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.link_rounded, color: _RentabilidadLight.gold.withValues(alpha: 0.9), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Referencia: presupuesto #${widget.presupuestoPreCargado!.id.substring(0, 6)}… (solo lectura; el PDF al cliente no se toca desde acá)',
                                style: TextStyle(color: _RentabilidadLight.textoSec, fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _tarjeta(
                titulo: 'Costos',
                subtitulo: 'Mapa de trabajo interno: no cambia el presupuesto al cliente ni el dashboard público',
                icono: Icons.receipt_long_rounded,
                colorAcento: _RentabilidadLight.costos,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _RentabilidadLight.fondo,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _RentabilidadLight.borde),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 18, color: _RentabilidadLight.textoSec.withValues(alpha: 0.9)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Lo que cargás acá solo afecta este simulador y el PDF/guardado de rentabilidad. El presupuesto armado para el cliente queda igual.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _RentabilidadLight.textoSec,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Costos variables', style: TextStyle(fontWeight: FontWeight.w700, color: _RentabilidadLight.texto)),
                    const SizedBox(height: 6),
                    ..._costosVariables.map(
                      (c) => _FilaCostoAjuste(
                        item: c,
                        onChanged: () {
                          setState(() {});
                          _recalcular();
                        },
                        onEditarNombreYBase: () => _agregarOEditarCosto(false, existing: c),
                        onEliminar: () => _eliminarCostoDelAnalisis(false, c),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _agregarOEditarCosto(false),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        label: const Text('Agregar variable'),
                      ),
                    ),
                    const Divider(height: 24),
                    const Text('Costos fijos', style: TextStyle(fontWeight: FontWeight.w700, color: _RentabilidadLight.texto)),
                    const SizedBox(height: 6),
                    ..._costosFijos.map(
                      (c) => _FilaCostoAjuste(
                        item: c,
                        onChanged: () {
                          setState(() {});
                          _recalcular();
                        },
                        onEditarNombreYBase: () => _agregarOEditarCosto(true, existing: c),
                        onEliminar: () => _eliminarCostoDelAnalisis(true, c),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _agregarOEditarCosto(true),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        label: const Text('Agregar fijo'),
                      ),
                    ),
                    const Divider(),
                    _filaTotal('Suma costos variables', totalCV),
                    _filaTotal('Suma costos fijos', totalCF),
                    _buildDesgloseDescuentosCostos(),
                    _filaTotal('Honorario Adrián (en total costos)', hAdrian),
                    const SizedBox(height: 6),
                    _filaTotal('Total costos + honorario', totalCostos, destacar: true),
                  ],
                ),
              ),
              _tarjeta(
                titulo: 'Resultado',
                subtitulo: 'Ganancia neta empresa después de todo',
                icono: Icons.insights_rounded,
                colorAcento: _RentabilidadLight.ok,
                bordeDestacado: Border.all(color: _RentabilidadLight.gold.withValues(alpha: 0.5), width: 1.5),
                child: _resultado == null
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Ganancia neta empresa',
                            style: TextStyle(fontSize: 12, color: _RentabilidadLight.textoSec, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _resultado!.gananciaNetaEmpresa.toCurrency(),
                            style: GoogleFonts.oswald(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: _resultado!.gananciaNetaEmpresa >= 0 ? _RentabilidadLight.ok : _RentabilidadLight.costos,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildStatusSemaforo(_resultado!.estado),
                          if (_resultado!.estado == EstadoRentabilidad.perdida) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Revisá precio al cliente o costos para cubrir honorario y gastos.',
                              style: TextStyle(fontSize: 12, color: _RentabilidadLight.textoSec),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _filaResumen('Margen bruto', _resultado!.margenBruto.toCurrency()),
                          _filaResumen('Punto de equilibrio', _resultado!.puntoEquilibrio.toCurrency()),
                          _filaResumen('Markup empresa', '${_resultado!.markupEmpresaPct.toStringAsFixed(1)} %'),
                        ],
                      ),
              ),
            ];

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  sliver: SliverToBoxAdapter(
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < cols.length; i++) ...[
                                if (i > 0) const SizedBox(width: 16),
                                Expanded(child: cols[i]),
                              ],
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < cols.length; i++) ...[
                                if (i > 0) const SizedBox(height: 16),
                                cols[i],
                              ],
                            ],
                          ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      controller: _notasCtrl,
                      maxLines: 2,
                      decoration: _inputDec('Notas internas (opcional)'),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _resultado == null ? null : _exportarPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Exportar PDF', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _RentabilidadLight.texto,
                              side: const BorderSide(color: _RentabilidadLight.borde),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _guardar,
                            icon: const Icon(Icons.save_outlined),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text('Guardar cálculo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _RentabilidadLight.gold,
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _totalDescuentosSobreCostos() {
    final v = _costosVariables.fold<double>(0, (s, e) => s + e.montoDescuento);
    final f = _costosFijos.fold<double>(0, (s, e) => s + e.montoDescuento);
    return v + f;
  }

  Widget _filaDesgloseDescuento({
    required String rubro,
    required String descripcion,
    required double monto,
    bool pendiente = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: pendiente ? _RentabilidadLight.gold.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _RentabilidadLight.borde),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    rubro,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: _RentabilidadLight.texto,
                    ),
                  ),
                ),
                Text(
                  '− ${monto.toCurrency()}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: _RentabilidadLight.costos.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              descripcion,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _RentabilidadLight.textoSec.withValues(alpha: 0.95),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesgloseDescuentosCostos() {
    final total = _totalDescuentosSobreCostos();
    if (total < 0.005) return const SizedBox.shrink();

    final bloques = <Widget>[];

    void appendPara(List<CostoItem> items) {
      for (final c in items) {
        var n = 0;
        for (final r in c.registrosDescuento) {
          n++;
          bloques.add(
            _filaDesgloseDescuento(
              rubro: c.concepto,
              descripcion: _textoRegistroDescuentoRent(n, r),
              monto: r.montoDescontado,
            ),
          );
        }
        if (c.montoDescuentoPendiente >= 0.005) {
          final det = c.detalleAjuste.trim();
          bloques.add(
            _filaDesgloseDescuento(
              rubro: c.concepto,
              descripcion: det.isEmpty
                  ? 'Ajuste cargado en la fila, aún sin guardar con «Guardar ajuste y seguir».'
                  : 'Ajuste pendiente (sin guardar) · $det',
              monto: c.montoDescuentoPendiente,
              pendiente: true,
            ),
          );
        }
      }
    }

    appendPara(_costosVariables);
    appendPara(_costosFijos);

    if (bloques.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          'Descuentos sobre costos (detalle)',
          style: GoogleFonts.oswald(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _RentabilidadLight.texto,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Cada fila es un descuento aplicado al costo base del rubro; el total coincide con base − neto en las líneas de arriba.',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _RentabilidadLight.textoSec.withValues(alpha: 0.95),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        ...bloques,
        const Divider(height: 22),
        _filaTotal('Total descuentos (suma de todo lo restado al costo)', total, destacar: true),
      ],
    );
  }

  Widget _filaTotal(String label, double monto, {bool destacar = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: destacar ? FontWeight.w800 : FontWeight.w600,
              color: destacar ? _RentabilidadLight.texto : _RentabilidadLight.textoSec,
              fontSize: destacar ? 14 : 13,
            ),
          ),
          Text(
            monto.toCurrency(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: destacar ? _RentabilidadLight.costos : _RentabilidadLight.texto,
              fontSize: destacar ? 15 : 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaResumen(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _RentabilidadLight.textoSec, fontWeight: FontWeight.w600)),
          Text(valor, style: const TextStyle(color: _RentabilidadLight.texto, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

double? _parseValorAr(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  try {
    return NumberFormat.decimalPattern('es_AR').parse(t).toDouble();
  } catch (_) {
    final norm = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(norm);
  }
}

InputDecoration _rentCostoInputDec(String label, {String? prefix, String? suffix}) {
  return InputDecoration(
    labelText: label,
    prefixText: prefix,
    suffixText: suffix,
    filled: true,
    fillColor: _RentabilidadLight.fondo,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _RentabilidadLight.gold, width: 2),
    ),
  );
}

class _FilaCostoAjuste extends StatefulWidget {
  const _FilaCostoAjuste({
    required this.item,
    required this.onChanged,
    required this.onEditarNombreYBase,
    required this.onEliminar,
  });

  final CostoItem item;
  final VoidCallback onChanged;
  final VoidCallback onEditarNombreYBase;
  final VoidCallback onEliminar;

  @override
  State<_FilaCostoAjuste> createState() => _FilaCostoAjusteState();
}

class _FilaCostoAjusteState extends State<_FilaCostoAjuste> {
  late TextEditingController _pesosCtrl;
  late TextEditingController _pctCtrl;
  late TextEditingController _detalleCtrl;
  final FocusNode _pesosFocus = FocusNode();
  final FocusNode _pctFocus = FocusNode();
  final FocusNode _detalleFocus = FocusNode();

  static const _stepPesos = 5000.0;
  static const _stepPct = 1.0;

  @override
  void initState() {
    super.initState();
    _pesosCtrl = TextEditingController(text: _fmtPesos(widget.item.sacarPesos));
    _pctCtrl = TextEditingController(text: _fmtPct(widget.item.sacarPorcentaje));
    _detalleCtrl = TextEditingController(text: widget.item.detalleAjuste);
  }

  @override
  void didUpdateWidget(covariant _FilaCostoAjuste oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pesosFocus.hasFocus) {
      _pesosCtrl.text = _fmtPesos(widget.item.sacarPesos);
    }
    if (!_pctFocus.hasFocus) {
      _pctCtrl.text = _fmtPct(widget.item.sacarPorcentaje);
    }
    if (!_detalleFocus.hasFocus) {
      _detalleCtrl.text = widget.item.detalleAjuste;
    }
  }

  @override
  void dispose() {
    _pesosCtrl.dispose();
    _pctCtrl.dispose();
    _detalleCtrl.dispose();
    _pesosFocus.dispose();
    _pctFocus.dispose();
    _detalleFocus.dispose();
    super.dispose();
  }

  String _fmtPesos(double v) => v.toFormattedNumber();

  String _fmtPct(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _lineaRegistro(int n, RegistroDescuentoRent r) => _textoRegistroDescuentoRent(n, r);

  void _syncCtrlsDesdeItem() {
    _pesosCtrl.text = _fmtPesos(widget.item.sacarPesos);
    _pctCtrl.text = _fmtPct(widget.item.sacarPorcentaje);
    _detalleCtrl.text = widget.item.detalleAjuste;
  }

  void _guardarAjusteYContinuar() {
    final ok = widget.item.guardarDescuentoPendiente();
    if (!ok) return;
    _syncCtrlsDesdeItem();
    widget.onChanged();
  }

  void _quitarUltimoRegistro() {
    widget.item.quitarUltimoRegistro();
    _syncCtrlsDesdeItem();
    widget.onChanged();
  }

  void _bumpPesos(double delta) {
    _commitPesos();
    final max = widget.item.baseRestanteTrasRegistros;
    widget.item.sacarPesos = (widget.item.sacarPesos + delta).clamp(0.0, max);
    _pesosCtrl.text = _fmtPesos(widget.item.sacarPesos);
    widget.onChanged();
  }

  void _bumpPct(double delta) {
    _commitPct();
    widget.item.sacarPorcentaje = (widget.item.sacarPorcentaje + delta).clamp(0.0, 100.0);
    _pctCtrl.text = _fmtPct(widget.item.sacarPorcentaje);
    widget.onChanged();
  }

  void _commitPesos() {
    final v = _parseValorAr(_pesosCtrl.text) ?? widget.item.sacarPesos;
    final max = widget.item.baseRestanteTrasRegistros;
    widget.item.sacarPesos = v.clamp(0.0, max);
    _pesosCtrl.text = _fmtPesos(widget.item.sacarPesos);
    widget.onChanged();
  }

  void _commitPct() {
    final raw = _pctCtrl.text.replaceAll(',', '.').replaceAll('%', '').trim();
    final v = double.tryParse(raw) ?? widget.item.sacarPorcentaje;
    widget.item.sacarPorcentaje = v.clamp(0.0, 100.0);
    _pctCtrl.text = _fmtPct(widget.item.sacarPorcentaje);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _RentabilidadLight.fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _RentabilidadLight.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.concepto,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _RentabilidadLight.texto,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Nombre y monto base',
                onPressed: widget.onEditarNombreYBase,
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: _RentabilidadLight.textoSec,
              ),
              IconButton(
                tooltip: 'Quitar solo de este análisis (no modifica el presupuesto al cliente)',
                onPressed: widget.onEliminar,
                icon: const Icon(Icons.delete_outline_rounded, size: 22),
                color: _RentabilidadLight.costos.withValues(alpha: 0.85),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Base: ${c.montoBase.toCurrency()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _RentabilidadLight.textoSec,
                  ),
                ),
              ),
              Text(
                'Neto: ${c.montoEfectivo.toCurrency()}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: _RentabilidadLight.texto,
                ),
              ),
            ],
          ),
          if (c.montoDescuento > 0.005) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Descuento (base − neto)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _RentabilidadLight.textoSec.withValues(alpha: 0.95),
                    ),
                  ),
                ),
                Text(
                  '− ${c.montoDescuento.toCurrency()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _RentabilidadLight.costos.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'pesos',
                label: Text('Sacar en \$'),
                icon: Icon(Icons.payments_outlined, size: 16),
              ),
              ButtonSegment<String>(
                value: 'porcentaje',
                label: Text('Sacar en %'),
                icon: Icon(Icons.percent_rounded, size: 16),
              ),
            ],
            selected: {c.modoAjuste},
            onSelectionChanged: (Set<String> s) {
              final next = s.first;
              if (next != c.modoAjuste) {
                setState(() => c.modoAjuste = next);
                widget.onChanged();
              }
            },
          ),
          const SizedBox(height: 8),
          if (c.modoAjuste == 'pesos')
            Row(
              children: [
                IconButton(
                  onPressed: c.baseRestanteTrasRegistros <= 0 ? null : () => _bumpPesos(-_stepPesos),
                  icon: const Icon(Icons.remove_circle_outline),
                  color: _RentabilidadLight.textoSec,
                ),
                Expanded(
                  child: TextField(
                    controller: _pesosCtrl,
                    focusNode: _pesosFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _rentCostoInputDec('Sacar del base', prefix: '\$ '),
                    onSubmitted: (_) => _commitPesos(),
                    onEditingComplete: _commitPesos,
                  ),
                ),
                IconButton(
                  onPressed: c.baseRestanteTrasRegistros <= 0 ? null : () => _bumpPesos(_stepPesos),
                  icon: const Icon(Icons.add_circle_outline),
                  color: _RentabilidadLight.textoSec,
                ),
              ],
            )
          else
            Row(
              children: [
                IconButton(
                  onPressed: () => _bumpPct(-_stepPct),
                  icon: const Icon(Icons.remove_circle_outline),
                  color: _RentabilidadLight.textoSec,
                ),
                Expanded(
                  child: TextField(
                    controller: _pctCtrl,
                    focusNode: _pctFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _rentCostoInputDec('Sacar del base', suffix: ' %'),
                    onSubmitted: (_) => _commitPct(),
                    onEditingComplete: _commitPct,
                  ),
                ),
                IconButton(
                  onPressed: () => _bumpPct(_stepPct),
                  icon: const Icon(Icons.add_circle_outline),
                  color: _RentabilidadLight.textoSec,
                ),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            c.modoAjuste == 'pesos'
                ? 'Se resta en pesos del saldo disponible (máx. ${c.baseRestanteTrasRegistros.toCurrency()}).'
                : 'El % se aplica sobre el saldo que queda (0–100 %; tras los ajustes guardados abajo).',
            style: TextStyle(fontSize: 10, color: _RentabilidadLight.textoSec.withValues(alpha: 0.9)),
          ),
          if (c.registrosDescuento.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Descuentos guardados',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _RentabilidadLight.texto.withValues(alpha: 0.9),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            ...c.registrosDescuento.asMap().entries.map((e) {
              final i = e.key + 1;
              final r = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _RentabilidadLight.borde),
                  ),
                  child: Text(
                    _lineaRegistro(i, r),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _quitarUltimoRegistro,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Deshacer último guardado'),
                style: TextButton.styleFrom(foregroundColor: _RentabilidadLight.textoSec),
              ),
            ),
            Text(
              'Saldo para el próximo ajuste: ${c.baseRestanteTrasRegistros.toCurrency()}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _RentabilidadLight.gold.withValues(alpha: 0.95)),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _detalleCtrl,
            focusNode: _detalleFocus,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Detalle del ajuste',
              hintText: 'Opcional: a quién o qué aplica (proveedor, ítem, acuerdo…)',
              filled: true,
              fillColor: _RentabilidadLight.fondo,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _RentabilidadLight.gold, width: 2),
              ),
              helperText: 'Escribí la nota y tocá el botón de abajo para guardarla junto al descuento.',
              helperStyle: TextStyle(fontSize: 10, color: _RentabilidadLight.textoSec.withValues(alpha: 0.85)),
            ),
            onChanged: (t) => widget.item.detalleAjuste = t,
            onSubmitted: (_) {
              widget.item.detalleAjuste = _detalleCtrl.text;
              FocusScope.of(context).unfocus();
            },
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: widget.item.montoDescuentoPendiente < 0.005 ? null : _guardarAjusteYContinuar,
            icon: const Icon(Icons.save_outlined, size: 20),
            label: const Text('Guardar ajuste y seguir'),
            style: FilledButton.styleFrom(
              backgroundColor: _RentabilidadLight.gold,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
