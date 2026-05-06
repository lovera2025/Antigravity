import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/ar_time.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/repositories/eventos_repository.dart';
import '../../eventos/services/mora_cuota_calculator.dart';
import '../providers/finanzas_provider.dart';

/// Fila agregada para el listado Cobro (evento + institución).
@immutable
class _CobroFila {
  final ContratoAlumno contrato;
  final DateTime? primeraCuotaBase;
  final DateTime? ultimoPago;
  final MoraCuotaResumen mora;
  final double moraPendiente;

  const _CobroFila({
    required this.contrato,
    this.primeraCuotaBase,
    this.ultimoPago,
    required this.mora,
    this.moraPendiente = 0,
  });
}

bool _esInteresPago(String? concepto) =>
    esPagoInteresMoraPorConcepto(concepto);

double _sumMoraCobradaDesdePagos(Iterable<Map<String, dynamic>> pagos) {
  double s = 0;
  for (final p in pagos) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    final lk = (p['line_kind'] as String?)?.trim();
    final c = p['concepto']?.toString() ?? '';
    if (lk == kLineKindInteresMora || _esInteresPago(c)) {
      s += (p['monto'] as num).toDouble();
    }
  }
  return s;
}

/// Pago que cuenta como abono al plan de cuota base (alineado a [ContratosRepository.registrarPago]).
bool _pagoEsCuotaBase(Map<String, dynamic> p) {
  if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return false;
  if (_esInteresPago(p['concepto']?.toString())) return false;
  final c = (p['concepto']?.toString() ?? '').toLowerCase();
  if (c.contains('mesa') || c.contains('silla')) return false;
  if (c.contains('base') || c.trim().isEmpty) return true;
  return false;
}

/// Último pago "al plan" (cualquier concepto distinto de solo interés).
DateTime? _ultimoPagoAlPlan(Iterable<Map<String, dynamic>> pagos) {
  final list = pagos.toList();
  DateTime? last;
  for (final p in list) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    if (_esInteresPago(p['concepto']?.toString())) continue;
    final fp = p['fecha_pago']?.toString();
    if (fp == null) continue;
    final d = DateTime.tryParse(fp);
    if (d == null) continue;
    if (last == null || d.isAfter(last)) last = d;
  }
  if (last != null) return last;
  for (final p in list) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    final fp = p['fecha_pago']?.toString();
    if (fp == null) continue;
    final d = DateTime.tryParse(fp);
    if (d == null) continue;
    if (last == null || d.isAfter(last)) last = d;
  }
  return last;
}

DateTime? _minFechaBase(Iterable<Map<String, dynamic>> pagos) {
  DateTime? min;
  for (final p in pagos) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    if (!_pagoEsCuotaBase(p)) continue;
    final fp = p['fecha_pago']?.toString();
    if (fp == null) continue;
    final d = DateTime.tryParse(fp);
    if (d == null) continue;
    if (min == null || d.isBefore(min)) min = d;
  }
  return min;
}

/// Nombre de institución unificado para el listado COBRO (evita duplicados por typo, sin tocar la DB).
String _institucionCanonica(String? raw) {
  final t = raw?.trim() ?? '';
  if (t.isEmpty) return '';
  switch (t.toLowerCase()) {
    case 'sgarado':
    case 'sagrado':
      return 'SAGRADO';
    default:
      return t;
  }
}

/// Valor del combo "Institución" para listar todos los contratos del evento (sin filtrar por campo institución).
const String _kCobroTodosInstitucion = '__COBRO_TODOS_EL_EVENTO__';
const String _kCobroMarcaMensaje = 'Junior Eventos';

/// Filtro de cuota base: [todos] | al menos abonó una | ninguna.
enum _CobroFiltroCuota { todos, conAlMenosUna, ninguna }

bool _contratoEsBaja(ContratoAlumno a) => a.nombreAlumno.trim().startsWith('[BAJA]');

String? _whatsAppUri(String? telefono) {
  if (telefono == null) return null;
  final raw = telefono.replaceAll(RegExp(r'\D'), '');
  if (raw.isEmpty) return null;
  var n = raw;
  if (n.length >= 8 && n.length <= 10 && !n.startsWith('54')) {
    n = '54$n';
  } else if (n.startsWith('0')) {
    n = '54${n.replaceFirst(RegExp(r'^0+'), '')}';
  }
  return 'https://wa.me/$n';
}

/// Primera palabra de [nombreAlumno] (según carga, puede ser nombre o apellido).
/// Quitar puntuación al final (p. ej. "Pérez,") para no duplicar comas con el cuerpo.
String _primeraPalabraNombreAlumno(String nombreAlumno) {
  var t = nombreAlumno.trim();
  if (t.toUpperCase().startsWith('[BAJA]')) {
    t = t.replaceFirst(RegExp(r'^\[BAJA\]\s*', caseSensitive: false), '').trim();
  }
  if (t.isEmpty) return '';
  var w = t.split(RegExp(r'\s+')).first;
  w = w.replaceAll(RegExp(r'[,.;:\s]+$'), '');
  w = w.replaceAll(RegExp(r'^[,\.;:\s]+'), '');
  return w;
}

/// Pestaña **Cobro**: seguimiento por evento masivo + institución (Mi Empresa).
class CobroMasivosTab extends ConsumerStatefulWidget {
  final bool isDark;
  final Color gold;

  const CobroMasivosTab({super.key, required this.isDark, required this.gold});

  @override
  ConsumerState<CobroMasivosTab> createState() => _CobroMasivosTabState();
}

class _CobroMasivosTabState extends ConsumerState<CobroMasivosTab> {
  bool _loadingEventos = true;
  String? _error;
  List<Evento> _eventosMasivos = [];
  String? _eventoId;
  bool _loadingDetalle = false;
  List<ContratoAlumno> _contratos = [];
  String? _institucion;
  List<String> _instituciones = [];
  List<_CobroFila> _filas = [];
  final _busquedaCtrl = TextEditingController();
  _CobroFiltroCuota _filtroCuota = _CobroFiltroCuota.todos;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarEventos();
  }

  void _resetFiltrosVista() {
    _busquedaCtrl.clear();
    _filtroCuota = _CobroFiltroCuota.todos;
  }

  Future<void> _cargarEventos() async {
    setState(() {
      _loadingEventos = true;
      _error = null;
    });
    try {
      final evRepo = ref.read(eventosRepositoryProvider);
      final list = await evRepo.getAll(modalidad: 'masivo');
      if (!mounted) return;
      setState(() {
        _eventosMasivos = list;
        _loadingEventos = false;
        if (_eventoId != null && !_eventosMasivos.any((e) => e.id == _eventoId)) {
          _eventoId = null;
          _contratos = [];
          _instituciones = [];
          _institucion = null;
          _filas = [];
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingEventos = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _cargarContratosYarmar(String? eventoId) async {
    if (eventoId == null) {
      setState(() {
        _contratos = [];
        _instituciones = [];
        _institucion = null;
        _filas = [];
        _loadingDetalle = false;
        _resetFiltrosVista();
      });
      return;
    }
    setState(() {
      _loadingDetalle = true;
      _error = null;
      _institucion = null;
      _filas = [];
      _resetFiltrosVista();
    });
    try {
      final cRepo = ref.read(contratosRepositoryProvider);
      final c = await cRepo.getByEvento(eventoId);
      final inst = c
          .map((a) => _institucionCanonica(a.institucion))
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _contratos = c;
        _instituciones = inst;
        _institucion = _kCobroTodosInstitucion;
      });
      await _armarFilas(_kCobroTodosInstitucion);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDetalle = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _armarFilas(String? institucion) async {
    if (_eventoId == null) {
      if (mounted) {
        setState(() {
          _filas = [];
          _loadingDetalle = false;
        });
      }
      return;
    }
    if (institucion == null || institucion.isEmpty) {
      if (mounted) {
        setState(() {
          _filas = [];
          _loadingDetalle = false;
        });
      }
      return;
    }
    setState(() {
      _loadingDetalle = true;
      _error = null;
    });
    try {
      var alumnos = institucion == _kCobroTodosInstitucion
          ? List<ContratoAlumno>.from(_contratos)
          : _contratos
              .where((a) => _institucionCanonica(a.institucion) == institucion)
              .toList();
      alumnos = alumnos.where((a) => !_contratoEsBaja(a)).toList();
      final ids = alumnos.map((a) => a.id).toList();
      final cRepo = ref.read(contratosRepositoryProvider);
      final pagos = await cRepo.getPagosForContratoIds(ids);
      final porContrato = <String, List<Map<String, dynamic>>>{};
      for (final p in pagos) {
        final id = p['contrato_alumno_id'] as String?;
        if (id == null) continue;
        porContrato.putIfAbsent(id, () => []).add(p);
      }
      final filas = <_CobroFila>[];
      for (final a in alumnos) {
        final list = porContrato[a.id] ?? [];
        final primera = _minFechaBase(list);
        final ultimo = _ultimoPagoAlPlan(list);
        final mora = MoraCuotaCalculator.calcular(a);
        final moraPagada = _sumMoraCobradaDesdePagos(list);
        final moraPend = MoraCuotaCalculator.pendienteDisplay(
          interesAcumulado: mora.interesAcumulado,
          moraCobradaHistorial: moraPagada,
          moraPendienteTracked: a.moraPendienteTracked,
        );
        filas.add(_CobroFila(
          contrato: a,
          primeraCuotaBase: primera,
          ultimoPago: ultimo,
          mora: mora,
          moraPendiente: moraPend,
        ));
      }
      filas.sort((x, y) {
        if (x.mora.enMora != y.mora.enMora) return x.mora.enMora ? -1 : 1;
        return x.contrato.nombreAlumno.toLowerCase().compareTo(y.contrato.nombreAlumno.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _filas = filas;
        _loadingDetalle = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDetalle = false;
          _error = '$e';
        });
      }
    }
  }

  String _etiquetaEvento(Evento e) {
    final f = ArTime.formatFechaCorta(e.fechaEvento);
    final nombre = e.cliente != null ? e.cliente!.nombreCompleto.trim() : '';
    if (nombre.isNotEmpty) {
      return '$f · $nombre';
    }
    return '$f · ${e.tipo}';
  }

  /// Filas a mostrar: búsqueda por nombre + filtro de cuota base (el listado base ya excluye [BAJA]).
  List<_CobroFila> _filasFiltradasVista() {
    var list = _filas;
    final q = _busquedaCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((f) => f.contrato.nombreAlumno.toLowerCase().contains(q))
          .toList();
    }
    switch (_filtroCuota) {
      case _CobroFiltroCuota.todos:
        break;
      case _CobroFiltroCuota.conAlMenosUna:
        list = list.where((f) => f.contrato.cuotasPagadas >= 1).toList();
        break;
      case _CobroFiltroCuota.ninguna:
        list = list.where((f) => f.contrato.cuotasPagadas == 0).toList();
        break;
    }
    return list;
  }

  String _valorFiltroInstitucionValido() {
    if (_institucion == _kCobroTodosInstitucion) return _kCobroTodosInstitucion;
    if (_institucion != null && _instituciones.contains(_institucion)) {
      return _institucion!;
    }
    return _kCobroTodosInstitucion;
  }

  @override
  Widget build(BuildContext context) {
    // Cuando el realtime de finanzas refresca (anulación de cobros, etc.), reconsultamos
    // los contratos del evento elegido para que el contador "X / N" no quede desfasado.
    ref.listen<AsyncValue<FinanzasState>>(finanzasProvider, (prev, next) async {
      if (_eventoId != null) {
        final c = await ref.read(contratosRepositoryProvider).getByEvento(_eventoId!);
        if (!mounted) return;
        setState(() => _contratos = c);
        await _armarFilas(_institucion);
      }
    });

    final filasVista = _filasFiltradasVista();
    final muted = widget.isDark ? Colors.white54 : Colors.black54;
    if (_error != null && _eventosMasivos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No se pudo cargar: $_error', style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COBRO — EVENTOS MASIVOS',
                    style: GoogleFonts.oswald(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Elegí un evento masivo. No se listan alumnos dados de baja. Podés buscar por nombre y filtrar por cuota base del plan: todos, al menos 1 cuota base, o ninguna.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              color: widget.gold,
              tooltip: 'Recargar',
              onPressed: _loadingEventos
                  ? null
                  : () async {
                      await _cargarEventos();
                      if (_eventoId != null) {
                        await _cargarContratosYarmar(_eventoId);
                      }
                    },
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_loadingEventos)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else ...[
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use — value controla el evento seleccionado (no solo valor inicial).
            value: _eventoId,
            decoration: const InputDecoration(
              labelText: 'Evento masivo',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('Seleccionar evento...')),
              ..._eventosMasivos.map(
                (e) => DropdownMenuItem<String>(
                  value: e.id,
                  child: Text(_etiquetaEvento(e), overflow: TextOverflow.ellipsis, maxLines: 2),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _eventoId = v);
              _cargarContratosYarmar(v);
            },
          ),
          if (_eventoId != null && _loadingDetalle) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_eventoId != null && !_loadingDetalle) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _valorFiltroInstitucionValido(),
              decoration: const InputDecoration(
                labelText: 'Vista (institución opcional)',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String>(
                  value: _kCobroTodosInstitucion,
                  child: Text('Todos los alumnos del evento', overflow: TextOverflow.ellipsis),
                ),
                ..._instituciones.map(
                  (i) => DropdownMenuItem<String>(value: i, child: Text(i, overflow: TextOverflow.ellipsis)),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _institucion = v);
                _armarFilas(v);
              },
            ),
            if (_instituciones.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ningún contrato tiene el campo Institución cargado; igual podés ver a todos con la opción de arriba. Podés completar el dato en el detalle del evento masivo para filtrar por escuela.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.35),
                ),
              ),
            if (_filas.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _busquedaCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Buscar alumno',
                  hintText: 'Nombre…',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  suffixIcon: _busquedaCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          onPressed: () {
                            setState(() {
                              _busquedaCtrl.clear();
                            });
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text('Cuota base (plan)', style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Semantics(
                label: 'Filtro: todos, al menos 1 cuota base, o ninguna',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_CobroFiltroCuota>(
                    style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -2, vertical: -2)),
                    segments: const [
                      ButtonSegment(
                        value: _CobroFiltroCuota.todos,
                        label: Text('Todos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      ButtonSegment(
                        value: _CobroFiltroCuota.conAlMenosUna,
                        label: Text('Al menos 1 cuota base', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      ButtonSegment(
                        value: _CobroFiltroCuota.ninguna,
                        label: Text('Ninguna', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ],
                    showSelectedIcon: false,
                    selected: <_CobroFiltroCuota>{_filtroCuota},
                    onSelectionChanged: (Set<_CobroFiltroCuota> s) {
                      if (s.isEmpty) return;
                      setState(() => _filtroCuota = s.first);
                    },
                  ),
                ),
              ),
            ],
          ],
        ],
        if (_error != null && _eventosMasivos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Aviso: $_error', style: const TextStyle(color: Colors.orange, fontSize: 12)),
        ],
        if (_institucion != null && !_loadingDetalle && _filas.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            _filas.length == filasVista.length
                ? '${_filas.length} alumno(s) activo(s) (excl. bajas)'
                : 'Mostrando ${filasVista.length} de ${_filas.length} alumno(s) activo(s) (excl. bajas)',
            style: TextStyle(color: widget.gold, fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (filasVista.isEmpty)
            Text(
              'Ningún alumno coincide con la búsqueda o con el filtro de cuota.',
              style: TextStyle(color: muted, fontSize: 13, height: 1.3),
            )
          else
            ...filasVista.map((f) => _tarjetaAlumno(f, muted)),
        ],
        if (_institucion != null && !_loadingDetalle && _filas.isEmpty && _error == null) ...[
          const SizedBox(height: 20),
          Text(
            _institucion == _kCobroTodosInstitucion
                ? 'No hay alumnos cargados en este evento.'
                : 'Sin alumnos para esta institución.',
            style: TextStyle(color: muted),
          ),
        ],
      ],
    );
  }

  Widget _tarjetaAlumno(_CobroFila f, Color muted) {
    final a = f.contrato;
    final mora = f.mora;
    final saldo = a.saldoDeudor;
    String estado;
    Color chipColor;
    if (saldo <= 0.01) {
      estado = 'LIQUIDADO';
      chipColor = Colors.green.shade700;
    } else if (mora.enMora) {
      estado = 'MORA${mora.diasMora > 0 ? ' · ${mora.diasMora} d' : ''}';
      chipColor = Colors.red.shade700;
    } else {
      estado = 'AL DÍA (saldo ${saldo.toCurrency()})';
      chipColor = Colors.blueGrey.shade600;
    }

    final wUri = _whatsAppUri(a.telefono);
    final curso = a.cursoDivision?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.nombreAlumno,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      if (curso != null && curso.isNotEmpty)
                        Text(curso, style: TextStyle(fontSize: 12, color: muted)),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              a.contratoFirmado ? Icons.assignment_turned_in_outlined : Icons.pending_actions_outlined,
                              size: 14,
                              color: a.contratoFirmado ? Colors.teal : muted,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                a.contratoFirmado ? 'Contrato firmado' : 'Aún no firmó contrato',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: a.contratoFirmado ? Colors.teal : muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (wUri != null)
                  IconButton(
                    icon: const Icon(Icons.chat_rounded, size: 20),
                    color: const Color(0xFF25D366),
                    tooltip: 'WhatsApp',
                    onPressed: () => _abrirWhatsappOClipboard(wUri, a),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text(estado, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  backgroundColor: chipColor.withValues(alpha: 0.2),
                  side: BorderSide(color: chipColor.withValues(alpha: 0.4)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (f.primeraCuotaBase != null)
                  Text('1.ª cuota base: ${ArTime.formatFechaHora(f.primeraCuotaBase!)}', style: TextStyle(fontSize: 11, color: muted))
                else
                  Text('1.ª cuota base: —', style: TextStyle(fontSize: 11, color: muted)),
                if (f.ultimoPago != null)
                  Text('Últ. pago: ${ArTime.formatFechaHora(f.ultimoPago!)}', style: TextStyle(fontSize: 11, color: muted))
                else
                  Text('Últ. pago: —', style: TextStyle(fontSize: 11, color: muted)),
                if (a.telefono != null && a.telefono!.trim().isNotEmpty)
                  Text('Tel: ${a.telefono}', style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
            if (mora.fechaVencimientoProximaCuota != null && saldo > 0.01)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Vto. próx. cuota base: ${ArTime.formatFechaCorta(mora.fechaVencimientoProximaCuota!)}',
                  style: TextStyle(fontSize: 10, color: muted.withValues(alpha: 0.9)),
                ),
              ),
            if (mora.enMora && f.moraPendiente > 0.01)
              Text(
                'Mora pendiente: ${f.moraPendiente.toCurrency()}',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirWhatsappOClipboard(String wUri, ContratoAlumno a) async {
    final nombreCorto = _primeraPalabraNombreAlumno(a.nombreAlumno);
    final saludo = nombreCorto.isNotEmpty ? 'Hola $nombreCorto' : 'Hola';
    final msg =
        '$saludo, te contactamos desde $_kCobroMarcaMensaje. Te recordamos abonar la cuota a tiempo y así evitás intereses. Si ya abonaste, desestimá el mensaje. Cualquier duda, a disposición.';

    final base = wUri.split('?').first;
    final uri = Uri.parse('$base?text=${Uri.encodeComponent(msg)}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!ok) {
        await Clipboard.setData(ClipboardData(text: msg));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp. El mensaje quedó copiado al portapapeles.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: msg));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir WhatsApp. Mensaje copiado. ($e)')),
      );
    }
  }
}
